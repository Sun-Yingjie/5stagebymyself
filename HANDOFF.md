# 五级流水 RISC-V 处理器项目交接文档

> 交接日期：2026-07-16  
> 项目路径（原设备）：`F:\file\project\5stagebymyself`  
> Git 分支：`main`，交接文档创建前与 `origin/main` 同步  
> 交接文档创建前最新提交：`db32459 Add rv32_pipeline_ctrl module for pipeline control logic and hazard management`  
> 当前准确停点：`rv32_pipeline_ctrl.sv` 已完成并通过 lint，尚未创建 `tb/unit/tb_rv32_pipeline_ctrl.sv`

## 1. 给接手 Codex 的快速指令

请不要重新从零规划处理器，也不要直接跳到完整 `rv32_core`。接手后按以下顺序工作：

1. 完整阅读本文件；
2. 阅读 `docs/00_processor_architecture.md` 至 `docs/05_rtl_implementation_order.md`；
3. 阅读 `rtl/rv32_pkg.sv`、`rtl/rv32_pipeline_ctrl.sv`；
4. 浏览现有 `rtl/` 和 `tb/unit/`，确认接口没有因传输而改变；
5. 先创建并完成 `tb/unit/tb_rv32_pipeline_ctrl.sv`；
6. 该 TB 通过后再进入 `rv32_idu.sv`，不要提前实现 IFU、LSU 或完整 core。

本项目的默认协作方式是：**用户亲手逐行编写主要 RTL，Codex 负责讲解、拆分、审阅、验证和补充经用户授权的重复性测试**。不要一上来把整个处理器代码全部生成给用户。

## 2. 项目目标与用户背景

用户已经学习《Digital Design and Computer Architecture》，希望通过亲手实现一颗简单的 RISC-V 五级流水处理器，系统学习数字 IC 实习需要的知识。目标不只是“代码能跑”，还包括：

- 能解释每个流水级、流水寄存器和控制事件的逐周期行为；
- 能分析 RAW、load-use、控制冒险和访存副作用；
- 能写可综合、可 lint、便于波形调试的 SystemVerilog RTL；
- 能建立模块单测、核心级定向测试、官方 ISA 测试和退休跟踪；
- 最终完成 VCS、SpyGlass、DC，并在后续完成 FM、PT 和代表性门级仿真闭环；
- 为数字 IC 实习准备一套可以讲清微架构、验证证据和 ASIC 结果的项目。

用户有过流片经历，使用过 DC 和 VCS；可用工具包括 DC、VCS、Formality、PrimeTime、SpyGlass、Verdi。用户有 SMIC 28nm 和 180nm 工艺库。

主目标工艺已经确定为 **SMIC 28nm**。180nm 只作为核心稳定后的工艺尺度对比，不同时维护两套主收敛目标。

## 3. 协作原则

### 3.1 学习优先

- 先解释硬件含义、接口责任和常见错误，再让用户手写；
- 每次只推进一个清晰的小步骤；
- 审阅时给出具体证据，不只说“看起来没问题”；
- 对关键概念使用逐周期例子；
- 重复性 TB 用例可以在用户明确表示不想继续手写后由 Codex 补齐；
- 每个模块完成后运行 lint 和单元仿真，再进入下一模块。

### 3.2 设计方式

- 坚持自上而下：架构边界 → 流水契约 → 模块责任 → RTL → 验证；
- 当前只关注五级流水核心，协处理器/NPU 只保留扩展边界；
- 不为了“显得高级”过度使用 SystemVerilog；
- 使用可综合的工程化子集：`logic`、`always_ff`、`always_comb`、`typedef enum logic`、`typedef struct packed`、package、parameter、function；
- 暂不使用 RTL `interface/modport`、class、动态数组和软件式复杂抽象；
- 外部接口保持扁平，小型模块只传真正需要的字段；流水寄存器使用 package 中的 packed struct。

### 3.3 修改文件

