// ステージ（地面・崖・小物・草）の RealityKit CustomMaterial 用シェーダー。
// アプリのターゲットではコンパイルしない（CI に Metal Toolchain が無くても通るように）。
// tools/stage/build_shaders.sh が metallib（実機 / シミュレータ / macOS）を作り App/Resources/Stage/ へ置く。
// テクスチャの割り当て・配合マップの意味は docs/STAGE.md の 3.4 を参照。
//
// 座標: 地図座標 m = (x, -z)（m）。+m.y が北（画面の上）。地面の配合マップは m = (-20…140, -20…140) を覆い、
// 画像の上端が北（m.y = 140）。テクスチャは画像の上端が v = 0（Metal の向き。RealityKit 標準材質の UV とは上下が逆）。

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

namespace stage {

// 地面のタイルは画質で異方性を変える（custom_parameter.z: 1 / 2 / 4）。constexpr の sampler は変数で選べないので 3 つ持つ
constexpr sampler tileSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear, max_anisotropy(4));
constexpr sampler tileSampler2(coord::normalized, address::repeat, filter::linear, mip_filter::linear, max_anisotropy(2));
constexpr sampler tileSampler1(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
constexpr sampler mapSampler(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler atlasSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear, max_anisotropy(2));

constant float kMapOrigin = -20.0;
constant float kMapSpan = 160.0;

// タイルの実寸の周期（m）
constant float kPeriodGrass = 6.0;
constant float kPeriodForest = 6.0;
constant float kPeriodDirt = 7.0;
constant float kPeriodPaving = 5.0;
constant float kPeriodRiverbed = 6.0;
constant float kPeriodRock = 4.0;
constant float kPeriodMoss = 4.0;

inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

inline float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1));
    float d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

inline float fbm3(float2 p) {
    return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.07 + 11.3) + 0.15 * vnoise(p * 4.13 + 5.7);
}

inline float2 rot(float2 v, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

inline float luma(half3 c) { return dot(float3(c), float3(0.299, 0.587, 0.114)); }

inline half3 saturateColor(half3 c, half s) {
    half l = half(luma(c));
    return mix(half3(l), c, s);
}

/// 異方性の段（1 / 2 / 4）を選んで読む。aniso は描画全体で同じ値なので分岐の費用はほぼ無い。
inline half4 tileFetch(texture2d<half> t, float2 uv, gradient2d g, float aniso) {
    if (aniso < 1.5) { return t.sample(tileSampler1, uv, g); }
    if (aniso < 3.0) { return t.sample(tileSampler2, uv, g); }
    return t.sample(tileSampler, uv, g);
}

/// 2 つの縮尺・向きで読んで低周波のノイズで混ぜ、タイルの繰り返しを目立たなくする。
/// 勾配は呼び出し側で求めた値を使う（分岐の中でも mip が乱れない）。
inline half3 sampleTile(texture2d<half> t, float2 m, float period, float2 dmx, float2 dmy, float variation, float seed,
                        float aniso) {
    float2 uv = m / period;
    half3 a = tileFetch(t, uv, gradient2d(dmx / period, dmy / period), aniso).rgb;
    if (variation <= 0.001) { return a; }
    float p2 = period * 1.73;
    float2 uv2 = rot(m, 1.1 + seed) / p2 + float2(0.37, 0.71) + seed;
    half3 b = tileFetch(t, uv2, gradient2d(rot(dmx, 1.1 + seed) / p2, rot(dmy, 1.1 + seed) / p2), aniso).rgb;
    float n = smoothstep(0.3, 0.7, vnoise(m * 0.075 + seed * 13.0)) * variation;
    // 2 枚の混合で下がるコントラストを、タイル全体の平均色（最小の mip）の周りで戻す
    half3 mixc = mix(a, b, half(n));
    half3 mean = t.sample(tileSampler1, float2(0.5), level(float(t.get_num_mip_levels() - 1))).rgb;
    half k = half(1.0 / sqrt(max(0.5, n * n + (1.0 - n) * (1.0 - n))));
    return mean + (mixc - mean) * mix(1.0h, k, 0.6h);
}

/// 水面のさざ波の高さ（2 方向の流れ）。
inline float rippleHeight(float2 m, float t) {
    float2 flow = float2(0.7071, -0.7071); // 川は北西 → 南東へ流れる
    float a = vnoise(m * 1.3 - flow * t * 0.55);
    float b = vnoise(rot(m, 0.8) * 2.1 - flow * t * 0.8 + 7.0);
    return a * 0.6 + b * 0.4;
}

/// 浅瀬の川底に揺れる光の網目（コースティクス）。
inline float caustics(float2 m, float t) {
    float2 p = m * 0.9;
    float c1 = abs(sin(p.x * 2.1 + sin(p.y * 1.7 + t * 0.9) * 1.3 + t * 0.6));
    float c2 = abs(sin(p.y * 2.3 + sin(p.x * 1.5 - t * 0.7) * 1.4 - t * 0.5));
    float c = (1.0 - c1) * (1.0 - c2);
    return smoothstep(0.35, 0.95, c);
}

} // namespace stage

