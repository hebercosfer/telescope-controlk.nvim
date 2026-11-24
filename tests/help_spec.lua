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

describe("? with text, and controlk's prefixes", function()
  local function list_with(query, user)
    local items
    help.items(query, { config = config.resolve(user or {}), cache = {} }, function(result)
      items = result
    end)
    return items
  end

  local function index_of(items, pred)
    for i, item in ipairs(items) do
      if pred(item) then
        return i
      end
    end
  end

  local function prefix_row(prefix)
    return function(item)
      return item.prompt == prefix .. " "
    end
  end

  local function help_row(tag)
    return function(item)
      return item.text == tag and item.prompt == nil
    end
  end

  it("lists the matching prefix first, then its help, then the help tags", function()
    local items = list_with("mark")
    assert.are.equal("'", items[1].tag)
    assert.are.equal("' ", items[1].prompt)
    assert.is_true(items[1].pinned)
    assert.are.equal("controlk-source-marks", items[2].text)
    assert.is_true(items[2].pinned)
    assert.is_nil(items[2].prompt)
    items[2].run(items[2])
    assert.are.equal("help", vim.bo.filetype)
    vim.cmd.helpclose()
    assert.is_nil(items[3].prompt)
  end)

  it("matches the prefix itself, and titles ignoring case", function()
    assert.is_not_nil(index_of(list_with("cm"), prefix_row("cm")))
    local items = list_with("CMake")
    local cm, cmo = index_of(items, prefix_row("cm")), index_of(items, prefix_row("cmo"))
    local cm_help = index_of(items, help_row("controlk-source-cmake_targets"))
    local cmo_help = index_of(items, help_row("controlk-source-cmake_open"))
    assert.are.same({ 1, 2, 3, 4 }, { cm, cmo, cm_help, cmo_help })
  end)

  it("takes the text literally, not as a pattern", function()
    assert.is_not_nil(index_of(list_with("."), prefix_row(".")))
    assert.is_not_nil(list_with("%"))
  end)

  it("trims the text", function()
    assert.are.equal("'", list_with(" mark ")[1].tag)
    -- Only spaces is `?` alone: every prefix, not every title that holds "".
    assert.are.same(list_with(""), list_with("  "))
  end)

  it("gives a user source a prefix row and no help row", function()
    local items = list_with("echo", {
      sources = {
        echo = {
          prefix = "g",
          title = "Echo source",
          items = function(_, _, done)
            done({})
          end,
        },
      },
    })
    assert.are.equal(1, index_of(items, prefix_row("g")))
    for _, item in ipairs(items) do
      assert.is_false(item.pinned == true and item.text == "controlk-sources")
    end
  end)

  it("lists controlk's section once", function()
    local count = 0
    for _, item in ipairs(list_with("mark")) do
      if item.text == "controlk-source-marks" then
        count = count + 1
      end
    end
    assert.are.equal(1, count)
  end)
end)
