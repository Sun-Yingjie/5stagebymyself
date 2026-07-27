# CSR、Trap 与 Machine Interrupt

本文档描述当前 RTL 已实现的有限 Machine profile、Zicsr 语义、Machine counter、MRET、同步 trap 与精确 Machine interrupt。当前执行环境固定按 Machine cause 编码运行，但没有完整 privilege level、PMP、debug 或 delegation，因此不能把它等同于完整 RISC-V Privileged Architecture。

## 1. CSR Profile

| 地址 | 名称 | Reset/读值 | 写入规则 |
|---:|---|---|---|
| `0x300` | `mstatus` | `0x00001800` | 只保存 `MIE[3]`、`MPIE[7]`；`MPP[12:11]` 固定读作 `11`，其余位读 0、写忽略 |
| `0x301` | `misa` | 固定 `0x40001100` | RV32 + I + M；合法 WARL 写，状态不变 |
| `0x304` | `mie` | `0` | 只保存 `MSIE[3]`、`MTIE[7]`、`MEIE[11]`，其余位读 0、写忽略 |
| `0x305` | `mtvec` | `MTVEC_RESET & 0xfffffffc` | 低两位清零，只支持 Direct mode |
| `0x340` | `mscratch` | `0` | 32 位读写 |
| `0x341` | `mepc` | `0` | 低两位清零 |
| `0x342` | `mcause` | `0` | 32 位读写；trap/interrupt entry 自动写入 cause |
| `0x343` | `mtval` | `0` | 32 位读写；interrupt entry 写 0 |
| `0x344` | `mip` | 三路 IRQ 实时映射 | `MSIP/MTIP/MEIP` 分别反映 software/timer/external 输入；CSR 写合法但无状态副作用 |
| `0xB00` | `mcycle` | `0` | `mcycle[31:0]`，可读写 |
| `0xB02` | `minstret` | `0` | `minstret[31:0]`，可读写 |
| `0xB80` | `mcycleh` | `0` | `mcycle[63:32]`，可读写 |
| `0xB82` | `minstreth` | `0` | `minstret[63:32]`，可读写 |
| `0xF11` | `mvendorid` | `0` | Machine read-only，真实写非法 |
| `0xF12` | `marchid` | `0` | Machine read-only，真实写非法 |
| `0xF13` | `mimpid` | `0` | Machine read-only，真实写非法 |
| `0xF14` | `mhartid` | `0` | Machine read-only，真实写非法 |
| `0xF15` | `mconfigptr` | `0` | Machine read-only，真实写非法 |

不在表中的 CSR 地址不存在，任何访问都产生 illegal-instruction trap。当前没有 privilege level 或 CSR 权限比较逻辑，所有已存在 CSR 都按上述固定 profile 判定。

`mip` 不是“整寄存器只读、写非法”的 Machine ID CSR：对它的真实写是合法 WARL no-op，中断源电平只能由 Core 外部清除。

## 2. Zicsr 指令语义

六条指令都在 ID 译码，在 EX 固化 source，在 MEM 对 CSR 旧值执行原子 read-modify-write；需要写 `rd` 时，旧值经 MEM/WB 返回。

| 指令 | 运算 | 读抑制 | 写抑制 |
|---|---|---|---|
| `CSRRW` | `new = rs1` | `rd=x0` | 无，始终是真实写 |
| `CSRRS` | `new = old \| rs1` | 无 | 指令中的 `rs1` 字段为 `x0` |
| `CSRRC` | `new = old & ~rs1` | 无 | 指令中的 `rs1` 字段为 `x0` |
| `CSRRWI` | `new = uimm` | `rd=x0` | 无，始终是真实写 |
| `CSRRSI` | `new = old \| uimm` | 无 | `uimm=0` |
| `CSRRCI` | `new = old & ~uimm` | 无 | `uimm=0` |

写抑制由指令字段是否为 0 决定，不由运行时 source 数据是否碰巧为 0 决定。

访问判定规则：

- 对存在的可写 CSR，合法读或写按表中规则提交；
- `misa` 和 `mip` 的真实写合法，但读值仍由固定实现或 IRQ 输入决定；
- 对 Machine read-only ID CSR，`CSRRS/CSRRC` 的 `rs1=x0` 或立即数版本的 `uimm=0` 可合法纯读；
- 对 Machine read-only ID CSR 的真实写产生 illegal instruction；
- 不存在 CSR 即使读或写被抑制也仍然非法；
- illegal 访问不写 CSR，也不写通用寄存器。

## 3. 提交事件与状态优先级

`rv32_csr_trap` 是 Machine CSR、counter 和 interrupt event pending 的唯一所有者。普通 CSR 写只由真正被流水接受的 `commit_valid` 提交；interrupt eligibility 则使用不依赖流水动作的 `mem_commit_candidate` 以及当前 CSR/MRET 的 effective post-commit 值，避免 `interrupt_take` 与 `mem_wb_action` 形成组合反馈。

普通状态更新优先级为：

```text
reset
> synchronous trap entry
> interrupt entry
> MRET
> explicit CSR write
```

若当前 CSR 写或 MRET 后立即取 interrupt，实现会先形成 post-write/post-MRET effective 值，再应用 interrupt entry。因此写 `mie/mstatus/mtvec` 的当前指令仍正常提交，MRET 也仍正常退休，不会被随后发生的 entry 丢失语义。

## 4. Machine Counter

