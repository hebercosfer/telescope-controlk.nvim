local controlk = require("controlk")

local function rhs_of(lhs)
  return vim.tbl_get(vim.fn.maparg(lhs, "n", false, true), "rhs")
end

local function is_locator(rhs)
  return rhs ~= nil and rhs:find("Telescope controlk", 1, true) ~= nil
end

local KEYS = { "<C-k>", "<F7>", "<F8>" }

local function clear_keys()
  for _, lhs in ipairs(KEYS) do
    pcall(vim.keymap.del, "n", lhs)
  end
end

describe("controlk.setup keymap", function()
  before_each(clear_keys)
  after_each(clear_keys)

  it("maps <C-k> in normal mode by default", function()
    controlk.setup(nil)
    assert.is_true(is_locator(rhs_of("<C-k>")))
  end)

  it("maps the configured key instead of <C-k>", function()
    controlk.setup({ keymap = "<F7>" })
    assert.is_true(is_locator(rhs_of("<F7>")))
    assert.is_nil(rhs_of("<C-k>"))
  end)

  it("maps nothing when keymap is false", function()
    controlk.setup({ keymap = false })
    assert.is_nil(rhs_of("<C-k>"))
  end)

  it("stays mapped when setup runs again", function()
    controlk.setup(nil)
    controlk.setup(nil)
    assert.is_true(is_locator(rhs_of("<C-k>")))
  end)

  it("moves the locator when the configured key changes", function()
    controlk.setup({ keymap = "<F7>" })
    controlk.setup({ keymap = "<F8>" })
    assert.is_true(is_locator(rhs_of("<F8>")))
    assert.is_nil(rhs_of("<F7>"))
  end)

  it("never takes over a mapping of your own", function()
    vim.keymap.set("n", "<F8>", ":echo 'mine'<CR>")
    controlk.setup({ keymap = "<F8>" })
    assert.is_truthy((rhs_of("<F8>") or ""):find("echo 'mine'", 1, true))
  end)
end)
