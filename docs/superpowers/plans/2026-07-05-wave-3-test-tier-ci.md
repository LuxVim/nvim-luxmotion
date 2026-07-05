# Wave 3: Test Tier + CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real-Neovim integration test tier that exercises motions against a live buffer and pins the Wave 1–2 fidelity fixes as regressions, plus GitHub Actions CI and stylua/luacheck style tooling.

**Architecture:** A new `tests/nvim/` tree runs *inside* headless Neovim (`nvim --headless --clean -u tests/nvim/init.lua`) via a dependency-free harness that mirrors the existing unit-harness idiom (`describe`/`it`/`before_each`/assertions) and adds a `wait_for` helper (built on `vim.wait`) because whisk animations are asynchronous. Specs drive motions through whisk's installed keymaps, wait for the animation loop to settle, and assert real cursor/viewport targets against ground-truth Vim semantics. CI runs the plain-Lua unit tier, the Neovim-matrix integration tier, `stylua --check`, and `luacheck`; a canonical `stylua.toml` + one-time normalization make the style gate green.

**Tech Stack:** Lua 5.1+ (Neovim runtime), plain-Lua unit test harness (`tests/`), headless Neovim integration harness (`tests/nvim/`) for behavior the mocks cannot exercise, GitHub Actions, stylua 2.4.1, luacheck.

**Findings covered:**
- **#5** — Native-delegation calculators have zero behavioral coverage because the mock `vim.cmd` is a no-op; add a real-nvim integration tier that asserts actual motion targets. (Tasks 2, 3, 4)
- **#18** — No CI pipeline: the 441-test suite, stylua, and luacheck never run automatically; add `.github/workflows/ci.yml`. (Task 5)
- **#49** — No `stylua.toml`/`.editorconfig` and inconsistent quote style; add config and normalize once. (Task 1)

## Execution Model

- Branch: `audit/wave-3-test-tier-ci`, created from `main` **after** the Wave 1 and Wave 2 PRs have merged. Every fidelity spec in this wave asserts **post-Wave-1–2 behavior** — see the "Wave 1–2 dependency" note in Global Constraints.
- Executor: one Sonnet 5 subagent (high effort) per task, fresh context per task, given only that task's text plus this plan's header and Global Constraints.
- Task review: an Opus 4.8 subagent (xhigh effort) reviews each completed task's diff against the task spec before the next task starts. Review verdict gates progression.
- Wave review: one Fable agent reviews the wave's full branch diff (`git diff main...HEAD`) against this plan plus the findings file before the PR is opened.
- PR: opened to `main` when all tasks complete, `bash scripts/run_tests.sh` and `bash scripts/run_nvim_tests.sh` both pass, and the Fable wave review passes.

## Global Constraints

- Neovim >= 0.8 API compatibility only. The integration harness restricts itself to APIs present in 0.8.3 (the CI matrix floor): `vim.wait`, `vim.opt`, `vim.fn.globpath(dir, pat, false, true)`, `vim.api.nvim_replace_termcodes`, `vim.api.nvim_feedkeys`, `vim.api.nvim_get_autocmds`, `vim.fn.reg_executing`, `vim.api.nvim_win_get_cursor`. Do not reach for `vim.uv`, `nvim_exec2`, or anything newer.
- No inline comments in code. LuaCATS/JSDoc-style annotation comments are permitted only where a task explicitly calls for them (no task here calls for them).
- Commit style: conventional commits with scope, matching repo history (`test(nvim): ...`, `ci: ...`, `style: ...`, `chore(style): ...`, `docs: ...`). NO AI attribution of any kind — no "Generated with", no "Co-Authored-By: Claude".
- Every task ends with `bash scripts/run_tests.sh` passing (441+ unit tests, zero failures) before its commit. Integration tasks (2, 3, 4) additionally end with `bash scripts/run_nvim_tests.sh` passing.
- Do not modify files outside this wave's scope. Do not touch `lua/luxmotion/` or `plugin/luxmotion.vim` (deprecation shims). Task 1 normalizes `lua/` — under the `stylua.toml` in this plan, `lua/luxmotion/init.lua` is already clean and stylua leaves it byte-for-byte unchanged (verified); do not hand-edit it.
- **Wave 1–2 dependency (load-bearing):** The integration specs in Tasks 3 and 4 assert the *correct* Vim behavior, which the Wave 1 and Wave 2 fixes deliver. On the merged `main` these specs are green. If a spec is **red**, the corresponding upstream fix is missing or regressed — **escalate; do not weaken or edit the assertion**. That red is the regression detector working as designed. The expected values in this plan were captured from real (native) Neovim and are authoritative.

---

### Task 1: Style tooling and one-time normalization (#49)

Add the canonical formatting contract and normalize the codebase in a dedicated mechanical commit, so Task 5's `stylua --check lua/` gate is green.

