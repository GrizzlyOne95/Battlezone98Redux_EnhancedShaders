#version 120

uniform sampler2D diffuseMap;

varying vec4 vColor;
varying vec2 vTexCoord;
#ifdef LOGDEPTH_ENABLE
varying float vDepth;
#endif

void main()
{
	vec4 diffuseTex = texture2D(diffuseMap, vTexCoord);
	vec4 oColor = diffuseTex * vColor;

	gl_FragData[0] = oColor;

#ifdef LOGDEPTH_ENABLE
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
