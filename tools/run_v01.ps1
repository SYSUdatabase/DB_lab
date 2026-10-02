param(
    [string]$Server = 'localhost\SQLEXPRESS',
    [ValidatePattern('^TokenHubDB_v01(?:_[A-Za-z0-9]+)?$')]
    [string]$DatabaseName = ('TokenHubDB_v01_' + [guid]::NewGuid().ToString('N').Substring(0,12)),
    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string]$RunLabel = ('run_' + [guid]::NewGuid().ToString('N').Substring(0,12)),
    [switch]$DropExisting
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "result/$RunLabel"
if (Test-Path -LiteralPath $outDir) {
    throw "Result directory already exists; choose a new RunLabel: $RunLabel"
}
if ($DropExisting) {
    $dropSql = "IF DB_ID(N'$DatabaseName') IS NOT NULL BEGIN ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$DatabaseName]; END"
    & sqlcmd -S $Server -d master -E -C -b -f 65001 -Q $dropSql
    if ($LASTEXITCODE -ne 0) { throw "FAILED to drop $DatabaseName" }
}
$files = @('00_create_database.sql','01_create_tables.sql','02_insert_data.sql',
           '03_crud_demo.sql','view.sql','query.sql','constraint.sql','role.sql','verify.sql')
foreach ($name in $files) {
    $inputFile = Join-Path $repoRoot "sql/$name"
    if (-not (Test-Path -LiteralPath $inputFile)) { throw "Missing script: $inputFile" }
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'sql/signature.sql'))) {
    throw 'Missing script: sql/signature.sql'
}
Get-Command sqlcmd -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path $outDir | Out-Null
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
    $rawSignature = & sqlcmd -S $Server -d $DatabaseName -E -C -b -f 65001 -h -1 -W `
      -v "DatabaseName=$DatabaseName" `
      -i (Join-Path $repoRoot 'sql/signature.sql')
    if ($LASTEXITCODE -ne 0) { throw 'FAILED signature.sql' }
    $rawSignature | Where-Object { $_ -match '^[A-Za-z_]+\|\d+\|[0-9A-F]{64}$' } |
      Set-Content -LiteralPath $signature -Encoding utf8
    $sigLines = (Get-Content -LiteralPath $signature | Measure-Object -Line).Lines
    if ($sigLines -ne 14) { throw "signature.sql returned $sigLines signature lines, expected 14" }
    Write-Output "PASS signature.sql"
    Write-Output "PASS v0.1 $DatabaseName"
}
finally {
    Stop-Transcript | Out-Null
}
