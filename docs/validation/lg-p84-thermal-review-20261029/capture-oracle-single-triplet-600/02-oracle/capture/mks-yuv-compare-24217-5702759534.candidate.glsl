#version 320 es
#extension GL_EXT_YUV_target : require
#ifdef GL_FRAGMENT_PRECISION_HIGH 
precision highp float;            
#else                             
precision mediump float;          
#endif                            
precision mediump sampler2D; 
precision mediump sampler3D; 
precision highp int; 
uniform  sampler2D _8002;
layout(std430, binding=0)  coherent restrict buffer _13 {
uint _12[106496];
};
uniform mat3 _d;
uniform mat3 _e;
in vec2 _8003;
layout(yuv) out highp vec3 out_color;
layout(std430,binding=1) coherent restrict buffer mks_oracle_probe { highp uint mks_probe_words[40960]; };
uniform highp int mks_probe_pair;
highp uint mks_probe_helpers=0u;
highp uint mks_probe_sites=0u;
highp uvec2 mks_probe_seen_counts=uvec2(0u);
highp uvec2 mks_probe_seen_uv=uvec2(0u);
highp uint mks_probe_reason=1u;
highp uint mks_probe_selected=2u;
highp vec2 mks_tap_uv;
highp vec4 mks_tap_sample;
highp uint mks_tap_count;
uniform highp int mks_uv_oracle_use_a;
bool mks_oracle_valid;
highp vec2 mks_oracle_uv(highp vec2 own_uv) {
mks_probe_helpers++;
mks_oracle_valid=true;
ivec2 p=ivec2(gl_FragCoord.xy)-ivec2(1304,636);
if(all(greaterThanEqual(p,ivec2(0)))&&all(lessThan(p,ivec2(64,64)))) {
uint i=uint(p.y*64+p.x)*26u;
mks_probe_seen_counts=uvec2(_12[i+10u],_12[i+25u]);
mks_probe_seen_uv=uvec2(_12[i+20u],_12[i+21u]);
highp vec2 a_uv=uintBitsToFloat(mks_probe_seen_uv);
mks_probe_reason=0u;
if(mks_probe_seen_counts.x!=1u) mks_probe_reason|=2u;
if(mks_probe_seen_counts.y!=1u) mks_probe_reason|=4u;
if(any(isnan(a_uv))||any(isinf(a_uv))) mks_probe_reason|=8u;
if(mks_probe_reason!=0u) {mks_oracle_valid=false; return own_uv;}
mks_probe_selected=mks_uv_oracle_use_a==1 ? 1u : 0u;
return mks_uv_oracle_use_a==1 ? a_uv : own_uv;
}
mks_oracle_valid=false;
return own_uv;
}
#define mks_capture_words _12

const float _2 = float(0); 
const float _3 = float(0); 
const float _8004 = float(1); 
vec4 _8001() {
// pl_shader_sample_direct                                  
mks_tap_uv=mks_oracle_uv(_8003);
highp vec4 mks_sample_value=vec4(textureLod(_8002, mks_tap_uv, 0.0));
mks_probe_sites++;
mks_tap_sample=mks_sample_value;
mks_tap_count+=mks_oracle_valid ? 1u : 0u;
vec4 color=vec4(_8004)*mks_sample_value;   
return color;
}

const float _4 = float(1); 
const float _5 = float(0.9996919631958008); 
const float _6 = float(0.0003080070891883224); 
const float _7 = float(4.926108360290527); 
const float _9 = float(0.26270022988319397); 
const float _a = float(0.6779980063438416); 
const float _b = float(0.0593017153441906); 
#define _8 vec3(_9, _a, _b) 
const float _c = float(0.20000004768371582); 
const float _f = float(1); 
vec4 _1() {
vec4 color = vec4(_2, vec2(_3), 1.0);   
// pass_read_image                        
{                                         
vec4 tmp;                                 
tmp = vec4(_4) * _8001(); 
color[0] = tmp[0];
color[1] = tmp[1];
color[2] = tmp[2];
}
// pl_shader_decode_color 
{ 
}
// pl_shader_color_map 
{                      
// pl_shader_linearize 
color.rgb = max(color.rgb, 0.0); 
color.rgb = _5 * color.rgb + vec3(_6);                  
color.rgb = mix(vec3(4.0) * color.rgb * color.rgb,        
                exp((color.rgb - vec3(0.5599107146263123)) * vec3(1.0/0.1788327693939209))
                    + vec3(0.2846689224243164),                           
                lessThan(vec3(0.5), color.rgb));          
color.rgb *= 1.0 / 12.0;                                      
color.rgb *= _7 * pow(max(dot(_8, color.rgb), 0.0), _c);   
// pl_shader_delinearize 
color.rgb = max(color.rgb, 0.0); 
color.rgb *= vec3(1.0/49.261085510253906);                         
color.rgb = pow(color.rgb, vec3(0.1593017578125));              
color.rgb = (vec3(0.8359375) + vec3(18.8515625) * color.rgb)      
             / (vec3(1.0) + vec3(18.6875) * color.rgb); 
color.rgb = pow(color.rgb, vec3(78.84375));              
}
// pl_shader_encode_color 
{ 
}
color.rgba *= vec4(1.0 / _f); 
vec4 _10 = color;                 
color = vec4(0.0, 0.0, 0.0, 1.0); 
color[0] = _10[0]; 
color[1] = _10[1]; 
color[2] = _10[2]; 
color[3] = _10[3]; 
return color;
}

