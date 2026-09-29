#include <sstream>

#include "def.h"
#include "DoViBaker.h"
#include "DoViCubes.h"
#include "DoViTonemap.h"
#include "DoViStatsFileLoader.h"

AVSValue __cdecl Create_RealDoViBaker(
  PClip blclip,
  PClip elclip,
  const char* rpuPath,
  uint16_t desiredTrimPq,
  float targetMaxNits,
  float targetMinNits,
  bool qnd,
  bool rgbProof,
  bool nlqProof,
  const AVSValue* args, 
  IScriptEnvironment* env)
{
  if (!blclip->GetVideoInfo().HasVideo() || (elclip && !elclip->GetVideoInfo().HasVideo())) {
    env->ThrowError("DoViBaker: Clip not available");
  }

  if (!blclip->GetVideoInfo().IsYUV() || (elclip && !elclip->GetVideoInfo().IsYUV())) {
    env->ThrowError("DoViBaker: Clip must be in YUV format");
  }

  int blClipChromaSubSampled = -1;
  if (blclip->GetVideoInfo().Is420()) {
    blClipChromaSubSampled = 1;
  }
  if (blclip->GetVideoInfo().Is444()) {
    blClipChromaSubSampled = 0;
  }
  if (blClipChromaSubSampled < 0) {
    env->ThrowError("DoViBaker: Only 444 and 420 subsampling allowed");
  }

  int elClipChromaSubSampled = blClipChromaSubSampled;
  if (elclip) {
    elClipChromaSubSampled = -1;
    if (elclip && elclip->GetVideoInfo().Is420()) {
      elClipChromaSubSampled = 1;
    }
    if (elclip && elclip->GetVideoInfo().Is444()) {
      elClipChromaSubSampled = 0;
    }
    if (elclip && elClipChromaSubSampled < 0) {
      env->ThrowError("DoViBaker: Only 444 and 420 subsampling allowed");
    }
  }

  int quarterResolutionEl = 0;
  if (elclip) {
    quarterResolutionEl = -1;
    if ((blclip->GetVideoInfo().width == elclip->GetVideoInfo().width) && (blclip->GetVideoInfo().height == elclip->GetVideoInfo().height)) {
      quarterResolutionEl = 0;
    }
    if ((blclip->GetVideoInfo().width == 2 * elclip->GetVideoInfo().width) && (blclip->GetVideoInfo().height == 2 * elclip->GetVideoInfo().height)) {
      quarterResolutionEl = 1;
    }
    if (quarterResolutionEl < 0) {
      env->ThrowError("DoViBaker: Enhancement Layer must either be same size or quarter size as Base Layer");
    }
  }
  
  if (quarterResolutionEl == 0) {
    return new DoViBaker<false>(blclip, elclip, rpuPath, blClipChromaSubSampled, elClipChromaSubSampled, desiredTrimPq, targetMinNits, targetMaxNits, qnd, rgbProof, nlqProof, env);
  }
  if (quarterResolutionEl == 1) {
    return new DoViBaker<true>(blclip, elclip, rpuPath, blClipChromaSubSampled, elClipChromaSubSampled, desiredTrimPq, targetMinNits, targetMaxNits, qnd, rgbProof, nlqProof, env);
  }
}

AVSValue __cdecl Create_DoViBaker(AVSValue args, void* user_data, IScriptEnvironment* env)
{
  auto elClip = (args[1].Defined() ? args[1].AsClip() : nullptr);

  return Create_RealDoViBaker(
    args[0].AsClip(), 
    elClip, 
    args[2].AsString(""),
    args[3].AsInt(0),
    args[4].AsFloat(100),
    args[5].AsFloat(0),
    args[6].AsBool(false),
    args[7].AsBool(false),
    args[8].AsBool(false),
    &args, env);
}

const AVS_Linkage *AVS_linkage = nullptr;
extern "C" const char* AvisynthPluginInit3(IScriptEnvironment* env, const AVS_Linkage* const vectors) {
 AVS_linkage = vectors;
 env->AddFunction("DoViBaker", "c[el]c[rpu]s[trimPq]i[targetMaxNits]f[targetMinNits]f[qnd]b[rgbProof]b[nlqProof]b", Create_DoViBaker, 0);
 return "DoViBaker P5 reference";
}
void ypp2ycc(uint16_t* ycc, float y, float u, float v) {
  //YPrPb to YCrCb
  static const uint32_t scale = 1 << DoViProcessor::outContainerBitDepth;
  static const uint32_t bias = 16 << (DoViProcessor::outContainerBitDepth - 8);
  static const uint32_t ltop = scale - (21 << (DoViProcessor::outContainerBitDepth - 8));
  static const uint32_t ctop = scale - (16 << (DoViProcessor::outContainerBitDepth - 8));

  ycc[0] = y * (ltop - bias) + bias;
  ycc[1] = (u + 0.5) * (ctop - bias) + bias;
  ycc[2] = (v + 0.5) * (ctop - bias) + bias;
}

inline uint16_t to8bits(uint16_t sample) {
  // we just check for 8bit precicion deviations, assuming smaller differences to be not visible
  return (sample >> (DoViProcessor::outContainerBitDepth - 8));
}

bool checkElProcessing(const DoViProcessor &dovi) {
  uint16_t yuv[3];
  ypp2ycc(yuv, 0.5000, 0.0000, 0.0000);
  uint16_t inGrey = yuv[0];
  ypp2ycc(yuv, 1.0000, 0.0000, 0.0000);
  uint16_t elHi = yuv[0];
  ypp2ycc(yuv, 0.0000, 0.0000, 0.0000);
  uint16_t elLo = yuv[0];
  uint16_t outHi = dovi.processSampleY(inGrey, elHi);
  uint16_t outLo = dovi.processSampleY(inGrey, elLo);
  return outHi != outLo;
}

