local config = require("controlk.config")

describe("config.resolve", function()
  it("is valid with no options", function()
    local cfg, errors = config.resolve(nil)
    assert.are.same({}, errors)
    assert.are.equal("buffers", cfg.prefix_map["o"])
    assert.are.equal("lsp_classes", cfg.prefix_map["c"])
    assert.are.equal("cmake_open", cfg.prefix_map["cmo"])
  end)

  it("renames a prefix and frees the old one", function()
    local cfg, errors = config.resolve({ prefixes = { lsp_classes = "C" } })
    assert.are.same({}, errors)
    assert.are.equal("lsp_classes", cfg.prefix_map["C"])
    assert.is_nil(cfg.prefix_map["c"])
  end)

  it("drops a prefix when it is set to false", function()
    local cfg, errors = config.resolve({ prefixes = { eval = false } })
    assert.are.same({}, errors)
    assert.is_nil(cfg.prefix_map["="])
  end)

  it("replaces default_sources instead of merging into it", function()
    local cfg = config.resolve({ default_sources = { "files" } })
    assert.are.same({ "files" }, cfg.default_sources)
  end)

  it("removes disabled sources from the prefixes and the defaults", function()
    local cfg, errors = config.resolve({ disabled = { "buffers" } })
    assert.are.same({}, errors)
    assert.is_nil(cfg.prefix_map["o"])
    assert.are.same({ "files", "lines" }, cfg.default_sources)
  end)

  it("reports two sources sharing a prefix and keeps one", function()
    local cfg, errors = config.resolve({ prefixes = { buffers = "c" } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find("prefix 'c'", 1, true))
    assert.is_truthy(cfg.prefix_map["c"])
  end)

  it("reports unknown sources", function()
    local _, errors = config.resolve({ prefixes = { nonsense = "n" } })
    assert.is_truthy(errors[1]:find("unknown source 'nonsense'", 1, true))
  end)

  it("reports prefixes that contain whitespace or are empty", function()
    local _, errors = config.resolve({ prefixes = { eval = "a b", shell = "" } })
    assert.are.equal(2, #errors)
  end)

  it("removes web engines set to false", function()
    local cfg =
      config.resolve({ web = { engines = { Google = false, Mine = "https://x.test/?q=%s" } } })
    assert.is_nil(cfg.web.engines.Google)
    assert.are.equal("https://x.test/?q=%s", cfg.web.engines.Mine)
    assert.is_truthy(cfg.web.engines.Wikipedia)
  end)

  it("does not modify the defaults between calls", function()
    config.resolve({ prefixes = { lsp_classes = "C" } })
    local cfg = config.resolve(nil)
    assert.are.equal("lsp_classes", cfg.prefix_map["c"])
  end)
end)

describe("config.resolve keymap", function()
  it("defaults the locator key to <C-k>", function()
    local cfg, errors = config.resolve(nil)
    assert.are.same({}, errors)
    assert.are.equal("<C-k>", cfg.keymap)
  end)

  it("accepts false to map nothing", function()
    local cfg, errors = config.resolve({ keymap = false })
    assert.are.same({}, errors)
    assert.is_false(cfg.keymap)
  end)

  it("reports a keymap that is neither a string nor false", function()
    local _, errors = config.resolve({ keymap = 5 })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find("keymap", 1, true))
  end)
end)

describe("config.resolve styles", function()
  it("defaults to the default style and cutie's sizes", function()
    local cfg, errors = config.resolve(nil)
    assert.are.same({}, errors)
    assert.are.equal("default", cfg.style)
    assert.are.same({ width = 40, height = 15, preview = true }, cfg.cutie)
  end)

  it("accepts every Telescope layout and theme, and cutie", function()
    for _, name in ipairs({
      "horizontal",
      "vertical",
      "flex",
      "center",
      "bottom_pane",
      "ivy",
      "dropdown",
      "cutie",
    }) do
      local cfg, errors = config.resolve({ style = name })
      assert.are.same({}, errors, name)
      assert.are.equal(name, cfg.style)
    end
  end)

  it("warns about styles that do not suit a locator, and keeps them", function()
    for _, name in ipairs({ "cursor", "current_buffer" }) do
      local cfg, errors = config.resolve({ style = name })
      assert.are.equal(name, cfg.style)
      assert.are.equal(1, #errors)
      assert.matches("does not suit a locator", errors[1])
    end
  end)

  it("falls back to default on an unknown style", function()
    local cfg, errors = config.resolve({ style = "fancy" })
    assert.are.equal("default", cfg.style)
    assert.are.same({ "unknown style 'fancy'; using 'default'" }, errors)
  end)

  it("accepts auto and positive integers for cutie.width, and falls back otherwise", function()
    assert.are.equal("auto", config.resolve({ cutie = { width = "auto" } }).cutie.width)
    assert.are.equal(32, config.resolve({ cutie = { width = 32 } }).cutie.width)
    for _, bad in ipairs({ 0, -3, 2.5, "wide" }) do
      local cfg, errors = config.resolve({ cutie = { width = bad } })
      assert.are.equal(40, cfg.cutie.width)
      assert.matches("invalid cutie.width", errors[1])
    end
    local cfg, errors = config.resolve({ cutie = { height = 0 } })
    assert.are.equal(15, cfg.cutie.height)
    assert.matches("invalid cutie.height", errors[1])
  end)
end)

describe("config.resolve option shapes", function()
  it("warns instead of failing when cutie is not a table", function()
    local cfg, errors = config.resolve({ cutie = false })
    assert.are.same({ width = 40, height = 15, preview = true }, cfg.cutie)
    assert.matches("invalid cutie", errors[1])
  end)

  it("warns about a layout_config that is not a table, and drops it", function()
    local cfg, errors = config.resolve({ layout_config = 5 })
    assert.is_nil(cfg.layout_config)
    assert.matches("invalid layout_config", errors[1])
  end)

  it("warns about a cutie.preview that is not a boolean", function()
    local cfg, errors = config.resolve({ cutie = { preview = "yes" } })
    assert.is_true(cfg.cutie.preview)
    assert.matches("invalid cutie.preview", errors[1])
  end)
end)
