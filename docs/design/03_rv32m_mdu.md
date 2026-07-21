# RV32M 迭代式 MDU 设计合同

## 1. 目标与边界

本增量完整实现八条 RV32M 指令：

```text
MUL MULH MULHSU MULHU DIV DIVU REM REMU
```

使用单发射、单在途、固定迭代次数的阻塞式 MDU。MDU 位于 EX，结果继续经过
EX/MEM、MEM/WB 和现有 `WB_EXEC` 路径写回。

本增量不实现 Zmmul-only 子集、pipelined multiplier、多请求队列、乘除并行、
early-out、指令融合、clock gating 或全流水 valid-ready 重构。

完整八条指令通过验收前不得设置 `misa.M`。完成后 `misa` 固定从
`0x40000100` 更新为 `0x40001100`。

## 2. 指令译码

八条指令均使用 `OPCODE_OP`、`funct7=7'b0000001`，由 `funct3` 区分。新增
`mdu_operation_e` 和最小 `mdu_ctrl_t`，从 decoder 携带到 ID/EX。

M 指令：

- `uses_rs1=1`、`uses_rs2=1`；
- `rd` 按普通 R 型指令解释；
- `wb_ctrl.register_write=1`；
- `wb_ctrl.writeback_select=WB_EXEC`；
- 不形成 DMem、CSR、branch/jump 或 exception 控制。

任何保留的 funct 组合继续产生 illegal-instruction exception。

## 3. 模块接口

新增独立 `rv32_mdu`，建议接口：

```text
clk, rst

req_valid
req_ready
req_operation
req_operand_a
req_operand_b

rsp_valid
rsp_ready
rsp_result

kill
```

协议：

1. 只在 `req_valid && req_ready` 的时钟沿锁存 operation 和经过 forwarding 的两个
   操作数；
2. 非 IDLE 状态 `req_ready=0`，同一条被 HOLD 的 ID/EX 指令不得重复启动；
3. 完成后 `rsp_valid=1`；
4. `rsp_valid && !rsp_ready` 时结果必须保持；
5. 只在 `rsp_valid && rsp_ready` 时把该 M 指令送入 EX/MEM；
6. `kill` 取消所有在途状态，不产生 response；
7. 同步优先级固定为 `reset > kill > normal state transition`。

MDU 不产生同步异常。整数除零和有符号溢出按 ISA 返回普通结果。

流水集成必须使用以下分层信号，不能把 available 和 fire 混为一谈：

```text
m_ex_valid =
    id_ex_q.valid &&
    id_ex_q.mdu_ctrl.valid &&
    !id_ex_q.exception.valid

req_valid = m_ex_valid && mdu_is_idle && !global_kill
req_fire  = req_valid && req_ready

response_available = m_ex_valid && rsp_valid

rsp_ready =
    m_ex_valid &&
    (ex_mem_action == PIPE_LOAD) &&
    !global_kill

rsp_fire = rsp_valid && rsp_ready
```

`response_available` 必须由 `rsp_valid` 表示，不能用 `rsp_fire` 代替，否则 pipeline
可能一直等待一次只有在 pipeline 接受后才成立的 fire，形成控制死锁。

M 指令的 EX/MEM candidate 只有在 `response_available=1` 时才允许 `valid=1`，payload
来自 MDU response register；最终只在 `rsp_fire=1` 的时钟沿被流水接受。reset、较老
trap、MRET 或 interrupt 令 `global_kill=1` 时，`req_valid=0`、`rsp_ready=0`。

## 4. 状态机

首版固定状态：

```text
IDLE → RUN (32 iterations) → FINALIZE → RESPONSE → IDLE
```

### IDLE

- `req_ready=1`；
- 请求握手时保存 operation、操作数符号、幅值和特殊情况标志；
- 初始化 accumulator、multiplicand/multiplier 或 quotient/remainder；
- 清零 iteration counter，进入 RUN。

### RUN

- 每个时钟沿完成一次 radix-2 迭代；
- iteration counter 明确计数 32 次，不依赖操作数 early-out；
- 乘法路径维护 64 位 partial product；
- 除法路径维护 33 位 remainder 和 32 位 quotient；
- 第 32 次迭代完成后进入 FINALIZE。

### FINALIZE

- 按 operation 完成有符号修正；
- 处理除零与 `INT_MIN / -1`；
- 从 64 位 product、quotient 或 remainder 选择 32 位结果；
- 把最终结果锁存后进入 RESPONSE。

