// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "iYiShader/iYiShader"
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
		[Normal]_Normal("Normal", 2D) = "bump" {}
        [MainTexture]_MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0


		[Header(Secondary Map)]
		_MainTex2("Albedo (RGB)", 2D) = "gray" {}
		_SecondaryMapStrength("Smoothness", Range(0,4)) = 2
		[Normal]_Normal2("Normal2", 2D) = "bump" {}


		[Header(Additional settings)]
		[Ambient Occlusion]_AmbientOcclusion("Ambient Occlusion", 2D) = "bump" {}
		[Toggle(USE_SPECTROSCOPY)]_Spectroscopy("Spectroscopy", Float) = 0

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
			#pragma shader_feature USE_SPECTROSCOPY
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

			sampler2D _MainTex;
			half4 _MainTex_ST;
			half _Glossiness;
			half _Metallic;
			fixed4 _Color;
			sampler2D _Normal;
			half4 _Normal_ST;
			sampler2D _MainTex2;
			half4 _MainTex2_ST;
			half _SecondaryMapStrength;
			sampler2D _Normal2;
			half4 _Normal2_ST;
			fixed4  _FresnelColor;
			half _FresnelRimCoefficient;
			half _FresnelBaseCoefficient;
			sampler2D _AmbientOcclusion;
			half4 _AmbientOcclusion_ST;
			
			
			// Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
			// See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
			// #pragma instancing_options assumeuniformscaling
			UNITY_INSTANCING_BUFFER_START(Props)
				// put more per-instance properties here
			UNITY_INSTANCING_BUFFER_END(Props)

			struct v2f
			{
				UNITY_POSITION(pos);
				float2 uv : TEXCOORD0; // _MainTex
				float3 worldNormal : TEXCOORD1;
				float3 worldPos : TEXCOORD8;
				float3 worldLightDir : TEXCOORD2;
				float3 ambient: TEXCOORD3;
				float3 lightDir : TEXCOORD4;
				UNITY_SHADOW_COORDS(5)
				float3 viewDir : TEXCOORD6;
				float3 worldViewDir : TEXCOORD7;
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


				o.worldViewDir = normalize(UnityWorldSpaceViewDir(o.worldPos));
				#ifndef USING_DIRECTIONAL_LIGHT
					o.worldLightDir = normalize(UnityWorldSpaceLightDir(o.worldPos));
				#else
					o.worldLightDir = _WorldSpaceLightPos0.xyz;
				#endif

				// for bamp map
				TANGENT_SPACE_ROTATION;
				o.lightDir = normalize(mul(rotation, ObjSpaceLightDir(v.vertex)));
				o.viewDir = normalize(mul(rotation, ObjSpaceViewDir(v.vertex)));

				return o;
			}

			fixed4 frag(v2f IN, half ASEVFace : VFACE) : SV_Target{
				// Albedo comes from a texture tinted by color
				fixed4 col = tex2D(_MainTex, IN.uv * _MainTex_ST.xy + _MainTex_ST.zw) * _Color;
				half3 second = (tex2D(_MainTex2, IN.uv * _MainTex2_ST.xy + _MainTex2_ST.zw).rgb * _SecondaryMapStrength + (1 - _SecondaryMapStrength)/2) * 2;
				col.rgb = clamp(col.rgb * second, 0.01, 0.99);

				half3 normal = normalize(pow((UnpackScaleNormal(tex2D(_Normal, IN.uv * _Normal_ST.xy + _Normal_ST.zw), 1) + UnpackScaleNormal(tex2D(_Normal2, IN.uv * _Normal2_ST.xy + _Normal2_ST.zw), 1)) , 1));



				half fresnel = _FresnelBaseCoefficient + (1.0 - _FresnelRimCoefficient) * pow(1.0 - max(0, dot(normal, IN.viewDir)), 5);
				col.rgb = saturate(col.rgb + fresnel * _FresnelColor);

				UNITY_LIGHT_ATTENUATION(atten, IN, IN.worldPos);
				fixed lightProduct = max(0, dot(normal, IN.lightDir));
				fixed lanbert = saturate(lightProduct *0.25 + 0.75); // make labert shadows softer
				fixed lanbert2 = pow(lightProduct, 0.2); // make the boundary of shadows clearer
				fixed3 shadowAttenuation = ( lanbert +2 * lanbert2) / 3 * atten * _LightColor0;
				fixed3 shadow = shadowAttenuation / 2 + 0.5;
				fixed3 shadow2 = pow(shadowAttenuation, 0.3);
				
				// 1st pow: high intensity shadow, avoid gray ones
				//		to make the intensity of colors softer, make the value decrease in it
				// though this shader avoid to make the charactor agly in dark places,
				// ambient light makes them saturated white. the last pow() makes an ambient light softer
				IN.ambient *= tex2D(_AmbientOcclusion, IN.uv * _AmbientOcclusion_ST.xy + _AmbientOcclusion_ST.zw);
				col.rgb = (pow(col, 1 / pow(shadow, 1))) * ((2*shadow + 1*shadow2)/3 + pow(IN.ambient, 3)) * col.a;


				half NdotL = max(0, lightProduct);
				float3 R = reflect(-IN.lightDir, normal);
				float3 specular = pow(max(0, dot(R, IN.viewDir)), _Glossiness * 100)*_Glossiness * atten * _LightColor0;
				col.rgb += max(0, specular);

				#ifdef USE_SPECTROSCOPY
					fixed mag = length(col.rgb) * 0.05;
					col.rgb *= 1 - mag / 2;
					fixed theta = 30 * dot(normal, IN.viewDir) * atan(IN.pos.x / 50 + IN.pos.y / 50 + IN.pos.z / 50) + IN.worldNormal.x;
					col.r += cos(theta) * mag;
					col.g += sin(theta) * mag;
					col.b += (1 - cos(theta) - sin(theta)) * mag;
				#endif
				
				return col;
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

			struct v2f
			{
				UNITY_POSITION(pos);
				half2 uv : TEXCOORD0;
				half3 worldNormal: TEXCOORD1;
				half3 ambient: TEXCOORD2;
				half3 worldPos: TEXCOORD3;
				float3 lightDir : TEXCOORD4;
				float3 worldLightDir : TEXCOORD5;
				float3 viewDir : TEXCOORD6;
			};

			sampler2D _MainTex;
			half4 _MainTex_ST;
			half _Glossiness;
			half _Metallic;
			fixed4 _Color;
			uniform sampler2D _Normal;
			uniform float4 _Normal_ST;
			uniform float _NormalScale;
			sampler2D _Normal2;
			half4 _Normal2_ST;
			sampler2D _MainTex2;
			half4 _MainTex2_ST;

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
				TANGENT_SPACE_ROTATION;
				o.lightDir = normalize(mul(rotation, ObjSpaceLightDir(v.vertex)));
				o.viewDir = normalize(mul(rotation, ObjSpaceViewDir(v.vertex)));

				return o;
			}

			half4 frag(v2f IN) : COLOR
			{
				fixed4 col = tex2D(_MainTex, IN.uv * _MainTex_ST.xy + _MainTex_ST.zw) * _Color;
				col.rgb = clamp(col.rgb * tex2D(_MainTex2, IN.uv * _MainTex2_ST.xy + _MainTex2_ST.zw).rgb * 2, 0.01, 0.99);

				half3 normal = normalize(pow((UnpackScaleNormal(tex2D(_Normal, IN.uv * _Normal_ST.xy + _Normal_ST.zw), 1) + UnpackScaleNormal(tex2D(_Normal2, IN.uv * _Normal2_ST.xy + _Normal2_ST.zw), 1)) , 1));
				
				UNITY_LIGHT_ATTENUATION(atten, IN, IN.worldPos);

				float3 worldPos = IN.worldPos;
				float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
				half NdotL = max(0, dot(IN.worldNormal, IN.worldLightDir));
				if (NdotL <= 0) {
					atten = 0;
				}

				fixed lightProduct = max(0, dot(normal, IN.lightDir));
				fixed lanbert = saturate(lightProduct *0.25 + 0.75);
				fixed lanbert2 = pow(lightProduct, 0.2);
				fixed3 shadowAttenuation = (lanbert + 2 * lanbert2) / 3 * atten * _LightColor0;
				fixed3 shadow1 = shadowAttenuation / 2 + 0.5;
				fixed3 shadow2 = pow(shadowAttenuation, 0.3);
				col.rgb = (pow(col, 1 / pow(shadow1, 1))) * ((2 * shadow1 + 1 * shadow2) / 3 + pow(IN.ambient, 3)) * atten * _LightColor0 * col.a;
				float3 R = normalize(-IN.worldLightDir + 2.0 * IN.worldNormal * NdotL);
				float3 spec = pow(max(0, dot(R, worldViewDir)), _Glossiness * 1000)*_LightColor0 *_Glossiness * atten;
				col.rgb += max(0, spec);

				#ifdef USE_SPECTROSCOPY
					fixed mag = length(col.rgb) * 0.05;
					col.rgb *= 1 - mag / 2;
					fixed theta = 30 * dot(normal, IN.viewDir) * atan(IN.pos.x / 50 + IN.pos.y / 50 + IN.pos.z / 50) + IN.worldNormal.x;
					col.r += cos(theta) * mag;
					col.g += sin(theta) * mag;
					col.b += (1 - cos(theta) - sin(theta)) * mag;
				#endif
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

	CustomEditor "IyiShaderGUI"
}