// MARK: - 地面

[[visible]] void stageGroundSurface(realitykit::surface_parameters params) {
    using namespace stage;
    float3 mp = params.geometry().model_position();
    float2 m = float2(mp.x, -mp.z);
    float t = params.uniforms().time();
    // x: タイルの繰り返し対策の強さ（low 0）、y: 水面の動きの強さ、z: 異方性（1 / 2 / 4）、w: 予備
    float4 cp = params.uniforms().custom_parameter();
    auto tex = params.textures();
    float2 dmx = dfdx(m), dmy = dfdy(m);

    // 配合マップ。縁を低周波ノイズで揺らし、16 cm の画素より細かい不規則な縁にする
    float2 warp = float2(vnoise(m * 0.6), vnoise(m * 0.6 + 19.7)) - 0.5;
    float2 cuv = float2((m.x - kMapOrigin) / kMapSpan, 1.0 - (m.y - kMapOrigin) / kMapSpan);
    float2 cuvw = cuv + warp * (0.7 / kMapSpan);
    half4 ctrl = tex.custom().sample(mapSampler, cuvw);
    half4 aux = tex.ambient_occlusion().sample(mapSampler, cuv);

    float wDirt = float(ctrl.r);
    float wPave = float(ctrl.g);
    float wRiver = float(ctrl.b);
    float wForest = float(ctrl.a);
    float wGrass = saturate(1.0 - wDirt - wPave - wRiver - wForest);
    float variation = cp.x;
    float aniso = cp.z;

    // 各層（重みが無い層は読まない）
    half3 cGrass = half3(0), cForest = half3(0), cDirt = half3(0), cPave = half3(0), cBed = half3(0);
    float hGrass = 0, hForest = 0, hDirt = 0, hPave = 0, hBed = 0;
    if (wGrass > 0.004) {
        cGrass = sampleTile(tex.base_color(), m, kPeriodGrass, dmx, dmy, variation, 0.0, aniso);
        cGrass *= half3(0.93, 0.98, 0.86);
        cGrass = saturateColor(cGrass, 0.86h);
        hGrass = luma(cGrass) * 0.9 + 0.12;
    }
    if (wForest > 0.004) {
        cForest = sampleTile(tex.specular(), m, kPeriodForest, dmx, dmy, variation, 0.31, aniso);
        cForest *= half3(0.95, 1.0, 0.95);
        hForest = luma(cForest) * 0.9 + 0.1;
    }
    if (wDirt > 0.004) {
        cDirt = sampleTile(tex.emissive_color(), m, kPeriodDirt, dmx, dmy, variation, 0.57, aniso);
        cDirt = saturateColor(cDirt, 0.58h) * half3(0.97, 0.9, 0.82);
        hDirt = (1.0 - luma(cDirt)) * 0.35 + 0.2; // 割れ目（暗い所）は低い → 草が被さる
    }
    if (wPave > 0.004) {
        cPave = sampleTile(tex.roughness(), m, kPeriodPaving, dmx, dmy, variation, 0.19, aniso) * half3(0.92, 0.93, 0.95);
        hPave = luma(cPave) * 0.8 + 0.25;
    }
    if (wRiver > 0.004) {
        float2 refr = (float2(rippleHeight(m, t), rippleHeight(m + 3.1, t)) - 0.5) * 0.25 * cp.y;
        cBed = sampleTile(tex.metallic(), m + refr, kPeriodRiverbed, dmx, dmy, variation * 0.5, 0.83, aniso);
        hBed = 0.3;
    }

    // 高さ付きの混合（縁で草が土へ被さる手描き風の境界）
    const float depth = 0.16;
    float sGrass = hGrass + wGrass, sForest = hForest + wForest, sDirt = hDirt + wDirt;
    float sPave = hPave + wPave, sBed = hBed + wRiver;
    float ma = max(max(max(sGrass, sForest), max(sDirt, sPave)), sBed) - depth;
    float bGrass = wGrass > 0.004 ? max(sGrass - ma, 0.0) : 0.0;
    float bForest = wForest > 0.004 ? max(sForest - ma, 0.0) : 0.0;
    float bDirt = wDirt > 0.004 ? max(sDirt - ma, 0.0) : 0.0;
    float bPave = wPave > 0.004 ? max(sPave - ma, 0.0) : 0.0;
    float bBed = wRiver > 0.004 ? max(sBed - ma, 0.0) : 0.0;
    float bSum = max(1e-4, bGrass + bForest + bDirt + bPave + bBed);
    half3 color = (cGrass * half(bGrass) + cForest * half(bForest) + cDirt * half(bDirt) + cPave * half(bPave)
                   + cBed * half(bBed)) / half(bSum);

    // 土と草の境目をわずかに暗く（踏み固められた縁）
    float edge = 4.0 * wDirt * (1.0 - wDirt);
    color *= half(1.0 - 0.10 * edge);

    // 大きな色むら（aux.g: 0.5 が中立）
    float macro = float(aux.g) - 0.5;
    color *= half(1.0 + macro * 0.34);
    color = mix(color, color * half3(1.07, 1.04, 0.86), half(saturate(macro) * 0.6 * (bGrass / bSum)));

    half roughness = 0.92h;
    half specular = 0.18h;
    half3 emissive = half3(0);

    // 水面
    if (wRiver > 0.004) {
        float d = float(aux.b);                      // 0 = 岸、1 = 中央
        float wet = smoothstep(0.15, 0.55, wRiver);  // 水に覆われている度合い
        // 色は線形値（sRGB で浅瀬 (60,150,150)、深み (25,85,105) 相当）
        half3 shallow = half3(0.03, 0.20, 0.22);
        half3 deep = half3(0.008, 0.07, 0.12);
        half3 water = mix(shallow, deep, half(smoothstep(0.0, 1.0, d)));
        half3 under = color * half3(0.40, 0.62, 0.68) * half(mix(0.85, 0.3, d));
        half3 surf = mix(under, water, half(0.55 + 0.4 * d));
        // 浅瀬のコースティクス
        float caus = caustics(m, t * cp.y) * (1.0 - d) * 0.10;
        surf += half3(0.55, 0.85, 0.8) * half(caus);
        // さざ波の明暗と照り返し（太陽は左上の奥）
        float r0 = rippleHeight(m, t * cp.y);
        float rx = rippleHeight(m + float2(0.15, 0), t * cp.y) - r0;
        float ry = rippleHeight(m + float2(0, 0.15), t * cp.y) - r0;
        float glint = pow(saturate(0.5 + (-rx * 0.8 + ry * 1.1) * 3.5), 6.0);
        float sparkle = step(0.86, vnoise(m * 4.0 + float2(t * 0.9, -t * 0.7))) * step(0.6, vnoise(m * 1.3 - t * 0.3));
        emissive += half3(0.75, 0.95, 1.0) * half((glint * 0.12 + sparkle * 0.25) * wet * cp.y);
        surf *= half(0.93 + r0 * 0.14);
        // 岸の泡
        float foam = (1.0 - smoothstep(0.0, 0.55, abs(float(wRiver) - 0.42) * 4.0)) * step(0.45, vnoise(m * 2.4 + float2(t * 0.25, 0)));
        surf = mix(surf, half3(0.62, 0.78, 0.76), half(foam * 0.3));
        color = mix(color, surf, half(wet));
        roughness = mix(roughness, 0.18h, half(wet));
        specular = mix(specular, 0.5h, half(wet));
    }

    // 遮蔽（崖の根元・木陰・草むらの下）: 色を青緑寄りに暗くする
    float ao = float(aux.r);
    color *= mix(half3(1.0), half3(0.52, 0.6, 0.6), half(ao * 0.85));

    params.surface().set_base_color(color);
    params.surface().set_emissive_color(emissive);
    params.surface().set_roughness(roughness);
    params.surface().set_metallic(0.0h);
    params.surface().set_specular(specular);
    params.surface().set_ambient_occlusion(half(1.0 - ao * 0.5));
}

