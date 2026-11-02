# Standalone LG half-equivalence quality gate

Verdict: **FAIL-quality-gate**, remote exit file and adb shell exit both 3. One authorized execution only, with host timeout 40s and program alarm 30s. Binary push was followed by complete byte readback matching SHA256 2ef551fd1d3b401b19b14030ccc89afc889e18be35d270fff7b23abb23856f10.

Completed=true, stage=complete; integer readback and input transfer passed, all input normal/subnormal/nonfinite transfer mismatch counts zero. Capture coverage sentinel checks completed without error. GL error count zero, cleanup complete. On Adreno 530, finite input quantization bit mismatches=24538; finite CSC output mismatches=24570; PQ-domain mismatches=4225 / 12282. This is a numerical quality failure, not an execution-permission or unsupported result.

First quantization difference: pixel11/channel0 baseline b3800000 (-5.960464477539063e-8) versus candidate 80000000 (-0.0). This observes finite nonzero versus signed negative zero; the exact compiler/driver cause is not established. No tolerance or fallback variant was applied.

Probe PID8801 no longer exists; no matching probe processes remain. Postflight GPU thermal level0/max652800000Hz, CPU2 max2342400kHz, battery31.3C/VTS34.6C. Original five system settings unchanged, panel HDR remains0, screen remains ON. No App or video was launched and no system setting changed. Only the unique test directory/binary/output files were added on device.

Evidence: execution.json, build-receipt.json, remote-command.sh, binary-readback.stdout, exit.txt, stdout.txt, stderr.txt, result.json, verdict.json, preflight/postflight logs. Workspace baseline/after files retain unrelated dirty state; this task wrote only this evidence directory and did not modify implementation. Standalone synthetic EGL comparisons do not establish media-frame/YUV/panel equivalence.
