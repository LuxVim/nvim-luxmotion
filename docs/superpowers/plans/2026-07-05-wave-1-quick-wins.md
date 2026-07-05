# Wave 1: Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the patch-release "quick wins" for whisk.nvim — trivial-to-small correctness fixes with no open design questions — closing GitHub issue #14 (`%` jumps to line 1) and every stale-state / autocmd / config leak.

**Architecture:** whisk.nvim is a Neovim motion-animation plugin: keymap handlers (`registry/keymaps.lua`) capture input and call `engine/orchestrator.execute`, which builds a `Context` (`context/builder.lua`), runs a per-motion `calculator` (`calculators/*.lua`), and drives an animation `loop` that applies `traits`. This wave introduces one cross-wave contract — an explicit-count signal (`has_count`) threaded from the keymap handler through the context into the calculators — and uses it to fix the `%` and `G` count-semantics bugs. The remaining tasks are self-contained fixes to the orchestrator cancel path, the fallback key-execution mechanism, the performance module's autocmd lifecycle and FPS metric, the setup/config reset path, and the README install recipe.

**Tech Stack:** Lua 5.1+ (Neovim runtime), plain-Lua unit test harness (`tests/`), headless Neovim probes for behavior the mocks cannot exercise.

**Findings covered:**
- **#1** — `%` with no count runs `1%` (jumps to 1% of file = line 1) instead of the matching bracket; root cause of open issue #14. (Tasks 1, 2)
- **V2** — `line.G` reads `vim.v.count` directly instead of `context.input`, breaking `orchestrator.execute("line_G", { count = N })`. (Tasks 1, 3)
- **#6** — `gg`/`G` always jump to first non-blank, ignoring `'startofline'` (Neovim default keeps the column). (Task 3)
- **#13** — trait `animating` flag leaks on every cancellation path; orchestrator never passes `on_cancel`. (Task 4)
- **#8** — fallback builds `normal! <C-d>` from literal key strings, so scroll motions silently no-op when the category is disabled. (Task 5)
- **#7** — performance module leaks an ungrouped `BufEnter`/`BufWinEnter` autocmd on every `setup()`. (Task 6)
- **#34** — FPS metric counts idle gaps as a frame, collapsing `get_current_fps()` after any pause. (Task 7)
- **#25** — `setup()` re-invocation accumulates stale config because `reset()` never resets config. (Task 8)
- **#28** — README lazy.nvim recipe triggers a double `setup()` and leaks a performance autocmd. (Task 9)

## Execution Model

- Branch: `audit/wave-1-quick-wins`, created from `main` (Wave 1 branches from current `main`).
- Executor: one Sonnet 5 subagent (high effort) per task, fresh context per task, given only that task's text plus this plan's header and Global Constraints.
- Task review: an Opus 4.8 subagent (xhigh effort) reviews each completed task's diff against the task spec before the next task starts. Review verdict gates progression.
- Wave review: one Fable agent reviews the wave's full branch diff (`git diff main...HEAD`) against this plan plus the findings file before the PR is opened.
- PR: opened to `main` when all tasks complete, `bash scripts/run_tests.sh` passes, and the Fable wave review passes. The PR description MUST contain the line `Fixes #14`.

## Global Constraints

- Neovim >= 0.8 API compatibility only (no `vim.uv`, no `nvim_exec2`, no APIs newer than 0.8 unless feature-detected). `vim.o.startofline`, `vim.api.nvim_replace_termcodes`, `vim.api.nvim_feedkeys`, `vim.api.nvim_create_augroup`, and `vim.api.nvim_del_augroup_by_id` are all 0.8-safe.
- No inline comments in code. LuaCATS/JSDoc-style annotation comments are permitted only where a task explicitly calls for them (none do in this wave).
- Commit style: conventional commits with scope, matching repo history (`fix(engine): ...`, `feat(context): ...`, `test: ...`, `docs: ...`, `chore: ...`). NO AI attribution of any kind — no "Generated with", no "Co-Authored-By: Claude".
- Every task ends with `bash scripts/run_tests.sh` passing (baseline is 441 tests, zero failures; this wave adds tests) before its commit.
- Do not modify files outside this wave's scope. Do not touch `lua/luxmotion/` or `plugin/luxmotion.vim` (deprecation shims).
- Headless probes are additional verification for behavior the mock harness cannot exercise (mock `vim.cmd`/`nvim_feedkeys` are no-ops). Probe files are written to `/tmp/` and are NOT committed. Run each probe with combined output capture (`2>&1`) since headless `print()` may route to stderr.

---

### Task 1: Explicit-count input contract — `has_count` (#1, V2)

Introduces the pinned cross-wave contract used by Tasks 2 and 3 and by later waves. The keymap handler captures whether the user typed an explicit count; the context builder threads it to calculators.

**Files:**
- Modify: `lua/whisk/registry/keymaps.lua`
- Modify: `lua/whisk/context/builder.lua`
- Test: `tests/unit/registry/keymaps_spec.lua` (add tests)
- Test: `tests/unit/context/builder_spec.lua` (add tests)

