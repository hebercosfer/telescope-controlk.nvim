local controlk = require("controlk")
local telescope = require("telescope")

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
