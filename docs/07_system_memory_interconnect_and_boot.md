# 系统启动、存储层次与互联协议规格

> 文档状态：v0.1 基线
> 文档性质：启动、存储和互联范围内的详细规格
> 上位需求：`06_ai_system_project_requirements.md`
> 适用范围：CPU、NPU、Loader、ITCM、DTCM、Tensor Scratchpad 及协议适配器
> 原则：CPU 私有存储保持简单确定，NPU 控制与数据通路分离，复杂性限制在适配器和所有权边界。

## 0. 文档优先级与冻结决定

本文冻结 CPU、NPU 和三类片上存储之间的互联拓扑、启动方式及逐段协议。在启动、存储和互联范围内，优先级为：

1. `07_system_memory_interconnect_and_boot.md`；
2. `06_ai_system_project_requirements.md`；
3. `00_processor_architecture.md` 至 `05_rtl_implementation_order.md`。

本文冻结：

- 首版不使用 Instruction Cache 或 Data Cache；
- CPU 指令存储采用 ITCM，本地数据存储采用 DTCM；
- AI 权重、输入、激活和输出使用 Tensor Scratchpad；
- 三者物理上均可由同步 SRAM macro 实现；
- CPU 通过现有 `imem_req/rsp` 访问 ITCM；
- CPU 通过现有 `dmem_req/rsp` 访问 DTCM、Tensor Scratchpad 和 NPU MMIO；
- CPU 到 NPU 控制寄存器使用 AXI4-Lite；
- NPU 到 Tensor Scratchpad 使用受限 AXI4 Memory-Mapped；
- NPU 内部 Data Mover 承担专用数据搬运，不另建通用 DMA；
- CPU 与 NPU 分时使用 Tensor Scratchpad；
- 启动初期允许 back-door preload，随后增加 front-door Loader；
- 首版使用单一时钟域，不引入 CDC。

## 1. 存储器属性

### 1.1 ITCM

ITCM 是 CPU 私有指令存储：

- CPU 只能通过取指接口读取；
- 保存 reset entry、启动代码和 `.text`；
- 无 tag、miss、refill 或 replacement；
- 正常运行期间 CPU 不能用 load/store 修改；
- 首版使用固定一周期响应的同步 SRAM 模型。

ITCM 描述访问组织。物理实现可以是 SRAM macro；固定程序版本以后也可以替换成 ROM。

### 1.2 DTCM

DTCM 是 CPU 私有本地数据存储：

- CPU 通过 load/store 访问；
- 保存 `.rodata`、`.data`、`.bss`、栈和标量临时数据；
- NPU 不访问；
- 无 Cache 和一致性问题；
- 首版使用固定一周期响应的同步 SRAM 模型。

CPU 需要通过 load 读取的常量必须放在 DTCM，不能放在只连接取指端口的 ITCM。

### 1.3 Tensor Scratchpad

Tensor Scratchpad 是软件显式管理的 AI 数据存储：

- 保存输入、INT8 权重、INT32 bias、量化参数、descriptor、中间激活和输出；
- CPU 在 NPU idle 时准备数据和读取结果；
- NPU 在 busy 时通过 AXI4 主通路独占访问；
- 数据位置由软件、manifest 和 descriptor 明确指定；
- 无 Cache tag、自动替换和硬件一致性。

它不称为 CPU TCM，因为它不是 CPU 私有紧耦合存储，而是 CPU/NPU 分时共享的 scratchpad。

## 2. 主从关系

### 2.1 主设备

| 主设备 | 可访问目标 | 活跃阶段 |
|---|---|---|
| Front-door Loader | ITCM、DTCM、Tensor Scratchpad | CPU/NPU 释放 reset 前 |
| CPU IF | ITCM | CPU 正常运行 |
| CPU LSU | DTCM、Tensor Scratchpad、NPU MMIO | CPU 正常运行 |
| NPU Data Mover | Tensor Scratchpad | NPU busy |

### 2.2 从设备

| 从设备 | 访问者 | 接口 |
|---|---|---|
| ITCM | Loader、CPU IF，分时 | 简单 SRAM wrapper |
| DTCM | Loader、CPU LSU，分时 | 简单 SRAM wrapper |
| Tensor Scratchpad | Loader、CPU LSU、NPU，分时 | 多前端、单 SRAM backend |
| NPU Control Registers | CPU LSU | AXI4-Lite Slave |

