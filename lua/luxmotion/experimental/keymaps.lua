local scroll_keymaps = require("luxmotion.scroll.keymaps")

local M = {}

function M.setup_keymaps()
  vim.keymap.set("n", "gg", function()
    scroll_keymaps.smooth_position("gg")
  end, { desc = "Smooth goto first line" })

  vim.keymap.set("n", "G", function()
    scroll_keymaps.smooth_position("G")
  end, { desc = "Smooth goto last line" })
end

return M