$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1')
$public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1')

foreach ($file in @($private) + @($public)) {
    . $file.FullName
}

Update-TypeData -TypeName 'LatencyAudit.Result' -DefaultDisplayPropertySet Category, Id, Status, Severity, CurrentText, Expected -Force
Update-TypeData -TypeName 'LatencyAudit.Audit' -DefaultDisplayPropertySet Score, Grade, ComputerName, Passed, Failed, Info, Skipped -Force

Export-ModuleMember -Function $public.BaseName
