import Foundation

/// Private opengl-next v1 ABI. Keep offsets synchronized with
/// video/out/gpu_next/libmpv_gpu_next.h; Swift struct layout is not a C ABI.
enum GpuNextRenderABI {
  static let targetParameter: UInt32 = 0x47504e01
  static let diagnosticsParameter: UInt32 = 0x47504e02

  static func withTarget<Result>(
    primaries: UInt32, transfer: UInt32, width: UInt32, height: UInt32,
    internalFormat: UInt32, componentDepth: UInt32,
    referenceWhite: Float, peak: Float, black: Float,
    body: (UnsafeMutableRawPointer) throws -> Result
  ) rethrows -> Result {
    let storage = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 4)
    defer { storage.deallocate() }
    storage.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
    let words: [UInt32] = [1, 64, primaries, transfer, 1, width, height,
                           internalFormat, componentDepth]
    for (index, word) in words.enumerated() {
      storage.storeBytes(of: word, toByteOffset: index * 4, as: UInt32.self)
    }
    for (index, value) in [referenceWhite, peak, black].enumerated() {
      storage.storeBytes(of: value, toByteOffset: 36 + index * 4, as: Float.self)
    }
    return try body(storage)
  }

  static func withDiagnostics<Result>(
    body: (UnsafeMutableRawPointer) throws -> Result
  ) rethrows -> Result {
    let storage = UnsafeMutableRawPointer.allocate(byteCount: 28, alignment: 4)
    defer { storage.deallocate() }
    storage.initializeMemory(as: UInt8.self, repeating: 0, count: 28)
    storage.storeBytes(of: UInt32(1), as: UInt32.self)
    storage.storeBytes(of: UInt32(28), toByteOffset: 4, as: UInt32.self)
    return try body(storage)
  }

  static func hasDegradation(_ diagnostics: UnsafeRawPointer) -> Bool {
    [8, 12, 16].contains {
      diagnostics.load(fromByteOffset: $0, as: UInt32.self) != 0
    }
  }
}
