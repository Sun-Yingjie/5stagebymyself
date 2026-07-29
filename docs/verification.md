# 验证方法与结果

当前验证体系覆盖 D0～D5 和 V1 首版：叶子模块 self-checking TB 锁定局部组合与
时序语义，真实 Core 流水回归用架构事件、协议不变量和 directed program 证明集成
行为；D5 增加双模拟器可重复随机 backpressure，V1 增加冻结 ACT4 适用集和同 ELF
Spike 差分。各层结论边界独立，不能互相替代。

## 1. 验证层次

### 1.1 Unit TB

Icarus 每次使用唯一 RTL filelist 加一个 unit testbench，当前固定运行 16 个：

```text
alu, branch_compare, csr_alu, csr_trap, csr_decoder, decoder,
exu, forward_unit, idu, ifu, imm_gen, lsu, mdu, pipeline_ctrl, regfile, wbu
```

Unit TB 检查：

- 全部 RV32I/Zicsr/RV32M 译码编码与非法负例，包括 MRET 精确编码和 WFI 合法 NOP hint；
- ALU、branch compare、立即数、CSR RMW、前递优先级与 late-result hazard；
- `mcycle/mcycleh/minstret/minstreth` 的自动更新、64 位进位、half write 和 commit 排除语义；
- MDU 八种运算、32 次固定迭代、除零/有符号溢出、response hold、reset/kill；
- WBU 四种写回来源、retire payload、reset/invalid 和 `x0` 写回观察语义；
- 流水控制优先级和各级 `LOAD/HOLD/CLEAR` 动作；
- IFU/LSU 单笔事务、对齐、访问错误和 LSU outstanding 状态；
- `mie/mip` WARL/MRO、三种 interrupt cause 与优先级、post-CSR/MRET effective-state preview、entry 和延后一拍的 interrupt 观察事件。

### 1.2 Core TB

Core 环境由五个源文件组成：

| 文件 | 职责 |
|---|---|
| `tb/core/rv32_tb_pkg.sv` | RV32I/Zicsr/RV32M 指令编码器与退休/DMem 期望类型 |
| `tb/core/rv32_imem_model.sv` | 单在途 IMem 模型、错误注入和程序装载 |
| `tb/core/rv32_dmem_model.sv` | 小端字节存储模型、`wstrb` 写入与错误响应 |
| `tb/core/rv32_backpressure_driver.sv` | D5 xorshift32、四路随机 gate 与有界公平性 |
| `tb/core/tb_rv32_core.sv` | directed/D5 场景、scoreboard、协议 monitor、超时与结果汇总 |

`tb/core/rv32_core_tb.f` 只列 TB 源；RTL 编译顺序唯一来自 `filelists/rv32_core_rtl.f`，其中 `rv32_mdu.sv` 位于 `rv32_core.sv` 之前。

每个场景执行相同流程：同步复位并清空模型与计数器，装载独立手工编码小程序，登记期望 retire/trap/DMem 事件，释放复位并逐周期在线比较，最后精确检查事件数、内存结果和超时。通用寄存器没有物理 reset，场景程序会先初始化自己读取的寄存器；架构 x0 由读端口和写保护检查，不依赖物理数组初值。

## 2. Scoreboard 与协议检查

### 2.1 架构事件

每个 `retire_valid` 周期按程序顺序比较：

- `retire_pc` 和 `retire_instr`；
- `retire_rd_we`；
- 写回有效时的 `retire_rd_addr` 与 `retire_rd_data`。

每个同步 trap 按顺序比较 `trap_pc/cause/value`，并检查故障指令没有同时普通退休。每次 DMem request 握手比较读写方向、原始字节地址、写数据和 `wstrb`；因此重复 store 或错误路径请求不能被“最终内存值碰巧正确”掩盖。

Machine interrupt 使用两个明确时序点：

1. 内部 `interrupt_take` 同拍完成 CSR entry、flush 和 redirect；
2. 单项 pending 状态在下一拍输出一次 `trap_valid`，但不得再次 redirect、flush 或更新 CSR。

post-commit interrupt 的延后 trap 事件与边界指令的 WB retire 同拍，monitor 必须先消费 retire，再消费 interrupt，证明事件顺序为“边界指令退休 → interrupt”。empty-pipeline interrupt 的延后事件没有配对 retire；reset 必须清除 pending 并抑制迟到事件。

