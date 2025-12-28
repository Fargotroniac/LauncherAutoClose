# VERSION: 2025.12.28.2113
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
$updateStamp     = Join-Path $baseDir "last_update_time.txt"
$localScriptPath = $MyInvocation.MyCommand.Path
$backupPath      = "$localScriptPath.bak"

# --- 2. NAČTENÍ / VYTVOŘENÍ KONFIGURACE (JSON) ---------------------------------
$defaultConfig = @{
    Ubisoft  = @{ Enabled = $true; WaitTime = 90 }
    Blizzard = @{ Enabled = $true; WaitTime = 90 }
    Update   = @{ Beta = $false }
}

if (-not (Test-Path $configFile)) {
    $defaultConfig | ConvertTo-Json | Set-Content $configFile
}

try {
    $config = Get-Content $configFile -Raw | ConvertFrom-Json
    if (-not $config.Update) { 
        $config | Add-Member -MemberType NoteProperty -Name "Update" -Value $defaultConfig.Update
        $config | ConvertTo-Json | Set-Content $configFile
    }
} catch {
    $config = $defaultConfig 
}

# --- 3. AUTO-UPDATE SYSTÉM ----------------------------------------------------

# Nastavení kanálu a intervalu
if ($config.Update.Beta) {
    $branch = "beta"
    $intervalHours = 1
} else {
    $branch = "main"
    $intervalHours = 24 
}

$remoteScriptUrl = "https://raw.githubusercontent.com/Fargotroniac/LauncherAutoClose/$branch/LauncherAutoClose.ps1"

function Validate-ScriptContent {
    param([string]$content)
    if (-not $content -or $content.Length -lt 3000) { return $false }
    if ($content -match "<html" -or $content -match "<body" -or $content -match "<!DOCTYPE html") { return $false }
    
    $versionLine = ($content -split "`r?`n") | Where-Object { $_ -match "^# VERSION:" }
    if (-not $versionLine -or $versionLine -notmatch "^# VERSION:\s\d{4}\.\d{2}\.\d{2}\.\d{4}$") { return $false }
    
    if ($content -notmatch "Try-Update" -or $content -notmatch "function\s+Watch-Launcher") { return $false }
    if ($content -notmatch "\$ubiGamesList" -or $content -notmatch "\$configFile") { return $false }
    return $true
}

function Get-VersionFromContent {
    param([string]$content)
    $line = ($content -split "`r?`n") | Where-Object { $_ -like '# VERSION:*' }
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

$shouldUpdate = $false
$now = Get-Date

if (-not (Test-Path $updateStamp)) {
    $shouldUpdate = $true
} else {
    $lastDateStr = (Get-Content $updateStamp).Trim()
    if ([DateTime]::TryParse($lastDateStr, [ref]$lastUpdate)) {
        if ($now -gt $lastDate.AddHours($intervalHours)) {
            $shouldUpdate = $true
        }
    } else {
        $shouldUpdate = $true
    }
}

if ($shouldUpdate) {
    $updateResult = Try-Update
    $now.ToString("yyyy-MM-dd HH:mm:ss") | Set-Content $updateStamp
    if ($updateResult) { return }
}

# --- 4. DATA -------------------------
$ubiGamesList = @{
    "ACU" = "Any"
}

$ubiLauncherData = @{
    Companies = @("Ubisoft", "Ubisoft Entertainment");
    Processes = @("UbisoftConnect", "upc", "UplayWebHelper")
}

$blizzGamesList = @{

}

$blizzLauncherData = @{
    Companies = @(); Processes = @()
}

# --- 5. FUNKCE ------------------------------------
function Watch-Launcher {
    param (
        [string]$LauncherName,
        [Hashtable]$GamesList,
        [Hashtable]$LData,
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
            
            # Kontrola procesů launcheru
            $procsToClose = Get-Process | Where-Object { 
                $LData.Processes -contains $_.Name -and 
                ($null -ne $_.Company -and ($LData.Companies -contains $_.Company))
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

Watch-Launcher -LauncherName "Ubisoft" -GamesList $ubiGamesList -LData $ubiLauncherData -Settings $config.Ubisoft -AllProcesses $running
Watch-Launcher -LauncherName "Blizzard" -GamesList $blizzGamesList -LData $blizzLauncherData -Settings $config.Blizzard -AllProcesses $running