- 现有代码大部分由用户亲手写成，请保留其结构和可读性；
- 未经用户要求，不要进行大规模重构；
- 源文件修改后检查文件末尾换行；
- 中文文档使用 UTF-8；PowerShell 读取时建议显式 `Get-Content -Encoding UTF8`。

## 4. 已冻结的 v0.1 架构

### 4.1 微架构

- 32 位地址和数据；
- 单发射、顺序执行；
- `IF / ID / EX / MEM / WB` 五级流水；
- 指令和数据通路分离；
- 每组流水寄存器都有独立 `valid`；
- branch/JAL/JALR 在 EX 产生重定向；
- 静态预测不跳转；
- EX/MEM 和 MEM/WB 到 EX 的前递；
- load-use 固定插入一个 bubble；
- 两路异步读、一路同步写寄存器堆；
- WB→ID 显式组合旁路；
- 单时钟域；核心内部 `rst` 是高有效同步复位；
- 芯片级 `ext_rst_n` 和 reset synchronizer 在 core 外部；
- `RESET_VECTOR` 参数化，默认规划值为 0；
- v0.1 存储器模型采用请求接受后下一周期响应，接口仍保留 valid/ready；
- 指令、数据通道各自最多一笔在途事务。

### 4.2 v0.1 指令范围

共 37 条：

- R 型：`ADD SUB SLL SLT SLTU XOR SRL SRA OR AND`；
- I 型运算：`ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI`；
- 高位立即数：`LUI AUIPC`；
- 分支：`BEQ BNE BLT BGE BLTU BGEU`；
- 跳转：`JAL JALR`；
- load：`LB LH LW LBU LHU`；
- store：`SB SH SW`。

v0.1 测试只使用自然对齐访问。精确非法指令异常、非对齐访问、`ECALL/EBREAK`、CSR、中断、RV32M 和可变长多周期执行属于后续版本。

### 4.3 当前不做

- Cache、MMU、Linux；
- 超标量、乱序、多核；
- 动态分支预测；
- 浮点和向量；
- 核心内部 AXI；
- 当前阶段的 NPU RTL；
- 在功能稳定前进行极限 PPA 优化。

## 5. 关键设计决定

### 5.1 流水寄存器动作

package 中已冻结：

```text
PIPE_LOAD   装入候选值
PIPE_HOLD   保持当前状态
PIPE_CLEAR  只要求清除 valid，宽数据字段无所谓
```

不要把 bubble 和 flush 简化成“清零某个模块”。应按被清除的流水边界理解：load-use 对 ID/EX `CLEAR` 插入 bubble；EX redirect 对 IF/ID、ID/EX `CLEAR` 冲刷年轻指令。

### 5.2 复位

- core 只接收高有效同步 `rst`；
- reset 清除四组流水寄存器 `valid` 和所有事务控制状态；
- PC 回到 `RESET_VECTOR`；
- 宽数据字段不要求复位；
- `x1~x31` 不要求复位；`x0` 始终读出 0。

### 5.3 寄存器堆与 WB→ID

`rv32_regfile` 只负责：

- 两个组合异步读端口；
- 一个上升沿同步写端口；
- 阻止写 `x0`；
- 读 `x0` 强制返回 0。

WB→ID 旁路不放在 regfile，而放在未来 `rv32_idu`：

```text
wb_bus.valid
&& wb_bus.rd_write_enable
&& wb_bus.rd_addr != 0
&& wb_bus.rd_addr == id_rs*_addr
    → ID 使用 wb_bus.rd_data
否则
    → ID 使用 regfile 读出值
```

所有寄存器和流水寄存器都使用上升沿，不采用下降沿写 regfile 的教学实现。

### 5.4 前递

