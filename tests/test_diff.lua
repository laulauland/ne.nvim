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

test("record_diff stores changes as original/updated", function()
  diff.clear()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "test2.lua")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "original" })

  diff.capture_original(bufnr)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified" })
  diff.record_diff(bufnr)

  local diffs = diff.get_recent_diffs()
  eq(1, #diffs)
  eq(true, diffs[1].original ~= nil and diffs[1].original ~= "")
  eq(true, diffs[1].updated ~= nil and diffs[1].updated ~= "")
  eq(true, diffs[1].original:find("original") ~= nil)
  eq(true, diffs[1].updated:find("modified") ~= nil)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("record_diff respects max_diffs", function()
  diff.clear()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "test3.lua")

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
  vim.api.nvim_buf_set_name(bufnr, "test4.lua")
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
