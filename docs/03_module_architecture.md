# 模块划分与顶层集成架构

> 上位规格：`00_processor_architecture.md`、`01_core_system_context.md`、`02_pipeline_contract.md`  
> 当前阶段：冻结模块职责、状态所有权、依赖关系和顶层集成方式，暂不编写 RTL。

## 1. 模块划分原则

- 模块边界按照职责和状态所有权划分，不机械地为每个流水级或每个多路器创建模块。
- 四组流水寄存器集中由 `rv32_core` 管理，以便统一实现 `LOAD/HOLD/CLEAR`。
- 拥有独立事务状态的 IFU 和 LSU 分别封装。
- 数据相关检测和全局流水动作选择分离，避免一个控制模块同时理解全部数据通路细节。
- v0.1 不创建 CSR、乘除法和协处理器 RTL，只保留后续接入位置。
- 模块接口必须能够独立验证，但不能为了单元测试而复制架构状态。

## 2. 顶层模块树

```text
rv32_core
├── rv32_ifu
├── rv32_idu
│   ├── rv32_decoder
│   ├── rv32_imm_gen
│   └── rv32_regfile
├── rv32_exu
│   ├── rv32_alu
│   └── rv32_branch_compare
├── rv32_lsu
├── rv32_forward_unit
├── rv32_pipeline_ctrl
└── rv32_csr_trap         v0.2 加入
```

另有非模块公共包：

```text
rv32_pkg.sv
```

公共包用于保存 ISA 常量、枚举、语义控制类型和流水数据结构，不拥有硬件状态。

## 3. 模块职责

### 3.1 `rv32_core`

- 定义处理器核外部端口；
- 实例化并连接所有子模块；
- 保存 IF/ID、ID/EX、EX/MEM、MEM/WB；
- 对四组流水寄存器执行统一动作；
- 组织 WB 写回选择和退休跟踪输出；
- 保证顶层数据流和控制流可以在一个文件中完整追踪。

### 3.2 `rv32_ifu`

- 保存下一取指地址；
- 管理指令请求在途状态和请求 PC；
- 接收、保持或丢弃指令响应；
- 保存 branch/jump 重定向目标；
- 标记并排空错误路径取指响应；
- 向核心提供可装入 IF/ID 的取指结果。

### 3.3 `rv32_idu`

- 组织指令译码、立即数生成和通用寄存器读取；
- 接收 WB 写回端口；
- 完成 WB→ID 显式旁路；
- 将 `FENCE` 译码为无源寄存器、无写回、无访存控制的合法流水指令；
- 输出 ID/EX 所需的数据和语义控制；
- 不拥有流水寄存器。

`rv32_decoder`、`rv32_imm_gen` 和 `rv32_regfile` 是 IDU 内部可独立验证的子模块。

### 3.4 `rv32_exu`

- 根据前递选择生成 `rs1_exec/rs2_exec`；
- 选择 ALU 操作数；
- 执行算术、逻辑、移位和比较；
- 完成 branch 条件判断和 redirect 目标计算；
- 计算 load/store 地址和 store 写数据；
- 为未来乘除法和协处理器结果预留接入位置。

### 3.5 `rv32_lsu`

- 使用 EX 计算结果形成数据请求；
- 管理请求是否已经握手以及响应是否仍在等待；
- 输出 EX 请求等待和 MEM 响应等待事件；
- 生成 `wstrb` 和对齐后的 store 写数据；
- 处理 load 字节选择、符号扩展或零扩展；
- 把正常结果或访问错误交给后续流水控制。

### 3.6 `rv32_forward_unit`

- 比较 ID/EX 源寄存器与 EX/MEM、MEM/WB 目的寄存器；
- 产生 `rs1` 和 `rs2` 的前递选择；
- 实现 EX/MEM 高于 MEM/WB 的优先级；
- 识别不可从 EX/MEM 取得的 load 结果；
- 根据 `uses_rs1/uses_rs2` 产生 load-use hazard。

该模块只产生选择和 hazard 信息，不保存状态，也不直接修改流水寄存器。

