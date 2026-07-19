# 总体架构与接口

本文档描述当前 `rv32_core` RTL 已实现的架构边界。它是实现与验证的事实来源；未来能力只有在进入 RTL 并取得验证证据后，才应写入“当前能力”。

## 1. 项目边界

`rv32_core` 是一颗 32 位、单 hart、单发射、顺序执行的 RISC-V Core，而不是完整 SoC。核内包含五级流水、通用寄存器、有限 Machine CSR 与同步 trap 状态；存储器、总线适配器、外设和调试系统位于核外。

当前设计采用：

- `XLEN=32`，`IALIGN=32`；
- `IF / ID / EX / MEM / WB` 五级流水；
- 指令与数据访问通道分离；
- 静态不跳转，branch/JAL/JALR 在 EX 决策；
- 每个访存通道最多一笔在途事务；
- 高有效同步复位。

## 2. 当前 ISA 能力

### 2.1 整数与控制流

| 类别 | 指令 |
|---|---|
| R 型整数运算 | `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND` |
| I 型整数运算 | `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` |
| 高位立即数 | `LUI AUIPC` |
| 条件分支 | `BEQ BNE BLT BGE BLTU BGEU` |
| 跳转 | `JAL JALR` |
| Load | `LB LH LW LBU LHU` |
| Store | `SB SH SW` |
| 顺序 | `FENCE` |

在当前顺序、阻塞式数据通道中，`FENCE` 作为无额外副作用的合法指令进入流水并退休。`FENCE.I` 属于未实现的独立扩展，按非法指令处理。

### 2.2 Zicsr 与同步 trap

已实现六条 Zicsr 指令：

```text
CSRRW CSRRS CSRRC CSRRWI CSRRSI CSRRCI
```

当前存在有限 Machine CSR profile，并支持 cause `0/1/2/3/4/5/6/7/11` 的精确同步 trap。具体规则见 [CSR 与同步 Trap](csr_trap.md)。

## 3. 模块组织

```text
rv32_core
├── rv32_ifu
├── rv32_idu
│   ├── rv32_decoder
│   │   └── rv32_csr_decoder
│   ├── rv32_imm_gen
│   └── rv32_regfile
├── rv32_exu
│   ├── rv32_alu
│   └── rv32_branch_compare
├── rv32_lsu
├── rv32_csr_trap
│   └── rv32_csr_alu
├── rv32_forward_unit
└── rv32_pipeline_ctrl
```

没有独立 WB 模块：写回选择、WB bus 和 retire 输出由 `rv32_core` 直接形成。最终 MEM/WB candidate 和同步异常优先级也由 `rv32_core` 统一决定；LSU 内同名输出只是兼容接口，不是最终状态所有者。

## 4. 状态所有权

| 状态 | 唯一所有者 | 说明 |
|---|---|---|
| `x0`～`x31` | `rv32_regfile` | `x0` 恒为 0，写 `x0` 被抑制 |
| IF/ID、ID/EX、EX/MEM、MEM/WB | `rv32_core` | 每级以 `valid` 区分真实指令与 bubble |
| EX hold 快照 | `rv32_core` | request stall 时固定已完成前递的 EX 结果与 redirect |
| IMem pending/outstanding/stale | `rv32_ifu` | 维持取指请求并排空错误路径响应 |
| DMem outstanding | `rv32_lsu` | 维护单笔数据事务生命周期 |
| Machine CSR 与 trap entry | `rv32_csr_trap` | 普通 CSR 写和 trap 自动更新共用一个所有者 |

通用寄存器数组不在复位时清零。软件和 testbench 不得假定 `x1`～`x31` 的复位值；必须先写后读。

## 5. 顶层参数与接口

### 5.1 参数

| 参数 | 默认值 | 作用 |
|---|---:|---|
| `RESET_VECTOR` | `0x00000000` | 复位后的第一条取指地址 |
| `MTVEC_RESET` | `0x00000000` | `mtvec` 复位值，低两位强制清零 |
| `COPROC_ENABLE` | `0` | 预留参数；当前不能启用协处理器数据通路 |

