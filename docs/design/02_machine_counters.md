# Machine Counter 设计合同

## 1. 目标与边界

本增量实现 Machine Mode 的两个基本 64 位计数器：

| CSR | 地址 | 含义 |
|---|---:|---|
| `mcycle` | `0xB00` | cycle count 低 32 位 |
| `minstret` | `0xB02` | retired/committed instruction count 低 32 位 |
| `mcycleh` | `0xB80` | cycle count 高 32 位 |
| `minstreth` | `0xB82` | retired/committed instruction count 高 32 位 |

本项目选择确定性 reset 值 0。四个 CSR 均为 Machine read-write。

本增量不实现 `time/timeh`、`cycle/instret` 用户态 shadow、Zicntr、Zihpm、
`mcounteren` 或 `mcountinhibit`。没有 U/S Mode，因此 `mcounteren` 不存在；没有
`mcountinhibit` 等价于计数始终使能。

## 2. 为什么需要内部 commit 事件

外部 `retire_valid` 在 WB 由 MEM/WB packet 产生。但是 CSR 指令在 MEM 读取和写入
CSR；如果直接用同周期 WB retire 更新 `minstret`，紧邻的 counter 读写会出现程序
顺序旁路问题。

因此定义内部一次性事件：

```text
commit_valid =
    !rst &&
    (mem_wb_action == PIPE_LOAD) &&
    mem_wb_candidate.valid
```

其含义是：该指令已经完成所有可能产生异常的工作，此后一定会在 WB 正常退休。
外部 retire 事件仍保持现有时序，只是比内部 commit 晚一个流水级。

必须满足：

- 同步 trap 指令不产生 `commit_valid`；
- MRET 产生 `commit_valid`；
- load/store 只在成功 response 后产生一次；
- MEM wait 期间不重复产生；
- interrupt 若发生在某条指令之后，该指令产生 commit；
- interrupt 若发生在某条指令之前，该指令不产生 commit。

## 3. 自动更新语义

在每个非 reset 时钟沿：

```text
mcycle_next   = mcycle_q + 1
minstret_next = minstret_q + (commit_valid ? 1 : 0)
```

计数器自然按 64 位无符号数回绕，不产生异常和 interrupt。

`mcycle` 在流水 hold、存储等待、MDU busy 和空闲周期都继续计数。`minstret` 只在
一次性 commit 时递增，不按流水 valid 或 clock cycle 推测退休。

## 4. 显式 CSR 写与自动更新

RISC-V 定义 counter CSR 写在该指令其他行为完成之后生效。实现采用“先计算自动
更新，再覆盖被写的 32 位 slice”：

```text
cycle_work   = mcycle_q + 1
instret_work = minstret_q + commit_valid

if write mcycle:    cycle_work[31:0]  = csr_write_candidate
if write mcycleh:   cycle_work[63:32] = csr_write_candidate
if write minstret:  instret_work[31:0]  = csr_write_candidate
if write minstreth: instret_work[63:32] = csr_write_candidate
```

这样写 `minstret` 的指令先被视为完成，再由显式写覆盖低半；写高半时低半仍正常
计入该指令。未被写的另一半保留自动递增以及可能产生的 carry。

counter 不能直接塞进现有 CSR 状态的 `reset > trap > csr_write` 单一 `else-if`
分支，否则 trap、MRET 或普通 CSR 写周期可能漏加 `mcycle`。counter 必须使用独立的
两层 next-state：

1. 每个非 reset 周期先形成自动更新后的 work value；
2. 只有已经 commit 的 counter CSR slice 写覆盖对应 32 位 half。

因此 counter 自身的时序优先级为：

```text
reset > automatic update followed by committed counter-slice write
```

同步 trap、MRET 和非 counter CSR 写不阻止同周期 `mcycle` 自动增加；它们只按
`commit_valid` 决定是否增加 `minstret`。非法 CSR 访问、被 trap 取消或没有形成
commit 的 CSR 指令不得执行 counter slice 写。

## 5. CSR 读取

在 RV32 中一次 CSR 指令只原子访问一个 32 位 half：

- 读低半返回当前 `[31:0]`；
- 读高半返回当前 `[63:32]`；
- 硬件不保证软件两次读取之间 64 位值不变化；
- 软件需要用 `high-low-high` 序列取得一致快照。

counter 读取沿用当前 Zicsr read suppression 和 write suppression 规则。

## 6. 状态所有权

首版把 `mcycle_q` 和 `minstret_q` 放入 `rv32_csr_trap`，继续保持 Machine CSR 状态
只有一个所有者。若模块体积以后明显膨胀，再通过独立重构 PR 抽出
`rv32_machine_counters`，不得在功能 PR 中同时做结构重构。

需要向 CSR 模块提供明确的 `commit_valid`，不能用 `ex_mem_q.valid`、
`mem_wb_q.valid` 或 `retire_valid` 近似代替。

## 7. 必须验证的场景

### 7.1 Unit TB

- reset 后四个 half 为 0；
- `mcycle` 每个非 reset 周期加 1；
- `minstret` 仅在 `commit_valid` 加 1；
- 64 位低半溢出向高半进位；
- 分别写四个 half，未写 half 保持自动更新语义；
- CSR SET/CLEAR 使用操作前旧值形成新值；
- suppressed write 不覆盖自动更新：`mcycle` 仍加 1，正常 commit 的 counter 纯读
  仍令 `minstret` 加 1；
- reset 与写/增量同周期时 reset 获胜。

### 7.2 Core directed TB

- 连续普通 ALU 指令正确计数；
- load/store wait 多个周期只增加一次 `minstret`；
- ECALL/EBREAK/illegal/faulting load/store 不计入 `minstret`；
- MRET 计入 `minstret`；
- 对 counter 的 CSR 读写自身遵循 post-completion 写语义；
- back-to-back counter CSR 指令观察程序顺序一致的值；
- reset 清除在途指令且不产生迟到 increment；
- `mcycle` 在 MEM wait 与未来 MDU busy 时继续增加。
- `mcycle` 在同步 trap、MRET 和普通非 counter CSR 写周期仍增加 1；

## 8. 完成门禁

- `commit_valid` 的唯一含义在流水文档和 RTL 中一致；
- 每条正常指令对 `minstret` 的贡献恰好为 1；
- faulting 或被 flush 的指令贡献为 0；
- counter CSR 读写不破坏现有 Zicsr 原子 RMW；
- 完整回归与 Core lint 通过。
