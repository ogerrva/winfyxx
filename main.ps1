# --- DETERMINA SE ESTÁ RODANDO COMO ADMIN ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# --- DEFINIÇÕES DE DIRETÓRIOS E COMPATIBILIDADE ---
$InstallDir = Join-Path $env:LOCALAPPDATA "FYXX"
$JsonPath = Join-Path $InstallDir "apps.json"
$LocalScriptPath = Join-Path $InstallDir "main.ps1"
$LocalVersionPath = Join-Path $InstallDir "version.txt"
$ShortcutPath = "$env:USERPROFILE\Desktop\FYXX Utility.lnk"

# --- BOOTSTRAP: DESACOPLAMENTO DE PROCESSO (Roda no terminal do cliente) ---
# Se o script estiver rodando sem caminho físico (IEX) ou não for Administrador:
if (-not $PSCommandPath -or -not $isAdmin) {
    # Garante a criação da pasta local
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Baixa silenciosamente a versão mais nova antes de disparar o processo independente
    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $headers = @{ "Cache-Control" = "no-cache, no-store, must-revalidate"; "Pragma" = "no-cache" }
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/main.ps1?t=$timestamp" -Headers $headers -OutFile $LocalScriptPath
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/apps.json?t=$timestamp" -Headers $headers -OutFile $JsonPath
    }
    catch {
        # Fallback offline caso o cliente esteja sem internet
    }

    # Dispara um processo NOVO, SEPARADO e ELEVADO para rodar o utilitário
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`"" -Verb RunAs
    
    # Encerra o terminal atual do usuário imediatamente. O programa continuará rodando livre no novo processo.
    Exit
}

# --- EXECUÇÃO DO PROCESSO INDEPENDENTE (A partir daqui roda em background elevado) ---

# Carrega as APIs nativas do Windows sem duplicar tipos (Evita erros ao rodar o script múltiplas vezes)
if (-not ([System.Management.Automation.PSTypeName]"Win32.Win32ConsoleUtils").Type) {
    Add-Type -MemberDefinition @"
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    "@ -Name "Win32ConsoleUtils" -Namespace "Win32" | Out-Null
}

# Oculta o console deste processo elevado em segundo plano
$hwnd = [Win32.Win32ConsoleUtils]::GetConsoleWindow()
if ($hwnd -ne [IntPtr]::Zero) {
    [Win32.Win32ConsoleUtils]::ShowWindowAsync($hwnd, 0) | Out-Null
}

# Carrega as bibliotecas gráficas do .NET
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- SISTEMA DE LOGS SEGURO ---
$global:InitialLogs = @()
$logTextBox = $null

function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $text = "[$timestamp] $Message`r`n"
    if ($null -ne $logTextBox) {
        if ($form.InvokeRequired) {
            $form.Invoke([Action[string]]{ $logTextBox.AppendText($args[0]) }, $text)
        } else {
            $logTextBox.AppendText($text)
        }
    } else {
        $global:InitialLogs += $text
    }
}

function Test-Winget {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Set-EdgeGoogleDefault {
    $EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    try {
        if (-not (Test-Path $EdgePath)) {
            New-Item -Path $EdgePath -Force | Out-Null
        }
        Set-ItemProperty -Path $EdgePath -Name 'RestoreOnStartup' -Value 4 -Type DWord -Force
        Set-ItemProperty -Path $EdgePath -Name 'RestoreOnStartupURLs' -Value @('https://www.google.com') -Type MultiString -Force
        Set-ItemProperty -Path $EdgePath -Name 'NewTabPageLocation' -Value 'https://www.google.com' -Type String -Force
        Set-ItemProperty -Path $EdgePath -Name 'DefaultSearchProviderEnabled' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $EdgePath -Name 'DefaultSearchProviderKeyword' -Value 'google.com' -Type String -Force
        Set-ItemProperty -Path $EdgePath -Name 'DefaultSearchProviderName' -Value 'Google' -Type String -Force
        Set-ItemProperty -Path $EdgePath -Name 'DefaultSearchProviderSearchURL' -Value 'https://www.google.com/search?q={searchTerms}' -Type String -Force
        Set-ItemProperty -Path $EdgePath -Name 'DefaultSearchProviderSuggestURL' -Value 'https://www.google.com/complete/search?output=chrome&q={searchTerms}' -Type String -Force
        return $true
    }
    catch {
        return $false
    }
}

# Verifica atualizações e cria o atalho localmente
function Install-LocalFilesAndShortcut {
    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $headers = @{ 
            "Cache-Control" = "no-cache, no-store, must-revalidate"
            "Pragma"        = "no-cache"
            "User-Agent"    = "FYXX-Utility-Updater"
        }
        
        $ApiUrl = "https://api.github.com/repos/ogerrva/winfyxx/commits/main"
        $remoteSha = (Invoke-RestMethod -Uri $ApiUrl -Headers $headers -ErrorAction Stop).sha
        
        $localSha = ""
        if (Test-Path $LocalVersionPath) {
            $localSha = Get-Content $LocalVersionPath -Raw
        }
        
        if ($remoteSha -ne $localSha) {
            Write-Log "Atualizando binários locais a partir do repositório..."
            Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/main.ps1?t=$timestamp" -Headers $headers -OutFile $LocalScriptPath
            Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/apps.json?t=$timestamp" -Headers $headers -OutFile $JsonPath
            $remoteSha | Out-File $LocalVersionPath -NoNewline -Encoding utf8
            Write-Log "Atualização do utilitário aplicada com sucesso."
        } else {
            Write-Log "O utilitário já se encontra na última versão estável."
        }
        
        if (-not (Test-Path $ShortcutPath)) {
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
            $Shortcut.TargetPath = "powershell.exe"
            $Shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LocalScriptPath`""
            $Shortcut.IconLocation = "powershell.exe"
            $Shortcut.WorkingDirectory = $InstallDir
            $Shortcut.Save()
            Write-Log "Atalho de Área de Trabalho gerado com sucesso."
        }
    }
    catch {
        Write-Log "Aviso: Sincronização offline ou indisponível temporariamente."
    }
}

