-- CMake support without a generator-specific parser: targets and their
-- definition sites come from CMake's File API (codemodel v2), and tests come
-- from `ctest --show-only=json-v1`. Works with Makefiles, Ninja and the rest.

local util = require("controlk.util")

local M = {}

---@param path string
---@return any decoded JSON
local function read_json(path)
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end
M.read_json = read_json

--- Follow a backtrace node (and its parents) to the file and line that defined an entity.
local function backtrace_location(graph, index, source)
  if not graph or not graph.nodes or index == nil then
    return nil, nil
  end
  local file, line
  local node_index = index
  for _ = 1, 64 do
    local node = graph.nodes[node_index + 1]
    if not node then
      break
    end
    line = line or node.line
    if file == nil and node.file ~= nil then
      file = graph.files[node.file + 1]
    end
    if file and line then
      break
    end
    node_index = node.parent
    if node_index == nil then
      break
    end
  end
  if not file then
    return nil, nil
  end
  if file:sub(1, 1) ~= "/" then
    file = source .. "/" .. file
  end
  return file, line
end

---@class controlk.CodeModel
---@field source string
---@field targets { name: string, type: string, path: string|nil, lnum: integer|nil }[]

--- Turn a codemodel-v2 document (plus its per-target files) into a flat target list.
---@param model table decoded codemodel-v2 JSON
---@param reply_dir string directory holding the reply files
---@param read? fun(path: string): any|nil reader, injectable for tests
---@return controlk.CodeModel
function M.parse_codemodel(model, reply_dir, read)
  read = read or read_json
  local source = model.paths and model.paths.source or ""
  local configuration = model.configurations and model.configurations[1] or {}

  local targets = {}
  for _, ref in ipairs(configuration.targets or {}) do
    local ok, target = pcall(read, reply_dir .. "/" .. ref.jsonFile)
    if ok and type(target) == "table" then
      local path, lnum = backtrace_location(target.backtraceGraph, target.backtrace, source)
      table.insert(targets, { name = target.name, type = target.type, path = path, lnum = lnum })
    end
  end
  table.sort(targets, function(a, b)
    return a.name < b.name
  end)
  return { source = source, targets = targets }
end

