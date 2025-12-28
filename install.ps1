# ==============================================================================
# INSTALLER: Launcher Auto Close (LAC) - ROBUST VERSION
# ==============================================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Instalator musi byt spusten jako SPRAVCE!"
    pause; exit
}

$baseDir = "C:\ProgramData\LauncherAutoClose"
$scriptPath = Join-Path $baseDir "LauncherAutoClose.ps1"
$configFile = Join-Path $baseDir "config.json"
# Opravena URL dle doporuceni
$remoteUrl = "https://raw.githubusercontent.com/Fargotroniac/LauncherAutoClose/main/LauncherAutoClose.ps1"

Write-Host "--- Zahajuji instalaci Launcher Auto Close (LAC) ---" -ForegroundColor Cyan

if (-not (Test-Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

Write-Host "[..] Stahuji aktualni skript z GitHubu..."
try {
    Invoke-WebRequest -Uri $remoteUrl -OutFile $scriptPath -UseBasicParsing -ErrorAction Stop
    Write-Host "[OK] Skript stazen." -ForegroundColor Green
} catch {
    Write-Error "Nepodarilo se stahnout skript. Zkontrolujte pripojeni nebo URL: $remoteUrl"
    pause; exit
}

if (-not (Test-Path $configFile)) {
    $defaultConfig = @{ Ubisoft = @{ Enabled = $true; WaitTime = 90 }; Blizzard = @{ Enabled = $true; WaitTime = 90 } }
    $defaultConfig | ConvertTo-Json | Set-Content $configFile
}

# --- REGISTRACE ÚLOHY S VYLEPŠENOU ROBUSTNOSTÍ ---
Write-Host "[..] Registruji ulohu do Planovace..."

$taskName = "LauncherAutoClose"
# Pridano -WorkingDirectory dle doporuceni
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -WorkingDirectory $baseDir

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$trigger1 = New-ScheduledTaskTrigger -AtStartup
# Pridano -RepetitionDuration pro nekonecny beh
$trigger2 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1)

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances Parallel

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger1, $trigger2 -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "[OK] Instalace dokoncena. LAC je aktivni." -ForegroundColor Green
pause
