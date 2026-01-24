local M = {}

M.defaults = {
  server_url = "http://localhost:8080",
  max_tokens = 512,
  temperature = 0.0,
  debounce_ms = 300,
  debounce_ms_min = 300,
  debounce_ms_max = 1000,
  request_timeout = 10,
  max_prompt_size = 8192,
  max_diff_size = 1024,
  auto_trigger = true,
  suggestion_hl_group = "Comment",
  debug = {
    enabled = false,
    dir = vim.fn.expand("~/.local/share/ne/debug"),
  },
  keymaps = {
    accept_suggestion = "<Tab>",
    accept_word = "<C-Right>",
    clear_suggestion = "<C-]>",
    trigger_suggestion = "<C-Space>",
  },
  context = {
    max_files = 3,
    max_diffs = 5,
  },
  server = {
    auto_start = false,
    model_path = vim.fn.expand("~/.local/share/ne/sweep-next-edit-1.5b.q8_0.v2.gguf"),
    binary = "llama-server",
    host = "127.0.0.1",
    port = 8080,
    context_size = 8192,
    gpu_layers = nil,
    threads = nil,
    extra_args = {},
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

function M.get(key)
  if key then
    return M.options[key]
  end
  return M.options
end

return M
