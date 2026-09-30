$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$targetDir = Join-Path $repoRoot 'sql'
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
$names = @('00_create_database.sql', '01_create_tables.sql',
           '02_insert_data.sql', '03_crud_demo.sql')
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($name in $names) {
    $source = Join-Path $repoRoot "week3/sql/$name"
    $content = [System.IO.File]::ReadAllText($source)
    if (-not $content.Contains('TokenHubDB_Week3')) {
        throw "Source does not contain expected database name: $source"
    }
    $converted = $content.Replace('TokenHubDB_Week3', '$(DatabaseName)')
    [System.IO.File]::WriteAllText((Join-Path $targetDir $name), $converted, $utf8)
    Write-Output "PREPARED $name"
}
