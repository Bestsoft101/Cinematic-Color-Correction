#include "ReShadeUI.fxh"
#include "ReShade.fxh"

#define BLOOM
#define BLOOM_TRESHOLD 0.25
#define BLOOM_LOD 16
#define BLOOM_COLOR
#define BLUR_STEPS_X 16
#define BLUR_STEPS_Y 4
#define BLUR_SCALE_X 1
#define BLUR_SCALE_Y 1

#define TONEMAP

#define CROSSPROCESS

#define VIGNETTE

#define vec3 float3
#define vec4 float4
#define mix lerp

uniform float BLOOM_STRENGTH <
	ui_label = "Bloom Strength";
	ui_type = "slider";
	ui_min = 0.0f;
	ui_max = 1.0f;
> = 0.15f;

uniform float VIGNETTE_STRENGTH <
	ui_label = "Vignette Strength";
	ui_type = "slider";
	ui_min = 0.0f;
	ui_max = 1.0f;
> = 0.6f;

uniform float GAMMA <
	ui_label = "Gamma";
	ui_type = "slider";
	ui_min = 0.5f;
	ui_max = 1.5f;
> = 1.0f;

texture2D BloomTexture {
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = RGBA8;
	MipLevels = 11;
};

sampler2D BloomSampler {
	Texture = BloomTexture;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};

bool isEven(int num) {
	return ((num / 2) * 2) == num;
}

vec4 BlurV(vec4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	float lod = BLOOM_LOD;
	float2 offset;
	if(lod > 1) {
		offset = 0.25f;
	}else{
		offset = 0.0f;
	}
	
	vec3 blur = 0.0f;
	float2 newTexcoord = (texcoord - offset) * lod;
	float padding = 0.001f * lod;
	
	if(newTexcoord.x > -padding
			&& newTexcoord.y > -padding
			&& newTexcoord.x < 1.0f + padding
			&& newTexcoord.y < 1.0f + padding) {
		int quality = BLUR_STEPS_Y;
		float scale = BLUR_SCALE_Y;
		float qh;
		if(isEven(quality)) {
			qh = quality / 2 - 0.5f;
		}else {
			qh = quality / 2;
		}
		float total = 0.0f;
		
		for(int i=0; i < quality; i++) {
			float2 offset = float2(0.0f, (1.0f / BUFFER_HEIGHT) * (i - qh) * (scale * lod));
			float strength = sin(((i + 1) / float(quality + 1)) * 3.14159);
			
			vec3 blurLayer = tex2D(ReShade::BackBuffer, newTexcoord + offset).rgb * strength;
			blurLayer = blurLayer * (1.0f + BLOOM_TRESHOLD) - BLOOM_TRESHOLD;
			#ifdef BLOOM_COLOR
			blurLayer *= vec3(1.0f, 0.7f, 0.0f);
			#endif
			
			blurLayer = clamp(blurLayer, 0.0f, 1.0f);
			
			blur += blurLayer;
			total += strength;
		}
		blur /= total;
	}
	
	return vec4(blur, 1.0f);
}

vec4 BlurH(vec4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	float lod = BLOOM_LOD;
	float2 offset;
	if(lod > 1) {
		offset = 0.25f;
	}else{
		offset = 0.0f;
	}
	
	vec3 blur = 0.0f;
	//float2 newTexcoord = (texcoord - offset) * lod;
	float2 newTexcoord = (texcoord / lod) + offset;
	float padding = 0.001f * lod;
	
	int quality = BLUR_STEPS_X;
	float scale = BLUR_SCALE_X;
	float qh;
	if(isEven(quality)) {
		qh = quality / 2 - 0.5f;
	}else {
		qh = quality / 2;
	}
	float total = 0.0f;
	
	for(int i=0; i < quality; i++) {
		float2 offset = float2((1.0f / BUFFER_WIDTH) * (i - qh) * scale, 0.0f);
		float strength = sin(((i + 1) / float(quality + 1)) * 3.14159);
		
		blur += tex2Dlod(BloomSampler, vec4(newTexcoord + offset, 0.0f, 0)).rgb * strength;
		total += strength;
	}
	
	blur /= total;
	
	return vec4(blur, 1.0f);
}

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// From https://github.com/dmnsgn/glsl-tone-map
vec3 aces(vec3 x) {
	const float a = 1.7;
	const float b = 0.29;
	const float c = 1.0;
	const float d = 0.8;
	const float e = 0.25;
	
	return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

vec4 Final(vec4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	vec3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	
	#ifdef BLOOM
	vec3 bloom = BlurH(vpos, texcoord).rgb;
	
	color += bloom * BLOOM_STRENGTH;
	#endif
	
	#ifdef VIGNETTE
	float2 center = 0.5f;
	
	float vignette = length(texcoord - center) * 1.41421f;
	vignette = pow(vignette, 2.0f);
	vignette = 1.0f - vignette;
	vignette = mix(1.0f, vignette, VIGNETTE_STRENGTH);
	vignette = clamp(vignette, 0.0f, 1.0f);
	color *= vignette;
	#endif
	
	#ifdef CROSSPROCESS
	float brightness = rgb2hsv(color).b;
	
	float crossProcessGamma = 1.6f;
	float crossProcessStrength = 0.5f;
	
	float darkFactor = (1.0f - pow(brightness, 1.0f / crossProcessGamma)) - 0.5f;
	float brightFactor = (pow(brightness, crossProcessGamma)) - 0.5f;
	
	vec3 darkColor = color * vec3(0.0f, 0.7f, 1.0f) * 1.3f;
	vec3 brightColor = color * vec3(1.0f, 1.0f, 0.0f) * 1.3f;
	
	color = mix(color, darkColor, clamp(darkFactor * crossProcessStrength, 0.0f, 1.0f));
	#endif
	
	#ifdef TONEMAP
	color = aces(color);
	#endif
	
	color = pow(color, vec3(GAMMA, GAMMA, GAMMA));	
	
	return vec4(color, 1.0f);
}
	
technique CCC {
	pass {
		VertexShader = PostProcessVS;
		PixelShader = BlurV;
		RenderTarget = BloomTexture;
	}
	pass {
		VertexShader = PostProcessVS;
		PixelShader = Final;
	}
}