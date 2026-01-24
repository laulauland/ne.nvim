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

-- extract_cursor_window tests

test("extract_cursor_window returns full content when small", function()
  local content = "line1\nline2\nline3"
  local window, start_line, end_line = util.extract_cursor_window(content, 2, 21)
  eq(content, window)
  eq(1, start_line)
  eq(3, end_line)
end)

test("extract_cursor_window extracts window centered on cursor", function()
  -- Create 30 lines
  local lines = {}
  for i = 1, 30 do
    table.insert(lines, "line" .. i)
  end
  local content = util.join_lines(lines)

  -- Cursor at line 15, should get lines 5-25 (21 lines)
  local window, start_line, end_line = util.extract_cursor_window(content, 15, 21)

  eq(5, start_line)
  eq(25, end_line)
  assert(window:find("line15"), "window should contain cursor line")
  assert(window:find("line5"), "window should contain start")
  assert(window:find("line25"), "window should contain end")
  assert(not window:find("line4\n"), "window should not contain line before start")
  assert(not window:find("line26"), "window should not contain line after end")
end)

test("extract_cursor_window handles cursor near start", function()
  local lines = {}
  for i = 1, 30 do
    table.insert(lines, "line" .. i)
  end
  local content = util.join_lines(lines)

  -- Cursor at line 3
  local window, start_line, end_line = util.extract_cursor_window(content, 3, 21)

  eq(1, start_line)
  eq(21, end_line)
  assert(window:find("line1"), "window should contain line 1")
  assert(window:find("line21"), "window should contain line 21")
end)

test("extract_cursor_window handles cursor near end", function()
  local lines = {}
  for i = 1, 30 do
    table.insert(lines, "line" .. i)
  end
  local content = util.join_lines(lines)

  -- Cursor at line 28
  local window, start_line, end_line = util.extract_cursor_window(content, 28, 21)

  eq(10, start_line)
  eq(30, end_line)
  assert(window:find("line30"), "window should contain last line")
  assert(window:find("line10"), "window should contain line 10")
end)

test("extract_cursor_window handles empty content", function()
  local window, start_line, end_line = util.extract_cursor_window("", 1, 21)
  eq("", window)
  eq(1, start_line)
  eq(1, end_line)
end)

test("extract_cursor_window clamps cursor to valid range", function()
  local content = "line1\nline2\nline3"
  -- Cursor beyond file end
  local window = util.extract_cursor_window(content, 100, 21)
  eq(content, window)

  -- Cursor at 0
  window = util.extract_cursor_window(content, 0, 21)
  eq(content, window)
end)

test("extract_cursor_window respects custom window size", function()
  local lines = {}
  for i = 1, 20 do
    table.insert(lines, "line" .. i)
  end
  local content = util.join_lines(lines)

  -- Window size of 5 (2 above + cursor + 2 below)
  local window, start_line, end_line = util.extract_cursor_window(content, 10, 5)

  eq(8, start_line)
  eq(12, end_line)
  assert(window:find("line10"), "window should contain cursor line")
end)

-- extract_completion_delta tests

test("extract_completion_delta finds inline insertion", function()
  local current = "def foo():\n    pass"
  local response = "def foo():\n    return 42"

  local delta = util.extract_completion_delta(current, response, 2)
  eq("return 42", delta)
end)

test("extract_completion_delta finds added lines", function()
  local current = "line1\nline2"
  local response = "line1\nline2\nline3\nline4"

  local delta = util.extract_completion_delta(current, response, 2)
  eq("line3\nline4", delta)
end)

test("extract_completion_delta returns nil when no changes", function()
  local current = "line1\nline2"
  local response = "line1\nline2"

  local delta = util.extract_completion_delta(current, response, 1)
  eq(nil, delta)
end)

test("extract_completion_delta extracts partial line change", function()
  local current = "function test()\n    print("
  local response = "function test()\n    print('hello world')"

  local delta = util.extract_completion_delta(current, response, 2)
  eq("'hello world')", delta)
end)

test("extract_completion_delta handles first line change", function()
  local current = "def "
  local response = "def foo():"

  local delta = util.extract_completion_delta(current, response, 1)
  eq("foo():", delta)
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
