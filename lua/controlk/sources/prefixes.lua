-- The prefix list, as Qt Creator's locator shows its filters. Picking an entry does not run
-- anything: its `prompt` replaces the input, so the locator switches to that source.

return {
  id = "prefixes",
  title = "Prefixes",
  items = function(_, ctx, done)
    -- Required here, not at the top: the registry loads this module.
    local registry = require("controlk.sources")
    local items = {}
    for prefix, id in pairs(ctx.config.prefix_map) do
      if id ~= "prefixes" then
        local source = registry.get(id)
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
    done(items)
  end,
}
