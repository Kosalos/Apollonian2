// https://github.com/portsmouth/snelly (under fractals: apollonian_pt.html)
// also visit: http://paulbourke.net/fractals/apollony/
// lighting effects: https://github.com/shockham/mandelbulb

#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

constant int MAX_MARCHING_STEPS = 255;
constant float MIN_DIST = 0.0;
constant float MAX_DIST = 20; //100.0;
constant float EPSILON = 0.0001;
constant float N_EPSILON = 0.001;

float3 toRectangular(float3 sph) {
    float ss = sph.x * sin(sph.z);
    return float3( ss * cos(sph.y), ss * sin(sph.y), sph.x * cos(sph.z));
}

float3 toSpherical(float3 rec) {
    return float3(length(rec),
                  atan2(rec.y,rec.x),
                  atan2(sqrt(rec.x*rec.x+rec.y*rec.y), rec.z));
}

float scene(float3 pos,Control control) {
    const float PI = 3.1415926;
    float scale = 0.001 + control.dali;
    
    float s = 1.0;
    float aa = control.multiplier * 100;
    float t = 1.0 + 0.25 * cos(0.02 * PI * aa * (pos.z - pos.x) / scale);
    
    for (int i=0; i<10; i++) {
        pos = -1.0 + 2.0 * fract(0.5 * pos + 0.5);
        float r2 = dot(pos,pos);
        float k = t/r2;
        pos *= k;
        s *= k;
    }
    
    return 1.5 * (0.25 * abs(pos.y) / (s * scale) );
}

float shortest_dist(float3 eye, float3 marchingDirection, Control control) {
    float start = MIN_DIST;
    float end = MAX_DIST;
    float depth = start;
    
    for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
        float dist = scene(eye + depth * marchingDirection,control);
        if (dist < control.minDist) {
            return depth;
        }
        
        depth += dist;
        
        if (depth >= end) {
            return end;
        }
    }
    return end;
}

float3 estimate_normal(float3 p, Control control) {
    return normalize(float3(
                            scene(float3(p.x + N_EPSILON, p.y, p.z),control) - scene(float3(p.x - N_EPSILON, p.y, p.z),control),
                            scene(float3(p.x, p.y + N_EPSILON, p.z),control) - scene(float3(p.x, p.y - N_EPSILON, p.z),control),
                            scene(float3(p.x, p.y, p.z  + N_EPSILON),control) - scene(float3(p.x, p.y, p.z - N_EPSILON),control)  ));
}

float3 phong_contrib
(
 float3 diffuse,
 float3 specular,
 float  alpha,
 float3 p,
 float3 eye,
 float3 lightPos,
 float3 lightIntensity,
 Control control
 ) {
    float3 N = estimate_normal(p,control);
    float3 L = normalize(lightPos - p);
    float3 V = normalize(eye - p);
    float3 R = normalize(reflect(-L, N));
    
    float dotLN = dot(L, N);
    float dotRV = dot(R, V);
    
    if (dotLN < 0.0) {
        // Light not visible from this point on the surface
        return float3(0.0, 0.0, 0.0);
    }
    
    if (dotRV < 0.0) {
        // Light reflection in opposite direction as viewer, apply only diffuse
        // component
        return lightIntensity * (diffuse * dotLN);
    }
    return lightIntensity * (diffuse * dotLN + specular * pow(dotRV, alpha));
}

float calc_AO(float3 pos, float3 nor, Control control) {
    float occ = 0.0;
    float sca = 1.0;
    for(int i=0; i<5; i++) {
        float hr = 0.01 + 0.12*float(i)/4.0;
        float3 aopos =  nor * hr + pos;
        float dd = scene(aopos,control);
        occ += -(dd-hr)*sca;
        sca *= 0.95;
    }
    return clamp( 1.0 - 3.0*occ, 0.0, 1.0 );
}

float soft_shadow(float3 camera, float3 light, float mint, float maxt, float k, Control control) {
    float res = 1.0;
    for(float t = mint; t < maxt;) {
        float h = scene(camera + light * t,control);
        if( h < 0.001) return 0.0;
        
        res = min(res, k * h / t);
        t += h;
    }
    return res;
}

float3 lighting(float ambient, float diffuse, float specular, float harshness, float3 p, float3 eye, Control control) {
    float3 color = float3(ambient);
    float3 normal = estimate_normal(p,control);
    
    color = mix(color, normal, control.lighting.saturation);
    color = mix(color, float3(1.0 - smoothstep(0.0, 0.6, distance(float2(0.0), p.xy))), control.lighting.gamma);
    
    float occ = calc_AO(p, normal,control);
    
    float3 light1Pos = control.light;
    float3 light1Intensity = float3(1); // 0.4);
    
    color += phong_contrib(diffuse, specular, harshness, p, eye, light1Pos, light1Intensity, control);
    color = mix(color, color * occ * soft_shadow(p, normalize(light1Pos), control.lighting.shadowMin, control.lighting.shadowMax * 10, control.lighting.shadowMult * 30,control), control.lighting.shadowAmt);

    return color;
}

kernel void rayMarchShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 constant Control &control [[buffer(0)]],
 uint2 p [[thread_position_in_grid]])
{
    float2 uv = float2(float(p.x) / float(control.xSize), float(p.y) / float(control.ySize));     // map pixel to 0..1
    float3 viewVector = control.focus - control.camera;
    
    float3 topVector = toSpherical(viewVector);
    topVector.z += 1.5708;
    topVector = toRectangular(topVector);
    float3 sideVector = cross(viewVector,topVector);
    sideVector = normalize(sideVector) * length(topVector);
    
    float3 color = float3(0,0,0);
    
    float dx = control.zoom * (uv.x - 0.5);
    float dy = (-1.0) * control.zoom * (uv.y - 0.5);
    float3 direction = normalize((sideVector * dx) + (topVector * dy) + viewVector);
    
    float dist = shortest_dist(control.camera,direction,control);
    
    if (dist <= MAX_DIST - EPSILON) {
        float3 p = control.camera + dist * direction;
        color = lighting(control.lighting.ambient,control.lighting.diffuse,control.lighting.specular,(1 - control.lighting.harshness) * 10, p, control.camera,control);
    }
    
    outTexture.write(float4(color,1),p);
}

