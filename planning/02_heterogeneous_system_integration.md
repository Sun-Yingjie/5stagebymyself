# CPU—NPU 异构系统集成规划

> 文档状态：v0.1 候选规划
> 前置条件：五级流水 CPU 和独立 NPU 都已通过各自回归
> 原则：先用最小内部协议形成真实闭环，再升级标准总线。

## 1. 集成目标

该阶段不重新设计 CPU 或 NPU，而是验证以下完整路径：

```text
软件参考结果
-> 存储镜像
-> CPU 裸机程序
-> MMIO 配置与 START
-> NPU 读取 Tensor
-> INT8 计算
-> NPU 写回结果
-> CPU 轮询并检查结果
-> PASS/FAIL
```

第一个系统版本只要求功能闭环、接口正确和可复现验证，不追求通用 SoC 或极限吞吐。

## 2. 候选系统拓扑

```text
CPU IF  <----------------------> ITCM

CPU LSU <----------------------> DTCM
    |
    +---- simple MMIO ---------> NPU control registers
    |
    +---- CPU Tensor port --+
                             |
NPU memory port -------------+--> tensor_owner_mux --> Tensor Scratchpad

Loader/testbench ----------------> ITCM / DTCM / Tensor Scratchpad
```

这是一种分层互联，不把 CPU、NPU 和所有 SRAM 一次性挂到统一总线上。

## 3. 三类存储的角色

### 3.1 ITCM

- CPU 私有取指存储；
- 保存 reset entry、启动代码和 `.text`；
- CPU 通过 `imem_req/rsp` 直接访问；
- 无 tag、miss、refill 和 replacement；
- 正常运行期间不由 NPU 访问。

### 3.2 DTCM

- CPU 私有本地数据存储；
- 保存 `.rodata`、`.data`、`.bss`、栈和标量临时数据；
- CPU 通过 `dmem_req/rsp` 访问；
- NPU 不访问；
- 无 Cache coherence 问题。

### 3.3 Tensor Scratchpad

- 保存输入、权重、量化参数、中间结果和输出；
- 由软件和 manifest 显式管理地址；
- CPU 在 NPU idle 时准备输入或读取结果；
- NPU busy 时拥有访问权；
- 不自动与 ITCM/DTCM 复制数据；
- 不是 Cache，也不是 CPU 私有 TCM。

容量、bank 数量、端口和最终 SRAM 组织在 NPU 工作负载冻结后再决定。

## 4. 最小内部协议

### 4.1 CPU 指令接口

沿用 CPU 项目定义的 `imem_req/rsp`。首个系统模型可以是一笔在途、固定或可配置延迟的同步 memory wrapper。

### 4.2 CPU 数据接口

沿用 CPU 项目定义的 `dmem_req/rsp`，由地址译码器选择 DTCM、Tensor CPU port 或 NPU MMIO。

通用规则：

- 请求在 `req_valid && req_ready` 时提交；
- 响应在 `rsp_valid && rsp_ready` 时提交；
- 未握手时 valid 和 payload 保持；
- 每个已接受请求恰好产生一个完成响应；
- 最多一笔在途；
- 未映射或越界地址返回 error；
- store 也要有完成响应，避免 CPU 提前越过副作用边界。

### 4.3 NPU 数据接口

NPU 第一版使用与 Tensor adapter 之间的简单 `mem_req/rsp`，不要求 burst、多 outstanding 或乱序响应。数据宽度和 packing 在 NPU 规格冻结后决定。

## 5. MMIO + 轮询

MMIO 表示 NPU 寄存器映射到 CPU 数据地址空间，并不要求第一版使用 AXI4-Lite。CPU 的 `dmem_req/rsp` 可以通过地址译码后直接访问寄存器模块。

候选最小寄存器语义：

| 名称 | 属性 | 用途 |
|---|---|---|
| `CTRL` | WO/W1P | `START`、可选 `CLEAR_DONE` |
| `STATUS` | RO | `BUSY`、`DONE`、`ERROR` |
| `DESC_ADDR` 或参数寄存器 | RW | 指向任务描述或直接保存任务参数 |
| `CYCLE_CNT` | RO | 上一次任务周期数 |
| `ERROR_CODE` | RO | 错误原因 |
| `VERSION` | RO | 能力和版本标识 |

具体 offset、descriptor 结构和参数数量要等 NPU 第一个任务冻结后再定义。

基本软件流程：

```text
准备 Tensor
-> 写配置
-> 写 START
-> 轮询 STATUS
-> 观察 DONE 或 ERROR
-> 读取结果
```

## 6. Tensor 所有权

候选状态：

```text
TENSOR_OWNER_LOADER
TENSOR_OWNER_CPU
TENSOR_OWNER_NPU
```

候选转换：

```text
reset
  -> LOADER
  -> loader_done
  -> CPU
  -> accepted START
  -> NPU
  -> final write completed / error drained
  -> CPU
```

必须保持：

- 同一周期只有一个 owner 可以访问 SRAM backend；
- owner 只在没有未完成事务时切换；
- NPU busy 时 CPU 仍可取指、访问 DTCM 和轮询 MMIO；
- NPU busy 时 CPU 的 Tensor 请求不能产生 SRAM 副作用；
- `DONE` 不能早于最终输出写完成；
- CPU 观察 `DONE` 后才能读取结果。

## 7. 启动与数据装载

第一步允许 testbench 在 reset 期间使用 `$readmemh` 分别加载：

```text
itcm.hex
dtcm.hex
tensor.hex
```

后续可以增加 front-door Loader，把写请求通过受控端口送入三块 SRAM。Loader 活跃期间 CPU/NPU 保持 reset；Loader 完成后再释放 CPU。

三块 SRAM 不互联，也不会自动初始化彼此。程序、CPU 数据和 Tensor 数据由镜像生成工具分别放入目标存储。

## 8. 候选地址空间

地址空间只有在容量和工作负载冻结后才能正式确定。可以暂用以下不重叠窗口做仿真原型：

| 区域 | 候选基地址 | 备注 |
|---|---:|---|
| ITCM | `0x0000_0000` | 取指地址空间 |
| DTCM | `0x1000_0000` | CPU 本地数据 |
| Tensor Scratchpad | `0x2000_0000` | CPU/NPU 分时共享 |
| NPU MMIO | `0x4000_0000` | 控制和状态 |

容量变化必须同步更新 linker script、manifest、镜像生成器和硬件范围检查。

## 9. 系统完成证据

- CPU 从 ITCM 运行真实裸机程序；
- CPU 通过真实 MMIO 配置并启动 NPU；
- NPU 通过真实 memory interface 读取和写回 Tensor；
- CPU 轮询并检查结果；
- 与软件整数参考模型位精确一致；
- reset、backpressure、非法地址、重复 START 和所有权边界测试；
- 关键握手与无副作用断言；
- 系统级仿真、综合、STA 和已知限制记录。

完成上述闭环后，才评估是否用标准 AMBA adapter 替换内部协议。
