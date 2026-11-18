local util = require("controlk.util")

return {
  id = "commands",
  title = "Ex commands",
  tag = "cmd",
  items = function(_, ctx, done)
    util.memo(ctx, "commands", function(finish)
      local user = vim.api.nvim_get_commands({})
      local items = {}
      for _, name in ipairs(vim.fn.getcompletion("", "command")) do
        local definition = user[name] and user[name].definition
        table.insert(items, {
          text = name,
          detail = definition,
          -- Open the command line with the name filled in, so arguments can follow.
          run = function()
            vim.api.nvim_feedkeys(":" .. name .. " ", "n", false)
          end,
        })
      end
      finish(items)
    end, done)
  end,
}
