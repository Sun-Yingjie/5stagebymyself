# AI 异构计算系统项目级需求基线

> 文档状态：v0.2 基线
> 文档性质：项目级最高优先级需求与交付依据
> 目标场景：边缘端 INT8 AI 推理
> 目标用途：2027 年 4 月开始的 AI 硬件相关实习面试
> 核心原则：先完整做出一版并走通流程，在过程中学习；性能优化和设计空间探索服从于按期完成。

## 0. 文档优先级与解释规则

本文补充并修正现有文档尚未定义的项目目标、AI 工作负载、系统边界和交付时限。文档优先级为：

1. `06_ai_system_project_requirements.md`；
2. `07_system_memory_interconnect_and_boot.md` 在启动、存储和互联范围内作为本文的详细下位规格；若局部细节冲突，以更新后的 `07` 为准；
3. `00_processor_architecture.md` 至 `05_rtl_implementation_order.md`；
4. RTL、testbench、脚本和阶段性记录中的局部说明。

CPU 内部的五级流水、valid、冒险、请求/响应、退休和验证规则继续沿用 `00`～`05`。本文明确覆盖以下旧路线：

- NPU 是项目必要交付物，不再是完成全部 CPU 扩展后的无限期后续工作；
- 不要求先完成 CPU 的 CSR、中断、RV32M、Cache 或 Linux 再开始 NPU；
- 首版 NPU 主控制方式采用 MMIO + 轮询，不要求 custom instruction；
- 旧文档中的 `cp_req/cp_rsp` 保留为可选实验位置，首版系统将 `COPROC_ENABLE` 设为 0；
- CPU 的完整 Formality、PrimeTime 和门级闭环放在 CPU—NPU 系统完成后统一进行；
- 首版不把多种 PE、数据流和 buffer 配置的全面 tradeoff 作为完成门槛。

任何新增功能如果威胁端到端闭环和交付日期，应移入首版之后。

## 1. 项目的真实需求

### 1.1 第一目标：形成可运行、可验证、可讲解的完整版本

项目第一使用者是作者本人，第一交付场景是 2027 年 4 月开始的实习面试。优先级为：

1. 能按期完成；
2. 功能正确；
3. 作者能够解释每个关键模块和状态转换；
4. 从软件参考模型到 RTL、系统集成和 ASIC 前端流程可以复现；
5. 有真实周期、面积、时序和波形证据；
6. 前五项完成后再做性能和面积优化。

项目计划在 **2027 年 3 月 20 日前完成可面试版本**，为 4 月预留修复、整理和演练时间。

### 1.2 第二目标：通过实践学习完整硬件开发流程

项目必须让作者实际经历并能够解释：

- 从需求到系统架构和模块接口；
- 从 SystemVerilog RTL 到单元测试和系统 testbench；
- 五级流水中的 stall、flush、forwarding 和访存等待；
- INT8 乘加、INT32 累加、requantization、舍入和饱和；
- NPU 地址生成、片上数据搬运和结果写回；
- CPU 使用 MMIO 启动 NPU并轮询状态；
- AXI4-Lite 控制面和 AXI4 数据面的正确握手；
- 软件整数参考模型与 RTL 的位精确比对；
- lint、综合、等价验证、STA 和门级 smoke；
- 如何阅读关键波形、面积构成和关键路径。

项目不以堆叠功能数量为目标。关键 RTL、主要 testbench、设计决定和结果解释应由作者理解并能够独立复述。

## 2. 最终系统定义

本项目设计并验证一个面向边缘端 INT8 推理的可综合异构计算系统：

- 五级流水 RV32I 核作为控制处理器；
- ITCM 保存 CPU 程序，DTCM 保存 CPU 本地数据；
- Tensor Scratchpad 保存输入、权重、量化参数、中间激活和输出；
- CPU 通过 AXI4-Lite MMIO 配置 NPU并轮询 `BUSY/DONE/ERROR`；
- NPU 通过受限 AXI4 Memory-Mapped Master 访问 Tensor Scratchpad；
- NPU 内部 Data Mover 承担专用数据搬运，不另建通用 DMA；
- CPU 与 NPU 分时使用 Tensor Scratchpad，首版不实现 Cache coherence；
- 软件整数参考模型提供位精确 golden result；
- 最终系统完成 RTL 仿真和 ASIC 前端流程。

