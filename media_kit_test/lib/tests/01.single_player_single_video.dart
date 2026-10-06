import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video_controller/ohos_video_controller/sw_render.dart';

import '../common/globals.dart';
import '../common/local_playback_observer.dart';
import '../common/sources/sources.dart';
import '../common/widgets.dart';

class SinglePlayerSingleVideoScreen extends StatefulWidget {
  const SinglePlayerSingleVideoScreen({super.key});

  @override
  State<SinglePlayerSingleVideoScreen> createState() =>
      _SinglePlayerSingleVideoScreenState();
}

class _SinglePlayerSingleVideoScreenState
    extends State<SinglePlayerSingleVideoScreen> {
  late final Player player = Player(
    // TEMPORARY emulator probe: verbose mpv logs for the black-frame chain.
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.debug),
  );
  late final VideoController controller = VideoController(
    player,
    configuration: configuration.value,
  );
  LocalPlaybackObserver? _localObserver;

  // TEMPORARY emulator diagnostics: poll the software render bridge frame
  // counter so bridge liveness is observable from hilog.
  Timer? _swFramesPoll;

  @override
  void initState() {
    super.initState();
    final opening = player.open(Media(sources[0]));
    player.stream.error.listen((error) => debugPrint(error));
    // TEMPORARY: vo/vd/cplayer logs for the emulator black-frame chain.
    player.stream.log.listen((log) {
      if (log.prefix == 'vo' ||
          log.prefix == 'vo/libmpv' ||
          log.prefix == 'vd' ||
          (log.prefix == 'cplayer' && log.level != 'debug') ||
          log.level == 'error') {
        debugPrint('MPV[${log.prefix}] ${log.level}: ${log.text}');
      }
    });
    _swFramesPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final frames = SwRender.frames();
      if (frames > 0) {
        debugPrint('SwRender frames=$frames '
            'submitted=${SwRender.submitted()} '
            'pixelSum=${SwRender.pixelSum()}');
      }
      // TEMPORARY: native bridge logs reach Dart only through the FFI ring
      // buffer (hilog drops LOG_APP here; the file mirror failed silently).
      final logs = SwRender.takeLogs();
      for (final line in logs.split('\n')) {
        if (line.trim().isNotEmpty) debugPrint('SwNative: $line');
      }
      final platform = player.platform;
      if (platform != null) {
        try {
          final vo = await (platform as dynamic).getProperty('vo');
          final vf = await (platform as dynamic)
              .getProperty('video-format');
          final idle = await (platform as dynamic)
              .getProperty('idle-active');
          final w = player.state.width;
          debugPrint('SwRender mpv vo=$vo video-format=$vf '
              'idle=$idle width=$w');
        } catch (_) {}
      }
    });
    if (LocalPlaybackObserver.enabled) {
      _localObserver = LocalPlaybackObserver(player)
        ..observeOpen(opening, sources[0]);
    }
  }

  @override
  void dispose() {
    _swFramesPoll?.cancel();
    _localObserver?.stop();
    player.dispose();
    super.dispose();
  }

  List<Widget> get items => [
        for (int i = 0; i < sources.length; i++)
          ListTile(
            title: Text(
              'Video $i',
              style: const TextStyle(
                fontSize: 14.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              final opening = player.open(Media(sources[i]));
              _localObserver?.observeOpen(opening, sources[i]);
            },
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final horizontal =
        MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    return Scaffold(
      appBar: AppBar(
        title: const Text('package:media_kit'),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FloatingActionButton(
            heroTag: 'file',
            tooltip: 'Open [File]',
            onPressed: () => showFilePicker(context, player),
            child: const Icon(Icons.file_open),
          ),
          const SizedBox(width: 16.0),
          FloatingActionButton(
            heroTag: 'uri',
            tooltip: 'Open [Uri]',
            onPressed: () => showURIPicker(context, player),
            child: const Icon(Icons.link),
          ),
        ],
      ),
      body: SizedBox.expand(
        child: horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              margin: const EdgeInsets.all(32.0),
                              child: Video(
                                controller:
                                    _localObserver?.observe(controller) ?? controller,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32.0),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1.0, thickness: 1.0),
                  Expanded(
                    flex: 1,
                    child: ListView(
                      children: items,
                    ),
                  ),
                ],
              )
            : ListView(
                children: [
                  Video(
                    controller: _localObserver?.observe(controller) ?? controller,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width * 9.0 / 16.0,
                  ),
                  ...items,
                ],
              ),
      ),
    );
  }
}
