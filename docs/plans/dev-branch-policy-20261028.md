# media-kit development branch policy (2026-10-28)

## Active branches (verified)

- `main` — default and upstream-facing stable branch, retain.
- `dev` — long-lived active development/integration branch; started from the reviewed CI+compat integration `9c67f5305ec52fe9e12a86cdda295711161919f0`.
- Temporary topic branches — branch from `dev`, review into `dev`, then retire after acceptance. Do not add more permanent release-specific branches without a real need.

## Retired branches: lightweight tags verified, branches deleted

| Deleted former branch | Original full HEAD | Verified lightweight tag | Historical PR |
| --- | --- | --- | --- |
| `routing/MK-ROUTING-20261011` | `0597c8318ccf50f0824249ceeab310632efb84ab` | `archive/routing-20261011` | #4 closed, unmerged |
| `compat/piliplus-zero-change-20261018` | `c8c5aaab3ee777bcf1f2b87166695a9814c24772` | `archive/compat-20261026` | #7 closed, unmerged |
| `ci/verified-native-packages-20261023` | `d76622180dc9d082c9e690dd7d355f418627fb4a` | `archive/native-ci-20261023` | #7/#8 closed, unmerged |
| `integration/ci-compat-20261028` | `9c67f5305ec52fe9e12a86cdda295711161919f0` | `archive/ci-compat-20261028` | #8 closed, unmerged |

The four historical commits were independently verified as ancestors of `dev` (`behind_by=0`). Archived tag refs were created **before deletion** and checked to point to the exact old HEADs. Only `main` and `dev` remain. No branch history was rewritten. PR #4/#7/#8 discussions were preserved with an explicit superseded-by-dev closure note; they were **not** merged again to `main`.

Archival run: https://github.com/Goodwu/media-kit/actions/runs/40665503968 — `archive-and-delete` success. The first attempted archive workflow on the prior commit failed at YAML parsing before taking any actions; the corrected workflow completed successfully. Its one-time write-capable workflow file has been removed from the active branch after the successful run (history remains available for audit).

These tags preserve source snapshots. They are **not** releases, application builds, binary identities, or device-validation claims.

## GitHub Actions migration

Normal development CI follows `dev`:

- Full CI: `.github/workflows/ci.yml`, including existing cross-platform jobs.
- Verified-native / Android tooling / HDR routing tests: `.github/workflows/ci-compat-regression.yml`.
- Output architecture checks: `.github/workflows/managed-output-checks.yml`.
- Compatible legacy `piliplus-*` / `ohos-dart-contracts` workflows and generic `routing-darwin-tests`, `routing-query-tests`, `routing-source`: replace former `compat` or `routing` push triggers with `dev`, preserving their existing source checks and path filters.

Historical cross-repository workflows `routing-handoff-sources.yml` and `routing-source-review.yml` remain manual-only because they intentionally reference the *other repository's* old PiliPlusX routing branch. `piliplus-ohos-adaptation.yml` and `piliplus-source-snapshot.yml` remain manual-only: GitHub returned 404 for `Goodwu/PiliPlus` `feature/ohos`, their required App branch. They are not represented as current automatic `dev` validation.

At the branch rename, verified-native/HDR unit tests and managed-output boundaries were passing. The comprehensive 23-job CI already had unrelated failures, including `media_kit_test` lockfile-resolution mismatches (same tracked pubspec/lock files on `main`) and Web failures; enabling `dev` CI does not certify full platform readiness. Device testing and native package freshness require independent checks.

## Future development rules

- Keep `main` and `dev` as the only permanent branches, never rewrite or remove archival tags.
- Treat native build receipt, binary identity, native capabilities, and device rendering as separate verification gates.
- Do not claim that closing an old Draft PR is equivalent to merging it into `main`.
