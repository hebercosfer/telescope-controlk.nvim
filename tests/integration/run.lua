-- Integration harness for controlk: drives the real Telescope picker by typing into its prompt.
-- Run from the repository root:
--   SESSION=lsp    nvim --headless -u NONE \
--     --cmd "set rtp+=$PWD,$LAZY/telescope.nvim,$LAZY/plenary.nvim" \
--     -c "luafile tests/integration/run.lua"
--   SESSION=config (same command)
-- FZF=1 also loads telescope-fzf-native, as the owner's config does. Put its directory on the
-- runtimepath too: --cmd "set rtp+=$LAZY/telescope-fzf-native.nvim". Without this, the picker's
-- sorter is never tested with a sorter that keeps state.
-- Needs clangd, cmake (with Ninja) and ctest on PATH. Works in a temporary copy of the
-- fixtures (FIXTURES=<dir> reuses one).
-- Fixtures are copied to a temporary directory for every run. They must not sit inside this
-- repository: its .git would become the project root of the samples. Set FIXTURES to
-- reuse a directory.
-- DEPRECATION_REPORT=<file> records deprecated calls made by Neovim or the plugins, for
-- tests/check_deprecations.lua. A deprecated call from controlk's own code fails at once.
dofile(vim.fn.getcwd() .. "/tests/support/deprecations.lua").install(
  vim.fn.getcwd(),
  os.getenv("DEPRECATION_REPORT")
)
local SRC = vim.fn.getcwd() .. "/tests/integration/fixtures"
local FIX = os.getenv("FIXTURES") or vim.fn.tempname()
local SESSION = os.getenv("SESSION") or "lsp"
local actions = require("telescope.actions")
local state = require("telescope.actions.state")
if os.getenv("FZF") == "1" then
  require("telescope").load_extension("fzf")
end

local passed, failed = 0, 0
local function say(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), " ") .. "\n")
end
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
  end
  say((cond and "PASS " or "FAIL ") .. name .. (detail and ("  -- " .. detail) or ""))
end

local function rows_of(picker)
  local rows = {}
  for entry in picker.manager:iter() do
    table.insert(rows, { display = entry.display, value = entry.value })
  end
  return rows
end

local function settle(picker)
  local last, stable = -1, 0
  vim.wait(8000, function()
    local n = 0
    for _ in picker.manager:iter() do
      n = n + 1
    end
    if n == last then
      stable = stable + 1
    else
      stable = 0
    end
    last = n
    -- Zero rows can just mean the async sources have not answered yet (CTest on a slow
    -- runner), so only rows count as settled. A query that really has no rows waits
    -- out the 8 seconds above.
    return stable >= 12 and n > 0
  end, 25)
end

local function open_picker(origin)
  if vim.api.nvim_buf_get_name(0) ~= origin then
    vim.cmd.edit(origin)
  end
  require("controlk").open({})
  local prompt = vim.api.nvim_get_current_buf()
  local picker = state.get_current_picker(prompt)
  vim.wait(150, function()
    return false
  end, 20)
  return picker, prompt
end

