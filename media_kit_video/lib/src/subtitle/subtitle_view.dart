/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import 'package:media_kit_video/src/video_controller/video_controller.dart';

/// Flutter-rendered subtitles, independently composited above video output.
class SubtitleView extends StatefulWidget {
  const SubtitleView({
    super.key,
    required this.controller,
    required this.configuration,
    this.enableDragSubtitle = false,
    this.onUpdatePadding,
  });

  final VideoController controller;
  final SubtitleViewConfiguration configuration;
  final bool enableDragSubtitle;
  final ValueChanged<EdgeInsets>? onUpdatePadding;

  @override
  SubtitleViewState createState() => SubtitleViewState();
}

class SubtitleViewState extends State<SubtitleView> {
  late List<String> subtitle;
  late EdgeInsets padding;
  Duration duration = const Duration(milliseconds: 100);
  StreamSubscription<List<String>>? subscription;
  int _generation = 0;

  static const kTextScaleFactorReferenceWidth = 1920.0;
  static const kTextScaleFactorReferenceHeight = 1080.0;

  void _bind() {
    final generation = ++_generation;
    unawaited(subscription?.cancel());
    subtitle = widget.controller.player.state.subtitle;
    subscription = widget.controller.player.stream.subtitle.listen((value) {
      if (!mounted || generation != _generation) return;
      setState(() => subtitle = value);
    });
  }

  @override
  void initState() {
    super.initState();
    padding = widget.configuration.padding;
    _bind();
  }

  @override
  void didUpdateWidget(SubtitleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) _bind();
    if (widget.configuration.padding != oldWidget.configuration.padding) {
      padding = widget.configuration.padding;
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(subscription?.cancel());
    super.dispose();
  }

  void setPadding(EdgeInsets padding, {
    Duration duration = const Duration(milliseconds: 100),
  }) {
    setState(() {
      this.padding = padding;
      this.duration = duration;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.configuration.visible) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final area = constraints.maxWidth * constraints.maxHeight;
      const reference = kTextScaleFactorReferenceWidth * kTextScaleFactorReferenceHeight;
      final scale = sqrt((area / reference).clamp(0.0, 1.0));
      final config = widget.configuration;
      final scaler = config.textScaler ?? TextScaler.linear(config.textScaleFactor ?? scale);
      final value = [for (final line in subtitle) if (line.trim().isNotEmpty) line.trim()].join('\n');
      Widget text(TextStyle style) => Text(
        value, style: style, textAlign: config.textAlign, textScaler: scaler,
      );
      Widget content = config.strokeStyle == null ? text(config.style) : Stack(
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(child: text(config.strokeStyle!)),
          text(config.style),
        ],
      );
      if (widget.enableDragSubtitle) {
        content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            setState(() {
              duration = Duration.zero;
              padding = padding.copyWith(
                bottom: (padding.bottom - details.delta.dy).clamp(0.0, 200.0).toDouble(),
              );
            });
          },
          onVerticalDragEnd: (_) {
            duration = const Duration(milliseconds: 100);
            widget.onUpdatePadding?.call(padding);
          },
          child: content,
        );
      }
      return Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          padding: padding,
          duration: duration,
          alignment: Alignment.bottomCenter,
          child: content,
        ),
      );
    });
  }
}

/// Subtitle appearance. Existing responsive scaling remains the default;
/// callers supplying pre-scaled text can explicitly use textScaleFactor: 1.
class SubtitleViewConfiguration {
  const SubtitleViewConfiguration({
    this.visible = true,
    this.style = const TextStyle(
      height: 1.4,
      fontSize: 32.0,
      letterSpacing: 0.0,
      wordSpacing: 0.0,
      color: Color(0xffffffff),
      fontWeight: FontWeight.normal,
      backgroundColor: Color(0xaa000000),
    ),
    this.strokeStyle,
    this.textAlign = TextAlign.center,
    this.textScaler,
    this.textScaleFactor,
    this.padding = const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 24.0),
  }) : assert(textScaler == null || textScaleFactor == null),
       assert(textScaleFactor == null || textScaleFactor >= 0);

  final bool visible;
  final TextStyle style;
  final TextStyle? strokeStyle;
  final TextAlign textAlign;
  final TextScaler? textScaler;
  final double? textScaleFactor;
  final EdgeInsets padding;

  SubtitleViewConfiguration copyWith({
    bool? visible,
    TextStyle? style,
    TextStyle? strokeStyle,
    TextAlign? textAlign,
    TextScaler? textScaler,
    double? textScaleFactor,
    EdgeInsets? padding,
  }) => SubtitleViewConfiguration(
    visible: visible ?? this.visible,
    style: style ?? this.style,
    strokeStyle: strokeStyle ?? this.strokeStyle,
    textAlign: textAlign ?? this.textAlign,
    textScaler: textScaleFactor != null ? null : textScaler ?? this.textScaler,
    textScaleFactor: textScaler != null ? null : textScaleFactor ?? this.textScaleFactor,
    padding: padding ?? this.padding,
  );

  @override
  bool operator ==(Object other) => identical(this, other) ||
      other is SubtitleViewConfiguration && other.visible == visible &&
      other.style == style && other.strokeStyle == strokeStyle &&
      other.textAlign == textAlign && other.textScaler == textScaler &&
      other.textScaleFactor == textScaleFactor && other.padding == padding;

  @override
  int get hashCode => Object.hash(visible, style, strokeStyle, textAlign,
                                  textScaler, textScaleFactor, padding);
}
