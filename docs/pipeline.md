# 五级流水契约

本文档定义当前五级流水的逐周期行为。它关注“状态在什么条件下推进、保持、插入 bubble 或被冲刷”，而不是只描述数据通路模块名称。

## 1. 五级职责

| 流水级 | 主要职责 | 输出状态 |
|---|---|---|
| IF | 发起取指、管理单笔在途请求、接收指令或访问错误 | IF/ID candidate |
| ID | 主译码、立即数生成、读通用寄存器、形成早期异常 | ID/EX candidate |
| EX | ALU、branch compare、地址/目标计算、前递、对齐检查、迭代式 RV32M 请求/等待 | EX/MEM candidate 与 raw redirect |
| MEM | 等待 DMem、格式化 load、CSR RMW、合并最终异常、提交 trap/MRET/interrupt | MEM/WB candidate 或边界事件 |
| WB | 选择 ALU/load/PC+4/CSR 旧值，写寄存器并产生 retire | WB bus 与 retire |

每一组流水寄存器都有 `valid`。`valid=0` 表示 bubble，其余字段没有架构意义，也不得触发寄存器写、store、CSR 写或 redirect。

## 2. 流水动作

四组流水寄存器统一使用三种动作：

- `PIPE_LOAD`：装载本周期 candidate；
- `PIPE_HOLD`：保持全部字段不变；
- `PIPE_CLEAR`：只把 `valid` 清零，形成 bubble。

取指 PC 使用对应的 `FETCH_RESET/HOLD/SEQUENTIAL/REDIRECT` 动作。全局控制优先级固定如下，先命中的条件覆盖后续条件：

| 优先级 | 条件 | IF/ID | ID/EX | EX/MEM | MEM/WB | 结果 |
|---:|---|---|---|---|---|---|
| 1 | reset | clear | clear | clear | clear | fetch reset |
| 2 | synchronous trap take | clear | clear | clear | clear | 跳到当前 `mtvec` |
| 3 | post-commit interrupt | clear | clear | clear | load | 当前 MEM 指令提交，跳到有效 `mtvec` |
| 4 | empty-pipeline interrupt | clear | clear | clear | clear | 无提交指令，跳到有效 `mtvec` |
| 5 | MRET commit | clear | clear | clear | load | MRET 提交，跳到当前 `mepc` |
| 6 | MEM response wait | hold | hold | hold | clear | 全局等待，防止重复退休 |
| 7 | EX request/multicycle wait | hold | hold | clear | load | 等待 DMem 请求或 MDU 结果 |
| 8 | EX raw redirect | clear | clear | load | load | 提交 redirect |
| 9 | late-result hazard | hold | clear | load | load | 插入一个 bubble |
| 10 | 无可用取指响应 | clear | load | load | load | 后端继续排空 |
| 11 | 正常 | load | load | load | load | 顺序推进 |

post-commit 与 empty-pipeline interrupt 分开仲裁，是因为前者必须让当前 MEM 指令进入 MEM/WB，后者没有可提交指令。MRET 后若恢复出的 MIE 立即使 pending interrupt eligible，按 post-commit interrupt 行处理，不先取返回目标指令。

`ex_multicycle_wait` 由 `rv32_mdu` 的响应可用性驱动。M 指令在 ID/EX 保持，EX/MEM 插入 bubble，较老 MEM/WB 继续排空；完成的 MDU response 若遇到较老 MEM wait，会保持稳定直到可以装载 EX/MEM。

## 3. 数据冒险

### 3.1 前递

EX 的两个源操作数分别选择：

1. EX/MEM 中最近的生产者；
2. MEM/WB 中次近的生产者；
3. ID/EX 保存的寄存器值。

EX/MEM 只能前递已经可用的 `WB_EXEC` 或 `WB_PC_PLUS_4` 结果。完成的 RV32M 结果沿现有 `WB_EXEC` 路径进入 EX/MEM，因此也可从 EX/MEM 前递。load 数据和 CSR 旧值在 MEM 结束后才可用，只能从 MEM/WB 前递。写 `x0` 不构成生产者。

