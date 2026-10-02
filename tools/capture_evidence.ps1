param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$SqlFile,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Database = 'TokenHubDB_v01_FinalA',
    [string]$CompareDatabase = 'TokenHubDB_v01_FinalB',
    [string]$Server = 'localhost\SQLEXPRESS',
    [string]$LogFile
)
$ErrorActionPreference = 'Stop'
$absSql = (Resolve-Path -LiteralPath $SqlFile).Path
$absOut = [IO.Path]::GetFullPath($Output)
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $LogFile) {
    $LogFile = Join-Path $repoRoot ('result/evidence_logs/' + [IO.Path]::GetFileNameWithoutExtension($absSql) + '.log')
}
$absLog = [IO.Path]::GetFullPath($LogFile)
if (Test-Path -LiteralPath $absLog) { throw "Evidence log exists: $absLog" }
if (Test-Path -LiteralPath $absOut) { throw "Evidence image exists: $absOut" }
New-Item -ItemType Directory -Path (Split-Path -Parent $absLog),(Split-Path -Parent $absOut) -Force | Out-Null
# 直接传参数；未预期 SQL 错误必须中止，禁止把报错输出截图当作 PASS。
& sqlcmd -S $Server -d $Database -E -C -b -f 65001 -u -W -w 160 `
    -v "DatabaseName=$Database" "CompareDatabase=$CompareDatabase" -i $absSql -o $absLog
if ($LASTEXITCODE -ne 0) { throw "Evidence SQL failed; see $absLog" }
$lines = @(Get-Content -LiteralPath $absLog -Encoding Unicode)
if ($lines.Count -eq 0) { throw 'Empty evidence output' }
if (@($lines | Select-String -Pattern '\bFAIL\b|\bDIFF\b').Count -gt 0) { throw 'Evidence assertion failed' }
if (@($lines | Select-String -Pattern '\bPASS\b|\bMATCH\b').Count -eq 0) { throw 'Evidence has no successful assertion' }
# 分页截取实际 WinForms 输出控件；日志另存，固定字号以保留最终 PASS。
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$wrapped = New-Object 'System.Collections.Generic.List[string]'
foreach ($line in $lines) {
    if ($line.Length -eq 0) { $wrapped.Add(''); continue }
    for ($offset=0; $offset -lt $line.Length; $offset+=150) {
        $wrapped.Add($line.Substring($offset,[Math]::Min(150,$line.Length-$offset)))
    }
}
$pages = [int][Math]::Ceiling($wrapped.Count / 40.0)
for ($page=0; $page -lt $pages; $page++) {
    $target = $absOut
    if ($pages -gt 1) {
        $target = Join-Path (Split-Path -Parent $absOut) `
            ([IO.Path]::GetFileNameWithoutExtension($absOut) + ('_p{0:D2}' -f ($page+1)) + '.png')
    }
    if (Test-Path -LiteralPath $target) { throw "Image exists: $target" }
    $form = New-Object System.Windows.Forms.Form
    $form.Size = New-Object System.Drawing.Size(1536,1050)
    $form.Text = $Title
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(-30000,-30000)
    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.WordWrap = $false
    $box.Dock = 'Fill'
    $box.Font = New-Object System.Drawing.Font('Consolas',12)
    $box.BackColor = [System.Drawing.Color]::FromArgb(18,18,18)
    $box.ForeColor = [System.Drawing.Color]::White
    $header = @($Title,"Database: $Database  Server: $Server",("Actual sqlcmd output; page {0}/{1}" -f ($page+1),$pages),'')
    $first = $page*40
    $last = [Math]::Min($first+39,$wrapped.Count-1)
    $box.Lines = @($header) + @($wrapped.GetRange($first,$last-$first+1))
    $form.Controls.Add($box)
    $form.CreateControl()
    $box.CreateControl()
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $box.SelectionLength = 0
    $bitmap = New-Object System.Drawing.Bitmap($form.Width,$form.Height)
    try {
        $form.DrawToBitmap($bitmap,(New-Object System.Drawing.Rectangle(0,0,$form.Width,$form.Height)))
        $bitmap.Save($target,[System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output "CAPTURED $target"
    }
    finally { $bitmap.Dispose(); $form.Dispose() }
}
