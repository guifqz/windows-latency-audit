BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\LatencyAudit\LatencyAudit.psd1') -Force
}

AfterAll {
    Remove-Module LatencyAudit -ErrorAction SilentlyContinue
}

Describe 'New-LatencyRule' {
    It 'requires Expected unless the rule is informational' {
        InModuleScope LatencyAudit {
            { New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity High -Test { 1 } } |
                Should -Throw '*Expected*'
            { New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Info -Test { 1 } } |
                Should -Not -Throw
        }
    }

    It 'requires Backup and Undo whenever Fix is given' {
        InModuleScope LatencyAudit {
            { New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Low -Expected 1 -Test { 1 } -Fix { } } |
                Should -Throw '*Backup*'
        }
    }

    It 'builds Fix, Backup and Undo from registry targets' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Low -Expected 1 -Test { 1 } `
                -Targets @(@{ Path = 'HKCU:\Software\Fake'; Name = 'V'; Value = 1; Kind = 'DWord' })
            $rule.Fix | Should -Not -BeNullOrEmpty
            $rule.Backup | Should -Not -BeNullOrEmpty
            $rule.Undo | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-LatencyRule' {
    It 'passes when the value equals Expected' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity High -Expected 2 -Test { 2 }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Pass'
            $result.Compliant | Should -BeTrue
        }
    }

    It 'fails when the value differs from Expected' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity High -Expected 2 -Test { 1 }
            (Invoke-LatencyRule -Rule $rule).Status | Should -Be 'Fail'
        }
    }

    It 'fails when the test returns nothing' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity High -Expected 2 -Test { $null }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Fail'
            $result.CurrentText | Should -Be 'não definido'
        }
    }

    It 'accepts a predicate as Expected' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Low `
                -Expected { param($v) $v -le 10 } -ExpectedText 'até 10' -Test { 7 }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Pass'
            $result.Expected | Should -Be 'até 10'
        }
    }

    It 'reports Info for informational rules without scoring them' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Info -Test { 'qualquer' }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Info'
            $result.Compliant | Should -BeNullOrEmpty
        }
    }

    It 'still computes compliance for informational rules that declare Expected' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Info -Expected $false -Test { $true }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Info'
            $result.Compliant | Should -BeFalse
        }
    }

    It 'maps a skip result to Skipped' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity High -Expected 1 `
                -Test { New-LaSkipResult -Reason 'sem suporte' }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Skipped'
            $result.Detail | Should -Be 'sem suporte'
        }
    }

    It 'captures exceptions as Error instead of throwing' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity High -Expected 1 -Test { throw 'falhou' }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Error'
            $result.Detail | Should -Be 'falhou'
        }
    }

    It 'uses Display for the text while comparing the raw value' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Low -Expected 1 `
                -Test { New-LaTestResult -Value 1 -Display 'Ligado' -Detail 'nota' }
            $result = Invoke-LatencyRule -Rule $rule
            $result.Status | Should -Be 'Pass'
            $result.CurrentText | Should -Be 'Ligado'
            $result.Detail | Should -Be 'nota'
        }
    }

    It 'appends the unit to the displayed value' {
        InModuleScope LatencyAudit {
            $rule = New-LatencyRule -Id 'x' -Category 'C' -Title 'T' -Why 'W' -Severity Low -Expected 5 -Unit 'dias' -Test { 5 }
            (Invoke-LatencyRule -Rule $rule).CurrentText | Should -Be '5 dias'
        }
    }
}

Describe 'Rule catalog' {
    BeforeAll {
        $script:Rules = @(Get-LatencyRule)
    }

    It 'contains every documented rule' {
        $expected = 'power-plan', 'game-mode', 'hags', 'game-dvr', 'fullscreen-optimizations', 'vbs-hvci',
        'mouse-acceleration', 'nagle', 'net-adapter-power', 'usb-selective-suspend', 'startup-apps',
        'background-apps', 'visual-effects', 'pagefile', 'disk-space', 'pending-reboot',
        'gpu-driver-age', 'ram-speed', 'display-refresh'
        $script:Rules.Id | Should -Be $expected
    }

    It 'has unique ids' {
        ($script:Rules.Id | Select-Object -Unique).Count | Should -Be $script:Rules.Count
    }

    It 'documents every rule in pt-BR with a title, category and explanation' {
        foreach ($rule in $script:Rules) {
            $rule.Title | Should -Not -BeNullOrEmpty -Because $rule.Id
            $rule.Category | Should -Not -BeNullOrEmpty -Because $rule.Id
            $rule.Why.Length | Should -BeGreaterThan 40 -Because $rule.Id
        }
    }

    It 'pairs every Fix with Backup and Undo' {
        foreach ($rule in $script:Rules | Where-Object Fix) {
            $rule.Backup | Should -Not -BeNullOrEmpty -Because $rule.Id
            $rule.Undo | Should -Not -BeNullOrEmpty -Because $rule.Id
        }
    }

    It 'never offers a fix for informational-only placebo candidates' {
        foreach ($id in 'nagle', 'fullscreen-optimizations', 'visual-effects') {
            ($script:Rules | Where-Object Id -eq $id).Fix | Should -BeNullOrEmpty
        }
    }

    It 'guards VBS/HVCI behind -Force with a security warning' {
        $rule = $script:Rules | Where-Object Id -eq 'vbs-hvci'
        $rule.Severity | Should -Be 'Info'
        $rule.RequiresForce | Should -BeTrue
        $rule.RequiresAdmin | Should -BeTrue
        $rule.Warning | Should -Match 'segurança|proteção'
    }

    It 'filters with Get-LatencyRule -Category' {
        (Get-LatencyRule -Category 'Energia').Id | Should -Be @('power-plan', 'usb-selective-suspend')
    }
}

