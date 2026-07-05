# Wave 6: Feature Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship whisk.nvim's differentiating feature set on the now-correct base: observable animation lifecycle events, skip predicates, a public `animate_to` API, the missing motion groups (H/M/L, `*`/`#`, marks, `<C-e>`/`<C-y>`, horizontal scroll), custom easing functions, proportional duration, and per-motion overrides.

**Architecture:** Config plumbing lands first because three findings share one validation surface: the easing set/function pass-through (#24), the duration spec resolver in a new `engine/duration.lua` (#42), and per-motion overrides under a new top-level `motions` config table (#43). The exclusion predicates (#21) are deliberately **top-level** (`exclude = { buftypes, filetypes }`, `min_distance`) rather than per-category: buffer exclusion is a property of the buffer/window a motion runs in, not of the cursor-vs-scroll category — a `:terminal` buffer should suppress both categories at once, and duplicating the lists per category would force users to keep two copies in sync; `keymaps` and `performance` establish precedent for cross-cutting top-level keys. New motions reuse the existing calculator patterns (direct math in a new `calculators/screen.lua`, native delegation through Wave 2's `calculators/native.lua`, scroll math in `calculators/scroll.lua`), horizontal scroll threads `leftcol` through the existing snapshot → interpolate → `restore_view` path, and User events land last because they observe every path built before them.

**Tech Stack:** Lua 5.1+ (Neovim runtime), plain-Lua unit test harness (tests/), headless Neovim probes for behavior the mocks cannot exercise.

**Findings covered:**
- `#19` — Emit `User` autocmd events (`WhiskAnimationStart`/`WhiskAnimationComplete`/`WhiskAnimationCancel`) and wire the dead trait `on_start`/`on_complete` hooks.
- `#21` — Skip-animation predicates: `exclude.buftypes`/`exclude.filetypes`, `min_distance`, and `b:whisk_disable`/`g:whisk_disable`, wired into the Wave 2 `should_skip_animation` seam (skipped motions apply synchronously).
- `#22` — Public `whisk.animate_to(opts)` API so other plugins can request an animated jump to an arbitrary `{line, col}`.
- `#23` — Missing motions: `H`/`M`/`L` (screen math), `*`/`#` (native delegation, jump), backtick/quote mark jumps (char input, native delegation, jump, in-buffer only), `<C-e>`/`<C-y>` (scroll math with scrolloff pull).
- `#24` — `easing` accepts a `function(t) -> number` or a name; named set extended with `quadratic`, `cubic`, `quartic`, `quintic`, `circular`, `sine`.
- `#42` — Optional proportional duration: `duration = { min, max, per_line }` resolved from travel distance in a new `engine/duration.lua`.
- `#43` — Per-motion overrides: `motions = { [motion_id] = { duration, easing } }`, resolved as category config < per-motion user config.
- `#44` — Horizontal scroll: `viewport.leftcol` becomes animatable end to end; new `zh`/`zl`/`zH`/`zL` scroll motions that return nil under `'wrap'`.

## Execution Model

- Branch: `audit/wave-6-features`, created from `main` (after the previous wave's PR has merged; Wave 1 branches from current main).
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

### Wave 6 working notes (read before any task)

- **Post-Wave-5 baseline.** This branch starts after Waves 1–5 merged. The following pinned contracts exist and are used below: `input.has_count` (Wave 1), `lua/whisk/calculators/native.lua` with `M.calculate(motion_cmd, context, opts)` (Wave 2), `jump = true` motion flag + orchestrator `m'` jumplist push (Wave 2), a private `should_skip_animation` seam in `engine/orchestrator.lua` whose true-branch applies the calculator result synchronously through the motion's traits at progress 1.0 (Wave 2), registry validation/unregister (Wave 5), per-(trait, winid) animating state on `registry/traits.lua` (Wave 4/5), the headless integration tier under `tests/nvim/specs/` (Wave 3), and `doc/whisk.txt` vimdoc (Wave 5). Where a task edits code introduced by an earlier wave, it anchors by function name and shows the complete replacement body; keep any earlier-wave logic the task explicitly says to preserve.
- **Per-(trait, winid) animating state call shape.** Tasks below write `traits.is_animating(trait_id, winid)` / `traits.set_animating(trait_id, winid, value)`. If the merged Wave 4/5 code orders these parameters differently, mirror the exact call shape `orchestrator.execute` uses on the branch — the requirement is that animate_to scopes animating state to its target window exactly like the orchestrator does.
- **`native.calculate` opts.** Wave 2's landed opts shape is `{ char = string|nil, include_count = boolean|nil }` (count included by default). Tasks below pass `{ include_count = false }` to suppress the `context.input.count` prefix on the delegated command; the observable requirement is stated in each step (the executed command must be exactly the string shown, with no count prefix).
- **Leftcol plumbing (reconciled against Waves 2 and 4).** Wave 2 kept `Context:restore_view(topline, line, col)` unchanged, reading leftcol from `self.viewport.leftcol`; Wave 4 then made the scroll trait topline-only via `Context:set_topline(topline)` with the cursor trait as the sole cursor writer. Task 8 therefore threads the interpolated leftcol by extending `set_topline` to `set_topline(topline, leftcol)` (nil = preserve the window's current leftcol) — it does NOT add a fourth `restore_view` parameter.
- **Headless probe specs.** Files under `tests/nvim/specs/` in this plan are standalone scripts: they run inside a real Neovim via `nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/<name>_spec.lua" +"qa!"` from the repo root, print `OK: ...` lines, print `SPEC PASS: <name>` on success, and exit non-zero via `cquit! 1` on failure. If the Wave 3 tier's runner auto-discovers `tests/nvim/specs/*_spec.lua`, these files are picked up unchanged; each is also directly runnable with the exact command given in its step.
- **`doc/whisk.txt` edits**: insert each help block where the step says (config section for config keys, or immediately above the trailing modeline for new sections), keeping the file's existing tag style. Regenerate helptags only if the repo's docs tooling does so; committing the text change is sufficient.

---

### Task 1: Custom easing functions and extended named easing set (#24)

**Files:**
- Modify: `lua/whisk/engine/loop.lua`
- Modify: `lua/whisk/config/validation.lua`
- Test: `tests/unit/engine/loop_spec.lua`, `tests/unit/config/validation_spec.lua`

**Interfaces:**
- Consumes: `loop.get_easing(easing_type)` (existing).
- Produces: `loop.get_easing(easing_type: string|fun(t: number): number): fun(t: number): number` — passes functions through unchanged; resolves the 10-name set `linear`, `ease-in`, `ease-out`, `ease-in-out`, `quadratic`, `cubic`, `quartic`, `quintic`, `circular`, `sine`; falls back to linear. Local `validate_easing(value, path)` in `validation.lua` — accepted by Tasks 3 and 9 as the single easing-shape validator.

**Steps:**

- [ ] Append this suite to the end of `tests/unit/engine/loop_spec.lua`:

```lua
describe('engine/loop easing extensions', function()
  local loop

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    loop = require('whisk.engine.loop')
    loop.stop_all()
  end)

  it('get_easing passes a function through unchanged', function()
    local custom = function(t) return t * t * t end
    assert.equals(loop.get_easing(custom), custom)
  end)

  it('quadratic matches 1 - (1 - t)^2', function()
    local fn = loop.get_easing('quadratic')
    assert.equals(fn(0), 0)
    assert.equals(fn(1), 1)
    assert.equals(fn(0.5), 0.75)
  end)

  it('cubic matches 1 - (1 - t)^3', function()
    local fn = loop.get_easing('cubic')
    assert.equals(fn(0), 0)
    assert.equals(fn(1), 1)
    assert.equals(fn(0.5), 0.875)
  end)

  it('quartic matches 1 - (1 - t)^4', function()
    local fn = loop.get_easing('quartic')
    assert.equals(fn(0.5), 0.9375)
  end)

  it('quintic matches 1 - (1 - t)^5', function()
    local fn = loop.get_easing('quintic')
    assert.equals(fn(0.5), 0.96875)
  end)

  it('circular matches sqrt(1 - (1 - t)^2)', function()
    local fn = loop.get_easing('circular')
    assert.equals(fn(0), 0)
    assert.equals(fn(1), 1)
    assert.less_than(math.abs(fn(0.5) - math.sqrt(0.75)), 1e-9)
  end)

  it('sine matches sin(t * pi / 2)', function()
    local fn = loop.get_easing('sine')
    assert.equals(fn(0), 0)
    assert.less_than(math.abs(fn(0.5) - math.sin(0.25 * math.pi)), 1e-9)
    assert.less_than(math.abs(fn(1) - 1), 1e-9)
  end)

  it('existing four names keep working', function()
    for _, name in ipairs({ 'linear', 'ease-in', 'ease-out', 'ease-in-out' }) do
      local fn = loop.get_easing(name)
      assert.is_type(fn, 'function')
      assert.equals(fn(0), 0)
      assert.equals(fn(1), 1)
    end
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/config/validation_spec.lua`:

```lua
describe('config/validation easing extensions', function()
  local validation

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    validation = require('whisk.config.validation')
  end)

  it('accepts the extended named easing set for cursor and scroll', function()
    for _, name in ipairs({ 'quadratic', 'cubic', 'quartic', 'quintic', 'circular', 'sine' }) do
      assert.does_not_throw(function()
        validation.validate_config({ cursor = { easing = name }, scroll = { easing = name } })
      end)
    end
  end)

  it('accepts an easing function for cursor', function()
    assert.does_not_throw(function()
      validation.validate_config({ cursor = { easing = function(t) return t end } })
    end)
  end)

  it('accepts an easing function for scroll', function()
    assert.does_not_throw(function()
      validation.validate_config({ scroll = { easing = function(t) return t * t end } })
    end)
  end)

  it('still rejects unknown easing names', function()
    assert.throws(function()
      validation.validate_config({ cursor = { easing = 'bounce' } })
    end, 'easing')
  end)

  it('still rejects non-string non-function easing values', function()
    assert.throws(function()
      validation.validate_config({ scroll = { easing = 123 } })
    end, 'easing')
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the new tests fail: `quadratic`/`cubic`/`quartic`/`quintic`/`circular`/`sine` resolve to linear (`fn(0.5)` returns `0.5`, not the curve values), `get_easing` does not return the custom function identity, and validation throws on function easing and the six new names.
- [ ] In `lua/whisk/engine/loop.lua`, replace the `easing_functions` table with (formulas are the standard ease-out family: quadratic `1-(1-t)^2`, cubic `1-(1-t)^3`, quartic `1-(1-t)^4`, quintic `1-(1-t)^5`, circular `sqrt(1-(1-t)^2)`, sine `sin(t*pi/2)`):

```lua
local easing_functions = {
  linear = function(t) return t end,
  ["ease-in"] = function(t) return t * t end,
  ["ease-out"] = function(t) return 1 - (1 - t) * (1 - t) end,
  ["ease-in-out"] = function(t)
    if t < 0.5 then
      return 2 * t * t
    else
      return 1 - 2 * (1 - t) * (1 - t)
    end
  end,
  quadratic = function(t) return 1 - (1 - t) ^ 2 end,
  cubic = function(t) return 1 - (1 - t) ^ 3 end,
  quartic = function(t) return 1 - (1 - t) ^ 4 end,
  quintic = function(t) return 1 - (1 - t) ^ 5 end,
  circular = function(t) return math.sqrt(1 - (1 - t) ^ 2) end,
  sine = function(t) return math.sin(t * math.pi / 2) end,
}
```

- [ ] In the same file, replace the body of `M.get_easing` with:

```lua
function M.get_easing(easing_type)
  if type(easing_type) == "function" then
    return easing_type
  end
  return easing_functions[easing_type] or easing_functions.linear
end
```

- [ ] In `lua/whisk/config/validation.lua`, replace the `valid_easing_types` table and add the shared validator directly below it:

```lua
local valid_easing_types = {
  ["linear"] = true,
  ["ease-in"] = true,
  ["ease-out"] = true,
  ["ease-in-out"] = true,
  ["quadratic"] = true,
  ["cubic"] = true,
  ["quartic"] = true,
  ["quintic"] = true,
  ["circular"] = true,
  ["sine"] = true,
}

local function validate_easing(value, path)
  if value == nil then
    return
  end
  if type(value) == "function" then
    return
  end
  if type(value) ~= "string" or not valid_easing_types[value] then
    error(path .. " easing must be a function or one of: linear, ease-in, ease-out, ease-in-out, quadratic, cubic, quartic, quintic, circular, sine")
  end
end
```

- [ ] In `validate_config`, replace the cursor easing branch (`if config.cursor.easing and not valid_easing_types[config.cursor.easing] then error(...) end`) with `validate_easing(config.cursor.easing, "cursor.easing")`, and the scroll easing branch with `validate_easing(config.scroll.easing, "scroll.easing")`.
- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures. (The pre-existing validation_spec tests `rejects invalid cursor easing` / `rejects non-string cursor easing` still pass: the new error message contains the word `easing`, which is the pattern those tests match.)
- [ ] Commit: `git add lua/whisk/engine/loop.lua lua/whisk/config/validation.lua tests/unit/engine/loop_spec.lua tests/unit/config/validation_spec.lua && git commit -m "feat(engine): accept easing functions and extend the named easing set"`

---

### Task 2: Proportional duration resolution engine (#42)

**Files:**
- Create: `lua/whisk/engine/duration.lua`
- Modify: `lua/whisk/engine/orchestrator.lua`, `lua/whisk/config/validation.lua`
- Test: create `tests/unit/engine/duration_spec.lua`; modify `tests/unit/config/validation_spec.lua`, `tests/unit/engine/orchestrator_spec.lua`, `tests/init.lua`

**Interfaces:**
- Produces: `duration_engine.resolve(duration_config: number|WhiskDurationSpec, distance: number): number` — numeric config returns itself; table `{ min, max, per_line }` returns `clamp(min + per_line * distance, min, max)`. `duration_engine.distance(context, result): number` — `abs(result.cursor.line - context.cursor.line)` when the result moves the cursor, else the topline delta for scroll-only results, else 0. Local module alias in consumers: `local duration_engine = require("whisk.engine.duration")`. Tasks 3, 4, and 9 consume both functions. Local `validate_duration(value, path)` in `validation.lua` — consumed by Tasks 3 and 9.
- Consumes: orchestrator `loop.start` options (existing), `validate_easing` from Task 1.

**Steps:**

- [ ] Create `tests/unit/engine/duration_spec.lua`:

```lua
local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('engine/duration', function()
  local duration_engine

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    duration_engine = require('whisk.engine.duration')
  end)

  it('exports resolve and distance', function()
    assert.is_type(duration_engine.resolve, 'function')
    assert.is_type(duration_engine.distance, 'function')
  end)

  it('resolve returns numeric config unchanged', function()
    assert.equals(duration_engine.resolve(150, 40), 150)
  end)

  it('resolve clamps to min for zero distance', function()
    assert.equals(duration_engine.resolve({ min = 50, max = 300, per_line = 10 }, 0), 50)
  end)

  it('resolve grows linearly with distance', function()
    assert.equals(duration_engine.resolve({ min = 50, max = 300, per_line = 10 }, 5), 100)
  end)

  it('resolve clamps to max for long distances', function()
    assert.equals(duration_engine.resolve({ min = 50, max = 300, per_line = 10 }, 500), 300)
  end)

  it('resolve treats a missing per_line as zero', function()
    assert.equals(duration_engine.resolve({ min = 80, max = 200 }, 50), 80)
  end)

  it('resolve returns zero for invalid config', function()
    assert.equals(duration_engine.resolve(nil, 10), 0)
  end)

  it('distance uses the cursor line delta when the result moves the cursor', function()
    local context = { cursor = { line = 10, col = 0 }, viewport = { topline = 1 } }
    local result = { cursor = { line = 25, col = 0 } }
    assert.equals(duration_engine.distance(context, result), 15)
  end)

  it('distance uses the topline delta for scroll-only results', function()
    local context = { cursor = { line = 10, col = 0 }, viewport = { topline = 5 } }
    local result = { viewport = { topline = 45 } }
    assert.equals(duration_engine.distance(context, result), 40)
  end)

  it('distance is zero when nothing moves', function()
    local context = { cursor = { line = 10, col = 0 }, viewport = { topline = 5 } }
    local result = { cursor = { line = 10, col = 3 } }
    assert.equals(duration_engine.distance(context, result), 0)
  end)
end)
```

- [ ] Register the new spec in `tests/init.lua`: insert `require('tests.unit.engine.duration_spec')` immediately after the line `require('tests.unit.engine.orchestrator_spec')`.
- [ ] Append this suite to the end of `tests/unit/config/validation_spec.lua`:

```lua
describe('config/validation duration extensions', function()
  local validation

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    validation = require('whisk.config.validation')
  end)

  it('accepts a duration spec table for cursor and scroll', function()
    assert.does_not_throw(function()
      validation.validate_config({
        cursor = { duration = { min = 50, max = 300, per_line = 5 } },
        scroll = { duration = { min = 100, max = 500, per_line = 2 } },
      })
    end)
  end)

  it('accepts a duration spec without per_line', function()
    assert.does_not_throw(function()
      validation.validate_config({ cursor = { duration = { min = 50, max = 300 } } })
    end)
  end)

  it('rejects a duration spec missing min', function()
    assert.throws(function()
      validation.validate_config({ cursor = { duration = { max = 300, per_line = 5 } } })
    end, 'duration')
  end)

  it('rejects a duration spec with max below min', function()
    assert.throws(function()
      validation.validate_config({ cursor = { duration = { min = 300, max = 50 } } })
    end, 'duration')
  end)

  it('rejects a duration spec with negative per_line', function()
    assert.throws(function()
      validation.validate_config({ scroll = { duration = { min = 50, max = 300, per_line = -1 } } })
    end, 'duration')
  end)

  it('rejects a duration spec with unknown keys', function()
    assert.throws(function()
      validation.validate_config({ cursor = { duration = { min = 50, max = 300, speed = 9 } } })
    end, 'duration')
  end)

  it('still accepts plain numeric durations', function()
    assert.does_not_throw(function()
      validation.validate_config({ cursor = { duration = 120 }, scroll = { duration = 0 } })
    end)
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/engine/orchestrator_spec.lua`:

```lua
describe('engine/orchestrator proportional duration', function()
  local orchestrator
  local motions
  local traits
  local loop

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 30 do
      lines[i] = "line " .. i
    end
    mocks.set_buffer_content(lines)
    mocks.set_cursor(1, 0)
    mocks.set_window_size(20, 80)
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
        return { cursor = { line = ctx.cursor.line + ctx.input.count, col = ctx.cursor.col } }
      end,
    })
  end)

  it('execute accepts a duration spec table in category config', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true, duration = { min = 50, max = 400, per_line = 10 } } })

    orchestrator.execute('test_j', { count = 3 })
    assert.is_true(loop.is_running())
  end)

  it('execute still works with plain numeric duration', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true, duration = 150 } })

    orchestrator.execute('test_j', { count = 3 })
    assert.is_true(loop.is_running())
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: the entire `engine/duration` suite errors with `module 'whisk.engine.duration' not found`, the validation duration-spec tests fail (table durations currently throw `duration must be a positive number`), and `execute accepts a duration spec table` fails inside `loop.start` (arithmetic on a table).
- [ ] Create `lua/whisk/engine/duration.lua` (LuaCATS annotations are explicitly called for here — they define `WhiskDurationSpec` for the whole wave):

