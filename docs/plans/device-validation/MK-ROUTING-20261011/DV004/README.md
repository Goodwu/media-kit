# DV004 integration disposition

PR6 source: `9a2c5768dd10e71975b7c3e76bb7125460a43e5b`. Public integration parent: `ebb00b8a0dedec42a68b84a4ec6e7dffb6c17f02`. The two files in `source-snapshot/` retain the exact original bytes and use non-executable `.txt` paths. Their hashes are in `docs/plans/core-device-integration-20261012.json`.

This merge retains the public `gatherDecoderReviewFacts` production file and its existing cross-round decoder-change rejection test. It imports the two compatible final-plan rejection cases, adapting the MIME case to describe its actual complete-first-round fixture and removing its unreachable `betweenRounds` callback. No temporary diagnostics were enabled.

The PR6 proposal to authorize only the first complete sample, its logical-name-publication positive case and associated helper are not enabled. Actual decoder-identity sequence evidence and the user's diagnostic/acceptance-semantic decisions remain open. The original REQUEST_CHANGES findings are not closed by source ancestry integration.

Future DEVICE updates must compare against this disposition as well as Git ancestry: the PR6 source commit is a merge parent, but its production policy was deliberately retained as the public version. A clean incremental merge does not prove that deferred behavior has been resolved or accepted. Continue the original DEVICE work line and central PR4 coordination.