uint16_t checkMatrix(const DoViProcessor& dovi) {
  uint16_t yuv[3];
  uint16_t rgb[3];
  uint16_t diffBits = 0;

  static const uint16_t maxNormRGB = 255 << (DoViProcessor::outContainerBitDepth - 8);
  static const uint16_t halfNormRGB = maxNormRGB >> 1;

  ypp2ycc(yuv, 1.0000, 0.0000, 0.0000); // 10000nits white
  dovi.sample2rgb(rgb[0], rgb[1], rgb[2], yuv[0], yuv[1], yuv[2]);
  diffBits |= std::abs(rgb[0] - maxNormRGB);
  diffBits |= std::abs(rgb[1] - maxNormRGB);
  diffBits |= std::abs(rgb[2] - maxNormRGB);
    
  ypp2ycc(yuv, 0.0000, 0.0000, 0.0000); // black
  dovi.sample2rgb(rgb[0], rgb[1], rgb[2], yuv[0], yuv[1], yuv[2]);
  diffBits |= rgb[0];
  diffBits |= rgb[1];
  diffBits |= rgb[2];

  ypp2ycc(yuv, 0.5000, 0.0000, 0.0000); // 92nits white
  dovi.sample2rgb(rgb[0], rgb[1], rgb[2], yuv[0], yuv[1], yuv[2]);
  diffBits |= std::abs(rgb[0] - halfNormRGB);
  diffBits |= std::abs(rgb[1] - halfNormRGB);
  diffBits |= std::abs(rgb[2] - halfNormRGB);

  ypp2ycc(yuv, 0.2627 / 2, -0.1396 / 2, 0.5000 / 2); // half intensity red
  dovi.sample2rgb(rgb[0], rgb[1], rgb[2], yuv[0], yuv[1], yuv[2]);
  diffBits |= std::abs(rgb[0] - halfNormRGB);
  diffBits |= rgb[1];
  diffBits |= rgb[2];

  ypp2ycc(yuv, 0.6780 / 2, -0.3604 / 2, -0.4598 / 2); // half intensity blue
  dovi.sample2rgb(rgb[0], rgb[1], rgb[2], yuv[0], yuv[1], yuv[2]);
  diffBits |= rgb[0];
  diffBits |= std::abs(rgb[1] - halfNormRGB);
  diffBits |= rgb[2];
  
  ypp2ycc(yuv, 0.0593 / 2, 0.5000 / 2, -0.0402 / 2); // half intensity green
  dovi.sample2rgb(rgb[0], rgb[1], rgb[2], yuv[0], yuv[1], yuv[2]);
  diffBits |= rgb[0];
  diffBits |= rgb[1];
  diffBits |= std::abs(rgb[2] - halfNormRGB);

  return diffBits;
}

uint16_t checkNonIdentityMapping(const DoViProcessor& dovi) {
  uint16_t yuv[3];
  uint16_t ely = dovi.getNlqOffset(0);
  uint16_t diffBits = 0;
  for (int i = 0; i <= 10; i++) {
    ypp2ycc(yuv, float(i) / 10.0, 0.0000, 0.0000);
    uint16_t bly = yuv[0];
    int y = dovi.processSampleY(bly, ely);
    diffBits |= std::abs(y - bly);
  }
  return diffBits;
}

double Spline16Filter(double value) {
  value = fabs(value);

  if (value < 1.0) {
    return ((value - 9.0 / 5.0) * value - 1.0 / 5.0) * value + 1.0;
  }
  else if (value < 2.0) {
    return ((-1.0 / 3.0 * (value - 1.0) + 4.0 / 5.0) * (value - 1.0) - 7.0 / 15.0) * (value - 1.0);
  }
  return 0.0;
}

double Spline36Filter(double value) {
  value = fabs(value);

  if (value < 1.0) {
    return ((13.0 / 11.0 * (value)-453.0 / 209.0) * (value)-3.0 / 209.0) * (value)+1.0;
  }
  else if (value < 2.0) {
    return ((-6.0 / 11.0 * (value - 1.0) + 270.0 / 209.0) * (value - 1.0) - 156.0 / 209.0) * (value - 1.0);
  }
  else if (value < 3.0) {
    return  ((1.0 / 11.0 * (value - 2.0) - 45.0 / 209.0) * (value - 2.0) + 26.0 / 209.0) * (value - 2.0);
  }
  return 0.0;
}

double Spline64Filter(double value) {
  value = fabs(value);

  if (value < 1.0) {
    return ((49.0 / 41.0 * (value)-6387.0 / 2911.0) * (value)-3.0 / 2911.0) * (value)+1.0;
  }
  else if (value < 2.0) {
    return ((-24.0 / 41.0 * (value - 1.0) + 4032.0 / 2911.0) * (value - 1.0) - 2328.0 / 2911.0) * (value - 1.0);
  }
  else if (value < 3.0) {
    return ((6.0 / 41.0 * (value - 2.0) - 1008.0 / 2911.0) * (value - 2.0) + 582.0 / 2911.0) * (value - 2.0);
  }
  else if (value < 4.0) {
    return ((-1.0 / 41.0 * (value - 3.0) + 168.0 / 2911.0) * (value - 3.0) - 97.0 / 2911.0) * (value - 3.0);
  }
  return 0.0;
}

