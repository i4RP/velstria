#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

namespace first_person {
constexpr sampler materialSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

// custom: x = NDC upper boundary, y = texture flags, z = original emissive intensity, w = capture mask.
inline half visibility(realitykit::surface_parameters params) {
    float boundary = params.uniforms().custom_parameter().x;
    if (boundary >= 1.0) { return 1.0h; }
    float4 world = float4(params.geometry().world_position(), 1.0);
    float4 clip = params.uniforms().view_to_projection() * params.uniforms().world_to_view() * world;
    if (clip.w <= 0.0 || !all(isfinite(clip))) { discard_fragment(); }
    float y = clip.y / clip.w;
    if (y > boundary) { discard_fragment(); }
    // 0.3% of the screen, entirely INSIDE the permitted band. Never expands its coverage.
    return half(1.0 - smoothstep(boundary - 0.006, boundary, y));
}

inline void shade(realitykit::surface_parameters params, bool unlit) {
    half keep = visibility(params);
    float4 cp = params.uniforms().custom_parameter();
    uint flags = uint(cp.y);
    float2 uv = params.geometry().uv0();
    if (flags & 1u) { uv.y = 1.0 - uv.y; }
    auto tex = params.textures();
    auto mc = params.material_constants();
    auto surface = params.surface();
    half4 base = (flags & 2u) ? tex.base_color().sample(materialSampler, uv) : half4(1.0h);
    half opacity = half(mc.opacity_scale()) * base.a;
    if (flags & 1024u) { opacity *= tex.opacity().sample(materialSampler, uv).r; }
    if (opacity <= half(mc.opacity_threshold())) { discard_fragment(); }
    surface.set_opacity(opacity * keep);
    if (cp.w > 0.5) {
        surface.set_base_color(half3(0.0h));
        surface.set_emissive_color(half3(1.0h));
        surface.set_roughness(1.0h);
        surface.set_metallic(0.0h);
        surface.set_specular(0.0h);
        surface.set_clearcoat(0.0h);
        return;
    }
    half3 color = base.rgb * half3(mc.base_color_tint());
    if (unlit) {
        surface.set_emissive_color(color);
        return;
    }
    surface.set_base_color(color);
    half3 emissive = half3(mc.emissive_color());
    if (flags & 8u) { emissive *= tex.emissive_color().sample(materialSampler, uv).rgb; }
    surface.set_emissive_color(emissive * half(cp.z));
    if (flags & 4u) {
        surface.set_normal(float3(realitykit::unpack_normal(tex.normal().sample(materialSampler, uv).rgb)));
    }
    half rough = half(mc.roughness_scale());
    half metallic = half(mc.metallic_scale());
    half specular = half(mc.specular_scale());
    half coat = half(mc.clearcoat_scale());
    half coatRough = half(mc.clearcoat_roughness_scale());
    if (flags & 16u) { rough *= tex.roughness().sample(materialSampler, uv).r; }
    if (flags & 32u) { metallic *= tex.metallic().sample(materialSampler, uv).r; }
    if (flags & 64u) { specular *= tex.specular().sample(materialSampler, uv).r; }
    if (flags & 256u) { coat *= tex.clearcoat().sample(materialSampler, uv).r; }
    if (flags & 512u) { coatRough *= tex.clearcoat_roughness().sample(materialSampler, uv).r; }
    surface.set_roughness(rough);
    surface.set_metallic(metallic);
    surface.set_specular(specular);
    surface.set_clearcoat(coat);
    surface.set_clearcoat_roughness(coatRough);
    surface.set_ambient_occlusion((flags & 128u) ? tex.ambient_occlusion().sample(materialSampler, uv).r : 1.0h);
}
}

[[visible]] void firstPersonLitSurface(realitykit::surface_parameters params) { first_person::shade(params, false); }
[[visible]] void firstPersonUnlitSurface(realitykit::surface_parameters params) { first_person::shade(params, true); }
