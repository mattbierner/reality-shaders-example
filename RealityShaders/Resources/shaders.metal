#include <metal_stdlib>
using namespace metal;

#include <SceneKit/scn_metal>

struct VertexInput {
    float3 position  [[attribute(SCNVertexSemanticPosition)]];
    float3 normal [[attribute(SCNVertexSemanticNormal)]];
    float2 texCoords [[attribute(SCNVertexSemanticTexcoord0)]];
};

struct NodeBuffer {
    float4x4 modelViewProjectionTransform;
    float4x4 modelViewTransform;
};


/**
* Map a position in model space to a texture coordinate for sampling from the background.
*
* This is copied from https://developer.apple.com/documentation/arkit/tracking_and_visualizing_faces
*/
float2 getBackgroundCoordinate(
                      constant float4x4& displayTransform,
                      constant float4x4& modelViewTransform,
                      constant float4x4& projectionTransform,
                      float4 position) {
    // Transform the vertex to the camera coordinate system.
    float4 vertexCamera = modelViewTransform * position;
    
    // Camera projection and perspective divide to get normalized viewport coordinates (clip space).
    float4 vertexClipSpace = projectionTransform * vertexCamera;
    vertexClipSpace /= vertexClipSpace.w;
    
    // XY in clip space is [-1,1]x[-1,1], so adjust to UV texture coordinates: [0,1]x[0,1].
    // Image coordinates are Y-flipped (upper-left origin).
    float4 vertexImageSpace = float4(vertexClipSpace.xy * 0.5 + 0.5, 0.0, 1.0);
    vertexImageSpace.y = 1.0 - vertexImageSpace.y;
    
    // Apply ARKit's display transform (device orientation * front-facing camera flip).
    return (displayTransform * vertexImageSpace).xy;
}


/// Region:  Geometry Effect
/// This uses the vertex shader to distort the surface.

struct GeometryEffectInOut {
    float4 position [[ position ]];
    float2 backgroundTextureCoords;
};

vertex GeometryEffectInOut geometryEffectVertextShader(VertexInput in [[ stage_in ]],
                                  constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                                  constant NodeBuffer& scn_node [[ buffer(1) ]],
                                  constant float4x4& u_displayTransform [[buffer(2)]],
                                  constant float& u_time [[buffer(3)]])
{
    GeometryEffectInOut out;

    // Compute the texture coordinates used to read from the background image
    out.backgroundTextureCoords = getBackgroundCoordinate(
                                   u_displayTransform,
                                   scn_node.modelViewTransform,
                                   scn_frame.projectionTransform,
                                   float4(in.position, 1.0));

    // Distort the geometry in model space using a simple 3D sin wave
    float waveHeight = 0.25;
    float waveFrequency = 20.0;

    float len = length(in.position.xy);

    float blending = max(0.0, 0.5 - len);
    in.position.z += sin(len * waveFrequency + u_time * 5) * waveHeight * blending;
    
    // And then project the geometry
    out.position = scn_node.modelViewProjectionTransform * float4(in.position, 1.0);
      
    return out;
}

fragment float4 geometryEffectFragmentShader(GeometryEffectInOut in [[ stage_in] ],
                                 texture2d<float, access::sample> diffuseTexture [[texture(0)]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    // Now just read from the background image
    float3 color = diffuseTexture.sample(textureSampler, in.backgroundTextureCoords).rgb;
    return float4(color, 1.0);
}


/// Region: Image Effect
/// This uses a fragement shader to distort the surface

struct ImageEffectInOut {
    float4 position [[ position ]];
    float2 textureCoords;
    float3 modelPosition;
};


vertex ImageEffectInOut imageEffectVertextShader(VertexInput in [[ stage_in ]],
                                  constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                                  constant NodeBuffer& scn_node [[ buffer(1) ]],
                                  constant float4x4& u_displayTransform [[buffer(2)]],
                                  constant float& u_time [[buffer(3)]])
{
    ImageEffectInOut out;

    // Before we computed the background texture coordinates in the vertex shader.
    // This time we instead compute them in the fragement shader. This makes distoring
    // the texture coordinates far easier
    out.textureCoords = in.texCoords;

    // Also write out the position in model space to use for computing the background texture coordinates.
    out.modelPosition = in.position;

    out.position = scn_node.modelViewProjectionTransform * float4(in.position, 1.0);
      
    return out;
}

fragment float4 imageEffectFragmentShader(ImageEffectInOut in [[ stage_in] ],
                                 texture2d<float, access::sample> diffuseTexture [[texture(0)]],
                                 constant SCNSceneBuffer& scn_frame [[buffer(0)]],
                                 constant NodeBuffer& scn_node [[ buffer(1) ]],
                                 constant float4x4& u_displayTransform [[buffer(2)]],
                                 constant float& u_time [[buffer(3)]])
{
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    // Distort the texture coordinates using a simple sine effect.
    float waveFrequency = 15;
    float waveSize = 0.05;
    float radius = 0.3;
    
    float blending = 1.0 - clamp((max(radius, length(in.textureCoords - 0.5)) - radius) / (0.5 - radius), 0.0, 1.0);
    float2 textureCoordinateDelta = float2(0.0, sin(in.textureCoords.x * waveFrequency + u_time * 5) * waveSize * blending);
    
    // Now we compute the texture coordinates to use for reading from the background.
    // However we feed in the transformed coordinate to apply the effect.
    //
    // If the plane was a different size than 1x1, we'd want to scale the textureCoordinateDelta
    float2 coords = getBackgroundCoordinate(
        u_displayTransform,
        scn_node.modelViewTransform,
        scn_frame.projectionTransform,
        float4(in.modelPosition + float3(textureCoordinateDelta, 0.0), 1.0));
    
    float3 color = diffuseTexture.sample(textureSampler, coords).rgb;
    return float4(color, 1.0);
}
