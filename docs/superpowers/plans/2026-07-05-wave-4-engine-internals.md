# Wave 4: Engine Internals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize the frame-loop hot path (dedupe, pooling, cached reads, clock-true pacing), wire the dead `ignore_events` config into real `'eventignore'` suppression, and scope trait domination per window — with behavior pinned by both test tiers.

**Architecture:** whisk.nvim animates cursor/scroll motions through a registry-driven engine: keymaps call `engine/orchestrator.execute`, which builds a `context/Context`, runs the motion's calculator, and enqueues an animation in `engine/loop` (a `vim.defer_fn`-driven frame queue over pooled animation objects from `engine/pool`), where each frame interpolates a result and applies it through per-trait apply functions in `registry/traits`/`registry/builtin`. This wave changes only engine internals and the Context write path; every motion's public behavior, trait membership, and calculator results are unchanged. Wave 3's real-Neovim integration tier and CI already exist on `main`: every task must keep both tiers green, and tasks whose behavior the Lua mocks cannot observe carry mandatory headless-Neovim probes (port a probe into the Wave 3 tier as an integration spec in the same commit when that tier's harness idiom accommodates it — discover the tier layout via `.github/workflows/` and `tests/`; otherwise run the probe manually and paste its output into the commit message body).

**Tech Stack:** Lua 5.1+ (Neovim runtime), plain-Lua unit test harness (tests/), headless Neovim probes for behavior the mocks cannot exercise.

**Findings covered:**

- **#15** — identical-frame dedupe: skip trait application when the integer frame `{line, col, topline}` is unchanged; first and final frames always apply.
- **#16** — `performance.ignore_events` is dead config; wire it into `'eventignore'` around intermediate-frame trait application only (final frame unsuppressed), and update the README performance section.
- **#29** — scroll motions apply the cursor twice per frame; add `Context:set_topline` and make the scroll trait topline-only so the cursor trait is the sole cursor writer.
- **#30** — `interpolate_result` allocates 3 tables per frame; pooled animations own a reusable `interpolated` scratch table written in place.
- **#31** — context validity re-checked 2-3x per frame; validate once per animation per frame and move the Context write methods to a caller-validates contract.
- **#32** — clamp path re-reads `line_count`/line lengths every frame; cache them in a `frame_cache` reset at the top of each `process_frame` tick (buffer edits picked up on the next tick).
- **#33** — flat 16ms re-arm drifts by per-frame work; schedule frame N against the animation clock: `interval - (elapsed_ms % interval)`, min 1ms.
- **#35** — native-delegation helper begins with a provably no-op cursor write; remove it (or, if Wave 2 already omits it, pin exactly one save-exec-restore cycle with a counting test).
- **#37** — animating state is global, so domination snaps other windows' animations; key it per `(trait_id, winid)` and dominate via a new `loop.complete_for_window(winid)`.

## Execution Model

