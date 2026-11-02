# Windows installer (beta): the terminal setup and the developer tools, split into components you pick from a menu.
#
#   .\install.ps1                  interactive menu
#   .\install.ps1 -All             every component that works on Windows
#   .\install.ps1 -Only shell,nvim
#   .\install.ps1 -DryRun          show what would happen, change nothing
#   .\install.ps1 -Yes             no questions; answer each with its default
#   .\install.ps1 -List            list the components
#
# Normally started through the top-level install.ps1 (which also fetches the repository). Works in Windows
# PowerShell 5.1 and PowerShell 7. Packages come from winget (App Installer, built into Windows 10 and 11).
# Windows has no zsh, tmux or Ghostty: the shell is PowerShell with the same prompt, aliases and fzf keys, and the
# terminal is Windows Terminal with the same colours and font. The Linux-only parts are listed but cannot be selected.
[CmdletBinding()]
param(
  [switch]$All,
  [string]$Only = '',
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$List,
  [switch]$Help
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$script:DotfilesDir = $env:DOTFILES_DIR
if (-not $script:DotfilesDir) { $script:DotfilesDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$script:DryRun = [bool]$DryRun
$script:AssumeYes = [bool]$Yes
. (Join-Path $script:DotfilesDir 'windows\lib.ps1')

$C = Join-Path $script:DotfilesDir 'config'
$Arch = $env:PROCESSOR_ARCHITECTURE   # AMD64 or ARM64 (x86 for a 32-bit shell on a 64-bit system)
if ($env:PROCESSOR_ARCHITEW6432) { $Arch = $env:PROCESSOR_ARCHITEW6432 }

$ProfileTargets = @(
  (Join-Path $script:Documents 'PowerShell\Microsoft.PowerShell_profile.ps1'),        # PowerShell 7
  (Join-Path $script:Documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')  # Windows PowerShell 5.1
)
$NvimDir = Join-Path $script:LocalAppData 'nvim'
$FragmentDst = Join-Path $script:LocalAppData 'Microsoft\Windows Terminal\Fragments\rhmatzeka-dotfile\dotfiles.json'
$WtProfileGuid = '{8af80b22-81dc-5325-91bc-4b9b947457a5}'   # same as in config/windows-terminal/dotfiles.json
$ToolsDir = Join-Path $script:LocalAppData 'rhmatzeka-dotfile-tools'

# ------------------------------------------------------------------ menu ----
$script:MenuTitle = 'Windows (beta)'
$script:MenuItems = @('base', 'shell', 'nvim', 'terminal', 'web', 'rust')
$script:MenuDefaults = @('base', 'shell', 'nvim', 'terminal')
$script:MenuOffOrder = @('tmux', 'browsers', 'desktop', 'apps')
$script:MenuOff = @{
  tmux     = 'no tmux on Windows: use Windows Terminal panes (Alt+Shift+D splits), or WSL with the Linux installer'
  browsers = 'Browsh, elinks and w3m are Linux/macOS only'
  desktop  = 'Hyprland + Caelestia desktop (Linux only)'
  apps     = 'Microsoft 365 web-app launchers (Linux only; Windows has Office itself)'
}

$script:MenuDesc = {
  param($c)
  switch ($c) {
    'base'     { 'winget packages: git, ripgrep, fzf, eza, zoxide, PowerShell 7 and the JetBrainsMono Nerd Font' }
    'shell'    { 'PowerShell profile: starship prompt, fzf keys (Ctrl+R/Ctrl+T), zoxide, eza and git aliases' }
    'nvim'     { 'Neovim (NvChad) with tree-sitter parsers and LSP servers' }
    'terminal' { 'Windows Terminal profile + colour scheme (the Ghostty look: Dracula + cyan, Nerd Font)' }
    'web'      { 'Web development: PHP, Composer, MariaDB, phpMyAdmin (MariaDB does not start with Windows unless you say yes)' }
    'rust'     { 'Rust toolchain via rustup (rustc, cargo, clippy, rustfmt, rust-analyzer)' }
  }
}

$script:MenuStatus = {
  param($c)
  switch ($c) {
    'base'     { if ((Have 'git') -and (Have 'rg') -and (Have 'fzf') -and (Font-Present)) { 'installed' } }
    'shell'    { if ((Installed-Here $ProfileTargets[0]) -and (Have 'starship')) { 'installed' } }
    'nvim'     { if ((Installed-Here (Join-Path $NvimDir 'lua\plugins\dotfiles.lua')) -and (Have 'nvim')) { 'installed' } }
    'terminal' { if (Installed-Here $FragmentDst) { 'installed' } }
    'web'      { if ((Have 'php') -and ((Have 'mariadb') -or (Find-MariaDB))) { 'installed' } }
    'rust'     { if ((Have 'rustup') -or (Test-Path (Join-Path $script:UserHome '.cargo\bin\rustup.exe'))) { 'installed' } }
  }
}

$script:MenuNote = {
  param($c)
  switch ($c) {
    'nvim' { 'about 500 MB (Node.js, parsers and LSP servers) plus a C compiler (about 1 GB) if you have none, 5-15 minutes' }
    'web'  { 'about 400 MB; MariaDB asks for administrator rights (a Windows prompt)' }
    'rust' { 'about 1 GB (toolchain in ~\.rustup)' }
  }
}

function Usage { Get-Content -LiteralPath $PSCommandPath | Select-Object -Skip 1 -First 7 | ForEach-Object { $_ -replace '^# ?', '' } }

# --------------------------------------------------------------- helpers ----
function Font-Present {
  foreach ($d in @((Join-Path $env:WINDIR 'Fonts'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'))) {
    if (Get-ChildItem -LiteralPath $d -Filter 'JetBrainsMono*Nerd*' -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
  }
  return $false
}

function Find-MariaDB {
  $dirs = @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'MariaDB *') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
  foreach ($d in $dirs) { $bin = Join-Path $d.FullName 'bin'; if (Test-Path (Join-Path $bin 'mariadb.exe')) { return $bin } }
  return $null
}

function Has-CCompiler { return ((Have 'cl') -or (Have 'gcc') -or (Have 'clang')) }

# Windows PowerShell 5.1 refuses to run any script (the profile included) until the user allows local scripts.
# PowerShell 7 already allows them. This checks the 5.1 policy and offers the usual fix: RemoteSigned for this user.
function Fix-ExecutionPolicy {
  $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (-not (Test-Path $ps51)) { return }
  $ErrorActionPreference = 'Continue'
  # no double quotes inside arguments for native programs: Windows PowerShell 5.1 passes them on mangled
  $lines = @(& $ps51 -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy -List | ForEach-Object { [string]$_.Scope + ''='' + [string]$_.ExecutionPolicy }')
  $pol = @{}
  foreach ($l in $lines) { $kv = ([string]$l).Split('='); if ($kv.Count -eq 2) { $pol[$kv[0].Trim()] = $kv[1].Trim() } }
  foreach ($gpo in @('MachinePolicy', 'UserPolicy')) {
    if ($pol[$gpo] -and $pol[$gpo] -ne 'Undefined') { Warn "script policy is set by your organisation ($gpo = $($pol[$gpo])); the profile only loads if it allows local scripts."; return }
  }
  $eff = 'Restricted'
  if ($pol['CurrentUser'] -and $pol['CurrentUser'] -ne 'Undefined') { $eff = $pol['CurrentUser'] }
  elseif ($pol['LocalMachine'] -and $pol['LocalMachine'] -ne 'Undefined') { $eff = $pol['LocalMachine'] }
  if (@('RemoteSigned', 'Unrestricted', 'Bypass') -contains $eff) { Ok "PowerShell may run local scripts ($eff)"; return }
  Info "Windows PowerShell's script policy is $eff: it would refuse to load the profile."
  if ($script:DryRun) { Info '[dry-run] would offer: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'; return }
  if (Confirm 'Allow local scripts for your user (Set-ExecutionPolicy RemoteSigned -Scope CurrentUser)?' 'y') {
    & $ps51 -NoProfile -NonInteractive -Command 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force' | Out-Host
    Ok 'local scripts allowed for your user (downloaded scripts still need a signature)'
  } else {
    Warn 'left as it is: Windows PowerShell 5.1 will not load the profile (PowerShell 7 will).'
  }
}

# Windows Terminal keeps settings.json in one of these, depending on how it was installed
function Find-WtSettings {
  $cands = @(
    (Join-Path $script:LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $script:LocalAppData 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $script:LocalAppData 'Microsoft\Windows Terminal\settings.json')
  )
  return @($cands | Where-Object { Test-Path -LiteralPath $_ })
}

function Has-WindowsTerminal {
  if (Have 'wt') { return $true }
  try { return [bool](Get-AppxPackage -Name 'Microsoft.WindowsTerminal*' -ErrorAction Stop) } catch { return $false }
}

function Write-Utf8([string]$path, [string]$text) {
  [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
}

# Set-WtDefault SETTINGS -> point "defaultProfile" at our profile. A text edit, so comments and layout stay as they are.
function Set-WtDefault([string]$settings) {
  $text = [IO.File]::ReadAllText($settings)
  $re = '("defaultProfile"\s*:\s*")([^"]*)(")'
  $m = [regex]::Match($text, $re)
  if (-not $m.Success) { Warn "no defaultProfile in $(Short $settings); pick 'dotfiles (PowerShell)' in Settings > Startup."; return }
  $old = $m.Groups[2].Value
  if ($old -eq $WtProfileGuid) { Ok 'already the default Windows Terminal profile'; return }
  if ($script:DryRun) { Info "[dry-run] would make 'dotfiles (PowerShell)' the default profile in $(Short $settings)"; return }
  $backup = Join-Path (Join-Path $script:BackupRoot $script:Stamp) 'windows-terminal-settings.json'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
  Copy-Item -LiteralPath $settings -Destination $backup -Force
  $new = $text.Substring(0, $m.Groups[2].Index) + $WtProfileGuid + $text.Substring($m.Groups[2].Index + $m.Groups[2].Length)
  Write-Utf8 $settings $new
  Add-ManifestRow $settings $WtProfileGuid $backup 'wt-default' $old
  Ok "default Windows Terminal profile: dotfiles (PowerShell) (it was $old; a copy of settings.json is in $(Short $backup))"
}

# ------------------------------------------------------------ preflight ----
function Preflight {
  if ($env:OS -ne 'Windows_NT') { Die 'This installer is for Windows (use install.sh on Linux and macOS).' }
  $build = [Environment]::OSVersion.Version.Build
  if ($build -lt 17763) { Die "Windows 10 version 1809 or newer is needed for winget (this is build $build)." }
  if (@('AMD64', 'ARM64') -notcontains $Arch) { Die "unsupported CPU: $Arch (64-bit Windows is needed)" }
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if ($admin) { Warn 'running as administrator: that works, but a normal window is better (Windows asks for permission when a step needs it).' }
  if ($script:DryRun) { Info 'DRY RUN: nothing will be changed.' }
  Refresh-Path
}

# ----------------------------------------------------------- components ----
function Comp-base {
  Step 'Base: command-line tools, PowerShell 7, Nerd Font'
  Need-Packages @('Git.Git', 'BurntSushi.ripgrep.MSVC', 'junegunn.fzf', 'jqlang.jq', 'Microsoft.PowerShell')
  Optional-Packages @('eza-community.eza', 'ajeetdsouza.zoxide', 'Fastfetch-cli.Fastfetch', 'aristocratos.btop4win')
  if (Font-Present) { Ok 'font already present: JetBrainsMono Nerd Font' }
  elseif (-not (Winget-Install 'DEVCOM.JetBrainsMonoNerdFont')) { throw 'could not install the JetBrainsMono Nerd Font' }
}

function Comp-shell {
  Step 'Shell: PowerShell profile + starship'
  Need-Packages @('Starship.Starship')
  Fix-ExecutionPolicy
  foreach ($t in $ProfileTargets) { Backup-And-Link (Join-Path $C 'powershell\profile.ps1') $t }
  Backup-And-Link (Join-Path $C 'starship\starship.toml') (Join-Path $script:UserHome '.config\starship.toml')
  Info 'zsh and Oh My Zsh are not native on Windows; for the full Linux shell, install WSL and run the Linux installer inside it.'
}

function Comp-nvim {
  Step 'Neovim (NvChad)'
  Need-Packages @('Neovim.Neovim', 'OpenJS.NodeJS.LTS', 'Git.Git', 'BurntSushi.ripgrep.MSVC', 'tree-sitter.tree-sitter-cli')
  # nvim-treesitter builds each parser with a C compiler. Without Visual Studio, WinLibs (GCC) is the light option.
  if (Has-CCompiler) { Ok 'C compiler found' }
  else {
    Info 'no C compiler found: installing WinLibs (GCC, MinGW-w64) for the tree-sitter parsers'
    Need-Packages @('BrechtSanders.WinLibs.POSIX.UCRT')
  }
  # tree-sitter asks for cl.exe (Visual Studio) unless CC says otherwise; config/nvim/dotfiles.lua does the same inside nvim
  if (-not (Have 'cl') -and -not $env:CC -and (Have 'gcc')) { $env:CC = 'gcc' }

  $marker = Join-Path $NvimDir '.rhmatzeka-dotfiles'
  if ((Test-Path -LiteralPath $NvimDir) -and -not (Test-Path -LiteralPath $marker)) {
    Warn "an nvim config already exists at $(Short $NvimDir): leaving it untouched."
    Warn "Add $C\nvim\dotfiles.lua to its lua\plugins\ if you want the extra parsers/LSP."
    return
  }
  if (-not (Test-Path -LiteralPath $NvimDir)) {
    Info 'cloning the NvChad starter'
    if ($script:DryRun) { Info '[dry-run] would clone NvChad/starter' }
    else {
      Git-Clone 'https://github.com/NvChad/starter' $NvimDir
      Remove-Item -Recurse -Force -LiteralPath (Join-Path $NvimDir '.git')
      New-Item -ItemType File -Path $marker | Out-Null
    }
  }
  Backup-And-Link (Join-Path $C 'nvim\dotfiles.lua') (Join-Path $NvimDir 'lua\plugins\dotfiles.lua')

  if ($script:DryRun) { Info '[dry-run] would sync plugins, build tree-sitter parsers and install LSP servers'; return }
  $nvim = (Get-Command nvim).Source
  Info 'syncing plugins (first run, a minute or two)'
  if (-not (Invoke-Timeout 600 $nvim @('--headless', '+Lazy! sync', '+qa'))) { Warn 'plugin sync reported a problem; it will retry when you open nvim' }
  Info 'building tree-sitter parsers'
  $lua = "+lua local ok,e=pcall(function() require('nvim-treesitter').install(dofile(vim.fn.stdpath('config')..'/lua/plugins/dotfiles.lua')[1].opts.ensure_installed):wait(540000) end) if not ok then print(e) end"
  if (-not (Invoke-Timeout 600 $nvim @('--headless', '+Lazy load nvim-treesitter', $lua, '+qa'))) { Warn 'parser build reported a problem; check :checkhealth nvim-treesitter' }
  Info 'installing LSP servers and formatters (Mason)'
  $mason = (Get-Content -LiteralPath (Join-Path $C 'nvim\mason-packages') | Where-Object { $_ }) -join ' '
  if (-not (Invoke-Timeout 900 $nvim @('--headless', '+Lazy load mason.nvim', "+MasonInstall $mason", '+qall'))) { Warn 'Mason reported a problem; run :Mason inside nvim to see which package failed' }
  Ok 'Neovim is ready (config in %LOCALAPPDATA%\nvim)'
}

function Comp-terminal {
  Step 'Terminal: Windows Terminal profile and colours'
  # the profile starts PowerShell 7 (pwsh.exe)
  Need-Packages @('Microsoft.PowerShell')
  if (Has-WindowsTerminal) { Ok 'Windows Terminal already installed' }
  elseif (-not (Winget-Install 'Microsoft.WindowsTerminal')) { throw 'could not install Windows Terminal' }
  if (-not (Font-Present)) { Warn 'the JetBrainsMono Nerd Font is missing (the base component installs it); icons show as boxes until then.' }
  Backup-And-Link (Join-Path $C 'windows-terminal\dotfiles.json') $FragmentDst
  $settings = @(Find-WtSettings)
  if ($settings.Count -eq 0) {
    Info "Windows Terminal has no settings yet: open it once, then choose 'dotfiles (PowerShell)' in Settings > Startup > Default profile (or run this again)."
  } elseif (Confirm "Make 'dotfiles (PowerShell)' the default Windows Terminal profile?" 'y') {
    foreach ($s in $settings) { Set-WtDefault $s }
  } else {
    Info "Open it from the tab menu (the arrow next to +): dotfiles (PowerShell)."
  }
  Info 'Ghostty has no Windows version; the profile uses the same colours, font, padding and cursor.'
}

function Comp-web {
  Step 'Web development: PHP, Composer, MariaDB, phpMyAdmin'
  Need-Packages @('PHP.PHP.8.5', 'MariaDB.Server')

  # php.ini: the zip from php.net has none. Start from php.ini-development and turn on what Composer and MariaDB need.
  if ($script:DryRun) { Info '[dry-run] would write php.ini (openssl, curl, mbstring, mysqli, pdo_mysql, zip, fileinfo)' }
  else {
    $php = Get-Command php -ErrorAction SilentlyContinue
    if (-not $php) { throw 'php is not on PATH after installing it; open a new terminal and run this again' }
    $phpDir = Split-Path -Parent $php.Source
    $t = Get-LinkTarget $php.Source; if ($t) { $phpDir = Split-Path -Parent $t }
    $ini = Join-Path $phpDir 'php.ini'
    if (Test-Path -LiteralPath $ini) { Ok "php.ini already exists: $ini (left as it is)" }
    elseif (Test-Path -LiteralPath (Join-Path $phpDir 'php.ini-development')) {
      $text = [IO.File]::ReadAllText((Join-Path $phpDir 'php.ini-development'))
      $ext = (Join-Path $phpDir 'ext') -replace '\\', '/'
      $text = [regex]::Replace($text, '(?m)^;\s*extension_dir\s*=\s*"ext"', "extension_dir = `"$ext`"")
      foreach ($e in @('curl', 'fileinfo', 'mbstring', 'mysqli', 'openssl', 'pdo_mysql', 'zip')) {
        $text = [regex]::Replace($text, "(?m)^;extension=$e\s*$", "extension=$e")
      }
      Write-Utf8 $ini $text
      Ok "wrote $ini (openssl, curl, mbstring, mysqli, pdo_mysql, zip, fileinfo)"
    } else { Warn "php.ini-development not found next to php.exe ($phpDir); write php.ini by hand" }
  }

  # Composer: the official composer.phar, checked against its published SHA-256, plus a composer.cmd shim
  $phar = Join-Path $script:LocalBin 'composer.phar'
  if (Test-Path -LiteralPath $phar) { Ok 'Composer already installed' }
  elseif ($script:DryRun) { Info '[dry-run] would download composer.phar (checked against its SHA-256) into ~\.local\bin' }
  else {
    $tmp = [IO.Path]::GetTempFileName()
    Fetch 'https://getcomposer.org/download/latest-stable/composer.phar' $tmp
    $sum = (Invoke-WebRequest -Uri 'https://getcomposer.org/download/latest-stable/composer.phar.sha256' -UseBasicParsing).Content
    if ($sum -is [byte[]]) { $sum = [Text.Encoding]::ASCII.GetString($sum) }
    $want = ($sum.Trim() -split '\s+')[0]
    $got = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
    if ($got -ne $want.ToUpper()) { Remove-Item $tmp; throw "composer.phar checksum mismatch (got $got)" }
    New-Item -ItemType Directory -Force -Path $script:LocalBin | Out-Null
    Move-Item -LiteralPath $tmp -Destination $phar -Force
    Set-Content -LiteralPath (Join-Path $script:LocalBin 'composer.cmd') -Value '@php "%~dp0composer.phar" %*' -Encoding Ascii
    Ok 'Composer installed in ~\.local\bin'
  }
  Add-UserPath $script:LocalBin

  # MariaDB: the MSI installs a Windows service that starts with Windows. Ask, like brew services / systemctl elsewhere.
  $bin = Find-MariaDB
  if ($bin) { Add-UserPath $bin }
  if ($script:DryRun) { Info '[dry-run] would ask whether MariaDB should start with Windows' }
  elseif (Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue) {
    if (Confirm 'Keep MariaDB starting with Windows?' 'n') { Ok 'MariaDB starts with Windows (service "MariaDB")' }
    else {
      Info 'setting the MariaDB service to start by hand (Windows asks for permission)'
      try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList '-NoProfile -Command "Stop-Service MariaDB; Set-Service MariaDB -StartupType Manual"'
        Ok 'MariaDB is stopped and starts only when you run: net start MariaDB  (as administrator)'
      } catch { Warn 'not changed (permission refused); turn it off in services.msc if you want' }
    }
  }
  Info 'Log in with: mariadb -u root   (add -p if you gave root a password during setup)'

  # phpMyAdmin: the official zip, served with PHP's own web server when you want it
  $pma = Join-Path $ToolsDir 'phpmyadmin'
  if (Test-Path -LiteralPath (Join-Path $pma 'index.php')) { Ok 'phpMyAdmin already there' }
  elseif ($script:DryRun) { Info "[dry-run] would download phpMyAdmin into $(Short $pma)" }
  else {
    try {
      $zip = Join-Path $env:TEMP 'phpmyadmin.zip'
      Fetch 'https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip' $zip
      $tmpDir = Join-Path $env:TEMP 'phpmyadmin-unzip'
      if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
      Expand-Archive -LiteralPath $zip -DestinationPath $tmpDir -Force
      $inner = Get-ChildItem -LiteralPath $tmpDir -Directory | Select-Object -First 1
      New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
      Move-Item -LiteralPath $inner.FullName -Destination $pma
      Remove-Item -Recurse -Force $tmpDir, $zip -ErrorAction SilentlyContinue
      Ok "phpMyAdmin in $(Short $pma)"
    } catch { Warn "phpMyAdmin skipped: $($_.Exception.Message)" }
  }
  Info "phpMyAdmin: php -S localhost:8080 -t `"$pma`"   then open http://localhost:8080"
}

function Comp-rust {
  Step 'Rust (rustup)'
  if ((Have 'rustup') -or (Test-Path (Join-Path $script:UserHome '.cargo\bin\rustup.exe'))) { Ok 'rustup already installed' }
  else {
    # The default (MSVC) toolchain links with Visual Studio's linker. Without Visual Studio, the GNU toolchain brings
    # its own, so nothing else is needed; switch later with: rustup default stable-msvc
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $hasMsvc = $false
    if (Test-Path $vswhere) { $hasMsvc = [bool](& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) }
    $hostTriple = ''
    if (-not $hasMsvc) {
      if (Confirm 'No Visual Studio C++ tools found. Install Visual Studio Build Tools for the MSVC toolchain (about 5 GB)?' 'n') {
        if (-not (Winget-Install 'Microsoft.VisualStudio.2022.BuildTools' @('--override', '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'))) { throw 'could not install the Visual Studio Build Tools' }
      } elseif ($Arch -eq 'AMD64') {
        $hostTriple = 'x86_64-pc-windows-gnu'
        Info 'using the GNU toolchain (no Visual Studio needed)'
      } else { Warn 'ARM64 has no GNU toolchain: Rust installs, but linking needs the Visual Studio Build Tools.' }
    }
    $triple = 'x86_64-pc-windows-msvc'; if ($Arch -eq 'ARM64') { $triple = 'aarch64-pc-windows-msvc' }
    if ($script:DryRun) { Info "[dry-run] would run the official rustup-init.exe ($triple)$(if ($hostTriple) { " with --default-host $hostTriple" })" }
    else {
      $init = Join-Path $env:TEMP 'rustup-init.exe'
      Fetch "https://static.rust-lang.org/rustup/dist/$triple/rustup-init.exe" $init
      $a = @('-y', '--profile', 'default'); if ($hostTriple) { $a += @('--default-host', $hostTriple) }
      $ErrorActionPreference = 'Continue'
      & $init @a | Out-Host
      if ($LASTEXITCODE -ne 0) { throw "rustup-init failed (exit $LASTEXITCODE)" }
      Remove-Item $init -ErrorAction SilentlyContinue
      $ErrorActionPreference = 'Stop'
    }
  }
  if (-not $script:DryRun) {
    Refresh-Path
    $ErrorActionPreference = 'Continue'
    & rustup component add rust-analyzer clippy rustfmt 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Warn 'could not add rust-analyzer/clippy/rustfmt' }
    Ok "$(& rustc --version 2>$null)"
  }
  Info 'rustup put ~\.cargo\bin on your PATH; open a new terminal to use cargo.'
}

# ----------------------------------------------------------------- main ----
if ($Help) { Usage; exit 0 }
if ($List) { Menu-List; exit 0 }
Preflight
if ($All) { $selected = @($script:MenuItems) }
elseif ($Only) { $selected = Menu-FromList $Only }
else { $selected = Menu-Choose }
if (-not (Menu-Confirm $selected)) { Info 'Cancelled.'; exit 0 }

Run-Selected $selected
if (-not $script:DryRun -and $script:OkList.Count -gt 0) {
  if ($script:OkList -contains 'shell' -or $script:OkList -contains 'terminal') { Info "Open a new Windows Terminal tab ('dotfiles (PowerShell)') to load the new shell." }
  $bk = Join-Path $script:BackupRoot $script:Stamp
  if (Test-Path -LiteralPath $bk) { Info "Files that were replaced are in $(Short $bk)" }
}
if ($script:FailedList.Count -gt 0) { exit 1 }
exit 0
