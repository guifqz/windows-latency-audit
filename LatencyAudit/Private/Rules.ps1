# Rule catalog. Each rule is data: how to read the current value (Test), what is expected,
# why it matters (pt-BR, shown to the user) and, when a safe change exists, how to apply
# (Fix), snapshot (Backup) and revert (Undo) it. Rules marked Info are reported but never scored.

$script:HighPerformancePlans = @(
    '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'  # Alto desempenho
    'e9a42b02-d5df-448d-aa00-03f14749eb61'  # Desempenho máximo
)
$script:UsbSubgroup = '2a737441-1930-4402-8d77-b2bebba308a3'
$script:UsbSelectiveSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$script:VirtualAdapterPattern = 'Basic|Remote|Virtual|Parsec|Meta|Mirage|Indirect'

function Get-LaActiveVideoController {
    $controllers = @(Get-LaCimInstance -ClassName Win32_VideoController |
            Where-Object { $_.Name -notmatch $script:VirtualAdapterPattern })
    if ($controllers.Count -eq 0) { return $null }
    $active = @($controllers | Where-Object { $_.CurrentRefreshRate -gt 0 })
    if ($active.Count -gt 0) { $active[0] } else { $controllers[0] }
}

function Get-LaRuleCatalog {
    @(
        New-LatencyRule -Id 'power-plan' -Category 'Energia' -Severity High `
            -Title 'Plano de energia ativo' `
            -Why 'Planos Equilibrado e Economia de energia reduzem a frequência da CPU sob carga leve e aumentam a variação de tempo de quadro (frametime). Alto desempenho ou Desempenho máximo mantêm a CPU responsiva. Em notebook na bateria o consumo sobe.' `
            -Expected { param($v) $v -in $script:HighPerformancePlans } `
            -ExpectedText 'Alto desempenho ou Desempenho máximo' `
            -RequiresAdmin `
            -Test {
                $plan = Get-LaActivePowerPlan
                if (-not $plan) { return New-LaSkipResult -Reason 'Não foi possível ler o plano de energia ativo.' }
                $stock = '381b4222-f694-41f0-9685-ff5bb260df2e', 'a1841308-3541-4fab-bc81-f71556f20b4a'
                $detail = if ($plan.Guid -in $script:HighPerformancePlans + $stock) { "GUID $($plan.Guid)" }
                else { 'Plano personalizado: se já foi ajustado para desempenho, ignore este achado.' }
                New-LaTestResult -Value $plan.Guid -Display $plan.Name -Detail $detail
            } `
            -Backup { @{ Guid = (Get-LaActivePowerPlan).Guid } } `
            -Fix { Invoke-LaPowerCfg -Argument '/setactive', 'SCHEME_MIN' | Out-Null } `
            -Undo { param($State) Invoke-LaPowerCfg -Argument '/setactive', $State.Guid | Out-Null }

        New-LatencyRule -Id 'game-mode' -Category 'Jogos' -Severity Low `
            -Title 'Modo de Jogo do Windows' `
            -Why 'O Modo de Jogo evita que o Windows Update instale drivers e notifique durante o jogo e prioriza recursos para o processo em primeiro plano. O ganho costuma ser pequeno; o ponto é não deixar desligado sem motivo.' `
            -Expected 1 -ExpectedText 'Ligado' `
            -Targets @(@{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Value = 1; Kind = 'DWord' }) `
            -Test {
                $v = Get-LaRegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled'
                if ($null -eq $v) {
                    return New-LaTestResult -Value 1 -Display 'Ligado (padrão)' -Detail 'Valor ausente: vale o padrão do Windows, que é ligado.'
                }
                New-LaTestResult -Value $v -Display $(if ($v -eq 1) { 'Ligado' } else { 'Desligado' })
            }

        New-LatencyRule -Id 'hags' -Category 'Gráficos' -Severity Low `
            -Title 'Agendamento de GPU acelerado por hardware (HAGS)' `
            -Why 'Move o agendamento de memória de vídeo da CPU para a GPU. Pode reduzir latência com Frame Generation (DLSS 3/FSR 3) e aliviar a CPU, mas em alguns drivers e jogos o resultado é neutro ou pior. Ative e compare o desempenho antes de manter.' `
            -Expected 2 -ExpectedText 'Ligado' `
            -RequiresAdmin -RebootRequired `
            -Targets @(@{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Value = 2; Kind = 'DWord' }) `
            -Test {
                $v = Get-LaRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
                $text = switch ($v) { 2 { 'Ligado' } 1 { 'Desligado' } default { 'Padrão do driver' } }
                New-LaTestResult -Value $v -Display $text -Detail 'Exige GPU e driver compatíveis; sem suporte o valor é ignorado.'
            }

        New-LatencyRule -Id 'game-dvr' -Category 'Jogos' -Severity Medium `
            -Title 'Captura em segundo plano (Xbox Game DVR / Game Bar)' `
            -Why 'A gravação em segundo plano mantém o codificador de vídeo da GPU ativo e consome CPU, memória e disco enquanto você joga, o que pode gerar quedas de FPS e microtravadas. Quem não usa a captura do Windows ganha estabilidade desativando.' `
            -Expected 'Desativada' `
            -Targets @(
                @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Value = 0; Kind = 'DWord' }
                @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Value = 0; Kind = 'DWord' }
            ) `
            -Test {
                $store = Get-LaRegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled'
                $capture = Get-LaRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled'
                $enabled = ($store -ne 0) -or ($capture -ne 0)
                New-LaTestResult -Value $(if ($enabled) { 'Ativa' } else { 'Desativada' }) `
                    -Detail "GameDVR_Enabled=$(Format-LaValue $store); AppCaptureEnabled=$(Format-LaValue $capture)"
            }

        New-LatencyRule -Id 'fullscreen-optimizations' -Category 'Jogos' -Severity Info `
            -Title 'Otimizações de tela cheia (flag global)' `
            -Why 'Em jogos modernos (DirectX 11/12 com flip model) a otimização de tela cheia é neutra ou melhora a latência. Desativar ajuda principalmente em jogos antigos e depende do título. Por isso só informamos: teste jogo a jogo em vez de mudar globalmente.' `
            -Test {
                $v = Get-LaRegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode'
                New-LaTestResult -Value $v -Display $(if ($v -eq 2) { 'Desativadas globalmente' } else { 'Padrão do Windows' })
            }

        New-LatencyRule -Id 'vbs-hvci' -Category 'Segurança' -Severity Info `
            -Title 'Isolamento de núcleo / Integridade de memória (VBS e HVCI)' `
            -Why 'VBS e HVCI usam o hipervisor para proteger o kernel contra drivers maliciosos. O custo em jogos varia de zero a alguns por cento de FPS, mais perceptível em CPUs antigas. Esta é uma troca entre segurança e desempenho e a decisão é sua: a ferramenta só mostra o estado.' `
            -Expected $false -ExpectedText 'Integridade de memória desligada' `
            -RequiresAdmin -RequiresForce -RebootRequired `
            -Warning 'Desativar a Integridade de memória (HVCI) remove uma proteção contra drivers maliciosos e exploits no kernel. Só faça isso em máquina dedicada a jogos, com drivers de fontes confiáveis.' `
            -Targets @(@{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Enabled'; Value = 0; Kind = 'DWord' }) `
            -Test {
                $guard = @(Get-LaCimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard')
                if ($guard.Count -eq 0 -or $null -eq $guard[0]) {
                    return New-LaSkipResult -Reason 'Win32_DeviceGuard indisponível neste sistema.'
                }
                $vbs = [int]$guard[0].VirtualizationBasedSecurityStatus -eq 2
                $hvci = @($guard[0].SecurityServicesRunning) -contains 2
                $text = if ($hvci) { 'VBS ativo, Integridade de memória (HVCI) ativa' }
                elseif ($vbs) { 'VBS ativo, HVCI desligada' }
                else { 'VBS desligado' }
                New-LaTestResult -Value $hvci -Display $text
            }

        New-LatencyRule -Id 'mouse-acceleration' -Category 'Entrada' -Severity Medium `
            -Title 'Aceleração do mouse (Aprimorar precisão do ponteiro)' `
            -Why 'Com a aceleração ligada, a distância percorrida pelo cursor depende da velocidade do movimento, o que atrapalha a memória muscular em jogos de mira. Desligada, o movimento é proporcional. A mudança vale após encerrar a sessão do Windows.' `
            -Expected 'Desativada' `
            -Targets @(
                @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Value = '0'; Kind = 'String' }
                @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Value = '0'; Kind = 'String' }
                @{ Path = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Value = '0'; Kind = 'String' }
            ) `
            -Test {
                $speed = Get-LaRegistryValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed'
                New-LaTestResult -Value $(if ("$speed" -eq '0') { 'Desativada' } else { 'Ativada' }) -Detail "MouseSpeed=$(Format-LaValue $speed)"
            }

        New-LatencyRule -Id 'nagle' -Category 'Rede' -Severity Info `
            -Title 'Algoritmo de Nagle (TcpAckFrequency / TCPNoDelay)' `
            -Why 'O ajuste de Nagle afeta conexões TCP. A maioria dos jogos competitivos usa UDP, então a mudança não traz ganho comprovado e entra na lista de dicas sem efeito. Não avaliamos nem alteramos; use ping e jitter medidos como referência.' `
            -Test { New-LaTestResult -Value $null -Display 'Informativo, não avaliado' }

        New-LatencyRule -Id 'net-adapter-power' -Category 'Rede' -Severity Medium `
            -Title 'Economia de energia nos adaptadores de rede' `
            -Why 'Quando o Windows pode desligar o adaptador para economizar energia, a placa pode acordar com atraso e causar picos de ping e quedas de conexão. Em desktop não há motivo para manter ligado.' `
            -Expected { param($v) @($v | Where-Object { $_ }).Count -eq 0 } `
            -ExpectedText 'Nenhum adaptador com economia de energia' `
            -RequiresAdmin `
            -Test {
                $state = Get-LaNetAdapterPowerState
                if ($null -eq $state) { return New-LaSkipResult -Reason 'Cmdlets de gerenciamento de energia de rede indisponíveis.' }
                $names = @($state | Where-Object AllowTurnOffEnabled | ForEach-Object Name)
                New-LaTestResult -Value $names
            } `
            -Backup { @{ Items = @(Get-LaNetAdapterPowerState | Where-Object AllowTurnOffEnabled | ForEach-Object { @{ Name = $_.Name } }) } } `
            -Fix {
                foreach ($adapter in @(Get-LaNetAdapterPowerState | Where-Object AllowTurnOffEnabled)) {
                    Set-LaNetAdapterPowerState -Name $adapter.Name -AllowTurnOff $false
                }
            } `
            -Undo {
                param($State)
                foreach ($item in $State.Items) { Set-LaNetAdapterPowerState -Name $item.Name -AllowTurnOff $true }
            }

        New-LatencyRule -Id 'usb-selective-suspend' -Category 'Energia' -Severity Medium `
            -Title 'Suspensão seletiva de USB (plano ativo, na tomada)' `
            -Why 'A suspensão seletiva coloca portas USB em repouso. Mouse, teclado e headset podem ter atraso ao acordar ou desconectar por instantes. Desativar na tomada elimina essa fonte de falha de entrada.' `
            -Expected 0 -ExpectedText 'Desativada' `
            -RequiresAdmin `
            -Test {
                $v = Get-LaPowerSettingAc -SubgroupGuid $script:UsbSubgroup -SettingGuid $script:UsbSelectiveSuspend
                if ($null -eq $v) { return New-LaSkipResult -Reason 'Configuração não encontrada no plano de energia ativo.' }
                New-LaTestResult -Value $v -Display $(if ($v -eq 0) { 'Desativada' } else { 'Ativada' })
            } `
            -Backup {
                @{ Value = Get-LaPowerSettingAc -SubgroupGuid $script:UsbSubgroup -SettingGuid $script:UsbSelectiveSuspend }
            } `
            -Fix {
                Set-LaPowerSettingAc -SubgroupGuid $script:UsbSubgroup -SettingGuid $script:UsbSelectiveSuspend -Value 0
            } `
            -Undo {
                param($State)
                Set-LaPowerSettingAc -SubgroupGuid $script:UsbSubgroup -SettingGuid $script:UsbSelectiveSuspend -Value ([int]$State.Value)
            }

        New-LatencyRule -Id 'startup-apps' -Category 'Sistema' -Severity Low `
            -Title 'Programas na inicialização' `
            -Why 'Cada programa na inicialização disputa CPU, disco e rede logo após o boot e muitos continuam em segundo plano durante o jogo. A ferramenta não remove nada, porque só você sabe o que usa.' `
            -Expected { param($v) $v -le 10 } -ExpectedText 'até 10 itens' -Unit 'itens' `
            -Test {
                $items = @(Get-LaCimInstance -ClassName Win32_StartupCommand)
                if ($items.Count -eq 1 -and $null -eq $items[0]) {
                    return New-LaSkipResult -Reason 'Win32_StartupCommand indisponível.'
                }
                $sample = ($items | Select-Object -First 5 -ExpandProperty Name) -join ', '
                New-LaTestResult -Value $items.Count -Detail $(if ($sample) { "Exemplos: $sample" })
            }

        New-LatencyRule -Id 'background-apps' -Category 'Sistema' -Severity Low `
            -Title 'Apps em segundo plano (chave global)' `
            -Why 'Apps da Microsoft Store permitidos em segundo plano consomem CPU, rede e bateria. No Windows 11 o controle é por app e a chave global pode não existir; nesse caso a regra é ignorada.' `
            -Expected 1 -ExpectedText 'Desativado' `
            -Targets @(@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Value = 1; Kind = 'DWord' }) `
            -Test {
                $v = Get-LaRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled'
                if ($null -eq $v) { return New-LaSkipResult -Reason 'Chave global ausente (controle por app no Windows 11).' }
                New-LaTestResult -Value $v -Display $(if ($v -eq 1) { 'Desativado' } else { 'Permitido' })
            }

        New-LatencyRule -Id 'visual-effects' -Category 'Sistema' -Severity Info `
            -Title 'Efeitos visuais do Windows' `
            -Why 'Animações e transparências usam a GPU do desktop, não a do jogo em tela cheia. O impacto em FPS é pequeno e só importa em GPU integrada ou PC fraco. Mostramos o estado sem recomendar mudança.' `
            -Test {
                $v = Get-LaRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting'
                $text = switch ($v) {
                    0 { 'Deixar o Windows escolher' } 1 { 'Melhor aparência' } 2 { 'Melhor desempenho' } 3 { 'Personalizado' }
                    default { 'Padrão do Windows' }
                }
                New-LaTestResult -Value $v -Display $text
            }

        New-LatencyRule -Id 'pagefile' -Category 'Sistema' -Severity Medium `
            -Title 'Arquivo de paginação (pagefile)' `
            -Why 'Sem arquivo de paginação, jogos e launchers podem fechar com erro de memória insuficiente mesmo com muita RAM livre, porque reservam mais memória virtual do que usam. O recomendado é deixar o Windows gerenciar.' `
            -Expected { param($v) $v -ne 'Desativado' } -ExpectedText 'Gerenciado pelo sistema ou manual' `
            -Test {
                $cs = @(Get-LaCimInstance -ClassName Win32_ComputerSystem) | Select-Object -First 1
                if (-not $cs) { return New-LaSkipResult -Reason 'Win32_ComputerSystem indisponível.' }
                if ($cs.AutomaticManagedPagefile) { return New-LaTestResult -Value 'Automático' }
                $files = @(Get-LaCimInstance -ClassName Win32_PageFileSetting | Where-Object { $_ })
                if ($files.Count -eq 0) { return New-LaTestResult -Value 'Desativado' }
                $detail = ($files | ForEach-Object { "$($_.Name): $($_.InitialSize)-$($_.MaximumSize) MB" }) -join '; '
                New-LaTestResult -Value 'Manual' -Detail $detail
            }

        New-LatencyRule -Id 'disk-space' -Category 'Sistema' -Severity Medium `
            -Title 'Espaço livre no disco do sistema' `
            -Why 'Disco quase cheio atrasa atualizações, cache de shaders, arquivo de paginação e a escrita em SSD (menos área para o controlador trabalhar). Manter pelo menos 15% livre evita perda de desempenho e falhas de instalação.' `
            -Expected { param($v) $v -ge 15 } -ExpectedText 'pelo menos 15% livre' -Unit '% livre' `
            -Test {
                $drive = $env:SystemDrive
                $disk = @(Get-LaCimInstance -ClassName Win32_LogicalDisk | Where-Object { $_ -and $_.DeviceID -eq $drive }) | Select-Object -First 1
                if (-not $disk -or -not $disk.Size) { return New-LaSkipResult -Reason "Disco $drive não encontrado." }
                $percent = [math]::Round(100 * $disk.FreeSpace / $disk.Size, 1)
                $detail = '{0:N1} GB livres de {1:N1} GB em {2}' -f ($disk.FreeSpace / 1GB), ($disk.Size / 1GB), $drive
                New-LaTestResult -Value $percent -Detail $detail
            }

        New-LatencyRule -Id 'pending-reboot' -Category 'Sistema' -Severity Low `
            -Title 'Reinicialização pendente do Windows Update' `
            -Why 'Com atualização aguardando reinício, o Windows pode usar CPU e disco em segundo plano e drivers novos ainda não valem. Reinicie antes de medir ou jogar.' `
            -Expected $false `
            -Test {
                $pending = (Test-LaRegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                (Test-LaRegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
                New-LaTestResult -Value ([bool]$pending)
            }

        New-LatencyRule -Id 'gpu-driver-age' -Category 'Gráficos' -Severity Medium `
            -Title 'Idade do driver de vídeo' `
            -Why 'Drivers de GPU recebem correções de desempenho e estabilidade para jogos novos quase todo mês. Um driver com mais de seis meses tende a perder otimizações e correções de travamento. Baixe sempre do site do fabricante.' `
            -Expected { param($v) $v -le 180 } -ExpectedText 'até 180 dias' -Unit 'dias' `
            -Test {
                $gpu = Get-LaActiveVideoController
                if (-not $gpu -or -not $gpu.DriverDate) { return New-LaSkipResult -Reason 'GPU física não detectada.' }
                $days = [int][math]::Max(0, ((Get-Date) - [datetime]$gpu.DriverDate).TotalDays)
                New-LaTestResult -Value $days -Detail ('{0}, versão {1}, de {2:dd/MM/yyyy}' -f $gpu.Name, $gpu.DriverVersion, $gpu.DriverDate)
            }

        New-LatencyRule -Id 'ram-speed' -Category 'Hardware' -Severity High `
            -Title 'Velocidade da memória RAM versus nominal' `
            -Why 'Pentes vendidos como DDR4-3200 ou DDR5-6000 costumam rodar em velocidade bem menor até ativar XMP ou EXPO na BIOS. Memória lenta derruba os FPS mínimos em jogos limitados pela CPU, sobretudo em Ryzen. A correção é feita na BIOS e esta ferramenta não a altera.' `
            -Expected { param($v) $v -ge 95 } -ExpectedText 'pelo menos 95% da velocidade nominal' -Unit '% da velocidade nominal' `
            -Test {
                $modules = @(Get-LaCimInstance -ClassName Win32_PhysicalMemory | Where-Object { $_.Speed -gt 0 -and $_.ConfiguredClockSpeed -gt 0 })
                if ($modules.Count -eq 0) { return New-LaSkipResult -Reason 'Velocidade configurada da RAM indisponível.' }
                $ratio = ($modules | ForEach-Object { 100 * $_.ConfiguredClockSpeed / $_.Speed } | Measure-Object -Minimum).Minimum
                $configured = ($modules | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
                $rated = ($modules | Measure-Object Speed -Maximum).Maximum
                New-LaTestResult -Value ([int][math]::Round($ratio)) -Detail "Configurada: $configured MT/s; nominal do módulo: $rated MT/s"
            }

        New-LatencyRule -Id 'display-refresh' -Category 'Gráficos' -Severity High `
            -Title 'Taxa de atualização do monitor' `
            -Why 'É comum o monitor de 144 Hz ou mais ficar em 60 Hz após trocar de cabo, driver ou GPU. Isso reduz a fluidez e aumenta a latência de exibição. A taxa máxima é a informada pelo driver de vídeo e pode diferir do que o monitor suporta.' `
            -Expected $true -ExpectedText 'Na taxa máxima informada pelo driver' `
            -Test {
                $gpu = Get-LaActiveVideoController
                if (-not $gpu -or -not ($gpu.CurrentRefreshRate -gt 0) -or -not ($gpu.MaxRefreshRate -gt 0)) {
                    return New-LaSkipResult -Reason 'Taxa de atualização atual ou máxima não detectada via CIM.'
                }
                $atMax = [int]$gpu.CurrentRefreshRate -ge [int]$gpu.MaxRefreshRate
                New-LaTestResult -Value $atMax -Display "$($gpu.CurrentRefreshRate) Hz (máximo $($gpu.MaxRefreshRate) Hz)"
            }
    )
}
