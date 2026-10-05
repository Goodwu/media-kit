import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Presentation only: native producer stop/release remains owned by the
/// existing PlatformView lifecycle, never by this lease.
class AndroidOutputPresentationOwner extends ChangeNotifier {
  final _tokens = <Object>{};
  bool _disposed = false;

  bool get suspended => _tokens.isNotEmpty;

  VoidCallback acquire() {
    if (_disposed) return () {};
    final token = Object();
    _tokens.add(token);
    if (_tokens.length == 1) notifyListeners();
    return () {
      if (_disposed || !_tokens.remove(token)) return;
      if (_tokens.isEmpty) notifyListeners();
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _tokens.clear();
    super.dispose();
  }
}

class AndroidOutputPresentationScope
    extends InheritedNotifier<AndroidOutputPresentationOwner> {
  const AndroidOutputPresentationScope({
    super.key,
    required AndroidOutputPresentationOwner owner,
    required super.child,
  }) : super(notifier: owner);

  static AndroidOutputPresentationOwner? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AndroidOutputPresentationScope>()
          ?.notifier;
}

/// A stable presentation owner above controller replacement/null gaps.
/// A fullscreen page creates its own host rather than inheriting the suspended
/// window host, including when a navigator is below the window video.
class AndroidOutputPresentationHost extends StatefulWidget {
  const AndroidOutputPresentationHost({super.key, required this.child});
  final Widget child;

  @override
  State<AndroidOutputPresentationHost> createState() =>
      _AndroidOutputPresentationHostState();
}

class _AndroidOutputPresentationHostState
    extends State<AndroidOutputPresentationHost> {
  final _owner = AndroidOutputPresentationOwner();

  @override
  Widget build(BuildContext context) => AndroidOutputPresentationScope(
        owner: _owner,
        child: widget.child,
      );

  @override
  void dispose() {
    _owner.dispose();
    super.dispose();
  }
}

/// Drops the entire native/Texture output subtree while keeping VideoState,
/// controls, subtitles and viewport constraints alive. [builder] includes
/// layout reporting, so a suspended output cannot publish a stale viewport.
class AndroidOutputPresentationBody extends StatelessWidget {
  const AndroidOutputPresentationBody({
    super.key,
    required this.enabled,
    required this.builder,
  });

  final bool enabled;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (enabled &&
        (AndroidOutputPresentationScope.maybeOf(context)?.suspended ?? false)) {
      return const SizedBox.expand();
    }
    return builder(context);
  }
}

/// Keeps window-owned shared notifiers alive until the pushed route's overlay
/// has gone. Only the original owner requests disposal; borrowing fullscreen
/// VideoStates never dispose shared notifiers. Entries disappear on last release.
class FullscreenNotifierLifetime {
  static final _entries = HashMap<Object, _NotifierLifetimeEntry>.identity();

  static VoidCallback retain(Object owner) {
    final entry = _entries.putIfAbsent(owner, _NotifierLifetimeEntry.new);
    entry.references++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--entry.references != 0) return;
      _entries.remove(owner);
      entry.dispose?.call();
    };
  }

  static void disposeOwner(Object owner, VoidCallback dispose) {
    final entry = _entries[owner];
    if (entry == null) {
      dispose();
    } else {
      entry.dispose ??= dispose;
    }
  }
}

class _NotifierLifetimeEntry {
  int references = 0;
  VoidCallback? dispose;
}
