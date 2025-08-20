# ================================
# ExportProject.ps1 – eksport kodu do 1 pliku TXT (auto-detect 'GrafikWPF')
# Stabilny dla Windows PowerShell 5.1:
#  - rekurencja bez -Include (filtr po rozszerzeniu w kodzie),
#  - pomija .vs/bin/obj/.git/packages/TestResults,
#  - zapisuje 2 pliki: UTF-8 z BOM (ProjektSnapshot.txt) i Windows-1250 (ProjektSnapshot_win1250.txt).
# ================================

[CmdletBinding()]
param(
    # Katalog ROOT projektu (tu powstaną pliki snapshotu)
    [string]$SourcePath = "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods",
    # Nazwa GŁÓWNEGO pliku wyjściowego (UTF-8 z BOM)
    [string]$OutputFile = "ProjektSnapshot.txt"
)

# Ścieżki plików wyjściowych
$Utf8File   = Join-Path $SourcePath $OutputFile
$Win1250File= Join-Path $SourcePath ([System.IO.Path]::GetFileNameWithoutExtension($OutputFile) + "_win1250" + [System.IO.Path]::GetExtension($OutputFile))

# Rozszerzenia do eksportu (małe litery, z kropką)
$allowedExt = @('.cs', '.xaml', '.csproj', '.sln', '.ps1', '.json')

# Ignorowane katalogi (dopasowanie do pełnej ścieżki, małe litery)
$ignoreDirs = @('\.git\', '\bin\', '\obj\', '\packages\', '\testresults\', '\.vs\')

function New-Separator([int]$len = 60) {
    try { return [string]::new('=', $len) } catch { return ('=' * $len) }
}

function Should-IgnorePath([string]$fullPath) {
    $p = $fullPath.ToLower()
    foreach ($frag in $ignoreDirs) {
        if ($p -like ("*" + $frag + "*")) { return $true }
    }
    return $false
}

function Is-AllowedExt([string]$fullPath) {
    $ext = [System.IO.Path]::GetExtension($fullPath)
    if ([string]::IsNullOrWhiteSpace($ext)) { return $false }
    return ($allowedExt -contains $ext.ToLower())
}

function Get-WatchedFiles([string]$root) {
    # ZBIERAMY WSZYSTKO rekurencyjnie, potem filtrujemy
    Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            (-not (Should-IgnorePath $_.FullName)) -and (Is-AllowedExt $_.FullName)
        } |
        Sort-Object FullName
}

function Count-WatchedFiles([string]$root) {
    try { return (Get-WatchedFiles $root).Count } catch { return 0 }
}

# --- Auto-detekcja podfolderu "GrafikWPF" (jeśli ma ≥ plików niż ROOT) ---
$chosenPath = $SourcePath
$grafikDir  = Join-Path $SourcePath "GrafikWPF"
try {
    if (Test-Path $grafikDir) {
        $rootCount   = Count-WatchedFiles $SourcePath
        $grafikCount = Count-WatchedFiles $grafikDir
        if ($grafikCount -ge $rootCount) { $chosenPath = $grafikDir }
    }
} catch { }

# --- Zbierz pliki ---
$files = Get-WatchedFiles $chosenPath
$sep   = New-Separator 60

# --- Przygotuj writerów do dwóch formatów: UTF-8 z BOM i Windows-1250 ---
$utf8WithBom  = New-Object System.Text.UTF8Encoding($true)         # BOM = true
$cp1250       = [System.Text.Encoding]::GetEncoding(1250)

$swUtf8   = New-Object System.IO.StreamWriter($Utf8File, $false, $utf8WithBom)
$sw1250   = New-Object System.IO.StreamWriter($Win1250File, $false, $cp1250)

# Helper do pisania do obu plików jednocześnie
function Write-Both([string]$line = "") {
    $swUtf8.WriteLine($line)
    $sw1250.WriteLine($line)
}

