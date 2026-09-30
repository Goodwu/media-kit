import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:universal_platform/universal_platform.dart';

import 'common/globals.dart';
import 'common/sources/sources.dart';
import 'tests/01.single_player_single_video.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const diagnostics = bool.fromEnvironment(
    'MEDIA_KIT_DIAGNOSTICS',
    defaultValue: true,
  );
  if (!diagnostics) {
    // L0 disables Dart/Flutter debugPrint generation before any test screen or
    // package callback is created. It does not change playback configuration.
    debugPrint = (String? _, {int? wrapWidth}) {};
  }
  MediaKit.ensureInitialized();
  if (UniversalPlatform.isAndroid) {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (error) {
      debugPrint('ANDROID_FILE_PICKER_CACHE_CLEANUP error=$error');
    }
  }
  const preopenFullscreen = bool.fromEnvironment(
    'MEDIA_KIT_ANDROID_PREOPEN_FULLSCREEN',
  );
  await SystemChrome.setPreferredOrientations(
    preopenFullscreen && UniversalPlatform.isAndroid
        ? const [DeviceOrientation.landscapeLeft]
        : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );
  if (preopenFullscreen && UniversalPlatform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await const MethodChannel('media_kit_hdr_lab/flutter_surface_probe')
        .invokeMethod<void>('SetShortEdges');
  }
  runApp(const MyApp(DownloadingScreen()));
  await prepareSources();
  runApp(
    MyApp(
      const bool.fromEnvironment('MEDIA_KIT_AUTO_SINGLE_PLAYER')
          ? const SinglePlayerSingleVideoScreen()
          : (const bool.fromEnvironment('MEDIA_KIT_AUTO_LIFECYCLE') ||
                  const bool.fromEnvironment('MEDIA_KIT_AUTO_RESIZE'))
              ? const AutoLifecycleScreen()
              : const PrimaryScreen(),
    ),
  );
}

class AutoLifecycleScreen extends StatefulWidget {
  const AutoLifecycleScreen({super.key});

  @override
  State<AutoLifecycleScreen> createState() => _AutoLifecycleScreenState();
}

class _AutoLifecycleScreenState extends State<AutoLifecycleScreen> {
  int generation = 1;
  bool _removed = false;
  Player? _logRebinder;
  StreamSubscription? _logRebinderSubscription;

  Future<void> _rebindFfmpegLog() async {
    if (!mounted || _logRebinder != null) return;
    final rebinder = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.v),
    );
    _logRebinder = rebinder;
    _logRebinderSubscription = rebinder.stream.log.listen(
      (log) => debugPrint('AUTO_LIFECYCLE_REBIND_LOG '
          '[${log.prefix}] ${log.level}: ${log.text}'),
    );
    try {
      final handle = await rebinder.handle;
      debugPrint('AUTO_LIFECYCLE_REBIND_READY handle=$handle');
    } catch (error) {
      debugPrint('AUTO_LIFECYCLE_REBIND_ERROR $error');
    }
  }

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 14), () {
      if (!mounted || _removed) return;
      setState(() => generation++);
      debugPrint('AUTO_LIFECYCLE_RECREATE generation=$generation');
      if (const bool.fromEnvironment('MEDIA_KIT_AUTO_LIFECYCLE_LOG_REBIND')) {
        Future<void>.delayed(
          const Duration(seconds: 9),
          _rebindFfmpegLog,
        );
      }
    });
    const terminateSeconds = int.fromEnvironment(
      'MEDIA_KIT_AUTO_LIFECYCLE_REMOVE_SECONDS',
      defaultValue: -1,
    );
    if (terminateSeconds >= 0) {
      Future<void>.delayed(Duration(seconds: terminateSeconds), () {
        if (!mounted || _removed) return;
        setState(() => _removed = true);
        debugPrint('AUTO_LIFECYCLE_REMOVE');
      });
    }
  }

  @override
  void dispose() {
    final subscription = _logRebinderSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    final rebinder = _logRebinder;
    if (rebinder != null) unawaited(rebinder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _removed
        ? const SizedBox.shrink()
        : SinglePlayerSingleVideoScreen(key: ValueKey(generation));
  }
}

class MyApp extends StatelessWidget {
  final Widget child;
  const MyApp(this.child, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.windows: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.android: OpenUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      home: child,
    );
  }
}

class PrimaryScreen extends StatelessWidget {
  const PrimaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('package:media_kit'),
        actions: [
          ValueListenableBuilder<VideoControllerConfiguration>(
            valueListenable: configuration,
            builder: (context, value, _) => TextButton(
              onPressed: () {
                configuration.value = value.copyWith(
                  enableHardwareAcceleration: !value.enableHardwareAcceleration,
                );
              },
              child: Text(value.enableHardwareAcceleration ? 'H/W' : 'S/W'),
            ),
          ),
          if (UniversalPlatform.isAndroid)
            ValueListenableBuilder<VideoControllerConfiguration>(
              valueListenable: configuration,
              builder: (context, value, _) => TextButton(
                onPressed: () {
                  configuration.value = value.copyWith(
                    android: value.android.copyWith(
                      usePlatformView: !value.android.usePlatformView,
                    ),
                  );
                },
                child: Text(value.android.usePlatformView
                    ? 'PlatformView'
                    : 'TextureView'),
              ),
            ),
          const SizedBox(width: 16.0),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text(
              'single_player_single_video.dart',
              style: TextStyle(fontSize: 14.0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SinglePlayerSingleVideoScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class DownloadingScreen extends StatelessWidget {
  const DownloadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('package:media_kit'),
      ),
      body: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: progress,
          child: const CircularProgressIndicator(),
          builder: (context, progress, child) => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              child!,
              const SizedBox(height: 16.0),
              Text(
                progress,
                style: const TextStyle(fontSize: 14.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