三块 SRAM 不直接相连，也不会自动复制数据。数据移动必须由 Loader、CPU 或 NPU 显式发起。

## 3. 互联拓扑

```text
                             +-------------+
                loader ---->| ITCM mux    |----> ITCM SRAM
CPU imem_req/rsp ----------->| CPU port    |
                             +-------------+

                             +-------------+
                loader ---->| DTCM mux    |----> DTCM SRAM
CPU dmem_req/rsp --+-------->| CPU port    |
                   |         +-------------+
                   |
                   v
          +----------------+
          | address decoder|
          +---+--------+---+
              |        |
              |        +--> cpu_to_axilite
              |                    |
              |                    v
              |             NPU AXI4-Lite
              |             control registers
              |                    |
              |                    v
              |                NPU Engine
              |                    |
              |              NPU Data Mover
              |                    |
              |              AXI4 Master
              |                    |
              |              axi_to_sram
              |                    |
              v                    v
       cpu_tensor_adapter    npu_tensor_adapter
              |                    |
              +---------+----------+
                        v
                 tensor_owner_mux <---- loader
                        |
                        v
                Tensor Scratchpad
```

这是混合互联：

- CPU 私有低延迟存储使用简单直连接口；
- NPU 控制面使用 AXI4-Lite；
- NPU 数据面使用 AXI4 burst；
- Tensor Scratchpad 使用显式所有权控制；
- Loader 只在启动阶段进入 SRAM。

首版不建立覆盖全部主从设备的统一 AXI crossbar。

## 4. 地址空间

### 4.1 指令空间

| 区域 | 起始地址 | 结束地址 | 默认容量 |
|---|---:|---:|---:|
| ITCM | `0x0000_0000` | `0x0000_FFFF` | 64 KiB |

`RESET_VECTOR` 默认为 `0x0000_0000`。ITCM 只通过 `imem_req/rsp` 访问，不进入 data address decoder。

### 4.2 数据空间

| 区域 | 起始地址 | 结束地址 | 默认容量 |
|---|---:|---:|---:|
| DTCM | `0x1000_0000` | `0x1000_FFFF` | 64 KiB |
| Tensor Scratchpad | `0x2000_0000` | `0x2007_FFFF` | 512 KiB |
| NPU MMIO | `0x4000_0000` | `0x4000_0FFF` | 4 KiB |

这些是首版逻辑地址空间和仿真默认值。真实 SRAM macro 容量变化必须同步更新本文、linker script、manifest 和范围检查。

### 4.3 译码规则

- 使用完整 32-bit byte address；
- 任一地址最多命中一个目标；
- 目标选择在请求握手后锁存到响应完成；
- 未映射地址返回 `dmem_rsp_error = 1`；
- DTCM 和 Tensor 返回包含目标 byte 的 32-bit 对齐 word；
- CPU LSU 根据地址低位完成 byte/halfword 选择；
- store 的 `dmem_req_wstrb[3:0]` 控制四个 byte lane。

## 5. Loader 启动协议

### 5.1 两阶段加载策略

第一阶段优先完成端到端功能，testbench 在 reset 期间 back-door 加载：

```systemverilog
$readmemh("itcm.hex",   dut.u_itcm.mem);
$readmemh("dtcm.hex",   dut.u_dtcm.mem);
$readmemh("tensor.hex", dut.u_tensor_sram.mem);
```

第二阶段增加 front-door Loader：

```text
loader_valid
loader_ready
loader_target[1:0]   // ITCM / DTCM / TENSOR
loader_addr[31:0]    // 目标内部 byte offset
loader_wdata[31:0]
loader_wstrb[3:0]
loader_done
```

### 5.2 Loader 事务

```text
loader_fire = loader_valid && loader_ready
```

- `loader_valid` 未握手时全部字段保持；
- 首版 Loader 只支持写；
- `loader_addr` 是目标内部 byte offset；
- Loader 检查对齐、范围和 byte strobe；
- `loader_done` 只有在所有写事务完成后才能置位；
- Loader active 时 CPU 和 NPU 保持 reset；
- Loader 完成后在安全时钟边沿释放 CPU/NPU；
- Loader 首版由 testbench 驱动，SPI/UART/JTAG 以后作为前置 adapter。

### 5.3 内存镜像

