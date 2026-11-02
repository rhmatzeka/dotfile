# rhmatzeka/dotfile - Windows entry point (Windows 10/11, Windows PowerShell 5.1 or PowerShell 7).
#
#   irm https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.ps1))) -DryRun -All
#   .\install.ps1 -Only shell,terminal          (from a checkout)
#   .\install.ps1 -Uninstall
#
# This file only checks the system, fetches the repository to %LOCALAPPDATA%\rhmatzeka-dotfile (with git, which it
# installs through winget when missing) and hands over to windows\install.ps1 in a fresh PowerShell that is allowed to
# run it. Everything it will do is printed first; -DryRun changes nothing. Linux and macOS use install.sh instead.
# ASCII only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
[CmdletBinding()]
param(
  [switch]$Uninstall,
  [switch]$All,
  [string]$Only = '',
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$List,
  [switch]$Help
)

# Everything runs inside this script block, so `irm | iex` never closes the window (no `exit`) and leaves no
# variables or settings behind in the user's session. Its output is NOT captured: the installer it starts must keep
# the real console (colours, the menu, questions). The result travels in $LASTEXITCODE.
& {
  $ErrorActionPreference = 'Stop'
  function Quit([int]$c) { $global:LASTEXITCODE = $c }
  function Say([string]$m)  { Write-Host '  > ' -ForegroundColor Cyan -NoNewline; Write-Host $m }
  function Good([string]$m) { Write-Host '  ok ' -ForegroundColor Green -NoNewline; Write-Host $m }
  function Bad([string]$m)  { Write-Host '  x ' -ForegroundColor Red -NoNewline; Write-Host $m }

  $repoUrl = 'https://github.com/rhmatzeka/dotfile.git'; if ($env:DOTFILES_REPO) { $repoUrl = $env:DOTFILES_REPO }
  $branch = 'main'; if ($env:DOTFILES_BRANCH) { $branch = $env:DOTFILES_BRANCH }
  $dir = Join-Path $env:LOCALAPPDATA 'rhmatzeka-dotfile'; if ($env:DOTFILES_DIR) { $dir = $env:DOTFILES_DIR }
  $action = 'install'; if ($Uninstall) { $action = 'uninstall' }

  Write-Host ''
  Write-Host "  dotfiles $action" -ForegroundColor Cyan
  Write-Host '  https://github.com/rhmatzeka/dotfile' -ForegroundColor DarkGray
  Write-Host ''

  if ($env:OS -ne 'Windows_NT') { Bad 'This is the Windows installer. On Linux and macOS run: bash <(curl -fsSL https://dotfiles.rahmateka.my.id)'; Quit 1; return }
  $os = [Environment]::OSVersion.Version
  Good "Detected: Windows (build $($os.Build), $env:PROCESSOR_ARCHITECTURE), PowerShell $($PSVersionTable.PSVersion)"

  function Refresh-Path {
    $env:Path = ([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:Path) -join ';'
  }

  # Run from a checkout? Use it as is. Run through irm? Fetch the repository.
  if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'windows\install.ps1')) -and -not $env:DOTFILES_FORCE_CLONE) {
    $dir = $PSScriptRoot
    Good "Using this checkout: $dir"
  } else {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
      if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Bad 'git and winget are both missing. Install "App Installer" from the Microsoft Store (https://aka.ms/getwinget) and run this again.'
        Quit 1; return
      }
      Say 'git is needed to fetch the repository: installing it with winget'
      & winget install --id Git.Git --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
      Refresh-Path
      if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Bad 'git is still not on PATH; open a new PowerShell window and run this again.'; Quit 1; return }
    }
    $ErrorActionPreference = 'Continue'   # git writes progress to stderr, which 5.1 would treat as an error
    if (Test-Path (Join-Path $dir '.git')) {
      $origin = (& git -C $dir remote get-url origin 2>$null) -replace '\.git$', ''
      if ($origin -ne ($repoUrl -replace '\.git$', '')) {
        Bad "$dir is a git repository of something else (origin: $origin); not touching it."
        Say 'Set DOTFILES_DIR to another folder and run again.'
        Quit 1; return
      }
      Say "Updating $dir"
      if (& git -C $dir status --porcelain 2>$null) { Say "Local changes found in ${dir}: leaving them untouched and not updating." }
      else {
        & git -C $dir fetch -q origin $branch 2>&1 | Out-Null
        & git -C $dir checkout -q $branch 2>&1 | Out-Null
        & git -C $dir pull -q --ff-only origin $branch 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Say 'Could not fast-forward; continuing with what is already there.' }
      }
    } else {
      Say "Fetching $repoUrl -> $dir"
      & git clone -q --branch $branch $repoUrl $dir 2>&1 | Out-Host
      if ($LASTEXITCODE -ne 0) { Bad 'git clone failed.'; Quit 1; return }
    }
  }

  $target = Join-Path $dir "windows\$action.ps1"
  if (-not (Test-Path $target)) { Bad "Missing $target"; Quit 1; return }
  $fwd = @()
  foreach ($k in @('All', 'DryRun', 'Yes', 'List', 'Help')) { if ((Get-Variable $k -ValueOnly)) { $fwd += "-$k" } }
  if ($Only) { $fwd += @('-Only', $Only) }
  # the same kind of PowerShell that runs this (5.1 or 7); -ExecutionPolicy Bypass for this one process only
  $exe = Join-Path $PSHOME 'powershell.exe'; if ($PSVersionTable.PSEdition -eq 'Core') { $exe = Join-Path $PSHOME 'pwsh.exe' }
  $env:DOTFILES_DIR = $dir
  Write-Host ''
  & $exe -NoProfile -ExecutionPolicy Bypass -File $target @fwd
  Quit $LASTEXITCODE
}
# started as a file: pass the exit code on. Started through irm | iex: keep it in $LASTEXITCODE, the window stays open.
if ($PSCommandPath) { exit $LASTEXITCODE }
