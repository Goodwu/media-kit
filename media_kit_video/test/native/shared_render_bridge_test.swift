import Foundation
import CoreVideo

@main enum SharedBridgeTest {
  static func main() {
    GpuNextRenderABI.withTarget(primaries: 2, transfer: 3, width: 3840, height: 2160,
      internalFormat: 0x881A, componentDepth: 16, referenceWhite: 203, peak: 406, black: 0) { p in
      assert(p.load(as: UInt32.self) == 1)
      assert(p.load(fromByteOffset: 4, as: UInt32.self) == 64)
      assert(p.load(fromByteOffset: 20, as: UInt32.self) == 3840)
      assert(p.load(fromByteOffset: 36, as: Float.self) == 203)
      assert(p.load(fromByteOffset: 40, as: Float.self) == 406)
      for offset in stride(from: 48, to: 64, by: 4) {
        assert(p.load(fromByteOffset: offset, as: UInt32.self) == 0)
      }
    }
    GpuNextRenderABI.withDiagnostics { p in
      assert(p.load(fromByteOffset: 4, as: UInt32.self) == 28)
      assert(!GpuNextRenderABI.hasDegradation(p))
      for offset in [8, 12, 16] {
        p.storeBytes(of: UInt32(1), toByteOffset: offset, as: UInt32.self)
        assert(GpuNextRenderABI.hasDegradation(p))
        p.storeBytes(of: UInt32(0), toByteOffset: offset, as: UInt32.self)
      }
    }
    let handle: Int64 = 99281
    NativeFrameRegistry.register(handle: handle) { nil }
    assert(NativeFrameRegistry.publishDisplayHeadroom(handle: handle, value: 2))
    let first = NativeFrameRegistry.outputSnapshot(handle: handle)
    assert(first.currentHeadroom == 2 && !first.floatEnabled)
    assert(!NativeFrameRegistry.publishDisplayHeadroom(handle: handle, value: 2))
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: true)
    let second = NativeFrameRegistry.outputSnapshot(handle: handle)
    assert(second.floatEnabled && second.epoch == first.epoch + 1)
    NativeFrameRegistry.setFloatOutputEnabled(handle: handle, enabled: true)
    assert(NativeFrameRegistry.outputSnapshot(handle: handle).epoch == second.epoch)
    var buffer: CVPixelBuffer?
    assert(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_64RGBAHalf,
      nil, &buffer) == kCVReturnSuccess)
    let pixelBuffer = buffer!
    NativeFrameRegistry.setSharedRenderer(handle: handle, enabled: true)
    assert(!NativeFrameRegistry.hasAcceptedSharedTarget(handle: handle))
    NativeFrameRegistry.markProduced(handle: handle, pixelBuffer: pixelBuffer, epoch: second.epoch)
    assert(NativeFrameRegistry.hasAcceptedSharedTarget(handle: handle))
    assert(NativeFrameRegistry.isCurrentOutputFrame(handle: handle, pixelBuffer: pixelBuffer))
    assert(NativeFrameRegistry.tryAcquireCurrentFrame(handle: handle, pixelBuffer: pixelBuffer))
    assert(!NativeFrameRegistry.tryAcquireCurrentFrame(handle: handle, pixelBuffer: pixelBuffer))
    NativeFrameRegistry.completeInFlight(handle: handle, pixelBuffer: pixelBuffer)
    assert(NativeFrameRegistry.tryAcquireCurrentFrame(handle: handle, pixelBuffer: pixelBuffer))
    NativeFrameRegistry.completeInFlight(handle: handle, pixelBuffer: pixelBuffer)
    var otherBuffer: CVPixelBuffer?
    assert(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_64RGBAHalf,
      nil, &otherBuffer) == kCVReturnSuccess)
    let pool = SwappableObjectManager<CVPixelBuffer>(objects: [pixelBuffer, otherBuffer!])
    pool.pushAsReady(pool.nextAvailable()!)
    NativeFrameRegistry.registerLeaseProvider(handle: handle) {
      pool.withCurrentSnapshot { current in
        guard let current, NativeFrameRegistry.tryAcquireCurrentFrame(handle: handle,
          pixelBuffer: current) else { return nil }
        return current
      }
    }
    assert(NativeFrameRegistry.acquireFrame(handle: handle) === pixelBuffer)
    pool.pushAsReady(pool.nextAvailable()!) {
      NativeFrameRegistry.isInFlight(handle: handle, pixelBuffer: $0)
    }
    assert(pool.nextAvailable() == nil)
    NativeFrameRegistry.completeInFlight(handle: handle, pixelBuffer: pixelBuffer)
    pool.releaseHeld { !NativeFrameRegistry.isInFlight(handle: handle, pixelBuffer: $0) }
    assert(pool.nextAvailable() === pixelBuffer)
    NativeFrameRegistry.advanceOutputEpoch(handle: handle)
    assert(!NativeFrameRegistry.isCurrentOutputFrame(handle: handle, pixelBuffer: pixelBuffer))
    assert(!NativeFrameRegistry.hasAcceptedSharedTarget(handle: handle))
    assert(!NativeFrameRegistry.tryAcquireCurrentFrame(handle: handle, pixelBuffer: pixelBuffer))
    NativeFrameRegistry.markProduced(handle: handle, pixelBuffer: pixelBuffer, epoch: second.epoch)
    assert(!NativeFrameRegistry.isCurrentOutputFrame(handle: handle, pixelBuffer: pixelBuffer))
    assert(NativeFrameRegistry.publishDisplayHeadroom(handle: handle, value: .nan))
    assert(NativeFrameRegistry.outputSnapshot(handle: handle).currentHeadroom == nil)
    NativeFrameRegistry.unregister(handle: handle)
    assert(NativeFrameRegistry.outputSnapshot(handle: handle).currentHeadroom == nil)
    print("PASS: target ABI layout/reserved fields, diagnostics gates, coherent display/format epochs and cleanup")
  }
}