ID 还包含 WB→ID 同周期旁路：若 WB 正在写与 ID 读取相同的非零寄存器，ID 直接取得 WB 数据，而不依赖寄存器数组的读写先后语义。

### 3.2 Late-result bubble

load 或 CSR 指令位于 EX，且下一条 ID 指令读取其 `rd` 时，`late_result_hazard=1`：

- fetch 和 IF/ID 保持；
- ID/EX 清空，插入一个 bubble；
- 生产者继续进入 EX/MEM；
- 下一周期消费者再进入 EX，并从 MEM/WB 获得结果。

该机制统一处理 load-use 与 CSR-use，不为 CSR 另开旁路协议。

### 3.3 EX hold 快照

DMem request 受反压时，ID/EX 必须保持。但是 ID/EX 内保存的是译码时的寄存器值，
前递源可能在等待期间离开流水。为保证 stalled request payload 稳定，
`rv32_execute_stage` 在第一次 HOLD 时保存已完成前递的 EX/MEM candidate 和 raw
redirect；解除 HOLD 前始终使用该快照。M 指令由 MDU 自己捕获已前递操作数并保持
response，不进入普通 EX hold 快照。

### 3.4 RV32M 多周期执行

`rv32_mdu` 一次只接受一条请求，捕获 EX 前递后的两个操作数与 operation，执行固定 32 轮迭代，再进入 response 状态。八条 RV32M 指令共用这一路径，并完整处理除零与有符号除法溢出。

- request 只在 MDU idle 且当前 ID/EX 是有效 M 指令时发出一次；
- response 在 `valid && ready` 前保持结果稳定；
- M 指令没有结果时拉高 `ex_multicycle_wait`，不得把普通 ALU 占位值送入 EX/MEM；
- reset、较老同步 trap、interrupt 或 MRET 会 kill 年轻 MDU 请求/运行/响应；
- MDU response 被消费后，结果以普通 `WB_EXEC` packet 继续经过 MEM/WB 和 forwarding。

## 4. 控制冒险与重定向

branch、JAL、JALR 在 EX 计算是否跳转和目标地址：

- not-taken branch 不产生 redirect；
- taken branch、JAL、JALR 产生 raw redirect；
- JALR 先清目标 bit 0，再按 `IALIGN=32` 检查低两位；
- redirect 提交时清除 IF/ID 与 ID/EX，控制转移指令本身进入 EX/MEM；
- 较老 MEM wait 优先于年轻 redirect，等待结束后 redirect 才能提交一次；
- 最终 redirect 优先级为同步 trap、Machine interrupt、MRET、普通 EX redirect。

IFU 可能已经有错误路径请求 pending 或 outstanding。redirect 不撤销外部已经接受的事务，而是把它标为 stale：旧响应被握手排空，但不形成有效 IF/ID 指令；目标请求在 slot 可用时发出。

## 5. 存储器反压

### 5.1 IMem

IFU 分别维护：

- 尚未被 IMem 接受的 pending request；
- 已接受、尚未返回的 outstanding request；
- redirect target 与 stale 标记。

未接受请求的 `valid/addr` 必须稳定。正常响应只有在 IF/ID 可以装载时才 ready；stale 响应可以立即排空。

### 5.2 DMem

数据请求由当前 EX candidate 形成，包含原始字节地址、读写方向、对齐后的写数据和 `wstrb`。请求未被接受时触发 EX request wait；接受后 LSU 记录一笔 outstanding，指令位于 MEM 等待响应。

load 和 store 都需要 response：

- load 成功响应产生符号扩展或零扩展结果；
- store 成功响应确认该请求完成；
- error 响应产生 load/store access fault；
- outstanding 时 `dmem_rsp_ready=1`；
- 一个 response 完成的同周期可以接受下一笔 request。

地址未对齐、已经携带早期异常，或被更老同步 trap、Machine interrupt/MRET 阻断的年轻访存，不得发出 DMem 请求。

## 6. 精确同步异常

### 6.1 检测位置

