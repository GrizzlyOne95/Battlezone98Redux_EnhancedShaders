#version 120

uniform mat4 wvpMat;
uniform vec4 diffuseColor;

attribute vec4 vertex;
attribute vec4 colour;
attribute vec2 uv0;

varying vec4 vColor;
varying vec2 vTexCoord;
varying float vDepth;

void main()
{
	gl_Position = wvpMat * vertex;
	vColor = colour.bgra * diffuseColor;	// swap R and B channels for OpenGL
	vTexCoord = uv0;
	vDepth = gl_Position.z;
}
