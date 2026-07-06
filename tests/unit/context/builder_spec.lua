local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('context/builder', function()
  local builder
  local Context

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
    mocks.set_cursor(3, 2)
    mocks.set_window_size(40, 120)
    mocks.set_topline(1)
    builder = require('whisk.context.builder')
    Context = require('whisk.context.Context')
  end)

  it('exports build function', function()
    assert.is_not_nil(builder.build)
    assert.is_type(builder.build, 'function')
  end)

  it('build returns a Context instance', function()
    local ctx = builder.build({})
    assert.is_type(ctx, 'table')
    assert.is_type(ctx.is_valid, 'function')
    assert.is_type(ctx.set_cursor, 'function')
  end)

  it('build Context has correct bufnr and winid', function()
    local ctx = builder.build({})
    assert.is_type(ctx.bufnr, 'number')
    assert.is_type(ctx.winid, 'number')
  end)

  it('build Context captures starting state', function()
    mocks.set_cursor(2, 3)
    mocks.set_topline(1)
    mocks.clear_package_cache()
    local ctx = require('whisk.context.builder').build({})
    assert.equals(ctx.start.cursor[1], 2)
    assert.equals(ctx.start.cursor[2], 3)
    assert.equals(ctx.start.line_count, 5)
  end)

  it('build attaches input to context', function()
    local ctx = builder.build({ char = 'x', count = 5 })
    assert.equals(ctx.input.char, 'x')
    assert.equals(ctx.input.count, 5)
  end)

  it('build defaults count to 1', function()
    local ctx = builder.build({})
    assert.equals(ctx.input.count, 1)
  end)

  it('build defaults has_count to false', function()
    local ctx = builder.build({})
    assert.is_false(ctx.input.has_count)
  end)

  it('build copies has_count from input', function()
    local ctx = builder.build({ has_count = true })
    assert.is_true(ctx.input.has_count)
  end)

  it('build returns context with cursor position', function()
    local ctx = builder.build({})
    assert.is_not_nil(ctx.cursor)
    assert.equals(ctx.cursor.line, 3)
    assert.equals(ctx.cursor.col, 2)
  end)

  it('build returns context with viewport info', function()
    local ctx = builder.build({})
    assert.is_not_nil(ctx.viewport)
    assert.equals(ctx.viewport.topline, 1)
    assert.equals(ctx.viewport.height, 40)
    assert.equals(ctx.viewport.width, 120)
  end)

  it('build returns context with buffer info', function()
    local ctx = builder.build({})
    assert.is_not_nil(ctx.buffer)
    assert.equals(ctx.buffer.line_count, 5)
  end)

  it('build returns context with input', function()
    local input = { count = 5, char = 'f', direction = 'forward' }
    local ctx = builder.build(input)
    assert.is_not_nil(ctx.input)
    assert.equals(ctx.input.count, 5)
    assert.equals(ctx.input.char, 'f')
    assert.equals(ctx.input.direction, 'forward')
  end)

  it('build preserves provided count', function()
    local ctx = builder.build({ count = 10 })
    assert.equals(ctx.input.count, 10)
  end)

  it('build requires input parameter', function()
    assert.throws(function()
      builder.build(nil)
    end)
  end)

  it('build with empty input returns valid context', function()
    local ctx = builder.build({})
    assert.is_not_nil(ctx)
    assert.is_not_nil(ctx.cursor)
    assert.is_not_nil(ctx.viewport)
    assert.is_not_nil(ctx.buffer)
    assert.is_not_nil(ctx.input)
  end)

  it('build reflects current cursor position', function()
    mocks.set_cursor(1, 0)
    mocks.clear_package_cache()
    local ctx1 = require('whisk.context.builder').build({})
    assert.equals(ctx1.cursor.line, 1)
    assert.equals(ctx1.cursor.col, 0)

    mocks.set_cursor(5, 4)
    mocks.clear_package_cache()
    local ctx2 = require('whisk.context.builder').build({})
    assert.equals(ctx2.cursor.line, 5)
    assert.equals(ctx2.cursor.col, 4)
  end)

  it('build reflects current window size', function()
    mocks.set_window_size(80, 200)
    mocks.clear_package_cache()
    local ctx = require('whisk.context.builder').build({})
    assert.equals(ctx.viewport.height, 80)
    assert.equals(ctx.viewport.width, 200)
  end)

  it('build reflects current topline', function()
    mocks.set_topline(10)
    mocks.clear_package_cache()
    local ctx = require('whisk.context.builder').build({})
    assert.equals(ctx.viewport.topline, 10)
  end)

  it('build reflects current buffer line count', function()
    mocks.set_buffer_content({ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" })
    mocks.clear_package_cache()
    local ctx = require('whisk.context.builder').build({})
    assert.equals(ctx.buffer.line_count, 10)
  end)

  it('build handles all input fields', function()
    local input = {
      count = 3,
      char = 'x',
      direction = 'backward',
      extra = 'ignored',
    }
    local ctx = builder.build(input)
    assert.equals(ctx.input.count, 3)
    assert.equals(ctx.input.char, 'x')
    assert.equals(ctx.input.direction, 'backward')
  end)
end)
