local util = require("ne.util")
local config = require("ne.config")
local diff = require("ne.diff")

local M = {}

local FILE_SEP = "<|file_sep|>"
local STOP_TOKENS = { "<|file_sep|>", "</s>", "<|endoftext|>" }
local WINDOW_SIZE = 21 -- Fixed 21-line window (10 above + cursor + 10 below)

--- Log debug metadata to JSONL file
--- @param meta table Metadata table with request info
local function debug_log(meta)
  local debug_opts = config.get("debug")
  if not debug_opts or not debug_opts.enabled then
    return
  end

  local dir = debug_opts.dir
  vim.fn.mkdir(dir, "p")

  local jsonl_file = dir .. "/debug.jsonl"
  local f = io.open(jsonl_file, "a")
  if f then
    local line = util.json_encode(meta)
    f:write(line .. "\n")
    f:close()
  end
end

--- Build prompt for completion request using 21-line cursor windows
--- @param file_path string Path to the file being edited
--- @param original_content string Original file content
--- @param current_content string Current file content
--- @param cursor_line number Current cursor line (1-indexed)
--- @param context_files table<string, string> Additional context files
--- @param recent_diffs table Recent diffs for context
--- @return string prompt The built prompt
--- @return table meta Metadata about the prompt contents
function M.build_prompt(file_path, original_content, current_content, cursor_line, context_files, recent_diffs)
  context_files = context_files or {}
  recent_diffs = recent_diffs or diff.get_recent_diffs()

  local max_prompt_size = config.get("max_prompt_size") or 8192

  -- Extract 21-line windows centered on cursor
  local original_window = util.extract_cursor_window(original_content, cursor_line, WINDOW_SIZE)
  local current_window = util.extract_cursor_window(current_content, cursor_line, WINDOW_SIZE)

  local parts = {}

  -- Calculate base size (file content that we always need)
  local header_overhead = #FILE_SEP * 3 + #"original/" + #"current/" + #"updated/" + #file_path * 3 + 10
  local base_size = header_overhead + #original_window + #current_window

  local remaining_budget = max_prompt_size - base_size

  -- Add context files (newest first, drop if over budget)
  local context_parts = {}
  local ctx_files_count = 0
  for path, content in pairs(context_files) do
    local entry = FILE_SEP .. path .. "\n" .. content
    local entry_size = #entry + 1
    if remaining_budget >= entry_size then
      table.insert(context_parts, entry)
      remaining_budget = remaining_budget - entry_size
      ctx_files_count = ctx_files_count + 1
    end
  end

  -- Add recent diffs (newest first, drop oldest if over budget)
  -- Format: <|file_sep|>{file}.diff\noriginal:\n{content}\nupdated:\n{content}
  local diff_parts = {}
  local diffs_count = 0
  for _, d in ipairs(recent_diffs) do
    local orig = d.original or ""
    local upd = d.updated or ""
    if orig ~= "" or upd ~= "" then
      local entry = FILE_SEP .. d.file_path .. ".diff\n"
        .. "original:\n" .. orig .. "\n"
        .. "updated:\n" .. upd
      local entry_size = #entry + 1
      if remaining_budget >= entry_size then
        table.insert(diff_parts, 1, entry) -- prepend to maintain order
        remaining_budget = remaining_budget - entry_size
        diffs_count = diffs_count + 1
      end
    end
  end

  -- Build final prompt in order: context files, diffs, current file
  for _, part in ipairs(context_parts) do
    table.insert(parts, part)
  end
  for _, part in ipairs(diff_parts) do
    table.insert(parts, part)
  end

  -- Main file content - raw 21-line windows, no headers
  table.insert(parts, FILE_SEP .. "original/" .. file_path)
  table.insert(parts, original_window)
  table.insert(parts, FILE_SEP .. "current/" .. file_path)
  table.insert(parts, current_window)
  table.insert(parts, FILE_SEP .. "updated/" .. file_path)

  local prompt = table.concat(parts, "\n")

  -- Build metadata
  local meta = {
    file = file_path,
    cursor_line = cursor_line,
    orig_window_size = #original_window,
    curr_window_size = #current_window,
    diffs = diffs_count,
    ctx_files = ctx_files_count,
    prompt_size = #prompt,
  }

  return prompt, meta
