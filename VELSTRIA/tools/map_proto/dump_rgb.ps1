# ミニマップ領域（画像座標 x 95..985, y 0..880）の RGB を rgb4.txt に書き出す（fitwalls.mjs の入力）。
# 使い方: .\dump_rgb.ps1 -Image <スクリーンショットの PNG> （数分かかる。出力は 7 MB 超なのでコミットしない）
param([Parameter(Mandatory)][string]$Image, [string]$Out = "$PSScriptRoot\rgb4.txt")
Add-Type -AssemblyName System.Drawing
$b = New-Object System.Drawing.Bitmap $Image
$sb = New-Object System.Text.StringBuilder
for ($y = 0; $y -lt 880; $y++) { for ($x = 95; $x -lt 985; $x++) { $c = $b.GetPixel($x, $y); [void]$sb.Append(("{0},{1},{2};" -f $c.R, $c.G, $c.B)) }; [void]$sb.AppendLine() }
[System.IO.File]::WriteAllText($Out, $sb.ToString())
