# Oculta o console do PowerShell imediatamente para não atrapalhar o usuário
$showWindowAsync = Add-Type -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@ -Name "Win32ShowWindowAsync" -Namespace "Win32" -PassThru

$hwnd = (Get-Process -Id $PID).MainWindowHandle
if ($hwnd -ne [IntPtr]::Zero) {
    # nCmdShow = 0 (Oculta a janela)
    $showWindowAsync::ShowWindowAsync($hwnd, 0) | Out-Null
}

# Garante privilégios de Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Carrega as bibliotecas gráficas do .NET
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- DIRETÓRIO LOCAL E INSTALAÇÃO DO ATALHO ---
$InstallDir = Join-Path $env:LOCALAPPDATA "FYXX"
$JsonPath = Join-Path $InstallDir "apps.json"
$LocalScriptPath = Join-Path $InstallDir "main.ps1"
$ShortcutPath = "$env:USERPROFILE\Desktop\FYXX Utility.lnk"

# Garante a criação da pasta local
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# --- FUNÇÕES AUXILIARES ---

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

# Método para instalar arquivos locais e criar o atalho de forma silenciosa
function Install-LocalFilesAndShortcut {
    try {
        # Baixa os arquivos atualizados do GitHub para a pasta persistente local
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/main.ps1" -OutFile $LocalScriptPath
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/apps.json" -OutFile $JsonPath
        
        # Cria o atalho (.lnk) na Área de Trabalho se ele não existir
        if (-not (Test-Path $ShortcutPath)) {
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
            $Shortcut.TargetPath = "powershell.exe"
            # O atalho executa com a tela totalmente oculta (-WindowStyle Hidden)
            $Shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LocalScriptPath`""
            $Shortcut.IconLocation = "powershell.exe"
            $Shortcut.WorkingDirectory = $InstallDir
            $Shortcut.Save()
            Write-Log "Atalho 'FYXX Utility' criado na Área de Trabalho."
        }
    }
    catch {
        Write-Log "Aviso: Falha ao atualizar ou criar o atalho local."
    }
}

# --- CARREGA O ARQUIVO JSON LOCAL ---
# Se o arquivo não existir localmente por algum problema de conexão, ele baixa diretamente do seu GitHub temporariamente
if (-not (Test-Path $JsonPath)) {
    try {
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/apps.json" -OutFile $JsonPath
    }
    catch {
        # Fallback de segurança se estiver offline na primeira execução
        New-Item -ItemType File -Path $JsonPath -Force | Out-Null
    }
}

$AppConfig = Get-Content $JsonPath -Raw | ConvertFrom-Json

# --- CONSTRUÇÃO DA INTERFACE GRÁFICA (GUI) ---

$form = New-Object System.Windows.Forms.Form
$form.Text = "Gerenciador de Programas & Sistema - By OGERRVA"
$form.Size = New-Object System.Drawing.Size(750, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

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

function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $text = "[$timestamp] $Message`r`n"
    if ($form.InvokeRequired) {
        $form.Invoke([Action[string]]{ $logTextBox.AppendText($args[0]) }, $text)
    } else {
        $logTextBox.AppendText($text)
    }
}

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 80)
$tabControl.Size = New-Object System.Drawing.Size(690, 320)
$form.Controls.Add($tabControl)

# --- ABA 1: INSTALAÇÃO ---
$tabInstall = New-Object System.Windows.Forms.TabPage
$tabInstall.Text = "Instalação"
$tabControl.Controls.Add($tabInstall)

$installCheckboxes = @()
$colX = @(20, 240, 460)
$startY = 20
$rowSpacing = 30

for ($i = 0; $i -lt $AppConfig.install.Count; $i++) {
    $colIndex = [math]::Floor($i / 5)
    $rowIndex = $i % 5
    
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $AppConfig.install[$i].Name
    $cb.Tag = $AppConfig.install[$i].ID
    $cb.Location = New-Object System.Drawing.Point($colX[$colIndex], ($startY + ($rowIndex * $rowSpacing)))
    $cb.Size = New-Object System.Drawing.Size(200, 20)
    $tabInstall.Controls.Add($cb)
    $installCheckboxes += $cb
}

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

$uninstallCheckboxes = @()
for ($i = 0; $i -lt $AppConfig.uninstall.Count; $i++) {
    $colIndex = [math]::Floor($i / 5)
    $rowIndex = $i % 5
    
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $AppConfig.uninstall[$i].Name
    $cb.Tag = $AppConfig.uninstall[$i].ID
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


# --- LÓGICA DE EXECUÇÃO MULTIPROCESSO ---

$form.Add_Load({
    Write-Log "Iniciando verificação do sistema..."
    
    # Executa a cópia de arquivos e criação do atalho local em segundo plano
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        Install-LocalFilesAndShortcut
        
        # Validação do Winget
        if (Test-Winget) {
            Write-Log "Gerenciador de pacotes Winget pronto para uso."
        } else {
            Write-Log "Aviso: Winget não detectado. Algumas funções podem necessitar de instalação prévia."
        }
        
        # Consulta de ativação do Windows
        $status = "Não Ativado"
        $check = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
        if ($check -match "permanente|permanent|ativado|activated") {
            $status = "Ativado"
        }
        
        $form.Invoke([Action]{
            $lblStatus.Text = "Status do Windows: $status"
            Write-Log "Licença do sistema operacional detectada como: $status"
        })
    }) | Out-Null
})

# Lógica de ativação silenciosa e não bloqueante do seu BAT
$btnAutoActivate.Add_Click({
    $btnAutoActivate.Enabled = $false
    Write-Log "Iniciando processo de ativação silenciosa..."
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        $check = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
        if ($check -match "permanente|permanent|ativado|activated") {
            Write-Log "O Windows já está devidamente ativado."
            $form.Invoke([Action]{ $btnAutoActivate.Enabled = $true })
            return
        }
        
        Write-Log "Aplicando chave de produto padrão..."
        $procKey = Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX" -NoNewWindow -PassThru -Wait
        
        $KMS_Servers = @("kms.loli.best", "zh.us.to", "kms.digiboy.ir", "kms.msguides.com")
        $success = $false
        
        foreach ($server in $KMS_Servers) {
            Write-Log "Tentando conexão com o servidor KMS: $server..."
            
            # Executa os comandos do slmgr silenciosamente
            $pSkms = Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /skms $server" -NoNewWindow -PassThru -Wait
            $pAto = Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ato" -NoNewWindow -PassThru -Wait
            
            # Valida se obteve sucesso
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

# Instalação Lote (Assíncrona)
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
        Write-Log "Processos finalizados."
        $form.Invoke([Action]{ $btnInstallSelected.Enabled = $true })
    }) | Out-Null
})

# Desinstalação Lote (Assíncrona)
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

# Atualização em Lote (Assíncrona)
$btnUpgradeAll.Add_Click({
    $btnUpgradeAll.Enabled = $false
    Write-Lo
