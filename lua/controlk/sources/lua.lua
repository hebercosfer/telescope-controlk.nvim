-- `lua`: run Lua, as `:lua` does, with the completion a command-line menu shows for `:lua`.
-- `=` (eval) stays the way to see the value of an expression.

local cmdline = require("controlk.cmdline")

return {
  id = "lua",
  title = "Run Lua",
  tag = "lua",
  items = function(query, ctx, done)
    local prefix = cmdline.prefix_of(ctx, "lua", "lua")
    local list = {}
    if query ~= "" then
      -- Runs the chunk in the window the locator came from. What `print` writes, and any
      -- error, is notified.
      table.insert(list, {
        text = query,
        detail = "run",
        pinned = true,
        passthrough = true,
        run = function()
          cmdline.run("lua " .. query, ctx.origin_win)
        end,
      })
    end
    vim.list_extend(
      list,
      cmdline.completions("lua " .. query, function(line)
        return prefix .. " " .. line:gsub("^lua ", "")
      end)
    )
    done(list)
  end,
}
