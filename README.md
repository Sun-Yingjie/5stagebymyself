# RV32 五级流水处理器核

这是一个面向数字 IC、处理器微架构学习与实习展示的 32 位 RISC-V 处理器核。项目当前聚焦一件事：把一颗单发射、顺序执行的五级流水 Core 做成可阅读、可运行、可验证的完整 RTL 工程。

## 架构概览

```text
                         retire / trap
                              │
IMem valid-ready ──► IF ─► ID ─► EX ─► MEM ─► WB
                                          │
                                  DMem valid-ready
```

- `IF / ID / EX / MEM / WB` 五级流水，单发射、顺序执行；
- 独立 IMem/DMem request-response 接口，各通道最多一笔在途事务；
- EX/MEM、MEM/WB 前递和 WB→ID 同周期旁路；
- load/CSR late-result bubble、EX redirect、存储反压与在途事务复位；
- MEM 统一提交精确同步 trap，并提供独立 retire/trap 观察接口；
- 面向综合的 SystemVerilog RTL，Icarus 与 Verilator 共用同一套回归入口。

## 当前指令范围

| 类别 | 已实现指令或行为 |
|---|---|
| 寄存器整数运算 | `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND` |
| 立即数整数运算 | `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` |
| 高位立即数 | `LUI AUIPC` |
| 条件分支 | `BEQ BNE BLT BGE BLTU BGEU` |
| 跳转 | `JAL JALR` |
| Load | `LB LH LW LBU LHU` |
| Store | `SB SH SW` |
| 顺序与环境 | `FENCE` 正常退休；`ECALL EBREAK` 产生同步 trap |
| Zicsr | `CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI` |

当前同步异常覆盖 cause `0/1/2/3/4/5/6/7/11`。这表示已有 RV32I 主体、Zicsr 访问机制与最小 Machine trap 状态，不等于完整特权架构实现。

## 快速回归

需要 Bash、Icarus Verilog、`vvp` 和 Verilator。

```bash
scripts/run_regression.sh
```

仅运行 Icarus unit/core 回归：

```bash
scripts/run_regression.sh --icarus-only
```

如需保留编译与运行日志：

```bash
BUILD_ROOT=/tmp/rv32-build scripts/run_regression.sh
```

当前完整回归结果：

```text
14/14 unit TBs passed
Icarus core:   20/20 scenarios, 139 retirements, 12 traps, 21 DMem requests, 3918 checks
Verilator core: 20/20 scenarios, 139 retirements, 12 traps, 21 DMem requests, 3918 checks
```

GitHub Actions 在 Pull Request、推送到 `main` 和手动触发时运行同一脚本。

## 仓库结构

```text
README.md
LICENSE
rtl/                         Core RTL
tb/unit/                     叶子模块 self-checking TB
tb/core/                     Core TB、scoreboard、存储模型
filelists/rv32_core_rtl.f     唯一 RTL 编译清单
scripts/run_regression.sh     本地与 CI 的统一回归入口
.github/workflows/
└── rtl-regression.yml        GitHub Actions 回归
docs/
├── architecture.md          ISA、模块、状态与顶层接口
├── pipeline.md              流水推进、冒险、反压与 flush
├── csr_trap.md              CSR profile 与精确同步 trap
├── verification.md          验证结构、结果、复现与缺口
└── design/                  已冻结的最终目标与后续增量设计合同
    ├── 00_final_target.md
    ├── 01_mret.md
    ├── 02_machine_counters.md
    ├── 03_rv32m_mdu.md
    └── 04_machine_interrupt.md
```

## 阅读顺序

1. [总体架构与接口](docs/architecture.md)
2. [五级流水契约](docs/pipeline.md)
3. [CSR 与同步 Trap](docs/csr_trap.md)
4. [验证方法与结果](docs/verification.md)
5. [最终处理器设计目标](docs/design/00_final_target.md)

1～4 描述当前 RTL 已实现事实；5 及其子设计描述后续准备实现的能力，不得提前解读为已实现功能。

## 已知限制与采用的路线

- 尚未实现 RV32M、`MRET`、`WFI` hint、interrupt、counter、Cache、MMU、Linux、多核和一致性；
- 协处理器端口在 RTL 中保留，但当前固定关闭；
- 当前 backpressure 证据以 directed 场景为主，尚未形成随机等待回归；
- 尚未接入 ACT4 和参考模型差分，不能宣称完成完整架构认证。

项目已采用 [最终处理器设计目标](docs/design/00_final_target.md)，后续依赖顺序固定为：

```text
D0  冻结设计合同
 → D1  MRET + WFI hint
 → D2  Machine counters
 → D3  RV32M 迭代式 MDU
 → D4  精确 Machine interrupt
 → D5  最终设计冻结与 directed/random regression
 → V1  ACT4 与参考模型差分
 → A1  ASIC lint、综合、约束与 STA
```

`docs/design/` 设计合同合入 `main` 标志 D0 完成，随后进入 D1。D1～D4 各使用独立能力分支和 PR，同步交付合同状态更新、RTL、unit/core directed test 与完整回归证据；D5 再独立完成随机回归和最终设计冻结。ACT4、差分和 ASIC 工具链位于功能设计闭环之后，不是 D0～D5 的替代验收。

NPU、异构系统、AXI crossbar 和 DMA 仍在独立项目中维护。本处理器项目只在 A1 阶段接入 Core 自身的 ASIC 前端流程；当前不含已完成的工艺映射或 signoff 结果。

## 许可证

本项目采用 [Apache License 2.0](LICENSE)。
