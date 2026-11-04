# PP-F1 chain check
app_pid=12419
- [PASS] same_pid foreign_pids=none (makeComponentInstance runs in mediaserver=exempt)
chain window: t0=1793637485839 (surfaceDestroyed=yes) home=1793637484746 return=1793637487242
## chain
- surfaceDestroyed: 1793637485839
- mkst_shutdown exit: 1793637485893
- dart authorize begin: 1793637487789
- java authorize enter: 1793637487790
- java authorize result ok: 1793637487791
- mkst_ensure_init exit ready=1: 1793637487863
- mkst_create_decoder_window exit ok: 1793637487865
- makeComponentInstance(new): 1793637487873
- Now Executing(new): 1793637487952
- [PASS] chain_complete 
- [PASS] chain_task_order_strict task_deltas=mkst_shutdown exit:1896ms,dart authorize begin:2ms,java authorize result ok:72ms,mkst_ensure_init exit ready=1:2ms,mkst_create_decoder_window exit ok:8ms,makeComponentInstance(new):79ms
- [PASS] identity_wid_dart_java wid=1051070->1051070
- [PASS] identity_owner_key_native owner_key=15162735945616733173
- [PASS] surface_generation_bump sc_gen=1 -> dart gen=2 wid 1050978->1051070
- [PASS] prehome_dvP84_route count=4
- [PASS] prehome_decoder_window count=1
- [PASS] prehome_codec_executing count=5
- [PASS] dataspace_applied_evidence lgPqApply/lgDataSpaceBinding/MKSURF-E1 count=8
- [PASS] zero_fatal_anr count=0
## verdict: PASS (11/11)
