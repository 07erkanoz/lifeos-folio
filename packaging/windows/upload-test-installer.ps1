$ErrorActionPreference = 'Stop'
foreach ($required in @('GITHUB_REPOSITORY', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'RUNNER_TEMP')) {
    if (![Environment]::GetEnvironmentVariable($required)) { throw "Missing CI environment: $required" }
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $root 'build/windows/installer'
$setups = @(Get-ChildItem -LiteralPath $output -Filter '*-Setup.exe')
if ($setups.Count -ne 1) { throw 'Expected exactly one Windows installer.' }
$setup = $setups[0].FullName
$checksum = "$setup.sha256"
if (!(Test-Path -LiteralPath $checksum)) { throw 'Installer checksum is missing.' }
$expectedHash = ((Get-Content -LiteralPath $checksum -Raw).Trim() -split '\s+')[0]
if ((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Installer does not match its checksum.'
}
# Publish manual test builds as prereleases without replacing the latest stable
# release. Release storage is independent of the Actions artifact storage quota.
$tag = "windows-test-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$runUrl = "https://github.com/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
$notesFile = Join-Path $env:RUNNER_TEMP 'folio-windows-release-notes.md'
@"
Windows x64 test kurulumu. Kurulum, güncelleme ve kaldırma kontrollerinden geçmiştir.

Kaynak commit: $env:GITHUB_SHA
Derleme: $runUrl

Setup.exe ve SHA-256 sağlama dosyası ektedir. Kurulum henüz kod imzalama sertifikasıyla imzalanmamıştır.
"@ | Set-Content -LiteralPath $notesFile -Encoding utf8
& gh release create $tag $setup $checksum --repo $env:GITHUB_REPOSITORY --target $env:GITHUB_SHA `
    --prerelease --latest=false --title "LifeOS Folio Windows Setup - test $env:GITHUB_RUN_ID" --notes-file $notesFile
if ($LASTEXITCODE -ne 0) { throw 'Publishing the Windows installer test release failed.' }
$url = & gh release view $tag --repo $env:GITHUB_REPOSITORY --json url --jq .url
if ($LASTEXITCODE -ne 0 -or !$url) { throw 'Could not read the installer test release URL.' }
if ($env:GITHUB_STEP_SUMMARY) {
    "Windows Setup hazır: [Test sürümünden indir]($url)." |
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
}
Write-Host "Windows installer uploaded: $url"