### 2.2 Valid-ready 与多周期合同

逐周期检查包括：

- request 在 `valid && !ready` 时保持 `valid` 和 payload；
- response 在 `valid && !ready` 时保持 `valid`、data 和 error；
- IMem/DMem outstanding 只能是 0 或 1，没有 outstanding 时不得完成 response；
- MDU 请求只启动一次，busy 期间不重复接受请求，response 在消费前保持；
- MDU 等待时 IF/ID、ID/EX 保持，EX/MEM 清空，使更老 MEM/WB 能排空；
- MDU request/response 握手分别计数；被更老 trap/MRET/interrupt kill 的在途运算允许没有 response handshake，但不得形成写回；
- reset 期间不得请求、接收响应、retire、trap 或产生迟到的 MDU/interrupt 事件；
- 有效输出不得包含无法解释的 X/Z。

### 2.3 流水、提交与副作用

- 上一拍 `PIPE_HOLD` 后，对应流水寄存器全部字段不变；
- 上一拍 `PIPE_CLEAR` 后，对应 `valid=0`；
- 全局动作优先级检查同步 trap、post-commit interrupt、empty-pipeline interrupt、MRET、MEM wait、EX request/多周期 wait、EX redirect、late-result hazard 和 fetch unavailable；
- `mem_commit_candidate` 作为动作无关的仲裁输入，`commit_valid` 只在 MEM/WB 真正 `PIPE_LOAD` 时成立；post-commit interrupt 必须与一次 `commit_valid` 同拍，不能形成组合反馈；
- MRET 正常退休一次，WFI 作为无副作用 hint 正常退休；faulting 或被 flush 的指令不增加 `minstret`；
- MDU 捕获 EX forwarding 后的操作数，结果可被 EX/MEM forwarding 消费；
- 同步异常、MRET 或 interrupt 必须阻断年轻 DMem request、kill 年轻 MDU，并压过年轻 branch/jump redirect；
- trap-vector/interrupt handler 请求与首条指令不得重复；协处理器关闭时所有请求信号保持静默。

## 3. 当前回归结果

### 3.1 已冻结的 D3 稳定基线

2026-07-26 在 D1～D3 已闭环、D4 IRQ 输入保持低的设计上复现：

| 回归 | 结果 |
|---|---|
| Icarus unit | 15/15 TB 通过 |
| Icarus core | 31/31 场景通过 |
| Verilator core | 31/31 场景通过 |
| 架构事件 | 225 retirements，17 traps，27 DMem requests |
| MDU 握手 | 26 requests / 25 response handshakes；缺少的一笔由较老 trap 按设计 kill |
| 自动检查 | 17462 checks |

D3 的 31 个 Core 场景由 D0 的 20 个同步异常/流水/协议场景，加上下列 D1～D3 场景组成：

```text
mret_wfi_return
mret_beats_young_redirect
machine_counters
counter_fault_exclusion
rv32m_multiply_variants
rv32m_divide_variants
rv32m_forwarding_consumers
rv32m_load_wait_rsp_hold
rv32m_store_wait_rsp_hold
rv32m_trap_kills_response
rv32m_mret_kills_request
```

### 3.2 D4 最终定向回归

已通过的 D4 独立门禁包括：

- CSR/trap unit：433 checks，覆盖 `mie/mip`、mask/cause/priority、post-state preview、entry、empty boundary、MRET 立即重评价、同步异常优先级和 reset-pending；
- D4 IRQ 为低时的 no-regression gate：Icarus 15/15 unit，Core 保持 D3 的 31/31 与 17462 checks；
- Verilator Core lint/elaboration：未发现由 interrupt preview/commit 路径引入的组合环。

D4 新增 20 个 Core directed 场景，覆盖以下类别：

- 全局/局部 mask、MSI/MTI/MEI cause 及 `MEI > MSI > MTI`；
- 顺序 ALU、taken/not-taken branch、JAL/JALR 和 MRET 的 resume PC；
- load/store response wait、已提交 store 不重放和年轻 store 不越界；
- 同步 exception 高于 pending interrupt；
- 写 `mie/mstatus/mtvec` 后的 post-commit preview，以及 MRET 后立即重入；
- interrupt 与年轻 branch/MDU、MDU busy/response、DMem wait 的竞争；
- empty-pipeline boundary、IFU pending、`minstret` 边界计数、held IRQ 和 reset；
- post-commit retire 与延后 interrupt trap 的同拍顺序，以及延后事件不重复 entry/redirect。

