# dotfiles

A one-command setup for a Linux terminal and desktop: zsh, tmux, Neovim, Ghostty, terminal browsers, and an optional
Hyprland + Caelestia desktop. Nothing is overwritten without a backup, and everything can be undone.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh)
```

## Preview

<!--
  ADD YOUR VIDEO HERE (full instructions: docs/adding-a-preview.md)
  1. Open this file on github.com and click the pencil icon (Edit).
  2. Drag and drop your .mp4 / .mov into the editor. GitHub uploads it and inserts a link like
     https://github.com/user-attachments/assets/<id>
  3. Keep that link on a line of its own (that turns it into a player), delete the placeholder image below, commit.
  A GIF works too: ![Demo](docs/demo.gif)
-->

![Preview video coming soon](docs/preview-placeholder.svg)

## Install

Use `bash <(...)` rather than `curl | bash`: it keeps your terminal attached, so the menu and the `sudo` password
prompt work. **Read a script before you run it.** You can look at this one first:

```bash
curl -fsSL https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh | less
```

Every step can be rehearsed without changing anything:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh) --dry-run --all
```

A short domain (`dotfiles.rahmateka.my.id`) can serve the same script; see [docs/short-domain.md](docs/short-domain.md).
Until that is set up, use the GitHub URL above.

## What you get

| Component | Contents |
|---|---|
| `base` | Base packages (git, fzf, ripgrep, eza, zoxide, ...) and the JetBrainsMono Nerd Font |
| `shell` | zsh, Oh My Zsh (autosuggestions, syntax highlighting) and the starship prompt |
| `tmux` | tmux with a cyan / Dracula theme |
| `nvim` | Neovim + NvChad, tree-sitter parsers (html, css, js, php, ...) and LSP servers through Mason |
| `terminal` | Ghostty config: dark theme, Vim-style keys |
| `browsers` | Terminal browsers: Browsh (Firefox in the terminal), elinks, w3m |
| `desktop` | Hyprland + Caelestia shell. **Debian 13 only, beta.** Builds Qt 6.11 from source (1 to 2 hours) |

The default selection is everything except `desktop`.

## Supported systems

| System | Status |
|---|---|
| Debian 13 (trixie) | `base`, `shell`, `tmux`, `nvim`, `terminal`, `browsers` installed and checked **from scratch in a clean Debian 13**. `desktop`: the package lists are validated; the source build has not been re-run through this script yet (beta) |
| Ubuntu 24.04 LTS | Same six components installed and checked from scratch in a clean Ubuntu. Not in Ubuntu's repositories, so handled differently: `starship` uses its official installer, `fastfetch` is skipped, and Browsh is skipped (no `firefox-esr` package), while elinks and w3m are installed |
| Ubuntu 26.04 LTS | Same six components installed and checked from scratch in a clean Ubuntu. `starship` and `fastfetch` come straight from apt here. Browsh is skipped (no `firefox-esr` package); elinks and w3m are installed |
| Arch, Fedora, macOS | **Not supported yet.** Contributions are welcome (see below) |

`desktop` is Debian 13 only because it depends on `trixie-backports` (Hyprland) and on pinned build versions.

### How this was tested

- Real installs into **clean root filesystems** (a minimal Debian 13 and minimal Ubuntu images), as a normal user, with
  the results inspected afterwards: tool versions, fonts, tmux and zsh reading their config, 18 tree-sitter parsers and
  7 LSP servers in Neovim, and syntax colours on a PHP file that mixes HTML and JavaScript.
- A user who **already has their own config files**: they are backed up, a second install does not back them up
  again, and `uninstall` puts the originals back. The whole flow was also run through the public GitHub URL.
- `--dry-run` for every component, shellcheck, and a GitHub Actions run on Ubuntu for every push.
- Failures are not swallowed: a failed `apt` step fails its component and the installer exits non-zero.

**Not tested:** the `desktop` source build from scratch, any distribution not listed above, and ARM machines.

## Usage

```bash
./install.sh                    # interactive menu
./install.sh --all              # every component, including desktop
./install.sh --only shell,nvim  # pick components
./install.sh --dry-run --all    # show what would happen, change nothing
./install.sh --yes              # no questions, use the default answers
./install.sh --list             # list the components
```

Through `curl`, put the options after the command, for example
`bash <(curl -fsSL <url>) --only shell,tmux`.

## Safety

- A file that would be replaced is **moved** to `~/.dotfiles-backup/<timestamp>/`, never overwritten.
- Every symlink it creates is recorded, so `uninstall` only undoes what this installer did.
- `sudo` is used only to install packages and, for `desktop`, to write under `/opt` and `/usr/local`.
- Run it as a normal user, not as root.

## Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rhmatzeka/dotfile/main/uninstall.sh)
```

The links are removed and your original files come back. Packages, fonts, Oh My Zsh and anything built under `/opt`
are left in place; the list is printed at the end.

## How it works

The top-level `install.sh` detects the OS, fetches this repository to `~/.dotfiles`, and hands over to the installer for
that platform (`linux/debian/install.sh`). Configs live in `config/` and are installed as symlinks, so editing them
in `~/.dotfiles` takes effect immediately. Shared helpers (backup, symlinks, dry run) are in `lib/common.sh`.

```
install.sh  uninstall.sh        entry points (OS detection)
lib/common.sh                   shared helpers
linux/debian/                   Debian/Ubuntu installer: install.sh, uninstall.sh, desktop.sh
config/                         zsh, starship, tmux, nvim, ghostty, elinks, caelestia
bin/                            small scripts (web, firefox-for-browsh)
docs/                           preview placeholder, how-tos
```

## Adding another OS

Create `linux/<name>/install.sh` and `uninstall.sh` (see `linux/debian/` for the shape) and add the OS to the detection
in `install.sh`. Use the helpers in `lib/common.sh` so that `--dry-run` and backups keep working. Pull requests are
welcome; please say in the description which system you actually tested on.

## License and credits

The code in this repository is MIT licensed. The colour palette is [Dracula](https://draculatheme.com) (MIT) with a cyan
accent. These are downloaded during installation and are **not** redistributed here: Oh My Zsh (MIT), the NvChad starter
(Unlicense), Browsh (LGPL-2.1), quickshell and the Caelestia shell/CLI (GPL-3.0, built from source), and the Hyprland
configuration from `caelestia-dots/caelestia` (cloned from upstream).
