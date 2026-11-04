# PP-S1 chain check
app_pid=19416
- [PASS] same_pid foreign_pids=none (makeComponentInstance runs in mediaserver=exempt)
chain window: t0=1793638684783 (surfaceDestroyed=yes) home=1793638683478 return=1793638696438
## chain
- surfaceDestroyed: 1793638684783
- mkst_shutdown exit: 1793638684856
- dart authorize begin: 1793638696554
- java authorize enter: 1793638696735
- java authorize result ok: 1793638696736
- mkst_ensure_init exit ready=1: 1793638696864
- mkst_create_decoder_window exit ok: 1793638696866
- makeComponentInstance(new): 1793638696875
- Now Executing(new): 1793638696935
- [PASS] chain_complete 
- [PASS] chain_task_order_strict task_deltas=mkst_shutdown exit:11698ms,dart authorize begin:182ms,java authorize result ok:128ms,mkst_ensure_init exit ready=1:2ms,mkst_create_decoder_window exit ok:9ms,makeComponentInstance(new):60ms
- [PASS] identity_wid_dart_java wid=2494->2494
- [PASS] identity_owner_key_native owner_key=10896403421259852160
- [PASS] surface_generation_bump sc_gen=1 -> dart gen=2 wid 1050978->2494
- [PASS] prehome_dvP84_route count=5
- [PASS] prehome_decoder_window count=1
- [PASS] prehome_codec_executing count=5
- [PASS] dataspace_applied_evidence lgPqApply/lgDataSpaceBinding/MKSURF-E1 count=8
- [PASS] zero_fatal_anr count=0
## verdict: PASS (11/11)