- `mcycle` 在每个非 reset 周期加 1，包括 wait、bubble、trap 与 interrupt 周期；
- `minstret` 只在 `commit_valid` 时加 1；faulting 指令与 interrupt 事件本身不计数；
- post-commit interrupt 的当前 MEM 指令正常计入 `minstret`；
- 对四个 counter half 的已提交 CSR 写，在同一时钟沿覆盖被寻址的 32 位自动更新结果，未寻址的另一半保持正常更新；
- 64 位加法发生在整体 counter 上，低半溢出会自然进位到高半。

当前没有 user-level `cycle/instret` shadow CSR、`mcountinhibit` 或其他性能计数器。

## 5. MRET 与 WFI

`MRET` 在 MEM 提交点读取当前 `mepc`，而不是在 EX 提前快照：

```text
next_pc      <- mepc
mstatus.MIE  <- old mstatus.MPIE
mstatus.MPIE <- 1
```

MRET 本身正常进入 MEM/WB 并退休一次，同时清除年轻流水、阻断年轻 DMem request、kill 年轻 MDU，并压过年轻 branch/jump redirect。若恢复出的 MIE 使某个 pending interrupt 立即 eligible，则先完成上述 MRET 语义，再直接进入 interrupt；`mepc` 保存 MRET 返回目标，fetch 不会先执行该目标指令。

`WFI` 当前实现为合法、无额外副作用、正常退休的 NOP hint；不实现睡眠、唤醒或时钟门控。

## 6. 同步 Trap 提交

同步 trap 只在 MEM 中的指令有效、最终异常有效且不再等待 DMem response 时提交。`trap_valid`、`trap_pc`、`trap_cause`、`trap_value` 与内部 `trap_take` 同周期有效。

提交时执行：

```text
mepc         <- faulting_pc & 0xfffffffc
mcause       <- cause
mtval        <- value
mstatus.MPIE <- old mstatus.MIE
mstatus.MIE  <- 0
next_pc      <- current mtvec
```

同步 trap 高于 Machine interrupt、MRET、CSR 写和年轻 redirect。故障指令不普通退休，也不提交显式 CSR/DMem/寄存器副作用；同周期 WB 中更老指令仍可以退休。

## 7. 精确 Machine Interrupt

### 7.1 Pending、enable 与优先级

三路顶层输入是已经与 Core 时钟同步的高电平请求：

```text
irq_software -> mip.MSIP -> mie.MSIE
irq_timer    -> mip.MTIP -> mie.MTIE
irq_external -> mip.MEIP -> mie.MEIE
```

普通 eligibility 还要求 `mstatus.MIE=1`。多个来源同时 eligible 时，固定优先级为：

```text
Machine external > Machine software > Machine timer
```

### 7.2 精确边界与 entry

正常边界采用 post-commit interrupt：当前 MEM 指令先完成并进入 MEM/WB，entry 保存该指令的架构后继 PC。taken branch/JAL/JALR 保存控制转移目标，普通或 not-taken 指令保存 `pc+4`，MRET 保存提交时读取的返回目标。当前 load/store 不会被取消或重放，年轻 store/MDU/redirect 被抑制。

若四级流水寄存器均无有效指令、LSU 没有 outstanding 且 MDU idle，也可在 empty-pipeline boundary 取 interrupt；此时使用 Core 保存的 `resume_pc_q`，且没有配对 retire。

entry 执行：

```text
mepc         <- resume_pc & 0xfffffffc
mcause       <- selected interrupt cause
mtval        <- 0
mstatus.MPIE <- effective pre-entry MIE
mstatus.MIE  <- 0
next_pc      <- effective mtvec
```

若 IRQ 输入保持为 1，entry 清除 MIE 会防止未经重新使能的重复进入；输入电平本身不会被 Core 清除。

### 7.3 Trap 观察事件

interrupt take 同拍完成 CSR 更新、flush 和 redirect，但外部 interrupt `trap_valid` 由单项 pending 寄存器延后一拍输出一次：

```text
trap_pc    = 已写入 mepc 的 resume PC
trap_cause = selected interrupt cause
trap_value = 0
```

对于 post-commit interrupt，该延后事件与边界指令的 WB retire 同拍。外部 monitor/scoreboard 必须先解释 retire，再解释 interrupt trap，保持“当前指令退休 → interrupt”的架构顺序。延后的事件只用于观察，不会再次 flush、redirect 或更新 CSR；reset 会立即抑制并清除 pending 事件。

## 8. Cause 与 payload

### 8.1 同步异常

| Cause | 名称 | `trap_value/mtval` |
|---:|---|---|
| 0 | instruction address misaligned | 对齐检查失败的控制转移目标 |
| 1 | instruction access fault | 取指 PC |
| 2 | illegal instruction | 完整 32 位指令字 |
| 3 | breakpoint | `0` |
| 4 | load address misaligned | 数据字节地址 |
| 5 | load access fault | 数据字节地址 |
| 6 | store/AMO address misaligned | 数据字节地址 |
| 7 | store/AMO access fault | 数据字节地址 |
| 11 | environment call from M-mode | `0` |

对同一条指令，最终异常选择顺序为：已随流水携带的早期异常、CSR illegal、LSU access fault。

### 8.2 Machine interrupt

| `mcause` | 名称 |
|---:|---|
| `0x80000003` | Machine software interrupt |
| `0x80000007` | Machine timer interrupt |
| `0x8000000b` | Machine external interrupt |

## 9. 未实现内容

- 完整 privilege level/transition、delegation、PMP 与 debug CSR；
- vectored `mtvec`、NMI、U/S interrupt；
- PLIC、CLINT、片上 timer 与异步 IRQ 同步器；
- user counter shadow、其他 Machine performance counter 及未列出的 Machine CSR；
- 完整 privileged architecture/ACT4 认证。
