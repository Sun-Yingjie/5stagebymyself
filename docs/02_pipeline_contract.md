# 五级流水职责与状态边界

> 上位规格：`00_processor_architecture.md`、`01_core_system_context.md`

## 1. 基本设计前提

- 处理器采用 `IF / ID / EX / MEM / WB` 五级顺序流水。
- v0.1 指令存储器立即接受请求，并在请求握手后的下一周期返回指令响应。
- v0.1 数据存储器立即接受请求，并在请求握手后的下一周期返回 load/store 完成响应。
- 寄存器堆具有两路异步读端口和一路同步写端口，`x0` 恒为 0。
- 分支在 EX 阶段完成条件判断和目标地址计算，默认按 `PC + 4` 顺序取指。
- 每组流水寄存器都具有独立的 `valid`，用来区分真实指令和空流水槽。
- 流水寄存器的数据字段在 `valid = 0` 时无效，不要求清零。

## 2. 流水级职责

| 流水级 | 输入 | 本级完成的工作 | 输出 |
|---|---|---|---|
| IF | 取指状态、指令请求/响应、EX 阶段产生的重定向信息 | 管理取指请求、保存请求 PC、接收或丢弃指令响应、选择顺序或重定向地址 | 指令、对应请求 PC、`PC + 4`、有效标志 |
| ID | 指令、指令 PC、`PC + 4`、WB 写回信息 | 指令译码、读取寄存器堆、生成立即数、生成 EX/MEM/WB 所需控制信号、检测 late-result hazard | `rs1/rs2` 编号及数据、`rd` 编号、立即数、PC、`PC + 4`、指令、CSR 地址及控制信号 |
| EX | ID/EX 中的数据和控制信号、EX/MEM 与 MEM/WB 的前递数据 | 选择前递操作数、完成算术逻辑运算、计算访存地址、固化 CSR 源、选择 store 数据、完成分支比较和分支目标地址计算 | ALU 结果、CSR 源、store 数据、分支是否跳转、分支目标地址、目的寄存器及后续控制信号 |
| MEM | ALU 结果、CSR 地址和源、store 数据、MEM/WB 控制信号、数据请求/响应 | 管理 load/store 请求和完成响应；执行 CSR 访问检查和原子读改写；等待期间反压年轻流水；合并最终异常 | CSR 修改前旧值、load 读出数据、ALU 结果、`PC + 4`、目的寄存器及 WB 控制信号 |
| WB | ALU 结果、load 数据、CSR 修改前旧值、`PC + 4`、目的寄存器及 WB 控制信号 | 根据写回来源选择最终结果；当指令有效且需要写回时更新寄存器堆 | `wb_write_enable`、`wb_rd_addr`、`wb_write_data`，以及后续使用的退休跟踪信息 |

## 3. 流水状态边界

| 流水寄存器 | 至少需要保存的内容 |
|---|---|
| IF/ID | `valid、pc、instruction、pc_plus_4` |
| ID/EX | `valid、pc、instruction、pc_plus_4、rs1_addr、rs2_addr、rs1_data、rs2_data、rd_addr、immediate、csr_ctrl、csr_address、EX/MEM/WB 控制信号` |
| EX/MEM | `valid、pc、instruction、pc_plus_4、exec_result、store_data、csr_ctrl、csr_address、csr_source、rd_addr、MEM/WB 控制信号` |
| MEM/WB | `valid、pc、instruction、exec_result、load_result、csr_read_data、pc_plus_4、rd_addr、WB 控制信号` |

保留 `pc` 和 `instruction` 到 WB，主要用于后续生成退休跟踪信息、差分验证和波形调试。控制信号在向后传递时逐级缩减：进入 EX/MEM 后不再保留只供 EX 使用的控制信号，进入 MEM/WB 后只保留 WB 仍然需要的控制信号。

## 4. 统一流水寄存器动作

### 4.1 流水寄存器动作

每组流水寄存器在每个时钟沿只允许执行一种动作：

| 动作 | 行为 |
|---|---|
| `LOAD` | 装载上一级产生的完整下一状态，包括下一状态的 `valid` |
| `HOLD` | 当前 `valid`、数据和控制字段全部保持不变 |
| `CLEAR` | 只把当前流水寄存器的 `valid` 置 0，其他字段无须清零 |

