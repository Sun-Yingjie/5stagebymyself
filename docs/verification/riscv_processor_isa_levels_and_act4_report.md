# RISC-V 处理器能力层级、指令扩展与 ACT4 测试范围报告

> 文档状态：学习与规划报告  
> 整理日期：2026-07-17  
> 适用项目：32 位、单发射、顺序执行、五级流水 RISC-V 处理器核  
> 资料基线：RISC-V Ratified Specifications Library 与 `riscv-arch-test` ACT4

## 1. 报告目的

本报告回答三个问题：

1. RISC-V 官方如何描述“不同能力的处理器”；
2. 面向教学、裸机、MCU、RTOS、Linux 和高性能应用的处理器，一般需要哪些指令与系统能力；
3. 当前五级流水核处在哪一层，下一步增加哪些能力最有学习和项目展示价值。

这里首先要澄清：RISC-V 官方没有统一的“一级处理器、二级处理器、三级处理器”分类。官方使用的是：

```text
基础 ISA
   + 非特权扩展
   + 特权模式与特权扩展
   + 执行环境和平台
   + 可选的标准 Profile
```

因此，本报告中的 L0～L5 是为本项目建立的**工程学习层级**，不是 RISC-V International 的官方等级。每一级引用官方 ISA、Profile 和 ACT4 测试计划来定义边界。

另一个重要原则是：指令集能力和微架构性能不是同一维度。一颗顺序五级流水核和一颗乱序超标量核可以实现相同的 ISA；Cache、分支预测、发射宽度和主频不会自动改变它支持哪些指令。

## 2. 官方术语：Base、Extension、Privilege、Profile 与 Platform

### 2.1 Base ISA：不可缺少的基础

每个 RISC-V ISA 都必须选择一个基础整数 ISA，例如：

- `RV32I`：32 位整数寄存器，32 个通用寄存器；
- `RV64I`：64 位整数寄存器，32 个通用寄存器；
- `RV32E`：面向极小型嵌入式核，只有 `x0～x15` 共 16 个通用寄存器；
- `RV64E`：64 位、16 个通用寄存器的嵌入式基础 ISA。

`RV32E` 不是 RV32I 完成后的“更高一级”，而是一个以寄存器数量换面积和功耗的平行选择。当前项目已经实现 32 个整数寄存器，因此应沿 `RV32I` 发展，没有必要改成 RV32E。

### 2.2 Extension：按需求增加的标准能力

常见扩展包括：

| 扩展 | 主要能力 | 典型使用场景 |
|---|---|---|
| `M` | 整数乘法和除法 | 通用 C 程序、控制算法、地址和定点计算 |
| `Zmmul` | 只实现乘法，不实现除法 | FPGA、低成本 MCU、定点 DSP |
| `A` | 原子读改写、LR/SC | 多核、操作系统、线程同步 |
| `F` | IEEE 754 单精度浮点 | 控制、传感、通用计算 |
| `D` | IEEE 754 双精度浮点 | 高精度和通用应用处理器 |
| `C` | 16 位压缩指令 | 降低代码尺寸和取指带宽 |
| `B` | 位操作 | 编解码、加密、操作系统、编译器优化 |
| `V` | 应用处理器向量运算 | 数据并行、媒体、科学计算、机器学习 |
| `Zve*` | 较小的嵌入式向量子集 | MCU、DSP、边缘 AI |
| `Zicsr` | 6 条 CSR 读改写指令 | trap、中断、计数器、特权控制 |
| `Zifencei` | 指令流与数据写入同步 | 自修改代码、代码加载、I-Cache 一致性 |
| `Zicntr` | 基础周期/时间/退休计数器 | 性能测量、软件时基 |

扩展是模块化选择，不代表所有处理器都应该实现全部扩展。例如单核、无操作系统的小 MCU 不一定需要 `A`；有 NPU 的边缘 AI SoC 也不一定需要让 CPU 实现完整 `V`。

### 2.3 Privileged Architecture：从“会执行程序”到“能管理系统”

官方特权架构定义三种特权级：

| 模式 | 含义 | 典型软件 |
|---|---|---|
| M-mode | Machine Mode，最高特权级，也是硬件平台唯一必需的特权级 | 固件、异常和中断入口、SBI 实现 |
| S-mode | Supervisor Mode | Linux 等操作系统内核 |
| U-mode | User Mode | 普通应用程序 |

一个只验证算术、跳转和访存的教学核，可以暂时不建立完整特权环境；但要成为能稳定运行裸机固件、RTOS 或操作系统的处理器，就要定义 CSR、异常、中断、返回和内存保护。

### 2.4 Profile：为软件生态冻结一组能力

Profile 不是单条指令扩展，而是面向某类软件生态规定一组 mandatory 和 optional 能力。

- `RVI20U32`：以完整 RV32I 为基础的通用 32 位非特权软件基线；
- `RVA20/RVA22/RVA23`：面向可运行丰富软件栈的 64 位应用处理器；
- `RVB23`：面向允许定制标准 OS 源码构建的 64 位应用处理器，强制集合比 RVA23 更重视实现成本的可选性。

截至本报告日期，官方 RVA/RVB 应用处理器 Profile 都是 64 位目标。不能把一个 RV32 五级流水核直接称为 RVA23 处理器。

### 2.5 Platform：ISA 之外仍然需要系统硬件

“支持了某些指令”和“能运行某类软件”之间还隔着平台：

- ROM、SRAM/DRAM 和地址映射；
- 定时器；
- 外部和软件中断控制器；
- UART 等调试输出；
- 启动固件；
- Linux 场景下的 SBI、设备树和更完整的 SoC 约定。

ACT4 主要认证架构行为，不能证明整个 SoC 平台已经能启动 RTOS 或 Linux。

## 3. L0：教学型“RV32I 程序子集”处理器

### 3.1 目标

L0 用于学习数据通路和流水控制：

- 五级流水；
- 数据前递；
- load-use stall；
- 分支和跳转冲刷；
- load/store byte strobe；
- valid/ready 背压。

这个层级允许只实现 RV32I 中最常用的普通数据处理指令，但必须明确称为“RV32I 子集”，不能称为完整 RV32I。

### 3.2 当前项目已经实现的 37 条指令

