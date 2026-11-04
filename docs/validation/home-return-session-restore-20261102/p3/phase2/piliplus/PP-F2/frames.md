# PP-F2 frame-advance check

- [PASS] prehome_frames_advance present 421967934249550->421995130772144 ns (+27.2s frames / 27.3s wall), state 3->3
- [PASS] postreturn_frames_advance[post_return_1->post_return_2] present 422000597575058->422017214146250 ns (+16.6s frames / 12.6s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 422017214146250->422031793701869 ns (+14.6s frames / 14.6s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
## verdict: PASS (6/6)
