[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^Web[A-Za-z0-9]{3,12}$')]
    [string]$Suffix,

    [string]$Server = 'localhost\SQLEXPRESS',

    [switch]$AllowIncomplete,
    [switch]$KeepEvidence,
    [switch]$RemoveRuntime,

    [ValidatePattern('^[A-Za-z][A-Za-z0-9]{3,18}$')]
    [string]$RuntimeAccountName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ((Split-Path -Leaf $repoRoot) -ne 'DB_lab' -or
    -not (Test-Path -LiteralPath (Join-Path $repoRoot '.git') -PathType Container) -or
    -not (Test-Path -LiteralPath (Join-Path $repoRoot 'AGENT.md') -PathType Leaf)) {
    throw 'Run this script only from the DB_lab checkout.'
}

if ($RemoveRuntime -and -not $RuntimeAccountName) {
    throw 'RemoveRuntime requires the exact RuntimeAccountName created by setup_web_runtime.ps1.'
}
if (-not $RemoveRuntime -and $RuntimeAccountName) {
    throw 'RuntimeAccountName is accepted only together with -RemoveRuntime.'
}

$sourceDb = "TokenHubDB_v01_$Suffix"
$v10Db = "TokenHubDB_v10_$Suffix"
$v11Db = "TokenHubDB_v11_$Suffix"
$databaseNames = @($v11Db, $v10Db, $sourceDb)

$sourceEvidence = Join-Path $repoRoot "result\source_$Suffix"
$v11Evidence = Join-Path $repoRoot "result\week6\v11\$Suffix"
$webEvidence = Join-Path $repoRoot "result\webapp\$Suffix"
$evidenceDirs = @($sourceEvidence, $v11Evidence, $webEvidence)
$backupDirectory = Join-Path $repoRoot "result\sql_backups\$Suffix"
$backupDirectoryExists = Test-Path -LiteralPath $backupDirectory -PathType Container
$manifestPath = Join-Path $webEvidence 'manifest.json'
$copyLogDir = $v11Evidence

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'sqlcmd was not found. No cleanup was performed.'
}

function Invoke-MasterQuery {
    param([Parameter(Mandatory = $true)][string]$Query)

    $output = & sqlcmd -S $Server -d master -E -C -b -h -1 -W -w 65535 -Q $Query 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd query failed. No later cleanup steps were run. Output: $($output | Out-String)"
    }
    return @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

# A completed app_prepare run writes this manifest only after the database chain is ready.
$manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
if ($manifestExists) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "The run manifest is unreadable; refusing cleanup: $manifestPath"
    }
    if ($manifest.source -ne $sourceDb -or
        $manifest.database -ne $v11Db -or
        $manifest.server -ne $Server) {
        throw "The run manifest does not match Suffix/Server. Expected $sourceDb and $v11Db on $Server."
    }
}

# Check exact database names; no wildcard database matching is used.
$existingDatabases = @()
foreach ($databaseName in $databaseNames) {
    $rows = Invoke-MasterQuery "SET NOCOUNT ON; IF DB_ID(N'$databaseName') IS NOT NULL SELECT N'EXISTS';"
    if ($rows -contains 'EXISTS') {
        $existingDatabases += $databaseName
    }
}

$existingEvidence = @($evidenceDirs | Where-Object { Test-Path -LiteralPath $_ })
$runtimeTask = $null
$runtimeUser = $null
$runtimeProfile = $null
$profileSid = $null
$runtimeFiles = @()
$runtimeTaskName = $null
$runtimeLogin = $null

if ($RemoveRuntime) {
    $runtimeTaskName = "TokenHub-$RuntimeAccountName"
    $runtimeLogin = "$env:COMPUTERNAME\$RuntimeAccountName"
    $runtimeTask = Get-ScheduledTask -TaskName $runtimeTaskName -ErrorAction SilentlyContinue
    $runtimeUser = Get-LocalUser -Name $RuntimeAccountName -ErrorAction SilentlyContinue
    if ($runtimeUser -and $runtimeUser.Description -ne 'TokenHub restricted local Web runtime') {
        throw "Local account $RuntimeAccountName is not marked as a TokenHub runtime account; refusing to remove it."
    }
    if ($runtimeUser) {
        $profileSid = $runtimeUser.SID.Value
        $runtimeProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$profileSid'" -ErrorAction Stop
        if ($runtimeProfile -and ($runtimeProfile.Special -or $runtimeProfile.Loaded)) {
            throw "The runtime account profile is special or still loaded; sign out and retry."
        }
    }
    if ($runtimeTask) {
        $taskAction = ($runtimeTask.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' '
        $expectedRunner = Join-Path $repoRoot 'tools\run_web.ps1'
        if ($taskAction -notlike "*$expectedRunner*") {
            throw "Scheduled task $runtimeTaskName does not point to this checkout; refusing to remove it."
        }
    }
    $instanceDir = Join-Path $repoRoot 'instance'
    foreach ($name in @('runtime.json', 'runtime_identity.log', 'runtime.log', 'webapp.log')) {
        $path = Join-Path $instanceDir $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $runtimeFiles += $path
        }
    }
}

