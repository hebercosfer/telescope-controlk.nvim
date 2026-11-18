local cmake = require("controlk.cmake")

local fixtures = vim.fn.getcwd() .. "/tests/fixtures"

local function targets_by_name(model)
  local by_name = {}
  for _, target in ipairs(model.targets) do
    by_name[target.name] = target
  end
  return by_name
end

describe("cmake.read_model", function()
  it("lists every target with its type and definition site", function()
    local model = cmake.read_model(fixtures .. "/build")
    assert.is_truthy(model)
    assert.are.equal(3, #model.targets)

    local by_name = targets_by_name(model)
    assert.are.equal("EXECUTABLE", by_name.app.type)
    assert.are.equal("STATIC_LIBRARY", by_name.corelib.type)
    assert.are.equal("UTILITY", by_name.docs.type)

    assert.are.equal(5, by_name.app.lnum)
    assert.are.equal(4, by_name.corelib.lnum)
    assert.are.equal(8, by_name.docs.lnum)
    assert.is_truthy(by_name.app.path:match("/CMakeLists%.txt$"))
  end)

  it("returns nil when the build directory has no File API reply", function()
    assert.is_nil(cmake.read_model(fixtures .. "/no-such-build"))
  end)

  it("sorts targets by name", function()
    local model = cmake.read_model(fixtures .. "/build")
    assert.are.same(
      { "app", "corelib", "docs" },
      { model.targets[1].name, model.targets[2].name, model.targets[3].name }
    )
  end)
end)

describe("cmake.parse_codemodel", function()
  it("follows parent nodes to find a file that is only set on an ancestor", function()
    local reply = "/reply"
    local model = {
      paths = { source = "/src" },
      configurations = { { targets = { { jsonFile = "t.json" } } } },
    }
    local target = {
      name = "lib",
      type = "STATIC_LIBRARY",
      backtrace = 1,
      backtraceGraph = {
        files = { "sub/CMakeLists.txt" },
        nodes = {
          { file = 0 },
          { command = 0, line = 12, parent = 0 },
        },
      },
    }
    local parsed = cmake.parse_codemodel(model, reply, function(path)
      assert.are.equal("/reply/t.json", path)
      return target
    end)

    assert.are.equal("/src/sub/CMakeLists.txt", parsed.targets[1].path)
    assert.are.equal(12, parsed.targets[1].lnum)
  end)

  it("skips targets whose files cannot be read", function()
    local model = {
      paths = { source = "/src" },
      configurations = { { targets = { { jsonFile = "missing.json" }, { jsonFile = "ok.json" } } } },
    }
    local parsed = cmake.parse_codemodel(model, "/reply", function(path)
      if path:match("missing") then
        error("no such file")
      end
      return { name = "ok", type = "UTILITY" }
    end)
    assert.are.equal(1, #parsed.targets)
    assert.are.equal("ok", parsed.targets[1].name)
    assert.is_nil(parsed.targets[1].path)
  end)
end)

describe("cmake.parse_tests", function()
  it("reads test names from ctest's JSON output", function()
    local text = table.concat(vim.fn.readfile(fixtures .. "/ctest.json"), "\n")
    assert.are.same({ "smoke", "corelib_unit" }, cmake.parse_tests(text))
  end)

  it("reports invalid output instead of failing", function()
    local names, err = cmake.parse_tests("not json")
    assert.is_nil(names)
    assert.is_truthy(err)
  end)
end)

describe("cmake.exact_test_regex", function()
  it("anchors plain names", function()
    assert.are.equal("^smoke$", cmake.exact_test_regex("smoke"))
  end)

  it("escapes regex metacharacters", function()
    assert.are.equal("^a\\.b\\(1\\)\\+$", cmake.exact_test_regex("a.b(1)+"))
  end)
end)
