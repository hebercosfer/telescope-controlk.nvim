-- The Telescope adapter. Everything Telescope-specific lives in this file.

local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")

local cmake = require("controlk.cmake")
local config = require("controlk.config")
local cutie = require("controlk.cutie")
local parse = require("controlk.parse")
local prefixes = require("controlk.sources.prefixes")
local util = require("controlk.util")

local M = {}

-- Pseudo source used when no prefix is typed: the default_sources merged.
local DEFAULT = "default"

local function make_entry(item)
  local text = item.text or ""
  local display = ("%-8s %s"):format(item.tag or "", text)
  if item.detail and item.detail ~= "" then
    display = display .. "  " .. item.detail
  end
  return {
    value = item,
    display = display,
    ordinal = item.ordinal or (text .. " " .. (item.detail or "")),
    filename = item.path,
    -- Telescope previews entry.path, then entry.filename, then entry.value. A row with no file
    -- (prefixes, commands, web...) would hand it the item table, which fails in path_expand.
    -- An empty path is what its previewers treat as "nothing to preview". A buffer without a
    -- name gets "[No Name]", as Telescope's own buffer picker does: its previewer then shows
    -- the buffer's lines (master) or nothing (v0.1.9), never an error.
    path = item.path or (item.bufnr ~= nil and "[No Name]" or ""),
    lnum = item.lnum,
    col = item.col,
  }
end

-- Items marked passthrough were already filtered by their source (the LSP
-- server, a shell, a URL...), so fuzzy matching must not drop them. They keep
-- the order the source produced.
--
-- The fuzzy sorter is a sorter of its own, with its own state. Telescope only
-- runs the lifecycle (init, start, finish, destroy) of the sorter the picker
-- holds, so pass it on. fzf-native keeps its state in init, and without it
-- every finder call fails.
local function make_sorter(opts)
  local fuzzy = conf.generic_sorter(opts)
  return sorters.Sorter:new({
    init = function()
      fuzzy:_init()
    end,
    start = function(_, prompt)
      fuzzy:_start(prompt)
    end,
    finish = function(_, prompt)
      fuzzy:_finish(prompt)
    end,
    destroy = function()
      fuzzy:_destroy()
    end,
    scoring_function = function(_, prompt, line, entry)
      local item = entry.value
      -- Telescope ranks lower scores first. Pinned rows (prefix suggestions) score below any
      -- fuzzy match, in their own order.
      if item and item.pinned then
        return (entry.index or 1) * 1e-6
      end
      if item and item.passthrough then
        return entry.index or 1
      end
      return fuzzy:scoring_function(prompt, line, entry)
    end,
  })
end

local function run_default(query, ctx, done)
  -- A partly typed prefix ("c") lists the prefixes it could become before the usual results.
  local collected = prefixes.matching(query, ctx.config.prefix_map, ctx.config.source_map)
  local function step(index)
    local id = ctx.config.default_sources[index]
    if not id then
      return done(collected)
    end
    local source = ctx.config.source_map[id]
    source.items(query, ctx, function(items)
      vim.list_extend(collected, util.tag_items(items, source.tag))
      step(index + 1)
    end)
  end
  step(1)
end

local function finder_for(id, ctx)
  local items
  if id == DEFAULT then
    items = function(query, done)
      run_default(query, ctx, done)
    end
  else
    local source = ctx.config.source_map[id]
    items = function(query, done)
      source.items(query, ctx, function(list)
        done(util.tag_items(list, source.tag))
      end)
    end
  end

  return finders.new_dynamic({
    fn = function(query)
      return util.await(function(done)
        items(query, done)
      end)
    end,
    entry_maker = make_entry,
  })
end

-- The cutie layout: window positions from cutie.geometry, given to Telescope as the picker's
-- get_window_options. A box is 0-based and includes the border; Telescope wants the content's
-- 1-based line and column.
local function cutie_window_options(cfg)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    table.insert(wins, {
      col = vim.api.nvim_win_get_position(win)[2],
      width = vim.api.nvim_win_get_width(win),
      floating = vim.api.nvim_win_get_config(win).relative ~= "",
    })
  end
  -- Measured once, when the locator opens: its own windows must not count as a sidebar.
  local width = cutie.resolve_width(cfg.cutie.width, wins, vim.o.columns)

  return function(picker)
    local g = cutie.geometry({
      columns = vim.o.columns,
      lines = vim.o.lines,
      cmdheight = vim.o.cmdheight,
      laststatus = vim.o.laststatus,
    }, { width = width, height = cfg.cutie.height, preview = cfg.cutie.preview })
    local initial = require("telescope.pickers.window").get_initial_window_options(picker)
    local function place(win, box)
      win.line, win.col = box.row + 2, box.col + 2
      win.width, win.height = box.width - 2, box.height - 2
      return win
    end
    return {
      prompt = place(initial.prompt, g.prompt),
      results = place(initial.results, g.results),
      preview = picker.previewer and g.preview and place(initial.preview, g.preview) or false,
    }
  end
end

-- Hides or shows cutie's list and preview, borders included. The prompt always stays.
local function set_cutie_hidden(picker, hidden)
  for _, win in ipairs({
    picker.results_win,
    picker.results_border and picker.results_border.winid,
    picker.preview_win,
    picker.preview_border and picker.preview_border.winid,
  }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, { hide = hidden })
    end
  end
end