# Without the completed manifest, cleanup is allowed only as an explicit partial-run cleanup.
$hasAnyRunArtifact = ($existingDatabases.Count -gt 0) -or
    ($existingEvidence.Count -gt 0) -or
    $backupDirectoryExists -or
    ($RemoveRuntime -and (($null -ne $runtimeTask) -or ($null -ne $runtimeUser) -or ($runtimeFiles.Count -gt 0)))

if (-not $manifestExists -and $hasAnyRunArtifact -and -not $AllowIncomplete) {
    throw "No completed manifest exists. If you personally started this unique suffix and want to clean its partial output, rerun with -AllowIncomplete after checking the exact database names."
}
if (-not $manifestExists -and -not $hasAnyRunArtifact) {
    Write-Output "No run artifacts found for $Suffix. Nothing to clean."
    return
}

# New runs isolate SQL backups in result/sql_backups/<RunId>; this folder is writable
# by the project user and explicitly grants Modify to the SQL Server service identity.
$resultRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'result')).TrimEnd('\') + '\'
$backupNamePattern = '^(?:' + [regex]::Escape($sourceDb) + '|' +
    [regex]::Escape($v10Db) + ')_W6_[0-9a-f]{12}\.bak$'
$backupFiles = @()

if ($backupDirectoryExists) {
    $fullBackupDirectory = [IO.Path]::GetFullPath($backupDirectory)
    if (-not $fullBackupDirectory.StartsWith($resultRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup directory escaped result/: $fullBackupDirectory"
    }
    $backupDirectoryItem = Get-Item -LiteralPath $fullBackupDirectory -Force -ErrorAction Stop
    if ($backupDirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Backup directory is a reparse point; refusing cleanup: $fullBackupDirectory"
    }
    $backupEntries = @(Get-ChildItem -LiteralPath $fullBackupDirectory -Force -ErrorAction Stop)
    foreach ($entry in $backupEntries) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Backup entry is a reparse point; refusing cleanup: $($entry.FullName)"
        }
        if ($entry.PSIsContainer -or $entry.Name -notmatch $backupNamePattern) {
            throw "Unexpected item in this run's SQL backup directory; refusing cleanup: $($entry.FullName)"
        }
        $backupFiles += $entry.FullName
    }

    # The path records are also checked: they must point into this exact RunId folder.
    foreach ($logName in @('copy_v01_to_v10.txt', 'copy_v10_to_v11.txt')) {
        $pathRecord = Join-Path $copyLogDir ($logName -replace '\.txt$', '.backup_path.txt')
        if (Test-Path -LiteralPath $pathRecord -PathType Leaf) {
            $recordedPath = (Get-Content -LiteralPath $pathRecord -Raw -Encoding UTF8).Trim()
            if (-not [IO.Path]::IsPathRooted($recordedPath) -or
                -not ([IO.Path]::GetFullPath($recordedPath)).StartsWith(
                    $fullBackupDirectory.TrimEnd('\') + '\',
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                (Split-Path -Leaf $recordedPath) -notmatch $backupNamePattern) {
                throw "Backup path record does not belong to RunId $($Suffix): $pathRecord"
            }
        }
    }
}
else {
    # Legacy batches wrote .bak files to SQL Server's protected default backup folder.
    # Logged paths are authoritative for this RunId. msdb history can contain older
    # backups for the same database name, so accept only this RunId's exact filename pattern.
    $recordedBackupCandidates = @()
    foreach ($logName in @('copy_v01_to_v10.txt', 'copy_v10_to_v11.txt')) {
        $logPath = Join-Path $copyLogDir $logName
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            foreach ($line in Get-Content -LiteralPath $logPath -Encoding UTF8) {
                if ($line -match '^backup=(.+)$') {
                    $recordedBackupCandidates += $Matches[1].Trim()
                }
            }
        }
        $pathRecord = Join-Path $copyLogDir ($logName -replace '\.txt$', '.backup_path.txt')
        if (Test-Path -LiteralPath $pathRecord -PathType Leaf) {
            $recordedBackupCandidates += (Get-Content -LiteralPath $pathRecord -Raw -Encoding UTF8).Trim()
        }
    }

    $historyQuery = @"
SET NOCOUNT ON;
SELECT DISTINCT CONVERT(NVARCHAR(4000), mf.physical_device_name)
FROM msdb.dbo.backupset AS bs
INNER JOIN msdb.dbo.backupmediafamily AS mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name IN (N'$sourceDb', N'$v10Db') AND bs.type = 'D';
"@
    $historyCandidates = @()
    try {
        $historyCandidates = @(Invoke-MasterQuery $historyQuery)
    }
    catch {
        if ($recordedBackupCandidates.Count -eq 0) {
            throw 'Cannot inspect legacy SQL backup history; no cleanup was performed.'
        }
        Write-Warning 'Using only the exact legacy backup paths recorded in this run''s logs.'
    }

    # Ignore unrelated historical backup names (including removed probe files); never
    # let them broaden this RunId's cleanup scope. Logged paths remain strictly validated.
    $matchingHistoryCandidates = @($historyCandidates | Where-Object {
        $_ -and [IO.Path]::IsPathRooted($_) -and
        (Split-Path -Leaf $_) -match $backupNamePattern
    })
    $backupPathSet = @(
        @($recordedBackupCandidates) + @($matchingHistoryCandidates) |
            Where-Object { $_ } | Sort-Object -Unique
    )
    if ($backupPathSet.Count -gt 0) {
        $backupRootRows = Invoke-MasterQuery "SET NOCOUNT ON; SELECT CONVERT(NVARCHAR(4000), SERVERPROPERTY('InstanceDefaultBackupPath'));"
        $backupRootText = @($backupRootRows | Where-Object { $_ -and $_ -ne 'NULL' } | Select-Object -Last 1)
        if ($backupRootText.Count -eq 0) {
            throw 'SQL Server did not return InstanceDefaultBackupPath; refusing legacy backup cleanup.'
        }
        $backupRoot = [IO.Path]::GetFullPath($backupRootText[0].Trim()).TrimEnd('\')
        try {
            [void](Get-Item -LiteralPath $backupRoot -Force -ErrorAction Stop)
        }
        catch [System.UnauthorizedAccessException] {
            throw "Legacy backup directory is inaccessible: $backupRoot. Run the exact legacy cleanup once from elevated PowerShell; new runs no longer use this directory."
        }

        foreach ($candidate in $backupPathSet) {
            if (-not [IO.Path]::IsPathRooted($candidate)) {
                throw "Legacy backup path is not absolute; refusing cleanup: $candidate"
            }
            $fullPath = [IO.Path]::GetFullPath($candidate)
            if ((Split-Path -Leaf $fullPath) -notmatch $backupNamePattern) {
                throw "Recorded backup filename does not match this RunId; refusing cleanup: $fullPath"
            }
            $parent = [IO.Path]::GetFullPath((Split-Path -Parent $fullPath)).TrimEnd('\')
            if (-not $parent.Equals($backupRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Legacy backup path is outside SQL Server's default backup folder: $fullPath"
            }
            try {
                $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            }
            catch [System.Management.Automation.ItemNotFoundException] {
                continue
            }
            catch [System.UnauthorizedAccessException] {
                throw "Legacy backup file is inaccessible: $fullPath. Run the exact legacy cleanup once from elevated PowerShell."
            }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Legacy backup path is a reparse point; refusing to delete: $fullPath"
            }
            $backupFiles += $fullPath
        }
    }
}
$backupFiles = @($backupFiles | Sort-Object -Unique)
# Validate every output directory stays inside result/ and is not a junction/symlink.
$resultRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'result')).TrimEnd('\') + '\'
if (-not $KeepEvidence) {
    foreach ($path in $existingEvidence) {
        $fullPath = [IO.Path]::GetFullPath($path)
        if (-not $fullPath.StartsWith($resultRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Evidence path escaped result/: $fullPath"
        }
        $item = Get-Item -LiteralPath $fullPath -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Evidence directory is a reparse point; refusing to delete: $fullPath"
        }
        $nestedLinks = @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
        if ($nestedLinks.Count -gt 0) {
            throw "Evidence directory contains a reparse point; refusing recursive deletion: $fullPath"
        }
    }
}

# Cache directories are disposable and reproducible; the virtual environment and Git data are excluded.
$cacheNames = @('__pycache__', '.ruff_cache', '.pytest_cache', '.mypy_cache')
function Find-ProjectCaches {
    param([Parameter(Mandatory = $true)][string]$Path)

    $found = @()
    foreach ($directory in Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue) {
        if ($directory.Name -in @('.git', '.venv', 'instance')) {
            continue
        }
        if ($directory.Name -in $cacheNames) {
            $found += $directory
            continue
        }
        $found += Find-ProjectCaches -Path $directory.FullName
    }
    return $found
}
$cacheDirs = @(Find-ProjectCaches -Path $repoRoot)

# Print the full inventory before the single confirmation/WhatIf gate.
Write-Output "Run suffix: $Suffix"
Write-Output "SQL Server: $Server"
Write-Output 'Databases to drop:'
if ($existingDatabases.Count -eq 0) { Write-Output '  (none)' }
foreach ($name in $existingDatabases) { Write-Output "  $name" }
Write-Output 'Run-specific SQL backup directory to delete:'
if ($backupDirectoryExists) { Write-Output "  $backupDirectory" } else { Write-Output '  (none)' }
Write-Output 'SQL backup files to delete:'
if ($backupFiles.Count -eq 0) { Write-Output '  (none)' }
foreach ($path in $backupFiles) { Write-Output "  $path" }
if ($KeepEvidence) {
    Write-Output 'Evidence directories: KEEP'
}
else {
    Write-Output 'Evidence directories to delete:'
    if ($existingEvidence.Count -eq 0) { Write-Output '  (none)' }
    foreach ($path in $existingEvidence) { Write-Output "  $path" }
}
Write-Output 'Cache directories to delete:'
if ($cacheDirs.Count -eq 0) { Write-Output '  (none)' }
foreach ($directory in $cacheDirs) { Write-Output "  $($directory.FullName)" }

if ($RemoveRuntime) {
    Write-Output "Runtime task/account/login/profile to remove: $runtimeTaskName / $runtimeLogin / $RuntimeAccountName"
    if ($runtimeProfile) { Write-Output "  Profile: $($runtimeProfile.LocalPath)" }
    Write-Output 'Runtime files to delete (file contents are never read):'
    foreach ($path in $runtimeFiles) { Write-Output "  $path" }
}

$action = 'drop this run''s databases, delete its SQL backups, evidence and caches'
if ($RemoveRuntime) { $action += ', and remove the explicitly named local runtime account/profile/task/login and instance files' }
if ($KeepEvidence) { $action = $action.Replace(' evidence', ' (keep evidence)')
}
if (-not $PSCmdlet.ShouldProcess("Run $Suffix on $Server", $action)) {
    return
}

# Stop the dedicated Web task before dropping its database.
if ($RemoveRuntime -and $runtimeTask) {
    if ($runtimeTask.State -eq 'Running') {
        Stop-ScheduledTask -InputObject $runtimeTask -ErrorAction Stop
    }
    Unregister-ScheduledTask -TaskName $runtimeTaskName -Confirm:$false -ErrorAction Stop
}

foreach ($databaseName in $databaseNames) {
    if ($existingDatabases -contains $databaseName) {
        $quotedName = '[' + $databaseName.Replace(']', ']]') + ']'
        $dropSql = "SET NOCOUNT ON; IF DB_ID(N'$databaseName') IS NOT NULL BEGIN ALTER DATABASE $quotedName SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $quotedName; END;"
        [void](Invoke-MasterQuery $dropSql)
        $check = Invoke-MasterQuery "SET NOCOUNT ON; IF DB_ID(N'$databaseName') IS NOT NULL SELECT N'STILL_EXISTS';"
        if ($check -contains 'STILL_EXISTS') {
            throw "Database still exists after DROP: $databaseName"
        }
        Write-Output "Dropped and verified absent: $databaseName"
    }
}

foreach ($path in $backupFiles) {
    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $path) {
        throw "Backup file still exists after deletion: $path"
    }
    Write-Output "Deleted backup: $path"
}
if ($backupDirectoryExists) {
    $remainingBackupEntries = @(Get-ChildItem -LiteralPath $backupDirectory -Force -ErrorAction Stop)
    if ($remainingBackupEntries.Count -gt 0) {
        throw "Unexpected files remain in the run backup directory: $backupDirectory"
    }
    Remove-Item -LiteralPath $backupDirectory -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $backupDirectory) {
        throw "Backup directory still exists after deletion: $backupDirectory"
    }
    Write-Output "Deleted run backup directory: $backupDirectory"
}

