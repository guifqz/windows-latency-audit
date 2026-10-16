BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\LatencyAudit\LatencyAudit.psd1') -Force
}

AfterAll {
    Remove-Module LatencyAudit -ErrorAction SilentlyContinue
}

Describe 'Get-LatencyScore' {
    It 'returns 100 when every scored rule passes' {
        InModuleScope LatencyAudit {
            $results = @(
                [pscustomobject]@{ Status = 'Pass'; Severity = 'High' }
                [pscustomobject]@{ Status = 'Pass'; Severity = 'Low' }
            )
            Get-LatencyScore -Result $results | Should -Be 100
        }
    }

    It 'returns 0 when every scored rule fails' {
        InModuleScope LatencyAudit {
            $results = @(
                [pscustomobject]@{ Status = 'Fail'; Severity = 'High' }
                [pscustomobject]@{ Status = 'Fail'; Severity = 'Medium' }
            )
            Get-LatencyScore -Result $results | Should -Be 0
        }
    }

    It 'weights High=3, Medium=2, Low=1' {
        InModuleScope LatencyAudit {
            # earned 3 of 6 => 50
            $results = @(
                [pscustomobject]@{ Status = 'Pass'; Severity = 'High' }
                [pscustomobject]@{ Status = 'Fail'; Severity = 'Medium' }
                [pscustomobject]@{ Status = 'Fail'; Severity = 'Low' }
            )
            Get-LatencyScore -Result $results | Should -Be 50
        }
    }

    It 'ignores Info, Skipped and Error results' {
        InModuleScope LatencyAudit {
            $results = @(
                [pscustomobject]@{ Status = 'Pass'; Severity = 'Medium' }
                [pscustomobject]@{ Status = 'Info'; Severity = 'Info' }
                [pscustomobject]@{ Status = 'Skipped'; Severity = 'High' }
                [pscustomobject]@{ Status = 'Error'; Severity = 'High' }
            )
            Get-LatencyScore -Result $results | Should -Be 100
        }
    }

    It 'returns 100 when nothing could be scored' {
        InModuleScope LatencyAudit {
            Get-LatencyScore -Result @() | Should -Be 100
        }
    }

    It 'rounds to the nearest integer' {
        InModuleScope LatencyAudit {
            # earned 2 of 3 => 66.67 => 67
            $results = @(
                [pscustomobject]@{ Status = 'Pass'; Severity = 'Medium' }
                [pscustomobject]@{ Status = 'Fail'; Severity = 'Low' }
            )
            Get-LatencyScore -Result $results | Should -Be 67
        }
    }
}

Describe 'Get-LatencyGrade' {
    It 'maps <Score> to <Grade>' -ForEach @(
        @{ Score = 100; Grade = 'Excelente' }
        @{ Score = 90; Grade = 'Excelente' }
        @{ Score = 89; Grade = 'Bom' }
        @{ Score = 75; Grade = 'Bom' }
        @{ Score = 74; Grade = 'Regular' }
        @{ Score = 50; Grade = 'Regular' }
        @{ Score = 49; Grade = 'Crítico' }
        @{ Score = 0; Grade = 'Crítico' }
    ) {
        InModuleScope LatencyAudit -Parameters @{ Score = $Score; Grade = $Grade } {
            Get-LatencyGrade -Score $Score | Should -Be $Grade
        }
    }
}

Describe 'Invoke-LatencyAudit scoring' {
    BeforeEach {
        Mock -ModuleName LatencyAudit Get-LaCimInstance { $null }
        Mock -ModuleName LatencyAudit Get-LaRegistryEntry { [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null } }
    }

    It 'aggregates custom rules into score, grade and counters' {
        $rules = InModuleScope LatencyAudit {
            @(
                New-LatencyRule -Id 'a' -Category 'X' -Title 'A' -Why 'w' -Severity High -Expected 1 -Test { 1 }
                New-LatencyRule -Id 'b' -Category 'X' -Title 'B' -Why 'w' -Severity High -Expected 1 -Test { 0 }
                New-LatencyRule -Id 'c' -Category 'Y' -Title 'C' -Why 'w' -Severity Info -Test { 'n/a' }
                New-LatencyRule -Id 'd' -Category 'Y' -Title 'D' -Why 'w' -Severity Low -Expected 1 -Test { New-LaSkipResult -Reason 'sem dado' }
                New-LatencyRule -Id 'e' -Category 'Y' -Title 'E' -Why 'w' -Severity Low -Expected 1 -Test { throw 'boom' }
            )
        }

        $audit = Invoke-LatencyAudit -Rule $rules

        $audit.Score | Should -Be 50
        $audit.Grade | Should -Be 'Regular'
        $audit.Passed | Should -Be 1
        $audit.Failed | Should -Be 1
        $audit.Info | Should -Be 1
        $audit.Skipped | Should -Be 1
        $audit.Errors | Should -Be 1
        $audit.Results | Should -HaveCount 5
    }

    It 'filters by RuleId and Category with wildcards' {
        $audit = Invoke-LatencyAudit -RuleId 'nagle', 'fullscreen*'
        $audit.Results.Id | Should -Be @('fullscreen-optimizations', 'nagle')
    }
}
