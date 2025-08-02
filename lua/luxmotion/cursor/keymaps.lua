local cursor_animation = require("luxmotion.cursor.animation")
local viewport = require("luxmotion.core.viewport")
local cursor_movement = require("luxmotion.cursor.movement")
local config = require("luxmotion.config")

local M = {}

function M.smooth_move(direction, count)
  count = count or 1
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    -- Fall back to normal Vim movement
    local normal_count = count > 1 and tostring(count) or ""
    vim.cmd("normal! " .. normal_count .. direction)
    return
  end
  
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line = cursor_movement.calculate_target_line(current_line, direction, count)
  local target_col = cursor_movement.calculate_target_col(current_col, direction, count, current_line)
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.smooth_word_move(direction, count)
  count = count or 1
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    -- Fall back to normal Vim movement
    local normal_count = count > 1 and tostring(count) or ""
    vim.cmd("normal! " .. normal_count .. direction)
    return
  end
  
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line, target_col = cursor_movement.calculate_word_target(direction, count)
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.smooth_find_move(direction, char, count)
  count = count or 1
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    -- Fall back to normal Vim movement
    local normal_count = count > 1 and tostring(count) or ""
    vim.cmd("normal! " .. normal_count .. direction .. char)
    return
  end
  
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line, target_col = cursor_movement.calculate_find_target(direction, char, count)
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.smooth_text_object_move(direction, count)
  count = count or 1
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    -- Fall back to normal Vim movement
    local normal_count = count > 1 and tostring(count) or ""
    vim.cmd("normal! " .. normal_count .. direction)
    return
  end
  
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line, target_col = cursor_movement.calculate_text_object_target(direction, count)
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.smooth_line_move(direction, count)
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    -- Fall back to normal Vim movement
    local normal_count = count and count > 1 and tostring(count) or ""
    vim.cmd("normal! " .. normal_count .. direction)
    return
  end
  
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line, target_col = cursor_movement.calculate_line_target(direction, count)
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.smooth_search_move(direction, count)
  count = count or 1
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    -- Fall back to normal Vim movement
    local normal_count = count > 1 and tostring(count) or ""
    vim.cmd("normal! " .. normal_count .. direction)
    return
  end
  
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line, target_col = cursor_movement.calculate_search_target(direction, count)
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.smooth_screen_line_move(direction, count)
  count = count or 1
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    -- Fall back to normal Vim movement
    local normal_count = count > 1 and tostring(count) or ""
    vim.cmd("normal! " .. normal_count .. direction)
    return
  end
  
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line, target_col = cursor_movement.calculate_screen_line_target(direction, count)
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.setup_keymaps()
  vim.keymap.set("n", "j", function()
    M.smooth_move("j", vim.v.count1)
  end, { desc = "Smooth move down" })

  vim.keymap.set("n", "k", function()
    M.smooth_move("k", vim.v.count1)
  end, { desc = "Smooth move up" })

  vim.keymap.set("n", "h", function()
    M.smooth_move("h", vim.v.count1)
  end, { desc = "Smooth move left" })

  vim.keymap.set("n", "l", function()
    M.smooth_move("l", vim.v.count1)
  end, { desc = "Smooth move right" })

  -- Visual mode keymaps
  vim.keymap.set("v", "j", function()
    M.smooth_move("j", vim.v.count1)
  end, { desc = "Smooth move down (visual)" })

  vim.keymap.set("v", "k", function()
    M.smooth_move("k", vim.v.count1)
  end, { desc = "Smooth move up (visual)" })

  vim.keymap.set("v", "h", function()
    M.smooth_move("h", vim.v.count1)
  end, { desc = "Smooth move left (visual)" })

  vim.keymap.set("v", "l", function()
    M.smooth_move("l", vim.v.count1)
  end, { desc = "Smooth move right (visual)" })

  vim.keymap.set("n", "0", function()
    M.smooth_move("0", 1)
  end, { desc = "Smooth move to beginning of line" })

  vim.keymap.set("n", "$", function()
    M.smooth_move("$", 1)
  end, { desc = "Smooth move to end of line" })

  vim.keymap.set("v", "0", function()
    M.smooth_move("0", 1)
  end, { desc = "Smooth move to beginning of line (visual)" })

  vim.keymap.set("v", "$", function()
    M.smooth_move("$", 1)
  end, { desc = "Smooth move to end of line (visual)" })

  -- Word movement keymaps
  vim.keymap.set("n", "w", function()
    M.smooth_word_move("w", vim.v.count1)
  end, { desc = "Smooth word forward" })

  vim.keymap.set("n", "b", function()
    M.smooth_word_move("b", vim.v.count1)
  end, { desc = "Smooth word backward" })

  vim.keymap.set("n", "e", function()
    M.smooth_word_move("e", vim.v.count1)
  end, { desc = "Smooth end of word" })

  -- Visual mode word movements
  vim.keymap.set("v", "w", function()
    M.smooth_word_move("w", vim.v.count1)
  end, { desc = "Smooth word forward (visual)" })

  vim.keymap.set("v", "b", function()
    M.smooth_word_move("b", vim.v.count1)
  end, { desc = "Smooth word backward (visual)" })

  vim.keymap.set("v", "e", function()
    M.smooth_word_move("e", vim.v.count1)
  end, { desc = "Smooth end of word (visual)" })

  -- WORD movement keymaps (W, B, E)
  vim.keymap.set("n", "W", function()
    M.smooth_word_move("W", vim.v.count1)
  end, { desc = "Smooth WORD forward" })

  vim.keymap.set("n", "B", function()
    M.smooth_word_move("B", vim.v.count1)
  end, { desc = "Smooth WORD backward" })

  vim.keymap.set("n", "E", function()
    M.smooth_word_move("E", vim.v.count1)
  end, { desc = "Smooth end of WORD" })

  vim.keymap.set("v", "W", function()
    M.smooth_word_move("W", vim.v.count1)
  end, { desc = "Smooth WORD forward (visual)" })

  vim.keymap.set("v", "B", function()
    M.smooth_word_move("B", vim.v.count1)
  end, { desc = "Smooth WORD backward (visual)" })

  vim.keymap.set("v", "E", function()
    M.smooth_word_move("E", vim.v.count1)
  end, { desc = "Smooth end of WORD (visual)" })

  -- Find character movements (f, F, t, T)
  vim.keymap.set("n", "f", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("f", char, vim.v.count1)
  end, { desc = "Smooth find character forward" })

  vim.keymap.set("n", "F", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("F", char, vim.v.count1)
  end, { desc = "Smooth find character backward" })

  vim.keymap.set("n", "t", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("t", char, vim.v.count1)
  end, { desc = "Smooth till character forward" })

  vim.keymap.set("n", "T", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("T", char, vim.v.count1)
  end, { desc = "Smooth till character backward" })

  vim.keymap.set("v", "f", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("f", char, vim.v.count1)
  end, { desc = "Smooth find character forward (visual)" })

  vim.keymap.set("v", "F", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("F", char, vim.v.count1)
  end, { desc = "Smooth find character backward (visual)" })

  vim.keymap.set("v", "t", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("t", char, vim.v.count1)
  end, { desc = "Smooth till character forward (visual)" })

  vim.keymap.set("v", "T", function()
    local char = vim.fn.getcharstr()
    M.smooth_find_move("T", char, vim.v.count1)
  end, { desc = "Smooth till character backward (visual)" })

  -- Text object movements ({, }, (, ), %)
  vim.keymap.set("n", "}", function()
    M.smooth_text_object_move("}", vim.v.count1)
  end, { desc = "Smooth paragraph forward" })

  vim.keymap.set("n", "{", function()
    M.smooth_text_object_move("{", vim.v.count1)
  end, { desc = "Smooth paragraph backward" })

  vim.keymap.set("n", ")", function()
    M.smooth_text_object_move(")", vim.v.count1)
  end, { desc = "Smooth sentence forward" })

  vim.keymap.set("n", "(", function()
    M.smooth_text_object_move("(", vim.v.count1)
  end, { desc = "Smooth sentence backward" })

  vim.keymap.set("n", "%", function()
    M.smooth_text_object_move("%", vim.v.count1)
  end, { desc = "Smooth matching bracket" })

  vim.keymap.set("v", "}", function()
    M.smooth_text_object_move("}", vim.v.count1)
  end, { desc = "Smooth paragraph forward (visual)" })

  vim.keymap.set("v", "{", function()
    M.smooth_text_object_move("{", vim.v.count1)
  end, { desc = "Smooth paragraph backward (visual)" })

  vim.keymap.set("v", ")", function()
    M.smooth_text_object_move(")", vim.v.count1)
  end, { desc = "Smooth sentence forward (visual)" })

  vim.keymap.set("v", "(", function()
    M.smooth_text_object_move("(", vim.v.count1)
  end, { desc = "Smooth sentence backward (visual)" })

  vim.keymap.set("v", "%", function()
    M.smooth_text_object_move("%", vim.v.count1)
  end, { desc = "Smooth matching bracket (visual)" })

  -- Line jump movements (gg, G, |)
  vim.keymap.set("n", "gg", function()
    M.smooth_line_move("gg", vim.v.count1)
  end, { desc = "Smooth goto first line" })

  vim.keymap.set("n", "G", function()
    M.smooth_line_move("G", vim.v.count1)
  end, { desc = "Smooth goto last line" })

  vim.keymap.set("n", "|", function()
    M.smooth_line_move("|", vim.v.count1)
  end, { desc = "Smooth goto column" })

  vim.keymap.set("v", "gg", function()
    M.smooth_line_move("gg", vim.v.count1)
  end, { desc = "Smooth goto first line (visual)" })

  vim.keymap.set("v", "G", function()
    M.smooth_line_move("G", vim.v.count1)
  end, { desc = "Smooth goto last line (visual)" })

  vim.keymap.set("v", "|", function()
    M.smooth_line_move("|", vim.v.count1)
  end, { desc = "Smooth goto column (visual)" })

  -- Search movements (n, N)
  vim.keymap.set("n", "n", function()
    M.smooth_search_move("n", vim.v.count1)
  end, { desc = "Smooth next search result" })

  vim.keymap.set("n", "N", function()
    M.smooth_search_move("N", vim.v.count1)
  end, { desc = "Smooth previous search result" })

  vim.keymap.set("v", "n", function()
    M.smooth_search_move("n", vim.v.count1)
  end, { desc = "Smooth next search result (visual)" })

  vim.keymap.set("v", "N", function()
    M.smooth_search_move("N", vim.v.count1)
  end, { desc = "Smooth previous search result (visual)" })

  -- Screen line movements (gj, gk)
  vim.keymap.set("n", "gj", function()
    M.smooth_screen_line_move("gj", vim.v.count1)
  end, { desc = "Smooth down screen line" })

  vim.keymap.set("n", "gk", function()
    M.smooth_screen_line_move("gk", vim.v.count1)
  end, { desc = "Smooth up screen line" })

  vim.keymap.set("v", "gj", function()
    M.smooth_screen_line_move("gj", vim.v.count1)
  end, { desc = "Smooth down screen line (visual)" })

  vim.keymap.set("v", "gk", function()
    M.smooth_screen_line_move("gk", vim.v.count1)
  end, { desc = "Smooth up screen line (visual)" })
end

return M