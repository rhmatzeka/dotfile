# Undo what install.ps1 put in place on Windows, and bring back the files it replaced (from ~\.dotfiles-backup).
#
#   .\uninstall.ps1            interactive
#   .\uninstall.ps1 -DryRun    show what would happen
#   .\uninstall.ps1 -Yes       no questions
#
# It only removes links that still point into this repository and copies that nobody has edited since. winget
# packages, fonts, the NvChad clone and the script policy are left alone; the list at the end says how to remove them.
[CmdletBinding()]
param([switch]$DryRun, [switch]$Yes, [switch]$Help)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$script:DotfilesDir = $env:DOTFILES_DIR
if (-not $script:DotfilesDir) { $script:DotfilesDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$script:DryRun = [bool]$DryRun
$script:AssumeYes = [bool]$Yes
. (Join-Path $script:DotfilesDir 'windows\lib.ps1')

if ($Help) { Get-Content -LiteralPath $PSCommandPath | Select-Object -Skip 1 -First 4 | ForEach-Object { $_ -replace '^# ?', '' }; exit 0 }

$rows = @(Read-Manifest)
if ($rows.Count -eq 0) { Info "Nothing to undo: no record of installed files at $(Short $script:Manifest)."; exit 0 }
Step 'Files recorded by the installer'
foreach ($r in $rows) { Write-Host "     $(Short $r.Dst)" }
if (-not (Confirm 'Remove them and restore your original files?' 'y')) { Info 'Cancelled.'; exit 0 }

$removed = 0; $restored = 0; $skipped = 0
function Restore-Backup($r) {
  if ($r.Backup -and (Test-Path -LiteralPath $r.Backup)) {
    if ($script:DryRun) { Info "[dry-run] would restore $(Short $r.Dst)" }
    else { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $r.Dst) | Out-Null; Move-Item -LiteralPath $r.Backup -Destination $r.Dst -Force }
    $script:restored++
    Ok "restored $(Short $r.Dst)"
  } else { Ok "removed $(Short $r.Dst)" }
}

# newest first, so a file replaced twice ends up as it was before the first install
[array]::Reverse($rows)
foreach ($r in $rows) {
  switch ($r.Kind) {
    'link' {
      if ((Get-LinkTarget $r.Dst) -eq $r.Src) {
        if ($script:DryRun) { Info "[dry-run] would remove $(Short $r.Dst)" } else { (Get-Item -LiteralPath $r.Dst -Force).Delete() }
        $removed++; Restore-Backup $r
      } else { Warn "left alone (changed since install): $(Short $r.Dst)"; $skipped++ }
    }
    'copy' {
      if ((Test-Path -LiteralPath $r.Dst) -and (Get-FileHash -LiteralPath $r.Dst -Algorithm SHA256).Hash -eq $r.Extra) {
        if ($script:DryRun) { Info "[dry-run] would remove $(Short $r.Dst)" } else { Remove-Item -LiteralPath $r.Dst -Force }
        $removed++; Restore-Backup $r
      } else { Warn "left alone (edited since install): $(Short $r.Dst)"; $skipped++ }
    }
    'wt-default' {
      # put Windows Terminal's default profile back, unless someone already chose another one
      if (-not (Test-Path -LiteralPath $r.Dst)) { $skipped++; continue }
      $text = [IO.File]::ReadAllText($r.Dst)
      $m = [regex]::Match($text, '("defaultProfile"\s*:\s*")([^"]*)(")')
      if ($m.Success -and $m.Groups[2].Value -eq $r.Src) {
        if ($script:DryRun) { Info '[dry-run] would set the default Windows Terminal profile back' }
        else {
          $new = $text.Substring(0, $m.Groups[2].Index) + $r.Extra + $text.Substring($m.Groups[2].Index + $m.Groups[2].Length)
          [IO.File]::WriteAllText($r.Dst, $new, (New-Object Text.UTF8Encoding $false))
        }
        $restored++; Ok 'default Windows Terminal profile set back'
      } else { Warn 'default Windows Terminal profile was changed since install: left alone'; $skipped++ }
    }
  }
}

if (-not $script:DryRun) {
  Remove-Item -LiteralPath $script:Manifest -Force
  Remove-Item -LiteralPath $script:StateDir -ErrorAction SilentlyContinue   # only goes when empty (Linux/macOS share it)
}
Write-Host ''
Ok "$removed file(s) removed, $restored restored, $skipped skipped."

Step 'Not removed (delete by hand if you want them gone)'
@'
   %LOCALAPPDATA%\nvim           the NvChad starter (only if it has a .rhmatzeka-dotfiles marker), %LOCALAPPDATA%\nvim-data
   %LOCALAPPDATA%\rhmatzeka-dotfile-tools   phpMyAdmin
   ~\.local\bin\composer.*       Composer;  php.ini next to php.exe
   ~\.rustup, ~\.cargo           Rust (rustup self uninstall)
   winget packages               winget list, then: winget uninstall --id <id>
   script policy                 Set-ExecutionPolicy Undefined -Scope CurrentUser   (in Windows PowerShell)
'@ | Write-Host
exit 0
