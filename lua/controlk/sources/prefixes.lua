-- The prefix list, as Qt Creator's locator shows its filters: what an empty prompt shows,
-- what `?` alone shows, and what a partly typed prefix narrows to. Not a source itself.
-- Picking an entry does not run anything: its `prompt` replaces the input, so the locator
-- switches to that source.

local M = {}

--- One row per prefix accepted by `keep` (every prefix without it), sorted by prefix.
--- source_map holds the user's sources too; without it, only the built-ins have titles.
---@param prefix_map table<string, string>
---@param source_map table<string, table>|nil
---@param keep (fun(prefix: string): boolean)|nil
---@return table[]
function M.rows(prefix_map, source_map, keep)
  -- Required here, not at the top: the registry loads the help source, which loads this.
  source_map = source_map or require("controlk.sources").by_id
  local items = {}
  for prefix, id in pairs(prefix_map) do
    if not keep or keep(prefix) then
      local source = source_map[id]
      local title = source and source.title or id
      table.insert(items, {
        tag = prefix,
        text = title,
        ordinal = prefix .. " " .. title,
        prompt = prefix .. " ",
      })
    end
  end
  table.sort(items, function(a, b)
    return a.tag < b.tag
  end)
  return items
end

--- The prefixes a partly typed prompt could become, as pinned rows that rank before
--- every other row. Literal and case-sensitive, like the prefixes themselves.
---@param prompt string
---@param prefix_map table<string, string>
---@param source_map table<string, table>|nil
---@return table[] items
function M.matching(prompt, prefix_map, source_map)
  if prompt == "" then
    return {}
  end
  local items = M.rows(prefix_map, source_map, function(prefix)
    return prefix:sub(1, #prompt) == prompt
  end)
  for _, item in ipairs(items) do
    item.pinned = true
  end
  return items
end

return M
