# PP-B2 chain check
app_pid=16183
- [PASS] same_pid foreign_pids=none (makeComponentInstance runs in mediaserver=exempt)
chain window: t0=1793638165745 (surfaceDestroyed=yes) home=1793638164849 return=1793638175615
## chain
- surfaceDestroyed: 1793638165745
- mkst_shutdown exit: 1793638165801
- dart authorize begin: 1793638175574
- java authorize enter: 1793638175609
- java authorize result ok: 1793638175610
- mkst_ensure_init exit ready=1: 1793638175664
- mkst_create_decoder_window exit ok: 1793638175665
- makeComponentInstance(new): 1793638175671
- Now Executing(new): 1793638175716
- [PASS] chain_complete 
- [PASS] chain_task_order_strict task_deltas=mkst_shutdown exit:9773ms,dart authorize begin:36ms,java authorize result ok:54ms,mkst_ensure_init exit ready=1:1ms,mkst_create_decoder_window exit ok:6ms,makeComponentInstance(new):45ms
- [PASS] identity_wid_dart_java wid=2494->2494
- [PASS] identity_owner_key_native owner_key=798823943677045827
- [PASS] surface_generation_bump sc_gen=1 -> dart gen=2 wid 1050978->2494
- [PASS] prehome_dvP84_route count=4
- [PASS] prehome_decoder_window count=1
- [PASS] prehome_codec_executing count=5
- [PASS] dataspace_applied_evidence lgPqApply/lgDataSpaceBinding/MKSURF-E1 count=8
- [PASS] zero_fatal_anr count=0
## verdict: PASS (11/11)
