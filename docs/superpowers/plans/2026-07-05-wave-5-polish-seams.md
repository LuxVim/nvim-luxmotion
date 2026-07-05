# Wave 5: Polish and Seams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring whisk.nvim to public-facing ecosystem maturity (vimdoc, checkhealth, LuaCATS, changelog, rockspec, contributor surface) and tighten the architecture seams (registry validation/unregister, management-owned config mutation, orchestrator diagnostics, keymap restore-on-clear) while deleting dead code.

**Architecture:** Wave 5 touches the public surface and the extension seams, never the animation math. Behavioral code changes flow through the existing facades (`config` → `config.management`, motions/traits registries, `engine.orchestrator`, `registry.keymaps`); each new capability is a named seam later waves and third parties can rely on. Ecosystem artifacts (`doc/whisk.txt`, `lua/whisk/health.lua`, `CHANGELOG.md`, `CONTRIBUTING.md`, rockspec, `.github/`) are additive and self-contained.

**Tech Stack:** Lua 5.1+ (Neovim runtime), plain-Lua unit test harness (tests/), headless Neovim probes for behavior the mocks cannot exercise.

**Findings covered:**
- **#38** — init enable/disable toggles mutate the config table directly; route through a new `management.set_enabled`.
- **#17** — registry seams lack field validation, duplicate rejection, and `unregister`.
- **#41** — `orchestrator.execute` returns silently on unknown motion_id; add a boolean return + one-time `vim.notify`.
- **#36** — keymap install clobbers user mappings and `clear()` deletes rather than restores; snapshot `maparg` and restore.
- **#40** — dead `performance.frame_rate_threshold` config key is never read; remove it.
- **#48** — no `:checkhealth whisk`; add `lua/whisk/health.lua`.
- **#39** — dead module `utils/visual.lua` is unreferenced; delete it and its spec.
- **#47** — no LuaCATS annotations on the public API; add them.
- **#45** — `plugin/whisk.vim` has no Neovim version guard; add `if !has('nvim-0.8')`.
- **#20** — no vimdoc; author `doc/whisk.txt`.
- **#46** — no CHANGELOG/release process; add `CHANGELOG.md` + a Releases section to CONTRIBUTING.
- **#51** — no CONTRIBUTING guide; add `CONTRIBUTING.md`.
- **#50** — no luarocks rockspec; add `whisk.nvim-scm-1.rockspec`.
- **#52** — no issue/PR templates; add `.github/` templates.

## Execution Model

