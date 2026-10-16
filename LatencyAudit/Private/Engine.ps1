# Rule engine: rule factory, evaluation, scoring and the generic registry actions.

$script:SeverityWeight = @{ High = 3; Medium = 2; Low = 1; Info = 0 }

function New-LaTestResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Cria apenas objetos em memória.')]
    param(
        [AllowNull()]$Value,
        [string]$Display,
        [string]$Detail
    )
    [pscustomobject]@{ PSTypeName = 'LatencyAudit.TestResult'; Value = $Value; Display = $Display; Detail = $Detail }
}

function New-LaSkipResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Cria apenas objetos em memória.')]
    param([Parameter(Mandatory)][string]$Reason)
    [pscustomobject]@{ PSTypeName = 'LatencyAudit.SkipResult'; Reason = $Reason }
}

function New-LatencyRule {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Cria apenas objetos em memória.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Why,
        [Parameter(Mandatory)][scriptblock]$Test,
        [AllowNull()]$Expected,
        [string]$ExpectedText,
        [string]$Unit,
        [Parameter(Mandatory)][ValidateSet('High', 'Medium', 'Low', 'Info')][string]$Severity,
        [hashtable[]]$Targets,
        [scriptblock]$Fix,
        [scriptblock]$Backup,
        [scriptblock]$Undo,
        [switch]$RequiresAdmin,
        [switch]$RequiresForce,
        [switch]$RebootRequired,
        [string]$Warning
    )

    if ($null -eq $Expected -and $Severity -ne 'Info') {
        throw "Regra '$Id': Expected é obrigatório quando Severity não é Info."
    }
    if ($Targets -and -not $Fix) {
        $Fix = $script:RegistryFix
        $Backup = $script:RegistryBackup
        $Undo = $script:RegistryUndo
    }
    if ($Fix -and (-not $Backup -or -not $Undo)) {
        throw "Regra '$Id': Fix exige Backup e Undo."
    }
    if (-not $ExpectedText -and $null -ne $Expected -and $Expected -isnot [scriptblock]) {
        $ExpectedText = Format-LaValue -Value $Expected
    }

    [pscustomobject]@{
        PSTypeName     = 'LatencyAudit.Rule'
        Id             = $Id
        Category       = $Category
        Title          = $Title
        Why            = $Why
        Test           = $Test
        Expected       = $Expected
        ExpectedText   = $ExpectedText
        Unit           = $Unit
        Severity       = $Severity
        Targets        = $Targets
        Fix            = $Fix
        Backup         = $Backup
        Undo           = $Undo
        RequiresAdmin  = [bool]$RequiresAdmin
        RequiresForce  = [bool]$RequiresForce
        RebootRequired = [bool]$RebootRequired
        Warning        = $Warning
    }
}

function Format-LaValue {
    param(
        [AllowNull()]$Value,
        [string]$Unit
    )
    if ($null -eq $Value) { return 'não definido' }
    if ($Value -is [bool]) { return $(if ($Value) { 'Sim' } else { 'Não' }) }
    $text = if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value)
        if ($items.Count -eq 0) { 'nenhum' } else { $items -join ', ' }
    }
    else { [string]$Value }
    if ($Unit) { "$text $Unit" } else { $text }
}

function Test-LaCompliance {
    param(
        [AllowNull()]$Value,
        [AllowNull()]$Expected
    )
    if ($null -eq $Expected) { return $null }
    if ($Expected -is [scriptblock]) { return [bool](& $Expected $Value) }
    $Value -eq $Expected
}

