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
  if type(expected) == "table" and type(actual) == "table" then
    if #expected ~= #actual then
      error(string.format("expected %d items, got %d", #expected, #actual))
    end
    for i, v in ipairs(expected) do
      if v ~= actual[i] then
        error(string.format("at index %d: expected %q, got %q", i, tostring(v), tostring(actual[i])))
      end
    end
  elseif expected ~= actual then
    error(string.format("expected %q, got %q", tostring(expected), tostring(actual)))
  end
end

vim.opt.rtp:prepend(".")
local util = require("ne.util")

print("\n=== util tests ===\n")

test("split_lines splits on newlines", function()
  local lines = util.split_lines("a\nb\nc")
  eq({ "a", "b", "c" }, lines)
end)

test("split_lines handles empty string", function()
  local lines = util.split_lines("")
  eq({ "" }, lines)
end)

test("split_lines handles single line", function()
  local lines = util.split_lines("hello")
  eq({ "hello" }, lines)
end)

test("join_lines joins with newlines", function()
  local result = util.join_lines({ "a", "b", "c" })
  eq("a\nb\nc", result)
end)

test("trim removes whitespace", function()
  eq("hello", util.trim("  hello  "))
  eq("hello", util.trim("hello"))
  eq("", util.trim("   "))
end)

test("trim_start removes leading whitespace", function()
  eq("hello  ", util.trim_start("  hello  "))
  eq("hello", util.trim_start("hello"))
end)

test("first_line_split separates first line", function()
  local result = util.first_line_split("first\nsecond\nthird", "Comment")
  eq("first", result.first_line)
  eq(2, #result.other_lines)
end)

test("get_last_line returns last line", function()
  eq("third", util.get_last_line("first\nsecond\nthird"))
  eq("only", util.get_last_line("only"))
end)

test("line_count counts newlines", function()
  eq(0, util.line_count("hello"))
  eq(2, util.line_count("a\nb\nc"))
end)

test("to_next_word extracts first word", function()
  eq("hello", util.to_next_word("hello world"))
  eq(" world", util.to_next_word(" world"))
end)

test("contains finds substring", function()
  eq(true, util.contains("hello world", "world"))
  eq(false, util.contains("hello", "world"))
end)

test("json_encode/decode roundtrip", function()
  local data = { key = "value", num = 42 }
  local encoded = util.json_encode(data)
  local decoded = util.json_decode(encoded)
  eq("value", decoded.key)
  eq(42, decoded.num)
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