| 类别 | 指令 |
|---|---|
| 高位立即数 | `LUI`、`AUIPC` |
| 跳转 | `JAL`、`JALR` |
| 条件分支 | `BEQ`、`BNE`、`BLT`、`BGE`、`BLTU`、`BGEU` |
| Load | `LB`、`LH`、`LW`、`LBU`、`LHU` |
| Store | `SB`、`SH`、`SW` |
| 立即数整数运算 | `ADDI`、`SLTI`、`SLTIU`、`XORI`、`ORI`、`ANDI`、`SLLI`、`SRLI`、`SRAI` |
| 寄存器整数运算 | `ADD`、`SUB`、`SLL`、`SLT`、`SLTU`、`XOR`、`SRL`、`SRA`、`OR`、`AND` |

### 3.3 L0 不具备的能力

- `FENCE`；
- `ECALL`；
- `EBREAK`；
- 对非法指令、访问错误和非对齐访问的完整精确 trap；
- CSR 和中断；
- 标准 Profile 声明。

### 3.4 ACT4 的使用方式

ACT4 的 `I` 测试计划面向完整 RV32I，而不是本项目自行定义的 37 条子集。因此 L0 只能挑选部分测试做开发调试，不能把筛掉失败项后的结果称为 RV32I ACT 通过。

## 4. L1：完整 RV32I / RVI20U32 非特权基线

### 4.1 目标

L1 是第一个可以清晰对外声明的标准 ISA 边界：完整 RV32I。官方 RVI20U32 Profile 也以 RV32I 为 mandatory base，没有额外 mandatory extension。

### 4.2 完整 RV32I 指令集合

RV32I 一共有 40 条独立指令。除 L0 已实现的 37 条外，还需要：

| 指令 | 架构作用 | 简单五级核的实现方式 |
|---|---|---|
| `FENCE` | 对同一 hart 的内存和设备访问建立指定顺序 | 对当前顺序、阻塞、无 Cache/无 store buffer 核，可作为合法退休的 no-op，但必须接受所有规范要求的合法编码 |
| `ECALL` | 向执行环境发起服务请求并产生精确 trap | 进入执行环境或 Machine trap 入口 |
| `EBREAK` | 产生断点异常 | 进入精确 trap，后续可与调试模块衔接 |

需要注意：

- `FENCE.I` 不属于 RV32I，而属于独立的 `Zifencei` 扩展；
- `FENCE.TSO` 使用 `FENCE` 编码，RVI20U32 要求实现必须把它当作 TSO fence，或至少当作更强的普通全局 fence；
- `ECALL/EBREAK` 虽然编码在 SYSTEM major opcode 中，但属于基础非特权 ISA；
- 不支持非对齐 load/store 可以是合法选择，但必须产生规范定义的异常，不能把行为留成未定义；
- 合法 HINT 编码不能错误地产生可观察副作用。

### 4.3 L1 对当前项目的价值

完成 L1 后，项目描述可以从：

```text
实现 RV32I 常用程序子集的五级流水核
```

升级为：

```text
实现完整 RV32I 非特权指令语义、精确同步异常边界，
并通过对应 ACT4 架构测试的五级流水核
```

这比单纯继续增加更多算术指令更重要，因为它第一次形成了完整、可验证的架构契约。

### 4.4 ACT4 范围

- UDB 声明：`RV32I`；
- 生成范围：`I`；
- privilege tests：关闭；
- misaligned 行为：在 UDB 中如实声明“不支持并 trap”；
- 通过条件：适用的 `I` 测试全部通过，不能临时过滤 `FENCE` 或 SYSTEM 行为后宣称完成。

## 5. L2：实用裸机/MCU 核

### 5.1 常见工程配置

一个实用的 32 位 MCU 核常见配置可以写成：

```text
RV32IM_Zicsr_Zifencei
```

如果强调代码密度，再加入 `C`：

```text
RV32IMC_Zicsr_Zifencei
```

这不是官方规定所有 MCU 都必须如此，而是工具链支持、软件便利性和实现成本之间常见的工程平衡。

### 5.2 M 扩展：整数乘除法

RV32 的 `M` 扩展增加 8 条指令：

| 类别 | 指令 |
|---|---|
| 乘法低位 | `MUL` |
| 乘法高位 | `MULH`、`MULHSU`、`MULHU` |
| 除法 | `DIV`、`DIVU` |
| 余数 | `REM`、`REMU` |

对本项目，适合使用迭代式乘除单元来学习多周期执行、流水 hold 和结果提交。除零不会产生算术异常，商和余数必须返回规范规定的值。

如果时间或面积非常紧，可以先实现 `Zmmul`：它在 RV32 中只包含 `MUL、MULH、MULHSU、MULHU`，编码与 M 相同，但不能把它声明为完整 M。

### 5.3 Zicsr：CSR 指令

`Zicsr` 增加 6 条 CSR 原子读改写指令：

| 寄存器源 | 置位源 | 清零源 |
|---|---|---|
| `CSRRW` | `CSRRS` | `CSRRC` |
| `CSRRWI` | `CSRRSI` | `CSRRCI` |

实现 Zicsr 不只是给 decoder 增加 6 个编码，还需要：

- CSR 地址和权限检查；
- 读写副作用定义；
- 与 trap 提交的优先级；
- CSR 指令与前后指令的数据相关处理；
- 对未实现 CSR 的非法指令异常。

### 5.4 最小 Machine Mode

实用裸机核通常还要建立最小 Machine Mode。重要指令包括：

- `MRET`：从 Machine trap 返回；
- `WFI`：等待中断，简单实现可以把它作为合法 no-op，但软件必须仍能正确工作；
- `ECALL/EBREAK`：按照当前模式产生对应异常。

典型最小 CSR 集合可包括：

- trap 状态：`mstatus、mtvec、mepc、mcause、mtval`；
- 中断：`mie、mip`；
- 临时保存：`mscratch`；
- 能力描述：`misa`，是否实现及字段行为应按所采用的特权规范版本定义；
- Machine 计数器：`mcycle、minstret` 及其 RV32 高半部分；若进一步声明 `Zicntr`，还要实现 `cycle/time/instret` shadow CSR 及相应访问语义。

这里的关键能力不是 CSR 数量，而是精确 trap：出错指令之前的指令必须完成，出错指令及之后的错误路径不能产生架构副作用。

### 5.5 Zifencei：指令取值同步

`Zifencei` 只有一条指令：

```text
FENCE.I
```

无 I-Cache 且指令 SRAM 与数据写入路径完全分离时，软件可能很少用到它；但如果支持程序加载、自修改代码或未来加入 I-Cache，就必须明确它如何使后续取指看到先前的数据写入。

