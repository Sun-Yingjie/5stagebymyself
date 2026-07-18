# RTL 实现顺序与文件组织

> 当前阶段：核心 RTL 已连通；本文维护依赖顺序和工程组织，不替代上位架构规格。

## 1. 目录结构

```text
5stagebymyself/
├── docs/           架构、接口、验证和实现记录
├── rtl/            可综合 SystemVerilog RTL
├── tb/
│   ├── unit/       叶子模块单元测试
│   └── core/       rv32_core 集成测试环境
├── tests/
│   └── asm/        手写汇编与测试程序
├── scripts/        VCS、SpyGlass、DC、FM、PT 脚本
├── reports/        工具报告，不保存无意义的临时输出
└── waves/          关键调试波形和阶段性证据
```

后续可按需要增加 `build/` 作为本地临时产物目录。编译数据库、仿真中间文件和大体积临时波形不应混入 RTL 目录。

## 2. RTL 文件顺序

```text
01  rv32_pkg.sv
02  rv32_imm_gen.sv
03  rv32_alu.sv
04  rv32_csr_alu.sv
05  rv32_csr_trap.sv
06  rv32_csr_decoder.sv
07  rv32_branch_compare.sv
08  rv32_decoder.sv
09  rv32_regfile.sv
10  rv32_forward_unit.sv
11  rv32_pipeline_ctrl.sv
12  rv32_idu.sv
13  rv32_exu.sv
14  rv32_ifu.sv
15  rv32_lsu.sv
16  rv32_core.sv
```

顺序依据是依赖关系和可验证性，不代表最终流水级的重要程度。公共包先完成；被实例化模块必须位于使用者之前，例如 `rv32_csr_alu` 先于 `rv32_csr_trap`、`rv32_csr_decoder` 先于 `rv32_decoder`；最后才连接完整核心。可综合编译的事实源是 `filelists/rv32_core_rtl.f`，本文与其保持一致。

## 3. 每个模块的完成循环

每个 RTL 模块都采用同一循环：

1. 先用自然语言说明输入、输出和应生成的硬件；
2. 用户亲手编写第一版 RTL；
3. 助手按功能、时序、综合、lint 和编码风格审阅；
4. 用户修改并解释关键设计决定；
5. 编写最小单元测试；
6. 运行仿真并阅读关键波形；
7. 测试通过后才进入下一个依赖模块。

公共包没有硬件状态，但仍需通过独立编译和类型审阅。

## 4. 文件与命名约定

- 可综合文件使用 `.sv`；
- 一个主要模块对应一个同名文件；
- 公共类型只放在 `rv32_pkg.sv`，通过 `import rv32_pkg::*;` 使用；
- 不使用全局 `` `include `` 复制类型定义；
- 时序当前值和候选值分别使用 `_q`、`_d`；
- valid/ready 事务完成条件统一使用后缀 `_fire`；
- 寄存器地址使用 `_addr`，32 位寄存器值使用 `_data`；
- active-low 信号才使用 `_n`；核心内部同步高有效复位命名为 `rst`；
- testbench 顶层使用 `tb_<dut_name>` 命名；
- 工具产生的中间文件不放入 `rtl/`。

## 5. 第一项实现任务

第一份 RTL 是：

```text
rtl/rv32_pkg.sv
```

分四次完成：

1. package 外壳和流水动作枚举；
2. 数据通路与译码控制枚举；
3. 分层控制 packed struct；
4. 四组流水寄存器及公共小型数据包。

每次只增加一组相关类型，先解释位宽、编码和综合含义，再由用户手写并接受审阅。
