# PP-E1 frame-advance check

- [PASS] prehome_frames_advance present 423407948846188->423433426936074 ns (+25.5s frames / 25.5s wall), state 3->3
- during-home sf: 0 -> 0 (layer gone = 0 expected; states 2/2)
- [FAIL] postreturn_frames_advance[post_return_1->post_return_2] present 0->0 ns (+0.0s frames / 11.6s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 0->423475526326943 ns (+423475.5s frames / 13.8s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(CodecLooper)', '(MediaCodec_loop)', '(RenderThread)', '(Thread-7)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(CodecLooper)', '(DartWorker)', '(MediaCodec_loop)', '(Thread-7)', '(demux)']
## verdict: FAIL (5/6)
