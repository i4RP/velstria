// 担当: battle-renderer（スキル演出）。演出のメッシュ用の表面シェーダー（CustomMaterial。FXPrograms が加算・アルファの 2 つの
// Program に載せる）。Xcode がアプリの default.metallib にコンパイルする。
//
// 入力（FXMaterialLibrary が材質に書く）:
//   base_color の画像 = 形（白 + アルファ。FXTex）かコマ送りのシート（FXSheet）、base_color_tint = 主の色
//   emissive_color = 模様の明るい所の色・溶ける縁の光の色（どちらも無ければ使わない）
//   custom の画像 = 繰り返しの模様（FXFlowTex。流れ・溶けが無ければ形と同じ画像）
//   custom_parameter: x, y = 模様の流れる速さ（UV / 秒）、z = 模様の繰り返し、w = 縁の欠け（0〜1）
//   metallic_scale = 模様の強さ（0 = 模様なし: 形 × 色だけ）、roughness_scale = 明るさ（加算の段階のフェード。1 = そのまま）
//   specular_scale = コマ送りの 1 / 列、clearcoat_scale = 1 / 行（0 = コマ送りなし）
//   clearcoat_roughness_scale = 溶ける縁の光の幅（0 = 光らない）
// 1 体ごとの値（SkillFXPlayer が頂点の色へ書く。FXMeshSlot）: g = コマ（0〜255 のコマ番号）、b = 溶けの進み（0〜1）、
//   a = 模様の種（同じ模様を重ねても揃わないように模様をずらす）。r は予約（255）。
// 加算（blendMode .add）はアルファを使わないので、色に形のアルファを掛けて出す。アルファ合成は色と不透明度を別に出す。
// 加算のシートは乗算済みの色の不透明な版（白は輝度 = アルファ、色付きは色 × アルファ）、アルファ合成のシートは
// 色にアルファを焼き込んだ版（FXSheetLibrary）なので、形と色の取り出し方が合成で違う。
// 注意: unlit の CustomMaterial は set_emissive_color の値だけで描く（base_color など他の出力は無視される。Apple の
// CustomMaterial.LightingModel.unlit の説明）。色は必ず emissive に出す（2026-10-17 に base_color だけで出して何も映らなかった）。

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

/// 形 × 模様 × 色。uv は画像の向き（v の上 = 画像の上）に合わせて裏返した座標。additive = 加算の Program か。
inline Shaded shade(realitykit::surface_parameters params, bool additive) {
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    auto tex = params.textures();
    auto mc = params.material_constants();
    float4 cp = params.uniforms().custom_parameter();
    float t = params.uniforms().time();
    half4 vc = half4(params.geometry().color());

    half3 tintA = half3(mc.base_color_tint().rgb);
    half3 tintB = half3(mc.emissive_color());
    half strength = half(mc.metallic_scale());
    half bright = half(mc.roughness_scale());
    float cellU = float(mc.specular_scale());
    float cellV = float(mc.clearcoat_scale());
    half edgeWidth = half(mc.clearcoat_roughness_scale());

    // 形（とコマ送りの画像の色）
    half shape;
    half3 picture = half3(1.0h);
    if (cellU > 0.0001 && cellV > 0.0001) {
        // コマ送り: コマ番号 → 格子の位置（左上から行優先）。縁の画素で隣のコマを拾わないよう少し内へ寄せる
        float columns = floor(1.0 / cellU + 0.5);
        float frame = floor(float(vc.g) * 255.0 + 0.5);
        float col = fmod(frame, columns);
        float row = floor(frame / columns);
        float2 fuv = (clamp(uv, float2(0.004), float2(0.996)) + float2(col, row)) * float2(cellU, cellV);
        half4 s = tex.base_color().sample(shapeSampler, fuv);
        if (additive) {
            shape = max(s.r, max(s.g, s.b));
            picture = s.rgb / max(shape, 0.002h);
        } else {
            shape = s.a;
            picture = clamp(s.rgb / max(s.a, 0.004h), half3(0.0h), half3(1.0h));
        }
    } else {
        shape = tex.base_color().sample(shapeSampler, uv).a;
    }

    // 模様（流れ・縁の欠け・溶けに使う）。種で模様をずらす
    half dissolve = vc.b;
    // 模様の強さ 0 の縁の欠けは従来どおり効かない（模様 = 1）。溶けだけの時も模様を引く
    bool needsPattern = strength > 0.001h || dissolve > 0.001h;
    half pattern = 1.0h;
    if (needsPattern) {
        float2 seed = float2(float(vc.a) * 0.731, float(vc.a) * 0.419);
        float2 fuv = uv * cp.z + cp.xy * t + seed;
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
    half3 color = mix(tintA, tintB, mixAmt) * (1.0h + strength * (pattern - 0.5h) * 0.8h) * picture;
    // 溶け: 進み d の分だけ、模様の暗い所から消える。消える縁は tintB で光る
    if (dissolve > 0.001h) {
        half th = dissolve * 1.1h - 0.05h;
        half keep = smoothstep(th, th + 0.05h, pattern);
        if (edgeWidth > 0.001h) {
            half rim = keep * (1.0h - smoothstep(th + 0.05h, th + 0.05h + edgeWidth, pattern));
            color = mix(color, tintB * 1.4h, saturate(rim * 1.5h));
        }
        shape *= keep;
    }
    return Shaded{ max(color, half3(0)) * bright, saturate(shape) };
}
} // namespace fx

[[visible]] void fxAddSurface(realitykit::surface_parameters params) {
    fx::Shaded s = fx::shade(params, true);
    params.surface().set_emissive_color(s.color * s.alpha);
    params.surface().set_base_color(s.color * s.alpha);
    params.surface().set_opacity(s.alpha);
}

/// 描画の切り分け用（撮影の probe だけ）: 計算をせず、材質の色をそのまま不透明で塗る。
[[visible]] void fxDebugSurface(realitykit::surface_parameters params) {
    auto mc = params.material_constants();
    params.surface().set_base_color(half3(mc.base_color_tint().rgb));
    params.surface().set_emissive_color(half3(mc.base_color_tint().rgb));
    params.surface().set_opacity(1.0h);
}

[[visible]] void fxAlphaSurface(realitykit::surface_parameters params) {
    fx::Shaded s = fx::shade(params, false);
    params.surface().set_emissive_color(s.color);
    params.surface().set_base_color(s.color);
    params.surface().set_opacity(s.alpha);
}
