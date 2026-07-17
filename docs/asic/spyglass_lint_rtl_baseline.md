# SpyGlass lint/lint_rtl Baseline

## Run Configuration

- Date: 2026-07-17
- Tool: Synopsys SpyGlass L-2016.06
- Top: `rv32_core`
- Goal: `lint/lint_rtl`
- Source list: `filelists/rv32_core_rtl.f`
- Technology library: not required for this goal

## Result

- Command-line read: 0 errors, 0 warnings
- Design read: 0 errors, 0 warnings
- Blackbox resolution: 0 errors, 0 warnings
- SGDC checks: 0 errors, 0 warnings
- Policy lint: 0 errors, 76 warnings
- Waived messages: 0

The source set parsed and elaborated successfully, and SpyGlass detected
`rv32_core` as the only top-level design unit. This is a successful baseline
run, but it is not yet a lint-clean quality gate.

## Warning Classification

### W415a: 55 warnings

The reported signals are assigned more than once in the same combinational
process. They are not driven by multiple processes.

- 48 warnings come from assigning an entire packed struct to zero and then
  assigning every required field. These can be removed by eliminating the
  redundant whole-struct assignment after core verification is frozen.
- 7 warnings come from intentional next-state logic in `rv32_ifu` and
  `rv32_lsu`: default `d = q`, followed by event-priority overrides. This
  hardware pattern should remain and receive narrowly scoped justification.

### W240: 18 warnings

- 4 warnings are disabled v0.1 coprocessor response inputs.
- 4 warnings are `id_ex_t` fields not consumed by `rv32_exu`.
- 10 warnings are `ex_mem_t` fields not consumed on one side of `rv32_lsu`.

These warnings result from deliberate stage-bundle interfaces and reserved
extension ports. Refactoring the interfaces into scattered scalar ports would
reduce lint messages but make the pipeline contract less coherent.

### W528: 3 warnings

The three messages are the fields of one `mem_exception` bundle produced by
`rv32_lsu` and not consumed by `rv32_core`. v0.1 requires `rsp_error = 0` and
does not implement trap handling, so the exception-commit path is deliberately
deferred. This warning must remain documented and its waiver must expire when
v0.2 exception handling is implemented.

## Remediation Order

1. Wait for the current core regression to finish and freeze the RTL baseline.
2. Remove redundant packed-struct zero assignments where every field already
   has an unconditional assignment.
3. Re-run all unit and core regressions.
4. Re-run SpyGlass and confirm the expected W415a reduction.
5. Add only object-scoped waivers for intentional state-update, bundle-interface
   and deferred-extension warnings.

No broad rule-level waiver is permitted.
