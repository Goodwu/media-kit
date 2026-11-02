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
in vec2 _15;
out vec2 _8003;
in vec2 _16;
invariant gl_Position;
invariant _8003;
void main() {
_8003 = _15;
vec2 va_pos = _16; 
gl_Position = vec4(va_pos, 0.0, 1.0); 
}