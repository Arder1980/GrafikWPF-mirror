# ================================
# ExportProject.ps1 – eksport kodu do 1 pliku TXT (auto-detect 'GrafikWPF')
# UTF-8 z BOM (dla zgodności z Windows/Notatnik), rekurencja, .vs/bin/obj/.git/packages/TestResults ignorowane.
# ================================

[CmdletBinding()]
param(
    # Katalog ROOT projektu (tu powstanie ProjektSnapshot.txt)
    [string]$SourcePath = "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods",
    [string]$OutputFile = "ProjektSnapshot.txt"
)

# Pełna ścieżka do snapshotu
$OutputFile = Join-Path $SourcePath $OutputFile

# Rozszerzenia do eksportu
$extensions = @("*.cs", "*.xaml", "*.csproj", "*.sln", "*.ps1", "*.json")

# Ignorowane katalogi (po pełnej ścieżce)
$ignoreDirs = @("bin", "obj", ".git", "packages", "TestResults", ".vs")

function New-Separator([int]$len = 60) {
    try { return [string]::new('=', $len) } catch { return ('=' * $len) }
}

function Test-IgnoredFullPath {
    param([string]$fullLower)
    foreach ($d in $ignoreDirs) {
        if ($fullLower -like "*\${d.ToLower()}\*") { return $true }
    }
    return $false
}

function Get-WatchedFiles {
    param([string]$path)
    # Uwaga: -Include działa pewnie, gdy -Path zawiera wildcard (*)
    $pathWithWildcard = Join-Path $path '*'
    Get-ChildItem -Path $pathWithWildcard -Recurse -File -Force -Include $extensions -ErrorAction SilentlyContinue |
        Where-Object {
            -not (Test-IgnoredFullPath $_.FullName.ToLower())
        } |
        Sort-Object FullName
}

function Count-MatchingFiles {
    param([string]$path)
    try { return (Get-WatchedFiles -path $path).Count } catch { return 0 }
}

# --- Auto-detekcja podfolderu "GrafikWPF" (jeśli w nim jest więcej plików kodu niż w root) ---
$chosenPath = $SourcePath
$grafikDir  = Join-Path $SourcePath "GrafikWPF"
try {
    if (Test-Path $grafikDir) {
        $rootCount   = Count-MatchingFiles -path $SourcePath
        $grafikCount = Count-MatchingFiles -path $grafikDir
        if ($grafikCount -ge $rootCount) { $chosenPath = $grafikDir }
    }
} catch { }

try {
    $files = Get-WatchedFiles -path $chosenPath

    # --- UTF-8 z BOM (większa kompatybilność z Notatnikiem/konsolą) ---
    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $sw = New-Object System.IO.StreamWriter($OutputFile, $false, $utf8WithBom)

    $sep = New-Separator 60

    # --- Nagłówek snapshotu ---
    $sw.WriteLine("=== ProjektSnapshot.txt - {0} ===" -f (Get-Date))
    $sw.WriteLine("Źródło skanowania: {0}" -f $chosenPath)
    $sw.WriteLine("Ignorowane katalogi: {0}" -f ($ignoreDirs -join ", "))
    $sw.WriteLine("Rozszerzenia: {0}" -f ($extensions -join ", "))
    $sw.WriteLine("Plików łącznie: {0}" -f $files.Count)
    $sw.WriteLine($sep)

    # --- Podsumowanie plików wg folderów (bez operatora -f, żeby uniknąć kolizji z {} w ścieżkach) ---
    try {
        $sw.WriteLine("Podsumowanie plików wg folderów:")
        $groups = $files | Group-Object { $_.Directory.FullName }
        foreach ($g in $groups | Sort-Object Name) {
            $line = "  " + $g.Name + "  ->  " + $g.Count
            $sw.WriteLine($line)
        }
        $sw.WriteLine($sep)
        $sw.WriteLine()
    } catch {
        $sw.WriteLine("[WARN] Folder summary error: {0}" -f $_.Exception.Message)
        $sw.WriteLine($sep)
        $sw.WriteLine()
    }

    # --- Zawartość plików ---
    foreach ($f in $files) {
        $sw.WriteLine("=== FILE: {0} ===" -f $f.FullName)
        try {
            $sw.WriteLine((Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop))
        } catch {
            $sw.WriteLine("[ERROR] Cannot read file: {0} | {1}" -f $f.FullName, $_.Exception.Message)
        }
        $sw.WriteLine("=== END FILE: {0} ===" -f $f.FullName)
        $sw.WriteLine()
    }

    $sw.Close()

    if ($files.Count -eq 0) {
        "[WARN] Export finished: 0 files collected (check SourcePath / extensions)" | Out-File -FilePath $OutputFile -Append -Encoding utf8
    }

    Write-Output "[OK] Snapshot saved to $OutputFile (files: $($files.Count); from: $chosenPath)"
    exit 0
}
catch {
    try {
        "[FATAL] $($_.Exception.Message)" | Out-File -FilePath $OutputFile -Append -Encoding utf8
    } catch { }
    Write-Output "[OK] Snapshot saved with errors to $OutputFile (from: $chosenPath)"
    exit 0
}
