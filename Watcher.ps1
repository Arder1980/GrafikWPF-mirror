# ================================
# Watcher.ps1 (v4.3) – polling, snapshot w ROOT, log UTF-16 (Unicode)
# ================================

[CmdletBinding()]
param(
    # ROOT repo (tu jest .git i ExportProject.ps1; tu zapisze się ProjektSnapshot.txt i Watcher.log)
    [string]$ProjectRoot     = "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods",
    # Katalog z kodem do monitorowania (domyślnie podfolder "GrafikWPF" w ROOT)
    [string]$SourcePath      = "",
    [string]$Remote          = "mirror",
    [string]$Branch          = "public",
    [int]   $PollSeconds     = 5,
    [string]$GitExe          = "C:\Program Files\Git\cmd\git.exe"
)

# Jeśli nie podano SourcePath -> ustaw na podfolder "GrafikWPF"
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $ProjectRoot "GrafikWPF"
}

# Ścieżki narzędzi i logów
$ExportScript = Join-Path $ProjectRoot "ExportProject.ps1"
$LogFile      = Join-Path $ProjectRoot "Watcher.log"

# Monitorowane rozszerzenia i ignorowane katalogi (po pełnej ścieżce)
$WatchedExtensions  = @(".cs", ".xaml", ".csproj", ".sln", ".ps1", ".json")
$IgnorePathPatterns = @("\.git\", "\bin\", "\obj\", "\packages\", "\TestResults\", "\.vs\")

# ------------------------------
# Pomocnicze
# ------------------------------
function Write-Log([string]$msg) {
    try {
        $ts  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "$ts $msg"
        # LOG: UTF-16 (Unicode) z BOM – pełna zgodność z Windows/Notatnik
        $line | Out-File -FilePath $LogFile -Append -Encoding Unicode
        Write-Host $line
    } catch {
        Write-Host ("[LOG ERROR] " + $_.Exception.Message)
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
    $builder = New-Object System.Text.StringBuilder
    $files = Get-WatchedFiles
    foreach ($f in $files) {
        [void]$builder.AppendLine(($f.FullName + "|" + $f.Length + "|" + $f.LastWriteTimeUtc.Ticks))
    }
    $txt = $builder.ToString()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($txt)
    $hashBytes = $sha.ComputeHash($bytes)
    $sha.Dispose()
    -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
}

function Do-ExportCommitPush {
    try {
        Write-Log "[INFO] Change detected -> export + commit + push"
        Write-Log "[INFO] Ignored directories: bin, obj, .git, packages, TestResults, .vs"

        # Eksport: SourcePath dla eksportu = ProjectRoot (snapshot w ROOT)
        powershell -NoProfile -ExecutionPolicy Bypass -File $ExportScript -SourcePath $ProjectRoot | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log ("[ERROR] ExportProject.ps1 failed (exit " + $LASTEXITCODE + ")")
            return
        }

        # Upewnij się, że snapshot jest śledzony nawet przy .gitignore
        & $GitExe -C $ProjectRoot add -f "ProjektSnapshot.txt" | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log ("[ERROR] git add (snapshot) failed (exit " + $LASTEXITCODE + ")"); return }

        # Dodaj resztę zmian
        & $GitExe -C $ProjectRoot add . | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Log ("[ERROR] git add (all) failed (exit " + $LASTEXITCODE + ")"); return }

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
Write-Host "=== Start Watcher ==="
Write-Log  "[INFO] Start Watcher (polling)"
Write-Log  ("[INFO] ProjectRoot: " + $ProjectRoot)
Write-Log  ("[INFO] SourcePath: " + $SourcePath)
Write-Log  ("[INFO] PollSeconds: " + $PollSeconds)
Write-Log  ("[INFO] Export script: " + $ExportScript)
Write-Log  ("[INFO] GitExe: " + $GitExe)

# Nagłówek logu
("=== Watcher started " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===") | Out-File -FilePath $LogFile -Append -Encoding Unicode

if (-not (Test-Path $ProjectRoot))  { Write-Log ("[ERROR] ProjectRoot not found: " + $ProjectRoot);  exit 1 }
if (-not (Test-Path $SourcePath))   { Write-Log ("[ERROR] SourcePath not found: " + $SourcePath);    exit 1 }
if (-not (Test-Path $ExportScript)) { Write-Log ("[ERROR] ExportProject.ps1 not found at: " + $ExportScript); exit 1 }

# ------------------------------
# Pętla pollingu
# ------------------------------
$prevSig = ""
Write-Log "[INFO] Initial snapshot (on start)"
while ($true) {
    try {
        $sig = Compute-Signature
        if ($sig -ne $prevSig) {
            if ($prevSig -ne "") { Write-Log "[INFO] Snapshot changed" }
            $prevSig = $sig
            Do-ExportCommitPush
        }
    } catch {
        Write-Log ("[ERROR] Poll loop: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
}
