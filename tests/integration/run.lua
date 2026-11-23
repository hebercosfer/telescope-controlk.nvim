-- Integration harness for controlk: drives the real Telescope picker by typing into its prompt.
-- Run from the repository root:
--   SESSION=lsp    nvim --headless -u NONE \
--     --cmd "set rtp+=$PWD,$LAZY/telescope.nvim,$LAZY/plenary.nvim" \
--     -c "luafile tests/integration/run.lua"
--   SESSION=config (same command)
-- FZF=1 also loads telescope-fzf-native, as many configurations do. Put its directory on the
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
-- Normalized, and resolved once it exists: macOS keeps temporary files behind a symlink
-- (/var -> /private/var), and Windows paths come with backslashes.
local FIX = vim.fs.normalize(os.getenv("FIXTURES") or vim.fn.tempname())
local SESSION = os.getenv("SESSION") or "lsp"
local actions = require("telescope.actions")
local state = require("telescope.actions.state")
if os.getenv("FZF") == "1" then
  require("telescope").load_extension("fzf")
end

local passed, failed = 0, 0
-- Flushed at once: if Neovim dies, the last line shows how far it got.
local function say(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), " ") .. "\n")
  io.stdout:flush()
end

-- Terminal buffers whose terminal Neovim has closed (TermClose fired).
local term_closed = {}
vim.api.nvim_create_autocmd("TermClose", {
  callback = function(args)
    term_closed[args.buf] = true
  end,
})