### 3.7 `rv32_pipeline_ctrl`

- 接收 reset、trap、MEM wait、EX wait、redirect、load-use 和前端响应状态；
- 按事件优先级选择唯一事件；
- 输出取指状态以及四组流水寄存器的动作；
- 输出当前 EX 指令是否允许进入 EX/MEM；
- 不保存架构状态，不理解具体指令编码。

### 3.8 `rv32_csr_trap`

v0.2 加入，拥有 `mstatus`、`mtvec`、`mepc`、`mcause` 和 `mtval` 等 Machine Mode 架构状态。它接收 MEM 中已经合并完成的最老异常，完成 CSR 状态更新，并产生：

- 只持续一个周期的 `trap_take`；
- 指向 trap handler 的 `trap_redirect`；
- `trap_valid/pc/cause/value` 跟踪事件。

该模块不检测译码、地址或总线错误，也不直接清除流水寄存器。异常检测仍归属各流水功能模块，流水动作仍由 `rv32_pipeline_ctrl` 统一选择。CSR 指令读写和 `mret` 的完整接口在后续 Zicsr/Machine Mode 增量中继续扩展；本轮先冻结同步异常提交边界。v0.1 中不存在该模块实例。

## 4. 状态所有权

| 状态 | 唯一所有者 |
|---|---|
| 下一取指地址、取指在途、过期响应 | `rv32_ifu` |
| `x0～x31` 通用寄存器 | `rv32_regfile` |
| IF/ID、ID/EX、EX/MEM、MEM/WB | `rv32_core` |
| 数据请求已发送、等待响应 | `rv32_lsu` |
| CSR 和 trap 状态 | `rv32_csr_trap`，v0.2 |
| 流水动作选择 | 纯组合 `rv32_pipeline_ctrl`，不拥有状态 |

任何架构状态不能被两个模块同时保存或驱动。流水寄存器中保存的是指令经过该边界所需的快照，不视为对子模块内部状态的复制。

## 5. 不单独建立的模块

v0.1 不单独建立 `rv32_wbu`。WB 当前只包含写回来源选择、寄存器写使能门控和退休输出，放在 `rv32_core` 更容易观察完整提交路径。

四组流水寄存器也不做成四个独立模块。它们使用公共数据类型，但时序更新集中在 `rv32_core`，避免 stall、flush 和 reset 控制分散。

## 6. 内外接口表达方式

### 6.1 外部接口保持扁平

`rv32_core` 的时钟、复位、指令通道、数据通道、退休跟踪和未来协处理器端口使用普通扁平信号，不使用 SystemVerilog `interface/modport`。

这样便于 testbench、SRAM/AXI adapter、SpyGlass、DC、PT 和 Verdi 直接连接、约束和观察顶层端口。

### 6.2 内部使用强类型数据包

流水状态和语义控制使用 `rv32_pkg.sv` 中定义的 `typedef enum logic` 和 `typedef struct packed`。packed struct 只组织位字段，不引入软件对象或动态行为，综合后仍为普通触发器、组合逻辑和连线。

四组流水状态统一命名：

```text
if_id_q   / if_id_d
id_ex_q   / id_ex_d
ex_mem_q  / ex_mem_d
mem_wb_q  / mem_wb_d
```

`_q` 表示当前寄存器值，`_d` 表示组合产生的下一状态。

### 6.3 SystemVerilog 使用边界

可综合 RTL 采用：

- `logic`；
- `always_ff`、`always_comb`；
- `typedef enum logic`；
- `typedef struct packed`；
- `package/import`；
- `parameter/localparam`；
- 纯组合 `function automatic`；
- 必要的 `generate` 和显式 signed/unsigned 转换。

v0.1 暂不在可综合 RTL 中使用 `interface/modport`、class、动态数组、queue、随机化、constraint 或 UVM 风格对象。

### 6.4 公共包使用规则

