$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'instance/runtime.json') | ConvertFrom-Json
$env:DB_LAB_APP_DATABASE = $config.database
$env:DB_LAB_SERVER = $config.server
$env:DB_LAB_SECRET = $config.secret
$env:DB_LAB_PORT = [string]$config.port
Remove-Item Env:DB_LAB_PREVIEW -ErrorAction SilentlyContinue
# Windows PowerShell 5.1 turns redirected native stderr (Flask/Waitress logging) into terminating errors under 'Stop'; rely on exit codes instead.
$ErrorActionPreference = 'Continue'
& (Join-Path $root '.venv/Scripts/python.exe') (Join-Path $root 'tools/runtime_identity.py') *> (Join-Path $root 'instance/runtime_identity.log')
if ($LASTEXITCODE -ne 0) { throw 'Actual Windows runtime identity verification failed; inspect instance/runtime_identity.log' }
& (Join-Path $root '.venv/Scripts/python.exe') -m webapp *> (Join-Path $root 'instance/runtime.log')
exit $LASTEXITCODE