# --- CARREGAMENTO RESILIENTE DO JSON ---
$AppConfig = $null
if (Test-Path $JsonPath) {
    try {
        $AppConfig = Get-Content $JsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Log "Iniciando verificação de integridade do apps.json..."
    }
}

if (-not $AppConfig) {
    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $headers = @{ "Cache-Control" = "no-cache, no-store, must-revalidate" }
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/apps.json?t=$timestamp" -Headers $headers -OutFile $JsonPath
        $AppConfig = Get-Content $JsonPath -Raw | ConvertFrom-Json
    }
    catch {
        $DefaultApps = '[{"Name":"Discord","ID":"Discord.Discord"},{"Name":"Epic Games","ID":"EpicGames.EpicGamesLauncher"},{"Name":"WinRAR","ID":"RARLab.WinRAR"},{"Name":"EA Play","ID":"ElectronicArts.EADesktop"},{"Name":"Ubisoft Connect","ID":"Ubisoft.Connect"},{"Name":"Terminus SSH","ID":"Termius.Termius"},{"Name":"FileZilla","ID":"FileZilla.FileZillaClient"},{"Name":"Brave Browser","ID":"BraveSoftware.BraveBrowser"},{"Name":"Telegram","ID":"Telegram.TelegramDesktop"},{"Name":"VSCode","ID":"Microsoft.VisualStudioCode"},{"Name":"VLC","ID":"VideoLAN.VLC"},{"Name":"CPU-Z","ID":"CPUID.CPU-Z"},{"Name":"Chrome","ID":"Google.Chrome"},{"Name":"Firefox","ID":"Mozilla.Firefox"},{"Name":"Edge","ID":"Microsoft.Edge"},{"Name":"Opera","ID":"Opera.Opera"},{"Name":"GeForce Experience","ID":"Nvidia.GeForceExperience"}]'
        $AppConfig = $DefaultApps | ConvertFrom-Json
        $DefaultApps | Out-File $JsonPath -Encoding utf8
    }
}

if ($null -eq $AppConfig -or $AppConfig.Count -eq 0) {
    $AppConfig = @( @{ Name = "Discord"; ID = "Discord.Discord" } )
}

