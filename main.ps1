# Garante privilégios de Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Este utilitário precisa ser executado como Administrador." -ForegroundColor Red
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Carrega as bibliotecas de interface gráfica do .NET
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- FUNÇÕES DE SISTEMA ---

# Verifica se o Winget está disponível
function Test-Winget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    return $true
}

# Executa a instalação do Winget caso não esteja presente
function Install-Winget {
    Write-Log "Instalando o Winget..."
    try {
        Start-Process "https://aka.ms/getwinget" -Wait
        Start-Process winget -ArgumentList "install --id Microsoft.Winget.Source" -NoNewWindow -Wait
        return $true
    }
    catch {
        return $false
    }
}

# Verifica o estado real de ativação do Windows
function Get-WindowsActivationStatus {
    try {
        $service = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' and LicenseStatus=1"
        if ($service) { return "Ativado" } else { return "Não Ativado" }
    }
    catch {
        return "Erro ao ler status"
    }
}

# Tweak para definir o Google como padrão no Microsoft Edge
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

# --- ESTRUTURA DA INTERFACE GRÁFICA (GUI) ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "Gerenciador de Programas & Sistema - By OGERRVA"
$form.Size = New-Object System.Drawing.Size(750, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Título do Programa
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Gerenciador de Programas"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.Size = New-Object System.Drawing.Size(350, 35)
$form.Controls.Add($titleLabel)

# Créditos do Autor
$authorLabel = New-Object System.Windows.Forms.Label
$authorLabel.Text = "======= By OGERRVA ======="
$authorLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$authorLabel.Location = New-Object System.Drawing.Point(20, 50)
$authorLabel.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($authorLabel)

# Console de Logs (Saída de texto em tempo real)
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

function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logTextBox.AppendText("[$timestamp] $Message`r`n")
}

# Abas Principais
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 80)
$tabControl.Size = New-Object System.Drawing.Size(690, 320)
$form.Controls.Add($tabControl)

# --- ABA 1: INSTALAÇÃO ---
$tabInstall = New-Object System.Windows.Forms.TabPage
$tabInstall.Text = "Instalação"
$tabControl.Controls.Add($tabInstall)

# Listagem exata dos 15 programas para instalação
$installAppsList = @(
    @{ Name = "Discord"; ID = "Discord.Discord" },
    @{ Name = "Epic Games"; ID = "EpicGames.EpicGamesLauncher" },
    @{ Name = "WinRAR"; ID = "RARLab.WinRAR" },
    @{ Name = "EA Play"; ID = "ElectronicArts.EADesktop" },
    @{ Name = "Ubisoft Connect"; ID = "Ubisoft.Connect" },
    @{ Name = "Terminus SSH"; ID = "Termius.Termius" },
    @{ Name = "Telegram"; ID = "Telegram.TelegramDesktop" },
    @{ Name = "VSCode"; ID = "Microsoft.VisualStudioCode" },
    @{ Name = "VLC"; ID = "VideoLAN.VLC" },
    @{ Name = "CPU-Z"; ID = "CPUID.CPU-Z" },
    @{ Name = "Chrome"; ID = "Google.Chrome" },
    @{ Name = "Firefox"; ID = "Mozilla.Firefox" },
    @{ Name = "Edge"; ID = "Microsoft.Edge" },
    @{ Name = "Opera"; ID = "Opera.Opera" },
    @{ Name = "GeForce Experience"; ID = "Nvidia.GeForceExperience" }
)

# Renderiza os Checkboxes em 3 colunas
$installCheckboxes = @()
$colX = @(20, 240, 460)
$startY = 20
$rowSpacing = 30

for ($i = 0; $i -lt $installAppsList.Count; $i++) {
    $colIndex = [math]::Floor($i / 5)
    $rowIndex = $i % 5
    
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $installAppsList[$i].Name
    $cb.Tag = $installAppsList[$i].ID
    $cb.Location = New-Object System.Drawing.Point($colX[$colIndex], ($startY + ($rowIndex * $rowSpacing)))
    $cb.Size = New-Object System.Drawing.Size(200, 20)
    $tabInstall.Controls.Add($cb)
    $installCheckboxes += $cb
}

# Botões da aba de instalação
$btnInstallSelected = New-Object System.Windows.Forms.Button
$btnInstallSelected.Text = "Instalar Selecionados"
$btnInstallSelected.Location = New-Object System.Drawing.Point(20, 200)
$btnInstallSelected.Size = New-Object System.Drawing.Size(180, 30)
$tabInstall.Controls.Add($btnInstallSelected)

$btnCustomInstall = New-Object System.Windows.Forms.Button
$btnCustomInstall.Text = "Pesquisa e Instal. Personalizada"
$btnCustomInstall.Location = New-Object System.Drawing.Point(220, 200)
$btnCustomInstall.Size = New-Object System.Drawing.Size(220, 30)
$tabInstall.Controls.Add($btnCustomInstall)


# --- ABA 2: DESINSTALAÇÃO ---
$tabUninstall = New-Object System.Windows.Forms.TabPage
$tabUninstall.Text = "Desinstalação"
$tabControl.Controls.Add($tabUninstall)

