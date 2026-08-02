# D5 可重复随机回归与设计冻结合同

## 1. 状态与目的

本文冻结 D5 的执行合同。D5 不新增 ISA 或微架构能力，而是在 D0～D4 的固定
`RV32IM_Zicsr + M-mode-only` RTL 上增加可重复、可批量报告的随机等待验证。

当前实现包含四路随机 backpressure 驱动、一个固定架构程序、Core 在线 scoreboard、
机器可读单次结果和标准库批量 runner。D5 只有在本文第 10 节的完整 campaign 门禁
全部通过后才能标记为完成；单个 seed 通过只表示基础设施可运行。

默认 directed 回归必须保持随机功能关闭。D5 不允许为了让随机测试通过而弱化原有
retire、trap、DMem、协议或流水不变量。

## 2. 随机化边界

现有 IMem/DMem 模型各有两个环境控制输入：

| 随机 gate | 被控制的行为 | 不允许改变的行为 |
|---|---|---|
| IMem request allow | `imem_req_ready` 何时允许请求握手 | DUT 的 request valid/address |
| IMem response allow | 已接受请求的 response 首次何时可见 | 已出现的 valid/data/error |
| DMem request allow | `dmem_req_ready` 何时允许请求握手 | DUT 的 write/address/data/strobe |
| DMem response allow | 已接受请求的 response 首次何时可见 | 已出现的 valid/data/error |

随机驱动不能直接修改 Core 产生的 valid、payload 或 ready，也不能在事务进行中修改
memory/error map。IRQ 不做逐拍毛刺式随机；后续加入 IRQ episode 时，只能由 seed
预先确定 source、架构触发边界和有界 hold 时间，并在时钟安全边界驱动。

Core TB 保留原来的四个 scenario enable。模型实际 enable 为：

```text
scenario_enable && (!d5_random_active || random_allow)
```

因此 directed task 和随机驱动始终是各自信号的唯一写者，不存在多个 procedural
driver，也不会改变 `+D5_ONLY` 以外的场景。

## 3. Valid-ready 安全性

request allow 只控制接收端 ready。ready 可以在尚未握手时变化，而 DUT source 必须
在 `valid && !ready` 时保持 valid 和完整 payload；Core TB 的逐拍 monitor 继续检查
这一点。

response allow 只控制 response 的首次出现。IMem/DMem 模型在 request handshake 时
快照 data/error；一旦 response valid 出现，`response_started_q` 会锁住 valid，直到
`valid && ready`。随机 allow 随后变低也不能撤销 response 或改变 payload。

模型继续保持每通道最多一笔 outstanding，并允许 response 完成与下一 request 在
同一拍交接。随机驱动不得破坏这一 turnover 语义。

## 4. PRNG 与跨模拟器可重复性

随机源固定为 32 位 `xorshift32`：

```text
x ^= x << 13
x ^= x >> 17
x ^= x << 5
```

每个活动周期按固定顺序生成四个 word，依次用于 IMem request、IMem response、
DMem request、DMem response。无论当前是否存在 demand，每周期都消费四次状态，
避免测试行为改变随机流位置。

不使用 `$urandom`、constraint random、class、queue 或 covergroup。这样 Icarus 与
Verilator 对同一 seed 应产生相同 gate 序列。输入 seed 为 0 时，effective seed 固定
替换为 `0x6d2b79f5`，防止 xorshift 锁死在零状态。

随机 gate 在 `posedge clk` 使用 nonblocking assignment 生成下一周期值。它不与
scenario 的 negedge 控制发生采样竞态。

## 5. 概率与公平性

`STALL_PCT` 表示每路 gate 在未达到公平性上限时选择 low 的百分比。四路各自维护
连续 low 计数。若此前已经连续 low `MAX_STALL` 拍，则下一拍强制 high，并记录一次
forced grant。

因此 `MAX_STALL=N` 的精确定义是：任一路随机 gate 最多连续为 low N 个完整周期；
`MAX_STALL=0` 表示 gate 永远允许。即使 demand 恰好在 low streak 中间出现，也不会
发生无限饥饿。随机回归的 timeout 仍是错误保护，不承担公平性保证。

参数合法范围为：

- `STALL_PCT`: 0～100；
- `MAX_STALL`: 0～1024；
- `TIMEOUT`: 大于 0。

## 6. Plusarg 与运行模式

Core TB 接受：

```text
+D5_ONLY
+SEED=<32-bit hexadecimal>
+STALL_PCT=<0..100>
+MAX_STALL=<0..1024>
+TIMEOUT=<positive cycles>
+TRACE
+DUMP=<waveform path>
```

默认值为 seed `00000001`、stall 50%、最大连续等待 8 拍、D5 timeout 10000 拍。
不带 `+D5_ONLY` 时 timeout 仍为原 directed 值 600，随机驱动关闭，原 51 个场景的
执行顺序和逐拍控制不变。

`+TRACE` 用于失败重放，不用于普通 campaign。`+DUMP` 复用现有 VCD 接口；
Verilator binary 必须以 `--trace` 构建。

## 7. 固定 D5 程序与 oracle

当前 `d5_random_backpressure` 是固定程序，seed 只改变时序，不改变架构期望。程序
覆盖：

- IMem request/response 随机等待；
- word store/load、load-use 依赖和 DMem request/response 随机等待；
- `MUL`、`DIV`、MDU 后继依赖；
- taken branch、JAL 及 wrong-path store 抑制；
- WFI 合法 hint；
- ECALL、trap-vector fetch、handler retirement 和 trap 后年轻 store 抑制。

