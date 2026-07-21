# MRET 设计合同

## 1. 目标与边界

本增量实现 `MRET`，关闭以下最小 Machine trap 软件闭环：

```text
normal execution
  → synchronous trap entry
  → handler updates mepc if needed
  → MRET
  → resume at mepc
```

同一增量把 `WFI` 实现为合法、正常退休的 NOP hint，以满足本项目采用的
Machine-Level ISA 基线；不实现睡眠、唤醒或 clock gating。

本增量不加入 interrupt、counter、RV32M、U/S Mode 或 vectored `mtvec`。

## 2. 架构语义

`MRET` 的唯一合法编码为：

```text
32'h3020_0073
```

Core 始终运行在 Machine Mode，因此该编码合法；其他未实现的 privileged SYSTEM
编码仍产生 illegal-instruction exception。`WFI` 的合法编码为 `32'h1050_0073`，
行为与无架构副作用的 NOP 相同，但保留真实 instruction 和 PC 供 retire 观察。

MRET 提交时按同一个时钟沿完成：

```text
next_pc      <- current mepc
mstatus.MIE  <- old mstatus.MPIE
mstatus.MPIE <- 1
```

`MPP` 继续固定读作 Machine。`mepc[1:0]` 已由 WARL 规则固定为 0，所以返回目标
满足当前 `IALIGN=32`。

MRET 是正常退休的指令：

- 不写通用寄存器；
- 不执行显式 CSR RMW；
- 不访问 DMem；
- 不产生 trap；
- 必须恰好产生一次 `retire_valid`；
- 只冲刷比它年轻的指令。

## 3. 流水元数据

建议在以下 packet 中增加单比特 `mret`：

```text
decode_ctrl_t → id_ex_t → ex_mem_t
```

MRET 到达 MEM 后完成提交，不需要把 `mret` 再携带到 MEM/WB。MEM/WB 中保留的
原始 instruction 足以产生正常 retire 事件。

译码 MRET 时所有普通副作用控制必须为 0：

```text
uses_rs1/uses_rs2 = 0
csr_ctrl          = 0
mem_ctrl          = 0
wb_ctrl           = 0
exception         = 0
```

已有早期 exception 优先于任何随 packet 携带的 MRET 标志；无效 packet 的 `mret`
没有意义，也不得触发返回。

## 4. MEM 提交条件

定义：

```text
mret_commit =
    ex_mem_q.valid &&
    ex_mem_q.mret &&
    !final_mem_exception.valid &&
    mem_stage_complete
```

虽然 MRET 自身不访问 DMem，仍使用统一 `mem_stage_complete` 表达 MEM 提交边界。
`mret_commit` 必须是一次性事件，不能因为下游或前端停顿重复拉高。

## 5. 流水动作

MRET 需要独立于同步 trap 的动作行：

| 事件 | IF/ID | ID/EX | EX/MEM | MEM/WB | Fetch |
|---|---|---|---|---|---|
| synchronous trap | clear | clear | clear | clear | redirect `mtvec` |
| MRET commit | clear | clear | clear | load | redirect `mepc` |

两者的差别是 MRET 自身必须进入 MEM/WB，而发生同步异常的指令不得进入 MEM/WB。

全局控制优先级在本增量后冻结为：

```text
reset
> synchronous trap
> MRET commit
> MEM response wait
> EX request/multicycle wait
> EX redirect
> late-result hazard
> fetch unavailable
> normal
```

MRET commit 必须压过同周期年轻 branch/JAL/JALR redirect。

## 6. Redirect 与副作用抑制

redirect 仲裁扩展为：

```text
synchronous trap target (mtvec)
> MRET target (mepc)
> EX branch/jump target
```

MRET 到达 MEM 的同周期，年轻 EX 指令可能已经形成 DMem request。必须把
`mret_commit` 纳入年轻请求阻断：

```text
ex_request_block =
    older_final_exception ||
    older_mem_control_redirect
```

这里 `older_mem_control_redirect` 至少包含 MRET；未来也包含 interrupt。被 MRET
冲刷的年轻 store 不得在同周期完成 request handshake。

已经被外部接受的更老事务不受 MRET 影响；按照顺序流水语义，MRET 只有在所有更老
指令都已经越过其提交边界后才能提交。

## 7. CSR 状态更新优先级

`rv32_csr_trap` 的时序优先级扩展为：

```text
reset > synchronous trap entry > MRET commit > explicit CSR write
```

MRET 使用时钟沿前的 `mepc` 和 `MPIE`。它不与同一条指令的显式 CSR 写共存。

未来加入 interrupt 时，必须在 MRET 后立即重新评价 interrupt enable；本增量先保留
该接口和优先级位置，不提前实现 interrupt。

## 8. 必须验证的场景

### 8.1 Unit TB

- decoder 只接受 `0x30200073`；
- decoder 接受 `0x10500073` 为无副作用、正常退休的 WFI hint；
- 其他未实现 privileged SYSTEM 编码仍然 illegal；
- MRET 不读寄存器、不写 GPR、不形成 CSR/DMem 控制；
- `MIE=0/1`、`MPIE=0/1` 的四种返回组合；
- redirect 使用提交前的 `mepc`；
- MRET 与 reset 同周期时 reset 获胜；
- 同步 trap 与 MRET 竞争时 trap 获胜。

### 8.2 Core directed TB

- ECALL 进入 handler，handler 调整 `mepc` 后 MRET 返回；
- MRET 自身恰好退休一次；
- 返回目标之后的第一条指令正常执行；
- MRET 后的顺序错误路径指令被冲刷；
- MRET 与年轻 taken branch 同周期时返回目标获胜；
- MRET 与年轻 store 同周期时 store 不发 request；
- MRET 提交时 WB 中更老指令仍可正常退休；
- reset 发生在 MRET 到达各流水级时不产生迟到 redirect/retire。

## 9. 完成门禁

- 设计合同、RTL、unit TB、core TB 位于同一能力 PR；
- 原有同步异常 cause matrix 不退化；
- MRET 既不被计作 trap，也不重复退休；
- 没有被冲刷指令的 GPR、CSR、DMem 或 redirect 副作用；
- Icarus、Verilator 回归和 Core lint 通过。
