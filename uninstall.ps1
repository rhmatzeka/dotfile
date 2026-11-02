# rhmatzeka/dotfile - undo the Windows install (your original files come back from ~\.dotfiles-backup).
#
#   irm https://raw.githubusercontent.com/rhmatzeka/dotfile/main/uninstall.ps1 | iex
#   .\uninstall.ps1 -DryRun
#
# winget packages and fonts are left alone; the uninstaller lists them at the end.
[CmdletBinding()]
param([switch]$DryRun, [switch]$Yes)

& {
  if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'install.ps1'))) {
    & (Join-Path $PSScriptRoot 'install.ps1') -Uninstall -DryRun:$DryRun -Yes:$Yes
    return
  }
  # Started through irm: fetch the entry script from the repository itself.
  $url = 'https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.ps1'
  if ($env:DOTFILES_INSTALL_URL) { $url = $env:DOTFILES_INSTALL_URL }
  $entry = [scriptblock]::Create((Invoke-RestMethod -Uri $url -UseBasicParsing))
  & $entry -Uninstall -DryRun:$DryRun -Yes:$Yes
}
if ($PSCommandPath) { exit $LASTEXITCODE }
