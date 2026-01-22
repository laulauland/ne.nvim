local config = require("ne.config")
local util = require("ne.util")

local M = {}

M.job_id = nil
M.status = "stopped"
M.output_buf = nil

local function get_server_cmd()
  local opts = config.get("server")
  local cmd = {
    opts.binary or "llama-server",
    "-m", opts.model_path,
    "-c", tostring(opts.context_size or 8192),
    "--port", tostring(opts.port or 8080),
    "--host", opts.host or "127.0.0.1",
  }

  if opts.gpu_layers then
    table.insert(cmd, "-ngl")
    table.insert(cmd, tostring(opts.gpu_layers))
  end

  if opts.threads then
    table.insert(cmd, "-t")
    table.insert(cmd, tostring(opts.threads))
  end

  for _, arg in ipairs(opts.extra_args or {}) do
    table.insert(cmd, arg)
  end

  return cmd
end

local function create_output_buffer()
  if M.output_buf and vim.api.nvim_buf_is_valid(M.output_buf) then
    return M.output_buf
  end

  M.output_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(M.output_buf, "ne://server")
  vim.bo[M.output_buf].buftype = "nofile"
  vim.bo[M.output_buf].bufhidden = "hide"
  vim.bo[M.output_buf].swapfile = false
  return M.output_buf
end

local function append_output(data)
  if not M.output_buf or not vim.api.nvim_buf_is_valid(M.output_buf) then
    return
  end

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(M.output_buf) then
      return
    end
    local lines = vim.split(data, "\n", { trimempty = false })
    vim.api.nvim_buf_set_lines(M.output_buf, -1, -1, false, lines)
  end)
end

function M.start(callback)
  callback = callback or function() end

  if M.job_id then
    callback(false, "server already running")
    return
  end

  local server_opts = config.get("server")
  local model_path = server_opts and server_opts.model_path
  if not model_path or model_path == "" then
    callback(false, "server.model_path not configured")
    return
  end

  local cmd = get_server_cmd()
  create_output_buffer()

  M.status = "starting"
  vim.notify("ne: Starting server...", vim.log.levels.INFO)

  M.job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data then
        append_output(table.concat(data, "\n"))
      end
    end,
    on_stderr = function(_, data)
      if data then
        append_output(table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, exit_code)
      M.job_id = nil
      M.status = "stopped"
      vim.schedule(function()
        if exit_code ~= 0 then
          vim.notify("ne: Server exited with code " .. exit_code, vim.log.levels.WARN)
        else
          vim.notify("ne: Server stopped", vim.log.levels.INFO)
        end
      end)
    end,
  })

  if M.job_id <= 0 then
    M.job_id = nil
    M.status = "stopped"
    callback(false, "failed to start server")
    return
  end

  local function wait_for_ready(attempts)
    if attempts <= 0 then
      callback(false, "server did not become ready")
      return
    end

    local opts = config.get()
    local url = opts.server_url .. "/health"

    vim.system({ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", url }, { text = true }, function(result)
      vim.schedule(function()
        if result.stdout and result.stdout:match("200") then
          M.status = "running"
          vim.notify("ne: Server ready", vim.log.levels.INFO)
          callback(true, nil)
        else
          vim.defer_fn(function()
            wait_for_ready(attempts - 1)
          end, 500)
        end
      end)
    end)
  end

  vim.defer_fn(function()
    wait_for_ready(20)
  end, 1000)
end

function M.stop(callback)
  callback = callback or function() end

  if not M.job_id then
    callback(false, "server not running")
    return
  end

  vim.fn.jobstop(M.job_id)
  M.job_id = nil
  M.status = "stopped"
  callback(true, nil)
end

function M.restart(callback)
  callback = callback or function() end

  M.stop(function()
    vim.defer_fn(function()
      M.start(callback)
    end, 500)
  end)
end

function M.is_running()
  return M.job_id ~= nil and M.status == "running"
end

function M.get_status()
  return M.status
end

function M.show_logs()
  if not M.output_buf or not vim.api.nvim_buf_is_valid(M.output_buf) then
    vim.notify("ne: No server logs available", vim.log.levels.WARN)
    return
  end

  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, M.output_buf)
  vim.cmd("normal! G")
end

return M
