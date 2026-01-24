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

vim.opt.rtp:prepend(".")
require("ne.config").setup({})
local backend = require("ne.backend")

print("\n=== backend tests ===\n")

test("build_prompt includes file separators", function()
  local prompt = backend.build_prompt(
    "test.py",
    "def foo(): pass",
    "def foo():\n    return 42",
    {},
    {}
  )

  contains(prompt, "<|file_sep|>original/test.py")
  contains(prompt, "<|file_sep|>current/test.py")
  contains(prompt, "<|file_sep|>updated/test.py")
  contains(prompt, "def foo(): pass")
  contains(prompt, "def foo():\n    return 42")
end)

test("build_prompt includes context files", function()
  local context = {
    ["utils.py"] = "def helper(): pass",
  }

  local prompt = backend.build_prompt(
    "test.py",
    "original",
    "current",
    context,
    {}
  )

  contains(prompt, "<|file_sep|>utils.py")
  contains(prompt, "def helper(): pass")
end)

test("build_prompt includes recent diffs as patches", function()
  local diffs = {
    {
      file_path = "other.py",
      patch = "--- a/other.py\n+++ b/other.py\n@@ -1,1 +1,1 @@\n-old code\n+new code",
    },
  }

  local prompt = backend.build_prompt(
    "test.py",
    "original",
    "current",
    {},
    diffs
  )

  contains(prompt, "<|file_sep|>other.py.diff")
  contains(prompt, "-old code")
  contains(prompt, "+new code")
end)

test("build_prompt ordering is correct", function()
  local context = { ["ctx.py"] = "context" }
  local diffs = {
    { file_path = "d.py", patch = "--- a/d.py\n+++ b/d.py\n@@ -1,1 +1,1 @@\n-o\n+u" },
  }

  local prompt = backend.build_prompt("main.py", "orig", "curr", context, diffs)

  local ctx_pos = prompt:find("ctx.py")
  local diff_pos = prompt:find("d.py.diff")
  local orig_pos = prompt:find("original/main.py")
  local curr_pos = prompt:find("current/main.py")
  local upd_pos = prompt:find("updated/main.py")

  eq(true, ctx_pos < diff_pos)
  eq(true, diff_pos < orig_pos)
  eq(true, orig_pos < curr_pos)
  eq(true, curr_pos < upd_pos)
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