本项目可以表述为：

> 一套由自研五级流水 RV32I 控制、通过 MMIO 配置、能够自主访问片上 Tensor Scratchpad 的 INT8 边缘推理加速系统。

它不是通用高性能 CPU、通用 NPU 产品、完整 SoC 平台或追求极限 PPA 的量产芯片。

## 3. 首版工作负载

### 3.1 必选端到端工作负载

首版使用 **INT8 LeNet-5 风格网络在 MNIST 上的 batch=1 推理** 作为端到端验收工作负载：

```text
input: 1 x 28 x 28 x 1

Conv2D: 1 -> 6, kernel 5 x 5, stride 1
ReLU
AveragePool: 2 x 2, stride 2

Conv2D: 6 -> 16, kernel 5 x 5, stride 1
ReLU
AveragePool: 2 x 2, stride 2

Flatten
FullyConnected: 256 -> 120
ReLU
FullyConnected: 120 -> 84
ReLU
FullyConnected: 84 -> 10
Argmax
```

选择小型完整网络是为了保证个人能够在截止日期前完成模型导出、NPU、CPU 软件、存储、AXI、验证和 ASIC 闭环。ResNet-20 或 MobileNet 不作为首版完成条件。

### 3.2 算子分工

| 算子 | 首版执行位置 |
|---|---|
| Conv2D | NPU |
| FullyConnected | NPU，复用 dot-product datapath |
| Bias | NPU，在 INT32 累加域加入 |
| Requantization / saturation | NPU |
| ReLU | NPU，允许与 requantization 融合 |
| AveragePool | CPU |
| Flatten | 地址解释，不进行物理复制 |
| Argmax | CPU |

如果 AveragePool 的 CPU 实现成为明显瓶颈，可以在端到端版本完成后加入 NPU pooling。

### 3.3 模型事实源

首版必须冻结：

- 网络拓扑；
- checkpoint 文件和哈希；
- MNIST 数据划分和预处理；
- FP32 准确率和 INT8 准确率；
- 每层 tensor shape；
- 每层权重、bias 和量化参数；
- 每层整数 golden output；
- Tensor Scratchpad 地址和 byte length。

硬件调试不得在不同实验中静默更换 checkpoint 或量化参数。

## 4. 数值规格

| 需求编号 | 要求 |
|---|---|
| NUM-001 | 输入激活和权重使用 signed INT8。 |
| NUM-002 | 首版使用对称量化，INT8 zero point 固定为 0。 |
| NUM-003 | 激活和权重首版使用 per-tensor scale；per-output-channel 属于后续扩展。 |
| NUM-004 | 乘法结果和 dot-product 累加器使用 signed INT32。 |
| NUM-005 | bias 使用 signed INT32，并在 INT32 域加入。 |
| NUM-006 | requantization 使用整数 multiplier 和右移量。 |
| NUM-007 | 舍入规则为 round-to-nearest、ties-away-from-zero。 |
| NUM-008 | 结果显式饱和到 signed INT8 的 `[-128, 127]`。 |
| NUM-009 | ReLU 在量化域把负值截断为 0。 |

软件整数参考模型是数值语义的事实源。RTL 必须逐元素完全一致，不能用浮点误差阈值掩盖整数实现错误。

## 5. 首版系统边界

### 5.1 CPU

- 实现旧文档 v0.1 范围内的五级流水 RV32I；
- 能够运行裸机程序；
- 通过 `imem_req/rsp` 访问 ITCM；
- 通过 `dmem_req/rsp` 访问 DTCM、Tensor Scratchpad 和 NPU MMIO；
- 使用普通 load/store 控制 NPU，不修改 ISA；
- 首版不要求 CSR、中断、RV32M、Cache、MMU 或 Linux。

### 5.2 NPU

- 至少支持 INT8 Conv2D 和 FullyConnected；
- 支持 bias、requantization、saturation 和 ReLU；
- 一次只执行一个任务；
- 接受 START 后自主读取 Tensor Scratchpad、计算并写回；
- 提供 `BUSY`、`DONE`、`ERROR` 和周期计数；
- 首版不支持命令队列、并发任务、中断和抢占。

### 5.3 存储和互联

