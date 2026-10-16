function Restore-LatencyBackup {
    <#
    .SYNOPSIS
        Desfaz alterações feitas por Set-LatencyRecommendation a partir de um arquivo de backup.
    .DESCRIPTION
        Lê o JSON de backup e executa o Undo de cada regra com o estado salvo, na ordem
        inversa da aplicação. Valores que não existiam antes são removidos em vez de
        ficarem com um padrão inventado.
    .PARAMETER Path
        Caminho do arquivo LatencyAudit-backup-*.json.
    .EXAMPLE
        Get-ChildItem $env:ProgramData\LatencyAudit\backups | Sort-Object LastWriteTime |
            Select-Object -Last 1 | Restore-LatencyBackup -WhatIf
    .EXAMPLE
        Restore-LatencyBackup -Path C:\ProgramData\LatencyAudit\backups\LatencyAudit-backup-20261016-101500-123.json
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('LatencyAudit.ChangeResult')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path
    )

    process {
        $backup = Read-LatencyBackupFile -Path $Path
        $catalog = Get-LaRuleCatalog
        $entries = @($backup.Entries)
        [array]::Reverse($entries)

        foreach ($entry in $entries) {
            $id = $entry.RuleId
            $rule = Find-LaRule -Catalog $catalog -Id $id
            if (-not $rule -or -not $rule.Undo) {
                Write-Warning "Regra '$id' não existe nesta versão ou não tem Undo; entrada ignorada."
                New-LaChangeResult -RuleId $id -Status 'Skipped' -Message 'Regra desconhecida ou sem Undo.'
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($rule.Title, "Restaurar valores anteriores de '$id'")) { continue }

            if ($rule.RequiresAdmin -and -not (Test-LaAdmin)) {
                Write-Error "A regra '$id' exige PowerShell como administrador para restaurar."
                continue
            }
            try {
                & $rule.Undo $entry.State $rule
                New-LaChangeResult -RuleId $id -Status 'Restored' -BackupPath $Path `
                    -RebootRequired $rule.RebootRequired -Message 'Valores anteriores restaurados.'
            }
            catch {
                Write-Error "Falha ao restaurar '$id': $($_.Exception.Message)"
                New-LaChangeResult -RuleId $id -Status 'Failed' -BackupPath $Path -Message $_.Exception.Message
            }
        }
    }
}
