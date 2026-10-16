BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\LatencyAudit\LatencyAudit.psd1') -Force

    # Mocks run inside the module scope, so they report calls through a log file named by an env var.
    function Get-TestLog {
        if (Test-Path -LiteralPath $env:LATENCYAUDIT_TEST_LOG) { @(Get-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG) } else { @() }
    }
    function Clear-TestLog {
        Remove-Item -LiteralPath $env:LATENCYAUDIT_TEST_LOG -ErrorAction SilentlyContinue
    }
}

AfterAll {
    Remove-Module LatencyAudit -ErrorAction SilentlyContinue
}

Describe 'Backup file' {
    It 'round-trips entries through JSON' {
        $dir = Join-Path $TestDrive 'roundtrip'
        InModuleScope LatencyAudit -Parameters @{ Dir = $dir } {
            $entries = @(
                [pscustomobject]@{ RuleId = 'game-dvr'; State = @{ Items = @(@{ Path = 'HKCU:\X'; Name = 'A'; Existed = $true; Value = 1; Kind = 'DWord' }) } }
                [pscustomobject]@{ RuleId = 'power-plan'; State = @{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e' } }
            )
            $path = Write-LatencyBackupFile -Entry $entries -Directory $Dir

            $path | Should -Exist
            $path | Should -BeLike (Join-Path $Dir 'LatencyAudit-backup-*.json')

            $doc = Read-LatencyBackupFile -Path $path
            $doc.Version | Should -Be 1
            $doc.Entries | Should -HaveCount 2
            $doc.Entries[0].RuleId | Should -Be 'game-dvr'
            @($doc.Entries[0].State.Items) | Should -HaveCount 1
            $doc.Entries[0].State.Items[0].Value | Should -Be 1
            $doc.Entries[1].State.Guid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        }
    }

    It 'creates the backup directory when missing' {
        $dir = Join-Path $TestDrive 'nested\backups'
        InModuleScope LatencyAudit -Parameters @{ Dir = $dir } {
            Write-LatencyBackupFile -Entry @([pscustomobject]@{ RuleId = 'x'; State = @{} }) -Directory $Dir | Out-Null
        }
        $dir | Should -Exist
    }

    It 'keeps single-entry arrays as arrays' {
        $dir = Join-Path $TestDrive 'single'
        InModuleScope LatencyAudit -Parameters @{ Dir = $dir } {
            $path = Write-LatencyBackupFile -Directory $Dir -Entry @([pscustomobject]@{ RuleId = 'x'; State = @{ Items = @(@{ Name = 'solo' }) } })
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Match '"Items":\s*\['
            $raw | Should -Match '"Entries":\s*\['
        }
    }

    It 'rejects a missing file' {
        InModuleScope LatencyAudit {
            { Read-LatencyBackupFile -Path 'C:\nao\existe.json' } | Should -Throw '*não encontrado*'
        }
    }

    It 'rejects malformed JSON and unknown versions' {
        $bad = Join-Path $TestDrive 'bad.json'
        $old = Join-Path $TestDrive 'old.json'
        Set-Content -LiteralPath $bad -Value '{ not json'
        Set-Content -LiteralPath $old -Value '{"Version": 99, "Entries": []}'
        InModuleScope LatencyAudit -Parameters @{ Bad = $bad; Old = $old } {
            { Read-LatencyBackupFile -Path $Bad } | Should -Throw '*inválido*'
            { Read-LatencyBackupFile -Path $Old } | Should -Throw '*inválido*'
        }
    }
}

Describe 'Set-LatencyRecommendation' {
    BeforeEach {
        $env:LATENCYAUDIT_TEST_LOG = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        Mock -ModuleName LatencyAudit Test-LaAdmin { $true }
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null } }
        Mock -ModuleName LatencyAudit Get-LaCimInstance { $null }
        Mock -ModuleName LatencyAudit Set-LaRegistryValue { Add-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG -Value "set:$Name=$Value" }
        Mock -ModuleName LatencyAudit Remove-LaRegistryValue { Add-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG -Value "remove:$Name" }
        Mock -ModuleName LatencyAudit Invoke-LaPowerCfg { Add-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG -Value "powercfg:$($Argument -join ' ')" }
    }

    AfterAll {
        Remove-Item -Path Env:LATENCYAUDIT_TEST_LOG, Env:LATENCYAUDIT_TEST_DIR -ErrorAction SilentlyContinue
    }

    It 'writes nothing and changes nothing under -WhatIf' {
        $dir = Join-Path $TestDrive 'whatif'
        $result = Set-LatencyRecommendation -RuleId 'game-dvr' -BackupDirectory $dir -WhatIf
        $result | Should -BeNullOrEmpty
        $dir | Should -Not -Exist
        Should -Invoke Set-LaRegistryValue -ModuleName LatencyAudit -Times 0 -Exactly
    }

    It 'saves the backup before touching the registry' {
        $dir = Join-Path $TestDrive 'order'
        $env:LATENCYAUDIT_TEST_DIR = $dir
        Mock -ModuleName LatencyAudit Set-LaRegistryValue {
            $has = [bool](Get-ChildItem -Path $env:LATENCYAUDIT_TEST_DIR -Filter '*.json' -ErrorAction SilentlyContinue)
            Add-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG -Value "set:backupExisted=$has"
        }
        Set-LatencyRecommendation -RuleId 'game-dvr' -BackupDirectory $dir -Confirm:$false | Out-Null
        Get-TestLog | Should -Contain 'set:backupExisted=True'
    }

    It 'applies the fix and records the previous values' {
        $dir = Join-Path $TestDrive 'apply'
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 1; Kind = 'DWord' } }

        $result = Set-LatencyRecommendation -RuleId 'game-dvr' -BackupDirectory $dir -Confirm:$false

        $result.Status | Should -Be 'Applied'
        $result.BackupPath | Should -Exist
        Should -Invoke Set-LaRegistryValue -ModuleName LatencyAudit -Times 2 -Exactly -ParameterFilter { $Value -eq 0 -and $Kind -eq 'DWord' }

        $doc = Get-Content -LiteralPath $result.BackupPath -Raw | ConvertFrom-Json
        $doc.Entries[0].RuleId | Should -Be 'game-dvr'
        @($doc.Entries[0].State.Items) | Should -HaveCount 2
        $doc.Entries[0].State.Items[0].Existed | Should -BeTrue
        $doc.Entries[0].State.Items[0].Value | Should -Be 1
    }

    It 'does nothing when the rule already complies' {
        $dir = Join-Path $TestDrive 'compliant'
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 1; Kind = 'DWord' } } -ParameterFilter { $Name -eq 'AutoGameModeEnabled' }

        $result = Set-LatencyRecommendation -RuleId 'game-mode' -BackupDirectory $dir -Confirm:$false

        $result.Status | Should -Be 'AlreadyCompliant'
        $dir | Should -Not -Exist
        Should -Invoke Set-LaRegistryValue -ModuleName LatencyAudit -Times 0 -Exactly
    }

    It 'refuses admin-only rules from a non-elevated session but allows per-user ones' {
        Mock -ModuleName LatencyAudit Test-LaAdmin { $false }
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 1; Kind = 'DWord' } } -ParameterFilter { $Name -eq 'HwSchMode' }
        $dir = Join-Path $TestDrive 'noadmin'

        $result = Set-LatencyRecommendation -RuleId 'hags' -BackupDirectory $dir -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'administrador'
        Should -Invoke Set-LaRegistryValue -ModuleName LatencyAudit -Times 0 -Exactly

        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = '1'; Kind = 'String' } } -ParameterFilter { $Name -eq 'MouseSpeed' }
        (Set-LatencyRecommendation -RuleId 'mouse-acceleration' -BackupDirectory $dir -Confirm:$false).Status | Should -Be 'Applied'
    }

    It 'refuses unknown rules and rules without a fix' {
        $dir = Join-Path $TestDrive 'invalid'
        Set-LatencyRecommendation -RuleId 'nao-existe', 'nagle' -BackupDirectory $dir -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err | Should -HaveCount 2
        "$($err[0])" | Should -Match 'desconhecida'
        "$($err[1])" | Should -Match 'não tem correção'
        $dir | Should -Not -Exist
    }

    It 'requires -Force for VBS/HVCI and shows the security warning' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            [pscustomobject]@{ VirtualizationBasedSecurityStatus = 2; SecurityServicesRunning = @(2) }
        } -ParameterFilter { $ClassName -eq 'Win32_DeviceGuard' }
        $dir = Join-Path $TestDrive 'vbs'

        Set-LatencyRecommendation -RuleId 'vbs-hvci' -BackupDirectory $dir -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        "$err" | Should -Match '-Force'
        Should -Invoke Set-LaRegistryValue -ModuleName LatencyAudit -Times 0 -Exactly

        $result = Set-LatencyRecommendation -RuleId 'vbs-hvci' -Force -BackupDirectory $dir -Confirm:$false -WarningVariable warn -WarningAction SilentlyContinue
        $result.Status | Should -Be 'Applied'
        $result.RebootRequired | Should -BeTrue
        "$warn" | Should -Match 'segurança|proteção'
        Should -Invoke Set-LaRegistryValue -ModuleName LatencyAudit -Times 1 -Exactly -ParameterFilter { $Name -eq 'Enabled' -and $Value -eq 0 }
    }

    It 'reports Failed but keeps the backup when a fix throws' {
        $dir = Join-Path $TestDrive 'failure'
        Mock -ModuleName LatencyAudit Set-LaRegistryValue { throw 'acesso negado' }
        $result = Set-LatencyRecommendation -RuleId 'game-dvr' -BackupDirectory $dir -Confirm:$false -ErrorAction SilentlyContinue
        $result.Status | Should -Be 'Failed'
        $result.BackupPath | Should -Exist
    }

    It 'backs up and switches the power plan' {
        $dir = Join-Path $TestDrive 'plan'
        Mock -ModuleName LatencyAudit Get-LaActivePowerPlan { [pscustomobject]@{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Name = 'Equilibrado' } }
        $result = Set-LatencyRecommendation -RuleId 'power-plan' -BackupDirectory $dir -Confirm:$false
        $result.Status | Should -Be 'Applied'
        Get-TestLog | Should -Contain 'powercfg:/setactive SCHEME_MIN'
        (Get-Content -LiteralPath $result.BackupPath -Raw | ConvertFrom-Json).Entries[0].State.Guid | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
    }
}

