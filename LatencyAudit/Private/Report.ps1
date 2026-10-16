# HTML rendering for Export-LatencyAuditReport. Everything user-visible is HTML-encoded.

$script:ReportCss = @'
:root{--bg:#f4f6f9;--card:#fff;--text:#1b2430;--muted:#5d6b7e;--line:#e2e7ee;--ok:#1a8f4c;--warn:#c27c0e;--bad:#c93c3c;--info:#2f6fd6;--skip:#7b8794;--track:#e6ebf2}
@media (prefers-color-scheme:dark){:root{--bg:#10151c;--card:#182029;--text:#e6ebf2;--muted:#9aa8b9;--line:#26313e;--ok:#3ec57a;--warn:#e5a63a;--bad:#ef6a6a;--info:#6ea2f5;--skip:#8795a5;--track:#26313e}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 "Segoe UI",system-ui,-apple-system,sans-serif}
main{max-width:920px;margin:0 auto;padding:32px 20px 48px}
header{display:flex;flex-wrap:wrap;gap:28px;align-items:center;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:24px 28px}
.gauge{position:relative;width:160px;height:160px;flex:none}
.gauge svg{width:100%;height:100%;transform:rotate(-90deg)}
.gauge .track{fill:none;stroke:var(--track);stroke-width:12}
.gauge .bar{fill:none;stroke-width:12;stroke-linecap:round}
.gauge .num{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.gauge .num strong{font-size:40px;line-height:1}
.gauge .num span{font-size:13px;color:var(--muted)}
h1{margin:0 0 4px;font-size:24px}
.meta{color:var(--muted);font-size:13px;margin:0 0 14px}
.chips{display:flex;flex-wrap:wrap;gap:8px}
.chip{border:1px solid var(--line);border-radius:999px;padding:3px 12px;font-size:13px}
.note{margin:16px 0 0;padding:10px 14px;border-radius:10px;background:color-mix(in srgb,var(--warn) 14%,transparent);border:1px solid var(--warn);font-size:14px}
h2{margin:32px 0 12px;font-size:17px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-left:5px solid var(--skip);border-radius:10px;padding:14px 18px;margin:0 0 10px}
.card.pass{border-left-color:var(--ok)}.card.fail{border-left-color:var(--bad)}.card.info{border-left-color:var(--info)}.card.error{border-left-color:var(--warn)}
.card h3{margin:0;font-size:15px;display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.badge{font-size:11px;font-weight:600;border-radius:6px;padding:1px 8px;color:#fff;background:var(--skip)}
.badge.pass{background:var(--ok)}.badge.fail{background:var(--bad)}.badge.info{background:var(--info)}.badge.error{background:var(--warn)}
.sev{font-size:12px;color:var(--muted);font-weight:400}
.values{margin:6px 0 0;font-size:14px}
.values b{font-weight:600}
.why{margin:6px 0 0;color:var(--muted);font-size:14px}
.detail{margin:6px 0 0;font-size:12.5px;color:var(--muted);font-family:Consolas,monospace}
.warning{margin:8px 0 0;padding:8px 12px;border-radius:8px;background:color-mix(in srgb,var(--bad) 12%,transparent);font-size:13.5px}
code{font-family:Consolas,monospace;font-size:13px;background:var(--track);border-radius:5px;padding:1px 6px}
footer{margin-top:36px;color:var(--muted);font-size:12.5px;text-align:center}
@media (max-width:560px){header{padding:18px}.gauge{margin:0 auto}}
'@

function ConvertTo-LaHtml {
    param([AllowNull()]$Text)
    ([string]$Text).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
}

function Get-LaScoreColor {
    param([int]$Score)
    if ($Score -ge 75) { 'var(--ok)' } elseif ($Score -ge 50) { 'var(--warn)' } else { 'var(--bad)' }
}

function ConvertTo-LaReportHtml {
    param(
        [Parameter(Mandatory)]$Audit,
        [string]$Note
    )

    $statusLabel = @{ Pass = 'Conforme'; Fail = 'Atenção'; Info = 'Informativo'; Skipped = 'Ignorada'; Error = 'Erro' }
    $severityLabel = @{ High = 'impacto alto'; Medium = 'impacto médio'; Low = 'impacto baixo'; Info = 'sem pontuação' }
    $statusOrder = @{ Fail = 0; Error = 1; Info = 2; Skipped = 3; Pass = 4 }

    $circumference = 2 * [math]::PI * 70
    $offset = [math]::Round($circumference * (1 - $Audit.Score / 100), 2)
    $color = Get-LaScoreColor -Score $Audit.Score
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="pt-BR"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.AppendLine('<title>LatencyAudit - Relatório</title>')
    [void]$sb.AppendLine("<style>$script:ReportCss</style></head><body><main>")

    [void]$sb.AppendLine('<header>')
    [void]$sb.AppendLine(('<div class="gauge" role="img" aria-label="Nota {0} de 100"><svg viewBox="0 0 160 160"><circle class="track" cx="80" cy="80" r="70"/><circle class="bar" cx="80" cy="80" r="70" stroke="{1}" stroke-dasharray="{2}" stroke-dashoffset="{3}"/></svg><div class="num"><strong>{0}</strong><span>de 100</span></div></div>' -f `
                $Audit.Score, $color, $circumference.ToString('0.##', $inv), $offset.ToString('0.##', $inv)))
    [void]$sb.AppendLine('<div>')
    [void]$sb.AppendLine("<h1>Auditoria de latência: $(ConvertTo-LaHtml $Audit.Grade)</h1>")
    [void]$sb.AppendLine(('<p class="meta">{0} &middot; {1} &middot; {2:dd/MM/yyyy HH:mm}</p>' -f (ConvertTo-LaHtml $Audit.ComputerName), (ConvertTo-LaHtml $Audit.OS), $Audit.Timestamp))
    [void]$sb.AppendLine(('<div class="chips"><span class="chip">{0} conformes</span><span class="chip">{1} para ajustar</span><span class="chip">{2} informativas</span><span class="chip">{3} ignoradas</span></div>' -f $Audit.Passed, $Audit.Failed, $Audit.Info, ($Audit.Skipped + $Audit.Errors)))
    if ($Note) { [void]$sb.AppendLine("<p class=`"note`">$(ConvertTo-LaHtml $Note)</p>") }
    [void]$sb.AppendLine('</div></header>')

    $groups = @($Audit.Results | Group-Object Category)
    foreach ($group in $groups) {
        [void]$sb.AppendLine("<h2>$(ConvertTo-LaHtml $group.Name)</h2>")
        $ordered = $group.Group | Sort-Object { $statusOrder[$_.Status] }
        foreach ($r in $ordered) {
            $cls = $r.Status.ToLowerInvariant()
            [void]$sb.AppendLine("<section class=`"card $cls`">")
            [void]$sb.AppendLine(('<h3><span class="badge {0}">{1}</span>{2}<span class="sev">{3}</span></h3>' -f $cls, $statusLabel[$r.Status], (ConvertTo-LaHtml $r.Title), $severityLabel[$r.Severity]))
            if ($r.Status -notin 'Skipped', 'Error') {
                $expected = if ($r.Expected) { " &nbsp;&middot;&nbsp; Esperado: <b>$(ConvertTo-LaHtml $r.Expected)</b>" } else { '' }
                [void]$sb.AppendLine("<p class=`"values`">Atual: <b>$(ConvertTo-LaHtml $r.CurrentText)</b>$expected</p>")
            }
            [void]$sb.AppendLine("<p class=`"why`">$(ConvertTo-LaHtml $r.Why)</p>")
            if ($r.Detail) { [void]$sb.AppendLine("<p class=`"detail`">$(ConvertTo-LaHtml $r.Detail)</p>") }
            if ($r.Status -eq 'Fail' -and $r.CanFix) {
                $force = if ($r.RequiresForce) { ' -Force' } else { '' }
                [void]$sb.AppendLine("<p class=`"why`">Correção: <code>Set-LatencyRecommendation -RuleId $(ConvertTo-LaHtml $r.Id)$force -WhatIf</code></p>")
            }
            if ($r.Warning) { [void]$sb.AppendLine("<p class=`"warning`">$(ConvertTo-LaHtml $r.Warning)</p>") }
            [void]$sb.AppendLine('</section>')
        }
    }

    $version = (Get-Module LatencyAudit | Select-Object -First 1).Version
    [void]$sb.AppendLine("<footer>Gerado por LatencyAudit $version &middot; somente leitura: nenhuma configuração foi alterada.</footer>")
    [void]$sb.AppendLine('</main></body></html>')
    $sb.ToString()
}
