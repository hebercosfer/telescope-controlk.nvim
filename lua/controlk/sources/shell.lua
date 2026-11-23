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
          -- A string: the terminal runs it with 'shell' and 'shellcmdflag' (cmd.exe /s /c on
          -- Windows, where "-c" opened an interactive prompt and never ran the command).
          util.terminal(query, ctx.root)
        end,
      },
    })
  end,
}