if ($RemoveRuntime) {
    $loginLiteral = $runtimeLogin.Replace("'", "''")
    $loginQuoted = '[' + $runtimeLogin.Replace(']', ']]') + ']'
    $dropLogin = "SET NOCOUNT ON; IF SUSER_ID(N'$loginLiteral') IS NOT NULL DROP LOGIN $loginQuoted;"
    [void](Invoke-MasterQuery $dropLogin)

    if ($runtimeProfile) {
        Remove-CimInstance -InputObject $runtimeProfile -ErrorAction Stop
    }
    if ($runtimeUser) {
        . (Join-Path $PSScriptRoot 'batch_logon_right.ps1')
        Set-BatchLogonRight -Sid $runtimeUser.SID.Value -Revoke
        Remove-LocalUser -Name $RuntimeAccountName -ErrorAction Stop
    }

    foreach ($path in $runtimeFiles) {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    }
    $instanceDir = Join-Path $repoRoot 'instance'
    if ((Test-Path -LiteralPath $instanceDir -PathType Container) -and
        @(Get-ChildItem -LiteralPath $instanceDir -Force).Count -eq 0) {
        Remove-Item -LiteralPath $instanceDir -Force
    }
}

foreach ($directory in ($cacheDirs | Sort-Object { $_.FullName.Length } -Descending)) {
    if (Test-Path -LiteralPath $directory.FullName -PathType Container) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Cache directory is a reparse point; refusing to delete: $($directory.FullName)"
        }
        Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction Stop
    }
}

