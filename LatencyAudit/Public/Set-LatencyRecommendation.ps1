function Set-LatencyRecommendation {
    <#
    .SYNOPSIS
        Aplica as correções recomendadas, com backup prévio dos valores atuais.
    .DESCRIPTION
        Para cada regra solicitada: reavalia o estado atual, ignora o que já está conforme,
        grava um backup JSON com os valores anteriores em %ProgramData%\LatencyAudit\backups
        e só então aplica a correção. Use Restore-LatencyBackup para desfazer.

        Só exige administrador ao aplicar de fato; -WhatIf funciona sem elevação.
        Regras que reduzem a segurança (VBS/HVCI) exigem -Force e mostram um aviso.
    .PARAMETER RuleId
        Ids das regras a aplicar (veja Get-LatencyRule).
    .PARAMETER Force
        Autoriza regras marcadas como RequiresForce, que trocam segurança por desempenho.
    .PARAMETER BackupDirectory
        Pasta dos backups. Padrão: %ProgramData%\LatencyAudit\backups.
    .EXAMPLE
        Set-LatencyRecommendation -RuleId game-dvr, mouse-acceleration -WhatIf
    .EXAMPLE
        Set-LatencyRecommendation -RuleId power-plan -Confirm:$false
    .EXAMPLE
        Set-LatencyRecommendation -RuleId vbs-hvci -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('LatencyAudit.ChangeResult')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ArgumentCompleter({
                Get-LatencyRule -Id "$($args[2])*" | Where-Object Fix | ForEach-Object Id
            })]
        [string[]]$RuleId,

        [switch]$Force,

        [string]$BackupDirectory = (Get-LaBackupDirectory)
    )

    $catalog = Get-LaRuleCatalog
    $pending = [System.Collections.Generic.List[object]]::new()

    foreach ($id in $RuleId) {
        $rule = Find-LaRule -Catalog $catalog -Id $id
        if (-not $rule) {
            Write-Error "Regra desconhecida: '$id'. Use Get-LatencyRule para listar."
            continue
        }
        if (-not $rule.Fix) {
            Write-Error "A regra '$id' não tem correção automática."
            continue
        }
        if ($rule.RequiresForce -and -not $Force) {
            Write-Error "A regra '$id' reduz a segurança e exige -Force. $($rule.Warning)"
            continue
        }

        $current = Invoke-LatencyRule -Rule $rule
        if ($current.Status -in 'Skipped', 'Error') {
            Write-Warning "Regra '$id' ignorada: $($current.Detail)"
            New-LaChangeResult -RuleId $id -Status 'Skipped' -Message $current.Detail
            continue
        }
        if ($current.Compliant) {
            New-LaChangeResult -RuleId $id -Status 'AlreadyCompliant' -Message 'Já está conforme, nada a fazer.'
            continue
        }

        if ($rule.Warning) { Write-Warning $rule.Warning }
        if (-not $PSCmdlet.ShouldProcess($rule.Title, "Aplicar correção '$id'")) { continue }

        if ($rule.RequiresAdmin -and -not (Test-LaAdmin)) {
            Write-Error "A regra '$id' exige PowerShell como administrador."
            continue
        }
        $pending.Add([pscustomobject]@{ Rule = $rule; RuleId = $id; State = (& $rule.Backup $rule) })
    }

    if ($pending.Count -eq 0) { return }

    $backupPath = Write-LatencyBackupFile -Entry $pending -Directory $BackupDirectory
    Write-Verbose "Backup gravado em $backupPath"

    foreach ($item in $pending) {
        try {
            & $item.Rule.Fix $item.Rule
            New-LaChangeResult -RuleId $item.RuleId -Status 'Applied' -BackupPath $backupPath `
                -RebootRequired $item.Rule.RebootRequired -Message 'Correção aplicada.'
        }
        catch {
            Write-Error "Falha ao aplicar '$($item.RuleId)': $($_.Exception.Message)"
            New-LaChangeResult -RuleId $item.RuleId -Status 'Failed' -BackupPath $backupPath -Message $_.Exception.Message
        }
    }
}
