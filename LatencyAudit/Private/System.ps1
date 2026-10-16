# Thin wrappers around the operating system. Every read or write that touches the
# registry, CIM or powercfg goes through here so the tests can mock a single layer.

function Test-LaAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LaRegistryEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($key -and ($key.GetValueNames() -contains $Name)) {
        return [pscustomobject]@{
            Exists = $true
            Value  = $key.GetValue($Name)
            Kind   = [string]$key.GetValueKind($Name)
        }
    }
    [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
}

function Get-LaRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    (Get-LaRegistryEntry -Path $Path -Name $Name).Value
}

function Set-LaRegistryValue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A confirmação é feita pelos comandos públicos antes de chamar este wrapper.')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Kind
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Kind -ErrorAction Stop
}

function Remove-LaRegistryValue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A confirmação é feita pelos comandos públicos antes de chamar este wrapper.')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
}

function Test-LaRegistryKey {
    param([Parameter(Mandatory)][string]$Path)
    Test-Path -LiteralPath $Path
}

function Get-LaCimInstance {
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Namespace = 'root\cimv2'
    )
    try {
        Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop
    }
    catch {
        Write-Verbose "CIM $Namespace\$ClassName indisponivel: $($_.Exception.Message)"
        $null
    }
}

function Invoke-LaPowerCfg {
    param([Parameter(Mandatory)][string[]]$Argument)
    $output = & powercfg.exe @Argument 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg $($Argument -join ' ') falhou: $($output -join ' ')"
    }
    $output
}

function Get-LaActivePowerPlan {
    $line = Invoke-LaPowerCfg -Argument '/getactivescheme' | Select-Object -First 1
    if ("$line" -match '(?<guid>[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})\s*\((?<name>.+)\)') {
        return [pscustomobject]@{ Guid = $Matches.guid.ToLowerInvariant(); Name = $Matches.name.Trim() }
    }
    $null
}

# Index of a power setting on AC power for the active scheme, or $null when it cannot be read.
function Get-LaPowerSettingAc {
    param(
        [Parameter(Mandatory)][string]$SubgroupGuid,
        [Parameter(Mandatory)][string]$SettingGuid
    )
    $text = (Invoke-LaPowerCfg -Argument '/query', 'SCHEME_CURRENT', $SubgroupGuid, $SettingGuid) -join "`n"
    $hex = [regex]::Matches($text, '0x[0-9a-fA-F]+')
    if ($hex.Count -lt 2) { return $null }
    # The last two hex values are the current AC and DC indexes, in any locale.
    [Convert]::ToInt32($hex[$hex.Count - 2].Value, 16)
}

function Set-LaPowerSettingAc {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A confirmação é feita pelos comandos públicos antes de chamar este wrapper.')]
    param(
        [Parameter(Mandatory)][string]$SubgroupGuid,
        [Parameter(Mandatory)][string]$SettingGuid,
        [Parameter(Mandatory)][int]$Value
    )
    Invoke-LaPowerCfg -Argument '/setacvalueindex', 'SCHEME_CURRENT', $SubgroupGuid, $SettingGuid, "$Value" | Out-Null
    Invoke-LaPowerCfg -Argument '/setactive', 'SCHEME_CURRENT' | Out-Null
}

function Get-LaNetAdapterPowerState {
    if (-not (Get-Command -Name Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue)) { return $null }
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    foreach ($adapter in $adapters) {
        $pm = Get-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction SilentlyContinue
        if ($pm) {
            [pscustomobject]@{
                Name                = $adapter.Name
                AllowTurnOffEnabled = ($pm.AllowComputerToTurnOffDevice -eq 'Enabled')
            }
        }
    }
}

function Set-LaNetAdapterPowerState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A confirmação é feita pelos comandos públicos antes de chamar este wrapper.')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$AllowTurnOff
    )
    $state = if ($AllowTurnOff) { 'Enabled' } else { 'Disabled' }
    Set-NetAdapterPowerManagement -Name $Name -AllowComputerToTurnOffDevice $state -ErrorAction Stop
}
