# 存储互联与 AMBA 探索规划

> 文档状态：v0.1 候选规划
> 前置条件：简单 `valid/ready` 的 CPU—NPU 系统闭环已经稳定
> 原则：AMBA 是可验证的接口升级，不是当前 CPU 项目的完成条件。

## 1. 为什么延后 AMBA

在 CPU、NPU 和系统功能尚未分别稳定前引入 AMBA，会同时叠加：

- 计算数据通路错误；
- 地址生成错误；
- 存储所有权错误；
- 总线握手和响应错误；
- 多主设备仲裁错误。

因此先冻结内部寄存器语义和 memory request/response，再通过外围 adapter 接入标准协议。升级 AMBA 时，已通过的 CPU/NPU 功能回归应保持不变。

## 2. 各协议的候选角色

| 协议 | 适合的候选用途 | 当前判断 |
|---|---|---|
| APB | NPU 控制/状态寄存器 | 简单，适合作为第一个控制总线实验 |
| AHB-Lite | 片上 SRAM 和有限并发的数据通路 | 比 AXI 简单，适合小型边缘系统实验 |
| AXI4-Lite | 标准化 NPU 控制从接口 | 面试相关性高，但比直接 MMIO/APB 验证量大 |
| AXI4 | 高吞吐、burst、多个在途事务的数据通路 | 只有出现明确带宽或系统集成需求时再做 |
| ACE/CHI | Cache coherence 和大规模系统互联 | 当前规划不采用 |

APB、AHB-Lite 和 AXI 并不存在绝对优劣，选择必须由访问模式、并发、吞吐和验证预算决定。

## 3. 当前候选演进路线

### 路线 0：最小系统

```text
CPU dmem_req/rsp -> simple MMIO registers
NPU mem_req/rsp  -> Tensor Scratchpad adapter
```

这是异构系统的功能基线。

### 路线 1：较轻量 AMBA 实验

```text
CPU/system access
    -> AHB-Lite interconnect
    -> AHB-to-APB bridge
    -> NPU APB control registers

CPU/NPU data access
    -> controlled AHB-Lite path
    -> Tensor Scratchpad wrapper
```

该路线可以学习地址阶段/数据阶段、wait state、bridge 和仲裁，同时避免一开始承担完整 AXI 五通道和多 outstanding。

### 路线 2：加速器 IP 接口实验

```text
CPU/control adapter
    -> AXI4-Lite slave
    -> internal NPU registers

NPU Data Mover
    -> constrained AXI4 master
    -> AXI-to-SRAM adapter
    -> Tensor Scratchpad
```

受限 AXI4 可以先规定：单 ID、单 outstanding、固定数据宽度、INCR burst、自然对齐和禁止跨 4 KiB。是否实施必须由路线 1 的结果、岗位相关性和剩余时间决定。

## 4. 私有 TCM 与共享总线边界

即使以后增加系统总线，也优先保持：

- CPU IF 与 ITCM 直连；
- CPU LSU 与 DTCM 的本地路径简单确定；
- Tensor Scratchpad 作为 CPU/NPU 共享资源进入所有权控制或互联；
- NPU 控制寄存器进入低带宽控制总线。

如果把 CPU 每次取指和本地数据访问都强制放到共享总线，ITCM/DTCM 将失去低延迟、私有和确定性的主要意义，同时扩大仲裁和验证范围。

## 5. 多主设备与轮询问题

候选 initiator 包括 CPU LSU、NPU Data Mover 和启动 Loader。若共享同一数据总线，需要定义：

- 哪些阶段哪个 initiator 可以请求；
- 仲裁优先级或轮询策略；
- 是否允许打断 burst；
- CPU 轮询 `STATUS` 的最坏等待时间；
- NPU 是否会因 CPU 轮询而长期饥饿；
- owner 和 outstanding 的切换条件。

在单端口 Tensor Scratchpad 且 CPU/NPU 分时访问的第一版中，可以用显式 owner 限制并发；只有出现真实的访问重叠需求时才扩展为更复杂仲裁。

## 6. DMA 的决策边界

NPU 自身的 Data Mover 已经负责根据任务地址读取输入/权重并写回结果。以下需求出现前，不单独增加通用 DMA：

- 外部 DRAM 与片上 SRAM 之间的大块搬运；
- scatter-gather；
- 双缓冲和计算/传输重叠；
- 多个 accelerator 共享搬运资源；
- CPU 配置搬运成为实测瓶颈。

是否实现 DMA 应由数据来源和重叠需求决定，而不是因为完整 SoC 通常存在 DMA。

## 7. Adapter 边界

推荐长期保持以下分层：

```text
CPU core
  -> imem/dmem internal protocol
  -> bus adapter

NPU control core
  -> internal register semantics
  -> APB or AXI4-Lite adapter

NPU Data Mover
  -> internal load/store commands
  -> AHB-Lite or AXI4 adapter

SRAM backend
  <- protocol-to-SRAM wrapper
```

这样可以对 adapter 做独立 testbench，并在不修改计算核心的情况下比较不同互联方案。

## 8. 协议升级的验收证据

- adapter 单元测试独立通过；
- valid/ready 或协议 payload 在等待期间保持；
- wait-state/backpressure 覆盖；
- 地址译码、对齐和错误响应；
- 多 initiator 时的仲裁和无饥饿约束；
- reset 中断事务后的状态清理；
- 升级前后软件可见行为和计算结果一致；
- 协议引入前后的周期、面积、关键路径和验证成本记录。

## 9. 冻结 AMBA 方案前必须回答的问题

1. Tensor 每个任务实际搬运多少数据？
2. 连续访问比例和理想 burst 长度是多少？
3. NPU 计算吞吐需要多大的 SRAM 带宽？
4. CPU 和 NPU 是否真的需要并发访问共享存储？
5. 数据是否只在片上，还是需要外部 DRAM？
6. 目标岗位更重视协议实现还是 NPU 微架构？
7. 剩余时间是否足以完成协议专项验证？

这些问题没有答案前，APB + AHB-Lite 和 AXI4-Lite + AXI4 都只是候选方案，不是冻结需求。
