local config = require("controlk.config")
local help = require("controlk.sources.help")

local function list(query)
  local items
  help.items(query, { config = config.resolve({}), cache = {} }, function(result)
    items = result
  end)
  return items
end

local function texts(items, n)
  return vim.tbl_map(function(item)
    return item.text
  end, vim.list_slice(items, 1, n))
end

describe("? with text", function()
  it("lists :help's own matches first, pinned, in Neovim's order", function()
    local items = list("number")
    local expected = vim.fn.getcompletion("number", "help")
    assert.are.same(vim.list_slice(expected, 1, 3), texts(items, 3))
    assert.is_true(items[1].pinned)
    assert.is_true(items[1].passthrough)
  end)

  it("then every other tag, for fuzzy matching", function()
    local items = list("bufgetlines")
    -- :help completion finds nothing for this abbreviation; the fuzzy rows still hold it.
    assert.are.same({}, vim.fn.getcompletion("bufgetlines", "help"))
    local found
    for _, item in ipairs(items) do
      if item.text == "nvim_buf_get_lines()" then
        found = item
      end
    end
    assert.is_not_nil(found)
    assert.is_nil(found.pinned)
  end)

  it("lists no tag twice", function()
    local seen = {}
    for _, item in ipairs(list("number")) do
      assert.is_nil(seen[item.text], item.text)
      seen[item.text] = true
    end
  end)

  it("opens the help on Enter", function()
    local item = list("controlk-sources")[1]
    assert.are.equal("controlk-sources", item.text)
    item.run(item)
    assert.are.equal("help", vim.bo.filetype)
    vim.cmd.helpclose()
  end)
end)
