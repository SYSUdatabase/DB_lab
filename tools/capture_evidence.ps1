param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$SqlFile,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Database = 'TokenHubDB_v01_A',
    [string]$Server = 'localhost\SQLEXPRESS'
)
$ErrorActionPreference = 'Stop'
$absSql = (Resolve-Path $SqlFile).Path
$absOut = [IO.Path]::GetFullPath($Output)
$escapedTitle = $Title.Replace("'","''")
$escapedSql = $absSql.Replace("'","''")
$escapedServer = $Server.Replace("'","''")
$escapedDb = $Database.Replace("'","''")
$temp = Join-Path $env:TEMP ("db_lab_capture_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
$child = @"
`$Host.UI.RawUI.WindowTitle = '$escapedTitle'
Clear-Host
Write-Host 'DB_lab v0.1 - REAL SQL SERVER EVIDENCE'
Write-Host '$escapedTitle'
Write-Host 'Database: $escapedDb    Server: $escapedServer'
Write-Host ('-' * 78)
& sqlcmd -S '$escapedServer' -d '$escapedDb' -E -C -f 65001 -W -i '$escapedSql'
Write-Host ('-' * 78)
Write-Host 'Live result from SQL Server; window kept open for capture.'
Start-Sleep -Seconds 30
"@
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($temp,$child,$utf8)
$p = Start-Process powershell.exe -ArgumentList '-NoProfile','-File',$temp -WindowStyle Maximized -PassThru
Start-Sleep -Seconds 4
$ws = New-Object -ComObject WScript.Shell
[void]$ws.AppActivate($Title)
Start-Sleep -Seconds 1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width,$bounds.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location,[System.Drawing.Point]::Empty,$bounds.Size)
$dir = Split-Path -Parent $absOut
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$bmp.Save($absOut,[System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Remove-Item $temp -Force -ErrorAction SilentlyContinue
Write-Output "CAPTURED $absOut"
