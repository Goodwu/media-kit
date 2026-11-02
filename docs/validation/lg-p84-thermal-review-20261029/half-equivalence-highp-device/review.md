# LG highp-small-rtz standalone gate

PASS on this synthetic dataset only. One explicit highp-small-rtz execution, binary SHA49436ad2ea195aa01917b4a38a9f18baef436f2d43a74ebd2f266bb17a6f9fa9 with full device byte readback match. Remote exit.txt=0 and adb shell exit0; completed=true/stagecomplete. Integer/input/capture coverage/cleanup checks pass, GLerror0. All761904 RGB components have zero quantization/CSC bit differences, including finite, nonfinite, signed-zero and PQ categories. No first mismatch exists.

Small baseline model scope is nonzero finite abs(input)<2^-14 only:24568 components, RTZ matches24568/mismatches0; RNE matches15358/mismatches9210; RTZ-only9210/neither0. Domain coverage also includes normal/larger finite737302 and nonfinite18, but this is not a whole-domain GPU rounding-law proof.

PID9481 absent after completion; no probe process remains. Original five settings unchanged, HDR0 unchanged, GPU thermal level0/max652800000 unchanged, CPU2 cap2342400 unchanged. battery31.3C/VTS34.6C. No video/App lifecycle/system change or extra run occurred. Workspace baseline/after retain unrelated dirty state; only this evidence directory was written.

Result does not prove fused renderer shader, captured media/source frame, layout(yuv)/NV12 carrier or optical panel equivalence. Old builtin failure evidence remains separate and unchanged. See result.json, verdict.json, execution.json, remote-command.sh, exit.txt, stdout/stderr, build/source snapshots and pre/post logs.
