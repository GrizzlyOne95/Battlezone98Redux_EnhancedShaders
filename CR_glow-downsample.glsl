#version 120

uniform sampler2D rt;

varying vec2 vTexCoord;

void main()
{
	gl_FragData[0] = texture2D(rt, vTexCoord);
	gl_FragData[0].rgb *= gl_FragData[0].rgb;
}
