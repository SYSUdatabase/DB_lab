param([string]$Python)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Python) { $Python = Join-Path $repoRoot '.venv/Scripts/python.exe' }
if (-not (Test-Path -LiteralPath $Python)) { throw 'Create the repository venv first; see README.' }
# 正式样例只由当前生成器生成，不再从历史脚本覆盖。
Push-Location $repoRoot
try {
    & $Python -m tools.datagen
    if ($LASTEXITCODE -ne 0) { throw 'Dataset generation failed' }
}
finally { Pop-Location }
