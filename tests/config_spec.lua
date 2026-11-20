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

  it("browses the file system and jumps to lines by default", function()
    local cfg = config.resolve(nil)
    assert.are.same({ "filesystem", "lines" }, cfg.default_sources)
  end)

  it("replaces default_sources instead of merging into it", function()
    local cfg = config.resolve({ default_sources = { "files" } })
    assert.are.same({ "files" }, cfg.default_sources)
  end)

  it("removes disabled sources from the prefixes and the defaults", function()
    local cfg, errors = config.resolve({ disabled = { "filesystem" } })
    assert.are.same({}, errors)
    assert.is_nil(cfg.prefix_map["f"])
    assert.are.same({ "lines" }, cfg.default_sources)
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
  it("defaults the locator key to <leader>k", function()
    local cfg, errors = config.resolve(nil)
    assert.are.same({}, errors)
    assert.are.equal("<leader>k", cfg.keymap)
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
    assert.are.same({ width = 60, height = 15, preview = true }, cfg.cutie)
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
      assert.are.equal(60, cfg.cutie.width)
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
    assert.are.same({ width = 60, height = 15, preview = true }, cfg.cutie)
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

describe("config.resolve with user sources", function()
  local function items(_, _, done)
    done({})
  end

  it("adds a source with its own prefix, title and tag", function()
    local cfg, errors = config.resolve({
      sources = { multigrep = { prefix = "g", title = "Multi grep", tag = "grep", items = items } },
    })
    assert.are.same({}, errors)
    assert.are.equal("multigrep", cfg.prefix_map["g"])
    local source = cfg.source_map.multigrep
    assert.are.equal("Multi grep", source.title)
    assert.are.equal("grep", source.tag)
    assert.are.equal(items, source.items)
    assert.are.equal("buffers", cfg.prefix_map["o"])
  end)

  it("defaults the title and the tag to the id", function()
    local cfg = config.resolve({ sources = { todo = { prefix = "td", items = items } } })
    assert.are.equal("todo", cfg.source_map.todo.title)
    assert.are.equal("todo", cfg.source_map.todo.tag)
  end)

  it("lets prefixes rename or drop a user source's prefix", function()
    local cfg, errors = config.resolve({
      sources = { todo = { prefix = "td", items = items } },
      prefixes = { todo = "T" },
    })
    assert.are.same({}, errors)
    assert.are.equal("todo", cfg.prefix_map["T"])
    assert.is_nil(cfg.prefix_map["td"])
    cfg = config.resolve({
      sources = { todo = { prefix = "td", items = items } },
      prefixes = { todo = false },
    })
    assert.is_nil(cfg.prefix_map["td"])
  end)

  it("accepts a user source in default_sources and disabled", function()
    local cfg, errors = config.resolve({
      sources = { todo = { items = items } },
      default_sources = { "files", "todo" },
    })
    assert.are.same({}, errors)
    assert.are.same({ "files", "todo" }, cfg.default_sources)
    cfg, errors = config.resolve({
      sources = { todo = { prefix = "td", items = items } },
      disabled = { "todo" },
    })
    assert.are.same({}, errors)
    assert.is_nil(cfg.prefix_map["td"])
  end)

  it("keeps the built-in when a user source takes its prefix", function()
    local cfg, errors = config.resolve({ sources = { aaa = { prefix = "o", items = items } } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find("keeping 'buffers'", 1, true))
    assert.are.equal("buffers", cfg.prefix_map["o"])
  end)

  it("ignores a source that reuses a built-in id", function()
    local cfg, errors = config.resolve({ sources = { files = { prefix = "F", items = items } } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find("source 'files' ignored", 1, true))
    assert.is_nil(cfg.prefix_map["F"])
    assert.are_not.equal(items, cfg.source_map.files.items)
  end)

  it("ignores sources without an items function or with a bad prefix", function()
    local cfg, errors = config.resolve({
      sources = {
        nofn = { prefix = "n1" },
        badprefix = { prefix = "x y", items = items },
        notable = "rg",
        badtitle = { title = 3, items = items },
      },
    })
    assert.are.equal(4, #errors)
    for _, id in ipairs({ "nofn", "badprefix", "notable", "badtitle" }) do
      assert.is_nil(cfg.source_map[id])
    end
    assert.is_nil(cfg.prefix_map["n1"])
  end)

  it("reports sources that is not a table", function()
    local cfg, errors = config.resolve({ sources = "nope" })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find("invalid sources", 1, true))
    assert.are.equal("buffers", cfg.prefix_map["o"])
  end)
end)

describe("config.resolve with unknown options", function()
  it("reports an unknown option", function()
    local _, errors = config.resolve({ widht = 3 })
    assert.are.same({ "unknown option 'widht'" }, errors)
  end)

  it("points a top-level cutie key at the cutie table", function()
    local cfg, errors = config.resolve({ style = "cutie", width = 20 })
    assert.are.equal(1, #errors)
    assert.matches("unknown option 'width' %(did you mean cutie = { width = ... }%?%)", errors[1])
    assert.are.equal(60, cfg.cutie.width)
  end)

  it("reports an unknown key inside a fixed option table", function()
    local _, errors = config.resolve({ cutie = { widht = 20 }, lsp = { min = 2 } })
    table.sort(errors)
    assert.are.same({ "unknown option 'cutie.widht'", "unknown option 'lsp.min'" }, errors)
  end)

  it("accepts every documented option, nil defaults included", function()
    local _, errors = config.resolve({
      keymap = false,
      style = "ivy",
      layout_config = { height = 0.4 },
      cutie = { width = "auto", height = 10, preview = false },
      prefixes = { eval = false },
      sources = {},
      default_sources = { "files" },
      disabled = {},
      lsp = { min_query = 2 },
      cmake = { build_dir = "build" },
      web = { engines = { Mine = "https://x.test/?q=%s" } },
    })
    assert.are.same({}, errors)
  end)
end)