-- Wipes the terminal buffers the CMake and shell checks opened, once Neovim has closed their
-- terminals. On Windows, deleting a terminal buffer earlier can kill Neovim: the job may have
-- exited while its output is still being read, which jobwait() does not wait for. A buffer
-- whose terminal stays open is left alone.
-- Each step is logged: if Neovim dies here, the log shows which buffer and which step.
local function wipe_terminals()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      local name = vim.api.nvim_buf_get_name(buf)
      say(("  terminal %d: waiting for TermClose  %s"):format(buf, name))
      if vim.wait(10000, function()
        return term_closed[buf] == true
      end, 50) then
        say(("  terminal %d: closed, deleting"):format(buf))
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        say(("  terminal %d: deleted"):format(buf))
      else
        say(("  terminal %d: still open, buffer kept"):format(buf))
      end
    end
  end
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
  -- An empty prompt lists the prefixes, so cutie shows its list at once (T17).
  local rows = type_text(picker, prompt, "")
  check(
    "an empty cutie prompt shows the list, with the prefixes",
    not hidden(picker.results_win) and has_tag(rows, "c") and not has_tag(rows, "fs"),
    tostring(#rows) .. " rows"
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
  close(prompt)

  -- :Telescope resume builds a new picker from the cached one; it must work the same way.
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
    local again = type_text(picker, prompt, "")
    check("after resume, an empty prompt lists the prefixes", has_tag(again, "c"))
    local resumed = type_text(picker, prompt, "b ")
    check("after resume, a prefix still switches the source", only_tag(resumed, "buffer"))
    close(prompt)
  else
    check("after resume, an empty prompt lists the prefixes", false, "resume opened nothing")
  end

  require("controlk").setup({ style = "default" })
  vim.cmd.edit(FIX .. "/proj/src/widget.h")
  require("controlk").open({ style = "cutie" })
  vim.wait(150, function()
    return false
  end, 20)
  prompt = vim.api.nvim_get_current_buf()
  picker = state.get_current_picker(prompt)
  check(
    "style=cutie for one call opens cutie",
    picker ~= nil and picker.sorting_strategy == "descending"
  )
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
  check(
    "an empty prompt lists every prefix, and only prefixes",
    has_tag(rows, "c") and has_tag(rows, "?") and not has_tag(rows, "fs")
  )
  rows = type_text(picker, prompt, "sr")
  check(
    "text that is no prefix browses the project root",
    only_tag(rows, "fs") and has_display(rows, "src/")
  )

  -- Enter on a directory goes into it, through Telescope's real select action, and keeps the
  -- prefix that was typed.
  local function enter_dir(text, dir)
    local found = type_text(picker, prompt, text)
    for _ = 1, #found do
      local entry = state.get_selected_entry()
      if entry and entry.value.text == dir then
        break
      end
      actions.move_selection_next(prompt)
    end
    actions.select_default(prompt)
    settle(picker)
    return vim.api.nvim_buf_get_lines(prompt, 0, 1, false)[1] or "", rows_of(picker)
  end
  local entered, inside = enter_dir("sr", "src/")
  check(
    "enter on a directory goes into it",
    entered == picker.prompt_prefix .. "src/" and has_display(inside, "widget.h"),
    vim.inspect(entered)
  )
  entered, inside = enter_dir("f ", "src/")
  check(
    "enter on a directory keeps the f prefix",
    entered == picker.prompt_prefix .. "f src/" and has_display(inside, "widget.h"),
    vim.inspect(entered)
  )
  rows = type_text(picker, prompt, "src/wid")
  check("a typed path narrows inside it", has_display(rows, "widget.cpp") and #rows == 2)
  rows = type_text(picker, prompt, "4")
  check("default still jumps to a line number", has_display(rows, "Line 4"))

  rows = type_text(picker, prompt, "b ")
  check("o lists only buffers", only_tag(rows, "buffer") and #rows >= 1)

  rows = type_text(picker, prompt, "l 4")
  check("l 4 jumps to line 4", #rows == 1 and has_display(rows, "Line 4"))

  rows = type_text(picker, prompt, "l 7:3")
  check("l 7:3 gives line and column", has_display(rows, "Line 7, column 3"))

  rows = type_text(picker, prompt, "p widget")
  check("p finds files by name", has_display(rows, "widget.h") and has_tag(rows, "file"))

  rows = type_text(picker, prompt, "s Widget")
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

  rows = type_text(picker, prompt, "w widget")
  check("w offers the five engines, Direct included", has_tag(rows, "web") and #rows == 5)

  rows = type_text(picker, prompt, ": Telescope")
  check(": finds Ex commands", has_display(rows, "Telescope"))

  rows = type_text(picker, prompt, "? controlk-sources")
  check(
    "? text lists :help's match first",
    has_tag(rows, "help") and rows[1].value.text == "controlk-sources",
    rows[1] and rows[1].value.text
  )
  rows = type_text(picker, prompt, "? bufgetlines")
  check("? finds a tag :help misses, by fuzzy matching", has_display(rows, "nvim_buf_get_lines()"))
  rows = type_text(picker, prompt, "h lua-guide")
  check("h is no prefix any more", not has_tag(rows, "help"))

  rows = type_text(picker, prompt, "? ")
  check("? lists the prefixes", has_tag(rows, "c") and has_display(rows, "Workspace classes"))
  check("? lists itself, as help", has_tag(rows, "?"))

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
  check("c lists only prefixes, not the default sources", not has_tag(rows, "fs") and #rows == 4)

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
  for _, text in ipairs({ "? ", ": Telescope", "w widget", "b ", "" }) do
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
  say("== LSP from a buffer with no server (origin: proj/notes.txt)")
  -- A text file in the project: clangd does not attach to it, but runs for the project. The
  -- fixture has no .git, so the project root is the current directory.
  vim.cmd.cd(FIX .. "/proj")
  picker, prompt = open_picker(FIX .. "/proj/notes.txt")
  check("clangd is not attached to the text file", #vim.lsp.get_clients({ bufnr = 0 }) == 0)
  rows = type_text(picker, prompt, "c Widget")
  check(
    "c still finds classes through the project's clangd",
    has_tag(rows, "class") and has_display(rows, "Widget")
  )
  rows = type_text(picker, prompt, ". width")
  check("the document's own symbols still need an attached server", rows[1] and rows[1].value.hint)
  close(prompt)

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
  -- libcorelib.a with GCC or Clang, corelib.lib with MSVC.
  local built = FIX
    .. "/cmake_proj/build-ninja/"
    .. (vim.fn.has("win32") == 1 and "corelib.lib" or "libcorelib.a")
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
  wipe_terminals()

  say("== Enter acts (:, ', w, !, =, r)")
  -- Opens the locator, types text, selects the first row with `tag` and presses Enter through
  -- Telescope's real select action.
  local function enter_on(origin, text, tag, row_text)
    local p, b = open_picker(origin)
    local found = type_text(p, b, text)
    for _ = 1, #found do
      local entry = state.get_selected_entry()
      if entry and entry.value.tag == tag and (not row_text or entry.value.text == row_text) then
        break
      end
      actions.move_selection_next(b)
    end
    actions.select_default(b)
    vim.wait(200, function()
      return false
    end, 20)
  end
  local origin = FIX .. "/proj/src/widget.cpp"

  vim.fn.setreg('"', "")
  enter_on(origin, "= 6*7", "lua")
  check(
    "= copies the result to the unnamed register",
    vim.fn.getreg('"') == "42",
    vim.fn.getreg('"')
  )

  local real_open = vim.ui.open
  local opened
  vim.ui.open = function(url)
    opened = url
  end
  enter_on(origin, "w neovim lua", "web", "DuckDuckGo: neovim lua")
  check(
    "w opens the engine's URL with the query encoded",
    opened ~= nil and opened:find("neovim%20lua", 1, true) ~= nil,
    opened
  )
  opened = nil
  enter_on(origin, "w neovim.io/doc", "web", "Direct: neovim.io/doc")
  vim.ui.open = real_open
  check("w Direct opens the typed address", opened == "https://neovim.io/doc", opened)

  local real_feedkeys = vim.api.nvim_feedkeys
  local fed
  vim.api.nvim_feedkeys = function(keys)
    fed = keys
  end
  enter_on(origin, ": Telescope", "cmd", "Telescope")
  vim.api.nvim_feedkeys = real_feedkeys
  check(": puts a listed command on the command line", fed == ":Telescope ", vim.inspect(fed))

  vim.g.controlk_ran = nil
  enter_on(origin, ": let g:controlk_ran = 7", "cmd")
  check(": runs what was typed from its first row", vim.g.controlk_ran == 7, vim.g.controlk_ran)

  -- T18, T19: completion rows fill the prompt; what runs is notified.
  local notify_before = vim.notify
  local notes = {}
  vim.notify = function(message, level)
    table.insert(notes, { message = message, level = level })
  end
  local function prompt_after(text, tag, row_text)
    local p, b = open_picker(origin)
    local found = type_text(p, b, text)
    for _ = 1, #found do
      local entry = state.get_selected_entry()
      if entry and entry.value.tag == tag and entry.value.text == row_text then
        break
      end
      actions.move_selection_next(b)
    end
    actions.select_default(b)
    local line = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
    close(b)
    return line:sub(#p.prompt_prefix + 1), found
  end
  local line, found = prompt_after(": set tabst", "cmd", "tabstop")
  check(": set tabst offers tabstop", has_display(found, "tabstop"))
  check("Enter on it completes the prompt", line == ": set tabstop", line)

  enter_on(origin, ": echo 6 * 7", "cmd")
  check(
    ": notifies the output of what it runs",
    notes[#notes] and notes[#notes].message == "42",
    vim.inspect(notes[#notes])
  )

  line, found = prompt_after("lua vim.api.nvim_buf_get_l", "lua", "nvim_buf_get_lines")
  check("lua completes Lua names", has_display(found, "nvim_buf_get_lines"))
  check("Enter on one completes the prompt", line == "lua vim.api.nvim_buf_get_lines", line)

  vim.g.controlk_t = nil
  enter_on(origin, "lua vim.g.controlk_t = 1", "lua")
  check("lua runs a statement", vim.g.controlk_t == 1, vim.g.controlk_t)

  notes = {}
  enter_on(origin, "lua print(6 * 7)", "lua")
  check(
    "lua notifies what print writes",
    #notes == 1 and notes[1].message == "42" and notes[1].level == vim.log.levels.INFO,
    vim.inspect(notes)
  )

  notes = {}
  enter_on(origin, "lua error('boom')", "lua")
  check(
    "lua notifies an error",
    #notes == 1
      and notes[1].message:find("^E5108: [^\n]*boom$") ~= nil
      and notes[1].level == vim.log.levels.ERROR,
    vim.inspect(notes)
  )
  vim.notify = notify_before

  vim.cmd.edit(origin)
  vim.fn.cursor(1, 1)
  -- T21: references by name. The cursor stays on line 1, on no symbol: it plays no part.
  vim.fn.cursor(1, 1)
  -- The harness started clangd for widget.h only; a real config attaches it to every C++ buffer.
  local clangd = vim.lsp.get_clients({ name = "clangd" })[1]
  if clangd then
    vim.lsp.buf_attach_client(0, clangd.id)
    vim.wait(3000, function()
      return #vim.lsp.get_clients({ bufnr = 0, name = "clangd" }) > 0
    end, 50)
  end
  local rp, rb = open_picker(origin)
  local refs = type_text(rp, rb, "r Widget")
  local files = {}
  for _, row in ipairs(refs) do
    if row.value.path then
      files[vim.fs.basename(row.value.path)] = true
    end
  end
  check(
    "r Widget lists the references to Widget, wherever the cursor is",
    only_tag(refs, "ref") and #refs >= 2 and vim.tbl_count(files) >= 2,
    ("%d rows in %s"):format(#refs, table.concat(vim.tbl_keys(files), ", "))
  )
  local none = type_text(rp, rb, "r ")
  check("r alone asks for a name", #none == 1 and none[1].value.hint == true)
  local unknown = type_text(rp, rb, "r NoSuchSymbolAnywhere")
  check(
    "r with an unknown name says so",
    #unknown == 1 and unknown[1].value.text:find("no symbol named", 1, true) ~= nil,
    unknown[1] and unknown[1].value.text
  )
  close(rb)

  vim.cmd.edit(FIX .. "/proj/src/main.cpp")
  vim.api.nvim_buf_set_mark(0, "Q", 2, 0, {})
  vim.cmd.edit(origin)
  enter_on(origin, "' Q", "mark")
  check(
    "b jumps to the mark",
    -- Normalized: on Windows the buffer name has backslashes, FIX forward slashes.
    vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == FIX .. "/proj/src/main.cpp"
      and vim.api.nvim_win_get_cursor(0)[1] == 2,
    vim.api.nvim_buf_get_name(0) .. ":" .. vim.api.nvim_win_get_cursor(0)[1]
  )

  enter_on(origin, "! echo controlk-enter", "shell")
  check("! through Enter opens a terminal", vim.bo.buftype == "terminal", vim.bo.buftype)
  wipe_terminals()

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
                if query == "none" then
                  return done({})
                end
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
  local rows = type_text(picker, prompt, "widget")
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

  say("== Enter with nothing to act on opens the help")
  -- Types text, presses Enter through Telescope's real action, and returns the help tag under
  -- the cursor, or what is open instead.
  local function help_after(text)
    local p, b = open_picker(FIX .. "/proj/src/widget.h")
    type_text(p, b, text)
    actions.select_default(b)
    vim.wait(300, function()
      return vim.bo.filetype == "help"
    end, 20)
    if vim.bo.filetype ~= "help" then
      local what = vim.bo.filetype
      if vim.api.nvim_buf_is_valid(b) then
        close(b)
      end
      return "<no help: " .. what .. ">"
    end
    local tag = vim.api.nvim_get_current_line():match("%*(controlk[^*]+)%*")
    vim.cmd.helpclose()
    return tag
  end
  local tag = help_after("C zzqqxx")
  check("an empty list opens the source's help, by id", tag == "controlk-source-lsp_classes", tag)
  tag = help_after("C ")
  check("Enter on a hint row opens the help too", tag == "controlk-source-lsp_classes", tag)
  tag = help_after("g none")
  check("a user source opens the list of sources", tag == "controlk-sources", tag)
  tag = help_after("zzqqxx")
  check("an empty default view opens its help", tag == "controlk-default-view", tag)

  say("== files: hidden")
  vim.fn.writefile({}, FIX .. "/proj/.dotnote")
  local fp, fb = open_picker(FIX .. "/proj/src/widget.h")
  check(
    "p skips hidden files by default",
    not has_display(type_text(fp, fb, "p dotnote"), ".dotnote")
  )
  close(fb)
  require("controlk").setup({ files = { hidden = true } })
  fp, fb = open_picker(FIX .. "/proj/src/widget.h")
  check("files.hidden lists them", has_display(type_text(fp, fb, "p dotnote"), ".dotnote"))
  close(fb)

  say("== a source that misbehaves (T20)")
  notices = {}
  require("controlk").setup({
    default_sources = { "files", "broken" },
    sources = {
      broken = {
        prefix = "zz",
        title = "Broken source",
        tag = "broken",
        items = function()
          error("boom")
        end,
      },
    },
  })
  fp, fb = open_picker(FIX .. "/proj/src/widget.h")
  rows = type_text(fp, fb, "widget")
  check(
    "a source that errors leaves the other default sources listed",
    has_tag(rows, "file") and has_display(rows, "widget.h"),
    tostring(#rows) .. " rows"
  )
  check("and shows a hint naming it", has_display(rows, "broken failed: boom"))
  check(
    "and notifies the error",
    #notices >= 1 and notices[#notices]:find("source broken failed", 1, true) ~= nil,
    notices[#notices]
  )
  close(fb)
  require("controlk").setup({
    prefixes = { lsp_classes = "C", eval = false },
    default_sources = { "files" },
  })

  say("== checkhealth")
  vim.cmd("checkhealth controlk")
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  check(
    ":checkhealth controlk runs and reports no error",
    report:find("controlk: Neovim and plugins", 1, true) ~= nil
      and report:find("ERROR", 1, true) == nil,
    report:match("[^\n]*ERROR[^\n]*")
  )
  check(
    "it names the running clangd",
    report:find("clangd answers workspace symbols", 1, true) ~= nil
  )
  vim.cmd.bwipeout()

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
  -- Plugin managers generate doc/tags; Enter on an empty list opens controlk's help.
  vim.cmd.helptags(vim.fn.getcwd() .. "/doc")
  if not os.getenv("FIXTURES") then
    vim.fn.mkdir(FIX, "p")
    -- In Lua, not cp: Windows has none for system().
    for name, kind in vim.fs.dir(SRC, { depth = math.huge }) do
      if kind == "directory" then
        vim.fn.mkdir(FIX .. "/" .. name, "p")
      else
        vim.fn.writefile(vim.fn.readfile(SRC .. "/" .. name, "b"), FIX .. "/" .. name, "b")
      end
    end
  end
  FIX = vim.fs.normalize(vim.uv.fs_realpath(FIX) or FIX)
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

-- An error inside a session would stop the script, and headless Neovim does not always show
-- the message (the first Windows runs lost it). Print it, count it as a failure, and go on to
-- the result line.
local ok, err = xpcall(SESSION == "lsp" and lsp_and_cmake or config_session, debug.traceback)
if not ok then
  say("ERROR in session " .. SESSION .. ": " .. tostring(err))
  failed = failed + 1
end

say(("RESULT %s: %d passed, %d failed"):format(SESSION, passed, failed))
vim.cmd(failed == 0 and "qa!" or "cquit 1")
