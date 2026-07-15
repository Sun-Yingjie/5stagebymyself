# 后续项目规划区

本目录保存五级流水 CPU 项目完成后的研究和工程规划，包括独立 NPU、CPU—NPU 异构集成、片上存储互联和 AMBA 协议探索。

## 1. 与当前项目的边界

当前仓库的实现主线是一个完整的五级流水 RV32I 处理器项目。当前必须实现和验收的内容只由 `docs/00_processor_architecture.md` 至 `docs/05_rtl_implementation_order.md` 定义。

本目录中的内容：

- 不覆盖 `docs/00`～`05`；
- 不属于当前 CPU 项目的完成门槛；
- 不要求现在创建 NPU、SoC 或 AMBA RTL；
- 用于保存后续方向、候选接口、阶段门和待决策问题；
- 只有在后续项目正式启动时，才会转化为该项目自己的需求规格。

因此，即使本目录中的 NPU、异构系统或 AMBA 计划没有实施，当前五级流水 CPU 项目仍然可以独立完成并作为一个完整作品交付。

## 2. 文档索引

| 文档 | 作用 |
|---|---|
| `00_overall_roadmap.md` | CPU、NPU、异构系统和 AMBA 的整体路线与优先级 |
| `01_standalone_npu_project.md` | 独立 NPU 项目的目标、阶段和待决策问题 |
| `02_heterogeneous_system_integration.md` | CPU、NPU、ITCM、DTCM、Tensor Scratchpad 的候选集成方案 |
| `03_memory_interconnect_and_amba.md` | 简单接口到 APB/AHB-Lite/AXI 的演进方案和选择依据 |

## 3. 规划内容的状态

规划中的结论分为三类：

- **已确认原则**：例如先独立验证 CPU/NPU，再做系统集成；
- **候选方案**：例如 MMIO + 轮询、Tensor Scratchpad 分时所有权；
- **待决策事项**：例如 NPU 规模、目标算子、数据流、buffer、AMBA 组合和 DMA。

候选方案不能直接当作冻结规格。正式启动后续项目时，应先根据目标工作负载、时间和已有实现重新审阅。