// MARK: - 崖の芯（三平面投影: 側面は岩、上向きの面は苔。苔は roughness のスロット: clearcoat は .lit では束縛されない）

[[visible]] void stageRockSurface(realitykit::surface_parameters params) {
    using namespace stage;
    float3 p = params.geometry().model_position();
    float3 n = normalize(params.geometry().normal());
    auto tex = params.textures();
    float3 w = pow(abs(n), float3(4.0));
    w /= max(1e-4, w.x + w.y + w.z);
    half3 sx = tex.base_color().sample(tileSampler2, float2(p.z, -p.y) / kPeriodRock).rgb;
    half3 sz = tex.base_color().sample(tileSampler2, float2(p.x, -p.y) / kPeriodRock).rgb;
    half3 sy = tex.base_color().sample(tileSampler2, p.xz / kPeriodRock).rgb;
    half3 rock = sx * half(w.x) + sz * half(w.z) + sy * half(w.y);
    half3 moss = tex.roughness().sample(tileSampler2, p.xz / kPeriodMoss).rgb;
    float nz = vnoise(p.xz * 1.7 + p.y * 0.9);
    float top = smoothstep(0.45, 0.8, n.y + (nz - 0.5) * 0.45);
    half3 color = mix(rock, moss * half3(0.92, 1.0, 0.9), half(top));
    // 頂点色: rgb = 個体ごとの色味（0.5 が中立）
    half4 vc = half4(params.geometry().color());
    color *= vc.rgb * 2.0h;
    // 根元を暗く
    color *= half(mix(0.5, 1.0, smoothstep(0.0, 0.9, p.y)));
    params.surface().set_base_color(color);
    params.surface().set_roughness(0.9h);
    params.surface().set_metallic(0.0h);
    params.surface().set_specular(0.22h);
}

