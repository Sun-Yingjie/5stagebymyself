# RV32 五级流水 Core 定向仿真验证报告

## 1. 验证结论

- 验证日期：2026-07-17
- 冻结标识：`v0.1-rtl-baseline`
- RTL 基线：`b12d254`；后续冻结准备未修改处理器 RTL
- RTL/Test 回归基线：`a57e1b0`
- Icarus Verilog：13.0 stable
- Verilator：5.048
- Core 定向测试：7/7 场景通过
- 架构退休检查：98 条
- DMem 请求检查：18 笔
- 自动检查总数：1715 项
- 叶子模块回归：11/11 testbench 通过

本次验证证明当前 `rv32_core` 在固定一周期存储器响应和有限定向
backpressure 条件下，可以正确执行当前规划内的 RV32I 指令，处理两级前递、
load-use、控制重定向、不同宽度访存、错误路径副作用抑制和在途事务复位。

本次验证过程中发现并修复了一项真实的 core 集成缺陷：DMem 请求被反压时，
请求地址和写数据会随着前递源离开流水线而变化。修复后，同一套 Icarus 和
Verilator 测试均通过。

## 2. 验证环境

正式环境由以下文件组成：

| 文件 | 职责 |
|---|---|
| `tb/core/tb_rv32_core.sv` | 时钟复位、测试程序、scoreboard、协议检查和场景控制 |
| `tb/core/rv32_tb_pkg.sv` | 指令编码器和期望记录类型 |
| `tb/core/rv32_imem_model.sv` | 单在途指令存储器模型，可配置请求和响应使能 |
| `tb/core/rv32_dmem_model.sv` | 小端字节存储器模型，按 `wstrb` 产生一次写副作用 |
| `tb/core/rv32_core.f` | 固定编译顺序和完整源文件清单 |

每个场景都会执行以下步骤：

1. 拉高同步复位并清空 IMem、DMem；
2. 写入独立的手工编码 RV32I 小程序；
3. 建立完整的期望退休序列和 DMem 请求序列；
4. 释放复位并逐周期在线比较；
5. 达到期望退休数后检查请求数、事件数、存储器结果和超时；
6. 下一场景重新复位，避免结果依赖场景执行顺序。

寄存器堆没有复位，因此所有程序都会先初始化自己读取的架构寄存器。
测试不会通过读取 DUT 寄存器堆来判定架构结果。

## 3. Scoreboard 和断言

### 3.1 架构级退休检查

每个 `retire_valid` 周期按程序顺序比较：

- `retire_pc`；
- `retire_instr`；
- `retire_rd_we`；
- 写回有效时的 `retire_rd_addr` 和 `retire_rd_data`。

store、branch 和写 `x0` 指令仍必须正常退休，但预期 `retire_rd_we=0`。
当 `rd_we=0` 时不比较无架构意义的 `rd_addr/rd_data`。

### 3.2 DMem 副作用检查

每次 `dmem_req_valid && dmem_req_ready` 都比较：

- 读写方向；
- 原始字节地址；
- 已完成 byte-lane 移位的写数据；
- `wstrb`。

因此 store 不能通过“最终内存碰巧正确”掩盖重复请求，错误路径 store 也不能
产生任何握手。测试结束时还会检查关键 DMem 字的最终值。

### 3.3 协议检查

- `req_valid && !req_ready` 时，请求 valid、地址、数据和 strobe 保持；
- `rsp_valid && !rsp_ready` 时，响应 valid、数据和 error 保持；
- 每条通道的在途事务计数只能为 0 或 1；
- 没有在途请求时不得完成响应；
- reset 期间不得请求、接收响应或退休；
- 输出有效时，请求和退休字段不得包含无法解释的 X/Z。

### 3.4 流水控制检查

- 上一拍为 `PIPE_HOLD` 时，对应流水寄存器完整保持；
- 上一拍为 `PIPE_CLEAR` 时，对应流水寄存器 valid 清零；
- load-use、EX request wait、MEM response wait 和 redirect 必须选择规定动作；
- `qualified_redirect.valid` 必须等于
  `redirect_commit && raw_redirect.valid`；
- 禁用协处理器时，全部请求输出和 `cp_rsp_ready` 恒为零。

## 4. 场景与结果

