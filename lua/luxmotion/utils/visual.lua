local M = {}

function M.get_mode()
  return vim.fn.mode()
end

function M.save_selection()
  return {
    start_pos = vim.fn.getpos("'<"),
    end_pos = vim.fn.getpos("'>"),
    mode = M.get_mode()
  }
end

function M.restore_selection(selection)
  vim.fn.setpos("'<", selection.start_pos)
  vim.fn.setpos("'>", selection.end_pos)
  vim.cmd('normal! gv')
end

function M.exit_visual_mode()
  vim.cmd('normal! \\<Esc>')
end

function M.is_visual_mode(mode)
  mode = mode or M.get_mode()
  return mode == 'v' or mode == 'V' or mode == ''
end

return M