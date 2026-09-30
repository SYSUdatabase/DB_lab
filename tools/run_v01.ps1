param(
    [string]$Server = 'localhost\SQLEXPRESS',
    [ValidatePattern('^TokenHubDB_v01(?:_[A-Za-z0-9]+)?$')]
    [string]$DatabaseName = 'TokenHubDB_v01_A',
    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string]$RunLabel = 'run_A'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "result/$RunLabel"
if (Test-Path -LiteralPath $outDir) {
    throw "Result directory already exists; choose a new RunLabel: $RunLabel"
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$files = @('00_create_database.sql','01_create_tables.sql','02_insert_data.sql',
           '03_crud_demo.sql','query.sql','view.sql','constraint.sql','role.sql','verify.sql')
foreach ($name in $files) {
    $inputFile = Join-Path $repoRoot "sql/$name"
    if (-not (Test-Path -LiteralPath $inputFile)) { throw "Missing script: $inputFile" }
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'sql/signature.sql'))) {
    throw 'Missing script: sql/signature.sql'
}
Start-Transcript -Path (Join-Path $outDir 'console.log') | Out-Null
try {
    foreach ($name in $files) {
        $inputFile = Join-Path $repoRoot "sql/$name"
        $logFile = Join-Path $outDir "$name.log"
        & sqlcmd -S $Server -d master -E -C -b -r 1 -f 65001 -u `
          -v "DatabaseName=$DatabaseName" -i $inputFile -o $logFile
        if ($LASTEXITCODE -ne 0) {
            throw "FAILED $name; see $logFile and console.log"
        }
        Write-Output "PASS $name"
    }
    $signature = Join-Path $outDir 'signature.txt'
    & sqlcmd -S $Server -d $DatabaseName -E -C -b -f 65001 -u -h -1 -W `
      -i (Join-Path $repoRoot 'sql/signature.sql') -o $signature
    if ($LASTEXITCODE -ne 0) { throw 'FAILED signature.sql' }
    Write-Output "PASS signature.sql"
    Write-Output "PASS v0.1 $DatabaseName"
}
finally {
    Stop-Transcript | Out-Null
}