- `FWD_REG`：使用 ID/EX 保存的寄存器数据；
- `FWD_EX_MEM`：使用较新的 EX/MEM 生产者；
- `FWD_MEM_WB`：使用较老的 MEM/WB 最终写回值；
- EX/MEM 和 MEM/WB 同时匹配时，必须优先 EX/MEM；
- `valid=0`、`register_write=0`、`rd=0` 都不能成为生产者；
- `uses_rs1/uses_rs2` 必须参与判断；
- EX/MEM 中的 load 只有访存地址，不能当作 load 数据前递；
- 如果 EX/MEM 中匹配的是 load，不能跳过它使用 MEM/WB 中更老的同名数据；当前逻辑保持 `FWD_REG`，依靠 load-use/stall 不变量阻止消费者错误推进；
- 前递后的 `rs1_exec/rs2_exec` 再分流到 ALU、branch compare、JALR 和 store data，不能只在 ALU 输入局部旁路。

### 5.5 load-use

检测条件已经实现为：

```text
ID valid
&& EX valid
&& EX 是 load
&& EX.rd != 0
&& (
       ID uses rs1 && ID.rs1 == EX.rd
    || ID uses rs2 && ID.rs2 == EX.rd
   )
```

处理动作：PC/取指 `HOLD`，IF/ID `HOLD`，ID/EX `CLEAR`，后端 `LOAD`。

### 5.6 branch/JAL/JALR

- branch 在 EX 同时进行比较和 `PC + immediate` 目标计算；
- JAL 使用 `PC + immediate`；
- JALR 使用 `rs1 + immediate`，最终目标地址最低位需要清零（在 EXU/重定向逻辑实现时确认）；
- JAL/JALR 写回值为 `PC + 4`；
- `is_jump` 对 JAL/JALR 都为 1，`is_jalr` 只对 JALR 为 1；
- branch 的 `uses_rs1/uses_rs2` 必须为 1，因为比较器存在真实 RAW 相关。

### 5.7 store

- EX 用 `rs1_exec + immediate` 计算地址；
- `rs2_exec` 是 store data，必须经过前递；
- `valid=0` 的 EX/MEM 不得产生 store 请求；
- store 不写寄存器，但仍需走到 WB 并产生一次退休事件；
- 同一 store 请求只能握手一次，响应完成后才退休。

### 5.8 退休

统一在 WB 退休：

```text
retire_valid
retire_pc
retire_instr
retire_rd_we
retire_rd_addr
retire_rd_data
```

`retire_valid` 与寄存器写使能不是同一概念。branch、store 可以正常退休但 `retire_rd_we=0`。写 `x0` 也可以有有效退休事件，但不真正更新寄存器。

### 5.9 规范命名

已经冻结的名称包括：

- `retire_rd_data`，不要改回 `retire_rd_wdata`；
- `WB_EXEC / WB_LOAD / WB_PC_PLUS_4`；
- `OPA_* / OPB_* / ALU_* / BR_* / MEM_SIZE_* / FWD_* / IMM_*`；
- 核心同步高有效复位为 `rst`；只有低有效信号才使用 `_n`。

## 6. 文档层级

按顺序阅读：

1. `docs/00_processor_architecture.md`：项目目标、v0.1 范围和完成标准；
2. `docs/01_core_system_context.md`：外部存储接口、复位、退休、协处理器边界；
3. `docs/02_pipeline_contract.md`：流水职责、动作矩阵、冒险、异常元数据；
4. `docs/03_module_architecture.md`：模块划分、状态所有权和顶层接口；
5. `docs/04_verification_and_asic_plan.md`：验证层次、ASIC 门禁和工具闭环；
6. `docs/05_rtl_implementation_order.md`：RTL 文件顺序和编码约定。

里程碑口径已经统一：

- v0.1：功能/官方测试、VCS、SpyGlass、DC 基础综合；
- v1.0：在 v0.1 上增加 FM、PT 布局前 STA、代表性门级 smoke 和可重复归档；
- 当前没有布局布线工具，因此 PT 结果只能称为综合后、布局前 STA，不能称为 post-layout signoff。

## 7. 当前文件与完成状态

