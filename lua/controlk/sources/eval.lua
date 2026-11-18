local function hint(text)
  return { text = text, tag = "lua", hint = true, passthrough = true }
end

return {
  id = "eval",
  title = "Evaluate Lua expression",
  tag = "lua",
  items = function(query, _, done)
    if query == "" then
      return done({})
    end

    local chunk, err = load("return " .. query)
    if not chunk then
      return done({ hint(err) })
    end
    local ok, result = pcall(chunk)
    if not ok then
      return done({ hint(tostring(result)) })
    end

    local text = type(result) == "string" and result or vim.inspect(result)
    done({
      {
        text = text,
        detail = query,
        passthrough = true,
        -- Enter copies the result to the unnamed register.
        run = function()
          vim.fn.setreg('"', text)
          vim.notify("Copied to the unnamed register")
        end,
      },
    })
  end,
}
