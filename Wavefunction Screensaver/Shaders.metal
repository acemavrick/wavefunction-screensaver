//
//  Shaders.metal
//  Wavefunction Screensaver
//
//  Created by acemavrick on 6/28/25.
//

#include <metal_stdlib>
using namespace metal;

struct WaveUniforms {
    float dx;
    float dt;
    float c;
    float time;
    float damper;
    float padding0; // for alignment
    float2 resolution;
    // for colormap, not used in grey fragment shader
    float4 c0, c1, c2, c3, c4, c5, c6;
};

struct DisturbanceUniforms {
    float2 position;
    float radius;
    float strength;
};

// a struct to pass data from the vertex to the fragment shader
struct VertexOut {
    float4 position [[position]];
};

// vertex shader to draw a full-screen quad
vertex VertexOut waveVertex(uint vertexID [[vertex_id]]) {
    float4 positions[4] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0)
    };
    
    VertexOut out;
    out.position = positions[vertexID];
    return out;
}

kernel void updateWaveState(texture2d<float, access::read> u_p [[texture(0)]],
                            texture2d<float, access::read> u_c [[texture(1)]],
                            texture2d<float, access::read> laplacian [[texture(2)]],
                            texture2d<float, access::write> u_n [[texture(3)]],
                            constant WaveUniforms &uniforms [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= u_n.get_width() || gid.y >= u_n.get_height()) return;

    float laplacianVal = laplacian.read(gid).x;
    float uc = u_c.read(gid).x;
    float up = u_p.read(gid).x;

    float laplacianMultiplier = uniforms.dx > 0.0 ? pow(uniforms.dt * uniforms.c / uniforms.dx, 2.0) : 0.0;

    float val = laplacianMultiplier * laplacianVal + 2.0 * uc - up;
    val *= uniforms.damper;

    u_n.write(float4(val, 0.0, 0.0, 0.0), gid);
}

kernel void addDisturbance(texture2d<float, access::read_write> u_c [[texture(0)]],
                           constant DisturbanceUniforms &disturbance [[buffer(0)]],
                           constant WaveUniforms &uniforms [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= u_c.get_width() || gid.y >= u_c.get_height()) return;

    float dist = distance(float2(gid), disturbance.position);
    if (dist < disturbance.radius) {
        float current_val = u_c.read(gid).x;
        float pulse = disturbance.strength * (0.5 * (cos(dist / disturbance.radius * M_PI_F) + 1.0));
        u_c.write(float4(current_val + pulse, 0.0, 0.0, 0.0), gid);
    }
}

kernel void extractHighlights(texture2d<float, access::read> source [[texture(0)]],
                              texture2d<float, access::write> destination [[texture(1)]],
                              uint2 gid [[thread_position_in_grid]]) {

    if (gid.x >= source.get_width() || gid.y >= source.get_height()) return;

    float height = source.read(gid).x;
    
    // thresholding logic - only keep values that will be bright
    float threshold = 0.1;
    float bright = abs(height) > threshold ? height : 0.0;
    
    destination.write(float4(bright, 0.0, 0.0, 0.0), gid);
}


// map wave height to color
float3 getColorForHeight(float height) {
    float absHeight = abs(height);
    
    // black for very small amplitudes
    if (absHeight < 0.025) {
        return float3(0.0);
    }
    
    // power function to make wave crests brighter and more prominent
    float intensity = pow(absHeight, 0.75);

    float3 color;
    if (height > 0.0) {
        // positive waves: smooth gradient from deep blue to cyan to pure white
        float3 deep_blue = float3(0.0, 0.2, 0.9);
        float3 cyan = float3(0.1, 0.9, 1.0);
        color = mix(deep_blue, cyan, smoothstep(0.0, 0.5, intensity));
        color = mix(color, float3(1.0), smoothstep(0.5, 1.0, intensity));
    } else {
        // negative waves: smooth gradient from deep magenta to hot pink to pure white
        float3 deep_magenta = float3(0.8, 0.0, 0.6);
        float3 hot_pink = float3(1.0, 0.3, 0.7);
        color = mix(deep_magenta, hot_pink, smoothstep(0.0, 0.5, intensity));
        color = mix(color, float3(1.0), smoothstep(0.5, 1.0, intensity));
    }
    
    return color * intensity;
}

// filmic tone mapping operator to create a cinematic look
float3 filmicToneMap(float3 color) {
    color = max(float3(0.0), color - 0.004);
    color = (color * (6.2 * color + 0.5)) / (color * (6.2 * color + 1.7) + 0.06);
    return color;
}

fragment float4 waveFragment(VertexOut in [[stage_in]],
                             texture2d<float, access::read> waveTexture [[texture(0)]],
                             texture2d<float, access::read> bloomTexture [[texture(1)]])
{
    uint2 loc = uint2(in.position.xy);
    if (loc.x >= waveTexture.get_width() || loc.y >= waveTexture.get_height()) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float waveHeight = waveTexture.read(loc).r;
    float3 baseColor = getColorForHeight(waveHeight);

    // sample the pre-blurred bloom texture and color it
    float bloomAmount = bloomTexture.read(loc).r;
    float3 bloomColor = getColorForHeight(bloomAmount) * 1.5; // bloom intensity can be tweaked

    // combine and finalize color
    float3 finalColor = baseColor + bloomColor;
    finalColor = filmicToneMap(finalColor);
    
    return float4(finalColor, 1.0);
}