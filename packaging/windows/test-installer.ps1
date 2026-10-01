$ErrorActionPreference = 'Stop'
# This test installs and unregisters Folio; only run on the disposable CI runner.
if ($env:GITHUB_ACTIONS -ne 'true' -or !$env:RUNNER_TEMP) {
    throw 'Installer smoke tests must run on a disposable GitHub Actions runner.'
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $root 'build/windows/installer'
$setups = @(Get-ChildItem -LiteralPath $output -Filter '*-Setup.exe')
if ($setups.Count -ne 1) { throw 'Expected exactly one Setup executable.' }
$installDir = Join-Path $env:RUNNER_TEMP 'Folio Setup Test'
$exe = Join-Path $installDir 'lifeos_folio.exe'
$programShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'LifeOS Folio.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'LifeOS Folio.lnk'
$progId = 'HKCU:\Software\Classes\LifeOSEvrak.Document'
$capabilities = 'HKCU:\Software\LifeOSEvrak\Capabilities'
$contextBase = 'HKCU:\Software\Classes\SystemFileAssociations\.udf\shell'

function Invoke-Setup([string]$file, [string]$arguments, [string]$log) {
    $process = Start-Process -FilePath $file -ArgumentList "$arguments /LOG=`"$log`"" -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 100 | Write-Host }
        throw "Installer process failed with exit code $($process.ExitCode)."
    }
}

$options = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
$installOptions = "$options /DIR=`"$installDir`" /TASKS=`"desktopicon,associations,contextmenu`""
Invoke-Setup $setups[0].FullName $installOptions (Join-Path $output 'install.log')
foreach ($required in @('lifeos_folio.exe', 'flutter_windows.dll', 'data/flutter_assets',
    'tools/bin/qpdf.exe', 'tools/bin/tiffcp.exe', 'tools/bin/tesseract.exe',
    'tools/tessdata/tur.traineddata', 'vcruntime140.dll', 'vcruntime140_1.dll',
    'msvcp140.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $installDir $required))) { throw "Missing installed component: $required" }
}
foreach ($shortcut in @($programShortcut, $desktopShortcut)) {
    if (!(Test-Path -LiteralPath $shortcut)) { throw "Missing shortcut: $shortcut" }
}
$expectedPreview = "`"$exe`" --preview -- `"%1`""
if ((Get-Item "$progId\shell\open\command").GetValue('') -ne $expectedPreview) {
    throw 'Open command does not quote the executable and document correctly.'
}
foreach ($extension in @('.pdf', '.udf', '.docx', '.xlsx', '.tif')) {
    if ((Get-Item "$capabilities\FileAssociations").GetValue($extension) -ne 'LifeOSEvrak.Document') {
        throw "Missing file registration: $extension"
    }
}
if ((Get-Item "$contextBase\LifeOSFolio.Preview\command").GetValue('') -ne $expectedPreview) {
    throw 'Preview context command is incorrect.'
}
if ((Get-Item "$contextBase\LifeOSFolio.Edit\command").GetValue('') -ne "`"$exe`" --edit -- `"%1`"") {
    throw 'Edit context command is incorrect.'
}
# Installing over an existing version must keep unrelated user files intact.
$sentinel = Join-Path $installDir 'user-document.txt'
[IO.File]::WriteAllText($sentinel, 'preserve during upgrade and uninstall')
Invoke-Setup $setups[0].FullName $installOptions (Join-Path $output 'upgrade.log')
if (!(Test-Path -LiteralPath $sentinel)) { throw 'Upgrade deleted a user file.' }
Invoke-Setup (Join-Path $installDir 'unins000.exe') $options (Join-Path $output 'uninstall.log')
foreach ($removed in @($exe, $programShortcut, $desktopShortcut, $progId, $capabilities,
    "$contextBase\LifeOSFolio.Preview", "$contextBase\LifeOSFolio.Edit")) {
    if (Test-Path -LiteralPath $removed) { throw "Uninstall left an owned component: $removed" }
}
if (!(Test-Path -LiteralPath $sentinel)) { throw 'Uninstall deleted a user file.' }
Write-Host 'Installation, upgrade, shortcuts, document commands and uninstallation passed.'
