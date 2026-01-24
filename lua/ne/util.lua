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

--- Extract smart context around edit regions
--- @param original string Original file content
--- @param current string Current file content
--- @param max_size number Maximum size in bytes for each output
--- @param context_lines number|nil Lines of context around diff (default: 100)
--- @return string, string Truncated original and current with line range headers
function M.extract_edit_context(original, current, max_size, context_lines)
  context_lines = context_lines or 100

  -- If both fit within budget, return as-is
  if #original <= max_size and #current <= max_size then
    return original, current
  end

  local orig_lines = M.split_lines(original)
  local curr_lines = M.split_lines(current)

  local orig_len = #orig_lines
  local curr_len = #curr_lines

  -- Find first differing line
  local first_diff = nil
  local min_len = math.min(orig_len, curr_len)
  for i = 1, min_len do
    if orig_lines[i] ~= curr_lines[i] then
      first_diff = i
      break
    end
  end

  -- If no diff found in common part, diff starts at length difference
  if not first_diff then
    if orig_len ~= curr_len then
      first_diff = min_len + 1
    else
      -- Files are identical, return truncated from start
      return M._truncate_with_header(orig_lines, 1, orig_len, max_size),
          M._truncate_with_header(curr_lines, 1, curr_len, max_size)
    end
  end

  -- Find last differing line (scan from end)
  local last_diff_orig = orig_len
  local last_diff_curr = curr_len
  local orig_end = orig_len
  local curr_end = curr_len

  while orig_end >= first_diff and curr_end >= first_diff do
    if orig_lines[orig_end] ~= curr_lines[curr_end] then
      break
    end
    orig_end = orig_end - 1
    curr_end = curr_end - 1
  end

  last_diff_orig = math.max(first_diff, orig_end)
  last_diff_curr = math.max(first_diff, curr_end)

  -- Calculate windows centered on diff regions
  local orig_start = math.max(1, first_diff - context_lines)
  local orig_window_end = math.min(orig_len, last_diff_orig + context_lines)

  local curr_start = math.max(1, first_diff - context_lines)
  local curr_window_end = math.min(curr_len, last_diff_curr + context_lines)

  -- Extract and fit within max_size
  local orig_result = M._extract_window_fit(orig_lines, orig_start, orig_window_end, first_diff, last_diff_orig, max_size)
  local curr_result = M._extract_window_fit(curr_lines, curr_start, curr_window_end, first_diff, last_diff_curr, max_size)

  return orig_result, curr_result
end

--- Truncate lines with a header showing line range
--- @param lines table Array of lines
--- @param start_line number Start line (1-indexed)
--- @param end_line number End line (1-indexed)
--- @param max_size number Maximum size in bytes
--- @return string Truncated content with header
function M._truncate_with_header(lines, start_line, end_line, max_size)
  local total_lines = #lines

  -- Header format: [lines X-Y of Z]\n
  local header = string.format("[lines %d-%d of %d]\n", start_line, end_line, total_lines)
  local header_size = #header

  -- Only add header if we're actually truncating
  local is_full_file = (start_line == 1 and end_line == total_lines)

  if is_full_file then
    local content = M.join_lines(lines)
    if #content <= max_size then
      return content
    end
    -- Need to truncate even the full file
    header = string.format("[lines 1-? of %d]\n", total_lines)
    header_size = #header
  end

  local available = max_size - header_size
  if available <= 0 then
    return header .. "..."
  end

  -- Build content from the window
  local result_lines = {}
  local current_size = 0
  local actual_end = start_line - 1

  for i = start_line, end_line do
    local line = lines[i]
    local line_size = #line + 1 -- +1 for newline
    if current_size + line_size > available then
      break
    end
    table.insert(result_lines, line)
    current_size = current_size + line_size
    actual_end = i
  end

  -- Update header with actual end line
  header = string.format("[lines %d-%d of %d]\n", start_line, actual_end, total_lines)

  return header .. M.join_lines(result_lines)
end

--- Extract a window of lines that fits within max_size, keeping diff region centered
--- @param lines table Array of lines
--- @param window_start number Initial window start
--- @param window_end number Initial window end
--- @param diff_start number First differing line
--- @param diff_end number Last differing line
--- @param max_size number Maximum size in bytes
--- @return string Extracted content with header
function M._extract_window_fit(lines, window_start, window_end, diff_start, diff_end, max_size)
  local total_lines = #lines

  -- If window is the entire file and fits, return without header
  if window_start == 1 and window_end == total_lines then
    local content = M.join_lines(lines)
    if #content <= max_size then
      return content
    end
  end

  -- Header overhead estimate
  local header_template = "[lines %d-%d of %d]\n"
  local header_overhead = #string.format(header_template, window_start, window_end, total_lines)

  local available = max_size - header_overhead
  if available <= 0 then
    return string.format("[lines %d-%d of %d]\n...", window_start, window_start, total_lines)
  end

  -- Calculate content size for current window
  local function calc_window_size(ws, we)
    local size = 0
    for i = ws, we do
      size = size + #lines[i] + 1 -- +1 for newline
    end
    return size - 1 -- last line has no trailing newline in join
  end

  -- Shrink window if needed, keeping diff region centered
  while window_start < window_end do
    local size = calc_window_size(window_start, window_end)
    if size <= available then
      break
    end

    -- Shrink from the side further from diff center
    local diff_center = (diff_start + diff_end) / 2
    local start_dist = diff_center - window_start
    local end_dist = window_end - diff_center

    -- Don't shrink into the diff region
    if window_start < diff_start and (start_dist >= end_dist or window_end <= diff_end) then
      window_start = window_start + 1
    elseif window_end > diff_end then
      window_end = window_end - 1
    else
      -- Both edges are at diff boundaries, shrink from end
      window_end = window_end - 1
    end
  end

  -- Build result
  local result_lines = {}
  for i = window_start, window_end do
    table.insert(result_lines, lines[i])
  end

  local header = string.format("[lines %d-%d of %d]\n", window_start, window_end, total_lines)
  return header .. M.join_lines(result_lines)
end

return M
