-- /tradewinds probe: asks the client about the calls Tradewinds leans on but
-- that nobody has seen on this client yet (WoW Forever is neither retail nor
-- classic). One line per question, the answer or "missing", and it never
-- errors: every call is wrapped. Features that need one of these work
-- without it (see each line's "fallback").
--
-- The text is for bug reports and stays in English, like /tradewinds travel.
local _, ns = ...

local P = {}
ns.Probe = P

P.GUILD_WAIT = 6   -- seconds to wait for our own guild message to come back

local function get(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

local function line(name, answer)
  ns.Print("probe |cffffd100%s|r: %s", name, tostring(answer))
end

-- Runs fn and prints its answer; an error is reported as one.
local function ask(name, fn)
  local ok, answer = pcall(fn)
  line(name, ok and answer or ("error: " .. tostring(answer)))
end

local function present(path)
  local v = get(path)
  return v ~= nil and (type(v) .. " present") or "missing"
end

local function describe(v)
  if type(v) == "string" then return ("string (%d letters)"):format(#v) end
  if v == nil then return "nil" end
  return ("%s %s"):format(type(v), tostring(v))
end

local pending   -- the guild message we wait to see come back: { nonce, at }

-- Our own guild message coming back (CHAT_MSG_ADDON).
function P.OnAddonMessage(prefix, text, channel, sender)
  if not pending or prefix ~= ns.Net.PREFIX or channel ~= "GUILD" then return end
  local nonce = type(text) == "string" and text:match("^PB;(%d+)$")
  if nonce ~= pending.nonce then return end
  local took = (GetTime and GetTime() or 0) - pending.at
  pending = nil
  local me = UnitName and UnitName("player")
  local mine = type(sender) == "string" and type(me) == "string" and sender:match("^[^%-]+") == me
  line("guild addon message", ("arrived after %.1f s (sender %s)"):format(took, mine and "is you" or describe(sender)))
end

local function guildMessage()
  local inGuild = IsInGuild and IsInGuild()
  if not inGuild then
    line("guild addon message", "not tried: you're not in a guild")
    return
  end
  local api = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not api then
    line("guild addon message", "missing: no SendAddonMessage")
    return
  end
  local nonce = tostring(math.random(100000, 999999))
  pending = { nonce = nonce, at = GetTime and GetTime() or 0 }
  local ok, result = pcall(api, ns.Net.PREFIX, "PB;" .. nonce, "GUILD")
  if not ok then
    pending = nil
    line("guild addon message", "error sending: " .. tostring(result))
    return
  end
  line("guild addon message", ("sent (the call returned %s), waiting up to %d s for it to come back..."):format(
    describe(result), P.GUILD_WAIT))
  local mine = pending
  C_Timer.After(P.GUILD_WAIT, function()
    if pending == mine then
      pending = nil
      line("guild addon message", "did NOT come back (fallback: whisper each guildmate who has Tradewinds)")
    end
  end)
end

local function roster()
  if not GetNumGuildMembers then return "missing (fallback: the guild board shows last-seen times only)" end
  local total, online = GetNumGuildMembers()
  local out = ("GetNumGuildMembers %s / %s online"):format(describe(total), describe(online))
  if not GetGuildRosterInfo then return out .. "; GetGuildRosterInfo missing" end
  local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(1)
  return out .. ("; GetGuildRosterInfo(1): name %s, online (9th value) %s"):format(describe(name), describe(isOnline))
end

local function scaleAnimation()
  local f = CreateFrame("Frame")
  local ag = f:CreateAnimationGroup()
  local ok, a = pcall(ag.CreateAnimation, ag, "Scale")
  if not ok or not a then return "missing (fallback: the squeeze tween in UI/Effects.lua)" end
  local has = {}
  for _, m in ipairs({ "SetScale", "SetScaleFrom", "SetScaleTo", "SetOrigin" }) do
    if a[m] then has[#has + 1] = m end
  end
  return "present, with " .. (#has > 0 and table.concat(has, ", ") or "none of SetScale / SetScaleFrom / SetScaleTo / SetOrigin")
end

local function editBox()
  local ok, eb = pcall(CreateFrame, "EditBox", nil, UIParent)
  if not ok or not eb then return "missing" end
  local has = {}
  for _, m in ipairs({ "SetText", "HighlightText", "SetAutoFocus", "SetFocus", "ClearFocus", "SetMultiLine" }) do
    if eb[m] then has[#has + 1] = m end
  end
  eb:Hide()
  return "present, with " .. table.concat(has, ", ")
end

local function chatBox()
  local parts = {}
  for _, path in ipairs({ "ChatFrame_OpenChat", "ChatEdit_InsertLink", "ChatEdit_GetActiveWindow", "ChatFrameUtil.OpenChat",
    "ChatFrameUtil.InsertLink" }) do
    parts[#parts + 1] = path .. " " .. (get(path) and "yes" or "no")
  end
  local cf = DEFAULT_CHAT_FRAME
  parts[#parts + 1] = "DEFAULT_CHAT_FRAME.editBox " .. ((cf and cf.editBox) and "yes" or "no")
  return table.concat(parts, ", ")
end

local function sounds()
  local have, missing = 0, {}
  for _, list in pairs(ns.UI.SOUNDS or {}) do
    for _, name in ipairs(list) do
      if SOUNDKIT and SOUNDKIT[name] then have = have + 1 else missing[#missing + 1] = name end
    end
  end
  table.sort(missing)
  local seen, uniq = {}, {}
  for _, n in ipairs(missing) do
    if not seen[n] then seen[n] = true; uniq[#uniq + 1] = n end
  end
  return ("%d sound kits found; not on this client: %s"):format(have, #uniq > 0 and table.concat(uniq, ", ") or "none")
end

function P.Run()
  local build = GetBuildInfo and { GetBuildInfo() } or {}
  line("client", ("Tradewinds %s, build %s, interface %s, locale %s"):format(tostring(ns.VERSION), tostring(build[2]),
    tostring(build[4]), GetLocale and GetLocale() or "?"))
  ask("IsInGuild", function() return IsInGuild and describe(IsInGuild()) or "missing (fallback: the guild board is hidden)" end)
  ask("guild roster", roster)
  ask("guild roster refresh", function()
    return "C_GuildInfo.GuildRoster " .. present("C_GuildInfo.GuildRoster") .. ", GuildRoster " .. present("GuildRoster")
  end)
  ask("Ambiguate", function() return present("Ambiguate") end)
  ask("chat edit box", chatBox)
  ask("EditBox widget", editBox)
  ask("Scale animation", scaleAnimation)
  ask("sounds", sounds)
  ask("travel", function()
    local T = ns.Travel
    return ("flying %s, riding %s"):format(tostring(T and T.IsFlying()), tostring(T and T.IsRiding()))
  end)
  guildMessage()
end

ns.On("CHAT_MSG_ADDON", function(...) P.OnAddonMessage(...) end)