```lua
---@class WhiskDurationSpec
---@field min number Minimum duration in milliseconds
---@field max number Maximum duration in milliseconds
---@field per_line number|nil Additional milliseconds per line of travel

local M = {}

local function clamp(value, min_value, max_value)
  return math.max(min_value, math.min(value, max_value))
end

---Resolves a configured duration against the travel distance of a motion.
---@param duration_config number|WhiskDurationSpec
---@param distance number
---@return number
function M.resolve(duration_config, distance)
  if type(duration_config) == "number" then
    return duration_config
  end
  if type(duration_config) == "table" then
    local min_duration = duration_config.min or 0
    local max_duration = duration_config.max or min_duration
    local per_line = duration_config.per_line or 0
    return clamp(min_duration + per_line * (distance or 0), min_duration, max_duration)
  end
  return 0
end

---Computes the line-travel distance between a context and a calculator result.
---@param context table
---@param result table
---@return number
function M.distance(context, result)
  if result.cursor and context.cursor then
    return math.abs(result.cursor.line - context.cursor.line)
  end
  if result.viewport and result.viewport.topline and context.viewport and context.viewport.topline then
    return math.abs(result.viewport.topline - context.viewport.topline)
  end
  return 0
end

return M
```

- [ ] In `lua/whisk/config/validation.lua`, add the shared duration validator directly below `validate_easing`:

```lua
local function duration_error(path)
  error(path .. " duration must be a non-negative number or a table of the shape { min = number, max = number, per_line = number }")
end

local function validate_duration(value, path)
  if value == nil then
    return
  end
  if type(value) == "number" then
    if value < 0 then
      duration_error(path)
    end
    return
  end
  if type(value) ~= "table" then
    duration_error(path)
  end
  if type(value.min) ~= "number" or value.min < 0 then
    duration_error(path)
  end
  if type(value.max) ~= "number" or value.max < value.min then
    duration_error(path)
  end
  if value.per_line ~= nil and (type(value.per_line) ~= "number" or value.per_line < 0) then
    duration_error(path)
  end
  for key in pairs(value) do
    if key ~= "min" and key ~= "max" and key ~= "per_line" then
      duration_error(path)
    end
  end
end
```

- [ ] In `validate_config`, replace the cursor duration branch (`if config.cursor.duration and (type(config.cursor.duration) ~= "number" or config.cursor.duration < 0) then error(...) end`) with `validate_duration(config.cursor.duration, "cursor.duration")`, and the scroll duration branch with `validate_duration(config.scroll.duration, "scroll.duration")`.
- [ ] In `lua/whisk/engine/orchestrator.lua`, add the require after the existing top-of-file requires: `local duration_engine = require("whisk.engine.duration")`. Then, in the `loop.start` options table inside `M.execute`, replace the line `duration = category_config.duration,` with:

```lua
    duration = duration_engine.resolve(category_config.duration, duration_engine.distance(context, result)),
```

Keep every other option in that table exactly as it is on the branch.
- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures. (Numeric defaults resolve to themselves, so no behavior changes unless a user opts into the table form.)
- [ ] Commit: `git add lua/whisk/engine/duration.lua lua/whisk/engine/orchestrator.lua lua/whisk/config/validation.lua tests/unit/engine/duration_spec.lua tests/unit/config/validation_spec.lua tests/unit/engine/orchestrator_spec.lua tests/init.lua && git commit -m "feat(engine): resolve proportional duration from travel distance"`

---

### Task 3: Per-motion duration and easing overrides (#43)

**Files:**
- Modify: `lua/whisk/config/defaults.lua`, `lua/whisk/config/validation.lua`, `lua/whisk/config/management.lua`, `lua/whisk/config.lua`, `lua/whisk/engine/orchestrator.lua`
- Test: `tests/unit/config/defaults_spec.lua`, `tests/unit/config/validation_spec.lua`, `tests/unit/config/management_spec.lua`, `tests/unit/engine/orchestrator_spec.lua`

**Interfaces:**
- Produces: config key `motions = { [motion_id: string] = { duration?: number|WhiskDurationSpec, easing?: string|function } }` (default `{}`); `config.get_motion_overrides(motion_id: string): table` on the facade and `management.get_motion_overrides` behind it. Orchestrator resolution order: category config < per-motion user config.
- Consumes: `validate_duration`/`validate_easing` (Tasks 1–2), `duration_engine.resolve`/`.distance` (Task 2).

**Steps:**

- [ ] Append this suite to the end of `tests/unit/config/defaults_spec.lua`:

```lua
describe('config/defaults motion overrides', function()
  local defaults

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    defaults = require('whisk.config.defaults')
  end)

  it('has an empty motions overrides table by default', function()
    assert.is_type(defaults.config.motions, 'table')
    assert.is_nil(next(defaults.config.motions))
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/config/management_spec.lua`:

```lua
describe('config/management motion overrides', function()
  local management

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    management = require('whisk.config.management')
  end)

  it('returns an empty table when no override exists', function()
    local overrides = management.get_motion_overrides('basic_j')
    assert.is_type(overrides, 'table')
    assert.is_nil(overrides.duration)
    assert.is_nil(overrides.easing)
  end)

  it('returns the configured override table', function()
    management.update({ motions = { line_G = { duration = 400, easing = 'quintic' } } })
    local overrides = management.get_motion_overrides('line_G')
    assert.equals(overrides.duration, 400)
    assert.equals(overrides.easing, 'quintic')
  end)

  it('is exposed through the config facade', function()
    local config = require('whisk.config')
    assert.is_type(config.get_motion_overrides, 'function')
    assert.is_type(config.get_motion_overrides('basic_j'), 'table')
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/config/validation_spec.lua`:

```lua
describe('config/validation motion overrides', function()
  local validation

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    validation = require('whisk.config.validation')
  end)

  it('accepts per-motion duration and easing overrides', function()
    assert.does_not_throw(function()
      validation.validate_config({
        motions = {
          line_G = { duration = { min = 100, max = 600, per_line = 1 }, easing = 'quintic' },
          word_w = { duration = 80 },
          basic_j = { easing = function(t) return t end },
        },
      })
    end)
  end)

  it('rejects a non-table motions config', function()
    assert.throws(function()
      validation.validate_config({ motions = 'fast' })
    end, 'motions')
  end)

  it('rejects a non-table motion override entry', function()
    assert.throws(function()
      validation.validate_config({ motions = { line_G = 400 } })
    end, 'motions')
  end)

  it('rejects unknown override keys', function()
    assert.throws(function()
      validation.validate_config({ motions = { line_G = { speed = 400 } } })
    end, 'motions')
  end)

  it('rejects invalid override duration shapes', function()
    assert.throws(function()
      validation.validate_config({ motions = { line_G = { duration = -5 } } })
    end, 'duration')
  end)

  it('rejects invalid override easing values', function()
    assert.throws(function()
      validation.validate_config({ motions = { line_G = { easing = 'bounce' } } })
    end, 'easing')
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/engine/orchestrator_spec.lua`:

```lua
describe('engine/orchestrator per-motion overrides', function()
  local orchestrator
  local motions
  local traits
  local loop

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 30 do
      lines[i] = "line " .. i
    end
    mocks.set_buffer_content(lines)
    mocks.set_cursor(1, 0)
    mocks.set_window_size(20, 80)
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
        return { cursor = { line = ctx.cursor.line + ctx.input.count, col = ctx.cursor.col } }
      end,
    })
  end)

  it('prefers a per-motion easing function over category easing', function()
    local config = require('whisk.config')
    local called_with = nil
    config.update({
      cursor = { enabled = true, easing = 'linear' },
      motions = { test_j = { easing = function(t) called_with = t return t end } },
    })

    orchestrator.execute('test_j', { count = 2 })
    loop.complete_all()

    assert.equals(called_with, 1.0)
  end)

  it('uses category easing when no override exists', function()
    local config = require('whisk.config')
    local called = false
    config.update({
      cursor = { enabled = true, easing = 'linear' },
      motions = { other_motion = { easing = function(t) called = true return t end } },
    })

    orchestrator.execute('test_j', { count = 2 })
    loop.complete_all()

    assert.is_false(called)
  end)

  it('accepts a per-motion duration spec', function()
    local config = require('whisk.config')
    config.update({
      cursor = { enabled = true },
      motions = { test_j = { duration = { min = 20, max = 200, per_line = 5 } } },
    })

    orchestrator.execute('test_j', { count = 4 })
    assert.is_true(loop.is_running())
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: defaults has no `motions` key, `management.get_motion_overrides` is nil, validation accepts `motions = 'fast'` silently (the throws-tests fail with "Expected error but function succeeded"), and the per-motion easing spy is never called with `1.0`.
- [ ] In `lua/whisk/config/defaults.lua`, add to `M.config` (as a new top-level key, after `keymaps` and before `performance`):

```lua
  motions = {},
```

- [ ] In `lua/whisk/config/validation.lua`, add this block inside `validate_config`, after the `keymaps` block and before the final `return true`:

```lua
  if config.motions then
    if type(config.motions) ~= "table" then
      error("motions must be a table keyed by motion id")
    end
    for motion_id, overrides in pairs(config.motions) do
      if type(motion_id) ~= "string" then
        error("motions keys must be motion id strings")
      end
      if type(overrides) ~= "table" then
        error("motions." .. motion_id .. " must be a table of overrides")
      end
      for key in pairs(overrides) do
        if key ~= "duration" and key ~= "easing" then
          error("motions." .. motion_id .. "." .. key .. " is not a supported override (supported: duration, easing)")
        end
      end
      validate_duration(overrides.duration, "motions." .. motion_id .. ".duration")
      validate_easing(overrides.easing, "motions." .. motion_id .. ".easing")
    end
  end
```

- [ ] In `lua/whisk/config/management.lua`, add after `M.get_performance`:

```lua
function M.get_motion_overrides(motion_id)
  local overrides = current_config.motions and current_config.motions[motion_id]
  if type(overrides) == "table" then
    return overrides
  end
  return {}
