#include <cstdint>

#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>

namespace {

constexpr int32_t kTransferPq = 0;
constexpr int32_t kTransferHlg = 1;

int32_t PixelFormatForTransfer(int32_t transfer, bool reset) {
  // Keep SDR on the format Flutter's external texture path accepts on all
  // devices.  Use a 10-bit RGBA buffer for PQ/HLG so HDR is not quantized to
  // 8-bit before it reaches the native window.
  return reset ? NATIVEBUFFER_PIXEL_FMT_RGBA_8888
               : NATIVEBUFFER_PIXEL_FMT_RGBA_1010102;
}

int32_t ColorGamutForTransfer(int32_t transfer) {
  return transfer == kTransferHlg ? NATIVEBUFFER_COLOR_GAMUT_BT2100_HLG
                                  : NATIVEBUFFER_COLOR_GAMUT_BT2100_PQ;
}

int32_t SourceTypeForWindow(bool reset) {
  return reset ? OH_SURFACE_SOURCE_UI : OH_SURFACE_SOURCE_VIDEO;
}

int32_t ConfigureWindow(uint64_t surface_id, int32_t transfer, bool reset) {
  OHNativeWindow* window = nullptr;
  const int32_t create_result =
      OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface_id, &window);
  if (create_result != 0 || window == nullptr) {
    return create_result != 0 ? create_result : -1;
  }

  const int32_t gamut = reset ? NATIVEBUFFER_COLOR_GAMUT_STANDARD_BT709
                              : ColorGamutForTransfer(transfer);
  const int32_t format = PixelFormatForTransfer(transfer, reset);
  // This function is the stopped-VO initialization boundary. It owns only
  // static producer state; the VO owns dynamic color and white-point writes.
  const int32_t source_type = SourceTypeForWindow(reset);
  const int32_t source_type_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, SET_SOURCE_TYPE, source_type);
  const int32_t format_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, SET_FORMAT, format);
  int32_t actual_format = NATIVEBUFFER_PIXEL_FMT_BUTT;
  const int32_t format_get_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, GET_FORMAT, &actual_format);
  const int32_t gamut_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, SET_COLOR_GAMUT, gamut);

  // Dynamic color space, metadata, and white point are owned exclusively by
  // mpv's OHOS VO. Reset only prepares the producer; the VO writes the SDR
  // state on the next rendered frame.

  // There is no portable "native" sentinel across OHOS SDK versions.
  int32_t actual_gamut = -1;
  const int32_t get_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, GET_COLOR_GAMUT, &actual_gamut);
  OH_NativeWindow_DestroyNativeWindow(window);

  if (source_type_result != 0 || format_result != 0 ||
      format_get_result != 0 || gamut_result != 0 || get_result != 0) {
    if (source_type_result != 0) return source_type_result;
    if (format_result != 0) return format_result;
    if (format_get_result != 0) return format_get_result;
    if (gamut_result != 0) return gamut_result;
    return get_result;
  }
  if (actual_format != format) return -2;
  return actual_gamut == gamut ? 0 : -3;
}

}  // namespace

extern "C" int32_t media_kit_ohos_hdr_configure(uint64_t surface_id,
                                                  int32_t transfer) {
  if (surface_id == 0) return -1;
  return ConfigureWindow(surface_id, transfer, false);
}

extern "C" int32_t media_kit_ohos_hdr_reset(uint64_t surface_id) {
  if (surface_id == 0) return -1;
  // 0 means static source/format/gamut setup succeeded. Dynamic SDR color
  // space, metadata, and white point are restored by the VO on its next
  // frame, not by this FFI call.
  return ConfigureWindow(surface_id, kTransferPq, true);
}

extern "C" int32_t media_kit_ohos_hdr_prepare(uint64_t surface_id) {
  if (surface_id == 0) return -1;
  return ConfigureWindow(surface_id, kTransferPq, true);
}
