local config = require("controlk.config")

local M = {}

local state = { config = config.resolve(nil), errors = {} }

-- The key this module mapped, so that a later setup can move or remove it.
local locator_key = nil

--- Map the locator in normal mode. A mapping that is not ours is left alone.
---@param key string|false|nil
local function map_locator(key)
  if type(key) ~= "string" then
    key = nil
  end
  if locator_key and locator_key ~= key then
    local map = vim.fn.maparg(locator_key, "n", false, true)
    if (map.rhs or ""):find("Telescope controlk", 1, true) then
      pcall(vim.keymap.del, "n", locator_key)
    end
    locator_key = nil
  end
  if not key or vim.fn.maparg(key, "n") ~= "" then
    return
  end
  vim.keymap.set("n", key, "<cmd>Telescope controlk<cr>", { desc = "controlk: locator" })
  locator_key = key
end

--- Apply user options: the `extensions.controlk` table of `telescope.setup()`.
---@param opts table|nil
function M.setup(opts)
  local resolved, errors = config.resolve(opts)
  state.config = resolved
  state.errors = errors
  for _, message in ipairs(errors) do
    vim.notify("controlk: " .. message, vim.log.levels.WARN)
  end
  map_locator(resolved.keymap)
end

--- Open the locator picker.
---@param opts table|nil telescope picker options
function M.open(opts)
  require("controlk.picker").open(opts or {}, state.config)
end

---@return table resolved configuration
function M.config()
  return state.config
end

---@return string[] problems the last setup reported, for :checkhealth controlk
function M.errors()
  return state.errors
end

return M
