# Remote ASIC Execution

The default SSH target is `eda-host`, configured in the Mac user's
`~/.ssh/config`. The Ubuntu repository is expected at
`/path/to/5stagebymyself`.

Run the remote SpyGlass goal from the Mac repository root:

```bash
bash scripts/remote/run_spyglass.sh
```

The wrapper uses key-only SSH and explicitly exports the remote SpyGlass and
license paths, so it does not depend on an interactive `.bashrc`.

Machine-specific defaults can be overridden without editing the script:

```bash
ASIC_REMOTE_HOST=eda-host \
ASIC_REMOTE_ROOT=/path/to/5stagebymyself \
bash scripts/remote/run_spyglass.sh
```

This wrapper executes the files already present in the remote checkout. Source
synchronization remains an explicit Git or `rsync` step.
