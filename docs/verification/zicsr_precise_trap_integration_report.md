# Zicsr 与精确同步 trap 集成验证报告

## 1. 结论

- 验证日期：2026-07-18；
- 验证对象：PR #4，功能 RTL 提交 `d08e6d7`，审阅增强测试提交 `74b1eec`；
- 本地工具：Icarus Verilog 13.0、Verilator 5.048；
- CI 工具：Icarus Verilog 12.0、Verilator 5.020；
- 叶子模块回归：14/14 testbench 通过；
- core 定向回归：14/14 场景通过；
- 架构事件：125 条普通退休、6 次同步 trap、20 笔 DMem 请求；
- 自动检查：3157 项；
- 可综合顶层 Verilator `-Wall` lint：通过；
- 审阅结论：未发现阻止合并的 RTL、验证或安全问题。

本报告只记录在 `v0.1-rtl-baseline` 上新增的精确同步 trap、Machine CSR 状态基础和
六条 Zicsr 指令的集成证据，不改写 v0.1 冻结记录。当前结果不代表完整 Machine
Mode、ACT4 认证或 ASIC signoff。

## 2. 工程范围说明

本地 Git 规则原本建议把同步 trap、Zicsr 和 Machine Mode 作为连续独立分支。
PR #4 在本次合并审阅前以 16 个可回溯的小提交依次完成了契约、语义叶子、被动流水字段、
late-result hazard、CSR/trap owner、精确 trap 集成和最终 Zicsr 激活。由于六条 CSR
指令的非法访问验收依赖已经闭环的 trap 提交路径，本次合并审阅明确把 PR #4 作为一次
集成例外接受，不再重写已通过双模拟器与 CI 验证的提交历史。

该例外不扩大后续范围：`MRET`、Machine counter、RV32M 和 Machine interrupt 仍必须
从最新 `main` 分别建立独立分支。

## 3. 被验证的设计边界

### 3.1 Zicsr 数据通路

- `rv32_csr_decoder` 只识别六种 Zicsr `funct3`，并按 `rd/rs1/uimm` 编码字段产生读写抑制；
- 主 decoder 保留对 `ECALL/EBREAK` 的完整指令匹配，MRET 和其他 SYSTEM 编码仍 illegal；
- 寄存器源在 EX 使用正常前递网络，立即数源直接零扩展 `instruction[19:15]`；
- CSR 旧值在 MEM 形成，通过 `WB_CSR` 进入 MEM/WB，并与 load 共用 late-result hazard；
- 连续 CSR 指令按流水顺序读取前一条已经提交的新状态。

### 3.2 CSR 与 trap 状态

- `rv32_csr_trap` 是 CSR 和 trap 状态的唯一所有者；
- 地址存在性、MRO 与 WARL 行为符合 `docs/06_machine_csr_contract.md`；
- 显式状态更新优先级为 `reset > trap > CSR write`；
- MEM 最终异常优先级为早期异常、CSR illegal、LSU access fault；
- trap 更新 `mepc/mcause/mtval/mstatus`，并用当前 `mtvec` Direct base 重定向；
- 同周期更老 WB 指令允许退休，异常指令及其年轻指令不得产生普通副作用。

### 3.3 LSU 副作用资格

最终 MEM 异常通过 LSU 内部 `ex_request_block` 阻止年轻 EX load/store。测试不仅检查
最终存储器未变化，还在 DMem ready 的竞争周期直接确认：

```text
dmem_req_valid = 0
request_fire = 0
outstanding = 0
```

因此没有依靠 trap 后的流水冲刷掩盖已经发生的年轻 store 请求。

## 4. Core 场景结果

