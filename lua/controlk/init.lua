local config = require("controlk.config")

local M = {}

local state = { config = config.resolve(nil) }

--- Apply user options: the `extensions.controlk` table of `telescope.setup()`.
---@param opts table|nil
function M.setup(opts)
  local resolved, errors = config.resolve(opts)
  state.config = resolved
  for _, message in ipairs(errors) do
    vim.notify("controlk: " .. message, vim.log.levels.WARN)
  end
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

return M
