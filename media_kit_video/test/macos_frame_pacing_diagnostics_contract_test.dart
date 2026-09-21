import 'dart:io';

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void main() {
  final view = File(
    'common/darwin/Classes/plugin/NativeSurfaceView.swift',
  ).readAsStringSync();
  final blitter = File(
    'common/darwin/Classes/plugin/MetalSurfaceBlitter.swift',
  ).readAsStringSync();

  final diagnosticsStart = view.indexOf(
    'private final class FramePacingDiagnostics',
  );
  final surfaceStart = view.indexOf(
    'final class NativeSurfaceView: NSObject {',
    diagnosticsStart,
  );
  _require(
    diagnosticsStart >= 0 && surfaceStart > diagnosticsStart,
    'macOS frame-pacing diagnostics must remain isolated from the surface',
  );
  final diagnostics = view.substring(diagnosticsStart, surfaceStart);

  _require(
    diagnostics.contains('PILIPLUSX_FRAME_PACING_DIAGNOSTICS') &&
        diagnostics.contains('] == "1"') &&
        !diagnostics.contains('let enabled = true'),
    'diagnostics must require explicit opt-in even in debug builds',
  );
  _require(
    diagnostics.contains('private static let tickLimit = 900') &&
        diagnostics.contains(
          'private static let durationLimit: CFTimeInterval = 15.0',
        ) &&
        diagnostics.contains('guard !finished') &&
        diagnostics.contains('finished = true') &&
        view.contains('framePacingDiagnostics?.isFinished == true') &&
        view.contains('framePacingDiagnostics = nil'),
    'diagnostics must stop after a bounded tick or duration window',
  );
  _require(
    diagnostics.contains('guard !finished, pixelBuffer != nil else { return }'),
    'diagnostics must start its bounded window from an actual video buffer',
  );
  _require(
    RegExp('FramePacingDiagnostics macOS summary')
            .allMatches(diagnostics)
            .length ==
        1,
    'frame timing must emit one aggregate summary without per-frame logs',
  );
  _require(
    view.contains('private var drawDiagnosticsRemaining = 8') &&
        RegExp(r'drawDiagnosticsRemaining -= 1').allMatches(view).length == 2 &&
        view.contains('NativeSurfaceView macOS draw skipped') &&
        view.contains('NativeSurfaceView macOS draw handle='),
    'the pre-existing bounded draw diagnostics must remain available',
  );
  _require(
    diagnostics.contains('tickIntervals') &&
        diagnostics.contains('drawableAvailableCount') &&
        diagnostics.contains('consecutiveBufferReuseCount') &&
        diagnostics.contains('firstSequence') &&
        diagnostics.contains('lastSequence') &&
        diagnostics.contains('cpuWaitDurations') &&
        diagnostics.contains('gpuDurations'),
    'summary must cover tick pacing, drawable availability, buffer reuse, '
    'frame sequence, CPU wait, and GPU duration',
  );
  _require(
    !diagnostics.contains('CVPixelBufferLockBaseAddress') &&
        !diagnostics.contains('getBytes(') &&
        !diagnostics.contains('makeBlitCommandEncoder') &&
        !diagnostics.contains('pixelFormat'),
    'frame-pacing diagnostics must not read or describe video pixels',
  );

  final drawStart = blitter.indexOf('func draw(');
  final sampleStart = blitter.indexOf('private func sampleInput', drawStart);
  _require(
    drawStart >= 0 && sampleStart > drawStart,
    'Metal draw method must remain inspectable',
  );
  final draw = blitter.substring(drawStart, sampleStart);
  final wait = draw.indexOf('command.waitUntilCompleted()');
  _require(
    wait >= 0 &&
        RegExp(r'command\.waitUntilCompleted\(\)').allMatches(draw).length ==
            1 &&
        draw.indexOf('let waitStarted = timingHandler == nil') < wait &&
        draw.indexOf('if let timingHandler, let waitStarted', wait) > wait &&
        draw.contains('command.gpuStartTime') &&
        draw.contains('command.gpuEndTime'),
    'timing must observe the existing Metal wait without adding another wait',
  );
  _require(
    !draw.contains('addCompletedHandler') &&
        !draw.contains('DispatchSemaphore') &&
        !draw.contains('sleep(') &&
        !draw.contains('getBytes(') &&
        !draw.contains('CVPixelBufferLockBaseAddress'),
    'timing instrumentation must not add synchronization or pixel readback',
  );
}
