# media-kit development branch policy (2026-10-28)

## Active branches

- `main`: keep the default, upstream-facing stable branch. Do not delete.
- `dev`: long-lived active integration/development branch. Initially copied exactly from the tested CI+compat integration HEAD `9c67f5305ec52fe9e12a86cdda295711161919f0`.
- Temporary topic branches: create from `dev`, integrate back through review, then retire when superseded.

## Superseded branches: archive before deletion

| Branch | Archived HEAD | Proposed lightweight tag | Open PR dependencies |
| --- | --- | --- | --- |
| `routing/MK-ROUTING-20261011` | `0597c8318ccf50f0824249ceeab310632efb84ab` | `archive/routing-20261011` | #4 (head) |
| `compat/piliplus-zero-change-20261018` | `c8c5aaab3ee777bcf1f2b87166695a9814c24772` | `archive/compat-20261026` | #7 (base) |
| `ci/verified-native-packages-20261023` | `d76622180dc9d082c9e690dd7d355f418627fb4a` | `archive/native-ci-20261023` | #7 (head), #8 (base) |
| `integration/ci-compat-20261028` | `9c67f5305ec52fe9e12a86cdda295711161919f0` | `archive/ci-compat-20261028` | #8 (head) |

GitHub comparison confirmed all four archived HEADs are ancestors of `dev`; tagging preserves named snapshots and PR references, rather than rescuing otherwise unreachable changes. **Tags and deletions are proposed, not yet performed.** Before deleting, close/retarget the relevant draft PRs as superseded and confirm no other active automation consumes those branch refs. Retain PR discussion/history.

## GitHub Actions migration scope

General ongoing validation now triggers on `dev` pushes: `.github/workflows/ci.yml` (full platform CI), `ci-compat-regression.yml` (verified native package / Android tooling / HDR Dart unit tests), and `managed-output-checks.yml` (architecture constraints). Their PR triggers still support review.

One-off or project-specific workflows with literal `compat/piliplus-zero-change-20261018`, `routing/MK-ROUTING-20261011`, or PiliPlusX `routing` dependencies were deliberately **not** mass-retargeted: inspect their purpose and upstream checkout refs first. In particular, `routing-handoff-sources.yml` and `routing-source-review.yml` bind real cross-repository branches; replacing them blindly would invalidate provenance.

Do not force-push rewritten history, merge superseded PRs redundantly, tag unverified app releases, or treat CI success as device playback validation.