- Branch: `audit/wave-4-engine-internals`, created from `main` (after the previous wave's PR has merged; Wave 1 branches from current main).
- Executor: one Sonnet 5 subagent (high effort) per task, fresh context per task, given only that task's text plus this plan's header and Global Constraints.
- Task review: an Opus 4.8 subagent (xhigh effort) reviews each completed task's diff against the task spec before the next task starts. Review verdict gates progression.
- Wave review: one Fable agent reviews the wave's full branch diff (`git diff main...HEAD`) against this plan plus the findings file before the PR is opened.
- PR: opened to `main` when all tasks complete, `bash scripts/run_tests.sh` passes, and the Fable wave review passes.

## Global Constraints

- Neovim >= 0.8 API compatibility only (no vim.uv, no nvim_exec2, no APIs newer than 0.8 unless feature-detected).
- No inline comments in code. LuaCATS/JSDoc-style annotation comments are permitted only where a task explicitly calls for them.
- Commit style: conventional commits with scope, matching repo history (`fix(engine): ...`, `feat(context): ...`, `test: ...`, `docs: ...`, `chore: ...`). NO AI attribution of any kind — no "Generated with", no "Co-Authored-By: Claude".
- Every task ends with `bash scripts/run_tests.sh` passing (441+ tests, zero failures) before its commit.
- Do not modify files outside this wave's scope. Do not touch `lua/luxmotion/` or `plugin/luxmotion.vim` (deprecation shims) unless a finding says to.
- Wave-specific: Waves 1-3 have merged before this branch is cut. Some files this wave touches (`engine/orchestrator.lua`, `engine/loop.lua`, `calculators/native.lua`, `performance.lua`, the mocks) were modified by those waves, so locate code by content, never by line number. Where a task below quotes "current" code from commit 852b689, treat it as an anchor: find the equivalent block by content and apply the stated transformation without disturbing additions from Waves 1-2 (jump-flag push, `should_skip_animation`, `has_count`).
- Wave-specific: the Wave 3 real-Neovim integration tier and CI must also stay green. If that tier runs via a script or workflow (check `.github/workflows/` and `scripts/`), run it locally when a task changes engine/context behavior; headless probes in tasks below are mandatory where marked.

---

### Task 1: Pin the native helper to a single save-exec-restore cycle (#35)

The Wave 2 contract for `lua/whisk/calculators/native.lua` is `M.calculate(motion_cmd, context, opts)`: save the view with `vim.fn.winsaveview()`, execute `normal!` under `pcall`, capture the target cursor and `curswant` (via a second `vim.fn.winsaveview().curswant` read), restore the original view with `vim.fn.winrestview(saved)`, and return `{ cursor = { line, col }, curswant = number }`. The pre-Wave-2 per-file helpers (e.g. `calculate_via_native` in `word.lua` at 852b689) began with `vim.api.nvim_win_set_cursor(0, original)` — a guaranteed no-op because the context was just built from the current cursor. This task removes that leading write if any trace of it survived into `native.lua`, and pins the invariant with a call-counting test either way. It also adds the mock call-capture instrumentation that Tasks 2 and 9 reuse.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/calculators/native.lua` (only if a leading origin cursor write exists)
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_api.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_fn.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/calculators/native_spec.lua` (append a describe block; create the file and register it in `tests/init.lua` only if Wave 2 did not create it)

**Interfaces:**
- Consumes: `native.calculate(motion_cmd, context, opts) -> { cursor = { line, col }, curswant = number }` (Wave 2 contract, unchanged by this task).
- Produces (test infrastructure, used by Tasks 2 and 9): mock `vim_api` state gains `set_cursor_calls` (list of `{ winid = winid, line = pos[1], col = pos[2] }` captured on every `nvim_win_set_cursor`); mock `vim_fn` state gains `winsaveview_count` (number) and `winrestview_calls` (list of the raw view tables passed to `winrestview`). Both readable through the existing `mocks.get_api_state()` / `mocks.get_fn_state()`.

**Steps:**

- [ ] Instrument the API mock. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_api.lua`, add `set_cursor_calls = {},` to BOTH state-table literals (the module-level `local state = { ... }` and the one inside `function M.reset()`), placing it after `window_buffers = {},`. Then change `nvim_win_set_cursor` to record the raw call before clamping:

```lua
    nvim_win_set_cursor = function(winid, pos)
      table.insert(state.set_cursor_calls, { winid = winid, line = pos[1], col = pos[2] })
      local line = math.max(1, math.min(pos[1], #state.buffer_lines))
      local line_len = #(state.buffer_lines[line] or "")
      local col = math.max(0, math.min(pos[2], math.max(0, line_len - 1)))
      state.cursor = { line, col }
    end,
```

- [ ] Instrument the fn mock. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_fn.lua`, add `winsaveview_count = 0,` and `winrestview_calls = {},` to BOTH state-table literals (module-level and inside `M.reset()`), after `last_char = '',`. Change `winrestview` and `winsaveview` inside `M.create()` to:

```lua
    winrestview = function(view)
      table.insert(state.winrestview_calls, view)
      if view.topline then
        state.topline = view.topline
      end
    end,

    winsaveview = function()
      state.winsaveview_count = state.winsaveview_count + 1
      return {
        topline = state.topline,
        lnum = get_api_state().cursor[1],
        col = get_api_state().cursor[2],
        leftcol = 0,
        curswant = get_api_state().cursor[2],
      }
    end,
```

If Wave 2 already added a `curswant` field to `winsaveview`'s return, keep Wave 2's expression for it and add only the counter line.

- [ ] Write the pinning test. Open `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/calculators/native_spec.lua`. If it exists (Wave 2 created it), append the following complete describe block at the end of the file. If it does not exist, create the file with exactly this content and add `require('tests.unit.calculators.native_spec')` to `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/init.lua` directly after the `require('tests.unit.calculators.search_spec')` line:

```lua
local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('calculators/native single-cycle contract', function()
  local native
  local builder

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({ "alpha beta gamma", "delta epsilon", "zeta eta theta" })
    mocks.set_cursor(1, 0)
    mocks.set_window_size(40, 120)
    mocks.set_topline(1)
    native = require('whisk.calculators.native')
    builder = require('whisk.context.builder')
  end)

  it('performs exactly one save-exec-restore cycle with no leading cursor write', function()
    local context = builder.build({ count = 2, direction = 'w' })
    local api_state = mocks.get_api_state()
    local fn_state = mocks.get_fn_state()
    local set_cursor_before = #api_state.set_cursor_calls
    local save_before = fn_state.winsaveview_count
    local restore_before = #fn_state.winrestview_calls
    local commands_before = #mocks.get_commands()

    local result = native.calculate('w', context, {})

    assert.is_not_nil(result)
    assert.is_not_nil(result.cursor)
    assert.equals(#api_state.set_cursor_calls - set_cursor_before, 0)
    assert.equals(fn_state.winsaveview_count - save_before, 2)
    assert.equals(#fn_state.winrestview_calls - restore_before, 1)

    local normal_count = 0
    local commands = mocks.get_commands()
    for i = commands_before + 1, #commands do
      if commands[i]:match('normal!') then
        normal_count = normal_count + 1
      end
    end
    assert.equals(normal_count, 1)
  end)
end)
```

The two expected `winsaveview` calls are forced by the Wave 2 contract: one save before the motion, one `curswant` capture after it.

- [ ] Run `bash scripts/run_tests.sh`. Two outcomes are acceptable at this step:
  - The new test FAILS with `Expected: 0 / Actual: 1` on the `set_cursor_calls` assertion — `native.calculate` still issues a leading origin cursor write. Proceed to the next step.
  - The new test PASSES — Wave 2's helper already omits the write; the test is now the regression pin. Skip the next step.
- [ ] (Only if the test failed) Open `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/calculators/native.lua` and locate the `vim.api.nvim_win_set_cursor(...)` call that appears BEFORE the `pcall` that executes the `normal!` command and sets the cursor to the context's origin (the pattern from 852b689 was `vim.api.nvim_win_set_cursor(0, original)` immediately after computing `original` from `context.cursor`). Delete exactly that one call. Do not touch the failure-path restore, the post-motion capture, or the final `winrestview` restore.
- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures with the new test passing.
- [ ] Commit:

```
git add lua/whisk/calculators/native.lua tests/mocks/vim_api.lua tests/mocks/vim_fn.lua tests/unit/calculators/native_spec.lua tests/init.lua
git commit -m "perf(calculators): pin native helper to one save-exec-restore cycle"
```

(Include `lua/whisk/calculators/native.lua` and `tests/init.lua` in the add only if they were actually modified.)

---

### Task 2: Add Context:set_topline and make the scroll trait topline-only (#29)

Scroll-category motions carry traits `{ "cursor", "scroll" }`; per frame the cursor trait calls `set_cursor` and then the scroll trait's `restore_view` sets topline AND lnum/col, repositioning the cursor a second time with identical inputs. Decouple them: add `Context:set_topline(topline)` that restores only the topline (`nvim_win_call` + `winrestview` with `topline` only, no `lnum`/`col`), switch the scroll trait to it, and leave the cursor trait as the only cursor writer. Every motion's trait list stays unchanged — domination depends on trait membership. `zz`/`zt`/`zb` (scroll-only trait lists) keep the cursor stationary by construction; Neovim itself moves the cursor only if a topline-only restore would push it offscreen, and that expectation is pinned by a headless probe. `Context:restore_view` remains public API for full-view restoration.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/context/Context.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/registry/builtin.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/context/Context_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/registry/builtin_spec.lua`

**Interfaces:**
- Produces: `Context:set_topline(topline) -> boolean[, string reason]` — clamps `topline` via `clamp_line`, restores it through `nvim_win_call` + `winrestview({ topline = clamped })`, never writes `lnum`/`col`. (Task 9 later drops the internal validity check and the `reason` return path; until then it mirrors `set_cursor`'s contract.)
- Produces: scroll trait apply is topline-only; the cursor trait is the sole writer of cursor position. Trait lists on all motions unchanged.
- Consumes: `mocks.get_fn_state().winrestview_calls` from Task 1.

**Steps:**

- [ ] Write the failing Context tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/context/Context_spec.lua`, append inside the `describe('context/Context', ...)` block, after the `restore_view()` tests:

```lua
  it('set_topline() restores only the topline', function()
    local ctx = Context.new(1, 1000)
    local success = ctx:set_topline(3)
    assert.is_true(success)
    local fn_state = mocks.get_fn_state()
    local last = fn_state.winrestview_calls[#fn_state.winrestview_calls]
    assert.equals(last.topline, 3)
    assert.is_nil(last.lnum)
    assert.is_nil(last.col)
    assert.is_nil(last.leftcol)
  end)

  it('set_topline() does not move the cursor', function()
    mocks.set_cursor(2, 1)
    local ctx = Context.new(1, 1000)
    ctx:set_topline(4)
    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 2)
    assert.equals(cursor[2], 1)
  end)

  it('set_topline() clamps the topline to the line count', function()
    local ctx = Context.new(1, 1000)
    ctx:set_topline(99)
    local fn_state = mocks.get_fn_state()
    local last = fn_state.winrestview_calls[#fn_state.winrestview_calls]
    assert.equals(last.topline, 5)
  end)

  it('set_topline() returns false with reason if context invalid', function()
    local ctx = Context.new(1, 1000)
    mocks.delete_buffer(1)
    local success, reason = ctx:set_topline(3)
    assert.is_false(success)
    assert.equals(reason, 'buffer_deleted')
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the four new tests fail with `attempt to call method 'set_topline' (a nil value)`.
- [ ] Implement `set_topline`. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/context/Context.lua`, insert after the `Context:restore_view` function and before `return Context`:

```lua
function Context:set_topline(topline)
  local valid, reason = self:is_valid()
  if not valid then
    return false, reason
  end

  local clamped_topline = self:clamp_line(topline)

  vim.api.nvim_win_call(self.winid, function()
    vim.fn.winrestview({ topline = clamped_topline })
  end)
  return true
end
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the four Context tests pass, zero failures overall.
- [ ] Write the failing trait tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/registry/builtin_spec.lua`, REPLACE the existing test `it('scroll trait apply function works with Context', ...)` (it only asserted `does_not_throw`) with these two tests:

```lua
  it('scroll trait applies the topline without touching the cursor', function()
    builtin.register_traits()
    mocks.set_buffer_content({ "line1", "line2", "line3", "line4", "line5" })
    mocks.set_cursor(2, 0)
    mocks.set_topline(1)
    mocks.set_window_size(40, 120)

    local scroll_trait = traits.get('scroll')
    local Context = require('whisk.context.Context')
    local ctx = Context.new(1, 1000)
    ctx.viewport = { topline = 1 }

    local result = { viewport = { topline = 3 }, cursor = { line = 3, col = 0 } }
    scroll_trait.apply(ctx, result, 1.0)

    local fn_state = mocks.get_fn_state()
    assert.equals(fn_state.topline, 3)
    local last = fn_state.winrestview_calls[#fn_state.winrestview_calls]
    assert.is_nil(last.lnum)
    assert.is_nil(last.col)

    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 2)
    assert.equals(cursor[2], 0)
  end)

  it('scroll trait applies when the result has no cursor', function()
    builtin.register_traits()
    mocks.set_buffer_content({ "line1", "line2", "line3", "line4", "line5" })
    mocks.set_cursor(2, 0)
    mocks.set_topline(1)
    mocks.set_window_size(40, 120)

    local scroll_trait = traits.get('scroll')
    local Context = require('whisk.context.Context')
    local ctx = Context.new(1, 1000)
    ctx.viewport = { topline = 1 }

    assert.does_not_throw(function()
      scroll_trait.apply(ctx, { viewport = { topline = 4 } }, 1.0)
    end)
    assert.equals(mocks.get_fn_state().topline, 4)
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the first new trait test fails (`Expected: nil / Actual: 3` on `last.lnum`, because the old scroll trait passes `lnum`/`col` through `restore_view`) and the second fails with an error indexing `result.cursor.line` (the old trait dereferences `result.cursor` unconditionally).
- [ ] Implement the topline-only scroll trait. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/registry/builtin.lua`, replace the scroll trait registration inside `M.register_traits`:

```lua
  traits.register({
    id = "scroll",
    apply = function(context, result, progress)
      if result.viewport and result.viewport.topline and context.set_topline then
        context:set_topline(result.viewport.topline)
      end
    end,
  })
```

Do not modify `M.register_motions` — every motion keeps its exact trait list.

- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures.
- [ ] Headless verification (mandatory). From the repo root, pin the "Neovim keeps the cursor visible on a topline-only restore" expectation:

```bash
nvim --headless --clean --cmd "set rtp+=$PWD" -c 'lua local lines = {} for i = 1, 200 do lines[i] = tostring(i) end vim.api.nvim_buf_set_lines(0, 0, -1, false, lines) vim.api.nvim_win_set_cursor(0, {100, 0}) local Context = require("whisk.context.Context") local ctx = Context.new() ctx:set_topline(150) local top = vim.fn.line("w0") local cur = vim.api.nvim_win_get_cursor(0)[1] print(string.format("RESULT topline=%d cursor=%d visible=%s", top, cur, tostring(cur >= top)))' -c 'qa!'
```

Expected output line: `RESULT topline=150 cursor=150 visible=true` (with `scrolloff=0` under `--clean`, Neovim pulls the cursor to the first visible line rather than leaving it offscreen). Then verify a scroll-only motion keeps the cursor stationary through the real engine:

```bash
nvim --headless --clean --cmd "set rtp+=$PWD" -c 'lua require("whisk").setup({}) local lines = {} for i = 1, 200 do lines[i] = tostring(i) end vim.api.nvim_buf_set_lines(0, 0, -1, false, lines) vim.cmd("normal! 100Gzt") local before = vim.api.nvim_win_get_cursor(0)[1] require("whisk.engine.orchestrator").execute("position_zz", {}) vim.wait(500, function() return false end) local after = vim.api.nvim_win_get_cursor(0)[1] local top = vim.fn.line("w0") local expected_top = 100 - math.floor(vim.fn.winheight(0) / 2) print(string.format("RESULT before=%d after=%d ok=%s", before, after, tostring(after == 100 and math.abs(top - expected_top) <= 1)))' -c 'qa!'
```

Expected output line: `RESULT before=100 after=100 ok=true`. If the Wave 3 integration tier's harness accommodates these probes as specs, add them there in this commit; otherwise paste both output lines into the commit message body.

- [ ] Commit:

```
git add lua/whisk/context/Context.lua lua/whisk/registry/builtin.lua tests/unit/context/Context_spec.lua tests/unit/registry/builtin_spec.lua
git commit -m "perf(context): add set_topline and make scroll trait topline-only"
```

---
### Task 3: Reuse a pooled interpolation scratch table across frames (#30)

`interpolate_result` in `engine/loop.lua` builds a fresh `{ cursor = {}, viewport = {} }` (3 table allocations) on every frame of every animation — 33-42 tables per keypress — while `engine/pool.lua` exists precisely to recycle allocation in this path. Give every pooled animation object a reusable `interpolated` scratch table created in `pool.acquire` when absent; `interpolate_result` writes into it in place (clearing fields the result does not populate, so pooled reuse cannot leak a previous motion's values); `pool.release` keeps the scratch table but zeroes its fields.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/pool.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/pool_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`

**Interfaces:**
- Produces: pooled animation objects own `anim.interpolated = { cursor = {}, viewport = {} }` for their whole lifetime; `pool.release` preserves the table identity and clears `cursor.line`, `cursor.col`, `viewport.topline`.
- Produces (loop-internal): `interpolate_result(anim, progress) -> anim.interpolated` — signature changes from `(context, result, progress)` to `(anim, progress)`; both call sites (`process_frame`, `complete_all`) updated. Tasks 4, 8, 9 build on this signature.

**Steps:**

- [ ] Write the failing pool tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/pool_spec.lua`, append inside the describe block:

```lua
  it('acquire provides a reusable interpolated scratch table', function()
    local obj = pool.acquire()
    assert.is_type(obj.interpolated, 'table')
    assert.is_type(obj.interpolated.cursor, 'table')
    assert.is_type(obj.interpolated.viewport, 'table')
  end)

  it('release keeps the scratch table but clears its fields', function()
    pool.clear()
    local obj = pool.acquire()
    local scratch = obj.interpolated
    obj.interpolated.cursor.line = 5
    obj.interpolated.cursor.col = 2
    obj.interpolated.viewport.topline = 9
    pool.release(obj)

    local reused = pool.acquire()
    assert.equals(reused.interpolated, scratch)
    assert.is_nil(reused.interpolated.cursor.line)
    assert.is_nil(reused.interpolated.cursor.col)
    assert.is_nil(reused.interpolated.viewport.topline)
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm both fail (`Expected type: table / Actual type: nil` for `obj.interpolated`).
- [ ] Implement the pooled scratch. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/pool.lua`, replace `M.acquire` and `M.release`:

```lua
function M.acquire()
  local animation
  if pool_size > 0 then
    pool_size = pool_size - 1
    animation = table.remove(animation_pool)
  else
    animation = {
      start_time = 0,
      duration_ns = 0,
      easing_fn = nil,
      context = nil,
      result = nil,
      traits = nil,
      on_complete = nil,
      on_cancel = nil,
    }
  end

  if not animation.interpolated then
    animation.interpolated = { cursor = {}, viewport = {} }
  end

  return animation
end

function M.release(animation)
  if pool_size < MAX_POOL_SIZE then
    animation.start_time = 0
    animation.duration_ns = 0
    animation.easing_fn = nil
    animation.context = nil
    animation.result = nil
    animation.traits = nil
    animation.on_complete = nil
    animation.on_cancel = nil
    if animation.interpolated then
      animation.interpolated.cursor.line = nil
      animation.interpolated.cursor.col = nil
      animation.interpolated.viewport.topline = nil
    end
    pool_size = pool_size + 1
    table.insert(animation_pool, animation)
  end
end
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the pool tests pass, zero failures.
- [ ] Write the failing loop tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`, append inside the describe block. The target line 5000 guarantees the two observed frames land on different integer lines under the mock's fixed 100ms-per-call `hrtime` step, so this test stays valid after Task 4's dedupe:

```lua
  it('interpolation reuses one scratch table across frames', function()
    local traits = require('whisk.registry.traits')
    local received = {}
    traits.register({
      id = 'cursor',
      apply = function(context, result, progress)
        table.insert(received, result)
      end,
    })

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5000, col = 0 } },
      traits = { 'cursor' },
    })

    loop.force_process_frame()
    loop.force_process_frame()

    assert.equals(#received, 2)
    assert.equals(received[1], received[2])
  end)

  it('scratch cursor fields are nil for viewport-only results after pool reuse', function()
    local traits = require('whisk.registry.traits')
    traits.register({
      id = 'cursor',
      apply = function(context, result, progress) end,
    })
    loop.start({
      duration = 50,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
    })
    loop.force_process_frame()
    assert.equals(loop.get_active_count(), 0)

    local captured = nil
    traits.register({
      id = 'scroll',
      apply = function(context, result, progress)
        captured = result
      end,
    })
    loop.start({
      duration = 50,
      easing = 'linear',
      context = { viewport = { topline = 1 } },
      result = { viewport = { topline = 10 } },
      traits = { 'scroll' },
    })
    loop.force_process_frame()

    assert.is_not_nil(captured)
    assert.equals(captured.viewport.topline, 10)
    assert.is_nil(captured.cursor.line)
    assert.is_nil(captured.cursor.col)
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the first new loop test fails on `assert.equals(received[1], received[2])` (the old `interpolate_result` returns a fresh table per frame).
- [ ] Implement in-place interpolation. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`, replace `interpolate_result`:

```lua
local function interpolate_result(anim, progress)
  local interpolated = anim.interpolated

  if anim.result.cursor then
    interpolated.cursor.line = math.floor(lerp(anim.context.cursor.line, anim.result.cursor.line, progress) + 0.5)
    interpolated.cursor.col = math.floor(lerp(anim.context.cursor.col, anim.result.cursor.col, progress) + 0.5)
  else
    interpolated.cursor.line = nil
    interpolated.cursor.col = nil
  end

  if anim.result.viewport and anim.result.viewport.topline then
    interpolated.viewport.topline = math.floor(lerp(anim.context.viewport.topline, anim.result.viewport.topline, progress) + 0.5)
  else
    interpolated.viewport.topline = nil
  end

  return interpolated
end
```

Update the call site in `process_frame` from `interpolate_result(anim.context, anim.result, eased)` to `interpolate_result(anim, eased)`, and the call site in `M.complete_all` from `interpolate_result(anim.context, anim.result, eased_final)` to `interpolate_result(anim, eased_final)`.

- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures.
- [ ] Commit:

```
git add lua/whisk/engine/pool.lua lua/whisk/engine/loop.lua tests/unit/engine/pool_spec.lua tests/unit/engine/loop_spec.lua
git commit -m "perf(engine): reuse pooled interpolation scratch across frames"
```

---

### Task 4: Skip trait application for unchanged frames (#15)

`process_frame` applies every trait on every tick even when the floored integer position is identical to the previous frame — a one-line `j` issues ~11 identical `nvim_win_set_cursor` calls. Track the last-applied `{ line, col, topline }` on each animation and skip trait application when the interpolated integer frame is unchanged since the previous frame. The dedupe key covers cursor line, cursor col AND viewport topline (a scroll frame can change topline with a stationary cursor). The first frame of an animation always applies; the final frame always applies. `complete_all` is a final application by definition and keeps applying unconditionally.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/pool.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`

**Interfaces:**
- Produces: pooled animation objects gain `anim.has_applied` (boolean, reset in `loop.start` and `pool.release`) and `anim.last_applied = {}` (fields `line`, `col`, `topline`; created in `pool.acquire` when absent, cleared in `pool.release`).
- Produces (loop-internal, reused by Tasks 7-9): `apply_traits(anim, interpolated, eased)`, `is_unchanged(anim, interpolated) -> boolean`, `record_applied(anim, interpolated)`.

**Steps:**

- [ ] Write the failing tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`, append inside the describe block. Frame math relies on the mock `hrtime` advancing exactly 100ms per call (two calls per `force_process_frame`: the frame timestamp and `record_frame_time`):

```lua
  it('skips trait application when the integer frame is unchanged', function()
    local traits = require('whisk.registry.traits')
    local apply_count = 0
    traits.register({
      id = 'cursor',
      apply = function() apply_count = apply_count + 1 end,
    })

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 2, col = 0 } },
      traits = { 'cursor' },
    })

    loop.force_process_frame()
    loop.force_process_frame()
    loop.force_process_frame()
    assert.equals(apply_count, 1)

    loop.complete_all()
    assert.equals(apply_count, 2)
  end)

  it('applies the final frame even when unchanged from the previous frame', function()
    local traits = require('whisk.registry.traits')
    local apply_count = 0
    traits.register({
      id = 'cursor',
      apply = function() apply_count = apply_count + 1 end,
    })

    loop.start({
      duration = 250,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 1, col = 0 } },
      traits = { 'cursor' },
    })

    loop.force_process_frame()
    assert.equals(apply_count, 1)
    loop.force_process_frame()
    assert.equals(apply_count, 2)
    assert.equals(loop.get_active_count(), 0)
  end)

  it('does not skip frames where only the topline changes', function()
    local traits = require('whisk.registry.traits')
    local apply_count = 0
    traits.register({
      id = 'scroll',
      apply = function() apply_count = apply_count + 1 end,
    })

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 }, viewport = { topline = 1 } },
      result = { cursor = { line = 1, col = 0 }, viewport = { topline = 10000 } },
      traits = { 'scroll' },
    })

    loop.force_process_frame()
    loop.force_process_frame()
    assert.equals(apply_count, 2)
  end)
