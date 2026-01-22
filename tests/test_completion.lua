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
local completion = require("ne.completion")

print("\n=== completion tests ===\n")

test("namespace is created", function()
  eq(true, completion.ns_id ~= nil)
  eq(true, completion.ns_id > 0)
end)

test("has_suggestion returns false when no inlay", function()
  completion.dispose()
  eq(false, completion.has_suggestion())
end)

test("dispose clears inlay state", function()
  completion.inlay = { bufnr = 1, completion_text = "test" }
  completion.dispose()
  eq(nil, completion.inlay)
end)

test("inlay state set directly is valid", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world" })

  completion.inlay = {
    bufnr = bufnr,
    completion_text = "suggestion",
    row = 0,
    col = 5,
    is_floating = false,
  }

  eq(true, completion.inlay ~= nil)
  eq(bufnr, completion.inlay.bufnr)
  eq("suggestion", completion.inlay.completion_text)
  eq(0, completion.inlay.row)
  eq(5, completion.inlay.col)

  completion.dispose()
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("has_suggestion returns true with valid inlay", function()
  local bufnr = vim.api.nvim_create_buf(false, true)

  completion.inlay = {
    bufnr = bufnr,
    completion_text = "test completion",
    row = 0,
    col = 0,
  }

  eq(true, completion.has_suggestion())

  completion.dispose()
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("has_suggestion false with empty completion_text", function()
  completion.inlay = {
    bufnr = 1,
    completion_text = "",
    row = 0,
    col = 0,
  }
  eq(false, completion.has_suggestion())
  completion.dispose()
end)

test("render requires non-empty completion", function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "test" })
  vim.api.nvim_set_current_buf(bufnr)

  completion.render(bufnr, "")
  eq(nil, completion.inlay)

  completion.render(bufnr, nil)
  eq(nil, completion.inlay)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
