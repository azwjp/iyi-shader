﻿Shader "iYiShader/iYiShader-VRChat"
{
    Properties
	{
		[HideInInspector] _RenderingMode("Rendering Mode", Int) = 0
		[HideInInspector] _BlendA("Blend Source", Int) = 1.0
		[HideInInspector] _BlendB("Blend Distination", Int) = 0.0

		[Header(Rendering)]
		[Enum(UnityEngine.Rendering.CullMode)]_CullMode("Cull Mode", Int) = 0

		[Header(Texture)]
		[MainColor]_Color("Color", Color) = (1, 1, 1, 1)
		[MainTexture]_MainTex("Albedo (RGB)", 2D) = "white" {}
		[Normal]_Normal("Normal", 2D) = "bump" {}
        _NormalStrength ("NormalStrength", Range(0,100)) = 5
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
		_Specular ("Specular", Range(0,1)) = 0.0

		_EmissionMagnification("Emission Magnification", Range(0,10)) = 0
		
		_Masks("Masks", 2D) = "black" {}

		[Header(Secondary Map)]
		_MainTex2("Albedo (RGB)", 2D) = "gray" {}
		_SecondaryMapStrength("Secondary Map Strength", Range(0,2)) = 1
		_SecondaryMapMask("Secondary Map Mask", 2D) = "white" {}
		[Normal]_Normal2("Normal2", 2D) = "bump" {}
		_SecondaryNormalMapStrength("Secondary Normal Map Strength", Range(0,100)) = 1


		[Header(Additional settings)]
		[Ambient Occlusion]_AmbientOcclusion("Ambient Occlusion", 2D) = "bump" {}

		[Header(Fresnel Schlick approximation )]
		_FresnelColor("Fresnel Color", Color) = (1,1,1,0)
		[PowerSlider(2)] _FresnelRimCoefficient("Rim Coefficient", Range(0.0, 1.0)) = 1
		[PowerSlider(2)] _FresnelBaseCoefficient("Base Coefficient", Range(0.0, 1.0)) = 0
    }
    SubShader
    {
		Tags{ "RenderType" = "Opaque"}
		Blend[_BlendA][_BlendB]
		Cull[_CullMode]
        LOD 200

        CGINCLUDE
			#include "UnityPBSLighting.cginc"
			#include "AutoLight.cginc"
			#include "UnityCG.cginc"

			fixed4 _Color;
			sampler2D _MainTex;
			half4 _MainTex_ST;
			sampler2D _Normal;
			half4 _Normal_ST;
			half _NormalStrength;
			half _Glossiness;
			half _Metallic;
			half _Specular;
			fixed _EmissionMagnification;
			sampler2D _Masks;
			half4 _Masks_ST;
			sampler2D _MainTex2;
			half4 _MainTex2_ST;
			half _SecondaryMapStrength;
			sampler2D _SecondaryMapMask;
			half4 _SecondaryMapMask_ST;
			sampler2D _Normal2;
			half4 _Normal2_ST;
			sampler2D _AmbientOcclusion;
			half4 _AmbientOcclusion_ST;
			fixed4  _FresnelColor;
			half _FresnelRimCoefficient;
			half _FresnelBaseCoefficient;

			struct v2f
			{
				UNITY_POSITION(pos);
				float2 uv : TEXCOORD0; // _MainTex
				float3 worldPos : TEXCOORD1;
				float3 ambient: TEXCOORD2;
				float3 lightDir : TEXCOORD3;
				UNITY_SHADOW_COORDS(4)
				float3 viewDir : TEXCOORD5;
				float3 worldViewDir : TEXCOORD6;
				float3 worldNormal : TEXCOORD7;
			};

			inline float4x4 InvTangentMatrix(float3 tan, float3 bin, float3 nor)
			{
				return transpose(float4x4(
					float4(tan, 0),
					float4(bin, 0),
					float4(nor, 0),
					float4(0, 0, 0, 1)
					));
			}

			inline float4x4 GetInvTangentMatrix(appdata_full v)
			{
				float3 n = normalize(v.normal);
				return InvTangentMatrix(v.tangent, cross(n, v.tangent), n);
			}

			inline half3 Phong(fixed lightNormalProduct, half3 normal, half3 lightDir, half3 viewDir, half glossiness, fixed atten, half3 _LightColor0)
			{
				half NdotL = max(0, lightNormalProduct);
				float3 R = reflect(-lightDir, normal);
				float3 specular = pow(max(0, dot(R, viewDir)), glossiness * 100) * glossiness * atten * _LightColor0;
				return max(0, specular);
			}

			inline half3 ModColor(fixed lightNormalProduct, half4 col, half ambient, fixed atten, half3 _LightColor0)
			{
				fixed lanbert = saturate(lightNormalProduct * 0.25 + 0.75); // make labert shadows softer
				fixed lanbert2 = pow(lightNormalProduct, 0.5); // make the boundary of shadows clearer
				fixed3 shadowAttenuation = (lanbert + 2 * lanbert2) / 3 * atten * _LightColor0;
				fixed3 shadow = shadowAttenuation / 2 + 0.5;
				fixed3 shadow2 = pow(shadowAttenuation, 0.3);

				// 1st pow: high intensity shadow, avoid gray ones
				//		to make the intensity of colors softer, make the value decrease in it
				// though this shader avoid to make the charactor agly in dark places,
				// ambient light makes them saturated white. the last pow() makes an ambient light softer
				return (pow(col.rgb, 1 / pow(shadow, 0.5))) * ((2 * shadow + 1 * shadow2) / 3 + pow(ambient, 3)) * col.a;
			}

			inline half3 Spectroscopy(half3 col,fixed mag, fixed3 viewDir, fixed3 normal, fixed3 pos)
			{
				fixed theta = dot(normal, viewDir) * (pos.x + pos.y + pos.z) / 30 + (normal.x + normal.y + normal.z);

				fixed s = sin(theta*1.41421356);
				fixed c = cos(theta*0.6);
				return half3(c, s, 1 - c - s) * mag;
			}

            inline float3 boxProjection(float3 normalizedDir, float3 worldPosition, float4 probePosition, float3 boxMin, float3 boxMax)
            {
                #if UNITY_SPECCUBE_BOX_PROJECTION
                    if (probePosition.w > 0) {
                        float3 magnitudes = ((normalizedDir > 0 ? boxMax : boxMin) - worldPosition) / normalizedDir;
                        float magnitude = min(min(magnitudes.x, magnitudes.y), magnitudes.z);
                        normalizedDir = normalizedDir* magnitude + (worldPosition - probePosition);
                    }
            	#endif

            	return normalizedDir;
            }
			fixed4 frag(v2f IN, half ASEVFace : VFACE) : SV_Target{
				// GI
				SurfaceOutputStandard o;
				UNITY_INITIALIZE_OUTPUT(SurfaceOutputStandard, o);
				o.Albedo = 0.0;
				o.Emission = 0.0;
				o.Alpha = 0.0;
				o.Occlusion = 1.0;
				o.Normal = IN.worldNormal;

				UnityGI gi;
				UNITY_INITIALIZE_OUTPUT(UnityGI, gi);
				gi.indirect.diffuse = 0;
				gi.indirect.specular = 0;
				gi.light.color = 0;
				gi.light.dir = half3(0, 1, 0);
				gi.light.ndotl = LambertTerm(o.Normal, gi.light.dir);

				UnityGIInput giInput;
				UNITY_INITIALIZE_OUTPUT(UnityGIInput, giInput);
				giInput.light = gi.light;
				giInput.worldPos = IN.worldPos;
				giInput.worldViewDir = IN.worldViewDir;
				giInput.atten = 1;

				#if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
					giInput.lightmapUV = IN.lmap;
				#else
					giInput.lightmapUV = 0.0;
				#endif

					giInput.ambient = IN.ambient;

					giInput.probeHDR[0] = unity_SpecCube0_HDR;
					giInput.probeHDR[1] = unity_SpecCube1_HDR;

				#if UNITY_SPECCUBE_BLENDING || UNITY_SPECCUBE_BOX_PROJECTION
					giInput.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
				#endif

				#if UNITY_SPECCUBE_BOX_PROJECTION
					giInput.boxMax[0] = unity_SpecCube0_BoxMax;
					giInput.probePosition[0] = unity_SpecCube0_ProbePosition;
					giInput.boxMax[1] = unity_SpecCube1_BoxMax;
					giInput.boxMin[1] = unity_SpecCube1_BoxMin;
					giInput.probePosition[1] = unity_SpecCube1_ProbePosition;
				#endif

				LightingStandard_GI(o, giInput, gi);


				fixed4 masks = tex2D(_Masks, IN.uv * _Masks_ST.xy + _Masks_ST.zw);

				// Albedo comes from a texture tinted by color
				fixed4 mainTex = tex2D(_MainTex, IN.uv * _MainTex_ST.xy + _MainTex_ST.zw) * _Color;
				fixed4 col = mainTex;
				fixed smMask = _SecondaryMapStrength * (tex2D(_SecondaryMapMask, IN.uv * _SecondaryMapMask_ST.xy + _SecondaryMapMask_ST.zw) * _Color).r;
				
				col.rgb = clamp(col.rgb
						* (tex2D(_MainTex2, IN.uv * _MainTex2_ST.xy + _MainTex2_ST.zw).rgb * smMask + (1 - smMask) / 2) * 2
				, 0.01, 0.99);

				half3 normal = pow(UnpackScaleNormal(tex2D(_Normal, IN.uv * _Normal_ST.xy + _Normal_ST.zw), 1)
						+ UnpackScaleNormal(tex2D(_Normal2, IN.uv * _Normal2_ST.xy + _Normal2_ST.zw), 1)
				, 1);
				normal.z /= _NormalStrength;
				normal = normalize(normal);

				UNITY_LIGHT_ATTENUATION(atten, IN, IN.worldPos);
				fixed lightProduct = max(0, dot(normal, IN.lightDir));
				fixed lightProductDiff = saturate(lightProduct/dot(fixed3(0,0,1), IN.lightDir));
				IN.ambient *= tex2D(_AmbientOcclusion, IN.uv * _AmbientOcclusion_ST.xy + _AmbientOcclusion_ST.zw);


				col.rgb *=  (1 + gi.indirect.diffuse);
				col.rgb = col.rgb +  (col.rgb) * (gi.indirect.specular) * _Specular;
				col.rgb = saturate(col.rgb);

				col.rgb = ModColor(lightProduct, col, IN.ambient, atten, _LightColor0);
				half fresnel = _FresnelBaseCoefficient + (1.0 - _FresnelRimCoefficient) * pow(1.0 - max(0, dot(normal, IN.viewDir)), 5);
				col.rgb = saturate(col.rgb + fresnel * _FresnelColor);

				fixed mag = length(col.rgb) * 0.1;
				col.rgb *= 1 - mag / 2;
				col.rgb += Spectroscopy(col.rgb, mag, IN.viewDir, normal, IN.pos) * masks.b;

				// if over 1, the pixel emits glossily
				half glossiness = _Glossiness * masks.a;
				col.rgb = pow(saturate(col.rgb + Phong(lightProduct, normal, IN.lightDir, IN.viewDir, glossiness, atten, _LightColor0)), 1);

				// Rreflection
				half3 worldViewDir = normalize(_WorldSpaceCameraPos - IN.worldPos);
				half3 reflDir = reflect(-worldViewDir, IN.worldNormal);

				half3 reflDir0 = boxProjection(reflDir, IN.worldPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
				half3 reflDir1 = boxProjection(reflDir, IN.worldPos, unity_SpecCube1_ProbePosition, unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);

				half4 refColor0 = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflDir0, 0);
				refColor0.rgb = DecodeHDR(refColor0, unity_SpecCube0_HDR);

				// SpecCube1のサンプラはSpecCube0のものを使う
				half4 refColor1 = UNITY_SAMPLE_TEXCUBE_SAMPLER_LOD(unity_SpecCube1, unity_SpecCube0, reflDir1, 0);
				refColor1.rgb = DecodeHDR(refColor1, unity_SpecCube1_HDR);
								
				// emission
				half metalic = _Metallic + masks.r;
				col.rgb += mainTex * masks.g * _EmissionMagnification;

				col.rgb = col.rgb * (1 - metalic + glossiness + refColor0.rgb * _Specular);
				 //col.rgb = gi.indirect.specular + 0.5;

				return col;
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
			
			
			// Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
			// See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
			// #pragma instancing_options assumeuniformscaling
			UNITY_INSTANCING_BUFFER_START(Props)
				// put more per-instance properties here
			UNITY_INSTANCING_BUFFER_END(Props)

			v2f vert(appdata_full v) {
				v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv.xy = TRANSFORM_TEX(v.texcoord, _MainTex);
				o.worldPos.xyz = mul(unity_ObjectToWorld, v.vertex).xyz;
				UNITY_TRANSFER_LIGHTING(o, v.texcoord1.xy); // pass shadow and, possibly, light cookie coordinates to pixel shader
				o.worldNormal = UnityObjectToWorldNormal(v.normal);

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
				TANGENT_SPACE_ROTATION;
				o.lightDir = normalize(mul(rotation, ObjSpaceLightDir(v.vertex)));
				o.viewDir = normalize(mul(rotation, ObjSpaceViewDir(v.vertex)));

				return o;
			}

			ENDCG
		}

		Pass {
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

			v2f vert(appdata_full v)
			{
				v2f o = (v2f)0;

				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex);
				o.worldNormal = UnityObjectToWorldNormal(v.normal);

				TANGENT_SPACE_ROTATION;
				o.lightDir = normalize(mul(rotation, ObjSpaceLightDir(v.vertex)));
				o.viewDir = normalize(mul(rotation, ObjSpaceViewDir(v.vertex)));

				return o;
			}
			ENDCG
		}

		Pass
		{
			Tags{ "LightMode" = "ShadowCaster" }
			ZWrite Off

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

	CustomEditor "IyiShaderGUI"
}




