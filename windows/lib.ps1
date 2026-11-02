# Shared helpers for the Windows installer and uninstaller. Dot-source this file; do not run it.
#
# Written for Windows PowerShell 5.1 (what every Windows 10/11 has) and PowerShell 7. Keep this file ASCII only:
# PowerShell 5.1 reads a script without a BOM as ANSI, so a stray non-ASCII character breaks it.
#
# Conventions, the same as lib/common.sh on Linux and macOS:
#   $script:DryRun     print what would happen, change nothing
#   $script:AssumeYes  answer every question with its default (never turns a "no" default into a "yes")
#   Every file we put in place is recorded in a manifest so uninstall can undo exactly that, and any file we would
#   replace is moved to ~\.dotfiles-backup\<timestamp>\ first.
#
# Test hooks (environment variables): DOTFILES_HOME, DOTFILES_DOCUMENTS and DOTFILES_LOCALAPPDATA point the installer
# at a throw-away folder; DOTFILES_ANSWERS is a file whose lines are read as the answers to the menu and questions.

if (-not $script:DryRun)    { $script:DryRun = $false }
if (-not $script:AssumeYes) { $script:AssumeYes = $false }

function Get-EnvOr([string]$name, [string]$fallback) {
  $v = [Environment]::GetEnvironmentVariable($name)
  if ($v) { return $v } else { return $fallback }
}

$script:UserHome    = Get-EnvOr 'DOTFILES_HOME' $env:USERPROFILE
$script:Documents   = Get-EnvOr 'DOTFILES_DOCUMENTS' ([Environment]::GetFolderPath('MyDocuments'))
$script:LocalAppData = Get-EnvOr 'DOTFILES_LOCALAPPDATA' $env:LOCALAPPDATA
$script:StateDir    = Join-Path $script:UserHome '.local\state\rhmatzeka-dotfiles'
$script:Manifest    = Join-Path $script:StateDir 'links-windows.tsv'
$script:BackupRoot  = Get-EnvOr 'DOTFILES_BACKUP_DIR' (Join-Path $script:UserHome '.dotfiles-backup')
$script:Stamp       = Get-EnvOr 'DOTFILES_STAMP' (Get-Date -Format 'yyyyMMdd-HHmmss')
$script:LocalBin    = Join-Path $script:UserHome '.local\bin'

# ---------------------------------------------------------------- output ----
$script:Tick  = [string][char]0x2714
$script:Arrow = [string][char]0x25B8
$script:Cross = [string][char]0x2716

