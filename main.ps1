# --- 1. VERIFICAÇÃO DE ADMINISTRADOR ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "O programa precisa de permissao de Administrador. Reiniciando..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm 'win.fyxx.com.br?t=$(Get-Date -Format yyyyMMddHHmmss)' | iex`"" -Verb RunAs
    }
    Exit
}

# --- 2. CARREGAMENTO DE BIBLIOTECAS GRÁFICAS ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- 3. DEFINIÇÃO DE DIRETÓRIOS ---
$InstallDir = Join-Path $env:LOCALAPPDATA "FYXX"
$JsonPath = Join-Path $InstallDir "apps.json"
$LocalScriptPath = Join-Path $InstallDir "main.ps1"
$ShortcutPath = "$env:USERPROFILE\Desktop\FYXX Utility.lnk"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# --- 4. FUNÇÃO DE LOG (Escreve no Terminal e na Interface) ---
$logTextBox = $null

function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $text = "[$timestamp] $Message`r`n"
    
    # Imprime no terminal obrigatoriamente
    Write-Host "[$timestamp] $Message" -ForegroundColor Cyan

    if ($null -ne $logTextBox) {
        if ($form.InvokeRequired) {
            $form.Invoke([System.Action[string]]{
                param($str)
                $logTextBox.AppendText($str)
            }, $text)
        } else {
            $logTextBox.AppendText($text)
        }
    }
}