四组流水寄存器在同一个时钟沿同时执行各自动作，不存在先更新 IF/ID、再使用新 IF/ID 更新 ID/EX 的顺序关系。时序逻辑使用非阻塞赋值。

`CLEAR` 只制造一个无效流水槽。这个动作在语义上可能表示 bubble，也可能表示 flush：bubble 会保留上游等待指令，flush 会永久丢弃错误路径指令。

### 4.2 取指地址状态动作

取指地址不是简单地每个周期自动执行 `PC + 4`。它属于取指请求管理状态，具有以下动作：

| 动作 | 行为 |
|---|---|
| `RESET` | 设置下一取指地址为 `RESET_VECTOR`，清除旧取指事务状态 |
| `HOLD` | 保持当前请求地址、在途和重定向等待状态 |
| `SEQUENTIAL` | 在顺序取指请求被接受后，准备请求地址 `PC + 4` |
| `REDIRECT` | 保存 branch、jump 或未来异常产生的目标地址，并使旧路径响应失效 |

IF/ID 在指令响应握手时装载响应指令及此前保存的请求 PC，而不是在指令请求握手时装载。

### 4.3 已确认事件示例

late-result hazard（load-use 或 CSR-use）：

```text
取指状态 HOLD
IF/ID      HOLD
ID/EX      CLEAR
EX/MEM     LOAD
MEM/WB     LOAD
```

branch taken：

```text
取指状态 REDIRECT
IF/ID      CLEAR
ID/EX      CLEAR
EX/MEM     LOAD
MEM/WB     LOAD
```

数据访存等待：

```text
取指状态 HOLD
IF/ID      HOLD
ID/EX      HOLD
EX/MEM     HOLD
MEM/WB     CLEAR
```

reset：

```text
取指状态 RESET
IF/ID      CLEAR
ID/EX      CLEAR
EX/MEM     CLEAR
MEM/WB     CLEAR
```

## 5. 事件—动作矩阵

### 5.1 事件优先级

流水控制采用以下优先级：

```text
reset
> 已在 MEM 资格确认的精确异常/陷阱
> MEM wait
> EX wait（数据请求、乘除法或协处理器）
> EX redirect
> late-result hazard
> 前端无响应
> normal
```

- 更老指令的阻塞或异常必须阻止年轻指令产生控制事件。
- MEM wait 高于 EX redirect，因为 MEM 中的访存指令比 EX 中的分支更老。
- EX wait 包括数据请求尚未被接受，以及未来乘除法或协处理器尚未完成。
- late-result hazard 表示 ID 中的消费者依赖 EX 中尚不能从 EX/MEM 前递结果的生产者；v0.1 只有 load，接入 Zicsr 后还包括需要写回 CSR 旧值的指令。
- branch、JAL 和 JALR 都使用 `EX redirect` 事件。
- `trap_take` 只表示 MEM 中最老异常已具备提交资格；IF、ID、EX 的原始异常不能直接驱动全局冲刷。

### 5.2 动作矩阵

| 当前最高优先级事件 | 取指状态 | IF/ID | ID/EX | EX/MEM | MEM/WB |
|---|---|---|---|---|---|
| reset | RESET | CLEAR | CLEAR | CLEAR | CLEAR |
| 精确异常/陷阱 | REDIRECT | CLEAR | CLEAR | CLEAR | CLEAR |
| MEM wait | HOLD | HOLD | HOLD | HOLD | CLEAR |
| EX wait | HOLD | HOLD | HOLD | CLEAR | LOAD |
| EX redirect | REDIRECT | CLEAR | CLEAR | LOAD | LOAD |
| late-result hazard | HOLD | HOLD | CLEAR | LOAD | LOAD |
| 前端无响应 | HOLD | CLEAR | LOAD | LOAD | LOAD |
| normal，有响应 | SEQUENTIAL | LOAD | LOAD | LOAD | LOAD |

“前端无响应”一行表示 IF/ID 中的旧指令已经被 ID/EX 接收，但当前没有新的指令响应可以补入 IF/ID，因此 IF/ID 变为空。前端没有新指令不能阻止后端已有指令继续排空。

