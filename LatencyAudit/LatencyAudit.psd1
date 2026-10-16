@{
    RootModule            = 'LatencyAudit.psm1'
    ModuleVersion         = '0.1.0'
    GUID                  = 'b7d1e3a4-5c2f-4e9a-8a61-3f0c9d2e7b15'
    Author                = 'Guilherme'
    Copyright             = '(c) 2026 Guilherme. MIT License.'
    Description           = 'Audita configurações do Windows que afetam desempenho e latência em jogos, calcula uma nota e aplica correções reversíveis com backup.'
    PowerShellVersion     = '5.1'
    CompatiblePSEditions  = @('Desktop', 'Core')
    FunctionsToExport     = @(
        'Invoke-LatencyAudit'
        'Export-LatencyAuditReport'
        'Set-LatencyRecommendation'
        'Restore-LatencyBackup'
        'Get-LatencyRule'
    )
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags         = @('Windows', 'Gaming', 'Performance', 'Latency', 'Audit', 'Optimization')
            LicenseUri   = 'https://github.com/guifqz/windows-latency-audit/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/guifqz/windows-latency-audit'
        }
    }
}