if (-not $KeepEvidence) {
    foreach ($path in $existingEvidence) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $path) {
            throw "Evidence directory still exists after deletion: $path"
        }
    }
}

foreach ($databaseName in $databaseNames) {
    $check = Invoke-MasterQuery "SET NOCOUNT ON; IF DB_ID(N'$databaseName') IS NOT NULL SELECT N'STILL_EXISTS';"
    if ($check -contains 'STILL_EXISTS') {
        throw "Final verification failed; database remains: $databaseName"
    }
}
foreach ($path in $backupFiles) {
    if (Test-Path -LiteralPath $path) {
        throw "Final verification failed; backup remains: $path"
    }
}
if (Test-Path -LiteralPath $backupDirectory) {
    throw "Final verification failed; run backup directory remains: $backupDirectory"
}
if (-not $KeepEvidence) {
    foreach ($path in $evidenceDirs) {
        if (Test-Path -LiteralPath $path) {
            throw "Final verification failed; evidence directory remains: $path"
        }
    }
}
$remainingCaches = @(Find-ProjectCaches -Path $repoRoot)
if ($remainingCaches.Count -gt 0) {
    throw 'Final verification failed; disposable cache directories remain.'
}
if ($RemoveRuntime) {
    if (Get-ScheduledTask -TaskName $runtimeTaskName -ErrorAction SilentlyContinue) {
        throw "Final verification failed; scheduled task remains: $runtimeTaskName"
    }
    if (Get-LocalUser -Name $RuntimeAccountName -ErrorAction SilentlyContinue) {
        throw "Final verification failed; local account remains: $RuntimeAccountName"
    }
    if ($profileSid) {
        $remainingProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$profileSid'" -ErrorAction Stop
        if ($remainingProfile) { throw 'Final verification failed; local runtime profile remains.' }
    }
    $loginCheck = Invoke-MasterQuery "SET NOCOUNT ON; IF SUSER_ID(N'$($runtimeLogin.Replace("'", "''"))') IS NOT NULL SELECT N'STILL_EXISTS';"
    if ($loginCheck -contains 'STILL_EXISTS') { throw "Final verification failed; SQL login remains: $runtimeLogin" }
    foreach ($path in $runtimeFiles) {
        if (Test-Path -LiteralPath $path) { throw "Final verification failed; runtime file remains: $path" }
    }
}

Write-Output "Cleanup verification PASS for $Suffix."
if ($KeepEvidence) {
    Write-Output 'Evidence was intentionally retained; all run databases/backups and disposable caches were removed.'
}
