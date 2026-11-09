# PP-F2 chain check
app_pid=13228
- [PASS] same_pid foreign_pids=none (makeComponentInstance runs in mediaserver=exempt)
chain window: t0=1793637577811 (surfaceDestroyed=yes) home=1793637576683 return=1793637579000
## chain
- surfaceDestroyed: 1793637577811
- mkst_shutdown exit: 1793637577876
- dart authorize begin: 1793637580146
- java authorize enter: 1793637580147
- java authorize result ok: 1793637580148
- mkst_ensure_init exit ready=1: 1793637580220
- mkst_create_decoder_window exit ok: 1793637580221
- makeComponentInstance(new): 1793637580226
- Now Executing(new): 1793637580279
- [PASS] chain_complete 
- [PASS] chain_task_order_strict task_deltas=mkst_shutdown exit:2270ms,dart authorize begin:2ms,java authorize result ok:72ms,mkst_ensure_init exit ready=1:1ms,mkst_create_decoder_window exit ok:5ms,makeComponentInstance(new):53ms
- [PASS] identity_wid_dart_java wid=1051070->1051070
- [PASS] identity_owner_key_native owner_key=14601477037215364979
- [PASS] surface_generation_bump sc_gen=1 -> dart gen=2 wid 2099554->1051070
- [PASS] prehome_dvP84_route count=4
- [PASS] prehome_decoder_window count=1
- [PASS] prehome_codec_executing count=5
- [PASS] dataspace_applied_evidence lgPqApply/lgDataSpaceBinding/MKSURF-E1 count=8
- [PASS] zero_fatal_anr count=0
## verdict: PASS (11/11)
