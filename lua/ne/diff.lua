local util = require("ne.util")
local config = require("ne.config")

local M = {}

M.original_states = {}
M.recent_diffs = {}

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

function M.record_diff(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = util.get_buffer_path(bufnr)
  if path == "" then
    return
  end

  local original = M.original_states[path]
  local current = util.get_buffer_content(bufnr)

  if original and original ~= current then
    local max_diff_size = config.get("max_diff_size") or 1024

    -- Use smart truncation to focus on the changed region
    local truncated_original, truncated_updated = util.extract_edit_context(
      original,
      current,
      max_diff_size,
      50 -- context lines around diff
    )

    local diff_entry = {
      file_path = path,
      original = truncated_original,
      updated = truncated_updated,
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
