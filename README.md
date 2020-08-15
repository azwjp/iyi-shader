# iYi Shader
The shader for Akane Sayama's 3D toon model on Unity.
My avatar is an anime-like 3D model imaging figures.
The nose and mouth are more detailed than usual toon avatars, but it causes that the toon shaders work badly; ugly shadows appear on the face, and mouth and nose disappeared.

The aim is to show my anime-like avatar better everywhere with any light: natural environment, only a strong point light, many lights, a directional light without the environment light, or darker rooms.

Additionally, and it has also useful features that the Standard Shader has.
Most toon shaders have fewer features because they're light-weighted to use in low-resolution like social virtual ecosystems such as VRChat.
But when the users use a shader in a high-resolution environment including recording video or standalone games, the detailed features make the appearance greater.

## Specification
This shader has many features.
Like most other shaders, this supports two or more lights. Also, the meshes using this cast shadows onto the other objects and receive the shadows.

### Weak Shadow
This shader draws shadow softly but clearly like a toon rendering, but it is not completely stepped. Some shadow will be graduated.
And to better shadow for avatars, the shadows don't change only the brightness, but also the intensity. This works better on human skin.

The shader is lit. Lights change the brightness of meshes. However, the color won't be completely blackened due to the effect of weakening shadow.

### Secondary Map
The shader supports a secondary map like the Standard Shader.
You can use the first map for the whole surface: weaving cloth or dents on a  panel. And the second for the detail of textures: wrinkles on the skin or textures of cloth.

### Normal Map
Nothing to be said, the shader supports normal maps.

### Ambient Occlusion

### Transparent 
You can change the rendering mode from opaque to transparent. 

### Spectroscopy


## Installation
Copy and put the shader file and Editor folder into your asset folder.

## License
MIT