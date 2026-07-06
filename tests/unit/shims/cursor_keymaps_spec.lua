local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('cursor/keymaps (shims)', function()
  local cursor_keymaps
  local orchestrator_calls = {}

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    orchestrator_calls = {}

    package.loaded['whisk.engine.orchestrator'] = {
      execute = function(motion_id, input)
        table.insert(orchestrator_calls, { motion_id = motion_id, input = input })
      end,
      fallback = function() end,
    }

    cursor_keymaps = require('whisk.cursor.keymaps')
  end)

  it('exports deprecated functions', function()
    assert.is_type(cursor_keymaps.smooth_move, 'function')
    assert.is_type(cursor_keymaps.smooth_word_move, 'function')
    assert.is_type(cursor_keymaps.smooth_find_move, 'function')
    assert.is_type(cursor_keymaps.smooth_text_object_move, 'function')
    assert.is_type(cursor_keymaps.smooth_line_move, 'function')
    assert.is_type(cursor_keymaps.setup_keymaps, 'function')
  end)

  it('smooth_move h calls orchestrator with basic_h', function()
    cursor_keymaps.smooth_move('h', 1)
    assert.equals(#orchestrator_calls, 1)
    assert.equals(orchestrator_calls[1].motion_id, 'basic_h')
  end)

  it('smooth_move j calls orchestrator with basic_j', function()
    cursor_keymaps.smooth_move('j', 2)
    assert.equals(orchestrator_calls[1].motion_id, 'basic_j')
    assert.equals(orchestrator_calls[1].input.count, 2)
  end)

  it('smooth_move k calls orchestrator with basic_k', function()
    cursor_keymaps.smooth_move('k', 3)
    assert.equals(orchestrator_calls[1].motion_id, 'basic_k')
    assert.equals(orchestrator_calls[1].input.count, 3)
  end)

  it('smooth_move l calls orchestrator with basic_l', function()
    cursor_keymaps.smooth_move('l', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'basic_l')
  end)

  it('smooth_move 0 calls orchestrator with basic_0', function()
    cursor_keymaps.smooth_move('0', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'basic_0')
  end)

  it('smooth_move $ calls orchestrator with basic_$', function()
    cursor_keymaps.smooth_move('$', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'basic_$')
  end)

  it('smooth_word_move w calls orchestrator with word_w', function()
    cursor_keymaps.smooth_word_move('w', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'word_w')
  end)

  it('smooth_word_move b calls orchestrator with word_b', function()
    cursor_keymaps.smooth_word_move('b', 2)
    assert.equals(orchestrator_calls[1].motion_id, 'word_b')
    assert.equals(orchestrator_calls[1].input.count, 2)
  end)

  it('smooth_word_move e calls orchestrator with word_e', function()
    cursor_keymaps.smooth_word_move('e', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'word_e')
  end)

  it('smooth_word_move W calls orchestrator with word_W', function()
    cursor_keymaps.smooth_word_move('W', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'word_W')
  end)

  it('smooth_word_move B calls orchestrator with word_B', function()
    cursor_keymaps.smooth_word_move('B', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'word_B')
  end)

  it('smooth_word_move E calls orchestrator with word_E', function()
    cursor_keymaps.smooth_word_move('E', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'word_E')
  end)

  it('smooth_find_move f calls orchestrator with find_f', function()
    cursor_keymaps.smooth_find_move('f', 'x', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'find_f')
    assert.equals(orchestrator_calls[1].input.char, 'x')
  end)

  it('smooth_find_move F calls orchestrator with find_F', function()
    cursor_keymaps.smooth_find_move('F', 'y', 2)
    assert.equals(orchestrator_calls[1].motion_id, 'find_F')
    assert.equals(orchestrator_calls[1].input.char, 'y')
    assert.equals(orchestrator_calls[1].input.count, 2)
  end)

  it('smooth_find_move t calls orchestrator with find_t', function()
    cursor_keymaps.smooth_find_move('t', 'a', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'find_t')
  end)

  it('smooth_find_move T calls orchestrator with find_T', function()
    cursor_keymaps.smooth_find_move('T', 'b', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'find_T')
  end)

  it('smooth_text_object_move { calls orchestrator', function()
    cursor_keymaps.smooth_text_object_move('{', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'text_object_{')
  end)

  it('smooth_text_object_move } calls orchestrator', function()
    cursor_keymaps.smooth_text_object_move('}', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'text_object_}')
  end)

  it('smooth_text_object_move ( calls orchestrator', function()
    cursor_keymaps.smooth_text_object_move('(', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'text_object_(')
  end)

  it('smooth_text_object_move ) calls orchestrator', function()
    cursor_keymaps.smooth_text_object_move(')', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'text_object_)')
  end)

  it('smooth_text_object_move % calls orchestrator', function()
    cursor_keymaps.smooth_text_object_move('%', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'text_object_%')
  end)

  it('smooth_line_move gg calls orchestrator', function()
    cursor_keymaps.smooth_line_move('gg', 1)
    assert.equals(orchestrator_calls[1].motion_id, 'line_gg')
  end)

  it('smooth_line_move G calls orchestrator', function()
    cursor_keymaps.smooth_line_move('G', 50)
    assert.equals(orchestrator_calls[1].motion_id, 'line_G')
    assert.equals(orchestrator_calls[1].input.count, 50)
  end)

  it('smooth_line_move | calls orchestrator', function()
    cursor_keymaps.smooth_line_move('|', 10)
    assert.equals(orchestrator_calls[1].motion_id, 'line_|')
  end)

  it('setup_keymaps is a no-op', function()
    assert.does_not_throw(function()
      cursor_keymaps.setup_keymaps()
    end)
  end)

  it('smooth_search_move if exists', function()
    if cursor_keymaps.smooth_search_move then
      cursor_keymaps.smooth_search_move('n', 1)
      assert.equals(orchestrator_calls[1].motion_id, 'search_n')
    end
  end)

  it('smooth_screen_line_move if exists', function()
    if cursor_keymaps.smooth_screen_line_move then
      cursor_keymaps.smooth_screen_line_move('gj', 1)
      assert.equals(orchestrator_calls[1].motion_id, 'screen_gj')
    end
  end)
end)
