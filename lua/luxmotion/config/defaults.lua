local M = {}

M.config = {
  cursor = {
    duration = 250,
    easing = "ease-out",
    enabled = true,
  },
  scroll = {
    duration = 400,
    easing = "ease-out",
    enabled = true,
  },
  keymaps = {
    cursor = true,
    scroll = true,
    experimental = false,
  },
}

return M