**Interfaces:**
- Produces (pinned contract 1 — later waves import these exact shapes):
  - `keymaps.create_handler(motion)` → the input table passed to `orchestrator.execute` now includes `has_count = vim.v.count > 0` (note: `vim.v.count`, NOT `vim.v.count1`), in BOTH the `char` and non-`char` branches. Existing fields unchanged: `{ char?, count = vim.v.count1, direction = motion.keys[1] }`.
  - `context.builder.build(input)` → `ctx.input.has_count = input.has_count or false` (default `false`). Existing fields unchanged: `ctx.input = { char, count = input.count or 1, direction }`.
- Consumes: nothing new.

**Steps:**

- [ ] Write failing tests in `tests/unit/registry/keymaps_spec.lua`. Add these two `it(...)` blocks inside the `describe('registry/keymaps', ...)` block (e.g. after the existing `'created handler is callable'` test):

  ```lua
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
  ```

- [ ] Write failing tests in `tests/unit/context/builder_spec.lua`. Add these two `it(...)` blocks inside the `describe('context/builder', ...)` block (e.g. after `'build defaults count to 1'`):

  ```lua
  it('build defaults has_count to false', function()
    local ctx = builder.build({})
    assert.is_false(ctx.input.has_count)
  end)

  it('build copies has_count from input', function()
    local ctx = builder.build({ has_count = true })
    assert.is_true(ctx.input.has_count)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` line shows a nonzero count; failures include `registry/keymaps > create_handler sets has_count true when an explicit count was typed` (captured.has_count is nil, not true) and `context/builder > build copies has_count from input` (ctx.input.has_count is nil, not true).

- [ ] Implement the keymaps change. In `lua/whisk/registry/keymaps.lua`, replace the whole `M.create_handler` function with:

  ```lua
  function M.create_handler(motion)
    if motion.input == "char" then
      return function()
        local char = vim.fn.getcharstr()
        orchestrator.execute(motion.id, {
          char = char,
          count = vim.v.count1,
          direction = motion.keys[1],
          has_count = vim.v.count > 0,
        })
      end
    else
      return function()
        orchestrator.execute(motion.id, {
          count = vim.v.count1,
          direction = motion.keys[1],
          has_count = vim.v.count > 0,
        })
      end
    end
  end
  ```

- [ ] Implement the builder change. In `lua/whisk/context/builder.lua`, replace the `ctx.input = { ... }` assignment with:

  ```lua
    ctx.input = {
      char = input.char,
      count = input.count or 1,
      direction = input.direction,
      has_count = input.has_count or false,
    }
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Commit:
  ```
  git add lua/whisk/registry/keymaps.lua lua/whisk/context/builder.lua tests/unit/registry/keymaps_spec.lua tests/unit/context/builder_spec.lua
  git commit -m "feat(context): thread explicit-count signal via input.has_count"
  ```

---

### Task 2: `%` goes to the matching bracket, not 1% of the file (#1, Fixes #14)

`calculators/text_object.lua` has its own local native-delegation helper `calculate_via_native` that unconditionally prefixes `context.input.count` (always >= 1 from `vim.v.count1`). For `{ } ( )` a leading `1` is harmless (`1}` == `}`), but for `%` it changes semantics: `%` = go to matching bracket, `{n}%` = go to n% of the file. So a bare `%` runs as `1%` → line 1. Fix: the helper's caller builds the full command string; the `%` calculator runs bare `%` unless an explicit count was typed.

**Files:**
- Modify: `lua/whisk/calculators/text_object.lua`
- Test: `tests/unit/calculators/text_object_spec.lua` (add tests)

**Interfaces:**
- Consumes: `context.input.has_count` (from Task 1), `context.input.count`.
- Produces: `calculate_via_native(cmd, context)` — the local helper's signature changes so the CALLER builds the full command string (count prefix + motion char); the helper runs `normal! <cmd>` verbatim. (Superseded in Wave 2 by the shared `calculators/native.lua`; documented here as a visible seam.) Calculator return shape is unchanged: `{ cursor = { line, col } }`.

**Steps:**

- [ ] Write failing tests in `tests/unit/calculators/text_object_spec.lua`. Add these three `it(...)` blocks inside the `describe('calculators/text_object', ...)` block (e.g. after `'% handles no matching bracket gracefully'`):

  ```lua
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
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failure includes `calculators/text_object > % with no explicit count runs a bare % (issue #14)` — the current code records `normal! 1%`, so `assert.contains(commands, 'normal! %')` errors with "Table does not contain: normal! %".

