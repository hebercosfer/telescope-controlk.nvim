local web = require("controlk.sources.web")

local function urls(query, engines)
  local opened = {}
  local real = vim.ui.open
  vim.ui.open = function(url)
    table.insert(opened, url)
  end
  web.items(query, { config = { web = { engines = engines } } }, function(items)
    for _, item in ipairs(items) do
      item.run(item)
    end
  end)
  vim.ui.open = real
  return opened
end

describe("web source", function()
  it("encodes the query into a search engine's URL", function()
    assert.are.same(
      { "https://duckduckgo.com/?q=neovim%20lua" },
      urls("neovim lua", { DuckDuckGo = "https://duckduckgo.com/?q=%s" })
    )
  end)

  it("opens the query itself with an engine of just %s, adding https:// when needed", function()
    assert.are.same(
      { "https://github.com/neovim/neovim" },
      urls("github.com/neovim/neovim", { Direct = "%s" })
    )
    assert.are.same(
      { "http://localhost:8080/x?a=1" },
      urls("http://localhost:8080/x?a=1", { Direct = "%s" })
    )
  end)

  it("lists nothing for an empty query", function()
    assert.are.same({}, urls("", { Direct = "%s" }))
  end)
end)
