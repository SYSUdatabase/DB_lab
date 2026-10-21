param(
    [ValidatePattern('^TokenHubDB_v11_Web[A-Za-z0-9]{3,12}$')]
    [Parameter(Mandatory=$true)][string]$DatabaseName,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9]{3,18}$')][string]$AccountName = 'TokenHubWeb',
    [string]$Server = 'localhost\SQLEXPRESS',
    [int]$Port = 5050
)
$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this setup script in an elevated PowerShell. It creates the dedicated ordinary service account.'
}
$root = Split-Path -Parent $PSScriptRoot
$instance = Join-Path $root 'instance'
$configFile = Join-Path $instance 'runtime.json'
$taskName = "TokenHub-$AccountName"
if ((Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $configFile) -or (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    throw 'Account, runtime configuration or scheduled task already exists; choose a fresh account and project directory.'
}
# Account password exists only in this process and the Windows task credential store.
function Get-RandomSecret([int]$Count) {
    $bytes = New-Object byte[] $Count
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
    return [Convert]::ToBase64String($bytes)
}
$plain = (Get-RandomSecret 36) + 'aA9!'
$secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
$account = New-LocalUser -Name $AccountName -Password $secure -Description 'TokenHub restricted local Web runtime' -PasswordNeverExpires -UserMayNotChangePassword
$fullName = "$env:COMPUTERNAME\$AccountName"
$sid = $account.SID.Value
$setupSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
New-Item -ItemType Directory -Force -Path $instance | Out-Null
$secret = Get-RandomSecret 48
@{ database=$DatabaseName; server=$Server; secret=$secret; port=$Port; account=$fullName } | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $configFile
# Grant only traverse/read on the checkout; mutable application files stay in instance.
& icacls $root /grant "*${sid}:(OI)(CI)RX" /T /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot grant runtime checkout read access' }
& icacls $instance /inheritance:r /grant:r "*${sid}:(OI)(CI)M" "*${setupSid}:(OI)(CI)F" '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' /T /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict instance directory permissions' }
$login = $fullName.Replace(']',']]')
$sql = "IF SUSER_ID(N'$fullName') IS NOT NULL THROW 55009,'Runtime login already exists',1; CREATE LOGIN [$login] FROM WINDOWS; USE [$DatabaseName]; CREATE USER [$login] FOR LOGIN [$login]; ALTER ROLE app_runtime ADD MEMBER [$login];"
& sqlcmd -S $Server -d master -E -C -b -Q $sql
if ($LASTEXITCODE -ne 0) { throw 'SQL runtime login setup failed; keep account and inspect the failure before retrying' }
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\run_web.ps1`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User $fullName -Password $plain -RunLevel Limited | Out-Null
$plain = $null
Start-ScheduledTask -TaskName $taskName
Write-Output "Configured restricted runtime $fullName. Open http://127.0.0.1:$Port . Verify tools/runtime_identity.py under this account before final acceptance."