**Files:**
- Create: `stylua.toml`, `.editorconfig`
- Modify (normalization only, via stylua): `lua/whisk/context/builder.lua`, `lua/whisk/config/defaults.lua`, `lua/whisk/config.lua`, `lua/whisk/config/validation.lua`, `lua/whisk/context/Context.lua`, `lua/whisk/cursor/keymaps.lua`, `lua/whisk/scroll/keymaps.lua`, `lua/whisk/engine/lifecycle.lua`, `lua/whisk/engine/loop.lua`, `lua/whisk/performance.lua`, `lua/whisk/utils/visual.lua` (exactly 11 files change under the config below; the list is informational — run stylua, do not hand-edit).

**Interfaces:**
- Produces: `stylua.toml` (the style contract consumed by Task 5's stylua-action, pinned to stylua **2.4.1**), `.editorconfig`.
- Consumes: nothing.

**Context for the executor (read before starting):**
- The style below matches the dominant existing style: 2-space indent, double quotes preferred, longest existing line is 119 chars (so `column_width = 120` rewraps nothing — verified).
- **stylua binary requirement:** `lua/whisk/engine/loop.lua` and `lua/whisk/registry/keymaps.lua` use Lua 5.2 `goto`/`::continue::`. Some feature-limited stylua builds (including a cargo build that may be on `PATH`) cannot parse `goto` and will *silently skip* those files, leaving `loop.lua` un-normalized and failing CI later. You **must** use a goto-capable stylua **2.4.1**. The probe + fallback below fetches the official release (verified to parse `goto` and to produce the exact 11-file diff). This executor runs on macOS arm64; for another platform substitute the matching release asset.

Steps:

- [ ] Create `stylua.toml` with this exact content:
  ```toml
  column_width = 120
  line_endings = "Unix"
  indent_type = "Spaces"
  indent_width = 2
  quote_style = "AutoPreferDouble"
  call_parentheses = "Always"
  ```
- [ ] Create `.editorconfig` with this exact content:
  ```ini
  root = true

  [*]
  charset = utf-8
  end_of_line = lf
  insert_final_newline = true
  trim_trailing_whitespace = true
  indent_style = space
  indent_size = 2

  [*.md]
  trim_trailing_whitespace = false
  ```
- [ ] Commit the config files:
  ```bash
  git add stylua.toml .editorconfig
  git commit -m "chore(style): add stylua.toml and .editorconfig"
  ```
- [ ] Select a goto-capable stylua 2.4.1. Probe the stylua already on `PATH`, and download the official release if it cannot parse `goto`:
  ```bash
  STYLUA=stylua
  if ! "$STYLUA" --check lua/whisk/engine/loop.lua >/dev/null 2>&1 \
     && "$STYLUA" --check lua/whisk/engine/loop.lua 2>&1 | grep -q "error parsing"; then
    curl -sSL -o /tmp/stylua.zip \
      https://github.com/JohnnyMorganz/StyLua/releases/download/v2.4.1/stylua-macos-aarch64.zip
    unzip -o /tmp/stylua.zip -d /tmp/stylua-bin
    chmod +x /tmp/stylua-bin/stylua
    STYLUA=/tmp/stylua-bin/stylua
  fi
  "$STYLUA" --version
  ```
  (`STYLUA` must print `stylua 2.4.1`. Keep this shell for the next steps, or re-derive `STYLUA` the same way.)
- [ ] Normalize `lua/` (reads the repo `stylua.toml` automatically):
  ```bash
  "$STYLUA" lua/
  ```
- [ ] Verify the whole tree is clean — this MUST exit 0 over ALL files (proves `loop.lua` and `keymaps.lua` were parsed and normalized, and that CI's stylua-action will agree byte-for-byte):
  ```bash
  "$STYLUA" --check lua/ ; echo "stylua exit=$?"
  ```
  Expected: `stylua exit=0` with no `Diff in` / `error parsing` output.
- [ ] Confirm behavior is unchanged — the normalization is purely mechanical (quote style, trailing-whitespace trimming, single-line-function expansion, trailing commas):
  ```bash
  bash scripts/run_tests.sh
  ```
  Expected: `441` passed, `0` failed.
- [ ] Commit the normalization on its own:
  ```bash
  git add lua/
  git commit -m "style: normalize lua/ with stylua"
  ```

---

### Task 2: Integration harness, runner, and test-tier docs (#5)

Stand up the real-Neovim test tier: the runner, the headless entrypoint, the dependency-free harness, and a single smoke spec that proves the mechanism end-to-end. Document the two tiers.

**Files:**
- Create: `scripts/run_nvim_tests.sh`, `tests/nvim/init.lua`, `tests/nvim/harness.lua`, `tests/nvim/specs/smoke_spec.lua`
- Modify: `docs/ARCHITECTURE.md` (add a `## Testing` section), `README.md` (add a `## Development` section)

**Interfaces:**
- Produces:
  - `scripts/run_nvim_tests.sh` — runs `${NVIM:-nvim} --headless --clean -u tests/nvim/init.lua`; exits 0 on success, 1 on any failure.
  - `tests/nvim/harness.lua` module `M` with: `M.describe(name, fn)`, `M.it(name, fn)`, `M.before_each(fn)`, `M.feed(keys)`, `M.wait_for(predicate, timeout_ms)`, `M.record_load_error(spec, err)`, `M.assert` (table: `equals`, `is_true`, `is_false`, `is_not_nil`, `greater_or_equal`, `less_or_equal`), `M.finish()` (prints summary, then `:cquit 1` on any failure / `:qall!` on success).
  - `tests/nvim/init.lua` — prepends the repo to `runtimepath`, sets `vim.g.whisk_auto_setup = 0`, puts `tests/nvim/` on `package.path`, `dofile`s every `tests/nvim/specs/*_spec.lua` (sorted), then calls `harness.finish()`. Spec discovery is by glob, so later spec tasks add files **without** editing `init.lua`.
- Consumes: `require("whisk")`, `require("whisk.engine.loop")` (resolved via the prepended runtimepath).

**Context for the executor:** Whisk animations are asynchronous (`vim.defer_fn`; cursor 150ms, scroll 200ms). The drive pattern for every spec is: `feed(keys)` (runs the mapped handler synchronously, which calls `loop.start` and sets `is_running() == true`), then `wait_for(function() return not require("whisk.engine.loop").is_running() end, 2000)` to let `vim.wait` pump the deferred frames to completion, then assert the final cursor/buffer. This exact mechanism was validated end-to-end (`5j` → line 6; the harness catches the live `%` bug on `main`).

Steps:

- [ ] Write the runner `scripts/run_nvim_tests.sh` (mirrors `scripts/run_tests.sh` structure; honors an optional `NVIM` override so CI can pass the matrix binary):
  ```bash
  #!/bin/bash

  set -e

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

  cd "$PROJECT_ROOT"

  NVIM_BIN="${NVIM:-nvim}"

  echo "Running whisk.nvim integration tests (real Neovim)..."
  echo "================================"
  echo "Using Neovim: $NVIM_BIN"
  echo ""

  "$NVIM_BIN" --headless --clean -u tests/nvim/init.lua

  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo ""
    echo "All integration tests passed!"
  else
    echo ""
    echo "Some integration tests failed."
  fi

  exit $exit_code
  ```
- [ ] Make it executable:
  ```bash
  chmod +x scripts/run_nvim_tests.sh
  ```
- [ ] Write `tests/nvim/harness.lua` with this exact content:
  ```lua
  local M = {}

  local state = {
    passed = 0,
    failed = 0,
    failures = {},
    suite = "",
    before = nil,
  }

  local function write(text)
    io.write(text)
  end

  function M.describe(name, fn)
    state.suite = name
    state.before = nil
    write("\n" .. name .. "\n")
    local ok, err = pcall(fn)
    if not ok then
      state.failed = state.failed + 1
      table.insert(state.failures, { suite = name, name = "<describe body>", err = tostring(err) })
      write("  ! describe body error: " .. tostring(err) .. "\n")
    end
  end

  function M.before_each(fn)
    state.before = fn
  end

  function M.it(name, fn)
    if state.before then
      local before_ok, before_err = pcall(state.before)
      if not before_ok then
        state.failed = state.failed + 1
        table.insert(state.failures, { suite = state.suite, name = name, err = "before_each: " .. tostring(before_err) })
        write("  - " .. name .. " [before_each FAILED]\n")
        return
      end
    end

    local ok, err = pcall(fn)
    if ok then
      state.passed = state.passed + 1
      write("  + " .. name .. "\n")
    else
      state.failed = state.failed + 1
      table.insert(state.failures, { suite = state.suite, name = name, err = tostring(err) })
      write("  - " .. name .. " [FAILED]\n")
    end
  end

  function M.feed(keys)
    local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
    vim.api.nvim_feedkeys(termcodes, "mx", false)
  end

  function M.wait_for(predicate, timeout_ms)
    return vim.wait(timeout_ms or 1000, predicate, 5)
  end

  function M.record_load_error(spec, err)
    state.failed = state.failed + 1
    table.insert(state.failures, { suite = spec, name = "<load>", err = tostring(err) })
    write("\n! failed to load " .. spec .. ": " .. tostring(err) .. "\n")
  end

  local assert = {}

  function assert.equals(actual, expected, message)
    if actual ~= expected then
      error(string.format("%s\nExpected: %s\nActual: %s", message or "Assertion failed", tostring(expected), tostring(actual)))
    end
  end

  function assert.is_true(value, message)
    if value ~= true then
      error(string.format("%s\nExpected: true\nActual: %s", message or "Assertion failed", tostring(value)))
    end
  end

  function assert.is_false(value, message)
    if value ~= false then
      error(string.format("%s\nExpected: false\nActual: %s", message or "Assertion failed", tostring(value)))
    end
  end

  function assert.is_not_nil(value, message)
    if value == nil then
      error(message or "Expected not nil, got nil")
    end
  end

  function assert.greater_or_equal(actual, expected, message)
    if not (actual >= expected) then
      error(string.format("%s\nExpected %s >= %s", message or "Assertion failed", tostring(actual), tostring(expected)))
    end
  end

  function assert.less_or_equal(actual, expected, message)
    if not (actual <= expected) then
      error(string.format("%s\nExpected %s <= %s", message or "Assertion failed", tostring(actual), tostring(expected)))
    end
  end

  M.assert = assert

  function M.finish()
    write("\n" .. string.rep("=", 60) .. "\n")
    write(string.format("Integration results: %d passed, %d failed\n", state.passed, state.failed))
    for i, failure in ipairs(state.failures) do
      write(string.format("\n%d) %s > %s\n   %s\n", i, failure.suite, failure.name, failure.err))
    end
    if state.failed > 0 then
      vim.cmd("cquit 1")
    else
      vim.cmd("qall!")
    end
  end

  return M
  ```
- [ ] Write `tests/nvim/init.lua` with this exact content:
  ```lua
  local source = debug.getinfo(1, "S").source
  local dir = source:match("@(.*/)")
  local repo = vim.fn.fnamemodify(dir .. "../../", ":p")

  vim.opt.runtimepath:prepend(repo)
  vim.g.whisk_auto_setup = 0
  package.path = dir .. "?.lua;" .. package.path

  local harness = require("harness")

  local specs = vim.fn.globpath(dir .. "specs", "*_spec.lua", false, true)
  table.sort(specs)

  for _, spec in ipairs(specs) do
    local ok, err = pcall(dofile, spec)
    if not ok then
      harness.record_load_error(spec, err)
    end
  end

  harness.finish()
  ```
- [ ] Write `tests/nvim/specs/smoke_spec.lua` with this exact content (drives `5j` through the installed keymap; green on `main` — validated cursor `{6, 0}`):
  ```lua
  local harness = require("harness")
  local describe, it, before_each = harness.describe, harness.it, harness.before_each
  local assert = harness.assert
  local wait_for, feed = harness.wait_for, harness.feed

  local function settle()
    wait_for(function()
      return not require("whisk.engine.loop").is_running()
    end, 2000)
  end

  describe("integration: harness smoke", function()
    before_each(function()
      require("whisk.engine.loop").stop_all()
      vim.cmd("enew!")
      vim.o.scroll = 0
      vim.wo.foldenable = false
      local lines = {}
      for i = 1, 20 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      require("whisk").setup({})
    end)

    it("drives j through the installed keymap and settles at the target", function()
      feed("5j")
      assert.is_true(require("whisk.engine.loop").is_running(), "the animation loop starts synchronously on feed")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[1], 6, "5j lands on line 6")
    end)
  end)
  ```
- [ ] Run the new tier and confirm the smoke spec passes:
  ```bash
  bash scripts/run_nvim_tests.sh ; echo "nvim tests exit=$?"
  ```
  Expected: `1 passed, 0 failed` and `nvim tests exit=0`.
- [ ] Confirm the unit tier is unaffected (`tests/nvim/` is never required by `tests/init.lua`):
  ```bash
  bash scripts/run_tests.sh
  ```
  Expected: `441` passed, `0` failed.
- [ ] Add a `## Testing` section to `docs/ARCHITECTURE.md`. Use Edit with this `old_string` (the current last line of the file):
  ```
  - Built-in motions and traits are registered through `registry/builtin.lua` during setup.
  ```
  and this `new_string`:
  ```
  - Built-in motions and traits are registered through `registry/builtin.lua` during setup.

  ---

  ## Testing

  whisk.nvim is covered by two complementary, dependency-free test tiers (no plenary/busted):

  - **Unit tier** (`tests/`, run with `bash scripts/run_tests.sh`) — plain Lua against a mocked `vim` table (`tests/mocks/`). Fast and hermetic, but it cannot exercise native-delegation motions: the mock `vim.cmd` records commands without executing `normal!`, so calculators that delegate to `%`, `w`, `f`, `n`, `gj`, etc. read back their start position under test. The unit tier therefore asserts wiring, config, engine bookkeeping, and calculator result *shape* — not real motion targets.
  - **Integration tier** (`tests/nvim/`, run with `bash scripts/run_nvim_tests.sh`) — runs inside real headless Neovim (`nvim --headless --clean -u tests/nvim/init.lua`). A small harness (`tests/nvim/harness.lua`) drives motions through the installed keymaps, waits for animations to settle via `wait_for` (built on `vim.wait`), and asserts genuine cursor/viewport results against real Vim semantics. This is the only tier that can catch native-motion regressions such as matching-bracket `%` (issue #14), multibyte column landing, curswant stickiness, fold-aware `j`, and jumplist behavior.

  `tests/nvim/init.lua` prepends the repo to `runtimepath`, disables auto-setup, and `dofile`s every `tests/nvim/specs/*_spec.lua` by glob, exiting `:cquit 1` on any failure or `:qall!` on success.
  ```
- [ ] Add a `## Development` section to `README.md`. Use Edit with this `old_string`:
  ```
  ---

  ## Installation
  ```
  and this `new_string`:
  ```
  ---

  ## Development

  whisk.nvim has two dependency-free test tiers (no plenary/busted):

  - **Unit tier** — plain Lua against a mocked `vim`, fast and hermetic:

    ```bash
    bash scripts/run_tests.sh
    ```

  - **Integration tier** — real headless Neovim driving motions through the installed keymaps and asserting actual cursor/viewport targets:

    ```bash
    bash scripts/run_nvim_tests.sh
    ```

    Override the Neovim binary with `NVIM=/path/to/nvim bash scripts/run_nvim_tests.sh`.

  ---

  ## Installation
  ```
- [ ] Commit:
  ```bash
  git add scripts/run_nvim_tests.sh tests/nvim/ docs/ARCHITECTURE.md README.md
  git commit -m "test(nvim): add headless Neovim integration harness and runner"
  ```

---

### Task 3: Cursor-motion fidelity regression specs (#5)

Pin the Wave 1–2 cursor-fidelity fixes as integration regressions: `%` matching, multibyte `l`/`$`, curswant stickiness, fold-aware `j`, and jumplist entry after `G`. Every expected value below was captured from real native Neovim and is authoritative.

**Files:**
- Create: `tests/nvim/specs/native_motion_spec.lua`, `tests/nvim/specs/jumplist_spec.lua`

**Interfaces:**
- Consumes: `tests/nvim/harness.lua` (`describe`/`it`/`before_each`/`feed`/`wait_for`/`assert`) from Task 2. No new interfaces produced. No edit to `init.lua` (specs are glob-discovered).

**Ground-truth values (native Neovim, `nvim_win_get_cursor` returns `{row(1-indexed), col(0-indexed byte)}`):**
- `%` on `"foo(bar)baz"` from `(` at col 3 → `{1, 7}` (matching `)`). *(On `main` pre-fix whisk returns `{1, 3}` — the live #14 bug.)*
- On `"aébc"` (bytes: `a`=0, `é`=1–2, `b`=3, `c`=4): first `l` → col 1, second `l` → col 3 (skips `é`'s two bytes), `$` → col 4.
- On lines `{"abc", "abcdefgh"}` from `{1,0}`: `$` → `{1, 2}`; then `j` → `{2, 7}` (curswant holds end-of-line).
- Closed manual fold over lines 3–5, cursor on line 3, `j` → `{6, 0}`.
- 20-line buffer, `clearjumps`, cursor line 1: `G` → `{20, 0}`; then native `<C-o>` → `{1, 0}` (origin pushed onto the jumplist by the Wave 2 `m'` step).

Steps:

- [ ] Write `tests/nvim/specs/native_motion_spec.lua` with this exact content:
  ```lua
  local harness = require("harness")
  local describe, it, before_each = harness.describe, harness.it, harness.before_each
  local assert = harness.assert
  local wait_for, feed = harness.wait_for, harness.feed

  local function settle()
    wait_for(function()
      return not require("whisk.engine.loop").is_running()
    end, 2000)
  end

  describe("integration: native-motion fidelity", function()
    before_each(function()
      require("whisk.engine.loop").stop_all()
      vim.cmd("enew!")
      vim.o.scroll = 0
      vim.wo.foldenable = false
      require("whisk").setup({})
    end)

    it("% jumps from ( to its matching ) (issue #14)", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo(bar)baz" })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      feed("%")
      settle()
      local cur = vim.api.nvim_win_get_cursor(0)
      assert.equals(cur[1], 1, "% stays on line 1")
      assert.equals(cur[2], 7, "% lands on the matching ) at byte column 7")
    end)

    it("l steps by whole multibyte characters", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "aébc" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      feed("l")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[2], 1, "first l lands on é at byte column 1")
      feed("l")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[2], 3, "second l skips é's two bytes to b at byte column 3")
    end)

    it("$ lands on the first byte of the last character", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "aébc" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      feed("$")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[2], 4, "$ lands on c at byte column 4")
    end)

    it("j after $ keeps curswant at end of line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "abcdefgh" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      feed("$")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[2], 2, "$ on line 1 lands at column 2")
      feed("j")
      settle()
      local cur = vim.api.nvim_win_get_cursor(0)
      assert.equals(cur[1], 2, "j moves to line 2")
      assert.equals(cur[2], 7, "curswant keeps the cursor at the end of line 2 (column 7)")
    end)

    it("j skips over a closed fold", function()
      local lines = {}
      for i = 1, 10 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.cmd("setlocal foldmethod=manual foldlevel=0")
      vim.wo.foldenable = true
      vim.cmd("3,5fold")
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      feed("j")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[1], 6, "j from the closed fold (lines 3-5) lands on line 6")
    end)
  end)
  ```
- [ ] Write `tests/nvim/specs/jumplist_spec.lua` with this exact content (`<C-o>` is not mapped by whisk, so it runs natively and synchronously — no settle after it):
  ```lua
  local harness = require("harness")
  local describe, it, before_each = harness.describe, harness.it, harness.before_each
  local assert = harness.assert
  local wait_for, feed = harness.wait_for, harness.feed

  local function settle()
    wait_for(function()
      return not require("whisk.engine.loop").is_running()
    end, 2000)
  end

  describe("integration: jumplist", function()
    before_each(function()
      require("whisk.engine.loop").stop_all()
      vim.cmd("enew!")
      vim.o.scroll = 0
      vim.wo.foldenable = false
      local lines = {}
      for i = 1, 20 do
        lines[i] = "row " .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.cmd("clearjumps")
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      require("whisk").setup({})
    end)

    it("G pushes the origin onto the jumplist so <C-o> returns", function()
      feed("G")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[1], 20, "G lands on the last line")
      feed("<C-o>")
      assert.equals(vim.api.nvim_win_get_cursor(0)[1], 1, "<C-o> returns to the pre-jump line 1")
    end)
  end)
  ```
- [ ] Run the integration tier; all fidelity specs must pass on the post-Wave-1–2 branch:
  ```bash
  bash scripts/run_nvim_tests.sh ; echo "nvim tests exit=$?"
  ```
  Expected: `nvim tests exit=0`, `0 failed`. If any of these are red, the upstream Wave 1–2 fix is missing — escalate per Global Constraints; do not edit the assertion.
- [ ] Confirm the unit tier still passes:
  ```bash
  bash scripts/run_tests.sh
  ```
  Expected: `441` passed, `0` failed.
- [ ] Commit:
  ```bash
  git add tests/nvim/specs/native_motion_spec.lua tests/nvim/specs/jumplist_spec.lua
  git commit -m "test(nvim): pin cursor-motion fidelity regressions (%, multibyte, curswant, fold, jumplist)"
  ```

---

### Task 4: Scroll, macro-replay, and engine regression specs (#5)

Pin the remaining Wave 1–2 fixes: counted `<C-d>` honoring `'scroll'`, synchronous motion during macro replay, domination on fast typing, and idempotent performance-autocmd setup.

**Files:**
- Create: `tests/nvim/specs/scroll_spec.lua`, `tests/nvim/specs/replay_spec.lua`, `tests/nvim/specs/engine_spec.lua`

**Interfaces:**
- Consumes: `tests/nvim/harness.lua` from Task 2. No new interfaces produced. No edit to `init.lua`.

**Ground-truth values (native Neovim):**
- 200-line buffer, `scroll=0`, cursor line 1: `5<C-d>` → cursor line 6 and `&scroll == 5`; a following bare `<C-d>` → cursor line 11 with `&scroll` still 5 (bare `<C-d>` respects the count-set `'scroll'`).
- Buffer `{"abcde","abcde","abcde","abcde"}`, register `a` = `"jx"`, cursor line 1: `@a` replays `j` **synchronously** (because `reg_executing() ~= ""`), then `x`, so line 2 becomes `"bcde"` and line 1 stays `"abcde"`. *(On `main` pre-fix the async `j` returns before `x` fires, so `x` mangles line 1 → `"bcde"` and line 2 is untouched — the exact bug this pins.)*
- **Why `setreg`, not literal `qajxq` recording:** during *recording*, `j` still animates asynchronously (the Wave 2 skip-seam keys on `reg_executing`, not `reg_recording`), so a recorded macro is confounded by recording-time timing. Setting register `a` directly isolates the **replay** path — the only path the fix changes.
- 20-line buffer, cursor line 1: `jjjjj` (five rapid motions, each dominating the prior mid-flight) → cursor line 6 exactly (no lost or doubled movement).
- After the Wave 1–2 fix, `require("whisk").setup()` registers its performance autocmds under a named `WhiskPerformance` augroup and re-setup does not duplicate them: `#nvim_get_autocmds({ group = "WhiskPerformance", event = "BufEnter" }) == 1`. *(On `main` pre-fix the group does not exist and the query throws — so assert the group exists first, then assert the per-event count.)*

Steps:

- [ ] Write `tests/nvim/specs/scroll_spec.lua` with this exact content:
  ```lua
  local harness = require("harness")
  local describe, it, before_each = harness.describe, harness.it, harness.before_each
  local assert = harness.assert
  local wait_for, feed = harness.wait_for, harness.feed

  local function settle()
    wait_for(function()
      return not require("whisk.engine.loop").is_running()
    end, 2000)
  end

  describe("integration: scroll", function()
    before_each(function()
      require("whisk.engine.loop").stop_all()
      vim.cmd("enew!")
      vim.wo.foldenable = false
      local lines = {}
      for i = 1, 200 do
        lines[i] = "L" .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.o.scroll = 0
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      require("whisk").setup({})
    end)

    it("{n}<C-d> scrolls n lines and sets 'scroll' to n", function()
      feed("5<C-d>")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[1], 6, "5<C-d> moves the cursor down 5 lines to line 6")
      assert.equals(vim.o.scroll, 5, "5<C-d> sets 'scroll' to 5")
    end)

    it("bare <C-d> respects the 'scroll' value set by a previous count", function()
      feed("5<C-d>")
      settle()
      feed("<C-d>")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[1], 11, "bare <C-d> scrolls another 5 lines to line 11")
      assert.equals(vim.o.scroll, 5, "'scroll' stays 5 for the bare <C-d>")
    end)
  end)
  ```
- [ ] Write `tests/nvim/specs/replay_spec.lua` with this exact content:
  ```lua
  local harness = require("harness")
  local describe, it, before_each = harness.describe, harness.it, harness.before_each
  local assert = harness.assert
  local wait_for, feed = harness.wait_for, harness.feed

  local function settle()
    wait_for(function()
      return not require("whisk.engine.loop").is_running()
    end, 2000)
  end

  describe("integration: macro replay", function()
    before_each(function()
      require("whisk.engine.loop").stop_all()
      vim.cmd("enew!")
      vim.o.scroll = 0
      vim.wo.foldenable = false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcde", "abcde", "abcde", "abcde" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      require("whisk").setup({})
    end)

    it("@a replays j synchronously so the following x edits the right line", function()
      vim.fn.setreg("a", "jx")
      feed("@a")
      settle()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.equals(lines[1], "abcde", "line 1 is untouched: x did not fire before j landed")
      assert.equals(lines[2], "bcde", "the replayed j landed on line 2 before x deleted its first character")
    end)
  end)
  ```
- [ ] Write `tests/nvim/specs/engine_spec.lua` with this exact content:
  ```lua
  local harness = require("harness")
  local describe, it, before_each = harness.describe, harness.it, harness.before_each
  local assert = harness.assert
  local wait_for, feed = harness.wait_for, harness.feed

  local function settle()
    wait_for(function()
      return not require("whisk.engine.loop").is_running()
    end, 2000)
  end

  describe("integration: engine invariants", function()
    before_each(function()
      require("whisk.engine.loop").stop_all()
      vim.cmd("enew!")
      vim.o.scroll = 0
      vim.wo.foldenable = false
      local lines = {}
      for i = 1, 20 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      require("whisk").setup({})
    end)

    it("fast repeated j dominates in-flight animations without losing movement", function()
      feed("jjjjj")
      settle()
      assert.equals(vim.api.nvim_win_get_cursor(0)[1], 6, "five rapid j motions land exactly on line 6")
    end)

    it("repeated setup() leaves exactly one WhiskPerformance BufEnter autocmd", function()
      require("whisk").setup({})
      require("whisk").setup({})
      local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "WhiskPerformance", event = "BufEnter" })
      assert.is_true(ok, "the WhiskPerformance augroup exists after setup()")
      assert.equals(#autocmds, 1, "double setup() does not duplicate the BufEnter autocmd")
    end)
  end)
  ```
- [ ] Run the integration tier; all specs must pass on the post-Wave-1–2 branch:
  ```bash
  bash scripts/run_nvim_tests.sh ; echo "nvim tests exit=$?"
  ```
  Expected: `nvim tests exit=0`, `0 failed`. A red spec means the upstream fix is missing — escalate per Global Constraints.
- [ ] Confirm the unit tier still passes:
  ```bash
  bash scripts/run_tests.sh
  ```
  Expected: `441` passed, `0` failed.
- [ ] Commit:
  ```bash
  git add tests/nvim/specs/scroll_spec.lua tests/nvim/specs/replay_spec.lua tests/nvim/specs/engine_spec.lua
  git commit -m "test(nvim): pin scroll, macro-replay, and engine regressions"
  ```

---

### Task 5: GitHub Actions CI + luacheck config (#18)

Add the automated gate: unit tests on plain Lua, integration tests on a Neovim matrix, `stylua --check`, and `luacheck` — on push to `main` and on every pull request.

**Files:**
- Create: `.github/workflows/ci.yml`, `.luacheckrc`
- Modify: `README.md` (extend `## Requirements` and `## Development`)

**Interfaces:**
- Consumes: `scripts/run_tests.sh` (Task 0/existing), `scripts/run_nvim_tests.sh` (Task 2, honors `NVIM`), `stylua.toml` (Task 1). No interfaces produced.

**Context for the executor:**
- `.luacheckrc` must make `luacheck lua/` exit 0. `globals = { "vim" }` alone leaves 3 warnings post-normalization (unused callback arg `progress` ×2, unused loop variable `motion_id`), and luacheck exits non-zero on warnings. `unused_args = false` (the standard nvim-plugin idiom for fixed callback signatures — suppresses luacheck 212/213) clears them with **no source edits**, which are out of this wave's scope. Verified: post-normalization `luacheck lua/` with the config below reports `0 warnings / 0 errors`.
- The official stylua release (what `JohnnyMorganz/stylua-action` installs) parses the `goto`/`::continue::` in `loop.lua`/`keymaps.lua` — verified. Pin it to `2.4.1` to match Task 1's normalization byte-for-byte.
- `rhysd/action-setup-vim` exposes the installed binary as `steps.<id>.outputs.executable`; pass it through the `NVIM` env var that `scripts/run_nvim_tests.sh` reads. The matrix floor `v0.8.3` enforces the 0.8 API constraint the harness was written to.

Steps:

- [ ] Write `.luacheckrc` with this exact content:
  ```lua
  globals = { "vim" }
  unused_args = false
  ```
- [ ] Write `.github/workflows/ci.yml` with this exact content:
  ```yaml
  name: CI

  on:
    push:
      branches: [main]
    pull_request:

  jobs:
    unit:
      name: Unit tests (plain Lua)
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - name: Install Lua 5.1
          run: sudo apt-get update && sudo apt-get install -y lua5.1
        - name: Run unit tests
          run: bash scripts/run_tests.sh

    integration:
      name: Integration tests (Neovim ${{ matrix.neovim }})
      runs-on: ubuntu-latest
      strategy:
        fail-fast: false
        matrix:
          neovim: [v0.8.3, stable, nightly]
      steps:
        - uses: actions/checkout@v4
        - name: Set up Neovim
          uses: rhysd/action-setup-vim@v1
          id: nvim
          with:
            neovim: true
            version: ${{ matrix.neovim }}
        - name: Run integration tests
          run: bash scripts/run_nvim_tests.sh
          env:
            NVIM: ${{ steps.nvim.outputs.executable }}

    lint:
      name: Lint (stylua + luacheck)
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - name: stylua
          uses: JohnnyMorganz/stylua-action@v4
          with:
            version: 2.4.1
            args: --check lua/
        - name: Set up Lua
          uses: leafo/gh-actions-lua@v10
          with:
            luaVersion: "5.1"
        - name: Set up LuaRocks
          uses: leafo/gh-actions-luarocks@v4
        - name: Install luacheck
          run: luarocks install luacheck
        - name: Run luacheck
          run: luacheck lua/
  ```
- [ ] Confirm `luacheck lua/` is green locally with the new config (if luacheck is installed):
  ```bash
  luacheck lua/ ; echo "luacheck exit=$?"
  ```
  Expected: `0 warnings / 0 errors` and `luacheck exit=0`. (If luacheck is not installed locally, rely on the CI `lint` job — the config was verified against the post-normalization tree.)
- [ ] Extend the `## Requirements` section of `README.md`. Use Edit with this `old_string`:
  ```
  ## Requirements

  - Neovim >= 0.8
  ```
  and this `new_string`:
  ```
  ## Requirements

  - Neovim >= 0.8

  Contributing additionally requires Lua 5.1+ (or LuaJIT), Neovim (CI tests 0.8.3, stable, and nightly), `stylua`, and `luacheck`.
  ```
- [ ] Extend the `## Development` section of `README.md` with the lint commands and a CI note. Use Edit with this `old_string`:
  ```
      Override the Neovim binary with `NVIM=/path/to/nvim bash scripts/run_nvim_tests.sh`.

  ---

  ## Installation
  ```
  and this `new_string`:
  ```
      Override the Neovim binary with `NVIM=/path/to/nvim bash scripts/run_nvim_tests.sh`.

  ### Linting

  ```bash
  stylua --check lua/
  luacheck lua/
  ```

  All tiers and linters run in CI (`.github/workflows/ci.yml`) on every push to `main` and every pull request.

  ---

  ## Installation
  ```
- [ ] Confirm both test tiers still pass (CI runs the same commands):
  ```bash
  bash scripts/run_tests.sh
  bash scripts/run_nvim_tests.sh ; echo "nvim tests exit=$?"
  ```
  Expected: unit `441` passed / `0` failed; integration `0 failed` / `nvim tests exit=0`.
- [ ] Commit:
  ```bash
  git add .github/workflows/ci.yml .luacheckrc README.md
  git commit -m "ci: add GitHub Actions workflow and luacheck config"
  ```

---

## Verification summary (for the wave reviewer)

- Unit tier unchanged at 441 passing (`bash scripts/run_tests.sh`).
- Integration tier green (`bash scripts/run_nvim_tests.sh`): 1 smoke + 5 native-motion + 1 jumplist + 2 scroll + 1 replay + 2 engine specs.
- `stylua --check lua/` exits 0; `luacheck lua/` reports 0 warnings.
- `.github/workflows/ci.yml` present with `unit`, `integration` (matrix v0.8.3/stable/nightly), and `lint` jobs, triggered on push-to-main and pull_request.
- Every fidelity spec asserts a real native-Neovim value (all captured and listed per task); a red spec indicates a missing upstream Wave 1–2 fix, not a spec defect.
