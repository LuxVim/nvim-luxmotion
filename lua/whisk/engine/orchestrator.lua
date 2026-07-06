local traits = require("whisk.registry.traits")
local motions = require("whisk.registry.motions")
local context_builder = require("whisk.context.builder")
local loop = require("whisk.engine.loop")
local config = require("whisk.config")

local M = {}

local function is_same_position(context, result)
  if not result.cursor then
    return false
  end
  return context.cursor.line == result.cursor.line and context.cursor.col == result.cursor.col
end

local function is_same_viewport(context, result)
  if not result.viewport or not result.viewport.topline then
    return true
  end
  return context.viewport.topline == result.viewport.topline
end

function M.execute(motion_id, input)
  local motion = motions.get(motion_id)
  if not motion then
    return
  end

  local category_config = config.get(motion.category)
  if not category_config or not category_config.enabled then
    M.fallback(motion, input)
    return
  end

  local dominated = false
  for _, trait_id in ipairs(motion.traits) do
    if traits.is_animating(trait_id) then
      dominated = true
    end
  end

  if dominated then
    loop.complete_all()
  end

  local context = context_builder.build(input)
  local result = motion.calculator(context)

  if not result then
    return
  end

  if is_same_position(context, result) and is_same_viewport(context, result) then
    return
  end

  for _, trait_id in ipairs(motion.traits) do
    traits.set_animating(trait_id, true)
  end

  local function clear_animating()
    for _, trait_id in ipairs(motion.traits) do
      traits.set_animating(trait_id, false)
    end
  end

  loop.start({
    context = context,
    result = result,
    traits = motion.traits,
    duration = category_config.duration,
    easing = category_config.easing,
    on_complete = clear_animating,
    on_cancel = clear_animating,
  })
end

function M.fallback(motion, input)
  local cmd = ""
  if input.count and input.count > 1 then
    cmd = tostring(input.count)
  end
  cmd = cmd .. (input.direction or motion.keys[1])
  if input.char then
    cmd = cmd .. input.char
  end
  vim.cmd("normal! " .. cmd)
end

return M
