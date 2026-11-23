local cmdline = require("controlk.cmdline")

describe("cmdline.apply", function()
  it("replaces the word after the command", function()
    assert.are.equal("set tabstop", cmdline.apply("set tabst", "tabstop"))
  end)

  it("replaces a whole path that the completion repeats", function()
    assert.are.equal("e lua/controlk/", cmdline.apply("e lua/contr", "lua/controlk/"))
  end)

  it("replaces only the last field of a Lua name", function()
    assert.are.equal("lua vim.lsp", cmdline.apply("lua vim.ls", "lsp"))
    assert.are.equal(
      "lua vim.api.nvim_buf_get_lines",
      cmdline.apply("lua vim.api.nvim_buf_get_l", "nvim_buf_get_lines")
    )
    assert.are.equal("lua print(vim.fn.getcwd", cmdline.apply("lua print(vim.fn.getc", "getcwd"))
  end)

  it("appends after a trailing space", function()
    assert.are.equal("set all", cmdline.apply("set ", "all"))
  end)
end)

describe("cmdline.completions", function()
  it("offers what <Tab> would, as prompt rows", function()
    local rows = cmdline.completions("set tabst", function(line)
      return ": " .. line
    end)
    assert.are.equal(1, #rows)
    assert.are.equal("tabstop", rows[1].text)
    assert.is_true(rows[1].passthrough)
    assert.are.equal(": set tabstop", rows[1].prompt)
  end)

  it("completes Lua names", function()
    local rows = cmdline.completions("lua vim.api.nvim_buf_get_l", function(line)
      return line
    end)
    assert.are.equal("nvim_buf_get_lines", rows[1].text)
    assert.are.equal("lua vim.api.nvim_buf_get_lines", rows[1].prompt)
  end)
end)

describe("cmdline.run", function()
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

  it("notifies the output", function()
    cmdline.run("echo 1 + 1")
    assert.are.same({ { msg = "2", level = vim.log.levels.INFO } }, notified)
  end)

  it("notifies nothing when there is no output", function()
    cmdline.run("let g:controlk_cmdline_probe = 7")
    assert.are.equal(7, vim.g.controlk_cmdline_probe)
    assert.are.same({}, notified)
  end)

  it("notifies an Ex error without the call site", function()
    cmdline.run("NoSuchCommandAtAll")
    assert.are.equal(vim.log.levels.ERROR, notified[1].level)
    assert.are.equal("E492: Not an editor command: NoSuchCommandAtAll", notified[1].msg)
  end)

  it("notifies a Lua error without the stack traceback", function()
    cmdline.run('lua error("boom")')
    assert.are.equal("E5108: Lua: boom", notified[1].msg)
  end)
end)
