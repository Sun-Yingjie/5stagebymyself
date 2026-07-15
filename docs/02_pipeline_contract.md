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
| ID | 指令、指令 PC、`PC + 4`、WB 写回信息 | 指令译码、读取寄存器堆、生成立即数、生成 EX/MEM/WB 所需控制信号、检测 load-use hazard | `rs1/rs2` 编号及数据、`rd` 编号、立即数、PC、`PC + 4`、指令及控制信号 |
| EX | ID/EX 中的数据和控制信号、EX/MEM 与 MEM/WB 的前递数据 | 选择前递操作数、完成算术逻辑运算、计算访存地址、选择 store 数据、完成分支比较和分支目标地址计算 | ALU 结果、store 数据、分支是否跳转、分支目标地址、目的寄存器及后续控制信号 |
| MEM | ALU 结果、store 数据、MEM/WB 控制信号、数据请求/响应 | 管理 load/store 请求和完成响应；等待期间反压年轻流水；非访存指令直接向后传递 | load 读出数据、ALU 结果、`PC + 4`、目的寄存器及 WB 控制信号 |
| WB | ALU 结果、load 数据、`PC + 4`、目的寄存器及 WB 控制信号 | 根据写回来源选择最终结果；当指令有效且需要写回时更新寄存器堆 | `wb_write_enable`、`wb_rd_addr`、`wb_write_data`，以及后续使用的退休跟踪信息 |

## 3. 流水状态边界

| 流水寄存器 | 至少需要保存的内容 |
|---|---|
| IF/ID | `valid、pc、instruction、pc_plus_4` |
| ID/EX | `valid、pc、instruction、pc_plus_4、rs1_addr、rs2_addr、rs1_data、rs2_data、rd_addr、immediate、EX/MEM/WB 控制信号` |
| EX/MEM | `valid、pc、instruction、pc_plus_4、exec_result、store_data、rd_addr、MEM/WB 控制信号` |
| MEM/WB | `valid、pc、instruction、exec_result、load_result、pc_plus_4、rd_addr、WB 控制信号` |

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

load-use hazard：

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
> 精确异常/陷阱（后续）
> MEM wait
> EX wait（数据请求、乘除法或协处理器）
> EX redirect
> load-use hazard
> 前端无响应
> normal
```

- 更老指令的阻塞或异常必须阻止年轻指令产生控制事件。
- MEM wait 高于 EX redirect，因为 MEM 中的访存指令比 EX 中的分支更老。
- EX wait 包括数据请求尚未被接受，以及未来乘除法或协处理器尚未完成。
- branch、JAL 和 JALR 都使用 `EX redirect` 事件。
- 精确异常目前只保留控制位置，具体异常提交规则后续定义。

### 5.2 动作矩阵

| 当前最高优先级事件 | 取指状态 | IF/ID | ID/EX | EX/MEM | MEM/WB |
|---|---|---|---|---|---|
| reset | RESET | CLEAR | CLEAR | CLEAR | CLEAR |
| 精确异常/陷阱 | REDIRECT | CLEAR | CLEAR | CLEAR | CLEAR |
| MEM wait | HOLD | HOLD | HOLD | HOLD | CLEAR |
| EX wait | HOLD | HOLD | HOLD | CLEAR | LOAD |
| EX redirect | REDIRECT | CLEAR | CLEAR | LOAD | LOAD |
| load-use hazard | HOLD | HOLD | CLEAR | LOAD | LOAD |
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
```

`uses_rs1` 和 `uses_rs2` 必须来自真实指令语义。冒险检测不能只比较指令字中的 `rs1/rs2` 位域，因为 LUI、AUIPC 和 JAL 等指令在相同比特位置存在编码字段，但并不读取对应通用寄存器。

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
```

MEM/WB 直接前递最终的 `wb_write_data`，因此覆盖 ALU 结果、load 数据和 `PC + 4`。

如果 EX/MEM 中匹配的最新生产者是尚未得到数据的 load，不能跳过该生产者而错误地使用 MEM/WB 中更老的同名结果。v0.1 通过 load-use bubble 和 MEM 反压保证这种消费者不会错误向前推进。

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

### 8.5 load-use hazard

load-use hazard 的语义检测条件为：

```text
ID/EX.valid
&& ID/EX.memory_read
&& ID/EX.rd_addr != 0
&& IF/ID.valid
&& (
       (ID.uses_rs1 && ID.rs1_addr == ID/EX.rd_addr)
    || (ID.uses_rs2 && ID.rs2_addr == ID/EX.rd_addr)
   )