| 场景 | 退休 | Trap | DMem | 检查 | 主要覆盖 |
|---|---:|---:|---:|---:|---|
| `integer_and_forwarding` | 33 | 0 | 0 | 472 | 整数语义与两级前递 |
| `load_store_and_hazards` | 19 | 0 | 13 | 399 | load/store、3 次 load late-result |
| `control_flow_and_flush` | 34 | 0 | 0 | 626 | branch/JAL/JALR 与错误路径冲刷 |
| `protocol_backpressure` | 6 | 0 | 2 | 264 | IMem/DMem request/response 等待 |
| `mem_wait_blocks_redirect` | 5 | 0 | 1 | 176 | 老 MEM wait 压制年轻 redirect |
| `precise_illegal_trap` | 2 | 1 | 1 | 154 | 老退休、MEM trap、年轻 store 同拍竞争 |
| `trap_beats_redirect` | 2 | 1 | 0 | 116 | trap 高于年轻 branch redirect |
| `dmem_fault_trap_wait` | 2 | 1 | 1 | 160 | access fault 等真实响应后提交 |
| `trap_redirect_backpressure` | 1 | 1 | 0 | 128 | trap target 请求稳定保持 |
| `zicsr_rmw_and_hazard` | 11 | 0 | 0 | 198 | 六指令、旧值、连续访问、CSR-use bubble |
| `zicsr_mro_illegal` | 6 | 1 | 0 | 171 | MRO 抑制写合法、真实写 illegal |
| `zicsr_unknown_illegal` | 2 | 1 | 0 | 119 | 不存在地址即使抑制写仍 illegal |
| `reset_during_imem` | 1 | 0 | 0 | 70 | 复位清除取指在途状态 |
| `reset_during_dmem` | 1 | 0 | 2 | 104 | 复位清除数据在途状态 |
| **合计** | **125** | **6** | **20** | **3157** | **14/14 PASS** |

Icarus 与 Verilator 对每个场景得到相同计数。

## 5. 分层验证

14 个单元 testbench 覆盖：ALU、branch compare、CSR ALU、CSR/trap owner、CSR decoder、
主 decoder、EXU、forward unit、IDU、IFU、immediate generator、LSU、pipeline control 和
regfile。与本 PR 直接相关的重点包括：

- CSR WRITE/SET/CLEAR 的候选值；
- 六指令寄存器/立即数形式和读写抑制端点；
- 所有冻结 CSR 的 reset、读值、WARL/MRO、非法访问和 trap 优先级；状态型 task 自行 reset/seed，不依赖执行顺序；
- CSR source 前递、异常时 CSR 控制清除；
- late-result 检测及较新 EX/MEM late producer 对旧 MEM/WB 值的遮蔽；
- `ex_request_block` 同时阻断外部 valid、内部 fire 和 outstanding 状态更新。

完整单元套件由 Icarus 执行；合并审阅中修改的 `tb_rv32_csr_trap` 和
`tb_rv32_forward_unit` 还分别用 Verilator 5.048 独立编译运行并通过。

## 6. 复现命令

完整 Icarus 与 Verilator 回归：

```bash
scripts/run_v0_1_regression.sh
```

可综合顶层 lint：

```bash
verilator --lint-only --sv -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  --top-module rv32_core -f filelists/rv32_core_rtl.f
```

GitHub Actions 使用同一回归脚本，并在 Icarus 12.0 与 Verilator 5.020 上得到同样的
14/14 core 场景和 3157 项检查结果。

## 7. 已知边界与后续工作

- 同步异常 cause 的 core 级端到端矩阵尚未全部补齐；
- 当前固定在 M-mode，不实现低特权级访问检查；
- 未实现 `MRET`、Machine counter、interrupt、PMP、Debug、Zicntr/Zihpm 或 RV32M；
- 未运行 ACT4、参考模型差分、VCS、DC、Formality 或 PrimeTime；
- LSU 暂时保留旧兼容 MEM/WB/exception 输出，后续应以独立 refactor 清理；
- `rv32_csr_trap.mem_instruction` 当前为未使用的预留输入，可在后续 Machine Mode 增量中确认或删除。
