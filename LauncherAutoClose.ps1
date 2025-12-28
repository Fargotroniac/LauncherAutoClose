# VERSION: 2025.12.28.1950
# ==============================================================================
# Launcher Auto Close (LAC)
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
$remoteScriptUrl = "https://raw.githubusercontent.com/Fargotroniac/LauncherAutoClose/refs/heads/main/LauncherAutoClose.ps1"

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
    $config = $defaultConfig # Nouzový režim při poškození JSONu
}

# --- 3. AUTO-UPDATE SYSTÉM ----------------------------------------------------
function Validate-ScriptContent {
    param([string]$content)
    if (-not $content -or $content.Length -lt 1000) { return $false }
    if ($content -notmatch '# VERSION:' -or $content -notmatch 'function Watch-Launcher') { return $false }
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

# Kontrola updatu jednou denně
$today = (Get-Date).ToString("yyyy-MM-dd")
$lastUpdate = if (Test-Path $updateStamp) { (Get-Content $updateStamp).Trim() } else { "" }

if ($lastUpdate -ne $today) {
    if (Try-Update) {
        Set-Content $updateStamp $today
        return # Restart při příštím spuštění plánovače s novou verzí
    }
    Set-Content $updateStamp $today
}

# --- 4. DATA: SEZNAMY HER (Zde může být až 2000+ her) -------------------------
# Udržujeme v hashtable @{} pro bleskové vyhledávání O(1)
$ubiGamesList = @{
    "ACU"                  = "Any"
}

$blizzGamesList = @{
    "Diablo IV"           = "Blizzard"
    "Overwatch"           = "Blizzard"
}

$ubiLauncherDefs   = @{
    "upc"                    = "Ubisoft"
    "UbisoftConnect"         = "Ubisoft"
}
$blizzLauncherDefs = @{
    "Battle.net"             = "Blizzard"
}

# --- 5. HLAVNÍ VÝKONNÁ FUNKCE --------------------------------------------------
function Watch-Launcher {
    param (
        [string]$LauncherName,
        [Hashtable]$GamesList,
        [Hashtable]$LauncherList,
        [Object]$Settings,
        [Object]$AllProcesses
    )

    if (-not $Settings.Enabled) { return }

    $registryPath = "HKLM:\SOFTWARE\LauncherAutoClose"
    
    $activeGame = $AllProcesses | Where-Object { 
        $GamesList.ContainsKey($_.Name) -and (
            ($GamesList[$_.Name] -eq "Any") -or 
            ($null -ne $_.Company -and $_.Company -match [regex]::Escape($GamesList[$_.Name])) -or 
            ($null -ne $_.Description -and $_.Description -match [regex]::Escape($GamesList[$_.Name]))
        )
    } | Select-Object -First 1

    if ($activeGame) {
        if (-not (Test-Path "$registryPath\$LauncherName")) { New-Item "$registryPath\$LauncherName" -Force | Out-Null }
        Set-ItemProperty "$registryPath\$LauncherName" -Name "IsPlaying" -Value 1 -Force
    } 
    else {
        $regKey = "$registryPath\$LauncherName"
        if (Test-Path $regKey) {
            $val = Get-ItemProperty $regKey -Name "IsPlaying" -ErrorAction SilentlyContinue
            if ($val -and $val.IsPlaying -eq 1) {
                
                Start-Sleep -Seconds $Settings.WaitTime
                
                # Znovu načteme aktuální stav procesů pro ukončení launcheru
                $procsToClose = Get-Process | Where-Object { 
                    $LauncherList.ContainsKey($_.Name) -and ($_.Company -match $LauncherList[$_.Name])
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
}

# --- 6. VÝKONNOSTNÍ OPTIMALIZACE A SPUŠTĚNÍ ------------------------------------
# Načteme všechny běžící procesy jednou pro všechny volání funkce
$running = Get-Process | Select-Object Name, Company, Description

Watch-Launcher -LauncherName "Ubisoft" -GamesList $ubiGamesList -LauncherList $ubiLauncherDefs -Settings $config.Ubisoft -AllProcesses $running
Watch-Launcher -LauncherName "Blizzard" -GamesList $blizzGamesList -LauncherList $blizzLauncherDefs -Settings $config.Blizzard -AllProcesses $running
