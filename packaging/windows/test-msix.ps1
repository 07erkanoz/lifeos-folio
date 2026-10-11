$ErrorActionPreference = 'Stop'
# Installs the Store package on the disposable CI runner, signed for this
# test alone with a certificate made here and thrown away: both apps must
# start from it, Folio must write its data into the user folder (outside
# the AppData Windows keeps apart for a package) and that data must stay
# when the package is removed. Microsoft's certification kit then runs on
# the same signed package and leaves its report beside the packages.
if ($env:GITHUB_ACTIONS -ne 'true' -or !$env:RUNNER_TEMP) {
    throw 'MSIX smoke tests must run on a disposable GitHub Actions runner.'
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $root 'build/windows/msix'
$stores = @(Get-ChildItem -LiteralPath $output -Filter '*-Store.msix')
if ($stores.Count -ne 1) { throw 'Expected exactly one Store package.' }

$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
$signtool = Get-ChildItem -LiteralPath $kits -Recurse -Filter signtool.exe |
    Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1
if (!$signtool) { throw 'signtool.exe was not found.' }

$test = Join-Path $env:RUNNER_TEMP 'folio-msix-test.msix'
Copy-Item -LiteralPath $stores[0].FullName -Destination $test -Force
$publisher = 'CN=A88DF4A4-5857-47AC-959B-C26094290704'
$cert = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature `
    -FriendlyName 'Folio MSIX CI test' -CertStoreLocation 'Cert:\CurrentUser\My' `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
$pfx = Join-Path $env:RUNNER_TEMP 'folio-msix-test.pfx'
$password = ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $password | Out-Null
$cer = Join-Path $env:RUNNER_TEMP 'folio-msix-test.cer'
Export-Certificate -Cert $cert -FilePath $cer | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
& $signtool.FullName sign /fd SHA256 /f $pfx /p $plain $test | Out-Host
if ($LASTEXITCODE -ne 0) { throw "signtool failed: $LASTEXITCODE" }
Remove-Item -LiteralPath $pfx -Force

$data = Join-Path $env:USERPROFILE 'LifeOS Folio'
if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force }
# What Folio writes on every start (desktop_instance.dart).
$written = Join-Path $data 'desktop-instance.json'

Add-AppxPackage -Path $test
try {
    $package = Get-AppxPackage -Name 'ErkanZ.LifeOSFolioAvukatlariin'
    if (!$package) { throw 'The package did not install.' }
    foreach ($required in @('lifeos_folio.exe', 'lifeos_editor.exe', 'resources.pri',
        'vcruntime140.dll', 'msvcp140.dll', 'tools/bin/tesseract.exe')) {
        if (!(Test-Path -LiteralPath (Join-Path $package.InstallLocation $required))) {
            throw "Missing packaged component: $required"
        }
    }
    foreach ($app in @(@{ Id = 'Folio'; Process = 'lifeos_folio' }, @{ Id = 'Editor'; Process = 'lifeos_editor' })) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($package.PackageFamilyName)!$($app.Id)"
        $running = $null
        for ($i = 0; $i -lt 30 -and !$running; $i++) {
            Start-Sleep -Seconds 2
            $running = Get-Process -Name $app.Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -like "$($package.InstallLocation)*" }
        }
        if (!$running) { throw "$($app.Id) did not start from the package." }
        # Still there a while later: it did not fall over on first use.
        Start-Sleep -Seconds 10
        if ($running | Where-Object { $_.HasExited }) { throw "$($app.Id) exited soon after starting." }
        $running | Stop-Process -Force
        Write-Host "$($app.Id) started from the package."
    }
    if (!(Test-Path -LiteralPath $written)) {
        throw "Folio from the package did not write its data into $data."
    }
} finally {
    Get-Process -Name 'lifeos_folio', 'lifeos_editor' -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-AppxPackage -Name 'ErkanZ.LifeOSFolioAvukatlariin' | Remove-AppxPackage
}
if (!(Test-Path -LiteralPath $written)) { throw 'Removing the package deleted Folio data.' }
Write-Host 'MSIX install, start of both apps, data in the user folder and removal passed.'

# Windows App Certification Kit, as the Store runs it. Its verdict is
# reported, not yet enforced: a Windows Server runner may differ from a
# Windows 10/11 client, so the report is read before the Store sees it.
$appcert = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/App Certification Kit/appcert.exe'
if (Test-Path -LiteralPath $appcert) {
    $report = Join-Path $output 'wack-report.xml'
    & $appcert reset | Out-Host
    & $appcert test -appxpackagepath $test -reportoutputpath $report | Out-Host
    $wackExit = $LASTEXITCODE
    if ($wackExit -ne 0) { Write-Host "::warning::appcert exited with $wackExit." }
    if (Test-Path -LiteralPath $report) {
        [xml]$wack = Get-Content -LiteralPath $report -Raw
        $overall = $wack.REPORT.OVERALL_RESULT
        Write-Host "WACK: $overall"
        foreach ($t in @($wack.SelectNodes('//TEST[RESULT="FAIL"]'))) {
            Write-Host "::warning::WACK failed: $($t.NAME) - $($t.DESCRIPTION)"
        }
    } else {
        Write-Host '::warning::WACK produced no report.'
    }
    Get-AppxPackage -Name 'ErkanZ.LifeOSFolioAvukatlariin' | Remove-AppxPackage
} else {
    Write-Host '::warning::The Windows App Certification Kit is not on this runner.'
}
# The kit's own exit code is reported above, not passed on as this test's.
exit 0
