<#
.SYNOPSIS
    LÖVE 本地构建脚本 (Windows / PowerShell)
    生成 .love 包、Windows x86/x64 二进制包,并可尝试 Android APK 构建。

.DESCRIPTION
    这是 GitHub Actions 构建流程的本地等价实现,适用于在本机(无需 act/Docker)
    快速打包 LÖVE 游戏。读取 game/product.env 获取产品名等配置。

    目标(target)说明:
      love      仅生成 .love 包
      win64     生成 Windows x64 二进制包 (需 win64 运行时)
      win32     生成 Windows x86 二进制包 (需 win32 运行时)
      windows   同时生成 win64 + win32
      android   尝试构建 Android debug APK (需 JDK17 + Android SDK + 联网)
      all       love + windows (不含 android)
      clean     清空 builds 目录(保留 _runtime 下已下载的运行时)

.PARAMETER Target
    构建目标,见上。默认 all。

.EXAMPLE
    pwsh -File tools/build-local.ps1 love
    pwsh -File tools/build-local.ps1 windows
    pwsh -File tools/build-local.ps1 all
    pwsh -File tools/build-local.ps1 android

.NOTES
    可用环境变量覆盖默认路径:
      LOVE_WIN64_DIR   win64 LÖVE 运行时目录 (含 love.exe + dll)
      LOVE_WIN32_DIR   win32 LÖVE 运行时目录
      SEVENZIP         7z.exe 路径
      JAVA_HOME        JDK 17 根目录 (Android 构建)
      ANDROID_SDK_ROOT Android SDK 根目录 (Android 构建)
#>
[CmdletBinding()]
param(
    [ValidateSet('love', 'win64', 'win32', 'windows', 'android', 'all', 'clean')]
    [string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 可配置项 (环境变量优先,否则用默认值)
# ---------------------------------------------------------------------------
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$GameDir     = Join-Path $ProjectRoot 'game'
$BuildsDir   = Join-Path $ProjectRoot 'builds'
$RuntimeDir  = Join-Path $BuildsDir '_runtime'

$SevenZip     = if ($env:SEVENZIP)        { $env:SEVENZIP }        else { 'C:\Program Files\7-Zip\7z.exe' }
$LoveWin64Dir = if ($env:LOVE_WIN64_DIR)  { $env:LOVE_WIN64_DIR }  else { 'J:\love-11.5-win64' }
$LoveWin32Dir = if ($env:LOVE_WIN32_DIR)  { $env:LOVE_WIN32_DIR }  else { Join-Path $RuntimeDir 'love-11.5-win32' }

$LoveVersion     = '11.5'
$Win32DownloadUrl = "https://github.com/love2d/love/releases/download/$LoveVersion/love-$LoveVersion-win32.zip"

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Fail($msg)        { Write-Host "    [X]  $msg" -ForegroundColor Red; throw $msg }

function Read-ProductEnv {
    # 解析 game/product.env, 返回 hashtable
    $envFile = Join-Path $GameDir 'product.env'
    if (-not (Test-Path $envFile)) { Fail "找不到 $envFile" }
    $map = @{}
    foreach ($line in Get-Content $envFile) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim().Trim('"').Trim("'")
            $map[$key] = $val
        }
    }
    return $map
}

function Get-ProductFile($product) {
    # 与 GitHub Actions 一致: 空格替换为连字符
    return ($product -replace ' ', '-')
}

function Assert-Tool {
    if (-not (Test-Path $SevenZip)) {
        Fail "找不到 7z: $SevenZip (可设置 `$env:SEVENZIP 指向 7z.exe)"
    }
}

# ---------------------------------------------------------------------------
# 构建 .love 包
# ---------------------------------------------------------------------------
function Build-Love($productFile) {
    Write-Step "构建 .love 包"
    Assert-Tool
    New-Item -ItemType Directory -Force -Path $BuildsDir | Out-Null
    $loveOut = Join-Path $BuildsDir "$productFile.love"
    if (Test-Path $loveOut) { Remove-Item $loveOut -Force }

    Push-Location $GameDir
    try {
        & $SevenZip a -tzip -mx=9 $loveOut '*' '-xr!.gitkeep' | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "7z 打包失败" }
    } finally { Pop-Location }

    if (-not (Test-Path $loveOut)) { Fail ".love 未生成" }
    Write-Ok "$loveOut  ($([math]::Round((Get-Item $loveOut).Length/1KB)) KiB)"
    return $loveOut
}

