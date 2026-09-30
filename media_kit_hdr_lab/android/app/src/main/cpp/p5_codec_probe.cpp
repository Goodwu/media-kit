#include <jni.h>
#include <android/hardware_buffer.h>
#include <android/hardware_buffer_jni.h>
#include <dlfcn.h>
#include <cstdint>
#include <iomanip>
#include <sstream>

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_media_1kit_1hdr_1lab_P5CodecProbe_inspectHardwareBuffer(
    JNIEnv* env, jclass, jobject java_buffer) {
  void* library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
  using FromJava = AHardwareBuffer* (*)(JNIEnv*, jobject);
  using Describe = void (*)(const AHardwareBuffer*, AHardwareBuffer_Desc*);
  using LockPlanes = int (*)(AHardwareBuffer*, uint64_t, int32_t,
                             const ARect*, AHardwareBuffer_Planes*);
  using Unlock = int (*)(AHardwareBuffer*, int32_t*);
  auto from_java = library == nullptr ? nullptr :
      reinterpret_cast<FromJava>(dlsym(library, "AHardwareBuffer_fromHardwareBuffer"));
  auto describe = library == nullptr ? nullptr :
      reinterpret_cast<Describe>(dlsym(library, "AHardwareBuffer_describe"));
  auto lock_planes = library == nullptr ? nullptr :
      reinterpret_cast<LockPlanes>(dlsym(library, "AHardwareBuffer_lockPlanes"));
  auto unlock = library == nullptr ? nullptr :
      reinterpret_cast<Unlock>(dlsym(library, "AHardwareBuffer_unlock"));
  if (from_java == nullptr || describe == nullptr || lock_planes == nullptr ||
      unlock == nullptr) {
    if (library != nullptr) dlclose(library);
    return env->NewStringUTF("hardware-buffer-symbol-missing");
  }
  AHardwareBuffer* buffer = from_java(env, java_buffer);
  if (buffer == nullptr) {
    dlclose(library);
    return env->NewStringUTF("null-buffer");
  }

  AHardwareBuffer_Desc desc{};
  describe(buffer, &desc);
  std::ostringstream out;
  out << "format=" << desc.format << " size=" << desc.width << "x"
      << desc.height << " stride=" << desc.stride << " layers=" << desc.layers
      << " usage=" << desc.usage;

  AHardwareBuffer_Planes planes{};
  const int status = lock_planes(
      buffer, AHARDWAREBUFFER_USAGE_CPU_READ_RARELY, -1, nullptr, &planes);
  out << " lockStatus=" << status << " planeCount=" << planes.planeCount;
  if (status == 0) {
    for (uint32_t index = 0; index < planes.planeCount; ++index) {
      const auto& plane = planes.planes[index];
      out << " plane" << index << "RowStride=" << plane.rowStride
          << " plane" << index << "PixelStride=" << plane.pixelStride
          << " plane" << index << "First16=";
      const auto* bytes = static_cast<const unsigned char*>(plane.data);
      if (bytes == nullptr) {
        out << "null";
      } else {
        for (int byte = 0; byte < 16; ++byte) {
          out << std::hex << std::setw(2) << std::setfill('0')
              << static_cast<unsigned>(bytes[byte]);
        }
        out << std::dec;
      }
    }
    // The vendor-private format reports zero row and pixel strides. There is
    // no documented address calculation for pixel samples; do not treat the
    // allocation stride as a linear 16-bit image stride.
    out << " unlockStatus=" << unlock(buffer, nullptr);
  }
  dlclose(library);
  return env->NewStringUTF(out.str().c_str());
}