### 5.6 C：压缩指令

整数压缩能力主要由 `Zca` 构成。RV32 常见压缩指令包括：

```text
C.ADDI4SPN  C.LW      C.SW
C.NOP       C.ADDI    C.JAL     C.LI
C.ADDI16SP  C.LUI
C.SRLI      C.SRAI    C.ANDI
C.SUB       C.XOR     C.OR      C.AND
C.J         C.BEQZ    C.BNEZ
C.SLLI      C.LWSP    C.SWSP
C.JR        C.JALR    C.MV      C.ADD     C.EBREAK
```

加入压缩指令后，取指对齐从 `IALIGN=32` 放宽到 `IALIGN=16`。这会影响：

- PC 增量在 2 和 4 字节之间选择；
- 跨 word 取指；
- IF/ID 接口和指令拼接；
- 跳转目标对齐异常；
- 解压器与原始指令退休记录。

所以 C 虽然能提高代码密度，但对当前项目的前端改造大于增加 M 或 Zicsr。它适合放在完整 RV32I 和 trap/CSR 之后。

### 5.7 ACT4 范围

根据实际实现逐项开启：

- `I`；
- `M` 或 `Zmmul`；
- `Zicsr`；
- `Zifencei`；
- 压缩指令对应的 `Zca`，以及实际支持的 `Zcb/Zcf/Zcd` 等组件。

ACT4 当前按组件拆分测试。例如原子扩展有 `Zaamo` 和 `Zalrsc` 计划，压缩扩展有 `Zca/Zcb/Zcf/Zcd`，这能提醒设计者不能只写一个笼统的“支持 C/A”，而要给出准确能力声明。

## 6. L3：可运行 RTOS 的健壮 MCU/控制核

### 6.1 指令不是唯一门槛

RTOS 对普通整数指令的要求通常不会比 L2 高很多，真正新增的是可靠的系统控制能力：

- Machine Mode 精确异常；
- timer interrupt；
- external interrupt；
- software interrupt（按平台需求）；
- 中断屏蔽、pending 和优先级语义；
- `MRET` 返回；
- `WFI` 空闲；
- 可选的 PMP 内存保护；
- 确定的启动入口、栈、链接脚本和设备映射。

### 6.2 推荐指令和扩展

```text
推荐基线：RV32IM_Zicsr_Zifencei + Machine Mode
代码密度：可选 C
多核/强并发：增加 A
数值计算：按需求增加 F 或 Zfinx
```

### 6.3 A 扩展：何时才有必要

RV32 `A` 扩展包含：

| 类别 | 指令 |
|---|---|
| Load-reserved / store-conditional | `LR.W`、`SC.W` |
| 原子交换 | `AMOSWAP.W` |
| 原子算术 | `AMOADD.W` |
| 原子逻辑 | `AMOXOR.W`、`AMOAND.W`、`AMOOR.W` |
| 原子最值 | `AMOMIN.W`、`AMOMAX.W`、`AMOMINU.W`、`AMOMAXU.W` |

每条原子指令还具有 `aq/rl` 内存顺序位。

对单 hart、无 Cache、无 DMA 共享内存的 MCU，A 通常不是首要能力；关中断可以实现很多短临界区。以下情况才明显需要 A：

- 多 hart；
- 操作系统或运行库依赖原子操作；
- CPU 与 DMA/NPU/外设并发访问共享内存，并且软件需要无锁同步；
- 目标软件 ABI 或 Profile 明确要求 A。

实现 A 的难点不是 ALU，而是 reservation、原子性、总线锁定/独占访问、外部写入使 reservation 失效，以及内存顺序。

### 6.4 ACT4 范围

- L2 的全部已声明扩展；
- Machine 特权测试中与实现版本和参数匹配的部分；
- 中断和异常类测试；
- 若实现 A，则启用 `Zaamo` 与 `Zalrsc` 相关计划；
- PMP 测试必须与 PMP entry 数量、粒度和模式配置一致。

## 7. L4：可运行 Linux 的 RV32 应用处理器

### 7.1 常见非特权指令基线

一个工程上常见的 32 位 Linux 处理器起点是：

```text
RV32IMAC_Zicsr_Zifencei
```

其中：

- `I` 提供整数编译目标；
- `M` 避免大量乘除软件例程；
- `A` 支持内核和多线程原子同步；
- `C` 降低内核和用户程序代码尺寸；
- `Zicsr` 支撑特权状态；
- `Zifencei` 支撑代码加载和指令缓存同步。

这里是常见工程基线，不是当前官方 RVA Profile，因为 RVA Profile 目前只定义 64 位应用处理器。

### 7.2 必需的特权与地址转换能力

Linux 能力的主要门槛已经不再是增加几条 ALU 指令，而是：

- M/S/U 特权模式；
- Machine 和 Supervisor CSR；
- 异常与中断委托；
- `MRET`、`SRET`、`WFI`；
- `SFENCE.VMA`；
- Sv32 两级页表和地址转换；
- TLB 与页表遍历；
- instruction/load/store page fault；
- PMP；
- timer 和 external interrupt；
- SBI、启动固件和 SoC 平台设备。

官方特权规范明确说明 Sv32 提供支持现代 Unix 类操作系统所需的 32 位分页机制。

### 7.3 为什么这不适合作为当前项目近期目标

从 L3 到 L4 不是“小加几条指令”，而是增加 MMU、TLB、页表遍历、特权切换、异常委托、中断平台和启动软件。这会显著扩大设计与验证范围，并削弱当前项目“完成一版五级流水核并完整走通验证流程”的主线。

Linux-capable 可以作为长期学习分支，但不应成为当前实习项目前的完成门槛。

## 8. L5：现代 64 位应用处理器 Profile

### 8.1 RVA23U64

官方 RVA23U64 以 `RV64I` 为 mandatory base，并强制要求一大组扩展，包括：

- `M、A、F、D、C、B`；
- `Zicsr、Zicntr、Zihpm`；
- cache block 管理和预取相关扩展；
- `V` 及相关向量扩展；
- 条件操作、hint、附加压缩和附加浮点扩展；
- 一系列内存原子性、非对齐、reservation set 和指针屏蔽要求。

### 8.2 RVA23S64

RVA23S64 在 RVA23U64 基础上还要求：

