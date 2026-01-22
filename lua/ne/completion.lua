local util = require("ne.util")
local config = require("ne.config")
local backend = require("ne.backend")
local diff_mod = require("ne.diff")

local M = {}

M.ns_id = vim.api.nvim_create_namespace("ne")
M.inlay = nil
M.pending_request = false

function M.dispose()
  if M.inlay and M.inlay.bufnr and vim.api.nvim_buf_is_valid(M.inlay.bufnr) then
    vim.api.nvim_buf_clear_namespace(M.inlay.bufnr, M.ns_id, 0, -1)
  end
  M.inlay = nil
end

function M.render(bufnr, completion_text)
  M.dispose()

  if not completion_text or completion_text == "" then
    return
  end

  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "i" and mode ~= "ic" then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local line_after_cursor = current_line:sub(col + 1)

  local hl_group = config.get("suggestion_hl_group")
  local processed = util.first_line_split(completion_text, hl_group)
  local first_line = processed.first_line
  local other_lines = processed.other_lines

  local opts = {
    id = 1,
    hl_mode = "combine",
    priority = 1000,
  }

  local is_floating = #line_after_cursor > 0 and not util.contains(first_line, line_after_cursor)

  if is_floating then
    opts.virt_text = { { first_line, hl_group } }
    opts.virt_text_pos = "eol"
    completion_text = first_line
  else
    if first_line ~= "" then
      opts.virt_text = { { first_line, hl_group } }
    end
    if #other_lines > 0 then
      opts.virt_lines = other_lines
    end
    opts.virt_text_win_col = vim.fn.virtcol(".") - 1
  end

  vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, row, col, opts)

  M.inlay = {
    bufnr = bufnr,
    completion_text = completion_text,
    row = row,
    col = col,
    is_floating = is_floating,
  }
end

function M.accept()
  if not M.inlay then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", true)
    return
  end

  local completion_text = M.inlay.completion_text
  local bufnr = M.inlay.bufnr
  local row = M.inlay.row
  local col = M.inlay.col

  M.dispose()

  if not completion_text or completion_text == "" then
    return
  end

  local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local before_cursor = current_line:sub(1, col)
  local after_cursor = current_line:sub(col + 1)

  local lines = util.split_lines(completion_text)
  lines[1] = before_cursor .. lines[1]
  lines[#lines] = lines[#lines] .. after_cursor

  vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, lines)

  local new_row = row + #lines - 1
  local new_col = #lines[#lines] - #after_cursor
  vim.api.nvim_win_set_cursor(0, { new_row + 1, new_col })

  diff_mod.record_diff(bufnr)
end

function M.accept_word()
  if not M.inlay then
    return
  end

  local completion_text = M.inlay.completion_text
  local word = util.to_next_word(completion_text)

  local bufnr = M.inlay.bufnr
  local row = M.inlay.row
  local col = M.inlay.col

  M.dispose()

  if not word or word == "" then
    return
  end

  local current_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local before_cursor = current_line:sub(1, col)
  local after_cursor = current_line:sub(col + 1)

  local new_line = before_cursor .. word .. after_cursor
  vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
  vim.api.nvim_win_set_cursor(0, { row + 1, col + #word })
end

function M.trigger()
  local bufnr = vim.api.nvim_get_current_buf()

  if M.pending_request then
    return
  end

  M.pending_request = true

  backend.get_completion(bufnr, function(completion, err)
    M.pending_request = false

    if err then
      return
    end

    if completion then
      M.render(bufnr, completion)
    end
  end)
end

function M.has_suggestion()
  return M.inlay ~= nil and M.inlay.completion_text and M.inlay.completion_text ~= ""
end

M.trigger_debounced = util.debounce(M.trigger, config.defaults.debounce_ms)

function M.on_text_changed()
  M.dispose()
  if config.get("auto_trigger") then
    M.trigger_debounced()
  end
end

function M.on_insert_leave()
  M.dispose()
end

function M.on_cursor_moved()
  if M.inlay then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]
    if row ~= M.inlay.row or col ~= M.inlay.col then
      M.dispose()
    end
  end
end

return M