function Step([string]$m) { Write-Host ''; Write-Host "  == $m" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host "  $script:Tick " -ForegroundColor Green -NoNewline; Write-Host $m }
function Info([string]$m) { Write-Host "  $script:Arrow " -ForegroundColor Cyan -NoNewline; Write-Host $m }
function Warn([string]$m) { Write-Host '  ! ' -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Fail([string]$m) { Write-Host "  $script:Cross " -ForegroundColor Red -NoNewline; Write-Host $m }
function Die([string]$m)  { Fail $m; exit 1 }

function Have([string]$cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Short([string]$p) {
  if ($p -and $p.StartsWith($script:UserHome, [StringComparison]::OrdinalIgnoreCase)) { return '~' + $p.Substring($script:UserHome.Length) }
  return $p
}

# ----------------------------------------------------------------- input ----
$script:Answers = $null
$script:AnswerIndex = 0
$answersFile = [Environment]::GetEnvironmentVariable('DOTFILES_ANSWERS')
if ($answersFile -and (Test-Path -LiteralPath $answersFile)) { $script:Answers = @(Get-Content -LiteralPath $answersFile) }

# Interactive -> $true when a person can answer (or a test feeds the answers)
function Interactive {
  if ($null -ne $script:Answers) { return $true }
  try { return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) } catch { return $false }
}

# Read-Answer PROMPT -> one line, from the answers file in tests, from the keyboard otherwise ($null when out of input)
function Read-Answer([string]$prompt) {
  if ($null -ne $script:Answers) {
    Write-Host $prompt -NoNewline
    if ($script:AnswerIndex -ge $script:Answers.Count) { Write-Host ''; return $null }
    $a = $script:Answers[$script:AnswerIndex]; $script:AnswerIndex++
    Write-Host $a
    return $a
  }
  Write-Host $prompt -NoNewline
  return [Console]::ReadLine()
}

# Confirm "question" [y|n] -> $true for yes. Without a person, or with -Yes, the default answer is used.
function Confirm([string]$q, [string]$def = 'n') {
  $hint = '[y/N]'; if ($def -eq 'y') { $hint = '[Y/n]' }
  if ($script:AssumeYes -or -not (Interactive)) { return ($def -eq 'y') }
  $ans = Read-Answer "  ? $q $hint "
  if ([string]::IsNullOrEmpty($ans)) { $ans = $def }
  return ($ans -match '^(y|yes)$')
}

# ----------------------------------------------------------------- paths ----
# Refresh-Path -> pick up what an installer just added to PATH (winget, rustup, MSIs write it to the registry)
function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $extra = @($script:LocalBin, (Join-Path $script:UserHome '.cargo\bin'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($p in (@($extra) + ($machine -split ';') + ($user -split ';') + ($env:Path -split ';'))) {
    if ($p -and -not $parts.Contains($p)) { $parts.Add($p) }
  }
  $env:Path = $parts -join ';'
}

# Add-UserPath DIR -> put DIR on the user's PATH for good (registry), and on this process's PATH now
function Add-UserPath([string]$dir) {
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $list = @(); if ($user) { $list = $user -split ';' | Where-Object { $_ } }
  if ($list -contains $dir) { return }
  if ($script:DryRun) { Info "[dry-run] would add $(Short $dir) to your PATH"; return }
  [Environment]::SetEnvironmentVariable('Path', (($list + $dir) -join ';'), 'User')
  $env:Path = "$dir;$env:Path"
  Info "added $(Short $dir) to your PATH (new terminals pick it up)"
}

# ---------------------------------------------------------------- winget ----
function Ensure-Winget {
  if (Have 'winget') { return $true }
  if ($script:DryRun) { Info '[dry-run] winget is missing: it would be needed (App Installer from the Microsoft Store)'; return $true }
  Fail 'winget is missing. Install "App Installer" from the Microsoft Store (https://aka.ms/getwinget), then run this again.'
  return $false
}

function Winget-Has([string]$id) {
  $ErrorActionPreference = 'Continue'   # under Stop, PowerShell 5.1 turns a native program's stderr into an error
  if (-not (Have 'winget')) { return $false }
  $null = & winget list --id $id --exact --accept-source-agreements --disable-interactivity 2>$null
  return ($LASTEXITCODE -eq 0)
}

# Winget-Install ID [extra winget args...] -> $true when it is installed afterwards
function Winget-Install([string]$id, [string[]]$extra = @()) {
  if ($script:DryRun) { Write-Host "  [dry-run] winget install --id $id $($extra -join ' ')" -ForegroundColor DarkGray; return $true }
  $ErrorActionPreference = 'Continue'
  Info "winget install $id"
  # Out-Host: winget's output must not become this function's return value
  & winget install --id $id --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity @extra | Out-Host
  $rc = $LASTEXITCODE
  Refresh-Path
  # -1978335189 = 0x8A15002B "no newer version", -1978335135 = 0x8A150061 "already installed": both mean it is there
  if ($rc -eq 0 -or $rc -eq -1978335189 -or $rc -eq -1978335135) { return $true }
  Fail "winget could not install $id (exit $rc)"
  return $false
}

# Need-Packages ID... -> install what is missing; throws when one of them cannot be installed (the component fails)
function Need-Packages([string[]]$ids) {
  if (-not (Ensure-Winget)) { throw 'winget missing' }
  $missing = @($ids | Where-Object { -not (Winget-Has $_) })
  if ($missing.Count -eq 0) { Ok "already installed: $($ids -join ', ')"; return }
  foreach ($id in $missing) { if (-not (Winget-Install $id)) { throw "could not install $id" } }
}

# Optional-Packages ID... -> try each one; warn instead of failing
function Optional-Packages([string[]]$ids) {
  if (-not (Ensure-Winget)) { return }
  foreach ($id in $ids) {
    if (Winget-Has $id) { continue }
    if (-not (Winget-Install $id)) { Warn "optional, skipped: $id" }
  }
}

# ----------------------------------------------------------------- files ----
function Get-LinkTarget([string]$p) {
  $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if ($item -and $item.LinkType -eq 'SymbolicLink') { return @($item.Target)[0] }
  return $null
}

function Read-Manifest {
  if (-not (Test-Path -LiteralPath $script:Manifest)) { return @() }
  $rows = @()
  foreach ($line in (Get-Content -LiteralPath $script:Manifest)) {
    if (-not $line) { continue }
    $f = $line -split "`t"
    while ($f.Count -lt 5) { $f += '' }
    $rows += [pscustomobject]@{ Dst = $f[0]; Src = $f[1]; Backup = $f[2]; Kind = $f[3]; Extra = $f[4] }
  }
  return $rows
}

function Add-ManifestRow([string]$dst, [string]$src, [string]$backup, [string]$kind, [string]$extra) {
  New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
  Add-Content -LiteralPath $script:Manifest -Value (($dst, $src, $backup, $kind, $extra) -join "`t") -Encoding UTF8
}

# Installed-Here DST -> $true when DST is a file this installer put there (a link into the repo, or a recorded copy)
function Installed-Here([string]$dst) {
  $t = Get-LinkTarget $dst
  if ($t -and $t.StartsWith($script:DotfilesDir, [StringComparison]::OrdinalIgnoreCase)) { return $true }
  if (-not (Test-Path -LiteralPath $dst)) { return $false }
  foreach ($r in (Read-Manifest)) { if ($r.Dst -eq $dst -and $r.Kind -eq 'copy') { return $true } }
  return $false
}

# Backup-And-Link SRC DST -> a symbolic link to the repo file when Windows allows it (Developer Mode, or an admin
# shell), otherwise a copy (re-run the installer after `git pull` to refresh copies). The old file is backed up first.
function Backup-And-Link([string]$src, [string]$dst) {
  if (-not (Test-Path -LiteralPath $src)) { Warn "missing in repo, skipped: $src"; return }
  if ((Get-LinkTarget $dst) -eq $src) { Ok "already linked: $(Short $dst)"; return }
  if ($script:DryRun) {
    if (Test-Path -LiteralPath $dst) { Info "[dry-run] would back up $(Short $dst) and link it to the repo" }
    else { Info "[dry-run] would link $(Short $dst)" }
    return
  }
  $backup = ''
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  if ((Test-Path -LiteralPath $dst) -or (Get-LinkTarget $dst)) {
    $rel = $dst
    if ($dst.StartsWith($script:UserHome, [StringComparison]::OrdinalIgnoreCase)) { $rel = $dst.Substring($script:UserHome.Length).TrimStart('\') }
    else { $rel = $dst -replace ':', '' }
    $backup = Join-Path (Join-Path $script:BackupRoot $script:Stamp) $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
    Move-Item -LiteralPath $dst -Destination $backup -Force
    Info "backed up $(Short $dst) -> $(Short $backup)"
  }
  $kind = 'link'; $extra = ''
  try { New-Item -ItemType SymbolicLink -Path $dst -Target $src -ErrorAction Stop | Out-Null }
  catch {
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $kind = 'copy'; $extra = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
  }
  Add-ManifestRow $dst $src $backup $kind $extra
  if ($kind -eq 'link') { Ok "linked $(Short $dst)" }
  else { Ok "copied $(Short $dst) (Windows did not allow a link: turn on Developer Mode to get links that follow git pull)" }
}

# Fetch URL DEST -> download with a few retries
function Fetch([string]$url, [string]$dest) {
  if ($script:DryRun) { Info "[dry-run] would download $url"; return }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'   # the progress bar makes 5.1 downloads crawl
  try {
    for ($i = 1; $i -le 3; $i++) {
      try { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 600; return }
      catch { if ($i -eq 3) { throw "download failed: $url ($($_.Exception.Message))" }; Start-Sleep -Seconds 2 }
    }
  } finally { $ProgressPreference = $old }
}

# Git-Clone URL DEST -> clone once; if it exists, leave it alone
function Git-Clone([string]$url, [string]$dest) {
  if (Test-Path -LiteralPath (Join-Path $dest '.git')) { Ok "already cloned: $(Short $dest)"; return }
  if ($script:DryRun) { Info "[dry-run] would clone $url"; return }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
  $ErrorActionPreference = 'Continue'
  & git clone -q --depth 1 $url $dest 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "git clone failed: $url" }
}

# Invoke-Timeout SECONDS EXE ARG... -> run EXE with a time limit, output hidden; $true when it exits 0 in time.
# Arguments must not contain double quotes (they are joined into one command line).
function Invoke-Timeout([int]$seconds, [string]$exe, [string[]]$arguments) {
  $ErrorActionPreference = 'Continue'
  $line = ($arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $log = [IO.Path]::GetTempFileName()
  $p = Start-Process -FilePath $exe -ArgumentList $line -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  if (-not $p.WaitForExit($seconds * 1000)) { try { $p.Kill() } catch { }; Remove-Item $log, "$log.err" -ErrorAction SilentlyContinue; return $false }
  Remove-Item $log, "$log.err" -ErrorAction SilentlyContinue
  return ($p.ExitCode -eq 0)
}

# ------------------------------------------------------------------ menu ----
# Same checklist as lib/menu.sh. The installer sets $MenuItems, $MenuDefaults, $MenuOff (hashtable name -> reason,
# kept in order with $MenuOffOrder) and defines the scriptblocks $MenuDesc, $MenuStatus and $MenuNote.

function Menu-List {
  foreach ($c in $script:MenuItems) {
    $mark = ' '; if ($script:MenuDefaults -contains $c) { $mark = '*' }
    Write-Host ('  {0} {1,-9} {2}' -f $mark, $c, (& $script:MenuDesc $c))
  }
  Write-Host ''; Write-Host '  * = checked by default'
  if ($script:MenuOffOrder.Count -gt 0) {
    Write-Host ''; Write-Host '  Not available on Windows:'
    foreach ($c in $script:MenuOffOrder) { Write-Host ('  - {0,-9} {1}' -f $c, $script:MenuOff[$c]) }
  }
}

function Menu-FromList([string]$list) {
  $sel = @()
  foreach ($c in ($list -split '[,\s]+' | Where-Object { $_ })) {
    if ($script:MenuOff.ContainsKey($c)) { Die "$c cannot be installed on Windows: $($script:MenuOff[$c])" }
    if ($script:MenuItems -notcontains $c) { Die "unknown component: $c (see -List)" }
    if ($sel -notcontains $c) { $sel += $c }
  }
  return ,$sel
}

function Menu-Draw($on, $status, [string]$msg) {
  if (-not [Console]::IsOutputRedirected -and $null -eq $script:Answers) { Clear-Host }
  Write-Host ''
  Write-Host '  dotfiles installer' -ForegroundColor Cyan -NoNewline; Write-Host " - $script:MenuTitle" -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  Choose what to install (type a number to check or uncheck it):'
  Write-Host ''
  for ($i = 0; $i -lt $script:MenuItems.Count; $i++) {
    $c = $script:MenuItems[$i]
    if ($on[$i]) { Write-Host ('   {0,2}. [x] {1,-9} ' -f ($i + 1), $c) -ForegroundColor Cyan -NoNewline }
    else { Write-Host ('   {0,2}. [ ] {1,-9} ' -f ($i + 1), $c) -ForegroundColor DarkGray -NoNewline }
    Write-Host (& $script:MenuDesc $c) -ForegroundColor DarkGray -NoNewline
    if ($status[$i]) { Write-Host " ($($status[$i]))" -ForegroundColor Green } else { Write-Host '' }
  }
  if ($script:MenuOffOrder.Count -gt 0) {
    Write-Host ''; Write-Host '  Not available on Windows (cannot be selected):'
    foreach ($c in $script:MenuOffOrder) { Write-Host ('      -  {0,-9} {1}' -f $c, $script:MenuOff[$c]) -ForegroundColor DarkGray }
  }
  Write-Host ''
  Write-Host '  number check/uncheck  |  a all  |  n none  |  Enter continue  |  q quit'
  if ($msg) { Write-Host ''; Write-Host "  ! $msg" -ForegroundColor Yellow }
  Write-Host ''
}

# Menu-Choose -> the selected names. Without a person, or with -Yes, it takes the defaults without asking.
function Menu-Choose {
  if ($script:AssumeYes -or -not (Interactive)) { return ,@($script:MenuDefaults) }
  $n = $script:MenuItems.Count
  $on = New-Object bool[] $n
  $status = New-Object string[] $n
  for ($i = 0; $i -lt $n; $i++) {
    $c = $script:MenuItems[$i]
    $status[$i] = [string](& $script:MenuStatus $c)
    # already installed: nothing to do, so it starts unchecked (check it again to repair or update it)
    $on[$i] = ($script:MenuDefaults -contains $c) -and -not $status[$i]
  }
  $msg = ''
  while ($true) {
    Menu-Draw $on $status $msg; $msg = ''
    $ans = Read-Answer '  > '
    if ($null -eq $ans) { $ans = 'q' }
    $ans = $ans.Trim()
    if ($ans -eq '') { break }
    if ($ans -eq 'a') { for ($i = 0; $i -lt $n; $i++) { $on[$i] = $true }; continue }
    if ($ans -eq 'n') { for ($i = 0; $i -lt $n; $i++) { $on[$i] = $false }; continue }
    if ($ans -eq 'q') { Write-Host ''; Info 'Nothing installed.'; exit 0 }
    foreach ($tok in ($ans -split '[,\s]+' | Where-Object { $_ })) {
      $i = -1
      if ($tok -match '^\d+$') { $k = [int]$tok; if ($k -ge 1 -and $k -le $n) { $i = $k - 1 } }
      else { $i = [array]::IndexOf([string[]]$script:MenuItems, $tok) }
      if ($i -ge 0) { $on[$i] = -not $on[$i] }
      elseif ($script:MenuOff.ContainsKey($tok)) { $msg = "$tok is not available on Windows: $($script:MenuOff[$tok])" }
      else { $msg = "not a valid choice: $tok (use the numbers 1-$n)" }
    }
  }
  $sel = @()
  for ($i = 0; $i -lt $n; $i++) { if ($on[$i]) { $sel += $script:MenuItems[$i] } }
  Write-Host ''
  return ,$sel
}

# Menu-Confirm SELECTED -> $true to go ahead. Lists what will be installed, the heavy parts, and what Windows skips.
function Menu-Confirm($selected) {
  if ($selected.Count -eq 0) { Info 'Nothing selected.'; exit 0 }
  Write-Host ''
  Write-Host "  Will install: $($selected -join ' ')"
  foreach ($c in $selected) {
    if (& $script:MenuStatus $c) { continue }
    $note = & $script:MenuNote $c
    if ($note) { Write-Host ('    ! {0,-9} {1}' -f $c, $note) -ForegroundColor Yellow }
  }
  if ($script:MenuOffOrder.Count -gt 0) { Write-Host "  Not available on Windows, skipped: $($script:MenuOffOrder -join ' ')" -ForegroundColor DarkGray }
  Write-Host ''
  if ($script:DryRun) { return $true }
  return (Confirm 'Continue?' 'y')
}

# Run-Selected SELECTED -> runs Comp-<name> for each one, in menu order. One failure does not stop the rest.
function Run-Selected($selected) {
  $script:OkList = @(); $script:FailedList = @()
  foreach ($c in $script:MenuItems) {
    if ($selected -notcontains $c) { continue }
    try {
      & "Comp-$c"
      $script:OkList += $c
    } catch {
      Fail "component failed: $c ($($_.Exception.Message))"
      $script:FailedList += $c
    }
  }
  Write-Host ''
  if ($script:OkList.Count -gt 0) { Ok "Done: $($script:OkList -join ' ')" }
  if ($script:FailedList.Count -gt 0) { Fail "Failed: $($script:FailedList -join ' ') (run again with -Only $($script:FailedList -join ',') after fixing the cause)" }
}
