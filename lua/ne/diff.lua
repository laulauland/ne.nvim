local util = require("ne.util")
local config = require("ne.config")

local M = {}

M.original_states = {}
M.recent_diffs = {}

local WINDOW_SIZE = 21 -- Fixed 21-line window for diffs

function M.capture_original(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = util.get_buffer_path(bufnr)
  if path == "" then
    return
  end
  M.original_states[path] = util.get_buffer_content(bufnr)
end

function M.get_original(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = util.get_buffer_path(bufnr)
  return M.original_states[path] or util.get_buffer_content(bufnr)
end

--- Find the line where a change occurred between two contents
--- @param original string Original content
--- @param current string Current content
--- @return number Line number where change occurred (1-indexed)
local function find_change_line(original, current)
  local orig_lines = util.split_lines(original)
  local curr_lines = util.split_lines(current)

  -- Find first differing line
  local min_len = math.min(#orig_lines, #curr_lines)
  for i = 1, min_len do
    if orig_lines[i] ~= curr_lines[i] then
      return i
    end
  end

  -- If common lines are identical, change is at the length difference
  if #orig_lines ~= #curr_lines then
    return min_len + 1
  end

  -- Files are identical
  return 1
end

function M.record_diff(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = util.get_buffer_path(bufnr)
  if path == "" then
    return
  end

  local original = M.original_states[path]
  local current = util.get_buffer_content(bufnr)

  if original and original ~= current then
    -- Find where the change happened
    local change_line = find_change_line(original, current)

    -- Extract 21-line windows centered on the change
    local original_window = util.extract_cursor_window(original, change_line, WINDOW_SIZE)
    local updated_window = util.extract_cursor_window(current, change_line, WINDOW_SIZE)

    local diff_entry = {
      file_path = path,
      original = original_window,
      updated = updated_window,
    }

    table.insert(M.recent_diffs, 1, diff_entry)

    local max_diffs = config.get("context").max_diffs
    while #M.recent_diffs > max_diffs do
      table.remove(M.recent_diffs)
    end

    M.original_states[path] = current
  end
end

function M.get_recent_diffs()
  return M.recent_diffs
end

--- Get total size of all recent diffs in bytes
--- @return number Total size in bytes
function M.get_diffs_size()
  local size = 0
  for _, d in ipairs(M.recent_diffs) do
    size = size + #d.file_path + #(d.original or "") + #(d.updated or "")
  end
  return size
end

function M.clear()
  M.original_states = {}
  M.recent_diffs = {}
end

return M
