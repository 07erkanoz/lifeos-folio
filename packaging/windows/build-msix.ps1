param([string]$BundleDirectory = '', [string]$OutputDirectory = '')
# Folio's Microsoft Store package, from the bundle build-installer.ps1 has
# already completed with the C++ runtime. Two packages come out:
#   LifeOS-Folio-<version>-Store.msix  unsigned, for Partner Center, which
#                                      signs it with the reserved identity;
#   LifeOS-Folio-<version>-Deneme.msix unsigned as well, but with the
#                                      publisher Windows 11 installs with
#                                      Add-AppxPackage -AllowUnsigned, to try
#                                      a package before it goes to the Store.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (!$BundleDirectory) { $BundleDirectory = Join-Path $root 'build/windows/x64/runner/Release' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root 'build/windows/msix' }
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
foreach ($required in @('lifeos_folio.exe', 'lifeos_editor.exe', 'flutter_windows.dll',
    'data/flutter_assets', 'tools/bin/qpdf.exe', 'tools/bin/tesseract.exe',
    'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $bundle $required))) { throw "Missing package component: $required" }
}

# The Store takes major.minor.build.0: the fourth part is its own.
$versionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)')
if (!$versionMatch.Success) { throw 'pubspec.yaml does not contain a release version.' }
$version = $versionMatch.Groups[1].Value
$packageVersion = "$version.0"

# The newest Windows SDK's tools.
$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
$sdk = Get-ChildItem -LiteralPath $kits -Directory | Where-Object { $_.Name -match '^10\.' } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64/makeappx.exe') } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$sdk) { throw 'Windows SDK with makeappx.exe was not found.' }
$makeappx = Join-Path $sdk.FullName 'x64/makeappx.exe'
$makepri = Join-Path $sdk.FullName 'x64/makepri.exe'

$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'msix/AppxManifest.xml') -Raw -Encoding UTF8
$storePublisher = 'CN=A88DF4A4-5857-47AC-959B-C26094290704'
# Microsoft's mark for a package that is installed unsigned.
$unsignedPublisher = "$storePublisher, OID.2.25.311729368913984317654407730594956997722=1"

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($variant in @(@{ Name = 'Store'; Publisher = $storePublisher },
                       @{ Name = 'Deneme'; Publisher = $unsignedPublisher })) {
    $stage = Join-Path $output "stage-$($variant.Name)"
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -Path (Join-Path $bundle '*') -Destination $stage -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'msix/Assets') -Destination (Join-Path $stage 'Assets') -Recurse -Force
    $manifest = $template.Replace('{VERSION}', $packageVersion).Replace('{PUBLISHER}', $variant.Publisher)
    if ($manifest -match '\{[A-Z]+\}') { throw 'A placeholder is left in the manifest.' }
    [IO.File]::WriteAllText((Join-Path $stage 'AppxManifest.xml'), $manifest, $utf8)

    # resources.pri, for the logos' scale and target-size variants; indexed
    # from the logos alone, not the whole bundle.
    $pri = Join-Path $output "pri-$($variant.Name)"
    if (Test-Path -LiteralPath $pri) { Remove-Item -LiteralPath $pri -Recurse -Force }
    New-Item -ItemType Directory -Path $pri | Out-Null
    Copy-Item -LiteralPath (Join-Path $stage 'Assets') -Destination (Join-Path $pri 'Assets') -Recurse
    Copy-Item -LiteralPath (Join-Path $stage 'AppxManifest.xml') -Destination $pri
    $config = Join-Path $output "priconfig-$($variant.Name).xml"
    & $makepri createconfig /cf $config /dq tr-TR /pv 10.0.0 /o | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "makepri createconfig failed: $LASTEXITCODE" }
    # The default config splits scales into resource packages, which a
    # single .msix does not carry: every variant goes into one resources.pri.
    [xml]$priConfig = Get-Content -LiteralPath $config -Raw
    foreach ($node in @($priConfig.SelectNodes('//packaging'))) { [void]$node.ParentNode.RemoveChild($node) }
    $priConfig.Save($config)
    $resources = Join-Path $stage 'resources.pri'
    & $makepri new /pr $pri /cf $config /mn (Join-Path $pri 'AppxManifest.xml') /of $resources /o | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "makepri new failed: $LASTEXITCODE" }
    $extra = @(Get-ChildItem -LiteralPath $stage -Filter 'resources.*.pri')
    if ($extra.Count) { throw "makepri split the resources: $($extra.Name -join ', ')" }
    $dump = Join-Path $output "resources-$($variant.Name).xml"
    & $makepri dump /if $resources /of $dump /o | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "makepri dump failed: $LASTEXITCODE" }
    # Every logo, with its scale or target size, must be a candidate.
    $listed = (Get-Content -LiteralPath $dump -Raw).Replace('/', '\')
    $assets = @(Get-ChildItem -LiteralPath (Join-Path $stage 'Assets') -Filter '*.png')
    if ($assets.Count -lt 55) { throw "Only $($assets.Count) logos were packaged." }
    # The certification kit's limit for one image.
    foreach ($asset in $assets) {
        if ($asset.Length -ge 204800) { throw "$($asset.Name) is not under 200 KB." }
    }
    foreach ($asset in $assets) {
        if (!$listed.Contains("Assets\$($asset.Name)")) { throw "resources.pri lacks Assets\$($asset.Name)" }
    }
    Copy-Item -LiteralPath $dump -Destination (Join-Path $output "resources-$($variant.Name)-dump.xml") -Force

    $package = Join-Path $output "LifeOS-Folio-$version-$($variant.Name).msix"
    & $makeappx pack /d $stage /p $package /o | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed: $LASTEXITCODE" }
    Remove-Item -LiteralPath $stage, $pri -Recurse -Force
    Remove-Item -LiteralPath $config, $dump -Force
    $hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$package.sha256", "$hash  $([IO.Path]::GetFileName($package))`n")
    Write-Host "MSIX ready: $package"
}