end

--- Request completion from the backend
--- @param prompt string The prompt to send
--- @param callback function Callback function(content, err)
--- @return table|nil Job handle with :kill() method for cancellation
function M.request_completion(prompt, callback)
  local opts = config.get()
  local url = opts.server_url .. "/completion"
  local timeout = opts.request_timeout or 10

  local payload = {
    prompt = prompt,
    n_predict = opts.max_tokens,
    temperature = opts.temperature,
    stop = STOP_TOKENS,
    stream = false,
  }

  local json_payload = util.json_encode(payload)

  -- Use stdin (-d @-) to pass payload, avoids escaping issues with large/complex prompts
  local cmd = {
    "curl",
    "-s",
    "--max-time", tostring(timeout),
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", "@-",
    url,
  }

  local job = vim.system(cmd, { text = true, stdin = json_payload }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err_msg = result.stderr or "unknown error"
        if result.code == 28 or err_msg:find("timed out") then
          callback(nil, "request timed out")
        else
          callback(nil, "curl failed (code " .. result.code .. "): " .. err_msg)
        end
        return
      end

      local stdout = result.stdout or ""
      if stdout == "" then
        callback(nil, "empty response from server")
        return
      end

      local response = util.json_decode(stdout)
      if not response then
        local preview = stdout:sub(1, 200)
        callback(nil, "failed to parse response: " .. preview)
        return
      end

      local content = response.content
      if not content then
        callback(nil, "no content in response")
        return
      end

      callback(content, nil)
    end)
  end)

  return job
end

--- Get completion for the current buffer
--- @param bufnr number|nil Buffer number
--- @param callback function Callback function(content, err)
--- @return table|nil Job handle with :kill() method for cancellation
function M.get_completion(bufnr, callback)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local file_path = util.get_buffer_path(bufnr)
  if file_path == "" then
    callback(nil, "buffer has no file path")
    return nil
  end

  -- Get cursor position (1-indexed row)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  local original_content = diff.get_original(bufnr)
  local current_content = util.get_buffer_content(bufnr)

  if original_content == current_content then
    callback(nil, "no changes detected")
    return nil
  end

  -- Extract current window for later comparison with response
  local current_window, window_start = util.extract_cursor_window(current_content, cursor_line, WINDOW_SIZE)
  local cursor_line_in_window = cursor_line - window_start + 1

  local prompt, meta = M.build_prompt(
    file_path,
    original_content,
    current_content,
    cursor_line,
    {},
    diff.get_recent_diffs()
  )

  local start_time = vim.uv.hrtime()

  local job = M.request_completion(prompt, function(response, err)
    local end_time = vim.uv.hrtime()
    local latency_ms = math.floor((end_time - start_time) / 1000000)

    meta.ts = os.date("!%Y-%m-%dT%H:%M:%S")
    meta.resp_size = response and #response or 0
    meta.latency_ms = latency_ms
    meta.prompt = prompt
    meta.response = response
    meta.err = err

    debug_log(meta)

    if err then
      callback(nil, err)
      return
    end

    -- Extract the completion delta by diffing response against current window
    -- Trim leading/trailing whitespace from response (model often adds leading newline)
    local trimmed_response = response:match("^%s*(.-)%s*$") or response
    local completion = util.extract_completion_delta(current_window, trimmed_response, cursor_line_in_window)
    callback(completion, nil)
  end)

  return job
end

function M.health_check(callback)
  local opts = config.get()
  local url = opts.server_url .. "/health"

  vim.system({ "curl", "-s", url }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(false, "server not reachable")
        return
      end
      callback(true, nil)
    end)
  end)
end

return M
