# 独立 INT8 NPU 项目规划

> 文档状态：v0.1 候选规划
> 启动条件：当前五级流水 CPU 项目完成或进入稳定维护
> 原则：先证明数值和读—算—写闭环，再决定规模和性能优化。

## 1. 项目定位

该项目计划实现一颗面向边缘端 INT8 推理的可综合 NPU 原型。它首先是一个独立硬件作品，不把 CPU、AMBA 或完整 SoC 作为功能正确性的前置条件。

NPU 项目需要让作者实际经历：

- 工作负载到硬件需求的转换；
- INT8 乘加和 INT32 累加；
- bias、requantization、舍入和饱和；
- 地址生成、片上数据读取和结果写回；
- 控制状态机与 backpressure；
- 软件整数参考模型和 RTL 位精确验证；
- 综合、面积构成和关键路径分析。

## 2. 当前确认与暂不冻结

### 2.1 已确认原则

- 面向推理，不实现训练和反向传播；
- INT8 激活和权重、INT32 累加是首选数值方向；
- 软件整数参考模型是 RTL 数值语义的事实源；
- NPU 可以自主读写 Tensor memory；
- 一次只执行一个任务；
- 第一版不要求命令队列、抢占、多任务或 Cache coherence；
- 内部先使用简单 `valid/ready` 接口。

### 2.2 待决策事项

- 第一个处理对象是 dot-product、Fully Connected、Conv2D 还是其他任务；
- 是否在同一数据通路复用 FC 和 Conv2D；
- PE/MAC 数量和并行维度；
- output-stationary、weight-stationary 或其他数据流；
- local buffer、line buffer 和 accumulator buffer 的组织；
- Tensor memory 的容量、bank 和端口；
- 量化使用对称/非对称、per-tensor/per-channel；
- 第一个端到端模型和数据集；
- 是否需要 burst、双缓冲或专用 DMA。

这些问题必须由目标 workload、实现成本和时间共同决定，不能仅凭“更像商业 NPU”提前冻结。

## 3. 建议的递增实现顺序

### N0：软件事实源

- 定义输入、权重、bias、累加和输出的数据类型；
- 定义 requantization、舍入、溢出和饱和；
- 建立小型确定性 vector 和随机测试生成器；
- 记录 tensor shape、layout 和地址含义。

### N1：算术单元

- INT8 multiplier；
- INT32 accumulator 或小型 dot-product；
- bias；
- requantization；
- saturation；
- 可选 ReLU。

每个算术模块先做边界值和随机位精确测试。

### N2：最小计算引擎

- 配置寄存器或 testbench 配置端口；
- `START/BUSY/DONE/ERROR`；
- 一个小规模处理任务；
- 地址生成；
- 完整读—算—写状态机。

### N3：独立子系统闭环

- 行为级 Tensor memory；
- 读写 backpressure；
- 非法地址和错误响应；
- 与软件 golden 逐元素比较；
- 子系统综合、面积和时序报告。

### N4：按证据增强

只有 N3 稳定后，再考虑：

- 扩大 MAC 并行度；
- 增加 Conv2D 或更多算子；
- 增加 local buffer 和双缓冲；
- 计算与搬运重叠；
- 更完整的网络工作负载。

## 4. 候选内部接口

控制接口不绑定具体外部总线，可先抽象为：

```text
cfg_req_valid
cfg_req_ready
cfg_req_write
cfg_req_addr
cfg_req_wdata
cfg_req_wstrb

cfg_rsp_valid
cfg_rsp_ready
cfg_rsp_rdata
cfg_rsp_error
```

数据接口可先抽象为单笔请求/响应：

```text
mem_req_valid
mem_req_ready
mem_req_write
mem_req_addr
mem_req_wdata
mem_req_wstrb

mem_rsp_valid
mem_rsp_ready
mem_rsp_rdata
mem_rsp_error
```

APB、AHB-Lite 或 AXI adapter 以后连接在这些边界之外。计算核心不直接处理标准总线的全部通道状态。

## 5. 独立项目完成证据

独立 NPU 至少需要：

- 冻结的软件整数参考模型；
- 算术单元和控制单元测试；
- 随机小张量位精确回归；
- 一次真实的 memory 读取、计算和写回；
- reset、backpressure、非法配置和错误响应测试；
- 可讲解的关键波形；
- 可复现的 lint、综合和时序结果；
- 规模、周期、面积、关键路径和已知限制说明。

只有这些证据存在后，才把 NPU 作为异构系统集成中的可信模块。
