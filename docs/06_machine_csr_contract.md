# v0.2 Machine CSR Profile 与状态所有者契约

> 状态：Zicsr 状态所有者实现前的冻结契约。<br>
> 适用范围：RV32、`IALIGN=32`、单 hart、仅 M-mode。<br>
> 规范基线：[Zicsr 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)、[Privileged Architecture 1.13 Machine-Level ISA](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html) 和 [CSR address map](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html)。

## 1. 目标与非目标

本契约回答状态所有者实现前必须固定的四个问题：

1. 哪些 CSR 地址在本里程碑中存在；
2. 每个 CSR 的 reset、读值、可写位和合法化规则是什么；
3. 普通 Zicsr 写与同步 trap 自动更新如何排序；
4. 哪些访问必须产生 illegal-instruction，而不是被静默忽略。

本里程碑只为 Zicsr 和精确同步异常建立最小状态基础。当前运行模式固定为 M，
不加入 U/S-mode、interrupt、`MRET`、PMP、Debug、Zicntr 或 Zihpm。主 decoder
必须等状态所有者、异常合并和端到端测试都完成后，才把六条 CSR 指令从 illegal
切换为合法。

## 2. 冻结的实现环境

- `XLEN=32`，`IALIGN=32`，所以有效指令地址按 4 字节对齐；
- 单 hart，当前 privilege 恒为 M，不需要在首版 owner 接口中传 privilege mode；
- 当前实现报告 RV32I；Zicsr 没有独立的 `misa` 字母位；
- `mtvec` 首版只支持 Direct 模式；
- 所有本项目自行选择的 reset 值均固定为确定值，避免仿真 X 和不可复现实验；
- 标准 CSR 读没有读副作用，但仍严格遵守 Zicsr 的 read suppression；
- 一个周期最多提交一次显式 CSR 写或一次同步 trap 自动更新。

## 3. 本里程碑存在的 CSR

| 地址 | CSR | 类型 | reset/read 常量 | 写入和合法化规则 |
|---:|---|---|---:|---|
| `0x300` | `mstatus` | MRW/WARL | `0x0000_1800` | 保存 `MIE[3]`、`MPIE[7]`；`MPP[12:11]` 固定为 `11`；其余位读 0、写忽略 |
| `0x301` | `misa` | MRW/WARL 固定 | `0x4000_0100` | 写访问合法，但所有写值都合法化为固定的 RV32I 值；RV32M 完成前不得置 M 位 |
| `0x305` | `mtvec` | MRW/WARL | `MTVEC_RESET & 0xffff_fffc`，参数默认 0 | 仅 Direct；任何显式写都清零 `[1:0]` |
| `0x340` | `mscratch` | MRW | `0x0000_0000` | 32 位全部可写 |
| `0x341` | `mepc` | MRW/WARL | `0x0000_0000` | 显式写和 trap 自动写都清零 `[1:0]` |
| `0x342` | `mcause` | MRW/WLRL | `0x0000_0000` | 显式写保留 32 位；同步 trap 自动写的 interrupt 位为 0，并写入最终 cause |
| `0x343` | `mtval` | MRW | `0x0000_0000` | 32 位全部可写；trap 自动写入最终 exception value |
| `0xF11` | `mvendorid` | MRO | `0x0000_0000` | 只读常量；真实写尝试 illegal |
| `0xF12` | `marchid` | MRO | `0x0000_0000` | 只读常量；真实写尝试 illegal |
| `0xF13` | `mimpid` | MRO | `0x0000_0000` | 只读常量；真实写尝试 illegal |
| `0xF14` | `mhartid` | MRO | `0x0000_0000` | 单 hart ID 为 0；真实写尝试 illegal |
| `0xF15` | `mconfigptr` | MRO | `0x0000_0000` | 未提供配置数据结构；真实写尝试 illegal |

`misa` 和 identity CSR 刻意覆盖两种不同语义：

- `misa` 的地址属于 MRW。即使实现把整个值固定，写入也是一次合法 WARL 写，值保持不变；
- `mvendorid` 等地址属于 MRO。只有当本条指令的 `write_enable=1` 时才 illegal；
  被 Zicsr 规则抑制的写不构成只读写异常。

`mcause` 对显式软件写允许保留全部 32 位，是本项目对 WLRL 的确定实现选择。硬件自动
写入仍只产生当前支持的同步异常 cause。后续加入 interrupt 时再扩展 bit 31 的自动写语义，
不改变显式读写接口。

## 4. 本里程碑不存在的 CSR

以下地址当前必须按不存在处理，任何有效访问都产生 illegal-instruction：

- `mie/mip`：和 Machine interrupt 输入、屏蔽与接受顺序一起实现；
- `mcycle/mcycleh`、`minstret/minstreth`：放入独立 counter 增量；
- `cycle/time/instret` 及高半 shadow：未声明 Zicntr，且当前没有平台 `mtime`；
- `mhpmcounter*`、`mhpmevent*`：未声明 Zihpm；
- `medeleg/mideleg/medelegh`：本项目没有 S-mode；
- `mcounteren`：本项目没有 U/S-mode；
- `mstatush` 及扩展专用 Machine CSR：当前 profile 不实现相关扩展；
- PMP、环境配置、Debug、NMI 和自定义 CSR。