# ---------------------------------------------------------------------------
# 确保 win32 运行时存在 (必要时下载)
# ---------------------------------------------------------------------------
function Ensure-Win32Runtime {
    if (Test-Path (Join-Path $LoveWin32Dir 'love.exe')) { return }
    Write-Step "下载 LÖVE $LoveVersion win32 运行时"
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    $zip = Join-Path $RuntimeDir "love-$LoveVersion-win32.zip"
    if (-not (Test-Path $zip)) {
        Write-Host "    从 $Win32DownloadUrl 下载..."
        Invoke-WebRequest -Uri $Win32DownloadUrl -OutFile $zip -UseBasicParsing
    }
    & $SevenZip x $zip "-o$RuntimeDir" -y | Out-Null
    if (-not (Test-Path (Join-Path $LoveWin32Dir 'love.exe'))) { Fail "win32 运行时解压后仍找不到 love.exe" }
    Write-Ok "win32 运行时就绪: $LoveWin32Dir"
}

# ---------------------------------------------------------------------------
# 构建 Windows 二进制包 (fused exe + dll + zip)
# ---------------------------------------------------------------------------
function Build-Windows($productFile, $loveFile, $runtimeDir, $arch) {
    Write-Step "构建 Windows 包 [$arch]"
    Assert-Tool
    $loveExe = Join-Path $runtimeDir 'love.exe'
    if (-not (Test-Path $loveExe)) { Fail "找不到 $arch 运行时的 love.exe: $loveExe" }

    $stageRoot = Join-Path $BuildsDir "win-$arch"
    $stage     = Join-Path $stageRoot "$productFile-$arch"
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    # fuse: love.exe 字节 + .love 字节 => Product.exe
    $fused = Join-Path $stage "$productFile.exe"
    $fs = [System.IO.File]::Create($fused)
    try {
        foreach ($src in @($loveExe, $loveFile)) {
            $bytes = [System.IO.File]::ReadAllBytes($src)
            $fs.Write($bytes, 0, $bytes.Length)
        }
    } finally { $fs.Close() }

    # 复制运行时依赖 (所有 dll + license)
    Get-ChildItem $runtimeDir -File -Filter *.dll | ForEach-Object { Copy-Item $_.FullName -Destination $stage }
    $lic = Join-Path $runtimeDir 'license.txt'
    if (Test-Path $lic) { Copy-Item $lic -Destination $stage }

    # 打 zip
    $zipOut = Join-Path $BuildsDir "$productFile-$arch.zip"
    if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
    Push-Location $stageRoot
    try {
        & $SevenZip a -tzip -mx=9 $zipOut "$productFile-$arch" | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "$arch zip 打包失败" }
    } finally { Pop-Location }

    $dllCount = (Get-ChildItem $stage -Filter *.dll).Count
    Write-Ok "$zipOut  (exe + $dllCount dll, $([math]::Round((Get-Item $zipOut).Length/1KB)) KiB)"
}

