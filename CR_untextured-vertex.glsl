#version 120

uniform mat4 wvpMat;
uniform vec4 diffuseColor;

attribute vec4 vertex;
attribute vec4 colour;

varying vec4 vColor;
varying float vDepth;

void main()
{
	gl_Position = wvpMat * vertex;
	vColor = colour.bgra * diffuseColor;	// swap R and B channels for OpenGL
	vDepth = gl_Position.z;
}