- ITCM、DTCM 和 Tensor Scratchpad 首版均为无 Cache 的 SRAM-based memory；
- CPU 私有 ITCM/DTCM 使用简单 valid/ready 接口；
- NPU 控制面使用 AXI4-Lite；
- NPU 数据面使用受限 AXI4 burst；
- CPU 与 NPU 分时访问 Tensor Scratchpad；
- 启动阶段通过 preload 或 Loader 初始化三块 SRAM；
- 详细拓扑和协议由 `07_system_memory_interconnect_and_boot.md` 定义。

## 6. 性能和 PPA 的角色

首版必须测量和报告：

- 整网与逐层周期；
- NPU 计算周期和存储等待周期；
- 有效 MAC 数和利用率；
- 目标频率下的推理延迟；
- DC 标准单元面积、寄存器数量和关键路径；
- ITCM、DTCM 和 Tensor Scratchpad 容量；
- CPU-only 软件基线的计时口径；
- 已知性能瓶颈。

首版不设置强制 TOPS、TOPS/W、绝对面积或端到端毫秒门槛。目标时钟暂定为 100 MHz，用于建立真实 SDC、综合和 STA 约束，不要求继续追求最大 Fmax。

首版只要求实现一套稳定微架构。可以参数化 PE 数量和 buffer 容量，但不强制完成多种配置、两种数据流或 Pareto sweep。面试中需要解释选择及其代价，但不要求为每个选择实现对照组。

## 7. 功能完成标准

必须真实完成以下路径：

```text
MNIST image
  -> frozen INT8 software reference
  -> generate itcm/dtcm/tensor images
  -> initialize ITCM/DTCM/Tensor Scratchpad
  -> RV32I bare-metal program
  -> AXI4-Lite MMIO START
  -> NPU AXI4 reads
  -> INT8 compute
  -> NPU AXI4 writes
  -> AXI4-Lite STATUS polling
  -> CPU pooling / argmax
  -> final class
  -> compare with integer golden result
```

| 需求编号 | 要求 |
|---|---|
| FUNC-001 | RV32I 核能够运行启动 NPU 的裸机程序。 |
| FUNC-002 | CPU 必须通过真实 MMIO 寄存器启动 NPU，最终验收不得由 testbench 绕过 CPU 直接启动。 |
| FUNC-003 | Conv2D 和 FullyConnected 输出与整数参考模型逐元素一致。 |
| FUNC-004 | 至少一个 MNIST 输入完成整网推理并得到相同类别。 |
| FUNC-005 | 固定小型测试集完成回归并报告 RTL 与参考模型一致率。 |
| FUNC-006 | reset、backpressure、非法地址和错误响应不产生重复请求或错误存储副作用。 |

## 8. 验证和 ASIC 流程

### 8.1 验证层次

- CPU 叶子模块和核心级定向测试；
- INT8 multiplier、adder tree、accumulator、requantization、saturation 和 ReLU 单元测试；
- NPU 地址生成、buffer 和 Data Mover 测试；
- AXI4-Lite 五种相对握手顺序和 backpressure；
- AXI4 read/write burst、LAST、RESP 和 4 KiB 边界；
- 单层 Conv2D/FC 随机小张量比对；
- CPU—NPU 整网系统 smoke；
- 固定 seed、命令行和 PASS/FAIL 日志；
- 关键握手、所有权和副作用断言。

### 8.2 ASIC 前端流程

最终稳定配置按以下顺序走通：

1. VCS RTL 回归；
2. SpyGlass lint；
3. Design Compiler 综合；
4. Formality RTL—综合网表等价验证；
5. PrimeTime 布局前 STA；
6. 代表性零延迟门级 smoke；条件允许时增加 SDF smoke。

主目标工艺继续使用 SMIC 28nm。没有 P&R 和寄生参数时，不把结果称为 post-layout signoff。

如果商业工具因许可不可用，必须记录未完成项和替代验证，不能把未执行流程写成已经完成。

## 9. 时间计划

### M0：CPU 基线，截止 2026-08-31

- 完成 IDU、EXU、IFU、LSU 和 `rv32_core`；
- RV32I 指令、冒险、分支和访存测试通过；
- 能运行最小裸机程序；
- 完成一次基础综合。

### M1：软件事实源与系统规格，截止 2026-09-30

