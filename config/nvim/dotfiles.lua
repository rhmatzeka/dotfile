-- Extra plugin specs on top of the NvChad starter.
-- Linked to ~/.config/nvim/lua/plugins/dotfiles.lua by rhmatzeka/dotfile; edit it in ~/.dotfiles/config/nvim/.

return {
  -- Syntax highlighting. Without the html/css/js parsers, a .php or .vue file that is mostly markup stays plain white.
  -- Parsers are built with the `tree-sitter` CLI, which the installer puts in ~/.local/bin.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "vim", "lua", "vimdoc", "bash", "html", "css", "javascript", "typescript", "tsx",
        "json", "yaml", "toml", "markdown", "markdown_inline", "php", "phpdoc", "sql",
      },
    },
  },

  -- Same as the starter's own lspconfig spec, plus a few more servers.
  -- The binaries come from Mason (see mason-packages next to this file; the installer installs them).
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
      vim.lsp.enable { "lua_ls", "ts_ls", "bashls", "jsonls" }
    end,
  },
}
