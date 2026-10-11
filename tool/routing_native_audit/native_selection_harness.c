/* Test-only JNI fixture. Includes the current production selection function.
 * This checks selection control flow, not Android configure or presentation. */
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct Object *jobject;
typedef jobject jobjectArray;
typedef int jmethodID;
typedef int jfieldID;
struct FakeJNI;
typedef const struct FakeJNI *JNIEnv;
struct FakeJNI {
    int (*CallStaticIntMethod)(JNIEnv *, jobject, jmethodID, ...);
    jobject (*CallStaticObjectMethod)(JNIEnv *, jobject, jmethodID, ...);
    jobject (*CallObjectMethod)(JNIEnv *, jobject, jmethodID, ...);
    int (*CallBooleanMethod)(JNIEnv *, jobject, jmethodID, ...);
    void (*DeleteLocalRef)(JNIEnv *, jobject);
    int (*GetArrayLength)(JNIEnv *, jobjectArray);
    jobject (*GetObjectArrayElement)(JNIEnv *, jobjectArray, int);
    jobject (*GetObjectField)(JNIEnv *, jobject, jfieldID);
    int (*GetIntField)(JNIEnv *, jobject, jfieldID);
};
struct Object {
    const char *text;
    int value, count, encoder, software;
    jobject elements[4];
    jobject types, capabilities, profiles, name;
};
struct JNIAMediaCodecListFields {
    jobject mediacodec_list_class;
    jmethodID get_codec_count_id, get_codec_info_at_id, get_supported_types_id;
    jmethodID is_encoder_id, is_software_only_id, get_name_id;
    jmethodID get_codec_capabilities_id;
    jfieldID profile_levels_id, profile_id;
};
struct JNIAMediaFormatFields { int unused; };
static const int jni_amediacodeclist_mapping[1] = {1};
static const int jni_amediaformat_mapping[1] = {2};
enum { COUNT=1, INFO, TYPES, ENCODER, SOFTWARE, NAME, CAPS, PROFILES, PROFILE };
static struct Object codec_list;
static int call_count(JNIEnv *e, jobject o, jmethodID m, ...) {
    (void)e; (void)o; assert(m == COUNT); return codec_list.count;
}
static jobject call_info(JNIEnv *e, jobject o, jmethodID m, ...) {
    (void)e; (void)o; assert(m == INFO);
    va_list a; va_start(a,m); int i=va_arg(a,int); va_end(a);
    assert(i>=0 && i<codec_list.count); return codec_list.elements[i];
}
static jobject call_object(JNIEnv *e, jobject o, jmethodID m, ...) {
    (void)e; assert(o);
    if (m==TYPES) return o->types;
    if (m==NAME) return o->name;
    if (m==CAPS) return o->capabilities;
    abort();
}
static int call_bool(JNIEnv *e, jobject o, jmethodID m, ...) {
    (void)e; assert(o);
    if (m==ENCODER) return o->encoder;
    if (m==SOFTWARE) return o->software;
    abort();
}
static void release_ref(JNIEnv *e, jobject o) { (void)e; (void)o; }
static int array_length(JNIEnv *e, jobject a) { (void)e; assert(a); return a->count; }
static jobject array_item(JNIEnv *e, jobject a, int i) {
    (void)e; assert(a && i>=0 && i<a->count); return a->elements[i];
}
static jobject object_field(JNIEnv *e, jobject o, jfieldID f) {
    (void)e; assert(o && f==PROFILES); return o->profiles;
}
static int int_field(JNIEnv *e, jobject o, jfieldID f) {
    (void)e; assert(o && f==PROFILE); return o->value;
}
static const struct FakeJNI jni_table = {
    call_count, call_info, call_object, call_bool, release_ref,
    array_length, array_item, object_field, int_field
};
static JNIEnv env_value = &jni_table;
#define JNI_GET_ENV_OR_RETURN(env, log_ctx, result) ((env) = &env_value)
static int ff_jni_init_jfields(JNIEnv *e, void *fields, const int *map, int flag, void *log) {
    (void)e; (void)flag; (void)log;
    if (map==jni_amediacodeclist_mapping) {
        struct JNIAMediaCodecListFields *f=fields;
        *f=(struct JNIAMediaCodecListFields){&codec_list,COUNT,INFO,TYPES,ENCODER,SOFTWARE,NAME,CAPS,PROFILES,PROFILE};
    }
    return 0;
}
static void ff_jni_reset_jfields(JNIEnv *e, void *f, const int *m, int flag, void *log) {
    (void)e; (void)f; (void)m; (void)flag; (void)log;
}
static int ff_jni_exception_check(JNIEnv *e, int flag, void *log) {
    (void)e; (void)flag; (void)log; return 0;
}
static char *ff_jni_jstring_to_utf_chars(JNIEnv *e, jobject o, void *log) {
    (void)e; (void)log; assert(o && o->text);
    size_t n=strlen(o->text)+1; char *p=malloc(n); assert(p); memcpy(p,o->text,n); return p;
}
static void av_freep(void *address) { void **p=address; free(*p); *p=NULL; }
#define av_strcasecmp strcasecmp
#include <selection.c.inc>

#define AV_LOG_INFO 0
#define av_log(...) ((void)0)
static int native_lookup_profile(int format_profile) {
    int profile;
#include <lookup.c.inc>
    return profile;
}
#undef av_log
struct Fixture {
    struct Object info, types, mime, caps, levels, level, name;
};
static void make_codec(struct Fixture *f, const char *name, const char *mime, int profile) {
    memset(f,0,sizeof(*f));
    f->mime.text=mime; f->name.text=name; f->level.value=profile;
    f->levels.count=profile<0?0:1; f->levels.elements[0]=&f->level;
    f->caps.profiles=&f->levels;
    f->types.count=1; f->types.elements[0]=&f->mime;
    f->info.types=&f->types; f->info.capabilities=&f->caps; f->info.name=&f->name;
}
static int check(const char *label, int profile, const char *expected) {
    char *actual=ff_AMediaCodecList_getCodecNameByType("video/dolby-vision",profile,0,NULL);
    int match=(actual && expected)?strcmp(actual,expected)==0:actual==NULL && expected==NULL;
    printf("%s profile=%d expected=%s actual=%s result=%s\n",label,profile,
           expected?expected:"none",actual?actual:"none",match?"PASS":"FAIL");
    free(actual); return !match;
}
int main(void) {
    struct Fixture a,b;
    make_codec(&a,"vendor.p5-only","video/dolby-vision",32);
    make_codec(&b,"vendor.p8-only","video/dolby-vision",256);
    codec_list.count=2; codec_list.elements[0]=&a.info; codec_list.elements[1]=&b.info;
    int controls=0;
    controls+=check("control-p5-profile",32,"vendor.p5-only");
    controls+=check("control-p8-profile",256,"vendor.p8-only");
    // This is the profile=-1 value used by the current native P8 caller.
    int counterexample=check("counterexample-current-p8-mime-only",native_lookup_profile(256),"vendor.p8-only");
    a.info.encoder=1;
    controls+=check("control-skip-encoder",-1,"vendor.p8-only");
    a.info.encoder=0; a.info.software=1;
    controls+=check("control-skip-software",-1,"vendor.p8-only");
    a.info.software=0; a.mime.text="video/hevc";
    controls+=check("control-skip-other-mime",-1,"vendor.p8-only");
    printf("controls_failed=%d counterexample_reproduced=%d\n",controls,counterexample);
    // A reproduced defect is a failing regression, not a successful suite.
    return controls || counterexample ? 1 : 0;
}