### 5.2 IMem

| 信号 | 方向 | 含义 |
|---|---|---|
| `imem_req_valid/ready` | 出/入 | 取指请求握手 |
| `imem_req_addr[31:0]` | 出 | 字节地址 |
| `imem_rsp_valid/ready` | 入/出 | 取指响应握手 |
| `imem_rsp_data[31:0]` | 入 | 指令字 |
| `imem_rsp_error` | 入 | 指令访问错误 |

### 5.3 DMem

| 信号 | 方向 | 含义 |
|---|---|---|
| `dmem_req_valid/ready` | 出/入 | 数据请求握手 |
| `dmem_req_write` | 出 | `1` 为 store，`0` 为 load |
| `dmem_req_addr[31:0]` | 出 | 原始字节地址 |
| `dmem_req_wdata[31:0]` | 出 | 已按 byte lane 对齐的写数据 |
| `dmem_req_wstrb[3:0]` | 出 | 每字节写使能 |
| `dmem_rsp_valid/ready` | 入/出 | 数据响应握手 |
| `dmem_rsp_rdata[31:0]` | 入 | load 返回数据 |
| `dmem_rsp_error` | 入 | 数据访问错误 |

### 5.4 Retire 与 trap

| 信号 | 含义 |
|---|---|
| `retire_valid` | MEM/WB 中有一条正常退休指令 |
| `retire_pc/instr` | 退休指令的 PC 与指令字 |
| `retire_rd_we` | 该指令确实写入非零通用寄存器 |
| `retire_rd_addr/data` | 写回目的寄存器与数据；仅在 `retire_rd_we=1` 时有架构意义 |
| `trap_valid` | MEM 提交点本周期发生同步 trap |
| `trap_pc/cause/value` | 故障指令 PC、cause 与附加值 |

产生 trap 的指令不会普通退休；同周期位于 WB 的更老指令仍可退休。因此验证环境必须分别观察 retire 和 trap，两者不能合并成单一事件。

### 5.5 协处理器预留端口

RTL 保留 `cp_req_*` 与 `cp_rsp_*` 端口。当前所有请求输出和 `cp_rsp_ready` 固定为 0，`COPROC_ENABLE` 也尚未连接到执行路径；这些端口只表示未来扩展位置，不构成已实现功能。

## 6. Valid-ready 事务合同

请求或响应只在 `valid && ready` 的时钟沿完成一次传输。

1. source 拉高 `valid` 后，如果 sink 未拉高 `ready`，source 必须保持 `valid` 和全部 payload；
2. 每个通道最多一笔 outstanding，不使用 transaction ID；
3. 响应必须对应唯一的 outstanding 请求；
4. 允许旧 response 与下一笔 request 在同一周期分别握手；
5. `error` 只在响应握手时解释。

IFU 会把 redirect 前的 pending/outstanding 请求标为 stale，并接收、丢弃旧响应，避免错误路径指令进入 IF/ID。LSU 对 load 和 store 都等待响应；store 只有一次 request 握手，外部存储在返回 error 时必须保证失败写没有形成架构可见副作用。

## 7. 复位与初始行为

- `rst` 高有效，并在 `posedge clk` 同步生效；
- 四级流水寄存器的 `valid` 清零；
- IFU 回到 `RESET_VECTOR` 并准备重新取指；
- IFU/LSU 在途事务状态清零；
- Machine CSR 按 [CSR 与同步 Trap](csr_trap.md) 的 reset 值初始化；
- reset 期间不发请求、不接收响应、不产生 retire/trap；
- 通用寄存器 `x1`～`x31` 不保证复位值。

## 8. 当前不支持的能力

- RV32M、浮点、向量、压缩指令；
- `MRET`、interrupt、counter、完整 privilege transition；
- Cache、MMU、虚拟内存、Linux、多核与一致性；
- 非阻塞多笔访存和 transaction ID；
- 已启用的协处理器执行路径；
- 完整 ACT4 认证或参考模型差分。

流水级逐周期行为见 [五级流水契约](pipeline.md)，验证证据见 [验证方法与结果](verification.md)。
