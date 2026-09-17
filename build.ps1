#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cache = Join-Path $Root ".cache"
$Dist = Join-Path $Root "dist"
$DlcDir = Join-Path $Cache "domain-list-community"
$GeoipDir = Join-Path $Cache "geoip"
$Custom = Join-Path $Cache "geosite-data"

function Need-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Нужна команда '$Name'. $Hint"
    }
}

Need-Command git "Установите Git: https://git-scm.com/download/win"
Need-Command go "Установите Go: winget install GoLang.Go  (после установки откройте новый терминал)"
Need-Command curl.exe "Обычно есть в Windows 10+"

New-Item -ItemType Directory -Force -Path $Cache, $Dist | Out-Null

function Clone-OrUpdate([string]$Url, [string]$Dir) {
    if (-not (Test-Path (Join-Path $Dir ".git"))) {
        git clone --depth 1 --branch master $Url $Dir
        if ($LASTEXITCODE -ne 0) { throw "git clone failed: $Url" }
        return
    }
    git -C $Dir fetch --depth 1 origin master
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed: $Dir" }
    git -C $Dir reset --hard origin/master
    if ($LASTEXITCODE -ne 0) { throw "git reset failed: $Dir" }
}

function Strip-Line([string]$Raw) {
    $line = ($Raw -replace '#.*$', '')
    return $line.Trim()
}

function Test-HasRules([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = Strip-Line $raw
        if ($line) { return $true }
    }
    return $false
}

function Copy-WithDeps([string]$Name) {
    $src = Join-Path $DlcDir "data\$Name"
    $dst = Join-Path $Custom $Name
    if (-not (Test-Path $src)) {
        throw "Нет категории в domain-list-community: $Name"
    }
    if (Test-Path $dst) { return }
    Copy-Item -LiteralPath $src -Destination $dst
    foreach ($match in Select-String -LiteralPath $src -Pattern '^include:([a-zA-Z0-9_-]+)') {
        Copy-WithDeps $match.Matches[0].Groups[1].Value
    }
}

Write-Host "==> domain-list-community"
Clone-OrUpdate "https://github.com/v2fly/domain-list-community.git" $DlcDir

Write-Host "==> geoip compiler"
Clone-OrUpdate "https://github.com/v2fly/geoip.git" $GeoipDir

if (Test-Path $Custom) { Remove-Item -Recurse -Force $Custom }
New-Item -ItemType Directory -Force -Path $Custom | Out-Null

Write-Host "==> категории"
Get-Content -LiteralPath (Join-Path $Root "categories.txt") | ForEach-Object {
    $line = Strip-Line $_
    if ($line) { Copy-WithDeps $line }
}

$extraDir = Join-Path $Root "extra"
if (Test-Path $extraDir) {
    Write-Host "==> extra/"
    Get-ChildItem -LiteralPath $extraDir -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Custom $_.Name)
    }
}

$categoryRu = Join-Path $Custom "category-ru"
$foldFile = Join-Path $Root "fold-into-category-ru.txt"
if ((Test-Path $categoryRu) -and (Test-Path $foldFile)) {
    Write-Host "==> вшиваю теги в category-ru"
    Get-Content -LiteralPath $foldFile | ForEach-Object {
        $tag = Strip-Line $_
        if (-not $tag) { return }
        if (Test-HasRules (Join-Path $Custom $tag)) {
            Add-Content -LiteralPath $categoryRu -Value "include:$tag"
            Write-Host "    include:$tag"
        }
    }
}

Write-Host "==> geosite.dat"
Push-Location $DlcDir
try {
    go run . --datapath $Custom --outputdir $Dist --outputname geosite.dat
    if ($LASTEXITCODE -ne 0) { throw "сборка geosite.dat не удалась" }
} finally {
    Pop-Location
}

Write-Host "==> geoip.dat"
$ipDir = Join-Path $GeoipDir "custom-ips"
New-Item -ItemType Directory -Force -Path $ipDir | Out-Null
curl.exe -fsSL "https://raw.githubusercontent.com/v2fly/geoip/release/text/ru.txt" -o (Join-Path $ipDir "ru.txt")
if ($LASTEXITCODE -ne 0) { throw "не скачался ru.txt" }
curl.exe -fsSL "https://raw.githubusercontent.com/v2fly/geoip/release/text/private.txt" -o (Join-Path $ipDir "private.txt")
if ($LASTEXITCODE -ne 0) { throw "не скачался private.txt" }

$configJson = @'
{
  "input": [
    { "type": "text", "action": "add", "args": { "name": "ru", "uri": "custom-ips/ru.txt" } },
    { "type": "text", "action": "add", "args": { "name": "private", "uri": "custom-ips/private.txt" } }
  ],
  "output": [
    { "type": "v2rayGeoIPDat", "action": "output", "args": { "outputName": "geoip.dat", "outputDir": "output" } }
  ]
}
'@
$configPath = Join-Path $GeoipDir "custom-config.json"
[System.IO.File]::WriteAllText($configPath, $configJson, (New-Object System.Text.UTF8Encoding $false))

Push-Location $GeoipDir
try {
    go run . -c custom-config.json
    if ($LASTEXITCODE -ne 0) { throw "сборка geoip.dat не удалась" }
} finally {
    Pop-Location
}

$built = @(
    (Join-Path $GeoipDir "output\dat\geoip.dat"),
    (Join-Path $GeoipDir "output\geoip.dat"),
    (Join-Path $GeoipDir "geoip.dat")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $built) { throw "geoip.dat не появился после сборки" }
Copy-Item -LiteralPath $built -Destination (Join-Path $Dist "geoip.dat") -Force

Write-Host ""
Write-Host "Готово:"
Get-Item (Join-Path $Dist "geosite.dat"), (Join-Path $Dist "geoip.dat") | Format-Table Name, Length, LastWriteTime
