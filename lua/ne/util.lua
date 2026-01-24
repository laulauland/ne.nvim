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

--- Extract a fixed window of lines around cursor position
--- @param content string File content
--- @param cursor_line number Cursor line (1-indexed)
--- @param window_size number|nil Total window size (default: 21)
--- @return string Extracted window content (no headers)
--- @return number Start line of the window (1-indexed)
--- @return number End line of the window (1-indexed)
function M.extract_cursor_window(content, cursor_line, window_size)
  window_size = window_size or 21
  local half = math.floor(window_size / 2) -- 10 for default 21

  local lines = M.split_lines(content)
  local total = #lines

  -- Handle empty content
  if total == 0 then
    return "", 1, 1
  end

  -- Clamp cursor_line to valid range
  cursor_line = math.max(1, math.min(cursor_line, total))

  -- Calculate window bounds
  local start_line = math.max(1, cursor_line - half)
  local end_line = math.min(total, cursor_line + half)

  -- Adjust if we're near boundaries to maintain window_size when possible
  if end_line - start_line + 1 < window_size then
    if start_line == 1 then
      end_line = math.min(total, start_line + window_size - 1)
    elseif end_line == total then
      start_line = math.max(1, end_line - window_size + 1)
    end
  end

  -- Extract the window
  local result_lines = {}
  for i = start_line, end_line do
    table.insert(result_lines, lines[i])
  end

  return M.join_lines(result_lines), start_line, end_line
end

--- Extract the completion delta by diffing current window vs model response
--- Returns only the new/changed text to show as ghost text
--- @param current_window string Current 21-line window content
--- @param model_response string Model's rewritten window
--- @param cursor_line_in_window number Cursor position within the window (1-indexed)
--- @return string|nil Completion text to show, or nil if no completion
function M.extract_completion_delta(current_window, model_response, cursor_line_in_window)
  local current_lines = M.split_lines(current_window)
  local response_lines = M.split_lines(model_response)

  -- Find the first difference
  local diff_line = nil
  local max_common = math.min(#current_lines, #response_lines)

  for i = 1, max_common do
    if current_lines[i] ~= response_lines[i] then
      diff_line = i
      break
    end
  end

  -- If no diff found in common lines, check for added lines
  if not diff_line then
    if #response_lines > #current_lines then
      -- Model added lines at the end
      diff_line = #current_lines + 1
    else
      -- No changes or model removed lines (no completion to show)
      return nil
    end
  end

  -- Extract the completion starting from the diff
  if diff_line <= #response_lines then
    local completion_lines = {}

    -- For the first diff line, if it's a modification, extract just the added part
    if diff_line <= #current_lines then
      local curr_line = current_lines[diff_line]
      local resp_line = response_lines[diff_line]

      -- Find common prefix
      local prefix_len = 0
      local min_len = math.min(#curr_line, #resp_line)
      for i = 1, min_len do
        if curr_line:sub(i, i) == resp_line:sub(i, i) then
          prefix_len = i
        else
          break
        end
      end

      -- Get the new content after the common prefix
      local new_part = resp_line:sub(prefix_len + 1)
      if new_part ~= "" then
        table.insert(completion_lines, new_part)
      end

      -- Add subsequent lines only if they differ from current
      -- (for multi-line completions where model adds new lines)
      for i = diff_line + 1, #response_lines do
        local curr = current_lines[i]
        local resp = response_lines[i]
        if curr ~= resp then
          -- Line differs - add the response line
          if curr == nil then
            -- New line added by model
            table.insert(completion_lines, resp)
          else
            -- Line modified - for now just stop here
            -- (inline completion shouldn't span multiple modified lines)
            break
          end
        else
          -- Lines match again - stop adding
          break
        end
      end
    else
      -- Pure addition - all lines from diff_line onwards are new
      for i = diff_line, #response_lines do
        table.insert(completion_lines, response_lines[i])
      end
    end

    if #completion_lines > 0 then
      return M.join_lines(completion_lines)
    end
  end

  return nil
end

return M