| 来源 | 检测位置 | 异常 |
|---|---|---|
| IMem error | IF | instruction access fault |
| 译码 | ID | illegal instruction、ECALL、EBREAK |
| 地址/目标对齐 | EX | instruction/load/store address misaligned |
| CSR profile | MEM | 不存在 CSR 或 MRO 真实写 |
| DMem error | MEM | load/store access fault |

早期异常随流水寄存器携带到 MEM。EX 一旦产生地址异常，会清除该指令的 CSR、访存和写回控制，避免故障指令提前形成副作用。

### 6.2 最终合并与提交

MEM 对同一条指令按以下顺序选择唯一异常：

```text
已携带的早期异常 > CSR illegal > LSU response error
```

最终异常只在 MEM 提交点产生 trap。此时：

- 故障指令不进入有效 MEM/WB，因而不会普通退休或写通用寄存器；
- 故障指令不提交显式 CSR 写；
- 异常或更老异常阻断年轻 DMem request；
- IF/ID、ID/EX、EX/MEM、MEM/WB 被清空；
- IFU 重定向到当前 `mtvec`；
- 同周期 WB 中更老的指令仍允许正常退休。

这构成“每条指令要么正常退休，要么产生一次 trap”的精确性边界。CSR 自动更新和 payload 见 [CSR、Trap 与 Machine Interrupt](csr_trap.md)。

## 7. 精确 Machine interrupt 边界

Machine interrupt 不取消已经产生副作用的当前 MEM 指令。正常情况下先形成与流水动作无关的 `mem_commit_candidate`，再用当前 CSR/MRET 提交后的 effective interrupt enable 决定 post-commit interrupt：

1. 当前 MEM 指令完成且无同步异常；
2. 当前指令进入 MEM/WB，并形成一次 `commit_valid`；
3. interrupt entry 保存该指令的架构后继 PC；
4. 清空年轻流水、阻断年轻 DMem request、kill 年轻 MDU，并跳到有效 `mtvec`。

EX/MEM packet 携带当前指令自己的 `architectural_next_pc`：普通或 not-taken 指令为 `pc+4`，taken branch/JAL/JALR 为控制转移目标。MRET 的有效后继在 MEM 提交时读取当前 `mepc`，不能在 EX 提前快照。

Core 还维护 `resume_pc_q`，记录最近一次已提交边界后的下一架构 PC。只有在以下条件全部成立时才允许 empty-pipeline interrupt：

```text
IF/ID、ID/EX、EX/MEM、MEM/WB 均无效
&& !lsu_outstanding
&& mdu_idle
```

IFU pending/outstanding 没有架构副作用，不阻止 empty boundary；redirect 后由 stale-response 机制排空。empty interrupt 使用 `resume_pc_q` 写 `mepc`，且不产生退休事件。

interrupt take 同拍完成 CSR entry、flush 与 redirect，但外部 interrupt `trap_valid` 由单项 pending 状态延后一拍输出。对于 post-commit interrupt，该观察事件与边界指令的 WB retire 同拍，scoreboard 必须先消费 retire，再消费 interrupt trap。延后事件不得再次更新 CSR、flush 或 redirect。

## 8. 必须持续成立的不变量

- 无效或被冲刷的指令不得产生架构副作用；
- stalled request 的 `valid` 与 payload 保持稳定；
- 每通道 outstanding 计数只能为 0 或 1；
- 没有 outstanding 时不得接受 response；
- MEM wait 期间不得重复 retire；
- redirect 和 trap 各自只提交一次；
- faulting instruction 不 retire，年轻 store 不越过 trap；
- post-commit interrupt 的边界指令只 retire 一次，且事件顺序为 retire 后 trap；
- empty interrupt 不伪造 retire，MRET 后立即 interrupt 不执行返回目标指令；
- stalled MDU response 保持稳定，kill 后不得产生迟到结果；
- 写 `x0` 不改变状态，也不成为前递源。

这些不变量由 [验证方法与结果](verification.md) 中的 scoreboard 和协议检查逐周期监督。