highp float mks_half_store(highp float value) {
highp uint raw=floatBitsToUint(value); highp uint mag=raw&0x7fffffffu;
if(mag==0u||mag>=0x38800000u) return unpackHalf2x16(packHalf2x16(vec2(value,0.0))).x;
highp uint sign=raw&0x80000000u; highp int e=int(mag>>23u)-127;
if(e< -24) return uintBitsToFloat(sign);
highp uint h=((mag&0x7fffffu)|0x800000u)>>uint(-e-1);
highp float q=float(h)*0.000000059604644775390625;
return uintBitsToFloat(floatBitsToUint(q)|sign); }
void main() {
mks_tap_uv=vec2(0.0); mks_tap_sample=vec4(0.0); mks_tap_count=0u;
highp vec3 mks_rgb = _1().rgb;
highp vec3 mks_pre=mks_rgb;
mks_rgb=vec3(mks_half_store(mks_rgb.r),mks_half_store(mks_rgb.g),mks_half_store(mks_rgb.b));
highp float mks_y=0.2627*mks_rgb.r+0.6780*mks_rgb.g+0.0593*mks_rgb.b;
highp float mks_cb=(mks_rgb.b-mks_y)*0.5/(1.0-0.0593);
highp float mks_cr=(mks_rgb.r-mks_y)*0.5/(1.0-0.2627);
out_color=vec3(mks_y,mks_cb+0.5,mks_cr+0.5);
ivec2 mks_p=ivec2(gl_FragCoord.xy)-ivec2(1304,636);
if(all(greaterThanEqual(mks_p,ivec2(0)))&&all(lessThan(mks_p,ivec2(64,64)))){
uint mks_i=uint(mks_p.y*64+mks_p.x)*26u;
uint mks_old=atomicAdd(_12[mks_i+0u],1u);
if(mks_old==0u){
_12[mks_i+1u]=floatBitsToUint(mks_pre[0]);
_12[mks_i+4u]=floatBitsToUint(mks_rgb[0]);
_12[mks_i+7u]=floatBitsToUint(out_color[0]);
_12[mks_i+2u]=floatBitsToUint(mks_pre[1]);
_12[mks_i+5u]=floatBitsToUint(mks_rgb[1]);
_12[mks_i+8u]=floatBitsToUint(out_color[1]);
_12[mks_i+3u]=floatBitsToUint(mks_pre[2]);
_12[mks_i+6u]=floatBitsToUint(mks_rgb[2]);
_12[mks_i+9u]=floatBitsToUint(out_color[2]);
_12[mks_i+14u]=floatBitsToUint(mks_tap_uv[0]);
_12[mks_i+15u]=floatBitsToUint(mks_tap_uv[1]);
_12[mks_i+16u]=floatBitsToUint(mks_tap_sample[0]);
_12[mks_i+17u]=floatBitsToUint(mks_tap_sample[1]);
_12[mks_i+18u]=floatBitsToUint(mks_tap_sample[2]);
_12[mks_i+19u]=mks_tap_count;
}
uint mks_probe_i=(uint(mks_probe_pair)*4096u+uint(mks_p.y*64+mks_p.x))*10u;
uint mks_probe_old=atomicAdd(mks_probe_words[mks_probe_i],1u);
if(mks_probe_old==0u){
mks_probe_words[mks_probe_i+1u]=mks_probe_helpers;
mks_probe_words[mks_probe_i+2u]=mks_probe_sites;
mks_probe_words[mks_probe_i+3u]=mks_probe_seen_counts.x;
mks_probe_words[mks_probe_i+4u]=mks_probe_seen_counts.y;
mks_probe_words[mks_probe_i+5u]=mks_probe_seen_uv.x;
mks_probe_words[mks_probe_i+6u]=mks_probe_seen_uv.y;
mks_probe_words[mks_probe_i+7u]=mks_probe_reason;
mks_probe_words[mks_probe_i+8u]=mks_oracle_valid ? 1u : 0u;
mks_probe_words[mks_probe_i+9u]=mks_probe_selected;
}}
}