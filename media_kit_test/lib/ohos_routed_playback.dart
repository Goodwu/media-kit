import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// SDK exercise application, not PiliPlus and not an HDR certification screen.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: OhosRoutedPlaybackScreen()));
}

class OhosRoutedPlaybackScreen extends StatefulWidget {
  const OhosRoutedPlaybackScreen({super.key});
  @override
  State<OhosRoutedPlaybackScreen> createState() => _PlaybackState();
}

class _PlaybackState extends State<OhosRoutedPlaybackScreen> {
  final _uri = TextEditingController();
  RoutedVideoPlayback? _playback;
  StreamSubscription<Object>? _errors;
  String _status = 'Initializing SDK output';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    Player? player;
    RoutedVideoPlayback? playback;
    try {
      player = await Player.create();
      playback = await RoutedVideoPlayback.create(player);
      if (!mounted) {
        await playback.dispose();
        return;
      }
      _errors = playback.errors.listen(_error);
      setState(() {
        _playback = playback;
        _status = 'Output initialized. Enter a media URI to exercise playback.';
      });
    } catch (error) {
      if (playback != null) {
        try { await playback.dispose(); } catch (cleanup) { _error(cleanup); }
      } else if (player != null) {
        try { await player.dispose(); } catch (cleanup) { _error(cleanup); }
      }
      _error(error);
    }
  }

  void _error(Object error) {
    if (mounted) setState(() => _status = 'Error: $error');
  }

  Future<void> _run(Future<void> Function(RoutedVideoPlayback) action) async {
    final playback = _playback;
    if (playback == null) return;
    try { await action(playback); } catch (error) { _error(error); }
  }

  @override
  void dispose() {
    _uri.dispose();
    unawaited(_errors?.cancel());
    final playback = _playback;
    if (playback != null) {
      unawaited(playback.dispose().catchError((Object error) {
        debugPrint('OHOS SDK exercise disposal failed: $error');
      }));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = _playback;
    return Scaffold(
      appBar: AppBar(title: const Text('OHOS direction B — SDK exercise')),
      body: SafeArea(child: Column(children: [
        Expanded(child: playback == null
            ? const Center(child: CircularProgressIndicator())
            : Center(child: FittedBox(fit: BoxFit.contain, child: RoutedSimpleVideo(playback: playback)))),
        Padding(padding: const EdgeInsets.all(8), child: Text(_status)),
        const Text('Native output exercise; no HDR display verification claim.'),
        Padding(padding: const EdgeInsets.all(8), child: TextField(
          controller: _uri, decoration: const InputDecoration(labelText: 'Media URI'),
        )),
        Wrap(children: [
          TextButton(onPressed: playback == null ? null : () => _run((p) async {
            final uri = _uri.text.trim();
            if (uri.isEmpty) throw ArgumentError('Media URI is empty');
            await p.open(Media(uri), play: false);
            if (mounted) setState(() => _status = 'Opened paused; press Play.');
          }), child: const Text('Open paused')),
          TextButton(onPressed: () => _run((p) => p.play()), child: const Text('Play')),
          TextButton(onPressed: () => _run((p) => p.pause()), child: const Text('Pause')),
          TextButton(onPressed: () => _run((p) => p.seek(Duration.zero)), child: const Text('Restart')),
        ]),
      ])),
    );
  }
}
