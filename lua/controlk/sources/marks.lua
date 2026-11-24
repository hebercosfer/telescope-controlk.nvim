local function mark_item(mark, path, lnum, col)
  return {
    text = mark:sub(2),
    detail = ("%s:%d"):format(vim.fn.fnamemodify(path, ":~:."), lnum),
    path = path,
    lnum = lnum,
    col = col,
  }
end

return {
  id = "marks",
  title = "Marks",
  tag = "mark",
  items = function(query, ctx, done)
    local items = {}

    for _, m in ipairs(vim.fn.getmarklist()) do
      if m.file and m.file ~= "" then
        -- getmarklist() gives "~/..." for a file under the home directory; the previewer and
        -- bufadd() need the real path.
        table.insert(items, mark_item(m.mark, vim.fs.normalize(m.file), m.pos[2], m.pos[3]))
      end
    end

    for _, m in ipairs(vim.fn.getmarklist(ctx.origin_buf)) do
      local path = vim.api.nvim_buf_get_name(m.pos[1])
      if path ~= "" then
        table.insert(items, mark_item(m.mark, path, m.pos[2], m.pos[3]))
      end
    end

    -- "' Q" names mark Q. Fuzzy matching also scores the paths, so another mark whose path
    -- holds a Q can tie with it and win; the mark the query names ranks first.
    local name = vim.trim(query or "")
    for _, item in ipairs(items) do
      if item.text == name then
        item.pinned = true
      end
    end

    done(items)
  end,
}
