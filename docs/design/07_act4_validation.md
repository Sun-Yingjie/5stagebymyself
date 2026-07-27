# V1 ACT4 冻结回归合同

## 1. 定位与结论边界

本项目使用 RISC-V Architectural Certification Tests 第四代框架（ACT4），为当前
`RV32IM_Zicsr + finite M-mode` 实现建立可复现的官方架构测试入口。ACT4 回归与
V1 Spike 差分互补：前者扩大官方指令测试覆盖，后者逐事件比较同一个 ELF 的 retire
和访存轨迹。

ACT4 项目明确说明这些测试面向架构认证，不是完整处理器验证。因此本文中的通过只
表示“冻结 profile 下选中的 53 个自检 ELF 在 DUT 上通过”，不等价于：

- 完整 Sm、Zicntr、S/U mode 或中断行为通过；
- MC100/RVCP 认证证书；
- 随机、formal、差分或 ASIC signoff 已被替代。

官方入口与本文采用的固定资料如下：

- [ACT4 仓库 README（固定 revision）](https://github.com/riscv/riscv-arch-test/blob/072ed2e3d205ac9964a93c23759a9cc1a949b784/README.md)；
- [固定 ACT4 commit](https://github.com/riscv/riscv-arch-test/commit/072ed2e3d205ac9964a93c23759a9cc1a949b784)；
- [添加自定义 DUT/config 的官方指南](https://github.com/riscv/riscv-arch-test/blob/072ed2e3d205ac9964a93c23759a9cc1a949b784/docs/DeveloperGuide.md#adding-a-new-simulator-or-dut-config)；
- [Certification Test Plan](https://riscv.github.io/riscv-arch-test/ctp.html)；
- [Sail RISC-V 0.13 release](https://github.com/riscv/sail-riscv/releases/tag/0.13)。

ACT 源文件按文件声明 BSD-3-Clause 或 Apache-2.0，文档使用 CC-BY-4.0；本仓库只
保存 DUT config、适配宏、冻结 manifest 和 runner，不复制 ACT 测试源。

## 2. 冻结版本与 profile

唯一机器可读冻结源是 `verification/act4/profile.lock.json`：

| 项目 | 冻结值 |
|---|---|
| ACT4 repository | `https://github.com/riscv/riscv-arch-test.git` |
| ACT4 revision | `072ed2e3d205ac9964a93c23759a9cc1a949b784` |
| reference model | `sail-riscv 0.13` |
| DUT profile | `five-stage-rv32im-zicsr` |
| 执行扩展 | `I 2.1 + M 2.0 + Zicsr 2.0` |
| privilege tests | `include_priv_tests=false` |
| reset / test base | `0x80000000` |
| memory window | `0x80000000..0x8003ffff`，256 KiB |
| `tohost` / `fromhost` | `0x8003fff0` / `0x8003fff8` |
| pass / fail 值 | `tohost=1` / `tohost=3` |

runner 在生成测试前强制检查 ACT4 HEAD、tracked worktree clean、Sail 完整版本串、
cross GCC 主版本（至少 15）、冻结 manifest 数量，以及适配配置的 SHA-256。版本不符
不会降级为 warning。

报告另外保存当前项目 Git HEAD、dirty 状态、完整 `git status --short` 列表和 tracked
diff SHA-256。项目 worktree dirty 不直接失败，因为 DUT 可在未提交状态验证；真正参与
运行的 RTL、filelist、program TB、runner 和 helper 由逐文件 SHA-256 绑定。

## 3. 为什么 UDB 中出现 Sm

UDB configuration 为了描述 M-mode 执行环境而声明 `Sm 1.12.0`，但 DUT 并不声称
实现完整标准 Sm：

- `include_priv_tests=false`，不选择 Sm/Sdtrig privilege tests；
- `rvmodel_macros.h` 不定义 `STANDARD_SM_SUPPORTED`；
- `RVMODEL_BOOT_TO_MMODE` 为空，避免标准 Sm boot 访问 DUT 未实现的
  `mcountinhibit`、`mhpmevent*` 等 CSR；
- 没有声明 Zicntr，ACT4 不选择 counter 测试；
- 没有声明 C、S、U、PMP 或 Zifencei。

因此本回归只对 I/M/Zicsr 的适用测试作结论。`sail.json` 同样关闭 U、S、Zicntr、
Zifencei 等能力，避免参考模型 profile 与 DUT profile 漂移。

## 4. 冻结测试集合

`verification/act4/expected_tests.txt` 按完整相对源文件名冻结 53 项：

| 扩展 | 数量 | 范围 |
|---|---:|---|
| RV32I | 39 | 算术、逻辑、移位、分支、跳转、load/store、fence/nop |
| RV32M | 8 | mul/mulh/mulhsu/mulhu、div/divu、rem/remu |
| Zicsr | 6 | csrrw/csrrs/csrrc 及三个 immediate 变体 |
| 合计 | 53 | manifest 中逐项列出 |

ACT4 实际生成集合必须与 manifest 一致。缺失任何冻结 ELF 总是失败；额外 ELF 默认
也失败，只有显式 `--allow-manifest-drift` 才允许额外项，而且额外项不计入通过数。
runner 对每个冻结测试都写出 `generated/run/pass/fail/skip` 状态，不允许静默跳过。

## 5. 256 KiB memory 与 mailbox 门禁

ACT4 指令测试包含远大于普通 smoke 的 signature/data 区。初始 16 KiB 方案在链接
`I-addi-00` 时即越界，不能作为 ACT4 profile。

对全部 53 个生成 ELF 的每一个 `PT_LOAD` 做 high-water 测量后，最大镜像为
`rv32i/I/I-jal-00.S`：

```text
load low             0x80000000
load high (exclusive) 0x80031c20
span                  203808 bytes (0x31c20)
PT_LOAD segments      3
```

最终窗口冻结为 256 KiB，结束地址（exclusive）为 `0x80040000`。最大镜像到窗口末端
余 58,336 bytes；扣除末尾 16-byte `tohost/fromhost` mailbox 后，可用余量为
58,320 bytes。linker 的 `_end <= TOHOST` assertion、runner 的逐 ELF PT_LOAD 门禁与
ELF converter 的窗口检查共同防止 image 覆盖 mailbox。

program TB 的 memory depth 必须来自同一个 lock 值。runner 编译 Icarus 时显式传入：

```text
-Ptb_rv32_program.MEM_BYTES=262144
```

不能依赖 TB 的 16 KiB 默认值。报告保存所有 53 项的 load low/high、span、segment
列表、到 mailbox 的剩余 byte，以及全局最大项。

## 6. 执行链

一次 `--phase all` 依次执行：

1. 校验冻结版本、工具、manifest 与 config hash；
2. 将配置复制到独立 work directory，并解析为绝对工具路径；
3. ACT4 用 Sail 0.13 生成参考 signature，再构建 I/M/Zicsr 自检 ELF；
4. 校验生成集合，为冻结的 53 个 ELF 逐项计算 SHA-256，并原子写入
   `elf_hash_manifest.json`；
5. 用 cross `readelf -lW` 检查全部 PT_LOAD；
6. 仅编译一次 256 KiB program TB，并记录生成 `.vvp` 的 SHA-256；
7. `elf_to_mem.py` 将每个 ELF 转为相同窗口的 sparse word hex；
8. 并行运行 DUT，自检程序通过固定 mailbox 返回结果；
9. 写出逐项日志与汇总 JSON，并返回非零状态表示任一失败。

ACT4 的 custom model abstraction 与 mailbox 适配方式可参照
[官方 abstraction 说明](https://github.com/riscv/riscv-arch-test/blob/072ed2e3d205ac9964a93c23759a9cc1a949b784/docs/ctp/src/abstraction.adoc)
和[官方 rvmodel 宏示例](https://github.com/riscv/riscv-arch-test/blob/072ed2e3d205ac9964a93c23759a9cc1a949b784/config/cores/cve4/cv32e40s-rv32imc/rvmodel_macros.h)。

## 7. 运行方法

工具既可通过参数传入，也可用 `ACT4_ROOT`、`SAIL_RISCV_SIM`、`RISCV_GCC`、
`RISCV_OBJDUMP`、`RISCV_READELF`、`IVERILOG` 和 `VVP` 环境变量提供：

```bash
python3 scripts/run_act4.py \
  --phase all \
  --act4-root /absolute/path/to/riscv-arch-test \
  --sail /absolute/path/to/sail_riscv_sim \
  --work-dir /absolute/path/to/act4-output \
  --jobs 8 --run-jobs 4
```

依赖预装在隔离路径时，可额外传入 `--uv`、`--ruby`、`--bundle`、
`--bundle-gemfile`、`--bundle-path`、`--xdg-cache-home` 和重复的
`--path-prepend`。runner 会让这些工具目录先于 macOS `/usr/bin`，避免误选系统旧版
Ruby/Bundler。

`--phase build` 只生成、核对并测量 ELF，同时写出冻结 ELF hash manifest。建立基线
前还有一条防吸收门禁：若同一 work directory 已有 hash manifest，runner 必须在
调用 make 前验证现有 53 个 ELF，并在 make 后用同一 manifest 再验证一次，绝不
覆盖原基线；若没有 manifest，则 ELF 输出目录必须为空。这样被篡改的 up-to-date
缓存不会被一次 build 静默吸收为新的可信 hash。

`--phase run` 复用已生成 ELF，但必须先读取同一 `work-dir` 中上次成功 build 生成的
manifest，并对 53 项逐一核对路径对应内容的 size 和 SHA-256；manifest 缺失、格式
错误、build-input binding 漂移、条目缺失/多余或任一 ELF 被修改都会在编译 DUT 前
显式失败。`--phase all` 则在本次 build 后生成 manifest 并直接使用同批 ELF。

两种模式仍执行相同冻结检查。`--max-cycles` 是 DUT 架构周期上限，
`--wall-timeout` 是单例宿主时间上限。

## 8. 报告与失败语义

默认工件位于 `out/act4/`，也可由 `--work-dir` 改到临时目录：

```text
report.json                         总状态、版本、工具、hash、manifest、计数
elf_hash_manifest.json              上次 build 冻结的 53 项 ELF size/SHA-256
logs/act4-build.log                 ACT4/UDB/Sail/build 完整输出
logs/tb.compile.log                 含 MEM_BYTES 参数的 Icarus 编译命令
runs/<extension>/<test>/convert.log ELF 转换日志
runs/<extension>/<test>/simulation.log
runs/<extension>/<test>/trace.jsonl DUT 架构事件轨迹
```

`report.json` 的计数始终包含 `selected/generated/run/pass/fail/skip`。setup、版本、build、
manifest、PT_LOAD、转换、timeout、mailbox fail 或模拟器异常均返回非零；在无法运行时，
每个冻结项显式记为 skip 并附原因。只有 `pass=53, fail=0, skip=0` 才是本 profile 的
ACT4 通过。

`report.json` 的 provenance 字段冻结：

- `provenance.project_git`：项目 HEAD、dirty、status 列表和 tracked diff SHA-256；
- `provenance.inputs.dut_rtl_and_filelists`：DUT RTL 与 Core filelist；
- `provenance.inputs.program_tb_and_filelist`：实际 program TB 与 filelist；
- `provenance.inputs.runner`、`elf_to_mem_helper`：两个执行脚本；
- `provenance.inputs.act4_config`、`profile_lock`、`expected_tests_manifest`：ACT4
  profile 的本地冻结输入；
- `provenance.tools.<name>`：实际解析后的 executable path、文件 SHA-256 和
  `hash_status`；脚本型工具直接 hash 脚本文件，无法读取时 `sha256=null` 并保存
  `hash_error`，不会静默省略；
- `provenance.generation_tools`：Sail、cross GCC、cross objdump、make 和 Bundler
  各自的 resolved path、SHA-256 与 version；Bundler 未安装时显式记录
  `hash_status=unavailable`。这些字段与 ACT4 revision、clean/dirty status、tracked
  diff hash、profile/config/expected manifest hash 一起写入 ELF generation binding；
- `elf_hash_manifest` 与 `elf_sha256`：本次创建/验证的 manifest 身份和 53 项 hash；
- `simulation_binary`：实际执行的 `tb_rv32_program.vvp` path、size 与 SHA-256。

runner 启动后、读取 lock 或检查工具之前，就用原子 `temporary + replace` 写入
`report.json`，状态为 `running` 并生成新的 32-hex `run_id`。正常结束或任何已捕获
错误都用同一个 `run_id` 原子覆盖最终状态。复用 work directory 时，即使进程被 kill
或 host crash，留下的也只能是本次 `running`，不会继续暴露上一次的旧 `pass`。

## 9. 2026-07-27 冻结回归事实

新版 provenance schema 在全新 work directory 的最终 `--phase all` 结果：

```text
ACT4 revision:  072ed2e3d205ac9964a93c23759a9cc1a949b784
Sail:           0.13
cross GCC:      15.1.0
I / M / Zicsr:  39 / 8 / 6
selected:       53
generated:      53
run:            53
pass/fail/skip: 53 / 0 / 0
manifest drift: missing=0, extra=0
ACT build:      212 succeeded (fresh output directory)
ELF manifest:   mode=created, 53 hashes verified
report run_id:  2cfc500f3ec147c999a70684a0fdcbab
```

Icarus 的 53 个 simulation 均返回 0，trace 末项均为 `status=pass, tohost=1`；合计
418,198 个 DUT cycle、139,082 次 retirement 和 214,068 条 trace event。单例 cycle
范围为 384～32,854，未触及 2,000,000-cycle 上限。对报告进行独立只读审计时，
53 份 `readelf` PT_LOAD、converter metadata 和报告 footprint 三方完全一致；逐例
convert/simulation log 及 trace 均存在且非空。

本次本机工件保存在任务专用临时目录，未纳入 Git。独立只读审计重算并核对了 53 个
ELF、29 项项目输入、12 个工具、VVP 和 ELF manifest 的 SHA-256；ACT4 checkout
保持固定 HEAD、tracked clean 和空 diff hash。长期结论以本文的冻结 profile、命令、
数量、`run_id` 与边界为准。

## 10. 环境限制与后续边界

本次隔离的 macOS arm64 环境已成功完成 53 项回归。ACT4/UDB 0.1.14 在其他 cache
状态下仍可能误取 Linux `libz3.so`；遇到该问题时应使用官方 Linux 环境，或在任务专用
`XDG_CACHE_HOME` 中提供版本匹配的 macOS arm64 Z3 library，不要覆盖系统 Ruby、
系统 Z3 或全局 cache。此类 host dependency 修正不改变冻结 ACT4/Sail/DUT profile。

这 53 项不覆盖 interrupt 注入、WFI wakeup、MRET 精确返回、cycle counter 时序、
access fault platform map 或随机 backpressure。它不能替代 D5 campaign，也不能把
Spike 在含 C 的默认最大 ISA 下的 `mepc/IALIGN` 行为当作本 no-C DUT 的 Zicsr
oracle；完整 V1 仍使用已冻结的同 ELF 差分合同和明确的适用程序集合。
