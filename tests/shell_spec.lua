local shell = require("controlk.sources.shell")
local util = require("controlk.util")

describe("shell source", function()
  local real = util.terminal
  local got
  before_each(function()
    got = nil
    util.terminal = function(cmd, cwd)
      got = { cmd = cmd, cwd = cwd }
    end
  end)
  after_each(function()
    util.terminal = real
  end)

  it("lists nothing for an empty query", function()
    local items
    shell.items("", { root = "/proj" }, function(list)
      items = list
    end)
    assert.are.same({}, items)
  end)

  -- A string, not { shell, "-c", query }: Neovim then runs it with 'shell' and 'shellcmdflag',
  -- which is "/s /c" for cmd.exe on Windows. "-c" made cmd.exe open an interactive prompt.
  it("runs the command as a string, in the project root", function()
    local items
    shell.items("make test", { root = "/proj" }, function(list)
      items = list
    end)
    items[1].run(items[1])
    assert.are.same({ cmd = "make test", cwd = "/proj" }, got)
  end)
end)
