# Rebuild pre-week6 code, migrate a RESTORED COPY, and verify it.
# Only creates new databases/paths. Never drops or overwrites existing data.
[CmdletBinding()]
param(
    [string]$Server = 'localhost\SQLEXPRESS',
    [ValidatePattern('^[A-Za-z][A-Za-z0-9]{5,15}$')]
    [string]$Suffix = ('R' + [guid]::NewGuid().ToString('N').Substring(0,11))
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$archive = Join-Path $root 'archive\week6-pre-migration\DB_lab_pre_week6_c8d4e64_full_source.zip'
$expectedHash = 'D2DFA2F23504050ACBA3F4BDE95A7946DCA72D29F6599A6D75A67C16DDE5743C'
$work = Join-Path (Split-Path $root -Parent) "DB_lab_replay_$Suffix"
$evidence = Join-Path $root "result\week6\reproduction\$Suffix"
$sourceDb = "TokenHubDB_v01_$Suffix"
$targetDb = "TokenHubDB_v10_$Suffix"
$oldTargetLiteral = 'TokenHubDB_v10_W6_20261014'
$oldSourceLiteral = 'TokenHubDB_v01_A'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-Metadata([string]$query) {
    $output = @(& sqlcmd -S $Server -d master -E -C -b -W -h -1 -f 65001 -Q $query)
    if ($LASTEXITCODE -ne 0) { throw "SQL metadata failed: $query" }
    return @($output | Where-Object { $_ -and $_.Trim() })
}
function Invoke-File([string]$database, [string]$file, [string]$log) {
    if (Test-Path -LiteralPath $log) { throw "Refusing to overwrite: $log" }
    & sqlcmd -S $Server -d $database -E -C -b -r 1 -f 65001 -i $file -o $log
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $file; inspect $log" }
}
function Invoke-Baseline([string]$database, [string]$file) {
    if (Test-Path -LiteralPath $file) { throw "Refusing to overwrite: $file" }
    & sqlcmd -S $Server -d $database -E -C -b -f 65001 -u -h -1 -W -w 65535 -i (Join-Path $root 'week6\baseline.sql') -o $file
    if ($LASTEXITCODE -ne 0) { throw "Business baseline failed for $database" }
}
function Write-Text([string]$path, [string]$content) {
    if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite: $path" }
    [IO.File]::WriteAllText($path, $content, $utf8)
}

if (-not(Test-Path -LiteralPath $archive)) { throw "Pre-week6 source snapshot is missing" }
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
    throw "Pre-week6 source archive hash does not match the verified historical snapshot"
}
foreach ($path in @($work, $evidence)) {
    if (Test-Path -LiteralPath $path) { throw "Replay path already exists: $path" }
}
$free = Invoke-Metadata "SET NOCOUNT ON; SELECT CASE WHEN DB_ID(N'$sourceDb') IS NULL AND DB_ID(N'$targetDb') IS NULL THEN 'FREE' ELSE 'IN_USE' END;"
if ($free -notcontains 'FREE') { throw "Replay database names must be new" }
$backupDir = @(Invoke-Metadata "SET NOCOUNT ON; SELECT CONVERT(nvarchar(400),SERVERPROPERTY('InstanceDefaultBackupPath'));")
$dataDir = @(Invoke-Metadata "SET NOCOUNT ON; SELECT CONVERT(nvarchar(400),SERVERPROPERTY('InstanceDefaultDataPath'));")
if ($backupDir.Count -ne 1 -or $dataDir.Count -ne 1) {
    throw "Cannot determine SQL Server default backup/data directory"
}
$bak = Join-Path $backupDir[0].Trim() "$($sourceDb)_w6_replay.bak"
$data = Join-Path $dataDir[0].Trim() "$($targetDb).mdf"
$logdata = Join-Path $dataDir[0].Trim() "$($targetDb)_log.ldf"
foreach ($p in @($bak, $data, $logdata)) {
    if (Test-Path -LiteralPath $p) { throw "Refusing to overwrite SQL Server file: $p" }
}

New-Item -ItemType Directory -Path $evidence | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $work -ErrorAction Stop
if (@(Get-ChildItem -LiteralPath $work -Recurse -File).Count -ne 344) {
    throw "Historical code extraction did not restore all 344 files"
}
Write-Output "PASS extracted 344 historical source files into $work"

# Run only the historical code on a NEW source DB, never -DropExisting.
$originalRunner = Join-Path $work 'tools\run_v01.ps1'
$originalLabel = "w6replay$Suffix"
& $originalRunner -Server $Server -DatabaseName $sourceDb -RunLabel $originalLabel |
    Tee-Object -FilePath (Join-Path $evidence 'historical_bootstrap.log')
if (-not (Test-Path -LiteralPath (Join-Path $work "result\$originalLabel\signature.txt"))) {
    throw "Historical v0.1 bootstrap did not write its 14-table signature"
}
$viewCount = @(Invoke-Metadata "SET NOCOUNT ON; SELECT COUNT(*) FROM [$sourceDb].sys.views WHERE is_ms_shipped=0;")
if ($viewCount -notcontains '10') { throw "Historical code did not create canonical 10 views" }
Write-Output 'PASS canonical pre-week6 v0.1 reconstructed and verified'

# Backup and restore the REBUILT source to another NEW database.
# SQL names are generated from the validated suffix; filesystem paths are quoted.
$escape = { param($v) $v.Replace("'", "''") }
$copySQL = @"
:on error exit
SET NOCOUNT ON;
IF DB_ID(N'$sourceDb') IS NULL OR DB_ID(N'$targetDb') IS NOT NULL
 THROW 52300,'Invalid or occupied replay database',1;
