#version 120

const float gaussSamples[13] = float[]
(
	0.002216,
	0.008764,
	0.026995,
	0.064759,
	0.120985,
	0.176033,
	0.199471,
	0.176033,
	0.120985,
	0.064759,
	0.026995,
	0.008764,
	0.002216
);

uniform sampler2D rt;
uniform vec4 invMapSize;
uniform float scaleGlowOffset;

varying vec2 vTexCoord;

void main()
{
	vec4 colOut = vec4(0, 0, 0, 0);
	for (int i = 0; i < 13; i++)
	{
		colOut += texture2D(rt, vTexCoord + vec2(0.5, 0.5 + float(i - 6) * scaleGlowOffset) * invMapSize.xy) * gaussSamples[i];
	}
	gl_FragData[0] = colOut;
}
