#version 120

uniform sampler2D diffuseMap;

varying vec2 vTexCoord;
varying float vDepth;

void main()
{
	gl_FragData[0] = texture2D(diffuseMap, vTexCoord);

#ifdef LOGDEPTH_ENABLE	
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
