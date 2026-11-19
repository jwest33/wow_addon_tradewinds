-- Creature portraits for card tooltips.
--
-- A card knows its creature id (npc). The client turns that into a display id
-- by loading the creature into a hidden DressUpModel and reading
-- GetDisplayInfo once the server has answered; SetPortraitTextureFromCreature-
-- DisplayID then draws a still portrait, like a unit frame's. The models are
-- never shown (a shown model renders a 3D scene every frame, and this client
-- has had GPU hangs from that). Display ids are saved, so each creature is
-- only looked up once.
local _, ns = ...

local P = {}
ns.Portraits = P

local GIVE_UP = 6     -- seconds
local RESEND = 1
local pending, failed = {}, {}
local probes, ticker

local function newModel()
  local ok, m = pcall(CreateFrame, "DressUpModel")
  if ok and m and m.SetCreature and m.GetDisplayInfo then
    m:Hide()
    return m
  end
end

local function readDisplay(m)
  local ok, d = pcall(m.GetDisplayInfo, m)
  if ok and type(d) == "number" and d > 0 then return d end
end

-- Until the server answers, a model reports a stand-in: the player's own
-- appearance or an empty model's. Neither is the creature's.
local function standIns()
  if probes == nil then
    probes = false
    local own, blank = newModel(), newModel()
    if own and blank and own.SetUnit then probes = { own = own, blank = blank } end
  end
  if not probes then return nil, nil end
  pcall(probes.own.SetUnit, probes.own, "player")
  return readDisplay(probes.own), readDisplay(probes.blank)
end

local function poll()
  local now = GetTime()
  local own, blank, checked
  local any = false
  for npc, w in pairs(pending) do
    any = true
    local d = readDisplay(w.model)
    if d and not checked then
      own, blank = standIns()
      checked = true
    end
    if d and d ~= own and d ~= blank then
      pending[npc] = nil
      if ns.db then ns.db.displays[npc] = d end
      for _, cb in ipairs(w.cbs) do pcall(cb, d) end
    elseif now - w.t0 > GIVE_UP then
      pending[npc] = nil
      failed[npc] = true
    elseif now - w.sent > RESEND then
      w.sent = now
      pcall(w.model.SetCreature, w.model, npc)
    end
  end
  if not any and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

function P.Display(card)
  if card.display then return card.display end
  local d = ns.db and card.npc and ns.db.displays[card.npc]
  if type(d) == "number" then return d end
end

local function request(npc, cb)
  if failed[npc] or not (C_Timer and C_Timer.NewTicker and GetTime) then return end
  local w = pending[npc]
  if not w then
    local m = newModel()
    if not m then
      failed[npc] = true
      return
    end
    w = { model = m, t0 = GetTime(), sent = GetTime(), cbs = {} }
    pending[npc] = w
    pcall(m.SetCreature, m, npc)
    if not ticker then ticker = C_Timer.NewTicker(0.1, poll) end
  end
  w.cbs[#w.cbs + 1] = cb
end

-- Draws the card's creature into `tex`. Returns true if it did; otherwise
-- starts the lookup and calls onReady(displayID) when it's done.
function P.Apply(tex, card, onReady)
  if not SetPortraitTextureFromCreatureDisplayID then return false end
  local d = P.Display(card)
  if d then
    if not pcall(SetPortraitTextureFromCreatureDisplayID, tex, d) then return false end
    local t = tex:GetTexture()
    return t ~= nil and t ~= 0 and t ~= ""
  end
  if card.npc then request(card.npc, onReady) end
  return false
end