`SEQUENTIAL` 只在下一笔顺序取指请求真正完成请求握手时更新下一请求地址。IF/ID 则只在指令响应握手时装载指令，两者不是同一个事件。

`LOAD` 可以装入一个 `valid = 0` 的上游状态，因此可能自然产生 bubble。每个流水边界每周期只有一个动作，不能同时执行 HOLD、LOAD 和 CLEAR。

### 5.3 必须保持的不变量

- WB 中已经完成的旧指令只退休一次。
- 被保持的指令不会重复发送 store 或协处理器请求。
- 被 flush 的指令永远不能恢复为有效指令。
- 未返回的指令响应不会被误当成有效 IF/ID 内容。
- 同一周期出现多个条件时，优先级选择后每组状态都有唯一下一动作。

## 6. 指令类别与整体数据路径

### 6.1 EX 操作数和前递位置

寄存器数据先完成前递选择，再分别进入 ALU 操作数选择、分支比较和 store 数据路径：

```text
rs1_data → 前递选择 → rs1_exec ─┬→ ALU 操作数 A
                                 └→ 分支比较器

rs2_data → 前递选择 → rs2_exec ─┬→ ALU 操作数 B
                                 ├→ 分支比较器
                                 └→ store_data
```

不能只在 ALU 输入端加入前递，否则 branch 比较器和 store 数据仍可能使用旧的寄存器值。

### 6.2 指令类别数据路径

| 指令类别 | 使用 rs1 | 使用 rs2 | ALU 操作数 A | ALU 操作数 B | EX 主要结果 | WB 来源 |
|---|---:|---:|---|---|---|---|
| R 型整数运算 | 是 | 是 | `rs1_exec` | `rs2_exec` | 算术逻辑结果 | `WB_EXEC` |
| I 型整数运算 | 是 | 否 | `rs1_exec` | immediate | 算术逻辑结果 | `WB_EXEC` |
| LUI | 否 | 否 | zero | U-immediate | `0 + immediate` | `WB_EXEC` |
| AUIPC | 否 | 否 | PC | U-immediate | `PC + immediate` | `WB_EXEC` |
| load | 是 | 否 | `rs1_exec` | immediate | 访存地址 | `WB_LOAD` |
| store | 是 | 是 | `rs1_exec` | immediate | 访存地址 | 无 |
| branch | 是 | 是 | PC | B-immediate | 分支目标地址 | 无 |
| JAL | 否 | 否 | PC | J-immediate | 跳转目标地址 | `WB_PC_PLUS_4` |
| JALR | 是 | 否 | `rs1_exec` | I-immediate | 跳转目标地址 | `WB_PC_PLUS_4` |
| FENCE | 否 | 否 | 无架构用途 | 无架构用途 | 无副作用，通过流水 | 无 |
| CSR 寄存器形式 | 是 | 否 | 不使用主 ALU | 不使用主 ALU | EX 固化 `rs1_exec`，MEM 返回 CSR 旧值 | `WB_CSR` |
| CSR 立即数形式 | 否 | 否 | 不使用主 ALU | 不使用主 ALU | EX 零扩展 `instruction[19:15]`，MEM 返回 CSR 旧值 | `WB_CSR` |

store 写数据独立取自 `rs2_exec`。branch 使用比较逻辑比较 `rs1_exec` 和 `rs2_exec`，主 ALU 同时计算 `PC + immediate`。

JALR 的最终目标地址为：

```text
(rs1_exec + immediate) & 32'hffff_fffe
```

`PC + 4` 在 IF 计算并随指令向后传递。SLT、SLTU 和分支可以共享“相等、有符号小于、无符号小于”比较结果，具体组合逻辑组织在模块设计阶段确定。

### 6.3 写回来源

v0.1 的 WB 具有三种有效来源：

```text
WB_EXEC
WB_LOAD
WB_PC_PLUS_4
```

以上三个名称是 `writeback_select_e` 的正式枚举常量。未来乘除法和协处理器结果复用 `WB_EXEC` 写回来源，不增加新的 WB 多路器输入。