| 文件 | 状态 | 当前证据/说明 |
|---|---|---|
| `rtl/rv32_pkg.sv` | 完成 | ISA 常量、枚举、控制 struct、四组流水 bundle、WB bus、redirect 类型 |
| `rtl/rv32_imm_gen.sv` | 完成 | I/S/B/U/J 立即数；10 个测试通过 |
| `rtl/rv32_alu.sv` | 完成 | 10 类 ALU 操作；16 个测试通过 |
| `rtl/rv32_branch_compare.sv` | 完成 | 六类条件分支；10 个测试通过 |
| `rtl/rv32_decoder.sv` | 完成 | 37 条合法指令及关键非法编码；44 个测试通过 |
| `rtl/rv32_regfile.sv` | 完成 | 双读单写、x0；6 个测试通过 |
| `rtl/rv32_forward_unit.sv` | 完成 | 两级前递、优先级、load-use；17 个测试通过 |
| `rtl/rv32_pipeline_ctrl.sv` | RTL 完成 | 事件优先级和动作矩阵已 lint；TB 尚未创建 |
| `rtl/rv32_idu.sv` | 未开始 | 下一阶段（pipeline control TB 之后） |
| `rtl/rv32_exu.sv` | 未开始 | IDU 之后 |
| `rtl/rv32_ifu.sv` | 未开始 | EXU 之后 |
| `rtl/rv32_lsu.sv` | 未开始 | IFU 之后 |
| `rtl/rv32_core.sv` | 未开始 | 最后集成四组流水寄存器与全局控制 |

现有 TB：

```text
tb/unit/tb_rv32_imm_gen.sv
tb/unit/tb_rv32_alu.sv
tb/unit/tb_rv32_branch_compare.sv
tb/unit/tb_rv32_decoder.sv
tb/unit/tb_rv32_regfile.sv
tb/unit/tb_rv32_forward_unit.sv
```

截至 2026-07-16，以上 6 个 TB 已在原设备重新全量运行，总计 **103 个检查全部 PASS**。

尚不存在：

```text
tb/unit/tb_rv32_pipeline_ctrl.sv
tb/core/*
tests/asm/* 实际测试程序
VCS/SpyGlass/DC/FM/PT 可重复脚本
核心级波形和退休日志
```

## 8. 当前模块：rv32_pipeline_ctrl

### 8.1 输入输出

输入：