end
```

- [ ] In `lua/whisk/config.lua`, add `M.get_motion_overrides = management.get_motion_overrides` after the `M.get_performance` line.
- [ ] In `lua/whisk/engine/orchestrator.lua`, inside `M.execute`, insert directly before the `loop.start({` call:

```lua
  local motion_overrides = config.get_motion_overrides(motion.id)
  local duration_config = motion_overrides.duration or category_config.duration
  local easing_config = motion_overrides.easing or category_config.easing
```

Then in the `loop.start` options table replace the duration line from Task 2 with `duration = duration_engine.resolve(duration_config, duration_engine.distance(context, result)),` and replace `easing = category_config.easing,` with `easing = easing_config,`.
- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures.
- [ ] Commit: `git add lua/whisk/config/defaults.lua lua/whisk/config/validation.lua lua/whisk/config/management.lua lua/whisk/config.lua lua/whisk/engine/orchestrator.lua tests/unit/config/defaults_spec.lua tests/unit/config/management_spec.lua tests/unit/config/validation_spec.lua tests/unit/engine/orchestrator_spec.lua && git commit -m "feat(config): per-motion duration and easing overrides"`

---

### Task 4: Skip-animation predicates — buffer exclusions and minimum distance (#21)

**Files:**
- Modify: `lua/whisk/config/defaults.lua`, `lua/whisk/config/validation.lua`, `lua/whisk/engine/orchestrator.lua`, `tests/mocks/vim_api.lua`, `tests/mocks/init.lua`
- Create: `tests/nvim/specs/skip_predicates_spec.lua`
- Modify (docs): `README.md`, `doc/whisk.txt`
- Test: `tests/unit/config/defaults_spec.lua`, `tests/unit/engine/orchestrator_spec.lua`

**Interfaces:**
- Produces: top-level config keys `exclude = { buftypes = { "terminal", "prompt", "quickfix", "help", "nofile" }, filetypes = {} }` and `min_distance = 0`; extended private seam `should_skip_animation(context, result)` in the orchestrator (signature gains `result` so the min-distance predicate can measure travel). Skipped motions keep the Wave 2 behavior: the calculator result is applied synchronously through the motion's traits at progress 1.0.
- Consumes: `duration_engine.distance` (Task 2), Wave 2's `should_skip_animation` seam and its `vim.fn.reg_executing()` predicate (preserved), `config.get(category)` facade.
- Mock additions: `mocks.set_buffer_option(option, value)`, `mocks.set_buffer_var(name, value)`; mock `vim.api.nvim_buf_get_option` backed by a `buffer_options` table (defaults `{ filetype = "lua", buftype = "" }`), mock `vim.api.nvim_buf_get_var`, and `vim.g = {}` on the mock vim table.

**Steps:**

- [ ] In `tests/mocks/vim_api.lua`, make buffer options and buffer variables stateful. Add to the `state` table literal (both the initial one and the one in `M.reset`): `buffer_options = { filetype = "lua", buftype = "" },` and `buffer_vars = {},`. Add these module helpers after `M.set_window_buffer`:

```lua
function M.set_buffer_option(option, value)
  state.buffer_options[option] = value
end

function M.set_buffer_var(name, value)
  state.buffer_vars[name] = value
end
```

Then in `M.create()`, replace the existing `nvim_buf_get_option` entry with, and add `nvim_buf_get_var` beside it:

```lua
    nvim_buf_get_option = function(bufnr, option)
      return state.buffer_options[option]
    end,

    nvim_buf_get_var = function(bufnr, name)
      if state.buffer_vars[name] == nil then
        error("Key not found: " .. name)
      end
      return state.buffer_vars[name]
    end,
```

- [ ] In `tests/mocks/init.lua`, add `g = {},` to the `_G.vim` table literal in `M.setup` (after the `v = vim_core.v,` line), and add these forwarding helpers after `M.set_window_buffer`:

```lua
function M.set_buffer_option(option, value)
  vim_api.set_buffer_option(option, value)
end

function M.set_buffer_var(name, value)
  vim_api.set_buffer_var(name, value)
end
```

- [ ] Append this suite to the end of `tests/unit/config/defaults_spec.lua`:

```lua
describe('config/defaults skip predicates', function()
  local defaults

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    defaults = require('whisk.config.defaults')
  end)

  it('has default excluded buftypes', function()
    assert.is_type(defaults.config.exclude, 'table')
    for _, buftype in ipairs({ 'terminal', 'prompt', 'quickfix', 'help', 'nofile' }) do
      assert.contains(defaults.config.exclude.buftypes, buftype)
    end
  end)

  it('has no default excluded filetypes', function()
    assert.is_type(defaults.config.exclude.filetypes, 'table')
    assert.equals(#defaults.config.exclude.filetypes, 0)
  end)

  it('defaults min_distance to zero', function()
    assert.equals(defaults.config.min_distance, 0)
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/engine/orchestrator_spec.lua`:

```lua
describe('engine/orchestrator skip predicates', function()
  local orchestrator
  local motions
  local traits
  local loop
  local config

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 30 do
      lines[i] = "line " .. i
    end
    mocks.set_buffer_content(lines)
    mocks.set_cursor(1, 0)
    mocks.set_window_size(20, 80)
    mocks.set_topline(1)

    motions = require('whisk.registry.motions')
    traits = require('whisk.registry.traits')
    loop = require('whisk.engine.loop')
    orchestrator = require('whisk.engine.orchestrator')
    config = require('whisk.config')

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
        return { cursor = { line = ctx.cursor.line + ctx.input.count, col = ctx.cursor.col } }
      end,
    })

    config.update({ cursor = { enabled = true } })
  end)

  it('applies the motion synchronously in an excluded buftype', function()
    mocks.set_buffer_option('buftype', 'terminal')
    orchestrator.execute('test_j', { count = 3 })
    assert.is_false(loop.is_running())
    assert.equals(mocks.get_cursor()[1], 4)
  end)

  it('applies the motion synchronously in an excluded filetype', function()
    config.update({ exclude = { filetypes = { 'lua' } } })
    orchestrator.execute('test_j', { count = 2 })
    assert.is_false(loop.is_running())
    assert.equals(mocks.get_cursor()[1], 3)
  end)

  it('animates when the buffer is not excluded', function()
    orchestrator.execute('test_j', { count = 2 })
    assert.is_true(loop.is_running())
  end)

  it('applies synchronously below min_distance', function()
    config.update({ min_distance = 5 })
    orchestrator.execute('test_j', { count = 2 })
    assert.is_false(loop.is_running())
    assert.equals(mocks.get_cursor()[1], 3)
  end)

  it('animates at or above min_distance', function()
    config.update({ min_distance = 5 })
    orchestrator.execute('test_j', { count = 5 })
    assert.is_true(loop.is_running())
  end)

  it('applies synchronously when b:whisk_disable is set', function()
    mocks.set_buffer_var('whisk_disable', true)
    orchestrator.execute('test_j', { count = 2 })
    assert.is_false(loop.is_running())
    assert.equals(mocks.get_cursor()[1], 3)
  end)

  it('applies synchronously when g:whisk_disable is set', function()
    vim.g.whisk_disable = true
    orchestrator.execute('test_j', { count = 2 })
    assert.is_false(loop.is_running())
    assert.equals(mocks.get_cursor()[1], 3)
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: the defaults tests fail (no `exclude`/`min_distance` keys) and every skip-predicate test that expects `loop.is_running()` to be false fails because the orchestrator animates unconditionally.
- [ ] In `lua/whisk/config/defaults.lua`, add to `M.config` as top-level keys (after `motions` from Task 3, before `performance`):

```lua
  exclude = {
    buftypes = { "terminal", "prompt", "quickfix", "help", "nofile" },
    filetypes = {},
  },
  min_distance = 0,
```

- [ ] In `lua/whisk/config/validation.lua`, add inside `validate_config` after the `motions` block from Task 3:

```lua
  if config.exclude then
    if type(config.exclude) ~= "table" then
      error("exclude must be a table with buftypes and filetypes lists")
    end
    for key in pairs(config.exclude) do
      if key ~= "buftypes" and key ~= "filetypes" then
        error("exclude." .. key .. " is not supported (supported: buftypes, filetypes)")
      end
    end
    validate_string_list(config.exclude.buftypes, "exclude.buftypes")
    validate_string_list(config.exclude.filetypes, "exclude.filetypes")
  end

  if config.min_distance ~= nil and (type(config.min_distance) ~= "number" or config.min_distance < 0) then
    error("min_distance must be a non-negative number")
  end
```

and add the list validator next to `validate_duration`:

```lua
local function validate_string_list(value, path)
  if value == nil then
    return
  end
  if type(value) ~= "table" then
    error(path .. " must be a list of strings")
  end
  for _, entry in ipairs(value) do
    if type(entry) ~= "string" then
      error(path .. " must be a list of strings")
    end
  end
end
```

- [ ] In `lua/whisk/engine/orchestrator.lua`, locate the private `should_skip_animation` function introduced in Wave 2 and replace it (plus add its three predicate helpers above it) with the following. Preserve Wave 2's macro-replay predicate as the first check exactly as shown; if the Wave 2 body contains any additional predicate this plan does not know about, keep it as an extra check inside the same function:

```lua
local function is_listed(value, list)
  if not list then
    return false
  end
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

local function is_excluded_buffer(context)
  local exclude = config.get("exclude")
  if not exclude then
    return false
  end
  local ok_buftype, buftype = pcall(vim.api.nvim_buf_get_option, context.bufnr, "buftype")
  if ok_buftype and is_listed(buftype or "", exclude.buftypes) then
    return true
  end
  local ok_filetype, filetype = pcall(vim.api.nvim_buf_get_option, context.bufnr, "filetype")
  if ok_filetype and is_listed(filetype or "", exclude.filetypes) then
    return true
  end
  return false
end

local function is_disabled_by_variable(context)
  if vim.g and vim.g.whisk_disable == true then
    return true
  end
  local ok, value = pcall(vim.api.nvim_buf_get_var, context.bufnr, "whisk_disable")
  return ok and value == true
end

local function is_below_min_distance(context, result)
  local min_distance = config.get("min_distance") or 0
  if min_distance <= 0 then
    return false
  end
  return duration_engine.distance(context, result) < min_distance
end

local function should_skip_animation(context, result)
  if vim.fn.reg_executing and vim.fn.reg_executing() ~= "" then
    return true
  end
  if is_disabled_by_variable(context) then
    return true
  end
  if is_excluded_buffer(context) then
    return true
  end
  if is_below_min_distance(context, result) then
    return true
  end
  return false
end
```

- [ ] In `M.execute`, update the existing Wave 2 call site from `should_skip_animation(context)` to `should_skip_animation(context, result)`. The call site stays where Wave 2 put it: after the calculator has produced a non-nil `result` and before the same-position early exit; its true-branch (synchronous apply of the final frame through the motion's traits at progress 1.0, then return) is unchanged.
- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures.
- [ ] Create the headless probe `tests/nvim/specs/skip_predicates_spec.lua` (mock `vim.cmd` is a no-op and the mock has no real buftype semantics, so real-editor confirmation happens here):

```lua
local function fail(message)
  io.write("FAIL: " .. message .. "\n")
  vim.cmd("cquit! 1")
end

local function expect_equals(actual, expected, label)
  if actual ~= expected then
    fail(label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
  end
  io.write("OK: " .. label .. "\n")
end

require("whisk").setup({ cursor = { duration = 40 }, scroll = { duration = 40 } })
local orchestrator = require("whisk.engine.orchestrator")
local loop = require("whisk.engine.loop")

local lines = {}
for i = 1, 100 do
  lines[i] = "line " .. i
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

vim.bo.buftype = "nofile"
orchestrator.execute("basic_j", { count = 3, direction = "j" })
expect_equals(loop.get_active_count(), 0, "excluded buftype does not enqueue an animation")
expect_equals(vim.api.nvim_win_get_cursor(0)[1], 4, "excluded buftype still applies the motion synchronously")

vim.bo.buftype = ""
require("whisk").setup({ cursor = { duration = 40 }, scroll = { duration = 40 }, min_distance = 5 })
vim.api.nvim_win_set_cursor(0, { 10, 0 })
orchestrator.execute("basic_j", { count = 2, direction = "j" })
expect_equals(loop.get_active_count(), 0, "below min_distance applies synchronously")
expect_equals(vim.api.nvim_win_get_cursor(0)[1], 12, "min_distance skip still moves the cursor")

orchestrator.execute("basic_j", { count = 8, direction = "j" })
if loop.get_active_count() == 0 then
  fail("distance at or above min_distance should animate")
end
io.write("OK: distances at or above min_distance animate\n")
local settled = vim.wait(1000, function()
  return vim.api.nvim_win_get_cursor(0)[1] == 20
end, 10)
if not settled then
  fail("animated motion did not reach its target")
end
io.write("OK: animated motion lands on target\n")

vim.b.whisk_disable = true
orchestrator.execute("basic_j", { count = 6, direction = "j" })
expect_equals(loop.get_active_count(), 0, "b:whisk_disable applies synchronously")
expect_equals(vim.api.nvim_win_get_cursor(0)[1], 26, "b:whisk_disable still moves the cursor")
vim.b.whisk_disable = nil

io.write("SPEC PASS: skip_predicates\n")
```

- [ ] Run the probe from the repo root and confirm every `OK:` line plus `SPEC PASS: skip_predicates` prints and the exit code is 0:

```
nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/skip_predicates_spec.lua" +"qa!"
```

- [ ] Update `README.md`: replace the Configuration section's `require("whisk").setup({ ... })` code block (the one listing all defaults) with:

```lua
require("whisk").setup({
  cursor = {
    duration = 150,
    easing = "ease-out",
    enabled = true,
  },
  scroll = {
    duration = 200,
    easing = "ease-in-out",
    enabled = true,
  },
  keymaps = {
    cursor = true,
    scroll = true,
  },
  motions = {},
  exclude = {
    buftypes = { "terminal", "prompt", "quickfix", "help", "nofile" },
    filetypes = {},
  },
  min_distance = 0,
  performance = {
    enabled = false,
    disable_syntax_during_scroll = true,
    ignore_events = { "WinScrolled", "CursorMoved", "CursorMovedI" },
    reduce_frame_rate = false,
    frame_rate_threshold = 60,    -- not currently read by any code path
    auto_enable_on_large_files = true,
    large_file_threshold = 5000,
  },
})
```

and replace the line `**Easing options:** \`linear\`, \`ease-in\`, \`ease-out\`, \`ease-in-out\`` with:

```markdown
**Easing options:** a name — `linear`, `ease-in`, `ease-out`, `ease-in-out`, `quadratic`, `cubic`, `quartic`, `quintic`, `circular`, `sine` — or your own `function(t) -> number` mapping progress `t` in `[0, 1]` to eased progress in `[0, 1]`.

**Duration options:** a number of milliseconds (constant duration, the default), or a table `{ min = ms, max = ms, per_line = ms }` for distance-proportional duration: `clamp(min + per_line * lines_travelled, min, max)`.

**Per-motion overrides:** `motions = { [motion_id] = { duration = ..., easing = ... } }` overrides the category timing for a single motion, e.g. `motions = { line_G = { duration = { min = 150, max = 600, per_line = 1 }, easing = "quintic" } }`.

**Skipping animation:** motions in an excluded `buftype`/`filetype`, motions shorter than `min_distance` lines, and motions in buffers where `b:whisk_disable = true` (or globally, `g:whisk_disable = true`) apply instantly without animation.
```

- [ ] Update `doc/whisk.txt`: in the configuration section, document the new keys with this help text (adjust indentation to the file's existing style):

```
motions		Per-motion timing overrides, keyed by motion id: >
			motions = { line_G = { duration = 400, easing = "quintic" } }
<		Overrides win over the motion's category config.

exclude		Buffers whisk never animates in. Matching motions apply
		instantly. Defaults: >
			exclude = {
			  buftypes = { "terminal", "prompt", "quickfix", "help", "nofile" },
			  filetypes = {},
			}
<
min_distance	Minimum number of travelled lines before whisk animates a
		motion. Shorter motions apply instantly. Default: 0.

		Setting b:whisk_disable = v:true disables animation in one
		buffer; g:whisk_disable = v:true disables it everywhere.

		duration accepts a number (milliseconds) or a table
		{ min, max, per_line } for distance-proportional timing.
		easing accepts a name (linear, ease-in, ease-out, ease-in-out,
		quadratic, cubic, quartic, quintic, circular, sine) or a
		Lua function(t) that maps [0, 1] onto [0, 1].
```

- [ ] Run `bash scripts/run_tests.sh` one final time — all tests pass.
- [ ] Commit: `git add lua/whisk/config/defaults.lua lua/whisk/config/validation.lua lua/whisk/engine/orchestrator.lua tests/mocks/vim_api.lua tests/mocks/init.lua tests/unit/config/defaults_spec.lua tests/unit/engine/orchestrator_spec.lua tests/nvim/specs/skip_predicates_spec.lua README.md doc/whisk.txt && git commit -m "feat(engine): buffer exclusions and min-distance skip predicates"`

---

### Task 5: Screen-position motions H, M, L (#23)

**Files:**
- Create: `lua/whisk/calculators/screen.lua`, `tests/unit/calculators/screen_spec.lua`, `tests/nvim/specs/screen_motions_spec.lua`
- Modify: `lua/whisk/calculators/init.lua`, `lua/whisk/registry/builtin.lua`, `tests/init.lua`
- Test: `tests/unit/calculators/screen_spec.lua`, `tests/unit/registry/builtin_spec.lua`

**Interfaces:**
- Produces: `calculators.screen.H/M/L(context) -> { cursor = { line, col } }` (direct math from `viewport.topline` + `viewport.height` + effective scrolloff, first-non-blank column, matching native H/M/L semantics including the scrolloff clamp that relaxes at buffer edges); motion ids `screen_H`, `screen_M`, `screen_L` (keys `H`/`M`/`L`, modes n+v, category `cursor`, trait `cursor`, input `count`).
- Consumes: mock global `scrolloff` (5) via `vim.api.nvim_get_option`; real window-local scrolloff via `pcall(vim.api.nvim_win_get_option, ...)` with `-1` falling back to the global.

**Steps:**

- [ ] Create `tests/unit/calculators/screen_spec.lua` (the mock exposes only the global scrolloff of 5, and the pcall'd window-option read fails under the mock, so every expectation below uses scrolloff 5):

```lua
local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('calculators/screen', function()
  local screen

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    lines[45] = "    indented line"
    mocks.set_buffer_content(lines)
    mocks.set_cursor(50, 0)
    mocks.set_window_size(20, 80)
    mocks.set_topline(40)
    screen = require('whisk.calculators.screen')
  end)

  local function make_context(topline, height, cursor_line, count, line_count)
    return {
      cursor = { line = cursor_line, col = 0 },
      viewport = { topline = topline, height = height },
      input = { count = count or 1 },
      buffer = { line_count = line_count or 100 },
    }
  end

  it('exports H, M and L', function()
    assert.is_type(screen.H, 'function')
    assert.is_type(screen.M, 'function')
    assert.is_type(screen.L, 'function')
  end)

  it('H targets topline plus scrolloff when scrolled down', function()
    local result = screen.H(make_context(40, 20, 50, 1))
    assert.equals(result.cursor.line, 45)
  end)

  it('H lands on the first non-blank column', function()
    local result = screen.H(make_context(40, 20, 50, 1))
    assert.equals(result.cursor.col, 4)
  end)

  it('H honors a count larger than scrolloff', function()
    local result = screen.H(make_context(40, 20, 50, 10))
    assert.equals(result.cursor.line, 49)
  end)

  it('H reaches line 1 when the view is at the top', function()
    local result = screen.H(make_context(1, 20, 10, 1))
    assert.equals(result.cursor.line, 1)
  end)

  it('H clamps to the visible bottom for huge counts', function()
    local result = screen.H(make_context(40, 20, 50, 100))
    assert.equals(result.cursor.line, 59)
  end)

  it('M targets the middle of the visible lines', function()
    local result = screen.M(make_context(40, 20, 50, 1))
    assert.equals(result.cursor.line, 49)
  end)

  it('M uses the shorter visible span near end of buffer', function()
    local result = screen.M(make_context(95, 20, 97, 1))
    assert.equals(result.cursor.line, 97)
  end)

  it('L targets the visible bottom minus scrolloff mid-buffer', function()
    local result = screen.L(make_context(40, 20, 50, 1))
    assert.equals(result.cursor.line, 54)
  end)

  it('L honors a count larger than scrolloff', function()
    local result = screen.L(make_context(40, 20, 50, 10))
    assert.equals(result.cursor.line, 50)
  end)

  it('L reaches the last line when the buffer end is visible', function()
    local result = screen.L(make_context(90, 20, 95, 1))
    assert.equals(result.cursor.line, 100)
  end)

  it('L never goes above the topline', function()
    local result = screen.L(make_context(40, 20, 50, 100))
    assert.equals(result.cursor.line, 40)
  end)
end)
```

- [ ] Register the spec in `tests/init.lua`: insert `require('tests.unit.calculators.screen_spec')` immediately after the line `require('tests.unit.calculators.search_spec')`.
- [ ] Append this suite to the end of `tests/unit/registry/builtin_spec.lua`:

```lua
describe('registry/builtin screen motions', function()
  local builtin
  local motions

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    builtin = require('whisk.registry.builtin')
    motions = require('whisk.registry.motions')
    motions.clear()
    require('whisk.registry.traits').clear()
    builtin.register_all()
  end)

  it('registers screen_H, screen_M and screen_L', function()
    for _, id in ipairs({ 'screen_H', 'screen_M', 'screen_L' }) do
      local motion = motions.get(id)
      assert.is_not_nil(motion, id .. ' should be registered')
      assert.equals(motion.category, 'cursor')
      assert.is_type(motion.calculator, 'function')
    end
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: the screen spec errors with `module 'whisk.calculators.screen' not found` and the builtin test reports `screen_H should be registered`.
- [ ] Create `lua/whisk/calculators/screen.lua`:

```lua
local M = {}

local function get_first_non_blank(line_num)
  local line_content = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1] or ""
  local leading_space = line_content:match("^%s*")
  return leading_space and #leading_space or 0
end

local function get_scrolloff(context)
  local ok, value = pcall(vim.api.nvim_win_get_option, context.winid or 0, "scrolloff")
  if ok and type(value) == "number" and value >= 0 then
    return value
  end
  return vim.api.nvim_get_option("scrolloff") or 0
end

local function visible_bottom(context)
  return math.min(context.viewport.topline + context.viewport.height - 1, context.buffer.line_count)
end

function M.H(context)
  local scrolloff = get_scrolloff(context)
  local offset = context.input.count - 1
  if context.viewport.topline > 1 then
    offset = math.max(offset, scrolloff)
  end
  local target_line = math.min(context.viewport.topline + offset, visible_bottom(context))
  return {
    cursor = { line = target_line, col = get_first_non_blank(target_line) },
  }
end

function M.M(context)
  local bottom = visible_bottom(context)
  local target_line = context.viewport.topline + math.floor((bottom - context.viewport.topline) / 2)
  return {
    cursor = { line = target_line, col = get_first_non_blank(target_line) },
  }
end

function M.L(context)
  local scrolloff = get_scrolloff(context)
  local bottom = visible_bottom(context)
  local offset = context.input.count - 1
  if bottom < context.buffer.line_count then
    offset = math.max(offset, scrolloff)
  end
  local target_line = math.max(bottom - offset, context.viewport.topline)
  return {
    cursor = { line = target_line, col = get_first_non_blank(target_line) },
  }
end

return M
```

- [ ] In `lua/whisk/calculators/init.lua`, add `M.screen = require("whisk.calculators.screen")` after the `M.scroll` line.
- [ ] In `lua/whisk/registry/builtin.lua`, add inside `M.register_motions` (after the `screen_gk` registration):

```lua
  for _, key in ipairs({ "H", "M", "L" }) do
    motions.register({
      id = "screen_" .. key,
      keys = { key },
      modes = { "n", "v" },
      traits = { "cursor" },
      category = "cursor",
      calculator = calculators.screen[key],
      description = "screen position " .. key,
      input = "count",
    })
  end
```

- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures.
- [ ] Create the headless fidelity probe `tests/nvim/specs/screen_motions_spec.lua` (native H/M/L semantics — including scrolloff clamping and count handling — cannot be exercised by the mocks, so the probe compares the calculator's target against real `normal!` behavior):

```lua
local function fail(message)
  io.write("FAIL: " .. message .. "\n")
  vim.cmd("cquit! 1")
end

local function expect_equals(actual, expected, label)
  if actual ~= expected then
    fail(label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
  end
  io.write("OK: " .. label .. "\n")
end

vim.o.scrolloff = 3
local lines = {}
for i = 1, 200 do
  lines[i] = "line " .. i
end
lines[95] = "    indented 95"
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 100, 0 })
vim.cmd("normal! zz")

local builder = require("whisk.context.builder")
local screen = require("whisk.calculators.screen")

local function calculator_target(calculator, count)
  local context = builder.build({ count = count or 1 })
  return calculator(context)
end

local function native_target(key, count)
  local view = vim.fn.winsaveview()
  local prefix = count and tostring(count) or ""
  vim.cmd("normal! " .. prefix .. key)
  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.fn.winrestview(view)
  return cursor
end

for _, case in ipairs({
  { calculator = screen.H, key = "H", label = "H" },
  { calculator = screen.M, key = "M", label = "M" },
  { calculator = screen.L, key = "L", label = "L" },
}) do
  local result = calculator_target(case.calculator, 1)
  local native = native_target(case.key)
  expect_equals(result.cursor.line, native[1], case.label .. " target line matches native")
  expect_equals(result.cursor.col, native[2], case.label .. " target col matches native")
end

local h5 = calculator_target(screen.H, 5)
local h5_native = native_target("H", 5)
expect_equals(h5.cursor.line, h5_native[1], "5H target line matches native")

local l5 = calculator_target(screen.L, 5)
local l5_native = native_target("L", 5)
expect_equals(l5.cursor.line, l5_native[1], "5L target line matches native")

vim.cmd("normal! gg")
local h_top = calculator_target(screen.H, 1)
local h_top_native = native_target("H")
expect_equals(h_top.cursor.line, h_top_native[1], "H at buffer top matches native (no scrolloff clamp)")

io.write("SPEC PASS: screen_motions\n")
```

- [ ] Run the probe from the repo root and confirm all `OK:` lines plus `SPEC PASS: screen_motions` print with exit code 0:

```
nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/screen_motions_spec.lua" +"qa!"
```

- [ ] Run `bash scripts/run_tests.sh` once more — all tests pass.
- [ ] Commit: `git add lua/whisk/calculators/screen.lua lua/whisk/calculators/init.lua lua/whisk/registry/builtin.lua tests/unit/calculators/screen_spec.lua tests/unit/registry/builtin_spec.lua tests/init.lua tests/nvim/specs/screen_motions_spec.lua && git commit -m "feat(calculators): screen position motions H, M and L"`

---

### Task 6: Search-word and mark jump motions — `*`, `#`, backtick, quote (#23)

**Files:**
- Create: `lua/whisk/calculators/mark.lua`, `tests/unit/calculators/mark_spec.lua`, `tests/nvim/specs/search_mark_motions_spec.lua`
- Modify: `lua/whisk/calculators/search.lua`, `lua/whisk/calculators/init.lua`, `lua/whisk/registry/builtin.lua`, `tests/mocks/vim_fn.lua`, `tests/mocks/init.lua`, `tests/init.lua`
- Test: `tests/unit/calculators/mark_spec.lua`, `tests/unit/registry/builtin_spec.lua`

**Interfaces:**
- Produces: `calculators.search.star/hash(context)` (native delegation of `*`/`#` through Wave 2's `native.calculate`; the `@/` register and hlsearch side effects persist — that is correct and native); `calculators.mark["`"]` and `calculators.mark["'"]` (char input, native delegation, in-buffer only; cross-buffer marks execute the native jump directly and return nil; unset marks return nil). Motion ids `search_star` (`*`, modes n), `search_hash` (`#`, modes n), `mark_backtick` (`` ` ``, modes n+v, input `char`), `mark_quote` (`'`, modes n+v, input `char`) — all `category = "cursor"`, `traits = { "cursor" }`, `jump = true` (the Wave 2 orchestrator pushes `m'` before animating jump motions).
- Consumes: `native.calculate(motion_cmd, context, opts)` (Wave 2). The mark calculators pass `{ include_count = false }` to suppress the count prefix — the executed command must be exactly `` ` `` or `'` followed by the mark character, with no count. `*`/`#` use the default count behavior.
- Mock additions: `mocks.set_mark(mark, pos)`; mock `vim.fn.getpos` consults a `marks` table and returns `{ 0, 0, 0, 0 }` for unset marks.

**Steps:**

- [ ] In `tests/mocks/vim_fn.lua`, add `marks = {},` to the `state` table literal (both the initial one and the one in `M.reset`), add this helper after `M.set_last_char`:

```lua
function M.set_mark(mark, pos)
  state.marks[mark] = pos
end
```

and replace the `getpos` entry in `M.create()` with:

```lua
    getpos = function(mark)
      if mark == "'<" then
        return state.visual_start
      elseif mark == "'>" then
        return state.visual_end
      end
      if state.marks[mark] then
        return state.marks[mark]
      end
      return { 0, 0, 0, 0 }
    end,
```

- [ ] In `tests/mocks/init.lua`, add after `M.set_buffer_var`:

```lua
function M.set_mark(mark, pos)
  vim_fn.set_mark(mark, pos)
end
```

- [ ] Create `tests/unit/calculators/mark_spec.lua` (native delegation itself is a no-op under the mock `vim.cmd`, so these tests cover the routing decisions; native fidelity is probed headlessly below):

```lua
local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('calculators/mark', function()
  local mark

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 50 do
      lines[i] = "line " .. i
    end
    mocks.set_buffer_content(lines)
    mocks.set_cursor(1, 0)
    mark = require('whisk.calculators.mark')
  end)

  it('exports backtick and quote calculators', function()
    assert.is_type(mark["`"], 'function')
    assert.is_type(mark["'"], 'function')
  end)

  it('returns nil for an unset mark', function()
    local ctx = { bufnr = 1, cursor = { line = 1, col = 0 }, input = { char = 'a', count = 1 } }
    assert.is_nil(mark["`"](ctx))
  end)

  it('returns nil when no mark character was captured', function()
    local ctx = { bufnr = 1, cursor = { line = 1, col = 0 }, input = { count = 1 } }
    assert.is_nil(mark["`"](ctx))
  end)

  it('falls back to a direct native jump for cross-buffer marks', function()
    mocks.set_mark("'A", { 2, 30, 1, 0 })
    local ctx = { bufnr = 1, cursor = { line = 1, col = 0 }, input = { char = 'A', count = 1 } }
    local result = mark["`"](ctx)
    assert.is_nil(result)
    assert.contains(mocks.get_commands(), "normal! `A")
  end)

  it('delegates in-buffer marks to the native helper', function()
    mocks.set_mark("'a", { 0, 30, 5, 0 })
    local ctx = { bufnr = 1, cursor = { line = 1, col = 0 }, input = { char = 'a', count = 1 } }
    local result = mark["`"](ctx)
    assert.is_not_nil(result)
    assert.is_not_nil(result.cursor)
  end)

  it('quote calculator routes the same way', function()
    mocks.set_mark("'a", { 0, 30, 5, 0 })
    local ctx = { bufnr = 1, cursor = { line = 1, col = 0 }, input = { char = 'a', count = 1 } }
    local result = mark["'"](ctx)
    assert.is_not_nil(result)
  end)
end)
```

- [ ] Register the spec in `tests/init.lua`: insert `require('tests.unit.calculators.mark_spec')` immediately after the `screen_spec` require added in Task 5.
- [ ] Append this suite to the end of `tests/unit/registry/builtin_spec.lua`:

```lua
describe('registry/builtin search and mark motions', function()
  local builtin
  local motions

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    builtin = require('whisk.registry.builtin')
    motions = require('whisk.registry.motions')
    motions.clear()
    require('whisk.registry.traits').clear()
    builtin.register_all()
  end)

  it('registers search_star and search_hash as jump motions', function()
    for _, id in ipairs({ 'search_star', 'search_hash' }) do
      local motion = motions.get(id)
      assert.is_not_nil(motion, id .. ' should be registered')
      assert.equals(motion.category, 'cursor')
      assert.is_true(motion.jump == true, id .. ' should carry jump = true')
    end
  end)

  it('registers mark_backtick and mark_quote as char-input jump motions', function()
    for _, id in ipairs({ 'mark_backtick', 'mark_quote' }) do
      local motion = motions.get(id)
      assert.is_not_nil(motion, id .. ' should be registered')
      assert.equals(motion.input, 'char')
      assert.is_true(motion.jump == true, id .. ' should carry jump = true')
    end
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: the mark spec errors with `module 'whisk.calculators.mark' not found` and the builtin tests report the four ids as unregistered.
- [ ] Create `lua/whisk/calculators/mark.lua` (this file passes `{ include_count = false }` per the working note — the delegated command must be exactly the mark command plus the char, with no count prefix):

```lua
local native = require("whisk.calculators.native")

local M = {}

local function jump_to_mark(mark_cmd, context)
  if not context.input.char or context.input.char == "" then
    return nil
  end
  local position = vim.fn.getpos("'" .. context.input.char)
  local mark_bufnr, mark_line = position[1], position[2]
  if mark_line == 0 then
    return nil
  end
  if mark_bufnr ~= 0 and mark_bufnr ~= context.bufnr then
    pcall(vim.cmd, "normal! " .. mark_cmd .. context.input.char)
    return nil
  end
  return native.calculate(mark_cmd .. context.input.char, context, { include_count = false })
end

M["`"] = function(context)
  return jump_to_mark("`", context)
end

M["'"] = function(context)
  return jump_to_mark("'", context)
end

return M
```

- [ ] In `lua/whisk/calculators/search.lua`, add the two delegating calculators after the existing exports (the file already requires `whisk.calculators.native` since Wave 2; use the same local it uses):

```lua
function M.star(context)
  return native.calculate("*", context)
end

function M.hash(context)
  return native.calculate("#", context)
end
```

- [ ] In `lua/whisk/calculators/init.lua`, add `M.mark = require("whisk.calculators.mark")` after the `M.screen` line.
- [ ] In `lua/whisk/registry/builtin.lua`, add inside `M.register_motions` after the `screen_H`/`M`/`L` loop from Task 5 (star/hash are registered normal-mode only: in visual mode `*`/`#` are not standard motions and mapping them would shadow visual-star style plugins):

```lua
  motions.register({
    id = "search_star",
    keys = { "*" },
    modes = { "n" },
    traits = { "cursor" },
    category = "cursor",
    calculator = calculators.search.star,
    description = "search word under cursor forward",
    input = "count",
    jump = true,
  })

  motions.register({
    id = "search_hash",
    keys = { "#" },
    modes = { "n" },
    traits = { "cursor" },
    category = "cursor",
    calculator = calculators.search.hash,
    description = "search word under cursor backward",
    input = "count",
    jump = true,
  })

  motions.register({
    id = "mark_backtick",
    keys = { "`" },
    modes = { "n", "v" },
    traits = { "cursor" },
    category = "cursor",
    calculator = calculators.mark["`"],
    description = "jump to mark exact position",
    input = "char",
    jump = true,
  })

  motions.register({
    id = "mark_quote",
    keys = { "'" },
    modes = { "n", "v" },
    traits = { "cursor" },
    category = "cursor",
    calculator = calculators.mark["'"],
    description = "jump to mark first non-blank",
    input = "char",
    jump = true,
  })
```

- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures.
- [ ] Create the headless probe `tests/nvim/specs/search_mark_motions_spec.lua` (search register side effects, animation landing, jumplist push, and cross-buffer fallback are only observable in a real editor):

```lua
local function fail(message)
  io.write("FAIL: " .. message .. "\n")
  vim.cmd("cquit! 1")
end

local function expect_equals(actual, expected, label)
  if actual ~= expected then
    fail(label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
  end
  io.write("OK: " .. label .. "\n")
end

vim.o.hidden = true
require("whisk").setup({ cursor = { duration = 30 }, scroll = { duration = 30 } })
local orchestrator = require("whisk.engine.orchestrator")

local lines = {}
for i = 1, 120 do
  lines[i] = "filler " .. i
end
lines[10] = "alpha beta"
lines[80] = "gamma alpha"
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 10, 0 })

orchestrator.execute("search_star", { count = 1, direction = "*" })
local moved = vim.wait(1000, function()
  return vim.api.nvim_win_get_cursor(0)[1] == 80
end, 10)
if not moved then
  fail("* did not animate to the next occurrence")
end
io.write("OK: * animates to the next occurrence\n")
expect_equals(vim.fn.getreg("/"), "\\<alpha\\>", "* updates the search register (native side effect persists)")

orchestrator.execute("search_hash", { count = 1, direction = "#" })
local back = vim.wait(1000, function()
  return vim.api.nvim_win_get_cursor(0)[1] == 10
end, 10)
if not back then
  fail("# did not animate back to the previous occurrence")
end
io.write("OK: # animates to the previous occurrence\n")

vim.api.nvim_win_set_cursor(0, { 100, 3 })
vim.cmd("normal! ma")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
orchestrator.execute("mark_backtick", { char = "a", count = 1, direction = "`" })
local reached = vim.wait(1000, function()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return cursor[1] == 100 and cursor[2] == 3
end, 10)
if not reached then
  fail("backtick mark jump did not reach the exact mark position")
end
io.write("OK: backtick mark jump animates to the exact position\n")

local jumps = vim.fn.getjumplist(0)[1]
local pushed = false
for _, entry in ipairs(jumps) do
  if entry.lnum == 1 then
    pushed = true
  end
end
if not pushed then
  fail("jump flag did not push the origin onto the jumplist")
end
io.write("OK: mark jump pushes origin onto the jumplist\n")

local first_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 50, 0 })
vim.cmd("normal! mA")
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "other buffer line 1", "other buffer line 2" })
orchestrator.execute("mark_backtick", { char = "A", count = 1, direction = "`" })
expect_equals(vim.api.nvim_get_current_buf(), first_buf, "cross-buffer mark falls back to a native buffer switch")
expect_equals(vim.api.nvim_win_get_cursor(0)[1], 50, "cross-buffer mark lands on the mark line")

