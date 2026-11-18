local util = require("controlk.util")

return {
  id = "files",
  title = "Files in project",
  tag = "file",
  items = function(_, ctx, done)
    util.memo(ctx, "files", function(finish)
      local cmd
      if vim.fn.executable("rg") == 1 then
        -- rg already skips hidden paths and honours .gitignore.
        cmd = { "rg", "--files" }
      else
        cmd = { "git", "ls-files", "--cached", "--others", "--exclude-standard" }
      end
      vim.system(cmd, { cwd = ctx.root, text = true }, function(res)
        local paths = {}
        if res.code == 0 then
          for line in (res.stdout or ""):gmatch("[^\n]+") do
            table.insert(paths, line)
          end
        end
        finish(paths)
      end)
    end, function(paths)
      local items = {}
      for _, rel in ipairs(paths) do
        table.insert(items, { text = rel, path = ctx.root .. "/" .. rel })
      end
      done(items)
    end)
  end,
}