模块通过 `import rv32_pkg::*;` 或显式 `rv32_pkg::type_name` 引用公共类型。构建顺序保证 `rv32_pkg.sv` 先编译，不使用全局 `` `include `` 复制公共定义。

公共包只保存常量、类型和纯函数，不保存可变硬件状态。所有 enum 明确指定位宽，所有 struct 字段明确指定位宽和有无符号属性。

## 7. 类型目录与流水字段

### 7.1 控制枚举

`rv32_pkg.sv` 定义以下强类型枚举，具体二进制编码在 RTL 设计时显式给出：

| 类型 | 语义值 |
|---|---|
| `pipe_action_e` | `PIPE_LOAD / PIPE_HOLD / PIPE_CLEAR` |
| `fetch_action_e` | `FETCH_RESET / FETCH_HOLD / FETCH_SEQUENTIAL / FETCH_REDIRECT` |
| `alu_operation_e` | `ALU_ADD / ALU_SUB / ALU_SLL / ALU_SLT / ALU_SLTU / ALU_XOR / ALU_SRL / ALU_SRA / ALU_OR / ALU_AND` |
| `immediate_type_e` | `IMM_NONE / IMM_I / IMM_S / IMM_B / IMM_U / IMM_J` |
| `operand_a_select_e` | `OPA_RS1 / OPA_PC / OPA_ZERO` |
| `operand_b_select_e` | `OPB_RS2 / OPB_IMMEDIATE` |
| `branch_operation_e` | `BR_NONE / BR_EQ / BR_NE / BR_LT / BR_GE / BR_LTU / BR_GEU` |
| `memory_size_e` | `MEM_SIZE_BYTE / MEM_SIZE_HALF / MEM_SIZE_WORD` |
| `writeback_select_e` | `WB_EXEC / WB_LOAD / WB_PC_PLUS_4` |
| `forward_select_e` | `FWD_REG / FWD_EX_MEM / FWD_MEM_WB` |

写回来源使用正式枚举常量 `WB_EXEC`，而不是含义过窄的 `ALU`。未来乘除法和协处理器结果进入统一的 execution result 路径，不需要增加新的 WB 多路器输入。所有写回来源枚举常量使用 `WB_` 前缀，避免 package 作用域中的泛化名称冲突。

### 7.2 分层控制数据包

```text
ex_ctrl_t:
    operand_a_select
    operand_b_select
    alu_operation
    branch_operation
    is_jump
    is_jalr

mem_ctrl_t:
    memory_read
    memory_write
    memory_size
    load_unsigned

wb_ctrl_t:
    register_write
    writeback_select
```

ID 本地的完整译码结果为：

```text
decode_ctrl_t:
    uses_rs1
    uses_rs2
    immediate_type
    illegal_instruction
    ex_ctrl
    mem_ctrl
    wb_ctrl
```

`immediate_type` 只用于 ID 生成立即数。进入 ID/EX 的是已经扩展完成的 `immediate`，不再携带立即数类型。

### 7.3 异常数据包

```text
exception_t:
    valid
    cause[31:0]
    value[31:0]
```

v0.1 在流水数据包中保留 `exception_t`，但正常驱动为无异常。异常字段尚未参与架构行为时，综合工具可以删除无扇出的无用逻辑；v0.2 则直接启用这些已预留字段。

### 7.4 流水数据包

```text
if_id_t:
    valid
    pc[31:0]
    instruction[31:0]
    pc_plus_4[31:0]
    exception
```

```text
id_ex_t:
    valid
    pc[31:0]
    instruction[31:0]
    pc_plus_4[31:0]
    rs1_addr[4:0]
    rs2_addr[4:0]
    rd_addr[4:0]
    rs1_data[31:0]
    rs2_data[31:0]
    uses_rs1
    uses_rs2
    immediate[31:0]
    ex_ctrl
    mem_ctrl
    wb_ctrl
    exception
```

```text
ex_mem_t:
    valid
    pc[31:0]
    instruction[31:0]
    pc_plus_4[31:0]
    exec_result[31:0]
    store_data[31:0]
    rd_addr[4:0]
    mem_ctrl
    wb_ctrl
    exception
