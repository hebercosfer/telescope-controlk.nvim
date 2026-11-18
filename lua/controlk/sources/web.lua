return {
  id = "web",
  title = "Web search",
  tag = "web",
  items = function(query, ctx, done)
    if query == "" then
      return done({})
    end

    local encoded = vim.uri_encode(query, "rfc3986")
    local names = vim.tbl_keys(ctx.config.web.engines)
    table.sort(names)

    local items = {}
    for _, name in ipairs(names) do
      local url = ctx.config.web.engines[name]:gsub("%%s", function()
        return encoded
      end)
      table.insert(items, {
        text = ("%s: %s"):format(name, query),
        passthrough = true,
        run = function()
          vim.ui.open(url)
        end,
      })
    end
    done(items)
  end,
}