- Branch: `audit/wave-5-polish-seams`, created from `main` (after Wave 4's PR has merged).
- Executor: one Sonnet 5 subagent (high effort) per task, fresh context per task, given only that task's text plus this plan's header and Global Constraints.
- Task review: an Opus 4.8 subagent (xhigh effort) reviews each completed task's diff against the task spec before the next task starts. Review verdict gates progression.
- Wave review: one Fable agent reviews the wave's full branch diff (`git diff main...HEAD`) against this plan plus the findings file before the PR is opened.
- PR: opened to `main` when all tasks complete, `bash scripts/run_tests.sh` passes, and the Fable wave review passes.

## Global Constraints

- Neovim >= 0.8 API compatibility only (no vim.uv, no nvim_exec2, no APIs newer than 0.8 unless feature-detected).
- No inline comments in code. LuaCATS/JSDoc-style annotation comments are permitted only where a task explicitly calls for them (Task 8 is the only task that adds them). Do NOT add annotations opportunistically in other tasks.
- Pre-existing `--` inline comments in `lua/whisk/performance.lua` are out of scope; do not touch that file except where a task names it.
- Commit style: conventional commits with scope, matching repo history (`fix(engine): ...`, `feat(registry): ...`, `test: ...`, `docs: ...`, `chore: ...`). NO AI attribution of any kind — no "Generated with", no "Co-Authored-By: Claude".
- Every task ends with `bash scripts/run_tests.sh` passing (zero failures) before its commit. The suite is at **441 tests** on `main`; Tasks 1–6 raise it and Task 7 lowers it by deleting a spec. The load-bearing invariant per task is **zero failures**; the wave-end floor is **>= 441 tests**. Each task states its expected count delta.
- Do not modify files outside this wave's scope. Do not touch `lua/luxmotion/` or `plugin/luxmotion.vim` (deprecation shims) unless a task says to.

---

### Task 1: Route enable/disable through `management.set_enabled` (#38)

**Files:**
- Modify: `lua/whisk/config/management.lua`
- Modify: `lua/whisk/config.lua`
- Modify: `lua/whisk/init.lua`
- Test: `tests/unit/config/management_spec.lua`

**Interfaces:**
- Produces: `management.set_enabled(category, enabled)` → `boolean` (true when `category` is a known config section and its `.enabled` was set; false when the category does not exist). Re-exported on the config facade as `config.set_enabled`.
- Consumes: `init.enable/disable/enable_cursor/disable_cursor/enable_scroll/disable_scroll` now call `config.set_enabled(<category>, <bool>)` instead of mutating `config.get().<category>.enabled`. `init.toggle` still *reads* `config.get()` to decide direction (a read, not a mutation) and calls `M.enable()/M.disable()`.

Steps:

- [ ] Write the failing test. Append these tests inside the `describe('config/management', ...)` block in `tests/unit/config/management_spec.lua`, before the final `end)`:
```lua
  it('exports set_enabled', function()
    assert.is_type(management.set_enabled, 'function')
  end)

  it('set_enabled toggles cursor enabled flag', function()
    local ok = management.set_enabled('cursor', false)
    assert.is_true(ok)
    assert.is_false(management.get_cursor().enabled)

    management.set_enabled('cursor', true)
    assert.is_true(management.get_cursor().enabled)
  end)

  it('set_enabled toggles scroll enabled flag', function()
    management.set_enabled('scroll', false)
    assert.is_false(management.get_scroll().enabled)
  end)

  it('set_enabled returns false for unknown category', function()
    local ok = management.set_enabled('does_not_exist', true)
    assert.is_false(ok)
  end)
```

- [ ] Run it and see it fail: `bash scripts/run_tests.sh` → fails in `config/management` with `Motion ...`—no, with `set_enabled` being nil (`attempt to call field 'set_enabled' (a nil value)` / `Expected type: function Actual type: nil`).

- [ ] Minimal implementation — add `set_enabled` to `lua/whisk/config/management.lua`. Insert this function immediately before `function M.reset()`:
```lua
function M.set_enabled(category, enabled)
  local section = current_config[category]
  if section == nil then
    return false
  end
  section.enabled = enabled
  return true
end
```

- [ ] Wire the facade — in `lua/whisk/config.lua`, add the re-export. Change:
```lua
M.update = management.update
M.reset = management.reset
```
to:
```lua
M.update = management.update
M.reset = management.reset
M.set_enabled = management.set_enabled
```

- [ ] Route the init toggles — in `lua/whisk/init.lua`, replace the six toggle functions (`M.enable` through `M.disable_scroll`, lines 40–75) with:
```lua
function M.enable()
  config.set_enabled("cursor", true)
  config.set_enabled("scroll", true)
end

function M.disable()
  config.set_enabled("cursor", false)
  config.set_enabled("scroll", false)
end

function M.toggle()
  local cfg = config.get()
  if cfg.cursor.enabled or cfg.scroll.enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.enable_cursor()
  config.set_enabled("cursor", true)
end

function M.disable_cursor()
  config.set_enabled("cursor", false)
end

function M.enable_scroll()
  config.set_enabled("scroll", true)
end

function M.disable_scroll()
  config.set_enabled("scroll", false)
end
```

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures. Expected count: **445** (441 + 4 new). The existing `init_spec` enable/disable tests still pass because behavior is identical.

- [ ] Commit:
```bash
git add lua/whisk/config/management.lua lua/whisk/config.lua lua/whisk/init.lua tests/unit/config/management_spec.lua
git commit -m "refactor(config): route enable/disable toggles through management.set_enabled"
```

---

### Task 2: Registry validation, duplicate rejection, and unregister (#17)

**Files:**
- Modify: `lua/whisk/registry/motions.lua`
- Modify: `lua/whisk/registry/traits.lua`
- Test: `tests/unit/registry/motions_spec.lua`
- Test: `tests/unit/registry/traits_spec.lua`

**Interfaces:**
- Produces: `motions.register(definition)` now validates the normalized motion for the required fields `id, keys, modes, traits, category, calculator` (`modes` is defaulted to `{ "n", "v" }` before the check, so definitions omitting it still pass — the validation is on the normalized table). A missing field raises `error("whisk: motion registration missing required field '" .. field .. "'")`. A duplicate id raises exactly `error("whisk: motion '" .. id .. "' already registered")`.
- Produces: `motions.unregister(motion_id)` → `boolean` (true when removed; false no-op when the id is unknown). Removes the definition AND strips the id from `categories[category]`.
- Produces: `traits.register(definition)` validates required fields `id, apply`; missing raises `error("whisk: trait registration missing required field '" .. field .. "'")`; duplicate raises exactly `error("whisk: trait '" .. id .. "' already registered")`.
- Produces: `traits.unregister(trait_id)` → `boolean`; removes the definition and clears `state[trait_id]`.
- **Documentation note for Interfaces:** keymaps installed by `registry.keymaps` for a motion that is later unregistered are NOT removed by `unregister` — deleting stale keymaps is the caller's concern. Callers overriding a built-in should `unregister` then `register`, and re-run their keymap install.
- **Interpretation (surfaced):** the design pin lists `modes` among required fields, but `motions.register` defaults `modes`. This plan validates the *normalized* motion (post-default), so `modes` is nominally in the required-field list yet a definition omitting it still succeeds, preserving the existing `register defaults modes to n and v` test. This is the reconciliation of the pin with the codebase's defaulting behavior.

Steps:

- [ ] Write the failing tests for motions. In `tests/unit/registry/motions_spec.lua`, **replace** the existing `it('register overwrites existing motion with same id', ...)` block (the test that registers `same_id` twice and asserts the second wins) with:
```lua
  it('register rejects duplicate motion id', function()
    motions.register({
      id = 'same_id',
      keys = { 'a' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return { v = 1 } end,
    })

    assert.throws(function()
      motions.register({
        id = 'same_id',
        keys = { 'b' },
        modes = { 'v' },
        traits = { 'scroll' },
        category = 'scroll',
        calculator = function() return { v = 2 } end,
      })
    end, "already registered")
  end)

  it('register errors when a required field is missing', function()
    assert.throws(function()
      motions.register({
        id = 'missing_calc',
        keys = { 'a' },
        modes = { 'n' },
        traits = { 'cursor' },
        category = 'cursor',
      })
    end, "required field")
  end)

  it('unregister removes the motion and its category entry', function()
    motions.register({
      id = 'temp_motion',
      keys = { 'a' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
    })

    local removed = motions.unregister('temp_motion')
    assert.is_true(removed)
    assert.is_nil(motions.get('temp_motion'))
    assert.length(motions.get_by_category('cursor'), 0)
  end)

  it('unregister returns false for an unknown id', function()
    assert.is_false(motions.unregister('never_registered'))
  end)
```

- [ ] Write the failing tests for traits. In `tests/unit/registry/traits_spec.lua`, **replace** the existing `it('register overwrites existing trait', ...)` block with:
```lua
  it('register rejects duplicate trait id', function()
    traits.register({ id = 'same', apply = function() return 1 end })

    assert.throws(function()
      traits.register({ id = 'same', apply = function() return 2 end })
    end, "already registered")
  end)

  it('register errors when apply is missing', function()
    assert.throws(function()
      traits.register({ id = 'no_apply' })
    end, "required field")
  end)

  it('unregister removes the trait and its state', function()
    traits.register({ id = 'temp', apply = function() end })
    traits.set_animating('temp', 1000, true)

    local removed = traits.unregister('temp')
    assert.is_true(removed)
    assert.is_nil(traits.get('temp'))
    assert.is_false(traits.is_animating('temp', 1000))
  end)

  it('unregister returns false for an unknown id', function()
    assert.is_false(traits.unregister('never_registered'))
  end)
```

- [ ] Run them and see them fail: `bash scripts/run_tests.sh` → the duplicate-rejection and required-field tests fail (no error is thrown), and the `unregister` tests fail with `attempt to call field 'unregister' (a nil value)`.

- [ ] Minimal implementation — rewrite `lua/whisk/registry/motions.lua` in full:
```lua
local M = {}

local motions = {}
local categories = {}

local REQUIRED_FIELDS = { "id", "keys", "modes", "traits", "category", "calculator" }

function M.register(definition)
  local motion = {
    id = definition.id,
    keys = definition.keys,
    modes = definition.modes or { "n", "v" },
    traits = definition.traits,
    category = definition.category,
    calculator = definition.calculator,
    description = definition.description,
    input = definition.input,
  }

  for _, field in ipairs(REQUIRED_FIELDS) do
    if motion[field] == nil then
      error("whisk: motion registration missing required field '" .. field .. "'")
    end
  end

  if motions[motion.id] then
    error("whisk: motion '" .. motion.id .. "' already registered")
  end

  motions[motion.id] = motion

  categories[motion.category] = categories[motion.category] or {}
  table.insert(categories[motion.category], motion.id)
end

function M.get(motion_id)
  return motions[motion_id]
end

function M.get_by_category(category)
  local ids = categories[category] or {}
  local result = {}
  for _, id in ipairs(ids) do
    table.insert(result, motions[id])
  end
  return result
end

function M.all()
  return motions
end

function M.unregister(motion_id)
  local motion = motions[motion_id]
  if not motion then
    return false
  end

  motions[motion_id] = nil

  local category_ids = categories[motion.category]
  if category_ids then
    for index, id in ipairs(category_ids) do
      if id == motion_id then
        table.remove(category_ids, index)
        break
      end
    end
  end

  return true
end

function M.clear()
  motions = {}
  categories = {}
end

return M
```

- [ ] Minimal implementation — rewrite `lua/whisk/registry/traits.lua` in full (this listing already reflects Wave 4's per-`(trait_id, winid)` animating state — the Wave 5 additions are the REQUIRED_FIELDS validation, duplicate rejection, and `unregister`; if the branch file differs cosmetically, graft those three additions onto it rather than regressing Wave 4's signatures):
```lua
local M = {}

local traits = {}
local state = {}

local REQUIRED_FIELDS = { "id", "apply" }

function M.register(definition)
  for _, field in ipairs(REQUIRED_FIELDS) do
    if definition[field] == nil then
      error("whisk: trait registration missing required field '" .. field .. "'")
    end
  end

  local id = definition.id

  if traits[id] then
    error("whisk: trait '" .. id .. "' already registered")
  end

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

function M.unregister(trait_id)
  if not traits[trait_id] then
    return false
  end
  traits[trait_id] = nil
  state[trait_id] = nil
  return true
end

function M.reset()
  for id, _ in pairs(state) do
    state[id] = {}
  end
end

function M.clear()
  traits = {}
  state = {}
end

return M
```

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures. Expected count: **+6 over the pre-task branch count** (−2 removed overwrite tests, +8 new; absolute totals drifted as Waves 1–4 added tests). Verify `registry/builtin`, `init`, and `engine/orchestrator` suites still pass (setup calls `reset()`→`clear()` before `register_all()`, so no duplicate-id error arises during re-setup).

- [ ] Commit:
```bash
git add lua/whisk/registry/motions.lua lua/whisk/registry/traits.lua tests/unit/registry/motions_spec.lua tests/unit/registry/traits_spec.lua
git commit -m "feat(registry): validate definitions, reject duplicate ids, add unregister"
```

---

### Task 3: Orchestrator boolean return + one-time unknown-motion notify (#41)

**Files:**
- Modify: `lua/whisk/engine/orchestrator.lua`
- Test: `tests/unit/engine/orchestrator_spec.lua`
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/USAGE.md`

**Interfaces:**
- Produces: `orchestrator.execute(motion_id, input)` → `boolean handled`. Returns `true` for every path where the motion is registered (animation started, native fallback, nil-result no-op, or same-position no-op). Returns `false` only when `motion_id` is not registered, and in that case emits `vim.notify("whisk: unknown motion '" .. motion_id .. "'", vim.log.levels.WARN)` at most once per unique unknown id (tracked in a module-local table).

Steps:

- [ ] Write the failing tests. Append inside the `describe('engine/orchestrator', ...)` block in `tests/unit/engine/orchestrator_spec.lua`, before the final `end)`:
```lua
  it('execute returns true for a handled motion', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = true } })

    local handled = orchestrator.execute('test_j', { count = 2 })
    assert.is_true(handled)
  end)

  it('execute returns true when the category is disabled (fallback)', function()
    local config = require('whisk.config')
    config.update({ cursor = { enabled = false } })

    local handled = orchestrator.execute('test_j', { count = 1 })
    assert.is_true(handled)
  end)

  it('execute returns false for an unknown motion', function()
    local handled = orchestrator.execute('nonexistent_motion', {})
    assert.is_false(handled)
  end)

  it('execute notifies once per unknown motion id', function()
    orchestrator.execute('bogus_motion', {})
    orchestrator.execute('bogus_motion', {})

    local notifications = mocks.get_notifications()
    local count = 0
    for _, n in ipairs(notifications) do
      if n.msg == "whisk: unknown motion 'bogus_motion'" then
        count = count + 1
        assert.equals(n.level, vim.log.levels.WARN)
      end
    end
    assert.equals(count, 1)
  end)