# --- CONSTRUÇÃO DA INTERFACE GRÁFICA (GUI) ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "Gerenciador de Programas & Sistema - By OGERRVA"
$form.Size = New-Object System.Drawing.Size(750, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Força a criação do identificador de janela de imediato no thread visual principal
$null = $form.Handle

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Gerenciador de Programas"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.Size = New-Object System.Drawing.Size(350, 35)
$form.Controls.Add($titleLabel)

$authorLabel = New-Object System.Windows.Forms.Label
$authorLabel.Text = "======= By OGERRVA ======="
$authorLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$authorLabel.Location = New-Object System.Drawing.Point(20, 50)
$authorLabel.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($authorLabel)

$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Multiline = $true
$logTextBox.ScrollBars = "Vertical"
$logTextBox.ReadOnly = $true
$logTextBox.Location = New-Object System.Drawing.Point(20, 420)
$logTextBox.Size = New-Object System.Drawing.Size(690, 120)
$logTextBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$logTextBox.BackColor = [System.Drawing.Color]::Black
$logTextBox.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($logTextBox)

# Descarrega logs pré-inicialização com segurança
if ($global:InitialLogs.Count -gt 0) {
    $logTextBox.AppendText([string]::Join("", $global:InitialLogs))
    $global:InitialLogs = @()
}

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 80)
$tabControl.Size = New-Object System.Drawing.Size(690, 320)
$form.Controls.Add($tabControl)

# Configuração dinâmica de posições
$colX = @(20, 240, 460)
$startY = 20
$rowSpacing = 28
$itemsPerColumn = [math]::Ceiling($AppConfig.Count / 3)
if ($itemsPerColumn -lt 1) { $itemsPerColumn = 1 }

# --- ABA 1: INSTALAÇÃO ---
$tabInstall = New-Object System.Windows.Forms.TabPage
$tabInstall.Text = "Instalação"
$tabControl.Controls.Add($tabInstall)

$installCheckboxes = @()
for ($i = 0; $i -lt $AppConfig.Count; $i++) {
    $colIndex = [math]::Floor($i / $itemsPerColumn)
    $rowIndex = $i % $itemsPerColumn
    
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $AppConfig[$i].Name
    $cb.Tag = $AppConfig[$i].ID
    $cb.Location = New-Object System.Drawing.Point($colX[$colIndex], ($startY + ($rowIndex * $rowSpacing)))
    $cb.Size = New-Object System.Drawing.Size(200, 20)
    $tabInstall.Controls.Add($cb)
    $installCheckboxes += $cb
}

$btnInstallSelected = New-Object System.Windows.Forms.Button
$btnInstallSelected.Text = "Instalar Selecionados"
$btnInstallSelected.Location = New-Object System.Drawing.Point(20, 240)
$btnInstallSelected.Size = New-Object System.Drawing.Size(180, 30)
$tabInstall.Controls.Add($btnInstallSelected)

$btnCustomInstall = New-Object System.Windows.Forms.Button
$btnCustomInstall.Text = "Pesquisa e Instal. Personalizada"
$btnCustomInstall.Location = New-Object System.Drawing.Point(220, 240)
$btnCustomInstall.Size = New-Object System.Drawing.Size(220, 30)
$tabInstall.Controls.Add($btnCustomInstall)


# --- ABA 2: DESINSTALAÇÃO ---
$tabUninstall = New-Object System.Windows.Forms.TabPage
$tabUninstall.Text = "Desinstalação"
$tabControl.Controls.Add($tabUninstall)

$uninstallCheckboxes = @()
for ($i = 0; $i -lt $AppConfig.Count; $i++) {
    $colIndex = [math]::Floor($i / $itemsPerColumn)
    $rowIndex = $i % $itemsPerColumn
    
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $AppConfig[$i].Name
    $cb.Tag = $AppConfig[$i].ID
    $cb.Location = New-Object System.Drawing.Point($colX[$colIndex], ($startY + ($rowIndex * $rowSpacing)))
    $cb.Size = New-Object System.Drawing.Size(200, 20)
    $tabUninstall.Controls.Add($cb)
    $uninstallCheckboxes += $cb
}

$btnUninstallSelected = New-Object System.Windows.Forms.Button
$btnUninstallSelected.Text = "Desinstalar Selecionados"
$btnUninstallSelected.Location = New-Object System.Drawing.Point(20, 240)
$btnUninstallSelected.Size = New-Object System.Drawing.Size(180, 30)
$tabUninstall.Controls.Add($btnUninstallSelected)

$btnListInstalled = New-Object System.Windows.Forms.Button
$btnListInstalled.Text = "Listar Todos no Sistema"
$btnListInstalled.Location = New-Object System.Drawing.Point(220, 240)
$btnListInstalled.Size = New-Object System.Drawing.Size(200, 30)
$tabUninstall.Controls.Add($btnListInstalled)


# --- ABA 3: SISTEMA & AJUSTES ---
$tabSystem = New-Object System.Windows.Forms.TabPage
$tabSystem.Text = "Sistema & Ajustes"
$tabControl.Controls.Add($tabSystem)

