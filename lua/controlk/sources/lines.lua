return {
  id = "lines",
  title = "Line in current document",
  tag = "line",
  items = function(query, ctx, done)
    local line, column = query:match("^(%d+)[:+]?(%d*)$")
    if not line then
      return done({})
    end

    local lnum = tonumber(line)
    local col = tonumber(column) or 1
    local name = vim.api.nvim_buf_get_name(ctx.origin_buf)
    local text = column ~= "" and ("Line %d, column %d"):format(lnum, col) or ("Line %d"):format(lnum)
    done({
      {
        text = text,
        bufnr = ctx.origin_buf,
        path = name ~= "" and name or nil,
        lnum = lnum,
        col = col,
        passthrough = true,
      },
    })
  end,
}
