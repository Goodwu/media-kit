#version 320 es
#ifdef GL_FRAGMENT_PRECISION_HIGH 
precision highp float;            
#else                             
precision mediump float;          
#endif                            
precision mediump sampler2D; 
precision mediump sampler3D; 
precision highp int; 
uniform  sampler2D _8002;
uniform mat3 _d;
uniform mat3 _e;
in vec2 _8003;
out vec4 out_color;

const float _2 = float(0); 
const float _3 = float(0); 
const float _8004 = float(1); 
vec4 _8001() {
// pl_shader_sample_direct                                  
vec4 color = vec4(_8004) * vec4(textureLod(_8002, _8003, 0.0));   
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

void main() {
out_color = _1();
}