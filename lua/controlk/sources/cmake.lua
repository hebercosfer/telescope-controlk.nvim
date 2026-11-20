-- CMake sources: build targets (cm), open a target's definition (cmo), run tests (ct).

local cmake = require("controlk.cmake")
local util = require("controlk.util")

local function type_label(target_type)
  local label = (target_type or "target"):lower():gsub("_", " ")
  return label
end

local function configure_item(state)
  return {
    text = "Configure project",
    detail = table.concat(cmake.configure_command(state.root, state.build_dir), " "),
    tag = "cmake",
    passthrough = true,
    run = function()
      util.terminal(cmake.configure_command(state.root, state.build_dir), state.root)
    end,
  }
end

--- Items explaining why the model is missing, plus a way to fix it when possible.
local function error_items(state, tag)
  local items = { util.hint(state.error, tag) }
  if state.configure and state.root then
    table.insert(items, configure_item(state))
  end
  return items
end

--- Build items from the CMake model, or explain why there is none.
local function with_model(ctx, done, build)
  cmake.load_model(ctx, function(state)
    if state.error then
      return done(error_items(state, "cmake"))
    end
    done(build(state))
  end)
end

return {
  cmake_targets = {
    title = "CMake build targets",
    tag = "build",
    items = function(_, ctx, done)
      with_model(ctx, done, function(state)
        local items = {}
        for _, target in ipairs(state.model.targets) do
          table.insert(items, {
            text = target.name,
            detail = type_label(target.type),
            tag = "build",
            run = function()
              util.terminal(
                { "cmake", "--build", state.build_dir, "--target", target.name },
                state.root
              )
            end,
          })
        end
        table.insert(items, configure_item(state))
        return items
      end)
    end,
  },

  cmake_open = {
    title = "CMake target definitions",
    tag = "open",
    items = function(_, ctx, done)
      with_model(ctx, done, function(state)
        local items = {}
        for _, target in ipairs(state.model.targets) do
          if target.path then
            table.insert(items, {
              text = target.name,
              detail = ("%s  %s:%d"):format(
                type_label(target.type),
                vim.fn.fnamemodify(target.path, ":~:."),
                target.lnum or 1
              ),
              tag = "open",
              path = target.path,
              lnum = target.lnum,
            })
          end
        end
        return items
      end)
    end,
  },

  cmake_tests = {
    title = "CTest tests",
    tag = "test",
    items = function(_, ctx, done)
      cmake.load_model(ctx, function(state)
        if state.error then
          return done(error_items(state, "test"))
        end

        util.memo(ctx, "ctest:" .. state.build_dir, function(finish)
          cmake.list_tests(state.build_dir, function(names, err)
            finish({ names = names, err = err })
          end)
        end, function(result)
          if result.err then
            return done({ util.hint(result.err, "test") })
          end

          local items = {
            {
              text = "Run all tests",
              tag = "test",
              passthrough = true,
              run = function()
                util.terminal(
                  { "ctest", "--test-dir", state.build_dir, "--output-on-failure" },
                  state.root
                )
              end,
            },
          }
          for _, name in ipairs(result.names) do
            table.insert(items, {
              text = name,
              tag = "test",
              run = function()
                util.terminal({
                  "ctest",
                  "--test-dir",
                  state.build_dir,
                  "-R",
                  cmake.exact_test_regex(name),
                  "--output-on-failure",
                }, state.root)
              end,
            })
          end
          done(items)
        end)
      end)
    end,
  },
}