- `Zifencei`；
- Supervisor Architecture 1.13；
- `Sv39`；
- 页故障、页表访问、地址转换缓存失效相关能力；
- supervisor timer、性能计数和指针屏蔽；
- RVA23 当前还将增强的 Hypervisor 能力纳入 mandatory 集合。

### 8.3 对本项目的意义

RVA23 的价值是作为“现代通用应用处理器有多完整”的上界参照，而不是当前实现目标。它说明：

- 高级应用处理器的 ISA 合同已经远超 `RV64GC` 这几个字母；
- 向量、原子、浮点、压缩、Cache 管理和虚拟化共同服务于统一二进制软件生态；
- 一个教学五级流水项目没有必要通过堆叠这些扩展来证明价值。

## 9. 边缘 AI 处理器的指令选择不是简单向 L5 升级

本项目的长期方向包含边缘 AI/NPU，因此要特别区分 CPU 指令集和 AI 加速能力。

### 9.1 三种路线

| 路线 | CPU ISA | AI 计算位置 | 特点 |
|---|---|---|---|
| 小 CPU + NPU | RV32I/M + Zicsr | 独立 NPU | 最符合当前 CPU+加速器学习路线 |
| 嵌入式向量 CPU | RV32 + `Zve32x/Zve32f` | CPU 向量单元 | 软件编程统一，但 CPU 微架构复杂度上升 |
| 应用处理器向量 | RV64 + `V` | 大型向量单元 | 面向丰富 OS 和高性能软件生态，范围最大 |

### 9.2 对当前项目的建议

CPU 不需要先实现 V 才能连接 NPU。对一个通过 MMIO 下发任务、由 NPU 访问 Tensor Scratchpad 的边缘 AI 系统，CPU 更需要的是：

- 完整而可靠的整数控制流；
- 地址和循环计算所需的 M 或 Zmmul；
- trap/CSR 和必要的中断；
- 明确的共享存储和内存顺序规则；
- 如果 CPU/NPU 真正并发共享内存，再评估 A、DMA 和 cache coherence。

因此，NPU 是面向需求的正交扩展，不应被解释为处理器必须从 L2 一路升级到 RVA23。

## 10. ACT4 如何映射这些能力

ACT4 的核心思想是：DUT 在 UDB 中声明什么能力，框架就为相应能力选择测试，并用匹配配置的 Sail 模型计算参考结果。

当前 ACT4 testplans 目录包含的主要类别有：

- 基础整数与乘除：`I、M`；
- 浮点：`F、D`；
- 原子：`Zaamo、Zalrsc、Zabha、Zacas` 等；
- 位操作：`Zba、Zbb、Zbc、Zbs` 等；
- 压缩：`Zca、Zcb、Zcf、Zcd、Zcmop` 等；
- CSR/计数器/取指同步：`Zicsr、Zicntr、Zihpm、Zifencei`；
- 向量：整数、访存、浮点和 vector crypto 相关计划；
- privileged 子目录中的特权架构测试；
- 独立的 misaligned 访问计划。

这带来四条测试原则：

1. ISA 字符串和 UDB 必须如实描述实现，不能为了少跑测试而少声明已经对软件开放的能力；
2. “支持一个扩展”意味着该扩展中所有适用的规范行为都要通过，不是挑其中几条常用指令；
3. ACT4 通过不能替代流水冒险、背压、flush、断言、随机测试和综合检查；
4. 测试未覆盖的微架构内部错误，仍需现有 directed TB 和后续差分验证发现。

## 11. 当前项目定位

### 11.1 当前层级

当前核最准确的定位是：

```text
L0 已完成；L1 的 RTL 与 directed verification 已收口，正在补 ACT4 架构验收
```

它已经实现 RV32I 的 37 条普通整数、分支、跳转和访存指令，`FENCE` 可正常退休，
`ECALL/EBREAK` 和 cause 0、1、2、3、4、5、6、7、11 已进入统一精确 trap 通路；
六条 Zicsr 指令及当前 Machine CSR profile 也已完成 core directed verification。同步异常
cause 矩阵的证据见
[v0.2 同步异常 Cause 矩阵验证报告](v0.2_sync_trap_cause_matrix_report.md)。

尚未完成的是适用 ACT4、可变延迟与广泛 backpressure 门禁以及 v0.2 正式冻结流程。
因此当前仍不应把项目表述成“已经通过架构认证的完整 RV32I 核”。

所以目前不应写成“完整 RV32I 核”，更准确的表述是：

```text
实现 RV32I 指令语义、精确同步异常和 Zicsr 基础的 32 位单发射顺序五级流水处理器核；
具备前递、late-result stall、控制流冲刷和带背压的存储接口；
directed cause 矩阵已闭环，正在接入 ACT4 RV32I 架构测试。
```

### 11.2 建议的项目主线

| 优先级 | 能力 | 为什么现在值得做 | 完成证据 |
|---|---|---|---|
| P0 | 完整 RV32I | 冻结第一个标准 ISA 合同 | 全部适用 ACT4 `I` 测试通过 |
| P0 | 精确异常闭环 | 证明流水控制不只处理正常路径 | illegal/ECALL/EBREAK/访问和对齐定向测试 |
| P0 | ACT4 runner | 建立官方测试输入到 PASS/FAIL 的流程 | ELF/HEX 装载、超时、批量结果报告 |
| P1 | Zicsr + 最小 M-mode | 从“计算核”升级为可管理的处理器 | CSR、trap、MRET、权限测试 |
| P1 | M 或先 Zmmul | 学习多周期执行，实用价值高 | ACT4 M/Zmmul + directed corner cases |
| P2 | timer interrupt + WFI | 支撑裸机事件驱动和 RTOS 学习 | 精确中断、返回和低功耗空闲测试 |
| P2 | Zifencei | 为程序加载和未来 I-Cache 建立语义 | ACT4 Zifencei 测试 |
| 可选 | C | 代码密度好，但需要重做一部分取指前端 | Zca 等测试和混合 16/32 位程序 |
| 可选 | A | 单核当前收益较低，实现和互联代价较大 | Zaamo/Zalrsc 与并发验证 |
| 长期 | S/U + Sv32 | Linux 学习分支，远超当前近期范围 | 特权测试、MMU 测试和 Linux bring-up |
| 长期 | Zve/V 或 NPU | 面向数据并行和边缘 AI | 扩展专用验证和系统工作负载 |

### 11.3 建议的实际目标 ISA

如果以“实习前完成一版、讲清设计和验证流程”为目标，建议最终主线控制在：

