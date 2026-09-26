#include <jni.h>
#include <android/hardware_buffer.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <dlfcn.h>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>

namespace {
bool has_gl_extension(const char* name, bool es3) {
  if (es3) {
    GLint count = 0;
    glGetIntegerv(GL_NUM_EXTENSIONS, &count);
    for (GLint index = 0; index < count; ++index) {
      const char* extension = reinterpret_cast<const char*>(
          glGetStringi(GL_EXTENSIONS, static_cast<GLuint>(index)));
      if (extension != nullptr && std::string(extension) == name) return true;
    }
    return false;
  }
  const char* extensions = reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS));
  if (extensions == nullptr) return false;
  const std::string list = std::string(" ") + extensions + " ";
  return list.find(std::string(" ") + name + " ") != std::string::npos;
}

GLuint compile_shader(GLenum type, const char* source) {
  const GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, nullptr);
  glCompileShader(shader);
  GLint compiled = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
  if (compiled != GL_TRUE) {
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

std::string sample_texture(GLuint external_texture, bool es3, bool raw_yuv,
                           int precision_mode,
                           uint32_t image_width, uint32_t image_height,
                           uint32_t crop_left, uint32_t crop_top,
                           uint32_t crop_right, uint32_t crop_bottom) {
  const uint32_t crop_width = crop_right - crop_left;
  const uint32_t crop_height = crop_bottom - crop_top;
  const char* vertex_source = raw_yuv ?
      "#version 300 es\n"
      "in vec2 position;"
      "void main() { gl_Position = vec4(position, 0.0, 1.0); }" :
      "attribute vec2 position;"
      "void main() { gl_Position = vec4(position, 0.0, 1.0); }";
  const char* fragment_source = raw_yuv ?
      "#version 300 es\n"
      "#extension GL_EXT_YUV_target : require\n"
      "precision highp float;"
      "precision highp __samplerExternal2DY2YEXT;"
      "uniform __samplerExternal2DY2YEXT video;"
      "uniform vec2 sampleUv;"
      "out vec4 color;"
      "void main() { color = texture(video, sampleUv); }" :
      "#extension GL_OES_EGL_image_external : require\n"
      "precision mediump float;"
      "uniform samplerExternalOES video;"
      "uniform vec2 sampleUv;"
      "void main() { gl_FragColor = texture2D(video, sampleUv); }";
  const char* highp_float_fragment_source =
      "#extension GL_OES_EGL_image_external : require\n"
      "precision highp float;"
      "uniform samplerExternalOES video;"
      "uniform vec2 sampleUv;"
      "void main() { gl_FragColor = texture2D(video, sampleUv); }";
  const char* highp_sampler_fragment_source =
      "#extension GL_OES_EGL_image_external : require\n"
      "precision highp float;"
      "precision highp samplerExternalOES;"
      "uniform samplerExternalOES video;"
      "uniform vec2 sampleUv;"
      "void main() { gl_FragColor = texture2D(video, sampleUv); }";
  GLuint vertex = compile_shader(GL_VERTEX_SHADER, vertex_source);
  GLuint fragment = compile_shader(GL_FRAGMENT_SHADER,
      raw_yuv || precision_mode == 0 ? fragment_source :
      precision_mode == 1 || precision_mode == 3 ? highp_float_fragment_source :
      highp_sampler_fragment_source);
  if (vertex == 0 || fragment == 0) {
    if (vertex != 0) glDeleteShader(vertex);
    if (fragment != 0) glDeleteShader(fragment);
    return "shader-compile-failed";
  }
  GLuint program = glCreateProgram();
  glAttachShader(program, vertex);
  glAttachShader(program, fragment);
  glLinkProgram(program);
  GLint linked = GL_FALSE;
  glGetProgramiv(program, GL_LINK_STATUS, &linked);
  glDeleteShader(vertex);
  glDeleteShader(fragment);
  if (linked != GL_TRUE) {
    glDeleteProgram(program);
    return "shader-link-failed";
  }
  GLuint target_texture = 0;
  GLuint framebuffer = 0;
  glGenTextures(1, &target_texture);
  glBindTexture(GL_TEXTURE_2D, target_texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glGenFramebuffers(1, &framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         target_texture, 0);
  std::ostringstream out;
  out << "fboStatus=0x" << std::hex << glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
    glViewport(0, 0, 1, 1);
    glDisable(GL_DITHER);
    glDisable(GL_BLEND);
    glUseProgram(program);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_EXTERNAL_OES, external_texture);
    const GLenum filter = precision_mode == 3 ? GL_LINEAR : GL_NEAREST;
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, filter);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, filter);
    glUniform1i(glGetUniformLocation(program, "video"), 0);
    const GLint uv = glGetUniformLocation(program, "sampleUv");
    const GLint position = glGetAttribLocation(program, "position");
    const GLfloat triangle[] = {-1.f, -1.f, 3.f, -1.f, -1.f, 3.f};
    glEnableVertexAttribArray(position);
    glVertexAttribPointer(position, 2, GL_FLOAT, GL_FALSE, 0, triangle);
    for (float x : {0.1f, 0.5f, 0.9f}) {
      const float sample_x = (crop_left + static_cast<uint32_t>(x * crop_width) + 0.5f) /
                             image_width;
      const float sample_y = (crop_top + crop_height / 2 + 0.5f) / image_height;
      glUniform2f(uv, sample_x, sample_y);
      glDrawArrays(GL_TRIANGLES, 0, 3);
      unsigned char rgba[4]{};
      glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
      out << " x" << std::dec << x << "=" << static_cast<int>(rgba[0])
          << "," << static_cast<int>(rgba[1]) << ","
          << static_cast<int>(rgba[2]) << "," << static_cast<int>(rgba[3]);
    }
    if (es3) {
      GLuint ten_bit_texture = 0;
      glGenTextures(1, &ten_bit_texture);
      glBindTexture(GL_TEXTURE_2D, ten_bit_texture);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB10_A2, 1, 1, 0, GL_RGBA,
                   GL_UNSIGNED_INT_2_10_10_10_REV, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                             GL_TEXTURE_2D, ten_bit_texture, 0);
      out << " tenBitFboStatus=0x" << std::hex
          << glCheckFramebufferStatus(GL_FRAMEBUFFER);
      if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
        const int sample_points[][2] = {
            {233, 10}, {234, 10}, {235, 10}, {236, 10},
            {237, 10}, {238, 10}, {240, 10}, {252, 10}};
        for (const auto& point : sample_points) {
          const float sample_x = (crop_left + point[0] + 0.5f) / image_width;
          const float sample_y = (crop_top + point[1] + 0.5f) / image_height;
          glUniform2f(uv, sample_x, sample_y);
          glDrawArrays(GL_TRIANGLES, 0, 3);
          uint32_t packed = 0;
          glReadPixels(0, 0, 1, 1, GL_RGBA,
                       GL_UNSIGNED_INT_2_10_10_10_REV, &packed);
          const GLenum read_error = glGetError();
          out << std::dec << " pt-" << point[0] << "," << point[1] << "=" << (packed & 1023)
              << "," << ((packed >> 10) & 1023)
              << "," << ((packed >> 20) & 1023)
              << " err=0x" << std::hex << read_error;
        }
      }
      glDeleteTextures(1, &ten_bit_texture);
      {
        GLuint float_texture = 0;
        glGenTextures(1, &float_texture);
        glBindTexture(GL_TEXTURE_2D, float_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, 1, 1, 0, GL_RGBA,
                     GL_HALF_FLOAT, nullptr);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_2D, float_texture, 0);
        const GLenum float_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        out << " floatFboStatus=0x" << std::hex << float_status;
        if (float_status == GL_FRAMEBUFFER_COMPLETE) {
          for (int x : {233, 234, 235, 236, 237, 238, 240, 252}) {
            const float sample_x = (crop_left + x + 0.5f) / image_width;
            const float sample_y = (crop_top + 10 + 0.5f) / image_height;
            glUniform2f(uv, sample_x, sample_y);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            GLfloat rgba[4]{};
            glReadPixels(0, 0, 1, 1, GL_RGBA, GL_FLOAT, rgba);
            const GLenum read_error = glGetError();
            out << " ptFloat-" << std::dec << x << ",10=" << std::setprecision(9) << rgba[0] << ","
                << rgba[1] << "," << rgba[2] << " err=0x" << std::hex
                << read_error;
          }
        }
        glDeleteTextures(1, &float_texture);
      }
    }
    glDisableVertexAttribArray(position);
  }
  out << " sampleError=0x" << std::hex << glGetError();
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glDeleteFramebuffers(1, &framebuffer);
  glDeleteTextures(1, &target_texture);
  glDeleteProgram(program);
  return out.str();
}
}  // namespace

