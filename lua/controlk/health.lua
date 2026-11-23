-- :checkhealth controlk

local M = {}

local health = vim.health

local function executable(name)
  return vim.fn.executable(name) == 1
end

local function check_neovim()
  health.start("controlk: Neovim and plugins")
  local v = vim.version()
  local version = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.10.4") == 1 then
    health.ok("Neovim " .. version)
  else
    health.error("Neovim " .. version .. ": controlk needs 0.10.4 or later")
  end
  for _, mod in ipairs({ "telescope", "plenary" }) do
    if pcall(require, mod) then
      health.ok(mod .. " is installed")
    else
      health.error(mod .. " is not installed: controlk needs it")
    end
  end
end

local function check_tools()
  health.start("controlk: external tools")
  if executable("rg") then
    health.ok("rg: lists project files (`a`)")
  elseif executable("git") then
    health.warn("rg not found: `a` falls back to `git ls-files`, which works in git repos only")
  else
    health.error("neither rg nor git found: `a` (files in project) lists nothing")
  end
  local missing = {}
  for _, tool in ipairs({ "cmake", "ctest" }) do
    if executable(tool) then
      health.ok(tool .. ": CMake sources (`cm`, `cmo`, `ct`)")
    else
      table.insert(missing, tool)
    end
  end
  if #missing > 0 then
    health.warn(
      table.concat(missing, " and ") .. " not found: the CMake sources need them",
      { "Only needed for CMake projects." }
    )
  end
end

local function check_config()
  health.start("controlk: configuration")
  local errors = require("controlk").errors()
  if #errors == 0 then
    health.ok("no problems in the controlk options")
  end
  for _, message in ipairs(errors) do
    health.warn(message)
  end
  local cfg = require("controlk").config()
  if cfg.keymap then
    local map = vim.fn.maparg(cfg.keymap, "n", false, true)
    if (map.rhs or ""):find("Telescope controlk", 1, true) then
      health.ok(("%s opens the locator"):format(cfg.keymap))
    elseif map.lhs then
      health.info(("%s is mapped to something else, so controlk left it alone"):format(cfg.keymap))
    else
      health.info(
        ("%s is not mapped yet: it is mapped when the extension loads"):format(cfg.keymap)
      )
    end
  end
end

--- Where clangd will find compile_commands.json for a project, if anywhere: in the project
--- root, or in a build/ directory under it (clangd's own search, upward from each file).
---@param root string
---@return string|nil path
function M.clangd_database(root)
  local candidates = { root .. "/compile_commands.json", root .. "/build/compile_commands.json" }
  for _, path in ipairs(candidates) do
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

--- The compile_commands.json files in the build directories under the CMake root, absolute.
---@param root string
---@return string[]
function M.other_databases(root)
  local found = {}
  for _, dir in ipairs(require("controlk.cmake").build_dirs(root)) do
    local path = vim.fs.normalize(vim.fn.fnamemodify(dir .. "/compile_commands.json", ":p"))
    if vim.uv.fs_stat(path) then
      table.insert(found, path)
    end
  end
  return found
end

local function check_project()
  local util = require("controlk.util")
  local buf = vim.api.nvim_get_current_buf()
  local root = util.project_root(buf)
  health.start("controlk: this project (" .. vim.fn.fnamemodify(root, ":~") .. ")")

  local cmake_root = require("controlk.cmake").find_root(util.buffer_dir(buf))
  local database = M.clangd_database(root)
  if database then
    health.ok("clangd finds " .. vim.fn.fnamemodify(database, ":~:."))
  elseif cmake_root then
    local others = M.other_databases(cmake_root)
    if #others > 0 then
      health.warn(
        "compile_commands.json is in "
          .. vim.fn.fnamemodify(others[1], ":~:.")
          .. ", where clangd does not look",
        {
          "Add --compile-commands-dir=" .. vim.fs.dirname(others[1]) .. " to clangd's command",
          "or link it into the project root: ln -s "
            .. others[1]
            .. " "
            .. root
            .. "/compile_commands.json",
        }
      )
    else
      health.warn("no compile_commands.json: clangd sees only the open files and their headers", {
        "Configure with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON;"
          .. ' the "Configure project" item of `cm` does.',
        "See :h controlk-lsp",
      })
    end
  else
    health.info("no compile_commands.json and no CMakeLists.txt: not a C/C++ build, skipped")
  end

  local clients = require("controlk.sources.lsp").clients_for(
    { origin_buf = buf, root = root },
    "workspace/symbol"
  )
  if #clients == 0 then
    health.info(
      "no language server with workspace symbols is running for this project: "
        .. "`:`, `c` and `m` need one (open a source file to start it)"
    )
  end
  for _, client in ipairs(clients) do
    local indexing = #require("controlk.sources.lsp").status_hints({ client }, {}, "") > 0
    health.ok(
      ("%s answers workspace symbols%s"):format(
        client.name,
        indexing and " (still indexing: results are partial until it finishes)" or ""
      )
    )
  end
end

function M.check()
  check_neovim()
  check_tools()
  check_config()
  check_project()
end

return M
