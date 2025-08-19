# ================================
# ExportProject.ps1 – eksport kodu do 1 pliku TXT (auto-detect 'GrafikWPF')
# Zbiera wskazane rozszerzenia z całego drzewa (z pominięciem katalogów technicznych)
# i zapisuje je do ProjektSnapshot.txt w UTF-8 (bez BOM).
# ================================

[CmdletBinding()]
param(
    # Katalog ROOT projektu (tam zwykle jest .git / .sln; tu powstanie ProjektSnapshot.txt)
    [string]$SourcePath = "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods",
    # Nazwa pliku wyjściowego w ROOT
    [string]$OutputFile = "ProjektSnapshot.txt"
)

# Pełna ścieżka do snapshotu (zawsze w ROOT)
$OutputFile = Join-Path $SourcePath $OutputFile

# Rozszerzenia do eksportu (możesz dopisać kolejne, np. "*.yaml", "*.md")
$extensions = @("*.cs", "*.xaml", "*.csproj", "*.sln", "*.ps1", "*.json")

# Ignorowane katalogi (po pełnej ścieżce)
$ignoreDirs = @("bin", "obj", ".git", "packages", "TestResults", ".vs")

# -------------------------------
# Pomocnicze
# -------------------------------
function Test-IgnoredFullPath {
    param([string]$fullLower)
    return ($ignoreDirs | ForEach-Object { $fullLower -like "*\$_\*" }) -contains $true
}

function Get-WatchedFiles {
    param([string]$path)

    # Uwaga: -Include działa prawidłowo, gdy -Path zawiera wildcard (*)
    $pathWithWildcard = Join-Path $path '*'

    Get-ChildItem -Path $pathWithWildcard -Recurse -File -Force -Include $extensions |
        Where-Object {
            $fullLower = $_.FullName.ToLower()
            -not (Test-IgnoredFullPath $fullLower)
        } |
        Sort-Object FullName
}

function Count-MatchingFiles {
    param([string]$path)
    try {
        return (Get-WatchedFiles -path $path).Count
    } catch { return 0 }
}

# -------------------------------
# Auto-detekcja podfolderu "GrafikWPF" z kodem
# -------------------------------
$chosenPath = $SourcePath
$grafikDir  = Join-Path $SourcePath "GrafikWPF"

if (Test-Path $grafikDir) {
    # Jeśli w podfolderze "GrafikWPF" znajdziemy więcej plików kodu niż w root – użyj jego
    $rootCount   = Count-MatchingFiles -path $SourcePath
    $grafikCount = Count-MatchingFiles -path $grafikDir

    if ($grafikCount -gt $rootCount) {
        $chosenPath = $grafikDir
    }
}

try {
    # Zbierz pliki z wybranego miejsca
    $files = Get-WatchedFiles -path $chosenPath

    # Zapis w UTF-8 bez BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $sw = New-Object System.IO.StreamWriter($OutputFile, $false, $utf8NoBom)

    # Nagłówek snapshotu
    $sw.WriteLine("=== ProjektSnapshot.txt - {0} ===" -f (Get-Date))
    $sw.WriteLine("Źródło (SourcePath użyty do skanowania): {0}" -f $chosenPath)
    $sw.WriteLine("Plików: {0}" -f $files.Count)
    $sw.WriteLine("Ignorowane katalogi: {0}" -f ($ignoreDirs -join ", "))
    $sw.WriteLine("Rozszerzenia: {0}" -f ($extensions -join ", "))
    $sw.WriteLine(("=").PadLeft(41, "="))

    foreach ($f in $files) {
        $sw.WriteLine("=== FILE: {0} ===" -f $f.FullName)
        try {
            $sw.WriteLine((Get-Content -LiteralPath $f.FullName -Raw))
        }
        catch {
            $sw.WriteLine("[ERROR] Cannot read file: {0} | {1}" -f $f.FullName, $_.Exception.Message)
        }
        $sw.WriteLine("=== END FILE: {0} ===" -f $f.FullName)
        $sw.WriteLine()
    }

    $sw.Close()
    Write-Output "[OK] Snapshot saved to $OutputFile (files: $($files.Count); from: $chosenPath)"
    exit 0
}
catch {
    Write-Output "[ERROR] $($_.Exception.Message)"
    exit 1
}