```text
最低完成目标：完整 RV32I + 精确同步异常 + ACT4 I

推荐展示目标：RV32IM_Zicsr + 最小 Machine Mode
              + 精确异常/中断
              + ACT4 对应测试
              + directed TB / 差分 / 综合与 STA 闭环

可选加分项：Zifencei、timer interrupt、少量 PMP
```

不建议把 C、A、F/D、S-mode、MMU、Linux 和 V 同时纳入当前主线。一个能力边界清晰、官方测试和 ASIC 前端流程都走通的 RV32IM 核，比一个扩展很多但每项都没有验证闭环的核更适合作为当前项目成果。

## 12. 推荐展示目标的详细定义

### 12.1 这不是一份功能清单，而是一条完整证据链

推荐展示目标为：

```text
RV32IM_Zicsr + 最小 Machine Mode
               + 精确异常/中断
               + ACT4 对应测试
               + directed TB
               + 参考模型差分
               + 综合与 STA 闭环
```

这套目标的重点不在于扩展数量，而在于形成一条从需求到实现结果的完整证据链：

```text
目标软件与项目范围
        ↓
ISA 和特权架构合同
        ↓
五级流水微架构与多周期单元
        ↓
RTL 实现
        ↓
directed TB 验证内部机制
        ↓
ACT4 验证标准架构行为
        ↓
参考模型差分验证长程序和指令组合
        ↓
综合与 STA 验证可实现性
```

完成这条链后，项目能够回答面试中最关键的几类问题：

- 为什么选择这些指令，而没有选择另外一些扩展；
- 多周期乘除法如何与五级流水协同；
- 异常和中断怎样做到精确；
- 如何证明 RTL 不只是能跑几个手写程序；
- 设计综合以后面积、频率和关键路径是什么；
- 如果继续扩展，下一处架构瓶颈在哪里。

### 12.2 `M` 扩展与 Machine Mode 是两件不同的事

这个目标里有两个容易混淆的“M”：

| 名称 | 所属规范 | 含义 |
|---|---|---|
| `RV32IM` 中的 `M` | 非特权 ISA 扩展 | `MUL/DIV/REM` 等整数乘除法指令 |
| Machine Mode / M-mode | 特权架构 | 最高特权级、trap 入口和系统控制状态 |

所以准确的能力描述应该写成：

```text
实现 RV32I 基础整数 ISA、M 乘除法扩展和 Zicsr CSR 指令扩展；
实现仅含 Machine Mode 的最小特权执行环境。
```

不能因为 ISA 字符串中有 `M`，就认为已经实现了 Machine Mode；也不能因为实现了 Machine Mode，就把 ISA 写成 RV32IM。

### 12.3 目标能力边界

#### 12.3.1 明确支持

- `XLEN=32`，小端；
- 32 个整数寄存器；
- 完整 RV32I；
- 完整 RV32M；
- 完整 Zicsr 六条 CSR 指令；
- 单 hart、单发射、顺序执行、五级流水；
- 仅 Machine Mode；
- `MRET` 和 `WFI`；
- Direct 模式的 `mtvec`；
- 精确同步异常；
- Machine software、timer 和 external interrupt；
- 自然对齐的取指、load 和 store；
- 非对齐访问通过精确异常处理；
- 阻塞式、单个在途请求的指令和数据存储接口。

#### 12.3.2 暂不声明

- `C` 压缩指令；
- `A` 原子指令；
- `F/D` 浮点；
- `B` 位操作；
- `V/Zve` 向量；
- `Zifencei`；
- `Zicntr/Zihpm` 计数器扩展；
- U-mode、S-mode、PMP、MMU 和 Linux；
- Cache、一致性和多 hart；
- 调试模式和 trigger module。

`Zifencei` 暂不放入推荐目标，是因为当前系统采用独立指令存储器，CPU 的数据写通路不能修改正在取指的指令存储空间，并且没有 I-Cache。如果以后允许软件加载代码、统一存储器或者增加 I-Cache，就必须重新加入 `FENCE.I` 及相应的一致性语义。

`A` 暂不加入，是因为当前 CPU 核为单 hart，核心验证阶段也没有与 DMA/NPU 并发访问同一一致性内存的需求。它应由未来 CPU-NPU 系统的共享内存和同步需求决定，而不是为了让 ISA 字符串更长而增加。

#### 12.3.3 合规声明边界

`RV32IM_Zicsr` 是可以精确声明和测试的非特权 ISA 集合；“最小 Machine Mode”则是本项目的工程范围，不是官方已经定义好的 Profile 名称。对外描述时还要同时给出：

- 采用的 Privileged Architecture 版本；
- 只实现 M-mode，还是还实现 U/S-mode；
- CSR 清单及每个字段的 WARL/WPRI/只读零行为；
- interrupt source、priority 和 `mtvec` 模式；
- 是否有 PMP、计数器和非对齐访问支持。

因此，在全部适用 privileged tests 通过前，推荐表述是“实现 machine-mode-only 的 CSR、精确 trap 和中断执行环境”，而不是笼统宣称“完整支持全部 RISC-V 特权架构”。

### 12.4 完整 RV32I 的收口

当前 37 条普通 RV32I 指令已经覆盖主要数据通路。收口到完整 RV32I 需要补上：

| 能力 | 目标行为 | 对流水线的影响 |
|---|---|---|
| `FENCE` | 作为合法指令执行并退休 | 当前顺序阻塞访存下可以实现为 no-op，但必须接受规范要求的合法编码 |
| `ECALL` | 产生 Machine environment call 异常 | 进入统一 trap 提交流程，`mcause=11` |
| `EBREAK` | 产生 breakpoint 异常 | 不产生普通写回，进入 trap 提交流程 |
| 非法指令 | 产生 illegal-instruction 异常 | `mtval` 建议记录非法指令字 |
| 指令地址非对齐 | 对错误跳转目标产生异常 | 错误跳转不能先改变可见 PC 或产生年轻指令副作用 |
| load/store 非对齐 | 不发起部分存储访问，直接异常 | store byte strobe 必须保持为零 |

`FENCE` 能做 no-op 的原因不是它“不重要”，而是当前微架构满足：

- 顺序发射和退休；
- 访存阻塞；
- 最多一个在途数据请求；
- 没有 store buffer；
- 没有乱序 Cache 或一致性流量。

一旦这些条件变化，就必须重新审视 `FENCE` 的实现。

### 12.5 RV32M 的微架构方案

