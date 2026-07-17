# Remote ASIC Execution

The wrapper connects to a user-provided SSH target and executes the repository's
SpyGlass flow on that host. Keep machine names, installation paths, and license
locations in environment variables rather than committing them to the repository.

Configure all required values, then run the remote SpyGlass goal from the local
repository root:

```bash
export ASIC_REMOTE_HOST=eda-host
export ASIC_REMOTE_ROOT=/path/to/5stagebymyself
export ASIC_REMOTE_SPYGLASS_HOME=/path/to/SPYGLASS_HOME
export ASIC_REMOTE_LICENSE_FILE=/path/to/Synopsys.dat
bash scripts/remote/run_spyglass.sh
```

The wrapper uses key-only SSH and explicitly exports the remote SpyGlass and
license paths, so it does not depend on an interactive `.bashrc`.

`ASIC_REMOTE_HOST` may be a hostname or an alias configured in `~/.ssh/config`.
Do not commit private keys, credentials, license contents, or real machine paths.

This wrapper executes the files already present in the remote checkout. Source
synchronization remains an explicit Git or `rsync` step.
