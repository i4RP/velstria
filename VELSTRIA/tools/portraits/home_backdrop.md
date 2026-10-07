# ホーム画面の背景（HomeBackdrop）の生成記録

`App/Resources/Assets.xcassets/HomeBackdrop.imageset/HomeBackdrop.jpg`（2732×1537、JPEG 品質 80）。
2026-10-07 に Tripo API の text-to-image で 1 回生成し、そのまま採用（5 credits）。

- エンドポイント: `POST https://openapi.tripo3d.ai/v3/generation/text-to-image`（キーは `~/.config/tripo/api_key`。コミットしない）
- 本文: `{"model": "seedream_v5", "size": "4096x2304", "output_format": "png", "watermark": false, "prompt": <下記>}`
  - prompt は 1800 文字以内（超えると HTTP 400 / code 1004。課金なし）。
- 取り込み: `sips -s format jpeg -s formatOptions 80 -Z 2732 <出力> --out HomeBackdrop.jpg`

構図の約束（UI 側の前提）: 中央は暗く空いている（ヒーローの絵が重なる）、上部中央に星環と星、左右に浮遊城塞、
左下に青い結晶・右下に赤い炎（両陣営）、手前はシアンの導管が走る石畳の闘技場。iPhone の 19.5:9 では上下が切れる。

## prompt

```
Wide 16:9 cinematic environment concept art, no characters: an empty ancient battle arena beneath a colossal celestial star ring. Hand-painted semi-realistic splash art for a premium fantasy sci-fi mobile MOBA, rich painterly brushwork, dramatic volumetric light.
Sky: deep indigo and violet cosmos, soft nebula, countless stars. A gigantic tilted broken golden halo ring edged with blue-white starlight sweeps across the upper sky; a radiant four-pointed blue-white star glows inside it at upper center, casting soft god rays.
Left and right thirds: floating gothic citadels with slender spires on shattered floating rock islands, dim blue-violet silhouettes.
Ground: a vast circular arena of old cracked flagstones, low wide-angle camera, glowing cyan energy conduits engraved in the stone running to the horizon, broken pillars far at the sides. Cool blue crystal light from the far left, warm red-orange ember light from the far right, drifting sparks.
Composition: symmetrical, horizon slightly below middle. The center is calm, dark, nearly empty (a character will be placed there). Edges and bottom dim with dark vignette. Palette: indigo, violet, gold, cyan.
--no people, characters, figures, creatures, text, letters, logo, watermark, UI, frame
```