#### 12.5.1 为什么 M 适合作为展示扩展

M 扩展既有软件实用价值，又会引入当前流水尚未处理的一类问题：一条指令需要多个周期才能完成。因此它能自然展示：

- 多周期执行握手；
- pipeline hold；
- older instruction drain；
- forwarding 与结果提交；
- flush/trap 对长延迟单元的取消；
- 除零和有符号溢出等边界语义。

#### 12.5.2 推荐实现

推荐使用迭代式乘除单元，而不是第一版就使用单周期组合乘法器和除法器：

```text
EX 发起 MDU 请求
      │
      ▼
start ──> busy ──> done/result
            │
            └── hold IF/ID 和 ID/EX

older MEM/WB 指令继续排空
M 指令完成后进入 EX/MEM
随后复用普通 WB 和 forwarding 路径
```

接口至少要有：

```text
request_valid / request_ready
operation
operand_a / operand_b
response_valid / response_result
cancel 或等价的 flush 处理
```

必须定义的 corner case 包括：

- `MULH/MULHSU/MULHU` 的符号组合；
- `DIV/DIVU/REM/REMU` 的有符号和无符号语义；
- 除数为零；
- `0x80000000 / -1` 的有符号溢出；
- 目标寄存器为 `x0`；
- MDU busy 时遇到 DMem backpressure；
- M 指令完成同周期发生 trap/redirect 时的提交优先级；
- 请求只能启动一次，结果只能提交一次。

迭代式 MDU 是“多周期操作”，但不代表 STA 中要随意声明一条 multicycle path。只要每次迭代之间有寄存器，单次迭代的组合逻辑仍应满足一个时钟周期；操作总延迟由 ready/valid 协议表达。

### 12.6 Zicsr 与最小 Machine Mode

#### 12.6.1 最小 CSR 集合

推荐实现以下 CSR：

| CSR | 最小职责 |
|---|---|
| `mstatus` | 实现 `MIE、MPIE、MPP` 等本目标实际需要的字段；未实现字段按规范只读零或合法化 |
| `misa` | 只读报告 RV32、I 和 M；Zicsr 不通过单独的 `misa` 字母位表示 |
| `mie` | Machine software/timer/external interrupt enable |
| `mip` | Machine software/timer/external interrupt pending |
| `mtvec` | trap 入口地址，第一版只支持 Direct 模式 |
| `mscratch` | trap handler 临时保存寄存器 |
| `mepc` | 记录被异常打断的指令或被中断打断处的恢复 PC |
| `mcause` | 记录 exception/interrupt 标志和 cause code |
| `mtval` | 记录坏地址、非法指令字或规范允许的零值 |
| `mhartid` | 单 hart 实现返回 0 |
| `mvendorid/marchid/mimpid` | 可按规范实现为只读标识；没有分配的标识允许采用规范定义的零值 |
| `mcycle/mcycleh` | RV32 下组成 64 位 Machine cycle counter |
| `minstret/minstreth` | RV32 下组成 64 位 Machine instructions-retired counter |

当前 Machine Mode 规范包含 64 位精度的 `mcycle/minstret`，所以推荐目标应实现它们及 RV32 的高半部分。`Zicntr` 还涉及非特权 `cycle/time/instret` shadow CSR 及其可访问性；在这些接口、`time` 来源和权限语义没有实现前，仍不单独声明 Zicntr。其余 `mhpmcounter3～31` 和事件选择器按采用的规范允许实现为只读零，具体行为必须写入 UDB。

#### 12.6.2 CSR 指令的流水行为

Zicsr 的 6 条指令都是对单个 CSR 的原子读改写：

```text
CSRRW   CSRRS   CSRRC
CSRRWI  CSRRSI  CSRRCI
```

需要冻结以下规则：

- CSR 读值何时送入 `rd`；
- CSR 写入在哪一级提交；
- `rd=x0` 是否抑制读副作用；
- `rs1=x0` 或立即数字段为零时，哪些操作不写 CSR；
- 对只读 CSR 写入时产生非法指令异常；
- 对不存在或权限不允许的 CSR 访问产生非法指令异常；
- 连续 CSR 指令之间如何前递或停顿；
- CSR 普通写入和 trap 自动写入同周期冲突时，trap 优先级如何定义。

推荐让 CSR 的架构写入在统一提交点发生，并让 trap 更新具有更高优先级。这样可以避免错误路径 CSR 写入，也便于 retire trace 和参考模型对齐。

### 12.7 精确异常合同

#### 12.7.1 目标同步异常

| cause | 异常 | `mepc` | 建议的 `mtval` |
|---:|---|---|---|
| 0 | instruction address misaligned | 产生错误目标的指令 PC | 错误目标地址 |
| 1 | instruction access fault | 故障取指 PC | 故障取指地址 |
| 2 | illegal instruction | 非法指令 PC | 非法指令字 |
| 3 | breakpoint | `EBREAK` PC | 按采用的规范行为实现 |
| 4 | load address misaligned | load PC | 错误数据地址 |
| 5 | load access fault | load PC | 故障数据地址 |
| 6 | store address misaligned | store PC | 错误数据地址 |
| 7 | store access fault | store PC | 故障数据地址 |
| 11 | environment call from M-mode | `ECALL` PC | 0 |

本项目没有 A 扩展，但特权规范中的 cause 名称可能写作 store/AMO；当前实现只覆盖 store 对应行为。

#### 12.7.2 精确性的定义

对一条发生异常的指令：

1. 它之前的所有 older instruction 正常完成；
2. 它自身不产生普通寄存器、存储器或 CSR 副作用；
3. 它之后的 younger instruction 全部 flush；
4. `mepc/mcause/mtval/mstatus` 在同一个架构事件中更新；
5. PC 重定向到 `mtvec.BASE`；
6. trap handler 执行 `MRET` 后回到软件指定的恢复地址；
7. DMem 等待期间不能重复提交异常、store 或 trap redirect。

五级流水中推荐使用“异常随指令向后携带，在统一提交边界仲裁”的方法。前级可以尽早检测异常，但不能让多个流水级分别直接修改 CSR 和 PC。

#### 12.7.3 建议的提交与仲裁框架

同一周期可能同时出现 memory wait、同步异常、分支 redirect 和中断请求。这里不能只写成一条简单的组合优先级，因为分支成功完成后的目标 PC 本身就是“下一条架构 PC”，中断不应该把这个结果丢掉。

推荐分成两步处理：

