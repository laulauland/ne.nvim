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

-- extract_edit_context tests

test("extract_edit_context returns unchanged when under budget", function()
  local original = "line1\nline2\nline3"
  local current = "line1\nmodified\nline3"
  local orig_out, curr_out = util.extract_edit_context(original, current, 1000, 10)
  eq(original, orig_out)
  eq(current, curr_out)
end)

test("extract_edit_context finds diff in middle", function()
  -- Create a file with 20 lines, change in middle
  local lines = {}
  for i = 1, 20 do
    table.insert(lines, "line" .. i)
  end
  local original = util.join_lines(lines)

  lines[10] = "CHANGED"
  local current = util.join_lines(lines)

  -- Use small max_size to force truncation
  local orig_out, curr_out = util.extract_edit_context(original, current, 100, 3)

  -- Should have line range header
  assert(orig_out:match("^%[lines %d+%-%d+ of 20%]"), "original should have line range header")
  assert(curr_out:match("^%[lines %d+%-%d+ of 20%]"), "current should have line range header")

  -- Should contain the changed region
  assert(curr_out:find("CHANGED"), "current should contain the change")
end)

test("extract_edit_context handles change at start", function()
  local lines = {}
  for i = 1, 20 do
    table.insert(lines, string.format("this is a longer line number %02d", i))
  end
  local original = util.join_lines(lines)

  lines[1] = "FIRST_LINE_CHANGED_HERE"
  local current = util.join_lines(lines)

  -- Use small max_size to force truncation
  local orig_out, curr_out = util.extract_edit_context(original, current, 200, 3)

  -- Should start from line 1 and contain the change
  assert(orig_out:match("%[lines 1%-"), "original should start from line 1")
  assert(curr_out:match("%[lines 1%-"), "current should start from line 1")
  assert(curr_out:find("FIRST_LINE_CHANGED"), "current should contain the change")
end)

test("extract_edit_context handles change at end", function()
  local lines = {}
  for i = 1, 20 do
    table.insert(lines, string.format("this is a longer line number %02d", i))
  end
  local original = util.join_lines(lines)

  lines[20] = "LAST_LINE_CHANGED_HERE"
  local current = util.join_lines(lines)

  -- Use small max_size to force truncation
  local orig_out, curr_out = util.extract_edit_context(original, current, 200, 3)

  -- Should include line 20 and the change
  assert(orig_out:match("%-20 of 20%]"), "original should end at line 20")
  assert(curr_out:match("%-20 of 20%]"), "current should end at line 20")
  assert(curr_out:find("LAST_LINE_CHANGED"), "current should contain the change")
end)

test("extract_edit_context handles multiple change regions", function()
  local lines = {}
  for i = 1, 30 do
    table.insert(lines, "line" .. i)
  end
  local original = util.join_lines(lines)

  lines[5] = "CHANGE_A"
  lines[25] = "CHANGE_B"
  local current = util.join_lines(lines)

  -- With enough budget, should capture both changes
  local _, curr_out = util.extract_edit_context(original, current, 500, 5)

  assert(curr_out:find("CHANGE_A"), "should contain first change")
  assert(curr_out:find("CHANGE_B"), "should contain second change")
end)

test("extract_edit_context respects max_size", function()
  local lines = {}
  for i = 1, 100 do
    table.insert(lines, string.format("this is line number %03d with some content", i))
  end
  local original = util.join_lines(lines)

  lines[50] = "MODIFIED LINE IN THE MIDDLE"
  local current = util.join_lines(lines)

  local max_size = 500
  local orig_out, curr_out = util.extract_edit_context(original, current, max_size, 20)

  assert(#orig_out <= max_size, "original output should respect max_size")
  assert(#curr_out <= max_size, "current output should respect max_size")
end)

test("extract_edit_context handles identical files", function()
  local original = "line1\nline2\nline3"
  local current = "line1\nline2\nline3"
  local orig_out, curr_out = util.extract_edit_context(original, current, 50, 10)

  -- Should return something reasonable (truncated from start if needed)
  assert(orig_out ~= nil and #orig_out > 0, "should return non-empty original")
  assert(curr_out ~= nil and #curr_out > 0, "should return non-empty current")
end)

test("extract_edit_context handles empty files", function()
  local original = ""
  local current = "new content"
  local orig_out, curr_out = util.extract_edit_context(original, current, 100, 10)

  assert(orig_out ~= nil, "should handle empty original")
  assert(curr_out:find("new content"), "should contain new content")
end)

test("extract_edit_context handles added lines", function()
  local original = "line1\nline2"
  local current = "line1\nline2\nline3\nline4"

  local orig_out, curr_out = util.extract_edit_context(original, current, 100, 10)

  assert(curr_out:find("line3"), "should contain added line3")
  assert(curr_out:find("line4"), "should contain added line4")
end)

test("extract_edit_context handles deleted lines", function()
  local original = "line1\nline2\nline3\nline4"
  local current = "line1\nline2"

  local orig_out, curr_out = util.extract_edit_context(original, current, 100, 10)

  assert(orig_out:find("line3"), "original should contain deleted line3")
  assert(orig_out:find("line4"), "original should contain deleted line4")
end)

test("extract_edit_context line range header format", function()
  local lines = {}
  for i = 1, 50 do
    table.insert(lines, "line" .. i)
  end
  local original = util.join_lines(lines)

  lines[25] = "CHANGED"
  local current = util.join_lines(lines)

  local _, curr_out = util.extract_edit_context(original, current, 200, 5)

  -- Verify header format: [lines X-Y of Z]
  local start_line, end_line, total = curr_out:match("^%[lines (%d+)%-(%d+) of (%d+)%]")
  assert(start_line, "should have properly formatted header")
  assert(tonumber(total) == 50, "total should be 50")
  assert(tonumber(start_line) <= 25, "start should be at or before change")
  assert(tonumber(end_line) >= 25, "end should be at or after change")
end)

print("\n")
if vim.g.test_failures and vim.g.test_failures > 0 then
  print(string.format("FAILED: %d test(s) failed", vim.g.test_failures))
  vim.cmd("cq 1")
else
  print("All tests passed!")
end
