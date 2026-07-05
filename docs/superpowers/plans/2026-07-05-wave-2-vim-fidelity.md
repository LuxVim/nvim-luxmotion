# Wave 2: Vim Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make whisk.nvim behave like native Vim under synchronous key chains (macros, fast typing) and correct the calculator/context semantics that diverge from Neovim (multibyte columns, folds, curswant, jumplist, scroll option, scrolloff, leftcol, per-buffer syntax), while fixing the duplicate frame-timer leak.

**Architecture:** whisk.nvim maps motions to keymap handlers (`registry/keymaps.lua`) that call `engine/orchestrator.execute`, which builds a `Context` (`context/builder.lua`), runs a per-motion `calculator` (`calculators/*.lua`), and drives the deferred frame loop (`engine/loop.lua`) that applies `traits`. This wave introduces three cross-wave contracts: a shared native-delegation helper (`calculators/native.lua`, pinned contract 2) that runs real `normal!` motions and captures cursor + curswant; a `jump = true` motion flag (pinned contract 3) that makes the orchestrator push the jumplist; and a `should_skip_animation` seam (pinned contract 4) that applies results synchronously during macro replay. The loop additionally gains a `vim.on_key` interrupt (any keypress snaps animations to completion), a pending-timer guard, and a complete-at-target path for `BufLeave`. Final cursor positions become authoritative Vim positions; per-frame interpolation still lerps byte columns transiently (engine-internals territory, out of scope here).

**Tech Stack:** Lua 5.1+ (Neovim runtime), plain-Lua unit test harness (tests/), headless Neovim probes for behavior the mocks cannot exercise.

