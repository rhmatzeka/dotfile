# PowerShell profile (managed by rhmatzeka/dotfile). The Windows counterpart of config/zsh/zshrc.
# Linked to both $PROFILE files (PowerShell 7 and Windows PowerShell 5.1); machine-local tweaks go in
# ~\.config\powershell\local.ps1, which is not in the repo. ASCII only: 5.1 reads BOM-less scripts as ANSI.

# -- PATH ----------------------------------------------------------------------
foreach ($d in @("$HOME\.local\bin", "$HOME\.cargo\bin", "$HOME\.bun\bin")) {
  if ((Test-Path -LiteralPath $d) -and (($env:Path -split ';') -notcontains $d)) { $env:Path = "$d;$env:Path" }
}
$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

function _has([string]$c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

# -- line editing and history (PSReadLine ships with both PowerShell versions) ---
if (Get-Module -ListAvailable PSReadLine) {
  Import-Module PSReadLine -ErrorAction SilentlyContinue
  Set-PSReadLineOption -HistoryNoDuplicates -MaximumHistoryCount 50000 -BellStyle None
  # Dracula palette with a cyan accent, the same colours as zsh-syntax-highlighting in the zshrc.
  # ([char]27 instead of `e: Windows PowerShell 5.1 does not know the `e escape)
  $esc = [string][char]27
  Set-PSReadLineOption -Colors @{
    Command   = "$esc[1;38;2;0;217;255m"
    Parameter = "$esc[38;2;139;233;253m"
    String    = "$esc[38;2;241;250;140m"
    Variable  = "$esc[38;2;189;147;249m"
    Number    = "$esc[38;2;255;184;108m"
    Comment   = "$esc[38;2;108;117;125m"
    Error     = "$esc[38;2;255;85;85m"
  }
  # grey suggestions from history while you type (PSReadLine 2.1+, i.e. PowerShell 7 or an updated 5.1)
  if ((Get-Module PSReadLine).Version -ge [version]'2.1.0') {
    try { Set-PSReadLineOption -PredictionSource History -ErrorAction Stop } catch { }
  }
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
  Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
  Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

  # fzf: Ctrl+R history, Ctrl+T files, Alt+C directories (like fzf's key-bindings.zsh)
  if (_has 'fzf') {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'fzf history' -ScriptBlock {
      $hist = (Get-PSReadLineOption).HistorySavePath
      if (-not (Test-Path -LiteralPath $hist)) { return }
      $line = $null; $cursor = $null
      [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
      $lines = [System.Collections.Generic.List[string]]::new()
      foreach ($l in [IO.File]::ReadAllLines($hist)) { if ($l -and -not $lines.Contains($l)) { $lines.Add($l) } }
      $lines.Reverse()
      $pick = $lines | fzf --height 40% --reverse --no-sort --query $line
      [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
      if ($pick) {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($pick)
      }
    }
    Set-PSReadLineKeyHandler -Chord 'Ctrl+t' -BriefDescription 'fzf file' -ScriptBlock {
      $pick = if (_has 'rg') { rg --files --hidden --glob '!.git' 2>$null | fzf --height 40% --reverse } else { fzf --height 40% --reverse }
      [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
      if ($pick) { if ($pick -match '\s') { $pick = "'$pick'" }; [Microsoft.PowerShell.PSConsoleReadLine]::Insert($pick) }
    }
    Set-PSReadLineKeyHandler -Chord 'Alt+c' -BriefDescription 'fzf cd' -ScriptBlock {
      $pick = Get-ChildItem -Directory -Recurse -Depth 4 -Name -ErrorAction SilentlyContinue | fzf --height 40% --reverse
      if ($pick) { Set-Location -LiteralPath $pick }
      [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
  }
}

# -- aliases, each one optional ----------------------------------------------------
if (_has 'eza') {
  Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
  function ls { eza --group-directories-first --icons=auto @args }
  function ll { eza -lh --group-directories-first --icons=auto --git @args }
  function la { eza -lah --group-directories-first --icons=auto --git @args }
} else {
  function ll { Get-ChildItem @args }
  function la { Get-ChildItem -Force @args }
}
function n { nvim @args }
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function which([string]$name) { Get-Command $name -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue }
function touch([string]$path) { if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).LastWriteTime = Get-Date } else { New-Item -ItemType File -Path $path | Out-Null } }

# a few of Oh My Zsh's git aliases (only those that do not hide a built-in PowerShell alias such as gc, gp, gl)
if (_has 'git') {
  function g { git @args }
  function ga { git add @args }
  function gst { git status @args }
  function gd { git diff @args }
  function gco { git checkout @args }
  function gb { git branch @args }
  function glog { git log --oneline --decorate --graph @args }
}

if (_has 'zoxide') { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }

# -- prompt --------------------------------------------------------------------------
if (_has 'starship') {
  $env:STARSHIP_CONFIG = "$HOME\.config\starship.toml"
  Invoke-Expression (& starship init powershell --print-full-init | Out-String)
}

# -- machine-local overrides (not in the repo) ------------------------------------------
$local = "$HOME\.config\powershell\local.ps1"
if (Test-Path -LiteralPath $local) { . $local }
Remove-Variable local, d, esc -ErrorAction SilentlyContinue
