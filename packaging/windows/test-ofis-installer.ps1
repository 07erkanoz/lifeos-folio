$ErrorActionPreference = 'Stop'
# Installs and removes LifeOS Ofis; only run on the disposable CI runner.
if ($env:GITHUB_ACTIONS -ne 'true' -or !$env:RUNNER_TEMP) {
    throw 'Installer smoke tests must run on a disposable GitHub Actions runner.'
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $root 'build/windows/installer-ofis'
$setups = @(Get-ChildItem -LiteralPath $output -Filter '*-Setup.exe')
if ($setups.Count -ne 1) { throw 'Expected exactly one LifeOS Ofis Setup executable.' }
$installDir = Join-Path $env:RUNNER_TEMP 'Ofis Setup Test'
$exe = Join-Path $installDir 'lifeos_ofis.exe'
$programShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'LifeOS Ofis.lnk'
$application = 'HKCU:\Software\Classes\Applications\lifeos_ofis.exe'

function Invoke-Setup([string]$file, [string]$arguments, [string]$log) {
    $process = Start-Process -FilePath $file -ArgumentList "$arguments /LOG=`"$log`"" -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 100 | Write-Host }
        throw "Installer process failed with exit code $($process.ExitCode)."
    }
}

$options = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
Invoke-Setup $setups[0].FullName "$options /DIR=`"$installDir`" /TASKS=`"desktopicon,associations`"" (Join-Path $output 'install.log')
foreach ($required in @('lifeos_ofis.exe', 'flutter_windows.dll', 'data/flutter_assets',
    'tools/bin/qpdf.exe', 'tools/bin/tesseract.exe', 'tools/tessdata/tur.traineddata',
    'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $installDir $required))) { throw "Missing installed component: $required" }
}
# Folio's own programs are not Ofis's to install.
foreach ($foreign in @('lifeos_folio.exe', 'lifeos_editor.exe')) {
    if (Test-Path -LiteralPath (Join-Path $installDir $foreign)) { throw "LifeOS Ofis installed Folio's program: $foreign" }
}
if (!(Test-Path -LiteralPath $programShortcut)) { throw "Missing shortcut: $programShortcut" }
if ((Get-Item "$application\shell\open\command").GetValue('') -ne "`"$exe`" -- `"%1`"") {
    throw 'Open command does not quote the executable and document correctly.'
}
foreach ($extension in @('.udf', '.docx', '.pdf', '.imz')) {
    if ($null -eq (Get-Item "$application\SupportedTypes").GetValue($extension)) { throw "Missing supported type: $extension" }
}
# It starts, shows a window titled as itself, and stays up.
$process = Start-Process -FilePath $exe -PassThru
try {
    $shown = $false
    for ($i = 0; $i -lt 60 -and !$shown; $i++) {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        if ($process.HasExited) { throw "LifeOS Ofis exited at start with code $($process.ExitCode)." }
        $shown = $process.MainWindowTitle -like '*LifeOS Ofis*'
    }
    if (!$shown) { throw "LifeOS Ofis did not show its window (title: '$($process.MainWindowTitle)')." }
} finally {
    if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
}
$uninstaller = Join-Path $installDir 'unins000.exe'
if (!(Test-Path -LiteralPath $uninstaller)) { throw 'Uninstaller is missing.' }
Invoke-Setup $uninstaller $options (Join-Path $output 'uninstall.log')
if (Test-Path -LiteralPath $exe) { throw 'Uninstall left lifeos_ofis.exe behind.' }
if (Test-Path -LiteralPath $application) { throw 'Uninstall left the Open with registration behind.' }
Write-Host 'LifeOS Ofis installer smoke test passed.'
