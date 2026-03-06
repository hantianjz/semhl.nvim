# semhl.nvim Troubleshooting Plan

This plan is tailored to the reported issues:

1. Semantic highlights are inconsistent in a real `~/.config/nvim` setup.
2. Highlights are not correctly updated when text is moved.
3. Highlights are not correctly updated when code is commented/uncommented.

It incorporates guidance from Oracle analysis of the current implementation (`lua/semhl.lua`).

## Repro Fixtures

Use these files during manual checks:

1. `test/examples/lua_semhl_scenarios.lua`
2. `test/examples/typescript_semhl_scenarios.ts`
3. `test/examples/rust_semhl_scenarios.rs`

For each file, run the same edit operations:

1. Move a highlighted block (`dd` + `p` or visual move).
2. Comment/uncomment lines containing identifiers.
3. Rename one identifier to a new word.

## Baseline Setup

1. Start Neovim with your full config and open one scenario file.
2. Run `:SemhlLoad`.
3. Capture baseline:

```vim
:lua local s=require('semhl'); print('buf', vim.api.nvim_get_current_buf(), 'marks', #vim.api.nvim_buf_get_extmarks(0, s._ns, 0, -1, {type='highlight'}))
```

Expected result: marks are present and identifiers in code (not comments) are colored.

## Step-By-Step Plan With Tests

### Step 1: Verify duplicate callback attachment on repeated BufEnter

Why: `semhl_on_buffer_enter` currently re-registers parser callbacks each time, which can cause races and inconsistent updates.

Test:

1. Open one scenario file.
2. Switch away and back to the buffer 5-10 times.
3. Edit one identifier line once.
4. Observe whether highlighting flickers, duplicates, or lags.

Pass criteria: single stable update behavior per edit (no obvious duplicate processing).

If it fails: add a guard in `semhl_on_buffer_enter` to skip re-attach if `M._BUFFER_PARSERS[buffer]` already exists.

### Step 2: Validate full refresh stale extmark behavior

Why: full refresh path may re-highlight without first clearing all old extmarks, leaving stale colors after structural edits.

Test:

1. In scenario file, comment out a line with identifiers.
2. Trigger save (`:w`) or leave/re-enter buffer.
3. Check whether identifiers inside commented lines still appear colored.

Pass criteria: commented identifiers are not highlighted after refresh.

If it fails: clear namespace before full-buffer reprocess in refresh path.

### Step 3: Isolate `on_bytes` range update issues

Why: `on_bytes` dirty-range bookkeeping may not include old+new span correctly for deletes/replacements.

Test:

1. Temporarily disable `on_bytes` callback registration and keep `on_changedtree` only.
2. Repeat move/comment/rename operations in all three scenario files.
3. Compare stability to baseline.

Pass criteria: behavior becomes stable or clearly improves.

If it passes: `on_bytes` logic is a primary culprit and should be corrected before re-enabling.

### Step 4: Verify highlight namespace compatibility with full config

Why: defining highlight groups in plugin namespace can conflict with other config/plugins that manipulate hl namespaces.

Test:

1. While scenario buffer is open, switch colorschemes and split windows.
2. Check whether semhl extmarks still exist but colors disappear.
3. Compare with groups defined in global namespace (`ns=0`).

Pass criteria: semhl colors remain visible across windows/colorscheme transitions.

If it fails: create highlight groups in global namespace and keep only extmarks in semhl namespace.

### Step 5: Regression-check move and comment operations after each fix

Why: each fix should preserve correctness for the exact user-reported operations.

Test matrix (run after each applied fix):

1. Move code block containing 2+ identifiers.
2. Comment and uncomment those lines.
3. Rename one identifier and verify old color span is removed.
4. Undo/redo all edits.

Pass criteria: highlights always match current syntax/identifier positions with no stale spans.

### Step 6: Add automated regression tests

Why: lock in behavior and prevent regressions.

Test additions to `test/manual/highlighting_spec.lua` (or dedicated new spec):

1. Comment/uncomment line removes/restores identifier highlight.
2. Replace identifier text removes old extmark range.
3. Move line keeps extmarks aligned to actual identifier text.
4. Re-entering buffer does not multiply processing side effects.

Pass criteria: all tests pass under `./run_tests.sh --all`.

## Execution Order

Apply and verify in this order:

1. Attach guard to prevent duplicate callback registration.
2. Clear namespace before full refresh.
3. Temporarily disable `on_bytes` and re-test scenarios.
4. Adjust highlight group namespace usage if disappearing colors persist.
5. Rework `on_bytes` dirty-range math (old+new union), then re-enable.
6. Add regression tests and run full suite.

## Verification Commands

1. Unit tests: `./run_tests.sh`
2. Full test suite: `./run_tests.sh --all`
3. Manual scenario run: open each file in `test/examples/` with full user config and exercise edit operations.
