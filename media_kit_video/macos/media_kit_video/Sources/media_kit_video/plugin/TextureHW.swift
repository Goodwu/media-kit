import FlutterMacOS
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
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.nativeSurface = nativeSurface
    self.registryHandle = Int64(Int(bitPattern: handle))
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
    NativeFrameRegistry.observeFloatOutput(handle: registryHandle) { [weak self] handle, enabled in
      guard let self else { return }
      let changed = self.setHalfFloatOutput(enabled)
      if changed {
        DispatchQueue.main.async { [weak self] in
          self?.updateCallback()
        }
      }
    }
    NativeFrameRegistry.observeSurfaceActive(handle: registryHandle) { [weak self] _ in
      // Active is a post-presentation fact. Notify the output owner on either
      // edge without changing the producer mode here; float-output permission
      // is controlled independently by NativeSurfaceOutput.
      DispatchQueue.main.async { [weak self] in self?.updateCallback() }
    }
    NativeFrameRegistry.setFloatFormat(handle: registryHandle, enabled: false)

    self.initMPV()
  }

  deinit {
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
    let textureContext = textureContexts.current
    if textureContext == nil {
      return nil
    }

    return Unmanaged.passRetained(textureContext!.pixelBuffer)
  }

  private func initMPV() {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("initMPV")
      CGLSetCurrentContext(nil)
    }

    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
    )
    var procAddress = mpv_opengl_init_params(
      get_proc_address: {
        (ctx, name) in
        return TextureHW.getProcAddress(ctx, name)
      },
      get_proc_address_ctx: nil
    )

    var params: [mpv_render_param] = withUnsafeMutableBytes(of: &procAddress) {
      procAddress in
      return [
        mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
        mpv_render_param(
          type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
          data: procAddress.baseAddress.map {
            UnsafeMutableRawPointer($0)
          }
        ),
        mpv_render_param(),
      ]
    }

    MPVHelpers.checkError(
      mpv_render_context_create(&renderContext, handle, &params)
    )

    mpv_render_context_set_update_callback(
      renderContext,
      { (ctx) in
        let that = unsafeBitCast(ctx, to: TextureHW.self)
        DispatchQueue.main.async {
          that.updateCallback()
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
    // Render exactly one target per mpv update. Rendering both the Flutter
    // texture and the native surface doubles the expensive libplacebo pass and
    // causes visible cadence jitter on high-resolution HDR streams.
    if isHalfFloatOutput {
      guard let nativeTextureContext = nativeTextureContexts.nextAvailable() else {
        return
      }
      render(nativeTextureContext, size: size, halfFloat: true)
      nativeTextureContexts.pushAsReady(nativeTextureContext)
    } else if let textureContext = textureContexts.nextAvailable() {
      render(textureContext, size: size, halfFloat: false)
      textureContexts.pushAsReady(textureContext)
    }
  }

  private func render(
    _ textureContext: TextureGLContext,
    size: CGSize,
    halfFloat: Bool
  ) {
    let outputEpoch = NativeFrameRegistry.currentOutputEpoch(handle: registryHandle)
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
    let fboPtr = withUnsafeMutablePointer(to: &fbo) { $0 }

    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]
    mpv_render_context_render(renderContext, &params)
    // mpv renders through the OpenGL producer, while the native surface
    // consumes the resulting IOSurface through Metal. A flush only queues the
    // commands; it does not establish that the producer has finished writing
    // before Metal samples the buffer. Keep this explicit completion fence
    // until the two APIs are connected by a native shared-event path.
    glFinish()
    NativeFrameRegistry.markProduced(
      handle: registryHandle,
      pixelBuffer: textureContext.pixelBuffer,
      epoch: outputEpoch
    )
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
