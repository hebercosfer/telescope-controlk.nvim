-- The Telescope adapter. Everything Telescope-specific lives in this file.

local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")

local cmake = require("controlk.cmake")
local parse = require("controlk.parse")
local registry = require("controlk.sources")
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
    -- An empty path is what its previewers treat as "nothing to preview".
    path = item.path or (item.bufnr == nil and "" or nil),
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
      if item and item.passthrough then
        return entry.index or 1
      end
      return fuzzy:scoring_function(prompt, line, entry)
    end,
  })
end

local function run_default(query, ctx, done)
  local collected = {}
  local function step(index)
    local id = ctx.config.default_sources[index]
    if not id then
      return done(collected)
    end
    local source = registry.get(id)
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
    local source = registry.get(id)
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

---@param opts table telescope picker options
---@param cfg table resolved controlk configuration
function M.open(opts, cfg)
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
  local picker = pickers.new(opts, {
    prompt_title = "Locator",
    finder = finder_for(DEFAULT, ctx),
    sorter = make_sorter(opts),
    previewer = conf.grep_previewer(opts),
    on_input_filter_cb = function(prompt)
      local id, query = parse.parse(prompt, cfg.prefix_map)
      id = id or DEFAULT
      local result = { prompt = query }
      if id ~= current then
        current = id
        result.updated_finder = finder_for(id, ctx)
      end
      return result
    end,
    attach_mappings = function()
      actions.select_default:replace(function(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        -- An item with a prompt (the ? list) rewrites the input and keeps the picker open.
        -- on_input_filter_cb then switches to the source that prompt selects.
        if entry and entry.value.prompt then
          action_state.get_current_picker(prompt_bufnr):set_prompt(entry.value.prompt)
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
  picker:find()
end

return M
