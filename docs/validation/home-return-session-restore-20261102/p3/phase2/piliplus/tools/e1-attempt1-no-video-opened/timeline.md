# PP-E1 timeline

app_pid=20601 launch=00:59:46.302 home=01:00:39.113 return=01:00:50.177

## anchor events (chronologic)

## frame-advance samples
- play_start: state=0 pos=0 sf_last_present=423208919695847 sf_frames=54
- pre_home_1: state=0 pos=0 sf_last_present=423208919695847 sf_frames=54
- during_home_1: state=0 pos=0 sf_last_present=0 sf_frames=0
- during_home_2: state=0 pos=0 sf_last_present=0 sf_frames=0
- post_return_1: state=0 pos=0 sf_last_present=423270513328272 sf_frames=2
- post_return_2: state=0 pos=0 sf_last_present=423270513328272 sf_frames=2
- post_return_3: state=0 pos=0 sf_last_present=423270513328272 sf_frames=2

## thread cpu deltas (ticks, 10ms)
- play_start -> pre_home_1 (+26741ms): 
- pre_home_1 -> during_home_1 (+6660ms): (1.raster)(20620)+3, (le.piliplus.dev)(20601)+2, (Profile(20615)+1, (RenderThread)(20631)+1
- during_home_1 -> during_home_2 (+4100ms): (HeapTaskDaemon)(20611)+4
- during_home_2 -> post_return_1 (+7021ms): (1.raster)(20620)+3, (le.piliplus.dev)(20601)+1, (Binder:20601_2)(20613)+1, (RenderThread)(20631)+1
- post_return_1 -> post_return_2 (+12337ms): 
- post_return_2 -> post_return_3 (+13941ms): 
