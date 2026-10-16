BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\LatencyAudit\LatencyAudit.psd1') -Force

    $rules = InModuleScope LatencyAudit {
        @(
            New-LatencyRule -Id 'r1' -Category 'Energia' -Title 'Plano <script>alert(1)</script>' -Why 'Porque "importa" & muito.' `
                -Severity High -Expected 1 -Test { 0 } `
                -Targets @(@{ Path = 'HKCU:\Software\Fake'; Name = 'V'; Value = 1; Kind = 'DWord' })
            New-LatencyRule -Id 'r2' -Category 'Gráficos' -Title 'Driver' -Why 'Explicação.' -Severity Medium -Expected 1 -Test { 1 }
            New-LatencyRule -Id 'r3' -Category 'Gráficos' -Title 'Informativa' -Why 'Só informa.' -Severity Info -Test { 'x' }
        )
    }
    $script:Audit = Invoke-LatencyAudit -Rule $rules
}

AfterAll {
    Remove-Module LatencyAudit -ErrorAction SilentlyContinue
}

Describe 'Export-LatencyAuditReport' {
    BeforeAll {
        $script:Path = Join-Path $TestDrive 'out\relatorio.html'
        $script:File = $script:Audit | Export-LatencyAuditReport -Path $script:Path -Note 'Dados de teste'
        $script:Html = Get-Content -LiteralPath $script:Path -Raw -Encoding UTF8
    }

    It 'writes the file and returns it' {
        $script:File.FullName | Should -Be $script:Path
        $script:Path | Should -Exist
    }

    It 'shows the score, grade and one section per category' {
        $script:Html | Should -Match ('<strong>{0}</strong>' -f $script:Audit.Score)
        $script:Html | Should -Match '<h2>Energia</h2>'
        $script:Html | Should -Match '<h2>Gráficos</h2>'
        $script:Html | Should -Match 'Dados de teste'
    }

    It 'encodes user-visible text' {
        $script:Html | Should -Match 'Plano &lt;script&gt;'
        $script:Html | Should -Match '&quot;importa&quot; &amp; muito'
        $script:Html | Should -Not -Match '<script'
    }

    It 'is self-contained' {
        $script:Html | Should -Not -Match '(src|href)\s*='
        $script:Html | Should -Not -Match 'https?://'
    }

    It 'suggests the fix command for failing rules that can be fixed' {
        $script:Html | Should -Match 'Set-LatencyRecommendation -RuleId r1 -WhatIf'
    }

    It 'sets the gauge offset from the score' {
        $expected = [math]::Round(2 * [math]::PI * 70 * (1 - $script:Audit.Score / 100), 2).ToString('0.##', [cultureinfo]::InvariantCulture)
        $script:Html | Should -Match "stroke-dashoffset=`"$([regex]::Escape($expected))`""
    }
}
