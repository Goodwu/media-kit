import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../common/globals.dart';
import '../common/sources/sources.dart';
import '../common/widgets.dart';

class SinglePlayerSingleVideoScreen extends StatefulWidget {
  const SinglePlayerSingleVideoScreen({Key? key}) : super(key: key);

  @override
  State<SinglePlayerSingleVideoScreen> createState() =>
      _SinglePlayerSingleVideoScreenState();
}

class _SinglePlayerSingleVideoScreenState
    extends State<SinglePlayerSingleVideoScreen> {
  static const _windowChannel = MethodChannel('media_kit_test/window');
  static const _autoOpticalOutputScaleText = String.fromEnvironment(
    'MEDIA_KIT_AUTO_OPTICAL_OUTPUT_SCALE',
    defaultValue: '100',
  );
  static const _autoToneMapping = String.fromEnvironment(
    'MEDIA_KIT_AUTO_TONE_MAPPING',
  );
  static const _autoTexture = bool.fromEnvironment('MEDIA_KIT_AUTO_TEXTURE');
  static const _autoSdr = bool.fromEnvironment('MEDIA_KIT_AUTO_SDR');
  static const _autoStartSeconds = String.fromEnvironment(
    'MEDIA_KIT_AUTO_START_SECONDS',
  );
  bool _compactWindow = false;
  bool _autoPlayerDisposed = false;

  late final Player player = Player();
  late final VideoController controller = VideoController(
    player,
    configuration: configuration.value,
  );

  @override
  void initState() {
    super.initState();
    _openInitialSource();
    if (const bool.fromEnvironment('MEDIA_KIT_AUTO_RESIZE')) {
      Future<void>.delayed(const Duration(seconds: 6), () {
        _resizeTestWindow(width: 640.0, height: 520.0);
      });
      Future<void>.delayed(const Duration(seconds: 10), () {
        _disposeTestPlayer();
      });
    }
    player.stream.error.listen((error) => debugPrint(error));
    player.stream.log.listen(
      (log) => debugPrint(
        'MPVLOG [${log.prefix}] ${log.level}: ${log.text}',
      ),
    );
    player.stream.videoParams.listen(
      (params) => debugPrint('VIDEOPARAMS $params'),
    );
    Future<void>.delayed(const Duration(seconds: 4), () async {
      for (final property in [
        'vo',
        'hwdec-current',
        'path',
        'video-format',
        'video-params',
        // Keep the output contract in the same stock-libmpv session as the
        // NativeSurface/Metal samples. These are diagnostic readbacks only;
        // do not infer visible HDR from any one property.
        'target-prim',
        'target-trc',
        'target-peak',
        'sig-peak',
        'tone-mapping',
      ]) {
        try {
          final value = await player.getProperty(
            property,
            waitForInitialization: false,
          );
          debugPrint('MPVPROP $property=$value');
        } catch (error) {
          debugPrint('MPVPROP $property ERROR=$error');
        }
      }
    });
  }

  Map<String, Object> _autoNativeHdrConfiguration() {
    final opticalOutputScale =
        double.tryParse(_autoOpticalOutputScaleText) ?? 100.0;
    final configuration = <String, Object>{
      'transfer': 'pq',
      'masteringMetadata': <String, Object>{
        'minLuminance': 0.005,
        'maxLuminance': 1000.0,
      },
    };
    if (opticalOutputScale != 100.0) {
      configuration['opticalOutputScale'] = opticalOutputScale;
    }
    return configuration;
  }

  Future<void> _openInitialSource() async {
    debugPrint('AUTO_SOURCE path=${sources[0]}');
    if (_autoTexture) {
      // Isolated same-source SDR control: keep the normal Texture output and
      // make the target conversion explicit. This is diagnostic only and is
      // never part of PiliPlusX production configuration.
      for (final entry in const <String, String>{
        'target-prim': 'bt.709',
        'target-trc': 'bt.1886',
        'target-colorspace-hint': 'auto',
        'tone-mapping': 'bt.2390',
      }.entries) {
        try {
          await player.setProperty(entry.key, entry.value);
          debugPrint('AUTO_TEXTURE_SDR ${entry.key}=${entry.value}');
        } catch (error) {
          debugPrint('AUTO_TEXTURE_SDR ${entry.key} ERROR=$error');
        }
      }
    } else if (!const bool.fromEnvironment('MEDIA_KIT_AUTO_NATIVE_WINDOW',
        defaultValue: true)) {
      try {
        if (_autoSdr) {
          // Pure SDR control: do not configure NativeSurface/EDR or touch
          // tone-mapping. Keep mpv's normal BT.709 SDR target explicit.
          await player.setProperty('target-prim', 'bt.709');
          await player.setProperty('target-trc', 'bt.1886');
          debugPrint('AUTO_SDR_TARGET target-prim=bt.709 target-trc=bt.1886');
        } else {
          final output = await controller.platform.future;
          const targetPeak =
              String.fromEnvironment('MEDIA_KIT_AUTO_TARGET_PEAK');
          if (targetPeak.isNotEmpty) {
            await player.setProperty('target-peak', targetPeak);
            debugPrint('AUTO_NATIVE_TARGET_PEAK set=$targetPeak');
          }
          if (_autoToneMapping.isNotEmpty) {
            await player.setProperty('tone-mapping', _autoToneMapping);
            debugPrint('AUTO_NATIVE_TONE_MAPPING set=$_autoToneMapping');
          }
          final result = await output.configureHdrOutput(
            _autoNativeHdrConfiguration(),
          );
          debugPrint('AUTO_NATIVE_HDR_CONFIG result=$result');
        }
      } catch (error) {
        debugPrint('AUTO_NATIVE_HDR_CONFIG ERROR=$error');
      }
    }
    final autoStartSeconds = double.tryParse(_autoStartSeconds);
    final firstVideoParams = autoStartSeconds != null && autoStartSeconds >= 0.0
        ? player.stream.videoParams.firstWhere((params) => params.w != null)
        : null;
    await player.open(Media(
      sources[0],
      start: autoStartSeconds != null && autoStartSeconds >= 0.0
          ? Duration(
              microseconds:
                  (autoStartSeconds * Duration.microsecondsPerSecond).round(),
            )
          : null,
    ));
    if (autoStartSeconds != null && autoStartSeconds >= 0.0) {
      await firstVideoParams;
      await player.pause();
      debugPrint('AUTO_FIXED_START seconds=$autoStartSeconds');
      debugPrint('AUTO_FIXED_START paused position=${player.state.position}');
    }
    if (const bool.fromEnvironment('MEDIA_KIT_AUTO_NATIVE_EDGE')) {
      Future<void>.delayed(const Duration(milliseconds: 350), () async {
        try {
          final output = await controller.platform.future;
          final reset = await output.resetHdrOutput();
          debugPrint('AUTO_NATIVE_EDGE reset=$reset');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          final configure = await output.configureHdrOutput(
            _autoNativeHdrConfiguration(),
          );
          debugPrint('AUTO_NATIVE_EDGE configure=$configure');
        } catch (error) {
          debugPrint('AUTO_NATIVE_EDGE ERROR=$error');
        }
      });
    }
  }

  Future<void> _resizeTestWindow(
      {required double width, required double height}) async {
    try {
      final result = await _windowChannel.invokeMethod<Map<Object?, Object?>>(
        'setFrame',
        {'width': width, 'height': height},
      );
      debugPrint(
          'AUTO_WINDOW_RESIZE requested=${width}x$height result=$result');
    } catch (error) {
      debugPrint('AUTO_WINDOW_RESIZE ERROR=$error');
    }
  }

  Future<void> _disposeTestPlayer() async {
    if (_autoPlayerDisposed) return;
    _autoPlayerDisposed = true;
    await player.dispose();
    debugPrint('AUTO_PLAYER_DISPOSE completed');
  }

  @override
  void dispose() {
    if (!_autoPlayerDisposed) {
      player.dispose();
    }
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
              player.open(Media(sources[i]));
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
        actions: [
          IconButton(
            tooltip: 'Resize test window',
            icon: const Icon(Icons.open_in_full),
            onPressed: () async {
              final compact = !_compactWindow;
              await _windowChannel.invokeMethod('setFrame', {
                'width': compact ? 640.0 : 800.0,
                'height': compact ? 520.0 : 632.0,
              });
              if (mounted) {
                setState(() => _compactWindow = compact);
              }
            },
          ),
        ],
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
                                controller: controller,
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
                    controller: controller,
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
