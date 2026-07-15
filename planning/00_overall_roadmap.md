# AI 硬件项目整体路线

> 文档状态：v0.1 方向性规划
> 目标用途：2027 年 4 月开始的 AI 硬件相关实习面试
> 面试版本建议冻结日期：2027 年 3 月 20 日

## 1. 总体策略

整体目标不是在一个项目中同时完成 CPU、NPU、SoC、AMBA 和完整模型，而是形成一组前后衔接、各自可以独立验收的作品：

```text
P0  完整五级流水 RV32I CPU
             |
             v
P1  独立 INT8 NPU
             |
             v
P2  CPU—NPU 最小异构系统
             |
             v
P3  AMBA 接口与系统增强
```

每一级都必须有自己的 RTL、testbench、回归、波形、综合结果和项目说明。后一级没有完成，不否定前一级已经形成的作品。

## 2. P0：当前项目——完整五级流水 CPU

### 2.1 项目定位

当前项目只实现并验证五级流水 RISC-V 处理器核。范围和完成标准以 `docs/00`～`05` 为准。

当前主线包括：

- RV32I 指令执行；
- IF/ID/EX/MEM/WB 五级流水；
- valid、stall、flush、forwarding 和 load-use；
- 指令/数据请求响应接口和可变访存等待；
- 定向测试、官方架构测试和参考模型比对；
- VCS、SpyGlass、DC、Formality、PrimeTime 和代表性门级 smoke。

### 2.2 当前不进入实现主线

- NPU 数据通路；
- Tensor Scratchpad；
- CPU—NPU 系统集成；
- APB、AHB-Lite、AXI4-Lite 或 AXI4 interconnect；
- 通用 DMA、Cache、MMU、Linux 和外部 DRAM。

CPU 顶层可以保留未来扩展位置，但不能让后续项目拖慢 CPU 的验证和 ASIC 前端闭环。

### 2.3 出口条件

只有达到 `docs/04_verification_and_asic_plan.md` 的 CPU 项目完成门禁，才把 P0 视为完成。后续规划不能降低这些门禁。

## 3. P1：独立 NPU 项目

CPU 项目完成或进入稳定维护后，启动独立 NPU 项目。NPU 首先由 testbench 直接驱动，不依赖 CPU。

P1 的核心闭环是：

```text
软件整数参考模型
-> 输入与 golden vectors
-> NPU 配置
-> Tensor memory 行为模型
-> INT8 计算与写回
-> 逐元素位精确比较
-> 综合和关键路径分析
```

NPU 规模、目标算子、数据流和 buffer 组织在 P1 启动时再冻结。当前只确认它面向边缘端 INT8 推理，而不是训练或通用 AI 处理器。

## 4. P2：最小异构系统项目

CPU 和 NPU 分别稳定后，再做系统集成。第一版集成只追求真实闭环：

- CPU 使用普通 load/store 访问 NPU MMIO；
- CPU 写配置和 `START`，轮询 `BUSY/DONE/ERROR`；
- NPU 自主访问 Tensor Scratchpad 并写回结果；
- CPU 检查结果并形成明确 PASS/FAIL；
- ITCM、DTCM 和 Tensor Scratchpad 使用无 Cache 的片上存储模型；
- 控制面和数据面先使用简单 `valid/ready` 接口。

AMBA 不是 P2 第一个闭环的前置条件。

## 5. P3：AMBA 与系统增强

P2 稳定后，再把标准总线作为独立学习与升级内容：

- 控制面候选：APB 或 AXI4-Lite；
- 数据面候选：AHB-Lite 或受限 AXI4；
- 可选 bridge、地址译码、仲裁、burst 和错误响应；
- 根据实测需求再决定 DMA、双缓冲、中断和更复杂存储系统。

AMBA 通过外围 adapter 接入，不让协议状态机侵入 CPU 流水或 NPU 计算核心。

## 6. 优先级与回退策略

| 优先级 | 交付物 | 未完成时的回退 |
|---|---|---|
| 必须 | 完整五级流水 CPU | 不回退，当前项目主目标 |
| 高 | 独立 INT8 NPU | CPU 仍是完整作品 |
| 中 | CPU—NPU 最小异构闭环 | 分别展示 CPU 和 NPU |
| 可选增强 | AMBA、完整网络、更多性能优化 | 使用简单接口的系统版本 |

回退版本必须是真实完成的小闭环，不能用未验证的框图代替实现证据。

## 7. 后续决策顺序

1. 完成当前 CPU RTL、验证和 ASIC 前端闭环；
2. 根据剩余时间和目标岗位确定 NPU 第一个处理对象；
3. 冻结软件整数语义和最小工作负载；
4. 独立完成 NPU 的读—算—写闭环；
5. 使用简单接口集成 CPU、NPU 和 Tensor Scratchpad；
6. 根据系统实测结果选择是否以及使用哪一种 AMBA 协议；
7. 在时间允许时增加更完整模型和性能分析。

任何新增功能都应明确它属于 P0、P1、P2 或 P3，不能把未来规划重新塞回当前 CPU 项目的关键路径。
