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
require("ne.config").setup({
  server = {
    model_path = "",
    port = 9999,
  },
})
local server = require("ne.server")

print("\n=== server tests ===\n")

test("output buffer is nil initially", function()
  eq(nil, server.output_buf)
end)

test("initial status is stopped", function()
  eq("stopped", server.get_status())
end)

test("is_running returns false initially", function()
  eq(false, server.is_running())
end)

test("stop without running returns error", function()
  local called = false
  server.stop(function(ok, err)
    called = true
    eq(false, ok)
    eq("server not running", err)
  end)
  eq(true, called)
end)

test("start without model_path fails", function()
  require("ne.config").setup({
    server = {
      model_path = "",
    },
  })

  local called = false
  server.start(function(ok, err)
    called = true
    eq(false, ok)
    eq("server.model_path not configured", err)
  end)
  eq(true, called)
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