| 场景 | 周期 | 退休 | DMem | 检查 | 关键事件 |
|---|---:|---:|---:|---:|---|
| `integer_and_forwarding` | 37 | 32 | 0 | 386 | 无停顿 |
| `load_store_and_hazards` | 27 | 19 | 13 | 344 | 3 次 load-use |
| `control_flow_and_flush` | 57 | 34 | 0 | 502 | 9 次 redirect |
| `protocol_backpressure` | 23 | 6 | 2 | 205 | 3 EX wait、3 MEM wait、3 IMem request stall |
| `mem_wait_blocks_redirect` | 15 | 5 | 1 | 140 | 3 MEM wait、1 次延后 redirect |
| `reset_during_imem` | 7 | 1 | 0 | 55 | 清除在途取指 |
| `reset_during_dmem` | 10 | 1 | 2 | 83 | 复位前后各一笔 load 请求，只退休一次 |
| **合计** | **176** | **98** | **18** | **1715** | **7/7 PASS** |

### 4.1 整数指令与前递

覆盖全部当前实现的 R 型和 I 型 ALU 指令，以及 `LUI/AUIPC`：

- `ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND`；
- `ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI`；
- 零、负数、`-1`、最高位和 31 位移位；
- EX/MEM 和 MEM/WB 前递；
- 同一 `rd` 连续生产者的最新结果优先；
- WB 写回与 ID 读取同拍旁路；
- 写 `x0` 不产生真实写回，也不能成为前递源。

### 4.2 Load/store 与数据冒险

覆盖：

- `LB/LBU/LH/LHU/LW` 的符号和零扩展；
- `SB/SH/SW` 的地址低位、写数据移位和 `wstrb`；
- ALU 结果前递给 store data；
- load 结果经过一个 bubble 前递给 ALU 和 store data；
- 连续 store/load 的请求顺序和最终小端字节合并结果；
- load-use 事件恰好出现 3 次，没有重复插入 bubble。

### 4.3 控制冒险

覆盖六类 branch 的 taken 和 not-taken：

- `BEQ/BNE/BLT/BGE/BLTU/BGEU`；
- `JAL` 的目标和 `PC+4` 链接值；
- `JALR` 使用 EX/MEM 前递的基址并清除目标 bit 0；
- ALU 结果前递到 branch 比较器；
- taken 路径上的 register write 和 store 均被冲刷；
- 总计 9 次有效 redirect，每次只提交一次。

### 4.4 有限 backpressure

协议场景分别制造：

- 3 周期 IMem 请求等待；
- 2 周期初始 IMem 响应延迟；
- 3 周期 DMem 请求等待；
- 3 周期 DMem 响应等待。

store 请求在反压期间保持同一地址、数据和 strobe，只握手一次；store 响应完成
后，后续 load 正常发出并产生一个 load-use bubble。

### 4.5 MEM wait 与年轻 redirect

程序使用以下相关序列：

```text
写 x1=0
写 x1=1
延迟响应的 load
BNE x1, x0, target
错误路径 store
target
```

branch 在 EX 时依赖 MEM/WB 前递得到 `x1=1`。较老 load 等待响应期间：

- raw redirect 连续存在；
- MEM wait 始终优先，`redirect_commit=0`；
- 等待解除后 redirect 只提交一次；
- 错误路径 store 没有产生 DMem 请求。

该场景同时验证 EX HOLD 快照不仅稳定 DMem 请求，也稳定等待期间的 branch
比较结果和 redirect 目标。

### 4.6 在途事务复位

- IMem 场景在请求已接受、响应尚未出现时复位，旧响应不能污染复位后流水；
- DMem 场景在 load 请求已接受、响应尚未出现时复位，复位后重新执行；
- DMem 总共观察到复位前后两笔请求，但只有复位后的 load 退休一次。

## 5. 验证发现及 RTL 修复

### 5.1 首次失败

初版 `protocol_backpressure` 在 DMem request wait 中失败。首拍 store 请求为：

```text
addr  = 0x00000100
wdata = 0x00000055
wstrb = 1111
```

后续等待周期错误地变化为旧寄存器值：

```text
addr  = 0xffffffff
wdata = 0x00000001
```

这违反了 valid/ready 协议，也导致越界 store 返回 error，随后 load 和 store
无法正常完成。

### 5.2 根因

`PIPE_HOLD` 正确保持了 ID/EX，但 ID/EX 保存的是译码时读取的寄存器旧值。
store 第一次进入 EX 时，正确地址和数据来自 EX/MEM 与 MEM/WB 前递。等待期间
这些生产者继续退休并离开前递网络，EXU 随后回退到 ID/EX 中的旧值，因此
组合生成的 `ex_mem_candidate` 和 DMem 请求字段发生变化。

### 5.3 修复

`rv32_core` 在 ID/EX 第一次进入 HOLD 时保存：

- 已完成前递后的 `exec_result`；
- 已完成前递后的 `store_data`；
- 当时的 raw redirect valid 和 target。

