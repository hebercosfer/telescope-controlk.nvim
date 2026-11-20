local commands = require("controlk.sources.commands")

local function list(query)
  local items
  commands.items(query, { cache = {}, origin_win = vim.api.nvim_get_current_win() }, function(r)
    items = r
  end)
  return items
end

describe("commands source", function()
  it("lists the commands with no run row for an empty query", function()
    local items = list("")
    assert.is_true(#items > 100)
    assert.is_nil(items[1].pinned)
  end)

  it("puts a row that runs the typed command first", function()
    local items = list("let g:controlk_probe = 42")
    assert.are.equal(":let g:controlk_probe = 42", items[1].text)
    assert.is_true(items[1].pinned)
    items[1].run(items[1])
    assert.are.equal(42, vim.g.controlk_probe)
  end)

  it("reports an Ex error instead of raising it", function()
    local seen
    local real = vim.notify
    vim.notify = function(message)
      seen = message
    end
    local row = list("NoSuchCommandAtAll")[1]
    row.run(row)
    vim.notify = real
    assert.matches("E492", seen)
  end)
end)
