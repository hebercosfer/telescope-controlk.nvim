-- `?`: help. Alone, it lists the prefixes, as Qt Creator's locator lists its filters. With
-- text, it lists the prefixes the text names, then their sections of controlk's help, then
-- the help tags: first what `:help <Tab>` offers, in Neovim's own order (the exact tag first),
-- then every other tag, fuzzy matched, so an abbreviation still finds one.

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

-- The prefixes `text` names: it is the prefix, or the source's title holds it, ignoring case.
-- Not fuzzy: on short titles that would reach half the list. Then one row per section of the
-- help that explains one of them; a user source has none.
local function prefix_rows(text, cfg, files)
  local lower = text:lower()
  local rows = prefixes.rows(cfg.prefix_map, cfg.source_map, function(prefix)
    local source = cfg.source_map[cfg.prefix_map[prefix]]
    local title = source and source.title or ""
    return prefix == text or title:lower():find(lower, 1, true) ~= nil
  end)
  local sections = {}
  for _, row in ipairs(rows) do
    row.pinned = true
    local tag = "controlk-source-" .. cfg.prefix_map[row.tag]
    if files[tag] then
      table.insert(sections, {
        text = tag,
        detail = files[tag],
        pinned = true,
        passthrough = true,
        run = opener(tag),
      })
    end
  end
  return vim.list_extend(rows, sections)
end

return {
  id = "help",
  title = "Help, and this list of prefixes",
  tag = "help",
  items = function(query, ctx, done)
    local text = vim.trim(query)
    if text == "" then
      return done(prefixes.rows(ctx.config.prefix_map, ctx.config.source_map))
    end
    all_tags(ctx, function(tags)
      local list, seen = prefix_rows(text, ctx.config, tags.files), {}
      for _, row in ipairs(list) do
        if not row.prompt then
          seen[row.text] = true
        end
      end
      local ok, matched = pcall(vim.fn.getcompletion, text, "help")
      for _, tag in ipairs(ok and matched or {}) do
        if not seen[tag] then
          seen[tag] = true
          table.insert(list, {
            text = tag,
            detail = tags.files[tag],
            pinned = true,
            passthrough = true,
            run = opener(tag),
          })
        end
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
