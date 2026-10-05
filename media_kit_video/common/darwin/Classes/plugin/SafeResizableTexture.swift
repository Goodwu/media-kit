import CoreGraphics
import CoreVideo
import Foundation

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// This class avoids data race when called from a thread
public class SafeResizableTexture:
  NSObject,
  FlutterTexture,
  ResizableTextureProtocol
{
  private let lock = NSRecursiveLock()
  private let child: ResizableTextureProtocol

  init(_ child: ResizableTextureProtocol) {
    self.child = child
  }

  public func resize(_ size: CGSize) {
    return locked {
      return child.resize(size)
    }
  }

  public func render(_ size: CGSize) {
    return locked {
      return child.render(size)
    }
  }

  #if os(macOS)
  // Same original wrapper mutex and exactly one child render. The token comes
  // from this call, never from a latest/global sequence or recycled identity.
  func render(_ size: CGSize, diagnosticRequest: CompletedRenderRequest?) -> CompletedRenderToken? {
    return locked {
      if let hardware = child as? TextureHW {
        return hardware.render(size, diagnosticRequest: diagnosticRequest)
      }
      child.render(size)
      return nil
    }
  }
  #endif

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return child.copyPixelBuffer()
  }

  private func locked<T>(do block: () -> T) -> T {
    lock.lock()
    defer {
      lock.unlock()
    }

    return block()
  }
}
