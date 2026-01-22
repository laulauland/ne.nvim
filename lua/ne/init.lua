local config = require("ne.config")
local completion = require("ne.completion")
local diff = require("ne.diff")
local backend = require("ne.backend")
local server = require("ne.server")

local M = {}

local function setup_keymaps()
  local keymaps = config.get("keymaps")

  if keymaps.accept_suggestion then
    vim.keymap.set("i", keymaps.accept_suggestion, completion.accept, {
      noremap = true,
      silent = true,
      desc = "ne: Accept suggestion",
    })
  end

  if keymaps.accept_word then
    vim.keymap.set("i", keymaps.accept_word, completion.accept_word, {
      noremap = true,
      silent = true,
      desc = "ne: Accept word",
    })
  end

  if keymaps.clear_suggestion then
    vim.keymap.set("i", keymaps.clear_suggestion, completion.dispose, {
      noremap = true,
      silent = true,
      desc = "ne: Clear suggestion",
    })
  end

  if keymaps.trigger_suggestion then
    vim.keymap.set("i", keymaps.trigger_suggestion, completion.trigger, {
      noremap = true,
      silent = true,
      desc = "ne: Trigger suggestion",
    })
  end
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("ne", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      diff.capture_original(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      diff.record_diff(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    callback = function()
      completion.on_text_changed()
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      completion.on_insert_leave()
    end,
  })

  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = group,
    callback = function()
      completion.on_cursor_moved()
    end,
  })
end

local function setup_commands()
  vim.api.nvim_create_user_command("NeStatus", function()
    local server_status = server.get_status()
    backend.health_check(function(ok, err)
      if ok then
        vim.notify("ne: Server is healthy (status: " .. server_status .. ")", vim.log.levels.INFO)
      else
        vim.notify("ne: " .. (err or "Server unreachable") .. " (status: " .. server_status .. ")", vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Check ne server status" })

  vim.api.nvim_create_user_command("NeTrigger", function()
    completion.trigger()
  end, { desc = "Manually trigger ne completion" })

  vim.api.nvim_create_user_command("NeClear", function()
    completion.dispose()
  end, { desc = "Clear current ne suggestion" })

  vim.api.nvim_create_user_command("NeToggle", function()
    local current = config.get("auto_trigger")
    config.options.auto_trigger = not current
    vim.notify("ne: auto_trigger " .. (config.options.auto_trigger and "enabled" or "disabled"), vim.log.levels.INFO)
  end, { desc = "Toggle ne auto-trigger" })

  vim.api.nvim_create_user_command("NeStart", function()
    server.start(function(ok, err)
      if not ok then
        vim.notify("ne: " .. (err or "Failed to start server"), vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Start the llama server" })

  vim.api.nvim_create_user_command("NeStop", function()
    server.stop(function(ok, err)
      if ok then
        vim.notify("ne: Server stopped", vim.log.levels.INFO)
      else
        vim.notify("ne: " .. (err or "Failed to stop server"), vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Stop the llama server" })

  vim.api.nvim_create_user_command("NeRestart", function()
    server.restart(function(ok, err)
      if not ok then
        vim.notify("ne: " .. (err or "Failed to restart server"), vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Restart the llama server" })

  vim.api.nvim_create_user_command("NeLogs", function()
    server.show_logs()
  end, { desc = "Show llama server logs" })
end

local function setup_cleanup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ne_cleanup", { clear = true }),
    callback = function()
      if server.is_running() then
        server.stop()
      end
    end,
  })
end

function M.setup(opts)
  config.setup(opts)
  setup_keymaps()
  setup_autocmds()
  setup_commands()
  setup_cleanup()

  local server_opts = config.get("server")
  if server_opts and server_opts.auto_start and server_opts.model_path then
    vim.defer_fn(function()
      server.start()
    end, 100)
  end
end

M.trigger = completion.trigger
M.accept = completion.accept
M.accept_word = completion.accept_word
M.clear = completion.dispose
M.has_suggestion = completion.has_suggestion

M.server_start = server.start
M.server_stop = server.stop
M.server_restart = server.restart
M.server_status = server.get_status
M.server_logs = server.show_logs

return M