20 个场景为：

```text
irq_priority_external
irq_priority_software
irq_timer_cause
irq_global_mask
irq_local_mask
irq_resume_taken_branch
irq_resume_not_taken_branch
irq_resume_jal
irq_resume_jalr
irq_alu_mret_counter_order
irq_preview_mie
irq_preview_mstatus
irq_preview_mtvec
irq_mret_immediate_reentry
irq_sync_fault_priority
irq_load_wait_kills_store
irq_store_wait_kills_branch
irq_load_wait_kills_mdu_rsp
irq_empty_with_ifu_pending
irq_reset_clears_pending
```

最终 D0～D4 汇总：

| 回归 | 结果 |
|---|---|
| Icarus unit | 15/15 TB 通过 |
| Icarus core | 51/51 场景通过 |
| Verilator core | 51/51 场景通过 |
| 架构事件 | 364 retirements，34 traps，31 DMem requests |
| MDU 握手 | 27 requests / 25 response handshakes；两笔分别由较老 trap 和 interrupt kill |
| Machine interrupt | 17 take decisions；其中 reset 场景按设计抑制 1 个尚未采样的延后观察事件 |
| 自动检查 | 25528 checks |
| Core lint | Verilator lint/elaboration 通过，无 `UNOPTFLAT` |

## 4. Trap Cause 矩阵

### 4.1 同步异常

| Cause | Core 场景 | 关键证据 |
|---:|---|---|
| 0 | `control_address_misaligned` | not-taken branch 不误报；错位 JALR trap；年轻 store 被清除 |
| 1 | `instruction_access_fault` | 指令字伴随 IMem error；poisoned store 不发 DMem 请求 |
| 2 | `precise_illegal_trap`、CSR illegal 场景 | `mtval` 为指令字；老 WB 可退休；故障与年轻指令无副作用 |
| 3 | `breakpoint_trap` | `EBREAK` 产生 cause 3、value 0，不误报 illegal |
| 4 | `load_address_misaligned` | 地址 2 的 `LW` 不发请求、不写 `rd` |
| 5 | `dmem_fault_trap_wait` | 等 error response 完成后才 trap，事务最终排空 |
| 6 | `store_address_misaligned` | 地址 2 的 `SW` 不发请求、不修改内存 |
| 7 | `store_access_fault` | 越界 store 只请求一次；error 阻止年轻 store；内存不变 |
| 11 | `trap_redirect_backpressure` | `ECALL` 目标请求在 backpressure 下稳定并只握手一次 |

### 4.2 Machine interrupt

| `mcause` | 输入/来源 | 关键证据 |
|---:|---|---|
| `0x80000003` | `irq_software` / `mip.MSIP` | MSIE 与全局 MIE 共同控制 eligibility |
| `0x80000007` | `irq_timer` / `mip.MTIP` | MTIE mask、cause 和 post-commit entry |
| `0x8000000b` | `irq_external` / `mip.MEIP` | MEIE mask；多源同时 pending 时优先 |

叶子 TB 负责覆盖每种检测、状态更新和仲裁条件，Core TB 负责证明元数据经过真实流水后只在精确边界生效。二者不能互相替代。

## 5. 复现方式

完整 Icarus unit、Icarus core 与 Verilator core 回归：

```bash
scripts/run_regression.sh
```

只运行 Icarus：

```bash
scripts/run_regression.sh --icarus-only
```

保留日志到指定目录：

```bash
BUILD_ROOT=/tmp/rv32-build scripts/run_regression.sh
```

独立对面向综合的 Core 顶层做 Verilator lint/elaboration 检查：

```bash
verilator --lint-only --timing -Wall \
  -Wno-TIMESCALEMOD -Wno-DECLFILENAME \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  -Wno-UNSIGNED -Wno-BLKSEQ \
  --top-module rv32_core -f filelists/rv32_core_rtl.f
```

当前 Core 摘要由 `tb/core/tb_rv32_core.sv` 输出：

```text
[PASS] rv32_core: 51/51 scenarios, 364 retirements, 34 traps,
31 DMem requests, 27/25 MDU req/rsp, 17 interrupts, 25528 checks
```

以上摘要已由 Icarus 和 Verilator 独立运行并得到一致结果。