# Listagem exata dos 15 programas para desinstalação
$uninstallAppsList = @(
    @{ Name = "Discord"; ID = "Discord.Discord" },
    @{ Name = "Epic Games"; ID = "EpicGames.EpicGamesLauncher" },
    @{ Name = "WinRAR"; ID = "RARLab.WinRAR" },
    @{ Name = "EA Play"; ID = "ElectronicArts.EADesktop" },
    @{ Name = "Ubisoft Connect"; ID = "Ubisoft.Connect" },
    @{ Name = "FileZilla"; ID = "FileZilla.FileZillaClient" },
    @{ Name = "Telegram"; ID = "Telegram.TelegramDesktop" },
    @{ Name = "VSCode"; ID = "Microsoft.VisualStudioCode" },
    @{ Name = "VLC"; ID = "VideoLAN.VLC" },
    @{ Name = "CPU-Z"; ID = "CPUID.CPU-Z" },
    @{ Name = "Chrome"; ID = "Google.Chrome" },
    @{ Name = "Firefox"; ID = "Mozilla.Firefox" },
    @{ Name = "Edge"; ID = "Microsoft.Edge" },
    @{ Name = "Opera"; ID = "Opera.Opera" },
    @{ Name = "Brave"; ID = "BraveSoftware.BraveBrowser" }
)

# Renderiza Checkboxes de desinstalação em 3 colunas
$uninstallCheckboxes = @()
for ($i = 0; $i -lt $uninstallAppsList.Count; $i++) {
    $colIndex = [math]::Floor($i / 5)
    $rowIndex = $i % 5
    
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $uninstallAppsList[$i].Name
    $cb.Tag = $uninstallAppsList[$i].ID
    $cb.Location = New-Object System.Drawing.Point($colX[$colIndex], ($startY + ($rowIndex * $rowSpacing)))
    $cb.Size = New-Object System.Drawing.Size(200, 20)
    $tabUninstall.Controls.Add($cb)
    $uninstallCheckboxes += $cb
}

$btnUninstallSelected = New-Object System.Windows.Forms.Button
$btnUninstallSelected.Text = "Desinstalar Selecionados"
$btnUninstallSelected.Location = New-Object System.Drawing.Point(20, 200)
$btnUninstallSelected.Size = New-Object System.Drawing.Size(180, 30)
$tabUninstall.Controls.Add($btnUninstallSelected)

$btnListInstalled = New-Object System.Windows.Forms.Button
$btnListInstalled.Text = "Listar Todos no Sistema"
$btnListInstalled.Location = New-Object System.Drawing.Point(220, 200)
$btnListInstalled.Size = New-Object System.Drawing.Size(200, 30)
$tabUninstall.Controls.Add($btnListInstalled)


# --- ABA 3: SISTEMA & AJUSTES ---
$tabSystem = New-Object System.Windows.Forms.TabPage
$tabSystem.Text = "Sistema & Ajustes"
$tabControl.Controls.Add($tabSystem)

# Tweak do Edge
$btnEdgeTweak = New-Object System.Windows.Forms.Button
$btnEdgeTweak.Text = "Aplicar Google como Padrão no Microsoft Edge"
$btnEdgeTweak.Location = New-Object System.Drawing.Point(20, 20)
$btnEdgeTweak.Size = New-Object System.Drawing.Size(350, 35)
$tabSystem.Controls.Add($btnEdgeTweak)

# Atualizar todos os programas do sistema via Winget
$btnUpgradeAll = New-Object System.Windows.Forms.Button
$btnUpgradeAll.Text = "Atualizar Todos os Programas Instalados"
$btnUpgradeAll.Location = New-Object System.Drawing.Point(20, 70)
$btnUpgradeAll.Size = New-Object System.Drawing.Size(350, 35)
$tabSystem.Controls.Add($btnUpgradeAll)


# --- ABA 4: ATIVAÇÃO ---
$tabActivation = New-Object System.Windows.Forms.TabPage
$tabActivation.Text = "Ativação"
$tabControl.Controls.Add($tabActivation)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Verificando estado atual..."
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblStatus.Location = New-Object System.Drawing.Point(20, 20)
$lblStatus.Size = New-Object System.Drawing.Size(400, 25)
$tabActivation.Controls.Add($lblStatus)

$lblKeyInfo = New-Object System.Windows.Forms.Label
$lblKeyInfo.Text = "Insira a chave do produto (Product Key) de 25 caracteres abaixo:"
$lblKeyInfo.Location = New-Object System.Drawing.Point(20, 60)
$lblKeyInfo.Size = New-Object System.Drawing.Size(450, 20)
$tabActivation.Controls.Add($lblKeyInfo)

# Entrada de texto para a chave de licença oficial
$txtProductKey = New-Object System.Windows.Forms.TextBox
$txtProductKey.Location = New-Object System.Drawing.Point(20, 85)
$txtProductKey.Size = New-Object System.Drawing.Size(350, 25)
$tabActivation.Controls.Add($txtProductKey)

