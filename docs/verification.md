# 验证方法与结果

当前验证体系分为叶子模块 self-checking TB 和真实 Core 流水回归。前者定位组合/局部时序语义，后者用架构事件与协议不变量证明模块集成后的行为。两层都由统一脚本执行。

## 1. 验证层次

### 1.1 Unit TB

Icarus 每次使用唯一 RTL filelist 加一个 unit testbench，当前固定运行 14 个：

```text
alu, branch_compare, csr_alu, csr_trap, csr_decoder, decoder,
exu, forward_unit, idu, ifu, imm_gen, lsu, pipeline_ctrl, regfile
```

Unit TB 适合检查：

- 全部译码编码与非法负例；
- ALU、branch compare、立即数和 CSR RMW 真值；
- 前递优先级与 late-result hazard；
- 流水控制优先级和每一级动作；
- IFU/LSU 单笔事务状态、对齐与访问错误；
- CSR reset、WARL/MRO、读写抑制和 trap 更新。

### 1.2 Core TB

Core 环境由四个源文件组成：

| 文件 | 职责 |
|---|---|
| `tb/core/rv32_tb_pkg.sv` | 指令编码器与退休/DMem 期望类型 |
| `tb/core/rv32_imem_model.sv` | 单在途 IMem 模型、错误注入和程序装载 |
| `tb/core/rv32_dmem_model.sv` | 小端字节存储模型、`wstrb` 写入与错误响应 |
| `tb/core/tb_rv32_core.sv` | 场景、scoreboard、协议检查、超时与结果汇总 |

`tb/core/rv32_core_tb.f` 只列 TB 源；RTL 编译顺序唯一来自 `filelists/rv32_core_rtl.f`。

每个场景执行相同流程：同步复位并清空模型与计数器，装载独立手工编码小程序，登记期望事件，释放复位并逐周期在线比较，最后精确检查事件数、内存结果和超时。由于通用寄存器没有复位，程序会先初始化自己读取的寄存器。

## 2. Scoreboard 与协议检查

### 2.1 架构事件

每个 `retire_valid` 周期按程序顺序比较：

- `retire_pc` 和 `retire_instr`；
- `retire_rd_we`；
- 写回有效时的 `retire_rd_addr` 与 `retire_rd_data`。

每个 trap 按顺序比较 `trap_pc/cause/value`，并检查故障指令没有同时普通退休。每次 DMem request 握手比较读写方向、原始字节地址、写数据和 `wstrb`；因此重复 store 或错误路径请求不能被“最终内存值碰巧正确”掩盖。

### 2.2 Valid-ready 合同

逐周期检查包括：

- request 在 `valid && !ready` 时保持 `valid` 和 payload；
- response 在 `valid && !ready` 时保持 `valid`、data 和 error；
- 每个通道 outstanding 只能是 0 或 1；
- 没有 outstanding 时不得完成 response；
- reset 期间不得请求、接收响应、retire 或 trap；
- 有效输出不得包含无法解释的 X/Z。

### 2.3 流水与副作用

- 上一拍 `PIPE_HOLD` 后，对应流水寄存器全部字段不变；
- 上一拍 `PIPE_CLEAR` 后，对应 `valid=0`；
- trap、MEM wait、EX request wait、redirect 和 late-result hazard 必须选择规定动作；
- 异常指令和年轻错误路径指令不得写寄存器或 DMem；
- trap-vector 请求与 handler 首条指令必须各出现一次；
- 协处理器关闭时所有请求信号保持静默。

## 3. 当前回归结果

2026-07-18 在 PR #5 合入基线上复现的结果为：

| 回归 | 结果 |
|---|---|
| Icarus unit | 14/14 TB 通过 |
| Icarus core | 20/20 场景通过 |
| Verilator core | 20/20 场景通过 |
| 架构事件 | 139 retirements，12 traps，21 DMem requests |
| 自动检查 | 3918 checks |

Core 的 20 个场景覆盖：

```text
integer_and_forwarding
load_store_and_hazards
control_flow_and_flush
protocol_backpressure
mem_wait_blocks_redirect
precise_illegal_trap
trap_beats_redirect
dmem_fault_trap_wait
trap_redirect_backpressure
instruction_access_fault
breakpoint_trap
control_address_misaligned
load_address_misaligned
store_address_misaligned
store_access_fault
zicsr_rmw_and_hazard
zicsr_mro_illegal
zicsr_unknown_illegal
reset_during_imem
reset_during_dmem
```

## 4. 同步异常 Cause 矩阵

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

叶子 TB 负责覆盖每种检测条件，Core TB 负责证明异常元数据经过真实流水后只在 MEM 精确提交。二者不能互相替代。

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

独立检查可综合 Core 顶层：

```bash
verilator --lint-only --sv -Wall -Wno-fatal \
  -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  --top-module rv32_core -f filelists/rv32_core_rtl.f
```

预期 Core 摘要：

```text
[PASS] rv32_core: 20/20 scenarios, 139 retirements, 12 traps, 21 DMem requests, 3918 checks
```

## 6. 尚未关闭的缺口

### 6.1 ACT4

当前没有 ACT4 runner、批量 ELF/HEX 执行或 signature 判定，不能宣称完整 RV32I 架构测试通过。下一步 runner 至少需要：

- 锁定 ACT4/测试环境版本与 DUT ISA profile；
- 把测试 ELF 转换并装载到当前 IMem/DMem 模型；
- 定义启动地址、结束条件、PASS/FAIL 和 timeout；
- 批量运行适用 RV32I/Zicsr 测试并保存机器可读摘要；
- 明确 unsupported 测试必须来自 profile，不允许临时跳过失败项。

ACT4 验证架构语义，不能替代 directed TB 对 hazard、flush、backpressure 和副作用抑制的内部检查。

### 6.2 Backpressure 与差分

已有 request/response stall、MEM wait 与 redirect、trap target stall、事务中途复位等确定性场景，但尚无随机 seed、任意等待长度或覆盖率收敛证据。当前也没有参考模型差分。

建议顺序是：先完成可重复的 ACT4 RV32I runner，再增加受 seed 控制的 IMem/DMem 随机 backpressure，最后接入基于 retire/trap 事件的差分验证。
