local util = require("ne.util")
local config = require("ne.config")
local diff = require("ne.diff")

local M = {}

local FILE_SEP = "<|file_sep|>"
local STOP_TOKENS = { "<|file_sep|>", "</s>", "<|endoftext|>" }

local function debug_log(prompt, response, err)
  local debug_opts = config.get("debug")
  if not debug_opts or not debug_opts.enabled then
    return
  end

  local dir = debug_opts.dir
  vim.fn.mkdir(dir, "p")

  local timestamp = os.date("%Y%m%d_%H%M%S")
  local id = string.format("%s_%d", timestamp, math.random(1000, 9999))

  local prompt_file = string.format("%s/%s_prompt.txt", dir, id)
  local response_file = string.format("%s/%s_response.txt", dir, id)

  local pf = io.open(prompt_file, "w")
  if pf then
    pf:write(prompt)
    pf:close()
  end

  local rf = io.open(response_file, "w")
  if rf then
    if err then
      rf:write("ERROR: " .. err)
    else
      rf:write(response or "")
    end
    rf:close()
  end
end

function M.build_prompt(file_path, original_content, current_content, context_files, recent_diffs)
  context_files = context_files or {}
  recent_diffs = recent_diffs or diff.get_recent_diffs()

  local max_prompt_size = config.get("max_prompt_size") or 8192

  -- Reserve space for context/diffs (at least 20% of budget)
  local max_file_content_size = math.floor(max_prompt_size * 0.8 / 2) -- Split between original and current
  local header_overhead = #FILE_SEP * 3 + #"original/" + #"current/" + #"updated/" + #file_path * 3 + 10

  -- Smart context extraction: focus on the region where changes are happening
  original_content, current_content = util.extract_edit_context(
    original_content,
    current_content,
    max_file_content_size,
    100 -- context lines around diff
  )

  local parts = {}

  -- Calculate base size (file content that we always need)
  local base_size = header_overhead + #original_content + #current_content

  local remaining_budget = max_prompt_size - base_size

  -- Add context files (newest first, drop if over budget)
  local context_parts = {}
  for path, content in pairs(context_files) do
    local entry = FILE_SEP .. path .. "\n" .. content
    local entry_size = #entry + 1
    if remaining_budget >= entry_size then
      table.insert(context_parts, entry)
      remaining_budget = remaining_budget - entry_size
    end
  end

  -- Add recent diffs (newest first, drop oldest if over budget)
  local diff_parts = {}
  for _, d in ipairs(recent_diffs) do
    local patch = d.patch or ""
    if patch ~= "" then
      local entry = FILE_SEP .. d.file_path .. ".diff\n" .. patch
      local entry_size = #entry + 1
      if remaining_budget >= entry_size then
        table.insert(diff_parts, 1, entry) -- prepend to maintain order
        remaining_budget = remaining_budget - entry_size
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

  table.insert(parts, FILE_SEP .. "original/" .. file_path)
  table.insert(parts, original_content)
  table.insert(parts, FILE_SEP .. "current/" .. file_path)
  table.insert(parts, current_content)
  table.insert(parts, FILE_SEP .. "updated/" .. file_path)

  return table.concat(parts, "\n")
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

  local cmd = {
    "curl",
    "-s",
    "--max-time", tostring(timeout),
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", json_payload,
    url,
  }

  local job = vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err_msg = result.stderr or "unknown error"
        if result.code == 28 or err_msg:find("timed out") then
          callback(nil, "request timed out")
        else
          callback(nil, "curl failed: " .. err_msg)
        end
        return
      end

      local response = util.json_decode(result.stdout)
      if not response then
        callback(nil, "failed to parse response")
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

  local original_content = diff.get_original(bufnr)
  local current_content = util.get_buffer_content(bufnr)

  if original_content == current_content then
    callback(nil, "no changes detected")
    return nil
  end

  local prompt = M.build_prompt(file_path, original_content, current_content, {}, diff.get_recent_diffs())

  local job = M.request_completion(prompt, function(response, err)
    debug_log(prompt, response, err)
    callback(response, err)
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
