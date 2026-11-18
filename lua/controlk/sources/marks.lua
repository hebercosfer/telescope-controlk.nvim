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
  items = function(_, ctx, done)
    local items = {}

    for _, m in ipairs(vim.fn.getmarklist()) do
      if m.file and m.file ~= "" then
        table.insert(items, mark_item(m.mark, m.file, m.pos[2], m.pos[3]))
      end
    end

    for _, m in ipairs(vim.fn.getmarklist(ctx.origin_buf)) do
      local path = vim.api.nvim_buf_get_name(m.pos[1])
      if path ~= "" then
        table.insert(items, mark_item(m.mark, path, m.pos[2], m.pos[3]))
      end
    end

    done(items)
  end,
}
