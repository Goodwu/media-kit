"""Exercise real FBO getter/copy functions with host GL doubles; no GPU proof."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def function(path, name):
    text = path.read_text()
    pos = text.index(name + '(')
    start = text.rfind('\n', 0, pos) + 1
    brace = text.index('{', pos)
    depth, end = 1, brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


STUBS = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <math.h>
#define MP_ERR(...) ((void)0)
typedef unsigned GLuint;
typedef unsigned GLenum;
typedef int GLint;
enum { GL_READ_FRAMEBUFFER_BINDING=1, GL_DRAW_FRAMEBUFFER_BINDING,
 GL_CURRENT_PROGRAM, GL_ACTIVE_TEXTURE, GL_VIEWPORT, GL_TEXTURE_BINDING_EXTERNAL_OES,
 GL_FRAMEBUFFER, GL_READ_FRAMEBUFFER, GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
 GL_TEXTURE_2D, GL_TEXTURE_EXTERNAL_OES, GL_FRAMEBUFFER_COMPLETE, GL_TRIANGLES,
 GL_NO_ERROR, GL_TEXTURE0=100 };
struct GL {
 void (*GetIntegerv)(GLenum,GLint*);
 void (*ActiveTexture)(GLenum);
 void (*BindFramebuffer)(GLenum,GLuint);
 void (*FramebufferTexture2D)(GLenum,GLenum,GLenum,GLuint,GLint);
 GLenum (*CheckFramebufferStatus)(GLenum);
 void (*Viewport)(GLint,GLint,GLint,GLint);
 void (*UseProgram)(GLuint);
 void (*BindTexture)(GLenum,GLuint);
 void (*DrawArrays)(GLenum,GLint,GLint);
 GLenum (*GetError)(void);
};
typedef struct GL GL;
struct ra { bool is_gl; };
struct ra_tex_params { int dimensions; bool render_dst; };
struct ra_tex { struct ra_tex_params params; void *priv; };
struct ra_tex_gl { bool own_objects; GLenum target; GLuint texture,fbo; };
static bool ra_is_gl(struct ra *ra) { return ra->is_gl; }
struct timer { int unused; };
struct priv {
 GL *gl; GLuint fbo,program,oes_tex_name;
 struct timer gpu_copy_timer;
 bool slot_fbo_diag,slot_fbo_reuse;
 uint64_t slot_fbo_attempts,shared_fbo_attempts,slot_fbo_fallbacks,slot_fbo_copy_failures;
};
struct ra_hwdec_mapper { struct priv *priv; void *log; };
static GLint read_fb,draw_fb,program,active,viewport[4];
static GLuint oes[4],expected_fbo;
static int attaches,checks,draws,gets,timer_begins,timer_ends;
static GLenum framebuffer_status,draw_error;
static bool timer_enabled;
static void get(GLenum what,GLint *out) {
 gets++;
 switch (what) {
 case GL_READ_FRAMEBUFFER_BINDING: *out=read_fb; break;
 case GL_DRAW_FRAMEBUFFER_BINDING: *out=draw_fb; break;
 case GL_CURRENT_PROGRAM: *out=program; break;
 case GL_ACTIVE_TEXTURE: *out=active; break;
 case GL_VIEWPORT: memcpy(out,viewport,sizeof(viewport)); break;
 case GL_TEXTURE_BINDING_EXTERNAL_OES: *out=oes[active-GL_TEXTURE0]; break;
 default: assert(false);
 }
}
static void active_tex(GLenum value) { active=value; }
static void bind_fb(GLenum target,GLuint value) {
 if (target==GL_FRAMEBUFFER || target==GL_READ_FRAMEBUFFER) read_fb=value;
 if (target==GL_FRAMEBUFFER || target==GL_DRAW_FRAMEBUFFER) draw_fb=value;
}
static void attach(GLenum target,GLenum point,GLenum texture_target,GLuint texture,GLint level) {
 assert(target==GL_FRAMEBUFFER && point==GL_COLOR_ATTACHMENT0);
 assert(texture_target==GL_TEXTURE_2D && texture==555 && level==0); attaches++;
}
static GLenum check(GLenum target) { assert(target==GL_FRAMEBUFFER); checks++; return framebuffer_status; }
static void set_viewport(GLint x,GLint y,GLint w,GLint h) {
 viewport[0]=x;viewport[1]=y;viewport[2]=w;viewport[3]=h;
}
static void use_program(GLuint value) { program=value; }
static void bind_texture(GLenum target,GLuint value) {
 assert(target==GL_TEXTURE_EXTERNAL_OES); oes[active-GL_TEXTURE0]=value;
}
static void draw(GLenum mode,GLint first,GLint count) {
 assert(mode==GL_TRIANGLES && first==0 && count==3);
 assert(read_fb==(GLint)expected_fbo && draw_fb==(GLint)expected_fbo);
 assert(program==200 && active==GL_TEXTURE0 && oes[0]==300);
 assert(viewport[0]==0 && viewport[1]==0 && viewport[2]==3840 && viewport[3]==1920);
 draws++;
}
static GLenum get_error(void) { return draw_error; }
static bool mks_gpu_timer_begin(struct timer *t,GL *g,void *l,const char *label,double pts) {
 (void)t;(void)g;(void)l;assert(!strcmp(label,"input-copy") && pts==35.035);
 timer_begins++;return timer_enabled;
}
static void mks_gpu_timer_end(struct timer *t,bool enabled) {
 (void)t;assert(enabled==timer_enabled);timer_ends++;
}
static struct GL gl={get,active_tex,bind_fb,attach,check,set_viewport,use_program,
                     bind_texture,draw,get_error};
static void reset(struct priv *p) {
 *p=(struct priv){.gl=&gl,.fbo=100,.program=200,.oes_tex_name=300};
 read_fb=41;draw_fb=42;program=43;active=GL_TEXTURE0+3;
 viewport[0]=5;viewport[1]=7;viewport[2]=123;viewport[3]=456;
 for (int i=0;i<4;i++) oes[i]=50+i;
 attaches=checks=draws=gets=timer_begins=timer_ends=0;
 framebuffer_status=GL_FRAMEBUFFER_COMPLETE;draw_error=GL_NO_ERROR;
 timer_enabled=false;
}
static void restored(void) {
 assert(read_fb==41 && draw_fb==42 && program==43 && active==GL_TEXTURE0+3);
 assert(viewport[0]==5 && viewport[1]==7 && viewport[2]==123 && viewport[3]==456);
 for (int i=0;i<4;i++) assert(oes[i]==50u+i);
 assert(gets==6);
}
'''

TEST = r'''
int main(void) {
 struct ra ra={true},other={false};
 struct ra_tex_gl owned={.own_objects=true,.target=GL_TEXTURE_2D,.texture=555,.fbo=777};
 struct ra_tex tex={.params={.dimensions=2,.render_dst=true},.priv=&owned};
 GLuint fbo=999;
 assert(ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==777);
 owned.fbo=888; // slot recreation supplies the current object, no cached name
 assert(ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==888);
 assert(!ra_gl_get_owned_fbo(&other,&tex,&fbo) && fbo==0);
 assert(!ra_gl_get_owned_fbo(NULL,&tex,&fbo) && fbo==0);
 assert(!ra_gl_get_owned_fbo(&ra,NULL,&fbo) && fbo==0);
 assert(!ra_gl_get_owned_fbo(&ra,&tex,NULL));
 tex.priv=NULL;assert(!ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==0);tex.priv=&owned;
 owned.own_objects=false;assert(!ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==0);owned.own_objects=true;
 owned.target=GL_TEXTURE_EXTERNAL_OES;assert(!ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==0);owned.target=GL_TEXTURE_2D;
 tex.params.render_dst=false;assert(!ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==0);tex.params.render_dst=true;
 tex.params.dimensions=3;assert(!ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==0);tex.params.dimensions=2;
 owned.texture=0;assert(!ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==0);owned.texture=555;
 owned.fbo=0;assert(!ra_gl_get_owned_fbo(&ra,&tex,&fbo) && fbo==0);owned.fbo=888;
 assert(gets==0 && draws==0 && attaches==0 && checks==0); // getter is CPU-only
 struct priv p;struct ra_hwdec_mapper mapper={.priv=&p};
 reset(&p);expected_fbo=p.fbo;
 assert(draw_copy(&mapper,555,0,3840,1920,true,35.035));
 assert(attaches==1 && checks==1 && draws==1 && timer_begins==1 && timer_ends==1);
 assert(!p.shared_fbo_attempts && !p.slot_fbo_attempts);restored();
 reset(&p);p.slot_fbo_diag=true;p.slot_fbo_reuse=true;expected_fbo=888;
 assert(draw_copy(&mapper,555,888,3840,1920,true,35.035));
 assert(attaches==0 && checks==0 && draws==1 && timer_begins==1 && timer_ends==1);
 assert(p.slot_fbo_attempts==1 && p.shared_fbo_attempts==0 && p.slot_fbo_copy_failures==0);restored();
 reset(&p);p.slot_fbo_diag=true;p.slot_fbo_reuse=true;expected_fbo=888;draw_error=999;
 assert(!draw_copy(&mapper,555,888,3840,1920,true,35.035));
 assert(attaches==0 && checks==0 && draws==1 && p.slot_fbo_copy_failures==1);restored();
 reset(&p);p.slot_fbo_diag=true;expected_fbo=100;
 assert(draw_copy(&mapper,555,0,3840,1920,true,35.035));
 assert(p.shared_fbo_attempts==1 && p.slot_fbo_attempts==0);restored();
 reset(&p);expected_fbo=100;framebuffer_status=999;
 assert(!draw_copy(&mapper,555,0,3840,1920,true,35.035));
 assert(attaches==1 && checks==1 && draws==0 && timer_begins==0 && timer_ends==0);restored();
 reset(&p);expected_fbo=100;
 assert(draw_copy(&mapper,555,0,3840,1920,false,NAN));
 assert(attaches==1 && checks==1 && draws==1 && timer_begins==0 && timer_ends==1);restored();
 reset(&p);expected_fbo=888;timer_enabled=true;
 assert(draw_copy(&mapper,555,888,3840,1920,true,35.035));
 assert(timer_begins==1 && timer_ends==1);restored();
 return 0;
}
'''


class InputFboTest(unittest.TestCase):
    def test_real_getter_and_copy_with_gl_doubles(self):
        if not shutil.which('clang'):
            self.skipTest('clang unavailable')
        ra = ROOT / 'mpv/video/out/opengl/ra_gl.c'
        hw = ROOT / 'mpv/video/out/hwdec/hwdec_surfacetexture.c'
        source = STUBS + function(ra,'ra_gl_get_owned_fbo') + function(hw,'slot_fbo_report') + function(hw,'draw_copy') + TEST
        with tempfile.TemporaryDirectory() as temp:
            c,exe=Path(temp)/'fbo.c',Path(temp)/'fbo'
            c.write_text(source)
            subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror',str(c),'-lm','-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)


if __name__ == '__main__':
    unittest.main()
