# 精确 Machine Interrupt 设计合同

## 1. 目标与边界

本增量在 MRET、Machine counter 和 RV32M 已稳定后加入三类同步电平输入：

```text
irq_software
irq_timer
irq_external
```

三个输入都必须与 Core `clk` 同步。异步外设或跨时钟域同步属于 SoC wrapper。

本增量实现：

- `mie.MSIE/MTIE/MEIE`；
- `mip.MSIP/MTIP/MEIP`；
- `mstatus.MIE/MPIE` 的 interrupt entry/return；
- Machine software/timer/external interrupt；
- Direct `mtvec`；
- 指令边界上的精确 interrupt。

不实现 vectored mode、NMI、delegation、U/S interrupt、PLIC/CLINT 或片上 timer。

## 2. CSR 与输入语义

### 2.1 `mie`

`mie` 地址为 `0x304`，只保存：

```text
MEIE = bit 11
MTIE = bit 7
MSIE = bit 3
```

其余位读 0、写忽略。`mie` 是存在的 MRW CSR，沿用 Zicsr 原子 RMW 语义。

### 2.2 `mip`

`mip` 地址为 `0x344`：

```text
MEIP = irq_external
MTIP = irq_timer
MSIP = irq_software
```

三个已实现位是只读的电平反映，其余位读 0。对 `mip` 的 CSR 写是合法 WARL
no-op，不按 Machine ID CSR 的“整寄存器只读写非法”处理。中断源必须由 Core 外部
清除；只要输入保持为 1，pending 就保持为 1。

## 3. Eligibility 与优先级

普通情况下：

```text
external_eligible = mstatus.MIE && mie.MEIE && mip.MEIP
software_eligible = mstatus.MIE && mie.MSIE && mip.MSIP
timer_eligible    = mstatus.MIE && mie.MTIE && mip.MTIP
```

同时 eligible 时优先级固定：

```text
MEI > MSI > MTI
```

对应 `mcause`：

| Interrupt | `mcause` |
|---|---:|
| Machine software | `0x80000003` |
| Machine timer | `0x80000007` |
| Machine external | `0x8000000b` |

interrupt entry 写 `mtval=0`。

现有顶层 trap 观察接口继续复用，但内部取 interrupt 与外部事件分为两个时序点：

1. `interrupt_take` 在 MEM 提交边界生效，同拍更新 CSR、flush 并 redirect；
2. Core 同时把 resume PC、cause 和 value 锁存到单项
   `interrupt_event_pending_q`；
3. 下一拍由该 pending 状态拉高一次 `trap_valid`，`trap_pc` 等于已写入
   `mepc` 的 resume PC，`trap_cause` 等于选中的 interrupt cause，
   `trap_value=0`。

pending 为单拍自清事件：

```text
interrupt_event_pending_d = interrupt_take
trap_valid                 = interrupt_event_pending_q

posedge clk:
    if rst: interrupt_event_pending_q <- 0
    else:   interrupt_event_pending_q <- interrupt_event_pending_d
```

若本拍没有新的 `interrupt_take`，已输出事件在时钟沿后自动清除。

对 post-commit interrupt，这使 trap 观察事件与当前 MEM 指令的 WB retire 位于同一拍；
同拍有 `retire_valid && trap_valid` 时，外部监视器必须先解释 retire，再解释 interrupt
trap。因此架构事件序列保持为“当前指令退休 → interrupt”。empty-pipeline
interrupt 也沿用同一 pending 机制，只是发出 trap 事件的周期没有配对 retire。
interrupt 本身不是指令，不单独产生 retire 事件。reset 清除 pending 且抑制迟到的
`trap_valid`。

同一条 MEM 指令的同步 exception 高于所有 interrupt。interrupt 不得掩盖 faulting
load/store、illegal CSR 或控制流地址异常。

## 4. 精确边界选择

首版采用“当前 MEM 指令正常 commit 之后取 interrupt”，而不是在其副作用已经开始后
取消并重放它。

原因：load/store request 可能已经被外部接受；如果在 store 完成后把该指令当作
未执行并令 `mepc=mem_pc`，MRET 后会重复执行 store。post-commit interrupt 可以统一
处理 ALU、CSR、load、store、branch、MRET 和 MDU 指令。

正常边界使用 [Machine Counter 设计](02_machine_counters.md) 中不依赖流水动作的
`mem_commit_candidate`：

```text
post_commit_interrupt_take =
    mem_commit_candidate &&
    effective_interrupt_eligible
```

`effective_interrupt_eligible` 包含当前 CSR 或 MRET 提交后的有效状态。interrupt 决策不得
依赖 `commit_valid` 或 `mem_wb_action`；否则会形成
`commit_valid → interrupt_take → mem_wb_action → commit_valid` 组合环。仲裁完成后，
post-commit interrupt 动作必须选择 `PIPE_LOAD`，使同拍 `commit_valid=1`。

正常边界语义：

