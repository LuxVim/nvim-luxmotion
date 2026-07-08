local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('engine/orchestrator', function()
  local orchestrator
  local motions
  local traits
  local loop

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({
      "line 1",
      "line 2",
      "line 3",
      "line 4",
      "line 5",
    })
    mocks.set_cursor(1, 0)
    mocks.set_window_size(40, 120)
    mocks.set_topline(1)

    motions = require('whisk.registry.motions')
    traits = require('whisk.registry.traits')
    loop = require('whisk.engine.loop')
    orchestrator = require('whisk.engine.orchestrator')

    motions.clear()
    traits.clear()
    loop.stop_all()

    traits.register({
      id = 'cursor',
      apply = function(context, result, progress)
        if result.cursor then
          context:set_cursor(result.cursor.line, result.cursor.col)
        end
      end,
    })

    motions.register({
      id = 'test_j',
      keys = { 'j' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        return {
          cursor = {
            line = ctx.cursor.line + ctx.input.count,
            col = ctx.cursor.col,
          },
        }
      end,
    })
  end)

  it('exports required functions', function()
    assert.is_type(orchestrator.execute, 'function')
    assert.is_type(orchestrator.fallback, 'function')
  end)

  it('execute starts animation for registered motion', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 2 })

    assert.is_true(loop.is_running())
  end)

  it('execute calls calculator with context', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    local calculator_called = false
    motions.register({
      id = 'test_calc',
      keys = { 'x' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        calculator_called = true
        assert.is_not_nil(ctx.cursor)
        assert.is_not_nil(ctx.input)
        return { cursor = { line = 1, col = 0 } }
      end,
    })

    orchestrator.execute('test_calc', {})
    assert.is_true(calculator_called)
  end)

  it('execute uses fallback when category disabled', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = false } })

    orchestrator.execute('test_j', { count = 1, direction = 'j' })

    local fed = mocks.get_api_state().fed_keys
    assert.greater_than(#fed, 0)
    assert.equals(fed[1].keys, 'j')
  end)

  it('fallback feeds keys via feedkeys', function()
    local motion = motions.get('test_j')
    orchestrator.fallback(motion, { count = 3, direction = 'j' })

    local fed = mocks.get_api_state().fed_keys
    assert.greater_than(#fed, 0)
    assert.equals(fed[1].keys, '3j')
    assert.equals(fed[1].mode, 'nx')
  end)

  it('fallback resolves control-key termcodes via feedkeys, not vim.cmd', function()
    orchestrator.fallback({ keys = { '<C-d>' } }, { count = 1, direction = '<C-d>' })

    local fed = mocks.get_api_state().fed_keys
    assert.equals(#fed, 1)
    assert.equals(fed[1].keys, '<C-d>')
    assert.equals(fed[1].mode, 'nx')

    local commands = mocks.get_commands()
    assert.equals(#commands, 0)
  end)

  it('execute handles unknown motion gracefully', function()
    assert.does_not_throw(function()
      orchestrator.execute('nonexistent_motion', {})
    end)
  end)

  it('execute passes count to calculator', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    local received_count = nil
    motions.register({
      id = 'test_count',
      keys = { 'y' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        received_count = ctx.input.count
        return { cursor = { line = ctx.cursor.line + ctx.input.count, col = 0 } }
      end,
    })

    orchestrator.execute('test_count', { count = 5 })
    assert.equals(received_count, 5)
  end)

  it('execute passes direction to calculator', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    local received_direction = nil
    motions.register({
      id = 'test_dir',
      keys = { 'z' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        received_direction = ctx.input.direction
        return { cursor = { line = 1, col = 0 } }
      end,
    })

    orchestrator.execute('test_dir', { direction = 'forward' })
    assert.equals(received_direction, 'forward')
  end)

  it('execute does nothing when target equals current', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    motions.register({
      id = 'test_same',
      keys = { 's' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        return { cursor = { line = ctx.cursor.line, col = ctx.cursor.col } }
      end,
    })

    orchestrator.execute('test_same', {})
    assert.is_false(loop.is_running())
  end)

  it('execute marks traits as animating', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })
    assert.is_true(traits.is_animating('cursor'))
  end)

  it('clears the animating flag when the animation is cancelled for a buffer', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })
    assert.is_true(traits.is_animating('cursor'))

    loop.cancel_for_buffer(1)
    assert.is_false(traits.is_animating('cursor'))
  end)

  it('clears the animating flag when the animation is cancelled for a window', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })
    assert.is_true(traits.is_animating('cursor'))

    loop.cancel_for_window(1000)
    assert.is_false(traits.is_animating('cursor'))
  end)

  it('execute completes previous animation before starting new one (key repeat)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })
    assert.is_true(loop.is_running())

    local cursor_after_first = mocks.get_cursor()
    assert.equals(cursor_after_first[1], 1)

    orchestrator.execute('test_j', { count = 1 })

    local cursor_after_second = mocks.get_cursor()
    assert.equals(cursor_after_second[1], 2)
    assert.is_true(loop.is_running())
  end)

  it('execute detects change in viewport', function()
    local config = require('whisk.config')
    config.update({ scroll = { enabled = true } })

    motions.register({
      id = 'test_view_detect',
      keys = { 's' },
      modes = { 'n' },
      traits = { 'scroll' },
      category = 'scroll',
      calculator = function(_)
        return { viewport = { topline = 50 } }
      end,
    })

    orchestrator.execute('test_view_detect', {})
    assert.is_true(loop.is_running())
  end)

  it('execute does not start loop when cursor and viewport unchanged', function()
    local config = require('whisk.config')
    config.update({ scroll = { enabled = true } })

    motions.register({
      id = 'test_view_unchanged',
      keys = { 't' },
      modes = { 'n' },
      traits = { 'scroll' },
      category = 'scroll',
      calculator = function(ctx)
        return {
          cursor = { line = ctx.cursor.line, col = ctx.cursor.col },
          viewport = { topline = ctx.viewport.topline },
        }
      end,
    })

    orchestrator.execute('test_view_unchanged', {})
    assert.is_false(loop.is_running())
  end)
end)
