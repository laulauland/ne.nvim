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

--- Generate a unified diff between two strings
--- @param original string Original content
--- @param updated string Updated content
--- @param file_path string|nil Optional file path for header
--- @param max_size number|nil Maximum size in bytes (default: 1024)
--- @return string Unified diff patch, truncated if necessary
function M.unified_diff(original, updated, file_path, max_size)
  max_size = max_size or 1024
  file_path = file_path or "file"

  local orig_lines = M.split_lines(original)
  local upd_lines = M.split_lines(updated)

  local hunks = {}
  local context_lines = 3

  -- Simple diff algorithm: find changed regions
  local orig_idx = 1
  local upd_idx = 1
  local orig_len = #orig_lines
  local upd_len = #upd_lines

  while orig_idx <= orig_len or upd_idx <= upd_len do
    -- Skip matching lines
    while orig_idx <= orig_len and upd_idx <= upd_len and orig_lines[orig_idx] == upd_lines[upd_idx] do
      orig_idx = orig_idx + 1
      upd_idx = upd_idx + 1
    end

    if orig_idx > orig_len and upd_idx > upd_len then
      break
    end

    -- Found a difference, collect the hunk
    local hunk_orig_start = math.max(1, orig_idx - context_lines)
    local hunk_upd_start = math.max(1, upd_idx - context_lines)

    -- Find end of changed region
    local orig_change_end = orig_idx
    local upd_change_end = upd_idx

    -- Advance through different lines
    while orig_change_end <= orig_len or upd_change_end <= upd_len do
      if orig_change_end <= orig_len and upd_change_end <= upd_len and orig_lines[orig_change_end] == upd_lines[upd_change_end] then
        -- Check if we have enough context to end hunk
        local match_count = 0
        local i = 0
        while orig_change_end + i <= orig_len and upd_change_end + i <= upd_len and orig_lines[orig_change_end + i] == upd_lines[upd_change_end + i] do
          match_count = match_count + 1
          i = i + 1
          if match_count > context_lines * 2 then
            break
          end
        end
        if match_count > context_lines * 2 then
          break
        end
      end
      if orig_change_end <= orig_len then
        orig_change_end = orig_change_end + 1
      end
      if upd_change_end <= upd_len then
        upd_change_end = upd_change_end + 1
      end
    end

    local hunk_orig_end = math.min(orig_len, orig_change_end + context_lines - 1)
    local hunk_upd_end = math.min(upd_len, upd_change_end + context_lines - 1)

    -- Build hunk
    local hunk = {}
    local hunk_header = string.format("@@ -%d,%d +%d,%d @@",
      hunk_orig_start, hunk_orig_end - hunk_orig_start + 1,
      hunk_upd_start, hunk_upd_end - hunk_upd_start + 1)
    table.insert(hunk, hunk_header)

    -- Context before
    for i = hunk_orig_start, orig_idx - 1 do
      if i <= orig_len then
        table.insert(hunk, " " .. orig_lines[i])
      end
    end

    -- Removed lines
    for i = orig_idx, orig_change_end - 1 do
      if i <= orig_len then
        table.insert(hunk, "-" .. orig_lines[i])
      end
    end

    -- Added lines
    for i = upd_idx, upd_change_end - 1 do
      if i <= upd_len then
        table.insert(hunk, "+" .. upd_lines[i])
      end
    end

    -- Context after
    for i = orig_change_end, hunk_orig_end do
      if i <= orig_len then
        table.insert(hunk, " " .. orig_lines[i])
      end
    end

    table.insert(hunks, table.concat(hunk, "\n"))

    orig_idx = hunk_orig_end + 1
    upd_idx = hunk_upd_end + 1
  end

  if #hunks == 0 then
    return ""
  end

  local header = string.format("--- a/%s\n+++ b/%s", file_path, file_path)
  local diff = header .. "\n" .. table.concat(hunks, "\n")

  -- Truncate if too large
  if #diff > max_size then
    diff = diff:sub(1, max_size - 20) .. "\n... truncated ..."
  end

  return diff
end

return M
