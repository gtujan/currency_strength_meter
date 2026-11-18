# One-line installer for Currency Strength Meter on Windows (PowerShell 5.1+).
#   irm https://raw.githubusercontent.com/gtujan/currency_strength_meter/main/install.ps1 | iex
# Env overrides: CSM_REPO, CSM_BRANCH, CSM_DIR, CSM_BIN, CSM_LOCAL_SRC
$ErrorActionPreference = 'Stop'
$Repo   = if ($env:CSM_REPO)   { $env:CSM_REPO }   else { 'gtujan/currency_strength_meter' }
$Branch = if ($env:CSM_BRANCH) { $env:CSM_BRANCH } else { 'main' }
$Dir    = if ($env:CSM_DIR)    { $env:CSM_DIR }    else { Join-Path $HOME 'currency_strength_meter' }
$Bin    = if ($env:CSM_BIN)    { $env:CSM_BIN }    else { Join-Path $HOME '.local\bin' }

function Say($m) { Write-Host "==> $m" -ForegroundColor Green }

# 1. Python 3.8+
$py = $null
foreach ($c in @(@('py','-3'), @('python'), @('python3'))) {
  if (Get-Command $c[0] -ErrorAction SilentlyContinue) {
    $extra = @($c | Select-Object -Skip 1)
    & $c[0] @extra -c "import sys; sys.exit(sys.version_info < (3, 8))" 2>$null
    if ($LASTEXITCODE -eq 0) { $py = $c; break }
  }
}
if (-not $py) { throw 'Python 3.8+ not found. Install from https://www.python.org/downloads/ (tick "Add to PATH") and re-run.' }
$pyExe = $py[0]; $pyArgs = @($py | Select-Object -Skip 1)

# 2. Fetch project files (re-running updates code; .venv and logs are preserved)
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
if ($env:CSM_LOCAL_SRC) {
  Say "Copying project from $env:CSM_LOCAL_SRC to $Dir"
  robocopy $env:CSM_LOCAL_SRC $Dir /E /XD .venv __pycache__ .git /XF .server.pid server.log | Out-Null
} else {
  Say "Downloading $Repo@$Branch into $Dir"
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("csm_" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'src.zip'
  Invoke-WebRequest -UseBasicParsing "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip
  Expand-Archive $zip -DestinationPath $tmp -Force
  $root = Get-ChildItem $tmp -Directory | Select-Object -First 1
  Copy-Item (Join-Path $root.FullName '*') $Dir -Recurse -Force
  Remove-Item $tmp -Recurse -Force
}

# 3. Virtualenv + dependencies
Set-Location $Dir
$vpy = Join-Path $Dir '.venv\Scripts\python.exe'
if (-not (Test-Path $vpy)) {
  Say 'Creating virtualenv'
  & $pyExe @pyArgs -m venv .venv
  if ($LASTEXITCODE -ne 0) { throw 'venv creation failed.' }
}
Say 'Installing dependencies'
& $vpy -m pip install --quiet --upgrade pip
& $vpy -m pip install --quiet -r requirements.txt

# 4. Put `csmserve` on PATH (shim that forwards to the project's csmserve.cmd)
New-Item -ItemType Directory -Force -Path $Bin | Out-Null
Set-Content -Path (Join-Path $Bin 'csmserve.cmd') -Value "@echo off`r`n`"$Dir\csmserve.cmd`" %*" -Encoding ASCII
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $Bin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$Bin"), 'User')
  Say "Added $Bin to your user PATH (open a new terminal to pick it up)"
}

Write-Host @"

Installed in $Dir

  csmserve run       start the server  -> http://127.0.0.1:8765/
  csmserve stop|restart|status|logs

MT4 setup (once): copy CSMFeed.ex4 (precompiled, no compiling needed) from $Dir into
MQL4\Experts (MT4: File > Open Data Folder), restart MT4, attach CSMFeed to a chart, and allow
WebRequest for http://127.0.0.1:8765 (Tools > Options > Expert Advisors).
"@
