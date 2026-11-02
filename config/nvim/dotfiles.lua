-- Extra plugin specs on top of the NvChad starter.
-- Linked to ~/.config/nvim/lua/plugins/dotfiles.lua by rhmatzeka/dotfile; edit it in ~/.dotfiles/config/nvim/.
-- (On Windows: %LOCALAPPDATA%\nvim\lua\plugins\dotfiles.lua.)

-- Windows: tree-sitter builds parsers with Visual Studio's cl.exe unless CC names another compiler. The Windows
-- installer brings GCC (WinLibs) when there is no Visual Studio, so point CC at it. Nothing happens on Linux/macOS.
if vim.fn.has("win32") == 1 and (vim.env.CC or "") == "" and vim.fn.executable("cl") == 0 and vim.fn.executable("gcc") == 1 then
  vim.env.CC = "gcc"
end

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