1. **先判断当前最老指令能否完成**：如果 older load/store 仍在等待响应，或当前 MDU 操作尚未完成，则保持相关流水状态；任何 younger 分支、异常和中断都不能越过它产生架构效果。
2. **再计算完成后的架构 next PC**：
   - 当前最老指令发生同步异常时，该指令不完成，next PC 为 trap vector；
   - 当前最老指令是正常完成的 branch/jump 时，先得到它的 taken/fall-through next PC；
   - 若随后在这个指令边界接受中断，`mepc` 应保存上述 next PC，再跳转到 trap vector；
   - 没有 trap 和 redirect 时才顺序取指。

可以把它理解为：

```text
older operation ready?
    ├── no  -> hold，屏蔽所有 younger 架构事件
    └── yes -> 完成当前指令并计算 architectural_next_pc
                  ├── 当前指令同步异常 -> 不提交它，进入 trap
                  ├── 接受边界中断     -> mepc=architectural_next_pc，进入 trap
                  └── 无 trap           -> PC=architectural_next_pc
```

这样才能同时保证程序控制流正确、异常精确，并使 `mepc` 在分支完成与中断同时到达时具有可解释的值。

### 12.8 精确中断合同

#### 12.8.1 最小中断源

推荐给 core 提供三个电平型 pending 输入：

```text
machine_software_interrupt
machine_timer_interrupt
machine_external_interrupt
```

它们映射到 `mip` 中对应 pending 位，并由 `mie` 和 `mstatus.MIE` 控制是否可接受。第一版只实现 `mtvec` Direct 模式，所有异常和中断进入同一个 trap 入口，由软件读取 `mcause` 分派。

#### 12.8.2 中断为何也必须精确

中断是异步到达的，但必须在指令边界被观察：

- 已提交指令不能撤销；
- 尚未提交的指令不能泄漏副作用；
- `mepc` 必须指向返回后应继续执行的位置；
- `mcause` 最高位标记 interrupt，低位记录对应 cause code；
- trap 入口自动保存并关闭全局中断使能；
- `MRET` 恢复先前的中断使能状态；
- 当流水因 load/store 或 MDU 长操作阻塞时，中断接受时机必须唯一且可解释。

为了降低首版复杂度，可以规定：正在等待不可取消的 DMem 请求或 MDU 操作时先完成当前指令，再在下一个提交边界接受中断。这个策略增加中断延迟，但仍可保持精确性。

### 12.9 四层验证闭环

#### 12.9.1 第一层：directed TB 验证微架构机制

directed TB 负责验证 ACT4 看不到的内部交互。至少增加以下测试组：

| 测试组 | 重点场景 |
|---|---|
| 完整 RV32I | `FENCE、ECALL、EBREAK` 及合法/非法编码 |
| M 扩展 | 8 条指令、符号组合、除零、溢出、多周期 hold |
| CSR | 6 条 Zicsr 指令、读零/写抑制、只读和非法地址 |
| 同步异常 | 每类 cause、`mepc/mcause/mtval`、无错误副作用 |
| 中断 | 三类 pending、mask、全局使能、MRET、同时到达 |
| 流水交互 | trap 对 forwarding、load-use、branch flush 的影响 |
| 长延迟交互 | MDU busy、DMem wait、interrupt 和 redirect 组合 |
| 单次提交 | store、CSR、trap、M 结果均不能重复提交 |

关键断言可以围绕以下不变量建立：

- `x0` 永远为零；
- invalid pipeline entry 不产生副作用；
- faulting/younger instruction 不写寄存器、存储器和 CSR；
- 每个接受的 DMem/MDU 请求只产生一次响应和退休；
- trap take 同周期的 PC 和 CSR 更新保持一致；
- retire PC 顺序只会因已提交的 redirect/trap 改变。

#### 12.9.2 第二层：ACT4 验证标准架构行为

ACT4 配置应准确声明：

- `I`；
- `M`；
- `Zicsr`；
- Machine Mode 和采用的特权规范版本；
- 不支持 misaligned load/store，而是产生异常；
- 不声明 `A/C/F/D/B/V/Zifencei/Zicntr`；
- CSR 是否存在、字段是否可写以及中断源配置。

运行范围至少包括：

- `I` test plan；
- `M` test plan；
- `Zicsr` test plan；
- 与当前 Machine Mode、异常和中断配置相匹配的 privileged tests。

通过标准必须是：所有适用于当前 UDB 配置的测试都通过。调试阶段可以单独运行某个 ELF，但最终报告不能通过删除失败测试形成“全通过”。

#### 12.9.3 第三层：参考模型差分验证组合行为

ACT4 以单项规范规则为中心，差分验证则适合发现长程序中复杂指令组合的问题。推荐锁定一个参考模型版本：

- ACT4 已经使用 Sail 生成期望结果；
- 动态差分可以选择 Spike 或 Sail；
- 如果选择 Spike，可以形成与 ACT4/Sail 不同实现的交叉验证，但必须锁定 ISA、特权版本和配置。

DUT retire trace 建议至少包含：

```text
retire_valid
retire_pc
retire_instruction
retire_rd_write / retire_rd / retire_rd_data
retire_memory_address / write_data / byte_strobe
retire_trap / cause / target_pc
必要的 CSR 架构更新
```

差分可以分三步推进：

1. 先比较无异常、无中断的 RV32I/M 随机程序；
2. 再加入 CSR 和同步异常；
3. 异步中断单独验证，因为 DUT 与参考模型必须在相同架构边界注入中断，否则会出现合法但不同步的 trap 时机。

#### 12.9.4 第四层：综合与 STA 验证物理可实现性

综合和 STA 回答的是“这份 RTL 能否在目标工艺和时钟约束下实现”，而不是重复功能仿真。

综合至少记录：

- 工具、工艺库、corner 和约束版本；
- 核心总面积、组合面积、时序单元面积；
- 寄存器堆、MDU、CSR/trap 控制的面积占比；
- 是否存在 latch、多驱动、未解析引用和未约束端口；
- top-N 面积模块和关键算术单元映射结果。

STA 至少记录：

- 时钟周期、uncertainty、input/output delay；
- setup/hold 是否收敛；
- 最差路径起点、终点和逻辑组成；
- forwarding/ALU、branch redirect、LSU 地址、CSR/trap redirect、MDU 单次迭代中谁成为关键路径；
- false path 和 multicycle path 的每一条例外为什么成立。

