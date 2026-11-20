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
      local template = ctx.config.web.engines[name]
      local url
      if template == "%s" then
        -- The query is the address itself (the Direct engine): kept as typed, not encoded, with
        -- https:// added when it has no scheme.
        url = query:match("^%a[%w+.-]*://") and query or ("https://" .. query)
      else
        url = template:gsub("%%s", function()
          return encoded
        end)
      end
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
