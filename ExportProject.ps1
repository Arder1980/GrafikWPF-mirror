# ================================
# ExportProject.ps1 – eksport kodu do 1 pliku TXT
# Zbiera wskazane rozszerzenia z całego drzewa (z pominięciem katalogów technicznych)
# i zapisuje je do ProjektSnapshot.txt w UTF-8 (bez BOM).
# ================================

[CmdletBinding()]
param(
    # Katalog ROOT projektu (tam powstanie ProjektSnapshot.txt)
    [string]$SourcePath = "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods",
    # Nazwa pliku wyjściowego w ROOT
    [string]$OutputFile = "ProjektSnapshot.txt"
)

# Pełna ścieżka do snapshotu
$OutputFile = Join-Path $SourcePath $OutputFile

# Rozszerzenia do eksportu (możesz dopisać kolejne, np. "*.yaml", "*.md")
$extensions = @("*.cs", "*.xaml", "*.csproj", "*.sln", "*.ps1", "*.json")

# Ignorowane katalogi (po pełnej ścieżce)
$ignoreDirs = @("bin", "obj", ".git", "packages", "TestResults", ".vs")

# -------------------------------
# Funkcja: pobieranie plików
# Uwaga: -Include działa prawidłowo, gdy -Path zawiera wildcard (*)
# -------------------------------
function Get-FilesRecursively {
    param([string]$path)

    $pathWithWildcard = Join-Path $path '*'

    Get-ChildItem -Path $pathWithWildcard -Recurse -File -Force -Include $extensions |
        Where-Object {
            $full = $_.FullName.ToLower()
            -not ($ignoreDirs | ForEach-Object { $full -like "*\$_\*" })
        }
}

try {
    # Zbierz pliki i posortuj po pełnej ścieżce dla stabilnego porządku
    $files = Get-FilesRecursively $SourcePath | Sort-Object FullName

    # Zapis w UTF-8 bez BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $sw = New-Object System.IO.StreamWriter($OutputFile, $false, $utf8NoBom)

    # Nagłówek snapshotu
    $sw.WriteLine("=== ProjektSnapshot.txt - {0} ===" -f (Get-Date))
    $sw.WriteLine("Plików: {0}" -f $files.Count)
    $sw.WriteLine("Ignorowane katalogi: {0}" -f ($ignoreDirs -join ", "))
    $sw.WriteLine("Rozszerzenia: {0}" -f ($extensions -join ", "))
    $sw.WriteLine(("=").PadLeft(41, "="))

    foreach ($f in $files) {
        $sw.WriteLine("=== FILE: {0} ===" -f $f.FullName)
        try {
            # -Raw: cały plik w jednym strumieniu, bez numerów linii
            $sw.WriteLine((Get-Content -LiteralPath $f.FullName -Raw))
        }
        catch {
            # Jeśli jakiś plik nie da się odczytać, logujemy to do snapshotu i lecimy dalej
            $sw.WriteLine("[ERROR] Cannot read file: {0} | {1}" -f $f.FullName, $_.Exception.Message)
        }
        $sw.WriteLine("=== END FILE: {0} ===" -f $f.FullName)
        $sw.WriteLine()
    }

    $sw.Close()
    Write-Output "[OK] Snapshot saved to $OutputFile (files: $($files.Count))"
    exit 0
}
catch {
    Write-Output "[ERROR] $($_.Exception.Message)"
    exit 1
}
