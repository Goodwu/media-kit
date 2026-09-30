// Vendor dataspace extension + diagnostics probes for the Huawei LYA-AL00
// test device. Everything in this file was moved out of the media_kit_video
// bridge: the library only ships the public NDK dataspace path, and this
// test-app .so carries the device-specific fallback and the property-gated
// diagnostics probes.
#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/hardware_buffer.h>
#include <android/data_space.h>
#include <cstdint>
#include <cstdlib>
#include <cerrno>
#include <cstring>
#include <dlfcn.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <sys/system_properties.h>
#include <vector>
#define VK_USE_PLATFORM_ANDROID_KHR
#include <vulkan/vulkan.h>

#ifndef EGL_GL_COLORSPACE_BT2020_PQ_EXT
#define EGL_GL_COLORSPACE_BT2020_PQ_EXT 0x3340
#endif

static bool lyaPqWindow(ANativeWindow* window) {
  char sdk[PROP_VALUE_MAX] = {};
  char fingerprint[PROP_VALUE_MAX] = {};
  return ANativeWindow_getFormat(window) == AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM &&
      __system_property_get("ro.build.version.sdk", sdk) > 0 &&
      std::strcmp(sdk, "29") == 0 &&
      __system_property_get("ro.build.fingerprint", fingerprint) > 0 &&
      std::strcmp(fingerprint,
          "HUAWEI/LYA-AL00/HWLYA:10/HUAWEILYA-AL00/10.1.0.163C00:user/release-keys") == 0;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_media_1kit_1test_LyaPqDataSpaceExt_nativeApplyPqDataSpace(
    JNIEnv* env, jclass, jobject surface) {
  if (surface == nullptr) return JNI_FALSE;
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return JNI_FALSE;
  jboolean applied = JNI_FALSE;
  if (lyaPqWindow(window)) {
    void* library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
    using GetBuffersDataSpace = int32_t (*)(ANativeWindow*);
    const auto get_dataspace = library == nullptr ? nullptr
        : reinterpret_cast<GetBuffersDataSpace>(
            dlsym(library, "ANativeWindow_getBuffersDataSpace"));
    // This firmware's public setter rejects PQ during its HDR support
    // query, before reaching the window setter. The private ABI is confined
    // to the exact arm64 firmware and 10-bit window proven by the device
    // probe.
#if defined(__aarch64__)
    using WindowPerform = int (*)(ANativeWindow*, int, ...);
    WindowPerform perform = nullptr;
    std::memcpy(&perform,
        reinterpret_cast<const char*>(window) + 0x98, sizeof(perform));
    const int fallback_result = perform == nullptr
        ? -1 : perform(window, 19, ADATASPACE_BT2020_PQ);
    const int32_t actual = get_dataspace == nullptr ? -1 : get_dataspace(window);
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
        "p5PqFirmwareFallback perform=%d actual=%d expected=%d",
        fallback_result, actual, ADATASPACE_BT2020_PQ);
    if (fallback_result == 0 && actual == ADATASPACE_BT2020_PQ) applied = JNI_TRUE;
#endif
    if (library != nullptr) dlclose(library);
  }
  ANativeWindow_release(window);
  return applied;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_media_1kit_1test_LyaPqDataSpaceExt_nativeLatePqProbe(
    JNIEnv* env, jclass, jobject surface) {
  char enabled[PROP_VALUE_MAX] = {};
  if (__system_property_get("debug.media_kit.late_pq_probe", enabled) <= 0 ||
      std::strcmp(enabled, "1") != 0 || surface == nullptr) return;
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return;
  void* library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
  using GetBuffersDataSpace = int32_t (*)(ANativeWindow*);
  using SetBuffersDataSpace = int (*)(ANativeWindow*, int32_t);
  const auto get_dataspace = library == nullptr ? nullptr
      : reinterpret_cast<GetBuffersDataSpace>(
          dlsym(library, "ANativeWindow_getBuffersDataSpace"));
  const auto set_dataspace = library == nullptr ? nullptr
      : reinterpret_cast<SetBuffersDataSpace>(
          dlsym(library, "ANativeWindow_setBuffersDataSpace"));
  const int32_t before = get_dataspace == nullptr ? -1 : get_dataspace(window);
  const int result = set_dataspace == nullptr ? -1
      : set_dataspace(window, ADATASPACE_BT2020_PQ);
  const int32_t during = get_dataspace == nullptr ? -1 : get_dataspace(window);
  const int restore = result == 0 && set_dataspace != nullptr && before >= 0
      ? set_dataspace(window, before) : -1;
  const int32_t after = get_dataspace == nullptr ? -1 : get_dataspace(window);
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
      "latePqProbe format=%d size=%dx%d before=%d set=%d during=%d restore=%d after=%d",
      ANativeWindow_getFormat(window), ANativeWindow_getWidth(window),
      ANativeWindow_getHeight(window), before, result, during, restore, after);
  if (library != nullptr) dlclose(library);
  ANativeWindow_release(window);
}