### RESPONSE

- `rsp_valid=1`；
- 结果保持到 `rsp_ready=1`；
- 握手后回到 IDLE。

第一版不强制乘除共享同一加法器。先保证数据通路清楚、可验证，资源共享和 PPA
优化留到 ASIC 报告提供证据之后。

### 4.1 乘法逐拍 recurrence

请求握手时初始化：

```text
mul_acc_q          = 64'b0
mul_multiplicand_q = {32'b0, operand_a_magnitude}
mul_multiplier_q   = operand_b_magnitude
iteration_q        = 0
```

RUN 每拍组合形成：

```text
mul_acc_next =
    mul_acc_q + (mul_multiplier_q[0] ? mul_multiplicand_q : 64'b0)

mul_multiplicand_next = mul_multiplicand_q << 1
mul_multiplier_next   = mul_multiplier_q >> 1
```

当 `iteration_q==31` 时，必须把 `mul_acc_next` 而不是旧的 `mul_acc_q` 保存为最终
幅值，并进入 FINALIZE；否则保存三个 next value，`iteration_q++` 后继续 RUN。

signed 解释：

- `MUL` 可按 unsigned 迭代，低 32 位与 signed 乘法相同；
- `MULH` 的两个操作数均取 signed 幅值；
- `MULHSU` 只对 operand A 取 signed 幅值；
- `MULHU` 两个操作数均按 unsigned；
- FINALIZE 对完整 64 位幅值做二补数符号修正，再选择高/低 32 位。

### 4.2 除法逐拍 recurrence

除零与 signed overflow 在请求握手时记录 special flag，但仍走固定 32 次 RUN，保证
首版延迟不依赖数据。普通除法初始化：

```text
divisor_q   = divisor_magnitude
quotient_q  = dividend_magnitude
remainder_q = 33'b0
iteration_q = 0
```

RUN 每拍组合形成：

```text
remainder_shift = {remainder_q[31:0], quotient_q[31]}
quotient_next   = {quotient_q[30:0], 1'b0}

if (remainder_shift >= {1'b0, divisor_q}) begin
    remainder_next  = remainder_shift - {1'b0, divisor_q}
    quotient_next[0] = 1'b1
end
else begin
    remainder_next = remainder_shift
end
```

当 `iteration_q==31` 时，FINALIZE 必须使用本拍的 `quotient_next` 和
`remainder_next`，不能使用旧寄存器值。普通 signed 运算分别按 quotient sign 和
dividend sign 修正商、余数；special flag 的规定结果最终覆盖迭代结果。

### 4.3 固定延迟

定义请求在边沿 E0 完成握手。E1 至 E32 恰好执行 32 次 RUN 更新，E32 后进入
FINALIZE；E33 完成符号修正并进入 RESPONSE。`rsp_valid` 从 E33 后的周期开始为 1，
并保持到 `rsp_fire`。unit TB 必须检查该精确延迟，而不只检查“最终会完成”。

## 5. 运算语义

### 5.1 乘法

- `MUL` 返回 64 位乘积低 32 位；
- `MULH` 使用 signed × signed，返回高 32 位；
- `MULHSU` 使用 signed × unsigned，返回高 32 位；
- `MULHU` 使用 unsigned × unsigned，返回高 32 位。

建议统一转换为无符号幅值进行迭代，在 FINALIZE 对完整 64 位结果做符号修正，
再选择高半或低半。`MULHSU` 只能对 rs1 应用 signed 解释。

### 5.2 除法与余数

必须覆盖：

| operation/情况 | quotient | remainder |
|---|---|---|
| 任意 DIV/REM 除数为 0 | `0xffffffff` | 原被除数 |
| signed `DIV/REM`：`0x80000000 / 0xffffffff` | `0x80000000` | `0` |
| unsigned `DIVU/REMU`：`0x80000000 / 0xffffffff` | `0` | `0x80000000` |
| 普通 signed | 向 0 截断 | 符号跟随被除数 |
| unsigned | 无符号商 | 无符号余数 |

这些情况都不产生 trap。

## 6. 流水集成

MDU request 必须捕获 EX forwarding 后的 `rs1_exec/rs2_exec`，不能捕获 ID 阶段的
旧寄存器读值。IDU 一旦发现 packet 已携带 exception，必须像清除其他副作用控制
一样清除 `mdu_ctrl`；`req_valid` 也必须显式排除 exception packet。

