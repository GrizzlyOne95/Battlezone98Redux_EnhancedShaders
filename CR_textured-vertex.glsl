#version 120

uniform mat4 wvpMat;

attribute vec4 vertex;
attribute vec2 uv0;

varying vec2 vTexCoord;
varying float vDepth;

void main()
{
	gl_Position = wvpMat * vertex;
	vTexCoord = uv0;
	vDepth = gl_Position.z;
}
