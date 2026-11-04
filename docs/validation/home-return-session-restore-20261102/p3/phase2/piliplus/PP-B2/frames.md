# PP-B2 frame-advance check

- [PASS] prehome_frames_advance present 422552850398129->422584043162856 ns (+31.2s frames / 25.7s wall), state 2->3
- during-home sf: 0 -> 0 (layer gone = 0 expected; states 3/3)
- [PASS] postreturn_frames_advance[post_return_1->post_return_2] present 422596037861862->422612839945554 ns (+16.8s frames / 11.7s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 422612839945554->422626791046069 ns (+14.0s frames / 13.9s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
## verdict: PASS (6/6)