这表示当前只声明“项目 v0.2 CSR profile”，不声称已经完成全部 Machine-Level ISA。
在对外声称最小 Machine Mode 和执行对应 ACT4 配置前，必须补齐 `MRET`、Machine
counter 以及最终选定测试 profile 所要求的 CSR。

## 5. 访问合法性

状态所有者先独立计算地址存在性和整 CSR 只读属性：

```text
access_check_failed = !address_exists
                   || (write_enable && whole_csr_read_only)

csr_access_illegal = csr_access_valid && access_check_failed
```

当前 privilege 固定为 M，所以首版不增加 privilege 比较。以后加入较低特权级时，
在 `access_check_failed` 中增加权限条件，不改变其余接口。

必须区分以下两类写：

- 对 MRO CSR 的真实写尝试：整条访问 illegal，不读、不写、不向 `rd` 返回旧值；
- 对 MRW CSR 中未实现或固定字段的写：访问合法，这些位按 WARL 或只读字段规则
  被忽略或合法化。

组合读口固定为：

```text
if csr_access_valid && !csr_access_illegal && read_enable
    csr_read_data = addressed CSR 的修改前旧值
else
    csr_read_data = 0
```

因此 `CSRRW[I] rd=x0` 不读 CSR，但仍可写；`CSRRS/CSRRC` 的 `rs1=x0` 和
`CSRRSI/CSRRCI` 的 `uimm=0` 仍读 CSR，只是完全抑制写。

## 6. 显式 CSR 写

`rv32_csr_alu` 使用修改前旧值和 EX 固化的 source 生成候选值：

```text
WRITE: source
SET:   old | source
CLEAR: old & ~source
```

只有以下条件同时成立才允许在时钟沿提交显式写：

```text
csr_access_valid
&& !csr_access_illegal
&& csr_write_enable
&& !trap_take
```

候选值随后按目标 CSR 的规则合法化。非法访问和被抑制的写不能改变任何 CSR 状态。

## 7. 同步 trap 自动更新

状态所有者的时序优先级固定为：

```text
reset
> trap_take 自动更新
> 合法显式 CSR 写
```

`csr_access_illegal` 只依赖 CSR 访问输入和当前状态；core 使用它形成
`final_mem_exception`；状态所有者再根据最终异常产生：

```text
trap_take = mem_valid
         && final_mem_exception.valid
         && !mem_response_wait
```

不能让 `csr_access_illegal` 反向依赖 `final_mem_exception`，否则会形成组合环。

在 `trap_take` 对应的时钟沿：

- `mepc <= mem_pc & 32'hffff_fffc`；
- `mcause <= final_mem_exception.cause`；
- `mtval <= final_mem_exception.value`；
- `mstatus.MPIE <= mstatus.MIE`；
- `mstatus.MIE <= 0`；
- `mstatus.MPP` 继续读作 `11`；
- 本周期不提交异常指令的显式 CSR 写。

`trap_redirect.target` 使用时钟沿前的当前 `mtvec` base。`trap_valid/pc/cause/value`
与 `trap_take` 一一对应；同周期 WB 中更老指令仍可正常退休。

## 8. Owner 接口与集成边界

首版 `rv32_csr_trap` 先作为未接 core 的独立模块实现和单测。接口沿用
`docs/03_module_architecture.md` 第 9.7 节：

```text
输入：
clk/rst
mem_valid、mem_pc、mem_instruction、mem_response_wait
csr_access_valid/address/operation/source
csr_read_enable/write_enable
final_mem_exception

输出：
csr_read_data、csr_access_illegal
trap_take、trap_redirect
trap_valid、trap_pc、trap_cause、trap_value
```

正式接入 core 前必须先解决两项集成问题：

1. core 统一按“早期异常 > CSR illegal > LSU access fault”形成
   `final_mem_exception`；
2. MEM 中更老的 CSR illegal 必须进入 LSU 内部请求资格，禁止年轻 EX load/store
   在同周期握手。不得只在 LSU 外部与掉 `dmem_req_valid`，否则内部
   `request_fire/outstanding` 状态会与外部握手不一致。

## 9. 最低 directed test 矩阵

- reset 后逐个读取所有存在 CSR；
- `mscratch` 的 WRITE/SET/CLEAR 及返回旧值；
- `misa` 写访问合法、返回旧值且状态保持固定；
- MRO CSR 的纯读合法、真实写 illegal、被抑制写仍合法；
- 不存在地址的读和写都 illegal；
- `read_enable=0` 时输出 0，但合法写仍提交；
- `mtvec/mepc` 对所有低两位组合执行对齐合法化；
- 非法访问和被抑制写无状态变化；
- trap 同拍更新 `mepc/mcause/mtval/mstatus` 并产生 Direct redirect；
- trap 与显式 CSR 写同周期时 trap 胜出；
- reset、trap 和普通写各自只产生一次可观察状态变化。

只有上述单元测试、完整旧回归和 lint 通过后，才进入 core 集成和主 decoder 激活。