```

Frame-math derivation for reviewers: with `duration = 100000` (ns denominator `1e11`) the first tick's elapsed is `1e8`ns (progress 0.001) and the third tick's is `5e8`ns (progress 0.005), so a line-1-to-2 cursor stays floored at line 1 across all three ticks — only the first (first-frame rule) applies, and `complete_all` adds the always-applied final. With `duration = 250` the second tick's elapsed `3e8`ns caps progress at 1.0 — an unchanged-but-final frame that must still apply. In the topline test, progress 0.001 vs 0.003 over a 1-to-10000 topline yields floored toplines 11 vs 31 — changed, so both ticks apply.

- [ ] Run `bash scripts/run_tests.sh` and confirm the first test fails with `Expected: 1 / Actual: 3` (every tick currently applies) and the third passes trivially; the second passes (2 applies either way) — it exists to pin the final-frame rule against regressions.
- [ ] Implement the dedupe. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/pool.lua`, add `has_applied = false,` to the fresh-object literal in `M.acquire` (after `on_cancel = nil,`), add this block in `M.acquire` next to the `interpolated` guard:

```lua
  if not animation.last_applied then
    animation.last_applied = {}
  end
```

and add to `M.release`, after the `interpolated` clearing block:

```lua
    animation.has_applied = false
    if animation.last_applied then
      animation.last_applied.line = nil
      animation.last_applied.col = nil
      animation.last_applied.topline = nil
    end
```