```

```text
mem_wb_t:
    valid
    pc[31:0]
    instruction[31:0]
    pc_plus_4[31:0]
    exec_result[31:0]
    load_result[31:0]
    rd_addr[4:0]
    wb_ctrl
    exception
```

### 7.5 公共小型数据包

```text
wb_bus_t:
    valid
    rd_write_enable
    rd_addr[4:0]
    rd_data[31:0]
```

```text
redirect_t:
    valid
    target[31:0]
```

数据随指令向后传递，控制信息只传递到最后一个仍然需要它的阶段。

## 8. 模块依赖和组合路径方向

### 8.1 候选状态与动作分离

IFU、IDU、EXU 和 LSU 只计算“如果允许前进，下一状态应该是什么”；pipeline control 只选择 `LOAD/HOLD/CLEAR`，不修改候选数据内容：

```text
当前流水状态 _q
       │
       ▼
IFU / IDU / EXU / LSU
       │
       ▼
候选下一状态 _d
       │
       ├──────────────┐
       │              │
       ▼              ▼
数据相关检测      等待/重定向事件
       │              │
       └──────┬───────┘
              ▼
       pipeline_ctrl
              │
              ▼
      LOAD / HOLD / CLEAR
              │
              ▼
       下一时钟沿更新 _q
```

各模块主要产生：

- IFU：IF/ID 候选、取指响应可用和取指事务状态；
- IDU：ID/EX 候选和 ID 源寄存器语义；
- forward unit：前递选择和 load-use hazard；
- EXU：EX/MEM 候选以及原始 redirect 条件和目标；
- LSU：数据请求、EX 请求等待、MEM 响应等待和 MEM/WB 候选；
- CSR/trap：MEM 最终异常的资格确认、Machine Mode trap 状态和 trap redirect；
- pipeline control：取指动作和四组流水寄存器动作；
- core：状态更新、WB bus、退休/trap 输出和模块连接。

### 8.2 redirect 资格确认

EXU 只产生 `raw_redirect`。如果更老的 MEM 指令正在等待或发生异常，raw redirect 不能直接修改 IFU。

`rv32_csr_trap` 独立产生 `trap_redirect`。pipeline control 选择 `trap_take` 或 `EX redirect` 为当前最高优先级事件后，core 才生成一次 `qualified_redirect` 交给 IFU：trap 目标取自 `trap_redirect`，普通控制转移目标取自 `raw_redirect`。这样更老的 MEM trap 必然压过年轻 EX redirect，被保持在 EX 的同一条 branch 也不会反复重定向。

### 8.3 ready/valid 组合环路约束

请求或响应的 `valid` 不能组合依赖对端的 `ready`。例如：

```text
dmem_request_fire = dmem_req_valid && dmem_req_ready
ex_request_wait   = dmem_req_valid && !dmem_req_ready
```

`dmem_req_valid` 由当前有效访存指令和更老事务状态决定，不允许写成“ready 为 1 才拉高 valid”。响应通道遵守相同规则。

IFU/LSU 输出的响应可用和等待事件只能由当前已注册事务状态、当前流水状态和外部握手输入计算，不能反向组合依赖 pipeline control 输出动作。pipeline control 的动作可以在时钟沿更新 IFU/LSU 状态，但不能参与产生当前周期事件的组合路径。

### 8.4 Pipeline control 输入抽象

pipeline control 只接收归纳后的事件：

```text
trap_take
mem_response_wait
ex_request_wait
ex_multicycle_wait
raw_redirect_valid
load_use_hazard
fetch_response_available
```

`trap_take` 必须已经由 MEM 最终异常资格确认产生，不能是 IF、ID 或 EX 的原始异常。pipeline control 不解析指令字，不计算地址，不选择前递数据，也不直接驱动寄存器写或存储器写。

## 9. 模块接口契约

本节定义信息方向和职责，不冻结最终 SystemVerilog 端口排列。

### 9.1 IFU

输入：

```text
clk、rst
fetch_action
qualified_redirect
if_id_ready
imem_req_ready
imem_rsp_valid/data/error
```

输出：

```text
imem_req_valid/addr
imem_rsp_ready
if_id_candidate
fetch_response_available
```

`fetch_response_available` 不依赖 `if_id_ready`。`if_id_ready` 只决定响应是否在当前周期完成握手并进入 IF/ID。

### 9.2 IDU

输入：

```text
if_id_q
wb_bus
```

输出：

```text
id_ex_candidate
```

IDU 内部完成译码、立即数生成、寄存器读取和 WB→ID 旁路。候选数据同时向 forward unit 提供当前 ID 指令的源寄存器语义。`FENCE` 不需要新增控制字段：decoder 清除 `illegal_instruction`，保持所有副作用控制为 0，并选择确定的 `zero + zero` 内部执行结果，避免被忽略的编码字段引入 X 传播；现有 valid 流水自然把它送到 WB 退休。

### 9.3 Forward unit

输入：

```text
id_ex_candidate   当前 ID 消费者
id_ex_q           当前 EX 消费者
ex_mem_q          较新生产者
mem_wb_q          较老生产者
```

输出：

```text
rs1_forward_select
rs2_forward_select
load_use_hazard
```

该模块只产生选择和 hazard 信息，不传输或保存 32 位前递数据。

### 9.4 EXU

输入：

```text
id_ex_q
rs1_forward_select
rs2_forward_select
ex_mem_forward_value
mem_wb_forward_value
```

输出：

```text
ex_mem_candidate
raw_redirect
```

`raw_redirect` 不能直接驱动 IFU，必须先经过全局事件优先级确认。

### 9.5 LSU

输入：

```text
ex_mem_candidate
ex_mem_q
dmem_req_ready
dmem_rsp_valid/rdata/error
```

输出：

```text
dmem_req_valid/write/addr/wdata/wstrb
dmem_rsp_ready
ex_request_wait
mem_response_wait
mem_wb_candidate
mem_exception
```

`ex_mem_candidate` 用于形成即将从 EX 进入 MEM 的新请求，`ex_mem_q` 对应当前 MEM 中已经发送请求并等待响应的指令。

### 9.6 Pipeline control

输入：

```text
rst
trap_take
mem_response_wait
ex_request_wait
ex_multicycle_wait
raw_redirect.valid
load_use_hazard
fetch_response_available
```

输出：

```text
fetch_action
if_id_action
id_ex_action
ex_mem_action
mem_wb_action
redirect_commit
```

`redirect_commit` 表示普通 EX redirect 获准提交；`trap_take` 使用事件优先级中的独立 trap 路径。core 根据被选中的事件和对应目标产生唯一 `qualified_redirect`。

### 9.7 CSR/trap

输入：

```text
clk、rst
mem_valid
mem_pc
mem_exception
```

输出：

```text
trap_take
trap_redirect
trap_valid
trap_pc
trap_cause
trap_value
```

`mem_exception` 必须是 LSU 合并当前数据响应错误后的最终异常。`trap_take` 只在 `mem_valid && mem_exception.valid` 且该指令不再等待响应时有效；该周期的时钟沿把 `mem_pc`、`mem_exception.cause/value` 分别写入 `mepc`、`mcause`、`mtval`。`trap_redirect` 取自 `mtvec` 定义的 trap 入口。

`trap_valid/pc/cause/value` 与该次 `trap_take` 一一对应，不报告尚未提交的早期异常。CSR 指令访问端口和 `mret` 端口在后续增量中加入，不改变这里的异常提交接口。

### 9.8 Core

Core 根据 MEM/WB 当前状态生成 WB bus 和退休信息，仲裁 trap/EX redirect，根据动作和各级候选状态在唯一时序更新点更新四组流水寄存器。同周期存在更老 WB retire 和较年轻 MEM trap 时，两组跟踪输出都可以有效。

### 9.9 组合依赖顺序

```text
MEM/WB_q
  → WB bus

