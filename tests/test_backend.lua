local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("✓ " .. name)
  else
    print("✗ " .. name .. ": " .. tostring(err))
    vim.g.test_failures = (vim.g.test_failures or 0) + 1
  end
end

local function eq(expected, actual)
  if expected ~= actual then
    error(string.format("expected %q, got %q", tostring(expected), tostring(actual)))
  end
end

local function contains(str, substr)
  if not str:find(substr, 1, true) then
    error(string.format("expected %q to contain %q", str, substr))
  end
end

local function not_contains(str, substr)
  if str:find(substr, 1, true) then
    error(string.format("expected %q to NOT contain %q", str, substr))
  end
end

vim.opt.rtp:prepend(".")
require("ne.config").setup({})
local backend = require("ne.backend")

print("\n=== backend tests ===\n")

test("build_prompt includes file separators", function()
  local prompt = backend.build_prompt(
    "test.py",
    "def foo(): pass",
    "def foo():\n    return 42",
    5, -- cursor_line
    {},
    {}
  )

  contains(prompt, "<|file_sep|>original/test.py")
  contains(prompt, "<|file_sep|>current/test.py")
  contains(prompt, "<|file_sep|>updated/test.py")
  contains(prompt, "def foo(): pass")
  contains(prompt, "def foo():\n    return 42")
end)

test("build_prompt does not include line headers", function()
  -- Create larger content that would have been truncated before
  local lines = {}
  for i = 1, 50 do
    table.insert(lines, "line" .. i)
  end
  local original = table.concat(lines, "\n")
  lines[25] = "modified"
  local current = table.concat(lines, "\n")

  local prompt = backend.build_prompt(
    "test.py",
    original,
    current,
    25, -- cursor at modified line
    {},
    {}
  )

  -- Should NOT contain line headers
  not_contains(prompt, "[lines")
  not_contains(prompt, "of 50]")
end)

test("build_prompt uses 21-line window around cursor", function()
  -- Create 50 lines
  local lines = {}
  for i = 1, 50 do
    table.insert(lines, "line" .. i)
  end
  local original = table.concat(lines, "\n")
  lines[25] = "modified"
  local current = table.concat(lines, "\n")

  local prompt = backend.build_prompt(
    "test.py",
    original,
    current,
    25, -- cursor at line 25
    {},
    {}
  )

  -- Should contain lines around cursor (15-35 for 21-line window)
  contains(prompt, "line25")
  contains(prompt, "line15")
  contains(prompt, "line35")
  -- Should NOT contain lines far from cursor
  not_contains(prompt, "line1\n")
  not_contains(prompt, "line50")
end)

test("build_prompt includes context files", function()
  local context = {
    ["utils.py"] = "def helper(): pass",
  }

  local prompt = backend.build_prompt(
    "test.py",
    "original",
    "current",
    1,
    context,
    {}
  )

  contains(prompt, "<|file_sep|>utils.py")
  contains(prompt, "def helper(): pass")
end)

test("build_prompt includes recent diffs as original/updated", function()
  local diffs = {
    {
      file_path = "other.py",
      original = "old code",
      updated = "new code",
    },
  }

  local prompt = backend.build_prompt(
    "test.py",
    "original",
    "current",
    1,
    {},
    diffs
  )

  contains(prompt, "<|file_sep|>original/other.py")
  contains(prompt, "old code")
  contains(prompt, "<|file_sep|>updated/other.py")
  contains(prompt, "new code")
end)

test("build_prompt ordering is correct", function()
  local context = { ["ctx.py"] = "context" }
  local diffs = {
    { file_path = "d.py", original = "o", updated = "u" },
  }

  local prompt = backend.build_prompt("main.py", "orig", "curr", 1, context, diffs)

  local ctx_pos = prompt:find("ctx.py")
  local diff_orig_pos = prompt:find("original/d.py")
  local orig_pos = prompt:find("original/main.py")
  local curr_pos = prompt:find("current/main.py")
  local upd_pos = prompt:find("updated/main.py")

  eq(true, ctx_pos < diff_orig_pos)
  eq(true, diff_orig_pos < orig_pos)
  eq(true, orig_pos < curr_pos)
  eq(true, curr_pos < upd_pos)
end)

test("build_prompt returns metadata with cursor_line", function()
  local _, meta = backend.build_prompt(
    "test.py",
    "original",
    "current",
    10,
    {},
    {}
  )

  eq(10, meta.cursor_line)
  eq("test.py", meta.file)
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
