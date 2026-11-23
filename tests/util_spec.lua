local util = require("controlk.util")

describe("util.memo", function()
  it("runs compute once and shares the value with every caller", function()
    local ctx = { cache = {} }
    local calls = 0
    local compute = function(finish)
      calls = calls + 1
      finish({ "a", "b" })
    end

    local seen = {}
    util.memo(ctx, "key", compute, function(value)
      table.insert(seen, value)
    end)
    util.memo(ctx, "key", compute, function(value)
      table.insert(seen, value)
    end)

    assert.are.equal(1, calls)
    assert.are.equal(2, #seen)
    assert.are.same({ "a", "b" }, seen[2])
  end)

  it("makes callers that arrive while computing wait for the same result", function()
    local ctx = { cache = {} }
    local pending_finish
    local compute = function(finish)
      pending_finish = finish
    end

    local seen = {}
    util.memo(ctx, "slow", compute, function(value)
      table.insert(seen, "first:" .. value)
    end)
    util.memo(ctx, "slow", compute, function(value)
      table.insert(seen, "second:" .. value)
    end)
    assert.are.equal(0, #seen)

    pending_finish("done")
    assert.are.same({ "first:done", "second:done" }, seen)
  end)

  it("keeps different keys apart", function()
    local ctx = { cache = {} }
    local got = {}
    util.memo(ctx, "one", function(finish)
      finish(1)
    end, function(value)
      got.one = value
    end)
    util.memo(ctx, "two", function(finish)
      finish(2)
    end, function(value)
      got.two = value
    end)
    assert.are.same({ one = 1, two = 2 }, got)
  end)
end)

describe("util.hint", function()
  it("builds a non-actionable passthrough item", function()
    local item = util.hint("type more", "sym")
    assert.is_true(item.hint)
    assert.is_true(item.passthrough)
    assert.are.equal("sym", item.tag)
  end)
end)

describe("util.help_tag", function()
  it("names the section of a built-in source", function()
    assert.are.equal("controlk-source-lsp_classes", util.help_tag("lsp_classes"))
    assert.are.equal("controlk-source-filesystem", util.help_tag("filesystem"))
  end)

  it("names the default view when no prefix is typed", function()
    assert.are.equal("controlk-default-view", util.help_tag(nil))
  end)

  it("falls back to the list of sources for a source with no section", function()
    assert.are.equal("controlk-sources", util.help_tag("multigrep"))
  end)

  it("has a section for every built-in source", function()
    for id in pairs(require("controlk.sources").by_id) do
      assert.are.equal("controlk-source-" .. id, util.help_tag(id))
    end
  end)
end)

describe("util.is_absolute", function()
  it("knows Unix and Windows absolute paths", function()
    assert.is_true(util.is_absolute("/etc/hosts"))
    assert.is_true(util.is_absolute("C:/Users/me"))
    assert.is_true(util.is_absolute("c:\\Users\\me"))
    assert.is_true(util.is_absolute("\\\\server\\share"))
    assert.is_false(util.is_absolute("src/main.cpp"))
    assert.is_false(util.is_absolute("~/notes"))
    assert.is_false(util.is_absolute("C:relative"))
  end)
end)

describe("util.call_source", function()
  local notified
  local notify = vim.notify
  before_each(function()
    notified = {}
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
  end)
  after_each(function()
    vim.notify = notify
  end)

  it("passes a source's items on, tagged", function()
    local got
    local source = {
      id = "good",
      tag = "g",
      items = function(_, _, done)
        done({ { text = "a" } })
      end,
    }
    util.call_source(source, "", {}, function(items)
      got = items
    end)
    assert.are.same({ { text = "a", tag = "g" } }, got)
  end)

  it("turns an error into a hint naming the source, and notifies it", function()
    local got
    local source = {
      id = "broken",
      tag = "b",
      items = function()
        error("boom")
      end,
    }
    util.call_source(source, "", {}, function(items)
      got = items
    end)
    assert.are.equal(1, #got)
    assert.is_true(got[1].hint)
    assert.truthy(got[1].text:find("broken", 1, true))
    assert.truthy(got[1].text:find("boom", 1, true))
    assert.are.equal(1, #notified)
    assert.are.equal(vim.log.levels.ERROR, notified[1].level)
    assert.truthy(notified[1].msg:find("broken", 1, true))
  end)

  it("honours only the first answer", function()
    local calls = 0
    local source = {
      id = "twice",
      items = function(_, _, done)
        done({ { text = "first" } })
        done({ { text = "second" } })
      end,
    }
    local got
    util.call_source(source, "", {}, function(items)
      calls = calls + 1
      got = items
    end)
    assert.are.equal(1, calls)
    assert.are.equal("first", got[1].text)
  end)

  it("treats a nil answer as no items", function()
    local got
    local source = {
      id = "nil",
      items = function(_, _, done)
        done(nil)
      end,
    }
    util.call_source(source, "", {}, function(items)
      got = items
    end)
    assert.are.same({}, got)
  end)

  it("gives up on a source that never answers, after the timeout", function()
    local got
    local source = {
      id = "silent",
      items = function() end,
    }
    util.call_source(source, "", {}, function(items)
      got = items
    end, 20)
    assert.is_nil(got)
    vim.wait(500, function()
      return got ~= nil
    end)
    assert.is_true(got[1].hint)
    assert.truthy(got[1].text:find("silent", 1, true))
  end)
end)

describe("util.collect", function()
  local notify = vim.notify
  before_each(function()
    vim.notify = function() end
  end)
  after_each(function()
    vim.notify = notify
  end)

  local function source(id, behaviour)
    return { id = id, tag = id, items = behaviour }
  end

  it("keeps the sources' order, whatever order they answer in", function()
    local later
    local sources = {
      source("slow", function(_, _, done)
        later = done
      end),
      source("fast", function(_, _, done)
        done({ { text = "f" } })
      end),
    }
    local got
    util.collect(sources, "", {}, function(items)
      got = items
    end)
    assert.is_nil(got)
    later({ { text = "s" } })
    assert.are.same({ "s", "f" }, {
      got[1].text,
      got[2].text,
    })
  end)

  it("still lists the others when one source errors, answers twice or never answers", function()
    local sources = {
      source("good", function(_, _, done)
        done({ { text = "ok" } })
      end),
      source("broken", function()
        error("boom")
      end),
      source("twice", function(_, _, done)
        done({ { text = "1" } })
        done({ { text = "2" } })
      end),
      source("silent", function() end),
    }
    local got, calls = nil, 0
    util.collect(sources, "", {}, function(items)
      calls = calls + 1
      got = items
    end, 20)
    vim.wait(500, function()
      return got ~= nil
    end)
    assert.are.equal(1, calls)
    local texts = vim.tbl_map(function(item)
      return item.text
    end, got)
    assert.are.equal("ok", texts[1])
    assert.truthy(texts[2]:find("broken", 1, true))
    assert.are.equal("1", texts[3])
    assert.truthy(texts[4]:find("silent", 1, true))
    assert.are.equal(4, #got)
  end)

  it("answers at once with no sources", function()
    local got
    util.collect({}, "", {}, function(items)
      got = items
    end)
    assert.are.same({}, got)
  end)
end)

describe("util.act", function()
  -- The home directory comes from HOME, and on Windows from USERPROFILE.
  local home_before, profile_before = vim.env.HOME, vim.env.USERPROFILE
  local home
  before_each(function()
    home = vim.fn.tempname()
    vim.fn.mkdir(home, "p")
    vim.env.HOME = home
    vim.env.USERPROFILE = home
    vim.fn.writefile({ "one", "two", "three" }, home .. "/notes.txt")
  end)
  after_each(function()
    vim.env.HOME = home_before
    vim.env.USERPROFILE = profile_before
    vim.fn.delete(home, "rf")
  end)

  -- getmarklist() gives a global mark's file as "~/...", for any file under the home directory.
  it("opens a path written from the home directory", function()
    util.act({ path = "~/notes.txt", lnum = 2, col = 1 })
    -- Real paths: on macOS the temporary directory /var/... is a link to /private/var/...
    assert.are.equal(
      vim.uv.fs_realpath(home .. "/notes.txt"),
      vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0))
    )
    assert.are.equal(3, vim.api.nvim_buf_line_count(0))
    assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
  end)
end)
