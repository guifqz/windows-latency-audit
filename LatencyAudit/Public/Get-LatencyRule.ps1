function Get-LatencyRule {
    <#
    .SYNOPSIS
        Lista as regras de auditoria disponíveis.
    .DESCRIPTION
        Retorna os objetos de regra (Id, Category, Title, Why, Expected, Severity e, quando
        existir, Fix e Undo) sem executar nenhuma verificação.
    .PARAMETER Id
        Filtra por Id da regra. Aceita curingas.
    .PARAMETER Category
        Filtra por categoria. Aceita curingas.
    .EXAMPLE
        Get-LatencyRule -Category Gráficos | Format-Table Id, Severity, Title
    #>
    [CmdletBinding()]
    [OutputType('LatencyAudit.Rule')]
    param(
        [string[]]$Id = '*',
        [string[]]$Category = '*'
    )

    foreach ($rule in Get-LaRuleCatalog) {
        $idMatch = $Id | Where-Object { $rule.Id -like $_ }
        $categoryMatch = $Category | Where-Object { $rule.Category -like $_ }
        if ($idMatch -and $categoryMatch) { $rule }
    }
}