local function type_text(picker, prompt, text)
  vim.api.nvim_buf_set_lines(prompt, 0, -1, false, { picker.prompt_prefix .. text })
  settle(picker)
  local rows = rows_of(picker)
  local shown = {}
  for i = 1, math.min(4, #rows) do
    table.insert(shown, vim.trim(rows[i].display))
  end
  say(("  > %-16q %3d rows  %s"):format(text, #rows, table.concat(shown, " | ")))
  return rows
end

local function has_display(rows, needle)
  for _, r in ipairs(rows) do
    if r.display:find(needle, 1, true) then
      return true
    end
  end
  return false
end

local function has_tag(rows, tag)
  for _, r in ipairs(rows) do
    if r.value.tag == tag then
      return true
    end
  end
  return false
end

local function only_tag(rows, tag)
  if #rows == 0 then
    return false
  end
  for _, r in ipairs(rows) do
    if r.value.tag ~= tag then
      return false
    end
  end
  return true
end

local function close(prompt)
  actions.close(prompt)
  vim.wait(100, function()
    return false
  end, 20)
end

local function start_clangd(file)
  vim.cmd.edit(file)
  local id = vim.lsp.start({
    name = "clangd",
    cmd = { vim.fn.exepath("clangd"), "--background-index" },
    root_dir = FIX .. "/proj",
  }, { bufnr = vim.api.nvim_get_current_buf() })
  vim.wait(30000, function()
    local c = vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized
  end, 50)
  vim.wait(8000, function()
    return false
  end, 100)
end

-- ------------------------------------------------------------------ cutie style
local function cutie_checks()
  say("== cutie")
  vim.cmd.cd(FIX .. "/proj")
  local columns, lines = vim.o.columns, vim.o.lines
  vim.o.columns, vim.o.lines = 200, 50
  local function hidden(win)
    return win ~= nil and vim.api.nvim_win_get_config(win).hide == true
  end
  local function border(b)
    return b and b.winid
  end

  require("controlk").setup({ style = "cutie" })
  local picker, prompt = open_picker(FIX .. "/proj/src/widget.h")
  -- Nothing is visible yet, so the open and split keys must not act on a hidden row.
  local wins = #vim.api.nvim_tabpage_list_wins(0)
  for _, action in ipairs({ "select_default", "select_vertical", "select_horizontal" }) do
    pcall(actions[action], prompt)
    vim.wait(100, function()
      return false
    end, 20)
  end
  check(
    "keys on an empty cutie prompt act on nothing",
    vim.api.nvim_buf_is_valid(prompt)
      and vim.api.nvim_get_current_buf() == prompt
      and #vim.api.nvim_tabpage_list_wins(0) == wins,
    vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  )
  if not vim.api.nvim_buf_is_valid(prompt) or vim.api.nvim_get_current_buf() ~= prompt then
    vim.cmd("silent! only")
    picker, prompt = open_picker(FIX .. "/proj/src/widget.h")
  end
  check(
    "cutie hides the list and the preview while the prompt is empty",
    hidden(picker.results_win)
      and hidden(border(picker.results_border))
      and hidden(picker.preview_win)
      and hidden(border(picker.preview_border))
  )
  local pb = vim.api.nvim_win_get_config(border(picker.prompt_border))
  local last = vim.o.lines - vim.o.cmdheight - 2 -- the row above the status line
  check(
    "cutie's prompt is bottom-left, above the status line",
    pb.col == 0 and pb.row + pb.height - 1 == last,
    vim.inspect({ pb.row, pb.col, pb.height, last })
  )
  type_text(picker, prompt, "c W")
  check(
    "typing shows the list and the preview",
    not hidden(picker.results_win) and not hidden(picker.preview_win)
  )
  local rb = vim.api.nvim_win_get_config(border(picker.results_border))
  check("the list is cutie.width wide", rb.width == 60, tostring(rb.width))
  check(
    "the best match is next to the prompt",
    picker.sorting_strategy == "descending",
    picker.sorting_strategy
  )
  type_text(picker, prompt, "")
  check(
    "an empty prompt hides them again",
    hidden(picker.results_win) and hidden(picker.preview_win)
  )
  -- Too narrow for a preview, then wide again: Telescope drops the preview window and creates
  -- a new one, which must not appear while the prompt is empty.
  for _, width in ipairs({ 55, 200 }) do
    vim.o.columns = width
    vim.cmd("doautocmd VimResized")
    vim.wait(300, function()
      return false
    end, 20)
  end
  check(
    "a resize keeps them hidden, a new preview included",
    hidden(picker.results_win) and (picker.preview_win == nil or hidden(picker.preview_win)),
    vim.inspect({ preview = picker.preview_win })
  )
  close(prompt)

  -- :Telescope resume builds a new picker from the cached one; it must hide the same way.
  picker, prompt = open_picker(FIX .. "/proj/src/widget.h")
  type_text(picker, prompt, "c")
  close(prompt)
  require("telescope.builtin").resume()
  vim.wait(300, function()
    return false
  end, 20)
  prompt = vim.api.nvim_get_current_buf()
  picker = state.get_current_picker(prompt)
  if picker then
    type_text(picker, prompt, "")
    check(
      "after resume, an empty prompt still hides the list",
      hidden(picker.results_win) and hidden(picker.preview_win)
    )
    local resumed = type_text(picker, prompt, "o ")
    check("after resume, a prefix still switches the source", only_tag(resumed, "buffer"))
    close(prompt)
  else
    check("after resume, an empty prompt still hides the list", false, "resume opened nothing")
  end

  require("controlk").setup({ style = "default" })
  vim.cmd.edit(FIX .. "/proj/src/widget.h")
  require("controlk").open({ style = "cutie" })
  vim.wait(150, function()
    return false
  end, 20)
  prompt = vim.api.nvim_get_current_buf()
  picker = state.get_current_picker(prompt)
  check("style=cutie for one call opens cutie", picker ~= nil and hidden(picker.results_win))
  if picker then
    close(prompt)
  end
  require("controlk").setup({})
  vim.o.columns, vim.o.lines = columns, lines
end

-- ------------------------------------------------------------------ LSP + CMake
local function lsp_and_cmake()
  vim.cmd("runtime plugin/telescope.lua")
  vim.cmd.cd(FIX .. "/proj")
  start_clangd(FIX .. "/proj/src/widget.h")

  local picker, prompt = open_picker(FIX .. "/proj/src/widget.h")
  say("== default and prefixes (LSP origin: widget.h)")
  local rows = type_text(picker, prompt, "")
  check("default shows open buffers", has_tag(rows, "buffer"))
  check("default shows project files", has_tag(rows, "file"))

  rows = type_text(picker, prompt, "o ")
  check("o lists only buffers", only_tag(rows, "buffer") and #rows >= 1)

  rows = type_text(picker, prompt, "l 4")
  check("l 4 jumps to line 4", #rows == 1 and has_display(rows, "Line 4"))

  rows = type_text(picker, prompt, "l 7:3")
  check("l 7:3 gives line and column", has_display(rows, "Line 7, column 3"))

  rows = type_text(picker, prompt, "a widget")
  check("a finds files by name", has_display(rows, "widget.h") and has_tag(rows, "file"))

  rows = type_text(picker, prompt, ": Widget")
  check("colon finds workspace symbols", has_display(rows, "Widget") and has_tag(rows, "sym"))

  rows = type_text(picker, prompt, "c Widget")
  check("c lists classes only", only_tag(rows, "class") and has_display(rows, "Widget"))

  rows = type_text(picker, prompt, "m repaint")
  check("m finds the method", has_display(rows, "repaint") and only_tag(rows, "func"))

  rows = type_text(picker, prompt, "c ")
  check("c with an empty query gives a hint", #rows == 1 and rows[1].value.hint == true)

  rows = type_text(picker, prompt, ". width")
  check("dot searches the current document", has_tag(rows, "doc") and has_display(rows, "width"))

  rows = type_text(picker, prompt, "= 2*21")
  check("= evaluates Lua", has_display(rows, "42"))

  rows = type_text(picker, prompt, "r widget")
  check("r offers the four engines", has_tag(rows, "web") and #rows == 4)

  rows = type_text(picker, prompt, "t Telescope")
  check("t finds Ex commands", has_display(rows, "Telescope"))

  rows = type_text(picker, prompt, "h lua-guide")
  check("h finds help tags", has_tag(rows, "help") and #rows > 0)

  rows = type_text(picker, prompt, "? ")
  check("? lists the prefixes", has_tag(rows, "c") and has_display(rows, "Workspace classes"))
  check("? does not list itself", not has_tag(rows, "?"))

  -- Enter on a prefix goes through Telescope's real select action: the input becomes
  -- "c " and the picker stays open on the classes source.
  for _ = 1, #rows do
    local entry = state.get_selected_entry()
    if entry and entry.value.tag == "c" then
      break
    end
    actions.move_selection_next(prompt)
  end
  actions.select_default(prompt)
  settle(picker)
  local input = vim.api.nvim_buf_get_lines(prompt, 0, 1, false)[1] or ""
  check(
    "enter on a prefix puts it in the prompt",
    input == picker.prompt_prefix .. "c " and vim.api.nvim_buf_is_valid(prompt),
    vim.inspect(input)
  )
  rows = rows_of(picker)
  check("the picker then shows that source", #rows == 1 and rows[1].value.hint == true)

  rows = type_text(picker, prompt, "?")
  check("? alone lists the prefixes", has_tag(rows, "c") and has_display(rows, "Workspace classes"))

  rows = type_text(picker, prompt, "c")
  local first = {}
  for i = 1, math.min(4, #rows) do
    first[i] = rows[i].value.tag
  end
  check(
    "c suggests c, cm, cmo, ct first",
    vim.deep_equal(first, { "c", "cm", "cmo", "ct" }),
    table.concat(first, ",")
  )
  check("c still searches the default sources", has_tag(rows, "file") or has_tag(rows, "buffer"))

  rows = type_text(picker, prompt, "cmx")
  check("cmx suggests nothing", not has_tag(rows, "cm") and not has_tag(rows, "cmo"))

  -- Enter on the cm suggestion, through Telescope's real select action.
  rows = type_text(picker, prompt, "c")
  for _ = 1, #rows do
    local entry = state.get_selected_entry()
    if entry and entry.value.tag == "cm" then
      break
    end
    actions.move_selection_next(prompt)
  end
  actions.select_default(prompt)
  settle(picker)
  -- Without a suggestion row, Enter acts on a file and closes the picker.
  local open_now = vim.api.nvim_buf_is_valid(prompt)
  input = open_now and vim.api.nvim_buf_get_lines(prompt, 0, 1, false)[1] or "<picker closed>"
  check(
    "enter on a suggestion puts it in the prompt",
    input == picker.prompt_prefix .. "cm ",
    vim.inspect(input)
  )
  if open_now then
    close(prompt)
  end

  -- Rows without a file (prefixes, Ex commands, web) on a screen wide enough for the preview.
  -- Below 120 columns Telescope drops the preview window, so the rest of this harness never
  -- runs the previewer. With no path Telescope used to preview the item table itself.
  local columns = vim.o.columns
  vim.o.columns = 200
  local errors = {}
  local real_notify = vim.notify
  vim.notify = function(msg, level, ...)
    if level == vim.log.levels.ERROR then
      table.insert(errors, msg)
    end
    return real_notify(msg, level, ...)
  end
  vim.v.errmsg = ""
  -- A listed buffer with no name: a buffers row with a bufnr but no path.
  vim.cmd("enew")
  local unnamed = vim.api.nvim_get_current_buf()
  picker, prompt = open_picker(FIX .. "/proj/src/widget.h")
  check("a wide screen shows the preview", picker.previewer ~= nil and picker.preview_win ~= nil)
  for _, text in ipairs({ "? ", "t Telescope", "r widget", "o " }) do
    type_text(picker, prompt, text)
    for _ = 1, 3 do
      local ok, err = pcall(actions.move_selection_next, prompt)
      if not ok then
        table.insert(errors, err)
      end
      vim.wait(100, function()
        return false
      end, 20)
    end
  end
  check(
    "previewing rows without a file raises no error",
    vim.v.errmsg == "" and #errors == 0,
    vim.v.errmsg ~= "" and vim.v.errmsg or errors[1]
  )
  close(prompt)
  pcall(vim.api.nvim_buf_delete, unnamed, { force = true })
  vim.notify = real_notify
  vim.o.columns = columns
  picker, prompt = open_picker(FIX .. "/proj/src/widget.h")

  rows = type_text(picker, prompt, "f src/")
  check("f browses directories", has_display(rows, "widget.h"))

  close(prompt)

  -- action: jump to a class through `c`
  picker, prompt = open_picker(FIX .. "/proj/src/widget.h")
  rows = type_text(picker, prompt, "c Widget")
  close(prompt)
  local jump_target
  for _, r in ipairs(rows) do
    if r.display:find("Widget", 1, true) then
      jump_target = r.value
      break
    end
  end
  if jump_target then
    require("controlk.util").act(jump_target)
    local name = vim.api.nvim_buf_get_name(0)
    local line = vim.api.nvim_win_get_cursor(0)[1]
    check(
      "enter on a class jumps to its definition",
      name:match("widget%.h$") ~= nil and line == 12,
      ("%s:%d"):format(name, line)
    )
    check(
      "jumping within the open file keeps clangd attached",
      #vim.lsp.get_clients({ bufnr = 0 }) > 0
    )
  else
    check("enter on a class jumps to its definition", false, "no Widget row")
  end

  -- CMake, origin main.cpp in the CMake sample
  vim.cmd.cd(FIX .. "/cmake_proj")
  say("== CMake (origin: cmake_proj/src/main.cpp)")
  picker, prompt = open_picker(FIX .. "/cmake_proj/src/main.cpp")

  rows = type_text(picker, prompt, "cm ")
  check(
    "cm lists targets",
    has_display(rows, "app") and has_display(rows, "corelib") and has_display(rows, "docs")
  )
  check("cm offers reconfigure", has_display(rows, "Configure project"))
  local corelib
  for _, r in ipairs(rows) do
    if r.value.text == "corelib" then
      corelib = r.value
    end
  end

  rows = type_text(picker, prompt, "cmo ")
  local app_def
  for _, r in ipairs(rows) do
    if r.value.text == "app" then
      app_def = r.value
    end
  end
  check(
    "cmo lists definition sites",
    app_def ~= nil and app_def.path:match("CMakeLists%.txt$") ~= nil
  )
  check(
    "cmo gives the definition line",
    app_def ~= nil and app_def.lnum == 5,
    app_def and tostring(app_def.lnum)
  )

  rows = type_text(picker, prompt, "ct ")
  check(
    "ct lists tests",
    has_display(rows, "smoke")
      and has_display(rows, "corelib_unit")
      and has_display(rows, "Run all tests")
  )
  local run_all
  for _, r in ipairs(rows) do
    if r.value.text == "Run all tests" then
      run_all = r.value
    end
  end
  close(prompt)

  -- the picker resolves build-ninja here (build-mk is not configured); start from a clean state
  local built = FIX .. "/cmake_proj/build-ninja/libcorelib.a"
  os.remove(built)
  os.remove(FIX .. "/cmake_proj/build-ninja/Testing/Temporary/LastTest.log")

  if corelib then
    corelib.run(corelib)
    check("enter on a target opens a terminal buffer", vim.bo.buftype == "terminal", vim.bo.buftype)
    vim.wait(120000, function()
      return vim.fn.filereadable(built) == 1
    end, 200)
    check("enter on a target builds it", vim.fn.filereadable(built) == 1, built)
  end

  if run_all then
    run_all.run(run_all)
    local log = FIX .. "/cmake_proj/build-ninja/Testing/Temporary/LastTest.log"
    vim.wait(120000, function()
      return vim.fn.filereadable(log) == 1
    end, 200)
    check("enter on Run all tests runs ctest", vim.fn.filereadable(log) == 1, log)
    check(
      "enter on Run all tests opens a terminal buffer",
      vim.bo.buftype == "terminal",
      vim.bo.buftype
    )
  end

  -- shell source: "!" runs the command in a terminal buffer
  picker, prompt = open_picker(FIX .. "/cmake_proj/src/main.cpp")
  rows = type_text(picker, prompt, "! echo controlk-probe")
  local shell_row
  for _, r in ipairs(rows) do
    if r.value.tag == "shell" then
      shell_row = r.value
    end
  end
  close(prompt)
  check("! lists the command", shell_row ~= nil)
  if shell_row then
    shell_row.run(shell_row)
    check("! opens a terminal buffer", vim.bo.buftype == "terminal", vim.bo.buftype)
  end
  cutie_checks()
end

-- ----------------------------------------------------------- config customization
local function config_session()
  local notices = {}
  vim.notify = function(message)
    table.insert(notices, message)
  end

  vim.cmd("runtime plugin/telescope.lua")
  vim.cmd.cd(FIX .. "/proj")
  start_clangd(FIX .. "/proj/src/widget.h")

  require("telescope").setup({
    extensions = {
      controlk = {
        prefixes = { lsp_classes = "C", eval = false },
        default_sources = { "files" },
        sources = {
          echo = {
            prefix = "g",
            title = "Echo source",
            tag = "echo",
            items = function(query, ctx, done)
              -- Answers later, as a job would, to exercise the async path.
              vim.defer_fn(function()
                done({
                  { text = "echo " .. query, detail = ctx.root, passthrough = true },
                  {
                    text = "widget.h",
                    path = FIX .. "/proj/src/widget.h",
                    lnum = 1,
                    passthrough = true,
                  },
                })
              end, 10)
            end,
          },
        },
      },
    },
  })
  require("telescope").load_extension("controlk")
  check(
    "the default keymap maps <leader>k to the locator",
    (vim.fn.maparg("<leader>k", "n", false, true).rhs or ""):find("Telescope controlk", 1, true)
      ~= nil
  )

  say("== customised prefixes")
  local picker, prompt = open_picker(FIX .. "/proj/src/widget.h")
  local rows = type_text(picker, prompt, "")
  check("custom default_sources: only files", only_tag(rows, "file") and #rows > 0)
  rows = type_text(picker, prompt, "C Widget")
  check("custom prefix C reaches classes", only_tag(rows, "class") and has_display(rows, "Widget"))
  rows = type_text(picker, prompt, "c Widget")
  check("old prefix c no longer means classes", not has_tag(rows, "class"))
  rows = type_text(picker, prompt, "= 1+1")
  check("eval disabled: no lua rows", not has_tag(rows, "lua"))
  rows = type_text(picker, prompt, "g zzq")
  check(
    "a user source lists its rows under its prefix",
    only_tag(rows, "echo") and has_display(rows, "echo zzq") and #rows == 2
  )
  rows = type_text(picker, prompt, "?")
  check("? lists a user source", has_tag(rows, "g") and has_display(rows, "Echo source"))
  rows = type_text(picker, prompt, "g")
  check("a user prefix is suggested", has_tag(rows, "g") and has_display(rows, "Echo source"))
  close(prompt)

  say("== command and validation")
  vim.cmd("Telescope controlk")
  check(
    ":Telescope controlk opens the picker",
    vim.bo.filetype == "TelescopePrompt",
    vim.bo.filetype
  )
  close(vim.api.nvim_get_current_buf())

  notices = {}
  require("controlk").setup({ prefixes = { buffers = "C", lsp_classes = "C" } })
  check(
    "duplicate prefix is reported",
    #notices >= 1 and notices[1]:find("prefix 'C'", 1, true) ~= nil,
    notices[1]
  )

  say("== styles")
  -- Opens the locator with picker options, and returns the picker's layout strategy.
  local function layout_of(opts)
    if vim.api.nvim_buf_get_name(0) ~= FIX .. "/proj/src/widget.h" then
      vim.cmd.edit(FIX .. "/proj/src/widget.h")
    end
    require("controlk").open(opts or {})
    local buf = vim.api.nvim_get_current_buf()
    local p = state.get_current_picker(buf)
    local strategy = p and p.layout_strategy
    if p then
      close(buf)
    end
    return strategy
  end
  for _, case in ipairs({
    { "ivy", "bottom_pane" },
    { "vertical", "vertical" },
    { "dropdown", "center" },
    { "flex", "flex" },
  }) do
    require("controlk").setup({ style = case[1] })
    local got = layout_of()
    check(("style %s uses the %s layout"):format(case[1], case[2]), got == case[2], tostring(got))
  end
  require("controlk").setup({ style = "default" })
  local default_layout = require("telescope.config").values.layout_strategy
  check("default keeps Telescope's own layout", layout_of() == default_layout, layout_of())
  check("a per-call style wins over the config", layout_of({ style = "ivy" }) == "bottom_pane")
  check(
    "Telescope's own layout_strategy wins over style",
    layout_of({ style = "ivy", layout_strategy = "vertical" }) == "vertical"
  )
  notices = {}
  require("controlk").setup({ style = "current_buffer" })
  check(
    "a style that does not suit a locator warns",
    #notices >= 1 and notices[1]:find("does not suit a locator", 1, true) ~= nil,
    notices[1]
  )
  require("controlk").setup({})
end

-- Generated at run time (not committed): a compile database for clangd and a configured
-- CMake build directory, so the harness works from a fresh checkout.
local function prepare()
  if not os.getenv("FIXTURES") then
    vim.fn.mkdir(FIX, "p")
    vim.fn.system({ "cp", "-R", SRC .. "/.", FIX })
  end
  local proj = FIX .. "/proj"
  local db = {
    {
      directory = proj,
      file = proj .. "/src/main.cpp",
      arguments = { "clang++", "-std=c++17", "-c", "src/main.cpp" },
    },
    {
      directory = proj,
      file = proj .. "/src/widget.cpp",
      arguments = { "clang++", "-std=c++17", "-c", "src/widget.cpp" },
    },
  }
  local f = assert(io.open(proj .. "/compile_commands.json", "w"))
  f:write(vim.json.encode(db))
  f:close()

  local cm = FIX .. "/cmake_proj"
  local res = vim
    .system({ "cmake", "-S", cm, "-B", cm .. "/build-ninja", "-G", "Ninja" }, { text = true })
    :wait()
  assert(res.code == 0, "cmake configure failed: " .. (res.stderr or ""))
end

prepare()

if SESSION == "lsp" then
  lsp_and_cmake()
else
  config_session()
end

say(("RESULT %s: %d passed, %d failed"):format(SESSION, passed, failed))
vim.cmd(failed == 0 and "qa!" or "cquit 1")