- [ ] In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`, insert these three locals after `interpolate_result`:

```lua
local function apply_traits(anim, interpolated, eased)
  for _, trait_id in ipairs(anim.traits) do
    traits.apply_frame(trait_id, anim.context, interpolated, eased)
  end
end

local function is_unchanged(anim, interpolated)
  return anim.has_applied == true
    and interpolated.cursor.line == anim.last_applied.line
    and interpolated.cursor.col == anim.last_applied.col
    and interpolated.viewport.topline == anim.last_applied.topline
end

local function record_applied(anim, interpolated)
  anim.has_applied = true
  anim.last_applied.line = interpolated.cursor.line
  anim.last_applied.col = interpolated.cursor.col
  anim.last_applied.topline = interpolated.viewport.topline
end
```

Then replace the interpolate-and-apply section of `process_frame` (from `local elapsed = ...` through the `progress >= 1.0` completion block) with:

```lua
    local elapsed = current_time - anim.start_time
    local progress = math.min(elapsed / anim.duration_ns, 1.0)
    local eased = anim.easing_fn(progress)
    local is_final = progress >= 1.0

    local interpolated = interpolate_result(anim, eased)

    if is_final or not is_unchanged(anim, interpolated) then
      apply_traits(anim, interpolated, eased)
      record_applied(anim, interpolated)
    end

    if is_final then
      if anim.on_complete then
        anim.on_complete()
      end
      table.remove(frame_queue, i)
      pool.release(anim)
    end
```

Replace the trait loop inside `M.complete_all` with `apply_traits(anim, final, eased_final)`, and add `anim.has_applied = false` in `M.start` after `anim.on_cancel = options.on_cancel`.

- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures (the existing integration test `cursor is clamped when buffer shrinks during animation` must still pass: its 10ms duration makes the first tick final, which always applies).
- [ ] Commit:

```
git add lua/whisk/engine/loop.lua lua/whisk/engine/pool.lua tests/unit/engine/loop_spec.lua
git commit -m "perf(engine): skip trait application for unchanged frames"
```

---

### Task 5: Cache per-tick buffer reads for the clamp path (#32)

`set_cursor`/`set_topline` clamp on every application: `clamp_line` calls `nvim_buf_line_count` and `clamp_column` calls `nvim_buf_get_lines` (allocating the whole line string) — per trait, per frame. Cache both in a `frame_cache` that is reset at the top of each `process_frame` tick (and of each completion sweep) and attached to the animation's context, so the clamp path consults at most one live read per buffer per tick. Buffer edits mid-animation are picked up on the NEXT tick because the cache is reset per tick — the existing `cursor is clamped when buffer shrinks during animation` integration test must stay green.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/context/Context.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_api.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/context/Context_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`

**Interfaces:**
- Produces: `context.frame_cache = { line_count = number|nil, line_lengths = { [lnum] = length } }` — attached by the loop, consulted by `Context:get_line_count` / `Context:get_line_length` when present; contexts without an attached cache behave exactly as before (calculators, direct API users are unaffected).
- Produces (loop-internal): `reset_frame_cache()` and `attach_frame_cache(context)`; the cache is keyed per `context.bufnr` so multiple animations on one buffer share reads within a tick.
- Produces (test infrastructure): mock `vim_api` state gains counters `buf_get_lines_calls` and `buf_line_count_calls`.

**Steps:**

- [ ] Instrument the API mock. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_api.lua`, add `buf_get_lines_calls = 0,` and `buf_line_count_calls = 0,` to BOTH state-table literals (module-level and inside `M.reset()`), after `set_cursor_calls = {},`. Add `state.buf_get_lines_calls = state.buf_get_lines_calls + 1` as the first line of the `nvim_buf_get_lines` mock function, and `state.buf_line_count_calls = state.buf_line_count_calls + 1` as the first line of the `nvim_buf_line_count` mock function.
- [ ] Write the failing Context tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/context/Context_spec.lua`, append inside the describe block:

```lua
  it('get_line_count() consults an attached frame cache', function()
    local ctx = Context.new(1, 1000)
    ctx.frame_cache = { line_lengths = {} }
    assert.equals(ctx:get_line_count(), 5)
    mocks.set_buffer_content({ "a" })
    assert.equals(ctx:get_line_count(), 5)
    ctx.frame_cache = nil
    assert.equals(ctx:get_line_count(), 1)
  end)

  it('get_line_length() consults an attached frame cache', function()
    mocks.set_buffer_content({ "abc" })
    local ctx = Context.new(1, 1000)
    ctx.frame_cache = { line_lengths = {} }
    assert.equals(ctx:get_line_length(1), 3)
    mocks.set_buffer_content({ "abcdef" })
    assert.equals(ctx:get_line_length(1), 3)
    ctx.frame_cache = nil
    assert.equals(ctx:get_line_length(1), 6)
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm both fail (`Expected: 5 / Actual: 1` and `Expected: 3 / Actual: 6` — the current methods always read live).
- [ ] Implement cache consultation. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/context/Context.lua`, replace `Context:get_line_count` and `Context:get_line_length`:

```lua
function Context:get_line_count()
  local cache = self.frame_cache
  if cache and cache.line_count then
    return cache.line_count
  end
  local line_count = vim.api.nvim_buf_line_count(self.bufnr)
  if cache then
    cache.line_count = line_count
  end
  return line_count
end

function Context:get_line_length(line_num)
  local cache = self.frame_cache
  if cache and cache.line_lengths[line_num] then
    return cache.line_lengths[line_num]
  end
  local lines = vim.api.nvim_buf_get_lines(self.bufnr, line_num - 1, line_num, false)
  local length = 0
  if lines and lines[1] then
    length = #lines[1]
  end
  if cache then
    cache.line_lengths[line_num] = length
  end
  return length
end
```

(A cached length of `0` is truthy in Lua, so the zero-length case is served from the cache correctly.)

- [ ] Run `bash scripts/run_tests.sh` and confirm the two Context tests pass, zero failures.
- [ ] Write the failing loop tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`, append inside the describe block:

```lua
  it('caches buffer reads within a single frame tick', function()
    local builtin = require('whisk.registry.builtin')
    local builder = require('whisk.context.builder')
    builtin.register_traits()
    mocks.set_buffer_content({ "line 1", "line 2", "line 3", "line 4", "line 5" })
    mocks.set_cursor(1, 0)
    mocks.set_topline(1)
    mocks.set_window_size(40, 120)

    local ctx = builder.build({})
    loop.start({
      duration = 100000,
      easing = 'linear',
      context = ctx,
      result = { cursor = { line = 5, col = 0 }, viewport = { topline = 3 } },
      traits = { 'cursor', 'scroll' },
    })

    local api_state = mocks.get_api_state()
    local count_before = api_state.buf_line_count_calls
    loop.force_process_frame()
    assert.equals(api_state.buf_line_count_calls - count_before, 1)
  end)

  it('completion sweeps consult fresh buffer state after edits', function()
    local builtin = require('whisk.registry.builtin')
    local builder = require('whisk.context.builder')
    builtin.register_traits()
    mocks.set_buffer_content({
      "line 1", "line 2", "line 3", "line 4", "line 5",
      "line 6", "line 7", "line 8", "line 9", "line 10",
    })
    mocks.set_cursor(1, 0)
    mocks.set_topline(1)
    mocks.set_window_size(40, 120)

    local ctx = builder.build({})
    loop.start({
      duration = 100000,
      easing = 'linear',
      context = ctx,
      result = { cursor = { line = 10, col = 0 } },
      traits = { 'cursor' },
    })

    loop.force_process_frame()
    mocks.set_buffer_content({ "line 1", "line 2", "line 3" })
    loop.complete_all()

    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 3)
  end)
```

The first test's expectation: within one tick the cursor trait's clamp misses the cache once (`1` live `nvim_buf_line_count`) and the scroll trait's clamp then hits it — before this change the same tick issues 2 live reads.

- [ ] Run `bash scripts/run_tests.sh` and confirm the first loop test fails with `Expected: 1 / Actual: 2` and the second passes (it pins next-tick freshness for the completion sweep against regressions).
- [ ] Implement the tick cache in the loop. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`, add after the `local is_running = false` declaration:

```lua
local frame_cache = {}
```

and after the `record_applied` local function:

```lua
local function reset_frame_cache()
  for bufnr in pairs(frame_cache) do
    frame_cache[bufnr] = nil
  end
end

local function attach_frame_cache(context)
  if not context.bufnr then
    return
  end
  local cache = frame_cache[context.bufnr]
  if not cache then
    cache = { line_lengths = {} }
    frame_cache[context.bufnr] = cache
  end
  context.frame_cache = cache
end
```

In `process_frame`, add `reset_frame_cache()` immediately after `performance.record_frame_time()`, and add `attach_frame_cache(anim.context)` immediately after the validity-check block (before `local elapsed = ...`). In `M.complete_all`, add `reset_frame_cache()` as the first line of the function and `attach_frame_cache(anim.context)` as the first line inside its `for` loop.

- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures, including the pre-existing integration test `cursor is clamped when buffer shrinks during animation` (each tick resets the cache, so the shrink is observed on the tick after the edit).
- [ ] Commit:

```
git add lua/whisk/engine/loop.lua lua/whisk/context/Context.lua tests/mocks/vim_api.lua tests/unit/context/Context_spec.lua tests/unit/engine/loop_spec.lua
git commit -m "perf(context): cache buffer reads per frame tick"
```