# ---------------------------------------------------------------------------
# Android: 依赖检测 + 构建提示
# ---------------------------------------------------------------------------
function Build-Android($product, $productFile, $loveFile, $pe) {
    Write-Step "Android 打包 (依赖检测)"

    $missing = @()

    # JDK 17
    $javaHome = $env:JAVA_HOME
    $javaOk = $false
    if ($javaHome -and (Test-Path (Join-Path $javaHome 'bin\java.exe'))) {
        $verOut = & (Join-Path $javaHome 'bin\java.exe') -version 2>&1 | Out-String
        if ($verOut -match '"(\d+)') {
            $major = [int]$Matches[1]
            if ($major -eq 17) { $javaOk = $true; Write-Ok "JDK 17: $javaHome" }
            else { Write-Warn2 "JAVA_HOME 指向 JDK $major, love-android 需要精确的 JDK 17" }
        }
    }
    if (-not $javaOk) { $missing += 'JDK 17 (设置 $env:JAVA_HOME 指向 JDK17 根目录)' }

    # Android SDK
    $sdk = $env:ANDROID_SDK_ROOT; if (-not $sdk) { $sdk = $env:ANDROID_HOME }
    if (-not $sdk) { $sdk = 'F:\android_adk' }   # 本机已知位置
    if (Test-Path (Join-Path $sdk 'platform-tools\adb.exe')) {
        Write-Ok "Android SDK: $sdk"
    } else {
        $missing += "Android SDK (设置 `$env:ANDROID_SDK_ROOT, 需含 platform-tools/platforms/build-tools/ndk)"
    }

    # git (clone love-android)
    if (Get-Command git -ErrorAction SilentlyContinue) { Write-Ok "git 可用" }
    else { $missing += 'git (用于 clone love-android)' }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Warn2 "Android 构建缺少以下依赖,暂时跳过:"
        foreach ($m in $missing) { Write-Host "         - $m" -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "    补齐后的本地 Android 构建步骤 (手动):" -ForegroundColor Gray
        Write-Host "      1. 安装 JDK 17 (temurin/microsoft), 设 `$env:JAVA_HOME" -ForegroundColor Gray
        Write-Host "      2. git clone --recurse-submodules -b 11.5a https://github.com/love2d/love-android tools/love-android" -ForegroundColor Gray
        Write-Host "      3. 复制 game/* 到 tools/love-android/app/src/embed/assets/" -ForegroundColor Gray
        Write-Host "      4. 编辑 tools/love-android/gradle.properties:" -ForegroundColor Gray
        Write-Host "           app.application_id=$($pe['PRODUCT_ID'])" -ForegroundColor Gray
        Write-Host "           app.orientation=$($pe['ANDROID_ORIENTATION'])" -ForegroundColor Gray
        Write-Host "      5. cd tools/love-android; ./gradlew assembleEmbedNoRecordDebug" -ForegroundColor Gray
        Write-Host "      6. 产物: app/build/outputs/apk/embedNoRecord/debug/*.apk" -ForegroundColor Gray
        Write-Host ""
        Write-Host "    注意: 首次构建会用 NDK/CMake 从源码编译 liblove.so, 耗时长且需联网。" -ForegroundColor Gray
        return $false
    }

    # 依赖齐全 -> 执行实际构建
    Write-Step "Android 依赖齐全, 开始构建"
    $laDir = Join-Path $ProjectRoot 'tools\love-android'
    if (-not (Test-Path (Join-Path $laDir 'gradlew.bat'))) {
        Write-Host "    clone love-android (tag 11.5a, 含子模块)..."
        git clone --recurse-submodules --depth 1 -b 11.5a https://github.com/love2d/love-android $laDir
        if ($LASTEXITCODE -ne 0) { Fail "clone love-android 失败" }
    }

    # 复制游戏资源到 embed assets
    $assets = Join-Path $laDir 'app\src\embed\assets'
    New-Item -ItemType Directory -Force -Path $assets | Out-Null
    Get-ChildItem $GameDir -Exclude '.gitkeep' | ForEach-Object {
        Copy-Item $_.FullName -Destination $assets -Recurse -Force
    }

    # 配置 gradle.properties
    $gp = Join-Path $laDir 'gradle.properties'
    $content = Get-Content $gp -Raw
    $content = $content -replace '(?m)^app\.application_id=.*', "app.application_id=$($pe['PRODUCT_ID'])"
    $content = $content -replace '(?m)^app\.orientation=.*',    "app.orientation=$($pe['ANDROID_ORIENTATION'])"
    Set-Content -Path $gp -Value $content

    # local.properties 指向 SDK
    $sdkEsc = $sdk -replace '\\', '\\'
    Set-Content -Path (Join-Path $laDir 'local.properties') -Value "sdk.dir=$sdkEsc"

    # 构建
    Push-Location $laDir
    try {
        & .\gradlew.bat assembleEmbedNoRecordDebug
        if ($LASTEXITCODE -ne 0) { Fail "gradlew 构建失败" }
    } finally { Pop-Location }

    # 收集产物
    $apk = Get-ChildItem (Join-Path $laDir 'app\build\outputs\apk') -Recurse -Filter '*debug*.apk' | Select-Object -First 1
    if ($apk) {
        $outApk = Join-Path $BuildsDir "$productFile-debug.apk"
        Copy-Item $apk.FullName -Destination $outApk -Force
        Write-Ok "APK: $outApk"
        return $true
    }
    Fail "构建完成但未找到 APK 产物"
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
function Invoke-Clean {
    Write-Step "清理 builds (保留 _runtime)"
    if (Test-Path $BuildsDir) {
        Get-ChildItem $BuildsDir -Exclude '_runtime', '.gitignore' | Remove-Item -Recurse -Force
    }
    Write-Ok "已清理"
}

$pe = Read-ProductEnv
$product = $pe['PRODUCT_NAME']; if (-not $product) { $product = 'Game' }
$productFile = Get-ProductFile $product
Write-Host "产品: $product  (文件名: $productFile)  目标: $Target" -ForegroundColor Magenta

switch ($Target) {
    'clean'   { Invoke-Clean; break }
    'love'    { Build-Love $productFile | Out-Null; break }
    'win64'   {
        $love = Build-Love $productFile
        Build-Windows $productFile $love $LoveWin64Dir 'win64'
        break
    }
    'win32'   {
        $love = Build-Love $productFile
        Ensure-Win32Runtime
        Build-Windows $productFile $love $LoveWin32Dir 'win32'
        break
    }
    'windows' {
        $love = Build-Love $productFile
        Build-Windows $productFile $love $LoveWin64Dir 'win64'
        Ensure-Win32Runtime
        Build-Windows $productFile $love $LoveWin32Dir 'win32'
        break
    }
    'android' {
        $love = Build-Love $productFile
        Build-Android $product $productFile $love $pe | Out-Null
        break
    }
    'all'     {
        $love = Build-Love $productFile
        Build-Windows $productFile $love $LoveWin64Dir 'win64'
        Ensure-Win32Runtime
        Build-Windows $productFile $love $LoveWin32Dir 'win32'
        break
    }
}

Write-Host "`n完成。产物位于: $BuildsDir" -ForegroundColor Magenta