--- Read the latest codemodel-v2 reply of a configured build directory.
---@param build_dir string
---@return table|nil model nil when the project was never configured with the query file
function M.read_model(build_dir)
  local reply = build_dir .. "/.cmake/api/v1/reply"
  local indexes = vim.fn.glob(reply .. "/index-*.json", false, true)
  if #indexes == 0 then
    return nil
  end
  table.sort(indexes)

  local ok, index = pcall(read_json, indexes[#indexes])
  local entry = ok and index.reply and index.reply["codemodel-v2"]
  if not entry then
    return nil
  end
  local ok_model, model = pcall(read_json, reply .. "/" .. entry.jsonFile)
  if not ok_model then
    return nil
  end
  return M.parse_codemodel(model, reply)
end

--- Nearest directory at or above `dir` that holds a CMakeLists.txt. Prefers the
--- nearest one that already has a configured build directory.
---@param dir string
---@return string|nil
function M.find_root(dir)
  local roots = {}
  for _, file in
    ipairs(
      vim.fs.find("CMakeLists.txt", { upward = true, path = dir, limit = math.huge, type = "file" })
    )
  do
    table.insert(roots, vim.fs.dirname(file))
  end
  for _, root in ipairs(roots) do
    if #M.build_dirs(root) > 0 then
      return root
    end
  end
  return roots[1]
end

-- The names of the directories in `dir` (symbolic links to directories included).
local function subdirs(dir)
  local names = {}
  local handle = vim.uv.fs_scandir(dir)
  while handle do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if kind == "link" then
      local stat = vim.uv.fs_stat(dir .. "/" .. name)
      kind = stat and stat.type
    end
    if kind == "directory" then
      table.insert(names, name)
    end
  end
  return names
end

---@param root string
---@return string[] directories holding a CMakeCache.txt, sorted
function M.build_dirs(root)
  -- Listed with fs_scandir, not glob(): on Windows, with Neovim 0.10 and 0.11, glob() finds
  -- nothing under a root such as C:\Users\RUNNER~1\... (backslashes, an 8.3 name).
  local found = {}
  local function add(dir)
    if vim.uv.fs_stat(dir .. "/CMakeCache.txt") then
      table.insert(found, dir)
    end
  end
  for _, name in ipairs(subdirs(root)) do
    -- build*, build/*, cmake-build-*
    if name:find("^build") or name:find("^cmake%-build%-") then
      add(root .. "/" .. name)
    end
    if name == "build" then
      for _, sub in ipairs(subdirs(root .. "/build")) do
        add(root .. "/build/" .. sub)
      end
    end
  end
  table.sort(found)
  return found
end

---@param root string
---@param configured string|nil cfg.cmake.build_dir
---@return string|nil
function M.resolve_build_dir(root, configured)
  if configured then
    local dir = require("controlk.util").is_absolute(configured) and configured
      or (root .. "/" .. configured)
    return vim.fs.normalize(dir)
  end
  return M.build_dirs(root)[1]
end

--- The configure command. It also writes compile_commands.json, which clangd needs to index the
--- whole project; without it the workspace symbol sources only see the files that are open.
---@param root string
---@param build_dir string
---@return string[]
function M.configure_command(root, build_dir)
  return { "cmake", "-S", root, "-B", build_dir, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" }
end

--- Run the configure command after writing the File API query, then call done(ok, stderr).
function M.configure(root, build_dir, done)
  local query = build_dir .. "/.cmake/api/v1/query"
  vim.fn.mkdir(query, "p")
  vim.fn.writefile({}, query .. "/codemodel-v2")
  vim.system(M.configure_command(root, build_dir), { text = true }, function(res)
    -- Runs in a fast event, but the caller reads the model with vim.fn: hop back to the main loop.
    vim.schedule(function()
      done(res.code == 0, res.stderr)
    end)
  end)
end

--- Load the CMake model for the session, configuring first when needed.
--- Calls done(state) where state is { model, build_dir, root } or { error, ... }.
---@param ctx table
---@param done fun(state: table)
function M.load_model(ctx, done)
  util.memo(ctx, "cmake_model", function(finish)
    local root = ctx.cmake_root
    if not root then
      return finish({ error = "No CMakeLists.txt above this buffer" })
    end
    if vim.fn.executable("cmake") ~= 1 then
      return finish({ error = "cmake is not installed or not on PATH", root = root })
    end

    local build_dir = M.resolve_build_dir(root, ctx.config.cmake.build_dir)
    if not build_dir then
      return finish({
        error = "No configured build directory found",
        root = root,
        build_dir = root .. "/build",
        configure = true,
      })
    end

    local model = M.read_model(build_dir)
    if model then
      return finish({ model = model, build_dir = build_dir, root = root })
    end

    M.configure(root, build_dir, function(ok, stderr)
      if not ok then
        return finish({
          error = "CMake configure failed: " .. vim.trim(stderr or ""),
          root = root,
          build_dir = build_dir,
        })
      end
      local configured = M.read_model(build_dir)
      if not configured then
        return finish({
          error = "configure produced no CMake model",
          root = root,
          build_dir = build_dir,
        })
      end
      finish({ model = configured, build_dir = build_dir, root = root })
    end)
  end, done)
end

--- Test names from the output of `ctest --show-only=json-v1`.
---@param text string
---@return string[]|nil names
---@return string|nil err
function M.parse_tests(text)
  local ok, data = pcall(vim.json.decode, text or "")
  if not ok or type(data) ~= "table" then
    return nil, "could not parse ctest output"
  end
  local names = {}
  for _, test in ipairs(data.tests or {}) do
    table.insert(names, test.name)
  end
  return names
end

--- List CTest tests of a build directory.
---@param build_dir string
---@param done fun(names: string[]|nil, err: string|nil)
function M.list_tests(build_dir, done)
  vim.system(
    { "ctest", "--test-dir", build_dir, "--show-only=json-v1" },
    { text = true },
    function(res)
      if res.code ~= 0 then
        return done(nil, vim.trim(res.stderr or "ctest failed"))
      end
      done(M.parse_tests(res.stdout))
    end
  )
end

--- Escape a test name for ctest's -R regular expression, anchored to the whole name.
---@param name string
---@return string
function M.exact_test_regex(name)
  return "^" .. name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "\\%1") .. "$"
end

return M
