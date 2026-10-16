# windows-latency-audit

[![CI](https://github.com/guifqz/windows-latency-audit/actions/workflows/ci.yml/badge.svg)](https://github.com/guifqz/windows-latency-audit/actions/workflows/ci.yml)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> A PowerShell module that audits a Windows 10/11 machine for settings that affect gaming performance and input latency, scores it from 0 to 100 and explains every finding.
> Measure first: detection is read-only, changes are opt-in, backed up and reversible, and there are no placebo tweaks.

Auditoria de desempenho e latência para jogos no Windows, com nota de 0 a 100, explicação de cada achado e correções opcionais com backup e rollback. Não é mais um "debloater": primeiro mede, depois (se você quiser) muda, e sempre dá para desfazer.

Veja um relatório de exemplo (dados fictícios): [`docs/exemplo-relatorio.html`](docs/exemplo-relatorio.html).

## Filosofia

1. **Medir antes de mexer.** A auditoria é somente leitura, não exige administrador e não altera nada.
2. **Mudanças reversíveis.** Antes de qualquer correção, os valores atuais vão para um JSON em `%ProgramData%\LatencyAudit\backups`. `Restore-LatencyBackup` desfaz, inclusive removendo valores que não existiam antes.
3. **Sem placebo.** Dicas sem efeito comprovado (Nagle/TCPNoDelay, "otimizações" de tela cheia globais, efeitos visuais) aparecem só como informação, sem correção automática e sem pontuar.
4. **Segurança não é moeda de troca escondida.** VBS/HVCI é apenas reportado. Desativar exige `-Force` e mostra um aviso explícito.
5. **Cada regra explica o porquê**, em português, com o que o ajuste faz e quando ele não ajuda.

## Requisitos

- Windows 10 ou 11
- Windows PowerShell 5.1 ou PowerShell 7
- Administrador somente para **aplicar** correções que mexem em `HKLM`, plano de energia ou adaptador de rede (`-WhatIf` não exige)

## Instalação

```powershell
git clone https://github.com/guifqz/windows-latency-audit.git
Import-Module .\windows-latency-audit\LatencyAudit\LatencyAudit.psd1
```

## Uso

```powershell
# 1. Auditar (somente leitura)
$audit = Invoke-LatencyAudit
$audit.Score                                   # 0..100
$audit.Results | Where-Object Status -eq 'Fail' | Format-Table Id, CurrentText, Expected

# 2. Relatório HTML autocontido
$audit | Export-LatencyAuditReport -Path .\relatorio.html

# 3. Ver o que seria alterado, sem alterar
Set-LatencyRecommendation -RuleId game-dvr, mouse-acceleration -WhatIf

# 4. Aplicar (pede confirmação; PowerShell como administrador quando a regra exige)
Set-LatencyRecommendation -RuleId game-dvr, mouse-acceleration

# 5. Desfazer
Restore-LatencyBackup -Path "$env:ProgramData\LatencyAudit\backups\LatencyAudit-backup-20261016-101500-123.json"
```

Outros exemplos:

```powershell
Get-LatencyRule | Format-Table Id, Category, Severity, Title          # catálogo de regras
Invoke-LatencyAudit -Category Gráficos, Hardware                      # só algumas categorias
Set-LatencyRecommendation -RuleId vbs-hvci -Force -WhatIf             # regra sensível: exige -Force
```

### Comandos

| Comando | O que faz |
|---|---|
| `Invoke-LatencyAudit` | Roda as regras (somente leitura) e devolve um objeto com `Score`, `Grade`, contadores e `Results` |
| `Export-LatencyAuditReport` | Gera HTML autocontido (medidor da nota, achados por categoria, tema claro/escuro) |
| `Set-LatencyRecommendation` | Aplica correções (`-WhatIf`/`-Confirm`), com backup JSON prévio |
| `Restore-LatencyBackup` | Restaura os valores anteriores a partir de um backup |
| `Get-LatencyRule` | Lista as regras e seus metadados |

## Regras

Peso na nota: Alta = 3, Média = 2, Baixa = 1. Regras `Info` são mostradas, mas não pontuam. A nota é `pesos aprovados / pesos avaliados`; regras ignoradas ou com erro ficam de fora.

| Id | Categoria | Severidade | O que verifica | Correção |
|---|---|---|---|---|
| `power-plan` | Energia | Alta | Plano ativo é Alto desempenho ou Desempenho máximo | sim (admin) |
| `usb-selective-suspend` | Energia | Média | Suspensão seletiva de USB desligada (na tomada) | sim (admin) |
| `game-mode` | Jogos | Baixa | Modo de Jogo ligado | sim |
| `game-dvr` | Jogos | Média | Captura em segundo plano (Game DVR / Game Bar) desligada | sim |
| `fullscreen-optimizations` | Jogos | Info | Flag global de otimizações de tela cheia | não, depende do jogo |
| `hags` | Gráficos | Baixa | Agendamento de GPU por hardware (`HwSchMode`) | sim (admin, reinício) |
| `gpu-driver-age` | Gráficos | Média | Driver de vídeo com até 180 dias (`Win32_VideoController`) | não |
| `display-refresh` | Gráficos | Alta | Taxa de atualização atual igual à máxima informada pelo driver | não |
| `vbs-hvci` | Segurança | Info | VBS e Integridade de memória (HVCI): troca segurança por desempenho | só com `-Force` (admin, reinício) |
| `mouse-acceleration` | Entrada | Média | "Aprimorar precisão do ponteiro" desligado | sim |
| `nagle` | Rede | Info | Nota informativa sobre Nagle/TCPNoDelay | não |
| `net-adapter-power` | Rede | Média | Adaptadores físicos sem permissão para desligar por economia de energia | sim (admin) |
| `startup-apps` | Sistema | Baixa | Até 10 programas na inicialização | não |
| `background-apps` | Sistema | Baixa | Apps em segundo plano (chave global; ignorada se ausente) | sim |
| `visual-effects` | Sistema | Info | Estado dos efeitos visuais | não |
| `pagefile` | Sistema | Média | Arquivo de paginação não desativado | não |
| `disk-space` | Sistema | Média | Pelo menos 15% livre no disco do sistema | não |
| `pending-reboot` | Sistema | Baixa | Sem reinicialização pendente do Windows Update | não |
| `ram-speed` | Hardware | Alta | RAM rodando em pelo menos 95% da velocidade nominal (XMP/EXPO) | não (BIOS) |

### Como cada regra é definida

Regras são dados (`New-LatencyRule`): `Id`, `Category`, `Title`, `Why` (explicação em pt-BR), `Test` (devolve o valor atual), `Expected` (valor ou predicado), `Severity` e, opcionalmente, `Fix`, `Backup` e `Undo`. Regras de registro usam `-Targets` e ganham backup/undo genéricos. Adicionar uma regra é adicionar um item em [`LatencyAudit/Private/Rules.ps1`](LatencyAudit/Private/Rules.ps1).

## Segurança

- A auditoria nunca escreve no sistema. Todo acesso a registro, CIM e `powercfg` passa por uma camada fina ([`System.ps1`](LatencyAudit/Private/System.ps1)), que é a única coisa mockada nos testes.
- `Set-LatencyRecommendation` suporta `-WhatIf` e `-Confirm` (impacto alto: pede confirmação por padrão). Reavalia a regra, ignora o que já está conforme e **grava o backup antes de aplicar**.
- Exigir administrador só acontece na hora de aplicar. `-WhatIf` roda sem elevação.
- Regras marcadas como sensíveis (`vbs-hvci`) são recusadas sem `-Force`, e o aviso de segurança é exibido mesmo com `-Force`. Desativar a Integridade de memória remove uma proteção contra drivers maliciosos: só faça em máquina dedicada a jogos, com drivers de fonte confiável. A correção só altera a chave da HVCI (HypervisorEnforcedCodeIntegrity).
- Alguns ajustes só valem após reiniciar ou encerrar a sessão; o resultado indica `RebootRequired`.
- Os backups ficam em `%ProgramData%\LatencyAudit\backups` (um arquivo por execução). Para reverter, passe o arquivo a `Restore-LatencyBackup`.

## Limitações conhecidas

- `display-refresh` compara com a taxa máxima que o driver de vídeo informa via CIM, que pode diferir do que o monitor suporta. Sem esses dados a regra é ignorada.
- Plano de energia personalizado (por exemplo, um plano já ajustado à mão) é apontado como divergente, com uma nota para ignorar se for o caso.
- `startup-apps` conta o que o Windows expõe em `Win32_StartupCommand`; itens do Agendador de Tarefas e serviços não entram.
- `hags` e `gpu-driver-age` dependem do hardware e do driver; o relatório explica que o ganho pode ser nulo.

## Desenvolvimento

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force

Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning, Error
Invoke-Pester -Path .\Tests -Output Detailed
```

Os testes (Pester 5) cobrem o motor de regras, a nota, o backup/restauração e o relatório. Registro, CIM e `powercfg` são sempre mockados; nenhum teste toca o sistema real. Para regenerar o relatório de exemplo: `.\tools\New-ExampleReport.ps1`.

O CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) roda PSScriptAnalyzer e Pester em `windows-latest`, no PowerShell 7 e no Windows PowerShell 5.1.

### Estrutura

```
LatencyAudit/
  LatencyAudit.psd1 / .psm1
  Public/    comandos exportados
  Private/   motor de regras, catálogo, camada de sistema, backup, HTML
Tests/       Pester 5
docs/        relatório de exemplo
tools/       gerador do relatório de exemplo
```

## Licença

[MIT](LICENSE) (c) 2026 Guilherme.
