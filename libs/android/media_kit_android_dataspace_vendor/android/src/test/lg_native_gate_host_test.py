"""Compile the actual LG gate/JNI path with recording host dependencies."""
import pathlib
import subprocess
import tempfile

cpp = pathlib.Path(__file__).resolve().parents[1] / 'main/cpp'
# A4 module split: the LG adapter implementation (gates, arm state, exports)
# lives in lg_fw_adapter.cpp and the JNI registrations (delegating entries)
# in dataspace_apply.cpp; both are extracted in source order so the harness
# compiles the same gated path as the on-device .so.
adapter = (cpp / 'lg_fw_adapter.cpp').read_text()
plugin = (cpp / 'dataspace_apply.cpp').read_text()
actual = adapter[adapter.index('// Local logcat only:'):]
actual += plugin[plugin.index('// LG JNI registrations (A4 module split):'):]
stubs = r'''
#include <cassert>
#include <cstdint>
#include <cstring>
#include <vector>
#include <cstdarg>
#include <cstdio>
#define __aarch64__ 1
#define JNIEXPORT
#define JNICALL
#define JNI_TRUE 1
#define JNI_FALSE 0
#define ANDROID_LOG_INFO 4
#define ANDROID_LOG_WARN 5
#define PROP_VALUE_MAX 256
#define AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM 43
using jobject=void*;using jclass=void*;using jint=int;using jboolean=int;using jlong=long long;
using jlongArray=void*;using jsize=int;
struct JNIEnv {
 jlongArray NewLongArray(jsize){return (jlongArray)1;}
 void SetLongArrayRegion(jlongArray,jsize,jsize,const jlong*){}
};
struct ANativeWindow {};
using EGLint=int;using EGLDisplay=void*;using EGLConfig=void*;
constexpr int EGL_DEFAULT_DISPLAY=0,EGL_NATIVE_VISUAL_ID=0,EGL_RED_SIZE=1,EGL_GREEN_SIZE=2,EGL_BLUE_SIZE=3,EGL_ALPHA_SIZE=4,EGL_SURFACE_TYPE=5,EGL_RENDERABLE_TYPE=6,EGL_CONFIG_CAVEAT=7,EGL_CONFIG_ID=8,EGL_COLOR_BUFFER_TYPE=9,EGL_WINDOW_BIT=4,EGL_OPENGL_ES2_BIT=4,EGL_NON_CONFORMANT_CONFIG=0x3051;
#define EGL_NO_DISPLAY nullptr
struct Dl_info {void* dli_fbase;const char* dli_fname;};
ANativeWindow window;
int fmt=278, queryFmt=278, qret=0, pret=0, queryCalls=0, performCalls=0;
bool device=true, hook=true, noDisplay=false, enumFail=false, secondEnumFail=false, attrFail=false;
int count=1, actualCount=1, hookMode=0, propertyMode=0, attrFailAt=-1;
// Indices 0-8 serve the visual278 match; index 9 is EGL_COLOR_BUFFER_TYPE
// for the yuv-config49 capability (the source itself defines
// EGL_YUV_BUFFER_EXT = 0x3300, the value index 9 carries).
int attrs[10]={278,10,10,10,2,4,0x44,0x3051,61,0x3300};
int __android_log_print(int,const char*,const char*,...){return 0;}
int __system_property_get(const char* key,char* out){
 const char* v=strcmp(key,"ro.product.model")==0?"LG-H870DS":strcmp(key,"ro.build.version.sdk")==0?"24":"lge/lucye_global_com/lucye:7.0/NRD90U/172921900e77a:user/release-keys";
 int which=strcmp(key,"ro.product.model")==0?1:strcmp(key,"ro.build.version.sdk")==0?2:3;
 if(propertyMode==which)return 0;
 strcpy(out,device&&propertyMode!=which+3?v:"wrong");return strlen(out);
}
int ANativeWindow_getFormat(ANativeWindow*){return fmt;}
ANativeWindow* ANativeWindow_fromSurface(JNIEnv*,jobject s){return s?&window:nullptr;}
void ANativeWindow_release(ANativeWindow*){}
EGLDisplay eglGetDisplay(int){return noDisplay?nullptr:(void*)1;}
bool eglGetConfigs(EGLDisplay,EGLConfig* out,int,int* n){if(!out){*n=count;return !enumFail;}*n=actualCount;if(actualCount>0)out[0]=(void*)1;return !secondEnumFail;}
bool eglGetConfigAttrib(EGLDisplay,EGLConfig,int a,int* v){*v=attrs[a];return !attrFail&&a!=attrFailAt;}
int dladdr(void* address,Dl_info* i){bool perform=(uintptr_t)address==0x7100000018ULL;
 if(hookMode==1||hookMode==2&&perform)return 0;
 i->dli_fbase=(void*)(uintptr_t)(hookMode==3&&perform?2:1);
 i->dli_fname=hookMode==4?nullptr:hook?"/system/lib64/libgui.so":"wrong";return 1;}
// Actual code retains its firmware address-plausibility test. Provide
// synthetic evidenced addresses and intercept indirect calls ONLY in harness.
int queryStub(const ANativeWindow*,int,int* f){queryCalls++;*f=queryFmt;return qret;}
int performStub(ANativeWindow*,int,...){performCalls++;return pret;}
namespace std { void host_memcpy(void* dst,const void* src,size_t n){
 const auto offset=(const uint8_t*)src-(const uint8_t*)&window;
 if(offset==0x90||offset==0x98){void* p=hookMode==5?nullptr:(void*)(0x7100000000ULL+(offset==0x98?(hookMode==6?0x20:0x18):0));::memcpy(dst,&p,n);}else ::memcpy(dst,src,n);
} }
'''
# Preserve the real branch/gate control flow; replace only dependency reads and
# indirect machine addresses (which cannot be called in a host process).
actual = actual.replace('std::memcpy(', 'std::host_memcpy(')
actual = actual.replace('reinterpret_cast<QueryFn>(queryPtr)', 'queryStub')
actual = actual.replace('reinterpret_cast<PerformFn>(performPtr)', 'performStub')
tests = r'''
void reset(){fmt=queryFmt=278;qret=pret=queryCalls=performCalls=0;device=hook=true;noDisplay=enumFail=secondEnumFail=attrFail=false;count=actualCount=1;hookMode=propertyMode=0;attrFailAt=-1;int good[]={278,10,10,10,2,4,0x44,0x3051,61,0x3300};memcpy(attrs,good,sizeof(attrs));}
int apply(bool enabled=true,int ds=0x11c60000){return Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeApplyPqDataSpace(nullptr,nullptr,(void*)1,ds,enabled);}
void denied(){assert(!apply());assert(performCalls==0);}
int main(){
 reset();assert(apply());assert(queryCalls==1&&performCalls==1);
 reset();assert(!apply(false));assert(queryCalls==0&&performCalls==0);
 reset();fmt=queryFmt=43;assert(apply(false));assert(performCalls==1);
 reset();noDisplay=true;denied();reset();enumFail=true;denied();reset();secondEnumFail=true;denied();
 for(int n:{0,-1,1025}){reset();count=n;denied();}
 for(int n:{0,-1,2}){reset();actualCount=n;denied();}
 reset();attrFail=true;denied();
 for(int a=0;a<8;a++){reset();attrs[a]=0;denied();}
 reset();attrs[6]=4;denied();reset();attrs[6]=0x40;denied();
 reset();queryFmt=43;denied();assert(queryCalls==1);
 reset();qret=-1;denied();reset();device=false;denied();assert(queryCalls==0);
 reset();hook=false;denied();assert(queryCalls==0);
 reset();assert(!apply(true,0));assert(performCalls==0);
 reset();fmt=999;denied();reset();pret=-1;assert(!apply());assert(performCalls==1);
 for(int mode=1;mode<=6;mode++){reset();propertyMode=mode;denied();assert(queryCalls==0);}
 for(int mode=1;mode<=6;mode++){reset();hookMode=mode;denied();assert(queryCalls==0);}
 for(int a=0;a<9;a++){reset();attrFailAt=a;denied();}
 // c1-owner bound arm: the config49 NV12 window is admitted end-to-end and
 // refused again after the disarm (flag + format record + binding cleared).
 // reset() pins the visual278 fixture, so the NV12 cases manage the format
 // attrs themselves and zero the call counters around each apply.
 auto nv12=[&]{reset();fmt=queryFmt=0x7FA30C04;attrs[0]=0x7FA30C04;};
 // visual278 experiment off: only the yuv-diag branch could admit the NV12
 // format, so a refusal here proves the disarm reached the gate.
 auto deniedNV12=[&]{nv12();assert(!apply(false));assert(performCalls==0);};
 nv12();mkvendor_arm_yuv_diag(0xABCDEFULL,42);
 assert(apply(true,0x11c60000));assert(performCalls==1);
 mkvendor_disarm_yuv_diag();
 deniedNV12();
 // Disarm is idempotent.
 mkvendor_disarm_yuv_diag();assert(mkvendor_yuv_diag_enabled()==0);
 // Legacy setter arms the same flag unbound; the window gate is identical.
 mkvendor_set_yuv_diag_enabled(1);
 assert(mkvendor_yuv_diag_enabled()==1);
 nv12();assert(apply(true,0x11c60000));assert(performCalls==1);
 mkvendor_disarm_yuv_diag();
 assert(mkvendor_yuv_diag_enabled()==0);
 deniedNV12();
 // Armed but the public-EGL config49 capability missing: still refused.
 // Inline (not deniedNV12): the fixture reset inside it would restore the
 // capability attrs.
 nv12();attrs[9]=0;mkvendor_arm_yuv_diag(1,1);
 assert(!apply(false));assert(performCalls==0);
 mkvendor_disarm_yuv_diag();deniedNV12();
 // P8.4 A5 V2 review fix: the read-only binding snapshot drives the Java
 // authorization-termination rule (revoke/clear/unregister must disarm a
 // matching arm). Armed bound -> binding visible; legacy arm -> 0/0;
 // disarmed -> null (host JNIEnv shims NewLongArray to non-null, so a
 // disarmed state is the only way to observe the null return here).
 uint64_t bk=0;uint32_t bg=0;
 assert(mkvendor_yuv_diag_binding(&bk,&bg)==0);
 mkvendor_arm_yuv_diag(0xABCDEFULL,42);
 assert(mkvendor_yuv_diag_binding(&bk,&bg)==1);assert(bk==0xABCDEFULL&&bg==42);
 mkvendor_set_yuv_diag_enabled(1);
 assert(mkvendor_yuv_diag_binding(&bk,&bg)==1);assert(bk==0&&bg==0);
 assert(Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeYuvDiagBinding(nullptr,nullptr)!=(jlongArray)0);
 mkvendor_disarm_yuv_diag();
 assert(mkvendor_yuv_diag_binding(&bk,&bg)==0);
 assert(Java_com_alexmercerind_media_1kit_1android_1dataspace_1vendor_LgPqDataSpaceExt_nativeYuvDiagBinding(nullptr,nullptr)==(jlongArray)0);
 deniedNV12();
 puts("actual LG JNI/gate path: positive/default43, EGL/device/hook/query refusal, yuv-diag bound arm/disarm/binding cases passed");
}
'''
with tempfile.TemporaryDirectory(prefix='lg-native-gate-') as tmp:
    cpp = pathlib.Path(tmp)/'test.cpp'
    cpp.write_text(stubs+actual+tests)
    exe = pathlib.Path(tmp)/'test'
    subprocess.run(['clang++','-std=c++17',str(cpp),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
