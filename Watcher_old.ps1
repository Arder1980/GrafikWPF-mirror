# --- Watcher.ps1: autodetekcja git.exe, param -GitExe opcjonalny ---

param(
    [Parameter(Mandatory=$true)] [string]$SourcePath,
    [Parameter(Mandatory=$true)] [string]$RemoteName,
    [Parameter(Mandatory=$true)] [string]$RemoteUrl,
    [string]$RemoteBranch = "public",
    [int]$DebounceSeconds = 15,
    [string]$GitExe = ""
)

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg){  Write-Host "[ERR ] $msg" -ForegroundColor Red }

# Znajdź git.exe: 1) jeśli podano -GitExe, 2) PATH, 3) typowe lokalizacje
function Resolve-Git {
    if($GitExe){
        if(Test-Path -LiteralPath $GitExe){
            Write-Info "Using git: $GitExe"
            return $GitExe
        } else {
            Write-Warn "Provided GitExe not found: $GitExe"
        }
    }
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if($cmd){ Write-Info "Using git from PATH: $($cmd.Path)"; return $cmd.Path }

    $candidates = @(
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\git.exe",
        "$env:LOCALAPPDATA\GitHub\PortableGit_*\cmd\git.exe"
    )

    foreach($pat in $candidates){
        $found = Get-ChildItem -Path $pat -ErrorAction SilentlyContinue | Select-Object -First 1
        if($found){ Write-Info "Using git: $($found.FullName)"; return $found.FullName }
    }

    throw "Nie znaleziono git.exe. Zainstaluj Git for Windows lub uruchom z parametrem -GitExe ""pełna\ścieżka\do\git.exe""."
}

# Helper: wywołanie git pełną ścieżką
function Invoke-Git {
    & $script:GitExe @args
}


# Inic
$GitPath = Resolve-Git
$SourcePath = (Resolve-Path $SourcePath).Path

Write-Info "Start Watcher"
Write-Info "Script: $PSCommandPath"
Write-Info "SourcePath: $SourcePath"
Write-Info "Remote: $RemoteName -> $RemoteUrl (branch: $RemoteBranch)"
Write-Info "GitExe: $GitPath"
Write-Info "Debounce: $DebounceSeconds s"

function Ensure-GitRepo {
    Push-Location -LiteralPath $SourcePath
    try {
        if(-not (Test-Path (Join-Path $SourcePath '.git'))) {
            Write-Info "Init local git repo..."
            Invoke-Git init | Out-Null
        }
    } finally { Pop-Location }
}

function Ensure-Remote {
    Push-Location -LiteralPath $SourcePath
    try {
        $remotesRaw = Invoke-Git remote 2>$null
        $has = $false
        foreach($r in ($remotesRaw -split "`r?`n")){
            if([string]::IsNullOrWhiteSpace($r)) { continue }
            if($r.Trim() -eq $RemoteName) { $has = $true; break }
        }
        if($has){
            $currentUrl = Invoke-Git remote get-url $RemoteName 2>$null
            if($currentUrl -ne $RemoteUrl){
                Write-Warn "Remote '$RemoteName' has different URL. Updating..."
                Invoke-Git remote set-url $RemoteName $RemoteUrl | Out-Null
            }
        } else {
            Write-Info "Adding remote '$RemoteName'..."
            Invoke-Git remote add $RemoteName $RemoteUrl | Out-Null
        }
    } finally { Pop-Location }
}

function Ensure-Gitignore {
    $gitignore = Join-Path $SourcePath ".gitignore"
    if(Test-Path $gitignore){ return }
    Write-Warn ".gitignore not found - creating safe default."
    $content = @"
# Tooling folders
.git/
.vs/
.idea/
.vscode/
TestResults/
packages/
node_modules/
dist/
out/
_ReSharper.Caches/

# Build output
bin/
obj/
*.pdb
*.dll
*.exe
*.cache
*.log

# User/environment files
*.user
*.suo
*.tmp
*.swp
*.bak
*.db

# System
Thumbs.db
.DS_Store

# Profile-specific settings (optional)
appsettings.*.json

# Other artifacts
*.coverage
*.nupkg
"@
    $content | Out-File -FilePath $gitignore -Encoding UTF8 -Force
}

function Commit-And-Push {
    Push-Location -LiteralPath $SourcePath
    try {
        Invoke-Git add -A | Out-Null
        $status = Invoke-Git status --porcelain
        if([string]::IsNullOrWhiteSpace($status)){
            Write-Info "Nothing to push."
            return
        }
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Invoke-Git commit -m "Auto-publish: $stamp" | Out-Null

        $existsRemote = Invoke-Git ls-remote --heads $RemoteName $RemoteBranch
        if([string]::IsNullOrWhiteSpace($existsRemote)){
            Write-Info "First push to '$RemoteName/$RemoteBranch'..."
            Invoke-Git push -u $RemoteName HEAD:refs/heads/$RemoteBranch | Out-Null
        } else {
            Invoke-Git push $RemoteName HEAD:refs/heads/$RemoteBranch | Out-Null
        }
        Write-Info "Pushed to $RemoteName/$RemoteBranch."
    } finally { Pop-Location }
}

# --- START ---
Ensure-GitRepo
Ensure-Gitignore
Ensure-Remote
Commit-And-Push

# Watcher with debounce
$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $SourcePath
$fsw.IncludeSubdirectories = $true
$fsw.EnableRaisingEvents = $true
$fsw.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size, Attributes'

$lastChange = Get-Date
$pending = $false

Register-ObjectEvent $fsw Changed -Action { $global:pending = $true; $global:lastChange = Get-Date } | Out-Null
Register-ObjectEvent $fsw Created -Action { $global:pending = $true; $global:lastChange = Get-Date } | Out-Null
Register-ObjectEvent $fsw Deleted -Action { $global:pending = $true; $global:lastChange = Get-Date } | Out-Null
Register-ObjectEvent $fsw Renamed -Action { $global:pending = $true; $global:lastChange = Get-Date } | Out-Null

Write-Info "Watcher running."
try {
    while($true){
        Start-Sleep -Seconds 2
        if($pending -and ((Get-Date) - $lastChange).TotalSeconds -ge $DebounceSeconds){
            $pending = $false
            try { Commit-And-Push }
            catch { Write-Err $_; Start-Sleep -Seconds 5 }
        }
    }
} finally { $fsw.Dispose() }
