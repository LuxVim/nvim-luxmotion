local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('registry/keymaps', function()
  local keymaps
  local motions
  local config

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()

    motions = require('whisk.registry.motions')
    config = require('whisk.config')
    keymaps = require('whisk.registry.keymaps')

    motions.clear()
    config.reset()
    keymaps.clear()
  end)

  it('exports all required functions', function()
    assert.is_type(keymaps.setup, 'function')
    assert.is_type(keymaps.clear, 'function')
    assert.is_type(keymaps.create_handler, 'function')
  end)

  it('setup creates keymaps for registered motions', function()
    config.update({ keymaps = { cursor = true } })

    motions.register({
      id = 'test_j',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'Move down',
    })

    keymaps.setup()

    local registered = mocks.get_keymaps()
    assert.has_key(registered, 'n:j')
  end)

  it('setup creates keymaps for multiple modes', function()
    config.update({ keymaps = { cursor = true } })

    motions.register({
      id = 'test_k',
      keys = { 'k' },
      modes = { 'n', 'v' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'Move up',
    })

    keymaps.setup()

    local registered = mocks.get_keymaps()
    assert.has_key(registered, 'n:k')
    assert.has_key(registered, 'v:k')
  end)

  it('setup creates keymaps for multiple keys', function()
    config.update({ keymaps = { cursor = true } })

    motions.register({
      id = 'test_multi',
      keys = { 'gg', 'G' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'Go to line',
    })

    keymaps.setup()

    local registered = mocks.get_keymaps()
    assert.has_key(registered, 'n:gg')
    assert.has_key(registered, 'n:G')
  end)

  it('setup skips category when disabled', function()
    config.update({ keymaps = { cursor = false } })

    motions.register({
      id = 'test_disabled',
      keys = { 'x' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'Test motion',
    })

    keymaps.setup()

    local registered = mocks.get_keymaps()
    assert.is_nil(registered['n:x'])
  end)

  it('setup handles both cursor and scroll categories', function()
    config.update({ keymaps = { cursor = true, scroll = true } })

    motions.register({
      id = 'cursor_motion',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'Move down',
    })

    motions.register({
      id = 'scroll_motion',
      keys = { '<C-d>' },
      modes = { 'n' },
      traits = { 'scroll' },
      category = 'scroll',
      calculator = function() return {} end,
      description = 'Scroll down',
    })

    keymaps.setup()

    local registered = mocks.get_keymaps()
    assert.has_key(registered, 'n:j')
    assert.has_key(registered, 'n:<C-d>')
  end)

  it('clear removes all keymaps', function()
    config.update({ keymaps = { cursor = true } })

    motions.register({
      id = 'test_clear',
      keys = { 'y' },
      modes = { 'n', 'v' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'Test clear',
    })

    keymaps.setup()
    keymaps.clear()

    local deleted = mocks.get_deleted_keymaps()
    assert.greater_than(#deleted, 0)
  end)

  it('create_handler returns a function', function()
    local motion = {
      id = 'test',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
    }

    local handler = keymaps.create_handler(motion)
    assert.is_type(handler, 'function')
  end)

  it('created handler is callable', function()
    config.update({ cursor = { enabled = true } })

    local traits = require('whisk.registry.traits')
    traits.register({
      id = 'cursor',
      apply = function() end,
    })

    motions.register({
      id = 'handler_test',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        return { cursor = { line = ctx.cursor.line + 1, col = 0 } }
      end,
    })

    local motion = motions.get('handler_test')
    local handler = keymaps.create_handler(motion)

    assert.does_not_throw(function()
      handler()
    end)
  end)

  it('create_handler sets has_count false when no explicit count was typed', function()
    local orchestrator = require('whisk.engine.orchestrator')
    local captured
    orchestrator.execute = function(_, input) captured = input end

    local motion = {
      id = 'test_no_count',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
    }

    _G.vim.v.count = 0
    keymaps.create_handler(motion)()
    assert.is_false(captured.has_count)
  end)

  it('create_handler sets has_count true when an explicit count was typed', function()
    local orchestrator = require('whisk.engine.orchestrator')
    local captured
    orchestrator.execute = function(_, input) captured = input end

    local motion = {
      id = 'test_with_count',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
    }

    _G.vim.v.count = 3
    keymaps.create_handler(motion)()
    assert.is_true(captured.has_count)

    _G.vim.v.count = 0
  end)

  it('setup sets keymap options with desc', function()
    config.update({ keymaps = { cursor = true } })

    motions.register({
      id = 'with_desc',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'Move down',
    })

    keymaps.setup()

    local registered = mocks.get_keymaps()
    local keymap = registered['n:j']
    assert.is_not_nil(keymap.opts)
  end)

  it('setup with no registered motions does not crash', function()
    assert.does_not_throw(function()
      keymaps.setup()
    end)
  end)

  it('clear with no keymaps does not crash', function()
    assert.does_not_throw(function()
      keymaps.clear()
    end)
  end)
end)