---
### Task 6: Schedule frames against the animation clock (#33)

`process_frame` re-arms with a flat `vim.defer_fn(process_frame, performance.get_frame_interval())` measured from the END of the current frame's work, so the effective frame period is `interval + processing time` and cadence drifts precisely when frames are expensive. Schedule against the animation clock instead: the loop records `loop_start_ns` when it spins up, and every arm (initial and re-arm) waits `interval - (elapsed_ms % interval)` clamped to a minimum of 1ms, so frame N targets `loop_start + N * interval` regardless of per-frame work.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`

**Interfaces:**
- Produces (loop-internal): `loop_start_ns` (set in `M.start` whenever the loop transitions from idle to running) and `next_frame_delay() -> integer ms in [1, interval]`, used by both the initial arm in `M.start` and the re-arm in `process_frame`. Duration/progress math is untouched (progress remains hrtime-derived).

**Steps:**

- [ ] Write the failing tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`, append inside the describe block. Derivation: the mock `hrtime` advances exactly 100ms per call. In `M.start`, call one sets `start_time`/`loop_start_ns` and call two (inside `next_frame_delay`) reads elapsed 100ms, so the first delay is `16 - (100 % 16) = 12`. Executing that deferred frame consumes two more hrtime calls (frame timestamp, `record_frame_time`), and the re-arm's read then sees elapsed 400ms, so the second delay is `16 - (400 % 16) = 16`:

```lua
  it('schedules the first frame against the animation clock', function()
    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    local deferred = mocks.get_deferred_calls()
    assert.equals(#deferred, 1)
    assert.equals(deferred[1].delay, 12)
  end)

  it('re-arms subsequent frames on the animation clock within [1, interval]', function()
    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    mocks.execute_deferred(1)

    local deferred = mocks.get_deferred_calls()
    assert.equals(#deferred, 2)
    assert.equals(deferred[2].delay, 16)
    for _, call in ipairs(deferred) do
      assert.greater_or_equal(call.delay, 1)
      assert.less_or_equal(call.delay, 16)
    end
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the first test fails with `Expected: 12 / Actual: 16` (flat interval today).
- [ ] Implement clock-true scheduling. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`, add after the `local frame_cache = {}` declaration:

```lua
local loop_start_ns = 0
```

and after the `attach_frame_cache` local function:

```lua
local function next_frame_delay()
  local interval = performance.get_frame_interval()
  local elapsed_ms = (vim.loop.hrtime() - loop_start_ns) / 1000000
  local delay = math.floor(interval - (elapsed_ms % interval))
  if delay < 1 then
    delay = 1
  end
  return delay
end
```

In `process_frame`, change the re-arm from `vim.defer_fn(process_frame, performance.get_frame_interval())` to `vim.defer_fn(process_frame, next_frame_delay())`. In `M.start`, change the idle-to-running block to:

```lua
  if not is_running then
    is_running = true
    loop_start_ns = anim.start_time
    vim.defer_fn(process_frame, next_frame_delay())
  end
```

- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures.
- [ ] Commit:

```
git add lua/whisk/engine/loop.lua tests/unit/engine/loop_spec.lua
git commit -m "fix(engine): schedule frames against the animation clock"
```

---

### Task 7: Wire performance.ignore_events into 'eventignore' during intermediate frames (#16)

`performance.lua` builds an `ignored_events` lookup and exposes `should_ignore_event`, but nothing ever sets `vim.o.eventignore` — the documented `performance.ignore_events` config is dead. Make it real: during per-frame trait application (NOT the final frame), save `vim.o.eventignore`, extend it with the configured `performance.ignore_events` list, apply the traits, restore. The final completion frame — the natural-completion tick, `complete_all`, and (after Task 8) `complete_for_window` — applies WITHOUT suppression so statuslines and other plugins settle on the real resting position. Do not use `lazyredraw` (it would blank the animation's own frames). Update the README performance section (and the matching USAGE/ARCHITECTURE lines) in this same task. `should_ignore_event` remains public API, unchanged.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/performance.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_core.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/README.md`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/docs/USAGE.md`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/docs/ARCHITECTURE.md`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/performance_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`

**Interfaces:**
- Produces: `performance.suppress_events() -> string saved` — reads `vim.o.eventignore` (treating nil as `""` for mock compatibility), appends the comma-joined configured `performance.ignore_events` (no-op when the list is empty), returns the saved value. `performance.restore_events(saved)` — writes `saved` back to `vim.o.eventignore`. The joined string is cached against the config table reference so the hot path does not re-concatenate every frame.
- Produces (loop-internal): `apply_suppressed(anim, interpolated, eased)` — suppress, `pcall` the trait application, restore, re-raise on error; used only for non-final frames in `process_frame`. No config keys added (`ignore_events` already exists in `config/defaults.lua`).
- Consumes: `apply_traits`/`is_unchanged`/`record_applied` from Task 4.

**Steps:**

- [ ] Give the mock an `eventignore` option. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_core.lua`, change the `M.options` table to:

```lua
M.options = {
  scrolloff = 5,
  eventignore = "",
}
```

(The options table is module-level and not rebuilt by `reset()`, so every test below that touches `vim.o.eventignore` sets it to `""` at the start of the test.)

- [ ] Write the failing performance tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/performance_spec.lua`, append inside the describe block:

```lua
  it('suppress_events appends configured events to eventignore and restore_events restores', function()
    vim.o.eventignore = ""
    local saved = performance.suppress_events()
    assert.equals(saved, "")
    assert.matches(vim.o.eventignore, "WinScrolled")
    assert.matches(vim.o.eventignore, "CursorMoved")
    assert.matches(vim.o.eventignore, "CursorMovedI")
    performance.restore_events(saved)
    assert.equals(vim.o.eventignore, "")
  end)

  it('suppress_events preserves pre-existing eventignore entries', function()
    vim.o.eventignore = "BufEnter"
    local saved = performance.suppress_events()
    assert.equals(saved, "BufEnter")
    assert.matches(vim.o.eventignore, "BufEnter")
    assert.matches(vim.o.eventignore, "CursorMoved")
    performance.restore_events(saved)
    assert.equals(vim.o.eventignore, "BufEnter")
    vim.o.eventignore = ""
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm both fail with `attempt to call field 'suppress_events' (a nil value)`.
- [ ] Implement suppression in the performance module. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/performance.lua`, insert after the `M.should_ignore_event` function:

```lua
local eventignore_cache = {
  source = nil,
  joined = "",
}

local function joined_ignore_events()
  local events = config.get_performance().ignore_events
  if eventignore_cache.source ~= events then
    eventignore_cache.source = events
    eventignore_cache.joined = table.concat(events, ",")
  end
  return eventignore_cache.joined
end

function M.suppress_events()
  local saved = vim.o.eventignore or ""
  local events = joined_ignore_events()
  if events == "" then
    return saved
  end
  if saved == "" then
    vim.o.eventignore = events
  else
    vim.o.eventignore = saved .. "," .. events
  end
  return saved
end

function M.restore_events(saved)
  vim.o.eventignore = saved
end
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the two performance tests pass, zero failures.
- [ ] Write the failing loop tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`, append inside the describe block:

```lua
  it('applies intermediate frames with configured events suppressed', function()
    local traits = require('whisk.registry.traits')
    local seen = {}
    traits.register({
      id = 'cursor',
      apply = function() table.insert(seen, vim.o.eventignore) end,
    })
    vim.o.eventignore = ""

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 500, col = 0 } },
      traits = { 'cursor' },
    })

    loop.force_process_frame()
    assert.equals(#seen, 1)
    assert.matches(seen[1], "CursorMoved")
    assert.equals(vim.o.eventignore, "")
  end)

  it('applies the final frame without event suppression', function()
    local traits = require('whisk.registry.traits')
    local seen = {}
    traits.register({
      id = 'cursor',
      apply = function() table.insert(seen, vim.o.eventignore) end,
    })
    vim.o.eventignore = ""

    loop.start({
      duration = 50,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
    })

    loop.force_process_frame()
    assert.equals(#seen, 1)
    assert.equals(seen[1], "")
    assert.equals(loop.get_active_count(), 0)
  end)

  it('complete_all applies without event suppression', function()
    local traits = require('whisk.registry.traits')
    local seen = {}
    traits.register({
      id = 'cursor',
      apply = function() table.insert(seen, vim.o.eventignore) end,
    })
    vim.o.eventignore = ""

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
    })

    loop.complete_all()
    assert.equals(#seen, 1)
    assert.equals(seen[1], "")
  end)

  it('restores eventignore when a trait apply errors', function()
    local traits = require('whisk.registry.traits')
    traits.register({
      id = 'cursor',
      apply = function() error('boom') end,
    })
    vim.o.eventignore = ""

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 500, col = 0 } },
      traits = { 'cursor' },
    })

    assert.throws(function()
      loop.force_process_frame()
    end, 'boom')
    assert.equals(vim.o.eventignore, "")
  end)
```

(`duration = 50` makes the first mock tick's elapsed 100ms cap progress at 1.0 — a final frame; `duration = 100000` keeps ticks intermediate.)

- [ ] Run `bash scripts/run_tests.sh` and confirm the first new loop test fails on `assert.matches(seen[1], "CursorMoved")` (no suppression is wired yet; `seen[1]` is `""`), and the error test fails on the final `assert.equals` only if suppression were wired without restore — at this point it passes trivially; it exists to pin restore-on-error.
- [ ] Wire suppression into the loop. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`, insert after the `record_applied` local function:

```lua
local function apply_suppressed(anim, interpolated, eased)
  local saved = performance.suppress_events()
  local ok, err = pcall(apply_traits, anim, interpolated, eased)
  performance.restore_events(saved)
  if not ok then
    error(err, 0)
  end
end
```

Then, in `process_frame`, replace the apply block from Task 4:

