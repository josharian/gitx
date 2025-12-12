Run `./agent-build.sh` before sharing code changes, using with_escalated_permissions: true. It filters `xcodebuild` output to show only success or specific failures. Do *not* read the full log unless absolutely necessary—it's saved to `build/latest.log`.

## Tests

`./tests/line-staging/run.sh` tests the line staging/unstaging patch generation logic. Silent on success.