$btnEdgeTweak = New-Object System.Windows.Forms.Button
$btnEdgeTweak.Text = "Aplicar Google como Padrão no Microsoft Edge"
$btnEdgeTweak.Location = New-Object System.Drawing.Point(20, 20)
$btnEdgeTweak.Size = New-Object System.Drawing.Size(350, 35)
$tabSystem.Controls.Add($btnEdgeTweak)

$btnUpgradeAll = New-Object System.Windows.Forms.Button
$btnUpgradeAll.Text = "Atualizar Todos os Programas Instalados"
$btnUpgradeAll.Location = New-Object System.Drawing.Point(20, 70)
$btnUpgradeAll.Size = New-Object System.Drawing.Size(350, 35)
$tabSystem.Controls.Add($btnUpgradeAll)


# --- ABA 4: ATIVAÇÃO ---
$tabActivation = New-Object System.Windows.Forms.TabPage
$tabActivation.Text = "Ativação do Windows"
$tabControl.Controls.Add($tabActivation)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status do Windows: Verificando..."
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblStatus.Location = New-Object System.Drawing.Point(20, 25)
$lblStatus.Size = New-Object System.Drawing.Size(400, 25)
$tabActivation.Controls.Add($lblStatus)

$btnAutoActivate = New-Object System.Windows.Forms.Button
$btnAutoActivate.Text = "Ativar Windows"
$btnAutoActivate.Location = New-Object System.Drawing.Point(20, 70)
$btnAutoActivate.Size = New-Object System.Drawing.Size(200, 35)
$tabActivation.Controls.Add($btnAutoActivate)


# --- LÓGICA DE EXECUÇÃO ASSÍNCRONA ---

$form.Add_Load({
    Write-Log "Iniciando verificação operacional..."
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        # Atualiza a instalação local de arquivos e gera o atalho na área de trabalho
        Install-LocalFilesAndShortcut
        
        if (Test-Winget) {
            Write-Log "Gerenciador de pacotes Winget pronto."
        } else {
            Write-Log "Aviso: Winget ausente no sistema."
        }
        
        $status = "Não Ativado"
        $check = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
        if ($check -match "permanente|permanent|ativado|activated") {
            $status = "Ativado"
        }
        
        $form.Invoke([Action]{
            $lblStatus.Text = "Status do Windows: $status"
            Write-Log "Licenciamento verificado: $status"
        })
    }) | Out-Null
})

$btnAutoActivate.Add_Click({
    $btnAutoActivate.Enabled = $false
    Write-Log "Iniciando processo de ativação silenciosa..."
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        $check = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
        if ($check -match "permanente|permanent|ativado|activated") {
            Write-Log "O Windows já está ativado."
            $form.Invoke([Action]{ $btnAutoActivate.Enabled = $true })
            return
        }
        
        Write-Log "Aplicando chave de produto padrão..."
        $procKey = Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX" -NoNewWindow -PassThru -Wait
        
        $KMS_Servers = @("kms.loli.best", "zh.us.to", "kms.digiboy.ir", "kms.msguides.com")
        $success = $false
        
        foreach ($server in $KMS_Servers) {
            Write-Log "Tentando conexão com o servidor KMS: $server..."
            
            $pSkms = Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /skms $server" -NoNewWindow -PassThru -Wait
            $pAto = Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ato" -NoNewWindow -PassThru -Wait
            
            $checkStatus = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
            if ($checkStatus -match "permanente|permanent|ativado|activated") {
                $success = $true
                Write-Log "Ativação concluída com sucesso através de: $server"
                break
            }
        }
        
        if (-not $success) {
            Write-Log "Falha na ativação com os servidores disponíveis."
        }
        
        $form.Invoke([Action]{
            $lblStatus.Text = "Status do Windows: " + (if ($success) { "Ativado" } else { "Não Ativado" })
            $btnAutoActivate.Enabled = $true
        })
    }) | Out-Null
})

