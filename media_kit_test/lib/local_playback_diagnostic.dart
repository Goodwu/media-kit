import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'common/sources/sources.dart';
import 'main.dart' show MyApp, PrimaryScreen;

// Local-file entry point for the existing demo. Playback/UI use the original
// demo screens and default controller configuration; no network preparation.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initializeDarwinMpvOwnerBroker();
  const localSources = [
    '/Users/wuweiwei1/Library/Containers/com.example.mediaKitTest/Data/Documents/local-playback/media-kit-local-4k60.mp4',
    '/Users/wuweiwei1/Library/Containers/com.example.mediaKitTest/Data/Documents/local-playback/media-kit-local-sdr-control.mp4',
  ];
  for (final source in localSources) {
    if (!await File(source).exists()) {
      throw StateError('Local playback input missing: $source');
    }
  }
  sources.addAll(localSources);
  runApp(const MyApp(PrimaryScreen()));
}
