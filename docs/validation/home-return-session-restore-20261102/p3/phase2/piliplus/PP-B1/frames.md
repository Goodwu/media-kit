# PP-B1 frame-advance check

- [PASS] prehome_frames_advance present 422064733359669->422091352668774 ns (+26.6s frames / 26.6s wall), state 3->3
- during-home sf: 0 -> 0 (layer gone = 0 expected; states 2/2)
- [PASS] postreturn_frames_advance[post_return_1->post_return_2] present 422105719097935->422123531698084 ns (+17.8s frames / 12.7s wall), state 3
- [PASS] postreturn_frames_advance[post_return_2->post_return_3] present 422123531698084->422137975599485 ns (+14.4s frames / 14.5s wall), state 3
- [PASS] playback_resumed final state=3 (3=playing)
- [PASS] threads_active[post_return_1->post_return_2] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
- [PASS] threads_active[post_return_2->post_return_3] top=['(JNISurfaceTextu)', '(MediaCodec_loop)', '(Thread-8)', '(Thread-9)', '(demux)']
## verdict: PASS (6/6)
