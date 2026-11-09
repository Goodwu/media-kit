# O1 return-time chain (anchors after return_send_begin 22:58:32.610)

| anchor | line | device time | Δprev (ms) | identity |
|---|---|---|---|---|
| vo_null_property_complete(last before sc) | L1512 | 22:58:33.297 | — |  |
| java_surfaceCreated_enter | L1476 | 22:58:33.258 | -39 |  |
| dart_authorize_begin | L1513 | 22:58:33.297 | 39 | wid=2099314 generation=2 surfaceGeneration=2 |
| java_authorize_enter | L1528 | 22:58:33.360 | 63 | wid=2099314 generation=2 surfaceGeneration=2 |
| java_authorize_result | L1535 | 22:58:33.360 | 0 | wid=2099314 surfaceGeneration=2 code=ok |
| dart_authorize_result | L1540 | 22:58:33.370 | 10 | wid=2099314 surfaceGeneration=2 code=ok |
| native_ensure_init_exit | L1598 | 22:58:33.463 | 93 | generation=2 ready=1 owner_key=7113845237141439577 |
| native_create_decoder_window_exit | L1602 | 22:58:33.464 | 1 | generation=2 owner_key=7113845237141439577 result=ok |
| MediaCodec_create | L1603 | 22:58:33.466 | 2 |  |
| OMX_hevc_Now_Loaded | L1618 | 22:58:33.487 | 21 |  |

- ordered: False; wid=2099314; pre-HOME owner_key (from open, L953)=7113845237141439577; return ensure_init owner_key=7113845237141439577

Note: the `vo_null_property_complete(last before sc)` row (L1512, 22:58:33.297) is the bind-time stale-output detach that is issued in the same millisecond as `authorize begin`, not the HOME teardown ack. The HOME teardown chain for O1 is: `mkst_shutdown exit` L1218 22:58:22.434 -> `property complete vo=null` L1289 22:58:22.895 / L1317 22:58:23.214 (final). 23.214 < authorize begin 33.297, so the C1 ordering (teardown vo=null ack < authorize begin < java enter < java result ok < dart result ok < ensure_init ready=1 < create_decoder_window ok < MediaCodec create < OMX) holds for the return cycle; the "ordered: False" above is an artifact of the row-selection, not of the device sequence.
