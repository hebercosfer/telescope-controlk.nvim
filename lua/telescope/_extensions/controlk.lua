local telescope = require("telescope")
local controlk = require("controlk")

return telescope.register_extension({
  setup = function(ext_config)
    controlk.setup(ext_config)
  end,
  exports = {
    controlk = function(opts)
      controlk.open(opts)
    end,
  },
})
