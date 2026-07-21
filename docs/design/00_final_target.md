# 最终处理器设计目标

## 1. 文档地位

本文档冻结本项目的最终实现目标和后续增量边界。它描述“准备实现什么”，不表示
相关能力已经存在。当前已实现事实仍以仓库根目录的 `README.md`、
`docs/architecture.md`、`docs/pipeline.md`、`docs/csr_trap.md` 和
`docs/verification.md` 为准。

本目录中的子设计必须服从本文档。能力进入 RTL 并通过对应验证后，才更新当前能力
文档；设计计划不得提前写成实现结论。

## 2. 一句话目标

实现一颗可综合、可验证、面向裸机程序的：

```text
RV32IM_Zicsr + M-mode-only execution profile
```

处理器核保持 32 位、单 hart、单发射、顺序执行和五级流水。最终项目用于学习处理器
微架构与同步 RTL，并在设计闭环后依次接入 ACT4、差分验证和 ASIC 前端工具链。

本项目不把目标描述为完整 RISC-V 特权架构、Linux 处理器或完整 SoC。

规范基线采用 RISC-V International 当前 ratified 文档中的 RV32I 2.1、M 2.0、
Zicsr 2.0 和 Machine-Level ISA 1.13。实现阶段若升级规范版本，必须以独立文档提交
记录兼容性变化，不能静默改变已冻结语义。

