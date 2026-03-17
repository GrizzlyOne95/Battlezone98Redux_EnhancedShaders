#version 120

uniform mat4 wvpMat;

attribute vec4 vertex;

varying float vDepth;

void main()
{
	gl_Position = wvpMat * vertex;
	vDepth = gl_Position.z;
}