$btnActivateWin = New-Object System.Windows.Forms.Button
$btnActivateWin.Text = "Registrar Chave e Ativar Windows"
$btnActivateWin.Location = New-Object System.Drawing.Point(20, 125)
$btnActivateWin.Size = New-Object System.Drawing.Size(250, 30)
$tabActivation.Controls.Add($btnActivateWin)


# --- EVENTOS E LOGICAs DE EXECUÇÃO ---

# Ao carregar a tela
$form.Add_Load({
    Write-Log "Iniciando verificação operacional..."
    if (-not (Test-Winget)) {
        Write-Log "Aviso: Winget não detectado no sistema."
        $res = [System.Windows.Forms.MessageBox]::Show("O gerenciador de pacotes Winget não está instalado. Deseja instalá-lo agora?", "Winget não encontrado", [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
            $success = Install-Winget
            if ($success) { Write-Log "Winget instalado com sucesso." } else { Write-Log "Falha na instalação automática do Winget." }
        }
    } else {
        Write-Log "Winget validado e operacional."
    }

    # Atualiza o status do Windows de maneira silenciosa
    $actStatus = Get-WindowsActivationStatus
    $lblStatus.Text = "Status do Windows: $actStatus"
    Write-Log "Licenciamento do sistema operacional detectado como: $actStatus"
})

# Ação de Instalação Selecionada
$btnInstallSelected.Add_Click({
    $selected = $installCheckboxes | Where-Object { $_.Checked -eq $true }
    if ($selected.Count -eq 0) {
        Write-Log "Nenhum programa foi selecionado."
        return
    }
    
    $btnInstallSelected.Enabled = $false
    foreach ($cb in $selected) {
        $name = $cb.Text
        $id = $cb.Tag
        Write-Log "Baixando e instalando: $name..."
        Start-Process winget -ArgumentList "install --id $id --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait
        Write-Log "Instalação concluída: $name"
    }
    $btnInstallSelected.Enabled = $true
})

# Pesquisa e Instalação Personalizada (Caixa de Entrada interativa)
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
            Write-Log "Pesquisando por: '$progName' no Winget..."
            # Executa a pesquisa e redireciona os resultados para o console de log
            $results = winget search --name $progName
            foreach ($line in $results) {
                Write-Log $line
            }
            $inputBox.Close()
        }
    })
    
    $inputBox.ShowDialog() | Out-Null
})

# Ação de Desinstalação Selecionada
$btnUninstallSelected.Add_Click({
    $selected = $uninstallCheckboxes | Where-Object { $_.Checked -eq $true }
    if ($selected.Count -eq 0) {
        Write-Log "Nenhum programa foi marcado para desinstalação."
        return
    }
    
    $btnUninstallSelected.Enabled = $false
    foreach ($cb in $selected) {
        $name = $cb.Text
        $id = $cb.Tag
        Write-Log "Removendo aplicativo: $name..."
        Start-Process winget -ArgumentList "uninstall --id $id --silent" -NoNewWindow -Wait
        Write-Log "Desinstalação concluída: $name"
    }
    $btnUninstallSelected.Enabled = $true
})

# Listar Todos os Programas Instalados no Sistema
$btnListInstalled.Add_Click({
    Write-Log "Coletando lista de softwares instalados..."
    $rawList = winget list
    foreach ($line in $rawList) {
        Write-Log $line
    }
    Write-Log "Varredura de programas locais finalizada."
})

# Evento Tweak do Edge
$btnEdgeTweak.Add_Click({
    Write-Log "Modificando diretivas do Microsoft Edge no Registro..."
    $res = Set-EdgeGoogleDefault
    if ($res) {
        Write-Log "Sucesso: O mecanismo padrão do Edge foi definido para o Google."
    } else {
        Write-Log "Erro: Falha ao aplicar as políticas do Edge."
    }
})

# Evento Atualizar Tudo
$btnUpgradeAll.Add_Click({
    $btnUpgradeAll.Enabled = $false
    Write-Log "Buscando atualizações de pacotes ativos..."
    Start-Process winget -ArgumentList "upgrade --all --silent" -NoNewWindow -Wait
    Write-Log "Processamento de atualizações globais finalizado."
    $btnUpgradeAll.Enabled = $true
})

# Evento para registro de chave e ativação licenciada do Windows
$btnActivateWin.Add_Click({
    $key = $txtProductKey.Text.Trim()
    if ($key.Length -ne 29) {
        Write-Log "Aviso: O formato da chave inserida parece inválido (deve conter 25 caracteres alfanuméricos mais traços)."
        return
    }
    
    $btnActivateWin.Enabled = $false
    Write-Log "Instalando chave de produto inserida..."
    
    # Aplica a licença via script padrão do Windows
    Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ipk $key" -NoNewWindow -Wait
    
    Write-Log "Tentando registrar licença junto aos servidores oficiais da Microsoft..."
    Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ato" -NoNewWindow -Wait
    
    # Reavalia o status atualizado
    $actStatus = Get-WindowsActivationStatus
    $lblStatus.Text = "Status do Windows: $actStatus"
    Write-Log "Processo concluído. Novo estado: $actStatus"
    $btnActivateWin.Enabled = $true
})

# Executa a Janela
[System.Windows.Forms.Application]::Run($form)
