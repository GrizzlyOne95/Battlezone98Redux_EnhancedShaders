#version 120

uniform sampler2D scene;
uniform sampler2D blurX;
uniform float glowPower;

varying vec2 vTexCoord;

void main()
{
	gl_FragData[0] = texture2D(scene, vTexCoord) + texture2D(blurX, vTexCoord) * glowPower;
}