static void probe_egl_pq_window(ANativeWindow* window) {
  void* android_library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
  using GetBuffersDataSpace = int32_t (*)(ANativeWindow*);
  const auto get_dataspace = android_library == nullptr ? nullptr
      : reinterpret_cast<GetBuffersDataSpace>(
          dlsym(android_library, "ANativeWindow_getBuffersDataSpace"));
  EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (display == EGL_NO_DISPLAY || eglInitialize(display, nullptr, nullptr) != EGL_TRUE) {
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                        "eglPqProbe initialize=failed error=0x%x", eglGetError());
    if (android_library != nullptr) dlclose(android_library);
    return;
  }
  const char* extensions = eglQueryString(display, EGL_EXTENSIONS);
  const bool has_pq = extensions != nullptr &&
      std::strstr(extensions, "EGL_EXT_gl_colorspace_bt2020_pq") != nullptr;
  EGLConfig config = nullptr;
  EGLint count = 0;
  const EGLint config_attrs[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 10,
      EGL_GREEN_SIZE, 10, EGL_BLUE_SIZE, 10, EGL_ALPHA_SIZE, 2, EGL_NONE};
  const EGLBoolean chosen = eglChooseConfig(display, config_attrs, &config, 1, &count);
  EGLSurface surface = EGL_NO_SURFACE;
  EGLint create_error = EGL_SUCCESS;
  int32_t during_dataspace = get_dataspace == nullptr ? -1 : get_dataspace(window);
  if (has_pq && chosen == EGL_TRUE && count > 0) {
    const EGLint surface_attrs[] = {EGL_GL_COLORSPACE_KHR,
        EGL_GL_COLORSPACE_BT2020_PQ_EXT, EGL_NONE};
    surface = eglCreateWindowSurface(display, config, window, surface_attrs);
    create_error = eglGetError();
    during_dataspace = get_dataspace == nullptr ? -1 : get_dataspace(window);
  }
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
      "eglPqProbe extension=%d choose=%d configs=%d created=%d error=0x%x dataspace=%d",
      has_pq ? 1 : 0, chosen == EGL_TRUE ? 1 : 0, count,
      surface != EGL_NO_SURFACE ? 1 : 0, create_error, during_dataspace);
  if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
  eglTerminate(display);
  if (android_library != nullptr) dlclose(android_library);
}

