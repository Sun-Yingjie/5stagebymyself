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
- load/CSR late-result bubble、迭代式 RV32M EX wait、EX redirect、存储反压与在途事务复位；
- MEM 统一提交精确同步 trap、MRET 和 Machine interrupt，并提供独立 retire/trap 观察接口；
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
| RV32M | `MUL MULH MULHSU MULHU DIV DIVU REM REMU` |
| 顺序与环境 | `FENCE`、`WFI` hint 正常退休；`ECALL EBREAK` 产生同步 trap；`MRET` 返回 `mepc` |
| Zicsr | `CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI` |

当前实现范围为 **RV32IM + Zicsr**。同步异常覆盖 cause `0/1/2/3/4/5/6/7/11`；Machine software/timer/external interrupt 使用 cause `0x80000003/0x80000007/0x8000000b`。此外实现了 `mcycle/mcycleh/minstret/minstreth`、`mie/mip`、Direct `mtvec` 以及 `mstatus.MIE/MPIE` 的 interrupt entry/MRET 语义。这仍是有限 Machine profile，不等于完整特权架构。

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

当前确定性 RTL 回归结果为：

```text
16/16 unit TBs passed
Icarus core:    51/51 scenarios, 364 retirements, 34 traps, 31 DMem requests,
                 27/25 MDU req/rsp, 17 interrupts, 25528 checks
Verilator core: 51/51 scenarios, 364 retirements, 34 traps, 31 DMem requests,
                 27/25 MDU req/rsp, 17 interrupts, 25528 checks
```

D5/V1 当前验证结果：

```text
D5 release: 64 seeds × 2 simulators = 128/128 PASS, aggregate coverage 0x03ff
D5 stress:  4 seeds × 2 simulators =   8/8 PASS, aggregate coverage 0x03ff
ACT4:       53/53 applicable tests PASS (I=39, M=8, Zicsr=6), 0 fail/skip
Spike diff: 18/18 architectural events and 4/4 memory events match, 0 traps
```

D5 的 Icarus/Verilator 同 seed 结果逐字段一致，并保留故意 timeout 的可重复失败工件。
ACT4 结果只对应冻结的 `RV32IM_Zicsr` 适用集合；Spike 差分当前是一条强制 trap-free
的确定性 smoke lane，二者都不等价于完整 RISC-V 认证。

D5 release 与默认 Spike smoke 可分别运行：

```bash
python3 scripts/run_random_regression.py \
  --sim both --seeds 1..64 --stall-pct 50 --max-stall 8
python3 scripts/run_differential.py --compile-timeout 180
```

ACT4 还需要固定 checkout、Sail 0.13 和隔离的 UDB 工具环境，完整参数见
[ACT4 冻结回归合同](docs/design/07_act4_validation.md)。

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
scripts/run_random_regression.py
                              D5 双模拟器随机回归与失败重放
scripts/run_act4.py           冻结 ACT4 profile 的生成、执行与报告
scripts/run_differential.py   同 ELF 的 DUT/Spike 事件差分
tb/program/                   ELF 程序执行 TB、linker 与 smoke 程序
verification/                 ACT4 profile、差分/runner 负测
.github/workflows/
└── rtl-regression.yml        GitHub Actions 回归
docs/
├── architecture.md          ISA、模块、状态与顶层接口
├── pipeline.md              流水推进、冒险、反压与 flush
├── csr_trap.md              CSR、counter、trap 与 Machine interrupt
├── verification.md          验证结构、结果、复现与缺口
└── design/                  已冻结的最终目标与后续增量设计合同
    ├── 00_final_target.md
    ├── 01_mret.md
    ├── 02_machine_counters.md
    ├── 03_rv32m_mdu.md
    ├── 04_machine_interrupt.md
    ├── 05_random_regression.md
    ├── 06_differential_validation.md
    └── 07_act4_validation.md
```

## 阅读顺序

1. [总体架构与接口](docs/architecture.md)
2. [五级流水契约](docs/pipeline.md)
3. [CSR、Trap 与 Machine Interrupt](docs/csr_trap.md)
4. [验证方法与结果](docs/verification.md)
5. [最终处理器设计目标](docs/design/00_final_target.md)

1～4 描述当前 RTL 已实现事实；`docs/design/01_mret.md`～`04_machine_interrupt.md`
是已经落入 RTL 的冻结设计合同，`05`～`07` 分别冻结并记录 D5、Spike 差分和 ACT4
验证。ASIC 前端仍是下一阶段工作。

## 已知限制与采用的路线

- 尚未实现 RV32A/F/C/V、`FENCE.I`、完整 privilege/PMP/debug、vectored `mtvec`、Cache、MMU、Linux、多核和一致性；
- 协处理器端口在 RTL 中保留，但当前固定关闭；
- D5 当前只随机化 IMem/DMem request-ready 与 response-start；随机 IRQ episode 不在
  本轮冻结范围；
- ACT4 只选择 I/M/Zicsr 53 项，不覆盖完整 Sm、Zicntr、interrupt、MRET/counter
  时序；
- Spike 差分当前只覆盖一个 trap-free smoke ELF，不是随机程序或完整 ISA 差分。

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

当前 RTL 已按冻结合同完成到 D4；D5 随机回归、冻结 ACT4 适用集和首条 Spike
差分 lane 也已完成并通过。下一阶段是 A1 ASIC lint、综合、约束与 STA。D5/V1
证据扩展了验证深度，但不替代 D0～D4 directed test，也不越界声称完整认证。

NPU、异构系统、AXI crossbar 和 DMA 仍在独立项目中维护。本处理器项目只在 A1 阶段接入 Core 自身的 ASIC 前端流程；当前不含已完成的工艺映射或 signoff 结果。

## 许可证

本项目采用 [Apache License 2.0](LICENSE)。
