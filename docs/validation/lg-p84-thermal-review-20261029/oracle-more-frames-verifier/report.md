# LG schema7 additional-frame verification — 2026-10-30

Completed both authorized triplets at 600.032766667 s and 720.052666667 s. Each triplet used original UV → captured A0 UV → original UV, fresh processes, one A/B pair per process. Both completed with all per-round settings restored and the application stopped.

## Environment and inputs

- Workspace HEAD: `3bdf2c6cd21860c1c258d0b75f807b743d373e4a`; dirty baseline preserved in `baseline.json`.
- Device: LG `LGH870DS42e27764`, installed APK expected and checked per round: `36188b7a822de771be790a29d100d8ec2eff6313a0520c0e2e9845c208e85f72`.
- Brightness/backlight: 64 during capture; expected panel thermal status: 0. Every recorded GPU and panel thermal snapshot was 0.
- Source: historical full-byte `local-source.json` receipt plus current per-round file-size checks. This run did not perform a new full source hash.
- ROI: producer-fixed central 64×64 at x=1304, y=636; one pair A1→barrier→B1, then the original A1 CSC overwrites B before the sole swap.

## Results

| PTS | Mode | UV | Sample RGB | Pre RGB | Half RGB | YUV | PID |
|---|---|---:|---:|---:|---:|---:|---|
| 600.032766667 | 01-original | 1634 | 7 | 21 | 4 | 12 | 23240 |
| 600.032766667 | 02-oracle | 0 | 0 | 0 | 0 | 0 | 24217 |
| 600.032766667 | 03-original | 1634 | 7 | 21 | 4 | 12 | 25198 |
| 720.052666667 | 01-original | 1634 | 10 | 23 | 7 | 18 | 26225 |
| 720.052666667 | 02-oracle | 0 | 0 | 0 | 0 | 0 | 27193 |
| 720.052666667 | 03-original | 1634 | 10 | 23 | 7 | 18 | 28149 |

Values are counts of bit-different captured float components. Both oracle rounds were bit-equal for these captured fields. Both endpoint original rounds reproduced their exact differences.

Independently reran the analyzer on all six manifests; output exactly matched archived analysis. Recomputed every file size and SHA-256. Within each PTS triplet, four actual shader/body sources were identical, all A fields and Android A1 data were identical, and all seven endpoint files were byte-identical. Per-pixel sidecar/dependency and execution gates passed in every round. `verification.json` records checks, input-tool hashes, counts and all file hashes.

## Commands and raw evidence

The same command template was run serially with PTS/output changed:

```text
python3 tool/lg_p84_capture_round.py --serial LGH870DS42e27764
  --output docs/validation/lg-p84-thermal-review-20261029/capture-oracle-single-triplet-{600|720}
  --pts {600.032766667|720.052666667}
  --source-receipt docs/validation/lg-p84-thermal-review-20261029/local-source.json
  --expected-apk-sha256 36188b7a822de771be790a29d100d8ec2eff6313a0520c0e2e9845c208e85f72
  --brightness 64 --expected-backlight 64 --expected-panel-thermal-status 0
  --allow-unprotected-menu --repeat --sample-tap --oracle-triplet --oracle-probe --single-pair
```

Each command exited 2 because endpoint original captures contain float differences; each summary status is `completed-oracle-triplet`, reason null, restorationVerified true, verification `validated-triplet-evidence`. This is an expected diagnostic outcome, not an environment failure.

- `600-command.log`, `720-command.log`: command summaries.
- `../capture-oracle-single-triplet-600/` and `../capture-oracle-single-triplet-720/`: all raw logs, commands, original/restored state, captures and manifests.
- `*-reanalyzed.json`: independent analyzer reruns, with no changes to original evidence.

## Interpretation and limits

In these two fixed-frame central ROIs, supplying the captured A0 UV eliminates the observed downstream differences; restoring original UV reproduces them. This extends the earlier 35.035 s observation to two more PTS values. It does not establish full-frame equivalence, other ROIs, an interpolation/compiler/driver root cause, uninstrumented production equivalence, raw NV12 or panel equality, performance or power benefit, or resolution of the independent B2 zero-read issue. Different PTS values sample the same central ROI geometry. Each process contains one pair, so within-process repeatability is not measured; equal B source bytes across processes do not imply the same physical GL program instance. The oracle retains A rendering and is a diagnostic intervention, not a deliverable optimization.

## Worktree protection

No implementation, native source, tool or existing evidence was modified by this verifier. Tool hashes at end match the recorded baseline. Created only the three new evidence directories named in `verification.json`; existing dirty state was retained. Other agents were active; final `gitStatus` is recorded for comparison, without cleanup or attribution of unrelated changes.
