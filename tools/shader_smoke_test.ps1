param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$FxcPath = "fxc.exe"
)

$ErrorActionPreference = "Stop"

function Get-HlslProgramsFromFile {
    param([string]$Path)

    $lines = Get-Content -Path $Path
    $programs = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -notmatch '^(vertex_program|fragment_program)\s+(\S+)\s+hlsl\b') { continue }

        $kind = $matches[1]
        $name = $matches[2]
        $block = @($lines[$i])
        $depth = ([regex]::Matches($lines[$i], '\{')).Count - ([regex]::Matches($lines[$i], '\}')).Count
        $enteredBlock = ($depth -gt 0)
        $j = $i + 1
        while ($j -lt $lines.Count) {
            $block += $lines[$j]
            $depth += ([regex]::Matches($lines[$j], '\{')).Count
            $depth -= ([regex]::Matches($lines[$j], '\}')).Count
            if ($depth -gt 0) { $enteredBlock = $true }
            $j++
            if ($enteredBlock -and $depth -le 0) { break }
        }
        $i = $j - 1

        $source = $null
        $target = $null
        $entry = $null
        $defines = $null

        foreach ($raw in $block) {
            $trim = $raw.Trim()
            if ($trim.StartsWith("//")) { continue }
            if (-not $source -and $trim -match '^source\s+(\S+)') { $source = $matches[1]; continue }
            if (-not $target -and $trim -match '^target\s+(\S+)') { $target = $matches[1]; continue }
            if (-not $entry -and $trim -match '^entry_point\s+(\S+)') { $entry = $matches[1]; continue }
            if (-not $defines -and $trim -match '^preprocessor_defines\s+(.+)$') { $defines = $matches[1].Trim(); continue }
        }

        if (-not $target) { continue }
        if ($target -notin @("vs_3_0","ps_3_0","vs_4_0","ps_4_0")) { continue }
        if (-not $source -or -not $entry) { continue }

        $programs += [pscustomobject]@{
            FilePath = $Path
            Kind = $kind
            Name = $name
            Source = $source
            Target = $target
            Entry = $entry
            Defines = $defines
        }
    }

    return $programs
}

if (-not (Get-Command $FxcPath -ErrorAction SilentlyContinue)) {
    Write-Error "Could not find '$FxcPath'. Install Windows SDK fxc.exe or pass -FxcPath <full path>."
}

$programFiles = Get-ChildItem -Path $Root -Filter *.program -File
$allPrograms = @()
foreach ($pf in $programFiles) {
    $allPrograms += Get-HlslProgramsFromFile -Path $pf.FullName
}

if (-not $allPrograms -or $allPrograms.Count -eq 0) {
    Write-Error "No HLSL programs found in .program files under $Root"
}

$failures = @()
$compiled = 0

foreach ($p in $allPrograms) {
    $srcPath = Join-Path (Split-Path $p.FilePath -Parent) $p.Source
    if (-not (Test-Path $srcPath)) {
        $failures += "$($p.Name): missing source '$srcPath'"
        continue
    }

    $tempOutFile = Join-Path $env:TEMP "shader_smoke_$($p.Name)_$($p.Target).cso"

    $args = @(
        "/nologo",
        "/T", $p.Target,
        "/E", $p.Entry,
        "/Fo", $tempOutFile
    )

    if ($p.Defines) {
        $tokens = $p.Defines.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($d in $tokens) {
            $args += "/D"
            $args += $d
        }
    }

    $args += $srcPath

    $proc = Start-Process -FilePath $FxcPath -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError "$env:TEMP\shader_smoke_err.txt" -RedirectStandardOutput "$env:TEMP\shader_smoke_out.txt"
    if ($proc.ExitCode -ne 0) {
        $stderr = ""
        if (Test-Path "$env:TEMP\shader_smoke_err.txt") {
            $rawErr = Get-Content "$env:TEMP\shader_smoke_err.txt" -Raw
            if ($null -ne $rawErr) { $stderr = $rawErr.Trim() }
        }
        $stdout = ""
        if (Test-Path "$env:TEMP\shader_smoke_out.txt") {
            $rawOut = Get-Content "$env:TEMP\shader_smoke_out.txt" -Raw
            if ($null -ne $rawOut) { $stdout = $rawOut.Trim() }
        }
        $msg = if ($stderr) { $stderr } elseif ($stdout) { $stdout } else { "fxc exited $($proc.ExitCode)" }
        $failures += "$($p.Name) [$($p.Target)] in $(Split-Path $p.FilePath -Leaf): $msg"
    } else {
        $compiled++
    }

    if (Test-Path $tempOutFile) {
        Remove-Item $tempOutFile -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Compiled: $compiled / $($allPrograms.Count)"
    Write-Host "Failures:"
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "Shader smoke test passed: compiled $compiled permutations (vs_3_0/ps_3_0/vs_4_0/ps_4_0)."
