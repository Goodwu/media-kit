#include "DoViBaker.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

extern "C" const char* AvisynthPluginInit3(IScriptEnvironment*, const AVS_Linkage*);

class RawP5Frame final : public IClip {
    VideoInfo vi{};
    std::vector<unsigned char> raw;
public:
    explicit RawP5Frame(const char* path) {
        vi.width = 3840; vi.height = 2160; vi.fps_numerator = 24; vi.fps_denominator = 1;
        vi.num_frames = 6314; vi.pixel_type = VideoInfo::CS_YUV420P10;
        std::ifstream in(path, std::ios::binary);
        if (!in) throw std::runtime_error("raw input open failed");
        raw.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
        if (raw.size() != 24883200) throw std::runtime_error("raw input size mismatch");
    }
    PVideoFrame __stdcall GetFrame(int, IScriptEnvironment* env) override {
        PVideoFrame f = env->NewVideoFrame(vi);
        const size_t ybytes = 3840ULL * 2160 * 2;
        const unsigned char* ptrs[3] = {raw.data(), raw.data() + ybytes, raw.data() + ybytes + ybytes/4};
        const int planes[3] = {PLANAR_Y, PLANAR_U, PLANAR_V};
        for (int c=0;c<3;c++) {
            const int width = c ? 1920 : 3840, height = c ? 1080 : 2160;
            unsigned char* dst = f->GetWritePtr(planes[c]);
            int pitch = f->GetPitch(planes[c]);
            for (int y=0;y<height;y++) std::memcpy(dst+y*pitch, ptrs[c]+y*width*2, width*2);
        }
        return f;
    }
    void __stdcall GetAudio(void*, int64_t, int64_t, IScriptEnvironment*) override {}
    const VideoInfo& __stdcall GetVideoInfo() override { return vi; }
    bool __stdcall GetParity(int) override { return false; }
    int __stdcall SetCacheHints(int, int) override { return 0; }
};

int main(int argc, char** argv) {
    if (argc != 5) { std::fprintf(stderr,"usage: %s raw.yuv rpu.bin frame output.rgb48le\n",argv[0]); return 2; }
    IScriptEnvironment* env = nullptr;
    try {
        env = CreateScriptEnvironment(AVISYNTH_INTERFACE_VERSION);
        if (!env) throw std::runtime_error("CreateScriptEnvironment failed");
        AvisynthPluginInit3(env, env->GetAVSLinkage());
        PClip source = new RawP5Frame(argv[1]);
        PClip baker = new DoViBaker<false>(source, PClip(), argv[2], true, true, 0, 0.0f, 1000.0f, false, false, false, env);
        int n = std::atoi(argv[3]);
        PVideoFrame f = baker->GetFrame(n, env);
        std::FILE* out = std::fopen(argv[4],"wb");
        if (!out) throw std::runtime_error("output open failed");
        const uint16_t* row[3]; int pitch[3]; int planes[3]={PLANAR_R,PLANAR_G,PLANAR_B};
        for (int c=0;c<3;c++) { row[c]=(const uint16_t*)f->GetReadPtr(planes[c]); pitch[c]=f->GetPitch(planes[c])/2; }
        std::vector<uint16_t> line(3840*3);
        for (int y=0;y<2160;y++) {
            for (int x=0;x<3840;x++) for (int c=0;c<3;c++) line[x*3+c]=row[c][x];
            if (std::fwrite(line.data(),2,line.size(),out)!=line.size()) throw std::runtime_error("write failed");
            for (int c=0;c<3;c++) row[c]+=pitch[c];
        }
        std::fclose(out);
        std::fprintf(stderr,"wrote frame %d RGB48\n",n);
        f = PVideoFrame(); baker = PClip(); source = PClip();
        env->DeleteScriptEnvironment();
    } catch (const AvisynthError& e) { std::fprintf(stderr,"AviSynth: %s\n",e.msg); return 1; }
      catch (const std::exception& e) { std::fprintf(stderr,"error: %s\n",e.what()); return 1; }
    return 0;
}
