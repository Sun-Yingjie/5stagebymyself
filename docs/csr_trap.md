# CSR 与同步 Trap

本文档冻结当前 RTL 的 CSR profile、Zicsr 语义和同步 trap 提交规则。当前执行环境固定按 Machine cause 编码处理，但没有完整 privilege state、interrupt 或返回路径，因此不能把本实现称为完整 Machine Mode。

## 1. CSR Profile

| 地址 | 名称 | Reset/读值 | 写入规则 |
|---:|---|---|---|
| `0x300` | `mstatus` | `0x00001800` | 只保存 `MIE[3]`、`MPIE[7]`；`MPP[12:11]` 固定读作 `11`，其余位读 0、写忽略 |
| `0x301` | `misa` | 固定 `0x40000100` | 合法 WARL 写，状态不变 |
| `0x305` | `mtvec` | `MTVEC_RESET & 0xfffffffc` | 低两位清零，只支持 Direct mode |
| `0x340` | `mscratch` | `0` | 32 位读写 |
| `0x341` | `mepc` | `0` | 低两位清零 |
| `0x342` | `mcause` | `0` | 32 位读写；同步 trap 写入 cause，最高位为 0 |
| `0x343` | `mtval` | `0` | 32 位读写 |
| `0xF11` | `mvendorid` | `0` | Machine read-only，真实写非法 |
| `0xF12` | `marchid` | `0` | Machine read-only，真实写非法 |
| `0xF13` | `mimpid` | `0` | Machine read-only，真实写非法 |
| `0xF14` | `mhartid` | `0` | Machine read-only，真实写非法 |
| `0xF15` | `mconfigptr` | `0` | Machine read-only，真实写非法 |

不在表中的 CSR 地址不存在，任何访问都产生 illegal-instruction trap。当前没有 privilege level 寄存器或访问权限比较逻辑，所有已存在 CSR 都按上述固定 profile 判定。

## 2. Zicsr 指令语义

六条指令都在 ID 译码，在 EX 固化 source，在 MEM 对 CSR 旧值执行原子 read-modify-write；需要写 `rd` 时，旧值经 MEM/WB 返回。

| 指令 | 运算 | 读抑制 | 写抑制 |
|---|---|---|---|
| `CSRRW` | `new = rs1` | `rd=x0` | 无，始终是真实写 |
| `CSRRS` | `new = old | rs1` | 无 | 指令中的 `rs1` 字段为 `x0` |
| `CSRRC` | `new = old & ~rs1` | 无 | 指令中的 `rs1` 字段为 `x0` |
| `CSRRWI` | `new = uimm` | `rd=x0` | 无，始终是真实写 |
| `CSRRSI` | `new = old | uimm` | 无 | `uimm=0` |
| `CSRRCI` | `new = old & ~uimm` | 无 | `uimm=0` |

写抑制由指令字段是否为 0 决定，不由运行时 source 数据是否碰巧为 0 决定。

访问判定规则：

- 对存在的可写 CSR，合法读或写按表中规则提交；
- `misa` 的真实写合法，但读回仍为固定实现值；
- 对 Machine read-only CSR，`CSRRS/CSRRC` 的 `rs1=x0` 或立即数版本的 `uimm=0` 可合法纯读；
- 对 Machine read-only CSR 的真实写产生 illegal instruction；
- 不存在 CSR 即使读或写被抑制也仍然非法；
- illegal 访问不写 CSR，也不写通用寄存器。

## 3. CSR 状态更新优先级

`rv32_csr_trap` 是 CSR 状态的唯一所有者，时序更新优先级固定为：

```text
reset > trap_take > csr_write_commit
```

因此：

- reset 周期忽略其他更新；
- trap 与显式 CSR 写同周期时，trap 自动更新胜出；
- 合法显式写只在没有 trap 时提交；
- CSR 指令返回的是写入前旧值。

## 4. 同步 Trap 提交

trap 只在 MEM 中的指令有效、最终异常有效且不再等待 DMem response 时提交。`trap_valid`、`trap_pc`、`trap_cause`、`trap_value` 与 `trap_take` 是同周期脉冲。

提交时执行：

```text
mepc         <- faulting_pc & 0xfffffffc
mcause       <- cause
mtval        <- value
mstatus.MPIE <- old mstatus.MIE
mstatus.MIE  <- 0
next_pc      <- current mtvec
```

`mstatus.MPP` 始终固定为 Machine。redirect 使用时钟沿前的当前 `mtvec`；故障指令的显式 CSR 写被取消。故障指令不普通退休，但同周期 WB 中更老指令可以退休。

## 5. Cause 与 payload

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

当前没有 interrupt，因而 `mcause[31]` 在自动 trap 更新中始终为 0。对同一条指令，最终异常选择顺序为：已随流水携带的早期异常、CSR illegal、LSU access fault。

## 6. 未实现内容

- `MRET` 与 trap return；
- Machine software/timer/external interrupt；
- `mie`、`mip` 及中断优先级；
- `mcycle/minstret`、Zicntr 与性能计数器；
- privilege transition、delegation、PMP、debug CSR；
- vectored `mtvec`；
- RV32 下其他未列出的 Machine CSR。

这些能力必须以独立 RTL 增量加入，并同时补充 directed TB 与架构测试，不能仅通过增加 CSR 地址声明支持。
