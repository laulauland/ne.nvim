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
    local diff_entry = {
      file_path = path,
      original = original,
      updated = current,
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

function M.clear()
  M.original_states = {}
  M.recent_diffs = {}
end

return M
