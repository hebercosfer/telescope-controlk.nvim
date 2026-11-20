-- The prefix list, as Qt Creator's locator shows its filters. Picking an entry does not run
-- anything: its `prompt` replaces the input, so the locator switches to that source.

-- One row per prefix accepted by `keep`, sorted by prefix. The list itself is never listed.
-- source_map holds the user's sources too; without it, only the built-ins have titles.
local function rows(prefix_map, source_map, keep)
  -- Required here, not at the top: the registry loads this module.
  source_map = source_map or require("controlk.sources").by_id
  local items = {}
  for prefix, id in pairs(prefix_map) do
    if id ~= "prefixes" and keep(prefix) then
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

return {
  id = "prefixes",
  title = "Prefixes",
  items = function(_, ctx, done)
    done(rows(ctx.config.prefix_map, ctx.config.source_map, function()
      return true
    end))
  end,

  --- The prefixes a partly typed prompt could become, as pinned rows that rank before
  --- every other row. Literal and case-sensitive, like the prefixes themselves.
  ---@param prompt string
  ---@param prefix_map table<string, string>
  ---@param source_map table<string, table>|nil
  ---@return table[] items
  matching = function(prompt, prefix_map, source_map)
    if prompt == "" then
      return {}
    end
    local items = rows(prefix_map, source_map, function(prefix)
      return prefix:sub(1, #prompt) == prompt
    end)
    for _, item in ipairs(items) do
      item.pinned = true
    end
    return items
  end,
}
