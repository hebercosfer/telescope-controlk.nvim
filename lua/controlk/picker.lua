-- The Telescope adapter. Everything Telescope-specific lives in this file.

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")

local parse = require("controlk.parse")
local registry = require("controlk.sources")
local util = require("controlk.util")
local cmake = require("controlk.cmake")

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
    lnum = item.lnum,
    col = item.col,
  }
end

-- Items marked passthrough were already filtered by their source (the LSP
-- server, a shell, a URL...), so fuzzy matching must not drop them. They keep
-- the order the source produced.
local function make_sorter(opts)
  local fuzzy = conf.generic_sorter(opts)
  return sorters.Sorter:new({
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