1. 当前 MEM 指令完成且无同步异常；
2. 该指令形成一次 `commit_valid` 并进入 MEM/WB；
3. 若有 eligible interrupt，同时提交 interrupt entry；
4. `mepc` 保存该指令的架构后继 PC；
5. 清除年轻流水状态并取消年轻 DMem/MDU 副作用；
6. redirect 到有效 `mtvec`；
7. 锁存一笔 interrupt 观察事件，在该指令的 WB retire 周期输出。

因此发生 interrupt 的指令边界上：当前指令正常计入 `minstret`，interrupt 自身不
计入；MRET 返回后从尚未执行的下一条指令开始。

## 5. 架构后继 PC

为了正确保存 branch/jump 后的 interrupt resume PC，EX/MEM packet 必须携带普通
指令在 EX 已经确定的：

```text
architectural_next_pc
```

形成规则：

| 当前指令 | `architectural_next_pc` |
|---|---|
| 普通顺序指令 | `pc + 4` |
| not-taken branch | `pc + 4` |
| taken branch | branch target |
| JAL/JALR | jump target |
| MRET | 在 MEM 提交时读取的有效 `mepc` |

MRET 目标不能在 EX 提前快照：更老的 CSR 指令可能正在 MEM 写 `mepc`。MRET 到达
MEM 时，必须读取已经包含所有更老提交结果的 `mepc`，并用它覆盖 packet 中的普通
`architectural_next_pc`。

Core 还应维护一个 `resume_pc_q`，表示最近一次已提交边界之后的下一架构 PC：

先形成当前边界的中间值：

```text
boundary_resume_pc =
    mem_commit_candidate ? effective_architectural_next_pc : resume_pc_q
```

`effective_architectural_next_pc` 对普通指令使用 packet 中的值，对 MRET 使用 MEM 提交
时读取的有效 `mepc`。post-commit interrupt 写入自身 `mepc` 的必须是
`boundary_resume_pc`，不是最终被 redirect 目标覆盖后的 `resume_pc_d`。

`resume_pc_q` 的 next-state 优先级冻结为：

```text
reset                         -> RESET_VECTOR
synchronous trap             -> current mtvec
interrupt_take               -> effective mtvec
MRET commit without interrupt -> effective mepc
normal commit                -> architectural_next_pc
otherwise                    -> hold
```

若当前 CSR 指令修改 `mtvec` 并紧接着取 post-commit interrupt，`effective mtvec` 必须使用
已合法化的 post-write 值。若 MRET 后立即取 interrupt，先用返回目标写入 interrupt
`mepc`，再令最终 `resume_pc_q=effective_mtvec`。

空流水边界显式定义为：

```text
pipeline_empty =
    !if_id_q.valid &&
    !id_ex_q.valid &&
    !ex_mem_q.valid &&
    !mem_wb_q.valid

empty_interrupt_boundary =
    pipeline_empty &&
    !lsu_outstanding &&
    mdu_idle &&
    effective_interrupt_eligible
```

`mdu_idle` 直接来自 `rv32_mdu.idle`，不用 `req_ready` 或 `!rsp_valid` 近似代替。

当 `empty_interrupt_boundary=1` 时，interrupt 使用 `resume_pc_q` 写 `mepc`。IFU 的 pending 或
outstanding request 不是架构副作用，可按现有 stale 机制排空，不阻止该边界。

## 6. Post-commit CSR 与 MRET 立即重评价

interrupt eligibility 必须使用“当前指令提交后的有效状态”，不能永远只看时钟沿前
的 CSR 值。

### 6.1 写 `mstatus` 或 `mie`

若当前 CSR 指令写 `mstatus.MIE` 或 `mie` 并使 pending interrupt 变为 eligible，
该 CSR 指令先正常 commit，随后立即进入 interrupt：

- eligibility 使用 `csr_write_candidate` 合法化后的新值；
- CSR 新值必须保留；
- interrupt entry 再把 `mstatus.MPIE` 设置为 post-write MIE，并清 `MIE`；
- 如果当前指令写 `mtvec`，同边界 interrupt 使用 post-write `mtvec`。

### 6.2 MRET

MRET 后必须立即用恢复后的 `MIE=old MPIE` 重新评价 pending interrupt。若立即取
interrupt：

- MRET 本拍正常 commit，并在下一拍只退休一次；
- interrupt `mepc` 等于 MRET 的返回目标；
- 最终 `mstatus.MIE=0`；
- 最终 `mstatus.MPIE` 等于 MRET 恢复出的 MIE；
- fetch 直接跳到 `mtvec`，不得先提交返回目标的指令。

实现可以组合形成 `post_mret_interrupt_take`，但必须保持逻辑上的顺序为“先 MRET，
后 interrupt entry”。

## 7. 流水动作与事件优先级

post-commit interrupt 和 MRET 都允许当前 MEM 指令进入 MEM/WB。空流水 interrupt
没有当前提交指令，因此保持 MEM/WB 无效：