```

- [ ] Run them and see them fail: `bash scripts/run_tests.sh` → the return-value tests fail (`Expected: true Actual: nil`) and the notify test fails (`Expected: 1 Actual: 0`).

- [ ] Minimal implementation — apply these targeted edits to `lua/whisk/engine/orchestrator.lua`. Do NOT rewrite the file: on this branch `execute` already carries Wave 1's `on_cancel` wiring, Wave 2's `should_skip_animation` guard, jumplist push, and curswant application, and Wave 4's per-window domination (`traits.is_animating(trait_id, winid)` / `loop.complete_for_window(winid)`); `fallback` already resolves termcodes via `nvim_replace_termcodes` + `nvim_feedkeys`. Preserve all of it — this task only adds the return contract and the one-time notify.

  Edit 1 — after the `local M = {}` line, add:

```lua
local notified = {}
```

  Edit 2 — replace the unknown-motion guard at the top of `M.execute` (the `if not motion then` early return) with:

```lua
  if not motion then
    if not notified[motion_id] then
      notified[motion_id] = true
      vim.notify("whisk: unknown motion '" .. motion_id .. "'", vim.log.levels.WARN)
    end
    return false
  end
```

  Edit 3 — add `return true` to every handled exit path of `M.execute`, leaving the surrounding logic untouched:
  - after the `M.fallback(motion, input)` call in the disabled-category branch,
  - in the `if not result then` early exit,
  - in the same-position/same-viewport early exit,
  - in the synchronous `should_skip_animation` branch, after the final result is applied,
  - at the end of the animated path, after `loop.start({ ... })`.

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures. Expected count: **455** (451 + 4). The existing `execute handles unknown motion gracefully` test still passes (it asserts no throw).

- [ ] Update README — in `README.md`, in the `### Manual motion execution` section, after the closing ` ``` ` of the `orchestrator.execute(...)` example block, add this paragraph:
```markdown

`execute` returns `true` when the motion was handled — whether it animated, fell back to a native `normal!` motion, or produced no movement. It returns `false` only when `motion_id` is not registered, emitting a one-time `vim.notify` warning (`WARN` level) per unknown id so custom-keymap typos are diagnosable.
```

- [ ] Update ARCHITECTURE — in `docs/ARCHITECTURE.md`, in the `## Orchestrator` numbered list, replace step 1:
```markdown
1. Look up the motion definition from `motions.get(motion_id)`.
```
with:
```markdown
1. Look up the motion definition from `motions.get(motion_id)`. If the id is unregistered, emit a one-time `vim.notify` warning per unique id and return `false`. All other paths return `true`.
```

- [ ] Update USAGE — in `docs/USAGE.md`, in the `## Manual motions` section, after the closing ` ``` ` of the `orchestrator.execute(...)` example block, add:
```markdown

`execute` returns `true` when the motion is handled and `false` (with a one-time `WARN` notification) when `motion_id` is not a registered motion.
```

- [ ] Run tests again (docs edits are inert): `bash scripts/run_tests.sh` → zero failures, still **455**.

- [ ] Commit:
```bash
git add lua/whisk/engine/orchestrator.lua tests/unit/engine/orchestrator_spec.lua README.md docs/ARCHITECTURE.md docs/USAGE.md
git commit -m "feat(engine): return handled flag and warn once on unknown motion id"
```

---

### Task 4: Snapshot and restore user keymaps on clear (#36)

**Files:**
- Modify: `lua/whisk/registry/keymaps.lua`
- Modify: `tests/mocks/vim_fn.lua`
- Test: `tests/unit/registry/keymaps_spec.lua`

**Interfaces:**
- Produces: `registry.keymaps.setup()` snapshots `vim.fn.maparg(key, mode, false, true)` (the dict form) for every key+mode it will overwrite, keyed by `mode .. ":" .. key` in a module-local `snapshots` table, before installing whisk's mapping.
- Produces: `registry.keymaps.clear()` — for each whisk-managed key+mode: if a non-empty snapshot exists, restore it via `vim.fn.mapset(mode, false, snapshot)` when `vim.fn.exists("*mapset") == 1` (feature-detected; `mapset` replaces, so no delete needed), else rebuild via `vim.api.nvim_set_keymap` from the snapshot dict fields; if the snapshot is empty (no prior mapping), plain-delete whisk's mapping via `vim.keymap.del`. The snapshot entry is then cleared.
- Test-infra: `tests/mocks/vim_fn` gains `maparg`, `mapset`, and `exists`, plus `M.set_maparg(mode, lhs, dict)` and `M.get_mapset_calls()`.

Steps:

- [ ] Extend the mock — in `tests/mocks/vim_fn.lua`, add `maps = {}` and `mapset_calls = {}` to BOTH the initial `state` table (lines ~3-10) and the `state` table inside `M.reset()` (lines ~13-20). The initial state and reset must each read:
```lua
local state = {
  topline = 1,
  mode = 'n',
  visual_start = { 0, 1, 1, 0 },
  visual_end = { 0, 1, 1, 0 },
  search_pattern = '',
  last_char = '',
  maps = {},
  mapset_calls = {},
}
```
(apply the same two added keys to the `reset()` copy).

- [ ] Add mock setters/getters — in `tests/mocks/vim_fn.lua`, after the existing `function M.set_last_char(char)` block, add:
```lua
function M.set_maparg(mode, lhs, dict)
  state.maps[mode .. ':' .. lhs] = dict
end

function M.get_mapset_calls()
  return state.mapset_calls
end
```

- [ ] Add the mock functions — in `tests/mocks/vim_fn.lua`, inside the table returned by `M.create()`, add these three entries (place them after the `getcharstr` entry):
```lua
    maparg = function(name, mode, abbr, dict)
      local entry = state.maps[(mode or '') .. ':' .. name]
      if dict then
        return entry or {}
      end
      return (entry and entry.rhs) or ''
    end,

    mapset = function(mode, abbr, dict)
      table.insert(state.mapset_calls, { mode = mode, abbr = abbr, dict = dict })
      if dict and dict.lhs then
        state.maps[(dict.mode or mode or '') .. ':' .. dict.lhs] = dict
      end
    end,

    exists = function(expr)
      if expr == '*mapset' then
        return 1
      end
      return 0
    end,