```lua
    if is_final then
      apply_traits(anim, interpolated, eased)
      record_applied(anim, interpolated)
    elseif not is_unchanged(anim, interpolated) then
      apply_suppressed(anim, interpolated, eased)
      record_applied(anim, interpolated)
    end
```

`M.complete_all` keeps calling `apply_traits` directly — completion is a final frame and must not be suppressed.

- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures.
- [ ] Update the docs (same task, per the finding). In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/README.md`, in the `## Performance mode` section, remove the bullet:

```
- Exposes a configurable `ignore_events` list (default: `WinScrolled`, `CursorMoved`, `CursorMovedI`) for callers to check via `should_ignore_event()`
```

and add this paragraph immediately after the bullet list (before the "Toggle at runtime" line):

```
Independent of performance mode, the configured `ignore_events` list (default: `WinScrolled`, `CursorMoved`, `CursorMovedI`) is appended to `'eventignore'` while intermediate animation frames are applied and restored immediately after each frame. The final frame of every animation (including instant completion on domination) applies without suppression, so statuslines, gitsigns, and other event consumers settle on the real cursor and viewport position exactly once per motion. Set `performance = { ignore_events = {} }` before calling `setup()` to disable suppression entirely. `should_ignore_event()` remains available as a query helper while performance mode is active.
```

Also add `performance.suppress_events()` and `performance.restore_events(saved)` lines to the Performance module code block in README's Lua API section (after `performance.should_ignore_event(event)`).

In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/docs/USAGE.md`, replace the `ignore_events` table row:

```
| `ignore_events` | table | `{"WinScrolled", "CursorMoved", "CursorMovedI"}` | Events to flag as ignorable via `should_ignore_event()` while performance mode is active |
```

with:

```
| `ignore_events` | table | `{"WinScrolled", "CursorMoved", "CursorMovedI"}` | Events appended to `'eventignore'` while intermediate animation frames apply (restored after each frame; the final frame is never suppressed). Also queryable via `should_ignore_event()` while performance mode is active |
```

and add `performance.suppress_events()   -- append ignore_events to 'eventignore'; returns the saved value` and `performance.restore_events(saved)   -- restore a value returned by suppress_events()` to the performance module code block.

In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/docs/ARCHITECTURE.md`, replace the bullet:

```
- Populates a passive lookup table of ignored events (default: `WinScrolled`, `CursorMoved`, `CursorMovedI`). Callers check `should_ignore_event(event)` to decide whether to skip logic — no autocmds are registered to intercept events.
```

with:

```
- Suppresses the configured `ignore_events` (default: `WinScrolled`, `CursorMoved`, `CursorMovedI`) by appending them to `'eventignore'` around every intermediate frame's trait application (`suppress_events()`/`restore_events()`, called by the engine loop); the final frame always applies unsuppressed. This wiring is independent of performance mode being active. `should_ignore_event(event)` additionally exposes the list as a passive lookup while performance mode is active.
```

- [ ] Headless verification (mandatory). From the repo root:

```bash
nvim --headless --clean --cmd "set rtp+=$PWD" -c 'lua require("whisk").setup({}) local lines = {} for i = 1, 100 do lines[i] = "line " .. i end vim.api.nvim_buf_set_lines(0, 0, -1, false, lines) vim.api.nvim_win_set_cursor(0, {1, 0}) local moved = 0 vim.api.nvim_create_autocmd("CursorMoved", { callback = function() moved = moved + 1 end }) require("whisk.engine.orchestrator").execute("basic_j", { count = 5, direction = "j" }) vim.wait(500, function() return false end) local line = vim.api.nvim_win_get_cursor(0)[1] print(string.format("RESULT line=%d moved=%d ok=%s", line, moved, tostring(line == 6 and moved <= 2)))' -c 'qa!'
```

Expected output line: `RESULT line=6 moved=1 ok=true` (moved may be 2 depending on timer batching; `ok=true` is the requirement — before this task the same probe reports `moved` around 4-6). If the Wave 3 integration tier's harness accommodates this probe as a spec, add it there in this commit; otherwise paste the output line into the commit message body.

- [ ] Run `bash scripts/run_tests.sh` one final time and confirm zero failures.
- [ ] Commit:

```
git add lua/whisk/performance.lua lua/whisk/engine/loop.lua tests/mocks/vim_core.lua tests/unit/performance_spec.lua tests/unit/engine/loop_spec.lua README.md docs/USAGE.md docs/ARCHITECTURE.md
git commit -m "feat(performance): suppress configured events during intermediate frames"
```

---
### Task 8: Scope animating state and domination per window (#37)

Trait animating state is a global per-trait boolean, and domination calls `loop.complete_all()`, so a motion in window B force-snaps an in-flight animation in window A when both show the same buffer (no `BufLeave` fires between same-buffer splits). Key the state per `(trait_id, winid)`, make the orchestrator check the CURRENT window's traits, and dominate via a new `loop.complete_for_window(winid)` that completes-at-target only that window's animations. `loop.complete_all()` remains exported for whole-editor sweeps (`whisk.reset()` paths and any Wave 2 on_key guard). This changes public registry function signatures — the old-to-new mapping is pinned in the Interfaces block below.

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/registry/traits.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/orchestrator.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_api.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/init.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/README.md`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/docs/ARCHITECTURE.md`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/registry/traits_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/orchestrator_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`

**Interfaces (public signature change — old to new):**
- OLD `traits.is_animating(trait_id) -> boolean` → NEW `traits.is_animating(trait_id, winid) -> boolean`.
- OLD `traits.set_animating(trait_id, value)` → NEW `traits.set_animating(trait_id, winid, value)` (`value == false` deletes the window key so closed windows do not accumulate).
- NEW `loop.complete_for_window(winid)` — completes-at-target (final frame + `on_complete`, no suppression) every queued animation whose `context.winid == winid`, removes them from the queue, sets `is_running = false` only when the queue empties.
- UNCHANGED `loop.complete_all()` — retained for whole-editor reset/on_key sweeps; now shares the `finish_animation(anim)` internal helper with `complete_for_window`.
- Orchestrator: domination checks `traits.is_animating(trait_id, vim.api.nvim_get_current_win())` and calls `loop.complete_for_window(current_winid)`; animating flags are set/cleared with `context.winid`; `loop.start` receives an `on_cancel` that clears the same per-window flags.
- Produces (test infrastructure): mock `vim_api` gains `state.current_window` (default 1000), `nvim_get_current_win` returns it, and `mocks.set_current_window(winid)` sets it.

**Steps:**

- [ ] Add current-window control to the mocks. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/vim_api.lua`, add `current_window = 1000,` to BOTH state-table literals (module-level and inside `M.reset()`). Change the `nvim_get_current_win` mock to `return state.current_window`. Add this module function after `M.set_window_buffer`:

```lua
function M.set_current_window(winid)
  state.current_window = winid
end
```

In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/mocks/init.lua`, add after `M.set_window_buffer`:

```lua
function M.set_current_window(winid)
  vim_api.set_current_window(winid)
end
```

- [ ] Write the failing registry tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/registry/traits_spec.lua`, REPLACE the six animating-state tests with the window-scoped versions below, and ADD the two new tests at the end. Replacements:

```lua
  it('is_animating returns false initially', function()
    traits.register({
      id = 'cursor',
      apply = function() end,
    })

    assert.is_false(traits.is_animating('cursor', 1000))
  end)

  it('set_animating updates animating state', function()
    traits.register({
      id = 'cursor',
      apply = function() end,
    })

    traits.set_animating('cursor', 1000, true)
    assert.is_true(traits.is_animating('cursor', 1000))

    traits.set_animating('cursor', 1000, false)
    assert.is_false(traits.is_animating('cursor', 1000))
  end)

  it('is_animating returns false for unregistered trait', function()
    assert.is_false(traits.is_animating('nonexistent', 1000))
  end)

  it('reset clears all animating states', function()
    traits.register({ id = 'cursor', apply = function() end })
    traits.register({ id = 'scroll', apply = function() end })

    traits.set_animating('cursor', 1000, true)
    traits.set_animating('scroll', 1001, true)

    traits.reset()

    assert.is_false(traits.is_animating('cursor', 1000))
    assert.is_false(traits.is_animating('scroll', 1001))
  end)

  it('clear removes all traits and states', function()
    traits.register({ id = 'trait1', apply = function() end })
    traits.set_animating('trait1', 1000, true)

    traits.clear()

    assert.is_nil(traits.get('trait1'))
    assert.is_false(traits.is_animating('trait1', 1000))
  end)

  it('multiple traits can have independent states', function()
    traits.register({ id = 'cursor', apply = function() end })
    traits.register({ id = 'scroll', apply = function() end })

    traits.set_animating('cursor', 1000, true)
    traits.set_animating('scroll', 1000, false)

    assert.is_true(traits.is_animating('cursor', 1000))
    assert.is_false(traits.is_animating('scroll', 1000))

    traits.set_animating('cursor', 1000, false)
    traits.set_animating('scroll', 1000, true)

    assert.is_false(traits.is_animating('cursor', 1000))
    assert.is_true(traits.is_animating('scroll', 1000))
  end)
```

Additions:

```lua
  it('animating state is scoped per window', function()
    traits.register({ id = 'cursor', apply = function() end })

    traits.set_animating('cursor', 1000, true)

    assert.is_true(traits.is_animating('cursor', 1000))
    assert.is_false(traits.is_animating('cursor', 1001))
  end)

  it('set_animating false clears only the given window', function()
    traits.register({ id = 'cursor', apply = function() end })

    traits.set_animating('cursor', 1000, true)
    traits.set_animating('cursor', 1001, true)
    traits.set_animating('cursor', 1000, false)

    assert.is_false(traits.is_animating('cursor', 1000))
    assert.is_true(traits.is_animating('cursor', 1001))
  end)
```