**Findings covered:**
- **#2** (high) — Animation runs during macro replay; the next macro key operates on the stale pre-animation cursor (`wx` in a macro deletes at the origin). (Task 5)
- **#3** (high) — Performance mode saves/restores `'syntax'` on whatever buffer is current; entering a large file then a small one corrupts both buffers. (Task 11)
- **#4** (high) — `<C-d>`/`<C-u>` multiply half-page by count, ignore the `'scroll'` option, and re-center instead of preserving the cursor's screen row. (Task 8)
- **#9** (medium) — `h`/`l`/`$`/`|` use byte columns; multibyte lines get wrong counts and mid-character landings. (Tasks 1, 2)
- **#10** (medium) — `j`/`k` count buffer lines with no fold awareness, landing inside closed folds. (Task 2)
- **#11** (medium) — Animated `gg`/`G` (and jump motions applied via `set_cursor`) never push the jumplist; `<C-o>` after `G` does nothing. (Task 4)
- **#12** (medium) — No curswant concept; `$` then `j` does not stick to end of line. (Tasks 1, 3)
- **#14** (medium) — Domination/cancel paths clear `is_running` while a frame timer is still pending; the next `start` arms a second concurrent `process_frame` chain. (Task 7)
- **#26** (low) — `zt`/`zb` ignore `'scrolloff'`, placing the cursor flush against the window edge. (Task 9)
- **#27** (low) — `Context:restore_view` hardcodes `leftcol = 0`, resetting horizontal scroll every animated frame. (Task 10)
- **V1** (high) — Any non-whisk key typed during the ~150-200ms animation window executes at the interpolated cursor position (superset of #2 for real-time typing). (Task 6)
- **V3** (low) — `BufLeave` cancellation abandons the cursor at a mid-flight position instead of the motion target. (Task 12)

## Execution Model

- Branch: `audit/wave-2-vim-fidelity`, created from `main` AFTER the Wave 1 PR (`audit/wave-1-quick-wins`) has merged. Wave 1's contracts are assumed present: `create_handler` passes `has_count = vim.v.count > 0`, `context/builder.lua` copies `ctx.input.has_count = input.has_count or false`, `text_object.lua`'s `%` prefixes the count only when `has_count`, `line.lua`'s `gg`/`G` use `get_target_col` + `has_count`, and `orchestrator.execute` passes a shared `clear_animating` to both `on_complete` and `on_cancel`.
- Executor: one Sonnet 5 subagent (high effort) per task, fresh context per task, given only that task's text plus this plan's header and Global Constraints.
- Task review: an Opus 4.8 subagent (xhigh effort) reviews each completed task's diff against the task spec before the next task starts. Review verdict gates progression.
- Wave review: one Fable agent reviews the wave's full branch diff (`git diff main...HEAD`) against this plan plus the findings file before the PR is opened.
- PR: opened to `main` when all tasks complete, `bash scripts/run_tests.sh` passes, and the Fable wave review passes.

## Global Constraints

- Neovim >= 0.8 API compatibility only (no `vim.uv`, no `nvim_exec2`, no APIs newer than 0.8 unless feature-detected). `vim.on_key`, `vim.api.nvim_create_namespace`, `vim.api.nvim_win_call`, `vim.fn.winsaveview`/`winrestview` (including the `curswant` field), `vim.fn.reg_executing`, `vim.wo.scroll`, and `vim.wo.scrolloff` are all 0.8-safe.
- No inline comments in code. LuaCATS/JSDoc-style annotation comments are permitted only where a task explicitly calls for them.
- Commit style: conventional commits with scope, matching repo history (`fix(engine): ...`, `feat(context): ...`, `test: ...`, `docs: ...`, `chore: ...`). NO AI attribution of any kind — no "Generated with", no "Co-Authored-By: Claude".
- Every task ends with `bash scripts/run_tests.sh` passing (441+ tests at commit 852b689, plus Wave 1's additions — the gate is `Failed:  0`) before its commit.
- Do not modify files outside this wave's scope. Do not touch `lua/luxmotion/` or `plugin/luxmotion.vim` (deprecation shims).
- File:line references in the findings are valid at commit 852b689 and predate Wave 1; always locate code by content.

### Headless Probe Protocol

Most behaviors in this wave cannot be exercised by the mock harness (mock `vim.cmd` is a no-op that only records command strings; mock `nvim_feedkeys` is a no-op; there are no real folds, multibyte lines, jumplists, or window options). Each such task carries a headless-nvim probe step. Wave 3 will turn these probes into a permanent integration tier; for this wave they are transient verification artifacts.

- Write each probe to the exact `/tmp/whisk_probe_<name>.lua` path given in the task, run it with the exact command given, compare against the exact expected output, then delete it. Do NOT commit probe files.
- Probe command shape: `nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_<name>.lua" 2>&1`
- Every probe body is wrapped in `pcall` and prints `PROBE_ERROR: <err>` on failure, ending with `vim.cmd("qa!")`.
- Probes MUST assert user-facing behavior (final cursor line/col, buffer text after an edit, `<C-o>` landing line, `winsaveview()` fields), NEVER internal bookkeeping reads. In particular: do NOT assert `#vim.fn.getjumplist()[1]` immediately after a jumplist push — entry materialization is lazy and transiently reads as 0; assert where `<C-o>` actually lands instead.

---

### Task 1: Shared native-delegation helper `calculators/native.lua` (#9, #12 — pinned contract 2)

Consolidate the four per-file `calculate_via_native` locals (`word.lua`, `find.lua`, `search.lua`, `text_object.lua`) into one shared module that also captures `curswant` — the foundation for Task 2's `h/j/k/l/$/|` migration (#9, #10) and Task 3's curswant plumbing (#12). The helper does NOT re-set the cursor to the origin before executing (the cursor is already there); it saves the full view with `winsaveview()`, runs `normal!` under `pcall`, captures the target cursor and `curswant`, restores the original view with `winrestview()`, and returns `{ cursor = { line, col }, curswant = number }`. On `normal!` failure it restores the view and returns the origin cursor with no `curswant`.

**Files:**
- Create: `lua/whisk/calculators/native.lua`
- Modify: `lua/whisk/calculators/init.lua` (expose `M.native`)
- Modify: `lua/whisk/calculators/word.lua`, `lua/whisk/calculators/find.lua`, `lua/whisk/calculators/search.lua`, `lua/whisk/calculators/text_object.lua` (migrate)
- Modify: `tests/mocks/vim_fn.lua` (add `curswant` state), `tests/init.lua` (register new spec)
- Test: `tests/unit/calculators/native_spec.lua` (new), additions to `tests/unit/calculators/word_spec.lua`, `find_spec.lua`, `search_spec.lua`, `text_object_spec.lua`

**Interfaces:**
- Produces: `native.calculate(motion_cmd, context, opts) -> { cursor = { line = integer, col = integer }, curswant = integer|nil }` where `opts` is `{ char = string|nil, include_count = boolean|nil }`. `include_count` defaults to `true` (prefix `context.input.count`); `char` is appended literally after the motion command. This exact signature is a pinned cross-wave contract — all native-delegation calculators require it from this wave on.
- Consumes: `context.input.count`, `context.cursor.{line,col}`, `vim.fn.winsaveview()`, `vim.fn.winrestview()`, `vim.cmd`, `vim.api.nvim_win_get_cursor(0)`.
- Migrated callers: `word.w/b/e/W/B/E`, `search.n/N/gj/gk`, `text_object.{ } ( )` use defaults; `find.f/F/t/T` pass `{ char = context.input.char }`; `text_object.%` passes `{ include_count = context.input.has_count == true }` (preserving Wave 1's `%`-has_count semantics exactly).

**Steps:**

- [ ] Extend the mock so `winsaveview` reports `curswant`. In `tests/mocks/vim_fn.lua`, add `curswant = 0,` to the `local state = { ... }` table AND to the reassignment inside `function M.reset()` (place it after `last_char = '',` in each). Add a setter after `function M.set_last_char(char) ... end`:

  ```lua
  function M.set_curswant(value)
    state.curswant = value
  end
  ```

  Inside `M.create()`'s returned table, replace the `winrestview` function with:

  ```lua
    winrestview = function(view)
      if view.topline then
        state.topline = view.topline
      end
      if view.curswant ~= nil then
        state.curswant = view.curswant
      end
    end,
  ```

  and replace the `winsaveview` function with:

  ```lua
    winsaveview = function()
      return {
        topline = state.topline,
        lnum = get_api_state().cursor[1],
        col = get_api_state().cursor[2],
        leftcol = 0,
        curswant = state.curswant,
      }
    end,
  ```

  In `tests/mocks/init.lua`, add after `function M.set_topline(topline) ... end`:

  ```lua
  function M.set_curswant(value)
    vim_fn.set_curswant(value)
  end
  ```

- [ ] Write the failing spec. Create `tests/unit/calculators/native_spec.lua`:

  ```lua
  local runner = require('tests.runner')
  local assert = require('tests.helpers.assertions')
  local mocks = require('tests.mocks')

  local describe, it, before_each = runner.describe, runner.it, runner.before_each

  describe('calculators/native', function()
    local native

    before_each(function()
      mocks.setup()
      mocks.clear_package_cache()
      mocks.set_buffer_content({
        "hello world foo bar",
        "second line here",
      })
      mocks.set_cursor(2, 4)
      native = require('whisk.calculators.native')
    end)

    it('exports calculate function', function()
      assert.is_type(native.calculate, 'function')
    end)

    it('calculate prefixes count by default', function()
      local ctx = {
        cursor = { line = 2, col = 4 },
        input = { count = 3 },
      }
      native.calculate('w', ctx)

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! 3w')
    end)

    it('calculate appends the char suffix', function()
      local ctx = {
        cursor = { line = 2, col = 4 },
        input = { count = 2 },
      }
      native.calculate('f', ctx, { char = 'x' })

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! 2fx')
    end)

    it('calculate omits the count when include_count is false', function()
      local ctx = {
        cursor = { line = 2, col = 4 },
        input = { count = 4 },
      }
      native.calculate('%', ctx, { include_count = false })

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! %')
    end)

    it('calculate returns the post-motion cursor position', function()
      local ctx = {
        cursor = { line = 2, col = 4 },
        input = { count = 1 },
      }
      local result = native.calculate('w', ctx)

      assert.is_not_nil(result.cursor)
      assert.equals(result.cursor.line, 2)
      assert.equals(result.cursor.col, 4)
    end)

    it('calculate returns curswant from winsaveview', function()
      mocks.set_curswant(42)
      local ctx = {
        cursor = { line = 2, col = 4 },
        input = { count = 1 },
      }
      local result = native.calculate('w', ctx)

      assert.equals(result.curswant, 42)
    end)

    it('calculate returns the origin cursor without curswant when normal! fails', function()
      local original_cmd = _G.vim.cmd
      _G.vim.cmd = function() error('E486: pattern not found') end

      local ctx = {
        cursor = { line = 2, col = 4 },
        input = { count = 1 },
      }
      local result = native.calculate('n', ctx)

      _G.vim.cmd = original_cmd

      assert.equals(result.cursor.line, 2)
      assert.equals(result.cursor.col, 4)
      assert.is_nil(result.curswant)
    end)
  end)
  ```

  Register the spec in `tests/init.lua`: add this line directly BEFORE `require('tests.unit.calculators.basic_spec')`:

  ```lua
  require('tests.unit.calculators.native_spec')
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; the `calculators/native` suite fails in `before_each` with `module 'whisk.calculators.native' not found`.

- [ ] Create `lua/whisk/calculators/native.lua` (the LuaCATS annotations below are explicitly called for — this is a pinned cross-wave contract):

  ```lua
  local M = {}

  ---@class WhiskNativeCalculateOptions
  ---@field char string|nil literal suffix appended after the motion command
  ---@field include_count boolean|nil when false the count prefix is omitted (defaults to true)

  ---@param motion_cmd string
  ---@param context table motion context with input.count and cursor fields
  ---@param opts WhiskNativeCalculateOptions|nil
  ---@return { cursor: { line: integer, col: integer }, curswant: integer|nil }
  function M.calculate(motion_cmd, context, opts)
    opts = opts or {}

    local original_view = vim.fn.winsaveview()

    local cmd = motion_cmd
    if opts.include_count ~= false then
      cmd = context.input.count .. cmd
    end
    if opts.char then
      cmd = cmd .. opts.char
    end

    local success = pcall(vim.cmd, "normal! " .. cmd)

    if not success then
      vim.fn.winrestview(original_view)
      return {
        cursor = { line = context.cursor.line, col = context.cursor.col },
      }
    end

    local target = vim.api.nvim_win_get_cursor(0)
    local target_view = vim.fn.winsaveview()

    vim.fn.winrestview(original_view)

    return {
      cursor = { line = target[1], col = target[2] },
      curswant = target_view.curswant,
    }
  end

  return M
  ```

  In `lua/whisk/calculators/init.lua`, add after `M.basic = require("whisk.calculators.basic")`:

  ```lua
  M.native = require("whisk.calculators.native")
  ```

- [ ] Migrate the four callers. Replace the ENTIRE contents of `lua/whisk/calculators/word.lua` with:

  ```lua
  local native = require("whisk.calculators.native")

  local M = {}

  function M.w(context)
    return native.calculate("w", context)
  end

  function M.b(context)
    return native.calculate("b", context)
  end

  function M.e(context)
    return native.calculate("e", context)
  end

  function M.W(context)
    return native.calculate("W", context)
  end

  function M.B(context)
    return native.calculate("B", context)
  end

  function M.E(context)
    return native.calculate("E", context)
  end

  return M
  ```

  Replace the ENTIRE contents of `lua/whisk/calculators/find.lua` with:

  ```lua
  local native = require("whisk.calculators.native")

  local M = {}

  function M.f(context)
    return native.calculate("f", context, { char = context.input.char })
  end

  function M.F(context)
    return native.calculate("F", context, { char = context.input.char })
  end

  function M.t(context)
    return native.calculate("t", context, { char = context.input.char })
  end

  function M.T(context)
    return native.calculate("T", context, { char = context.input.char })
  end

  return M
  ```

  Replace the ENTIRE contents of `lua/whisk/calculators/search.lua` with:

  ```lua
  local native = require("whisk.calculators.native")

  local M = {}

  function M.n(context)
    return native.calculate("n", context)
  end

  function M.N(context)
    return native.calculate("N", context)
  end

  function M.gj(context)
    return native.calculate("gj", context)
  end

  function M.gk(context)
    return native.calculate("gk", context)
  end

  return M
  ```

  Replace the ENTIRE contents of `lua/whisk/calculators/text_object.lua` with (this preserves Wave 1's `%` semantics — count prefix only on an explicit count; verify against the file on the branch before replacing, and keep that semantic exactly):

  ```lua
  local native = require("whisk.calculators.native")

  local M = {}

  M["{"] = function(context)
    return native.calculate("{", context)
  end

  M["}"] = function(context)
    return native.calculate("}", context)
  end

  M["("] = function(context)
    return native.calculate("(", context)
  end

  M[")"] = function(context)
    return native.calculate(")", context)
  end

  M["%"] = function(context)
    return native.calculate("%", context, { include_count = context.input.has_count == true })
  end

  return M
  ```

- [ ] Lock the migrations with command-string tests. Add inside the `describe` block of `tests/unit/calculators/word_spec.lua`:

  ```lua
  it('w delegates through the shared native helper with count prefix', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 2 },
      buffer = { line_count = 3 },
    }
    word.w(ctx)

    local commands = mocks.get_commands()
    assert.equals(commands[#commands], 'normal! 2w')
  end)
  ```

  Add inside the `describe` block of `tests/unit/calculators/find_spec.lua`:

  ```lua
  it('f delegates through the shared native helper with count and char', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 2, char = 'o' },
      buffer = { line_count = 3 },
    }
    find.f(ctx)

    local commands = mocks.get_commands()
    assert.equals(commands[#commands], 'normal! 2fo')
  end)
  ```

  Add inside the `describe` block of `tests/unit/calculators/search_spec.lua`:

  ```lua
  it('n delegates through the shared native helper with count prefix', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 2 },
      buffer = { line_count = 3 },
    }
    search.n(ctx)

    local commands = mocks.get_commands()
    assert.equals(commands[#commands], 'normal! 2n')
  end)
  ```

  Add inside the `describe` block of `tests/unit/calculators/text_object_spec.lua`:

  ```lua
  it('% omits the count prefix without an explicit count after migration', function()
    local ctx = {
      cursor = { line = 8, col = 0 },
      input = { count = 1, has_count = false },
      buffer = { line_count = 9 },
    }
    text_object['%'](ctx)

    local commands = mocks.get_commands()
    assert.equals(commands[#commands], 'normal! %')
  end)

  it('% keeps the count prefix with an explicit count after migration', function()
    local ctx = {
      cursor = { line = 8, col = 0 },
      input = { count = 30, has_count = true },
      buffer = { line_count = 9 },
    }
    text_object['%'](ctx)

    local commands = mocks.get_commands()
    assert.equals(commands[#commands], 'normal! 30%')
  end)
  ```

  (If Wave 1 already added `%` command-string tests with identical names, keep Wave 1's versions and skip the duplicates — the assertions must exist once, not twice.)

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (mock `vim.cmd` is a no-op, so the real motion, view restore, and curswant capture cannot be exercised under the unit harness). Write this to `/tmp/whisk_probe_native.lua`:

  ```lua
  local ok, err = pcall(function()
    local native = require("whisk.calculators.native")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcde" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local result = native.calculate("$", { input = { count = 1 }, cursor = { line = 1, col = 0 } })
    print("cursor=" .. result.cursor.line .. "," .. result.cursor.col)
    print("curswant=" .. tostring(result.curswant))

    local restored = vim.api.nvim_win_get_cursor(0)
    print("restored=" .. restored[1] .. "," .. restored[2])
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_native.lua" 2>&1
  ```
  Expected output (empirically verified on Neovim; `2147483647` is what `winsaveview().curswant` reports after `normal! $` — v:maxcol semantics):
  ```
  cursor=1,4
  curswant=2147483647
  restored=1,0
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/calculators/native.lua lua/whisk/calculators/init.lua lua/whisk/calculators/word.lua lua/whisk/calculators/find.lua lua/whisk/calculators/search.lua lua/whisk/calculators/text_object.lua tests/mocks/vim_fn.lua tests/mocks/init.lua tests/init.lua tests/unit/calculators/native_spec.lua tests/unit/calculators/word_spec.lua tests/unit/calculators/find_spec.lua tests/unit/calculators/search_spec.lua tests/unit/calculators/text_object_spec.lua
  git commit -m "feat(calculators): add shared native delegation helper with curswant capture"
  ```

---

### Task 2: Migrate `h`/`j`/`k`/`l`/`$` and `|` to native delegation (#9, #10)

`basic.h/l` add/subtract the count from the BYTE column and `basic.$` uses byte length, breaking multibyte lines (#9: on `héllo`, `2l` from col 0 must land on col 3, not col 2; `$` on `abé` must land on col 2, not col 3). `basic.j/k` count buffer lines with zero fold handling (#10: with lines 2-5 in a closed fold, `2j` from line 1 must land on line 6, not line 3). `line.|` sets byte column `count - 1` where native `|` targets a display column. Delegate all of them through `native.calculate` so character, fold, and display-column semantics come from Neovim itself. `0` stays direct math (column 0 is always byte 0).

**Files:**
- Modify: `lua/whisk/calculators/basic.lua`, `lua/whisk/calculators/line.lua` (only the `M["|"]` block — `gg`/`G` carry Wave 1 changes and stay untouched)
- Test: `tests/unit/calculators/basic_spec.lua` (rewrite), `tests/unit/calculators/line_spec.lua` (replace the `|` tests only)

**Interfaces:**
- Consumes: `native.calculate(motion_cmd, context, opts)` from Task 1.
- Produces: unchanged calculator signatures `basic.h/j/k/l(context)`, `basic["0"](context)`, `basic["$"](context)`, `line["|"](context)` → `{ cursor = { line, col }, curswant = number|nil }`. Note `basic.j/k/$` now surface `curswant`, which Task 3 consumes.

**Steps:**

- [ ] Rewrite the spec to assert delegation. Replace the ENTIRE contents of `tests/unit/calculators/basic_spec.lua` with:

  ```lua
  local runner = require('tests.runner')
  local assert = require('tests.helpers.assertions')
  local mocks = require('tests.mocks')

  local describe, it, before_each = runner.describe, runner.it, runner.before_each

  describe('calculators/basic', function()
    local basic

    before_each(function()
      mocks.setup()
      mocks.clear_package_cache()
      mocks.set_buffer_content({
        "hello world",
        "second line",
        "third line",
        "fourth line",
        "fifth line",
      })
      mocks.set_cursor(3, 5)
      basic = require('whisk.calculators.basic')
    end)

    it('exports h, j, k, l, 0, $ functions', function()
      assert.is_type(basic.h, 'function')
      assert.is_type(basic.j, 'function')
      assert.is_type(basic.k, 'function')
      assert.is_type(basic.l, 'function')
      assert.is_type(basic['0'], 'function')
      assert.is_type(basic['$'], 'function')
    end)

    it('h delegates to native h with count prefix', function()
      local ctx = {
        cursor = { line = 3, col = 5 },
        input = { count = 2 },
        buffer = { line_count = 5 },
      }
      basic.h(ctx)

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! 2h')
    end)

    it('j delegates to native j with count prefix', function()
      local ctx = {
        cursor = { line = 3, col = 5 },
        input = { count = 2 },
        buffer = { line_count = 5 },
      }
      basic.j(ctx)

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! 2j')
    end)

    it('k delegates to native k with count prefix', function()
      local ctx = {
        cursor = { line = 3, col = 5 },
        input = { count = 4 },
        buffer = { line_count = 5 },
      }
      basic.k(ctx)

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! 4k')
    end)

    it('l delegates to native l with count prefix', function()
      local ctx = {
        cursor = { line = 3, col = 5 },
        input = { count = 3 },
        buffer = { line_count = 5 },
      }
      basic.l(ctx)

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! 3l')
    end)

    it('$ delegates to native $ with count prefix', function()
      local ctx = {
        cursor = { line = 3, col = 5 },
        input = { count = 1 },
        buffer = { line_count = 5 },
      }
      basic['$'](ctx)

      local commands = mocks.get_commands()
      assert.equals(commands[#commands], 'normal! 1$')
    end)

    it('h returns the post-motion cursor from the window', function()
      local ctx = {
        cursor = { line = 3, col = 5 },
        input = { count = 1 },
        buffer = { line_count = 5 },
      }
      local result = basic.h(ctx)

      assert.equals(result.cursor.line, 3)
      assert.equals(result.cursor.col, 5)
    end)

    it('j surfaces curswant from the native motion', function()
      mocks.set_curswant(11)
      local ctx = {
        cursor = { line = 3, col = 5 },
        input = { count = 1 },
        buffer = { line_count = 5 },
      }
      local result = basic.j(ctx)

      assert.equals(result.curswant, 11)
    end)

    it('0 moves to start of line without delegation', function()
      local ctx = {
        cursor = { line = 2, col = 8 },
        input = { count = 1 },
        buffer = { line_count = 5 },
      }
      local commands_before = #mocks.get_commands()
      local result = basic['0'](ctx)

      assert.equals(result.cursor.line, 2)
      assert.equals(result.cursor.col, 0)
      assert.equals(#mocks.get_commands(), commands_before)
    end)

    it('0 from column 0 stays at 0', function()
      local ctx = {
        cursor = { line = 1, col = 0 },
        input = { count = 1 },
        buffer = { line_count = 5 },
      }
      local result = basic['0'](ctx)
      assert.equals(result.cursor.col, 0)
    end)
  end)
  ```

- [ ] Replace the `|` tests in `tests/unit/calculators/line_spec.lua`. Delete every `it(...)` block whose name starts with `'|'` (at 852b689 these are `'| goes to column specified by count'`, `'| with count 1 goes to column 0'`, `'| goes to high column'`, `'| preserves line number'` — match by name prefix on the branch, Wave 1 does not touch them) and add these two in their place:

  ```lua
  it('| delegates to native | with count prefix', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 10 },
      buffer = { line_count = 10 },
    }
    line['|'](ctx)

    local commands = mocks.get_commands()
    assert.equals(commands[#commands], 'normal! 10|')
  end)

  it('| returns the post-motion cursor position', function()
    mocks.set_cursor(5, 3)
    local ctx = {
      cursor = { line = 5, col = 3 },
      input = { count = 1 },
      buffer = { line_count = 10 },
    }
    local result = line['|'](ctx)

    assert.equals(result.cursor.line, 5)
    assert.equals(result.cursor.col, 3)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `calculators/basic > h delegates to native h with count prefix` (arithmetic implementation records no command — `commands[#commands]` is nil) and `calculators/line > | delegates to native | with count prefix` (same shape).

- [ ] Implement. Replace the ENTIRE contents of `lua/whisk/calculators/basic.lua` with (the `get_line_length` local is dead after this migration — it must be removed):

  ```lua
  local native = require("whisk.calculators.native")

  local M = {}

  function M.h(context)
    return native.calculate("h", context)
  end

  function M.j(context)
    return native.calculate("j", context)
  end

  function M.k(context)
    return native.calculate("k", context)
  end

  function M.l(context)
    return native.calculate("l", context)
  end

  M["0"] = function(context)
    return {
      cursor = { line = context.cursor.line, col = 0 },
    }
  end

  M["$"] = function(context)
    return native.calculate("$", context)
  end

  return M
  ```

  In `lua/whisk/calculators/line.lua`, add at the top of the file (before `local M = {}`):

  ```lua
  local native = require("whisk.calculators.native")
  ```

  and replace the `M["|"]` block:

  ```lua
  M["|"] = function(context)
    local target_col = math.max(context.input.count - 1, 0)
    return {
      cursor = { line = context.cursor.line, col = target_col },
    }
  end
  ```

  with:

  ```lua
  M["|"] = function(context)
    return native.calculate("|", context)
  end
  ```

  Do NOT touch `gg`, `G`, `get_first_non_blank`, `get_target_col`, or `calculate_topline` — they carry Wave 1 changes.

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (mock `vim.cmd` is a no-op, so multibyte and fold semantics cannot be exercised under the unit harness). Write this to `/tmp/whisk_probe_basic.lua`:

  ```lua
  local ok, err = pcall(function()
    local basic = require("whisk.calculators.basic")

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "héllo" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local l2 = basic.l({ input = { count = 2 }, cursor = { line = 1, col = 0 } })
    print("multibyte_2l_col=" .. l2.cursor.col)

    local dollar = basic["$"]({ input = { count = 1 }, cursor = { line = 1, col = 0 } })
    print("multibyte_dollar_col=" .. dollar.cursor.col)
    print("dollar_curswant=" .. tostring(dollar.curswant))

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abé" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local dollar2 = basic["$"]({ input = { count = 1 }, cursor = { line = 1, col = 0 } })
    print("abe_dollar_col=" .. dollar2.cursor.col)

    local lines = {}
    for i = 1, 10 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.wo.foldmethod = "manual"
    vim.cmd("2,5fold")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local j2 = basic.j({ input = { count = 2 }, cursor = { line = 1, col = 0 } })
    print("fold_2j_line=" .. j2.cursor.line)
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_basic.lua" 2>&1
  ```
  Expected output (all four values empirically verified against native Neovim behavior — the byte-arithmetic implementation produced 2, 3, and 3 for the first three):
  ```
  multibyte_2l_col=3
  multibyte_dollar_col=5
  dollar_curswant=2147483647
  abe_dollar_col=2
  fold_2j_line=6
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/calculators/basic.lua lua/whisk/calculators/line.lua tests/unit/calculators/basic_spec.lua tests/unit/calculators/line_spec.lua
  git commit -m "fix(calculators): delegate h j k l $ and | to native motions for multibyte and fold fidelity"
  ```

---

### Task 3: Apply curswant at animation completion (#12)

Native Vim tracks curswant: after `$` the desired column is MAXCOL, so `j`/`k` stick to each line's end. Task 1's helper already captures `curswant`; this task carries it to the window. Add `Context:set_curswant(curswant)` (via `nvim_win_call` + `winrestview({ curswant = ... })` — empirically verified: a partial `winrestview` with only `curswant` sets the desired column without moving the cursor) and apply it ONCE at animation completion from the orchestrator's `on_complete`. It must NOT be applied on cancellation (per-frame `set_cursor` calls reset curswant to the actual column; only a completed motion owns the final value).

**Files:**
- Modify: `lua/whisk/context/Context.lua`, `lua/whisk/engine/orchestrator.lua`
- Test: `tests/unit/context/Context_spec.lua` (add), `tests/unit/engine/orchestrator_spec.lua` (add)

**Interfaces:**
- Produces: `Context:set_curswant(curswant) -> boolean, string|nil` — validity-guarded like `set_cursor`/`restore_view`; returns `false, reason` on invalid context. Later waves rely on this exact name.
- Consumes: calculator results carrying `result.curswant` (Tasks 1-2), `loop.start{ on_complete }`.
- Orchestrator contract: `on_complete` applies `result.curswant` (when present) BEFORE clearing animating flags; `on_cancel` never applies it. Task 5's synchronous path reuses the same rule.

**Steps:**

- [ ] Write failing tests. In `tests/unit/context/Context_spec.lua`, add inside the `describe` block (after the `restore_view` tests):

  ```lua
  it('set_curswant() records curswant through winrestview', function()
    local ctx = Context.new(1, 1000)
    local success = ctx:set_curswant(2147483647)
    assert.is_true(success)
    assert.equals(mocks.get_fn_state().curswant, 2147483647)
  end)

  it('set_curswant() returns false with reason if context invalid', function()
    local ctx = Context.new(1, 1000)
    mocks.delete_buffer(1)
    local success, reason = ctx:set_curswant(100)
    assert.is_false(success)
    assert.equals(reason, 'buffer_deleted')
    assert.equals(mocks.get_fn_state().curswant, 0)
  end)
  ```

  In `tests/unit/engine/orchestrator_spec.lua`, add inside the `describe` block:

  ```lua
  it('execute applies curswant at completion (#12)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    motions.register({
      id = 'test_curswant',
      keys = { 'd' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        return {
          cursor = { line = ctx.cursor.line + 1, col = 0 },
          curswant = 2147483647,
        }
      end,
    })

    orchestrator.execute('test_curswant', { count = 1 })
    loop.complete_all()

    assert.equals(mocks.get_fn_state().curswant, 2147483647)
  end)

  it('execute does not apply curswant on cancellation (#12)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    motions.register({
      id = 'test_curswant_cancel',
      keys = { 'e' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        return {
          cursor = { line = ctx.cursor.line + 1, col = 0 },
          curswant = 123,
        }
      end,
    })

    orchestrator.execute('test_curswant_cancel', { count = 1 })
    loop.cancel_for_buffer(1)

    assert.equals(mocks.get_fn_state().curswant, 0)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `context/Context > set_curswant() records curswant through winrestview` (`attempt to call method 'set_curswant' (a nil value)`) and `engine/orchestrator > execute applies curswant at completion (#12)` (state curswant stays 0).

- [ ] Implement. In `lua/whisk/context/Context.lua`, add after the `Context:restore_view` function (before `return Context`):

  ```lua
  function Context:set_curswant(curswant)
    local valid, reason = self:is_valid()
    if not valid then
      return false, reason
    end

    vim.api.nvim_win_call(self.winid, function()
      vim.fn.winrestview({ curswant = curswant })
    end)
    return true
  end
  ```

  In `lua/whisk/engine/orchestrator.lua`, the tail of `M.execute` currently reads (Wave 1's Task 4 shape):

  ```lua
    local function clear_animating()
      for _, trait_id in ipairs(motion.traits) do
        traits.set_animating(trait_id, false)
      end
    end

    loop.start({
      context = context,
      result = result,
      traits = motion.traits,
      duration = category_config.duration,
      easing = category_config.easing,
      on_complete = clear_animating,
      on_cancel = clear_animating,
    })
  ```

  Replace it with:

  ```lua
    local function clear_animating()
      for _, trait_id in ipairs(motion.traits) do
        traits.set_animating(trait_id, false)
      end
    end

    loop.start({
      context = context,
      result = result,
      traits = motion.traits,
      duration = category_config.duration,
      easing = category_config.easing,
      on_complete = function()
        if result.curswant then
          context:set_curswant(result.curswant)
        end
        clear_animating()
      end,
      on_cancel = clear_animating,
    })
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (the mock `winrestview` only records fields; real curswant stickiness cannot be exercised under the unit harness). Write this to `/tmp/whisk_probe_curswant.lua`:

  ```lua
  local ok, err = pcall(function()
    local Context = require("whisk.context.Context")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcde", "xxxxxxxxxx", "yy" })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })

    local ctx = Context.new()
    ctx:set_curswant(2147483647)

    vim.cmd("normal! j")
    local c1 = vim.api.nvim_win_get_cursor(0)
    print("j1=" .. c1[1] .. "," .. c1[2])

    vim.cmd("normal! j")
    local c2 = vim.api.nvim_win_get_cursor(0)
    print("j2=" .. c2[1] .. "," .. c2[2])
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_curswant.lua" 2>&1
  ```
  Expected output (empirically verified — after `set_curswant(2147483647)` from col 4, `j` sticks to each line's end: col 9 on the 10-char line, col 1 on the 2-char line):
  ```
  j1=2,9
  j2=3,1
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/context/Context.lua lua/whisk/engine/orchestrator.lua tests/unit/context/Context_spec.lua tests/unit/engine/orchestrator_spec.lua
  git commit -m "feat(context): apply curswant at animation completion"
  ```

---

### Task 4: Push the jumplist before animated jump motions (#11 — pinned contract 3)

Native `gg`/`G`/`n`/`N`/`%`/`{`/`}`/`(`/`)` are jump commands that push the pre-jump position onto the jumplist; whisk applies results via `nvim_win_set_cursor`, which pushes nothing (and after Task 1 the native-delegation calculators restore the view, so even their incidental pushes are followed by a cursor restore — the flag makes the push explicit and uniform). Add a `jump = true` flag to the affected motion definitions and have the orchestrator execute `m'` in the context window before starting the animation (`m'` sets the pre-jump mark exactly like a native jump; empirically verified deterministic across 5 fresh headless runs via `<C-o>` landing).

**Files:**
- Modify: `lua/whisk/registry/motions.lua` (preserve the `jump` field through `register`), `lua/whisk/registry/builtin.lua` (flag 9 motions), `lua/whisk/engine/orchestrator.lua` (push before animating)
- Test: `tests/unit/registry/motions_spec.lua`, `tests/unit/registry/builtin_spec.lua`, `tests/unit/engine/orchestrator_spec.lua` (add)

**Interfaces:**
- Produces: motion definitions accept `jump = boolean` (normalized to `false` when absent); `motions.get(id).jump` is readable. Pinned cross-wave contract: `line_gg`, `line_G`, `search_n`, `search_N`, `text_object_%`, `text_object_{`, `text_object_}`, `text_object_(`, `text_object_)` carry `jump = true`.
- Produces (private): orchestrator-local `push_jumplist(context)` executing `normal! m'` via `nvim_win_call(context.winid, ...)`. It runs only when `motion.jump` is true AND the motion will actually move (after the same-position early exit), and it also precedes Task 5's synchronous-apply path.

**Steps:**

- [ ] Write failing tests. In `tests/unit/registry/motions_spec.lua`, add inside the `describe` block:

  ```lua
  it('register preserves the jump flag', function()
    motions.register({
      id = 'jump_test',
      keys = { 'G' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() end,
      jump = true,
    })
    assert.is_true(motions.get('jump_test').jump)
  end)

  it('register defaults jump to false', function()
    motions.register({
      id = 'no_jump_test',
      keys = { 'j' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() end,
    })
    assert.is_false(motions.get('no_jump_test').jump)
  end)
  ```

  In `tests/unit/registry/builtin_spec.lua`, add inside the `describe` block:

  ```lua
  it('register_motions marks jump motions (#11)', function()
    builtin.register_motions()

    assert.is_true(motions.get('line_gg').jump)
    assert.is_true(motions.get('line_G').jump)
    assert.is_true(motions.get('search_n').jump)
    assert.is_true(motions.get('search_N').jump)
    assert.is_true(motions.get('text_object_%').jump)
    assert.is_true(motions.get('text_object_{').jump)
    assert.is_true(motions.get('text_object_}').jump)
    assert.is_true(motions.get('text_object_(').jump)
    assert.is_true(motions.get('text_object_)').jump)
  end)

  it('register_motions leaves non-jump motions unmarked (#11)', function()
    builtin.register_motions()

    assert.is_false(motions.get('basic_j').jump)
    assert.is_false(motions.get('word_w').jump)
    assert.is_false(motions.get('scroll_ctrl_d').jump)
  end)
  ```

  In `tests/unit/engine/orchestrator_spec.lua`, add inside the `describe` block:

  ```lua
  it('execute pushes a jumplist entry before animating jump motions (#11)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    motions.register({
      id = 'test_jump',
      keys = { 'G' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      jump = true,
      calculator = function(ctx)
        return { cursor = { line = ctx.cursor.line + 3, col = 0 } }
      end,
    })

    orchestrator.execute('test_jump', { count = 1 })

    local found = false
    for _, cmd in ipairs(mocks.get_commands()) do
      if cmd == "normal! m'" then
        found = true
      end
    end
    assert.is_true(found)
    assert.is_true(loop.is_running())
  end)

  it('execute does not push the jumplist for non-jump motions (#11)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })

    for _, cmd in ipairs(mocks.get_commands()) do
      assert.not_equals(cmd, "normal! m'")
    end
  end)

  it('execute does not push the jumplist when the jump motion is a no-op (#11)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    motions.register({
      id = 'test_jump_same',
      keys = { 'G' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      jump = true,
      calculator = function(ctx)
        return { cursor = { line = ctx.cursor.line, col = ctx.cursor.col } }
      end,
    })

    orchestrator.execute('test_jump_same', { count = 1 })

    for _, cmd in ipairs(mocks.get_commands()) do
      assert.not_equals(cmd, "normal! m'")
    end
    assert.is_false(loop.is_running())
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `registry/motions > register preserves the jump flag` (`motions.get('jump_test').jump` is nil — `register` strips unknown fields), `registry/builtin > register_motions marks jump motions (#11)`, and `engine/orchestrator > execute pushes a jumplist entry before animating jump motions (#11)` (no `normal! m'` recorded).

- [ ] Implement. In `lua/whisk/registry/motions.lua`, inside `M.register`, add `jump = definition.jump == true,` to the `local motion = { ... }` table (after `input = definition.input,`).

  In `lua/whisk/registry/builtin.lua`, add `jump = true,` to these five registration tables, each after the `description` line:
  - `id = "line_gg"` block
  - `id = "line_G"` block
  - `id = "search_n"` block
  - `id = "search_N"` block
  - the `text_objects` loop's `motions.register({ ... })` table (this flags all five: `{`, `}`, `(`, `)`, `%`)

  For example the text-objects loop becomes:

  ```lua
    for key, desc in pairs(text_objects) do
      motions.register({
        id = "text_object_" .. key,
        keys = { key },
        modes = { "n", "v" },
        traits = { "cursor" },
        category = "cursor",
        calculator = calculators.text_object[key],
        description = desc,
        input = "count",
        jump = true,
      })
    end
  ```

  In `lua/whisk/engine/orchestrator.lua`, add after the `is_same_viewport` function:

  ```lua
  local function push_jumplist(context)
    vim.api.nvim_win_call(context.winid, function()
      vim.cmd("normal! m'")
    end)
  end
  ```

  and inside `M.execute`, insert between the same-position early exit and the `set_animating` loop — i.e. after:

  ```lua
    if is_same_position(context, result) and is_same_viewport(context, result) then
      return
    end
  ```

  insert:

  ```lua
    if motion.jump then
      push_jumplist(context)
    end
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (the mock `vim.cmd` is a no-op, so no real jumplist exists under the unit harness). IMPORTANT: assert where `<C-o>` lands — do NOT read `#vim.fn.getjumplist()[1]` right after the push; entries materialize lazily and transiently read as 0 even when the push worked. Write this to `/tmp/whisk_probe_jumplist.lua`:

  ```lua
  local ok, err = pcall(function()
    require("whisk").setup()
    local lines = {}
    for i = 1, 50 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.cmd("clearjumps")
    vim.api.nvim_win_set_cursor(0, { 10, 0 })

    vim.api.nvim_feedkeys("G", "mx", false)
    vim.wait(1000, function()
      return not require("whisk.engine.loop").is_running()
    end)
    print("after_G_line=" .. vim.api.nvim_win_get_cursor(0)[1])

    vim.cmd("normal! \15")
    print("after_ctrl_o_line=" .. vim.api.nvim_win_get_cursor(0)[1])
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  (`"\15"` is the raw Ctrl-O byte.) Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_jumplist.lua" 2>&1
  ```
  Expected output (empirically verified with the `m'`-via-`nvim_win_call` mechanism, deterministic across repeated fresh runs):
  ```
  after_G_line=50
  after_ctrl_o_line=10
  ```
  Before this fix `after_ctrl_o_line` stayed at 50 (empty jumplist). Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/registry/motions.lua lua/whisk/registry/builtin.lua lua/whisk/engine/orchestrator.lua tests/unit/registry/motions_spec.lua tests/unit/registry/builtin_spec.lua tests/unit/engine/orchestrator_spec.lua
  git commit -m "fix(engine): push jumplist entry before animated jump motions"
  ```

---

### Task 5: Synchronous finalization during macro replay (#2 — pinned contract 4)

`M.execute` starts the animation via deferred frames and returns immediately; during macro replay the deferred frames cannot run until control returns to the event loop, so the next macro key operates on the stale pre-animation cursor (verified: register `wx` on `one two three four` deletes at col 0 instead of the word target). Add the pinned `should_skip_animation(context)` seam: when `vim.fn.reg_executing() ~= ""` (replay only — NOT `reg_recording`), apply the calculator result synchronously through the motion's traits at progress 1.0, apply `curswant` if present, and return without touching the loop. The jumplist push (Task 4) runs before this path. Wave 6 extends this same function with buftype/filetype exclusions and min-distance — the function name and call site are a pinned contract.

**Files:**
- Modify: `lua/whisk/engine/orchestrator.lua`
- Modify: `tests/mocks/vim_fn.lua`, `tests/mocks/init.lua` (add `reg_executing`)
- Test: `tests/unit/engine/orchestrator_spec.lua` (add)

**Interfaces:**
- Consumes: `vim.fn.reg_executing()` (empty string when not replaying), `traits.apply_frame(trait_id, context, result, progress)`, `Context:set_curswant` (Task 3), `push_jumplist` (Task 4).
- Produces (private, pinned names): `should_skip_animation(context) -> boolean` and `apply_final_result(motion, context, result)` in `engine/orchestrator.lua`. `M.execute` signature unchanged; when skipping, no `loop` entry is created and no animating flags are set.

**Steps:**

- [ ] Extend the mock. In `tests/mocks/vim_fn.lua`, add `reg_executing = '',` to the `local state = { ... }` table AND to the reassignment inside `function M.reset()` (after `curswant = 0,` in each). Add a setter after `function M.set_curswant(value) ... end`:

  ```lua
  function M.set_reg_executing(value)
    state.reg_executing = value
  end
  ```

  Inside `M.create()`'s returned table, add (after the `getcharstr` entry):

  ```lua
    reg_executing = function()
      return state.reg_executing
    end,
  ```

  In `tests/mocks/init.lua`, add after `function M.set_curswant(value) ... end`:

  ```lua
  function M.set_reg_executing(value)
    vim_fn.set_reg_executing(value)
  end
  ```

- [ ] Write failing tests. In `tests/unit/engine/orchestrator_spec.lua`, add inside the `describe` block:

  ```lua
  it('execute applies the result synchronously during macro replay (#2)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    mocks.set_reg_executing('x')
    orchestrator.execute('test_j', { count = 2 })

    assert.is_false(loop.is_running())
    assert.equals(loop.get_active_count(), 0)
    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 3)
  end)

  it('synchronous path does not mark traits as animating (#2)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    mocks.set_reg_executing('x')
    orchestrator.execute('test_j', { count = 1 })

    assert.is_false(traits.is_animating('cursor'))
  end)

  it('synchronous path applies curswant (#2, #12)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    motions.register({
      id = 'test_sync_curswant',
      keys = { 'p' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function(ctx)
        return {
          cursor = { line = ctx.cursor.line + 1, col = 0 },
          curswant = 77,
        }
      end,
    })

    mocks.set_reg_executing('x')
    orchestrator.execute('test_sync_curswant', { count = 1 })

    assert.equals(mocks.get_fn_state().curswant, 77)
  end)

  it('synchronous path still pushes the jumplist for jump motions (#2, #11)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    motions.register({
      id = 'test_sync_jump',
      keys = { 'G' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      jump = true,
      calculator = function(ctx)
        return { cursor = { line = ctx.cursor.line + 2, col = 0 } }
      end,
    })

    mocks.set_reg_executing('q')
    orchestrator.execute('test_sync_jump', { count = 1 })

    local found = false
    for _, cmd in ipairs(mocks.get_commands()) do
      if cmd == "normal! m'" then
        found = true
      end
    end
    assert.is_true(found)
    assert.is_false(loop.is_running())
  end)

  it('execute animates normally when no register is executing (#2)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    mocks.set_reg_executing('')
    orchestrator.execute('test_j', { count = 1 })

    assert.is_true(loop.is_running())
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `engine/orchestrator > execute applies the result synchronously during macro replay (#2)` — either `loop.is_running()` is true (no skip path yet) or, before the mock landed, `attempt to call field 'reg_executing' (a nil value)`.

- [ ] Implement. In `lua/whisk/engine/orchestrator.lua`, add after the `push_jumplist` function (Task 4):

  ```lua
  local function should_skip_animation(context)
    return vim.fn.reg_executing() ~= ""
  end

  local function apply_final_result(motion, context, result)
    for _, trait_id in ipairs(motion.traits) do
      traits.apply_frame(trait_id, context, result, 1.0)
    end
    if result.curswant then
      context:set_curswant(result.curswant)
    end
  end
  ```

  Inside `M.execute`, insert between the jump push and the `set_animating` loop — i.e. after:

  ```lua
    if motion.jump then
      push_jumplist(context)
    end
  ```

  insert:

  ```lua
    if should_skip_animation(context) then
      apply_final_result(motion, context, result)
      return
    end
  ```

  (Applying the raw `result` at progress 1.0 is exact: interpolation at 1.0 reproduces the result values, and the trait `apply` functions guard missing `cursor`/`viewport` fields themselves.)

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (mock `vim.cmd`/`nvim_feedkeys` are no-ops; real macro replay cannot be exercised under the unit harness). This reproduces finding #2's verified failure case end-to-end. Write this to `/tmp/whisk_probe_macro.lua`:

  ```lua
  local ok, err = pcall(function()
    require("whisk").setup()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one two three four" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.fn.setreg("x", "wx")

    vim.cmd("normal @x")

    print("line=" .. vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    print("col=" .. vim.api.nvim_win_get_cursor(0)[2])
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_macro.lua" 2>&1
  ```
  Expected output (`w` lands on the `t` of `two` at col 4, then `x` deletes it there — the finding's verified pre-fix output was `line=ne two three four`, `col=0`):
  ```
  line=one wo three four
  col=4
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/engine/orchestrator.lua tests/mocks/vim_fn.lua tests/mocks/init.lua tests/unit/engine/orchestrator_spec.lua
  git commit -m "fix(engine): apply motion results synchronously during macro replay"
  ```

---

### Task 6: Any keypress snaps animations to completion via `vim.on_key` (V1)

Task 5 fixes macro replay, but the general race remains: any non-whisk key typed during the ~150-200ms animation window (`x`, `i`, `dd`, another plugin's mapping) executes at the interpolated mid-flight position. Register a `vim.on_key` listener under a dedicated namespace whenever the frame queue goes 0→1 and remove it when the queue empties; the listener calls `M.complete_all()` so any keypress during an animation snaps it to its final position before the key's effect is processed. Completing on whisk's own keys is harmless — it is equivalent to the existing domination path (`complete_all` before `start`).

**Files:**
- Modify: `lua/whisk/engine/loop.lua`
- Modify: `tests/mocks/vim_core.lua`, `tests/mocks/vim_api.lua`, `tests/mocks/init.lua` (add `vim.on_key` + `nvim_create_namespace`)
- Test: `tests/unit/engine/loop_spec.lua` (add)

**Interfaces:**
- Consumes: `vim.on_key(fn, ns_id)` (nil `fn` removes the listener for that namespace), `vim.api.nvim_create_namespace("whisk_engine_loop")`.
- Produces (private): loop-local `attach_key_listener()` / `detach_key_listener()`. Attach happens in `M.start` when the queue was empty; detach happens at every point the queue empties: `process_frame`'s drain branch, `stop_all`, `complete_all`, and `cancel_for_buffer`/`cancel_for_window` when they empty the queue. No public API change.

**Steps:**

- [ ] Extend the mocks. In `tests/mocks/vim_core.lua`, add `on_key_listeners = {},` to the `local state = { ... }` table AND to the reassignment inside `function M.reset()` (after `hrtime_value = 0,` in each). Add after the `M.defer_fn` definition:

  ```lua
  M.on_key = function(fn, ns_id)
    local key = ns_id or 0
    if fn == nil then
      state.on_key_listeners[key] = nil
    else
      state.on_key_listeners[key] = fn
    end
  end

  function M.get_on_key_listeners()
    return state.on_key_listeners
  end
  ```

  In `tests/mocks/vim_api.lua`, add `namespaces = {},` and `namespace_id = 0,` to the `local state = { ... }` table AND to the reassignment inside `function M.reset()` (after `augroup_id = 0,` in each). Inside `function M.create()`'s returned table, add (after `nvim_create_augroup`):

  ```lua
      nvim_create_namespace = function(name)
        if state.namespaces[name] then
          return state.namespaces[name]
        end
        state.namespace_id = state.namespace_id + 1
        state.namespaces[name] = state.namespace_id
        return state.namespaces[name]
      end,
  ```

  In `tests/mocks/init.lua`, add `on_key = vim_core.on_key,` to the `_G.vim = { ... }` table (after `defer_fn = vim_core.defer_fn,`), and add after `function M.get_deferred_calls() ... end`:

  ```lua
  function M.get_on_key_listeners()
    return vim_core.get_on_key_listeners()
  end
  ```

- [ ] Write failing tests. In `tests/unit/engine/loop_spec.lua`, add inside the `describe('engine/loop', ...)` block, directly after the `before_each`/`after_each` setup:

  ```lua
  local function count_key_listeners()
    local count = 0
    for _, _ in pairs(mocks.get_on_key_listeners()) do
      count = count + 1
    end
    return count
  end
  ```

  and add these tests:

  ```lua
  it('start attaches an on_key listener when the queue becomes active (V1)', function()
    assert.equals(count_key_listeners(), 0)

    loop.start({
      duration = 100,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    assert.equals(count_key_listeners(), 1)
  end)

  it('a second start does not attach a second listener (V1)', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })
    loop.start({
      duration = 100,
      easing = 'linear',
      context = { viewport = { topline = 1 } },
      result = { viewport = { topline = 10 } },
      traits = {},
    })

    assert.equals(count_key_listeners(), 1)
  end)

  it('complete_all detaches the listener (V1)', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.complete_all()
    assert.equals(count_key_listeners(), 0)
  end)

  it('stop_all detaches the listener (V1)', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.stop_all()
    assert.equals(count_key_listeners(), 0)
  end)

  it('cancel_for_buffer detaches the listener when the queue empties (V1)', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      context = { bufnr = 1, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.cancel_for_buffer(1)
    assert.equals(count_key_listeners(), 0)
  end)

  it('the listener detaches when the queue drains naturally (V1)', function()
    loop.start({
      duration = 0,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    mocks.execute_deferred(1)
    assert.equals(count_key_listeners(), 0)
  end)

  it('the key listener snaps animations to completion (V1)', function()
    local traits = require('whisk.registry.traits')
    traits.register({
      id = 'cursor',
      apply = function(context, result, progress)
        if result.cursor then
          mocks.set_cursor(result.cursor.line, result.cursor.col)
        end
      end,
    })

    loop.start({
      duration = 150,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
    })

    local listener = nil
    for _, fn in pairs(mocks.get_on_key_listeners()) do
      listener = fn
    end
    assert.is_not_nil(listener)

    listener()

    assert.equals(loop.get_active_count(), 0)
    assert.is_false(loop.is_running())
    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 5)
    assert.equals(count_key_listeners(), 0)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `engine/loop > start attaches an on_key listener when the queue becomes active (V1)` (count is 0, expected 1).

- [ ] Implement. In `lua/whisk/engine/loop.lua`, add after `local is_running = false`:

  ```lua
  local key_listener_namespace = nil

  local function attach_key_listener()
    if key_listener_namespace then
      return
    end
    key_listener_namespace = vim.api.nvim_create_namespace("whisk_engine_loop")
    vim.on_key(function()
      M.complete_all()
    end, key_listener_namespace)
  end

  local function detach_key_listener()
    if not key_listener_namespace then
      return
    end
    vim.on_key(nil, key_listener_namespace)
    key_listener_namespace = nil
  end
  ```

  In `M.start`, replace:

  ```lua
    table.insert(frame_queue, anim)
  ```

  with:

  ```lua
    if #frame_queue == 0 then
      attach_key_listener()
    end
    table.insert(frame_queue, anim)
  ```

  In `process_frame`, replace the drain branch:

  ```lua
    if #frame_queue > 0 then
      vim.defer_fn(process_frame, performance.get_frame_interval())
    else
      is_running = false
    end
  ```

  with:

  ```lua
    if #frame_queue > 0 then
      vim.defer_fn(process_frame, performance.get_frame_interval())
    else
      is_running = false
      detach_key_listener()
    end
  ```

  In `M.stop_all`, add `detach_key_listener()` directly after `is_running = false`. In `M.complete_all`, add `detach_key_listener()` directly after `is_running = false`. In `M.cancel_for_buffer` AND `M.cancel_for_window`, replace:

  ```lua
    if #frame_queue == 0 then
      is_running = false
    end
  ```

  with:

  ```lua
    if #frame_queue == 0 then
      is_running = false
      detach_key_listener()
    end
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (mock `vim.on_key` never fires from real input; the fast-typing race can only be exercised in a real Neovim). This reproduces V1's failure scenario: `w` then `x` typed in the same input burst. Write this to `/tmp/whisk_probe_onkey.lua`:

  ```lua
  local ok, err = pcall(function()
    require("whisk").setup()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one two three four" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.api.nvim_feedkeys("wx", "mx", false)

    print("line=" .. vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    print("col=" .. vim.api.nvim_win_get_cursor(0)[2])
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_onkey.lua" 2>&1
  ```
  Expected output (the `x` keypress fires the on_key listener, which completes the `w` animation to col 4 before `x` deletes there; `reg_executing` is empty here so Task 5's path does NOT mask this — this exercises the listener):
  ```
  line=one wo three four
  col=4
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/engine/loop.lua tests/mocks/vim_core.lua tests/mocks/vim_api.lua tests/mocks/init.lua tests/unit/engine/loop_spec.lua
  git commit -m "fix(engine): snap animations to completion on any keypress via vim.on_key"
  ```

---

### Task 7: Single frame-loop timer via a pending-tick guard (#14)

`complete_all`/`cancel_for_*` set `is_running = false` while a `process_frame` timer scheduled by the previous frame is still pending; the domination path (`complete_all()` then `loop.start()` in the same `execute` call) then arms a SECOND timer, and each rapid domination leaks another concurrent `process_frame` chain. Track a `timer_pending` flag: set when `defer_fn` is scheduled, cleared at tick entry; `M.start` schedules only when no tick is pending; `process_frame` reschedules only when the queue is non-empty, so an orphaned tick after `complete_all`/`stop_all`/`cancel_*` is a safe no-op that simply dies.

**Files:**
- Modify: `lua/whisk/engine/loop.lua`
- Test: `tests/unit/engine/loop_spec.lua` (add)

**Interfaces:**
- Produces: no public API change. Internal invariant: at most one `process_frame` tick pending at any time; `is_running` continues to mean "queue active" for `M.is_running()` consumers.
- Consumes: mock `vim.defer_fn` recording (`mocks.get_deferred_calls()`, `mocks.execute_deferred(index)`).

**Steps:**

- [ ] Write failing tests. In `tests/unit/engine/loop_spec.lua`, add inside the `describe` block:

  ```lua
  it('domination does not arm a second frame timer (#14)', function()
    loop.start({
      duration = 1000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })
    assert.equals(#mocks.get_deferred_calls(), 1)

    loop.complete_all()
    loop.start({
      duration = 1000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 9, col = 0 } },
      traits = {},
    })

    assert.equals(#mocks.get_deferred_calls(), 1)
  end)

  it('an orphaned tick after complete_all is a safe no-op (#14)', function()
    loop.start({
      duration = 1000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })
    loop.complete_all()

    assert.does_not_throw(function()
      mocks.execute_deferred(1)
    end)
    assert.equals(#mocks.get_deferred_calls(), 1)
    assert.is_false(loop.is_running())
  end)

  it('the surviving tick drives a dominating animation and reschedules (#14)', function()
    loop.start({
      duration = 1000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })
    loop.complete_all()
    loop.start({
      duration = 1000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 9, col = 0 } },
      traits = {},
    })

    mocks.execute_deferred(1)

    assert.equals(loop.get_active_count(), 1)
    assert.equals(#mocks.get_deferred_calls(), 2)
    assert.is_true(loop.is_running())
  end)

  it('start after an idle drain arms a fresh timer (#14)', function()
    loop.start({
      duration = 1000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })
    loop.complete_all()
    mocks.execute_deferred(1)

    loop.start({
      duration = 1000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 9, col = 0 } },
      traits = {},
    })

    assert.equals(#mocks.get_deferred_calls(), 2)
    assert.is_true(loop.is_running())
  end)
  ```

  (The mock `hrtime` advances 100ms per call and `duration = 1000` gives progress 0.1 on the first tick, so the animation stays queued and MUST reschedule.)

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `engine/loop > domination does not arm a second frame timer (#14)` (deferred count is 2 — `complete_all` cleared `is_running` so the second `start` armed a duplicate timer).

- [ ] Implement. In `lua/whisk/engine/loop.lua` (post-Task-6 state), replace:

  ```lua
  local frame_queue = {}
  local is_running = false
  ```

  with:

  ```lua
  local frame_queue = {}
  local is_running = false
  local timer_pending = false
  ```

  Convert `process_frame` to a forward-declared local so a shared scheduler can precede it. Replace the line:

  ```lua
  local function process_frame()
  ```

  with:

  ```lua
  local process_frame

  local function schedule_frame()
    timer_pending = true
    vim.defer_fn(function()
      process_frame()
    end, performance.get_frame_interval())
  end

  process_frame = function()
    timer_pending = false
  ```

  (the first original body line, `local current_time = vim.loop.hrtime()`, now follows `timer_pending = false`). Replace `process_frame`'s drain branch:

  ```lua
    if #frame_queue > 0 then
      vim.defer_fn(process_frame, performance.get_frame_interval())
    else
      is_running = false
      detach_key_listener()
    end
  ```

  with:

  ```lua
    if #frame_queue > 0 then
      schedule_frame()
    else
      is_running = false
      detach_key_listener()
    end
  ```

  and close the function with `end` as before. In `M.start`, replace:

  ```lua
    if not is_running then
      is_running = true
      vim.defer_fn(process_frame, performance.get_frame_interval())
    end
  ```

  with:

  ```lua
    is_running = true
    if not timer_pending then
      schedule_frame()
    end
  ```

  `stop_all`, `complete_all`, `cancel_for_buffer`, and `cancel_for_window` are deliberately left NOT clearing `timer_pending` — a still-pending tick after them finds an empty queue (no-op, dies) or a re-armed queue (drives it, single chain either way).

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`. (No headless probe: the duplicate-timer invariant is fully observable through the mock `defer_fn` records; there is no real-nvim behavior the mocks cannot express here.)

- [ ] Commit:
  ```
  git add lua/whisk/engine/loop.lua tests/unit/engine/loop_spec.lua
  git commit -m "fix(engine): enforce single frame-loop timer with pending-tick guard"
  ```

---

### Task 8: `<C-d>`/`<C-u>` honor the `'scroll'` option and shift the viewport (#4)

Native `<C-d>` scrolls by the `'scroll'` option (default half a window), `{n}<C-d>` scrolls by n LINES and SETS `'scroll'` to n, and both preserve the cursor's screen row. whisk instead scrolls `count * floor(height/2)` and re-centers the target via `calculate_topline` (empirically verified: native `2<C-d>` from topline 40/line 50 gives topline 42/line 52 and `'scroll'`=2; whisk gave a 20-line jump with a re-centered viewport). Fix `ctrl_d`/`ctrl_u`: per-press amount is `context.input.count` when `has_count` (also assigning `vim.wo.scroll = count`), else `vim.wo.scroll` falling back to `floor(height/2)` when 0; the topline shifts BY the amount (clamped), never through `calculate_topline`. `ctrl_f`/`ctrl_b` are out of this finding's pinned scope and stay untouched.

**Files:**
- Modify: `lua/whisk/calculators/scroll.lua`
- Modify: `tests/mocks/vim_core.lua`, `tests/mocks/init.lua` (add `vim.wo`)
- Test: `tests/unit/calculators/scroll_spec.lua` (add)

**Interfaces:**
- Consumes: `context.input.has_count` (Wave 1 contract), `context.input.count`, `vim.wo.scroll` (read AND written), `context.viewport.{topline,height}`, `context.buffer.line_count`.
- Produces (private): `effective_scroll(context)`, `scroll_amount(context)`, and `clamp_topline(topline, context)` locals in `calculators/scroll.lua` (`clamp_topline` is reused by Task 9). Calculator signatures unchanged.
- Mock contract: `_G.vim.wo` is `vim_core.window_options` with `scroll = 0`, `scrolloff = -1` defaults, reset by `vim_core.reset()`.

**Steps:**

- [ ] Extend the mock with window options. In `tests/mocks/vim_core.lua`, add after the `M.options = { ... }` table:

  ```lua
  M.window_options = {
    scroll = 0,
    scrolloff = -1,
  }
  ```

  and add at the END of `function M.reset()` (after the `state = { ... }` reassignment):

  ```lua
    M.window_options.scroll = 0
    M.window_options.scrolloff = -1
  ```

  In `tests/mocks/init.lua`, add `wo = vim_core.window_options,` to the `_G.vim = { ... }` table (after `o = vim_core.options,`).

- [ ] Write failing tests. In `tests/unit/calculators/scroll_spec.lua`, add inside the `describe` block:

  ```lua
  it('ctrl_d without count scrolls by the scroll option (#4)', function()
    _G.vim.wo.scroll = 5
    local ctx = {
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1, has_count = false },
      buffer = { line_count = 100 },
    }
    local result = scroll.ctrl_d(ctx)

    assert.equals(result.cursor.line, 55)
    assert.equals(result.viewport.topline, 45)
  end)

  it('ctrl_d falls back to half the window height when scroll is 0 (#4)', function()
    _G.vim.wo.scroll = 0
    local ctx = {
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1, has_count = false },
      buffer = { line_count = 100 },
    }
    local result = scroll.ctrl_d(ctx)

    assert.equals(result.cursor.line, 60)
    assert.equals(result.viewport.topline, 50)
  end)

  it('ctrl_d with explicit count scrolls by count lines and sets the scroll option (#4)', function()
    _G.vim.wo.scroll = 0
    local ctx = {
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = 20 },
      input = { count = 2, has_count = true },
      buffer = { line_count = 100 },
    }
    local result = scroll.ctrl_d(ctx)

    assert.equals(result.cursor.line, 52)
    assert.equals(result.viewport.topline, 42)
    assert.equals(_G.vim.wo.scroll, 2)
  end)

  it('ctrl_u mirrors ctrl_d semantics (#4)', function()
    _G.vim.wo.scroll = 0
    local ctx = {
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = 20 },
      input = { count = 2, has_count = true },
      buffer = { line_count = 100 },
    }
    local result = scroll.ctrl_u(ctx)

    assert.equals(result.cursor.line, 48)
    assert.equals(result.viewport.topline, 38)
    assert.equals(_G.vim.wo.scroll, 2)
  end)

  it('ctrl_d preserves the cursor screen row (#4)', function()
    _G.vim.wo.scroll = 7
    local ctx = {
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1, has_count = false },
      buffer = { line_count = 100 },
    }
    local result = scroll.ctrl_d(ctx)

    assert.equals(result.cursor.line - result.viewport.topline, 50 - 40)
  end)

  it('ctrl_d clamps the topline to the last full page (#4)', function()
    _G.vim.wo.scroll = 10
    local ctx = {
      cursor = { line = 95, col = 0 },
      viewport = { topline = 79, height = 20 },
      input = { count = 1, has_count = false },
      buffer = { line_count = 100 },
    }
    local result = scroll.ctrl_d(ctx)

    assert.equals(result.cursor.line, 100)
    assert.equals(result.viewport.topline, 81)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `calculators/scroll > ctrl_d without count scrolls by the scroll option (#4)` (current code returns line 60 — `floor(20/2) * 1` — expected 55) and `ctrl_d with explicit count ...` (current code returns line 70 — half-page times count — expected 52).

- [ ] Implement. In `lua/whisk/calculators/scroll.lua`, add after the existing `calculate_topline` function:

  ```lua
  local function clamp_topline(topline, context)
    local max_topline = math.max(context.buffer.line_count - context.viewport.height + 1, 1)
    return math.max(1, math.min(topline, max_topline))
  end

  local function effective_scroll(context)
    local scroll_option = vim.wo.scroll
    if not scroll_option or scroll_option == 0 then
      return math.floor(context.viewport.height / 2)
    end
    return scroll_option
  end

  local function scroll_amount(context)
    if context.input.has_count then
      vim.wo.scroll = context.input.count
      return context.input.count
    end
    return effective_scroll(context)
  end
  ```

  Replace the `M.ctrl_d` and `M.ctrl_u` functions with:

  ```lua
  function M.ctrl_d(context)
    local amount = scroll_amount(context)
    local target_line = math.min(context.cursor.line + amount, context.buffer.line_count)
    local target_topline = clamp_topline(context.viewport.topline + amount, context)

    return {
      cursor = { line = target_line, col = context.cursor.col },
      viewport = { topline = target_topline },
    }
  end

  function M.ctrl_u(context)
    local amount = scroll_amount(context)
    local target_line = math.max(context.cursor.line - amount, 1)
    local target_topline = clamp_topline(context.viewport.topline - amount, context)

    return {
      cursor = { line = target_line, col = context.cursor.col },
      viewport = { topline = target_topline },
    }
  end
  ```

  `ctrl_f`, `ctrl_b`, `zz`, `zt`, `zb`, and `calculate_topline` stay untouched in this task. (The topline clamp keeps the existing repo convention of `line_count - height + 1` — no end-of-buffer overscroll.)

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (mock `vim.wo` is inert state; parity with the real `<C-d>` must be checked in a real Neovim). Write this to `/tmp/whisk_probe_scroll.lua`:

  ```lua
  local ok, err = pcall(function()
    local scroll = require("whisk.calculators.scroll")
    local lines = {}
    for i = 1, 200 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    local height = vim.api.nvim_win_get_height(0)

    vim.fn.winrestview({ topline = 40, lnum = 50, col = 0 })
    local whisk_result = scroll.ctrl_d({
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = height },
      input = { count = 2, has_count = true },
      buffer = { line_count = 200 },
    })
    print("whisk line=" .. whisk_result.cursor.line .. " topline=" .. whisk_result.viewport.topline .. " scroll=" .. vim.wo.scroll)

    vim.fn.winrestview({ topline = 40, lnum = 50, col = 0 })
    local keys = vim.api.nvim_replace_termcodes("2<C-d>", true, false, true)
    vim.api.nvim_feedkeys(keys, "nx", false)
    local native_view = vim.fn.winsaveview()
    print("native line=" .. native_view.lnum .. " topline=" .. native_view.topline .. " scroll=" .. vim.wo.scroll)

    print("match=" .. tostring(
      whisk_result.cursor.line == native_view.lnum
      and whisk_result.viewport.topline == native_view.topline
    ))
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_scroll.lua" 2>&1
  ```
  Expected output (empirically verified: native `2<C-d>` moved topline 40→42, cursor 50→52, and set `'scroll'` to 2):
  ```
  whisk line=52 topline=42 scroll=2
  native line=52 topline=42 scroll=2
  match=true
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/calculators/scroll.lua tests/mocks/vim_core.lua tests/mocks/init.lua tests/unit/calculators/scroll_spec.lua
  git commit -m "fix(calculators): honor scroll option and count-as-scroll for ctrl-d and ctrl-u"
  ```

---

### Task 9: `zt`/`zb` honor `'scrolloff'` (#26)

`zt` sets `topline = cursor line` and `zb` sets `topline = cursor line - height + 1`, placing the cursor flush against the window edge. Native `zt`/`zb` keep the cursor `'scrolloff'` lines away from the edge (empirically verified: height 22, line 50, `scrolloff=5` → native `zt` topline 45, native `zb` topline 34). Offset the toplines by the effective scrolloff: `vim.wo.scrolloff`, falling back to `vim.o.scrolloff` when the window-local value is -1 (the "use global" sentinel).

**Files:**
- Modify: `lua/whisk/calculators/scroll.lua`
- Test: `tests/unit/calculators/scroll_spec.lua` (add)

**Interfaces:**
- Consumes: `vim.wo.scrolloff` (mock default -1), `vim.o.scrolloff` (mock default 5), `clamp_topline(topline, context)` from Task 8.
- Produces (private): `effective_scrolloff()` local in `calculators/scroll.lua`. Formulas (pinned): `zt` topline = `line - scrolloff`; `zb` topline = `line - height + 1 + scrolloff`; both through `clamp_topline`. Calculator signatures unchanged; `zz` untouched.

**Steps:**

- [ ] Write failing tests. In `tests/unit/calculators/scroll_spec.lua`, add inside the `describe` block:

  ```lua
  it('zt offsets the topline by the window scrolloff (#26)', function()
    _G.vim.wo.scrolloff = 3
    local ctx = {
      cursor = { line = 50, col = 5 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1 },
      buffer = { line_count = 100 },
    }
    local result = scroll.zt(ctx)

    assert.equals(result.viewport.topline, 47)
  end)

  it('zb offsets the topline by the window scrolloff (#26)', function()
    _G.vim.wo.scrolloff = 3
    local ctx = {
      cursor = { line = 50, col = 5 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1 },
      buffer = { line_count = 100 },
    }
    local result = scroll.zb(ctx)

    assert.equals(result.viewport.topline, 34)
  end)

  it('zt falls back to the global scrolloff when the window value is -1 (#26)', function()
    _G.vim.wo.scrolloff = -1
    _G.vim.o.scrolloff = 5
    local ctx = {
      cursor = { line = 50, col = 5 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1 },
      buffer = { line_count = 100 },
    }
    local result = scroll.zt(ctx)

    assert.equals(result.viewport.topline, 45)
  end)

  it('zb falls back to the global scrolloff when the window value is -1 (#26)', function()
    _G.vim.wo.scrolloff = -1
    _G.vim.o.scrolloff = 5
    local ctx = {
      cursor = { line = 50, col = 5 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1 },
      buffer = { line_count = 100 },
    }
    local result = scroll.zb(ctx)

    assert.equals(result.viewport.topline, 36)
  end)

  it('zt clamps to line 1 near the top of the buffer (#26)', function()
    _G.vim.wo.scrolloff = 5
    local ctx = {
      cursor = { line = 2, col = 0 },
      viewport = { topline = 1, height = 20 },
      input = { count = 1 },
      buffer = { line_count = 100 },
    }
    local result = scroll.zt(ctx)

    assert.equals(result.viewport.topline, 1)
  end)

  it('zb clamps to line 1 near the top of the buffer (#26)', function()
    _G.vim.wo.scrolloff = 5
    local ctx = {
      cursor = { line = 5, col = 0 },
      viewport = { topline = 1, height = 20 },
      input = { count = 1 },
      buffer = { line_count = 100 },
    }
    local result = scroll.zb(ctx)

    assert.equals(result.viewport.topline, 1)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `calculators/scroll > zt offsets the topline by the window scrolloff (#26)` (current code returns topline 50 — flush — expected 47) and the `zb` variant (current code returns 31, expected 34).

- [ ] Implement. In `lua/whisk/calculators/scroll.lua`, add after the `scroll_amount` function (Task 8):

  ```lua
  local function effective_scrolloff()
    local scrolloff = vim.wo.scrolloff
    if scrolloff == nil or scrolloff < 0 then
      scrolloff = vim.o.scrolloff or 0
    end
    return scrolloff
  end
  ```

  Replace the `M.zt` and `M.zb` functions with:

  ```lua
  function M.zt(context)
    local target_topline = clamp_topline(context.cursor.line - effective_scrolloff(), context)

    return {
      cursor = { line = context.cursor.line, col = context.cursor.col },
      viewport = { topline = target_topline },
    }
  end

  function M.zb(context)
    local target_topline = clamp_topline(context.cursor.line - context.viewport.height + 1 + effective_scrolloff(), context)

    return {
      cursor = { line = context.cursor.line, col = context.cursor.col },
      viewport = { topline = target_topline },
    }
  end
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (parity with real `zt`/`zb` under a live `'scrolloff'`). Write this to `/tmp/whisk_probe_ztzb.lua`:

  ```lua
  local ok, err = pcall(function()
    local scroll = require("whisk.calculators.scroll")
    local lines = {}
    for i = 1, 200 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.o.scrolloff = 5
    local height = vim.api.nvim_win_get_height(0)
    local ctx = {
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = height },
      input = { count = 1 },
      buffer = { line_count = 200 },
    }

    vim.fn.winrestview({ topline = 40, lnum = 50, col = 0 })
    local zt = scroll.zt(ctx)
    vim.cmd("normal! zt")
    local native_zt = vim.fn.winsaveview().topline
    print("zt whisk=" .. zt.viewport.topline .. " native=" .. native_zt .. " match=" .. tostring(zt.viewport.topline == native_zt))

    vim.fn.winrestview({ topline = 40, lnum = 50, col = 0 })
    local zb = scroll.zb(ctx)
    vim.cmd("normal! zb")
    local native_zb = vim.fn.winsaveview().topline
    print("zb whisk=" .. zb.viewport.topline .. " native=" .. native_zb .. " match=" .. tostring(zb.viewport.topline == native_zb))
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_ztzb.lua" 2>&1
  ```
  Expected output (empirically verified at the default headless window height of 22 — the `match=true` fields are the assertion; the absolute numbers hold at that height):
  ```
  zt whisk=45 native=45 match=true
  zb whisk=34 native=34 match=true
  ```
  This also exercises the -1 fallback: a real window's `vim.wo.scrolloff` is -1 by default, so the calculator reads the global 5. Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/calculators/scroll.lua tests/unit/calculators/scroll_spec.lua
  git commit -m "fix(calculators): honor scrolloff in zt and zb targets"
  ```

---

### Task 10: Capture and preserve `leftcol` in animated view restores (#27)

`Context:restore_view` hardcodes `leftcol = 0`, so every animated frame of any scroll-trait motion snaps horizontal scroll back to column 0 on `nowrap` buffers. Capture the starting `leftcol` in the context (`context/builder.lua`, via `nvim_win_call` + `winsaveview`) and have `restore_view` use it. Design choice (documented here as the Interfaces contract): the `restore_view(topline, line, col)` signature stays unchanged; `leftcol` is read from `self.viewport.leftcol`, defaulting to 0 for bare `Context` instances that were not built by the builder.

**Files:**
- Modify: `lua/whisk/context/builder.lua`, `lua/whisk/context/Context.lua`
- Modify: `tests/mocks/vim_fn.lua`, `tests/mocks/init.lua` (add `leftcol` state)
- Test: `tests/unit/context/builder_spec.lua`, `tests/unit/context/Context_spec.lua` (add)

**Interfaces:**
- Produces: `ctx.viewport.leftcol` (integer, captured at build time); `Context:restore_view(topline, line, col)` signature UNCHANGED — `leftcol` sourced from `self.viewport and self.viewport.leftcol or 0`.
- Consumes: `vim.api.nvim_win_call(winid, fn)`, `vim.fn.winsaveview().leftcol`, `vim.fn.winrestview{ leftcol }`.
- Mock contract: `vim_fn` state gains `leftcol` (default 0), `winsaveview` returns it, `winrestview` records it, `mocks.set_leftcol(value)` sets it.

**Steps:**

- [ ] Extend the mock. In `tests/mocks/vim_fn.lua`, add `leftcol = 0,` to the `local state = { ... }` table AND to the reassignment inside `function M.reset()` (after `reg_executing = '',` in each). Add a setter after `function M.set_reg_executing(value) ... end`:

  ```lua
  function M.set_leftcol(value)
    state.leftcol = value
  end
  ```

  In `M.create()`'s `winsaveview`, change `leftcol = 0,` to `leftcol = state.leftcol,`. In `winrestview`, add after the `curswant` clause:

  ```lua
      if view.leftcol ~= nil then
        state.leftcol = view.leftcol
      end
  ```

  In `tests/mocks/init.lua`, add after `function M.set_reg_executing(value) ... end`:

  ```lua
  function M.set_leftcol(value)
    vim_fn.set_leftcol(value)
  end
  ```

- [ ] Write failing tests. In `tests/unit/context/builder_spec.lua`, add inside the `describe` block:

  ```lua
  it('build captures leftcol in the viewport (#27)', function()
    mocks.set_leftcol(8)
    mocks.clear_package_cache()
    local ctx = require('whisk.context.builder').build({})
    assert.equals(ctx.viewport.leftcol, 8)
  end)

  it('build captures leftcol 0 by default (#27)', function()
    local ctx = builder.build({})
    assert.equals(ctx.viewport.leftcol, 0)
  end)
  ```

  In `tests/unit/context/Context_spec.lua`, add inside the `describe` block:

  ```lua
  it('restore_view() preserves leftcol from the context viewport (#27)', function()
    local ctx = Context.new(1, 1000)
    ctx.viewport = { leftcol = 8 }
    mocks.set_leftcol(0)
    ctx:restore_view(2, 3, 1)
    assert.equals(mocks.get_fn_state().leftcol, 8)
  end)

  it('restore_view() defaults leftcol to 0 without viewport data (#27)', function()
    mocks.set_leftcol(5)
    local ctx = Context.new(1, 1000)
    ctx:restore_view(2, 3, 1)
    assert.equals(mocks.get_fn_state().leftcol, 0)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `context/builder > build captures leftcol in the viewport (#27)` (`ctx.viewport.leftcol` is nil) and `context/Context > restore_view() preserves leftcol from the context viewport (#27)` (recorded leftcol is 0 — hardcoded — expected 8).

- [ ] Implement. In `lua/whisk/context/builder.lua`, replace the viewport block:

  ```lua
    ctx.viewport = {
      topline = ctx.start.topline,
      height = vim.api.nvim_win_get_height(ctx.winid),
      width = vim.api.nvim_win_get_width(ctx.winid),
    }
  ```

  with:

  ```lua
    local view = vim.api.nvim_win_call(ctx.winid, function()
      return vim.fn.winsaveview()
    end)

    ctx.viewport = {
      topline = ctx.start.topline,
      height = vim.api.nvim_win_get_height(ctx.winid),
      width = vim.api.nvim_win_get_width(ctx.winid),
      leftcol = view.leftcol,
    }
  ```

  (Do not touch the `ctx.input` block — it carries Wave 1's `has_count`.) In `lua/whisk/context/Context.lua`, inside `Context:restore_view`, replace:

  ```lua
    local clamped_line, clamped_col = self:clamp_position(line, col)
    local clamped_topline = self:clamp_line(topline)

    vim.api.nvim_win_call(self.winid, function()
      vim.fn.winrestview({
        topline = clamped_topline,
        lnum = clamped_line,
        col = clamped_col,
        leftcol = 0,
      })
    end)
    return true
  ```

  with:

  ```lua
    local clamped_line, clamped_col = self:clamp_position(line, col)
    local clamped_topline = self:clamp_line(topline)
    local leftcol = self.viewport and self.viewport.leftcol or 0

    vim.api.nvim_win_call(self.winid, function()
      vim.fn.winrestview({
        topline = clamped_topline,
        lnum = clamped_line,
        col = clamped_col,
        leftcol = leftcol,
      })
    end)
    return true
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (mock `winrestview` only records; real horizontal-scroll preservation needs a `nowrap` window). Write this to `/tmp/whisk_probe_leftcol.lua`:

  ```lua
  local ok, err = pcall(function()
    local builder = require("whisk.context.builder")
    local long = string.rep("abcdefghij", 30)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { long, "short" })
    vim.wo.wrap = false
    vim.api.nvim_win_set_cursor(0, { 1, 50 })
    vim.fn.winrestview({ leftcol = 15 })

    local ctx = builder.build({ count = 1 })
    print("captured_leftcol=" .. ctx.viewport.leftcol)

    ctx:restore_view(1, 1, 50)
    print("restored_leftcol=" .. vim.fn.winsaveview().leftcol)
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_leftcol.lua" 2>&1
  ```
  Expected output (cursor col 50 stays visible with leftcol 15, so Neovim does not readjust it; before the fix `restored_leftcol` was 0):
  ```
  captured_leftcol=15
  restored_leftcol=15
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/context/builder.lua lua/whisk/context/Context.lua tests/mocks/vim_fn.lua tests/mocks/init.lua tests/unit/context/builder_spec.lua tests/unit/context/Context_spec.lua
  git commit -m "fix(context): preserve horizontal scroll during animated view restore"
  ```

---

### Task 11: Performance mode saves/restores `'syntax'` per buffer (#3)

`performance.enable()` stores `vim.bo.syntax` of whatever buffer is current at enable time and `disable()` writes it to whatever buffer is current at disable time. With `auto_enable_on_large_files` (a DEFAULT), entering a 6000-line python file then a lua file restores `syntax='python'` ONTO THE LUA BUFFER and leaves the python buffer permanently `'off'` — both buffers corrupted under pure default config. Key the saved syntax by bufnr, write `"off"`/restores through `vim.bo[bufnr].syntax`, restore ONLY to buffers that performance mode modified, and guard buffer validity on restore.

**Files:**
- Modify: `lua/whisk/performance.lua` (the `performance_state` table, `M.enable`, `M.disable` only — `setup`/`teardown`/`record_frame_time` carry Wave 1 changes and stay untouched)
- Modify: `tests/mocks/vim_core.lua` (per-buffer `vim.bo`), `tests/mocks/vim_api.lua` (switchable current buffer), `tests/mocks/init.lua`
- Test: `tests/unit/performance_spec.lua` (add)

**Interfaces:**
- Produces: `performance_state.saved_syntax` — table keyed by bufnr, replacing `original_syntax`. `M.enable()`/`M.disable()` signatures unchanged.
- Consumes: `vim.api.nvim_get_current_buf()`, `vim.bo[bufnr].syntax` (read/write), `vim.api.nvim_buf_is_valid(bufnr)`.
- Mock contract: `_G.vim.bo` becomes a metatable proxy — `vim.bo.syntax` targets the current buffer, `vim.bo[bufnr].syntax` targets that buffer; per-buffer tables default to `{ syntax = "lua", filetype = "lua" }`; `vim_core.reset()` clears the store. `vim_api` gains `state.current_buf` (default 1), `nvim_get_current_buf` returns it, `mocks.set_current_buf(bufnr)` sets it.

**Steps:**

- [ ] Extend the mocks. In `tests/mocks/vim_api.lua`, add `current_buf = 1,` to the `local state = { ... }` table AND to the reassignment inside `function M.reset()` (after `cursor = { 1, 0 },` in each). Change `nvim_get_current_buf` in `M.create()` to:

  ```lua
      nvim_get_current_buf = function()
        return state.current_buf
      end,
  ```

  and add a setter after `function M.set_window_buffer(winid, bufnr) ... end`:

  ```lua
  function M.set_current_buf(bufnr)
    state.current_buf = bufnr
  end
  ```

  In `tests/mocks/vim_core.lua`, replace:

  ```lua
  M.buffer_options = {
    syntax = "lua",
    filetype = "lua",
  }
  ```

  with:

  ```lua
  local buffer_option_store = {}

  local function get_current_bufnr()
    return require('tests.mocks.vim_api').get_state().current_buf
  end

  local function buffer_options_for(bufnr)
    if not buffer_option_store[bufnr] then
      buffer_option_store[bufnr] = { syntax = "lua", filetype = "lua" }
    end
    return buffer_option_store[bufnr]
  end

  M.buffer_options = setmetatable({}, {
    __index = function(_, key)
      if type(key) == 'number' then
        return buffer_options_for(key)
      end
      return buffer_options_for(get_current_bufnr())[key]
    end,
    __newindex = function(_, key, value)
      buffer_options_for(get_current_bufnr())[key] = value
    end,
  })
  ```

  and add at the END of `function M.reset()` (after the `window_options` resets from Task 8):

  ```lua
    for bufnr in pairs(buffer_option_store) do
      buffer_option_store[bufnr] = nil
    end
  ```

  In `tests/mocks/init.lua`, add after `function M.set_window_buffer(winid, bufnr) ... end`:

  ```lua
  function M.set_current_buf(bufnr)
    vim_api.set_current_buf(bufnr)
  end
  ```

- [ ] Write failing tests. In `tests/unit/performance_spec.lua`, add inside the `describe` block:

  ```lua
  it('enable disables syntax on the current buffer (#3)', function()
    local config = require('whisk.config')
    config.update({ performance = { disable_syntax_during_scroll = true } })
    _G.vim.bo[1].syntax = "python"

    performance.enable()

    assert.equals(_G.vim.bo[1].syntax, "off")
  end)

  it('disable restores syntax to the buffer it was saved from (#3)', function()
    local config = require('whisk.config')
    config.update({ performance = { disable_syntax_during_scroll = true } })
    _G.vim.bo[1].syntax = "python"

    mocks.set_current_buf(1)
    performance.enable()
    mocks.set_current_buf(2)
    performance.disable()

    assert.equals(_G.vim.bo[1].syntax, "python")
    assert.equals(_G.vim.bo[2].syntax, "lua")
  end)

  it('disable skips buffers that no longer exist (#3)', function()
    local config = require('whisk.config')
    config.update({ performance = { disable_syntax_during_scroll = true } })

    mocks.set_current_buf(1)
    performance.enable()
    mocks.delete_buffer(1)
    mocks.set_current_buf(2)

    assert.does_not_throw(function()
      performance.disable()
    end)
    assert.equals(_G.vim.bo[2].syntax, "lua")
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `performance > disable restores syntax to the buffer it was saved from (#3)` (current code writes `"python"` onto buffer 2 — the current buffer — so `_G.vim.bo[2].syntax` is `"python"`, expected `"lua"`; buffer 1 stays `"off"`, expected `"python"`).

- [ ] Implement. In `lua/whisk/performance.lua`, replace the state table (dropping its inline comment — touched blocks lose their comments per repo convention):

  ```lua
  local performance_state = {
    is_active = false,
    original_syntax = nil,
    ignored_events = {},
    event_listeners = {},
  }
  ```

  with:

  ```lua
  local performance_state = {
    is_active = false,
    saved_syntax = {},
    ignored_events = {},
    event_listeners = {},
  }
  ```

  Replace the body of `M.enable` with:

  ```lua
  function M.enable()
    if performance_state.is_active then
      return
    end

    local perf_config = config.get_performance()

    if perf_config.disable_syntax_during_scroll then
      local bufnr = vim.api.nvim_get_current_buf()
      if performance_state.saved_syntax[bufnr] == nil then
        performance_state.saved_syntax[bufnr] = vim.bo[bufnr].syntax
      end
      vim.bo[bufnr].syntax = "off"
    end

    for _, event in ipairs(perf_config.ignore_events) do
      performance_state.ignored_events[event] = true
    end

    performance_state.is_active = true
  end
  ```

  Replace the body of `M.disable` with:

  ```lua
  function M.disable()
    if not performance_state.is_active then
      return
    end

    for bufnr, syntax in pairs(performance_state.saved_syntax) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.bo[bufnr].syntax = syntax
      end
    end
    performance_state.saved_syntax = {}

    performance_state.ignored_events = {}

    performance_state.is_active = false
  end
  ```

  Do not modify `setup`, `teardown`, `auto_toggle`, or the monitoring section (Wave 1 owns those diffs).

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (real buffer-local `'syntax'` across a buffer switch cannot be exercised by the mock `vim.bo`). This reproduces finding #3's verified default-config corruption. Write this to `/tmp/whisk_probe_syntax.lua`:

  ```lua
  local ok, err = pcall(function()
    local config = require("whisk.config")
    local performance = require("whisk.performance")
    config.update({ performance = {
      auto_enable_on_large_files = true,
      large_file_threshold = 5,
      disable_syntax_during_scroll = true,
      enabled = false,
    } })

    local big = vim.api.nvim_get_current_buf()
    local lines = {}
    for i = 1, 10 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(big, 0, -1, false, lines)
    vim.bo[big].syntax = "python"

    performance.auto_toggle()
    print("big_during=" .. vim.bo[big].syntax)

    local small = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(small, 0, -1, false, { "tiny" })
    vim.bo[small].syntax = "lua"
    vim.api.nvim_set_current_buf(small)

    performance.auto_toggle()
    print("big_after=" .. vim.bo[big].syntax)
    print("small_after=" .. vim.bo[small].syntax)
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_syntax.lua" 2>&1
  ```
  Expected output (before the fix the verified output was `big_after=off`, `small_after=python` — both buffers corrupted):
  ```
  big_during=off
  big_after=python
  small_after=lua
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/performance.lua tests/mocks/vim_core.lua tests/mocks/vim_api.lua tests/mocks/init.lua tests/unit/performance_spec.lua
  git commit -m "fix(performance): save and restore syntax per buffer"
  ```

---

### Task 12: `BufLeave` completes animations at their target instead of dropping them (V3)

`lifecycle.lua`'s `BufLeave` autocmd calls `loop.cancel_for_buffer`, which discards the animation without applying the final frame — switching buffers mid-animation strands the old buffer's cursor at an arbitrary interpolated position. The engine already chose "complete, don't discard" for domination (commit 2236f0f); extend that to `BufLeave`: add `loop.complete_for_buffer(bufnr)` which applies the final frame + `on_complete` for animations whose context is still valid (during `BufLeave` the window still shows the buffer, so the final position is applicable) and falls back to `on_cancel` semantics for invalid contexts. `BufDelete` and `WinClosed` keep their drop (cancel) semantics — a deleted buffer or closed window has nothing to complete into.

**Files:**
- Modify: `lua/whisk/engine/loop.lua`, `lua/whisk/engine/lifecycle.lua`
- Test: `tests/unit/engine/loop_spec.lua`, `tests/unit/engine/lifecycle_spec.lua` (add)

**Interfaces:**
- Produces: `loop.complete_for_buffer(bufnr)` — for each queued animation with `context.bufnr == bufnr`: if `context:is_valid()` (or no `is_valid` method), apply the final eased frame through its traits and call `on_complete`; otherwise call `on_cancel('buffer_invalidated')`. Always removes the animation, releases it to the pool, and detaches the key listener when the queue empties.
- Consumes: `interpolate_result`, `traits.apply_frame`, `detach_key_listener` (Task 6), the orchestrator's `on_complete` (which applies curswant — Task 3).
- `lifecycle.setup()`: the `BufLeave` callback switches from `cancel_for_buffer` to `complete_for_buffer`; `BufDelete`/`WinClosed` callbacks unchanged.

**Steps:**

- [ ] Write failing tests. In `tests/unit/engine/loop_spec.lua`, add inside the `describe` block:

  ```lua
  it('complete_for_buffer applies the final frame for matching animations (V3)', function()
    local traits = require('whisk.registry.traits')
    traits.register({
      id = 'cursor',
      apply = function(context, result, progress)
        if result.cursor then
          mocks.set_cursor(result.cursor.line, result.cursor.col)
        end
      end,
    })

    local completed = false
    loop.start({
      duration = 150,
      easing = 'linear',
      context = { bufnr = 1, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
      on_complete = function() completed = true end,
    })

    loop.complete_for_buffer(1)

    assert.is_true(completed)
    assert.equals(loop.get_active_count(), 0)
    assert.is_false(loop.is_running())
    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 5)
  end)

  it('complete_for_buffer leaves other buffers animating (V3)', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      context = { bufnr = 1, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })
    loop.start({
      duration = 100,
      easing = 'linear',
      context = { bufnr = 2, winid = 1001, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.complete_for_buffer(1)

    assert.equals(loop.get_active_count(), 1)
    assert.is_true(loop.is_running())
  end)

  it('complete_for_buffer cancels instead when the context is invalid (V3)', function()
    local completed = false
    local cancel_reason = nil
    loop.start({
      duration = 150,
      easing = 'linear',
      context = {
        bufnr = 1,
        winid = 1000,
        cursor = { line = 1, col = 0 },
        is_valid = function() return false, 'buffer_deleted' end,
      },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
      on_complete = function() completed = true end,
      on_cancel = function(reason) cancel_reason = reason end,
    })

    loop.complete_for_buffer(1)

    assert.is_false(completed)
    assert.equals(cancel_reason, 'buffer_invalidated')
    assert.equals(loop.get_active_count(), 0)
  end)
  ```

  In `tests/unit/engine/lifecycle_spec.lua`, add inside the `describe` block:

  ```lua
  it('BufLeave completes animations for the buffer instead of dropping them (V3)', function()
    local loop = require('whisk.engine.loop')
    local traits = require('whisk.registry.traits')
    traits.register({
      id = 'cursor',
      apply = function(context, result, progress)
        if result.cursor then
          mocks.set_cursor(result.cursor.line, result.cursor.col)
        end
      end,
    })

    lifecycle.setup()

    loop.start({
      duration = 150,
      easing = 'linear',
      context = { bufnr = 7, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 9, col = 0 } },
      traits = { 'cursor' },
    })

    local bufleave_callback = nil
    for _, autocmd in ipairs(mocks.get_api_state().autocmds) do
      if autocmd.events == 'BufLeave' then
        bufleave_callback = autocmd.opts.callback
      end
    end
    assert.is_not_nil(bufleave_callback)

    bufleave_callback({ buf = 7 })

    assert.equals(loop.get_active_count(), 0)
    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 9)
  end)

  it('BufDelete still cancels without applying the final frame (V3)', function()
    local loop = require('whisk.engine.loop')
    lifecycle.setup()

    local cancelled = false
    loop.start({
      duration = 150,
      easing = 'linear',
      context = { bufnr = 7, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 9, col = 0 } },
      traits = {},
      on_cancel = function() cancelled = true end,
    })

    local bufdelete_callback = nil
    for _, autocmd in ipairs(mocks.get_api_state().autocmds) do
      if autocmd.events == 'BufDelete' then
        bufdelete_callback = autocmd.opts.callback
      end
    end
    assert.is_not_nil(bufdelete_callback)

    bufdelete_callback({ buf = 7 })

    assert.equals(loop.get_active_count(), 0)
    assert.is_true(cancelled)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `engine/loop > complete_for_buffer applies the final frame for matching animations (V3)` (`attempt to call field 'complete_for_buffer' (a nil value)`) and `engine/lifecycle > BufLeave completes animations for the buffer instead of dropping them (V3)` (cursor stays at line 1 — cancel drops the frame).

- [ ] Implement. In `lua/whisk/engine/loop.lua`, add after `M.complete_all`:

  ```lua
  function M.complete_for_buffer(bufnr)
    for i = #frame_queue, 1, -1 do
      local anim = frame_queue[i]
      if anim.context.bufnr == bufnr then
        local valid = true
        if anim.context.is_valid then
          valid = anim.context:is_valid()
        end
        if valid then
          local eased_final = anim.easing_fn(1.0)
          local final = interpolate_result(anim.context, anim.result, eased_final)
          for _, trait_id in ipairs(anim.traits) do
            traits.apply_frame(trait_id, anim.context, final, eased_final)
          end
          if anim.on_complete then
            anim.on_complete()
          end
        elseif anim.on_cancel then
          anim.on_cancel('buffer_invalidated')
        end
        table.remove(frame_queue, i)
        pool.release(anim)
      end
    end

    if #frame_queue == 0 then
      is_running = false
      detach_key_listener()
    end
  end
  ```

  In `lua/whisk/engine/lifecycle.lua`, replace the `BufLeave` autocmd registration:

  ```lua
    vim.api.nvim_create_autocmd('BufLeave', {
      group = autocmd_group,
      callback = function(args)
        loop.cancel_for_buffer(args.buf)
      end,
    })
  ```

  with:

  ```lua
    vim.api.nvim_create_autocmd('BufLeave', {
      group = autocmd_group,
      callback = function(args)
        loop.complete_for_buffer(args.buf)
      end,
    })
  ```

  (`BufDelete` and `WinClosed` registrations stay on `cancel_for_buffer`/`cancel_for_window`.)

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (real `BufLeave` firing and per-window cursor memory cannot be exercised under the mock autocmds). This reproduces V3's failure scenario: `G` in a long file, buffer switch within the animation window, return. Write this to `/tmp/whisk_probe_bufleave.lua`:

  ```lua
  local ok, err = pcall(function()
    require("whisk").setup()
    local first = vim.api.nvim_get_current_buf()
    local lines = {}
    for i = 1, 500 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(first, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local second = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(second, 0, -1, false, { "other" })

    vim.api.nvim_feedkeys("G", "mx", false)
    vim.api.nvim_set_current_buf(second)
    vim.api.nvim_set_current_buf(first)

    print("line_after_return=" .. vim.api.nvim_win_get_cursor(0)[1])
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_bufleave.lua" 2>&1
  ```
  Expected output (the buffer switch happens before any deferred frame runs, so without the fix the cursor is stranded at line 1 — the animation origin; with the fix `BufLeave` completes the `G` to the end of file before the switch):
  ```
  line_after_return=500
  ```
  Delete the probe file. Do NOT commit it.

- [ ] Commit:
  ```
  git add lua/whisk/engine/loop.lua lua/whisk/engine/lifecycle.lua tests/unit/engine/loop_spec.lua tests/unit/engine/lifecycle_spec.lua
  git commit -m "fix(engine): complete animations at target on BufLeave instead of dropping"
  ```
