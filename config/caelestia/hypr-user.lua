-- ~/.config/caelestia/hypr-user.lua  (managed by rhmatzeka/dotfile)
-- Personal Hyprland additions. Caelestia updates never touch this file.

-- Debian has no polkit-gnome; the MATE polkit agent does the same job
hl.on("hyprland.start", function()
    hl.exec_cmd("mate-polkit")
end)

-- Ghostty: skip the global 0.95 window opacity, so `background-opacity` in
-- ~/.config/ghostty/config.ghostty is the real transparency value
hl.window_rule({ match = { class = "com.mitchellh.ghostty" }, opacity = "1.0 override" })

-- Slower 4-finger workspace swipe (Caelestia default: distance 300, cancel_ratio 0.15, min_speed_to_force 5,
-- workspaces animation speed 5). A higher distance/ratio needs a longer swipe; a higher animation speed value is slower.
hl.config({
    gestures = {
        workspace_swipe_distance           = 600,
        workspace_swipe_cancel_ratio       = 0.3,
        workspace_swipe_min_speed_to_force = 20,
    },
})
hl.animation({ leaf = "workspaces", enabled = true, speed = 8, bezier = "standard" })

-- Dwindle layout: flip the focused window's split between side-by-side and stacked, and swap the two halves
hl.bind("SUPER + O", hl.dsp.layout("togglesplit"))
hl.bind("SUPER + SHIFT + O", hl.dsp.layout("swapsplit"))

-- Vim-style window navigation: Super+J/K/L focus (down/up/right), Super+Shift+H/J/K/L move the window.
-- Super+H HIDES the focused window: it is sent quietly to workspace 10 (not the scratchpad, which overlays every workspace
-- and stops workspace swiping). Bring it back: Super+0, then Super+Alt+1..9 to move it to a workspace.
-- Focus left: Super+Left arrow.
for key, dir in pairs({ J = "down", K = "up", L = "right" }) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = dir }))
end
for key, dir in pairs({ H = "left", J = "down", K = "up", L = "right" }) do
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end
hl.bind("SUPER + H", hl.dsp.window.move({ workspace = "10", follow = false }))
