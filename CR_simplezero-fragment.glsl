#version 120

varying float vDepth;

void main()
{
	gl_FragData[0] = vec4(0.0, 0.0, 0.0, 0.0);

#ifdef LOGDEPTH_ENABLE	
	// logarithmic depth
	const float C = 0.1;
	const float far = 1e+09;
	const float offset = 1.0;
	gl_FragDepth = log(C * vDepth + offset) / log(C * far + offset);
#endif
}