| 事件 | IF/ID | ID/EX | EX/MEM | MEM/WB | Fetch |
|---|---|---|---|---|---|
| synchronous trap | clear | clear | clear | clear | redirect `mtvec` |
| post-commit interrupt | clear | clear | clear | load | redirect `mtvec` |
| MRET without immediate interrupt | clear | clear | clear | load | redirect `mepc` |
| empty-pipeline interrupt | clear | clear | clear | clear | redirect `mtvec` |

此表描述内部 `interrupt_take` 周期的流水与 fetch 动作。延后一拍的外部
`trap_valid` 只消耗 `interrupt_event_pending_q`，不得再次 flush、redirect 或更新 CSR。

最终优先级冻结为：

```text
reset
> synchronous trap
> post-commit interrupt
> MRET redirect
> MEM response wait
> EX request/multicycle wait
> EX redirect
> late-result hazard
> fetch unavailable
> normal
```

这里 post-commit interrupt 包含 MRET 或 CSR 写之后立即变为 eligible 的情况。

## 8. 年轻副作用与在途操作

一旦本周期决定在 MEM 边界取 interrupt：

- 阻断年轻 EX DMem request handshake；
- 向年轻 MDU 发出 kill；
- 年轻 branch/jump redirect 不得提交；
- IFU pending/outstanding 错误路径请求按现有 stale 机制排空；
- 已提交的当前 load/store 不得被撤销或重复执行；
- WB 中更老指令仍可退休；
- 当前 MEM 指令随后在 WB 只退休一次，同拍输出延后的 interrupt trap
  事件，并按 retire 后 trap 的顺序解释。

MEM response wait 期间不能提前决定当前 load/store 是否 commit，因此 interrupt 等待
response。MDU 若位于更年轻 EX，可以继续计算，但 interrupt 提交时必须取消其结果。

## 9. CSR 状态更新

普通 interrupt entry：

```text
mepc         <- resume PC
mcause       <- selected interrupt cause
mtval        <- 0
mstatus.MPIE <- effective pre-entry MIE
mstatus.MIE  <- 0
next_pc      <- effective mtvec
```

普通状态更新优先级：

```text
reset
> synchronous trap entry
> interrupt entry
> MRET
> explicit CSR write
```

对 post-commit CSR/MRET 立即 interrupt，不能仅靠简单 `else-if` 丢掉先发生的返回或
CSR 写语义；应先形成 effective post-commit values，再应用 interrupt entry 转换。

## 10. 必须验证的场景

### 10.1 Unit TB

- `mie` WARL 位和 `mip` 只读输入映射；
- 三种独立 interrupt cause；
- MEI、MSI、MTI 同时 pending 的优先级；
- 全局 MIE 和局部 enable 的所有屏蔽组合；
- interrupt entry 的 `mstatus/mepc/mcause/mtval`；
- pending 输入保持时，MIE 清零防止未重新使能时重复进入；
- MRET 和 CSR 写后的立即重评价；
- reset、同步 trap、interrupt、MRET 的优先级；
- `interrupt_event_pending_q` 只延后观察事件，不重复更新 CSR 或 redirect；
- reset 清除 pending 并抑制迟到 `trap_valid`。

### 10.2 Core directed TB

- 顺序 ALU 指令后取 interrupt，MRET 返回下一条指令；
- taken/not-taken branch、JAL、JALR 后保存正确 resume PC；
- load/store response 前不取，成功 commit 后再取且不重复访问；
- 同步 exception 与 pending interrupt 同拍时 exception 获胜；
- 写 `mie/mstatus/mtvec` 后立即取 interrupt；
- MRET 后立即重新进入 pending interrupt；
- interrupt 取消年轻 store、branch 和 MDU；
- MDU busy/response、DMem wait 和 interrupt 的竞争；
- 空流水边界使用 `resume_pc_q`；
- interrupt 边界当前指令计入 `minstret`，interrupt 不计入；
- post-commit interrupt 的当前指令退休与延后 trap 事件同拍出现，scoreboard
  按 retire 后 trap 排序；
- 连续事件流中不得出现 `retire(A) → interrupt(after B) → retire(B)` 的乱序；
- `post_commit_interrupt_take` 不经 `commit_valid/mem_wb_action` 反馈计算，且成立
  必然伴随一次 `commit_valid`；
- 每次 interrupt 只产生一次 trap event 和一次 handler redirect；
- reset 清除所有迟到 interrupt/retire/request。

## 11. 完成门禁

- `mepc` 始终指向 MRET 后应执行的第一条指令；
- 已提交 store 不重放，未提交年轻 store 不越过 interrupt；
- 同步异常、MRET、CSR 写和 interrupt 的同拍优先级有 directed test；
- pending level 不因内部一次采样而丢失；
- 三类 interrupt、MRET 和 MDU/DMem 组合没有死锁或重复副作用；
- retire/trap 外部事件序列与 post-commit 架构顺序一致；
- interrupt 仲裁到 `commit_valid` 的路径无组合环；
- 完整回归与 Core lint 通过。
