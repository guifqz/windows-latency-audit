function Export-LatencyAuditReport {
    <#
    .SYNOPSIS
        Gera um relatório HTML autocontido a partir do resultado de Invoke-LatencyAudit.
    .DESCRIPTION
        O arquivo não depende de scripts, fontes ou imagens externas: tem medidor da nota e
        achados agrupados por categoria, com a explicação de cada regra. Segue o tema claro
        ou escuro do navegador.
    .PARAMETER Audit
        Objeto devolvido por Invoke-LatencyAudit. Se omitido, a auditoria é executada agora.
    .PARAMETER Path
        Arquivo de saída. Padrão: LatencyAudit-AAAAMMDD-HHmmss.html na pasta atual.
    .PARAMETER Note
        Texto opcional exibido em um aviso no topo do relatório.
    .EXAMPLE
        Invoke-LatencyAudit | Export-LatencyAuditReport -Path .\relatorio.html
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(ValueFromPipeline)]
        [PSTypeName('LatencyAudit.Audit')]$Audit,

        [string]$Path,

        [string]$Note
    )

    process {
        if (-not $Audit) { $Audit = Invoke-LatencyAudit }
        if (-not $Path) { $Path = Join-Path (Get-Location).Path ('LatencyAudit-{0:yyyyMMdd-HHmmss}.html' -f $Audit.Timestamp) }

        $html = ConvertTo-LaReportHtml -Audit $Audit -Note $Note
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $directory = Split-Path -Path $fullPath -Parent
        if ($directory -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($fullPath, $html, (New-Object System.Text.UTF8Encoding($false)))
        Get-Item -LiteralPath $fullPath
    }
}