定义：

```text
ex_multicycle_wait =
    valid M instruction in EX && !mdu_response_available
```

等待期间：

- IF/ID HOLD；
- ID/EX HOLD；
- EX/MEM CLEAR，使更老 MEM/WB 可以排空；
- MDU 自己持有 operation、operand 和 partial state。

结果 available 且没有更老 MEM wait/flush 时，M 指令形成正常 EX/MEM candidate，
`exec_result=mdu_rsp_result`。M 指令不得标记为现有 `id_ex_result_late`：它在结果完成
前一直留在 EX，完成并进入 EX/MEM 后，现有 EX/MEM forwarding 即可提供结果，后继
依赖指令不需要新增 late-result bubble。

## 7. EX hold 快照边界

当前 Core 会在 ID/EX HOLD 时保存已完成 forwarding 的 EX candidate。这对普通 ALU
指令和 DMem request backpressure 是必要的，但不能在 MDU 尚未完成时保存未完成
结果。

集成后快照捕获谓词冻结为：

```text
snapshot_capture =
    !ex_hold_valid_q &&
    id_ex_q.valid &&
    (id_ex_action == PIPE_HOLD) &&
    !id_ex_q.mdu_ctrl.valid
```

并且必须区分：

- 非 M 指令因 MEM wait/EX request wait 被 HOLD：继续使用 `ex_hold_*` 快照；
- M 指令正在 RUN/FINALIZE：不得捕获普通 EX/MEM snapshot；
- M 指令 RESPONSE 被更老 MEM wait 阻挡：由 MDU response register 保持结果；
- MDU response 真正被 pipeline 接受后才允许释放。

reset 或任意全局 flush 必须清除遗留 `ex_hold_valid_q`，不能让被取消指令的普通
snapshot 在后续周期重新成为 active candidate。

不得仅把当前固定的 `ex_multicycle_wait=0` 接线而保留原 snapshot 条件。

## 8. 与较老事件并行

- 较老 DMem wait 时，年轻 MDU 可以继续迭代；
- MDU 先完成时，response 保持到 MEM wait 解除；
- 较老同步 trap、MRET 或未来 interrupt 提交时向 MDU发出 `kill`；
- 较老 trap 与 MDU response 同周期时，较老 trap 获胜；
- 被 kill 的 M 指令不得进入 EX/MEM、写 GPR 或退休；
- reset 在 IDLE/RUN/FINALIZE/RESPONSE 任一状态都清除在途操作。

## 9. 必须验证的场景

### 9.1 Unit TB

- 八种 operation；
- `0`、`1`、`-1`、最大正数和最小负数；
- signed/unsigned 交叉组合，重点覆盖 `MULHSU`；
- 全部除零和 signed overflow 规则；
- 随机操作数与软件参考模型比较；
- request 只接受一次，busy 时拒绝新请求；
- response backpressure 时 payload 稳定；
- 精确检查 E0 请求至 E33 response 的固定延迟；
- kill/reset 覆盖四个状态；
- kill 与 `req_fire`、`rsp_fire` 同拍时 kill 获胜，且之后没有迟到 response；
- 固定最大周期内一定产生 response。

### 9.2 Core directed TB

- RV32I 生产者通过 forwarding 喂给 M 指令；
- load/CSR 结果通过现有 bubble/forwarding 喂给 M 指令；
- M 结果被紧邻 ALU、branch、load/store 消费；
- M 结果被紧邻 CSR source、branch 和 store data 消费；
- 有数据依赖和无数据依赖的 back-to-back M 指令；
- `rd=x0` 不写状态但指令正常退休；
- 较老 MEM wait 与 MDU 并行；
- 较老 trap/MRET 取消运行中和已完成未接收的 MDU；
- MDU response 与 DMem response、较老 trap 同拍的优先级；
- reset 发生在运算中间；
- 每条 M 指令只写回、退休一次。

## 10. 完成门禁

- 八条指令全部实现后才报告 `misa.M=1`；
- 无组合 `/` 或 `%` 推断的整宽除法器；
- 无 request 重发、response 丢失、重复写回或死锁；
- 原有流水、异常和存储回归无退化；
- Icarus、Verilator 回归和 Core lint 通过。