- 冻结 LeNet-5 checkpoint 和量化规则；
- 完成整数参考模型和 golden vectors；
- 完成 `07` 存储、Loader、MMIO 和 AXI 规格；
- 冻结 NPU descriptor 和 Tensor 地址布局。

### M2：NPU 独立功能，截止 2026-11-30

- 算术、requantization 和地址生成单测通过；
- Conv2D/FC 小张量比对通过；
- 至少一个完整网络层与 golden 一致。

### M3：MMIO、AXI 和存储集成，截止 2026-12-31

- CPU 可以访问 NPU AXI4-Lite 寄存器；
- NPU 可以通过 AXI4 访问 Tensor Scratchpad；
- 所有权切换和 backpressure 测试通过；
- CPU 可以完成一个 NPU 层任务。

### M4：端到端推理，截止 2027-01-31

- 一张 MNIST 图片完成整网推理；
- 最终类别与整数参考模型一致；
- 固定小型数据集回归通过；
- 保存关键波形和周期统计。

### M5：ASIC 前端流程，截止 2027-02-28

- VCS、SpyGlass、DC、Formality、PT 和代表性门级 smoke；
- 保存面积、时序、关键路径和已知限制。

### M6：面试交付，截止 2027-03-20

- 一键回归和工具脚本；
- README、架构图、结果报告和简历描述；
- 5 分钟、15 分钟和深挖版项目讲解；
- 每个关键决定的“需求—选择—代价—下一步”说明。

2027 年 3 月 21 日至 4 月只作为缓冲期，不规划新的必选功能。

## 10. 当前明确不做的内容

- ResNet-20、MobileNet、Transformer 或通用模型支持；
- 训练、反向传播和浮点硬件；
- INT4、FP16、BF16 或混合精度；
- 强制实现大规模 systolic array；
- 强制实现多 PE 配置、多数据流或完整 tradeoff sweep；
- custom instruction 作为首版 NPU 主控制接口；
- NPU 中断、命令队列、抢占和多任务；
- 独立通用 DMA、AXI4-Stream、外部 DRAM 和完整 AXI crossbar；
- CPU Cache、MMU、Linux、多核和一致性；
- 布局布线、寄生参数提取和 tape-out；
- 在没有可靠功耗 flow 时宣称具体 TOPS/W；
- 为增加简历功能数量而加入无法按期验证的模块。

## 11. 需求变更纪律

以下变化属于项目级范围变更：

- 更换必选网络；
- 增加必选算子；
- 改为 custom instruction 或异步中断控制；
- 增加外部 DRAM、独立 DMA 或完整 AXI interconnect；
- 要求多配置 tradeoff；
- 修改 2027 年 3 月 20 日交付日期；
- 在 M4 前加入与端到端推理无关的 CPU 功能。

范围变更必须说明对时间、RTL、验证和 ASIC 流程的影响。任何新功能如果威胁 M4，应移入首版之后。

## 12. 最终完成定义

项目只有在以下证据同时存在时才算完成：

- 可运行的五级流水 RV32I RTL；
- 可运行的 INT8 NPU RTL；
- CPU 通过 AXI4-Lite MMIO 启动并轮询 NPU；
- NPU 通过 AXI4 访问 Tensor Scratchpad；
- ITCM、DTCM、Tensor Scratchpad 和 Loader/preload 方案；
- 固定 INT8 软件参考模型；
- CPU 裸机程序驱动的端到端推理；
- 单元、层级和系统级回归；
- 可讲解的关键波形；
- 可重复的 lint、综合、等价和 STA 结果；
- 面积、周期、Fmax 和已知限制报告；
- 面向面试的 README、架构图和项目总结。

首版完成后的推荐简历表述为：

> 独立设计并验证一套面向边缘 INT8 推理的 RISC-V/NPU 异构计算原型：实现五级流水 RV32I 控制核、AXI4-Lite MMIO 控制、AXI4 NPU 数据主口、ITCM/DTCM/Tensor Scratchpad 存储层次和位精确软件参考模型，完成裸机端到端推理及 RTL 仿真、lint、综合、等价验证和布局前 STA 闭环。

表述中的每一项都必须有仓库中的 RTL、测试、脚本、日志、波形或报告支撑。
