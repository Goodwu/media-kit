#include <jni.h>
#include <android/hardware_buffer.h>
#include <android/native_window_jni.h>
#include <media/NdkImageReader.h>
#include <dlfcn.h>
#include <atomic>

namespace {
AImageReader* reader = nullptr;
void* media_library = nullptr;
void* android_library = nullptr;
std::atomic<int> image_count{0};
std::atomic<int> acquire_errors{0};
std::atomic<int> notifications{0};
bool deferred_acquire = false;
bool hold_previous_image = false;
AImage* held_image = nullptr;
using AcquireImage = media_status_t (*)(AImageReader*, AImage**);
using DeleteImage = void (*)(AImage*);
using SetListener = media_status_t (*)(AImageReader*,
                                       AImageReader_ImageListener*);
using DeleteReader = void (*)(AImageReader*);
AcquireImage acquire_image = nullptr;
DeleteImage delete_image = nullptr;
SetListener set_listener = nullptr;
DeleteReader delete_reader = nullptr;

void on_image(void*, AImageReader* source) {
  notifications.fetch_add(1);
  if (deferred_acquire) return;
  AImage* image = nullptr;
  const media_status_t status = acquire_image(source, &image);
  if (status == AMEDIA_OK && image != nullptr) {
    image_count.fetch_add(1);
    delete_image(image);
  } else {
    acquire_errors.fetch_add(1);
  }
}

void close_reader() {
  if (held_image != nullptr && delete_image != nullptr) {
    delete_image(held_image);
    held_image = nullptr;
  }
  if (reader != nullptr) {
    set_listener(reader, nullptr);
    delete_reader(reader);
    reader = nullptr;
  }
  if (media_library != nullptr) dlclose(media_library);
  if (android_library != nullptr) dlclose(android_library);
  media_library = nullptr;
  android_library = nullptr;
  acquire_image = nullptr;
  delete_image = nullptr;
  set_listener = nullptr;
  delete_reader = nullptr;
}
}  // namespace

extern "C" JNIEXPORT jobject JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_createNativeReader(
    JNIEnv* env, jclass, jint width, jint height, jint max_images,
    jboolean deferred, jboolean hold_previous) {
  close_reader();
  image_count.store(0);
  acquire_errors.store(0);
  notifications.store(0);
  deferred_acquire = deferred;
  hold_previous_image = hold_previous;
  media_library = dlopen("libmediandk.so", RTLD_NOW | RTLD_LOCAL);
  android_library = dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL);
  using NewReader = media_status_t (*)(int32_t, int32_t, int32_t, uint64_t,
                                       int32_t, AImageReader**);
  using GetWindow = media_status_t (*)(AImageReader*, ANativeWindow**);
  using ToSurface = jobject (*)(JNIEnv*, ANativeWindow*);
  auto symbol = [](void* library, const char* name) {
    return library == nullptr ? nullptr : dlsym(library, name);
  };
  auto new_reader = reinterpret_cast<NewReader>(
      symbol(media_library, "AImageReader_newWithUsage"));
  auto get_window = reinterpret_cast<GetWindow>(
      symbol(media_library, "AImageReader_getWindow"));
  acquire_image = reinterpret_cast<AcquireImage>(
      symbol(media_library, "AImageReader_acquireLatestImage"));
  delete_image = reinterpret_cast<DeleteImage>(
      symbol(media_library, "AImage_delete"));
  set_listener = reinterpret_cast<SetListener>(
      symbol(media_library, "AImageReader_setImageListener"));
  delete_reader = reinterpret_cast<DeleteReader>(
      symbol(media_library, "AImageReader_delete"));
  auto to_surface = reinterpret_cast<ToSurface>(
      symbol(android_library, "ANativeWindow_toSurface"));
  if (new_reader == nullptr || get_window == nullptr ||
      acquire_image == nullptr || delete_image == nullptr ||
      set_listener == nullptr || delete_reader == nullptr ||
      to_surface == nullptr) {
    close_reader();
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
                  "native-reader-symbol-missing");
    return nullptr;
  }
  const media_status_t created = new_reader(
      width, height, AIMAGE_FORMAT_PRIVATE,
      AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE, max_images, &reader);
  if (created != AMEDIA_OK || reader == nullptr) {
    close_reader();
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
                  "native-reader-create-failed");
    return nullptr;
  }
  AImageReader_ImageListener listener{};
  listener.onImageAvailable = on_image;
  if (set_listener(reader, &listener) != AMEDIA_OK) {
    close_reader();
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
                  "native-reader-listener-failed");
    return nullptr;
  }
  ANativeWindow* window = nullptr;
  if (get_window(reader, &window) != AMEDIA_OK || window == nullptr) {
    close_reader();
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
                  "native-reader-window-failed");
    return nullptr;
  }
  return to_surface(env, window);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_nativeReaderImageCount(
    JNIEnv*, jclass) {
  return image_count.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_nativeReaderAcquireErrors(
    JNIEnv*, jclass) {
  return acquire_errors.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_nativeReaderNotifications(
    JNIEnv*, jclass) {
  return notifications.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_pollNativeReaderImage(
    JNIEnv*, jclass) {
  if (reader == nullptr || acquire_image == nullptr) return -1;
  if (held_image != nullptr) {
    delete_image(held_image);
    held_image = nullptr;
  }
  AImage* image = nullptr;
  const media_status_t status = acquire_image(reader, &image);
  if (status == AMEDIA_OK && image != nullptr) {
    image_count.fetch_add(1);
    if (hold_previous_image) {
      held_image = image;
    } else {
      delete_image(image);
    }
  } else if (status != AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE) {
    acquire_errors.fetch_add(1);
  }
  return status;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_media_1kit_1test_P5CodecProbe_closeNativeReader(
    JNIEnv*, jclass) {
  close_reader();
}