IF/ID_q + WB bus
  → ID candidate

流水状态
  → forwarding/hazard

ID/EX_q + forwarding values
  → EX candidate + raw redirect

EX candidate + EX/MEM_q + dmem
  → LSU events + MEM/WB candidate

所有事件
  → pipeline actions

actions + candidates
  → 下一时钟沿状态
```

这是一张组合依赖图，不是仿真语句的执行顺序。沿箭头不能重新回到起点。

## 10. `rv32_core` 顶层端口

```systemverilog
module rv32_core #(
    parameter logic [31:0] RESET_VECTOR  = 32'h0000_0000,
    parameter bit          COPROC_ENABLE = 1'b0
) (
    input  logic        clk,
    input  logic        rst,

    output logic        imem_req_valid,
    input  logic        imem_req_ready,
    output logic [31:0] imem_req_addr,
    input  logic        imem_rsp_valid,
    output logic        imem_rsp_ready,
    input  logic [31:0] imem_rsp_data,
    input  logic        imem_rsp_error,

    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_addr,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    input  logic        dmem_rsp_valid,
    output logic        dmem_rsp_ready,
    input  logic [31:0] dmem_rsp_rdata,
    input  logic        dmem_rsp_error,

    output logic        retire_valid,
    output logic [31:0] retire_pc,
    output logic [31:0] retire_instr,
    output logic        retire_rd_we,
    output logic [4:0]  retire_rd_addr,
    output logic [31:0] retire_rd_data,

    output logic        cp_req_valid,
    input  logic        cp_req_ready,
    output logic [31:0] cp_req_pc,
    output logic [31:0] cp_req_instr,
    output logic [31:0] cp_req_rs1_data,
    output logic [31:0] cp_req_rs2_data,
    input  logic        cp_rsp_valid,
    output logic        cp_rsp_ready,
    input  logic [31:0] cp_rsp_data,
    input  logic        cp_rsp_error
);
```

上述代码块是当前 v0.1 RTL 的精确端口。v0.2 同步异常闭环在保持现有端口不变的基础上增加：

```systemverilog
    output logic        trap_valid,
    output logic [31:0] trap_pc,
    output logic [31:0] trap_cause,
    output logic [31:0] trap_value
