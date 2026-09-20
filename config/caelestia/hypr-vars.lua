-- ~/.config/caelestia/hypr-vars.lua  (managed by rhmatzeka/dotfile)
-- Overrides for the variables in Caelestia's ~/.config/hypr/variables.lua. Never edit ~/.config/hypr itself.
return {
  terminal = "ghostty",

  -- Vim-style keys (arrow keys keep working). Super+K/L are used to focus windows,
  -- so the panels / lock / sleep bindings move elsewhere.
  kbShowPanels  = "SUPER + B",
  kbLock        = "SUPER + Escape",
  kbRestoreLock = "SUPER + ALT + Escape",
  kbSleep       = "SUPER + SHIFT + Escape",

  -- Switch workspace: Ctrl+Super+H / L
  kbPrevWs = { "SUPER + mouse_up", "CTRL + SUPER + Left", "SUPER + Page_Up", "CTRL + SUPER + H" },
  kbNextWs = { "SUPER + mouse_down", "CTRL + SUPER + Right", "SUPER + Page_Down", "CTRL + SUPER + L" },

  -- Move a window to the neighbouring workspace: Ctrl+Super+Shift+H / L; special workspace: Ctrl+Super+Shift+K / J
  kbMoveWinToWsPrev      = { "SUPER + ALT + mouse_up", "SUPER + ALT + Page_Up", "CTRL + SUPER + SHIFT + Left", "CTRL + SUPER + SHIFT + H" },
  kbMoveWinToWsNext      = { "SUPER + ALT + mouse_down", "SUPER + ALT + Page_Down", "CTRL + SUPER + SHIFT + Right", "CTRL + SUPER + SHIFT + L" },
  kbMoveWinToWsSpecial   = { "SUPER + ALT + S", "CTRL + SUPER + SHIFT + Up", "CTRL + SUPER + SHIFT + K" },
  kbMoveWinFromWsSpecial = { "CTRL + SUPER + SHIFT + Down", "CTRL + SUPER + SHIFT + J" },

  -- Resize a window: Super+Alt+H / J / K / L
  kbWindowDecreaseWidth  = { "SUPER + Minus", "SUPER + ALT + Left", "SUPER + ALT + H" },
  kbWindowIncreaseWidth  = { "SUPER + Equal", "SUPER + ALT + Right", "SUPER + ALT + L" },
  kbWindowDecreaseHeight = { "SUPER + SHIFT + Minus", "SUPER + ALT + Up", "SUPER + ALT + K" },
  kbWindowIncreaseHeight = { "SUPER + SHIFT + Equal", "SUPER + ALT + Down", "SUPER + ALT + J" },
}