-- Sets up cutie for one prompt buffer: the list and preview hidden while the prompt is empty,
-- also after a resize. Runs for every find, so a picker rebuilt by :Telescope resume gets it.
local function attach_cutie(prompt_bufnr)
  local function current()
    local p = action_state.get_current_picker(prompt_bufnr)
    if p and vim.api.nvim_win_is_valid(p.prompt_win) then
      return p
    end
  end
  local p = current()
  if p then
    set_cutie_hidden(p, p:_get_prompt() == "")
  end
  -- Telescope's own VimResized handler re-sets every window, and a preview it drops and brings
  -- back is a new, visible window. Ours runs after it and hides them again.
  local group = vim.api.nvim_create_augroup("controlk_cutie_" .. prompt_bufnr, {})
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      vim.schedule(function()
        local live = current()
        if live then
          set_cutie_hidden(live, live:_get_prompt() == "")
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = prompt_bufnr,
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })
end

-- Applies the style to the picker options. Telescope's own layout_strategy (or a theme= on the
-- command line, which sets one) wins: it is what Telescope users already type.
---@return table opts
---@return string style
local function apply_style(opts, cfg)
  local style, message = config.check_style(opts.style or cfg.style)
  if opts.style and message then
    -- The config's own warnings were shown by setup; only a per-call style is new here.
    vim.notify("controlk: " .. message, vim.log.levels.WARN)
  end
  opts.style = nil
  if opts.layout_strategy then
    return opts, style
  end
  if cfg.layout_config then
    opts.layout_config =
      vim.tbl_deep_extend("force", vim.deepcopy(cfg.layout_config), opts.layout_config or {})
  end
  local kind = config.STYLES[style]
  if kind == "cutie" then
    opts.sorting_strategy = "descending"
    opts.get_window_options = cutie_window_options(cfg)
  elseif kind == "layout" then
    opts.layout_strategy = style
  elseif kind == "theme" then
    opts = require("telescope.themes")["get_" .. style](opts)
  end
  return opts, style
end

---@param opts table telescope picker options
---@param cfg table resolved controlk configuration
function M.open(opts, cfg)
  local style
  opts, style = apply_style(opts, cfg)
  local is_cutie = style == "cutie" and opts.get_window_options ~= nil
  local origin_buf = vim.api.nvim_get_current_buf()
  local ctx = {
    config = cfg,
    origin_buf = origin_buf,
    origin_win = vim.api.nvim_get_current_win(),
    root = util.project_root(origin_buf),
    cmake_root = cmake.find_root(util.buffer_dir(origin_buf)),
    cache = {},
  }

  local current = DEFAULT
  -- The prompt buffer of the picker on screen. :Telescope resume builds a new picker from this
  -- one's options, so the callbacks look it up instead of holding the first picker.
  local live_prompt
  local function cutie_empty(prompt_bufnr)
    if not is_cutie then
      return false
    end
    local p = action_state.get_current_picker(prompt_bufnr)
    return p ~= nil and p:_get_prompt() == ""
  end

  local function on_input(prompt)
    local live = is_cutie and live_prompt and action_state.get_current_picker(live_prompt)
    if live then
      set_cutie_hidden(live, prompt == "")
    end
    local id, query = parse.parse(prompt, cfg.prefix_map)
    id = id or DEFAULT
    local result = { prompt = query }
    if id ~= current then
      current = id
      result.updated_finder = finder_for(id, ctx)
    end
    return result
  end

  local picker = pickers.new(opts, {
    prompt_title = "Locator",
    finder = finder_for(DEFAULT, ctx),
    sorter = make_sorter(opts),
    previewer = conf.grep_previewer(opts),
    on_input_filter_cb = on_input,
    attach_mappings = function(bufnr)
      if is_cutie then
        live_prompt = bufnr
        -- After find has registered the picker for this buffer.
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            attach_cutie(bufnr)
          end
        end)
        -- With an empty cutie prompt nothing is visible, so the open and split keys act on
        -- nothing rather than on a hidden row.
        for _, name in ipairs({ "select_horizontal", "select_vertical", "select_tab" }) do
          actions[name]:replace_if(cutie_empty, function() end)
        end
      end
      actions.select_default:replace(function(prompt_bufnr)
        if cutie_empty(prompt_bufnr) then
          return
        end
        local entry = action_state.get_selected_entry()
        -- An item with a prompt (the ? list) rewrites the input and keeps the picker open.
        -- on_input_filter_cb then switches to the source that prompt selects.
        if entry and entry.value.prompt then
          action_state.get_current_picker(prompt_bufnr):set_prompt(entry.value.prompt)
          return
        end
        -- An item with a query (a directory in f) replaces the text after the prefix, so the
        -- same source lists the new query: "f lua/" becomes "f lua/controlk/".
        if entry and entry.value.query then
          local p = action_state.get_current_picker(prompt_bufnr)
          -- The prompt as typed: action_state.get_current_line() holds it after
          -- on_input_filter_cb, without the prefix.
          local line = vim.api.nvim_buf_get_lines(prompt_bufnr, 0, 1, false)[1] or ""
          local _, _, prefix = parse.parse(line:sub(#p.prompt_prefix + 1), cfg.prefix_map)
          p:set_prompt((prefix and (prefix .. " ") or "") .. entry.value.query)
          return
        end
        actions.close(prompt_bufnr)
        if entry then
          util.act(entry.value)
        end
      end)
      return true
    end,
  })
  -- :Telescope resume rebuilds the picker from this one, but reads on_input_filter_cb while
  -- Telescope keeps it as _on_input_filter_cb. Without the public key a resumed locator
  -- would stop switching sources when a prefix is typed.
  picker.on_input_filter_cb = on_input
  picker:find()
  if is_cutie then
    -- At once, so the list never flashes on open; attach_cutie repeats it after find.
    set_cutie_hidden(picker, true)
  end
end

return M