| 镜像 | 内容 |
|---|---|
| `itcm.hex` | reset entry、启动代码、`.text` |
| `dtcm.hex` | `.rodata`、`.data` 和初始标量 |
| `tensor.hex` | 输入、权重、bias、量化参数、descriptor 和初始 tensor |

`.bss` 由启动代码清零；栈只预留地址范围。

Linker section：

```text
.text                 -> ITCM
.rodata               -> DTCM
.data                 -> DTCM
.bss                  -> DTCM，启动时清零
stack                 -> DTCM
model/tensor manifest -> Tensor Scratchpad，独立镜像
```

### 5.4 字节序

- 使用 RISC-V little-endian；
- 最低地址 byte 位于 word 的 `[7:0]`；
- 四个 INT8 依次放入 `[7:0]`、`[15:8]`、`[23:16]`、`[31:24]`；
- INT32 bias 和量化乘数按 little-endian word 保存；
- manifest 记录每个 tensor 的 base、shape、layout、dtype 和 byte length；
- 镜像生成器检查目标范围。

### 5.5 复位层次

系统区分：

```text
por_rst   // reset Loader、互联控制和协议状态
core_rst  // 保持 CPU/NPU reset，直到 boot_ready

core_rst = por_rst || !boot_ready
```

SRAM 数据阵列不依赖 reset 清零；reset 只清除 valid、busy、done、error、owner 和 outstanding transaction 等控制状态。

## 6. CPU 到 ITCM

沿用：

```text
imem_req_valid
imem_req_ready
imem_req_addr

imem_rsp_valid
imem_rsp_ready
imem_rsp_data
imem_rsp_error
```

首版契约：

- 只读；
- 地址 4-byte 对齐；
- 最多一笔在途；
- 请求周期 N 握手，响应周期 N+1 有效；
- `imem_rsp_ready = 0` 时响应保持；
- 越界或非法地址返回 error；
- Loader active 或 CPU reset 时不接受 CPU 取指。

ITCM word index：

```text
itcm_word_index = imem_req_addr[ITCM_ADDR_MSB:2]
```

## 7. CPU 到 DTCM 和 Tensor

沿用：

```text
dmem_req_valid
dmem_req_ready
dmem_req_write
dmem_req_addr
dmem_req_wdata
dmem_req_wstrb

dmem_rsp_valid
dmem_rsp_ready
dmem_rsp_rdata
dmem_rsp_error
```

### 7.1 DTCM

- 最多一笔在途；
- 请求周期 N 握手，响应周期 N+1 有效；
- load 返回 32-bit 对齐 word；
- store 根据 `wstrb` 更新 byte；
- store 也返回完成响应；
- 越界返回 error；
- 响应未握手时保持；
- reset 不清除数据。

### 7.2 Tensor CPU 端口

- 仅在 `TENSOR_OWNER_CPU` 时接受；
- 使用与 DTCM 相同的 32-bit word 和 byte strobe；
- NPU busy 时 CPU Tensor 请求不进入 SRAM；
- 首版对非法 busy 访问返回 `dmem_rsp_error = 1`，同时触发系统 assertion；
- CPU 仍可在 NPU busy 时访问 DTCM 和 NPU MMIO。

## 8. CPU 到 NPU 的 AXI4-Lite 控制面

### 8.1 路径

```text
CPU dmem_req/rsp
    -> data address decoder
    -> cpu_to_axilite
    -> NPU AXI4-Lite Slave
```

MMIO 是地址语义，AXI4-Lite 是该区域的传输协议。

### 8.2 cpu_to_axilite

- 一次只接受一笔 CPU 请求；
- CPU load 转换为 `AR/R`；
- CPU store 转换为 `AW/W/B`；
- AW 和 W 独立握手，不能假设同周期；
- VALID 在 READY 前保持，payload 不变；
- store 收到 B response 后才完成；
- load 收到 R response 后才完成；
- `SLVERR/DECERR` 转为 `dmem_rsp_error = 1`；
- 不产生 burst；
- 不建立输入到输出的组合环路。

### 8.3 NPU 寄存器

| Offset | 名称 | 属性 | 定义 |
|---:|---|---|---|
| `0x000` | `CTRL` | WO/W1P | bit 0 START，bit 1 CLEAR_DONE |
| `0x004` | `STATUS` | RO | bit 0 BUSY，bit 1 DONE，bit 2 ERROR |
| `0x008` | `DESC_ADDR` | RW | Tensor 中 descriptor byte address |
| `0x00C` | `CYCLE_CNT` | RO | 上一次任务周期数 |
| `0x010` | `ERROR_CODE` | RO | 错误原因 |
| `0x014` | `VERSION` | RO | RTL 版本和能力 |