TB 的 `$readmemh` 存储模型不能直接作为 ASIC SRAM。综合边界应把指令/数据存储视为外部接口或 SRAM macro，并对接口路径给出明确约束。

### 12.10 分阶段实施顺序

推荐遵循以下顺序，每个阶段都保持回归可运行：

| 阶段 | 主要工作 | 阶段出口 |
|---|---|---|
| A. 冻结合同 | ISA 字符串、特权版本、CSR、cause、优先级、地址对齐 | 文档中不存在“实现时再决定”的关键架构语义 |
| B. ACT4 runner | ELF/HEX、链接地址、PASS/FAIL、timeout、批处理 | 当前 37 条子集可以通过选定 ELF 做 bring-up |
| C. 完整 RV32I | FENCE、ECALL、EBREAK、非法/非对齐异常 | 适用的 ACT4 I 全部通过 |
| D. Zicsr + M-mode | CSR 文件、trap commit、MRET、Direct mtvec | CSR 和同步异常 directed/ACT4 通过 |
| E. RV32M | 迭代 MDU、多周期 hold、corner cases | ACT4 M 和 MDU directed tests 通过 |
| F. 中断 | MSIP/MTIP/MEIP、mie/mip/mstatus、WFI | 精确中断和 MRET 回归通过 |
| G. 差分 | 随机程序、退休流、异常和 CSR 对比 | 约定回归规模下无 mismatch |
| H. ASIC 闭环 | lint、综合、STA、必要的形式等价 | 报告可复现、时序约束无遗漏 |

这个顺序与项目版本规划一致：v0.2 收口完整 RV32I 与精确同步异常，v0.3 完成 Zicsr 与最小 Machine Mode，v0.4 加入 RV32M，v0.5 再加入精确 Machine interrupt，之后完成官方 ISA 回归、差分和 ASIC 前端闭环。

### 12.11 最终完成标准

只有同时满足以下条件，才把推荐展示目标标记为完成：

- ISA/UDB 明确声明 `RV32IM_Zicsr`，未实现扩展没有误报；
- 完整 RV32I、RV32M 和 Zicsr 的适用 ACT4 测试全部通过；
- 最小 Machine Mode CSR、精确异常和三类 Machine interrupt 有 directed test；
- trap、store、CSR 和 MDU 结果不存在重复或错误路径副作用；
- 参考模型差分达到预先约定的程序数、指令数和随机种子规模；
- RTL lint 无未解释的高严重度问题；
- 综合成功且所有时序路径均被正确约束；
- 目标时钟下 setup/hold 结果和关键路径有记录；
- 工具版本、命令、配置、日志和结果能够复现；
- 文档能说明已知限制以及为什么暂不实现 C/A/S-mode/MMU/V。

### 12.12 面试中的项目叙述

推荐用下面的逻辑讲述项目，而不是按 RTL 文件列表介绍：

1. **需求**：在有限时间内独立完成一颗可综合、可验证的处理器核，重点学习完整 IC 前端流程；
2. **范围选择**：选择 RV32IM_Zicsr 和最小 Machine Mode，覆盖编译器整数目标、多周期单元和系统控制，但控制 Linux/MMU 等范围；
3. **微架构**：五级顺序流水、前递、stall、flush、阻塞式存储、多周期 MDU、统一 trap commit；
4. **关键难点**：memory wait、分支、MDU 和 trap/interrupt 同时出现时如何保证精确提交；
5. **验证证据**：directed TB 证明内部机制，ACT4 证明标准 ISA，差分验证复杂组合；
6. **实现证据**：lint、综合和 STA 证明 RTL 可实现，并用面积和关键路径解释设计取舍；
7. **边界意识**：明确 C/A/MMU/V 和 NPU 是后续由需求驱动的扩展，不把未实现能力包装为当前成果。

这样展示的重点是：能够定义处理器、实现处理器、验证处理器，并把它送入真实的 ASIC 前端分析流程。

## 13. 分层总结

| 层级 | 软件目标 | 一般指令/扩展 | 关键系统能力 | 本项目关系 |
|---|---|---|---|---|
| L0 | 教学汇编 | RV32I 常用子集 | 流水和存储接口 | 当前已完成主体 |
| L1 | 标准裸机整数程序 | 完整 RV32I | 精确同步异常边界 | 当前最优先目标 |
| L2 | 实用 MCU/裸机 | RV32IM[C] + Zicsr/Zifencei | 最小 M-mode | 推荐展示目标 |
| L3 | RTOS/健壮控制 | L2，A/F 按需求 | 中断、WFI、PMP、平台定时器 | 可作为后续增强 |
| L4 | 32 位 Linux | 常见 RV32IMAC + Zicsr/Zifencei | M/S/U、Sv32、MMU、SBI、平台 | 不属于近期范围 |
| L5 | 现代 64 位应用处理器 | RVA23/RVB23 大型 mandatory 集合 | Sv39、虚拟化、Cache 管理等 | 只作上界参考 |

## 14. 官方资料

- [RISC-V Ratified Specifications Library](https://docs.riscv.org/reference/home/index.html)
- [RV32I Base Integer Instruction Set](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)
- [RV32E/RV64E Base Integer Instruction Sets](https://docs.riscv.org/reference/isa/unpriv/rv32e.html)
- [M Extension](https://docs.riscv.org/reference/isa/unpriv/m-st-ext.html)
- [A Extension](https://docs.riscv.org/reference/isa/unpriv/a-st-ext.html)
- [Zicsr Extension](https://docs.riscv.org/reference/isa/unpriv/zicsr.html)
- [V and Zve Vector Extensions](https://docs.riscv.org/reference/isa/unpriv/v-st-ext)
- [RISC-V Privileged Architecture](https://docs.riscv.org/reference/isa/priv/priv-intro.html)
- [Machine-Level ISA](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
- [Supervisor ISA and Sv32](https://docs.riscv.org/reference/isa/priv/supervisor.html)
- [RVI20 Profiles](https://docs.riscv.org/reference/rva20-rvi20-rva22/rvi20.html)
- [RVA23 Profiles](https://docs.riscv.org/reference/rva23/rva23-profiles.html)
- [RVB23 Profiles](https://docs.riscv.org/reference/rvb23/v1.0/rvb23.html)
- [RISC-V Architectural Certification Tests / ACT4](https://github.com/riscv/riscv-arch-test#getting-started)
- [ACT4 Test Plans](https://github.com/riscv/riscv-arch-test/tree/act4/testplans)
