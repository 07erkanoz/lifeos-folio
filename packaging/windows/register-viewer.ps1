param([Parameter(Mandatory=$true)][string]$Executable, [string]$SelectedExtensions = '', [switch]$ContextMenuOnly)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Executable).Path
$progId = 'LifeOSEvrak.Document'
$classes = 'HKCU:\Software\Classes'
# Explorer verbs apply even when another viewer is the default. Only supported
# extensions receive verbs; no global * shell entries or UserChoice changes.
$previewExtensions = 'pdf','udf','docx','xlsx','odt','txt','md','markdown','html','htm','csv','tsv','json','xml','log','png','jpg','jpeg','gif','webp','bmp','tif','tiff','svg'
$editExtensions = 'pdf','udf','docx','xlsx','odt','txt','md','markdown','html','htm','csv','tsv','json','xml','log'
foreach ($extension in $previewExtensions) {
    $verbs = @(@{Id='Preview'; Label='Folio ile önizle'; Flag='--preview'})
    if ($extension -in $editExtensions) { $verbs += @{Id='Edit'; Label='Folio ile düzenle'; Flag='--edit'} }
    foreach ($verb in $verbs) {
        $key = "$classes\SystemFileAssociations\.$extension\shell\LifeOSFolio.$($verb.Id)"
        New-Item -Path "$key\command" -Force | Out-Null
        Set-Item -LiteralPath $key -Value $verb.Label
        New-ItemProperty -LiteralPath $key -Name Icon -PropertyType String -Value ('"' + $exe + '",0') -Force | Out-Null
        New-ItemProperty -LiteralPath $key -Name MultiSelectModel -PropertyType String -Value 'Document' -Force | Out-Null
        Set-Item -LiteralPath "$key\command" -Value ('"' + $exe + '" ' + $verb.Flag + ' -- "%1"')
    }
}
if ($ContextMenuOnly) { return }
New-Item -Path "$classes\$progId\shell\open\command" -Force | Out-Null
Set-Item -LiteralPath "$classes\$progId" -Value 'LifeOS Folio Belgesi'
Set-Item -LiteralPath "$classes\$progId\shell\open\command" -Value ('"' + $exe + '" "%1"')
New-Item -Path "$classes\$progId\DefaultIcon" -Force | Out-Null
Set-Item -LiteralPath "$classes\$progId\DefaultIcon" -Value ('"' + $exe + '",0')
$capabilities = 'HKCU:\Software\LifeOSEvrak\Capabilities'
New-Item -Path "$capabilities\FileAssociations" -Force | Out-Null
New-ItemProperty -Path $capabilities -Name ApplicationName -Value 'LifeOS Folio' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $capabilities -Name ApplicationDescription -Value 'Evrak arama, önizleme ve dönüştürme' -PropertyType String -Force | Out-Null
$extensions = 'pdf','udf','docx','xlsx','odt','txt','md','markdown','html','htm','csv','tsv','json','xml','log','png','jpg','jpeg','gif','webp','bmp','tif','tiff','svg'
if ($SelectedExtensions) {
    $selected = $SelectedExtensions.Split(',')
    foreach ($item in $selected) {
        if ($item -notin $extensions) { throw "Unsupported extension: $item" }
    }
    $extensions = $selected
}
# Capabilities describe the requested selection, without changing UserChoice.
Remove-Item -LiteralPath "$capabilities\FileAssociations" -Recurse -Force
New-Item -Path "$capabilities\FileAssociations" -Force | Out-Null
foreach ($extension in $extensions) {
    New-Item -Path "$classes\.$extension\OpenWithProgids" -Force | Out-Null
    New-ItemProperty -Path "$classes\.$extension\OpenWithProgids" -Name $progId -PropertyType String -Value '' -Force | Out-Null
    New-ItemProperty -Path "$capabilities\FileAssociations" -Name ".$extension" -Value $progId -PropertyType String -Force | Out-Null
}
New-Item -Path 'HKCU:\Software\RegisteredApplications' -Force | Out-Null
New-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name LifeOSEvrak -Value 'Software\LifeOSEvrak\Capabilities' -PropertyType String -Force | Out-Null
# Defaults remain under the user's control. Never modify UserChoice hashes.
