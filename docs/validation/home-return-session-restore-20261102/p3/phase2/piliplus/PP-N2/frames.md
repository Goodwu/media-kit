# PP-N2 frame-advance check

- [PASS] prehome_frames_advance present 421774463165353->421806464688622 ns (+32.0s frames / 26.8s wall), state 2->3
- during-home sf: 0 -> 0 (layer gone = 0 expected; states 2/2)
- [PASS] postreturn_frames_advance[post_return_1->post_return_2] present 421821313399866->421839051500172 ns (+17.7s frames / 12.7s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 421839051500172->421853728450218 ns (+14.7s frames / 14.6s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
## verdict: PASS (6/6)