Zicsr 流水接入时增加第四种来源 `WB_CSR`，选择 MEM/WB 保存的 CSR 修改前旧值。它不增加寄存器堆写端口，只扩展现有写回多路器。

### 6.4 ID 语义控制

ID 至少需要生成以下语义控制信息，当前不冻结具体编码位宽：

```text
uses_rs1
uses_rs2
immediate_type
operand_a_select
operand_b_select
alu_operation
branch_operation
is_jump
is_jalr
memory_read
memory_write
memory_size
load_unsigned
register_write
writeback_select
illegal_instruction
csr_ctrl.valid
csr_ctrl.operation
csr_ctrl.use_immediate
csr_ctrl.read_enable
csr_ctrl.write_enable
csr_address
```

`uses_rs1` 和 `uses_rs2` 必须来自真实指令语义。冒险检测不能只比较指令字中的 `rs1/rs2` 位域，因为 LUI、AUIPC 和 JAL 等指令在相同比特位置存在编码字段，但并不读取对应通用寄存器。

### 6.5 `FENCE` 流水行为

`FENCE` 在 ID 识别为合法指令，但不读取 `rs1/rs2`，不写 `rd`，不产生数据请求，也不产生 redirect。它保持 `valid=1` 依次通过 ID/EX、EX/MEM 和 MEM/WB，并在 WB 产生一次不写通用寄存器的普通退休事件。

decoder 接受 `MISC-MEM` opcode 下 `funct3=000` 的全部 `FENCE` 配置，忽略编码中的 `fm/pred/succ/rs1/rd` 字段。`funct3=001` 是未实现的 `FENCE.I`，仍产生 illegal-instruction 异常。

## 7. 数据请求的流水边界

### 7.1 请求发出时机

load/store 在 EX 计算地址，请求在该指令从 EX 进入 MEM 的时钟边界完成握手：

- `dmem_req_addr` 来自主 ALU 的地址计算结果；
- `dmem_req_wdata` 来自经过前递选择的 `rs2_exec`；
- 只有 ID/EX 中的访存指令有效、没有更老的 MEM 阻塞或异常，并且该指令获准进入 MEM 时，才允许请求握手；
- 如果 `dmem_req_ready = 0`，该指令保持在 EX，并使用事件矩阵中的 EX wait 动作；
- 请求握手后，访存指令进入 EX/MEM，并记录请求已经发送；
- MEM 负责等待响应、处理 load 数据和确认 store 完成。

### 7.2 一拍 load-use 时序

```text
C1：load 在 EX 计算地址并完成请求握手
    依赖指令在 ID，ID/EX 下一状态被 CLEAR

C2：load 在 MEM 接收响应
    EX 是 bubble，依赖指令在 ID 并于周期末进入 ID/EX

C3：load 在 WB
    依赖指令在 EX，通过 MEM/WB 前递获得 load 数据
```

在 v0.1 固定一周期响应下，该结构保持经典的一拍 load-use bubble。增加请求寄存器会延长 load 延迟，届时必须同步修改冒险控制。

### 7.3 时序代价

数据请求地址形成路径经过 EX 地址计算并到达核心数据接口。该路径将在 DC/PT 阶段检查；如果成为关键路径，后续可以增加请求缓冲，但不能在不修改流水时序规格的情况下直接插入寄存器。

## 8. 完整前递与数据冒险规则

### 8.1 EX 前递优先级

`rs1` 和 `rs2` 分别独立选择执行阶段使用的数据，优先级为：

```text
EX/MEM 中较新的生产者
> MEM/WB 中较老的生产者
> ID/EX 保存的寄存器读取值
```

生产者与消费者匹配至少需要满足：

```text
producer.valid
producer.register_write
producer.rd_addr != 0
producer.rd_addr == consumer.rs_addr
```

如果 EX/MEM 和 MEM/WB 同时匹配同一个源寄存器，必须选择 EX/MEM，因为它对应更新的指令结果。

### 8.2 前递数据值

EX/MEM 的可前递值取决于该指令的写回来源：