HOLD 期间和解除 HOLD 的推进周期使用该快照。正式的 ID/EX 流水寄存器仍完整
保持，因此没有改变 `PIPE_HOLD` 契约。

快照只保存会随前递源消失而变化的 97 位数据，加 1 位 valid，共 98 位状态；
没有保存整个 `ex_mem_t`，减少了不必要的 ASIC 触发器开销。

## 6. 工具结果

### 6.1 Icarus

```bash
iverilog -g2012 -s tb_rv32_core \
  -o /tmp/tb_rv32_core.vvp \
  -f tb/core/rv32_core.f
vvp /tmp/tb_rv32_core.vvp
```

结果：7/7 场景通过。Icarus 输出的
`constant selects in always_* processes are not currently supported` 表示其敏感列表
实现会保守包含所有位，不影响本次功能结果。

Scoreboard 使用并行标量数组，而不是动态索引的 packed struct 数组，以避免
不同 Icarus 版本对动态索引 packed struct 数组的 elaboration 差异。

### 6.2 Verilator

```bash
verilator --binary --timing -Wall \
  -Wno-TIMESCALEMOD -Wno-DECLFILENAME \
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  -Wno-UNSIGNED -Wno-BLKSEQ \
  --Mdir /tmp/rv32-v01-verilator \
  --top-module tb_rv32_core \
  -f tb/core/rv32_core.f
/tmp/rv32-v01-verilator/Vtb_rv32_core
```

结果：编译成功，7/7 场景和 1715 项检查通过。

这些 waiver 仅用于当前仿真 testbench 构建：

- `BLKSEQ`：scoreboard 在时钟监视器中有意使用阻塞赋值立即更新计数；
- `UNUSEDSIGNAL/UNUSEDPARAM`：包含预留协处理器端口和 packed bundle 未消费字段；
- `UNSIGNED`：`BASE_ADDR=0` 时 IMem 范围比较被常量化；
- `TIMESCALEMOD`：可综合 RTL 不声明仿真 timescale。

它们不是 SpyGlass 或 ASIC signoff waiver。

### 6.3 叶子模块回归

Icarus 下重新编译并执行以下 11 个 testbench，全部通过：

```text
alu, branch_compare, decoder, exu, forward_unit, idu,
ifu, imm_gen, lsu, pipeline_ctrl, regfile
```

冻结版本统一使用以下入口复现全部 11 个叶子 TB、Icarus core 和 Verilator core：

```bash
scripts/run_v0_1_regression.sh
```

LSU TB 中枚举类型的条件选择使用显式 `if/else`，避免 Icarus 13 对三目表达式
枚举结果要求显式 cast 的工具差异；该修改不涉及处理器 RTL。

### 6.4 SpyGlass baseline

SpyGlass L-2016.06 `lint/lint_rtl` 已完成：

- command/design read：0 error、0 warning；
- policy lint：0 error、76 warning；
- waived：0。

76 条 warning 已在 `docs/asic/spyglass_lint_rtl_baseline.md` 中按
W415a/W240/W528 分类。当前结果是可解释的静态检查 baseline，不宣称
lint-clean signoff。

## 7. 波形与调试入口

TB 支持按需生成 VCD，不默认向仓库写大文件：

```bash
vvp /tmp/tb_rv32_core.vvp +DUMP=/tmp/rv32_core.vcd
```

还可以使用 `+TRACE` 打印 backpressure 场景中的 ID/EX、EX/MEM、MEM/WB、
前递选择、寄存器值、DMem 请求和流水动作，便于复盘本次缺陷。

建议重点观察两段波形：

1. `protocol_backpressure`：DMem request stall 时地址、数据和 strobe 保持；
2. `mem_wait_blocks_redirect`：MEM wait 期间 raw redirect 存在但 commit 为零，
   响应完成后只提交一次。

## 8. 尚未完成的 P0 门禁

本报告只代表 core directed simulation 通过，不代表完整 P0 已验收。仍需完成：

- 与当前 RV32I 子集匹配的 RISC-V 官方架构测试；
- 锁定版本参考模型或 ISS 的退休流差分；
- VCS 正式回归，本机当前 PATH 中没有 VCS；
- DC、Formality 和 PT 流程；
- SpyGlass warning 的后续收敛和对象级 waiver；
- 当前规划推迟的 trap/CSR、访问异常闭环和非对齐访问；
- v0.2 的长延迟、广泛随机 backpressure 和随机程序验证。

当前结果可以作为进入 core 波形复盘、官方架构测试接入和 ASIC 前端检查前的
稳定功能基线。
