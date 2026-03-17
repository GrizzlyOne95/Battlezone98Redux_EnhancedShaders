#version 120

uniform mat4 wvpMat;
uniform mat4 texMat;

attribute vec4 vertex;
attribute vec4 colour;
attribute vec4 uv0;

varying vec4 vColor;
varying vec2 vTexCoord;

void main()
{
    gl_Position = wvpMat * vertex;
    vColor = colour.bgra;	// swap R and B channels for OpenGL
    vTexCoord = vec2(texMat * uv0);
}
