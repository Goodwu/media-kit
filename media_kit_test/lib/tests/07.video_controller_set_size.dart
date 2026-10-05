import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../common/globals.dart';
import '../common/local_playback_observer.dart';
import '../common/sources/sources.dart';

class VideoControllerSetSizeScreen extends StatefulWidget {
  const VideoControllerSetSizeScreen({super.key});

  @override
  State<VideoControllerSetSizeScreen> createState() =>
      _VideoControllerSetSizeScreenState();
}

class _VideoControllerSetSizeScreenState
    extends State<VideoControllerSetSizeScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(
    player,
    configuration: configuration.value,
  );
  LocalPlaybackObserver? _localObserver;

  @override
  void initState() {
    super.initState();
    player.setAudioTrack(AudioTrack.no());
    player.setPlaylistMode(PlaylistMode.loop);
    final opening = player.open(Media(sources[0]));
    player.stream.error.listen((error) => debugPrint(error));
    if (LocalPlaybackObserver.enabled) {
      _localObserver = LocalPlaybackObserver(player)
        ..observeOpen(opening, sources[0]);
    }
  }

  @override
  void dispose() {
    _localObserver?.stop();
    player.dispose();
    super.dispose();
  }

  Future<void> _setSize(int height) async {
    final width = 16 / 9 * height ~/ 1;
    final resizing = controller.setSize(width: width, height: height);
    _localObserver?.observeOperation(resizing, 'resize', {
      'requestedWidth': width, 'requestedHeight': height,
    });
    await resizing;
    // Local opt-in experiment: replay the same PTS after each size request.
    // Normal demo behavior remains the original size change.
    if (!mounted || _localObserver == null) return;
    final seeking = player.seek(const Duration(seconds: 10));
    _localObserver?.observeOperation(seeking, 'seek', {'targetMs': 10000});
    await seeking;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('package:media_kit'),
      ),
      body: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Video(
            controller: _localObserver?.observe(controller) ?? controller,
            controls: NoVideoControls,
          ),
          Card(
            margin: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: 120.0,
              height: 64.0 * 6,
              child: ListView(
                children: [
                  ListTile(
                    onTap: () => _setSize(2160),
                    title: const Text(
                      '2160p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () => controller.setSize(
                      width: 16 / 9 * 1440 ~/ 1,
                      height: 1440,
                    ),
                    title: const Text(
                      '1440p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () => _setSize(1080),
                    title: const Text(
                      '1080p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () => controller.setSize(
                      width: 16 / 9 * 720 ~/ 1,
                      height: 720,
                    ),
                    title: const Text(
                      '720p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () => controller.setSize(
                      width: 16 / 9 * 480 ~/ 1,
                      height: 480,
                    ),
                    title: const Text(
                      '480p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () => controller.setSize(
                      width: 16 / 9 * 360 ~/ 1,
                      height: 360,
                    ),
                    title: const Text(
                      '360p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () => controller.setSize(
                      width: 16 / 9 * 240 ~/ 1,
                      height: 240,
                    ),
                    title: const Text(
                      '240p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () => controller.setSize(
                      width: 16 / 9 * 144 ~/ 1,
                      height: 144,
                    ),
                    title: const Text(
                      '144p',
                      style: TextStyle(
                        fontSize: 14.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