同一 Core scoreboard 精确比较 17 次 retirement、1 次 trap、4 次 DMem request 和
2/2 次 MDU request/response。随机 fetch bubble 可以合法改变 late-result hazard 的
出现次数，因此 D5 不把该微架构计数与 directed 场景的固定值比较；retire、trap、
DMem、MDU、redirect 及所有通用协议断言仍保持严格。

达到最后一个期望 retirement/trap 后不能立即结束。TB 关闭新的 IMem request，并继续
执行 `MAX_STALL+8` 拍排空窗口；窗口开始及每一拍都要求无 DMem request/response、
无 LSU outstanding、MDU idle、无 MDU request/response、无 held EX operation。已在
trap handler 后进入流水的默认 NOP 可以退休，但任何其他 retirement、trap、DMem 或
MDU 事件都会失败。这样随机 ready 暂时为低时，迟到的错误 store 不能躲过最终检查。

后续若增加随机 IRQ episode，必须继续使用提前建立的独立 expected queue，不能用
DUT 的 interrupt 输出作为结果 oracle。

## 8. 覆盖代理与单次结果

每次 D5 运行只输出一条机器可读结果：

```text
[D5_RESULT] status=... seed=... cycles=... ... coverage=... state=...
```

结果包含架构事件数、四类 demand-qualified stall/delay、四路 gate low 总数、forced
grant、最大 low streak、最终 PRNG state 和 coverage bitmap。

当前 bitmap 定义：

| Bit | 覆盖代理 |
|---:|---|
| 0 | IMem request 确实受到 backpressure |
| 1 | IMem response 首次出现被延迟 |
| 2 | DMem request 确实受到 backpressure |
| 3 | DMem response 首次出现被延迟 |
| 4 | Core 出现 EX request wait |
| 5 | Core 出现 MEM response wait |
| 6 | 程序发生控制流 redirect |
| 7 | 程序进入 MDU multicycle wait |
| 8 | 程序观察到同步 trap |
| 9 | 至少一路触发过公平性 forced grant |

单个 seed 不强制命中所有概率性 bit；batch aggregate 必须命中 bit 0～8。Bit 9 在
release campaign 中必须命中，用来证明 low-run cap 路径实际执行过。

## 9. 批量 runner 与失败工件

统一入口为：

```bash
python3 scripts/run_random_regression.py
```

runner 只使用 Python 标准库，每个 simulator 编译一次并为全部 seed 复用 binary。
结果默认保存在被 `.gitignore` 排除的 `out/d5/<UTC timestamp>/`：

```text
config.json                 参数、工具版本、Git 状态、输入 SHA-256
build/<sim>/compile.log     编译日志与复用 binary
runs/<sim>/seed_*/run.log  每个 seed 的完整输出
summary.jsonl               每个运行一条 JSON
summary.csv                 表格化结果
summary.json                campaign 汇总和跨模拟器差异
```

首个失败 seed 会自动使用相同 binary、seed 和参数，以 `+TRACE +DUMP` 重跑，并保存
`replay.sh`、`replay.log` 和 `failure.vcd`。`replay.sh` 必须能原样复现同一首个失败。

runner 将请求 seed 与 DUT 回显 seed 分开保存，要求每个期望
`(simulator, requested_seed)` 恰好出现一次，并拒绝重复输入、重复结果、缺失结果和
额外结果。`[D5_RESULT]` 的完整字段必须存在、可解析；固定 oracle 必须为 17 retire、
1 trap、4 DMem、2/2 MDU、0 interrupt。若同时运行 Icarus 与 Verilator，runner 再
比较同 seed 的全部架构计数、等待统计、coverage 和最终 PRNG state；两个缺失结果
不能被当成相等。

## 10. D5 完成门禁

### 10.1 基础设施 smoke

```bash
python3 scripts/run_random_regression.py \
  --sim both --seeds 1,7,42,20260727
```

### 10.2 Release campaign

```bash
python3 scripts/run_random_regression.py \
  --sim both --seeds 1..64 \
  --stall-pct 50 --max-stall 8
```

### 10.3 高等待 stress

```bash
python3 scripts/run_random_regression.py \
  --sim both --seeds 1,17,20260727,a5a55a5a \
  --stall-pct 85 --max-stall 32 --timeout-cycles 20000
```

D5 只有同时满足以下条件才完成：

1. 随机关闭时当前 17/17 unit 和 51/51 Core directed 双模拟器回归不变；
2. smoke、release 和 stress 全部零失败、零 timeout；
3. 同 seed 的 Icarus/Verilator 结果字段一致；
4. 没有 valid-ready、outstanding、payload stability、scoreboard 或 X/Z 错误；
5. aggregate coverage bitmap 命中 bit 0～9；
6. 用故意过短的 `--timeout-cycles` 执行一次失败工件自检，并证明 `replay.sh` 可复现；
7. 精确记录工具版本、输入 SHA-256、pass/fail 数和任何限制。

Verilator line/toggle coverage 可以作为额外证据，但不得用百分比替代上述功能与协议
门禁。ACT4 和参考模型差分属于 V1，不计入 D5 的通过数量。

## 11. 文件边界

D5 基础设施只修改 testbench、runner 和本文档：

- `tb/core/rv32_backpressure_driver.sv`；
- `tb/core/tb_rv32_core.sv`；
- `tb/core/rv32_core_tb.f`；
- `scripts/run_random_regression.py`；
- 本文档及最终验证事实文档。

D5 原则上不修改 RTL。若随机回归发现真实 DUT 缺陷，必须保留失败 seed/波形，单独
说明根因和 RTL 修复，再重跑 directed、D5 和后续 V1 门禁。