// Read-only query of the exact SurfaceView window. Keep Vulkan dynamically
// loaded so this probe still loads on Android releases without libvulkan.so.
static void probe_vulkan_hdr_window(ANativeWindow* window) {
  void* library = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) {
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                        "vkHdrProbe library=missing");
    return;
  }
  const auto get_proc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
      dlsym(library, "vkGetInstanceProcAddr"));
  if (get_proc == nullptr) {
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                        "vkHdrProbe getInstanceProcAddr=missing");
    dlclose(library);
    return;
  }
  const auto enumerate_extensions =
      reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(
          get_proc(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties"));
  const auto create_instance = reinterpret_cast<PFN_vkCreateInstance>(
      get_proc(VK_NULL_HANDLE, "vkCreateInstance"));
  uint32_t extension_count = 0;
  VkResult result = enumerate_extensions == nullptr || create_instance == nullptr
      ? VK_ERROR_INITIALIZATION_FAILED
      : enumerate_extensions(nullptr, &extension_count, nullptr);
  std::vector<VkExtensionProperties> extensions(extension_count);
  if (result == VK_SUCCESS && extension_count > 0) {
    result = enumerate_extensions(nullptr, &extension_count, extensions.data());
  }
  const auto has_extension = [&](const char* name) {
    for (const auto& extension : extensions) {
      if (std::strcmp(extension.extensionName, name) == 0) return true;
    }
    return false;
  };
  const bool has_surface = has_extension(VK_KHR_SURFACE_EXTENSION_NAME);
  const bool has_android = has_extension(VK_KHR_ANDROID_SURFACE_EXTENSION_NAME);
  const bool has_colorspace = has_extension(VK_EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME);
  if (result != VK_SUCCESS || !has_surface || !has_android) {
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                        "vkHdrProbe extensions result=%d surface=%d android=%d colorspace=%d",
                        result, has_surface, has_android, has_colorspace);
    dlclose(library);
    return;
  }
  const char* enabled_extensions[] = {VK_KHR_SURFACE_EXTENSION_NAME,
      VK_KHR_ANDROID_SURFACE_EXTENSION_NAME,
      VK_EXT_SWAPCHAIN_COLOR_SPACE_EXTENSION_NAME};
  VkInstanceCreateInfo instance_info = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
  instance_info.enabledExtensionCount = has_colorspace ? 3 : 2;
  instance_info.ppEnabledExtensionNames = enabled_extensions;
  VkInstance instance = VK_NULL_HANDLE;
  result = create_instance(&instance_info, nullptr, &instance);
  if (result != VK_SUCCESS) {
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                        "vkHdrProbe createInstance=%d colorspace=%d", result,
                        has_colorspace);
    dlclose(library);
    return;
  }
  const auto destroy_instance = reinterpret_cast<PFN_vkDestroyInstance>(
      get_proc(instance, "vkDestroyInstance"));
  const auto create_surface = reinterpret_cast<PFN_vkCreateAndroidSurfaceKHR>(
      get_proc(instance, "vkCreateAndroidSurfaceKHR"));
  const auto destroy_surface = reinterpret_cast<PFN_vkDestroySurfaceKHR>(
      get_proc(instance, "vkDestroySurfaceKHR"));
  const auto enumerate_devices = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(
      get_proc(instance, "vkEnumeratePhysicalDevices"));
  const auto get_formats = reinterpret_cast<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(
      get_proc(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR"));
  if (create_surface == nullptr || destroy_surface == nullptr ||
      enumerate_devices == nullptr || get_formats == nullptr) {
    __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                        "vkHdrProbe instanceFunctions=missing");
    if (destroy_instance != nullptr) destroy_instance(instance, nullptr);
    dlclose(library);
    return;
  }
  VkAndroidSurfaceCreateInfoKHR surface_info = {
      VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR};
  surface_info.window = window;
  VkSurfaceKHR surface = VK_NULL_HANDLE;
  result = create_surface(instance, &surface_info, nullptr, &surface);
  if (result == VK_SUCCESS) {
    uint32_t device_count = 0;
    result = enumerate_devices(instance, &device_count, nullptr);
    std::vector<VkPhysicalDevice> devices(device_count);
    if (result == VK_SUCCESS && device_count > 0) {
      result = enumerate_devices(instance, &device_count, devices.data());
    }
    for (uint32_t i = 0; result == VK_SUCCESS && i < device_count; ++i) {
      uint32_t format_count = 0;
      VkResult format_result = get_formats(devices[i], surface, &format_count, nullptr);
      std::vector<VkSurfaceFormatKHR> formats(format_count);
      if (format_result == VK_SUCCESS && format_count > 0) {
        format_result = get_formats(devices[i], surface, &format_count,
                                    formats.data());
      }
      bool pq_10bit = false;
      bool hlg_10bit = false;
      bool pq_fp16 = false;
      for (uint32_t j = 0; j < format_count && format_result == VK_SUCCESS; ++j) {
        const auto& format = formats[j];
        __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                            "vkHdrProbe format device=%u index=%u format=%d colorspace=%d",
                            i, j, format.format, format.colorSpace);
        const bool ten_bit = format.format == VK_FORMAT_A2B10G10R10_UNORM_PACK32 ||
            format.format == VK_FORMAT_A2R10G10B10_UNORM_PACK32;
        pq_10bit |= ten_bit && format.colorSpace == VK_COLOR_SPACE_HDR10_ST2084_EXT;
        hlg_10bit |= ten_bit && format.colorSpace == VK_COLOR_SPACE_HDR10_HLG_EXT;
        pq_fp16 |= format.format == VK_FORMAT_R16G16B16A16_SFLOAT &&
            format.colorSpace == VK_COLOR_SPACE_HDR10_ST2084_EXT;
        if (format.colorSpace == VK_COLOR_SPACE_HDR10_ST2084_EXT ||
            format.colorSpace == VK_COLOR_SPACE_HDR10_HLG_EXT) {
          __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                              "vkHdrProbe hdrFormat device=%u format=%d colorspace=%d",
                              i, format.format, format.colorSpace);
        }
      }
      __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                          "vkHdrProbe surfaceFormats device=%u result=%d count=%u pq10=%d hlg10=%d pqFp16=%d",
                          i, format_result, format_count, pq_10bit, hlg_10bit,
                          pq_fp16);
    }
    destroy_surface(instance, surface, nullptr);
  }
  __android_log_print(ANDROID_LOG_INFO, "media_kit_vendor_ext",
                      "vkHdrProbe createSurfaceAndEnumerate=%d colorspaceExtension=%d",
                      result, has_colorspace);
  if (destroy_instance != nullptr) destroy_instance(instance, nullptr);
  dlclose(library);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_media_1kit_1test_LyaPqDataSpaceExt_nativeEglPqProbe(
    JNIEnv* env, jclass, jobject surface) {
  char enabled[PROP_VALUE_MAX] = {};
  if (__system_property_get("debug.media_kit.egl_hdr_probe", enabled) <= 0 ||
      std::strcmp(enabled, "1") != 0 || surface == nullptr) return;
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return;
  probe_egl_pq_window(window);
  ANativeWindow_release(window);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_media_1kit_1test_LyaPqDataSpaceExt_nativeVulkanHdrProbe(
    JNIEnv* env, jclass, jobject surface) {
  char enabled[PROP_VALUE_MAX] = {};
  if (__system_property_get("debug.media_kit.vk_hdr_probe", enabled) <= 0 ||
      std::strcmp(enabled, "1") != 0 || surface == nullptr) return;
  ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
  if (window == nullptr) return;
  probe_vulkan_hdr_window(window);
  ANativeWindow_release(window);
}
