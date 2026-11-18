local util = require("controlk.util")

return {
  id = "shell",
  title = "Run shell command",
  tag = "shell",
  items = function(query, ctx, done)
    if query == "" then
      return done({})
    end
    done({
      {
        text = query,
        detail = ctx.root,
        passthrough = true,
        run = function()
          util.terminal({ vim.o.shell, "-c", query }, ctx.root)
        end,
      },
    })
  end,
}
