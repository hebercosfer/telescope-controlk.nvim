local cutie = require("controlk.cutie")

local opts = { width = 40, height = 15, preview = true }
local screen = { columns = 200, lines = 50, cmdheight = 1, laststatus = 2 }

describe("cutie.geometry", function()
  it(
    "puts the prompt bottom-left above the status line, the list above, the preview right",
    function()
      local g = cutie.geometry(screen, opts)
      assert.are.same({ row = 45, col = 0, width = 40, height = 3 }, g.prompt)
      assert.are.same({ row = 28, col = 0, width = 40, height = 17 }, g.results)
      assert.are.same({ row = 28, col = 40, width = 160, height = 20 }, g.preview)
    end
  )

  it("uses the status line's row when there is no status line", function()
    local g = cutie.geometry(vim.tbl_extend("force", screen, { laststatus = 0 }), opts)
    assert.are.equal(46, g.prompt.row)
  end)

  it("never reaches the status line or the command line", function()
    for _, s in ipairs({ screen, { columns = 100, lines = 30, cmdheight = 2, laststatus = 3 } }) do
      local g = cutie.geometry(s, opts)
      local last = s.lines - s.cmdheight - (s.laststatus > 0 and 1 or 0) - 1
      for _, box in pairs(g) do
        assert.is_true(box.row + box.height - 1 <= last)
      end
    end
  end)

  it("shrinks the list on a short screen and keeps one row", function()
    local g = cutie.geometry({ columns = 30, lines = 8, cmdheight = 1, laststatus = 2 }, opts)
    assert.is_true(g.results.height >= 3)
    assert.are.equal(30, g.prompt.width)
    assert.is_true(g.results.row >= 0)
    assert.is_nil(g.preview)
  end)

  it("drops a preview narrower than 20 columns, or when switched off", function()
    local narrow = { columns = 59, lines = 50, cmdheight = 1, laststatus = 2 }
    assert.is_nil(cutie.geometry(narrow, opts).preview)
    assert.is_nil(cutie.geometry(screen, { width = 40, height = 15, preview = false }).preview)
  end)
end)

describe("cutie width", function()
  it("measures a left sidebar for auto, and nothing else", function()
    assert.are.equal(
      32,
      cutie.sidebar_width({
        { col = 0, width = 32, floating = false },
        { col = 33, width = 167, floating = false },
      }, 200)
    )
    assert.is_nil(cutie.sidebar_width({ { col = 0, width = 200, floating = false } }, 200))
    assert.is_nil(cutie.sidebar_width({ { col = 0, width = 120, floating = false } }, 200))
    assert.is_nil(cutie.sidebar_width({ { col = 0, width = 40, floating = true } }, 200))
  end)

  it("resolves auto to the sidebar or 40, and clamps to the screen", function()
    assert.are.equal(40, cutie.resolve_width("auto", {}, 200))
    assert.are.equal(
      32,
      cutie.resolve_width("auto", { { col = 0, width = 32, floating = false } }, 200)
    )
    assert.are.equal(30, cutie.resolve_width(40, {}, 30))
  end)
end)
