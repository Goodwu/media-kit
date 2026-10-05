import FlutterMacOS
import Foundation
import OpenGL.GL
import OpenGL.GL3

#if SWIFT_PACKAGE
  import Mpv
#endif

public class TextureHW: NSObject, FlutterTexture, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  private let handle: OpaquePointer
  private let updateCallback: UpdateCallback
  private let nativeSurface: Bool
  private let pixelFormat: CGLPixelFormatObj
  private let context: CGLContextObj
  private let textureCache: CVOpenGLTextureCache
  private var renderContext: OpaquePointer?
  // Candidate packaging records the backend choice in the signed bundle.
  // The environment flag also supports local standalone bridge experiments.
  private let useSharedRenderer =
    Bundle.main.object(forInfoDictionaryKey: "MediaKitSharedRenderer") as? Bool == true ||
    ProcessInfo.processInfo.environment["MEDIA_KIT_SHARED_RENDERER"] == "1"
  private var textureContexts = SwappableObjectManager<TextureGLContext>(
    objects: [],
    skipCheckArgs: true
  )
  private var nativeTextureContexts = SwappableObjectManager<TextureGLContext>(
    objects: [],
    skipCheckArgs: true
  )
  private let outputModeLock = NSLock()
  private var useHalfFloatOutput = false
  private let registryHandle: Int64
  private var completedRenderDiagnostics: CompletedRenderDiagnostics?
  private var failureDiagnostics: SharedRenderFailureDiagnostics?
  private let diagnosticUpdateCallback: ((CompletedRenderRequest?) -> Void)?

  private var isHalfFloatOutput: Bool {
    outputModeLock.lock()
    defer { outputModeLock.unlock() }
    return useHalfFloatOutput
  }

  @discardableResult
  private func setHalfFloatOutput(_ enabled: Bool) -> Bool {
    outputModeLock.lock()
    defer { outputModeLock.unlock() }
    let changed = useHalfFloatOutput != enabled
    useHalfFloatOutput = enabled
    return changed
  }

  init(
    handle: OpaquePointer,
    nativeSurface: Bool = false,
    completedRenderDiagnostics: CompletedRenderDiagnostics? = nil,
    diagnosticUpdateCallback: ((CompletedRenderRequest?) -> Void)? = nil,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.nativeSurface = nativeSurface
    let registryKey = Int64(Int(bitPattern: handle))
    self.registryHandle = registryKey
    self.completedRenderDiagnostics = completedRenderDiagnostics
    self.diagnosticUpdateCallback = diagnosticUpdateCallback
    self.updateCallback = updateCallback
    self.pixelFormat = OpenGLHelpers.createPixelFormat()
    self.context = OpenGLHelpers.createContext(pixelFormat)
    self.textureCache = OpenGLHelpers.createTextureCache(context, pixelFormat)

    super.init()

    NativeFrameRegistry.register(handle: registryHandle) { [weak self] in
      guard let self else { return nil }
      // The native surface is mounted before HDR promotion. Until the Metal
      // layer is verified active, feed it the regular BGRA frame so the
      // candidate surface cannot flash black while it waits for EDR proof.
      return self.isHalfFloatOutput
          ? self.nativeTextureContexts.current?.pixelBuffer
          : self.textureContexts.current?.pixelBuffer
    }
    NativeFrameRegistry.registerLeaseProvider(handle: registryHandle) { [weak self] in
      guard let self, self.isHalfFloatOutput else { return nil }
      let snapshot = self.nativeTextureContexts.withCurrentSnapshot { current -> (CVPixelBuffer?, CompletedRenderToken?, String?) in
        guard let current,
              NativeFrameRegistry.tryAcquireCurrentFrame(handle: self.registryHandle,
                pixelBuffer: current.pixelBuffer) else { return (nil, nil, nil) }
        return (current.pixelBuffer, current.completedRenderToken,
          self.failureDiagnostics == nil ? nil : Self.slotID(current))
      }
      if let buffer = snapshot.0, let slot = snapshot.2 {
        self.failureDiagnostics?.leased(buffer: Self.bufferID(buffer), slot: slot, token: snapshot.1)
      }
      return snapshot.0
    }
    NativeFrameRegistry.observeFloatOutput(handle: registryHandle) { [weak self] handle, enabled in
      guard let self else { return }
      let changed = self.setHalfFloatOutput(enabled)
      if changed {
        let request = self.completedRenderDiagnostics?.makeRequest(source: .floatOutput)
        DispatchQueue.main.async { [weak self] in
          self?.deliverUpdate(request)
        }
      }
    }
    NativeFrameRegistry.observeOutputTarget(handle: registryHandle) { [weak self] in
      DispatchQueue.main.async { [weak self] in self?.deliverUpdate(nil) }
    }
    NativeFrameRegistry.observeSurfaceActive(handle: registryHandle) { [weak self] _ in
      // Active is a post-presentation fact. Notify the output owner on either
      // edge without changing the producer mode here; float-output permission
      // is controlled independently by NativeSurfaceOutput.
      let request = self?.completedRenderDiagnostics?.makeRequest(source: .surfaceActive)
      DispatchQueue.main.async { [weak self] in self?.deliverUpdate(request) }
    }
    NativeFrameRegistry.setFloatFormat(handle: registryHandle, enabled: false)

    NativeFrameRegistry.observeInFlightDrained(handle: registryHandle) { [weak self] in
      self?.releaseHeldTextureContexts()
    }

    self.initMPV()
  }

  deinit {
    if failureDiagnostics != nil { SharedRenderFailureDiagnostics.unregister(handle: registryHandle) }
    NativeFrameRegistry.unregister(handle: registryHandle)
    disposePixelBuffer()
    disposeMPV()
    OpenGLHelpers.deleteTextureCache(textureCache)
    OpenGLHelpers.deletePixelFormat(pixelFormat)

    // Deleting the context may cause potential RAM or VRAM memory leaks, as it
    // is used in the `deinit` method of the `TextureGLContext`.
    // Potential fix: use a counter, and delete it only when the counter reaches
    // zero
    OpenGLHelpers.deleteContext(context)
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let snapshot = textureContexts.withCurrentSnapshot { current -> (Unmanaged<CVPixelBuffer>?, CompletedRenderToken?, String?) in
      guard let current else { return (nil, nil, nil) }
      return (Unmanaged.passRetained(current.pixelBuffer), current.completedRenderToken,
        failureDiagnostics == nil ? nil : Self.slotID(current))
    }
    if let failureDiagnostics {
      let output = NativeFrameRegistry.diagnosticOutputSnapshot(handle: registryHandle)
      failureDiagnostics.flutterCopy(slot: snapshot.2, token: snapshot.1, target: output)
    }
    completedRenderDiagnostics?.consume(token: snapshot.1,
      hasCurrent: snapshot.0 != nil, hasBuffer: snapshot.0 != nil)
    return snapshot.0
  }

  private func deliverUpdate(_ request: CompletedRenderRequest?) {
    completedRenderDiagnostics?.notePhase(request, .mainArrival)
    if completedRenderDiagnostics != nil, let diagnosticUpdateCallback {
      diagnosticUpdateCallback(request)
    } else {
      updateCallback()
    }
  }

  private func initMPV() {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("initMPV")
      CGLSetCurrentContext(nil)
    }

    let apiName = useSharedRenderer ? "opengl-next" : MPV_RENDER_API_TYPE_OPENGL
    var procAddress = mpv_opengl_init_params(
      get_proc_address: {
        (ctx, name) in
        return TextureHW.getProcAddress(ctx, name)
      },
      get_proc_address_ctx: nil
    )

    let createStatus = apiName.withCString { apiName in
      withUnsafeMutablePointer(to: &procAddress) { procAddress in
        var params: [mpv_render_param] = [
          mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiName)),
          mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: procAddress),
          mpv_render_param(),
        ]
        return mpv_render_context_create(&renderContext, handle, &params)
      }
    }
    MPVHelpers.checkError(createStatus)
    NativeFrameRegistry.setSharedRenderer(handle: registryHandle, enabled: useSharedRenderer && createStatus >= 0)
    failureDiagnostics = SharedRenderFailureDiagnostics.make(handle: registryHandle,
      sharedRenderer: useSharedRenderer && createStatus >= 0)
    if failureDiagnostics != nil && completedRenderDiagnostics == nil {
      // Only the explicit failure candidate needs tokens without pacing IO.
      completedRenderDiagnostics = CompletedRenderDiagnostics(active: true,
        automaticSampling: false)
    }

    mpv_render_context_set_update_callback(
      renderContext,
      { (ctx) in
        let that = unsafeBitCast(ctx, to: TextureHW.self)
        let request = that.completedRenderDiagnostics?.makeRequest(source: .mpv)
        DispatchQueue.main.async {
          that.deliverUpdate(request)
        }
      },
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
  }

  private func disposeMPV() {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("disposeMPV")
      CGLSetCurrentContext(nil)
    }

    mpv_render_context_set_update_callback(renderContext, nil, nil)
    mpv_render_context_free(renderContext)
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 {
      return
    }

    NSLog("TextureGL: resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()

    textureContexts.reinit(
      objects: [
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size,
          halfFloat: false
        ),
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size,
          halfFloat: false
        ),
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size,
          halfFloat: false
        ),
      ],
      skipCheckArgs: true
    )
    if nativeSurface {
      nativeTextureContexts.reinit(
        objects: [
          TextureGLContext(
            context: context,
            textureCache: textureCache,
            size: size,
            halfFloat: true
          ),
          TextureGLContext(
            context: context,
            textureCache: textureCache,
            size: size,
            halfFloat: true
          ),
          TextureGLContext(
            context: context,
            textureCache: textureCache,
            size: size,
            halfFloat: true
          ),
        ],
        skipCheckArgs: true
      )
    } else {
      nativeTextureContexts.reinit(objects: [], skipCheckArgs: true)
    }
    setHalfFloatOutput(NativeFrameRegistry.isFloatOutputEnabled(handle: registryHandle))
    NativeFrameRegistry.setFloatFormat(handle: registryHandle, enabled: nativeSurface)
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
    nativeTextureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    _ = render(size, diagnosticRequest: nil)
  }

  func render(_ size: CGSize, diagnosticRequest: CompletedRenderRequest?) -> CompletedRenderToken? {
    var completedToken: CompletedRenderToken?
    // A pool object parked for an async Metal blit may have drained since
    // the last render; return it to the writable pool before asking for
    // the next one.
    releaseHeldTextureContexts()
    // Render exactly one target per mpv update. Rendering both the Flutter
    // texture and the native surface doubles the expensive libplacebo pass and
    // causes visible cadence jitter on high-resolution HDR streams.
    let outputSnapshot = NativeFrameRegistry.outputSnapshot(handle: registryHandle)
    let halfFloat = useSharedRenderer ? outputSnapshot.floatEnabled : isHalfFloatOutput
    let pool = halfFloat ? nativeTextureContexts : textureContexts
    let before = failureDiagnostics == nil ? nil : pool.auditSnapshot(identity: Self.slotID)
    guard let target = pool.nextAvailable() else {
      completedRenderDiagnostics?.noteNoWritableSlot()
      return nil
    }
    let result = render(target, size: size, halfFloat: halfFloat,
      request: diagnosticRequest, snapshot: outputSnapshot, poolBefore: before)
    guard result.succeeded else {
      pool.returnUnpublished(target)
      failureDiagnostics?.finish(result.attempt, rawStatus: result.rawStatus,
        effectiveStatus: result.effectiveStatus,
        target: NativeFrameRegistry.diagnosticOutputSnapshot(handle: registryHandle),
        produced: false, pushed: false, token: nil,
        poolAfter: pool.auditSnapshot(identity: Self.slotID))
      return nil
    }
    completedToken = result.token
    pool.pushAsReady(target, hold: holdForAsyncBlit)
    failureDiagnostics?.finish(result.attempt, rawStatus: result.rawStatus,
      effectiveStatus: result.effectiveStatus,
      target: NativeFrameRegistry.diagnosticOutputSnapshot(handle: registryHandle),
      produced: true, pushed: true, token: completedToken,
      poolAfter: pool.auditSnapshot(identity: Self.slotID))
    NativeFrameRegistry.noteFrameProduced(handle: registryHandle)
    if let completedToken {
      completedRenderDiagnostics?.notePhase(diagnosticRequest, .published, token: completedToken)
    }
    return completedToken
  }

  /// Park predicate for `pushAsReady`: a rotated-out pool object still being
  /// read by an in-flight Metal blit must not return to the writable pool.
  private func holdForAsyncBlit(_ context: TextureGLContext) -> Bool {
    NativeFrameRegistry.isInFlight(handle: registryHandle, pixelBuffer: context.pixelBuffer)
  }

  /// Returns pool objects parked by the async Metal blit back to the
  /// writable pool once their in-flight mark has cleared.
  private func releaseHeldTextureContexts() {
    textureContexts.releaseHeld(where: { !holdForAsyncBlit($0) })
    nativeTextureContexts.releaseHeld(where: { !holdForAsyncBlit($0) })
  }

  private func render(
    _ textureContext: TextureGLContext,
    size: CGSize,
    halfFloat: Bool,
    request: CompletedRenderRequest?,
    snapshot: NativeFrameRegistry.OutputSnapshot,
    poolBefore: [String: Any]?
  ) -> (succeeded: Bool, token: CompletedRenderToken?,
        attempt: SharedRenderFailureDiagnostics.Attempt?, rawStatus: Int32, effectiveStatus: Int32) {
    let outputEpoch = snapshot.epoch
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("render")
      CGLSetCurrentContext(nil)
    }

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), textureContext.frameBuffer)
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    var fbo = mpv_opengl_fbo(
      fbo: Int32(textureContext.frameBuffer),
      w: Int32(size.width),
      h: Int32(size.height),
      internal_format: halfFloat ? Int32(0x881A) : 0
    )
    let targetWidth = UInt32(fbo.w)
    let targetHeight = UInt32(fbo.h)
    let targetInternalFormat = UInt32(fbo.internal_format)
    let normalDepth: UInt32 = halfFloat ? 16 : 8
    var actualDepth = normalDepth
    let diagnosticTarget = failureDiagnostics == nil ? nil :
      NativeFrameRegistry.diagnosticOutputSnapshot(handle: registryHandle)
    let diagnosticQuery = diagnosticTarget.map { target in
      target.epoch == outputEpoch && target.floatEnabled == halfFloat &&
        failureDiagnostics?.prepareAttachmentQuery(target: target) == true
    } ?? false
    if diagnosticQuery {
      // The terminal gate precedes all diagnostic GL reads.
      var attachmentDepth: GLint = 0
      glGetFramebufferAttachmentParameteriv(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
        GLenum(GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE), &attachmentDepth)
      let queryError = glGetError()
      if queryError == GLenum(GL_NO_ERROR), attachmentDepth > 0 {
        actualDepth = UInt32(attachmentDepth)
      } else {
        failureDiagnostics?.cancelBeforeRender("attachmentDepthQueryFailed")
      }
    }
    var failureAttempt: SharedRenderFailureDiagnostics.Attempt?
    if diagnosticQuery, let failureDiagnostics {
      let target = NativeFrameRegistry.diagnosticOutputSnapshot(handle: registryHandle)
      // Revalidate after the real GL query and before altering the mpv target.
      if target.epoch == outputEpoch && target.floatEnabled == halfFloat {
        failureAttempt = failureDiagnostics.begin(target: target, slot: Self.slotID(textureContext),
          actualDepth: actualDepth, poolBefore: poolBefore ?? [:])
      } else {
        _ = failureDiagnostics.prepareAttachmentQuery(target: target)
      }
    }
    let renderStart = completedRenderDiagnostics?.beginRender()
    var rawMpvStatus: Int32 = 0
    let renderStatus = withUnsafeMutablePointer(to: &fbo) { fboPtr -> Int32 in
      if useSharedRenderer {
        let headroom = snapshot.currentHeadroom ?? 1
        return GpuNextRenderABI.withTarget(
          primaries: halfFloat ? 2 : 1, transfer: halfFloat ? 3 : 2,
          width: targetWidth, height: targetHeight,
          internalFormat: targetInternalFormat, componentDepth: failureAttempt?.requestedDepth ?? normalDepth,
          referenceWhite: 203, peak: halfFloat ? Float(203 * headroom) : 203, black: 0
        ) { target in
          GpuNextRenderABI.withDiagnostics { diagnostics in
            var params: [mpv_render_param] = [
              mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
              mpv_render_param(type: mpv_render_param_type(rawValue: GpuNextRenderABI.targetParameter), data: target),
              mpv_render_param(type: mpv_render_param_type(rawValue: GpuNextRenderABI.diagnosticsParameter), data: diagnostics),
              mpv_render_param(),
            ]
            let status = mpv_render_context_render(renderContext, &params)
            rawMpvStatus = status
            let acquired = diagnostics.load(fromByteOffset: 20, as: UInt32.self) == 1
            let valid = diagnostics.load(fromByteOffset: 24, as: UInt32.self) == 1
            return status >= 0 && (!acquired || !valid || GpuNextRenderABI.hasDegradation(diagnostics))
              ? MPV_ERROR_GENERIC.rawValue : status
          }
        }
      }
      var params: [mpv_render_param] = [
        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
        mpv_render_param(),
      ]
      rawMpvStatus = mpv_render_context_render(renderContext, &params)
      return rawMpvStatus
    }
    let renderEnd = renderStart == nil ? nil : ProcessInfo.processInfo.systemUptime
    // mpv renders through the OpenGL producer, while the native surface
    // consumes the resulting IOSurface through Metal. A flush only queues the
    // commands; it does not establish that the producer has finished writing
    // before Metal samples the buffer. Keep this explicit completion fence
    // until the two APIs are connected by a native shared-event path.
    glFinish()
    let currentEpoch = renderStatus >= 0 ? NativeFrameRegistry.currentOutputEpoch(handle: registryHandle) : outputEpoch
    let succeeded = renderStatus >= 0 && currentEpoch == outputEpoch
    let effectiveStatus = succeeded ? renderStatus : (renderStatus < 0 ? renderStatus : MPV_ERROR_GENERIC.rawValue)
    let completedToken: CompletedRenderToken?
    if let renderStart, let renderEnd {
      let fenceEnd = ProcessInfo.processInfo.systemUptime
      // The FBO color attachment is created from this exact pixelBuffer.
      // Observe its allocated dimensions/format only in the enabled token
      // path; requested size and mpv FBO parameters are separate evidence.
      completedToken = completedRenderDiagnostics?.completeRender(
        epoch: outputEpoch, start: renderStart, end: renderEnd,
        fenceEnd: fenceEnd, succeeded: succeeded, request: request,
        actualFboWidth: renderStatus >= 0 ? CVPixelBufferGetWidth(textureContext.pixelBuffer) : nil,
        actualFboHeight: renderStatus >= 0 ? CVPixelBufferGetHeight(textureContext.pixelBuffer) : nil,
        pixelFormatCode: renderStatus >= 0 ? CVPixelBufferGetPixelFormatType(textureContext.pixelBuffer) : nil,
        renderParameterWidth: Int(fbo.w), renderParameterHeight: Int(fbo.h),
        failureAttemptID: failureAttempt?.id, failureSlotID: failureAttempt?.slot
      )
    } else {
      completedToken = nil
    }
    textureContext.completedRenderToken = completedToken
    guard succeeded else {
      return (false, nil, failureAttempt, rawMpvStatus, effectiveStatus)
    }
    NativeFrameRegistry.markProduced(
      handle: registryHandle,
      pixelBuffer: textureContext.pixelBuffer,
      epoch: outputEpoch
    )
    return (true, completedToken, failureAttempt, rawMpvStatus, effectiveStatus)
  }

  private static func slotID(_ value: TextureGLContext) -> String {
    String(describing: ObjectIdentifier(value))
  }
  private static func bufferID(_ value: CVPixelBuffer) -> String {
    String(describing: ObjectIdentifier(value as AnyObject))
  }

  static private func getProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<Int8>?
  ) -> UnsafeMutableRawPointer? {
    let symbol: CFString = CFStringCreateWithCString(
      kCFAllocatorDefault,
      name,
      kCFStringEncodingASCII
    )
    let indentifier = CFBundleGetBundleWithIdentifier(
      "com.apple.opengl" as CFString
    )
    let addr = CFBundleGetFunctionPointerForName(indentifier, symbol)

    if addr == nil {
      NSLog("Cannot get OpenGL function pointer!")
    }
    return addr
  }
}
