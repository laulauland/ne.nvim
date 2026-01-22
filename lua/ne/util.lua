local M = {}

function M.split_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

function M.join_lines(lines)
  return table.concat(lines, "\n")
end

function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

function M.trim_start(s)
  return s:match("^%s*(.*)$")
end

function M.first_line_split(text, hl_group)
  local lines = M.split_lines(text)
  local first_line = lines[1] or ""
  local other_lines = {}
  for i = 2, #lines do
    table.insert(other_lines, { { lines[i], hl_group } })
  end
  return {
    first_line = first_line,
    other_lines = other_lines,
  }
end

function M.get_last_line(text)
  local lines = M.split_lines(text)
  return lines[#lines] or ""
end

function M.line_count(text)
  local count = 0
  for _ in text:gmatch("\n") do
    count = count + 1
  end
  return count
end

function M.to_next_word(text)
  local word = text:match("^(%S+)")
  if word then
    return word
  end
  local space_then_word = text:match("^(%s+%S+)")
  if space_then_word then
    return space_then_word
  end
  return text
end

function M.contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

function M.get_buffer_content(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.get_buffer_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.fn.getcwd()
  if path:sub(1, #cwd) == cwd then
    path = path:sub(#cwd + 2)
  end
  return path
end

function M.debounce(fn, ms)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

function M.json_encode(data)
  return vim.fn.json_encode(data)
end

function M.json_decode(str)
  local ok, result = pcall(vim.fn.json_decode, str)
  if ok then
    return result
  end
  return nil
end

return M
