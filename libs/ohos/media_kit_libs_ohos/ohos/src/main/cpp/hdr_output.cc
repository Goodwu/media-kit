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
  // RenderService only treats a native window as an HDR video surface after
  // it has an explicit video source and non-zero white-point references. The
  // values are normalized [0, 1] controls (they are not display nit values).
  const int32_t source_type = SourceTypeForWindow(reset);
  const float hdr_white_point = reset ? 0.0f : 1.0f;
  const float sdr_white_point = reset ? 0.0f : 0.2f;
  const int32_t source_type_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, SET_SOURCE_TYPE, source_type);
  const int32_t hdr_white_point_result =
      OH_NativeWindow_NativeWindowHandleOpt(
          window, SET_HDR_WHITE_POINT_BRIGHTNESS, hdr_white_point);
  const int32_t sdr_white_point_result =
      OH_NativeWindow_NativeWindowHandleOpt(
          window, SET_SDR_WHITE_POINT_BRIGHTNESS, sdr_white_point);
  const int32_t format_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, SET_FORMAT, format);
  int32_t actual_format = NATIVEBUFFER_PIXEL_FMT_BUTT;
  const int32_t format_get_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, GET_FORMAT, &actual_format);
  const int32_t gamut_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, SET_COLOR_GAMUT, gamut);

  // SET_COLOR_GAMUT selects the panel gamut, while the compositor's HDR
  // decision also consumes the explicit transfer-function metadata on the
  // native buffer. Set both so the HCPP surface is not treated as an SDR
  // 10-bit surface.
  int32_t metadata_type =
      reset ? OH_VIDEO_NONE
            : (transfer == kTransferHlg ? OH_VIDEO_HDR_HLG
                                         : OH_VIDEO_HDR_HDR10);
  const int32_t metadata_type_result = OH_NativeWindow_SetMetadataValue(
      window, OH_HDR_METADATA_TYPE, sizeof(metadata_type),
      reinterpret_cast<uint8_t*>(&metadata_type));
  const OH_NativeBuffer_ColorSpace color_space =
      reset ? OH_COLORSPACE_BT709_LIMIT
            : (transfer == kTransferHlg ? OH_COLORSPACE_BT2020_HLG_LIMIT
                                         : OH_COLORSPACE_BT2020_PQ_LIMIT);
  const int32_t color_space_result =
      OH_NativeWindow_SetColorSpace(window, color_space);

  int32_t actual_gamut = NATIVEBUFFER_COLOR_GAMUT_NATIVE;
  const int32_t get_result = OH_NativeWindow_NativeWindowHandleOpt(
      window, GET_COLOR_GAMUT, &actual_gamut);
  OH_NativeWindow_DestroyNativeWindow(window);

  if (source_type_result != 0 || hdr_white_point_result != 0 ||
      sdr_white_point_result != 0 || format_result != 0 ||
      format_get_result != 0 || gamut_result != 0 || get_result != 0 ||
      metadata_type_result != 0 || color_space_result != 0) {
    if (source_type_result != 0) return source_type_result;
    if (hdr_white_point_result != 0) return hdr_white_point_result;
    if (sdr_white_point_result != 0) return sdr_white_point_result;
    if (format_result != 0) return format_result;
    if (format_get_result != 0) return format_get_result;
    if (gamut_result != 0) return gamut_result;
    if (metadata_type_result != 0) return metadata_type_result;
    if (color_space_result != 0) return color_space_result;
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
  return ConfigureWindow(surface_id, kTransferPq, true);
}

extern "C" int32_t media_kit_ohos_hdr_prepare(uint64_t surface_id) {
  if (surface_id == 0) return -1;
  return ConfigureWindow(surface_id, kTransferPq, true);
}