```text
普通运算、LUI、AUIPC → exec_result
JAL、JALR             → pc_plus_4
load                   → 当前不能使用普通 EX/MEM 前递
CSR                    → 当前不能使用普通 EX/MEM 前递
```

MEM/WB 直接前递最终的 `wb_write_data`，因此覆盖 ALU 结果、load 数据和 `PC + 4`。

如果 EX/MEM 中匹配的最新生产者具有 `result_late=1`，不能跳过该生产者而错误地使用 MEM/WB 中更老的同名结果。load 数据和 CSR 旧值都到 MEM 才形成，因此均不能从普通 EX/MEM 结果路径前递；late-result bubble 和 MEM 反压保证消费者不会错误向前推进。

### 8.3 前递后的用途

```text
rs1_exec → ALU 操作数 A、branch 比较、JALR 地址
rs2_exec → ALU 操作数 B、branch 比较、store data
```

因此前递选择位于用途分流之前。branch 和 store 不能只依赖 ALU 输入端的局部旁路。

### 8.4 WB 到 ID 显式旁路

本项目所有流水寄存器和通用寄存器堆写端口都使用时钟上升沿，不使用下降沿写寄存器堆的方法。通用寄存器堆采用组合异步读，并在 ID 增加显式 WB 旁路：

```text
如果 wb_write_enable
并且 wb_rd_addr != 0
并且 wb_rd_addr == id_rs1_addr
则 id_rs1_data 使用 wb_write_data
否则使用寄存器堆 rs1 读出值
```

`rs2` 使用相同规则。显式旁路使处理器不依赖寄存器堆或存储宏的 read-during-write 行为，便于后续替换实现并简化单边沿 STA。

### 8.5 late-result hazard

late-result hazard 的语义检测条件为：

```text
ID/EX.valid
&& ID/EX.result_late
&& ID/EX.rd_addr != 0
&& IF/ID.valid
&& (
       (ID.uses_rs1 && ID.rs1_addr == ID/EX.rd_addr)
    || (ID.uses_rs2 && ID.rs2_addr == ID/EX.rd_addr)
   )
```

RTL 统一定义 `result_late = memory_read || csr_ctrl.valid`：当前可达路径由 load 产生；主译码接通 Zicsr 后，CSR 旧值路径自动纳入同一规则。检测必须使用译码得到的 `uses_rs1/uses_rs2`，不能只比较指令位域。forward unit 和 pipeline control 之间统一使用 `late_result_hazard`。当前不优化 load 后紧跟 store data 的特殊情况，所有真实依赖统一插入一个 bubble。

### 8.6 必须覆盖的前递场景

- ALU→ALU；
- ALU→branch；
- ALU→JALR；
- ALU→store address；
- ALU→store data；
- load→上述消费者，暂停一拍后从 MEM/WB 前递；
- CSR→上述消费者，暂停一拍后从 MEM/WB 前递 CSR 旧值；
- WB 写回与 ID 读取同一寄存器；
- EX/MEM 和 MEM/WB 同时写同一个 `rd` 时选择更新的 EX/MEM 结果；
- 任何写入 `x0` 的指令都不能成为有效前递生产者。

### 8.7 Zicsr 流水契约

六条 CSR 指令在 ID 从 `instruction[31:20]` 取得 12 位 `csr_address`，并生成 `csr_ctrl.valid/operation/use_immediate/read_enable/write_enable`：

- `CSRRW/CSRRWI` 始终尝试写 CSR；仅当 `rd=x0` 时抑制 CSR 读取及其潜在读副作用；
- `CSRRS/CSRRC` 始终读取 CSR；仅当编码的 `rs1=x0` 时完全抑制 CSR 写；`rs1` 非零但寄存器运行值为零时仍属于一次 CSR 写；
- `CSRRSI/CSRRCI` 始终读取 CSR；仅当编码的 `uimm=0` 时完全抑制 CSR 写；
- immediate 形式把指令 `rs1` 字段零扩展为 32 位源，不读取通用寄存器。

ID/EX 保存 `csr_ctrl` 和 `csr_address`。寄存器形式的 CSR 源在 EX 使用正常前递网络选定；立即数形式在 EX 把随指令携带的 `instruction[19:15]` 零扩展为 32 位，不读取通用寄存器。EX/MEM 保存 `csr_ctrl`、`csr_address` 和固化后的 `csr_source`。