- [ ] Write the failing loop tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`, append inside the describe block:

```lua
  it('exports complete_for_window function', function()
    assert.is_type(loop.complete_for_window, 'function')
  end)

  it('complete_for_window completes only animations for the given window', function()
    local completed_a = false
    local completed_b = false

    loop.start({
      duration = 150,
      easing = 'linear',
      context = { bufnr = 1, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
      on_complete = function() completed_a = true end,
    })

    loop.start({
      duration = 150,
      easing = 'linear',
      context = { bufnr = 1, winid = 1001, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
      on_complete = function() completed_b = true end,
    })

    assert.equals(loop.get_active_count(), 2)
    loop.complete_for_window(1000)
    assert.is_true(completed_a)
    assert.is_false(completed_b)
    assert.equals(loop.get_active_count(), 1)
    assert.is_true(loop.is_running())

    loop.complete_for_window(1001)
    assert.is_true(completed_b)
    assert.equals(loop.get_active_count(), 0)
    assert.is_false(loop.is_running())
  end)

  it('complete_for_window applies the final frame for the target window', function()
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
      context = { winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
    })

    loop.complete_for_window(1000)

    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 5)
    assert.equals(cursor[2], 0)
  end)
```

- [ ] Write the failing orchestrator tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/orchestrator_spec.lua`, REPLACE the test `it('execute marks traits as animating', ...)` with:

```lua
  it('execute marks traits as animating for the context window', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })
    assert.is_true(traits.is_animating('cursor', 1000))
    assert.is_false(traits.is_animating('cursor', 1001))
  end)
```

and append these two tests:

```lua
  it('a motion in another window does not dominate animations elsewhere', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })
    assert.equals(loop.get_active_count(), 1)

    mocks.set_current_window(1001)
    orchestrator.execute('test_j', { count = 1 })

    assert.equals(loop.get_active_count(), 2)
    assert.is_true(traits.is_animating('cursor', 1000))
    assert.is_true(traits.is_animating('cursor', 1001))
  end)

  it('cancelling animations clears animating state for the window', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    orchestrator.execute('test_j', { count = 1 })
    assert.is_true(traits.is_animating('cursor', 1000))

    loop.cancel_for_window(1000)
    assert.is_false(traits.is_animating('cursor', 1000))
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the replaced/new tests fail: the traits tests fail because the old `set_animating(trait_id, value)` stores `1000` as the value and `is_animating` compares `== true`; the loop tests fail with `attempt to call field 'complete_for_window' (a nil value)`; the orchestrator tests fail on the two-argument `is_animating`.
- [ ] Implement the window-scoped registry. Replace the ENTIRE contents of `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/registry/traits.lua` with:

```lua
local M = {}

local traits = {}
local state = {}

function M.register(definition)
  local id = definition.id
  traits[id] = {
    id = id,
    apply = definition.apply,
    on_start = definition.on_start,
    on_complete = definition.on_complete,
  }
  state[id] = {}
end

function M.is_animating(trait_id, winid)
  local windows = state[trait_id]
  if not windows then
    return false
  end
  return windows[winid] == true
end

function M.set_animating(trait_id, winid, value)
  local windows = state[trait_id]
  if not windows then
    windows = {}
    state[trait_id] = windows
  end
  if value then
    windows[winid] = true
  else
    windows[winid] = nil
  end
end

function M.get(trait_id)
  return traits[trait_id]
end

function M.apply_frame(trait_id, context, result, progress)
  local trait = traits[trait_id]
  if trait and trait.apply then
    trait.apply(context, result, progress)
  end
end

function M.all()
  return traits
end

function M.reset()
  for id in pairs(state) do
    state[id] = {}
  end
end

function M.clear()
  traits = {}
  state = {}
end

return M
```

- [ ] Implement `complete_for_window`. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`, replace `M.complete_all` with the factored pair:

```lua
local function finish_animation(anim)
  local eased_final = anim.easing_fn(1.0)
  local final = interpolate_result(anim, eased_final)
  attach_frame_cache(anim.context)
  apply_traits(anim, final, eased_final)
  if anim.on_complete then
    anim.on_complete()
  end
end

function M.complete_all()
  reset_frame_cache()
  for _, anim in ipairs(frame_queue) do
    finish_animation(anim)
    pool.release(anim)
  end
  frame_queue = {}
  is_running = false
end

function M.complete_for_window(winid)
  reset_frame_cache()
  for i = #frame_queue, 1, -1 do
    local anim = frame_queue[i]
    if anim.context.winid == winid then
      finish_animation(anim)
      table.remove(frame_queue, i)
      pool.release(anim)
    end
  end

  if #frame_queue == 0 then
    is_running = false
  end
end
```

(`finish_animation` must be declared before `M.complete_all`; place it with the other local functions.)

- [ ] Update the orchestrator. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/orchestrator.lua`, replace the domination block (at 852b689 it read `local dominated = false ... loop.complete_all() end`) with:

```lua
  local current_winid = vim.api.nvim_get_current_win()

  local dominated = false
  for _, trait_id in ipairs(motion.traits) do
    if traits.is_animating(trait_id, current_winid) then
      dominated = true
    end
  end

  if dominated then
    loop.complete_for_window(current_winid)
  end
```

Replace the animating-flag block and the `loop.start` call so the flags are keyed by `context.winid` and cleared on both completion and cancellation (preserve any additional `loop.start` options or surrounding logic added by Waves 1-2, such as the jump-flag push or `should_skip_animation`; if an `on_cancel` closure already exists from a prior wave, merge this flag-clearing into its body):

```lua
  for _, trait_id in ipairs(motion.traits) do
    traits.set_animating(trait_id, context.winid, true)
  end

  loop.start({
    context = context,
    result = result,
    traits = motion.traits,
    duration = category_config.duration,
    easing = category_config.easing,
    on_complete = function()
      for _, trait_id in ipairs(motion.traits) do
        traits.set_animating(trait_id, context.winid, false)
      end
    end,
    on_cancel = function()
      for _, trait_id in ipairs(motion.traits) do
        traits.set_animating(trait_id, context.winid, false)
      end
    end,
  })
```

- [ ] Verify no stale call sites remain: `grep -rn "is_animating\|set_animating" lua/ tests/` must show only the new arities (definitions in `traits.lua`, three-argument `set_animating` and two-argument `is_animating` everywhere else), and `grep -rn "complete_all" lua/` must show only `loop.lua`'s definition plus any whole-editor sweep callers from prior waves (e.g. an on_key guard) — the orchestrator domination site must be the only caller converted to `complete_for_window`.
- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures (the pre-existing key-repeat domination test passes because the mock's current window and the built context's winid are both 1000).
- [ ] Update the docs. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/README.md`, replace the Behavior notes bullet:

```
- When a new motion starts while any of its traits are already animating, **all** active animations complete instantly at their final positions before the new animation begins (domination).
```

with:

```
- When a new motion starts in a window where any of its traits are already animating, that window's active animations complete instantly at their final positions before the new animation begins (domination). Animations in other windows are unaffected.
```

In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/docs/ARCHITECTURE.md`, make the matching updates (locate each by the quoted content, which may have drifted slightly since 852b689):
  - Replace `3. If any of the motion's traits are already animating, all active animations complete instantly at their final positions (domination).` with `3. If any of the motion's traits are already animating in the current window, that window's active animations complete instantly at their final positions (domination).`
  - Replace `3. Check if any of the motion's traits are currently animating. If so, call ` + "`loop.complete_all()`" + ` to snap **all** active animations to their final positions (domination). The check is per-trait, but the effect is global.` with `3. Check if any of the motion's traits are currently animating in the current window. If so, call ` + "`loop.complete_for_window(winid)`" + ` to snap that window's active animations to their final positions (domination). Both the check and the effect are scoped per window.`
  - After the table row for `complete_all()`, add a row: `| complete_for_window(winid) | Snaps that window's animations to their final positions and fires on_complete (domination) |`
  - Replace `Traits also track per-trait animation state to enable domination (preventing overlapping animations of the same type).` with `Traits also track per-trait, per-window animation state (keyed by (trait_id, winid)) to enable domination without cross-window side effects.`
- [ ] Run `bash scripts/run_tests.sh` one final time and confirm zero failures.
- [ ] Commit:

```
git add lua/whisk/registry/traits.lua lua/whisk/engine/loop.lua lua/whisk/engine/orchestrator.lua tests/mocks/vim_api.lua tests/mocks/init.lua tests/unit/registry/traits_spec.lua tests/unit/engine/orchestrator_spec.lua tests/unit/engine/loop_spec.lua README.md docs/ARCHITECTURE.md
git commit -m "feat(engine): scope animating state and domination per window"
```

---

### Task 9: Move context validity checks to the callers (#31)

Each frame validates `context:is_valid()` in the loop, then `set_cursor`/`set_topline`/`restore_view` each re-validate internally — 2-3 redundant triples of `nvim_buf_is_valid`/`nvim_win_is_valid`/`nvim_win_get_buf` per frame (~84 wasted API calls per ctrl_d). The loop's per-animation-per-frame check becomes the single source of truth: the three Context write methods drop their internal `is_valid` calls and adopt a caller-validates contract (pinned with LuaCATS annotations). Every production caller is audited to validate: the frame path already does; the completion sweeps (`complete_all`/`complete_for_window`) gain an explicit guard because the internal check was previously their ONLY guard; the orchestrator's Wave 2 synchronous-apply path gains an explicit guard; lifecycle handlers only cancel and never apply traits, so they need none.

**Caller audit (verify each row during this task):**

| Production caller | Path to a Context write | Validation |
|---|---|---|
| `loop.process_frame` | trait `apply` → `set_cursor`/`set_topline` | validates once per animation per frame at the top of the anim loop; cancels invalid animations before any apply |
| `loop.complete_all` / `loop.complete_for_window` | `finish_animation` → trait `apply` | explicit `is_valid()` guard added in this task; skips trait application but still fires `on_complete` (preserves the pre-change observable behavior where the internal check silently no-opped the write) |
| `engine/orchestrator` synchronous skip path (Wave 2 `should_skip_animation`) | direct `traits.apply_frame(..., result, 1.0)` | context is built from live state in the same tick; explicit `context:is_valid()` guard added in this task per the contract |
| `engine/lifecycle` | none — `BufDelete`/`WinClosed`/`BufLeave` only call `loop.cancel_for_*`, which never applies traits | no guard needed (verified by reading `lifecycle.lua`) |