// Diagnostic only. Sampling proves GPU access, not 10-bit precision, YUV
// conversion fidelity, or Dolby Vision correctness.
extern "C" JNIEXPORT jstring JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_inspectGpuImport(
    JNIEnv* env, jclass, jobject java_buffer, jint crop_left, jint crop_top,
    jint crop_right, jint crop_bottom) {
  std::ostringstream out;
  void* library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
  using FromJava = AHardwareBuffer* (*)(JNIEnv*, jobject);
  auto from_java = library == nullptr ? nullptr : reinterpret_cast<FromJava>(
      dlsym(library, "AHardwareBuffer_fromHardwareBuffer"));
  AHardwareBuffer* buffer = from_java == nullptr ? nullptr :
      from_java(env, java_buffer);
  if (buffer == nullptr) {
    if (library != nullptr) dlclose(library);
    return env->NewStringUTF("buffer-unavailable");
  }

  EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface surface = EGL_NO_SURFACE;
  EGLImageKHR image = EGL_NO_IMAGE_KHR;
  GLuint texture = 0;
  bool current = false;
  bool es3 = false;
  using GetNativeClientBuffer = EGLClientBuffer (*)(const AHardwareBuffer*);
  auto get_client_buffer = reinterpret_cast<GetNativeClientBuffer>(
      eglGetProcAddress("eglGetNativeClientBufferANDROID"));
  auto create_image = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
      eglGetProcAddress("eglCreateImageKHR"));
  auto destroy_image = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
      eglGetProcAddress("eglDestroyImageKHR"));
  auto bind_image = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
      eglGetProcAddress("glEGLImageTargetTexture2DOES"));

  do {
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, nullptr, nullptr)) {
      out << "eglInitialize-failed error=0x" << std::hex << eglGetError();
      break;
    }
    EGLConfig config = nullptr;
    EGLint count = 0;
    const EGLint config_attributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE};
    if (!eglChooseConfig(display, config_attributes, &config, 1, &count) ||
        count < 1) {
      out << "eglChooseConfig-failed error=0x" << std::hex << eglGetError();
      break;
    }
    const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    context = eglCreateContext(display, config, EGL_NO_CONTEXT,
                               context_attributes);
    if (context != EGL_NO_CONTEXT) {
      es3 = true;
    } else {
      const EGLint fallback_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2,
                                            EGL_NONE};
      context = eglCreateContext(display, config, EGL_NO_CONTEXT,
                                 fallback_attributes);
    }
    const EGLint surface_attributes[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    surface = eglCreatePbufferSurface(display, config, surface_attributes);
    if (context == EGL_NO_CONTEXT || surface == EGL_NO_SURFACE ||
        !eglMakeCurrent(display, surface, surface, context)) {
      out << "eglMakeCurrent-failed error=0x" << std::hex << eglGetError();
      break;
    }
    current = true;
    out << "es3=" << es3 << " ";
    out << "externalOes=" << has_gl_extension("GL_OES_EGL_image_external", es3)
        << " extYuvTarget=" << has_gl_extension("GL_EXT_YUV_target", es3);
    if (get_client_buffer == nullptr || create_image == nullptr ||
        destroy_image == nullptr || bind_image == nullptr) {
      out << " egl-image-symbol-missing";
      break;
    }
    EGLClientBuffer client_buffer = get_client_buffer(buffer);
    if (client_buffer == nullptr) {
      out << " native-client-buffer-null";
      break;
    }
    const EGLint image_attributes[] = {EGL_IMAGE_PRESERVED_KHR, EGL_TRUE,
                                       EGL_NONE};
    image = create_image(display, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID,
                         client_buffer, image_attributes);
    out << " imageCreated=" << (image != EGL_NO_IMAGE_KHR);
    if (image == EGL_NO_IMAGE_KHR) {
      out << " eglError=0x" << std::hex << eglGetError();
      break;
    }
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_EXTERNAL_OES, texture);
    bind_image(GL_TEXTURE_EXTERNAL_OES,
               reinterpret_cast<GLeglImageOES>(image));
    const GLenum bind_error = glGetError();
    out << " textureBindError=0x" << std::hex << bind_error;
    if (bind_error == GL_NO_ERROR) {
      using Describe = void (*)(const AHardwareBuffer*, AHardwareBuffer_Desc*);
      auto describe = reinterpret_cast<Describe>(
          dlsym(library, "AHardwareBuffer_describe"));
      AHardwareBuffer_Desc desc{};
      if (describe != nullptr) describe(buffer, &desc);
      if (desc.width == 0 || desc.height == 0) {
        out << " invalid-buffer-dimensions";
        break;
      }
      out << " imageSize=" << std::dec << desc.width << "x" << desc.height;
      const bool valid_crop = crop_left >= 0 && crop_top >= 0 &&
          crop_right > crop_left && crop_bottom > crop_top &&
          static_cast<uint32_t>(crop_right) <= desc.width &&
          static_cast<uint32_t>(crop_bottom) <= desc.height;
      out << " crop=" << crop_left << "," << crop_top << ","
          << crop_right << "," << crop_bottom
          << " cropValid=" << valid_crop;
      out << " sampleFull=" << sample_texture(texture, es3, false, 0,
          desc.width, desc.height, 0, 0, desc.width, desc.height);
      out << " sampleFullHighpFloat=" << sample_texture(texture, es3, false, 1,
          desc.width, desc.height, 0, 0, desc.width, desc.height);
      out << " sampleFullHighpSampler=" << sample_texture(texture, es3, false, 2,
          desc.width, desc.height, 0, 0, desc.width, desc.height);
      out << " sampleFullHighpLinear=" << sample_texture(texture, es3, false, 3,
          desc.width, desc.height, 0, 0, desc.width, desc.height);
      if (valid_crop && (crop_left != 0 || crop_top != 0 ||
                         static_cast<uint32_t>(crop_right) != desc.width ||
                         static_cast<uint32_t>(crop_bottom) != desc.height)) {
        out << " sampleCrop=" << sample_texture(texture, es3, false, 0,
            desc.width, desc.height, crop_left, crop_top,
            crop_right, crop_bottom);
        out << " sampleCropHighpFloat=" << sample_texture(texture, es3, false, 1,
            desc.width, desc.height, crop_left, crop_top,
            crop_right, crop_bottom);
        out << " sampleCropHighpSampler=" << sample_texture(texture, es3, false, 2,
            desc.width, desc.height, crop_left, crop_top,
            crop_right, crop_bottom);
        out << " sampleCropHighpLinear=" << sample_texture(texture, es3, false, 3,
            desc.width, desc.height, crop_left, crop_top,
            crop_right, crop_bottom);
      }
      if (es3 && has_gl_extension("GL_EXT_YUV_target", es3)) {
        out << " rawYuvFull=" << sample_texture(texture, es3, true, 0,
            desc.width, desc.height, 0, 0, desc.width, desc.height);
        if (valid_crop && (crop_left != 0 || crop_top != 0 ||
                           static_cast<uint32_t>(crop_right) != desc.width ||
                           static_cast<uint32_t>(crop_bottom) != desc.height)) {
          out << " rawYuvCrop=" << sample_texture(texture, es3, true, 0,
              desc.width, desc.height, crop_left, crop_top,
              crop_right, crop_bottom);
        }
      }
    }
  } while (false);

  if (texture != 0 && current) glDeleteTextures(1, &texture);
  if (image != EGL_NO_IMAGE_KHR && destroy_image != nullptr) {
    destroy_image(display, image);
  }
  if (current) eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                              EGL_NO_CONTEXT);
  if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
  if (context != EGL_NO_CONTEXT) eglDestroyContext(display, context);
  if (display != EGL_NO_DISPLAY) eglTerminate(display);
  dlclose(library);
  return env->NewStringUTF(out.str().c_str());
}