function Invoke-LatencyRule {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Rule)

    $status = $null
    $value = $null
    $display = $null
    $detail = $null
    $compliant = $null

    try {
        $raw = & $Rule.Test
        if ($raw -is [pscustomobject] -and $raw.PSObject.TypeNames -contains 'LatencyAudit.SkipResult') {
            $status = 'Skipped'
            $detail = $raw.Reason
        }
        else {
            if ($raw -is [pscustomobject] -and $raw.PSObject.TypeNames -contains 'LatencyAudit.TestResult') {
                $value = $raw.Value
                $display = $raw.Display
                $detail = $raw.Detail
            }
            else {
                $value = $raw
            }
            $compliant = Test-LaCompliance -Value $value -Expected $Rule.Expected
            $status = if ($Rule.Severity -eq 'Info') { 'Info' }
            elseif ($compliant) { 'Pass' }
            else { 'Fail' }
        }
    }
    catch {
        $status = 'Error'
        $detail = $_.Exception.Message
    }

    [pscustomobject]@{
        PSTypeName     = 'LatencyAudit.Result'
        Id             = $Rule.Id
        Category       = $Rule.Category
        Title          = $Rule.Title
        Severity       = $Rule.Severity
        Status         = $status
        Current        = $value
        CurrentText    = if ($status -in 'Skipped', 'Error') { '-' }
        elseif ($display) { $display }
        else { Format-LaValue -Value $value -Unit $Rule.Unit }
        Expected       = $Rule.ExpectedText
        Compliant      = $compliant
        Why            = $Rule.Why
        Detail         = $detail
        CanFix         = [bool]$Rule.Fix
        RequiresAdmin  = $Rule.RequiresAdmin
        RequiresForce  = $Rule.RequiresForce
        RebootRequired = $Rule.RebootRequired
        Warning        = $Rule.Warning
    }
}

function Get-LatencyScore {
    [CmdletBinding()]
    [OutputType([int])]
    param([AllowEmptyCollection()][object[]]$Result = @())

    $scored = @($Result | Where-Object { $_.Status -in 'Pass', 'Fail' })
    $total = ($scored | ForEach-Object { $script:SeverityWeight[$_.Severity] } | Measure-Object -Sum).Sum
    if (-not $total) { return 100 }
    $earned = (@($scored | Where-Object Status -eq 'Pass') |
            ForEach-Object { $script:SeverityWeight[$_.Severity] } | Measure-Object -Sum).Sum
    [int][math]::Round(100 * $earned / $total, [MidpointRounding]::AwayFromZero)
}

function Get-LatencyGrade {
    param([Parameter(Mandatory)][int]$Score)
    if ($Score -ge 90) { 'Excelente' }
    elseif ($Score -ge 75) { 'Bom' }
    elseif ($Score -ge 50) { 'Regular' }
    else { 'Crítico' }
}

# Generic actions for rules declared with -Targets (registry values). A target is
# @{ Path; Name; Value; Kind }. The snapshot keeps whether the value existed so the undo
# can delete it again instead of leaving a default behind.
$script:RegistryBackup = {
    param($Rule)
    @{
        Items = @(foreach ($t in $Rule.Targets) {
                $entry = Get-LaRegistryEntry -Path $t.Path -Name $t.Name
                @{ Path = $t.Path; Name = $t.Name; Existed = $entry.Exists; Value = $entry.Value; Kind = $entry.Kind }
            })
    }
}

$script:RegistryFix = {
    param($Rule)
    foreach ($t in $Rule.Targets) {
        Set-LaRegistryValue -Path $t.Path -Name $t.Name -Value $t.Value -Kind $t.Kind
    }
}

$script:RegistryUndo = {
    param($State)
    foreach ($item in $State.Items) {
        if ($item.Existed) {
            Set-LaRegistryValue -Path $item.Path -Name $item.Name -Value $item.Value -Kind $item.Kind
        }
        else {
            Remove-LaRegistryValue -Path $item.Path -Name $item.Name
        }
    }
}

function New-LaChangeResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Cria apenas objetos em memória.')]
    param(
        [Parameter(Mandatory)][string]$RuleId,
        [Parameter(Mandatory)][string]$Status,
        [string]$BackupPath,
        [bool]$RebootRequired,
        [string]$Message
    )
    [pscustomobject]@{
        PSTypeName     = 'LatencyAudit.ChangeResult'
        RuleId         = $RuleId
        Status         = $Status
        BackupPath     = $BackupPath
        RebootRequired = $RebootRequired
        Message        = $Message
    }
}


function Find-LaRule {
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][string]$Id
    )
    foreach ($rule in $Catalog) {
        if ($rule.Id -eq $Id) { return $rule }
    }
}