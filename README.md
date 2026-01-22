# ne.nvim

Neovim plugin for next-edit prediction using [sweep-next-edit-1.5B](https://huggingface.co/sweepai/sweep-next-edit-1.5B).

## Requirements

- Neovim 0.10+
- [llama.cpp](https://github.com/ggerganov/llama.cpp) (`llama-server` binary)
- [huggingface-cli](https://huggingface.co/docs/huggingface_hub/guides/cli) for model download

```bash
# Install huggingface-cli
brew install huggingface-cli

# Install llama.cpp (example for macOS)
brew install llama.cpp
```

## Installation

### lazy.nvim

```lua
{
  "laulauland/ne.nvim",
  build = "build.lua",
  config = function()
    require("ne").setup({
      server = {
        auto_start = true, -- by default it doesn't start on nvim bootup
      },
    })
  end,
}
```

The `build.lua` automatically downloads the model (~1.5GB) to `~/.local/share/ne/` on install.

## Configuration

```lua
require("ne").setup({
  server_url = "http://localhost:8080",
  max_tokens = 512,
  temperature = 0.0,
  debounce_ms = 300,
  auto_trigger = true,
  suggestion_hl_group = "Comment",

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
    model_path = "~/.local/share/ne/sweep-next-edit-1.5b.q8_0.v2.gguf",
    binary = "llama-server",
    host = "127.0.0.1",
    port = 8080,
    context_size = 8192,
    gpu_layers = nil,
    threads = nil,
    extra_args = {},
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:NeStart` | Start the llama server |
| `:NeStop` | Stop the llama server |
| `:NeRestart` | Restart the llama server |
| `:NeLogs` | View server output in a split |
| `:NeStatus` | Check server health |
| `:NeTrigger` | Manually trigger completion |
| `:NeClear` | Clear current suggestion |
| `:NeToggle` | Toggle auto-trigger on/off |

## Keymaps

Default keymaps (insert mode):

| Key | Action |
|-----|--------|
| `<Tab>` | Accept suggestion |
| `<C-Right>` | Accept next word |
| `<C-]>` | Clear suggestion |
| `<C-Space>` | Trigger suggestion |

## API

```lua
local ne = require("ne")

ne.trigger()        -- trigger completion
ne.accept()         -- accept suggestion
ne.accept_word()    -- accept next word
ne.clear()          -- clear suggestion
ne.has_suggestion() -- check if suggestion active

ne.server_start()   -- start server
ne.server_stop()    -- stop server
ne.server_restart() -- restart server
ne.server_status()  -- "stopped" | "starting" | "running"
ne.server_logs()    -- open logs buffer
```

## How It Works

The plugin tracks file changes and builds prompts in the sweep model format:

1. Captures original file state when buffer is opened
2. Records diffs when files are saved
3. On text change, sends context to the model:
   - Recent diffs from the session
   - Original file content
   - Current file content
4. Model predicts the "updated" version
5. Displays prediction as ghost text

## Manual Model Download

If automatic download fails:

```bash
mkdir -p ~/.local/share/ne
cd ~/.local/share/ne
huggingface-cli download sweepai/sweep-next-edit-1.5B \
  sweep-next-edit-1.5b.q8_0.v2.gguf --local-dir .
```

## Running Tests

```bash
nvim --headless -u NONE +"lua dofile('tests/run.lua')" +qa
```
