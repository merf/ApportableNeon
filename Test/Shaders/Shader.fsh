//
//  Shader.fsh
//  Test
//
//  Created by Neil Wallace on 04/02/2014.
//  Copyright (c) 2014 Neil Wallace. All rights reserved.
//

varying lowp vec4 vColour;
varying lowp vec2 vTexCoord;

uniform sampler2D u_Tex0Sampler;


void main()
{
	mediump vec2 tc = vTexCoord;
	tc -= 0.5;
	
	mediump float angle = atan(tc.y, tc.x);
	
	mediump float stripe = smoothstep(0.4, 0.5, sin(angle * 20.0));
	
	mediump vec4 colour = vec4(stripe, stripe, stripe,1);
	
    gl_FragColor = colour;
}