GO
BACKUP DATABASE [$sourceDb] TO DISK=N'$(& $escape $bak)'
 WITH COPY_ONLY,CHECKSUM,STATS=10;
GO
RESTORE VERIFYONLY FROM DISK=N'$(& $escape $bak)' WITH CHECKSUM;
GO
RESTORE DATABASE [$targetDb] FROM DISK=N'$(& $escape $bak)'
 WITH MOVE N'$sourceDb' TO N'$(& $escape $data)',
 MOVE N'$($sourceDb)_log' TO N'$(& $escape $logdata)',
 RECOVERY,CHECKSUM,STATS=10;
GO
IF DB_ID(N'$targetDb') IS NULL THROW 52301,'Replay restore missing',1;
PRINT 'PASS new v0.1 replay database safely restored';
GO
"@
$copyFile = Join-Path $evidence 'copy_replay.sql'
Write-Text $copyFile $copySQL
Invoke-File master $copyFile (Join-Path $evidence 'copy_replay.log')
Invoke-Baseline $sourceDb (Join-Path $evidence 'source_before.txt')
Invoke-Baseline $targetDb (Join-Path $evidence 'copy_before.txt')
$srcHash = (Get-FileHash (Join-Path $evidence 'source_before.txt') -Algorithm SHA256).Hash
$dstHash = (Get-FileHash (Join-Path $evidence 'copy_before.txt') -Algorithm SHA256).Hash
if ($srcHash -ne $dstHash) { throw "Newly restored copy differs from historical source" }
Write-Output "PASS v0.1 source/copy hash identical: $srcHash"

# Create run-specific SQL copies; do not edit the original migration or regression.
$migrationTemplate = [IO.File]::ReadAllText((Join-Path $root 'sql\migration.sql'))
if (-not($migrationTemplate.Contains($oldTargetLiteral))) { throw "Migration guard changed; review template" }
$migration = $migrationTemplate.Replace($oldTargetLiteral, $targetDb)
$migrationFile = Join-Path $evidence 'migration_replay.sql'
Write-Text $migrationFile $migration
Invoke-File $targetDb $migrationFile (Join-Path $evidence 'migration_replay.log')

$regression = [IO.File]::ReadAllText((Join-Path $root 'sql\regression.sql'))
$oldViewCheck = '(SELECT COUNT(*) FROM TokenHubDB_v01_A.sys.views WHERE is_ms_shipped=0)<>9'
if (-not($regression.Contains($oldViewCheck))) { throw "Regression legacy source check changed; review template" }
$regression = $regression.Replace($oldViewCheck,
    '(SELECT COUNT(*) FROM TokenHubDB_v01_A.sys.views WHERE is_ms_shipped=0)<>10')
$regression = $regression.Replace($oldTargetLiteral, $targetDb).Replace($oldSourceLiteral, $sourceDb)
$regressionFile = Join-Path $evidence 'regression_replay.sql'
Write-Text $regressionFile $regression
Invoke-File $targetDb $regressionFile (Join-Path $evidence 'regression_replay.log')

$verify = [IO.File]::ReadAllText((Join-Path $root 'week6\verify_v10.sql'))
if (-not($verify.Contains($oldTargetLiteral))) { throw "VFY target template missing" }
$verify = $verify.Replace($oldTargetLiteral, $targetDb)
$verifyFile = Join-Path $evidence 'verify_replay.sql'
Write-Text $verifyFile $verify
Invoke-File $targetDb $verifyFile (Join-Path $evidence 'verify_replay.log')
if (-not([IO.File]::ReadAllText((Join-Path $evidence 'verify_replay.log')).Contains(
    'PASS v1.0 adapted VFY01-VFY14 verification'))) {
    throw 'Full VFY01-VFY14 marker is missing'
}
Invoke-Baseline $targetDb (Join-Path $evidence 'copy_after.txt')
$oldRows = @(Get-Content -LiteralPath (Join-Path $evidence 'copy_before.txt') -Encoding Unicode |
    Where-Object {$_ -notmatch '^PERMISSION\|'})
$newRows = @(Get-Content -LiteralPath (Join-Path $evidence 'copy_after.txt') -Encoding Unicode |
    Where-Object {$_ -notmatch '^PERMISSION\|'})
$diff = @(Compare-Object -ReferenceObject $oldRows -DifferenceObject $newRows)
if ($diff.Count -ne 0) { throw "Business rows changed during normalization: $($diff.Count)" }
if ($oldRows.Count -ne 3763) { throw "Expected 3763 business baseline lines; got $($oldRows.Count)" }
$manifest = @(
    "pre_week6_git_commit=c8d4e64"
    "source_archive_sha256=$expectedHash"
    "source_database=$sourceDb"
    "migration_copy=$targetDb"
    "reconstructed_source_baseline_sha256=$srcHash"
    "business_rows=$($oldRows.Count)"
    "business_differences=$($diff.Count)"
    "regression=R01-R12 PASS"
    "full_vfy=VFY01-VFY14 PASS"
    "legacy_code_worktree=$work"
) -join [Environment]::NewLine
Write-Text (Join-Path $evidence 'replay_manifest.txt') ($manifest + [Environment]::NewLine)
Write-Output "PASS week6 full replay: v0.1 code -> isolated v1.0 migration -> R01-R12 -> VFY01-VFY14"
Write-Output "PASS $($oldRows.Count) business records with zero differences"
Write-Output "Evidence: $evidence"
