//
//  bsdf_shading.metal
//  Pollux
//
//  Created by Youssef Kamal Victor on 11/22/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//


#include "bsdf_shading_header.metal"

using namespace metal;


void SnS_diffuse(device Ray& ray,
                 thread Intersection& isect,
                 thread Material &m,
                 thread Loki& rng,
                 thread float& pdf) {
    
    const float3 n  = isect.normal;
    const float3 wo = -ray.direction;
    
    
    // Material's color divided `R` which in this case is InvPi
    float3 f = m.color * InvPi;
    
    //This is lambert factor for light attenuation
    float lambert_factor = fabs(dot(n, wo));
    
    //PDF Calculation
    float dotWo = dot(n, wo);
    float cosTheta = fabs(dotWo) * InvPi;
    pdf = cosTheta;
    
    if (abs(pdf) < ZeroEpsilon) {
        ray.idx_bounces[2] = 0;
        return;
    }
    
    float3 integral = (f * lambert_factor)
                            / pdf;
    ray.color *= integral;
    
    //Scatter the Ray
    ray.origin = isect.point + n*EPSILON;
    ray.direction = cosRandomDirection(n, rng);
    ray.idx_bounces[2]--;
}

void SnS_specular(device Ray& ray,
                  thread Intersection& isect,
                  thread Material &m,
                  thread Loki& rng,
                  thread float& pdf) {
    // TODO: Add Specular BSDF Interaction
}

void SnS_fresnel(device Ray& ray,
                 thread Intersection& isect,
                 thread Material &m,
                 thread Loki& rng,
                 thread float& pdf) {
    // TODO: Add Fresnel BSDF Interaction
}

void SnS_refract(device Ray& ray,
                 thread Intersection& isect,
                 thread Material &m,
                 thread Loki& rng,
                 thread float& pdf){
    float3 refractedRay;
    if (isect.outside) {
        refract(ray.direction, isect.normal, 1.f / m.index_of_refraction, refractedRay);
    } else {
        refract(ray.direction, isect.normal, m.index_of_refraction, refractedRay);
    }
    ray.origin = isect.point + refractedRay * 0.1;
    ray.color *= m.color;
    ray.direction = refractedRay;
    ray.idx_bounces[2]--;
    
}

void SnS_reflect(device Ray& ray,
                 thread Intersection& isect,
                 thread Material &m,
                 thread Loki& rng,
                 thread float& pdf){
    ray.origin = isect.point + isect.normal * EPSILON;
    ray.color *= m.color;
    float3 reflectedRay;
    reflect(ray.direction, isect.normal, reflectedRay);
    ray.direction = reflectedRay;
    ray.idx_bounces[2]--;
}

/**************************
 **************************
 ***** HELPER METHODS *****
 **************************
 **************************/

float3 cosRandomDirection(const float3 normal,
                          thread Loki& rng) {
    float up = sqrt(rng.rand()); // cos(theta)
    float over = sqrt(1 - up * up); // sin(theta)
    float around = rng.rand() * TWO_PI;
    
    // Find a direction that is not the normal based off of whether or not the
    // normal's components are all equal to sqrt(1/3) or whether or not at
    // least one component is less than sqrt(1/3). Taken from CUDA Pathtracer.
    // Originally learned from Peter Kutz.
    
    float3 directionNotNormal;
    if (abs(normal.x) < SQRT_OF_ONE_THIRD) {
        directionNotNormal = float3(1, 0, 0);
    }
    else if (abs(normal.y) < SQRT_OF_ONE_THIRD) {
        directionNotNormal = float3(0, 1, 0);
    }
    else {
        directionNotNormal = float3(0, 0, 1);
    }
    
    // Use not-normal direction to generate two perpendicular directions
    float3 perpendicularDirection1 =
    normalize(cross(normal, directionNotNormal));
    float3 perpendicularDirection2 =
    normalize(cross(normal, perpendicularDirection1));
    
    return up * normal
    + cos(around) * over * perpendicularDirection1
    + sin(around) * over * perpendicularDirection2;
}
