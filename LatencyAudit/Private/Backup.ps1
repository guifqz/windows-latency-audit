# Backup files: one JSON per apply run, holding the state captured before each fix.

$script:BackupVersion = 1

function Get-LaBackupDirectory {
    Join-Path $env:ProgramData 'LatencyAudit\backups'
}

function Write-LatencyBackupFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Entry,
        [Parameter(Mandatory)][string]$Directory
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $path = Join-Path $Directory "LatencyAudit-backup-$stamp.json"

    $document = [ordered]@{
        Version      = $script:BackupVersion
        Created      = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        User         = $env:USERNAME
        Entries      = @($Entry | ForEach-Object { [ordered]@{ RuleId = $_.RuleId; State = $_.State } })
    }
    ConvertTo-Json -InputObject $document -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    $path
}

function Read-LatencyBackupFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Backup não encontrado: $Path"
    }
    try {
        $document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Backup inválido (JSON ilegível): $Path"
    }
    if ($document.Version -ne $script:BackupVersion -or $null -eq $document.Entries) {
        throw "Backup inválido ou de versão não suportada: $Path"
    }
    $document
}
