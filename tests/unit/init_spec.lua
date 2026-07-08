local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each, after_each = runner.describe, runner.it, runner.before_each, runner.after_each

describe('init (main module)', function()
  local whisk

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({ "line 1", "line 2", "line 3" })
    mocks.set_cursor(1, 0)
    mocks.set_window_size(40, 120)
    mocks.set_topline(1)
    whisk = require('whisk')
  end)

  after_each(function()
    if whisk and whisk.reset then
      whisk.reset()
    end
  end)

  it('exports setup function', function()
    assert.is_type(whisk.setup, 'function')
  end)

  it('exports enable/disable functions', function()
    assert.is_type(whisk.enable, 'function')
    assert.is_type(whisk.disable, 'function')
    assert.is_type(whisk.toggle, 'function')
  end)

  it('exports cursor enable/disable functions', function()
    assert.is_type(whisk.enable_cursor, 'function')
    assert.is_type(whisk.disable_cursor, 'function')
  end)

  it('exports scroll enable/disable functions', function()
    assert.is_type(whisk.enable_scroll, 'function')
    assert.is_type(whisk.disable_scroll, 'function')
  end)

  it('exports toggle_performance function', function()
    assert.is_type(whisk.toggle_performance, 'function')
  end)

  it('exports reset function', function()
    assert.is_type(whisk.reset, 'function')
  end)

  it('setup with no config works', function()
    assert.does_not_throw(function()
      whisk.setup()
    end)
  end)

  it('setup with empty config works', function()
    assert.does_not_throw(function()
      whisk.setup({})
    end)
  end)

  it('setup with partial config works', function()
    assert.does_not_throw(function()
      whisk.setup({
        cursor = { duration = 100 },
      })
    end)
  end)

  it('setup with full config works', function()
    assert.does_not_throw(function()
      whisk.setup({
        cursor = { duration = 200, easing = 'linear', enabled = true },
        scroll = { duration = 300, easing = 'ease-in', enabled = false },
        keymaps = { cursor = true, scroll = false },
        performance = { enabled = false },
      })
    end)
  end)

  it('setup creates keymaps', function()
    whisk.setup()
    local keymaps = mocks.get_keymaps()
    local count = 0
    for _ in pairs(keymaps) do count = count + 1 end
    assert.greater_than(count, 0)
  end)

  it('enable enables both cursor and scroll', function()
    whisk.setup()
    whisk.disable()
    whisk.enable()

    local config = require('whisk.config')
    assert.is_true(config.get_cursor().enabled)
    assert.is_true(config.get_scroll().enabled)
  end)

  it('disable disables both cursor and scroll', function()
    whisk.setup()
    whisk.disable()

    local config = require('whisk.config')
    assert.is_false(config.get_cursor().enabled)
    assert.is_false(config.get_scroll().enabled)
  end)

  it('toggle toggles both cursor and scroll', function()
    whisk.setup()
    local config = require('whisk.config')

    local initial_cursor = config.get_cursor().enabled
    whisk.toggle()
    assert.equals(config.get_cursor().enabled, not initial_cursor)
  end)

  it('enable_cursor only enables cursor', function()
    whisk.setup()
    whisk.disable()
    whisk.enable_cursor()

    local config = require('whisk.config')
    assert.is_true(config.get_cursor().enabled)
    assert.is_false(config.get_scroll().enabled)
  end)

  it('disable_cursor only disables cursor', function()
    whisk.setup()
    whisk.disable_cursor()

    local config = require('whisk.config')
    assert.is_false(config.get_cursor().enabled)
    assert.is_true(config.get_scroll().enabled)
  end)

  it('enable_scroll only enables scroll', function()
    whisk.setup()
    whisk.disable()
    whisk.enable_scroll()

    local config = require('whisk.config')
    assert.is_false(config.get_cursor().enabled)
    assert.is_true(config.get_scroll().enabled)
  end)

  it('disable_scroll only disables scroll', function()
    whisk.setup()
    whisk.disable_scroll()

    local config = require('whisk.config')
    assert.is_true(config.get_cursor().enabled)
    assert.is_false(config.get_scroll().enabled)
  end)

  it('toggle_performance toggles performance mode', function()
    whisk.setup()
    local performance = require('whisk.performance')

    local initial = performance.is_active()
    whisk.toggle_performance()
    assert.equals(performance.is_active(), not initial)
  end)

  it('reset clears all state', function()
    whisk.setup()
    assert.does_not_throw(function()
      whisk.reset()
    end)
  end)

  it('setup applies user config', function()
    whisk.setup({
      cursor = { duration = 999 },
    })

    local config = require('whisk.config')
    assert.equals(config.get_cursor().duration, 999)
  end)

  it('setup validates config', function()
    assert.throws(function()
      whisk.setup({
        cursor = { duration = -100 },
      })
    end)
  end)

  it('multiple setup calls work', function()
    assert.does_not_throw(function()
      whisk.setup()
      whisk.setup({ cursor = { duration = 100 } })
      whisk.setup({ scroll = { duration = 200 } })
    end)
  end)

  it('setup starts from pristine defaults on each call', function()
    local config = require('whisk.config')

    whisk.setup({ cursor = { duration = 500 } })
    assert.equals(config.get_cursor().duration, 500)

    whisk.setup({ scroll = { duration = 100 } })
    assert.equals(config.get_cursor().duration, 150)
    assert.equals(config.get_scroll().duration, 100)
  end)

  it('setup registers traits', function()
    whisk.setup()
    local traits = require('whisk.registry.traits')
    assert.is_not_nil(traits.get('cursor'))
    assert.is_not_nil(traits.get('scroll'))
  end)

  it('setup registers motions', function()
    whisk.setup()
    local motions = require('whisk.registry.motions')
    assert.is_not_nil(motions.get('basic_j'))
    assert.is_not_nil(motions.get('scroll_ctrl_d'))
  end)

  it('setup initializes lifecycle', function()
    local lifecycle = require('whisk.engine.lifecycle')
    whisk.setup({})
    assert.is_true(lifecycle.is_active())
  end)

  it('reset tears down lifecycle', function()
    local lifecycle = require('whisk.engine.lifecycle')
    whisk.setup({})
    whisk.reset()
    assert.is_false(lifecycle.is_active())
  end)

  it('reset tears down performance mode', function()
    whisk.setup({ performance = { enabled = true } })
    local performance = require('whisk.performance')
    assert.is_true(performance.is_active())
    whisk.reset()
    assert.is_false(performance.is_active())
  end)
end)