Describe 'Catalog detection (mocked system layer)' {
    BeforeEach {
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null } }
        Mock -ModuleName LatencyAudit Test-LaRegistryKey { $false }
        Mock -ModuleName LatencyAudit Get-LaCimInstance { $null }
        Mock -ModuleName LatencyAudit Get-LaActivePowerPlan { $null }
        Mock -ModuleName LatencyAudit Get-LaPowerSettingAc { $null }
        Mock -ModuleName LatencyAudit Get-LaNetAdapterPowerState { $null }
    }

    It 'power-plan fails on Balanced and passes on High performance' {
        Mock -ModuleName LatencyAudit Get-LaActivePowerPlan { [pscustomobject]@{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Name = 'Equilibrado' } }
        (Invoke-LatencyAudit -RuleId 'power-plan').Results[0].Status | Should -Be 'Fail'

        Mock -ModuleName LatencyAudit Get-LaActivePowerPlan { [pscustomobject]@{ Guid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'; Name = 'Desempenho máximo' } }
        (Invoke-LatencyAudit -RuleId 'power-plan').Results[0].Status | Should -Be 'Pass'
    }

    It 'power-plan explains that a custom plan may already be tuned' {
        Mock -ModuleName LatencyAudit Get-LaActivePowerPlan { [pscustomobject]@{ Guid = '00000000-1111-2222-3333-444444444444'; Name = 'Meu plano' } }
        $result = (Invoke-LatencyAudit -RuleId 'power-plan').Results[0]
        $result.Status | Should -Be 'Fail'
        $result.Detail | Should -Match 'personalizado'
    }

    It 'game-mode treats a missing value as the Windows default (on)' {
        $result = (Invoke-LatencyAudit -RuleId 'game-mode').Results[0]
        $result.Status | Should -Be 'Pass'
        $result.Detail | Should -Match 'padrão'
    }

    It 'hags fails when the scheduler is explicitly off' {
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 1; Kind = 'DWord' } } -ParameterFilter { $Name -eq 'HwSchMode' }
        (Invoke-LatencyAudit -RuleId 'hags').Results[0].Status | Should -Be 'Fail'
    }

    It 'game-dvr fails while either capture flag is on' {
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 0; Kind = 'DWord' } } -ParameterFilter { $Name -eq 'GameDVR_Enabled' }
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 1; Kind = 'DWord' } } -ParameterFilter { $Name -eq 'AppCaptureEnabled' }
        (Invoke-LatencyAudit -RuleId 'game-dvr').Results[0].Status | Should -Be 'Fail'
    }

    It 'game-dvr passes when both are off' {
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = 0; Kind = 'DWord' } }
        (Invoke-LatencyAudit -RuleId 'game-dvr').Results[0].Status | Should -Be 'Pass'
    }

    It 'mouse-acceleration fails when MouseSpeed is 1' {
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $true; Value = '1'; Kind = 'String' } } -ParameterFilter { $Name -eq 'MouseSpeed' }
        (Invoke-LatencyAudit -RuleId 'mouse-acceleration').Results[0].Status | Should -Be 'Fail'
    }

    It 'vbs-hvci reports Info and never scores' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            [pscustomobject]@{ VirtualizationBasedSecurityStatus = 2; SecurityServicesRunning = @(1, 2) }
        } -ParameterFilter { $ClassName -eq 'Win32_DeviceGuard' }
        $audit = Invoke-LatencyAudit -RuleId 'vbs-hvci'
        $audit.Results[0].Status | Should -Be 'Info'
        $audit.Results[0].Compliant | Should -BeFalse
        $audit.Results[0].CurrentText | Should -Match 'HVCI'
    }

    It 'net-adapter-power fails when an adapter may be turned off' {
        Mock -ModuleName LatencyAudit Get-LaNetAdapterPowerState {
            @(
                [pscustomobject]@{ Name = 'Ethernet'; AllowTurnOffEnabled = $true }
                [pscustomobject]@{ Name = 'Wi-Fi'; AllowTurnOffEnabled = $false }
            )
        }
        $result = (Invoke-LatencyAudit -RuleId 'net-adapter-power').Results[0]
        $result.Status | Should -Be 'Fail'
        $result.CurrentText | Should -Be 'Ethernet'
    }

    It 'usb-selective-suspend is skipped when the setting is unreadable' {
        (Invoke-LatencyAudit -RuleId 'usb-selective-suspend').Results[0].Status | Should -Be 'Skipped'
    }

    It 'startup-apps fails above 10 entries' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            1..14 | ForEach-Object { [pscustomobject]@{ Name = "App$_" } }
        } -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' }
        (Invoke-LatencyAudit -RuleId 'startup-apps').Results[0].Status | Should -Be 'Fail'
    }

    It 'pagefile fails only when there is no page file at all' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance { [pscustomobject]@{ AutomaticManagedPagefile = $false } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        (Invoke-LatencyAudit -RuleId 'pagefile').Results[0].Status | Should -Be 'Fail'

        Mock -ModuleName LatencyAudit Get-LaCimInstance { [pscustomobject]@{ AutomaticManagedPagefile = $true } } -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
        (Invoke-LatencyAudit -RuleId 'pagefile').Results[0].Status | Should -Be 'Pass'
    }

    It 'disk-space fails under 15 percent free' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            [pscustomobject]@{ DeviceID = $env:SystemDrive; Size = 1000GB; FreeSpace = 100GB }
        } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }
        $result = (Invoke-LatencyAudit -RuleId 'disk-space').Results[0]
        $result.Status | Should -Be 'Fail'
        $result.Current | Should -Be 10
    }

    It 'pending-reboot fails when the Windows Update flag exists' {
        Mock -ModuleName LatencyAudit Test-LaRegistryKey { $true } -ParameterFilter { $Path -like '*RebootRequired' }
        (Invoke-LatencyAudit -RuleId 'pending-reboot').Results[0].Status | Should -Be 'Fail'
    }

    It 'gpu-driver-age fails for a driver older than 180 days and ignores virtual adapters' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            @(
                [pscustomobject]@{ Name = 'Parsec Virtual Display Adapter'; DriverDate = (Get-Date).AddDays(-5); CurrentRefreshRate = $null; DriverVersion = '1' }
                [pscustomobject]@{ Name = 'GPU Teste'; DriverDate = (Get-Date).AddDays(-400); CurrentRefreshRate = 144; DriverVersion = '2' }
            )
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
        $result = (Invoke-LatencyAudit -RuleId 'gpu-driver-age').Results[0]
        $result.Status | Should -Be 'Fail'
        $result.Current | Should -BeGreaterThan 390
        $result.Detail | Should -Match 'GPU Teste'
    }

    It 'ram-speed fails when modules run well below the rated speed' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            @(
                [pscustomobject]@{ Speed = 3200; ConfiguredClockSpeed = 2133 }
                [pscustomobject]@{ Speed = 3200; ConfiguredClockSpeed = 2133 }
            )
        } -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' }
        $result = (Invoke-LatencyAudit -RuleId 'ram-speed').Results[0]
        $result.Status | Should -Be 'Fail'
        $result.Current | Should -Be 67
    }

    It 'ram-speed is skipped when the configured speed is not reported' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance { [pscustomobject]@{ Speed = 3200; ConfiguredClockSpeed = $null } } -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' }
        (Invoke-LatencyAudit -RuleId 'ram-speed').Results[0].Status | Should -Be 'Skipped'
    }

    It 'display-refresh fails below the maximum and skips gracefully without data' {
        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            [pscustomobject]@{ Name = 'GPU Teste'; CurrentRefreshRate = 60; MaxRefreshRate = 144; DriverDate = Get-Date }
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
        (Invoke-LatencyAudit -RuleId 'display-refresh').Results[0].Status | Should -Be 'Fail'

        Mock -ModuleName LatencyAudit Get-LaCimInstance {
            [pscustomobject]@{ Name = 'GPU Teste'; CurrentRefreshRate = $null; MaxRefreshRate = $null; DriverDate = Get-Date }
        } -ParameterFilter { $ClassName -eq 'Win32_VideoController' }
        (Invoke-LatencyAudit -RuleId 'display-refresh').Results[0].Status | Should -Be 'Skipped'
    }
}