语义：

- START 是 write-one pulse；
- idle 且 descriptor 合法时接受 START，清除旧 DONE/ERROR 并置 BUSY；
- busy 时写 START 返回 `SLVERR`，当前任务不变；
- DONE 是 sticky，由 CLEAR_DONE 或下一次合法 START 清除；
- STATUS 轮询不影响执行；
- DESC_ADDR 必须 4-byte 对齐且位于 Tensor 范围；
- 首版无中断、队列和多上下文。

## 9. NPU 到 Tensor 的 AXI4 数据面

### 9.1 角色

- NPU Data Mover：AXI4 Memory-Mapped Master；
- `axi_to_sram`：AXI4 Slave；
- Tensor Scratchpad：同步 SRAM backend；
- NPU compute datapath 不直接处理 AXI 五通道。

### 9.2 Master 能力

| 属性 | 首版要求 |
|---|---|
| 地址宽度 | 32 bit |
| 数据宽度 | 32 bit |
| Burst | 仅 INCR |
| Burst 长度 | 1～16 beats |
| Beat 大小 | 4 bytes，`AxSIZE = 2` |
| ID | 固定 0 |
| Outstanding | 全局最多一笔 read 或 write burst |
| 对齐 | 4-byte |
| 4 KiB | 禁止跨越 |
| Narrow/unaligned | 不产生 |
| Out-of-order | 不支持 |

32-bit 可以统一 CPU、Loader、Tensor SRAM 和 NPU 首版 word 宽度，每个 beat 搬运四个 packed INT8。只有带宽成为实测瓶颈时才扩展 64-bit。

### 9.3 Read

1. Data Mover 产生地址和 burst length；
2. Master 驱动 AR，未握手时保持；
3. Slave 从 SRAM 逐拍读取；
4. R channel 返回数据和 RRESP；
5. Master 可以施加 RREADY backpressure；
6. 最后一拍必须 RLAST；
7. 非 OKAY、缺失 RLAST 或额外 beat 进入 ERROR。

### 9.4 Write

1. Data Mover 产生地址和 burst length；
2. Master 独立驱动 AW 和 W；
3. W payload 未握手时保持；
4. 最后一拍必须 WLAST；
5. Slave 只在 W handshake 后写 SRAM；
6. 全部 beat 写入后返回一次 B；
7. Master 收到 B handshake 后写 burst 才完成；
8. 非 OKAY 进入 ERROR。

NPU 不得在最后一个输出 B response 返回前宣告任务完成。

### 9.5 NPU 内部边界

```text
load_cmd_valid/ready
load_cmd_addr
load_cmd_bytes
load_data_valid/ready
load_data
load_data_last

store_cmd_valid/ready
store_cmd_addr
store_cmd_bytes
store_data_valid/ready
store_data
store_data_strb
store_data_last

data_error
```

Data Mover 把这些命令转换为 AXI burst。它已经承担专用 DMA 功能，首版不增加独立通用 DMA。

## 10. Tensor 所有权

### 10.1 状态

```text
TENSOR_OWNER_LOADER
TENSOR_OWNER_CPU
TENSOR_OWNER_NPU
```

### 10.2 转换

```text
power-on/reset
       |
       v
TENSOR_OWNER_LOADER
       | loader_done
       v
TENSOR_OWNER_CPU
       | accepted START
       v
TENSOR_OWNER_NPU
       | no outstanding AXI
       | final output B completed
       v
TENSOR_OWNER_CPU
```

### 10.3 规则

- Loader owner 时 CPU/NPU 请求禁止；
- CPU owner 时 NPU AXI 请求不进入 SRAM；
- NPU owner 时 CPU 可以取指、访问 DTCM 和轮询 MMIO；
- NPU owner 时 CPU Tensor 请求返回 error 且无副作用；
- owner 只在没有未完成请求时切换；
- BUSY 和 NPU owner 同次提交；
- DONE 前排空 AXI R/B；
- CPU 观察 DONE 后才能读结果；
- 无 Cache，因此无需 clean、invalidate 或 coherence。

## 11. 正常运行序列

### 11.1 Boot

