// 担当: battle-renderer（スキル演出）。演出のメッシュ用の表面シェーダー（CustomMaterial。FXPrograms が加算・アルファの 2 つの
// Program に載せる）。Xcode がアプリの default.metallib にコンパイルする。
//
// 入力（FXMaterialLibrary が材質に書く）:
//   base_color の画像 = 形（白 + アルファ。FXTex）、base_color_tint = 主の色
//   emissive_color = 模様の明るい所の色（流れが無ければ使わない）
//   custom の画像 = 繰り返しの模様（FXFlowTex。流れが無ければ形と同じ画像）
//   custom_parameter: x, y = 模様の流れる速さ（UV / 秒）、z = 模様の繰り返し、w = 縁の欠け（0〜1）
//   metallic_scale = 模様の強さ（0 = 模様なし: 形 × 色だけ）、roughness_scale = 明るさ（加算の段階のフェード。1 = そのまま）
// 加算（blendMode .add）はアルファを使わないので、色に形のアルファを掛けて出す。アルファ合成は色と不透明度を別に出す。

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

namespace fx {
constexpr sampler shapeSampler(address::clamp_to_edge, filter::linear, mip_filter::linear);
constexpr sampler flowSampler(address::repeat, filter::linear, mip_filter::linear);

struct Shaded {
    half3 color;
    half alpha;
};

/// 形 × 模様 × 色。uv は画像の向き（v の上 = 画像の上）に合わせて裏返した座標。
inline Shaded shade(realitykit::surface_parameters params) {
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    auto tex = params.textures();
    auto mc = params.material_constants();
    float4 cp = params.uniforms().custom_parameter();
    float t = params.uniforms().time();

    half shape = tex.base_color().sample(shapeSampler, uv).a;
    half3 tintA = half3(mc.base_color_tint().rgb);
    half3 tintB = half3(mc.emissive_color());
    half strength = half(mc.metallic_scale());
    half bright = half(mc.roughness_scale());

    half pattern = 1.0h;
    if (strength > 0.001h) {
        float2 fuv = uv * cp.z + cp.xy * t;
        // 2 つの速さで重ねて単調な縞にしない
        half a = tex.custom().sample(flowSampler, fuv).r;
        half b = tex.custom().sample(flowSampler, fuv * 0.57 + float2(0.31, 0.73) - cp.xy * t * 0.35).r;
        pattern = saturate(a * 0.65h + b * 0.55h);
    }
    // 縁の欠け: 形のアルファが低い所ほど、模様の暗い所から欠ける
    half erosion = half(cp.w);
    if (erosion > 0.001h) {
        half cut = smoothstep(erosion * (1.0h - shape), erosion * (1.0h - shape) + 0.18h, pattern);
        shape *= cut;
    }
    half mixAmt = saturate(pattern * strength);
    half3 color = mix(tintA, tintB, mixAmt) * (1.0h + strength * (pattern - 0.5h) * 0.8h);
    return Shaded{ max(color, half3(0)) * bright, saturate(shape) };
}
} // namespace fx

[[visible]] void fxAddSurface(realitykit::surface_parameters params) {
    fx::Shaded s = fx::shade(params);
    params.surface().set_base_color(s.color * s.alpha);
    params.surface().set_opacity(s.alpha);
}

[[visible]] void fxAlphaSurface(realitykit::surface_parameters params) {
    fx::Shaded s = fx::shade(params);
    params.surface().set_base_color(s.color);
    params.surface().set_opacity(s.alpha);
}
