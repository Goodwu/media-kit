# PP-S1 frame-advance check

- [PASS] prehome_frames_advance present 423069306571265->423102121322346 ns (+32.8s frames / 27.6s wall), state 6->3
- during-home sf: 0 -> 0 (layer gone = 0 expected; states 2/2)
- [PASS] postreturn_frames_advance[post_return_1->post_return_2] present 423118218075257->423134109566970 ns (+15.9s frames / 12.2s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 423134109566970->423148646307224 ns (+14.5s frames / 14.4s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
## verdict: PASS (6/6)
