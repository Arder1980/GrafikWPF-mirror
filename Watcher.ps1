# ================================
# Watcher.ps1 (v4) – prosty, pancerny watcher oparty na polling
# Co PollSeconds sekund liczy hash plików w katalogu z kodem (SourcePath).
# Gdy hash się zmienia -> ExportProject.ps1 -> git add -> commit -> push (mirror/public)
# ================================

param(
    # ROOT repo (tu jest .git i ExportProject.ps1; tu zapisze się ProjektSnapshot.txt)
    [string]$ProjectRoot     = "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods",
    # Katalog z kodem (monitorowany). Domyślnie podfolder "GrafikWPF" w ROOT.
    [string]$SourcePath      = "",
    [string]$Remote          = "mirror",
    [string]$Branch          = "public",
    [int]   $PollSeconds     = 5
)

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $ProjectRoot "GrafikWPF"
}

# Narzędzia i pliki
$GitExe       = "C:\Program Files\Git\cmd\git.exe"
$ExportScript = Join-Path $ProjectRoot "ExportProject.ps1"
$LogFile      = Join-Path $ProjectRoot "Watcher.log"

# Co monitorujemy
$WatchedExtensions  = @(".cs", ".xaml", ".csproj", ".sln", ".ps1", ".json")
$IgnorePathPatterns = @("\.git\", "\bin\", "\obj\", "\packages\", "\TestResults\")

# ------------------------------
# Pomocnicze
# ------------------------------
function Write-Log([string]$msg) {
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "$ts $msg"
        $line | Out-File -FilePath $LogFile -Encoding utf8 -Append
        Write-Output $msg
    } catch {
        Write-Output ("[LOG ERROR] " + $_.Exception.Message)
    }
}

function Test-IgnoredPath([string]$fullPath) {
    $p = $fullPath.ToLower()
    foreach ($pat in $IgnorePathPatterns) {
        if ($p -like ("*" + $pat + "*")) { return $true }
    }
    return $false
}

function Test-WatchedExtension([string]$fullPath) {
    $ext = [System.IO.Path]::GetExtension($fullPath)
    if ([string]::IsNullOrWhiteSpace($ext)) { return $false }
    return ($WatchedExtensions -contains $ext.ToLower())
}

function Get-WatchedFiles {
    Get-ChildItem -Path $SourcePath -Recurse -File -Force |
        Where-Object {
            (-not (Test-IgnoredPath $_.FullName)) -and (Test-WatchedExtension $_.FullName)
        } |
        Sort-Object FullName
}

function Compute-Signature {
    # Tworzymy deterministyczny tekstowy „odcisk palca” na bazie ścieżki, rozmiaru i czasu modyfikacji
    $builder = New-Object System.Text.StringBuilder
    $files = Get-WatchedFiles
    foreach ($f in $files) {
        # Wpis: pełna_ścieżka|rozmiar|ticks_czasu
        [void]$builder.AppendLine(($f.FullName + "|" + $f.Length + "|" + $f.LastWriteTimeUtc.Ticks))
    }
    $txt = $builder.ToString()

    # Hash SHA256 z powyższego tekstu
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($txt)
    $hashBytes = $sha.ComputeHash($bytes)
    $sha.Dispose()
    # Zwracamy hex
    -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
}

function Do-ExportCommitPush {
    try {
        Write-Log "[INFO] Change detected -> export + commit + push"

        # Eksport (uruchamiany z ROOT-u)
        powershell -NoProfile -ExecutionPolicy Bypass -File $ExportScript | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log ("[ERROR] ExportProject.ps1 failed (exit " + $LASTEXITCODE + ")")
            return
        }

        # git add/commit/push w ROOT
        & $GitExe -C $ProjectRoot add .        | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log ("[ERROR] git add failed (exit " + $LASTEXITCODE + ")"); return }

        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $msg = "auto: snapshot " + $stamp
        & $GitExe -C $ProjectRoot commit -m $msg --allow-empty | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log ("[ERROR] git commit failed (exit " + $LASTEXITCODE + ")"); return }

        & $GitExe -C $ProjectRoot push $Remote $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log ("[ERROR] git push failed (exit " + $LASTEXITCODE + ") - sprawdz remote/branch/tozsamosc"); return }

        Write-Log "[OK] Snapshot committed and pushed"
    }
    catch {
        Write-Log ("[ERROR] Export/Commit/Push: " + $_.Exception.Message)
    }
}

# ------------------------------
# Start – sanity checks
# ------------------------------
Write-Output "[INFO] Start Watcher (polling)"
Write-Output ("[INFO] ProjectRoot: " + $ProjectRoot)
Write-Output ("[INFO] SourcePath: " + $SourcePath)
Write-Output ("[INFO] PollSeconds: " + $PollSeconds)
Write-Output ("[INFO] Export script: " + $ExportScript)
Write-Output ("[INFO] GitExe: " + $GitExe)

("=== Watcher started " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===") | Out-File -FilePath $LogFile -Encoding utf8 -Append

if (-not (Test-Path $ProjectRoot)) { Write-Log ("[ERROR] ProjectRoot not found: " + $ProjectRoot); exit 1 }
if (-not (Test-Path $SourcePath))  { Write-Log ("[ERROR] SourcePath not found: " + $SourcePath);   exit 1 }
if (-not (Test-Path $ExportScript)){ Write-Log ("[ERROR] ExportProject.ps1 not found at: " + $ExportScript); exit 1 }

# ------------------------------
# Pętla pollingu
# ------------------------------
# Pierwsza sygnatura (po starcie) – wywoła od razu 1. eksport, żebyś miał snapshot w repo
$prevSig = ""
while ($true) {
    try {
        $sig = Compute-Signature
        if ($sig -ne $prevSig) {
            if ($prevSig -eq "") {
                Write-Log "[INFO] Initial snapshot (on start)"
            } else {
                Write-Log "[INFO] Snapshot changed"
            }
            $prevSig = $sig
            Do-ExportCommitPush
        }
    } catch {
        Write-Log ("[ERROR] Poll loop: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
}
