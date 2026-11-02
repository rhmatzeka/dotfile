# Checks for the Windows installer that need no packages: every .ps1 parses, and the menu does what it says when it is
# fed scripted answers (DOTFILES_ANSWERS), all in a throw-away home. Run with Windows PowerShell 5.1 and PowerShell 7:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\windows.ps1
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = 0
function Check([string]$name, [bool]$ok) {
  if ($ok) { Write-Host "  ok   $name" -ForegroundColor Green } else { Write-Host "  FAIL $name" -ForegroundColor Red; $script:failures++ }
}

# -- every PowerShell file parses, and is ASCII (5.1 reads BOM-less files as ANSI) --
$files = @(Get-ChildItem -Path $root -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\\.git\\' })
foreach ($f in $files) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
  Check "parses: $($f.Name)" ($errs.Count -eq 0)
  if ($errs.Count) { $errs | ForEach-Object { Write-Host "       $($_.Extent.StartLineNumber): $($_.Message)" } }
  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  Check "ascii:  $($f.Name)" (-not ($bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1))
}

# -- the menu, driven by an answers file --
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$env:DOTFILES_HOME = $tmp
$env:DOTFILES_DOCUMENTS = Join-Path $tmp 'Documents'
$env:DOTFILES_LOCALAPPDATA = Join-Path $tmp 'AppData\Local'
$exe = Join-Path $PSHOME 'powershell.exe'; if ($PSVersionTable.PSEdition -eq 'Core') { $exe = Join-Path $PSHOME 'pwsh.exe' }
$installer = Join-Path $root 'windows\install.ps1'

function Run-Menu([string[]]$answers, [string[]]$extra) {
  $file = Join-Path $tmp 'answers.txt'
  Set-Content -LiteralPath $file -Value $answers -Encoding Ascii
  $env:DOTFILES_ANSWERS = $file
  $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $installer @extra 2>&1 | Out-String
  $script:rc = $LASTEXITCODE
  Remove-Item Env:DOTFILES_ANSWERS
  return $out
}

# 5 = web: checked on top of the defaults; Enter continues; the dry run needs no "Continue?"
$out = Run-Menu @('5', '') @('-DryRun')
Check 'menu: toggling 5 adds web to the defaults' ($out -match 'Will install: base shell nvim terminal web')
Check 'menu: dry run exits 0' ($rc -eq 0)
Check 'menu: Linux-only parts are listed' ($out -match 'tmux' -and $out -match 'desktop')

# n = none, then 2 and 6 by name/number
$out = Run-Menu @('n', '2 rust', '') @('-DryRun')
Check 'menu: none + "2 rust" selects shell and rust' ($out -match 'Will install: shell rust')

# a Linux-only name typed into the menu is refused with a reason
$out = Run-Menu @('tmux', 'q') @('-DryRun')
Check 'menu: tmux is refused' ($out -match 'tmux is not available on Windows')
Check 'menu: q quits with 0' ($rc -eq 0 -and $out -match 'Nothing installed')

# saying no at "Continue?" installs nothing
$out = Run-Menu @('', 'n') @()
Check 'menu: "n" at Continue? cancels' ($out -match 'Cancelled' -and $rc -eq 0)

# -Only refuses Linux-only and unknown parts
$null = & $exe -NoProfile -ExecutionPolicy Bypass -File $installer -DryRun -Yes -Only desktop 2>&1
Check '-Only desktop is refused' ($LASTEXITCODE -ne 0)
$null = & $exe -NoProfile -ExecutionPolicy Bypass -File $installer -DryRun -Yes -Only nonsense 2>&1
Check '-Only nonsense is refused' ($LASTEXITCODE -ne 0)
$out = & $exe -NoProfile -ExecutionPolicy Bypass -File $installer -List 2>&1 | Out-String
Check '-List names every component' ($out -match 'base' -and $out -match 'rust' -and $out -match 'Not available on Windows')

# nothing was written into the throw-away home by any of the above
Check 'no files written by menu tests' (-not (Get-ChildItem -LiteralPath $tmp -Recurse -File | Where-Object { $_.Name -ne 'answers.txt' }))

Remove-Item -Recurse -Force $tmp
foreach ($v in 'DOTFILES_HOME', 'DOTFILES_DOCUMENTS', 'DOTFILES_LOCALAPPDATA') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
Write-Host ''
if ($failures) { Write-Host "  $failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host '  all checks passed' -ForegroundColor Green
