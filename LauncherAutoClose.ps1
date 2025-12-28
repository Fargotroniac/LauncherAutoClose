# VERSION: 2025.12.28.1049
# Tento skript je generován automaticky z větvě develop. Neupravujte jej přímo v main.

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
    $config = $defaultConfig 
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

$today = (Get-Date).ToString("yyyy-MM-dd")
$lastUpdate = if (Test-Path $updateStamp) { (Get-Content $updateStamp).Trim() } else { "" }

if ($lastUpdate -ne $today) {
    if (Try-Update) {
        Set-Content $updateStamp $today
        return 
    }
    Set-Content $updateStamp $today
}

# --- 4. DATA (ROZDĚLENÉ SEZNAMY) ---
$UbiGamesList = @{
#INSERT_UBI_GAMES#
}

$BlizzGamesList = @{
#INSERT_BLIZZ_GAMES#
}

$LauncherDefs = @{
    "UbisoftConnect" = "Ubisoft|Ubisoft Entertainment"
    "upc" = "Ubisoft|Ubisoft Entertainment"
    "UplayWebHelper" = "Ubisoft|Ubisoft Entertainment"
    "Battle.net" = "Blizzard Entertainment"
    "Agent" = "Blizzard Entertainment"
}

# --- 5. HLAVNÍ VÝKONNÁ FUNKCE ---
function Watch-Launcher {
    param (
        [string]$LauncherName,
        [Hashtable]$GamesList,
        [Hashtable]$LauncherList,
        [Object]$Settings,
        [Object]$AllProcesses,
        [string]$DefaultSignature  # "Ubisoft" nebo "Blizzard"
    )

    if (-not $Settings.Enabled) { return }

    $registryPath = "HKLM:\SOFTWARE\LauncherAutoClose"
    
    $activeGame = $AllProcesses | Where-Object { 
        $GamesList.ContainsKey($_.Name) -and (
            $rule = $GamesList[$_.Name]
            if ($rule -eq "Any") {
                # Pokud je v JSONu "Any", hledáme v podpisu výchozí jméno firmy
                ($null -ne $_.Company -and $_.Company -match $DefaultSignature) -or 
                ($null -ne $_.Description -and $_.Description -match $DefaultSignature)
            } else {
                # Jinak hledáme konkrétní slovo z JSONu (třeba "Assassin")
                ($null -ne $_.Company -and $_.Company -match $rule) -or 
                ($null -ne $_.Description -and $_.Description -match $rule)
            }
        )
    } | Select-Object -First 1

    # ... (zbytek logiky se zápisem do registru a zavíráním zůstává stejný) ...
    if ($activeGame) {
        if (-not (Test-Path "$registryPath\$LauncherName")) { New-Item "$registryPath\$LauncherName" -Force | Out-Null }
        Set-ItemProperty "$registryPath\$LauncherName" -Name "IsPlaying" -Value 1 -Force
    } 
    else {
        # ... logika ukončení (start-sleep atd.) ...
    }
}

# --- 6. SPUŠTĚNÍ ---
$running = Get-Process | Select-Object Name, Company, Description

# Tady voláme funkci pro každý launcher s jeho vlastním seznamem
Watch-Launcher -LauncherName "Ubisoft" -GamesList $UbiGamesList -LauncherList $LauncherDefs -Settings $config.Ubisoft -AllProcesses $running -DefaultSignature "Ubisoft"
Watch-Launcher -LauncherName "Blizzard" -GamesList $BlizzGamesList -LauncherList $LauncherDefs -Settings $config.Blizzard -AllProcesses $running -DefaultSignature "Blizzard"


