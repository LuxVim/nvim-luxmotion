local motions = require("whisk.registry.motions")
local orchestrator = require("whisk.engine.orchestrator")
local config = require("whisk.config")

local M = {}

function M.create_handler(motion)
  if motion.input == "char" then
    return function()
      local char = vim.fn.getcharstr()
      orchestrator.execute(motion.id, {
        char = char,
        count = vim.v.count1,
        direction = motion.keys[1],
        has_count = vim.v.count > 0,
      })
    end
  else
    return function()
      orchestrator.execute(motion.id, {
        count = vim.v.count1,
        direction = motion.keys[1],
        has_count = vim.v.count > 0,
      })
    end
  end
end

function M.setup()
  local keymap_config = config.get_keymaps()

  for motion_id, motion in pairs(motions.all()) do
    if keymap_config[motion.category] == false then
      goto continue
    end

    local handler = M.create_handler(motion)

    for _, key in ipairs(motion.keys) do
      for _, mode in ipairs(motion.modes) do
        vim.keymap.set(mode, key, handler, {
          desc = "Smooth " .. motion.description,
          silent = true,
        })
      end
    end

    ::continue::
  end
end

function M.clear()
  for _, motion in pairs(motions.all()) do
    for _, key in ipairs(motion.keys) do
      for _, mode in ipairs(motion.modes) do
        pcall(vim.keymap.del, mode, key)
      end
    end
  end
end

return M
