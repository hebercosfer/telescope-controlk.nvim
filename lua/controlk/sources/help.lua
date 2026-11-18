local util = require("controlk.util")

return {
  id = "help",
  title = "Help tags",
  tag = "help",
  items = function(_, ctx, done)
    util.memo(ctx, "help_tags", function(finish)
      local items = {}
      for _, file in ipairs(vim.api.nvim_get_runtime_file("doc/tags", true)) do
        for _, line in ipairs(vim.fn.readfile(file)) do
          local tag, doc = line:match("^([^\t]+)\t([^\t]+)\t")
          if tag and tag:sub(1, 1) ~= "!" then
            table.insert(items, {
              text = tag,
              detail = doc,
              run = function()
                vim.cmd({ cmd = "help", args = { tag } })
              end,
            })
          end
        end
      end
      finish(items)
    end, done)
  end,
}
