# PP-F1 frame-advance check

- [PASS] prehome_frames_advance present 421876730555157->421903321965564 ns (+26.6s frames / 26.6s wall), state 3->3
- [PASS] postreturn_frames_advance[post_return_1->post_return_2] present 421912667816863->421925399252535 ns (+12.7s frames / 12.6s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 421925399252535->421939943036279 ns (+14.5s frames / 14.5s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
## verdict: PASS (6/6)