# --- 5. FUNÇÕES AUXILIARES ---
function Test-Winget {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Set-EdgeGoogleDefault {
    $EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    try {
        if (-not (Test-Path $EdgePath)) { New-Item -Path $EdgePath -Force | Out-Null }
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
        Write-Log "Erro Edge Tweak: $_"
        return $false
    }
}

function Install-LocalFilesAndShortcut {
    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/main.ps1?t=$timestamp" -OutFile $LocalScriptPath -ErrorAction Stop
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/apps.json?t=$timestamp" -OutFile $JsonPath -ErrorAction Stop
        
        if (-not (Test-Path $ShortcutPath)) {
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
            $Shortcut.TargetPath = "powershell.exe"
            # ATALHO AGORA MANTÉM O TERMINAL ABERTO! (Sem -WindowStyle Hidden)
            $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$LocalScriptPath`""
            $Shortcut.IconLocation = "powershell.exe"
            $Shortcut.WorkingDirectory = $InstallDir
            $Shortcut.Save()
            Write-Log "Atalho de Área de Trabalho gerado."
        }
    }
    catch {
        Write-Log "Aviso: Nao foi possivel baixar os arquivos do GitHub."
    }
}

# --- 6. CARREGA O JSON ---
$AppConfig = $null
try {
    if (-not (Test-Path $JsonPath)) {
        Invoke-RestMethod "https://raw.githubusercontent.com/ogerrva/winfyxx/main/apps.json?t=$(Get-Date -Format yyyyMMddHHmmss)" -OutFile $JsonPath -ErrorAction Stop
    }
    $AppConfig = Get-Content $JsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Log "Usando lista padrao da memoria..."
    $DefaultApps = '[{"Name":"Discord","ID":"Discord.Discord"},{"Name":"Epic Games","ID":"EpicGames.EpicGamesLauncher"},{"Name":"WinRAR","ID":"RARLab.WinRAR"},{"Name":"EA Play","ID":"ElectronicArts.EADesktop"},{"Name":"Ubisoft Connect","ID":"Ubisoft.Connect"},{"Name":"Terminus SSH","ID":"Termius.Termius"},{"Name":"FileZilla","ID":"FileZilla.FileZillaClient"},{"Name":"Brave Browser","ID":"BraveSoftware.BraveBrowser"},{"Name":"Telegram","ID":"Telegram.TelegramDesktop"},{"Name":"VSCode","ID":"Microsoft.VisualStudioCode"},{"Name":"VLC","ID":"VideoLAN.VLC"},{"Name":"CPU-Z","ID":"CPUID.CPU-Z"},{"Name":"Chrome","ID":"Google.Chrome"},{"Name":"Firefox","ID":"Mozilla.Firefox"},{"Name":"Edge","ID":"Microsoft.Edge"},{"Name":"Opera","ID":"Opera.Opera"},{"Name":"GeForce Experience","ID":"Nvidia.GeForceExperience"}]'
    $AppConfig = $DefaultApps | ConvertFrom-Json
}

# --- 7. CONSTRUÇÃO DA INTERFACE (GUI) ---
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

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 80)
$tabControl.Size = New-Object System.Drawing.Size(690, 320)
$form.Controls.Add($tabControl)

$colX = @(20, 240, 460)
$startY = 20
$rowSpacing = 28
$itemsPerColumn = [math]::Ceiling($AppConfig.Count / 3)
if ($itemsPerColumn -lt 1) { $itemsPerColumn = 1 }

# ABA 1: INSTALAÇÃO
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

# ABA 2: DESINSTALAÇÃO
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

# ABA 3: SISTEMA
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

# ABA 4: ATIVAÇÃO
$tabActivation = New-Object System.Windows.Forms.TabPage
$tabActivation.Text = "Licenciamento"
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
$btnAutoActivate.Size = New-Object System.Drawing.Size(250, 35)
$tabActivation.Controls.Add($btnAutoActivate)

# --- 8. LÓGICA E EVENTOS ---

$form.Add_Load({
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            Install-LocalFilesAndShortcut
            
            if (Test-Winget) { Write-Log "Winget pronto." } else { Write-Log "Winget ausente." }
            
            $status = "Não Ativado"
            $check = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
            if ($check -match "permanente|permanent|ativado|activated") { $status = "Ativado" }
            
            $form.Invoke([System.Action[string]]{
                param($s)
                $lblStatus.Text = "Status do Windows: $s"
            }, $status)
        }
        catch { Write-Log "Erro no Load: $_" }
    }) | Out-Null
})

$btnInstallSelected.Add_Click({
    $selected = $installCheckboxes | Where-Object { $_.Checked -eq $true }
    if ($selected.Count -eq 0) { return }
    $btnInstallSelected.Enabled = $false
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            foreach ($cb in $selected) {
                $name = $cb.Text
                $id = $cb.Tag
                Write-Log "Instalando: $name..."
                # O comando start-process roda oculto no terminal, mas a janela principal do PS fica aberta.
                $proc = Start-Process winget -ArgumentList "install --id $id --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -PassThru -Wait
                if ($proc.ExitCode -eq 0) { Write-Log "Sucesso: $name" } else { Write-Log "Erro ao instalar: $name" }
            }
        }
        catch { Write-Log "Erro de instalacao: $_" }
        finally { $form.Invoke([System.Action]{ $btnInstallSelected.Enabled = $true }) }
    }) | Out-Null
})

$btnUninstallSelected.Add_Click({
    $selected = $uninstallCheckboxes | Where-Object { $_.Checked -eq $true }
    if ($selected.Count -eq 0) { return }
    $btnUninstallSelected.Enabled = $false
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            foreach ($cb in $selected) {
                $name = $cb.Text
                $id = $cb.Tag
                Write-Log "Removendo: $name..."
                $proc = Start-Process winget -ArgumentList "uninstall --id $id --silent" -NoNewWindow -PassThru -Wait
                if ($proc.ExitCode -eq 0) { Write-Log "Sucesso: $name removido." } else { Write-Log "Erro ao remover: $name" }
            }
        }
        catch { Write-Log "Erro de desinstalacao: $_" }
        finally { $form.Invoke([System.Action]{ $btnUninstallSelected.Enabled = $true }) }
    }) | Out-Null
})

$btnAutoActivate.Add_Click({
    $btnAutoActivate.Enabled = $false
    Write-Log "Iniciando ativacao silenciosa..."
    
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            $check = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
            if ($check -match "permanente|permanent|ativado|activated") {
                Write-Log "O Windows ja esta ativado."
                $form.Invoke([System.Action]{ $btnAutoActivate.Enabled = $true })
                return
            }
            
            Write-Log "Aplicando chave..."
            Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX" -NoNewWindow -Wait
            
            $KMS_Servers = @("kms.loli.best", "zh.us.to", "kms.digiboy.ir", "kms.msguides.com")
            $success = $false
            
            foreach ($server in $KMS_Servers) {
                Write-Log "Tentando KMS: $server..."
                Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /skms $server" -NoNewWindow -Wait
                Start-Process cscript -ArgumentList "C:\Windows\System32\slmgr.vbs /ato" -NoNewWindow -Wait
                
                $checkStatus = cscript //nologo C:\Windows\System32\slmgr.vbs /xpr
                if ($checkStatus -match "permanente|permanent|ativado|activated") {
                    $success = $true
                    Write-Log "Ativado com sucesso via: $server"
                    break
                }
            }
            
            $newStatus = if ($success) { "Ativado" } else { "Não Ativado" }
            $form.Invoke([System.Action[string]]{
                param($s)
                $lblStatus.Text = "Status do Windows: $s"
                $btnAutoActivate.Enabled = $true
            }, $newStatus)
        }
        catch { Write-Log "Erro na ativacao: $_"; $form.Invoke([System.Action]{ $btnAutoActivate.Enabled = $true }) }
    }) | Out-Null
})

$btnUpgradeAll.Add_Click({
    $btnUpgradeAll.Enabled = $false
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            Write-Log "Atualizando todos..."
            Start-Process winget -ArgumentList "upgrade --all --silent" -NoNewWindow -Wait
            Write-Log "Atualizacao concluida."
        }
        catch { Write-Log "Erro: $_" }
        finally { $form.Invoke([System.Action]{ $btnUpgradeAll.Enabled = $true }) }
    }) | Out-Null
})

$btnEdgeTweak.Add_Click({
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            if (Set-EdgeGoogleDefault) { Write-Log "Edge atualizado para Google." }
        }
        catch { Write-Log "Erro Edge: $_" }
    }) | Out-Null
})

# --- 9. EXECUTAR A JANELA ---
[void]$form.ShowDialog()