```

检测必须使用译码得到的 `uses_rs1/uses_rs2`，不能只比较指令位域。当前不优化 load 后紧跟 store data 的特殊情况，所有真实依赖统一插入一个 bubble。

### 8.6 必须覆盖的前递场景

- ALU→ALU；
- ALU→branch；
- ALU→JALR；
- ALU→store address；
- ALU→store data；
- load→上述消费者，暂停一拍后从 MEM/WB 前递；
- WB 写回与 ID 读取同一寄存器；
- EX/MEM 和 MEM/WB 同时写同一个 `rd` 时选择更新的 EX/MEM 结果；
- 任何写入 `x0` 的指令都不能成为有效前递生产者。

## 9. 精确异常边界

v0.1 不实现异常处理 RTL，但整体流水预留以下精确异常边界，避免后续改变数据写和协处理器请求的位置。

### 9.1 异常检测位置

| 异常 | 检测位置 |
|---|---|
| 取指访问错误 | IF，根据 `imem_rsp_error` |
| 非法指令、ECALL、EBREAK | ID |
| branch/JAL/JALR 目标地址不对齐 | EX |
| load/store 地址不对齐 | EX |
| 数据访问错误 | MEM，根据 `dmem_rsp_error` |
| 协处理器执行错误 | 后续在 EX 等待响应时 |

RV32I 不支持压缩指令，指令地址按 4 字节对齐。JALR 强制目标地址 bit 0 为 0，但 bit 1 仍可能造成未对齐。

### 9.2 异常元数据

发生异常的指令携带以下信息向后传递：

```text
exception_valid
exception_cause
exception_value
```

异常值根据异常类型选择，例如非法指令使用指令字，访存未对齐使用访问地址，取指错误使用指令 PC。

已经携带异常的指令成为不可产生架构副作用的 poisoned instruction：

- 禁止通用寄存器写回；
- 禁止新的数据写或数据读请求；
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

这样数据访问错误等最晚异常已经确定；更老指令最多位于 WB，更年轻指令位于 EX、ID 和 IF，可以统一处理。

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

普通退休事件和 trap 事件必须互斥。异常指令产生一次 trap 事件，不产生 `retire_valid`。

### 9.5 异常与外部副作用

- EX 已经检测到访存地址未对齐时，不得发出数据请求。
- load 响应报告错误时，不得写 `rd`，而是产生异常。
- store 响应报告错误时，不得普通退休，而是产生异常。
- 为保持精确异常，存储适配器必须保证报告失败的 store 不产生不可撤销的架构可见写入。
- 更老的 MEM 异常优先于更年轻的 branch、load/store 或协处理器请求。

v0.1 遇到不支持的编码时使用仿真断言报告错误，官方架构测试只运行已实现子集。v0.2 加入 CSR 和异常状态后，再将这些情况转换为架构规定的 trap。

## 10. 本层结论

整体数据通路和流水控制边界已经冻结：

- 四组流水寄存器使用 `LOAD/HOLD/CLEAR` 统一动作；
- 全局事件使用年龄优先的事件—动作矩阵；
- 各类 RV32I 指令的数据来源、EX 用途和 WB 来源明确；
- 数据请求在 EX→MEM 边界发出，固定响应下保持一拍 load-use bubble；
- EX/MEM、MEM/WB 前递和 WB→ID 旁路规则明确；
- 异常元数据随指令传播，并预留 MEM 统一提交位置。

下一层开始确定模块划分、状态所有权、模块依赖和顶层集成方案。