try {
    # --- Nagłówek ---
    Write-Both ("=== ProjektSnapshot.txt - {0} ===" -f (Get-Date))
    Write-Both ("Źródło skanowania: {0}" -f $chosenPath)
    Write-Both ("Ignorowane katalogi: {0}" -f (($ignoreDirs -replace '\\','') -join ", ").Replace(".git",".git"))
    Write-Both ("Rozszerzenia: {0}" -f (($allowedExt | ForEach-Object { "*$($_)" }) -join ", "))
    Write-Both ("Plików łącznie: {0}" -f $files.Count)

    # Grupowanie wg folderów
    $dirGroups = $files | Group-Object { $_.Directory.FullName }
    Write-Both ("Unikalnych folderów: {0}" -f $dirGroups.Count)

    # Podgląd pierwszych 10 względnych ścieżek
    if ($files.Count -gt 0) {
        Write-Both "Podgląd pierwszych 10 ścieżek (względnych):"
        $i = 0
        foreach ($f in $files) {
            $rel = $f.FullName
            if ($rel.StartsWith($chosenPath)) { $rel = $rel.Substring($chosenPath.Length).TrimStart('\') }
            Write-Both ("  - " + $rel)
            $i++
            if ($i -ge 10) { break }
        }
    }

    Write-Both $sep

    # --- Podsumowanie wg folderów (malejąco po liczbie, potem po nazwie) ---
    Write-Both "Podsumowanie plików wg folderów:"
    $sortedSummary = $dirGroups | Sort-Object -Property @{Expression='Count';Descending=$true}, @{Expression='Name';Descending=$false}
    foreach ($g in $sortedSummary) {
        Write-Both ("  " + $g.Name + "  ->  " + $g.Count)
    }
    Write-Both $sep
    Write-Both ""

    # --- Indeks plików wg folderów (ścieżki względne od $chosenPath) ---
    Write-Both "Indeks plików wg folderów (ścieżki względne):"
    $sortedGroups = $dirGroups | Sort-Object -Property Name
    foreach ($g in $sortedGroups) {
        $dirAbs = $g.Name
        $dirRel = $dirAbs
        if ($dirRel.StartsWith($chosenPath)) { $dirRel = $dirRel.Substring($chosenPath.Length).TrimStart('\') }
        if ([string]::IsNullOrWhiteSpace($dirRel)) { $dirRel = "." }

        Write-Both ("  [" + $dirRel + "]")
        foreach ($f in ($g.Group | Sort-Object Name)) {
            $rel = $f.FullName
            if ($rel.StartsWith($chosenPath)) { $rel = $rel.Substring($chosenPath.Length).TrimStart('\') }
            Write-Both ("    - " + $rel)
        }
        Write-Both ""
    }
    Write-Both $sep
    Write-Both ""

    # --- Zawartość plików ---
    foreach ($f in $files) {
        Write-Both ("=== FILE: {0} ===" -f $f.FullName)
        try {
            $content = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop
            # Zapisz treść do obu plików:
            $swUtf8.WriteLine($content)
            $sw1250.WriteLine($content)
        } catch {
            Write-Both ("[ERROR] Cannot read file: {0} | {1}" -f $f.FullName, $_.Exception.Message)
        }
        Write-Both ("=== END FILE: {0} ===" -f $f.FullName)
        Write-Both ""
    }

    $swUtf8.Close()
    $sw1250.Close()

    if ($files.Count -eq 0) {
        "[WARN] Export finished: 0 files collected (check SourcePath / extensions)" | Out-File -FilePath $Utf8File -Append -Encoding utf8
        "[WARN] Export finished: 0 files collected (check SourcePath / extensions)" | Out-File -FilePath $Win1250File -Append -Encoding Default
    }

    Write-Output "[OK] Snapshot saved to $Utf8File and $Win1250File (files: $($files.Count); from: $chosenPath)"
    exit 0
}
catch {
    try {
        "[FATAL] $($_.Exception.Message)" | Out-File -FilePath $Utf8File    -Append -Encoding utf8
        "[FATAL] $($_.Exception.Message)" | Out-File -FilePath $Win1250File -Append -Encoding Default
    } catch { }
    Write-Output "[OK] Snapshot saved with errors to $Utf8File and $Win1250File (from: $chosenPath)"
    exit 0
}
