# Spike differential harness

The executable entry point is:

```bash
python3 scripts/run_differential.py --compile-timeout 180
```

RTL compilation has its own 180-second default timeout. `--timeout` remains the
30-second limit for all other tool and run commands; use `--compile-timeout`
when a loaded or parallel machine needs a larger compile budget.

It builds `tb/program/smoke.S`, runs the same ELF on Spike and the RTL program
testbench, and compares ordered retire and memory-side-effect streams. The fixed
profile is `RV32IM_Zicsr`, Machine-only, `_start=0x80000000`, with a 16 KiB
default memory window. `--memory-size` changes that window and is propagated to
the ELF converter, TB `MEM_BYTES` parameter, and Spike; 1 MiB is tested.

This lane is explicitly trap-free: Spike starts with `mtvec=0`, while the DUT
reset state uses `mtvec=0x80000300`. Before architectural comparison, any Spike
trap event, DUT trap event, or nonzero/missing DUT summary trap count forces a
mismatch. Trap handling, MRET, interrupts, WFI wakeup, cycle-counter values, and
access-fault equivalence are intentionally outside this differential profile.

The default artifact directory is a retained temporary directory printed by
the runner. Use `--build-dir` to choose an explicit location. The decisive
files are `comparison.json`, `first_divergence.json`, `dut.jsonl`,
`spike.jsonl`, and `spike.log`. When an explicit directory is reused, the
runner atomically replaces the two decisive result files with a new `run_id`
and `running/pending` state before tool preflight. A terminal pass, mismatch,
or error then atomically replaces them again. `first_divergence.json` is
therefore always current: its status is `pending`, `none`, `mismatch`, or
`error`, instead of leaving a previous mismatch behind after a later run.

Run the intentional trace-corruption negative test with:

```bash
python3 -m unittest \
  verification/differential/test_comparator.py \
  verification/differential/test_artifact_lifecycle.py
```

`manifest.json` records the same `run_id`; Git HEAD plus porcelain status;
SHA-256 for both filelists and every referenced RTL/program-TB source, the
runner, ELF converter, program/linker (or provided ELF), generated ELF/image,
and compiled VVP; and the resolved executable plus SHA-256 for every tool. It
is also atomically replaced. Unsupported filelist syntax is an error rather
than a silently incomplete provenance list.

The detailed contract, trace schema, comparison fields, and evidence boundary
are defined in `docs/design/06_differential_validation.md`.
