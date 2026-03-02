param(
    [string]$MaterialFile = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "CR_BZBase.material")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $MaterialFile)) {
    throw "Material file not found: $MaterialFile"
}

$text = Get-Content -Path $MaterialFile -Raw

function Reorder-TextureUnitsInPass([string]$passText) {
    $unitRegex = [regex]'(?ms)^\s*texture_unit\s+(\S+)\s*\{.*?^\s*\}'
    $matches = $unitRegex.Matches($passText)
    if ($matches.Count -eq 0) { return $passText }

    $orderedNames = @(
        "diffuseMap",
        "normalMap",
        "specularMap",
        "emissiveMap",
        "glossMap",
        "metallicMap",
        "detailMap",
        "shadowMap1",
        "shadowMap2",
        "shadowMap3"
    )

    $blocks = @()
    foreach ($m in $matches) {
        $blocks += [pscustomobject]@{
            Name = $m.Groups[1].Value
            Text = $m.Value.TrimEnd()
        }
    }

    $insertAt = $matches[0].Index
    $sb = New-Object System.Text.StringBuilder
    $cursor = 0
    foreach ($m in $matches) {
        [void]$sb.Append($passText.Substring($cursor, $m.Index - $cursor))
        $cursor = $m.Index + $m.Length
    }
    [void]$sb.Append($passText.Substring($cursor))
    $withoutUnits = $sb.ToString()

    $orderedBlocks = New-Object System.Collections.Generic.List[string]
    $used = New-Object System.Collections.Generic.HashSet[int]
    foreach ($name in $orderedNames) {
        for ($i = 0; $i -lt $blocks.Count; $i++) {
            if ($used.Contains($i)) { continue }
            if ($blocks[$i].Name -eq $name) {
                [void]$orderedBlocks.Add($blocks[$i].Text)
                [void]$used.Add($i)
            }
        }
    }
    for ($i = 0; $i -lt $blocks.Count; $i++) {
        if (-not $used.Contains($i)) {
            [void]$orderedBlocks.Add($blocks[$i].Text)
        }
    }

    $orderedText = ($orderedBlocks -join "`r`n`r`n") + "`r`n"
    return $withoutUnits.Insert($insertAt, $orderedText)
}

$passRegex = [regex]'(?ms)^abstract pass\b.*?^\}'
$result = $passRegex.Replace($text, { param($m) Reorder-TextureUnitsInPass $m.Value })

Set-Content -Path $MaterialFile -Value $result
Write-Host "Normalized texture unit ordering in $MaterialFile"