```text
assert core_rst
    -> load ITCM
    -> load DTCM
    -> load Tensor
    -> loader_done
    -> owner = CPU
    -> release core_rst
    -> CPU fetch RESET_VECTOR
```

### 11.2 CPU 启动 NPU

```text
CPU prepares Tensor
    -> write DESC_ADDR via AXI4-Lite
    -> write CTRL.START
    -> START accepted
    -> BUSY = 1
    -> Tensor owner = NPU
```

CPU 顺序执行、data channel 单笔在途且无 store buffer，因此 START 被接受前，前面的 Tensor store 已完成。以后加入 Cache/write buffer 时必须重新定义 FENCE 和一致性。

### 11.3 NPU 完成

```text
AXI read descriptor/input/weights
    -> compute
    -> AXI write output
    -> final B response
    -> owner = CPU
    -> BUSY = 0
    -> DONE = 1
```

### 11.4 CPU 读取结果

```text
poll STATUS
    -> observe DONE
    -> read output from Tensor
    -> optional CLEAR_DONE
```

## 12. 错误处理

### 12.1 CPU 侧

以下返回 `dmem_rsp_error = 1`：

- 未映射地址；
- NPU busy 时 CPU 访问 Tensor；
- AXI4-Lite SLVERR/DECERR；
- 不支持或越界 MMIO。

CPU 精确异常未完成时，系统 testbench 将 error 视为失败并记录地址；trap 单元接入后转换为 access fault。

### 12.2 NPU 侧

以下设置 STATUS.ERROR：

- descriptor 未对齐或越界；
- tensor 地址或长度越界；
- burst 跨 4 KiB；
- RRESP/BRESP 非 OKAY；
- RLAST/WLAST 错误；

busy 时重复写 START 只通过该次 AXI4-Lite 写的 `SLVERR` 拒绝，不改变当前任务的 `STATUS.ERROR`。系统 reset 会取消当前任务并清除 BUSY、DONE、ERROR 和协议 outstanding 状态；由于主从模块处于同一 reset 域，不保留一次跨 reset 的错误完成事件。

错误处理：

- 停止发起新事务；
- 排空已握手的必要响应；
- 不重复写输出；
- outstanding 清零后归还 Tensor；
- 置 `BUSY=0`、`DONE=1`、`ERROR=1`。

## 13. 系统不变量

- Loader active 时 CPU/NPU 不访问 SRAM；
- ITCM 正常运行只由 CPU IF 读取；
- DTCM 正常运行只由 CPU LSU 访问；
- Tensor backend 每周期只接受一个 owner；
- NPU busy 时 CPU Tensor 请求无副作用；
- VALID 在 READY 前保持，payload 不变；
- 每个 AXI write burst 恰好一个 B response；
- RLAST/WLAST 只在最后一拍；
- DONE 不早于最终输出 B response；
- owner 切换时无 outstanding；
- reset 时所有协议 VALID 清零；
- reset 不自动清除 SRAM 内容。

## 14. 模块划分

```text
soc_top.sv
soc_reset_ctrl.sv
soc_loader.sv
soc_addr_decoder.sv

itcm_wrapper.sv
dtcm_wrapper.sv
tensor_sram_wrapper.sv
tensor_owner_ctrl.sv
cpu_tensor_adapter.sv

cpu_to_axilite.sv
npu_ctrl_axilite.sv

npu_core.sv
npu_data_mover.sv
npu_axi_master.sv
axi_to_sram.sv
```

边界：

- `rv32_core` 不解析 AXI；
- `npu_core` 不直接处理 AXI 五通道；
- `cpu_to_axilite` 只转换 CPU 单笔 MMIO；
- `npu_axi_master` 只转换 Data Mover 命令；
- `axi_to_sram` 只负责协议到 SRAM；
- `tensor_owner_ctrl` 只负责 owner 和切换资格；
- SRAM wrapper 隔离 behavioral array 与未来 macro。

## 15. 实现顺序

### A. 简单存储

1. ITCM、DTCM、Tensor behavioral wrapper；
2. `$readmemh` 三个镜像；
3. CPU 运行最小裸机程序；
4. 地址、byte strobe 和越界测试。

### B. NPU MMIO

1. 控制寄存器行为；
2. AXI4-Lite Slave；
3. `cpu_to_axilite`；
4. CPU 完成 DESC_ADDR、START 和 STATUS 轮询。

### C. Tensor owner

