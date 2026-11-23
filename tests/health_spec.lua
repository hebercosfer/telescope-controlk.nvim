local health = require("controlk.health")

describe("health: compile_commands.json", function()
  local root

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
  end)

  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  local function db(dir)
    vim.fn.mkdir(root .. "/" .. dir, "p")
    vim.fn.writefile({ "[]" }, root .. "/" .. dir .. "/compile_commands.json")
    vim.fn.writefile({}, root .. "/" .. dir .. "/CMakeCache.txt")
  end

  it("finds the file where clangd looks: the root, then build/", function()
    assert.is_nil(health.clangd_database(root))
    db("build")
    assert.are.equal(root .. "/build/compile_commands.json", health.clangd_database(root))
    vim.fn.writefile({ "[]" }, root .. "/compile_commands.json")
    assert.are.equal(root .. "/compile_commands.json", health.clangd_database(root))
  end)

  it("lists databases in build directories clangd does not search, as absolute paths", function()
    db("build-ninja")
    assert.is_nil(health.clangd_database(root))
    local found = health.other_databases(root)
    assert.are.equal(1, #found)
    assert.are.equal(vim.fs.normalize(root .. "/build-ninja/compile_commands.json"), found[1])
  end)
end)
