local util = require("ne.util")
local config = require("ne.config")
local backend = require("ne.backend")
local diff_mod = require("ne.diff")

local M = {}

M.ns_id = vim.api.nvim_create_namespace("ne")
M.inlay = nil
M.pending_request = false
M.current_job = nil

-- Latency tracking for smart debouncing
M.latency_samples = {}
M.max_latency_samples = 10
M.current_debounce_ms = nil
M.debounce_timer = nil

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

--- Cancel any pending request
function M.cancel_pending()
  if M.current_job then
    pcall(function()
      M.current_job:kill()
    end)
    M.current_job = nil
  end
  M.pending_request = false
end

--- Record response latency and adjust debounce time
--- @param latency_ms number Response latency in milliseconds
local function record_latency(latency_ms)
  table.insert(M.latency_samples, latency_ms)
  while #M.latency_samples > M.max_latency_samples do
    table.remove(M.latency_samples, 1)
  end

  -- Calculate average latency
  local sum = 0
  for _, lat in ipairs(M.latency_samples) do
    sum = sum + lat
  end
  local avg_latency = sum / #M.latency_samples

  -- Adjust debounce based on latency
  local min_debounce = config.get("debounce_ms_min") or 300
  local max_debounce = config.get("debounce_ms_max") or 1000

  if avg_latency > 3000 then
    -- If responses consistently take 3+ seconds, increase debounce
    M.current_debounce_ms = math.min(max_debounce, min_debounce + (avg_latency - 3000) / 10)
  else
    -- Fast responses, use minimum debounce
    M.current_debounce_ms = min_debounce
  end
end

--- Get current debounce time in milliseconds
--- @return number Debounce time in ms
function M.get_debounce_ms()
  return M.current_debounce_ms or config.get("debounce_ms") or config.defaults.debounce_ms
end

function M.trigger()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Cancel any pending request before starting a new one
  if M.pending_request then
    M.cancel_pending()
  end

  M.pending_request = true
  local start_time = vim.uv.hrtime()

  M.current_job = backend.get_completion(bufnr, function(completion, err)
    local end_time = vim.uv.hrtime()
    local latency_ms = (end_time - start_time) / 1000000

    M.pending_request = false
    M.current_job = nil

    if err then
      -- Don't record latency for cancelled/failed requests
      if err ~= "request timed out" and not err:find("kill") then
        return
      end
      -- Record slow latency for timeouts to increase debounce
      if err == "request timed out" then
        record_latency(10000)
      end
      return
    end

    -- Record successful response latency
    record_latency(latency_ms)

    if completion then
      M.render(bufnr, completion)
    end
  end)
end

function M.has_suggestion()
  return M.inlay ~= nil and M.inlay.completion_text and M.inlay.completion_text ~= ""
end

--- Debounced trigger with dynamic debounce time
function M.trigger_debounced()
  if M.debounce_timer then
    M.debounce_timer:stop()
  else
    M.debounce_timer = vim.uv.new_timer()
  end

  local debounce_ms = M.get_debounce_ms()
  M.debounce_timer:start(debounce_ms, 0, function()
    M.debounce_timer:stop()
    vim.schedule(function()
      M.trigger()
    end)
  end)
end

function M.on_text_changed()
  M.dispose()
  -- Cancel pending request when text changes
  M.cancel_pending()
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
