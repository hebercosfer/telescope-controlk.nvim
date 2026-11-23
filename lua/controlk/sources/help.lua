-- `?`: help. Alone, it lists the prefixes, as Qt Creator's locator lists its filters. With
-- text, it searches help tags: first what `:help <Tab>` offers, in Neovim's own order (the
-- exact tag first), then every other tag, fuzzy matched, so an abbreviation still finds one.

local prefixes = require("controlk.sources.prefixes")
local util = require("controlk.util")

local function opener(tag)
  return function()
    vim.cmd({ cmd = "help", args = { tag } })
  end
end

-- Every tag on 'runtimepath', once per picker: the rows, and each tag's help file.
local function all_tags(ctx, done)
  util.memo(ctx, "help_tags", function(finish)
    local rows, files = {}, {}
    for _, file in ipairs(vim.api.nvim_get_runtime_file("doc/tags", true)) do
      for _, line in ipairs(vim.fn.readfile(file)) do
        local tag, doc = line:match("^([^\t]+)\t([^\t]+)\t")
        if tag and tag:sub(1, 1) ~= "!" and not files[tag] then
          files[tag] = doc
          table.insert(rows, { text = tag, detail = doc, run = opener(tag) })
        end
      end
    end
    finish({ rows = rows, files = files })
  end, done)
end

return {
  id = "help",
  title = "Help, and this list of prefixes",
  tag = "help",
  items = function(query, ctx, done)
    if query == "" then
      return done(prefixes.rows(ctx.config.prefix_map, ctx.config.source_map))
    end
    all_tags(ctx, function(tags)
      local ok, matched = pcall(vim.fn.getcompletion, query, "help")
      local list, seen = {}, {}
      for _, tag in ipairs(ok and matched or {}) do
        seen[tag] = true
        table.insert(list, {
          text = tag,
          detail = tags.files[tag],
          pinned = true,
          passthrough = true,
          run = opener(tag),
        })
      end
      for _, row in ipairs(tags.rows) do
        if not seen[row.text] then
          table.insert(list, row)
        end
      end
      done(list)
    end)
  end,
}