## 6. D5 随机回归结果

D5 固定架构程序每次严格比较 17 次 retirement、1 次同步 trap、4 次 DMem request
和 2/2 次 MDU request/response；seed 只改变 IMem/DMem request-ready 和
response-start 时序。到达最后一个期望事件后，TB 继续运行 `MAX_STALL+8` 拍，要求
LSU、DMem、MDU 和 held-EX 静默，只允许 trap handler 后的无副作用 NOP 退休。

2026-07-27 的最终 campaign：

| Campaign | 配置 | 结果 | 关键证据 |
|---|---|---:|---|
| release | seed `1..64`，stall 50%，cap 8，Icarus + Verilator | 128/128 PASS | 两侧各 9,963 cycles、1,088 retire、64 traps、256 DMem、128/128 MDU；coverage `03ff` |
| high-wait | seed `1,17,20260727,a5a55a5a`，stall 85%，cap 32，双模拟器 | 8/8 PASS | 每侧 cycle 为 382/447/327/362；coverage `03ff` |
| timeout replay | seed 1，timeout 1，Icarus | 预期 FAIL 并可复现 | 原始与 replay 均为 cycle 17、state `e026d14a`、coverage `0001` |

release `run_id=7471b1bbb92d45889682db33335ce97a`，high-wait
`run_id=52cda6bdc5844bc7839f0a1b3ca73d59`。两批生成工件保存在被 Git 忽略的
`out/d5/`，均满足 `result_integrity_errors=[]`、`cross_sim_mismatches=[]`、零
max-streak 越界。runner 将 requested/reported seed、完整
结果 schema、重复/缺失 simulator-seed key 和固定架构计数作为硬门禁；相关负测位于
`verification/random/test_runner_integrity.py`。完整合同见
[D5 随机回归](design/05_random_regression.md)。

## 7. V1 架构验证结果

### 7.1 ACT4

ACT4 固定到 commit `072ed2e3d205ac9964a93c23759a9cc1a949b784` 和 Sail RISC-V
0.13。冻结集合为 RV32I 39 项、RV32M 8 项、Zicsr 6 项；最终结果为：

```text
selected=53 generated=53 run=53 pass=53 fail=0 skip=0
```

53 个 ELF 的 PT_LOAD 均通过 256 KiB 窗口和 mailbox 边界检查。最大项 `I-jal-00`
占 203,808 bytes，距 `tohost` 仍有 58,320 bytes。该结果只证明冻结适用集，不包括
完整 Sm、Zicntr、interrupt、MRET/counter 时序或正式 RVCP 认证。详见
[ACT4 冻结回归](design/07_act4_validation.md)。最终 fresh-all 报告的
`run_id=2cfc500f3ec147c999a70684a0fdcbab`；大型 ELF/trace 工件保存在本机任务临时目录，
不纳入 Git。

### 7.2 Spike 差分

首条 trap-free `RV32IM_Zicsr` smoke ELF 在 DUT 与 Spike 上得到 18/18 个一致的架构
事件和 4/4 个一致的 memory event；DUT 76 cycles、0 traps、`tohost=1`，
`first_divergence=null`。comparator 负测篡改第 2 个寄存器写事件后，在 event index 1
稳定报告首个差异。

最终 delivery smoke 的 comparison、first-divergence 和 manifest 使用同一个
`run_id=e7d8e0892fc54f588fbd7c05b92c9172`；ELF/VVP/trace 工件保存在本机任务临时目录，
不纳入 Git。

Spike reset `mtvec=0`，而 DUT program TB 的 reset `mtvec=0x80000300`，因此当前 lane
明确拒绝任何 trap；MRET、同步 trap、interrupt、counter 值、WFI 睡眠和访问错误均不
在本次差分通过声明内。详见 [Spike 差分合同](design/06_differential_validation.md)。

## 8. 仍未关闭的验证边界

- D5 没有随机 IRQ episode、functional/code coverage 收敛或 formal；
- ACT4 53 项不是完整特权架构或正式认证证书；
- Spike 差分只有一个确定性 trap-free 程序，尚无随机程序生成、失败最小化或 trap
  共同初始化；
- 尚未开展 A1 ASIC lint、综合、时钟约束与 STA。

ACT4/差分验证架构语义，不能替代 directed TB 对 hazard、flush、backpressure、event
ordering 和副作用抑制的内部检查。