- [ ] Implement the fix. Replace the entire contents of `lua/whisk/calculators/text_object.lua` with:

  ```lua
  local M = {}

  local function calculate_via_native(cmd, context)
    local original = { context.cursor.line, context.cursor.col }
    vim.api.nvim_win_set_cursor(0, original)

    local success = pcall(vim.cmd, "normal! " .. cmd)

    if not success then
      vim.api.nvim_win_set_cursor(0, original)
      return {
        cursor = { line = context.cursor.line, col = context.cursor.col },
      }
    end

    local target = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_win_set_cursor(0, original)

    return {
      cursor = { line = target[1], col = target[2] },
    }
  end

  M["{"] = function(context)
    return calculate_via_native(context.input.count .. "{", context)
  end

  M["}"] = function(context)
    return calculate_via_native(context.input.count .. "}", context)
  end

  M["("] = function(context)
    return calculate_via_native(context.input.count .. "(", context)
  end

  M[")"] = function(context)
    return calculate_via_native(context.input.count .. ")", context)
  end

  M["%"] = function(context)
    local cmd = "%"
    if context.input.has_count then
      cmd = context.input.count .. "%"
    end
    return calculate_via_native(cmd, context)
  end

  return M
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (the mock `vim.cmd` is a no-op, so the real bracket-jump cannot be exercised under the unit harness). Write this to `/tmp/whisk_probe_pct.lua`:

  ```lua
  local ok, err = pcall(function()
    local text_object = require("whisk.calculators.text_object")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo(", "bar", "baz", ")end" })

    local ctx_bare = { cursor = { line = 1, col = 3 }, input = { count = 1, has_count = false }, buffer = { line_count = 4 } }
    local r1 = text_object["%"](ctx_bare)
    print("bare_line=" .. r1.cursor.line)

    local ctx_count = { cursor = { line = 1, col = 3 }, input = { count = 1, has_count = true }, buffer = { line_count = 4 } }
    local r2 = text_object["%"](ctx_count)
    print("count1_line=" .. r2.cursor.line)
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_pct.lua" 2>&1
  ```
  Expected output contains `bare_line=4` (cursor on `(` at line 1 → matching `)` at line 4) and `count1_line=1` (`1%` of a 4-line file → line 1). This confirms the issue #14 fix end-to-end. Do NOT commit the probe file.

- [ ] Commit:
  ```
  git add lua/whisk/calculators/text_object.lua tests/unit/calculators/text_object_spec.lua
  git commit -m "fix(calculators): run bare % for matching bracket, gate count on explicit count (#14)"
  ```

---

### Task 3: `gg`/`G` respect `'startofline'` and read `context.input` for count (#6, V2)

Two trivial fidelity fixes to the same file, `calculators/line.lua`:
- **#6:** `gg`/`G` always set the target column via `get_first_non_blank`. Neovim's default is `nostartofline`, under which native `gg`/`G` KEEP the current column. Respect `vim.o.startofline`: preserve the current column (clamped to the target line) when off; first non-blank when on.
- **V2:** `M.G` branches on `vim.v.count == 0`, coupling a pure calculator to global editor state and breaking `orchestrator.execute("line_G", { count = N })` (where `vim.v.count` is 0/stale). Branch on `context.input.has_count` / `context.input.count` instead, preserving `{count}G` → line N and bare `G` → last line.

**Files:**
- Modify: `lua/whisk/calculators/line.lua`
- Test: `tests/unit/calculators/line_spec.lua` (add `startofline` reset to `before_each`; add tests; update existing `G` tests to use `has_count`)

**Interfaces:**
- Consumes: `context.input.has_count`, `context.input.count`, `context.cursor.col`, `vim.o.startofline`.
- Produces: `M.gg(context)` and `M.G(context)` unchanged return shape: `{ cursor = { line, col }, viewport = { topline } }`.

**Steps:**

- [ ] Add `startofline` to the mock options so tests can toggle it deterministically. In `tests/mocks/vim_core.lua`, change the `M.options` table from:

  ```lua
  M.options = {
    scrolloff = 5,
  }
  ```
  to:
  ```lua
  M.options = {
    scrolloff = 5,
    startofline = false,
  }
  ```

- [ ] Pin `startofline` per-test for isolation. In `tests/unit/calculators/line_spec.lua`, add this line at the END of the `before_each(function() ... end)` block (right after `line = require('whisk.calculators.line')`):

  ```lua
    _G.vim.o.startofline = false
  ```
  Note: this mutates the shared options table IN PLACE each test (correct — `mocks.setup()` binds `_G.vim.o = vim_core.options` before `reset()` runs, so an in-place write is safe; do NOT reassign `M.options` or `_G.vim.o` to a fresh table). Add an `after_each` to the same `describe` block to prevent a `startofline = true` leak into specs that run after this one:

  ```lua
    after_each(function()
      _G.vim.o.startofline = false
    end)
  ```

- [ ] Update the existing `G` tests to use the `has_count` contract instead of `vim.v.count`. In `tests/unit/calculators/line_spec.lua`, replace these existing `it(...)` blocks with the versions below (drop the now-inert `_G.vim.v.count = ...` lines; add `has_count`):

  Replace `'G without explicit count goes to last line'`:
  ```lua
  it('G without explicit count goes to last line', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 10 },
    }
    local result = line.G(ctx)
    assert.equals(result.cursor.line, 10)
  end)
  ```

  Replace `'G with count goes to specified line'`:
  ```lua
  it('G with count goes to specified line', function()
    local ctx = {
      cursor = { line = 10, col = 0 },
      input = { count = 3, has_count = true },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 10 },
    }
    local result = line.G(ctx)
    assert.equals(result.cursor.line, 3)
  end)
  ```

  Replace `'G clamps to last line'`:
  ```lua
  it('G clamps to last line', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 500, has_count = true },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 10 },
    }
    local result = line.G(ctx)
    assert.equals(result.cursor.line, 10)
  end)
  ```

  Replace `'G returns viewport adjustment'`:
  ```lua
  it('G returns viewport adjustment', function()
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 100 },
    }
    local result = line.G(ctx)
    assert.is_not_nil(result.viewport)
  end)
  ```

  Replace `'gg and G preserve column appropriately'`:
  ```lua
  it('gg and G preserve column appropriately', function()
    local ctx = {
      cursor = { line = 5, col = 10 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 10 },
    }

    local gg_result = line.gg(ctx)
    assert.is_type(gg_result.cursor.col, 'number')

    local g_result = line.G(ctx)
    assert.is_type(g_result.cursor.col, 'number')
  end)
  ```

- [ ] Add new `startofline` and V2 tests. In `tests/unit/calculators/line_spec.lua`, add these `it(...)` blocks inside the `describe` block (e.g. before the final `'gg and G preserve column appropriately'` test):

  ```lua
  it('gg preserves the current column when startofline is off (nvim default)', function()
    _G.vim.o.startofline = false
    mocks.set_buffer_content({ "aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc" })
    local ctx = {
      cursor = { line = 3, col = 5 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 3 },
    }
    local result = line.gg(ctx)
    assert.equals(result.cursor.line, 1)
    assert.equals(result.cursor.col, 5)
  end)

  it('gg uses first non-blank column when startofline is on', function()
    _G.vim.o.startofline = true
    mocks.set_buffer_content({ "    indented", "second line", "third line" })
    local ctx = {
      cursor = { line = 3, col = 8 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 3 },
    }
    local result = line.gg(ctx)
    assert.equals(result.cursor.col, 4)
  end)

  it('G preserves the current column when startofline is off', function()
    _G.vim.o.startofline = false
    mocks.set_buffer_content({ "aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc" })
    local ctx = {
      cursor = { line = 1, col = 4 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 3 },
    }
    local result = line.G(ctx)
    assert.equals(result.cursor.line, 3)
    assert.equals(result.cursor.col, 4)
  end)

  it('G clamps a preserved column to a shorter target line when startofline is off', function()
    _G.vim.o.startofline = false
    mocks.set_buffer_content({ "long line here", "abc" })
    local ctx = {
      cursor = { line = 1, col = 10 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 2 },
    }
    local result = line.G(ctx)
    assert.equals(result.cursor.line, 2)
    assert.equals(result.cursor.col, 2)
  end)

  it('G uses first non-blank column when startofline is on', function()
    _G.vim.o.startofline = true
    mocks.set_buffer_content({ "line one", "  indented last" })
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 1, has_count = false },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 2 },
    }
    local result = line.G(ctx)
    assert.equals(result.cursor.line, 2)
    assert.equals(result.cursor.col, 2)
  end)

  it('G honors has_count from context input, not vim.v.count (V2)', function()
    _G.vim.v.count = 0
    local ctx = {
      cursor = { line = 1, col = 0 },
      input = { count = 5, has_count = true },
      viewport = { height = 40, topline = 1 },
      buffer = { line_count = 10 },
    }
    local result = line.G(ctx)
    assert.equals(result.cursor.line, 5)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `calculators/line > gg preserves the current column when startofline is off (nvim default)` (current code returns col 0 from first-non-blank, expected 5) and `calculators/line > G honors has_count from context input, not vim.v.count (V2)` (current code reads `vim.v.count == 0` → last line 10, expected 5).

- [ ] Implement the fix. Replace the entire contents of `lua/whisk/calculators/line.lua` with:

  ```lua
  local M = {}

  local function get_first_non_blank(line_num)
    local line_content = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1] or ""
    local leading_space = line_content:match("^%s*")
    return leading_space and #leading_space or 0
  end

  local function get_target_col(context, target_line)
    if vim.o.startofline then
      return get_first_non_blank(target_line)
    end
    local line_content = vim.api.nvim_buf_get_lines(0, target_line - 1, target_line, false)[1] or ""
    local max_col = math.max(#line_content - 1, 0)
    return math.max(0, math.min(context.cursor.col, max_col))
  end

  local function calculate_topline(target_line, context)
    local win_height = context.viewport.height
    local topline = target_line - math.floor(win_height / 2)
    return math.max(1, math.min(topline, context.buffer.line_count - win_height + 1))
  end

  function M.gg(context)
    local target_line = context.input.count
    target_line = math.max(1, math.min(target_line, context.buffer.line_count))
    local target_col = get_target_col(context, target_line)

    return {
      cursor = { line = target_line, col = target_col },
      viewport = { topline = calculate_topline(target_line, context) },
    }
  end

  function M.G(context)
    local target_line
    if not context.input.has_count then
      target_line = context.buffer.line_count
    else
      target_line = math.max(1, math.min(context.input.count, context.buffer.line_count))
    end
    local target_col = get_target_col(context, target_line)

    return {
      cursor = { line = target_line, col = target_col },
      viewport = { topline = calculate_topline(target_line, context) },
    }
  end

  M["|"] = function(context)
    local target_col = math.max(context.input.count - 1, 0)
    return {
      cursor = { line = context.cursor.line, col = target_col },
    }
  end

  return M
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Commit:
  ```
  git add lua/whisk/calculators/line.lua tests/unit/calculators/line_spec.lua tests/mocks/vim_core.lua
  git commit -m "fix(calculators): gg/G respect startofline and read context.input count"
  ```

---

### Task 4: Clear the `animating` trait flag on cancellation (#13)

`orchestrator.execute` sets `traits.set_animating(trait_id, true)` and passes only an `on_complete` callback to `loop.start`. The flag is cleared ONLY on normal completion; every cancel path (`process_frame` context-invalid, `cancel_for_buffer`, `cancel_for_window`) calls a nil `on_cancel`, leaving the flag stuck true. This becomes user-visible when a concurrent different-trait animation is running (a stale flag triggers a spurious `complete_all()` that snaps the other animation early). Fix: route both `on_complete` and `on_cancel` through one shared cleanup.

**Files:**
- Modify: `lua/whisk/engine/orchestrator.lua`
- Test: `tests/unit/engine/orchestrator_spec.lua` (add tests)

**Interfaces:**
- Consumes: `loop.start{ ..., on_cancel }` (already supported by `loop.lua`; `anim.on_cancel` is invoked on every cancel path).
- Produces: no signature change to `M.execute`; the `loop.start` options table now includes `on_cancel`.

**Steps:**

- [ ] Write failing tests in `tests/unit/engine/orchestrator_spec.lua`. Add these two `it(...)` blocks inside the `describe('engine/orchestrator', ...)` block (e.g. after `'execute marks traits as animating'`):

  ```lua
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
  ```
  (The mock `Context.new()` uses `nvim_get_current_buf() == 1` and `nvim_get_current_win() == 1000`, so `cancel_for_buffer(1)` / `cancel_for_window(1000)` match the in-flight animation.)

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; both new tests fail with `traits.is_animating('cursor')` still `true` after cancel (current code passes no `on_cancel`, so the flag is never cleared).

- [ ] Implement the fix. In `lua/whisk/engine/orchestrator.lua`, replace the block that starts at `for _, trait_id in ipairs(motion.traits) do` (the `set_animating(..., true)` loop) through the end of the `loop.start({ ... })` call inside `M.execute` with:

  ```lua
    for _, trait_id in ipairs(motion.traits) do
      traits.set_animating(trait_id, true)
    end

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

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Commit:
  ```
  git add lua/whisk/engine/orchestrator.lua tests/unit/engine/orchestrator_spec.lua
  git commit -m "fix(engine): clear animating trait flags on cancellation paths"
  ```

---

### Task 5: Fallback resolves termcodes and feeds keys (#8)

Keymaps install independent of the `enabled` flags, so a disabled category routes to `orchestrator.fallback`, which builds `cmd` and runs `vim.cmd("normal! " .. cmd)`. For scroll motions `input.direction` is the literal string `'<C-d>'`, and `:normal!` treats it as five literal characters — a silent no-op. Fix: resolve keycodes via `nvim_replace_termcodes` and execute via `nvim_feedkeys`. The existing `count > 1` prefix gate is already correct (finding #1 confirms the fallback count path) and is preserved.

**Files:**
- Modify: `lua/whisk/engine/orchestrator.lua`
- Modify: `tests/mocks/vim_api.lua` (add `nvim_replace_termcodes`, `nvim_feedkeys`, `fed_keys` state)
- Test: `tests/unit/engine/orchestrator_spec.lua` (update two existing fallback tests; add one)

**Interfaces:**
- Consumes: `vim.api.nvim_replace_termcodes(cmd, true, false, true)`, `vim.api.nvim_feedkeys(keys, "nx", false)`.
- Produces: `M.fallback(motion, input)` signature unchanged; execution path now feeds resolved keys instead of running `:normal!`.

**Steps:**

- [ ] Extend the mock. In `tests/mocks/vim_api.lua`, add `fed_keys = {},` to the `state` table in BOTH the initial `local state = { ... }` definition and the `function M.reset()` reassignment (place it after `augroup_id = 0,` in each). Then, inside `function M.create()`'s returned table, add these two functions (e.g. right after `nvim_del_augroup_by_id`):

  ```lua
      nvim_replace_termcodes = function(str, from_part, do_lt, special)
        return str
      end,

      nvim_feedkeys = function(keys, mode, escape_ks)
        table.insert(state.fed_keys, { keys = keys, mode = mode })
      end,
  ```

- [ ] Update the two existing fallback tests and add a new one in `tests/unit/engine/orchestrator_spec.lua`.

  Replace `'execute uses fallback when category disabled'`:
  ```lua
  it('execute uses fallback when category disabled', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = false } })

    orchestrator.execute('test_j', { count = 1, direction = 'j' })

    local fed = mocks.get_api_state().fed_keys
    assert.greater_than(#fed, 0)
  end)
  ```

  Replace `'fallback executes normal command'`:
  ```lua
  it('fallback feeds keys via feedkeys', function()
    local motion = motions.get('test_j')
    orchestrator.fallback(motion, { count = 3, direction = 'j' })

    local fed = mocks.get_api_state().fed_keys
    assert.greater_than(#fed, 0)
  end)
  ```

  Add a new test (e.g. after the one above):
  ```lua
  it('fallback resolves control-key termcodes via feedkeys, not vim.cmd', function()
    orchestrator.fallback({ keys = { '<C-d>' } }, { count = 1, direction = '<C-d>' })

    local fed = mocks.get_api_state().fed_keys
    assert.equals(#fed, 1)
    assert.equals(fed[1].keys, '<C-d>')
    assert.equals(fed[1].mode, 'nx')

    local commands = mocks.get_commands()
    assert.equals(#commands, 0)
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `engine/orchestrator > fallback resolves control-key termcodes via feedkeys, not vim.cmd` (current `fallback` runs `vim.cmd`, so `fed_keys` is empty and `commands` is nonempty).

- [ ] Implement the fix. In `lua/whisk/engine/orchestrator.lua`, replace the entire `M.fallback` function with:

  ```lua
  function M.fallback(motion, input)
    local cmd = ""
    if input.count and input.count > 1 then
      cmd = tostring(input.count)
    end
    cmd = cmd .. (input.direction or motion.keys[1])
    if input.char then
      cmd = cmd .. input.char
    end
    local keys = vim.api.nvim_replace_termcodes(cmd, true, false, true)
    vim.api.nvim_feedkeys(keys, "nx", false)
  end
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (the mock `nvim_feedkeys` is a no-op, so the real scroll cannot be exercised under the unit harness). Write this to `/tmp/whisk_probe_fallback.lua`:

  ```lua
  local ok, err = pcall(function()
    local orchestrator = require("whisk.engine.orchestrator")
    local lines = {}
    for i = 1, 500 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local before = vim.fn.line("w0")
    orchestrator.fallback({ keys = { "<C-d>" } }, { count = 1, direction = "<C-d>" })
    local after = vim.fn.line("w0")

    print("topline_before=" .. before)
    print("topline_after=" .. after)
    print("scrolled=" .. tostring(after > before))
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_fallback.lua" 2>&1
  ```
  Expected output contains `scrolled=true` (`topline_after` > `topline_before`; the resolved `<C-d>` performs a real half-page scroll). Before the fix this printed `scrolled=false`. Do NOT commit the probe file.

- [ ] Commit:
  ```
  git add lua/whisk/engine/orchestrator.lua tests/mocks/vim_api.lua tests/unit/engine/orchestrator_spec.lua
  git commit -m "fix(engine): resolve termcodes and feed keys in fallback path"
  ```

---

### Task 6: Group the performance autocmd and add teardown (#7)

`performance.setup` registers `nvim_create_autocmd({'BufEnter','BufWinEnter'}, {...})` with NO augroup and no teardown. Because the plugin auto-runs `setup()` and most users also call `setup({...})`, the second setup re-registers a duplicate autocmd — unremovable and accumulating. Fix (mirroring `lifecycle.lua`): register under a named augroup `WhiskPerformance` with `clear = true`, add `M.teardown()` that deletes the augroup and restores modified state, and call it from `init.M.reset`.

**Files:**
- Modify: `lua/whisk/performance.lua`
- Modify: `lua/whisk/init.lua`
- Test: `tests/unit/performance_spec.lua` (add tests)
- Test: `tests/unit/init_spec.lua` (add test)

**Interfaces:**
- Produces: `performance.teardown()` — deletes the `WhiskPerformance` augroup and disables performance mode (restoring syntax). `performance.setup()` registers its autocmd under augroup `WhiskPerformance` (`clear = true`).
- Consumes: `init.M.reset()` now calls `performance.teardown()`.

**Steps:**

- [ ] Write failing tests in `tests/unit/performance_spec.lua`. Add these three `it(...)` blocks inside the `describe('performance', ...)` block (e.g. after `'setup creates autocmds'`):

  ```lua
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
  ```

- [ ] Write a failing test in `tests/unit/init_spec.lua`. Add this `it(...)` block inside the `describe('init (main module)', ...)` block (e.g. after `'reset tears down lifecycle'`):

  ```lua
  it('reset tears down performance mode', function()
    whisk.setup({ performance = { enabled = true } })
    local performance = require('whisk.performance')
    assert.is_true(performance.is_active())
    whisk.reset()
    assert.is_false(performance.is_active())
  end)
  ```

- [ ] Run the tests and see them fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; failures include `performance > exports teardown` (`performance.teardown` is nil) and `performance > setup registers its autocmd under the WhiskPerformance augroup` (current autocmd has no `opts.group`).

- [ ] Implement the performance module change. In `lua/whisk/performance.lua`:

  Add a module-level local for the augroup handle. Immediately after the `performance_state = { ... }` block near the top of the file, add:
  ```lua
  local autocmd_group = nil
  ```

  Replace the entire `M.setup` function with:
  ```lua
  function M.setup()
    local perf_config = config.get_performance()

    if perf_config.enabled then
      M.enable()
    end

    autocmd_group = vim.api.nvim_create_augroup("WhiskPerformance", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
      group = autocmd_group,
      callback = function()
        M.auto_toggle()
      end,
    })
  end
  ```

  Add a new `M.teardown` function immediately after `M.setup`:
  ```lua
  function M.teardown()
    M.disable()
    if autocmd_group then
      vim.api.nvim_del_augroup_by_id(autocmd_group)
      autocmd_group = nil
    end
  end
  ```

- [ ] Implement the init change. In `lua/whisk/init.lua`, replace the entire `M.reset` function with:

  ```lua
  function M.reset()
    keymaps.clear()
    loop.stop_all()
    traits.clear()
    motions.clear()
    lifecycle.teardown()
    local performance = require("whisk.performance")
    performance.teardown()
    initialized = false
  end
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Headless probe (the mock cannot replicate real augroup `clear = true` semantics, so the no-accumulation behavior needs real Neovim). Write this to `/tmp/whisk_probe_perfaug.lua`:

  ```lua
  local ok, err = pcall(function()
    local whisk = require("whisk")
    whisk.setup({})
    whisk.setup({})
    whisk.setup({})
    local aus = vim.api.nvim_get_autocmds({ group = "WhiskPerformance", event = "BufEnter" })
    print("bufenter_count=" .. #aus)
  end)
  if not ok then print("PROBE_ERROR: " .. tostring(err)) end
  vim.cmd("qa!")
  ```

  Run it:
  ```
  nvim --headless --clean --noplugin --cmd "set runtimepath+=/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim" -c "luafile /tmp/whisk_probe_perfaug.lua" 2>&1
  ```
  Expected output contains `bufenter_count=1` (three `setup()` calls leave exactly one `BufEnter` autocmd in the `WhiskPerformance` group — no accumulation). Do NOT commit the probe file.

- [ ] Commit:
  ```
  git add lua/whisk/performance.lua lua/whisk/init.lua tests/unit/performance_spec.lua tests/unit/init_spec.lua
  git commit -m "fix(engine): group performance autocmd and tear it down on reset"
  ```

---

### Task 7: FPS metric skips idle gaps (#34)

`record_frame_time` keeps `last_frame_time` across idle periods, so the first frame of the next animation records the whole idle gap into the 10-sample window and drags `current_fps` down (headless: 62.5 → 9.0 after a 300ms gap). Fix: when the gap since `last_frame_time` exceeds 5x the current frame interval, update `last_frame_time` without recording the sample.

**Files:**
- Modify: `lua/whisk/performance.lua`
- Test: `tests/unit/performance_spec.lua` (add test)

**Interfaces:**
- Consumes: `M.get_frame_interval()` (existing).
- Produces: `M.record_frame_time()` signature unchanged; large gaps no longer contribute a sample.

**Steps:**

- [ ] Write a failing test in `tests/unit/performance_spec.lua`. Add this `it(...)` block inside the `describe('performance', ...)` block (e.g. after `'record_frame_time and get_current_fps work'`):

  ```lua
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
  ```
  (`_G.vim.loop` is replaced with a controllable `hrtime` stub for this test only — `before_each` rebinds `_G.vim.loop = vim_core.loop` next test. Performance mode is disabled here, so `get_frame_interval()` returns 16 → idle threshold 80ms. Twelve 16ms frames give `1000/16 = 62.5` fps; the 300ms gap exceeds 80ms and is skipped, so fps stays 62.5.)

- [ ] Run the test and see it fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; `performance > skips frame samples when the idle gap exceeds 5x the frame interval` fails at the second assertion — current code records the 300ms gap, dropping fps to ~22.5 (not 62.5).

- [ ] Implement the fix. In `lua/whisk/performance.lua`, replace the entire `M.record_frame_time` function with:

  ```lua
  function M.record_frame_time()
    local current_time = vim.loop.hrtime()

    if perf_stats.last_frame_time > 0 then
      local frame_time = (current_time - perf_stats.last_frame_time) / 1000000
      local idle_threshold = M.get_frame_interval() * 5

      if frame_time > idle_threshold then
        perf_stats.last_frame_time = current_time
        return
      end

      table.insert(perf_stats.frame_times, frame_time)

      if #perf_stats.frame_times > 10 then
        table.remove(perf_stats.frame_times, 1)
      end

      if #perf_stats.frame_times > 0 then
        local avg_frame_time = 0
        for _, time in ipairs(perf_stats.frame_times) do
          avg_frame_time = avg_frame_time + time
        end
        avg_frame_time = avg_frame_time / #perf_stats.frame_times
        perf_stats.current_fps = 1000 / avg_frame_time
      end
    end

    perf_stats.last_frame_time = current_time
  end
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Commit:
  ```
  git add lua/whisk/performance.lua tests/unit/performance_spec.lua
  git commit -m "fix(performance): skip idle gaps in the FPS metric"
  ```

---

### Task 8: `setup()` starts from pristine config each call (#25)

`init.reset()` clears keymaps/loop/traits/motions/lifecycle/performance but never config; `config.update()` deep-merges into the persistent `current_config`, and `management.reset()` is never called in production. So repeated `setup()` calls merge cumulatively — a value set by an earlier `setup()` cannot be cleared by a later one that omits it. Fix: call `config.reset()` at the start of `setup()` (before validate/update), NOT inside `M.reset()` (which is also the public teardown path).

**Files:**
- Modify: `lua/whisk/init.lua`
- Test: `tests/unit/init_spec.lua` (add test)

**Interfaces:**
- Consumes: `config.reset()` (existing facade → `management.reset`).
- Produces: `M.setup(user_config)` now resets config to defaults before applying the user table. `M.reset()` is unchanged by this task.

**Steps:**

- [ ] Write a failing test in `tests/unit/init_spec.lua`. Add this `it(...)` block inside the `describe('init (main module)', ...)` block (e.g. after `'multiple setup calls work'`):

  ```lua
  it('setup starts from pristine defaults on each call', function()
    local config = require('whisk.config')

    whisk.setup({ cursor = { duration = 500 } })
    assert.equals(config.get_cursor().duration, 500)

    whisk.setup({ scroll = { duration = 100 } })
    assert.equals(config.get_cursor().duration, 150)
    assert.equals(config.get_scroll().duration, 100)
  end)
  ```

- [ ] Run the test and see it fail: `bash scripts/run_tests.sh`. Expected: `Failed:` nonzero; `init (main module) > setup starts from pristine defaults on each call` fails — after the second `setup()`, `cursor.duration` is still the stale `500` (expected default `150`).

- [ ] Implement the fix. In `lua/whisk/init.lua`, replace the entire `M.setup` function with:

  ```lua
  function M.setup(user_config)
    if initialized then
      M.reset()
    end

    config.reset()
    config.validate(user_config)
    config.update(user_config)

    local performance = require("whisk.performance")
    performance.setup()

    builtin.register_all()
    keymaps.setup()
    lifecycle.setup()

    initialized = true
  end
  ```

- [ ] Run the tests and see them pass: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Commit:
  ```
  git add lua/whisk/init.lua tests/unit/init_spec.lua
  git commit -m "fix(config): reset to defaults at the start of setup()"
  ```

---

### Task 9: README lazy.nvim recipe disables auto-setup (#28)

The documented lazy.nvim recipe uses `opts = {}` without disabling auto-setup. Since `plugin/whisk.vim` defaults `g:whisk_auto_setup = 1` and auto-calls `setup()`, while lazy independently calls `setup(opts)`, `setup()` runs twice at startup — leaking a duplicate performance autocmd (the engine-side leak is fixed in Task 6; this documents the correct single-setup recipe). Docs-only task: no test cycle; validation is proofreading plus tests still green.

**Files:**
- Modify: `README.md`

**Interfaces:** none (documentation only).

**Steps:**

- [ ] Update the lazy.nvim recipe. In `README.md`, replace the lazy.nvim code block and add one explanatory sentence. Change:

  ```markdown
  ### lazy.nvim

  ```lua
  {
    "josstei/whisk.nvim",
    event = "VeryLazy",
    opts = {},
  }
  ```
  ```
  to:
  ```markdown
  ### lazy.nvim

  ```lua
  {
    "josstei/whisk.nvim",
    event = "VeryLazy",
    init = function() vim.g.whisk_auto_setup = 0 end,
    opts = {},
  }
  ```

  The `init` hook disables the plugin's built-in auto-setup so that lazy.nvim's `opts` is the single source of `setup()`; without it, whisk is configured twice at startup (once on load, once by lazy), leaking a duplicate performance autocmd.
  ```

- [ ] Proofread the edited section: confirm the code block is valid Lua, the sentence reads cleanly, and no other README content was altered.

- [ ] Run the tests to confirm the branch is still green: `bash scripts/run_tests.sh`. Expected: `Failed:  0`.

- [ ] Commit:
  ```
  git add README.md
  git commit -m "docs: disable auto-setup in the lazy.nvim install recipe"
  ```

---

## Wave completion checklist

- [ ] All 9 tasks committed on `audit/wave-1-quick-wins`.
- [ ] `bash scripts/run_tests.sh` → `Failed:  0` (baseline 441 + added tests).
- [ ] All three headless probes produced their expected output (Task 2 `bare_line=4` / `count1_line=1`; Task 5 `scrolled=true`; Task 6 `bufenter_count=1`).
- [ ] Fable wave review of `git diff main...HEAD` against this plan and the findings file passes.
- [ ] PR opened to `main` with `Fixes #14` in the description.
