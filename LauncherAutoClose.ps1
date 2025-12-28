# VERSION: 2025.12.28.2023
# ==============================================================================
# Launcher Auto Close (LAC)
# Created by Fargotroniac
# ==============================================================================

# --- 1. ZÁKLADNÍ CESTY A PŘÍPRAVA ----------------------------------------------
$baseDir = "C:\ProgramData\LauncherAutoClose"
if (-not (Test-Path $baseDir)) {
    New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
}

$configFile      = Join-Path $baseDir "config.json"
$updateStamp     = Join-Path $baseDir "last_update.txt"
$localScriptPath = $MyInvocation.MyCommand.Path
$backupPath      = "$localScriptPath.bak"
$remoteScriptUrl = "https://raw.githubusercontent.com/Fargotroniac/LauncherAutoClose/main/LauncherAutoClose.ps1"

# --- 2. NAČTENÍ / VYTVOŘENÍ KONFIGURACE (JSON) ---------------------------------
$defaultConfig = @{
    Ubisoft  = @{ Enabled = $true;  WaitTime = 90 }
    Blizzard = @{ Enabled = $true;  WaitTime = 90 }
}

if (-not (Test-Path $configFile)) {
    $defaultConfig | ConvertTo-Json | Set-Content $configFile
}

try {
    $config = Get-Content $configFile -Raw | ConvertFrom-Json
} catch {
    $config = $defaultConfig 
}

# --- 3. AUTO-UPDATE SYSTÉM ----------------------------------------------------
function Validate-ScriptContent {
    param(
        [string]$content
    )

    # 1) Základní kontrola
    if (-not $content) { return $false }
    if ($content.Length -lt 3000) { return $false }

    # 2) Kontrola HTML (Zůstává stejná)
    if ($content -match "<html" -or $content -match "<body" -or $content -match "<!DOCTYPE html") { return $false }

    # 3) Kontrola verze
    $versionLine = ($content -split "`r?`n") | Where-Object { $_ -match "^# VERSION:" }
    if (-not $versionLine) { return $false }
    if ($versionLine -notmatch "^# VERSION:\s\d{4}\.\d{2}\.\d{2}\.\d{4}$") { return $false }

    # 4) Kontrola funkcí
    if ($content -notmatch "Try-Update") { return $false }
    if ($content -notmatch "Validate-ScriptContent") { return $false }
    if ($content -notmatch "Get-VersionFromContent") { return $false }

    # 5) Kontrola hlavní funkce
    if ($content -notmatch "function\s+Watch-Launcher") { return $false }

    # 6) Kontrola seznamů
    if ($content -notmatch "\$ubiGamesList") { return $false }

    # 7) Kontrola spouštění
    if ($content -notmatch "Watch-Launcher") { return $false }

    # 8) Kontrola configu
    if ($content -notmatch "\$configFile") { return $false }
    if ($content -notmatch "ConvertFrom-Json") { return $false }

    return $true
}

function Get-VersionFromContent {
    param([string]$content)
    $lines = $content -split "`r?`n"
    $line  = $lines | Where-Object { $_ -like '# VERSION:*' }
    if (-not $line) { return $null }
    return $line.Replace('# VERSION:', '').Trim()
}

function Try-Update {
    try {
        Copy-Item $localScriptPath $backupPath -Force
        $tempPath = "$localScriptPath.tmp"
        Invoke-WebRequest -Uri $remoteScriptUrl -OutFile $tempPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        
        $newContent = Get-Content $tempPath -Raw
        if (-not (Validate-ScriptContent $newContent)) {
            Remove-Item $tempPath -Force; return $false
        }

        $localVersion  = Get-VersionFromContent (Get-Content $localScriptPath -Raw)
        $remoteVersion = Get-VersionFromContent $newContent

        if ($localVersion -and ([version]$remoteVersion -gt [version]$localVersion)) {
            Move-Item $tempPath $localScriptPath -Force
            return $true
        }
        Remove-Item $tempPath -Force; return $false
    } catch { return $false }
}

$today = (Get-Date).ToString("yyyy-MM-dd")
$lastUpdate = if (Test-Path $updateStamp) { (Get-Content $updateStamp).Trim() } else { "" }

if ($lastUpdate -ne $today) {
    if (Try-Update) {
        Set-Content $updateStamp $today
        return 
    }
    Set-Content $updateStamp $today
}

# --- 4. DATA -------------------------
# --- Ubisoft ---
$ubiGamesList = @{
    "ACU" = "Any"
}

$ubiLauncherDefs   = @{
[PSCustomObject]@{ Companies = @("Ubisoft", "Ubisoft Entertainment"); Processes = @("UbisoftConnect", "upc", "UplayWebHelper") }
}
# --- Blizzard ---
$blizzGamesList = @{

}

$blizzLauncherDefs = @{
 @{ Companies = @(); Processes = @() }
}

# --- 5. HLAVNÍ VÝKONNÁ FUNKCE --------------------------------------------------
function Watch-Launcher {
    param (
        [string]$LauncherName,
        [Hashtable]$GamesList,
        [Object]$LauncherData, 
        [Object]$Settings,
        [Object]$AllProcesses
    )

    if (-not $Settings.Enabled -or $GamesList.Count -eq 0) { return }

    $registryPath = "HKLM:\SOFTWARE\LauncherAutoClose"
    
    # 1. Detekce hry
    $activeGame = $AllProcesses | Where-Object { 
        $GamesList.ContainsKey($_.Name) -and (
            ($GamesList[$_.Name] -eq "Any") -or 
            ($null -ne $_.Company -and $_.Company -match [regex]::Escape($GamesList[$_.Name]))
        )
    } | Select-Object -First 1

    if ($activeGame) {
        if (-not (Test-Path "$registryPath\$LauncherName")) { New-Item "$registryPath\$LauncherName" -Force | Out-Null }
        Set-ItemProperty "$registryPath\$LauncherName" -Name "IsPlaying" -Value 1 -Force
    } 
    else {
        $regKey = "$registryPath\$LauncherName"
        $val = Get-ItemProperty $regKey -Name "IsPlaying" -ErrorAction SilentlyContinue
        if ($val -and $val.IsPlaying -eq 1) {
            
            Start-Sleep -Seconds $Settings.WaitTime
            
            $procsToClose = Get-Process | Where-Object { 
                $LauncherData.Processes -contains $_.Name -and 
                ($LauncherData.Companies -contains $_.Company)
            } -ErrorAction SilentlyContinue
            
            if ($procsToClose) {
                $procsToClose | ForEach-Object { $_.CloseMainWindow() | Out-Null }
                Start-Sleep -Seconds 30
                $procsToClose | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            Remove-ItemProperty $regKey -Name "IsPlaying" -ErrorAction SilentlyContinue
        }
    }
}

# --- 6. SPUŠTĚNÍ ---
$running = Get-Process | Select-Object Name, Company, Description

Watch-Launcher -LauncherName "Ubisoft" -GamesList $ubiGamesList -LauncherList $ubiLauncherDefs -Settings $config.Ubisoft -AllProcesses $running
Watch-Launcher -LauncherName "Blizzard" -GamesList $blizzGamesList -LauncherList $blizzLauncherDefs -Settings $config.Blizzard -AllProcesses $running
