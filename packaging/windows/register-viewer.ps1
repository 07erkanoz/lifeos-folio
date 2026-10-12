param([Parameter(Mandatory=$true)][string]$Executable, [string]$SelectedExtensions = '', [switch]$ContextMenuOnly)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$progId = 'LifeOSEvrak.Document'
$classes = 'HKCU:\Software\Classes'
# The same keys as the installer (folio.iss) writes: a press here must never
# leave Windows with less than the installer told it.

# A key made when it is missing, and left as it is when it is there.
# New-Item -Force on a key that exists recreates it and drops its values:
# other programs' Open with entries under the same extension among them.
function Ensure-Key([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
}
function Set-Default([string]$Path, [string]$Value) {
    Ensure-Key $Path
    Set-Item -LiteralPath $Path -Value $Value
}
function Set-Value([string]$Path, [string]$Name, [string]$Value) {
    Ensure-Key $Path
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType String -Value $Value -Force | Out-Null
}
# Explorer keeps what it knows of the file types until it is told they changed.
function Notify-Explorer {
    try {
        Add-Type -Namespace Folio -Name Shell -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);'
        [Folio.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    } catch { }
}

$icon = '"' + $exe + '",0'
$previewCommand = '"' + $exe + '" --preview -- "%1"'
$editCommand = '"' + $exe + '" --edit -- "%1"'

# Explorer verbs apply even when another viewer is the default. Only supported
# extensions receive verbs; no global * shell entries or UserChoice changes.
$previewExtensions = 'pdf','udf','docx','xlsx','odt','txt','md','markdown','html','htm','csv','tsv','json','xml','log','png','jpg','jpeg','gif','webp','bmp','tif','tiff','svg'
$editExtensions = 'pdf','udf','docx','xlsx','odt','txt','md','markdown','html','htm','csv','tsv','json','xml','log'
foreach ($extension in $previewExtensions) {
    $verbs = @(@{Id='Preview'; Label='Folio ile önizle'; Command=$previewCommand})
    if ($extension -in $editExtensions) { $verbs += @{Id='Edit'; Label='Folio ile düzenle'; Command=$editCommand} }
    foreach ($verb in $verbs) {
        $key = "$classes\SystemFileAssociations\.$extension\shell\LifeOSFolio.$($verb.Id)"
        Set-Default $key $verb.Label
        Set-Value $key 'Icon' $icon
        Set-Value $key 'MultiSelectModel' 'Document'
        Set-Default "$key\command" $verb.Command
    }
}
if ($ContextMenuOnly) { Notify-Explorer; return }

$extensions = $previewExtensions
if ($SelectedExtensions) {
    foreach ($item in $SelectedExtensions.Split(',')) {
        if ($item -notin $extensions) { throw "Unsupported extension: $item" }
    }
}

# The document type: opened in the preview, as the installer has it, with
# "Düzenle" beside it.
Set-Default "$classes\$progId" 'LifeOS Folio Belgesi'
Set-Default "$classes\$progId\DefaultIcon" $icon
Set-Default "$classes\$progId\shell" 'open'
Set-Default "$classes\$progId\shell\open" 'Folio ile önizle'
Set-Default "$classes\$progId\shell\open\command" $previewCommand
Set-Default "$classes\$progId\shell\edit" 'Folio ile düzenle'
Set-Default "$classes\$progId\shell\edit\command" $editCommand

# Open with: Folio by its own name, for every type it reads.
$application = "$classes\Applications\lifeos_folio.exe"
Set-Value $application 'FriendlyAppName' 'LifeOS Folio'
Set-Default "$application\DefaultIcon" $icon
Set-Default "$application\shell\open\command" $previewCommand
Set-Default "$application\shell\edit\command" $editCommand

# What Windows' Default apps page lists for Folio: every supported type, so
# that each can be given to it there. The choice itself stays the user's.
$capabilities = 'HKCU:\Software\LifeOSEvrak\Capabilities'
Set-Value $capabilities 'ApplicationName' 'LifeOS Folio'
Set-Value $capabilities 'ApplicationDescription' 'Belge arama, önizleme ve düzenleme'
Set-Value $capabilities 'ApplicationIcon' $icon
foreach ($extension in $extensions) {
    Set-Value "$classes\.$extension\OpenWithProgids" $progId ''
    Set-Value "$application\SupportedTypes" ".$extension" ''
    Set-Value "$capabilities\FileAssociations" ".$extension" $progId
}
Set-Value 'HKCU:\Software\RegisteredApplications' 'LifeOSEvrak' 'Software\LifeOSEvrak\Capabilities'
# Defaults remain under the user's control. Never modify UserChoice hashes.
Notify-Explorer
