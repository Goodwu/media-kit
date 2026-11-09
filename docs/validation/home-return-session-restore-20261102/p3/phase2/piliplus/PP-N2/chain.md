# PP-N2 chain check
app_pid=11357
- [PASS] same_pid foreign_pids=none (makeComponentInstance runs in mediaserver=exempt)
chain window: t0=1793637389255 (surfaceDestroyed=yes) home=1793637388152 return=1793637400691
## chain
- surfaceDestroyed: 1793637389255
- mkst_shutdown exit: 1793637389323
- dart authorize begin: 1793637400689
- java authorize enter: 1793637400847
- java authorize result ok: 1793637400848
- mkst_ensure_init exit ready=1: 1793637400930
- mkst_create_decoder_window exit ok: 1793637400932
- makeComponentInstance(new): 1793637400940
- Now Executing(new): 1793637400996
- [PASS] chain_complete 
- [PASS] chain_task_order_strict task_deltas=mkst_shutdown exit:11366ms,dart authorize begin:159ms,java authorize result ok:82ms,mkst_ensure_init exit ready=1:2ms,mkst_create_decoder_window exit ok:8ms,makeComponentInstance(new):56ms
- [PASS] identity_wid_dart_java wid=2099650->2099650
- [PASS] identity_owner_key_native owner_key=13333629899867554184
- [PASS] surface_generation_bump sc_gen=1 -> dart gen=2 wid 1050978->2099650
- [PASS] prehome_dvP84_route count=4
- [PASS] prehome_decoder_window count=1
- [PASS] prehome_codec_executing count=5
- [PASS] dataspace_applied_evidence lgPqApply/lgDataSpaceBinding/MKSURF-E1 count=8
- [PASS] zero_fatal_anr count=0
## verdict: PASS (11/11)
