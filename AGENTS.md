# AGENTS.md — Uri Reconstruction Instrument

## Working Conventions

- Write product shell code for POSIX `sh`, using `#!/bin/sh` and `set -e` as the baseline.
- Prefix internal functions and local variables with an underscore; expose externally callable functions without one.
- Reuse the existing shared abstractions for output, YAML processing, and temporary resource management.
- Write shell completion code in the native syntax of its target shell; it is exempt from the POSIX `sh` rules that apply to product shell code.
