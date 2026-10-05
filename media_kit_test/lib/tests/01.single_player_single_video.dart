import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
  late final Player player = Player();
  late final VideoController controller = VideoController(
    player,
    configuration: configuration.value,
  );
  LocalPlaybackObserver? _localObserver;

  @override
  void initState() {
    super.initState();
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