只有 EX/MEM 中有效、未携带早期异常的 CSR 指令才能在 MEM 形成 `csr_access_valid`。CSR 状态所有者先检查地址、权限和只读属性，再读取和写入：读值是本条指令执行前的旧值，写值分别为 `source`、`old | source` 或 `old & ~source`。接口固定 `csr_access_illegal = csr_access_valid && access_check_failed`；没有有效且合法的读取时 `csr_read_data=0`。非法访问不得产生真实读写副作用；合法写入只在本条指令获准提交时发生。

MEM/WB 保存 `csr_read_data`，CSR 旧值经 `WB_CSR` 写回。因此 CSR 指令与紧随其后的 `rd` 消费者触发一拍 late-result stall，随后从 MEM/WB 前递。连续 CSR 指令不需要额外停顿：较老指令在 MEM 时提交，较年轻指令下一周期进入 MEM 后读取更新值。

不存在的 CSR、权限不足的访问，或对只读 CSR 发起 `write_enable=1` 的访问，在 MEM 产生 illegal-instruction 异常。该指令不写 CSR、不写 `rd`、不普通退休；只读 CSR 上被规范抑制的写操作仍是合法读取。

## 9. v0.2 精确同步异常契约

v0.1 已在流水数据包中预留异常元数据。v0.2 启用这些字段并完成同步异常的检测、传播、禁止副作用、MEM 统一提交和 trap 重定向。本节不包含异步中断；中断将在同步异常闭环稳定后单独加入。

### 9.1 异常检测位置

| 异常 | 检测位置 |
|---|---|
| 取指访问错误 | IF，根据 `imem_rsp_error` |
| 非法指令、ECALL、EBREAK | ID |
| taken branch、JAL、JALR 目标地址不对齐 | EX |
| load/store 地址不对齐 | EX |
| 数据访问错误 | MEM，根据 `dmem_rsp_error` |
| CSR 地址不存在、权限不足或对只读 CSR 的真实写 | MEM，根据 CSR 状态所有者的访问检查 |
| 协处理器执行错误 | 后续在 EX 等待响应时 |

RV32I 不支持压缩指令，当前核心使用 `IALIGN=32`。JALR 先把计算结果的 bit 0 清零，再检查最终目标是否按 4 字节对齐；未跳转的条件分支不检查也不产生目标地址未对齐异常。

v0.2 使用以下 Machine Mode 同步异常编码和 `exception_value` 规则：

| `exception_cause` | 异常 | `exception_value` / `mtval` |
|---:|---|---|
| 0 | instruction address misaligned | 最终控制转移目标地址 |
| 1 | instruction access fault | 出错的取指 PC |
| 2 | illegal instruction | 32 位指令字 |
| 3 | breakpoint | 0 |
| 4 | load address misaligned | 有效地址 |
| 5 | load access fault | 有效地址 |
| 6 | store/AMO address misaligned | 有效地址 |
| 7 | store/AMO access fault | 有效地址 |
| 11 | environment call from M-mode | 0 |

当前没有 AMO，但 cause 6/7 沿用规范名称和编码。`mepc` 对所有上述异常保存发生异常的指令 PC。

### 9.2 异常元数据

发生异常的指令携带以下信息向后传递：

```text
exception_valid
exception_cause
exception_value
```

一条指令一旦携带 `exception_valid=1`，后级只能原样保留该异常，不能用年轻阶段重新检测到的条件覆盖它。这样可以保持同一条指令内更早发现的异常优先。

已经携带异常的指令成为不可产生架构副作用的 poisoned instruction：

- 禁止通用寄存器写回；
- 禁止新的数据写或数据读请求；
- 禁止形成真实 CSR 读写访问；
- 禁止协处理器请求；
- 禁止普通退休事件。

### 9.3 MEM 统一提交异常

所有同步异常统一在 MEM 正式提交：

```text
IF 检测 → 携带到 MEM
ID 检测 → 携带到 MEM
EX 检测 → 携带到 MEM
MEM 检测 → 当拍提交
```