```

这些端口是提交级跟踪接口，不是外部中断输入，也不承担 CSR 软件访问功能。

### 10.1 顶层约束

- `rst` 是高有效同步核心复位，芯片级 `ext_rst_n` 位于外部 wrapper。
- `RESET_VECTOR` 默认是 0，可由测试环境或 SoC 集成修改。
- 指令请求地址必须按 4 字节对齐。
- `dmem_req_addr` 是完整字节地址。
- 数据存储器返回包含目标字节的 32 位对齐数据，LSU 根据地址低位完成字节或半字选择。
- store 写数据移动到对应字节通道，`dmem_req_wstrb[3:0]` 标识有效写字节。
- load/store 共用数据响应通道，store 响应中的 `dmem_rsp_rdata` 无效。
- 每个通道最多一笔在途事务，因此当前不需要事务 ID。

### 10.2 协处理器禁用行为

当 `COPROC_ENABLE = 0` 时：

```text
cp_req_valid = 0
cp_rsp_ready = 0
```

其他协处理器请求输出固定为 0，custom 指令不进入协处理器路径。未使用协处理器输入产生的 lint 信息必须通过参数化常量传播或有依据的局部 waiver 处理，不能用无意义逻辑掩盖。

v0.1 顶层不包含外部中断、trap 跟踪、Cache、AXI、JTAG 或调试接口；v0.2 只按上述定义增加同步异常的 trap 跟踪输出，外部中断仍不加入。

## 11. 本层结论

模块划分和顶层集成架构已经冻结：

- 模块按职责与状态所有权划分；
- 流水寄存器集中在 core；
- 外部端口扁平、内部数据包强类型；
- 候选数据、事件检测和动作选择单向依赖；
- 模块接口契约和组合依赖方向明确；
- `rv32_core` 顶层参数、端口、位宽和协处理器禁用行为明确。

下一层定义验证体系以及 VCS、SpyGlass、DC、Formality 和 PT 的验收标准。
