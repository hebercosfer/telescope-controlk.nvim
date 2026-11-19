local M = {}

--- Split a prompt into the source it targets and the query for that source.
--- A prefix only counts when it is followed by a space; the longest match wins.
---@param prompt string
---@param prefix_map table<string, string> prefix -> source id
---@return string|nil source_id nil means no prefix was typed
---@return string query text after the prefix (the whole prompt when there is no prefix)
---@return string|nil prefix the prefix that matched
function M.parse(prompt, prefix_map)
  prompt = prompt or ""
  local best
  for prefix in pairs(prefix_map) do
    if prompt:sub(1, #prefix + 1) == prefix .. " " and (best == nil or #prefix > #best) then
      best = prefix
    end
  end
  if best then
    return prefix_map[best], prompt:sub(#best + 2), best
  end
  -- The prefix list needs no space: "?" alone shows it at once.
  if prompt ~= "" and prefix_map[prompt] == "prefixes" then
    return "prefixes", "", prompt
  end
  return nil, prompt, nil
end

return M
