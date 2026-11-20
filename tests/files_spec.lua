local files = require("controlk.sources.files")

describe("files source rg command", function()
  it("lists what rg lists by default", function()
    assert.are.same({ "rg", "--files" }, files.rg_command(nil))
    assert.are.same({ "rg", "--files" }, files.rg_command({ hidden = false, ignored = false }))
  end)

  it("adds hidden paths, never .git itself", function()
    assert.are.same(
      { "rg", "--files", "--hidden", "--glob", "!.git" },
      files.rg_command({ hidden = true })
    )
  end)

  it("adds ignored files", function()
    assert.are.same({ "rg", "--files", "--no-ignore" }, files.rg_command({ ignored = true }))
  end)
end)