// MARK: - 小物（Meshy のアトラス）

[[visible]] void stagePropSurface(realitykit::surface_parameters params) {
    using namespace stage;
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y; // メッシュの UV は RealityKit の向き（下端 0）
    auto tex = params.textures();
    half3 c = tex.base_color().sample(atlasSampler, uv).rgb;
    half4 vc = half4(params.geometry().color());
    c *= vc.rgb * 2.0h;
    float y = params.geometry().model_position().y;
    c *= half(mix(0.62, 1.0, smoothstep(0.0, 0.7, y)));
    params.surface().set_base_color(c);
    params.surface().set_roughness(0.86h);
    params.surface().set_metallic(0.0h);
    params.surface().set_specular(0.25h);
}

// MARK: - 頂点色だけの草花（草むら・草の房・花）

[[visible]] void stageVertexColorSurface(realitykit::surface_parameters params) {
    using namespace stage;
    half4 vc = half4(params.geometry().color());
    float3 p = params.geometry().model_position();
    // 細かな明暗のむら（同じ色の塊に見えないように）
    half n = half(0.9 + 0.2 * vnoise(p.xz * 3.1 + p.y));
    params.surface().set_base_color(vc.rgb * n);
    params.surface().set_roughness(0.8h);
    params.surface().set_metallic(0.0h);
    params.surface().set_specular(0.3h);
}

// MARK: - 風の揺れ（頂点色の a = 揺れの重み。0 の頂点は動かない）

[[visible]] void stageWindGeometry(realitykit::geometry_parameters params) {
    float w = params.geometry().color().a;
    float amp = params.uniforms().custom_parameter().x;
    if (w * amp <= 0.0005) { return; }
    float3 wp = params.geometry().world_position();
    float t = params.uniforms().time();
    float ph = dot(wp.xz, float2(0.23, 0.17));
    float s = sin(t * 1.35 + ph) * 0.7 + sin(t * 2.4 + ph * 1.9) * 0.3;
    params.geometry().set_world_position_offset(float3(s * 0.07, 0.0, s * 0.035) * (w * amp));
}
