import 'dart:async';

/// Coalesce the width/height notifications of a video reconfiguration without
/// introducing another state owner. Each subscriber owns and cancels both legs.
Stream<(int, int)> legacyDimensions(Stream<int?> widths, Stream<int?> heights) =>
    Stream<(int, int)>.multi((output) {
      var width = 0;
      var height = 0;
      var cancelled = false;
      var pending = false;
      var done = 0;
      (int, int)? previous;
      void emit() {
        pending = false;
        if (cancelled) return;
        final next = (width, height);
        if (next != previous) {
          previous = next;
          output.add(next);
        }
      }
      void schedule() {
        if (pending || cancelled) return;
        pending = true;
        scheduleMicrotask(emit);
      }
      void close() {
        if (++done == 2) {
          scheduleMicrotask(() {
            if (!cancelled) {
              if (pending) emit();
              output.close();
            }
          });
        }
      }
      final w = widths.listen((value) { width = value ?? 0; schedule(); },
          onError: output.addError, onDone: close);
      final h = heights.listen((value) { height = value ?? 0; schedule(); },
          onError: output.addError, onDone: close);
      output.onCancel = () async {
        cancelled = true;
        await Future.wait([w.cancel(), h.cancel()]);
      };
    }, isBroadcast: true);
