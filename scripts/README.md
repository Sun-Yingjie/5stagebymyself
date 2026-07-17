# ASIC Scripts

The ASIC flow uses `rv32_core` as the synthesis and signoff top module.
Generated tool databases, logs and waveforms belong under `build/` or
`reports/` and are ignored by Git.

Planned order:

1. `spyglass`: RTL static checks
2. `dc`: synthesis and constraint checks
3. `fm`: RTL-to-gate equivalence
4. `pt`: post-synthesis, pre-layout STA
5. `gls`: representative gate-level smoke tests

The common synthesizable source list is
`filelists/rv32_core_rtl.f`. Testbench and memory-model files must not be
added to that list.
