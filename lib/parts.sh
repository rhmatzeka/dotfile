# shellcheck shell=bash
# Steps that are the same on Linux and macOS once the packages are there. Source lib/common.sh first and set C to
# the repository's config/ directory. bash 3.2 safe (macOS).

# Oh My Zsh with the two plugins, then the zsh and starship configs from the repo
shell_configs() {
  git_clone https://github.com/ohmyzsh/ohmyzsh "$HOME/.oh-my-zsh"
  git_clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  git_clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  backup_and_link "$C/zsh/zshrc" "$HOME/.zshrc"
  backup_and_link "$C/starship/starship.toml" "$HOME/.config/starship.toml"
}

# The NvChad starter (unless the user already has an nvim config of their own), the repo's plugin spec, then a
# headless first run: plugins, tree-sitter parsers and the Mason LSP servers. Needs nvim, git, node/npm, a C compiler.
nvchad_setup() {
  local cfg="$HOME/.config/nvim" marker="$HOME/.config/nvim/.rhmatzeka-dotfiles"
  if [ -e "$cfg" ] && [ ! -e "$marker" ]; then
    warn "an nvim config already exists at ~/.config/nvim: leaving it untouched."
    warn "Add $C/nvim/dotfiles.lua to its lua/plugins/ if you want the extra parsers/LSP."
    return 0
  fi
  if [ ! -e "$cfg" ]; then
    info "cloning the NvChad starter"
    if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would clone NvChad/starter"
    else git clone -q --depth 1 https://github.com/NvChad/starter "$cfg" && rm -rf "$cfg/.git" && : >"$marker"; fi
  fi
  [ "$DRY_RUN" = 1 ] || mkdir -p "$cfg/lua/plugins"
  backup_and_link "$C/nvim/dotfiles.lua" "$cfg/lua/plugins/dotfiles.lua"

  [ "$DRY_RUN" = 1 ] && { info "[dry-run] would sync plugins, build tree-sitter parsers and install LSP servers"; return 0; }
  info "syncing plugins (first run, a minute or two)"
  with_timeout 600 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || warn "plugin sync reported a problem; it will retry when you open nvim"
  info "building tree-sitter parsers"
  with_timeout 600 nvim --headless "+Lazy load nvim-treesitter" "+lua local ok,e=pcall(function() require('nvim-treesitter').install(dofile(vim.fn.stdpath('config')..'/lua/plugins/dotfiles.lua')[1].opts.ensure_installed):wait(540000) end) if not ok then print(e) end" +qa >/dev/null 2>&1 \
    || warn "parser build reported a problem; check :checkhealth nvim-treesitter"
  info "installing LSP servers and formatters (Mason)"
  with_timeout 900 nvim --headless "+Lazy load mason.nvim" "+MasonInstall $(paste -sd' ' "$C/nvim/mason-packages")" "+qall" >/dev/null 2>&1 \
    || warn "Mason reported a problem; run :Mason inside nvim to see which package failed"
  ok "Neovim is ready"
}

# elinks config; DOWNLOADS = where it should save files
elinks_configs() {
  local downloads="$1"
  # elinks saves into the current directory by default; point it at the Downloads folder (absolute path, this file is per machine)
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] would write ~/.config/elinks/local.conf (download folder)"
  else
    mkdir -p "$HOME/.config/elinks" "$downloads"
    printf '## written by rhmatzeka/dotfile: where elinks saves downloads\nset document.download.directory = "%s/"\n' "$downloads" >"$HOME/.config/elinks/local.conf"
  fi
  backup_and_link "$C/elinks/elinks.conf" "$HOME/.config/elinks/elinks.conf"
}

# rustup from rustup.rs (stable toolchain, shell files untouched: the zsh config puts ~/.cargo/bin on PATH)
rustup_setup() {
  if have rustup || [ -x "$HOME/.cargo/bin/rustup" ]; then
    ok "rustup already installed"
  elif [ "$DRY_RUN" = 1 ]; then info "[dry-run] would run the official rustup installer (rustup.rs)"
  else
    info "running the official rustup installer (stable toolchain, no changes to your shell files)"
    curl -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile default \
      || { fail "rustup installer failed"; return 1; }
  fi
  if [ "$DRY_RUN" != 1 ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    rustup component add rust-analyzer clippy rustfmt >/dev/null 2>&1 || warn "could not add rust-analyzer/clippy/rustfmt"
    ok "$(rustc --version 2>/dev/null)"
  fi
  info "\$HOME/.cargo/bin must be on your PATH (the zsh config from this repo does that)."
}
