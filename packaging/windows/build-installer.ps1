param([string]$BundleDirectory = '', [string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (!$BundleDirectory) { $BundleDirectory = Join-Path $root 'build/windows/x64/runner/Release' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root 'build/windows/installer' }
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
foreach ($required in @('lifeos_folio.exe', 'flutter_windows.dll', 'data/flutter_assets',
    'tools/bin/qpdf.exe', 'tools/bin/tiffcp.exe', 'tools/bin/tesseract.exe',
    'tools/tessdata/tur.traineddata')) {
    if (!(Test-Path -LiteralPath (Join-Path $bundle $required))) { throw "Missing release component: $required" }
}
# Ship Microsoft's redistributable CRT beside the executable: no separate
# download, machine-wide runtime install or administrator prompt on the client.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Visual Studio C++ redistributable location could not be found.' }
$redist = Get-ChildItem -LiteralPath (Join-Path $vs 'VC/Redist/MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$redist) { throw 'No Visual C++ runtime version was found.' }
$crt = Get-ChildItem -LiteralPath (Join-Path $redist.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
if (!$crt) { throw 'The x64 CRT redistribution directory is missing.' }
Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $bundle -Force
foreach ($dll in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $bundle $dll))) { throw "Missing C++ runtime: $dll" }
}
$versionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)')
if (!$versionMatch.Success) { throw 'pubspec.yaml does not contain a release version.' }
$version = $versionMatch.Groups[1].Value
$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (!(Test-Path -LiteralPath $iscc)) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if (!$command) { throw 'Inno Setup 6.3 or newer is required to build the installer.' }
    $iscc = $command.Source
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
& $iscc "/DAppVersion=$version" "/DBundleDir=$bundle" "/DInstallerOutput=$output" (Join-Path $PSScriptRoot 'folio.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed: $LASTEXITCODE" }
$setup = Join-Path $output "LifeOS-Folio-$version-Windows-x64-Setup.exe"
if (!(Test-Path -LiteralPath $setup)) { throw 'Installer output was not produced.' }
$hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$setup.sha256", "$hash  $([IO.Path]::GetFileName($setup))`n")
Write-Host "Installer ready: $setup"
