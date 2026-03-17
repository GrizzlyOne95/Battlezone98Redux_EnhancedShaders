#version 120

uniform mat4 wvpMat;

attribute vec4 vertex;
attribute vec4 colour;
attribute vec2 uv0;

varying vec4 vColor;
varying vec2 vTexCoord;

void main()
{
    gl_Position = wvpMat * vertex;
    vColor = colour.bgra;	// swap R and B channels for OpenGL
    vTexCoord = uv0;
}