io.write("SPEC PASS: search_mark_motions\n")
```

- [ ] Run the probe from the repo root and confirm all `OK:` lines plus `SPEC PASS: search_mark_motions` print with exit code 0:

```
nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/search_mark_motions_spec.lua" +"qa!"
```

- [ ] Run `bash scripts/run_tests.sh` once more — all tests pass.
- [ ] Commit: `git add lua/whisk/calculators/mark.lua lua/whisk/calculators/search.lua lua/whisk/calculators/init.lua lua/whisk/registry/builtin.lua tests/mocks/vim_fn.lua tests/mocks/init.lua tests/unit/calculators/mark_spec.lua tests/unit/registry/builtin_spec.lua tests/init.lua tests/nvim/specs/search_mark_motions_spec.lua && git commit -m "feat(calculators): star, hash and mark jump motions"`

---

### Task 7: Line-scroll motions `<C-e>` and `<C-y>`, motion documentation (#23)

**Files:**
- Modify: `lua/whisk/calculators/scroll.lua`, `lua/whisk/registry/builtin.lua`, `README.md`, `doc/whisk.txt`
- Create: `tests/nvim/specs/scroll_line_motions_spec.lua`
- Test: `tests/unit/calculators/scroll_spec.lua`, `tests/unit/registry/builtin_spec.lua`

**Interfaces:**
- Produces: `calculators.scroll.ctrl_e/ctrl_y(context) -> { cursor, viewport = { topline } }` — topline moves by `count`; the cursor is pulled along only when it would leave the scrolloff window (mirroring native `<C-e>`/`<C-y>`). Shared local `get_scrolloff(context)` in `scroll.lua` (same fallback logic as `screen.lua`: window-local option when readable and `>= 0`, else global). Motion ids `scroll_ctrl_e` (`<C-e>`), `scroll_ctrl_y` (`<C-y>`), modes n+v, category `scroll`, traits `{ "cursor", "scroll" }`, input `count`.
- Consumes: existing scroll calculator conventions; the orchestrator's topline-aware `is_same_viewport` (the #12 fix) which keeps topline-only changes from being swallowed.

**Steps:**

- [ ] Append this suite to the end of `tests/unit/calculators/scroll_spec.lua` (mock global scrolloff is 5; the pcall'd window-option read fails under the mock):

```lua
describe('calculators/scroll line scroll', function()
  local scroll

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    mocks.set_buffer_content(lines)
    mocks.set_cursor(50, 0)
    mocks.set_window_size(20, 80)
    mocks.set_topline(40)
    scroll = require('whisk.calculators.scroll')
  end)

  local function make_context(topline, cursor_line, count)
    return {
      cursor = { line = cursor_line, col = 0 },
      viewport = { topline = topline, height = 20 },
      input = { count = count or 1 },
      buffer = { line_count = 100 },
    }
  end

  it('exports ctrl_e and ctrl_y', function()
    assert.is_type(scroll.ctrl_e, 'function')
    assert.is_type(scroll.ctrl_y, 'function')
  end)

  it('ctrl_e moves the topline down by count', function()
    local result = scroll.ctrl_e(make_context(40, 50, 3))
    assert.equals(result.viewport.topline, 43)
  end)

  it('ctrl_e leaves a deep cursor untouched', function()
    local result = scroll.ctrl_e(make_context(40, 55, 1))
    assert.equals(result.cursor.line, 55)
  end)

  it('ctrl_e pulls the cursor to keep scrolloff from the top', function()
    local result = scroll.ctrl_e(make_context(40, 42, 1))
    assert.equals(result.viewport.topline, 41)
    assert.equals(result.cursor.line, 46)
  end)

  it('ctrl_e clamps the topline to the last line', function()
    local result = scroll.ctrl_e(make_context(98, 100, 10))
    assert.equals(result.viewport.topline, 100)
  end)

  it('ctrl_y moves the topline up by count', function()
    local result = scroll.ctrl_y(make_context(40, 50, 3))
    assert.equals(result.viewport.topline, 37)
  end)

  it('ctrl_y leaves a high cursor untouched', function()
    local result = scroll.ctrl_y(make_context(40, 45, 1))
    assert.equals(result.cursor.line, 45)
  end)

  it('ctrl_y pulls the cursor to keep scrolloff from the bottom', function()
    local result = scroll.ctrl_y(make_context(40, 57, 1))
    assert.equals(result.viewport.topline, 39)
    assert.equals(result.cursor.line, 53)
  end)

  it('ctrl_y clamps the topline to line 1', function()
    local result = scroll.ctrl_y(make_context(2, 5, 10))
    assert.equals(result.viewport.topline, 1)
  end)

  it('ctrl_e and ctrl_y preserve the column', function()
    local ctx = make_context(40, 50, 1)
    ctx.cursor.col = 7
    assert.equals(scroll.ctrl_e(ctx).cursor.col, 7)
    assert.equals(scroll.ctrl_y(ctx).cursor.col, 7)
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/registry/builtin_spec.lua`:

```lua
describe('registry/builtin line scroll motions', function()
  local builtin
  local motions

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    builtin = require('whisk.registry.builtin')
    motions = require('whisk.registry.motions')
    motions.clear()
    require('whisk.registry.traits').clear()
    builtin.register_all()
  end)

  it('registers scroll_ctrl_e and scroll_ctrl_y in the scroll category', function()
    for _, id in ipairs({ 'scroll_ctrl_e', 'scroll_ctrl_y' }) do
      local motion = motions.get(id)
      assert.is_not_nil(motion, id .. ' should be registered')
      assert.equals(motion.category, 'scroll')
    end
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: `scroll.ctrl_e`/`scroll.ctrl_y` are nil and the builtin test reports the two ids as unregistered.
- [ ] In `lua/whisk/calculators/scroll.lua`, add after the existing `calculate_topline` local:

```lua
local function get_scrolloff(context)
  local ok, value = pcall(vim.api.nvim_win_get_option, context.winid or 0, "scrolloff")
  if ok and type(value) == "number" and value >= 0 then
    return value
  end
  return vim.api.nvim_get_option("scrolloff") or 0
end
```

and add the two calculators after `M.ctrl_b`:

```lua
function M.ctrl_e(context)
  local scrolloff = get_scrolloff(context)
  local target_topline = math.min(context.viewport.topline + context.input.count, context.buffer.line_count)
  local min_line = math.min(target_topline + scrolloff, context.buffer.line_count)
  local target_line = math.max(context.cursor.line, min_line)
  return {
    cursor = { line = target_line, col = context.cursor.col },
    viewport = { topline = target_topline },
  }
end

function M.ctrl_y(context)
  local scrolloff = get_scrolloff(context)
  local target_topline = math.max(context.viewport.topline - context.input.count, 1)
  local bottom = target_topline + context.viewport.height - 1
  local max_line = math.max(bottom - scrolloff, 1)
  local target_line = math.min(context.cursor.line, max_line)
  return {
    cursor = { line = target_line, col = context.cursor.col },
    viewport = { topline = target_topline },
  }
end
```

- [ ] In `lua/whisk/registry/builtin.lua`, add inside `M.register_motions` after the `scroll_ctrl_b` registration:

```lua
  motions.register({
    id = "scroll_ctrl_e",
    keys = { "<C-e>" },
    modes = { "n", "v" },
    traits = { "cursor", "scroll" },
    category = "scroll",
    calculator = calculators.scroll.ctrl_e,
    description = "scroll down one line",
    input = "count",
  })

  motions.register({
    id = "scroll_ctrl_y",
    keys = { "<C-y>" },
    modes = { "n", "v" },
    traits = { "cursor", "scroll" },
    category = "scroll",
    calculator = calculators.scroll.ctrl_y,
    description = "scroll up one line",
    input = "count",
  })
```

- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures.
- [ ] Create the headless fidelity probe `tests/nvim/specs/scroll_line_motions_spec.lua` (`normal!` bypasses mappings, so the native measurement is unaffected by whisk's keymaps):

```lua
local function fail(message)
  io.write("FAIL: " .. message .. "\n")
  vim.cmd("cquit! 1")
end

local function expect_equals(actual, expected, label)
  if actual ~= expected then
    fail(label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
  end
  io.write("OK: " .. label .. "\n")
end

vim.o.scrolloff = 3
require("whisk").setup({ cursor = { duration = 30 }, scroll = { duration = 30 } })
local orchestrator = require("whisk.engine.orchestrator")

local lines = {}
for i = 1, 300 do
  lines[i] = "line " .. i
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 150, 0 })
vim.cmd("normal! zz")

local view = vim.fn.winsaveview()
vim.cmd('execute "normal! 3\\<C-e>"')
local native_topline = vim.fn.line("w0")
local native_cursor = vim.api.nvim_win_get_cursor(0)
vim.fn.winrestview(view)

orchestrator.execute("scroll_ctrl_e", { count = 3, direction = "<C-e>" })
local settled = vim.wait(1000, function()
  return vim.fn.line("w0") == native_topline
end, 10)
if not settled then
  fail("ctrl_e did not animate to the native topline")
end
expect_equals(vim.fn.line("w0"), native_topline, "3<C-e> topline matches native")
expect_equals(vim.api.nvim_win_get_cursor(0)[1], native_cursor[1], "3<C-e> cursor matches native")

view = vim.fn.winsaveview()
vim.cmd('execute "normal! 5\\<C-y>"')
native_topline = vim.fn.line("w0")
native_cursor = vim.api.nvim_win_get_cursor(0)
vim.fn.winrestview(view)

orchestrator.execute("scroll_ctrl_y", { count = 5, direction = "<C-y>" })
settled = vim.wait(1000, function()
  return vim.fn.line("w0") == native_topline
end, 10)
if not settled then
  fail("ctrl_y did not animate to the native topline")
end
expect_equals(vim.fn.line("w0"), native_topline, "5<C-y> topline matches native")
expect_equals(vim.api.nvim_win_get_cursor(0)[1], native_cursor[1], "5<C-y> cursor matches native")

io.write("SPEC PASS: scroll_line_motions\n")
```

- [ ] Run the probe from the repo root and confirm all `OK:` lines plus `SPEC PASS: scroll_line_motions` print with exit code 0:

```
nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/scroll_line_motions_spec.lua" +"qa!"
```

- [ ] Update the `README.md` Motion IDs table (section `### Motion IDs`) — replace the `Search`, `Screen`, and `Scroll` rows and add a `Mark` row so the table reads:

```markdown
| Category | IDs |
|----------|-----|
| Basic | `basic_h`, `basic_j`, `basic_k`, `basic_l`, `basic_0`, `basic_$` |
| Word | `word_w`, `word_b`, `word_e`, `word_W`, `word_B`, `word_E` |
| Find | `find_f`, `find_F`, `find_t`, `find_T` |
| Text Object | `text_object_{`, `text_object_}`, `text_object_(`, `text_object_)`, `text_object_%` |
| Line | `line_gg`, `line_G`, `line_\|` |
| Search | `search_n`, `search_N`, `search_star`, `search_hash` |
| Screen | `screen_gj`, `screen_gk`, `screen_H`, `screen_M`, `screen_L` |
| Mark | `mark_backtick`, `mark_quote` |
| Scroll | `scroll_ctrl_d`, `scroll_ctrl_u`, `scroll_ctrl_f`, `scroll_ctrl_b`, `scroll_ctrl_e`, `scroll_ctrl_y`, `position_zz`, `position_zt`, `position_zb` |
```

and add this bullet to the `## Behavior notes` section:

```markdown
- `*` and `#` update the search register `@/` and `'hlsearch'` exactly like native — that side effect is intentional. Backtick/quote mark jumps animate only for in-buffer marks; marks in another buffer fall back to the native buffer switch.
```

- [ ] Update `doc/whisk.txt`: in the motions/motion-id listing section, add `H` `M` `L` (screen position), `*` `#` (search word under cursor, jump), `` ` `` `'` (mark jumps, char input, in-buffer only, jump), and `CTRL-E` `CTRL-Y` (line scroll) entries with their motion ids (`screen_H`, `screen_M`, `screen_L`, `search_star`, `search_hash`, `mark_backtick`, `mark_quote`, `scroll_ctrl_e`, `scroll_ctrl_y`), noting the `@/` side effect for `*`/`#` and the cross-buffer fallback for marks, matching the file's existing entry format.
- [ ] Run `bash scripts/run_tests.sh` once more — all tests pass.
- [ ] Commit: `git add lua/whisk/calculators/scroll.lua lua/whisk/registry/builtin.lua tests/unit/calculators/scroll_spec.lua tests/unit/registry/builtin_spec.lua tests/nvim/specs/scroll_line_motions_spec.lua README.md doc/whisk.txt && git commit -m "feat(calculators): line scroll motions CTRL-E and CTRL-Y"`

---

### Task 8: Horizontal scroll animation — leftcol threading and zh/zl/zH/zL (#44)

**Files:**
- Modify: `lua/whisk/context/builder.lua`, `lua/whisk/engine/loop.lua`, `lua/whisk/engine/orchestrator.lua`, `lua/whisk/registry/builtin.lua`, `lua/whisk/calculators/scroll.lua`, `tests/mocks/vim_fn.lua`, `tests/mocks/vim_api.lua`, `tests/mocks/init.lua`, `README.md`, `doc/whisk.txt`
- Create: `tests/nvim/specs/horizontal_scroll_spec.lua`
- Test: `tests/unit/context/builder_spec.lua`, `tests/unit/engine/loop_spec.lua`, `tests/unit/engine/orchestrator_spec.lua`, `tests/unit/calculators/scroll_spec.lua`, `tests/unit/registry/builtin_spec.lua`

**Interfaces:**
- Produces: `context.viewport.leftcol` (snapshot at build time); `interpolate_result` lerps `viewport.leftcol` when the result carries one; the builtin scroll trait passes `result.viewport.leftcol` as `set_topline`'s second argument (nil = preserve; the trait stays topline-only per Wave 4, with the cursor trait as sole cursor writer); orchestrator `is_same_viewport` treats a leftcol change as a viewport change; `calculators.scroll.zh/zl/zH/zL(context) -> { cursor, viewport = { topline, leftcol } } | nil` (nil when `'wrap'` is set — native horizontal scrolling does nothing under wrap, and a nil result makes the orchestrator do nothing, which matches). zh/zl move leftcol by `-`/`+` count; zH/zL by half the window width. The cursor column is pulled along only far enough to stay inside `[leftcol, leftcol + width - 1]` (approximates native, ignoring `'sidescrolloff'` and gutter width — exact in default setups where `sidescrolloff = 0`). Motion ids `scroll_zh`, `scroll_zl` (input `count`), `scroll_zH`, `scroll_zL` — modes n, category `scroll`, traits `{ "cursor", "scroll" }`.
- Consumes: Wave 4's `Context:set_topline(topline)` — this task extends it to `set_topline(topline, leftcol)` (nil leftcol preserves the window's current leftcol). `Context:restore_view(topline, line, col)` is unchanged (Wave 2 reads leftcol from `self.viewport.leftcol`).
- Mock additions: `mocks.set_leftcol(leftcol)`, `mocks.set_window_option(option, value)`; mock `vim.fn.winsaveview` returns the tracked leftcol, mock `vim.fn.winrestview` stores `view.leftcol`, mock `vim.api.nvim_win_get_option` backed by `window_options` (default `{ wrap = false }`).

**Steps:**

- [ ] In `tests/mocks/vim_fn.lua`: add `leftcol = 0,` to the `state` table literal (initial and in `M.reset`); add this helper after `M.set_mark`:

```lua
function M.set_leftcol(leftcol)
  state.leftcol = leftcol
end
```

then in `M.create()` replace `winrestview` and `winsaveview` with:

```lua
    winrestview = function(view)
      if view.topline then
        state.topline = view.topline
      end
      if view.leftcol then
        state.leftcol = view.leftcol
      end
    end,

    winsaveview = function()
      return {
        topline = state.topline,
        lnum = get_api_state().cursor[1],
        col = get_api_state().cursor[2],
        leftcol = state.leftcol,
      }
    end,
```

- [ ] In `tests/mocks/vim_api.lua`: add `window_options = { wrap = false },` to the `state` table literal (initial and in `M.reset`); add this helper after `M.set_buffer_var`:

```lua
function M.set_window_option(option, value)
  state.window_options[option] = value
end
```

and add to the table returned by `M.create()`:

```lua
    nvim_win_get_option = function(winid, option)
      return state.window_options[option]
    end,
```

- [ ] In `tests/mocks/init.lua`, add after `M.set_mark`:

```lua
function M.set_leftcol(leftcol)
  vim_fn.set_leftcol(leftcol)
end

function M.set_window_option(option, value)
  vim_api.set_window_option(option, value)
end
```

- [ ] Append this suite to the end of `tests/unit/calculators/scroll_spec.lua`:

```lua
describe('calculators/scroll horizontal', function()
  local scroll

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 100 do
      lines[i] = string.rep("x", 300)
    end
    mocks.set_buffer_content(lines)
    mocks.set_cursor(50, 0)
    mocks.set_window_size(20, 80)
    mocks.set_topline(40)
    scroll = require('whisk.calculators.scroll')
  end)

  local function make_context(leftcol, cursor_col, count)
    return {
      winid = 1000,
      cursor = { line = 50, col = cursor_col or 0 },
      viewport = { topline = 40, height = 20, width = 80, leftcol = leftcol },
      input = { count = count or 1 },
      buffer = { line_count = 100 },
    }
  end

  it('exports zh, zl, zH and zL', function()
    assert.is_type(scroll.zh, 'function')
    assert.is_type(scroll.zl, 'function')
    assert.is_type(scroll.zH, 'function')
    assert.is_type(scroll.zL, 'function')
  end)

  it('zl increases leftcol by count', function()
    local result = scroll.zl(make_context(10, 40, 3))
    assert.equals(result.viewport.leftcol, 13)
    assert.equals(result.viewport.topline, 40)
  end)

  it('zh decreases leftcol by count', function()
    local result = scroll.zh(make_context(10, 40, 3))
    assert.equals(result.viewport.leftcol, 7)
  end)

  it('zh clamps leftcol at zero', function()
    local result = scroll.zh(make_context(2, 40, 10))
    assert.equals(result.viewport.leftcol, 0)
  end)

  it('zL scrolls half the window width right', function()
    local result = scroll.zL(make_context(10, 60))
    assert.equals(result.viewport.leftcol, 50)
  end)

  it('zH scrolls half the window width left', function()
    local result = scroll.zH(make_context(50, 60))
    assert.equals(result.viewport.leftcol, 10)
  end)

  it('zl pulls the cursor right when it would fall off the left edge', function()
    local result = scroll.zl(make_context(0, 2, 10))
    assert.equals(result.viewport.leftcol, 10)
    assert.equals(result.cursor.col, 10)
  end)

  it('zh pulls the cursor left when it would fall off the right edge', function()
    local result = scroll.zh(make_context(100, 190, 50))
    assert.equals(result.viewport.leftcol, 50)
    assert.equals(result.cursor.col, 129)
  end)

  it('returns nil when wrap is enabled', function()
    mocks.set_window_option('wrap', true)
    assert.is_nil(scroll.zh(make_context(10, 40)))
    assert.is_nil(scroll.zl(make_context(10, 40)))
    assert.is_nil(scroll.zH(make_context(10, 40)))
    assert.is_nil(scroll.zL(make_context(10, 40)))
  end)
end)
```

- [ ] Append this test to the end of `tests/unit/context/builder_spec.lua` (inside a new appended suite):

```lua
describe('context/builder leftcol snapshot', function()
  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({ 'line 1', 'line 2', 'line 3' })
    mocks.set_cursor(1, 0)
    mocks.set_window_size(40, 120)
    mocks.set_topline(1)
  end)

  it('captures the current leftcol into viewport', function()
    mocks.set_leftcol(12)
    local builder = require('whisk.context.builder')
    local ctx = builder.build({ count = 1 })
    assert.equals(ctx.viewport.leftcol, 12)
  end)

  it('defaults leftcol to zero', function()
    local builder = require('whisk.context.builder')
    local ctx = builder.build({ count = 1 })
    assert.equals(ctx.viewport.leftcol, 0)
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/engine/loop_spec.lua`:

```lua
describe('engine/loop leftcol interpolation', function()
  local loop

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    loop = require('whisk.engine.loop')
    loop.stop_all()
  end)

  it('complete_all applies the final leftcol through the scroll trait', function()
    local traits = require('whisk.registry.traits')
    local applied_leftcol = nil
    traits.register({
      id = 'scroll',
      apply = function(context, result, progress)
        if result.viewport then
          applied_leftcol = result.viewport.leftcol
        end
      end,
    })

    loop.start({
      duration = 100,
      easing = 'linear',
      context = { viewport = { topline = 1, leftcol = 0 } },
      result = { viewport = { topline = 1, leftcol = 12 } },
      traits = { 'scroll' },
    })

    loop.complete_all()
    assert.equals(applied_leftcol, 12)
  end)

  it('leftcol interpolation defaults a missing start leftcol to zero', function()
    local traits = require('whisk.registry.traits')
    local applied_leftcol = nil
    traits.register({
      id = 'scroll',
      apply = function(context, result, progress)
        if result.viewport then
          applied_leftcol = result.viewport.leftcol
        end
      end,
    })

    loop.start({
      duration = 100,
      easing = 'linear',
      context = { viewport = { topline = 1 } },
      result = { viewport = { topline = 1, leftcol = 8 } },
      traits = { 'scroll' },
    })

    loop.complete_all()
    assert.equals(applied_leftcol, 8)
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/engine/orchestrator_spec.lua`:

```lua
describe('engine/orchestrator leftcol viewport detection', function()
  local orchestrator
  local motions
  local traits
  local loop

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({ 'line 1', 'line 2', 'line 3' })
    mocks.set_cursor(1, 0)
    mocks.set_window_size(20, 80)
    mocks.set_topline(1)

    motions = require('whisk.registry.motions')
    traits = require('whisk.registry.traits')
    loop = require('whisk.engine.loop')
    orchestrator = require('whisk.engine.orchestrator')

    motions.clear()
    traits.clear()
    loop.stop_all()

    traits.register({ id = 'scroll', apply = function() end })

    require('whisk.config').update({ scroll = { enabled = true } })
  end)

  it('a leftcol-only change is not swallowed by the early exit', function()
    motions.register({
      id = 'test_zl',
      keys = { 'zl' },
      modes = { 'n' },
      traits = { 'scroll' },
      category = 'scroll',
      calculator = function(ctx)
        return {
          cursor = { line = ctx.cursor.line, col = ctx.cursor.col },
          viewport = { topline = ctx.viewport.topline, leftcol = (ctx.viewport.leftcol or 0) + 5 },
        }
      end,
    })

    orchestrator.execute('test_zl', {})
    assert.is_true(loop.is_running())
  end)

  it('an unchanged leftcol still exits early', function()
    motions.register({
      id = 'test_zl_same',
      keys = { 'zl' },
      modes = { 'n' },
      traits = { 'scroll' },
      category = 'scroll',
      calculator = function(ctx)
        return {
          cursor = { line = ctx.cursor.line, col = ctx.cursor.col },
          viewport = { topline = ctx.viewport.topline, leftcol = ctx.viewport.leftcol or 0 },
        }
      end,
    })

    orchestrator.execute('test_zl_same', {})
    assert.is_false(loop.is_running())
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/registry/builtin_spec.lua`:

```lua
describe('registry/builtin horizontal scroll motions', function()
  local builtin
  local motions

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    builtin = require('whisk.registry.builtin')
    motions = require('whisk.registry.motions')
    motions.clear()
    require('whisk.registry.traits').clear()
    builtin.register_all()
  end)

  it('registers scroll_zh, scroll_zl, scroll_zH and scroll_zL', function()
    for _, id in ipairs({ 'scroll_zh', 'scroll_zl', 'scroll_zH', 'scroll_zL' }) do
      local motion = motions.get(id)
      assert.is_not_nil(motion, id .. ' should be registered')
      assert.equals(motion.category, 'scroll')
    end
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: horizontal calculators are nil, builder does not expose `viewport.leftcol`, the leftcol-only orchestrator test finds the animation swallowed, the loop tests see `applied_leftcol` nil, and the builtin ids are unregistered.
- [ ] In `lua/whisk/context/builder.lua`, add this local above `M.build`:

```lua
local function window_leftcol(winid)
  local leftcol = 0
  vim.api.nvim_win_call(winid, function()
    local view = vim.fn.winsaveview()
    if view and view.leftcol then
      leftcol = view.leftcol
    end
  end)
  return leftcol
end
```

and add `leftcol = window_leftcol(ctx.winid),` as a new entry inside the `ctx.viewport = { ... }` table (alongside `topline`, `height`, `width`).
- [ ] In `lua/whisk/engine/loop.lua`, extend the branch's `interpolate_result` — after Wave 4 it is the in-place form `interpolate_result(anim, progress)` writing into the pooled `anim.interpolated` scratch table; do NOT reintroduce per-frame table allocation. Add this block immediately after the existing topline interpolation, using the same local names the branch's function uses for the context/result (shown here as `context`/`result`; mirror the branch):

```lua
  if result.viewport and result.viewport.leftcol then
    local start_leftcol = (context.viewport and context.viewport.leftcol) or 0
    interpolated.viewport.leftcol = math.floor(lerp(start_leftcol, result.viewport.leftcol, progress) + 0.5)
  end
```

Then in `lua/whisk/engine/pool.lua`, add `animation.interpolated.viewport.leftcol = nil` alongside the existing scratch-field zeroing in `release` (Wave 4 zeroes `topline`/`line`/`col` there; leftcol joins them so a pooled object never leaks a stale leftcol into an animation that has none).

- [ ] In `lua/whisk/context/Context.lua`, extend Wave 4's `Context:set_topline` to accept an optional second parameter: signature becomes `set_topline(topline, leftcol)`. Keep the method's existing body exactly as it is on the branch (clamping, `nvim_win_call` + `winrestview`, caller-validates contract) and add `leftcol = leftcol` to the `winrestview` payload table only when `leftcol` is non-nil, so nil preserves the window's current leftcol.

- [ ] In `lua/whisk/registry/builtin.lua`, replace the scroll trait registration inside `M.register_traits` with (this preserves Wave 4's topline-only scroll trait — the cursor trait remains the sole cursor writer — and threads the interpolated leftcol through `set_topline`'s second argument; nil preserves the window's current leftcol):

```lua
  traits.register({
    id = "scroll",
    apply = function(context, result, progress)
      if result.viewport and result.viewport.topline and context.set_topline then
        context:set_topline(result.viewport.topline, result.viewport.leftcol)
      end
    end,
  })
```

- [ ] In `lua/whisk/engine/orchestrator.lua`, replace `is_same_viewport` with:

```lua
local function is_same_viewport(context, result)
  if not result.viewport then
    return true
  end
  if result.viewport.topline and context.viewport.topline ~= result.viewport.topline then
    return false
  end
  if result.viewport.leftcol and (context.viewport.leftcol or 0) ~= result.viewport.leftcol then
    return false
  end
  return true
end
```

- [ ] In `lua/whisk/calculators/scroll.lua`, add after `M.ctrl_y`:

```lua
local function is_wrap_enabled(context)
  local ok, wrap = pcall(vim.api.nvim_win_get_option, context.winid or 0, "wrap")
  return ok and wrap == true
end

local function horizontal_result(context, target_leftcol)
  local clamped_leftcol = math.max(target_leftcol, 0)
  local right_edge = clamped_leftcol + context.viewport.width - 1
  local target_col = math.min(math.max(context.cursor.col, clamped_leftcol), right_edge)
  return {
    cursor = { line = context.cursor.line, col = target_col },
    viewport = { topline = context.viewport.topline, leftcol = clamped_leftcol },
  }
end

function M.zh(context)
  if is_wrap_enabled(context) then
    return nil
  end
  return horizontal_result(context, (context.viewport.leftcol or 0) - context.input.count)
end

function M.zl(context)
  if is_wrap_enabled(context) then
    return nil
  end
  return horizontal_result(context, (context.viewport.leftcol or 0) + context.input.count)
end

function M.zH(context)
  if is_wrap_enabled(context) then
    return nil
  end
  return horizontal_result(context, (context.viewport.leftcol or 0) - math.floor(context.viewport.width / 2))
end

function M.zL(context)
  if is_wrap_enabled(context) then
    return nil
  end
  return horizontal_result(context, (context.viewport.leftcol or 0) + math.floor(context.viewport.width / 2))
end
```

- [ ] In `lua/whisk/registry/builtin.lua`, add inside `M.register_motions` after the `position_zb` registration:

```lua
  motions.register({
    id = "scroll_zh",
    keys = { "zh" },
    modes = { "n" },
    traits = { "cursor", "scroll" },
    category = "scroll",
    calculator = calculators.scroll.zh,
    description = "scroll left",
    input = "count",
  })

  motions.register({
    id = "scroll_zl",
    keys = { "zl" },
    modes = { "n" },
    traits = { "cursor", "scroll" },
    category = "scroll",
    calculator = calculators.scroll.zl,
    description = "scroll right",
    input = "count",
  })

  motions.register({
    id = "scroll_zH",
    keys = { "zH" },
    modes = { "n" },
    traits = { "cursor", "scroll" },
    category = "scroll",
    calculator = calculators.scroll.zH,
    description = "scroll half width left",
  })

  motions.register({
    id = "scroll_zL",
    keys = { "zL" },
    modes = { "n" },
    traits = { "cursor", "scroll" },
    category = "scroll",
    calculator = calculators.scroll.zL,
    description = "scroll half width right",
  })
```

- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures.
- [ ] Create the headless probe `tests/nvim/specs/horizontal_scroll_spec.lua` (real leftcol rendering, wrap behavior, and the leftcol-preservation regression need a real editor):

```lua
local function fail(message)
  io.write("FAIL: " .. message .. "\n")
  vim.cmd("cquit! 1")
end

local function expect_equals(actual, expected, label)
  if actual ~= expected then
    fail(label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
  end
  io.write("OK: " .. label .. "\n")
end

vim.wo.wrap = false
require("whisk").setup({ cursor = { duration = 30 }, scroll = { duration = 30 } })
local orchestrator = require("whisk.engine.orchestrator")
local loop = require("whisk.engine.loop")

local lines = {}
for i = 1, 200 do
  lines[i] = string.rep("x", 400)
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 100, 50 })

orchestrator.execute("scroll_zl", { count = 10, direction = "zl" })
local scrolled = vim.wait(1000, function()
  return vim.fn.winsaveview().leftcol == 10
end, 10)
if not scrolled then
  fail("zl did not animate leftcol to 10")
end
io.write("OK: zl animates leftcol\n")

orchestrator.execute("scroll_zh", { count = 4, direction = "zh" })
scrolled = vim.wait(1000, function()
  return vim.fn.winsaveview().leftcol == 6
end, 10)
if not scrolled then
  fail("zh did not animate leftcol back to 6")
end
io.write("OK: zh animates leftcol\n")

vim.fn.winrestview({ leftcol = 10 })
vim.cmd("normal! zt")
orchestrator.execute("position_zz", { count = 1, direction = "zz" })
local recentred = vim.wait(1000, function()
  return vim.fn.line("w0") < 100
end, 10)
if not recentred then
  fail("zz did not animate after zt")
end
expect_equals(vim.fn.winsaveview().leftcol, 10, "vertical scroll preserves an existing leftcol")

vim.wo.wrap = true
local before = vim.fn.winsaveview().leftcol
orchestrator.execute("scroll_zl", { count = 5, direction = "zl" })
expect_equals(loop.get_active_count(), 0, "zl does nothing when wrap is set")
expect_equals(vim.fn.winsaveview().leftcol, before, "leftcol unchanged under wrap")

io.write("SPEC PASS: horizontal_scroll\n")
```

- [ ] Run the probe from the repo root and confirm all `OK:` lines plus `SPEC PASS: horizontal_scroll` print with exit code 0:

```
nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/horizontal_scroll_spec.lua" +"qa!"
```

- [ ] Update `README.md`: in the Motion IDs table, replace the `Scroll` row with:

```markdown
| Scroll | `scroll_ctrl_d`, `scroll_ctrl_u`, `scroll_ctrl_f`, `scroll_ctrl_b`, `scroll_ctrl_e`, `scroll_ctrl_y`, `scroll_zh`, `scroll_zl`, `scroll_zH`, `scroll_zL`, `position_zz`, `position_zt`, `position_zb` |
```

and add this bullet to `## Behavior notes`:

```markdown
- Horizontal scroll motions (`zh`, `zl`, `zH`, `zL`) animate the view's `leftcol` and do nothing when `'wrap'` is set, matching native behavior.
```

- [ ] Update `doc/whisk.txt`: add `zh`/`zl`/`zH`/`zL` entries (ids `scroll_zh`, `scroll_zl`, `scroll_zH`, `scroll_zL`) to the motion listing, noting they are no-ops when `'wrap'` is set, matching the file's existing entry format.
- [ ] Run `bash scripts/run_tests.sh` once more — all tests pass.
- [ ] Commit: `git add lua/whisk/context/builder.lua lua/whisk/engine/loop.lua lua/whisk/engine/orchestrator.lua lua/whisk/registry/builtin.lua lua/whisk/calculators/scroll.lua tests/mocks/vim_fn.lua tests/mocks/vim_api.lua tests/mocks/init.lua tests/unit/context/builder_spec.lua tests/unit/engine/loop_spec.lua tests/unit/engine/orchestrator_spec.lua tests/unit/calculators/scroll_spec.lua tests/unit/registry/builtin_spec.lua tests/nvim/specs/horizontal_scroll_spec.lua README.md doc/whisk.txt && git commit -m "feat(engine): animate horizontal scroll with zh, zl, zH and zL"`

---

### Task 9: Public `whisk.animate_to` API (#22)

**Files:**
- Modify: `lua/whisk/init.lua`, `lua/whisk/context/builder.lua`, `lua/whisk/calculators/scroll.lua`, `README.md`, `doc/whisk.txt`
- Create: `tests/nvim/specs/animate_to_spec.lua`
- Test: `tests/unit/init_spec.lua`, `tests/unit/context/builder_spec.lua`, `tests/unit/calculators/scroll_spec.lua`

**Interfaces:**
- Produces: `whisk.animate_to(opts: WhiskAnimateToOpts): boolean` where `opts = { line, col?, winid?, duration?, easing? }` — validates inputs (returns false on bad shapes), builds a context for the target window, constructs a `{ cursor, viewport }` result whose topline keeps the target visible (current topline if already visible, else centered via the scroll calculators' centering helper), starts a cursor+scroll animation through the loop, returns whether an animation started. When the cursor category is disabled it applies the final frame synchronously through the traits and returns false. `context_builder.build_for_window(winid, input)` — same population as `build` but bound to an explicit window. `calculators.scroll.center_topline(target_line, context): number` — the exported centering helper (the internal `calculate_topline` delegates to it).
- Consumes: `duration_engine.resolve`/`.distance` (Task 2), `validate`-equivalent inline shape checks matching Tasks 1–2 (function-or-name easing, number-or-spec duration), per-(trait, winid) animating state (Wave 4/5 — mirror `orchestrator.execute`'s call shape), `traits.apply_frame`, `loop.start` (the extra `motion_id = "animate_to"` option is inert until Task 10 wires it).

**Steps:**

- [ ] In `lua/whisk/calculators/scroll.lua`, export the centering helper and delegate the existing local to it. Add directly above the `local function calculate_topline` definition:

```lua
function M.center_topline(target_line, context)
  local win_height = context.viewport.height
  local topline = target_line - math.floor(win_height / 2)
  return math.max(1, math.min(topline, context.buffer.line_count - win_height + 1))
end
```

and replace the `calculate_topline` local's body with a delegation:

```lua
local function calculate_topline(target_line, context)
  return M.center_topline(target_line, context)
end
```

(`M` must be defined before `M.center_topline`; the file already opens with `local M = {}`, so place `M.center_topline` after that line and before `calculate_topline`.)
- [ ] Append this test to the horizontal suite added to `tests/unit/calculators/scroll_spec.lua` in Task 8 (as an additional `it` block inside `describe('calculators/scroll horizontal', ...)`), or as its own appended suite with the same `before_each` — either placement is acceptable as long as it runs:

```lua
  it('exports center_topline and centers the target', function()
    local ctx = {
      cursor = { line = 50, col = 0 },
      viewport = { topline = 40, height = 20 },
      input = { count = 1 },
      buffer = { line_count = 100 },
    }
    assert.equals(scroll.center_topline(50, ctx), 40)
    assert.equals(scroll.center_topline(5, ctx), 1)
    assert.equals(scroll.center_topline(99, ctx), 81)
  end)
```

- [ ] In `lua/whisk/context/builder.lua`, refactor `M.build` into a shared populate function plus a window-explicit variant. The populate body is the current body of `M.build` with `Context.new()` factored out — carry over **every** field the current `build` copies (including `has_count` from Wave 1 and `leftcol` from Task 8, plus any other input fields earlier waves added):

```lua
local function populate(ctx, input)
  ctx.input = {
    char = input.char,
    count = input.count or 1,
    direction = input.direction,
    has_count = input.has_count or false,
  }

  ctx.cursor = {
    line = ctx.start.cursor[1],
    col = ctx.start.cursor[2],
  }

  ctx.viewport = {
    topline = ctx.start.topline,
    height = vim.api.nvim_win_get_height(ctx.winid),
    width = vim.api.nvim_win_get_width(ctx.winid),
    leftcol = window_leftcol(ctx.winid),
  }

  ctx.buffer = {
    line_count = ctx.start.line_count,
  }

  return ctx
end

function M.build(input)
  return populate(Context.new(), input)
end

function M.build_for_window(winid, input)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  return populate(Context.new(bufnr, winid), input)
end
```

- [ ] Append this suite to the end of `tests/unit/context/builder_spec.lua`:

```lua
describe('context/builder build_for_window', function()
  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    mocks.set_buffer_content({ 'line 1', 'line 2', 'line 3' })
    mocks.set_cursor(2, 1)
    mocks.set_window_size(40, 120)
    mocks.set_topline(1)
  end)

  it('binds the requested window and populates all context fields', function()
    local builder = require('whisk.context.builder')
    local ctx = builder.build_for_window(1000, { count = 2 })
    assert.equals(ctx.winid, 1000)
    assert.equals(ctx.input.count, 2)
    assert.equals(ctx.cursor.line, 2)
    assert.is_not_nil(ctx.viewport.topline)
    assert.is_not_nil(ctx.viewport.leftcol)
    assert.is_not_nil(ctx.buffer.line_count)
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/init_spec.lua`:

```lua
describe('init animate_to', function()
  local whisk

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    mocks.set_buffer_content(lines)
    mocks.set_cursor(1, 0)
    mocks.set_window_size(20, 80)
    mocks.set_topline(1)
    whisk = require('whisk')
    whisk.setup({})
  end)

  after_each(function()
    whisk.reset()
  end)

  it('exports animate_to', function()
    assert.is_type(whisk.animate_to, 'function')
  end)

  it('returns false for non-table opts', function()
    assert.is_false(whisk.animate_to(nil))
  end)

  it('returns false when line is missing', function()
    assert.is_false(whisk.animate_to({}))
  end)

  it('returns false for an invalid easing shape', function()
    assert.is_false(whisk.animate_to({ line = 50, easing = 123 }))
  end)

  it('returns false for an invalid duration shape', function()
    assert.is_false(whisk.animate_to({ line = 50, duration = 'fast' }))
  end)

  it('returns false when the target equals the current position', function()
    assert.is_false(whisk.animate_to({ line = 1, col = 0 }))
  end)

  it('starts an animation for an on-screen target', function()
    local loop = require('whisk.engine.loop')
    assert.is_true(whisk.animate_to({ line = 10 }))
    assert.is_true(loop.is_running())
  end)

  it('animates an off-screen target to the exact position', function()
    local loop = require('whisk.engine.loop')
    assert.is_true(whisk.animate_to({ line = 80, col = 3 }))
    loop.complete_all()
    local cursor = mocks.get_cursor()
    assert.equals(cursor[1], 80)
    assert.equals(cursor[2], 3)
  end)

  it('centers the viewport for an off-screen target', function()
    local loop = require('whisk.engine.loop')
    whisk.animate_to({ line = 80 })
    loop.complete_all()
    assert.equals(mocks.get_fn_state().topline, 70)
  end)

  it('clamps an out-of-range line', function()
    local loop = require('whisk.engine.loop')
    assert.is_true(whisk.animate_to({ line = 99999 }))
    loop.complete_all()
    assert.equals(mocks.get_cursor()[1], 100)
  end)

  it('applies the position synchronously when cursor animations are disabled', function()
    whisk.disable()
    local loop = require('whisk.engine.loop')
    assert.is_false(whisk.animate_to({ line = 40 }))
    assert.is_false(loop.is_running())
    assert.equals(mocks.get_cursor()[1], 40)
  end)

  it('accepts duration and easing overrides', function()
    local loop = require('whisk.engine.loop')
    assert.is_true(whisk.animate_to({
      line = 60,
      duration = { min = 20, max = 200, per_line = 2 },
      easing = function(t) return t end,
    }))
    assert.is_true(loop.is_running())
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: `whisk.animate_to` is nil (`exports animate_to` fails and every animate_to call errors), `builder.build_for_window` is nil, and `scroll.center_topline` is nil.
- [ ] In `lua/whisk/init.lua`, add the requires after the existing top-of-file requires:

```lua
local context_builder = require("whisk.context.builder")
local scroll_calculators = require("whisk.calculators.scroll")
local duration_engine = require("whisk.engine.duration")
```

and add the API after `M.toggle_performance` (LuaCATS annotations are explicitly called for on this function; `WhiskDurationSpec` is defined in `engine/duration.lua` from Task 2). The `traits.is_animating`/`set_animating` calls must mirror the per-(trait, winid) call shape `orchestrator.execute` uses on this branch:

```lua
---@class WhiskAnimateToOpts
---@field line integer Target line, 1-based
---@field col integer|nil Target column, 0-based byte index, defaults to 0
---@field winid integer|nil Target window, defaults to the current window
---@field duration number|WhiskDurationSpec|nil Duration override for this animation
---@field easing string|fun(t: number): number|nil Easing override for this animation

---Animates the cursor and viewport of a window to an arbitrary position.
---Intended for plugin integrations such as diagnostics jumps, pickers and
---quickfix navigation. When animations are disabled the position is applied
---synchronously and false is returned.
---@param opts WhiskAnimateToOpts
---@return boolean started
function M.animate_to(opts)
  if type(opts) ~= "table" or type(opts.line) ~= "number" then
    return false
  end
  if opts.col ~= nil and type(opts.col) ~= "number" then
    return false
  end
  if opts.winid ~= nil and type(opts.winid) ~= "number" then
    return false
  end
  if opts.duration ~= nil and type(opts.duration) ~= "number" and type(opts.duration) ~= "table" then
    return false
  end
  if opts.easing ~= nil and type(opts.easing) ~= "string" and type(opts.easing) ~= "function" then
    return false
  end

  local winid = opts.winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  local context = context_builder.build_for_window(winid, { count = 1 })
  local target_line = context:clamp_line(math.floor(opts.line))
  local target_col = context:clamp_column(math.floor(opts.col or 0), target_line)

  local topline = context.viewport.topline
  local last_visible = topline + context.viewport.height - 1
  if target_line < topline or target_line > last_visible then
    topline = scroll_calculators.center_topline(target_line, context)
  end

  local result = {
    cursor = { line = target_line, col = target_col },
    viewport = { topline = topline },
  }

  if target_line == context.cursor.line and target_col == context.cursor.col and topline == context.viewport.topline then
    return false
  end

  local animation_traits = { "cursor", "scroll" }

  local category_config = config.get("cursor")
  if not category_config or not category_config.enabled then
    for _, trait_id in ipairs(animation_traits) do
      traits.apply_frame(trait_id, context, result, 1.0)
    end
    return false
  end

  for _, trait_id in ipairs(animation_traits) do
    if traits.is_animating(trait_id, winid) then
      loop.complete_all()
      break
    end
  end

  local duration_config = opts.duration or category_config.duration
  local easing_config = opts.easing or category_config.easing

  for _, trait_id in ipairs(animation_traits) do
    traits.set_animating(trait_id, winid, true)
  end

  local function clear_animating()
    for _, trait_id in ipairs(animation_traits) do
      traits.set_animating(trait_id, winid, false)
    end
  end

  loop.start({
    context = context,
    result = result,
    traits = animation_traits,
    duration = duration_engine.resolve(duration_config, duration_engine.distance(context, result)),
    easing = easing_config,
    motion_id = "animate_to",
    on_complete = clear_animating,
    on_cancel = clear_animating,
  })

  return true
end
```

- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures.
- [ ] Create the headless probe `tests/nvim/specs/animate_to_spec.lua`:

```lua
local function fail(message)
  io.write("FAIL: " .. message .. "\n")
  vim.cmd("cquit! 1")
end

local function expect_equals(actual, expected, label)
  if actual ~= expected then
    fail(label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
  end
  io.write("OK: " .. label .. "\n")
end

local whisk = require("whisk")
whisk.setup({ cursor = { duration = 40 }, scroll = { duration = 40 } })

local lines = {}
for i = 1, 500 do
  lines[i] = "line " .. i
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

expect_equals(whisk.animate_to({ line = 400, col = 2 }), true, "animate_to returns true for a valid off-screen target")
local reached = vim.wait(1000, function()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return cursor[1] == 400 and cursor[2] == 2
end, 10)
if not reached then
  fail("animate_to did not reach the target position")
end
io.write("OK: animate_to lands on the target position\n")

local topline = vim.fn.line("w0")
if not (topline <= 400 and 400 <= topline + vim.fn.winheight(0) - 1) then
  fail("animate_to left the target off-screen")
end
io.write("OK: animate_to keeps the target visible\n")

expect_equals(whisk.animate_to({}), false, "animate_to rejects a missing line")
expect_equals(whisk.animate_to({ line = 400, col = 2 }), false, "animate_to returns false when already at the target")

expect_equals(whisk.animate_to({ line = 1, easing = "quintic", duration = { min = 20, max = 120, per_line = 1 } }), true, "animate_to accepts overrides")
reached = vim.wait(1000, function()
  return vim.api.nvim_win_get_cursor(0)[1] == 1
end, 10)
if not reached then
  fail("animate_to with overrides did not reach the target")
end
io.write("OK: animate_to honors overrides and lands\n")

io.write("SPEC PASS: animate_to\n")
```

- [ ] Run the probe from the repo root and confirm all `OK:` lines plus `SPEC PASS: animate_to` print with exit code 0:

```
nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/animate_to_spec.lua" +"qa!"
```

- [ ] Update `README.md`: in the `## Lua API` section's first code block, add after the `whisk.reset()` line:

```lua
whisk.animate_to({ line = 480, col = 0 })   -- animated jump to an arbitrary position; returns true if an animation started
```

and add this subsection after `### Manual motion execution`:

```markdown
### Animating jumps from other plugins

`animate_to` lets any plugin route a jump through whisk instead of teleporting. It accepts `{ line, col?, winid?, duration?, easing? }`, keeps the target visible (centering the view when the target is off-screen), and returns `true` when an animation started:

```lua
vim.keymap.set("n", "]d", function()
  local diagnostic = vim.diagnostic.get_next()
  if diagnostic then
    require("whisk").animate_to({
      line = diagnostic.lnum + 1,
      col = diagnostic.col,
      duration = { min = 80, max = 300, per_line = 2 },
      easing = "cubic",
    })
  end
end)
```

When animations are disabled the position is applied instantly and `animate_to` returns `false`.
```

- [ ] Update `doc/whisk.txt`: add an `animate_to` entry to the API section with tag `*whisk.animate_to()*`:

```
animate_to({opts})					*whisk.animate_to()*
		Animate the cursor and viewport of a window to an arbitrary
		position. Intended for plugin integrations (diagnostics
		jumps, pickers, quickfix navigation).

		{opts} fields:
		  line	   (number, required) target line, 1-based
		  col	   (number) target column, 0-based, default 0
		  winid	   (number) target window, default current
		  duration (number or {min, max, per_line} table)
		  easing   (string name or Lua function)

		Returns true when an animation started. Off-screen targets
		scroll the view so the target stays visible. When cursor
		animations are disabled the position is applied instantly
		and false is returned.
```

- [ ] Run `bash scripts/run_tests.sh` once more — all tests pass.
- [ ] Commit: `git add lua/whisk/init.lua lua/whisk/context/builder.lua lua/whisk/calculators/scroll.lua tests/unit/init_spec.lua tests/unit/context/builder_spec.lua tests/unit/calculators/scroll_spec.lua tests/nvim/specs/animate_to_spec.lua README.md doc/whisk.txt && git commit -m "feat(api): public animate_to entry point for plugin integrations"`

---

### Task 10: WhiskAnimation User autocmd events and trait lifecycle hooks (#19)

**Files:**
- Create: `lua/whisk/engine/events.lua`, `tests/unit/engine/events_spec.lua`, `tests/nvim/specs/user_events_spec.lua`
- Modify: `lua/whisk/engine/loop.lua`, `lua/whisk/engine/pool.lua`, `lua/whisk/engine/orchestrator.lua`, `lua/whisk/registry/traits.lua`, `tests/mocks/vim_api.lua`, `tests/mocks/init.lua`, `tests/init.lua`, `README.md`, `doc/whisk.txt`
- Test: `tests/unit/engine/events_spec.lua`, `tests/unit/engine/loop_spec.lua`, `tests/unit/registry/traits_spec.lua`

**Interfaces:**
- Produces: `events.START/COMPLETE/CANCEL` pattern constants (`"WhiskAnimationStart"`, `"WhiskAnimationComplete"`, `"WhiskAnimationCancel"`); `events.emit(pattern: string, payload: table)` — fires `nvim_exec_autocmds("User", { pattern = pattern, data = payload })` wrapped in pcall, with the `data` field feature-detected once at load (Neovim 0.8 builds that reject `data` still get the event, just without payload). Loop fires START on `M.start`, COMPLETE on the `progress >= 1.0` branch and in `complete_all`, CANCEL in the invalid-context path, `cancel_for_buffer`, `cancel_for_window`, and `stop_all`; payload is `{ motion_id = ..., traits = ... }` (CANCEL additionally carries `reason`). `loop.start` accepts `motion_id` in its options; the pool zeroes it on release. `traits.notify_start(trait_id, context)` / `traits.notify_complete(trait_id, context)` invoke the previously dead per-trait `on_start`/`on_complete` hooks; the loop calls them alongside the events. Orchestrator passes `motion_id = motion.id` to `loop.start` (animate_to already passes `"animate_to"` from Task 9).
- Consumes: everything previously built — events observe all animation paths.
- Mock additions: mock `vim.api.nvim_exec_autocmds` recording into `state.exec_autocmds`; `mocks.get_exec_autocmds()`.

**Steps:**

- [ ] In `tests/mocks/vim_api.lua`: add `exec_autocmds = {},` to the `state` table literal (initial and in `M.reset`); add this helper after `M.set_window_option`:

```lua
function M.get_exec_autocmds()
  return state.exec_autocmds
end
```

and add to the table returned by `M.create()`:

```lua
    nvim_exec_autocmds = function(event, opts)
      table.insert(state.exec_autocmds, {
        event = event,
        pattern = opts and opts.pattern,
        data = opts and opts.data,
      })
    end,
```

- [ ] In `tests/mocks/init.lua`, add after `M.set_window_option`:

```lua
function M.get_exec_autocmds()
  return vim_api.get_exec_autocmds()
end
```

- [ ] Create `tests/unit/engine/events_spec.lua`:

```lua
local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('engine/events', function()
  local events

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    events = require('whisk.engine.events')
  end)

  it('exports pattern constants', function()
    assert.equals(events.START, 'WhiskAnimationStart')
    assert.equals(events.COMPLETE, 'WhiskAnimationComplete')
    assert.equals(events.CANCEL, 'WhiskAnimationCancel')
  end)

  it('emit fires a User autocmd with pattern and data', function()
    events.emit(events.START, { motion_id = 'test', traits = { 'cursor' } })
    local fired = mocks.get_exec_autocmds()
    local last = fired[#fired]
    assert.equals(last.event, 'User')
    assert.equals(last.pattern, 'WhiskAnimationStart')
    assert.equals(last.data.motion_id, 'test')
  end)

  it('emit never throws when nvim_exec_autocmds is unavailable', function()
    vim.api.nvim_exec_autocmds = nil
    mocks.clear_package_cache()
    events = require('whisk.engine.events')
    assert.does_not_throw(function()
      events.emit(events.START, { motion_id = 'x', traits = {} })
    end)
  end)
end)
```

- [ ] Register the spec in `tests/init.lua`: insert `require('tests.unit.engine.events_spec')` immediately after the `duration_spec` require added in Task 2.
- [ ] Append this suite to the end of `tests/unit/engine/loop_spec.lua`:

```lua
describe('engine/loop user events', function()
  local loop

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    loop = require('whisk.engine.loop')
    loop.stop_all()
  end)

  local function patterns_fired()
    local names = {}
    for _, entry in ipairs(mocks.get_exec_autocmds()) do
      table.insert(names, entry.pattern)
    end
    return names
  end

  it('start emits WhiskAnimationStart with the motion id', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      motion_id = 'basic_j',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    local fired = mocks.get_exec_autocmds()
    local last = fired[#fired]
    assert.equals(last.pattern, 'WhiskAnimationStart')
    assert.equals(last.data.motion_id, 'basic_j')
  end)

  it('complete_all emits WhiskAnimationComplete', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      motion_id = 'basic_j',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.complete_all()
    assert.contains(patterns_fired(), 'WhiskAnimationComplete')
  end)

  it('cancel_for_buffer emits WhiskAnimationCancel with a reason', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      motion_id = 'basic_j',
      context = { bufnr = 1, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.cancel_for_buffer(1)
    local fired = mocks.get_exec_autocmds()
    local last = fired[#fired]
    assert.equals(last.pattern, 'WhiskAnimationCancel')
    assert.equals(last.data.reason, 'buffer_invalidated')
  end)

  it('cancel_for_window emits WhiskAnimationCancel', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      motion_id = 'basic_j',
      context = { bufnr = 1, winid = 1000, cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.cancel_for_window(1000)
    assert.contains(patterns_fired(), 'WhiskAnimationCancel')
  end)

  it('stop_all emits WhiskAnimationCancel', function()
    loop.start({
      duration = 100,
      easing = 'linear',
      motion_id = 'basic_j',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 5, col = 0 } },
      traits = {},
    })

    loop.stop_all()
    assert.contains(patterns_fired(), 'WhiskAnimationCancel')
  end)

  it('trait on_start and on_complete hooks fire', function()
    local traits = require('whisk.registry.traits')
    local started = false
    local completed = false
    traits.register({
      id = 'hooked',
      apply = function() end,
      on_start = function() started = true end,
      on_complete = function() completed = true end,
    })

    loop.start({
      duration = 100,
      easing = 'linear',
      context = { cursor = { line = 1, col = 0 } },
      result = { cursor = { line = 3, col = 0 } },
      traits = { 'hooked' },
    })
    assert.is_true(started)

    loop.complete_all()
    assert.is_true(completed)
  end)
end)
```

- [ ] Append this suite to the end of `tests/unit/registry/traits_spec.lua`:

```lua
describe('registry/traits lifecycle notifications', function()
  local traits

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    traits = require('whisk.registry.traits')
    traits.clear()
  end)

  it('notify_start invokes the on_start hook', function()
    local seen = nil
    traits.register({
      id = 'hooked',
      apply = function() end,
      on_start = function(context) seen = context end,
    })
    traits.notify_start('hooked', { bufnr = 7 })
    assert.equals(seen.bufnr, 7)
  end)

  it('notify_complete invokes the on_complete hook', function()
    local called = false
    traits.register({
      id = 'hooked',
      apply = function() end,
      on_complete = function() called = true end,
    })
    traits.notify_complete('hooked', {})
    assert.is_true(called)
  end)

  it('notifications are safe for unknown traits and missing hooks', function()
    traits.register({ id = 'bare', apply = function() end })
    assert.does_not_throw(function()
      traits.notify_start('bare', {})
      traits.notify_complete('bare', {})
      traits.notify_start('missing', {})
      traits.notify_complete('missing', {})
    end)
  end)
end)
```

- [ ] Run `bash scripts/run_tests.sh` and confirm the failures: the events spec errors with `module 'whisk.engine.events' not found`, the loop event tests find no recorded autocmds (mock recorder returns an empty list; `fired[#fired]` is nil), and `traits.notify_start` is nil.
- [ ] Create `lua/whisk/engine/events.lua` (the load-time probe fires one `User WhiskEventsProbe` event to feature-detect the `data` field on Neovim 0.8; nobody listens to that pattern and both calls are pcall-wrapped):

```lua
local M = {}

M.START = "WhiskAnimationStart"
M.COMPLETE = "WhiskAnimationComplete"
M.CANCEL = "WhiskAnimationCancel"

local function detect_data_support()
  return (pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "WhiskEventsProbe",
    data = { probe = true },
  }))
end

local data_supported = detect_data_support()

function M.emit(pattern, payload)
  local options = { pattern = pattern }
  if data_supported then
    options.data = payload
  end
  pcall(vim.api.nvim_exec_autocmds, "User", options)
end

return M
```

- [ ] In `lua/whisk/registry/traits.lua`, add after `M.apply_frame`:

```lua
function M.notify_start(trait_id, context)
  local trait = traits[trait_id]
  if trait and trait.on_start then
    trait.on_start(context)
  end
end

function M.notify_complete(trait_id, context)
  local trait = traits[trait_id]
  if trait and trait.on_complete then
    trait.on_complete(context)
  end
end
```

- [ ] In `lua/whisk/engine/pool.lua`, add `motion_id = nil,` to the fresh-animation table in `M.acquire` and `animation.motion_id = nil` to the reset block in `M.release` (next to the other field resets).
- [ ] In `lua/whisk/engine/loop.lua`: add `local events = require("whisk.engine.events")` to the top-of-file requires. In `M.start`, add `anim.motion_id = options.motion_id` next to the other `anim.*` assignments, and add after the `table.insert(frame_queue, anim)` line:

```lua
  for _, trait_id in ipairs(anim.traits) do
    traits.notify_start(trait_id, anim.context)
  end
  events.emit(events.START, { motion_id = anim.motion_id, traits = anim.traits })
```

- [ ] Still in `loop.lua`, update the completion branch inside `process_frame` (emit before `pool.release`, which zeroes the fields):

```lua
    if progress >= 1.0 then
      if anim.on_complete then
        anim.on_complete()
      end
      for _, trait_id in ipairs(anim.traits) do
        traits.notify_complete(trait_id, anim.context)
      end
      events.emit(events.COMPLETE, { motion_id = anim.motion_id, traits = anim.traits })
      table.remove(frame_queue, i)
      pool.release(anim)
    end
```

and the invalid-context branch:

```lua
      if not valid then
        if anim.on_cancel then
          anim.on_cancel(reason)
        end
        events.emit(events.CANCEL, { motion_id = anim.motion_id, traits = anim.traits, reason = reason })
        table.remove(frame_queue, i)
        pool.release(anim)
        goto continue
      end
```

- [ ] Update `M.complete_all` so each animation notifies and emits before release:

```lua
function M.complete_all()
  for _, anim in ipairs(frame_queue) do
    local eased_final = anim.easing_fn(1.0)
    local final = interpolate_result(anim.context, anim.result, eased_final)
    for _, trait_id in ipairs(anim.traits) do
      traits.apply_frame(trait_id, anim.context, final, eased_final)
    end
    if anim.on_complete then
      anim.on_complete()
    end
    for _, trait_id in ipairs(anim.traits) do
      traits.notify_complete(trait_id, anim.context)
    end
    events.emit(events.COMPLETE, { motion_id = anim.motion_id, traits = anim.traits })
    pool.release(anim)
  end
  frame_queue = {}
  is_running = false
end
```

- [ ] Update `M.stop_all`, `M.cancel_for_buffer`, and `M.cancel_for_window` to emit CANCEL per animation (in `stop_all` add `events.emit(events.CANCEL, { motion_id = anim.motion_id, traits = anim.traits, reason = "stopped" })` inside the loop before `pool.release(anim)`; in `cancel_for_buffer` add `events.emit(events.CANCEL, { motion_id = anim.motion_id, traits = anim.traits, reason = "buffer_invalidated" })` inside the matching branch before `pool.release(anim)`; in `cancel_for_window` the same with reason `"window_invalidated"`).
- [ ] In `lua/whisk/engine/orchestrator.lua`, add `motion_id = motion.id,` to the `loop.start` options table in `M.execute`.
- [ ] Run `bash scripts/run_tests.sh` — all tests pass, zero failures. (Existing loop tests without `motion_id` still pass: the payload simply carries a nil `motion_id`, and every emit is pcall-wrapped.)
- [ ] Create the headless probe `tests/nvim/specs/user_events_spec.lua`:

```lua
local function fail(message)
  io.write("FAIL: " .. message .. "\n")
  vim.cmd("cquit! 1")
end

vim.o.hidden = true
require("whisk").setup({ cursor = { duration = 30 }, scroll = { duration = 30 } })
local orchestrator = require("whisk.engine.orchestrator")

local received = {}
for _, pattern in ipairs({ "WhiskAnimationStart", "WhiskAnimationComplete", "WhiskAnimationCancel" }) do
  vim.api.nvim_create_autocmd("User", {
    pattern = pattern,
    callback = function(args)
      table.insert(received, { pattern = pattern, data = args.data })
    end,
  })
end

local lines = {}
for i = 1, 200 do
  lines[i] = "line " .. i
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 1, 0 })

orchestrator.execute("line_G", { count = 1, direction = "G" })

local function saw(pattern, motion_id)
  for _, entry in ipairs(received) do
    if entry.pattern == pattern and (motion_id == nil or (entry.data and entry.data.motion_id == motion_id)) then
      return true
    end
  end
  return false
end

local completed = vim.wait(1000, function()
  return saw("WhiskAnimationComplete")
end, 10)
if not completed then
  fail("no WhiskAnimationComplete event received")
end
if not saw("WhiskAnimationStart", "line_G") then
  fail("WhiskAnimationStart with motion_id line_G not received")
end
io.write("OK: start and complete events carry the motion id\n")

if not saw("WhiskAnimationStart", "animate_to") then
  received = {}
  require("whisk").animate_to({ line = 1 })
  vim.wait(1000, function()
    return saw("WhiskAnimationComplete", "animate_to")
  end, 10)
  if not saw("WhiskAnimationStart", "animate_to") then
    fail("animate_to did not emit start event")
  end
end
io.write("OK: animate_to emits events\n")

received = {}
require("whisk").setup({ cursor = { duration = 3000 }, scroll = { duration = 3000 } })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
orchestrator.execute("line_G", { count = 1, direction = "G" })
vim.cmd("bdelete!")
local cancelled = vim.wait(1000, function()
  return saw("WhiskAnimationCancel")
end, 10)
if not cancelled then
  fail("no WhiskAnimationCancel event received after bdelete")
end
io.write("OK: cancellation emits WhiskAnimationCancel\n")

io.write("SPEC PASS: user_events\n")
```

- [ ] Run the probe from the repo root and confirm all `OK:` lines plus `SPEC PASS: user_events` print with exit code 0:

```
nvim --headless --clean --cmd "set runtimepath^=." +"luafile tests/nvim/specs/user_events_spec.lua" +"qa!"
```

- [ ] Update `README.md`: insert a new top-level section between `### Motion IDs` (end of the Lua API section) and `## Examples`:

```markdown
---

## Events

whisk fires `User` autocmds around every animation, so statuslines, dimming plugins, and other integrations can react to the animation lifecycle:

| Pattern | Fired |
|---------|-------|
| `WhiskAnimationStart` | when an animation is queued |
| `WhiskAnimationComplete` | when an animation reaches its final frame (including instant completion on domination) |
| `WhiskAnimationCancel` | when an animation is cancelled (buffer deleted, window closed, engine stopped) |

The event `data` carries `{ motion_id, traits }` (`WhiskAnimationCancel` adds a `reason`). On Neovim builds whose `nvim_exec_autocmds` does not support `data`, the events still fire without a payload.

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = { "WhiskAnimationStart", "WhiskAnimationComplete", "WhiskAnimationCancel" },
  callback = function(args)
    vim.g.whisk_animating = args.match == "WhiskAnimationStart"
    vim.cmd("redrawstatus")
  end,
})
```

Custom traits registered with `on_start` / `on_complete` callbacks now receive those hooks around each animation as well.
```

- [ ] Update `doc/whisk.txt`: add an events section (immediately above the trailing modeline) with tag `*whisk-events*`:

```
==============================================================================
EVENTS							*whisk-events*

whisk fires |User| autocommands around every animation:

	WhiskAnimationStart	an animation was queued
	WhiskAnimationComplete	an animation reached its final frame
	WhiskAnimationCancel	an animation was cancelled

The autocommand callback's "data" carries motion_id and traits;
WhiskAnimationCancel adds a reason. Example: >

	vim.api.nvim_create_autocmd("User", {
	  pattern = "WhiskAnimationStart",
	  callback = function(args)
	    vim.g.whisk_animating = true
	  end,
	})
<
On Neovim builds whose nvim_exec_autocmds() lacks the data field the
events still fire without a payload.
```

- [ ] Run `bash scripts/run_tests.sh` one final time — all tests pass, zero failures.
- [ ] Commit: `git add lua/whisk/engine/events.lua lua/whisk/engine/loop.lua lua/whisk/engine/pool.lua lua/whisk/engine/orchestrator.lua lua/whisk/registry/traits.lua tests/mocks/vim_api.lua tests/mocks/init.lua tests/unit/engine/events_spec.lua tests/unit/engine/loop_spec.lua tests/unit/registry/traits_spec.lua tests/init.lua tests/nvim/specs/user_events_spec.lua README.md doc/whisk.txt && git commit -m "feat(engine): emit WhiskAnimation user autocmd events"`
