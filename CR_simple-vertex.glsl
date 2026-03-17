#version 120

uniform mat4 wvpMat;
uniform mat4 worldViewMat;

attribute vec4 vertex;
attribute vec3 normal;
attribute vec2 uv0;
attribute vec4 colour;

varying vec4 vColor;
varying vec2 vTexCoord;
varying vec3 vViewPosition;
varying vec3 vViewNormal;
varying float vDepth;

void main()
{
	vec4 iPosition = vertex;
	vec3 iNormal = normal;
	vec2 iTexCoord = uv0;
	vec4 iColor = colour.bgra;

	gl_Position = wvpMat * iPosition;
	vTexCoord = iTexCoord;
	vViewPosition = vec3(worldViewMat * vec4(iPosition.xyz, 1.0));
	vViewNormal = vec3(worldViewMat * vec4(iNormal.xyz, 0.0));
	vDepth = gl_Position.z;
	vColor = iColor;
}