1. Loader/CPU/NPU 三态 owner；
2. START/DONE 切换；
3. busy 时 CPU Tensor error。

### D. NPU AXI

1. 简单 Data Mover command；
2. AXI read master；
3. AXI write master；
4. `axi_to_sram`；
5. backpressure 和 error；
6. 真实 Tensor 读写。

### E. Front-door Loader

1. Loader write；
2. reset 期间写三块 SRAM；
3. 最终系统 smoke 改用 front-door；
4. back-door 保留给快速回归。

### F. ASIC

1. SRAM wrapper 替换 macro/black-box 视图；
2. lint；
3. DC；
4. SRAM 容量和 cell area 分开；
5. Formality；
6. PT；
7. front-door 门级 smoke。

## 16. 验证计划

### 16.1 Loader

- 三个 target 首末地址；
- 非对齐和 byte strobe；
- valid 等待 ready；
- done 前不释放 CPU；
- 加载后逐 word 检查；
- active 时 CPU/NPU 不进入 SRAM。

### 16.2 CPU 存储

- 连续取指和 IF backpressure；
- DTCM byte/half/word；
- 未映射地址；
- response backpressure；
- reset 不清除数据。

### 16.3 AXI4-Lite

- AW 先、W 先和同周期；
- BREADY 延迟；
- ARREADY/RREADY 延迟；
- busy 时重复 START；
- 非法 offset；
- SLVERR 传播。

### 16.4 AXI4

- 1-beat 和 16-beat；
- 4 KiB 边界；
- 五通道独立 backpressure；
- RLAST/WLAST；
- RRESP/BRESP error；
- reset 中断；
- B response 前不得 DONE；
- little-endian packing。

### 16.5 所有权

- Loader→CPU；
- CPU→NPU；
- NPU 正常/错误→CPU；
- 切换边界请求；
- busy 时 CPU 非法 Tensor；
- 无双 owner。

### 16.6 系统

- front-door 加载三份镜像；
- CPU 从 ITCM 启动；
- 初始化 DTCM；
- CPU 写 MMIO；
- NPU AXI 读写 Tensor；
- CPU 轮询并读取结果；
- 与整数参考模型比对。

## 17. 暂不采用

### 17.1 全系统 AXI crossbar

首版不把 CPU imem、CPU dmem、NPU 和 Loader 全做成 AXI master，也不把三块 SRAM 全做成 AXI slave。它会增加多主仲裁、ID 路由、CPU 取指延迟和验证矩阵。

### 17.2 双端口 Tensor SRAM

首版不依赖 true dual-port macro，避免端口冲突规则、宏可用性和面积问题。

### 17.3 Cache

首版没有外部 DRAM和通用软件，不建立 I/D Cache，因此无需 cache maintenance 和 coherency。

### 17.4 独立 DMA

NPU Data Mover 已经通过 AXI burst 搬运数据。只有外部 DRAM、scatter-gather、双缓冲、计算传输重叠或多个 accelerator 共享搬运时再评估 DMA。

## 18. 后续扩展

- AXI 数据宽度 32→64 bit；
- 多 outstanding burst；
- NPU local buffer 和双缓冲；
- 计算与搬运重叠；
- polling→interrupt；
- 通用 DMA 或 AXI4-Stream；
- 外部 DRAM 和正式 AXI interconnect；
- SPI/UART/JTAG→Loader adapter；
- Cache 和一致性；
- 多任务和命令队列。

扩展必须有新的 workload、带宽或软件需求支撑。

## 19. 结论

首版架构冻结为：

```text
CPU IF
    -> imem req/rsp
    -> ITCM

CPU LSU
    -> dmem req/rsp
    -> DTCM
    -> Tensor CPU port
    -> cpu_to_axilite
    -> NPU AXI4-Lite control

NPU
    -> Data Mover
    -> constrained AXI4 Master
    -> axi_to_sram
    -> Tensor Scratchpad

Loader
    -> reset-time front-door write
    -> ITCM / DTCM / Tensor Scratchpad
```

ITCM/DTCM 是 CPU 私有无 Cache TCM；Tensor Scratchpad 是 CPU/NPU 分时共享、软件显式管理的 AI 数据存储。CPU 用 MMIO+轮询控制 NPU，NPU 用 AXI4 burst 搬运 tensor，Loader 在启动阶段写入三块 SRAM。CPU 流水线、NPU compute datapath、总线协议和 SRAM backend 通过适配器保持解耦。
