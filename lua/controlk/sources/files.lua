local util = require("controlk.util")

local source = {
  id = "files",
  title = "Files in project",
  tag = "file",
}

--- rg's command for the project files. By default rg skips hidden paths and what .gitignore
--- names; `hidden` and `ignored` add them back. .git itself is never listed.
---@param opts { hidden: boolean, ignored: boolean }|nil
---@return string[]
function source.rg_command(opts)
  opts = opts or {}
  local cmd = { "rg", "--files" }
  if opts.hidden then
    vim.list_extend(cmd, { "--hidden", "--glob", "!.git" })
  end
  if opts.ignored then
    table.insert(cmd, "--no-ignore")
  end
  return cmd
end

function source.items(_, ctx, done)
  util.memo(ctx, "files", function(finish)
    local cmd
    if vim.fn.executable("rg") == 1 then
      cmd = source.rg_command(ctx.config.files)
    else
      -- Lists tracked dotfiles already; git cannot add ignored files to this list.
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
end

return source
