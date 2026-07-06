local Context = require('whisk.context.Context')

local M = {}

function M.build(input)
  local ctx = Context.new()

  ctx.input = {
    char = input.char,
    count = input.count or 1,
    direction = input.direction,
    has_count = input.has_count or false,
  }

  ctx.cursor = {
    line = ctx.start.cursor[1],
    col = ctx.start.cursor[2],
  }

  ctx.viewport = {
    topline = ctx.start.topline,
    height = vim.api.nvim_win_get_height(ctx.winid),
    width = vim.api.nvim_win_get_width(ctx.winid),
  }

  ctx.buffer = {
    line_count = ctx.start.line_count,
  }

  return ctx
end

return M
