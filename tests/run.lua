local test_files = {
  "tests/test_util.lua",
  "tests/test_diff.lua",
  "tests/test_backend.lua",
  "tests/test_completion.lua",
  "tests/test_server.lua",
}

local total_failures = 0

for _, file in ipairs(test_files) do
  vim.g.test_failures = 0
  dofile(file)
  total_failures = total_failures + (vim.g.test_failures or 0)
end

print("\n=== Summary ===\n")
if total_failures > 0 then
  print(string.format("Total failures: %d", total_failures))
  vim.cmd("cq 1")
else
  print("All test suites passed!")
end
