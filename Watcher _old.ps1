# --- Watcher.ps1 (ASCII-safe) ---

param(
    [Parameter(Mandatory=$true)] [string]$SourcePath,
    [Parameter(Mandatory=$true)] [string]$RemoteName,
    [Parameter(Mandatory=$true)] [string]$RemoteUrl,
    [string]$RemoteBranch = "public",
    [int]$DebounceSeconds = 15
)

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg){  Write-Host "[ERR ] $msg" -ForegroundColor Red }

function Test-Git {
    $git = (Get-Command git -ErrorAction SilentlyContinue)
    if(-not $git){ throw "Git not found in PATH. Install Git for Windows (with Git Credential Manager)." }
}

function Ensure-GitRepo {
    Push-Location -LiteralPath $SourcePath
    try {
        if(-not (Test-Path (Join-Path $SourcePath ".git"))) {
            Write-Info "Initializing local git repo..."
            git init | Out-Null
        }
    } finally {
        Pop-Location
    }
}

function Ensure-Remote {
    Push-Location -LiteralPath $SourcePath
    try {
        # Read existing remotes safely and check by exact name
        $remotesRaw = git remote 2>$null
        $has = $false
        foreach($r in ($remotesRaw -split "`r?`n")){
            if([string]::IsNullOrWhiteSpace($r)) { continue }
            if($r.Trim() -eq $RemoteName) { $has = $true; break }
        }

        if($has){
            $currentUrl = git remote get-url $RemoteName 2>$null
            if($currentUrl -ne $RemoteUrl){
                Write-Warn "Remote '$RemoteName' has different URL. Updating..."
                git remote set-url $RemoteName $RemoteUrl | Out-Null
            }
        } else {
            Write-Info "Adding remote '$RemoteName'..."
            git remote add $RemoteName $RemoteUrl | Out-Null
        }
    } finally {
        Pop-Location
    }
}

function Ensure-Gitignore {
    $gitignore = Join-Path $SourcePath ".gitignore"
    if(Test-Path $gitignore){ return }
    Write-Warn ".gitignore not found - creating a safe default."

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
        git add -A | Out-Null
        $status = git status --porcelain
        if([string]::IsNullOrWhiteSpace($status)){
            Write-Info "Nothing to push."
            return
        }
        $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        git commit -m "Auto-publish: $stamp" | Out-Null

        $existsRemote = git ls-remote --heads $RemoteName $RemoteBranch
        if([string]::IsNullOrWhiteSpace($existsRemote)){
            Write-Info "First push to '$RemoteName/$RemoteBranch'..."
            git push -u $RemoteName HEAD:refs/heads/$RemoteBranch | Out-Null
        } else {
            git push $RemoteName HEAD:refs/heads/$RemoteBranch | Out-Null
        }
        Write-Info "Pushed to $RemoteName/$RemoteBranch."
    } finally {
        Pop-Location
    }
}

# --- START ---
Test-Git
$SourcePath = (Resolve-Path $SourcePath).Path
Ensure-GitRepo
Ensure-Gitignore
Ensure-Remote
Commit-And-Push

# File watcher with debounce
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

Write-Info "Watcher running. Folder: $SourcePath | Remote: $RemoteName -> $RemoteUrl | Branch: $RemoteBranch | Debounce: $DebounceSeconds s"
try {
    while($true){
        Start-Sleep -Seconds 2
        if($pending -and ((Get-Date) - $lastChange).TotalSeconds -ge $DebounceSeconds){
            $pending = $false
            try {
                Commit-And-Push
            } catch {
                Write-Err $_
                Start-Sleep -Seconds 5
            }
        }
    }
} finally {
    $fsw.Dispose()
}