这样数据访问错误等最晚异常已经确定；更老指令最多位于 WB，更年轻指令位于 EX、ID 和 IF，可以统一处理。最终资格条件为：

```text
trap_take = !rst
         && ex_mem_q.valid
         && final_mem_exception.valid
         && !mem_response_wait
```

`final_mem_exception` 在 MEM 按以下顺序合并：

```text
如果 ex_mem_q.exception.valid
    保留随指令携带的早期异常
否则如果 csr_access_valid && csr_access_illegal
    cause = 2，value = ex_mem_q.instruction
否则如果 lsu_exception.valid
    使用数据访问错误
否则
    无异常
```

CSR 与 load/store 在合法译码下互斥；上述顺序仍明确保证一条已经 poisoned 的指令不会被后级检查覆盖。`!mem_response_wait` 保证访存指令不再等待尚未完成的响应。CSR 非法访问当拍即可确定，不发起外部事务。早期流水级的 `exception_valid` 只随指令传播，不直接产生 `trap_take`；trap 状态更新、redirect、普通退休抑制都使用合并后的 `final_mem_exception`。

### 9.4 异常提交行为

当异常指令位于 MEM 时：

- MEM/WB 中更老的有效指令可以在该周期正常退休一次；
- 异常指令不进入普通退休路径；
- EX、ID、IF 中所有年轻指令被 flush；
- `mepc` 保存异常指令 PC；
- `mcause` 保存异常原因；
- `mtval` 保存异常附加值；
- 取指地址重定向到 `mtvec`。

流水动作使用事件矩阵中的精确异常行：

```text
取指状态 REDIRECT
IF/ID      CLEAR
ID/EX      CLEAR
EX/MEM     CLEAR
MEM/WB     CLEAR
```

同一条异常指令产生一次 trap 事件，不产生自己的 `retire_valid`。但是，WB 中更老指令的 retire 与 MEM 中较年轻指令的 trap 可以在同一周期同时出现；架构顺序是先完成更老的 WB retire，再提交 trap。

trap 重定向和分支重定向使用独立来源，最终只允许一次经过资格确认的重定向：

```text
qualified_redirect = trap_take
                   ? trap_redirect
                   : ex_redirect_commit ? raw_ex_redirect : none
```

因此 MEM trap 必须压过年轻 EX branch/JAL/JALR，原始 EX redirect 不能绕过流水控制直接修改 IFU。

### 9.5 异常与外部副作用

- EX 已经检测到访存地址未对齐时，不得发出数据请求。
- 已携带异常进入 EX 的 load/store 同样不得发出数据请求。
- load 响应报告错误时，不得写 `rd`，而是产生异常。
- store 响应报告错误时，不得普通退休，而是产生异常。
- 为保持精确异常，存储适配器必须保证报告失败的 store 不产生不可撤销的架构可见写入。
- 更老的 MEM 异常优先于更年轻的 branch、load/store 或协处理器请求。

更老的 MEM 最终异常必须通过 LSU 内部的 `ex_request_block` 阻止年轻 EX
load/store。该信号必须在 `dmem_req_valid`、`request_fire` 和 `outstanding`
状态更新之前生效，不能只在 core 顶层屏蔽 LSU 已生成的外部 valid。当前结构增量先把
`ex_request_block` 放入 LSU 内部；core 已由
`ex_mem_q.valid && final_mem_exception.valid` 驱动该输入。

v0.2 将不支持或保留的编码转换为 illegal-instruction trap，不再依赖仿真断言充当架构行为。

## 10. 本层结论

整体数据通路和流水控制边界已经冻结：

- 四组流水寄存器使用 `LOAD/HOLD/CLEAR` 统一动作；
- 全局事件使用年龄优先的事件—动作矩阵；
- 各类 RV32I 指令的数据来源、EX 用途和 WB 来源明确；
- 数据请求在 EX→MEM 边界发出，固定响应下保持一拍 load-use bubble；
- EX/MEM、MEM/WB 前递和 WB→ID 旁路规则明确；
- 异常元数据随指令传播，并预留 MEM 统一提交位置。

下一层开始确定模块划分、状态所有权、模块依赖和顶层集成方案。
