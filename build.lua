local MODEL_DIR = vim.fn.expand("~/.local/share/ne")
local MODEL_FILE = "sweep-next-edit-1.5b.q8_0.v2.gguf"
local MODEL_PATH = MODEL_DIR .. "/" .. MODEL_FILE
local REPO_ID = "sweepai/sweep-next-edit-1.5B"

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

local function run(cmd)
  local result = vim.fn.system(cmd)
  return vim.v.shell_error == 0, result
end

coroutine.yield("Checking for model file...")

if file_exists(MODEL_PATH) then
  coroutine.yield("Model already exists at " .. MODEL_PATH)
  return
end

coroutine.yield("Model not found, preparing download...")

if not command_exists("huggingface-cli") then
  error(
    "huggingface-cli not found. Install it with:\n"
      .. "  pip install huggingface-hub\n"
      .. "or\n"
      .. "  uv pip install huggingface-hub"
  )
end

local ok, err = run("mkdir -p " .. vim.fn.shellescape(MODEL_DIR))
if not ok then
  error("Failed to create model directory: " .. err)
end

coroutine.yield("Downloading model from HuggingFace (~1.5GB)...")
coroutine.yield("This may take a while depending on your connection...")

local cmd = string.format(
  "huggingface-cli download %s %s --local-dir %s",
  REPO_ID,
  MODEL_FILE,
  vim.fn.shellescape(MODEL_DIR)
)

ok, err = run(cmd)
if not ok then
  error("Failed to download model: " .. err)
end

if not file_exists(MODEL_PATH) then
  error("Download completed but model file not found at " .. MODEL_PATH)
end

coroutine.yield("Model downloaded successfully to " .. MODEL_PATH)
