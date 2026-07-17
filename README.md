# RV32 五级流水处理器核

本项目是一颗面向数字 IC 与计算机体系结构学习的 32 位 RISC-V 处理器核。当前版本采用单发射、顺序执行的 `IF / ID / EX / MEM / WB` 五级流水，目标是走通从架构定义、RTL、验证到 ASIC 前端分析的完整流程。

## 当前状态

当前冻结版本为 `v0.1-rtl-baseline`，它表示**功能 RTL 基线**，不表示完整 RV32I 认证或 ASIC signoff 完成。

- 37 条 RV32I 程序子集；
- EX/MEM、MEM/WB 前递；
- WB→ID 同周期旁路；
- load-use bubble；
- EX 阶段 branch/JAL/JALR redirect；
- 独立指令/数据 valid-ready 接口；
- 每通道最多一笔在途事务；
- 有限 backpressure 与在途事务复位；
- 统一 WB 退休接口；
- Icarus 11/11 叶子 TB、Icarus/Verilator core 7/7 场景通过；
- SpyGlass `lint/lint_rtl` baseline 已建立。

`HANDOFF.md` 是 2026-07-16 的历史交接快照，其中记录的实现停点已经过期。当前项目状态以本 README、[v0.1 冻结记录](docs/verification/v0.1_freeze_record.md)和[core 验证报告](docs/verification/rv32_core_verification_report.md)为准。

## v0.1 指令范围

| 类别 | 指令 |
|---|---|
| 寄存器整数运算 | `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND` |
| 立即数整数运算 | `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` |
| 高位立即数 | `LUI AUIPC` |
| 条件分支 | `BEQ BNE BLT BGE BLTU BGEU` |
| 跳转 | `JAL JALR` |
| Load | `LB LH LW LBU LHU` |
| Store | `SB SH SW` |

## 快速回归

需要：

- Icarus Verilog 与 `vvp`；
- Verilator；
- macOS/Linux Bash 环境。

运行完整 v0.1 回归：

```bash
scripts/run_v0_1_regression.sh
```

只运行 Icarus 叶子和 core 回归：

```bash
scripts/run_v0_1_regression.sh --icarus-only
```

脚本在系统临时目录中完成编译，不向仓库写入仿真产物。成功结果应包含：

```text
11/11 unit TBs passed
Icarus core: 7/7 scenarios passed
Verilator core: 7/7 scenarios passed
98 retirements, 18 DMem requests, 1715 checks
```

如需保留到指定位置，可以设置：

```bash
BUILD_ROOT=/path/to/build scripts/run_v0_1_regression.sh
```

## 持续集成

GitHub Actions 在以下事件运行同一套 v0.1 回归：

- Pull Request；
- 推送到 `main`；
- 在 Actions 页面手动触发。

工作流入口是 `.github/workflows/rtl-regression.yml`。它在 Ubuntu runner 上安装
Icarus Verilog 和 Verilator，然后直接调用 `scripts/run_v0_1_regression.sh`。
本地与 CI 复用同一脚本，避免两套回归入口随项目演进而产生差异。

## 目录

```text
rtl/            可综合 SystemVerilog RTL
tb/unit/        叶子模块 self-checking testbench
tb/core/        core testbench、scoreboard 和存储器模型
docs/           架构、流水契约、验证和 ASIC 记录
planning/       NPU 与异构系统的长期规划，不属于当前 CPU RTL
filelists/      可综合 RTL 和仿真编译顺序
constraints/    core SDC
scripts/        回归、SpyGlass 和远程工具脚本
reports/        工具报告落点
waves/          阶段性波形落点
```

## 已知边界

- 当前是 RV32I 的 37 条程序子集，不是完整 RV32I；
- 未实现 `FENCE、ECALL、EBREAK`；
- 非法指令、访问错误和非对齐访问尚未形成精确 trap 闭环；
- 未实现 Zicsr、Machine Mode、interrupt 和 RV32M；
- v0.1 测试只使用自然对齐访问；
- 当前无 Cache、MMU、Linux、多核和一致性；
- 未运行完整 ACT4、参考模型差分、VCS、DC、Formality 和 PrimeTime；
- testbench 中的小程序采用手工编码，`tests/asm/` 尚未形成软件工具链流程。

## 下一阶段

处理器核后续目标是：

```text
完整 RV32I 与精确同步异常
    → Zicsr + machine-mode-only 执行环境
    → 迭代式 RV32M
    → 精确 Machine interrupt
    → ACT4 + 参考模型差分
    → VCS / SpyGlass / DC / Formality / PrimeTime 闭环
```

详细理由和验收边界见 [RISC-V 处理器能力层级、指令扩展与 ACT4 报告](docs/verification/riscv_processor_isa_levels_and_act4_report.md)。

## 主要文档

- [处理器总体架构规格](docs/00_processor_architecture.md)
- [核心系统上下文](docs/01_core_system_context.md)
- [流水线契约](docs/02_pipeline_contract.md)
- [模块架构](docs/03_module_architecture.md)
- [验证与 ASIC 计划](docs/04_verification_and_asic_plan.md)
- [v0.1 core 验证报告](docs/verification/rv32_core_verification_report.md)
- [v0.1 冻结记录](docs/verification/v0.1_freeze_record.md)
- [SpyGlass baseline](docs/asic/spyglass_lint_rtl_baseline.md)

## 开源许可

本项目采用 [Apache License 2.0](LICENSE) 开源。你可以在遵守许可证条款的
前提下使用、修改和分发本项目的 RTL、验证代码、脚本与文档。

Copyright 2026 Sun-Yingjie
