<#
.SYNOPSIS
    Gera docs/exemplo-relatorio.html a partir de dados fictícios.
.DESCRIPTION
    Substitui o Test de cada regra do catálogo por um valor fixo e passa o resultado pelo
    mesmo motor e pelo mesmo gerador de HTML usados na auditoria real. Nada é lido do sistema.
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot '..\docs\exemplo-relatorio.html' }

$module = Import-Module (Join-Path $PSScriptRoot '..\LatencyAudit\LatencyAudit.psd1') -Force -PassThru

$fake = @{
    'power-plan'            = @{ Value = '381b4222-f694-41f0-9685-ff5bb260df2e'; Display = 'Equilibrado'; Detail = 'GUID 381b4222-f694-41f0-9685-ff5bb260df2e' }
    'game-mode'             = @{ Value = 1; Display = 'Ligado' }
    'hags'                  = @{ Value = 2; Display = 'Ligado' }
    'game-dvr'              = @{ Value = 'Ativa'; Detail = 'GameDVR_Enabled=1; AppCaptureEnabled=1' }
    'fullscreen-optimizations' = @{ Value = $null; Display = 'Padrão do Windows' }
    'vbs-hvci'              = @{ Value = $true; Display = 'VBS ativo, Integridade de memória (HVCI) ativa' }
    'mouse-acceleration'    = @{ Value = 'Ativada'; Detail = 'MouseSpeed=1' }
    'nagle'                 = @{ Value = $null; Display = 'Informativo, não avaliado' }
    'net-adapter-power'     = @{ Value = @() }
    'usb-selective-suspend' = @{ Value = 0; Display = 'Desativada' }
    'startup-apps'          = @{ Value = 7; Detail = 'Exemplos: Discord, Steam, OneDrive, Spotify, Teams' }
    'background-apps'       = @{ Skip = 'Chave global ausente (controle por app no Windows 11).' }
    'visual-effects'        = @{ Value = 3; Display = 'Personalizado' }
    'pagefile'              = @{ Value = 'Automático' }
    'disk-space'            = @{ Value = 42.3; Detail = '211,5 GB livres de 500,0 GB em C:' }
    'pending-reboot'        = @{ Value = $false }
    'gpu-driver-age'        = @{ Value = 45; Detail = 'GPU de exemplo, versão 32.0.15.8142, de 01/09/2026' }
    'ram-speed'             = @{ Value = 67; Detail = 'Configurada: 2133 MT/s; nominal do módulo: 3200 MT/s' }
    'display-refresh'       = @{ Value = $true; Display = '165 Hz (máximo 165 Hz)' }
}

function ConvertTo-Literal {
    param($Value)
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
    if ($Value -is [string]) { return "'" + $Value.Replace("'", "''") + "'" }
    if ($Value -is [array]) { return '@()' }
    [string]::Format([cultureinfo]::InvariantCulture, '{0}', $Value)
}

$rules = & $module {
    param($Fake, $ToLiteral)
    foreach ($rule in Get-LaRuleCatalog) {
        $data = $Fake[$rule.Id]
        $code = if ($data.Skip) {
            "New-LaSkipResult -Reason $(& $ToLiteral $data.Skip)"
        }
        else {
            "New-LaTestResult -Value $(& $ToLiteral $data.Value) -Display $(& $ToLiteral $data.Display) -Detail $(& $ToLiteral $data.Detail)"
        }
        $rule.Test = $ExecutionContext.SessionState.Module.NewBoundScriptBlock([scriptblock]::Create($code))
        $rule
    }
} $fake ${function:ConvertTo-Literal}

$audit = & $module { param($Rules) Invoke-LatencyAudit -Rule $Rules } $rules
$audit.ComputerName = 'PC-GAMER-EXEMPLO'
$audit.OS = 'Microsoft Windows 11 Pro (build 26100)'
$audit.Timestamp = [datetime]'2026-10-16T10:30:00'

$file = $audit | Export-LatencyAuditReport -Path $OutputPath -Note 'Dados fictícios, apenas para demonstração do relatório.'
"Relatório gerado: $($file.FullName) (nota $($audit.Score))"
