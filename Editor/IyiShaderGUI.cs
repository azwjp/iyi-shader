using UnityEngine;
using UnityEditor;
using System;

public class IyiShaderGUI : ShaderGUI
{
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        var property = FindProperty("_RenderingMode", properties);
        var renderingMode = (RenderingMode)property.floatValue;

        using (var scope = new EditorGUI.ChangeCheckScope())
        {
            renderingMode = (RenderingMode)EditorGUILayout.Popup("Rendering Mode", (int)renderingMode, Enum.GetNames(typeof(RenderingMode)));

            if (scope.changed)
            {
                property.floatValue = (int)renderingMode;
                foreach (Material material in property.targets)
                {
                    SetRenderingMode(material, renderingMode);
                }
            }
        }

        base.OnGUI(materialEditor, properties);
    }

    public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
    {
        base.AssignNewShaderToMaterial(material, oldShader, newShader);

        SetRenderingMode(material, (RenderingMode)material.GetInt("_RenderingMode"));
    }

    static void SetRenderingMode(Material material, RenderingMode renderingMode)
    {
        switch (renderingMode)
        {
            case RenderingMode.Opaque:
                material.SetOverrideTag("RenderType", "Opaque");
                material.SetOverrideTag("Queue", "Geometry");
                material.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Geometry;
                material.SetInt("_BlendA", (int)UnityEngine.Rendering.BlendMode.One);
                material.SetInt("_BlendB", (int)UnityEngine.Rendering.BlendMode.Zero);
                return;
            case RenderingMode.Transparent:
                material.SetOverrideTag("RenderType", "Transparent");
                material.SetOverrideTag("Queue", "Transparent");
                material.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
                material.SetInt("_BlendA", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
                material.SetInt("_BlendB", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                return;
            default:
                throw new Exception();
        }
    }

    enum RenderingMode
    {
        Opaque,
        Transparent,
    }
}
