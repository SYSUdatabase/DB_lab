param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$SqlFile,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Database = 'TokenHubDB_v01_A',
    [string]$Server = 'localhost\SQLEXPRESS',
    [string]$LogFile
)
$ErrorActionPreference = 'Stop'
$absSql = (Resolve-Path $SqlFile).Path
$absOut = [IO.Path]::GetFullPath($Output)
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $LogFile) {
    $LogFile = Join-Path $repoRoot ('result\evidence_logs\' + [IO.Path]::GetFileNameWithoutExtension($absSql) + '.log')
}
$absLog = [IO.Path]::GetFullPath($LogFile)
$logDir = Split-Path -Parent $absLog
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# Step 1: run sqlcmd for real and write the output to a log file.
cmd /c "sqlcmd -S `"$Server`" -d `"$Database`" -E -C -f 65001 -W -v DatabaseName=`"$Database`" -i `"$absSql`" > `"$absLog`" 2>&1"
if (-not (Test-Path $absLog)) { throw "sqlcmd produced no log: $absLog" }
$lines = @(Get-Content -LiteralPath $absLog -Encoding UTF8)
if ($lines.Count -eq 0) { throw "sqlcmd output is empty: $absLog" }
$failCount = @($lines | Select-String -Pattern 'FAIL').Count

# Step 2: pick a font size so the whole output fits the maximized window.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$avail = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height - 100
$fontSize = [Math]::Max(6, [Math]::Min(14, [Math]::Floor($avail / ($lines.Count * 1.45))))
$packed = [uint32](($fontSize -band 0xFF) -bor (($fontSize -band 0xFF) -shl 8))

# Step 3: build a child window that prints the captured log verbatim.
$lit = ($lines | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ","
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine('$OutputEncoding = [Text.Encoding]::UTF8')
$null = $sb.AppendLine("`$Host.UI.RawUI.WindowTitle = '" + $Title.Replace("'", "''") + "'")
$null = $sb.AppendLine("try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}")
$null = $sb.AppendLine("try { Add-Type -Name Native2 -Namespace DbLab -MemberDefinition '[DllImport(`"kernel32.dll`")] public static extern IntPtr GetStdHandle(int nStdHandle); [DllImport(`"kernel32.dll`")] public static extern bool SetConsoleFont(IntPtr hConsoleOutput, uint dwFontSize);'; [DbLab.Native2]::SetConsoleFont([DbLab.Native2]::GetStdHandle(-11), $packed) } catch {}")
$null = $sb.AppendLine('Start-Sleep -Milliseconds 500')
$null = $sb.AppendLine('try { $raw = $Host.UI.RawUI; $w = $raw.BufferSize.Width; $h = [Math]::Min(9000, ' + $lines.Count + ' + 14); if ($h -gt $raw.WindowSize.Height) { $raw.BufferSize = New-Object System.Management.Automation.Host.Size($w,$h); $raw.WindowSize = New-Object System.Management.Automation.Host.Size($w,$h) } } catch {}')
$null = $sb.AppendLine('Clear-Host')
$null = $sb.AppendLine("Write-Host 'DB_lab v0.1 - REAL SQL SERVER EVIDENCE' -ForegroundColor Cyan")
$null = $sb.AppendLine("Write-Host '" + $Title.Replace("'", "''") + "'")
$null = $sb.AppendLine("Write-Host 'Database: $Database    Server: $Server    Sql: " + (Split-Path -Leaf $absSql) + "'")
$null = $sb.AppendLine("Write-Host ('-' * 110)")
$null = $sb.AppendLine('$lines = @(' + $lit + ')')
$null = $sb.AppendLine('foreach ($l in $lines) { Write-Host $l }')
$null = $sb.AppendLine("Write-Host ('-' * 110)")
$null = $sb.AppendLine("Write-Host ('Verbatim sqlcmd output: " + $lines.Count + " lines, font ${fontSize}pt, log ' + '" + (Split-Path -Leaf $absLog) + "')")
$null = $sb.AppendLine('Start-Sleep -Seconds 180')

$temp = Join-Path $env:TEMP ("db_lab_capture_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
[IO.File]::WriteAllText($temp, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))

# Step 4: show the window, then grab the screen after it has painted.
$p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $temp -WindowStyle Maximized -PassThru
Start-Sleep -Seconds 3
$ws = New-Object -ComObject WScript.Shell
[void]$ws.AppActivate($p.Id)
Start-Sleep -Seconds 2
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$outDir = Split-Path -Parent $absOut
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$bmp.Save($absOut, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Remove-Item $temp -Force -ErrorAction SilentlyContinue
Write-Output "CAPTURED $absOut  lines=$($lines.Count) font=${fontSize}pt FAIL=$failCount log=$absLog"