$btnInstallSelected.Add_Click({
    $selected = $installCheckboxes | Where-Object { $_.Checked -eq $true }
    if ($selected.Count -eq 0) {
        Write-Log "Selecione ao menos um programa."
        return
    }
    
    $btnInstallSelected.Enabled = $false
    Write-Log "Instalações iniciadas em segundo plano..."
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        foreach ($cb in $selected) {
            $name = $cb.Text
            $id = $cb.Tag
            Write-Log "Instalando: $name..."
            
            $proc = Start-Process winget -ArgumentList "install --id $id --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -Wait
            
            if ($proc.ExitCode -eq 0) {
                Write-Log "Concluído: $name foi instalado."
            } else {
                Write-Log "Não foi possível concluir a instalação de: $name."
            }
        }
        Write-Log "Processos de instalação finalizados."
        $form.Invoke([Action]{ $btnInstallSelected.Enabled = $true })
    }) | Out-Null
})

$btnUninstallSelected.Add_Click({
    $selected = $uninstallCheckboxes | Where-Object { $_.Checked -eq $true }
    if ($selected.Count -eq 0) {
        Write-Log "Selecione ao menos um programa."
        return
    }
    
    $btnUninstallSelected.Enabled = $false
    Write-Log "Desinstalações iniciadas em segundo plano..."
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        foreach ($cb in $selected) {
            $name = $cb.Text
            $id = $cb.Tag
            Write-Log "Removendo: $name..."
            
            $proc = Start-Process winget -ArgumentList "uninstall --id $id --silent" -NoNewWindow -PassThru -Wait
            
            if ($proc.ExitCode -eq 0) {
                Write-Log "Concluído: $name foi removido."
            } else {
                Write-Log "Não foi possível remover: $name."
            }
        }
        Write-Log "Processos de remoção finalizados."
        $form.Invoke([Action]{ $btnUninstallSelected.Enabled = $true })
    }) | Out-Null
})

$btnUpgradeAll.Add_Click({
    $btnUpgradeAll.Enabled = $false
    Write-Log "Iniciando atualização de softwares instalados..."
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        $proc = Start-Process winget -ArgumentList "upgrade --all --silent" -NoNewWindow -PassThru -Wait
        Write-Log "Processo de atualizações globais finalizado."
        $form.Invoke([Action]{ $btnUpgradeAll.Enabled = $true })
    }) | Out-Null
})

$btnListInstalled.Add_Click({
    Write-Log "Consultando softwares locais..."
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        $list = winget list
        foreach ($line in $list) {
            Write-Log $line
        }
        Write-Log "Fim da lista de softwares locais."
    }) | Out-Null
})

$btnEdgeTweak.Add_Click({
    Write-Log "Iniciando aplicação de diretivas no Edge..."
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        $res = Set-EdgeGoogleDefault
        if ($res) {
            Write-Log "O Google foi configurado com sucesso como padrão no Edge."
        } else {
            Write-Log "Erro ao tentar salvar as chaves no registro."
        }
    }) | Out-Null
})

$btnCustomInstall.Add_Click({
    $inputBox = New-Object System.Windows.Forms.Form
    $inputBox.Text = "Pesquisa Customizada"
    $inputBox.Size = New-Object System.Drawing.Size(400, 150)
    $inputBox.StartPosition = "CenterParent"
    $inputBox.FormBorderStyle = "FixedDialog"
    $inputBox.MaximizeBox = $false
    
    $lblPrompt = New-Object System.Windows.Forms.Label
    $lblPrompt.Text = "Digite o nome do programa a ser pesquisado:"
    $lblPrompt.Location = New-Object System.Drawing.Point(20, 15)
    $lblPrompt.Size = New-Object System.Drawing.Size(350, 20)
    $inputBox.Controls.Add($lblPrompt)
    
    $txtInput = New-Object System.Windows.Forms.TextBox
    $txtInput.Location = New-Object System.Drawing.Point(20, 40)
    $txtInput.Size = New-Object System.Drawing.Size(340, 20)
    $inputBox.Controls.Add($txtInput)
    
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Pesquisar"
    $btnOk.Location = New-Object System.Drawing.Point(20, 75)
    $btnOk.Size = New-Object System.Drawing.Size(100, 25)
    $inputBox.Controls.Add($btnOk)
    
    $btnOk.Add_Click({
        $progName = $txtInput.Text
        if (-not [string]::IsNullOrEmpty($progName)) {
            Write-Log "Buscando por: '$progName' no catálogo..."
            [System.Threading.ThreadPool]::QueueUserWorkItem({
                $results = winget search --name $progName
                foreach ($line in $results) {
                    Write-Log $line
                }
            }) | Out-Null
            $inputBox.Close()
        }
    })
    $inputBox.ShowDialog() | Out-Null
})

# Executa o formulário
[System.Windows.Forms.Application]::Run($form)
