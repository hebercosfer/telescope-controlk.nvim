return {
  id = "filesystem",
  title = "Files in file system",
  tag = "fs",
  items = function(query, ctx, done)
    local expanded = vim.fn.expand(query)
    local path = expanded:sub(1, 1) == "/" and expanded or (ctx.root .. "/" .. expanded)

    local dir, base
    if path:sub(-1) == "/" then
      dir, base = path, ""
    else
      dir, base = vim.fs.dirname(path), vim.fs.basename(path)
    end

    local items = {}
    for _, name in ipairs(vim.fn.readdir(dir)) do
      if base == "" or name:sub(1, #base):lower() == base:lower() then
        local full = vim.fs.joinpath(dir, name)
        local is_dir = vim.fn.isdirectory(full) == 1
        table.insert(items, {
          text = name .. (is_dir and "/" or ""),
          path = full,
          passthrough = true,
          is_dir = is_dir,
        })
      end
    end

    table.sort(items, function(a, b)
      if a.is_dir ~= b.is_dir then
        return a.is_dir
      end
      return a.text < b.text
    end)
    done(items)
  end,
}
