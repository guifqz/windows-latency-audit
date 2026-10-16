function Invoke-LatencyAudit {
    <#
    .SYNOPSIS
        Audita o Windows em busca de configurações que afetam desempenho e latência em jogos.
    .DESCRIPTION
        Executa as regras em modo somente leitura (nenhuma alteração é feita e não exige
        administrador) e devolve um objeto com a nota de 0 a 100 e o resultado de cada regra.
        A nota é a soma dos pesos das regras aprovadas sobre as avaliadas (Alta = 3, Média = 2,
        Baixa = 1). Regras informativas, ignoradas ou com erro não entram no cálculo.
    .PARAMETER RuleId
        Executa apenas as regras com esses Ids. Aceita curingas.
    .PARAMETER Category
        Executa apenas as regras dessas categorias. Aceita curingas.
    .PARAMETER Rule
        Objetos de regra personalizados, no lugar do catálogo embutido (veja Get-LatencyRule).
    .EXAMPLE
        $audit = Invoke-LatencyAudit
        $audit.Score
        $audit.Results | Where-Object Status -eq 'Fail' | Format-Table
    .EXAMPLE
        Invoke-LatencyAudit -Category Energia, Gráficos | Export-LatencyAuditReport
    #>
    [CmdletBinding()]
    [OutputType('LatencyAudit.Audit')]
    param(
        [string[]]$RuleId = '*',
        [string[]]$Category = '*',
        [object[]]$Rule
    )

    if (-not $Rule) { $Rule = Get-LaRuleCatalog }
    $selected = foreach ($r in $Rule) {
        $idMatch = $RuleId | Where-Object { $r.Id -like $_ }
        $categoryMatch = $Category | Where-Object { $r.Category -like $_ }
        if ($idMatch -and $categoryMatch) { $r }
    }

    $results = @(foreach ($r in $selected) {
            Write-Verbose "Avaliando $($r.Id)"
            Invoke-LatencyRule -Rule $r
        })

    $os = @(Get-LaCimInstance -ClassName Win32_OperatingSystem) | Select-Object -First 1
    $score = Get-LatencyScore -Result $results

    [pscustomobject]@{
        PSTypeName   = 'LatencyAudit.Audit'
        Score        = $score
        Grade        = Get-LatencyGrade -Score $score
        ComputerName = $env:COMPUTERNAME
        OS           = if ($os) { "$($os.Caption) (build $($os.BuildNumber))" } else { 'Windows' }
        Timestamp    = Get-Date
        Passed       = @($results | Where-Object Status -eq 'Pass').Count
        Failed       = @($results | Where-Object Status -eq 'Fail').Count
        Info         = @($results | Where-Object Status -eq 'Info').Count
        Skipped      = @($results | Where-Object Status -eq 'Skipped').Count
        Errors       = @($results | Where-Object Status -eq 'Error').Count
        Results      = $results
    }
}
