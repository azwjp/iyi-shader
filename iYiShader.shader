// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Custom/iYiShader"
{
    Properties
    {
		[Header(Rendering)]
		[Enum(UnityEngine.Rendering.CullMode)]_CullMode("Cull Mode", Int) = 0
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
		[Normal][Header(Normal Map)]_Normal("Normal", 2D) = "bump" {}
		[Header(Fresnel Schlick approximation )]_FresnelColor("Fresnel Color", Color) = (1,1,1,0)
		[PowerSlider(2)] _FresnelRimCoefficient("Rim Coefficient", Range(0.0, 1.0)) = 1
		[PowerSlider(2)] _FresnelBaseCoefficient("Base Coefficient", Range(0.0, 1.0)) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
		Cull[_CullMode]
        LOD 200

        CGINCLUDE
			inline float4x4 InvTangentMatrix(float3 tan, float3 bin, float3 nor)
		{
			return transpose(float4x4(
				float4(tan, 0),
				float4(bin, 0),
				float4(nor, 0),
				float4(0, 0, 0, 1)
				));
		}
        ENDCG

		Pass{
			Tags { "LightMode"="ForwardBase" }

			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase

			
			// Physically based Standard lighting model, and enable shadows on all light types

			// Use shader model 3.0 target, to get nicer looking lighting
			#pragma target 3.0
			#include "UnityPBSLighting.cginc"
			#include "AutoLight.cginc"

			struct Input
			{
				float2 uv_MainTex;
				float3 worldPos;
				float3 worldNormal;

				half ASEVFace;
			};

			struct SurfaceOutputIyi
			{
				fixed3 Albedo;      // base (diffuse or specular) color
				float3 Normal;      // tangent space normal, if written
				half3 Emission;
				half Metallic;      // 0=non-metal, 1=metal
									// Smoothness is the user facing name, it should be perceptual smoothness but user should not have to deal with it.
									// Everywhere in the code you meet smoothness it is perceptual smoothness
				half Smoothness;    // 0=rough, 1=smooth
				half Occlusion;     // occlusion (default 1)
				fixed Alpha;        // alpha for transparencies
				Input SurfInput;
				UnityGIInput GIData;
			};

			sampler2D _MainTex;
			half4 _MainTex_ST;
			half _Glossiness;
			half _Metallic;
			fixed4 _Color;
			sampler2D _Normal;
			half4 _Normal_ST;
			half _NormalScale;
			fixed4  _FresnelColor;
			half _FresnelRimCoefficient;
			half _FresnelBaseCoefficient;

			inline half4 LightingIyi(SurfaceOutputIyi s, float3 viewDir, UnityGI gi)
			{
				//s.Normal = normalize(s.Normal);
				//
				half oneMinusReflectivity;
				half3 specColor;
				//s.Albedo = DiffuseAndSpecularFromMetallic(s.Albedo, s.Metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

				//// shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
				//// this is necessary to handle transparency in physically correct way - only diffuse component gets affected by alpha
				//half outputAlpha;
				//s.Albedo = PreMultiplyAlpha(s.Albedo, s.Alpha, oneMinusReflectivity, /*out*/ outputAlpha);
				//
				half4 c = 0;// UNITY_BRDF_PBS(s.Albedo, specColor, oneMinusReflectivity, s.Smoothness, s.Normal, viewDir, gi.light, gi.indirect);
				//half d = dot(s.Normal, viewDir);
				c.rgb = s.Albedo.rgb;
				c.a = s.Alpha;
							
				return c;
			}

			inline void LightingIyi_GI(
				SurfaceOutputIyi s,
				UnityGIInput data,
				inout UnityGI gi)
			{
				#if defined(UNITY_PASS_DEFERRED) && UNITY_ENABLE_REFLECTION_BUFFERS
							gi = UnityGlobalIllumination(data, s.Occlusion, s.Normal);
				#else
							Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.Smoothness, data.worldViewDir, s.Normal, lerp(unity_ColorSpaceDielectricSpec.rgb, s.Albedo, s.Metallic));
							gi = UnityGlobalIllumination(data, s.Occlusion, s.Normal, g);
				#endif
			}

			// Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
			// See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
			// #pragma instancing_options assumeuniformscaling
			UNITY_INSTANCING_BUFFER_START(Props)
				// put more per-instance properties here
			UNITY_INSTANCING_BUFFER_END(Props)

			/*void surf(Input IN, inout SurfaceOutputIyi o)
			{
				o.SurfInput = IN;
				// Albedo comes from a texture tinted by color
				fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
				o.Albedo = c.rgb;
				// Metallic and smoothness come from slider variables
				o.Metallic = _Metallic;
				o.Smoothness = _Glossiness;
				o.Alpha = c.a;
			}*/
			struct v2f
			{
				UNITY_POSITION(pos);
				float2 uv : TEXCOORD0; // _MainTex
				float3 worldNormal : TEXCOORD1;
				float3 worldPos : TEXCOORD2;
				float3 ambient: TEXCOORD3;
				float3 lightDir : TEXCOORD4;
				UNITY_SHADOW_COORDS(5)
			};
			v2f vert(appdata_full v) {
				v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv.xy = TRANSFORM_TEX(v.texcoord, _MainTex);
				o.worldPos.xyz = mul(unity_ObjectToWorld, v.vertex).xyz;
				o.worldNormal = UnityObjectToWorldNormal(v.normal);
				UNITY_TRANSFER_LIGHTING(o, v.texcoord1.xy); // pass shadow and, possibly, light cookie coordinates to pixel shader

				// ambient light
				#if UNITY_SHOULD_SAMPLE_SH
				#if defined(VERTEXLIGHT_ON)
					o.ambient = Shade4PointLights(
						unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
						unity_LightColor[0].rgb, unity_LightColor[1].rgb,
						unity_LightColor[2].rgb, unity_LightColor[3].rgb,
						unity_4LightAtten0, o.worldPos, o.worldNormal
					);
				#endif
					o.ambient += max(0, ShadeSH9(float4(o.worldNormal, 1)));
				#else
					o.ambient = 0;
				#endif

				// for bamp map
				float3 n = normalize(v.normal);
				o.lightDir = normalize(mul(mul(unity_WorldToObject, _WorldSpaceLightPos0), InvTangentMatrix(v.tangent, cross(n, v.tangent), n)));

				return o;
			}
			fixed4 frag(v2f IN, half ASEVFace : VFACE) : SV_Target{
				//surf
				SurfaceOutputIyi o;
				UNITY_INITIALIZE_OUTPUT(SurfaceOutputIyi, o);
				Input input;
				input.uv_MainTex = IN.uv;
				o.Emission = 0.0;
				o.Occlusion = 1.0;
				o.Normal = IN.worldNormal;

				input.ASEVFace = ASEVFace;
				// dup
				input.worldPos = IN.worldPos;
				input.worldNormal = IN.worldNormal;

				// surf method
				o.SurfInput = input;
				// Albedo comes from a texture tinted by color
				fixed4 col = tex2D(_MainTex, input.uv_MainTex) * _Color;

				float3 worldPos = IN.worldPos;
				float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
#ifndef USING_DIRECTIONAL_LIGHT
				fixed3 lightDir = normalize(UnityWorldSpaceLightDir(worldPos));
#else
				fixed3 lightDir = _WorldSpaceLightPos0.xyz;
#endif


				half fresnel = _FresnelBaseCoefficient + (1.0 - _FresnelRimCoefficient) * pow(1.0 - dot(IN.worldNormal, worldViewDir), 5);
				col.rgb += max(0, fresnel) * _FresnelColor;

				fixed3 lightProduct = max(0, dot(IN.worldNormal, lightDir));
				fixed3 lanbert = saturate(lightProduct *0.75 + 0.25);
				fixed3 lanbert2 = pow(lightProduct, 0.3);//(pow(col, 1 / pow(lightTmp, 0.2)));
				fixed3 shadowAttenuation = lanbert2 * SHADOW_ATTENUATION(IN) ;
				fixed3 shadow = saturate(shadowAttenuation / 2 + 0.5);
				fixed3 shadow2 = saturate(shadowAttenuation);
				col.rgb = (pow(col, 1 / pow(shadow, 1.5))) * (pow(shadow, 0.5) * _LightColor0 + IN.ambient);
				//fixed3 lightTmp = saturate(dot(IN.worldNormal, _WorldSpaceLightPos0.xyz));
				//fixed3 lanbert = saturate(lightTmp / 2 + 0.5);
				//fixed3 lanbert2 = saturate(lightTmp / 10 + 0.9);
				//col.rgb *= (pow(col, 1 / pow(lanbert, 1)));
				//col.rgb += IN.ambient;
				//col = tex2D(_MainTex, input.uv_MainTex) * _Color * SHADOW_ATTENUATION(IN);
				o.Albedo = col.rgb;
				// Metallic and smoothness come from slider variables
				o.Metallic = _Metallic;
				o.Smoothness = _Glossiness;
				o.Alpha = col.a;
				//surf(input,o);

				UNITY_LIGHT_ATTENUATION(atten, IN, worldPos);
				fixed4 c = 0;

				UnityGI gi;
				UNITY_INITIALIZE_OUTPUT(UnityGI, gi);
				gi.light.color = _LightColor0.rgb;
				gi.light.dir = lightDir;

				UnityGIInput giInput;
				UNITY_INITIALIZE_OUTPUT(UnityGIInput, giInput);
				giInput.light = gi.light;
				giInput.worldPos = worldPos;
				giInput.worldViewDir = worldViewDir;
				giInput.atten = atten;

				giInput.probeHDR[0] = unity_SpecCube0_HDR;
				giInput.probeHDR[1] = unity_SpecCube1_HDR;
				#if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
					giInput.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
				#endif
				LightingIyi_GI(o, giInput, gi);
				c += LightingIyi(o, worldViewDir, gi);

				half NdotL = max(0, dot(IN.worldNormal, lightProduct));
				float3 R = normalize(-lightDir + 2.0 * IN.worldNormal * NdotL);
				float3 specular = pow(max(0, dot(R, worldViewDir)), _Glossiness * 100)*_Glossiness * atten*_LightColor0;
				c.rgb += max(0, specular);


				return c;
			}
			ENDCG
		}
		Pass{

			Tags{ "LightMode" = "ForwardAdd" }

			Blend One One
			ZWrite Off

			CGPROGRAM
#pragma vertex vert
#pragma fragment frag
#pragma multi_compile_fwdadd

#include "UnityCG.cginc"
#include "AutoLight.cginc"
#include "UnityPBSLighting.cginc"

			struct appdata
		{
			half4 vertex : POSITION;
			half3 normal : NORMAL;
			half2 texcoord : TEXCOORD0;
		};

		struct v2f
		{
			UNITY_POSITION(pos);
			half2 uv : TEXCOORD0;
			half3 worldNormal: TEXCOORD1;
			half3 ambient: TEXCOORD2;
			half3 worldPos: TEXCOORD3;
			float3 lightDir : TEXCOORD4;
			float3 worldLightDir : TEXCOORD5;
		};

		sampler2D _MainTex;
		half4 _MainTex_ST;
		half _Glossiness;
		half _Metallic;
		fixed4 _Color;
		uniform sampler2D _Normal;
		uniform float4 _Normal_ST;
		uniform float _NormalScale;

		v2f vert(appdata_full v)
		{
			v2f o = (v2f)0;

			o.pos = UnityObjectToClipPos(v.vertex);
			o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
			o.worldNormal = UnityObjectToWorldNormal(v.normal);
			o.worldPos = mul(unity_ObjectToWorld, v.vertex);

			// for bamp map
			float3 n = normalize(v.normal);
			if (_WorldSpaceLightPos0.w > 0) {
				o.worldLightDir = normalize(_WorldSpaceLightPos0.xyz - o.worldPos.xyz);
			}
			else {
				o.worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
			}
			o.lightDir = normalize(mul(mul(unity_WorldToObject, o.worldLightDir), InvTangentMatrix(v.tangent, cross(n, v.tangent), n)));

			return o;
		}

		half4 frag(v2f IN) : COLOR
		{
			half4 col = tex2D(_MainTex, IN.uv);
			float2 uv_Normal = IN.uv * _Normal_ST.xy + _Normal_ST.zw;
			half3 normal = UnpackScaleNormal(tex2D(_Normal, uv_Normal), _NormalScale);


			UNITY_LIGHT_ATTENUATION(attenuation, IN, IN.worldPos);

			float3 worldPos = IN.worldPos;
			float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
			half NdotL = max(0, dot(IN.worldNormal, IN.worldLightDir));
			if (NdotL <= 0) {
				attenuation = 0;
			}

			
			half3 diff = max(0, dot(normal, IN.lightDir)) * _LightColor0 * attenuation;
			if(dot(normal, IN.lightDir) > 0) col.rgb *= pow(diff, 1); // make the light soft
			else col.rgb = 0;


			float3 R = normalize(-IN.worldLightDir + 2.0 * IN.worldNormal * NdotL);
			float3 spec = pow(max(0, dot(R, worldViewDir)), _Glossiness * 1000)*_LightColor0 *_Glossiness * attenuation;
			col.rgb += max(0, spec);
			return col;
		}
			ENDCG
		}
		Pass
		{
			Tags{ "LightMode" = "ShadowCaster" }

			CGPROGRAM
			#pragma vertex vert2
			#pragma fragment frag2
			#pragma multi_compile_shadowcaster

			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 texcoord : TEXCOORD0;
			};

			struct v2f2
			{
				V2F_SHADOW_CASTER;
			};

			v2f2 vert2(appdata v)
			{
				v2f2 o;
				TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
					return o;
			}

			fixed4 frag2(v2f2 i) : SV_Target
			{
				SHADOW_CASTER_FRAGMENT(i)
			}
			ENDCG
		}
    }
    FallBack "Diffuse"
}




