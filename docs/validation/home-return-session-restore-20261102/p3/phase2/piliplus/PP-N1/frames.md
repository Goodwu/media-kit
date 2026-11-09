# PP-N1 frame-advance check

- [PASS] prehome_frames_advance present 421475206818123->421506915373788 ns (+31.7s frames / 25.7s wall), state 2->3
- during-home sf: 0 -> 0 (layer gone = 0 expected; states 2/2)
- [PASS] postreturn_frames_advance[post_return_1->post_return_2] present 421520316840033->421537723352110 ns (+17.4s frames / 12.2s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 421537723352110->421551677920854 ns (+14.0s frames / 14.0s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
## verdict: PASS (6/6)