Describe 'Restore-LatencyBackup' {
    BeforeEach {
        $env:LATENCYAUDIT_TEST_LOG = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        Mock -ModuleName LatencyAudit Test-LaAdmin { $true }
        Mock -ModuleName LatencyAudit Get-LaCimInstance { $null }
        Mock -ModuleName LatencyAudit Set-LaRegistryValue { Add-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG -Value "set:$Name=$Value/$Kind" }
        Mock -ModuleName LatencyAudit Remove-LaRegistryValue { Add-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG -Value "remove:$Name" }
        Mock -ModuleName LatencyAudit Invoke-LaPowerCfg { Add-Content -LiteralPath $env:LATENCYAUDIT_TEST_LOG -Value "powercfg:$($Argument -join ' ')" }
    }

    AfterAll {
        Remove-Item -Path Env:LATENCYAUDIT_TEST_LOG, Env:LATENCYAUDIT_TEST_DIR -ErrorAction SilentlyContinue
    }

    It 'restores previous values after an apply (full round trip)' {
        $dir = Join-Path $TestDrive 'restore-roundtrip'
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 1; Kind = 'DWord' } }
        $applied = Set-LatencyRecommendation -RuleId 'game-dvr' -BackupDirectory $dir -Confirm:$false
        Clear-TestLog

        $restored = Restore-LatencyBackup -Path $applied.BackupPath -Confirm:$false

        $restored.Status | Should -Be 'Restored'
        Get-TestLog | Should -Contain 'set:GameDVR_Enabled=1/DWord'
        Get-TestLog | Should -Contain 'set:AppCaptureEnabled=1/DWord'
    }

    It 'removes values that did not exist before the change' {
        $dir = Join-Path $TestDrive 'restore-absent'
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null } }
        $applied = Set-LatencyRecommendation -RuleId 'game-dvr' -BackupDirectory $dir -Confirm:$false
        Clear-TestLog

        Restore-LatencyBackup -Path $applied.BackupPath -Confirm:$false | Out-Null

        Get-TestLog | Should -Contain 'remove:GameDVR_Enabled'
        Get-TestLog | Should -Contain 'remove:AppCaptureEnabled'
        @(Get-TestLog | Where-Object { $_ -like 'set:*' }).Count | Should -Be 0
    }

    It 'restores string values with their original type' {
        $dir = Join-Path $TestDrive 'restore-string'
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = '2'; Kind = 'String' } } -ParameterFilter { $Name -eq 'MouseThreshold2' }
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = '1'; Kind = 'String' } } -ParameterFilter { $Name -ne 'MouseThreshold2' }
        $applied = Set-LatencyRecommendation -RuleId 'mouse-acceleration' -BackupDirectory $dir -Confirm:$false
        Clear-TestLog

        Restore-LatencyBackup -Path $applied.BackupPath -Confirm:$false | Out-Null

        Get-TestLog | Should -Contain 'set:MouseThreshold2=2/String'
        Get-TestLog | Should -Contain 'set:MouseSpeed=1/String'
    }

    It 'restores the previous power plan' {
        $dir = Join-Path $TestDrive 'restore-plan'
        Mock -ModuleName LatencyAudit Get-LaActivePowerPlan { [pscustomobject]@{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Name = 'Equilibrado' } }
        $applied = Set-LatencyRecommendation -RuleId 'power-plan' -BackupDirectory $dir -Confirm:$false
        Clear-TestLog

        Restore-LatencyBackup -Path $applied.BackupPath -Confirm:$false | Out-Null

        Get-TestLog | Should -Contain 'powercfg:/setactive 381b4222-f694-41f0-9685-ff5bb260df2e'
    }

    It 'changes nothing under -WhatIf' {
        $dir = Join-Path $TestDrive 'restore-whatif'
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 1; Kind = 'DWord' } }
        $applied = Set-LatencyRecommendation -RuleId 'game-dvr' -BackupDirectory $dir -Confirm:$false
        Clear-TestLog

        Restore-LatencyBackup -Path $applied.BackupPath -WhatIf | Should -BeNullOrEmpty
        @(Get-TestLog).Count | Should -Be 0
    }

    It 'skips entries whose rule no longer exists' {
        $path = Join-Path $TestDrive 'orphan.json'
        '{"Version":1,"Entries":[{"RuleId":"regra-removida","State":{}}]}' | Set-Content -LiteralPath $path
        $result = Restore-LatencyBackup -Path $path -Confirm:$false -WarningAction SilentlyContinue
        $result.Status | Should -Be 'Skipped'
    }

    It 'fails clearly on an invalid backup' {
        { Restore-LatencyBackup -Path (Join-Path $TestDrive 'nada.json') -Confirm:$false } | Should -Throw '*não encontrado*'
    }
}
