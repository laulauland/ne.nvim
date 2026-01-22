local util = require("ne.util")
local config = require("ne.config")
local diff = require("ne.diff")

local M = {}

local FILE_SEP = "<|file_sep|>"
local STOP_TOKENS = { "<|file_sep|>", "</s>", "<|endoftext|>" }

function M.build_prompt(file_path, original_content, current_content, context_files, recent_diffs)
  context_files = context_files or {}
  recent_diffs = recent_diffs or diff.get_recent_diffs()

  local parts = {}

  for path, content in pairs(context_files) do
    table.insert(parts, FILE_SEP .. path)
    table.insert(parts, content)
  end

  for _, d in ipairs(recent_diffs) do
    table.insert(parts, FILE_SEP .. d.file_path .. ".diff")
    table.insert(parts, "original:")
    table.insert(parts, d.original)
    table.insert(parts, "updated:")
    table.insert(parts, d.updated)
  end

  table.insert(parts, FILE_SEP .. "original/" .. file_path)
  table.insert(parts, original_content)
  table.insert(parts, FILE_SEP .. "current/" .. file_path)
  table.insert(parts, current_content)
  table.insert(parts, FILE_SEP .. "updated/" .. file_path)

  return table.concat(parts, "\n")
end

function M.request_completion(prompt, callback)
  local opts = config.get()
  local url = opts.server_url .. "/completion"

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
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", json_payload,
    url,
  }

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "curl failed: " .. (result.stderr or "unknown error"))
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
end

function M.get_completion(bufnr, callback)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local file_path = util.get_buffer_path(bufnr)
  if file_path == "" then
    callback(nil, "buffer has no file path")
    return
  end

  local original_content = diff.get_original(bufnr)
  local current_content = util.get_buffer_content(bufnr)

  if original_content == current_content then
    callback(nil, "no changes detected")
    return
  end

  local prompt = M.build_prompt(file_path, original_content, current_content, {}, diff.get_recent_diffs())

  M.request_completion(prompt, callback)
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
