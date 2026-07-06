local orchestrator = require("whisk.engine.orchestrator")

local M = {}

local deprecated_warned = false
local function warn_deprecated()
  if not deprecated_warned then
    vim.notify(
      "[whisk] cursor.keymaps is deprecated. Use whisk.engine.orchestrator instead. See :help whisk-migration",
      vim.log.levels.WARN
    )
    deprecated_warned = true
  end
end

local function map_basic_motion(direction)
  local mapping = {
    h = "basic_h",
    j = "basic_j",
    k = "basic_k",
    l = "basic_l",
    ["0"] = "basic_0",
    ["$"] = "basic_$",
  }
  return mapping[direction]
end

local function map_word_motion(direction)
  return "word_" .. direction
end

local function map_find_motion(direction)
  return "find_" .. direction
end

local function map_text_object_motion(direction)
  return "text_object_" .. direction
end

local function map_line_motion(direction)
  return "line_" .. direction
end

local function map_search_motion(direction)
  return "search_" .. direction
end

function M.smooth_move(direction, count)
  warn_deprecated()
  local motion_id = map_basic_motion(direction)
  if motion_id then
    orchestrator.execute(motion_id, { count = count or 1, direction = direction })
  end
end

function M.smooth_word_move(direction, count)
  warn_deprecated()
  orchestrator.execute(map_word_motion(direction), { count = count or 1, direction = direction })
end

function M.smooth_find_move(direction, char, count)
  warn_deprecated()
  orchestrator.execute(map_find_motion(direction), { char = char, count = count or 1, direction = direction })
end

function M.smooth_text_object_move(direction, count)
  warn_deprecated()
  orchestrator.execute(map_text_object_motion(direction), { count = count or 1, direction = direction })
end

function M.smooth_line_move(direction, count)
  warn_deprecated()
  orchestrator.execute(map_line_motion(direction), { count = count, direction = direction })
end

function M.smooth_search_move(direction, count)
  warn_deprecated()
  orchestrator.execute(map_search_motion(direction), { count = count or 1, direction = direction })
end

function M.smooth_screen_line_move(direction, count)
  warn_deprecated()
  orchestrator.execute("screen_" .. direction, { count = count or 1, direction = direction })
end

function M.setup_keymaps()
end

return M
