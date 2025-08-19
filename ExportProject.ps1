# ================================
# ExportProject.ps1 – eksport kodu do 1 pliku TXT
# ================================

param(
    [string]$SourcePath = "C:\Users\adaml\OneDrive\Pulpit\GrafikWPF - projekt - GPT mods",
    [string]$OutputFile = "ProjektSnapshot.txt"
)

$OutputFile = Join-Path $SourcePath $OutputFile

# Rozszerzenia do eksportu
$extensions = @("*.cs", "*.xaml", "*.csproj", "*.sln", "*.ps1", "*.json")

# Ignorowane katalogi (po pełnej ścieżce)
$ignoreDirs = @("bin", "obj", ".git", "packages", "TestResults", ".vs")

# Funkcja rekurencyjna – UWAGA: -Include działa poprawnie, gdy -Path ma wildcard (*)
function Get-FilesRecursively {
    param ($path)

    $pathWithWildcard = Join-Path $path '*'

    Get-ChildItem -Path $pathWithWildcard -Recurse -File -Include $extensions |
        Where-Object {
            $fullPath = $_.FullName.ToLower()
            -not ($ignoreDirs | ForEach-Object { $fullPath -like "*\$_\*" })
        }
}

try {
    $files = Get-FilesRecursively $SourcePath | Sort-Object FullName

    # UTF-8 bez BOM
    $sw = New-Object IO.StreamWriter($OutputFile, $false, [Text.UTF8Encoding]::new($false))
    $sw.WriteLine("=== ProjektSnapshot.txt - $(Get-Date) ===")
    $sw.WriteLine("Plików: {0}" -f $files.Count)
    $sw.WriteLine("=========================================")

    foreach ($f in $files) {
        $sw.WriteLine("=== FILE: {0} ===" -f $f.FullName)
        $sw.WriteLine((Get-Content $f.FullName -Raw))
        $sw.WriteLine("=== END FILE: {0} ===" -f $f.FullName)
        $sw.WriteLine()
    }

    $sw.Close()
    Write-Output "[OK] Snapshot saved to $OutputFile"
    exit 0
}
catch {
    Write-Output "[ERROR] $($_.Exception.Message)"
    exit 1
}
