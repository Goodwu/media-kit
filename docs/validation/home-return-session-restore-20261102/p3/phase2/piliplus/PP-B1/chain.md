# PP-B1 chain check
app_pid=14050
- [PASS] same_pid foreign_pids=none (makeComponentInstance runs in mediaserver=exempt)
chain window: t0=1793637673861 (surfaceDestroyed=yes) home=1793637672757 return=1793637685234
## chain
- surfaceDestroyed: 1793637673861
- mkst_shutdown exit: 1793637673916
- dart authorize begin: 1793637685221
- java authorize enter: 1793637685273
- java authorize result ok: 1793637685275
- mkst_ensure_init exit ready=1: 1793637685334
- mkst_create_decoder_window exit ok: 1793637685335
- makeComponentInstance(new): 1793637685340
- Now Executing(new): 1793637685386
- [PASS] chain_complete 
- [PASS] chain_task_order_strict task_deltas=mkst_shutdown exit:11305ms,dart authorize begin:54ms,java authorize result ok:59ms,mkst_ensure_init exit ready=1:1ms,mkst_create_decoder_window exit ok:5ms,makeComponentInstance(new):46ms
- [PASS] identity_wid_dart_java wid=2099650->2099650
- [PASS] identity_owner_key_native owner_key=8290910650321503536
- [PASS] surface_generation_bump sc_gen=1 -> dart gen=2 wid 1050978->2099650
- [PASS] prehome_dvP84_route count=4
- [PASS] prehome_decoder_window count=1
- [PASS] prehome_codec_executing count=5
- [PASS] dataspace_applied_evidence lgPqApply/lgDataSpaceBinding/MKSURF-E1 count=8
- [PASS] zero_fatal_anr count=0
## verdict: PASS (11/11)
