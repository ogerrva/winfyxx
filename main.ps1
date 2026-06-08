# Garante que o script seja executado como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Este utilitário precisa ser executado como Administrador." -ForegroundColor Red
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Carrega as bibliotecas de GUI do .NET
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- FUNÇÕES DE SUPORTE ---

# 1. Verificar e instalar o Winget se necessário
function Test-Winget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $false
    }
    return $true
}

# 2. Verificar Status de Ativação do Windows de forma silenciosa
function Get-WindowsActivationStatus {
    try {
        # Consulta o licenciamento do Windows via WMI
        $service = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' and LicenseStatus=1"
        if ($service) {
            return "Ativado"
        } else {
            return "Não Ativado"
        }
    }
    catch {
        return "Erro ao verificar"
    }
}

# 3. Aplicar Google como padrão no Microsoft Edge
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

# --- CONSTRUÇÃO DA INTERFACE GRÁFICA (GUI) ---

# Janela Principal
$form = New-Object System.Windows.Forms.Form
$form.Text = "FYXX Utility - Protótipo"
$form.Size = New-Object System.Drawing.Size(600, 450)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Título Principal
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "FYXX Utility"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$titleLabel.Size = New-Object System.Drawing.Size(200, 35)
$form.Controls.Add($titleLabel)

# Status de Ativação
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Status do Windows: Verificando..."
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$statusLabel.Location = New-Object System.Drawing.Point(20, 50)
$statusLabel.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($statusLabel)

# Painel de Log
$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Multiline = $true
$logTextBox.ScrollBars = "Vertical"
$logTextBox.ReadOnly = $true
$logTextBox.Location = New-Object System.Drawing.Point(20, 280)
$logTextBox.Size = New-Object System.Drawing.Size(540, 110)
$logTextBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$logTextBox.BackColor = [System.Drawing.Color]::Black
$logTextBox.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($logTextBox)

function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logTextBox.AppendText("[$timestamp] $Message`r`n")
}

# TabControl (Abas do Utilitário)
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 80)
$tabControl.Size = New-Object System.Drawing.Size(540, 180)
$form.Controls.Add($tabControl)

# Aba 1: Aplicativos
$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = "Instalação de Programas"
$tabControl.Controls.Add($tabApps)

# Lista de Programas (Checkboxes na Aba Aplicativos)
$appsList = @(
    @{ Name = "Discord"; ID = "Discord.Discord"; Checked = $false },
    @{ Name = "VSCode"; ID = "Microsoft.VisualStudioCode"; Checked = $false },
    @{ Name = "Chrome"; ID = "Google.Chrome"; Checked = $false },
    @{ Name = "Firefox"; ID = "Mozilla.Firefox"; Checked = $false },
    @{ Name = "WinRAR"; ID = "RARLab.WinRAR"; Checked = $false }
)

$checkboxes = @()
$yPos = 15
foreach ($app in $appsList) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $app.Name
    $cb.Tag = $app.ID
    $cb.Location = New-Object System.Drawing.Point(20, $yPos)
    $cb.Size = New-Object System.Drawing.Size(120, 20)
    $tabApps.Controls.Add($cb)
    $checkboxes += $cb
    $yPos += 25
}

# Botão para Instalar Selecionados
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Instalar Selecionados"
$btnInstall.Location = New-Object System.Drawing.Point(200, 120)
$btnInstall.Size = New-Object System.Drawing.Size(150, 25)
$tabApps.Controls.Add($btnInstall)

# Aba 2: Otimizações e Correções
$tabTweaks = New-Object System.Windows.Forms.TabPage
$tabTweaks.Text = "Otimizações"
$tabControl.Controls.Add($tabTweaks)

# Botão para Aplicar Tweak do Edge
$btnEdgeTweak = New-Object System.Windows.Forms.Button
$btnEdgeTweak.Text = "Definir Google como Padrão no Edge"
$btnEdgeTweak.Location = New-Object System.Drawing.Point(20, 20)
$btnEdgeTweak.Size = New-Object System.Drawing.Size(250, 30)
$tabTweaks.Controls.Add($btnEdgeTweak)

# Botão de Upgrade do Sistema (Winget Upgrade All)
$btnUpgradeAll = New-Object System.Windows.Forms.Button
$btnUpgradeAll.Text = "Atualizar Todos os Programas (Winget)"
$btnUpgradeAll.Location = New-Object System.Drawing.Point(20, 60)
$btnUpgradeAll.Size = New-Object System.Drawing.Size(250, 30)
$tabTweaks.Controls.Add($btnUpgradeAll)

# --- AÇÕES DA INTERFACE ---

# Carregamento inicial do Form
$form.Add_Load({
    Write-Log "Iniciando verificação do sistema..."
    
    # Verifica Winget
    if (Test-Winget) {
        Write-Log "Gerenciador de pacotes Winget detectado."
    } else {
        Write-Log "Aviso: Winget não encontrado no sistema."
    }

    # Verifica ativação do Windows
    $activation = Get-WindowsActivationStatus
    $statusLabel.Text = "Status do Windows: $activation"
    Write-Log "Estado de ativação verificado: $activation."
})

# Ação de Instalação de Programas
$btnInstall.Add_Click({
    $selectedApps = $checkboxes | Where-Object { $_.Checked -eq $true }
    if ($selectedApps.Count -eq 0) {
        Write-Log "Nenhum programa selecionado para instalação."
        return
    }

    if (-not (Test-Winget)) {
        Write-Log "Erro: Não é possível instalar programas porque o Winget não está disponível."
        return
    }

    # Desabilita o botão temporariamente
    $btnInstall.Enabled = $false
    
    foreach ($cb in $selectedApps) {
        $appName = $cb.Text
        $appID = $cb.Tag
        Write-Log "Iniciando a instalação de: $appName ($appID)..."
        
        # Executa a instalação em segundo plano
        Start-Process winget -ArgumentList "install --id $appID --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait
        
        Write-Log "Processo de instalação concluído para: $appName"
    }
    
    $btnInstall.Enabled = $true
})

# Ação do Tweak do Edge
$btnEdgeTweak.Add_Click({
    Write-Log "Aplicando políticas para definir o Google como padrão no Edge..."
    $result = Set-EdgeGoogleDefault
    if ($result) {
        Write-Log "Políticas do Edge aplicadas com sucesso. O Google agora é o mecanismo padrão."
    } else {
        Write-Log "Falha ao gravar no registro do sistema. Verifique os privilégios de administrador."
    }
})

# Ação de Upgrade de Programas
$btnUpgradeAll.Add_Click({
    if (-not (Test-Winget)) {
        Write-Log "Erro: Winget indisponível."
        return
    }
    $btnUpgradeAll.Enabled = $false
    Write-Log "Iniciando atualização em lote dos softwares..."
    Start-Process winget -ArgumentList "upgrade --all --silent" -NoNewWindow -Wait
    Write-Log "Verificação de atualizações finalizada."
    $btnUpgradeAll.Enabled = $true
})

# Executa o Form
[System.Windows.Forms.Application]::Run($form)