```text
rst
trap_take
mem_response_wait
ex_request_wait
ex_multicycle_wait
raw_redirect_valid
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

### 8.2 已实现优先级

```text
rst
> trap_take
> mem_response_wait
> ex_request_wait || ex_multicycle_wait
> raw_redirect_valid
> load_use_hazard
> !fetch_response_available
> normal
```

必须使用一条 `if / else if` 优先级链，不能使用互相覆盖的独立 `if`。

### 8.3 动作矩阵

| 事件 | fetch | IF/ID | ID/EX | EX/MEM | MEM/WB | redirect_commit |
|---|---|---|---|---|---|---:|
| reset | RESET | CLEAR | CLEAR | CLEAR | CLEAR | 0 |
| trap | REDIRECT | CLEAR | CLEAR | CLEAR | CLEAR | 0 |
| MEM wait | HOLD | HOLD | HOLD | HOLD | CLEAR | 0 |
| EX wait | HOLD | HOLD | HOLD | CLEAR | LOAD | 0 |
| EX redirect | REDIRECT | CLEAR | CLEAR | LOAD | LOAD | 1 |
| load-use | HOLD | HOLD | CLEAR | LOAD | LOAD | 0 |
| 无取指响应 | HOLD | CLEAR | LOAD | LOAD | LOAD | 0 |
| normal | SEQUENTIAL | LOAD | LOAD | LOAD | LOAD | 0 |

`redirect_commit` 只批准当前 EX 的 raw redirect。trap 优先级更高，因此 trap 分支必须为 0，避免同时存在年轻 EX redirect 时错误批准它。

### 8.4 接手后的第一项任务：pipeline control TB

请让用户创建：

```text
tb/unit/tb_rv32_pipeline_ctrl.sv
```

已经向用户讲解但尚未落盘的 TB 结构：

- 声明上述全部输入输出；
- 实例化 `rv32_pipeline_ctrl`；
- `set_normal_inputs()` 将所有事件置 0，但必须把 `fetch_response_available=1`；
- `check_actions()` 使用 `!==` 比较六个输出；
- 第一个用例检查 normal：`FETCH_SEQUENTIAL + 五级 PIPE_LOAD + redirect_commit=0`。

建议按以下矩阵完成测试：

#### 单事件用例

1. normal；
2. reset；
3. trap；
4. MEM response wait；
5. EX request wait；
6. EX multicycle wait；
7. raw redirect；
8. load-use；
9. fetch response unavailable。

#### 优先级用例

1. `rst=1` 且其他事件全为 1，必须选 reset；
2. `trap_take=1`、`mem_response_wait=1`、`raw_redirect_valid=1`，必须选 trap 且 `redirect_commit=0`；
3. `mem_response_wait=1`、`ex_request_wait=1`、`raw_redirect_valid=1`，必须选 MEM wait；
4. `ex_request_wait=1`、`raw_redirect_valid=1`、`load_use_hazard=1`，必须选 EX wait；
5. `raw_redirect_valid=1`、`load_use_hazard=1`、无 fetch response，必须选 redirect 且 commit=1；
6. `load_use_hazard=1` 且无 fetch response，必须选 load-use。

TB 通过后，再进入 `rv32_idu.sv`。

## 9. 后续 RTL 顺序

严格按依赖推进：

```text
08  rv32_pipeline_ctrl.sv  ← RTL 完成，TB 待完成
09  rv32_idu.sv
10  rv32_exu.sv
11  rv32_ifu.sv
12  rv32_lsu.sv
13  rv32_core.sv
```

### 9.1 IDU 重点

- 实例化 decoder、imm_gen、regfile；
- 提取 `rs1/rs2/rd`；
- 构造 `id_ex_candidate`；
- 实现 WB→ID 同周期旁路；
- illegal 指令当前保留异常元数据路径，但精确异常行为不扩大到 v0.1；
- IDU 不拥有流水寄存器，`rv32_core` 才拥有 IF/ID 和 ID/EX 状态。

### 9.2 EXU 重点

- 根据 `FWD_REG/FWD_EX_MEM/FWD_MEM_WB` 选择 `rs1_exec/rs2_exec`；
- 前递选择发生在 ALU/branch/store data 分流之前；
- 选择 ALU A/B；
- 实例化 ALU 与 branch compare；
- branch/JAL/JALR 产生 `raw_redirect`；
- JALR 目标最低位清零；
- 形成 `ex_mem_candidate`；
- EX/MEM 前递值需根据 WB 来源区分 exec result 与 `PC+4`，load 不可从普通 EX/MEM 前递。

### 9.3 IFU 重点

- 明确区分 `request_pc`、`next_fetch_addr`、`IF/ID.pc`；
- 返回指令关联的是发出请求时保存的 `request_pc`，不是当拍 next PC；
- 管理单笔在途请求、旧路径响应丢弃和 redirect；
- `fetch_response_available` 不组合依赖 `if_id_ready`；
- 注意文档中的 `FETCH_SEQUENTIAL` 只应在顺序请求真正握手时推进请求地址。最终集成 IFU 时必须复核，不能简单把“有响应”和“请求握手”混为一个事件。

### 9.4 LSU 重点

- 地址、大小、符号扩展、wstrb、store data 移位；
- 请求未握手时保持 valid 和请求字段；
- 单笔在途且 store 只请求一次；
- `ex_request_wait` 与 `mem_response_wait` 语义分开；
- v0.1 固定一周期响应，仍需少量 backpressure 定向测试。

### 9.5 Core 重点

- 四组流水寄存器集中在 `rv32_core` 更新；
- 每组统一实现 `PIPE_LOAD/HOLD/CLEAR`；
- `CLEAR` 只清 valid；
- WB bus、退休、寄存器写门控和流水动作统一连接；
- 保证错误路径、bubble、无效指令不产生 regfile/store/协处理器/退休副作用。

## 10. 工具环境与已验证命令

### 10.1 原设备轻量验证环境

OSS CAD Suite 位于：

```text
D:\oss-cad-suite
```

Verilator 需要：

```powershell
$env:VERILATOR_ROOT='D:\oss-cad-suite\share\verilator'
```

单模块 lint 示例：

```powershell
verilator_bin.exe --lint-only --sv -Wall -Wno-fatal -Wno-UNUSEDPARAM `
    rtl\rv32_pkg.sv `
    rtl\rv32_pipeline_ctrl.sv
