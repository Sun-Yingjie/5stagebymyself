# SpyGlass RTL Lint

## First run on the Ubuntu EDA machine

Load the site-specific Synopsys environment first, then run from the
repository root:

```bash
which spyglass
spyglass -version
bash scripts/spyglass/run_spyglass.sh
```

The first goal is `lint/lint_rtl`. It checks source parsing, elaboration and
basic RTL quality without using a technology library. The run must use only
`filelists/rv32_core_rtl.f`; testbench and memory-model files are excluded.

The wrapper writes its console log to `build/spyglass/lint_rtl.log`. SpyGlass
may also create a version-dependent project-results directory in the
repository root; those generated directories are ignored by Git.

When the first run fails, preserve the complete console output. Resolve errors
in this order:

1. executable, license and goal availability
2. project or file-list syntax
3. SystemVerilog parsing and top-module elaboration
4. RTL lint findings

Do not add broad waivers during the first run.
