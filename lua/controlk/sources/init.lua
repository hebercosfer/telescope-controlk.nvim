-- Registry of every source. A module either returns one source (with an `id`)
-- or a table of sources keyed by their id. In the second form only entries with an
-- `items` function are sources: a module may export helpers next to them (lsp.kinds).

local modules = {
  "buffers",
  "files",
  "lines",
  "filesystem",
  "help",
  "prefixes",
  "commands",
  "marks",
  "eval",
  "lua",
  "shell",
  "web",
  "lsp",
  "cmake",
}

local M = { by_id = {} }

for _, name in ipairs(modules) do
  local mod = require("controlk.sources." .. name)
  if mod.id then
    M.by_id[mod.id] = mod
  else
    for id, source in pairs(mod) do
      if type(source) == "table" and type(source.items) == "function" then
        source.id = id
        M.by_id[id] = source
      end
    end
  end
end

---@param id string
---@return table|nil source
function M.get(id)
  return M.by_id[id]
end

return M