```

- [ ] Write the failing tests. Append inside the `describe('registry/keymaps', ...)` block in `tests/unit/registry/keymaps_spec.lua`, before the final `end)`:
```lua
  it('clear restores a pre-existing user mapping', function()
    config.update({ keymaps = { cursor = true } })
    local vim_fn = require('tests.mocks.vim_fn')
    vim_fn.set_maparg('n', 'n', { lhs = 'n', rhs = 'nzzzv', mode = 'n', noremap = 1, silent = 0 })

    motions.register({
      id = 'search_next',
      keys = { 'n' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'next result',
    })

    keymaps.setup()
    keymaps.clear()

    local mapset_calls = vim_fn.get_mapset_calls()
    local restored = false
    for _, call in ipairs(mapset_calls) do
      if call.dict and call.dict.lhs == 'n' then
        restored = true
      end
    end
    assert.is_true(restored)
  end)

  it('clear deletes whisk mapping when no prior user mapping existed', function()
    config.update({ keymaps = { cursor = true } })

    motions.register({
      id = 'plain_x',
      keys = { 'x' },
      modes = { 'n' },
      traits = { 'cursor' },
      category = 'cursor',
      calculator = function() return {} end,
      description = 'x motion',
    })

    keymaps.setup()
    keymaps.clear()

    local deleted = mocks.get_deleted_keymaps()
    local found = false
    for _, d in ipairs(deleted) do
      if d.lhs == 'x' and d.mode == 'n' then
        found = true
      end
    end
    assert.is_true(found)
  end)
```

- [ ] Run them and see them fail: `bash scripts/run_tests.sh` → the restore test fails (`Expected: true Actual: false` — `mapset` is never called; current `clear()` only deletes). The delete test passes already but is retained as a regression guard.

- [ ] Minimal implementation — rewrite `lua/whisk/registry/keymaps.lua` in full:
```lua
local motions = require("whisk.registry.motions")
local orchestrator = require("whisk.engine.orchestrator")
local config = require("whisk.config")

local M = {}

local snapshots = {}

local function snapshot_key(mode, key)
  return mode .. ":" .. key
end

function M.create_handler(motion)
  if motion.input == "char" then
    return function()
      local char = vim.fn.getcharstr()
      orchestrator.execute(motion.id, {
        char = char,
        count = vim.v.count1,
        direction = motion.keys[1],
      })
    end
  else
    return function()
      orchestrator.execute(motion.id, {
        count = vim.v.count1,
        direction = motion.keys[1],
      })
    end
  end
end

function M.setup()
  local keymap_config = config.get_keymaps()

  for motion_id, motion in pairs(motions.all()) do
    if keymap_config[motion.category] == false then
      goto continue
    end

    local handler = M.create_handler(motion)

    for _, key in ipairs(motion.keys) do
      for _, mode in ipairs(motion.modes) do
        snapshots[snapshot_key(mode, key)] = vim.fn.maparg(key, mode, false, true)
        vim.keymap.set(mode, key, handler, {
          desc = "Smooth " .. motion.description,
          silent = true,
        })
      end
    end

    ::continue::
  end
end

local function has_mapset()
  return vim.fn.exists("*mapset") == 1
end

local function restore_mapping(mode, key, snapshot)
  if has_mapset() then
    vim.fn.mapset(mode, false, snapshot)
  elseif snapshot.rhs then
    vim.api.nvim_set_keymap(mode, key, snapshot.rhs, {
      noremap = snapshot.noremap == 1,
      silent = snapshot.silent == 1,
      expr = snapshot.expr == 1,
      nowait = snapshot.nowait == 1,
    })
  end
end

function M.clear()
  for _, motion in pairs(motions.all()) do
    for _, key in ipairs(motion.keys) do
      for _, mode in ipairs(motion.modes) do
        local skey = snapshot_key(mode, key)
        local snapshot = snapshots[skey]
        if snapshot and next(snapshot) ~= nil then
          restore_mapping(mode, key, snapshot)
        else
          pcall(vim.keymap.del, mode, key)
        end
        snapshots[skey] = nil
      end
    end
  end
end

return M
```

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures. Expected count: **457** (455 + 2). The existing `clear removes all keymaps` test still passes (no pre-seeded mapping → empty snapshots → delete path).

- [ ] Headless verification (real `mapset` end-to-end). Run from the repo root:
```bash
nvim --headless --clean --cmd "set rtp+=$PWD" \
  -c "nnoremap n nzzzv" \
  -c "lua require('whisk').setup({ keymaps = { cursor = true } })" \
  -c "lua require('whisk').reset()" \
  -c "lua io.write('RESTORED:' .. vim.fn.maparg('n', 'n') .. '\n')" \
  -c "qa!" 2>&1
```
Expected: output contains `RESTORED:nzzzv` (whisk overwrote `n` on setup, then restored the user's `nzzzv` mapping on reset via `mapset`). If the environment lacks a `nvim` binary, the unit test above is the authoritative gate; note the skip.

- [ ] Commit:
```bash
git add lua/whisk/registry/keymaps.lua tests/mocks/vim_fn.lua tests/unit/registry/keymaps_spec.lua
git commit -m "feat(registry): snapshot and restore user keymaps on clear"
```

---

### Task 5: Remove dead `performance.frame_rate_threshold` config key (#40)

**Files:**
- Modify: `lua/whisk/config/defaults.lua`
- Test: `tests/unit/config/defaults_spec.lua`
- Modify: `README.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/ARCHITECTURE.md`

**Interfaces:** None new. `config.get_performance()` no longer returns a `frame_rate_threshold` field.

Steps:

- [ ] Confirm nothing reads the key beyond defaults + its test:
```bash
grep -rn "frame_rate_threshold" lua/ tests/ README.md docs/
```
Expected hits only: `lua/whisk/config/defaults.lua`, `tests/unit/config/defaults_spec.lua`, `README.md`, `docs/USAGE.md`, `docs/ARCHITECTURE.md`. `lua/whisk/config/validation.lua` has NO reference (it never validated the key) — confirm the grep shows none there; nothing to change in validation.

- [ ] Update the spec first — in `tests/unit/config/defaults_spec.lua`, remove the assertion line inside `it('has performance configuration', ...)`:
```lua
    assert.equals(defaults.config.performance.frame_rate_threshold, 60)
```

- [ ] Remove the key — in `lua/whisk/config/defaults.lua`, delete this line from the `performance` table:
```lua
    frame_rate_threshold = 60, -- Target FPS threshold for auto-switching to reduced frame rate (not currently read)
```

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures. Expected count unchanged: **457** (an assertion was removed, not a test).

- [ ] Update README — in `README.md`, in the `performance = { ... }` config block, remove the line:
```lua
    frame_rate_threshold = 60,    -- not currently read by any code path
```

- [ ] Update USAGE — in `docs/USAGE.md`, remove the same line from the `performance = { ... }` config block:
```lua
    frame_rate_threshold = 60,
```
and remove this row from the "Performance options" table:
```markdown
| `frame_rate_threshold` | number | `60` | Target FPS threshold for auto-switching to reduced frame rate (not currently read by any code path) |
```

- [ ] Update ARCHITECTURE — in `docs/ARCHITECTURE.md`, in the `## Performance mode` section, remove the trailing note paragraph:
```markdown
Note: `frame_rate_threshold` is defined in defaults (`60`) but is not currently read by any code path. It exists as a placeholder for future use.
```

- [ ] Run tests again (docs edits inert): `bash scripts/run_tests.sh` → zero failures, **457**.

- [ ] Commit:
```bash
git add lua/whisk/config/defaults.lua tests/unit/config/defaults_spec.lua README.md docs/USAGE.md docs/ARCHITECTURE.md
git commit -m "chore(config): remove unread performance.frame_rate_threshold key"
```

---

### Task 6: Add `:checkhealth whisk` health module (#48)

**Files:**
- Create: `lua/whisk/health.lua`
- Test: `tests/unit/health_spec.lua`
- Modify: `tests/init.lua`
- Modify: `tests/mocks/vim_core.lua`
- Modify: `tests/mocks/init.lua`
- Modify: `tests/mocks/vim_fn.lua`

**Interfaces:**
- Produces: `require("whisk.health").check()` — the entry point `:checkhealth whisk` invokes. Runs six report sections: Neovim version (`vim.fn.has("nvim-0.8")`), setup status (proxied by `require("whisk.engine.lifecycle").is_active()`), config validity (`config.validate(config.get())` under pcall), keymap conflicts on whisk-managed keys (via `maparg`, flagging mappings whose `desc` does not start with `"Smooth "`), luxmotion shim usage (`package.loaded["luxmotion"]`), and performance-mode status. Report functions are feature-detected for pre-0.10 vim.health (`h.start or h.report_start`, and likewise `ok`, `warn`, `error`, `info`).
- Test-infra: `vim_core` gains a recording `health` table + `get_health_reports()`; `mocks/init` wires `health = vim_core.health` into `_G.vim`; `vim_fn` gains `has`.

Steps:

- [ ] Extend `vim_core` with a recording health API — in `tests/mocks/vim_core.lua`, add `health = { start = {}, ok = {}, warn = {}, error = {}, info = {} }` to BOTH the initial `state` table and the `state` table inside `M.reset()`. Then, after the existing `M.keymap = { ... }` block, add:
```lua
M.health = {
  start = function(name)
    table.insert(state.health.start, name)
  end,
  ok = function(msg)
    table.insert(state.health.ok, msg)
  end,
  warn = function(msg, advice)
    table.insert(state.health.warn, { msg = msg, advice = advice })
  end,
  error = function(msg, advice)
    table.insert(state.health.error, { msg = msg, advice = advice })
  end,
  info = function(msg)
    table.insert(state.health.info, msg)
  end,
}

function M.get_health_reports()
  return state.health
end
```

- [ ] Wire health + `has` into the mocks — in `tests/mocks/init.lua`, add `health = vim_core.health,` to the `_G.vim = { ... }` table (place it after the `log = { levels = ... },` line). Then in `tests/mocks/vim_fn.lua`, inside `M.create()`'s returned table, add (after the `exists` entry added in Task 4):
```lua
    has = function(feature)
      if feature == 'nvim-0.8' or feature == 'nvim-0.7' then
        return 1
      end
      return 0
    end,
```

- [ ] Write the failing test — create `tests/unit/health_spec.lua`:
```lua
local runner = require('tests.runner')
local assert = require('tests.helpers.assertions')
local mocks = require('tests.mocks')

local describe, it, before_each = runner.describe, runner.it, runner.before_each

describe('health', function()
  local health

  before_each(function()
    mocks.setup()
    mocks.clear_package_cache()
    health = require('whisk.health')
  end)

  it('exports check function', function()
    assert.is_type(health.check, 'function')
  end)

  it('check runs without error', function()
    assert.does_not_throw(function()
      health.check()
    end)
  end)

  it('check emits report sections', function()
    health.check()
    local reports = require('tests.mocks.vim_core').get_health_reports()
    assert.greater_than(#reports.start, 0)
    assert.greater_than(#reports.ok, 0)
  end)

  it('check feature-detects report_* function names', function()
    local vim_core = require('tests.mocks.vim_core')
    local recording = vim_core.health
    local original = vim.health
    vim.health = {
      report_start = recording.start,
      report_ok = recording.ok,
      report_warn = recording.warn,
      report_error = recording.error,
      report_info = recording.info,
    }

    assert.does_not_throw(function()
      health.check()
    end)

    vim.health = original
  end)
end)
```

- [ ] Register the spec — in `tests/init.lua`, add this line after `require('tests.unit.performance_spec')`:
```lua
require('tests.unit.health_spec')
```

- [ ] Run it and see it fail: `bash scripts/run_tests.sh` → fails to load `whisk.health` (`module 'whisk.health' not found`).

- [ ] Minimal implementation — create `lua/whisk/health.lua`:
```lua
local M = {}

local function resolve_reporters()
  local h = vim.health or {}
  return {
    start = h.start or h.report_start,
    ok = h.ok or h.report_ok,
    warn = h.warn or h.report_warn,
    error = h.error or h.report_error,
    info = h.info or h.report_info,
  }
end

local function check_version(report)
  report.start("whisk: Neovim version")
  if vim.fn.has("nvim-0.8") == 1 then
    report.ok("Neovim >= 0.8")
  else
    report.error("Neovim >= 0.8 is required")
  end
end

local function check_setup(report)
  report.start("whisk: setup")
  local lifecycle = require("whisk.engine.lifecycle")
  if lifecycle.is_active() then
    report.ok("setup() has run (lifecycle autocommands active)")
  else
    report.warn("setup() has not run", { "Call require('whisk').setup() or enable auto-setup" })
  end
end

local function check_config(report)
  report.start("whisk: configuration")
  local config = require("whisk.config")
  local ok, err = pcall(config.validate, config.get())
  if ok then
    report.ok("configuration is valid")
  else
    report.error("invalid configuration: " .. tostring(err))
  end
end

local function check_keymaps(report)
  report.start("whisk: keymap conflicts")
  local motions = require("whisk.registry.motions")
  local keymap_config = require("whisk.config").get_keymaps()
  local conflicts = 0

  for _, motion in pairs(motions.all()) do
    if keymap_config[motion.category] ~= false then
      for _, key in ipairs(motion.keys) do
        for _, mode in ipairs(motion.modes) do
          local mapping = vim.fn.maparg(key, mode, false, true)
          if mapping and mapping.desc and mapping.desc:sub(1, 7) ~= "Smooth " then
            conflicts = conflicts + 1
            report.warn(string.format("key '%s' (%s) is mapped by another source: %s", key, mode, mapping.desc))
          end
        end
      end
    end
  end

  if conflicts == 0 then
    report.ok("no conflicting mappings on whisk-managed keys")
  end
end

local function check_luxmotion(report)
  report.start("whisk: luxmotion compatibility")
  if package.loaded["luxmotion"] then
    report.warn("the luxmotion deprecation shim is in use", { "Update your config to require('whisk') directly" })
  else
    report.ok("luxmotion shim not in use")
  end
end

local function check_performance(report)
  report.start("whisk: performance mode")
  local performance = require("whisk.performance")
  if performance.is_active() then
    report.info("performance mode is active")
  else
    report.info("performance mode is inactive")
  end
end

function M.check()
  local report = resolve_reporters()
  check_version(report)
  check_setup(report)
  check_config(report)
  check_keymaps(report)
  check_luxmotion(report)
  check_performance(report)
end

return M
```

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures. Expected count: **461** (457 + 4).

- [ ] Headless verification (`:checkhealth whisk` in real Neovim):
```bash
nvim --headless --clean --cmd "set rtp+=$PWD" \
  -c "checkhealth whisk" \
  -c "%print" \
  -c "qa!" 2>&1
```
Expected: output includes the section headers `whisk: Neovim version`, `whisk: setup`, `whisk: configuration`, `whisk: keymap conflicts`, `whisk: luxmotion compatibility`, `whisk: performance mode`. If no `nvim` binary is available, the unit tests are the gate; note the skip.

- [ ] Commit:
```bash
git add lua/whisk/health.lua tests/unit/health_spec.lua tests/init.lua tests/mocks/vim_core.lua tests/mocks/init.lua tests/mocks/vim_fn.lua
git commit -m "feat(health): add :checkhealth whisk diagnostics module"
```

---

### Task 7: Delete dead module `utils/visual.lua` (#39)

**Files:**
- Delete: `lua/whisk/utils/visual.lua`
- Delete: `tests/unit/utils/visual_spec.lua`
- Modify: `tests/init.lua`
- Modify: `docs/ARCHITECTURE.md`

**Interfaces:** None. This module has no production consumers.

Steps:

- [ ] Prove no production reference:
```bash
grep -rn "utils.visual\|utils/visual\|require([\"']whisk.utils.visual" lua/
```
Expected: no output (only tests referenced it). If any `lua/` hit appears, STOP and escalate — the module is not dead.

- [ ] Delete the module and its spec:
```bash
git rm lua/whisk/utils/visual.lua tests/unit/utils/visual_spec.lua
```

- [ ] Remove the spec require — in `tests/init.lua`, delete the line:
```lua
require('tests.unit.utils.visual_spec')
```
(and, if it leaves a dangling blank line where the `utils` group was, tidy it so the file has no doubled blank line).

- [ ] Remove the docs entry — in `docs/ARCHITECTURE.md`, in the `## Module structure` code block, delete these two lines (and the blank line separating them from the `scroll/` block above, so the layout stays clean):
```
  utils/
    visual.lua                Visual mode helpers
```

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures. Expected count: **444** (461 − 17 visual_spec tests). This decrease is expected and intended; the invariant is zero failures and the total stays above the 441 floor.

- [ ] Commit:
```bash
git add tests/init.lua docs/ARCHITECTURE.md
git commit -m "chore: remove dead utils/visual module and its spec"
```
(The `git rm` already staged the deletions; the `git add` stages the remaining edits.)

---

### Task 8: LuaCATS annotations on the public API (#47)

**Files:**
- Modify: `lua/whisk/config/defaults.lua`
- Modify: `lua/whisk/init.lua`
- Modify: `lua/whisk/engine/orchestrator.lua`
- Modify: `lua/whisk/registry/motions.lua`
- Modify: `lua/whisk/registry/traits.lua`
- Modify: `lua/whisk/context/Context.lua`

**Interfaces:** No runtime change. This task adds annotation comments only — the single permitted comment form (per Global Constraints). Types must match the code exactly as it stands after Tasks 1–7 (e.g., `WhiskPerformanceConfig` has NO `frame_rate_threshold`; `orchestrator.execute` returns `boolean`; `motions`/`traits` expose `unregister`; `config.set_enabled` exists).

Steps:

- [ ] Annotate the config schema — in `lua/whisk/config/defaults.lua`, insert the class definitions above `local M = {}` (the file's first line), and add a `---@type WhiskConfig` immediately above `M.config = {`:
```lua
---@class WhiskCursorConfig
---@field duration number Animation duration in milliseconds
---@field easing "linear"|"ease-in"|"ease-out"|"ease-in-out"
---@field enabled boolean

---@class WhiskScrollConfig
---@field duration number Animation duration in milliseconds
---@field easing "linear"|"ease-in"|"ease-out"|"ease-in-out"
---@field enabled boolean

---@class WhiskKeymapsConfig
---@field cursor boolean Install default cursor motion keymaps
---@field scroll boolean Install default scroll motion keymaps

---@class WhiskPerformanceConfig
---@field enabled boolean
---@field disable_syntax_during_scroll boolean
---@field ignore_events string[]
---@field reduce_frame_rate boolean
---@field auto_enable_on_large_files boolean
---@field large_file_threshold number

---@class WhiskConfig
---@field cursor WhiskCursorConfig
---@field scroll WhiskScrollConfig
---@field keymaps WhiskKeymapsConfig
---@field performance WhiskPerformanceConfig

local M = {}

---@type WhiskConfig
M.config = {
```
(Replace the existing `local M = {}` + `M.config = {` header; leave the table body unchanged.)

- [ ] Annotate the public entry points — in `lua/whisk/init.lua`, add annotations directly above each function. Above `function M.setup(user_config)`:
```lua
---@param user_config? WhiskConfig
```
Above `function M.reset()`, `function M.enable()`, `function M.disable()`, `function M.toggle()`, `function M.enable_cursor()`, `function M.disable_cursor()`, `function M.enable_scroll()`, `function M.disable_scroll()`, and `function M.toggle_performance()`, add:
```lua
---@return nil
```

- [ ] Annotate the orchestrator — in `lua/whisk/engine/orchestrator.lua`, add above `function M.execute(motion_id, input)`:
```lua
---@param motion_id string
---@param input table
---@return boolean handled
```
and above `function M.fallback(motion, input)`:
```lua
---@param motion table
---@param input table
---@return nil
```

- [ ] Annotate the motions registry — in `lua/whisk/registry/motions.lua`, add above `function M.register(definition)`:
```lua
---@param definition table
---@return nil
```
above `function M.get(motion_id)`:
```lua
---@param motion_id string
---@return table? motion
```
above `function M.get_by_category(category)`:
```lua
---@param category string
---@return table[] motions
```
above `function M.unregister(motion_id)`:
```lua
---@param motion_id string
---@return boolean removed
```

- [ ] Annotate the traits registry — in `lua/whisk/registry/traits.lua`, add above `function M.register(definition)`:
```lua
---@param definition table
---@return nil
```
above `function M.unregister(trait_id)`:
```lua
---@param trait_id string
---@return boolean removed
```

- [ ] Annotate the Context class — in `lua/whisk/context/Context.lua`, insert above `local Context = {}` (line 1):
```lua
---@class Context
---@field bufnr integer
---@field winid integer
---@field start { cursor: integer[], topline: integer, line_count: integer }
---@field input? { char?: string, count: integer, direction?: string }
---@field cursor? { line: integer, col: integer }
---@field viewport? { topline: integer, height: integer, width: integer }
---@field buffer? { line_count: integer }
```
and add annotations above the key methods — above `function Context.new(bufnr, winid)`:
```lua
---@param bufnr? integer
---@param winid? integer
---@return Context
```
above `function Context:is_valid()`:
```lua
---@return boolean valid
---@return string? reason
```
above `function Context:set_cursor(line, col)`:
```lua
---@param line integer
---@param col integer
---@return boolean ok
---@return string? reason
```
above `function Context:restore_view(topline, line, col)`:
```lua
---@param topline integer
---@param line integer
---@param col integer
---@return boolean ok
---@return string? reason
```

- [ ] Run tests and see them pass: `bash scripts/run_tests.sh` → zero failures, **444** (annotations are inert comments). If `luacheck` is installed (`command -v luacheck`), run `luacheck lua/whisk/` and confirm no new errors; otherwise the test suite is the gate.

- [ ] Commit:
```bash
git add lua/whisk/config/defaults.lua lua/whisk/init.lua lua/whisk/engine/orchestrator.lua lua/whisk/registry/motions.lua lua/whisk/registry/traits.lua lua/whisk/context/Context.lua
git commit -m "docs(annotations): add LuaCATS types for the public API"
```

---

### Task 9: Neovim version guard in `plugin/whisk.vim` (#45)

**Files:**
- Modify: `plugin/whisk.vim`

**Interfaces:** None. Behavioral guard only.

Steps:

- [ ] Add the guard — in `plugin/whisk.vim`, prepend these lines as the very top of the file (before the existing `if exists('g:loaded_whisk')` block):
```vim
if !has('nvim-0.8')
  echohl WarningMsg
  echomsg 'whisk.nvim requires Neovim >= 0.8'
  echohl None
  finish
endif

```
so the file begins:
```vim
if !has('nvim-0.8')
  echohl WarningMsg
  echomsg 'whisk.nvim requires Neovim >= 0.8'
  echohl None
  finish
endif

if exists('g:loaded_whisk')
  finish
endif
let g:loaded_whisk = 1
```

- [ ] Run tests (Lua suite is unaffected by the VimScript entry point): `bash scripts/run_tests.sh` → zero failures, **444**.

- [ ] Headless verification (modern Neovim passes the guard and loads). The failure path (old Neovim) is not testable in this environment; this probe confirms the guard is valid VimScript and does not block a supported version:
```bash
nvim --headless --clean --cmd "set rtp+=$PWD" \
  -c "runtime! plugin/whisk.vim" \
  -c "lua io.write('loaded=' .. tostring(vim.g.loaded_whisk) .. '\n')" \
  -c "qa!" 2>&1
```
Expected: output contains `loaded=1`.

- [ ] Commit:
```bash
git add plugin/whisk.vim
git commit -m "fix(plugin): guard against Neovim versions below 0.8"
```

---

### Task 10: Author vimdoc `doc/whisk.txt` (#20)

**Files:**
- Create: `doc/whisk.txt`

**Interfaces:** None. Produces help tags `whisk`, `whisk-setup`, `whisk-config`, `whisk-commands`, `whisk-api`, `whisk-motions`, `whisk-performance`, `whisk-health`.

Steps:

- [ ] Create `doc/whisk.txt` with the following content (standard vimdoc: 78-column tag markers, `*tag*` definitions right-aligned, `|cross-references|`). Keep every documented value in sync with the code as it stands after Tasks 1–9 (no `frame_rate_threshold`; `orchestrator.execute` returns a boolean; `:checkhealth whisk` exists):
```
*whisk.txt*	Smooth motion animations for Neovim

==============================================================================
CONTENTS					*whisk* *whisk-contents*

  1. Introduction ..................... |whisk-introduction|
  2. Requirements ..................... |whisk-requirements|
  3. Setup ............................ |whisk-setup|
  4. Configuration .................... |whisk-config|
  5. Commands ......................... |whisk-commands|
  6. Lua API .......................... |whisk-api|
  7. Motions .......................... |whisk-motions|
  8. Performance ...................... |whisk-performance|
  9. Health ........................... |whisk-health|
 10. Migration ........................ |whisk-migration|

==============================================================================
1. INTRODUCTION					*whisk-introduction*

whisk.nvim provides 60fps fluid animations for cursor movement, word
navigation, find/till, text objects, line jumps, search, screen lines, and
viewport scrolling, while preserving native Vim behavior. Motions work in
Normal and Visual modes with count prefixes (position motions zz/zt/zb are
Normal mode only).

==============================================================================
2. REQUIREMENTS					*whisk-requirements*

Neovim >= 0.8. The |plugin/whisk.vim| entry point warns and aborts on older
versions.

==============================================================================
3. SETUP					*whisk-setup*

The plugin auto-calls setup() on load. To call setup() yourself, set >
    let g:whisk_auto_setup = 0
<before the plugin loads, then: >
    require("whisk").setup({})
<
Calling setup() again at runtime re-initializes cleanly (keymaps and
autocommands are torn down and rebuilt).

==============================================================================
4. CONFIGURATION				*whisk-config*

All options with their defaults: >
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
      performance = {
        enabled = false,
        disable_syntax_during_scroll = true,
        ignore_events = { "WinScrolled", "CursorMoved", "CursorMovedI" },
        reduce_frame_rate = false,
        auto_enable_on_large_files = true,
        large_file_threshold = 5000,
      },
    })
<
cursor.duration	number (ms). Cursor animation duration. Default 150.
cursor.easing	"linear"|"ease-in"|"ease-out"|"ease-in-out". Default "ease-out".
cursor.enabled	boolean. Default true.
scroll.duration	number (ms). Scroll animation duration. Default 200.
scroll.easing	easing string. Default "ease-in-out".
scroll.enabled	boolean. Default true.
keymaps.cursor	boolean. Install default cursor keymaps. Default true.
keymaps.scroll	boolean. Install default scroll keymaps. Default true.

See |whisk-performance| for the performance.* options.

==============================================================================
5. COMMANDS					*whisk-commands*

:WhiskEnable			Enable all animations.
:WhiskDisable			Disable all animations.
:WhiskToggle			Toggle all animations.
:WhiskEnableCursor		Enable cursor animations.
:WhiskDisableCursor		Disable cursor animations.
:WhiskEnableScroll		Enable scroll animations.
:WhiskDisableScroll		Disable scroll animations.
:WhiskPerformanceEnable		Enable performance mode.
:WhiskPerformanceDisable	Disable performance mode.
:WhiskPerformanceToggle		Toggle performance mode.

==============================================================================
6. LUA API					*whisk-api*

>
    local whisk = require("whisk")
    whisk.setup({})
    whisk.enable()            whisk.disable()          whisk.toggle()
    whisk.enable_cursor()     whisk.disable_cursor()
    whisk.enable_scroll()     whisk.disable_scroll()
    whisk.toggle_performance()
    whisk.reset()             -- tear down keymaps/animations/registries/autocmds
<
Manual motion execution for custom keymaps: >
    local orchestrator = require("whisk.engine.orchestrator")
    orchestrator.execute("basic_j", { count = 5, direction = "j" })
<
orchestrator.execute(motion_id, input) returns true when the motion was
handled (animated, native fallback, or no movement) and false when motion_id
is not registered, warning once per unknown id.

Registry (extension points): >
    local motions = require("whisk.registry.motions")
    local traits  = require("whisk.registry.traits")
    motions.register({ id, keys, modes, traits, category, calculator })
    motions.unregister(id)
    traits.register({ id, apply, on_start, on_complete })
    traits.unregister(id)
<
register() validates required fields and errors on a duplicate id. Keymaps
installed for a motion are not removed by unregister(); that is the caller's
concern.

==============================================================================
7. MOTIONS					*whisk-motions*

Basic		basic_h basic_j basic_k basic_l basic_0 basic_$
Word		word_w word_b word_e word_W word_B word_E
Find		find_f find_F find_t find_T
Text Object	text_object_{ text_object_} text_object_( text_object_)
		text_object_%
Line		line_gg line_G line_|
Search		search_n search_N
Screen		screen_gj screen_gk
Scroll		scroll_ctrl_d scroll_ctrl_u scroll_ctrl_f scroll_ctrl_b
		position_zz position_zt position_zb (Normal mode only)

If a motion category is disabled, whisk falls back to native normal! behavior.
When a motion starts while any of its traits are animating, all active
animations complete instantly at their final positions (domination).

==============================================================================
8. PERFORMANCE					*whisk-performance*

performance.enabled		boolean. Start in performance mode. Default false.
performance.disable_syntax_during_scroll
				boolean. Disable syntax highlighting while
				performance mode is active. Default true.
performance.ignore_events	string[]. Events flagged ignorable via
				should_ignore_event(). Default WinScrolled,
				CursorMoved, CursorMovedI.
performance.reduce_frame_rate	boolean. Switch 60fps -> 30fps while active.
				Default false.
performance.auto_enable_on_large_files
				boolean. Auto-enable for large buffers.
				Default true.
performance.large_file_threshold
				number. Line-count threshold for auto-enable.
				Default 5000.

Toggle at runtime with |:WhiskPerformanceToggle|.

==============================================================================
9. HEALTH					*whisk-health*

Run |:checkhealth| whisk to diagnose your install. It reports the Neovim
version, whether setup() has run, config validity, keymap conflicts on
whisk-managed keys, luxmotion shim usage, and performance-mode status.

==============================================================================
10. MIGRATION					*whisk-migration*

whisk.nvim was previously nvim-luxmotion. A deprecation shim forwards
require("luxmotion"), :LuxMotion* commands, and g:luxmotion_auto_setup to
their whisk equivalents. The shim will be removed in a future release; update
your config to use whisk directly.

vim:tw=78:ts=8:noet:ft=help:norl:
```

- [ ] Verify help tags generate and resolve:
```bash
nvim --headless --clean -c "helptags $PWD/doc" -c "qa!" 2>&1
grep -E "^whisk(-setup|-config|-commands|-api|-motions|-performance|-health)?\b" "$PWD/doc/tags"
```
Expected: `doc/tags` is created and the grep prints lines for `whisk`, `whisk-setup`, `whisk-config`, `whisk-commands`, `whisk-api`, `whisk-motions`, `whisk-performance`, `whisk-health`. Note in the commit body that plugin managers run `:helptags` automatically on install, so `doc/tags` need not be committed (do not stage `doc/tags`).

- [ ] Run the Lua suite (unaffected): `bash scripts/run_tests.sh` → zero failures, **444**.

- [ ] Commit (stage only the doc source, not the generated `doc/tags`):
```bash
git add doc/whisk.txt
git commit -m "docs(vimdoc): add doc/whisk.txt help file"
```

---

### Task 11: CHANGELOG and CONTRIBUTING (#46, #51)

**Files:**
- Create: `CHANGELOG.md`
- Create: `CONTRIBUTING.md`

**Interfaces:** None.

Steps:

- [ ] Gather source material for the changelog history. Run:
```bash
git log --oneline main
git log --oneline --merges main
ls docs/superpowers/plans/
```
Use the merged wave plan titles under `docs/superpowers/plans/` (waves 1–4) plus the git history to write one changelog group per wave. Known historical anchors already on `main`: the nvim-luxmotion → whisk.nvim rename with deprecation shims (`fa2f6ba`), domination completes animations instead of stopping (`2236f0f`), and the zz/zt/zb viewport-change fix (`e2f4c8c`).

- [ ] Create `CHANGELOG.md` in Keep-a-Changelog format. Fill the four wave sections from the material gathered above (one `###` group per Added/Changed/Fixed as applicable per wave); the Unreleased section captures this wave's user-visible changes:
```markdown
# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `doc/whisk.txt` vimdoc help (`:help whisk`).
- `:checkhealth whisk` diagnostics module.
- LuaCATS type annotations for the public API.
- `motions.unregister()` / `traits.unregister()` registry extension seams.
- luarocks rockspec, `CONTRIBUTING.md`, and GitHub issue/PR templates.

### Changed
- `require("whisk").setup()` enable/disable toggles now route through
  `config.management.set_enabled`.
- `orchestrator.execute` returns a boolean and warns once on an unknown
  motion id.
- Registry `register()` validates required fields and rejects duplicate ids.
- `registry.keymaps.clear()` now restores pre-existing user mappings instead
  of deleting them.

### Removed
- Unread `performance.frame_rate_threshold` config key.
- Dead `whisk.utils.visual` module.

### Fixed
- `plugin/whisk.vim` now guards against Neovim versions below 0.8.

## [Wave 4 and earlier]

<!-- Fill from the wave plans under docs/superpowers/plans/ and git history.
     Summarize each of waves 1-4 as its own dated/themed group. Include the
     nvim-luxmotion -> whisk.nvim rename and the deprecation-shim removal
     timeline here. Note: no version tags exist yet; the first tagged release
     will move the Unreleased entries under a version heading. -->

[Unreleased]: https://github.com/josstei/whisk.nvim/compare/main...HEAD
```
Do NOT leave the "Wave 4 and earlier" section as a bare comment — replace it with concrete grouped entries drawn from the gathered material.

- [ ] Create `CONTRIBUTING.md`:
```markdown
# Contributing to whisk.nvim

Thanks for contributing! This guide covers local setup, testing, style, and
the release process.

## Development setup

Clone the repository. The unit test suite runs in a plain-Lua mock harness
(no Neovim required); integration checks use a real headless Neovim.

- Lua 5.1+ (or LuaJIT) for the unit suite.
- Neovim >= 0.8 for headless integration checks.

## Testing

whisk.nvim has two test tiers.

**Tier 1 — unit tests (mock harness).** Fast, no Neovim. The suite runs
against hand-written Vim API mocks under `tests/mocks/`, so tests do not need
a running editor:

    bash scripts/run_tests.sh

**Tier 2 — headless integration.** Real behavior the mocks cannot exercise is
verified with headless Neovim probes, e.g.:

    nvim --headless --clean --cmd "set rtp+=$PWD" -c "checkhealth whisk" -c "qa!"

Before writing this section's exact command, check `scripts/` and
`.github/workflows/` for the project's established second-tier / CI invocation
and cite it verbatim; if only the unit tier exists, document that plus the
headless probe pattern above.

Every change must leave `bash scripts/run_tests.sh` at zero failures.

## Code style

- Two-space indentation, double-quoted strings.
- No inline comments in `lua/whisk/`. The only permitted comment form is
  LuaCATS annotation comments (`---@class`, `---@param`, `---@return`).
- If configured, run `stylua lua/ tests/` and `luacheck lua/whisk/` before
  submitting.

## Commit convention

Conventional commits with a scope, matching the repo history:

    fix(engine): ...      feat(registry): ...
    docs: ...             chore: ...            test: ...

Policy: commit messages must NOT contain AI attribution — no "Generated
with ..." line and no "Co-Authored-By: Claude" trailer.

## Releases

1. Choose the next version `vX.Y.Z` following semver.
2. Move the `Unreleased` entries in `CHANGELOG.md` under a new `## [X.Y.Z]`
   heading and update the compare links.
3. Tag the release: `git tag vX.Y.Z && git push --tags`.
4. Create the matching GitHub release with the changelog section as its notes.
```

- [ ] Run tests (docs-only; unaffected): `bash scripts/run_tests.sh` → zero failures, **444**.

- [ ] Commit:
```bash
git add CHANGELOG.md CONTRIBUTING.md
git commit -m "docs: add CHANGELOG and CONTRIBUTING guide"
```

---

### Task 12: Rockspec and GitHub templates (#50, #52)

**Files:**
- Create: `whisk.nvim-scm-1.rockspec`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

**Interfaces:** None.

Steps:

- [ ] Create `whisk.nvim-scm-1.rockspec` (luarocks nvim-plugin conventions; `builtin` build auto-globs `lua/**/*.lua`, `copy_directories` ships `doc/` and `plugin/`):
```lua
rockspec_format = "3.0"
package = "whisk.nvim"
version = "scm-1"

source = {
  url = "git+https://github.com/josstei/whisk.nvim",
}

description = {
  summary = "Smooth motion animations for Neovim",
  detailed = [[
    whisk.nvim provides 60fps fluid animations for cursor movement, word
    navigation, find/till, text objects, line jumps, search, screen lines,
    and viewport scrolling, while preserving native Vim behavior.
  ]],
  homepage = "https://github.com/josstei/whisk.nvim",
  license = "MIT",
  labels = { "neovim" },
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  copy_directories = { "doc", "plugin" },
}
```

- [ ] Create `.github/ISSUE_TEMPLATE/bug_report.yml`:
```yaml
name: Bug report
description: Report a problem with whisk.nvim
labels: ["bug"]
body:
  - type: input
    id: nvim-version
    attributes:
      label: Neovim version
      description: Output of `nvim --version` (first line).
      placeholder: "NVIM v0.10.0"
    validations:
      required: true
  - type: input
    id: whisk-commit
    attributes:
      label: whisk.nvim commit
      description: The commit SHA or tag you are running.
    validations:
      required: true
  - type: textarea
    id: repro
    attributes:
      label: Minimal reproduction
      description: A minimal config and the exact steps to reproduce.
      render: lua
    validations:
      required: true
  - type: textarea
    id: expected
    attributes:
      label: Expected behavior
    validations:
      required: true
  - type: textarea
    id: actual
    attributes:
      label: Actual behavior
    validations:
      required: true
```

- [ ] Create `.github/ISSUE_TEMPLATE/feature_request.yml`:
```yaml
name: Feature request
description: Suggest an enhancement for whisk.nvim
labels: ["enhancement"]
body:
  - type: textarea
    id: problem
    attributes:
      label: Problem
      description: What are you trying to do that whisk.nvim does not support?
    validations:
      required: true
  - type: textarea
    id: proposal
    attributes:
      label: Proposed solution
    validations:
      required: true
  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives considered
    validations:
      required: false
```

- [ ] Create `.github/PULL_REQUEST_TEMPLATE.md`:
```markdown
## Summary

<!-- What does this PR change and why? -->

## Checklist

- [ ] Both test tiers pass: `bash scripts/run_tests.sh` (unit) and the
      headless integration checks are green.
- [ ] `stylua` reports no diffs (if configured).
- [ ] Documentation updated (README, `docs/`, `doc/whisk.txt`, CHANGELOG)
      where behavior or config changed.
- [ ] Commits follow the conventional-commit convention with a scope and
      contain no AI attribution.
```

- [ ] Run tests (docs/config only; unaffected): `bash scripts/run_tests.sh` → zero failures, **444**. If `luarocks` is installed (`command -v luarocks`), optionally run `luarocks lint whisk.nvim-scm-1.rockspec` and confirm it reports no errors; otherwise skip.

- [ ] Commit:
```bash
git add whisk.nvim-scm-1.rockspec .github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/feature_request.yml .github/PULL_REQUEST_TEMPLATE.md
git commit -m "chore: add rockspec and GitHub issue/PR templates"
```

---

## Wave completion checklist

- [ ] All 12 tasks committed on `audit/wave-5-polish-seams`.
- [ ] `bash scripts/run_tests.sh` → zero failures, total **>= 444** (441 floor cleared).
- [ ] `git diff main...HEAD` covers all 14 findings (#38, #17, #41, #36, #40, #48, #39, #47, #45, #20, #46, #51, #50, #52) and touches no out-of-scope files (no `lua/luxmotion/`, no `plugin/luxmotion.vim`).
- [ ] Fable wave review passes.
- [ ] PR opened to `main`.
