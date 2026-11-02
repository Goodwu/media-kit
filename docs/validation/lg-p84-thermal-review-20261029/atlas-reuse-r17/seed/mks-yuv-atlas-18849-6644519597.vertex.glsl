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
in vec2 _13;
out vec2 _8003;
in vec2 _14;
void main() {
_8003 = _13;
vec2 va_pos = _14; 
gl_Position = vec4(va_pos, 0.0, 1.0); 
}