```

Icarus 单测示例：

```powershell
$out = Join-Path $env:TEMP 'tb_rv32_forward_unit.vvp'
cmd.exe /d /c "call D:\oss-cad-suite\environment.bat && iverilog -g2012 -s tb_rv32_forward_unit -o $out rtl\rv32_pkg.sv rtl\rv32_forward_unit.sv tb\unit\tb_rv32_forward_unit.sv && vvp $out"
```

在另一设备上请按实际安装位置修改路径，不要把本机绝对路径写进工程脚本。

### 10.2 已知工具提示

Icarus 对 `always_comb` 中常量位选可能输出：

```text
sorry: constant selects in always_* processes are not fully supported
```

这是 Icarus 将敏感列表保守扩展到整个信号的能力提示，不是 RTL 功能错误。

Verilator 可能报告：

- imm_gen 没有使用 instruction opcode 位；
- decoder 没有使用 `rs1/rs2/rd` 位，因为这些字段由 IDU 提取；
- package 中某些常量对单独 leaf top 未使用。

这些提示必须理解后局部处理，不能用宽泛 waiver 掩盖真正问题。

### 10.3 2026-07-16 验证快照

- 现有 6 个 TB 全部通过；
- 合计 103 个检查通过；
- 8 个现有 RTL 文件一起通过 Verilator lint；
- 尚未运行 VCS、SpyGlass、DC、FM、PT；
- 尚未建立波形归档和核心级回归脚本。

## 11. 常见误区和已纠正问题

- 不要把 `retire_valid` 等同于寄存器写使能；
- 不要把写 `x0` 的指令当成无效指令；
- 不要只在 ALU 输入做旁路，branch 与 store data 也依赖前递后的源数据；
- 不要根据指令位域是否非零判断是否使用 `rs1/rs2`，必须使用 decoder 的 `uses_rs*`；
- 不要让 EX/MEM load 把地址当作 load 数据前递；
- 不要让 load 的较新 EX/MEM 匹配被更老 MEM/WB 同名值绕过；
- 不要在 `valid=0` 时产生 store 或退休副作用；
- 不要为了“波形没有 X”复位所有宽数据寄存器；通过 valid 说明字段是否有意义；
- 非法指令不能被静默译码为正常 ADD 等操作；
- trap 优先于年轻 EX redirect，trap 分支不能拉高 raw `redirect_commit`；
- TB 中每个用例都要重新设置默认输入，避免前一个场景泄漏；
- TB 使用 `!==` 捕获 X/Z；
- 时序 TB 在采样沿后等待一个小延迟，避免 NBA 竞争。

## 12. 当前 Git 与交付注意事项

交接文档创建前：

```text
branch: main
tracking: origin/main
HEAD: db32459
worktree: clean
```

创建本文件后，`HANDOFF.md` 会成为新增工作区文件。除非用户明确要求，不要自动替用户提交、推送或重写历史。用户会自行把本文件与现有工程交给另一设备。

## 13. 接手后的推荐第一句话

建议接手 Codex 向用户确认：

> 我已读取 `HANDOFF.md` 和现有架构文档，当前不重做架构规划。准确停点是 `rv32_pipeline_ctrl.sv` 已完成、`tb_rv32_pipeline_ctrl.sv` 尚未创建。我们先按现有动作矩阵完成 normal、单事件和优先级测试；通过后进入 `rv32_idu.sv`，继续保持你手写主要 RTL、我讲解和审阅的协作方式。

