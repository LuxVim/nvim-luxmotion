local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('performance', function()
  local performance

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({ "line 1", "line 2", "line 3" })
    performance = require('whisk.performance')
    performance.disable()
  end)

  it('exports all required functions', function()
    assert.is_type(performance.should_auto_enable, 'function')
    assert.is_type(performance.enable, 'function')
    assert.is_type(performance.disable, 'function')
    assert.is_type(performance.is_active, 'function')
    assert.is_type(performance.get_frame_interval, 'function')
    assert.is_type(performance.should_ignore_event, 'function')
    assert.is_type(performance.auto_toggle, 'function')
    assert.is_type(performance.setup, 'function')
  end)

  it('is_active returns false initially', function()
    assert.is_false(performance.is_active())
  end)

  it('enable activates performance mode', function()
    performance.enable()
    assert.is_true(performance.is_active())
  end)

  it('disable deactivates performance mode', function()
    performance.enable()
    performance.disable()
    assert.is_false(performance.is_active())
  end)

  it('get_frame_interval returns 16ms when inactive', function()
    performance.disable()
    local interval = performance.get_frame_interval()
    assert.equals(interval, 16)
  end)

  it('get_frame_interval returns 33ms when active with reduce_frame_rate', function()
    local config = require('whisk.config')
    config.update({ performance = { reduce_frame_rate = true } })
    performance.enable()
    local interval = performance.get_frame_interval()
    assert.equals(interval, 33)
  end)

  it('should_ignore_event returns false when inactive', function()
    performance.disable()
    assert.is_false(performance.should_ignore_event('CursorMoved'))
  end)

  it('should_ignore_event returns true for ignored events when active', function()
    performance.enable()
    assert.is_true(performance.should_ignore_event('CursorMoved'))
    assert.is_true(performance.should_ignore_event('CursorMovedI'))
    assert.is_true(performance.should_ignore_event('WinScrolled'))
  end)

  it('should_ignore_event returns false for non-ignored events', function()
    performance.enable()
    assert.is_false(performance.should_ignore_event('BufEnter'))
    assert.is_false(performance.should_ignore_event('TextChanged'))
  end)

  it('should_auto_enable returns false for small files', function()
    mocks.set_buffer_content({ "line 1", "line 2", "line 3" })
    assert.is_false(performance.should_auto_enable())
  end)

  it('should_auto_enable returns true for large files', function()
    local large_content = {}
    for i = 1, 6000 do
      table.insert(large_content, "line " .. i)
    end
    mocks.set_buffer_content(large_content)
    assert.is_true(performance.should_auto_enable())
  end)

  it('should_auto_enable respects config threshold', function()
    local config = require('whisk.config')
    config.update({ performance = { large_file_threshold = 100 } })

    local content = {}
    for i = 1, 150 do
      table.insert(content, "line " .. i)
    end
    mocks.set_buffer_content(content)

    assert.is_true(performance.should_auto_enable())
  end)

  it('should_auto_enable returns false when auto_enable disabled', function()
    local config = require('whisk.config')
    config.update({ performance = { auto_enable_on_large_files = false } })

    local large_content = {}
    for i = 1, 6000 do
      table.insert(large_content, "line " .. i)
    end
    mocks.set_buffer_content(large_content)

    assert.is_false(performance.should_auto_enable())
  end)

  it('auto_toggle enables for large files', function()
    local config = require('whisk.config')
    config.update({ performance = { auto_enable_on_large_files = true, large_file_threshold = 100 } })

    local content = {}
    for i = 1, 150 do
      table.insert(content, "line " .. i)
    end
    mocks.set_buffer_content(content)

    performance.auto_toggle()
    assert.is_true(performance.is_active())
  end)

  it('auto_toggle disables for small files', function()
    performance.enable()
    mocks.set_buffer_content({ "small", "file" })

    performance.auto_toggle()
    assert.is_false(performance.is_active())
  end)

  it('setup creates autocmds', function()
    performance.setup()
    local state = mocks.get_api_state()
    assert.greater_than(#state.autocmds, 0)
  end)

  it('exports teardown', function()
    assert.is_type(performance.teardown, 'function')
  end)

  it('setup registers its autocmd under the WhiskPerformance augroup', function()
    performance.setup()
    local state = mocks.get_api_state()
    local last = state.autocmds[#state.autocmds]
    assert.is_not_nil(last)
    assert.equals(last.opts.group, 'WhiskPerformance')
  end)

  it('teardown disables performance mode', function()
    performance.enable()
    assert.is_true(performance.is_active())
    performance.teardown()
    assert.is_false(performance.is_active())
  end)

  it('enable and disable are idempotent', function()
    performance.enable()
    performance.enable()
    assert.is_true(performance.is_active())

    performance.disable()
    performance.disable()
    assert.is_false(performance.is_active())
  end)

  it('record_frame_time and get_current_fps work', function()
    if performance.record_frame_time then
      assert.does_not_throw(function()
        performance.record_frame_time()
      end)
    end

    if performance.get_current_fps then
      local fps = performance.get_current_fps()
      assert.is_type(fps, 'number')
    end
  end)

  it('skips frame samples when the idle gap exceeds 5x the frame interval', function()
    local now = 0
    _G.vim.loop = { hrtime = function() return now end }

    for _ = 1, 12 do
      now = now + 16 * 1000000
      performance.record_frame_time()
    end
    assert.equals(performance.get_current_fps(), 62.5)

    now = now + 300 * 1000000
    performance.record_frame_time()
    assert.equals(performance.get_current_fps(), 62.5)
  end)
end)
