[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('android', 'windows', 'macos')] [string] $Platform,
    [Parameter(Mandatory)] [ValidateSet('amd64', 'arm64')] [string] $Architecture,
    [string] $ConfigPath = '',
    [switch] $Plan
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    if ($Platform -eq 'android' -and $Architecture -ne 'arm64' -or $Platform -eq 'windows' -and $Architecture -ne 'amd64') {
        throw 'Supported installers: android-arm64-v8a, windows-amd64, macos-amd64, macos-arm64.'
    }
    & (Join-Path $PSScriptRoot 'client.ps1') -Action Prepare -ConfigPath $ConfigPath
    $values = Get-Content -LiteralPath '.dart_tool/client-build-inputs.json' -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    $displayName = $values.APP_DISPLAY_NAME
    $version = $values.APP_VERSION
    $suffix = switch ($Platform) {
        android { 'android-arm64-v8a.apk' }
        windows { 'windows-amd64-compatible-setup.exe' }
        macos { "macos-$Architecture.dmg" }
    }
    $output = "dist/Bettbox-$version-$suffix"
    if ($Plan) {
        [PSCustomObject]@{Platform=$Platform; Architecture=$Architecture; Installer=$output; Panel=$values.METRON_BASE_URL; Portable=$false} | ConvertTo-Json -Compress
        return
    }
    function Native([string] $Command, [string[]] $Arguments) {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Command failed ($LASTEXITCODE)." }
    }
    if ($Platform -eq 'windows' -and !$IsWindows -or $Platform -eq 'macos' -and !$IsMacOS -or $Platform -eq 'android' -and !$IsLinux) {
        throw "Use the matching GitHub runner for $Platform."
    }
    New-Item -ItemType Directory -Path '.dart_tool' -Force | Out-Null
    $configFile = Join-Path $projectRoot '.dart_tool/installer-build-config.json'
    [IO.File]::WriteAllText($configFile, ($values | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if ($Platform -eq 'windows') {
        $env:GOAMD64 = 'v1'
        $env:RUSTFLAGS = '-C target-cpu=x86-64'
    }
    $defines = @("--dart-define-from-file=$configFile", '--dart-define=APP_ENV=stable', "--dart-define=APP_ASSET_SUFFIX=$suffix")
    $coreArgs = @('setup.dart', $Platform, '--arch', $Architecture, '--out', 'core')
    if ($Platform -eq 'windows') { $coreArgs += '--compatible' }
    Native 'dart' $coreArgs
    New-Item -ItemType Directory -Path 'dist' -Force | Out-Null

    if ($Platform -eq 'android') {
        $library = 'libclash/android/arm64-v8a/libmeta.so'
        if (!(Test-Path -LiteralPath $library)) { throw "Missing $library" }
        if (!(Test-Path -LiteralPath 'android/app/keystore.jks')) { throw 'Android release signing key missing.' }
        if ($env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_ENVIRONMENT -eq 'github-hosted') {
            # The native Go library is complete. Gradle/Rust do not need its
            # downloaded modules or compilation cache for the APK phase.
            Native 'go' @('clean', '-cache', '-modcache')
            Native 'df' @('-h', $projectRoot)
        }
        $manifestPath = Join-Path $projectRoot 'android/app/src/main/AndroidManifest.xml'
        $manifest = [xml]::new()
        $manifest.PreserveWhitespace = $true
        $manifest.Load($manifestPath)
        $android = 'http://schemas.android.com/apk/res/android'
        foreach ($element in $manifest.SelectNodes('//*')) {
            if ($element.LocalName -eq 'application' -or $element.GetAttribute('label', $android) -eq 'Bettbox') {
                $element.SetAttribute('label', $android, $displayName) | Out-Null
            }
        }
        $manifest.Save($manifestPath)
        Native 'flutter' (@('build', 'apk', '--release', '--no-pub', '--target-platform', 'android-arm64', '--split-per-abi') + $defines)
        Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk' -Destination $output -Force
        $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }
        Native (Join-Path $sdk 'build-tools/36.0.0/apksigner') @('verify', $output)
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $apk = [IO.Compression.ZipFile]::OpenRead((Join-Path $projectRoot $output))
        try {
            if (!$apk.GetEntry('lib/arm64-v8a/libmeta.so')) { throw 'APK missing ARM64 proxy core.' }
            if (@($apk.Entries | Where-Object { $_.FullName -match '^lib/[^/]+/[^/]+$' -and !$_.FullName.StartsWith('lib/arm64-v8a/') }).Count -gt 0) { throw 'APK contains an unexpected ABI.' }
        } finally { $apk.Dispose() }
    } else {
        $core = "libclash/$Platform/BettboxCore" + $(if ($Platform -eq 'windows') { '.exe' } else { '' })
        if (!(Test-Path -LiteralPath $core)) { throw "Missing $core" }
        if ($Platform -eq 'macos') {
            $expectedArch = if ($Architecture -eq 'amd64') { 'x86_64' } else { 'arm64' }
            $hostArch = (& /usr/bin/uname -m).Trim()
            if ($hostArch -ne $expectedArch) { throw "macOS runner architecture is $hostArch, expected $expectedArch." }
            Native '/usr/bin/codesign' @('--force', '--sign', '-', $core)
            $env:FLUTTER_XCODE_ARCHS = $expectedArch
            $env:FLUTTER_XCODE_EXCLUDED_ARCHS = if ($Architecture -eq 'amd64') { 'arm64' } else { 'x86_64' }
            $env:FLUTTER_XCODE_ONLY_ACTIVE_ARCH = 'YES'
            $env:FLUTTER_XCODE_CODE_SIGNING_ALLOWED = 'NO'
        }
        $hash = (Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash.ToLowerInvariant()
        $defines += "--dart-define=CORE_SHA256=$hash"
        Native 'flutter' (@('build', $Platform, '--release', '--no-pub') + $defines)
        if ($Platform -eq 'windows') {
            Native 'dart' @('windows/packaging/exe/package_windows.dart', '--arch', 'amd64', '--compatible', '--no-portable', '--installer', '--env', 'stable', '--config', $configFile)
        } else {
            $app = (Resolve-Path -LiteralPath 'build/macos/Build/Products/Release/Bettbox.app').Path
            foreach ($binary in @("$app/Contents/MacOS/Bettbox", "$app/Contents/MacOS/BettboxCore")) {
                $actualArch = (& /usr/bin/lipo -archs $binary).Trim()
                if ($LASTEXITCODE -ne 0 -or $actualArch -ne $expectedArch) { throw "Wrong architecture for $binary : $actualArch" }
            }
            Native 'python3' @('-c', 'import plistlib,sys; p=sys.argv[1]; d=plistlib.load(open(p,"rb")); d["CFBundleDisplayName"]=sys.argv[2]; plistlib.dump(d,open(p,"wb"),sort_keys=False)', "$app/Contents/Info.plist", $displayName)
            $frameworkRoot = "$app/Contents/Frameworks"
            if (Test-Path -LiteralPath $frameworkRoot) {
                foreach ($dylib in Get-ChildItem -LiteralPath $frameworkRoot -Filter '*.dylib' -File -Recurse) {
                    Native '/usr/bin/codesign' @('--force', '--sign', '-', $dylib.FullName)
                }
                foreach ($framework in @(Get-ChildItem -LiteralPath $frameworkRoot -Filter '*.framework' -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
                    Native '/usr/bin/codesign' @('--force', '--deep', '--sign', '-', $framework.FullName)
                }
            }
            Native '/usr/bin/codesign' @('--force', '--sign', '-', '--entitlements', 'macos/Runner/Release.entitlements', $app)
            Native '/usr/bin/codesign' @('--verify', '--deep', '--strict', $app)
            if ((Get-FileHash -LiteralPath "$app/Contents/MacOS/BettboxCore" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
                throw 'macOS core changed after its authentication hash was embedded.'
            }
            $stage = Join-Path $env:RUNNER_TEMP ('bettbox-dmg-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stage | Out-Null
            Native '/usr/bin/ditto' @($app, (Join-Path $stage "$displayName.app"))
            Native '/bin/ln' @('-s', '/Applications', (Join-Path $stage 'Applications'))
            Native '/usr/bin/hdiutil' @('create', '-volname', $displayName, '-srcfolder', $stage, '-format', 'UDZO', '-ov', $output)
            Native '/usr/bin/hdiutil' @('verify', $output)
        }
    }
    if (!(Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -eq 0) { throw "Installer missing: $output" }
    $checksum = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $projectRoot "$output.sha256"), "$checksum  $([IO.Path]::GetFileName($output))`n", [Text.Encoding]::ASCII)
    if ($env:GITHUB_OUTPUT) { "installer=$output" | Add-Content -LiteralPath $env:GITHUB_OUTPUT }
    if ($env:GITHUB_STEP_SUMMARY) { "Installer: $output`nSHA256: $checksum" | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY }
    Write-Host "Installer ready: $output"
} finally {
    Pop-Location
}
