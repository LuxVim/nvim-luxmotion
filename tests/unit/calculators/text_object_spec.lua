local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('calculators/text_object', function()
  local text_object

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({
      "First paragraph here.",
      "",
      "Second paragraph starts here.",
      "It continues on this line.",
      "",
      "Third paragraph.",
      "",
      "(some text in parens)",
      "{some text in braces}",
    })
    mocks.set_cursor(3, 0)
    text_object = require('whisk.calculators.text_object')
  end)

  it('exports {, }, (, ), % functions', function()
    assert.is_type(text_object['{'], 'function')
    assert.is_type(text_object['}'], 'function')
    assert.is_type(text_object['('], 'function')
    assert.is_type(text_object[')'], 'function')
    assert.is_type(text_object['%'], 'function')
  end)

  it('{ returns cursor result', function()
    local ctx = {
      cursor = { line = 4, col = 0 },
      input = { count = 1 },
      buffer = { line_count = 9 },
    }
    local result = text_object['{'](ctx)

    assert.is_not_nil(result)
    assert.is_not_nil(result.cursor)
    assert.is_type(result.cursor.line, 'number')
    assert.is_type(result.cursor.col, 'number')
  end)

  it('} returns cursor result', function()
    local ctx = {
      cursor = { line = 3, col = 0 },
      input = { count = 1 },
      buffer = { line_count = 9 },
    }
    local result = text_object['}'](ctx)

    assert.is_not_nil(result)
    assert.is_not_nil(result.cursor)
  end)

  it('( returns cursor result', function()
    local ctx = {
      cursor = { line = 4, col = 10 },
      input = { count = 1 },
      buffer = { line_count = 9 },
    }
    local result = text_object['('](ctx)

    assert.is_not_nil(result)
    assert.is_not_nil(result.cursor)
  end)

  it(') returns cursor result', function()
    local ctx = {
      cursor = { line = 3, col = 0 },
      input = { count = 1 },
      buffer = { line_count = 9 },
    }
    local result = text_object[')'](ctx)

    assert.is_not_nil(result)
    assert.is_not_nil(result.cursor)
  end)

  it('% returns cursor result', function()
    mocks.set_cursor(8, 0)
    local ctx = {
      cursor = { line = 8, col = 0 },
      input = { count = 1 },
      buffer = { line_count = 9 },
    }
    local result = text_object['%'](ctx)

    assert.is_not_nil(result)
    assert.is_not_nil(result.cursor)
  end)

  it('{ with count moves multiple paragraphs', function()
    local ctx = {
      cursor = { line = 6, col = 0 },
      input = { count = 2 },
      buffer = { line_count = 9 },
    }
    local result = text_object['{'](ctx)

    assert.is_not_nil(result.cursor)
  end)

  it('} with count moves multiple paragraphs', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 2 },
      buffer = { line_count = 9 },
    }
    local result = text_object['}'](ctx)

    assert.is_not_nil(result.cursor)
  end)

  it('{ at first paragraph stays in bounds', function()
    mocks.set_cursor(1, 0)
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 10 },
      buffer = { line_count = 9 },
    }
    local result = text_object['{'](ctx)

    assert.greater_or_equal(result.cursor.line, 1)
  end)

  it('} at last paragraph stays in bounds', function()
    mocks.set_cursor(9, 0)
    local ctx = {
      cursor = { line = 9, col = 0 },
      input = { count = 10 },
      buffer = { line_count = 9 },
    }
    local result = text_object['}'](ctx)

    assert.less_or_equal(result.cursor.line, 9)
  end)

  it('% handles no matching bracket gracefully', function()
    mocks.set_buffer_content({ "no brackets here" })
    mocks.set_cursor(1, 5)
    local ctx = {
      cursor = { line = 1, col = 5 },
      input = { count = 1 },
      buffer = { line_count = 1 },
    }

    assert.does_not_throw(function()
      text_object['%'](ctx)
    end)
  end)

  it('% with no explicit count runs a bare % (issue #14)', function()
    local ctx = {
      cursor = { line = 5, col = 0 },
      input = { count = 1, has_count = false },
      buffer = { line_count = 10 },
    }
    text_object['%'](ctx)
    local commands = mocks.get_commands()
    assert.contains(commands, 'normal! %')
  end)

  it('% with an explicit count runs {count}%', function()
    local ctx = {
      cursor = { line = 5, col = 0 },
      input = { count = 3, has_count = true },
      buffer = { line_count = 10 },
    }
    text_object['%'](ctx)
    local commands = mocks.get_commands()
    assert.contains(commands, 'normal! 3%')
  end)

  it('} still prepends the count (regression)', function()
    local ctx = {
      cursor = { line = 3, col = 0 },
      input = { count = 2, has_count = true },
      buffer = { line_count = 9 },
    }
    text_object['}'](ctx)
    local commands = mocks.get_commands()
    assert.contains(commands, 'normal! 2}')
  end)

  it('text object motions preserve column appropriately', function()
    local ctx = {
      cursor = { line = 3, col = 5 },
      input = { count = 1 },
      buffer = { line_count = 9 },
    }

    local result = text_object['}'](ctx)
    assert.is_type(result.cursor.col, 'number')
  end)
end)
