return {
  id = "buffers",
  title = "Open buffers",
  tag = "buffer",
  items = function(_, _, done)
    local infos = vim.fn.getbufinfo({ buflisted = 1 })
    table.sort(infos, function(a, b)
      return (a.lastused or 0) > (b.lastused or 0)
    end)

    local items = {}
    for _, info in ipairs(infos) do
      local has_name = info.name ~= ""
      table.insert(items, {
        text = has_name and vim.fn.fnamemodify(info.name, ":~:.") or "[No Name]",
        detail = info.changed == 1 and "[+]" or nil,
        bufnr = info.bufnr,
        path = has_name and info.name or nil,
        lnum = info.lnum > 0 and info.lnum or nil,
      })
    end
    done(items)
  end,
}