- [RV32I Base Integer ISA](https://docs.riscv.org/reference/isa/unpriv/rv32.html)
- [M Extension](https://docs.riscv.org/reference/isa/unpriv/m-st-ext.html)
- [Zicsr Extension](https://docs.riscv.org/reference/isa/unpriv/zicsr.html)
- [Machine-Level ISA](https://docs.riscv.org/reference/isa/priv/machine.html)

## 3. 最终架构范围

### 3.1 ISA

| 范围 | 最终支持内容 |
|---|---|
| RV32I | 当前整数、控制流、load/store 与 `FENCE` 指令 |
| M | `MUL MULH MULHSU MULHU DIV DIVU REM REMU` |
| Zicsr | `CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI` |
| 环境与返回 | `ECALL EBREAK MRET`；`WFI` 作为合法 NOP hint |

`FENCE.I` 属于 Zifencei，不在目标内。压缩、原子、浮点、向量和位操作扩展也不在
目标内。完整 RV32M 通过前，`misa.M` 必须保持为 0；完整实现后固定报告
`misa=0x40001100`。

### 3.2 Machine profile

最终保留当前 CSR，并新增以下状态：

| CSR | 地址 | 最终语义 |
|---|---:|---|
| `mstatus` | `0x300` | 保存 `MIE/MPIE`，`MPP` 固定为 Machine |
| `misa` | `0x301` | 固定报告 RV32IM，合法 WARL 写不改变状态 |
| `mie` | `0x304` | 保存 `MEIE/MTIE/MSIE`，其余位为 0 |
| `mtvec` | `0x305` | 只支持 Direct mode |
| `mscratch` | `0x340` | 32 位读写 |
| `mepc` | `0x341` | `IALIGN=32`，低两位读作 0 |
| `mcause` | `0x342` | 同步异常或 Machine interrupt cause |
| `mtval` | `0x343` | 同步异常 payload；interrupt 写 0 |
| `mip` | `0x344` | 只读反映 `MEIP/MTIP/MSIP` 输入 |
| `mcycle/mcycleh` | `0xB00/0xB80` | 64 位 Machine cycle counter |
| `minstret/minstreth` | `0xB02/0xB82` | 64 位 Machine commit counter |

Machine ID CSR 保持当前只读零值 profile。没有 U/S Mode，因此不实现
`mcounteren`；不实现 `time/timeh` 和用户态 counter shadow，也不声明 Zicntr。
`mcountinhibit` 不实现，行为等价于固定为 0。

### 3.3 Trap 与 interrupt

最终支持：

- 当前 cause `0/1/2/3/4/5/6/7/11` 的精确同步异常；
- `MRET` 返回；
- Machine software interrupt，interrupt cause 3；
- Machine timer interrupt，interrupt cause 7；
- Machine external interrupt，interrupt cause 11；
- interrupt 时 `mcause[31]=1`；
- 同时 pending 时固定优先级 `MEI > MSI > MTI`；
- `mtvec` 只支持 Direct mode。

同步异常优先于同一架构边界上的 interrupt。所有 trap 和返回都必须满足精确状态：
更老指令可以提交，故障或被中断边界之后的指令不得产生副作用。

### 3.4 微架构

以下选择保持不变：

- `IF / ID / EX / MEM / WB` 五级流水；
- 每级 packet 带 `valid`，由集中式 `LOAD/HOLD/CLEAR` 控制；
- 静态不跳转，branch/JAL/JALR 在 EX 决策；
- EX/MEM、MEM/WB forwarding 和 WB 到 ID bypass；
- load/CSR late-result bubble；
- 独立 IMem/DMem request-response valid-ready 接口；
- 每个存储通道最多一笔 outstanding；
- 同步异常在 MEM 统一判定；
- 正常指令经过 MEM/WB，在 WB 产生外部 retire 事件。

RV32M 使用 EX 内单发射、单在途、固定迭代次数的阻塞式 MDU。只在 MDU 边界使用
局部 request/response 握手，不把整条流水改造成 elastic valid-ready pipeline。

### 3.5 时钟与复位合同

- Core 只有一个 `clk`，全部架构和微架构状态在 `posedge clk` 更新；
- `rst` 为高有效同步复位；
- 不使用 derived clock、异步状态更新或内部三态；
- 首版不加入 clock gating；
- 顶层 Machine interrupt 输入定义为与 `clk` 同步的电平信号；
- 异步中断源的同步器属于 SoC wrapper，不属于 Core；
- 所有组合逻辑必须完整赋值，不允许推断 latch；
- valid-ready source 在 `valid && !ready` 时必须保持 valid 和 payload。

## 4. 明确非目标

- U/S Mode、特权级切换和 trap delegation；
- PMP、MMU、页表、Linux；
- Cache、多核、一致性和非阻塞访存；
- vectored `mtvec`、NMI、debug mode；
- `WFI` 睡眠状态、时钟门控和低功耗流程；`WFI` 指令本身只作为 NOP hint；
- pipelined multiplier、多请求 MDU、乘除并行；
- 全流水 valid-ready 重构；
- 当前处理器项目内的 NPU、AXI crossbar 或 DMA；
- 在功能设计完成前开展 ACT4 或 ASIC signoff 宣称。

## 5. 实现依赖顺序

```text
D0  冻结本目录的设计合同
 ↓
D1  MRET：关闭 trap entry → handler → return 闭环
 ↓
D2  Machine counters：建立内部 commit 事件和 64 位计数状态
 ↓
D3  RV32M：接入固定迭代式阻塞 MDU
 ↓
D4  Machine interrupt：覆盖 DMem、MDU、CSR、MRET 的精确边界
 ↓
D5  最终设计冻结与 directed/random regression
 ↓
V1  ACT4 与参考模型差分
 ↓
A1  ASIC lint、综合、约束与 STA
```

每个 D 阶段使用独立分支和 PR，不在同一 PR 中混入两个架构能力。每个 RTL 增量
必须同时包含对应 unit/core directed test 和设计文档状态更新。

## 6. 设计阶段完成条件

“最终设计已完成”必须同时满足：

1. D1 到 D4 的 RTL 全部合入稳定 `main`；
2. 每项能力的架构行为、状态所有权和优先级与对应设计文档一致；
3. 所有新增行为具有 directed unit/core test；
4. Icarus 和 Verilator 共用回归全部通过；
5. reset、stall、flush、trap 和 redirect 竞争场景没有重复副作用；
6. 当前能力文档已经从“计划”更新为“已实现事实”；
7. 不提前把 ACT4、差分或 ASIC 工具结果写成已通过。

ACT4 和 ASIC 工具链是设计完成后的验证与实现阶段，不是当前 D0 的门槛。

## 7. 同步设计学习主线

| 增量 | 重点学习内容 |
|---|---|
| MRET | 时序状态优先级、一次性 commit、flush 与 redirect |
| Counter | 64 位寄存器、计数使能、同拍自动更新与显式写 |
| RV32M | FSM、迭代数据通路、操作数快照、握手与 backpressure |
| Interrupt | 同步采样、优先级、精确边界和 post-commit 状态 |
| ASIC | 时钟约束、setup/hold、关键路径、综合映射与 STA |

## 8. 子设计索引

1. [MRET 设计](01_mret.md)
2. [Machine Counter 设计](02_machine_counters.md)
3. [RV32M MDU 设计](03_rv32m_mdu.md)
4. [Machine Interrupt 设计](04_machine_interrupt.md)
