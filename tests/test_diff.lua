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

local function not_contains(str, substr)
  if str:find(substr, 1, true) then
    error(string.format("expected %q to NOT contain %q", str, substr))
  end
end

vim.opt.rtp:prepend(".")
require("ne.config").setup({})
local diff = require("ne.diff")

print("\n=== diff tests ===\n")

test("capture and get original state", function()
  diff.clear()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "test.lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })

  diff.capture_original(bufnr)

  local original = diff.get_original(bufnr)
  eq("line1\nline2", original)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("record_diff stores 21-line windows", function()
  diff.clear()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "test2.lua")

  -- Create 50 lines
  local lines = {}
  for i = 1, 50 do
    table.insert(lines, "line" .. i)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  diff.capture_original(bufnr)

  -- Modify line 25
  lines[25] = "modified"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  diff.record_diff(bufnr)

  local diffs = diff.get_recent_diffs()
  eq(1, #diffs)
  eq(true, diffs[1].original ~= nil and diffs[1].original ~= "")
  eq(true, diffs[1].updated ~= nil and diffs[1].updated ~= "")

  -- Should contain the changed line
  eq(true, diffs[1].original:find("line25") ~= nil)
  eq(true, diffs[1].updated:find("modified") ~= nil)

  -- Should NOT contain line headers (no [lines X-Y of Z])
  not_contains(diffs[1].original, "[lines")
  not_contains(diffs[1].updated, "[lines")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("record_diff extracts window around change", function()
  diff.clear()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "test3.lua")

  -- Create 50 lines
  local lines = {}
  for i = 1, 50 do
    table.insert(lines, "line" .. i)
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  diff.capture_original(bufnr)

  -- Modify line 40 (near end)
  lines[40] = "changed"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  diff.record_diff(bufnr)

  local diffs = diff.get_recent_diffs()
  eq(1, #diffs)

  -- Should contain changed line and context
  eq(true, diffs[1].updated:find("changed") ~= nil)

  -- Window should be 21 lines centered on change
  -- So it should contain lines around 40 but not line 1
  eq(true, diffs[1].updated:find("line35") ~= nil or diffs[1].updated:find("line30") ~= nil)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("record_diff respects max_diffs", function()
  diff.clear()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "test4.lua")

  for i = 1, 10 do
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "content" .. i })
    diff.capture_original(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "content" .. (i + 1) })
    diff.record_diff(bufnr)
  end

  local diffs = diff.get_recent_diffs()
  eq(true, #diffs <= 5)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("clear resets state", function()
  diff.clear()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "test5.lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test" })

  diff.capture_original(bufnr)
  diff.clear()

  local diffs = diff.get_recent_diffs()
  eq(0, #diffs)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