**Files:**
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/context/Context.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`
- Modify: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/orchestrator.lua` (only if a synchronous apply path exists from Wave 2)
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/context/Context_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/registry/builtin_spec.lua`
- Test: `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`

**Interfaces:**
- Produces (contract change): `Context:set_cursor(line, col) -> true`, `Context:set_topline(topline) -> true`, `Context:restore_view(topline, line, col) -> true` — none validates internally any longer and none returns a `reason`; callers MUST validate with `Context:is_valid()` before invoking. The contract is pinned with LuaCATS annotations on all three methods (explicitly called for by this task). `restore_view` has no production caller after Task 2 but remains public API under the same contract.
- Produces (loop-internal): `finish_animation` validates before applying and still fires `on_complete` for invalid contexts.

**Steps:**

- [ ] Write the failing contract tests. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/context/Context_spec.lua`, append inside the describe block:

```lua
  it('set_cursor() trusts caller validation and applies without an internal check', function()
    local ctx = Context.new(1, 1000)
    mocks.delete_buffer(1)
    local success = ctx:set_cursor(3, 2)
    assert.is_true(success)
    assert.equals(mocks.get_cursor()[1], 3)
  end)

  it('set_topline() trusts caller validation and applies without an internal check', function()
    local ctx = Context.new(1, 1000)
    mocks.delete_buffer(1)
    local success = ctx:set_topline(3)
    assert.is_true(success)
    assert.equals(mocks.get_fn_state().topline, 3)
  end)

  it('restore_view() trusts caller validation and applies without an internal check', function()
    local ctx = Context.new(1, 1000)
    mocks.close_window(1000)
    local success = ctx:restore_view(2, 3, 1)
    assert.is_true(success)
    assert.equals(mocks.get_fn_state().topline, 2)
  end)
```

In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/engine/loop_spec.lua`, append inside the describe block:

```lua
  it('complete_all skips trait application for an invalid context but still calls on_complete', function()
    local Context = require('whisk.context.Context')
    local traits = require('whisk.registry.traits')
    local applied = false
    traits.register({
      id = 'cursor',
      apply = function() applied = true end,
    })

    local ctx = Context.new(1, 1000)
    ctx.cursor = { line = 1, col = 0 }
    local completed = false

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = ctx,
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
      on_complete = function() completed = true end,
    })

    mocks.delete_buffer(1)
    loop.complete_all()

    assert.is_false(applied)
    assert.is_true(completed)
    assert.equals(loop.get_active_count(), 0)
  end)

  it('complete_for_window skips trait application for an invalid context but still calls on_complete', function()
    local Context = require('whisk.context.Context')
    local traits = require('whisk.registry.traits')
    local applied = false
    traits.register({
      id = 'cursor',
      apply = function() applied = true end,
    })

    local ctx = Context.new(1, 1000)
    ctx.cursor = { line = 1, col = 0 }
    local completed = false

    loop.start({
      duration = 100000,
      easing = 'linear',
      context = ctx,
      result = { cursor = { line = 5, col = 0 } },
      traits = { 'cursor' },
      on_complete = function() completed = true end,
    })

    mocks.delete_buffer(1)
    loop.complete_for_window(1000)

    assert.is_false(applied)
    assert.is_true(completed)
    assert.equals(loop.get_active_count(), 0)
  end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the three Context tests fail (`Expected: true / Actual: false` — the internal checks still refuse) and both loop tests fail on `assert.is_false(applied)` (the trait apply function currently runs and only the write inside it is refused).
- [ ] Strip the internal checks and pin the contract. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/context/Context.lua`, replace `Context:set_cursor`, `Context:restore_view`, and `Context:set_topline` with (LuaCATS annotations are explicitly called for here):

```lua
--- Positions the cursor in the context window.
--- Callers own context validation: call is_valid() before invoking.
---@param line number
---@param col number
---@return boolean
function Context:set_cursor(line, col)
  local clamped_line, clamped_col = self:clamp_position(line, col)
  vim.api.nvim_win_set_cursor(self.winid, { clamped_line, clamped_col })
  return true
end

--- Restores topline, cursor line, and cursor column in the context window.
--- Callers own context validation: call is_valid() before invoking.
---@param topline number
---@param line number
---@param col number
---@return boolean
function Context:restore_view(topline, line, col)
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
end

--- Restores only the topline in the context window; never writes lnum/col.
--- Callers own context validation: call is_valid() before invoking.
---@param topline number
---@return boolean
function Context:set_topline(topline)
  local clamped_topline = self:clamp_line(topline)

  vim.api.nvim_win_call(self.winid, function()
    vim.fn.winrestview({ topline = clamped_topline })
  end)
  return true
end
```

- [ ] Guard the completion sweeps. In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/loop.lua`, replace `finish_animation`:

```lua
local function finish_animation(anim)
  local valid = true
  if anim.context.is_valid then
    valid = anim.context:is_valid()
  end
  if valid then
    local eased_final = anim.easing_fn(1.0)
    local final = interpolate_result(anim, eased_final)
    attach_frame_cache(anim.context)
    apply_traits(anim, final, eased_final)
  end
  if anim.on_complete then
    anim.on_complete()
  end
end
```

- [ ] Guard the orchestrator's synchronous path. Run `grep -n "apply_frame" /Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/engine/orchestrator.lua`. If Wave 2's `should_skip_animation` path applies the result synchronously through `traits.apply_frame`, wrap that application (and only it) in a validity check so it reads:

```lua
    if context:is_valid() then
      for _, trait_id in ipairs(motion.traits) do
        traits.apply_frame(trait_id, context, result, 1.0)
      end
    end
```

If the grep finds no synchronous apply site in `orchestrator.lua`, make no orchestrator change and state `no synchronous apply path present in orchestrator.lua` in the commit message body. The mock harness cannot drive this path deterministically (it depends on Wave 2's `vim.fn.reg_executing` wiring), so its verification is the headless macro probe below plus the wave review reading the diff.

- [ ] Remove the tests that encode the old self-validating contract, each replaced by the new contract/guard tests added above:
  - In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/context/Context_spec.lua`, delete: `it('set_cursor() returns false with reason if context invalid', ...)`, `it('set_cursor() does not modify cursor if context invalid', ...)`, `it('restore_view() returns false with reason if context invalid', ...)`, and `it('set_topline() returns false with reason if context invalid', ...)` (added in Task 2).
  - In `/Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/tests/unit/registry/builtin_spec.lua`, delete: `it('cursor trait does not set cursor when context is invalid', ...)` (the trait is no longer the validator; the frame-path guarantee is covered by the pre-existing integration test `animation cancels when buffer is deleted mid-animation` and the two new completion-sweep tests).
- [ ] Run `bash scripts/run_tests.sh` and confirm zero failures.
- [ ] Verify the audit table. Run `grep -rn "set_cursor\|set_topline\|restore_view" /Users/josstei/Development/nvim-workspace/plugins/whisk.nvim/lua/whisk/` and confirm the only production callers of the three Context write methods are the two trait apply functions in `registry/builtin.lua` (reached exclusively through the validated loop paths) and, if present, calculator-internal API usage that operates on the live window rather than a Context (e.g. `native.lua`, which uses raw `vim.api`/`vim.fn` and is unaffected by this contract). Confirm `lifecycle.lua` still only calls `loop.cancel_for_buffer`/`loop.cancel_for_window`.
- [ ] Headless verification (mandatory). From the repo root, exercise the synchronous macro path end-to-end:

```bash
nvim --headless --clean --cmd "set rtp+=$PWD" -c 'lua require("whisk").setup({})' -c 'call setline(1, range(1, 50))' -c 'call setreg("q", "5j")' -c 'normal! @q' -c 'lua print(string.format("RESULT line=%d", vim.api.nvim_win_get_cursor(0)[1]))' -c 'qa!'
```

Expected output line: `RESULT line=6` (the macro executes the motion through Wave 2's synchronous skip path; the guarded apply must still land the cursor). Paste the output line into the commit message body if not ported as an integration spec.

- [ ] Commit:

```
git add lua/whisk/context/Context.lua lua/whisk/engine/loop.lua lua/whisk/engine/orchestrator.lua tests/unit/context/Context_spec.lua tests/unit/registry/builtin_spec.lua tests/unit/engine/loop_spec.lua
git commit -m "perf(context): move validity checks to callers"
```

(Include `lua/whisk/engine/orchestrator.lua` in the add only if it was modified.)

---

## Wave completion checklist

- [ ] `bash scripts/run_tests.sh` — zero failures.
- [ ] Wave 3 integration tier and CI green (run the workflow's local equivalent from `.github/workflows/`).
- [ ] Re-run every headless probe from Tasks 2, 7, and 9 against the branch tip; all `RESULT ... ok=true` / expected lines reproduce.
- [ ] Findings-to-diff spot check for the Fable wave review: #35 → `calculators/native.lua` + `native_spec.lua`; #29 → `Context.lua`/`builtin.lua`; #30 → `pool.lua`/`loop.lua`; #15 → `loop.lua` dedupe block; #32 → `frame_cache`; #33 → `next_frame_delay`; #16 → `performance.lua` + loop wiring + README/USAGE/ARCHITECTURE; #37 → `traits.lua`/`orchestrator.lua`/`complete_for_window`; #31 → `Context.lua` LuaCATS contract + `finish_animation` guard + caller audit.
- [ ] Open the PR to `main`: title `Wave 4: Engine Internals`, body lists the nine findings, links this plan, and summarizes the Fable review outcome. No AI attribution.
