-- Combat effects for the round replay: glowing projectiles from attacker to
-- target, impact bursts, big damage numbers, keyword callouts ("Guard",
-- "Pierce", ...), death ghosts and banners. One OnUpdate drives them all, at
-- frame rate.
--
-- They're cosmetic: the replay's timing lives in UI/Game.lua, which waits
-- long enough for each effect to read. FX.Clear() finishes everything at
-- once (skipping a replay, switching games). Durations follow the replay
-- speed setting.
local _, ns = ...
local UI = ns.UI

local FX = {}
UI.FX = FX

local layer        -- drawn over the board
local driver       -- runs the tweens while any are running
local tweens = {}  -- { t, dur, step(p), done() }
local pool = { tex = {}, text = {}, ghost = {} }
local banner

-- colours: yours, theirs, and kinds of effect
FX.MINE = { 1, 0.82, 0.3 }
FX.THEIRS = { 1, 0.38, 0.22 }
FX.HURT = { 1, 0.25, 0.2 }
FX.HEAL = { 0.35, 1, 0.4 }
FX.VENOM = { 0.45, 1, 0.25 }
FX.FROST = { 0.55, 0.85, 1 }
FX.MAGIC = { 0.8, 0.5, 1 }
FX.GOLD = { 1, 0.85, 0.35 }
FX.WHITE = { 1, 1, 1 }

local function speed() return (ns.db and ns.db.settings.speed) or 1 end

local function smooth(p) return p * p * (3 - 2 * p) end
local function out(p) return 1 - (1 - p) * (1 - p) end

local function tick(_, elapsed)
  local i = 1
  while i <= #tweens do
    local tw = tweens[i]
    tw.t = tw.t + elapsed
    if tw.t >= 0 then
      local p = math.min(1, tw.t / tw.dur)
      tw.step(p)
      if p >= 1 then
        table.remove(tweens, i)
        if tw.done then tw.done() end
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  if #tweens == 0 and driver then driver:Hide() end
end

-- step(p) with p from 0 to 1 over dur seconds (after delay); done() at the end.
local function run(dur, step, done, delay)
  if not driver then
    if done then done() end
    return
  end
  local k = speed()
  tweens[#tweens + 1] = { t = -(delay or 0) / k, dur = math.max(0.01, dur / k), step = step, done = done }
  driver:Show()
end
FX.Run = run

-- Finishes every effect now (their last frame, then cleanup).
function FX.Clear()
  local list = tweens
  tweens = {}
  for _, tw in ipairs(list) do
    tw.step(1)
    if tw.done then tw.done() end
  end
  if banner then banner:Hide() end
  if driver then driver:Hide() end
end

function FX.Busy() return #tweens > 0 end

-- How many of each effect have been started (for the tests).
FX.counts = {}
local function count(kind) FX.counts[kind] = (FX.counts[kind] or 0) + 1 end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------
local function sprite(file, size, col, blend)
  local t = table.remove(pool.tex)
  if not t then t = layer:CreateTexture(nil, "OVERLAY") end
  t:SetTexture(UI.ART .. file)
  t:SetTexCoord(0, 1, 0, 1)
  t:SetBlendMode(blend or "ADD")
  t:SetVertexColor(col[1], col[2], col[3])
  t:SetSize(size, size)
  t:SetAlpha(1)
  t:ClearAllPoints()
  t:Show()
  return t
end

local function release(t)
  t:Hide()
  pool.tex[#pool.tex + 1] = t
end

local function label(size)
  local f = table.remove(pool.text)
  if not f then
    f = CreateFrame("Frame", nil, layer)
    f:SetSize(160, 40)
    f.plate = f:CreateTexture(nil, "BACKGROUND")
    f.plate:SetPoint("CENTER")
    f.plate:SetColorTexture(0.05, 0.03, 0.02, 0.75)
    f.fs = UI.Text(f, 20, "THICKOUTLINE")
    f.fs:SetPoint("CENTER")
  end
  f.fs:SetFont(UI.FONT, size, "THICKOUTLINE")
  f:SetFrameLevel(layer:GetFrameLevel() + 4)
  f:SetScale(1)
  f:SetAlpha(1)
  f:ClearAllPoints()
  f:Show()
  return f
end

local function releaseLabel(f)
  f:Hide()
  pool.text[#pool.text + 1] = f
end

-- A region's scale on screen. Text and textures may not have
-- GetEffectiveScale on every client: they share their parent frame's.
local function scaleOf(r)
  if r.GetEffectiveScale then return r:GetEffectiveScale() or 1 end
  local p = r.GetParent and r:GetParent()
  return (p and p.GetEffectiveScale and p:GetEffectiveScale()) or 1
end

-- Where b is, seen from a (in the effect layer's units).
local function delta(a, b)
  local ax, ay = a:GetCenter()
  local bx, by = b:GetCenter()
  if not (ax and ay and bx and by) then return 0, 0 end
  local sa, sb, sl = scaleOf(a), scaleOf(b), scaleOf(layer)
  return (bx * sb - ax * sa) / sl, (by * sb - ay * sa) / sl
end

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------
-- A small spark left behind by a projectile.
local function trail(anchor, x, y, col, size)
  local t = sprite("Spark", size, col)
  t:SetPoint("CENTER", anchor, "CENTER", x, y)
  run(0.28, function(p)
    t:SetAlpha(0.7 * (1 - p))
    t:SetSize(size * (1 - 0.6 * p), size * (1 - 0.6 * p))
  end, function() release(t) end)
end

-- An orb flying from region a to region b in dur seconds, curving a little,
-- with a trail. big: a larger orb (a hit on Morale).
function FX.Projectile(a, b, col, dur, big)
  if not (layer and a and b) then return end
  count("projectile")
  local dx, dy = delta(a, b)
  local dist = math.sqrt(dx * dx + dy * dy)
  local nx, ny = 0, 0
  if dist > 1 then nx, ny = -dy / dist, dx / dist end
  local bend = math.min(36, dist * 0.16) * ((dx >= 0) and 1 or -1)
  local size = big and 44 or 34
  local orb = sprite("Spark", size, col)
  local core = sprite("Spark", size * 0.4, FX.WHITE)
  local lastTrail = -1
  local function place(p)
    local e = p ^ 1.35
    local s = math.sin(math.pi * e) * bend
    local x, y = dx * e + nx * s, dy * e + ny * s
    orb:SetPoint("CENTER", a, "CENTER", x, y)
    core:SetPoint("CENTER", a, "CENTER", x, y)
    return x, y
  end
  place(0)
  run(dur, function(p)
    local x, y = place(p)
    if p - lastTrail >= 0.07 and p < 1 then
      lastTrail = p
      trail(a, x, y, col, size * 0.75)
    end
  end, function()
    release(orb)
    release(core)
  end)
end

-- An impact at region r: a flash, a shockwave ring and (melee) a slash.
function FX.Impact(r, col, scale, slash)
  if not (layer and r) then return end
  count("impact")
  scale = scale or 1
  local flash = sprite("Spark", 70 * scale, col)
  flash:SetPoint("CENTER", r, "CENTER")
  run(0.22, function(p) flash:SetAlpha(1 - p) end, function() release(flash) end)
  local ring = sprite("Ring", 20, col)
  ring:SetPoint("CENTER", r, "CENTER")
  run(0.38, function(p)
    local s = (20 + 80 * out(p)) * scale
    ring:SetSize(s, s)
    ring:SetAlpha(0.9 * (1 - p))
  end, function() release(ring) end)
  if slash then
    local sl = sprite("Slash", 74 * scale, FX.WHITE)
    if math.random(2) == 1 then sl:SetTexCoord(1, 0, 0, 1) end
    sl:SetPoint("CENTER", r, "CENTER")
    run(0.26, function(p) sl:SetAlpha(1 - p * p) end, function() release(sl) end)
  end
end

-- A ring pulsing out of region r (an Arrive or Fallen effect, a heal, a buff).
function FX.Pulse(r, col, size)
  if not (layer and r) then return end
  size = size or 110
  local ring = sprite("Ring", 30, col)
  ring:SetPoint("CENTER", r, "CENTER")
  local glow = sprite("Spark", size * 0.8, col)
  glow:SetPoint("CENTER", r, "CENTER")
  run(0.5, function(p)
    local s = 30 + (size - 30) * out(p)
    ring:SetSize(s, s)
    ring:SetAlpha(0.85 * (1 - p))
    glow:SetAlpha(0.5 * (1 - p))
  end, function()
    release(ring)
    release(glow)
  end)
end

-- A number that pops out of region r and floats up ("-3", "+2").
function FX.Number(r, text, col, size)
  if not (layer and r) then return end
  count("number")
  local f = label(size or 26)
  f.plate:Hide()
  f.fs:SetText(text)
  f.fs:SetTextColor(col[1], col[2], col[3])
  f:SetPoint("CENTER", r, "CENTER", 0, 14)
  run(0.9, function(p)
    local pop = p < 0.15 and (1.9 - 0.9 * smooth(p / 0.15)) or 1
    f:SetScale(pop)
    f:SetPoint("CENTER", r, "CENTER", 0, (14 + 30 * out(math.max(0, (p - 0.3) / 0.7))) / pop)
    f:SetAlpha(p < 0.55 and 1 or (1 - (p - 0.55) / 0.45))
  end, function() releaseLabel(f) end)
end

-- A keyword callout over region r ("Guard", "Pierce", ...), on a dark plate.
-- icon: an optional sprite beside it ("Shield", "Skull").
function FX.Callout(r, text, col, dy, icon)
  if not (layer and r) then return end
  count("callout")
  local f = label(14)
  f.plate:Show()
  f.fs:SetText(text)
  f.fs:SetTextColor(col[1], col[2], col[3])
  local w = (f.fs:GetStringWidth() or 50) + 14
  f.plate:SetSize(w, 20)
  dy = dy or 40
  f:SetPoint("CENTER", r, "CENTER", 0, dy)
  local ic
  if icon then
    ic = sprite(icon, 34, col, "BLEND")
    ic:SetPoint("CENTER", r, "CENTER", 0, dy - 30)
  end
  run(1.0, function(p)
    local pop = p < 0.12 and (1.6 - 0.6 * smooth(p / 0.12)) or 1
    f:SetScale(pop)
    f:SetPoint("CENTER", r, "CENTER", 0, (dy + 8 * p) / pop)
    local a = p < 0.7 and 1 or (1 - (p - 0.7) / 0.3)
    f:SetAlpha(a)
    if ic then
      local s = 34 * (p < 0.15 and (0.5 + 0.8 * smooth(p / 0.15)) or (1.3 - 0.3 * math.min(1, (p - 0.15) / 0.2)))
      ic:SetSize(s, s)
      ic:SetAlpha(a)
    end
  end, function()
    releaseLabel(f)
    if ic then release(ic) end
  end)
end

-- A dying unit: a ghost of its card shrinks, reddens and fades where it
-- stood, with a skull. slot: where it stood; card: its card frame (still
-- showing the unit).
function FX.Death(slot, card)
  if not (layer and slot and card) then return end
  count("death")
  local g = table.remove(pool.ghost)
  if not g then
    g = CreateFrame("Frame", nil, layer)
    g:SetSize(UI.CARD_W, UI.CARD_H)
    local A = UI.CARD_ART
    g.art = g:CreateTexture(nil, "BACKGROUND")
    g.art:SetPoint("TOPLEFT", A[1], -A[2])
    g.art:SetSize(A[3], A[4])
    g.art:SetTexCoord(0.08, 0.92, 0.22, 0.78)
    g.base = g:CreateTexture(nil, "BORDER")
    g.base:SetAllPoints()
    g.base:SetTexture(UI.ART .. "CardBase")
    g.base:SetTexCoord(0, 1, 0, UI.CARD_V)
    g.frame = g:CreateTexture(nil, "ARTWORK")
    g.frame:SetAllPoints()
    g.frame:SetTexture(UI.ART .. "CardBorder")
    g.frame:SetTexCoord(0, 1, 0, UI.CARD_V)
    g.wash = g:CreateTexture(nil, "OVERLAY")
    g.wash:SetPoint("TOPLEFT", 3, -3)
    g.wash:SetPoint("BOTTOMRIGHT", -3, 3)
    g.wash:SetColorTexture(0.6, 0.05, 0.05, 1)
    g.wash:SetBlendMode("ADD")
  end
  g.art:SetTexture(card.art:GetTexture())
  g.art:SetDesaturated(true)
  if card.border then g.frame:SetVertexColor(card.border[1], card.border[2], card.border[3]) end
  g:SetFrameLevel(layer:GetFrameLevel() + 1)
  g:ClearAllPoints()
  g:SetPoint("CENTER", slot, "CENTER")
  g:SetScale(1)
  g:SetAlpha(1)
  g:Show()
  run(0.6, function(p)
    local s = 1 - 0.28 * smooth(p)
    g:SetScale(s)
    g:SetAlpha(1 - smooth(p))
    g.wash:SetAlpha(0.55 * (1 - p))
  end, function()
    g:Hide()
    pool.ghost[#pool.ghost + 1] = g
  end)
  local skull = sprite("Skull", 40, { 0.95, 0.25, 0.2 }, "BLEND")
  skull:SetPoint("CENTER", slot, "CENTER", 0, 6)
  run(0.75, function(p)
    local s = 40 * (p < 0.2 and (0.4 + 0.9 * smooth(p / 0.2)) or 1.3)
    skull:SetSize(s, s)
    skull:SetAlpha(p < 0.55 and 1 or (1 - (p - 0.55) / 0.45))
  end, function() release(skull) end)
  FX.Impact(slot, { 0.7, 0.08, 0.06 }, 1.1)
end

-- A card arriving on the board: it drops in from a little above full size.
function FX.Arrive(card, col)
  if not (layer and card) then return end
  card:SetScale(1.3)
  card:SetAlpha(0)
  run(0.22, function(p)
    card:SetScale(1.3 - 0.3 * out(p))
    card:SetAlpha(math.min(1, p * 2))
  end, function()
    card:SetScale(1)
    card:SetAlpha(1)
  end)
  FX.Pulse(card:GetParent(), col or FX.WHITE, 120)
end

-- A banner across the middle of the board ("Round 3", "Swift units strike
-- first").
function FX.Banner(text, sub, col)
  if not layer then return end
  count("banner")
  local b = banner
  b.text:SetText(text)
  col = col or FX.GOLD
  b.text:SetTextColor(col[1], col[2], col[3])
  b.sub:SetText(sub or "")
  b:Show()
  b:SetScale(1)
  run(1.05, function(p)
    local a = p < 0.15 and smooth(p / 0.15) or p > 0.75 and (1 - (p - 0.75) / 0.25) or 1
    b:SetAlpha(a)
    b:SetScale(p < 0.15 and (1.25 - 0.25 * smooth(p / 0.15)) or 1)
  end, function() b:Hide() end)
end

-- Sets up the effect layer over `parent` (the board), at `level`; banners
-- are centred on x, y from its top left.
function FX.Build(parent, level, x, y)
  layer = CreateFrame("Frame", nil, parent)
  layer:SetAllPoints()
  layer:SetFrameLevel(level)
  -- the driver hangs off UIParent so effects always finish on time, even if
  -- the board is hidden (another tab) while a round plays out
  driver = CreateFrame("Frame", nil, UIParent)
  driver:SetScript("OnUpdate", tick)
  driver:Hide()
  banner = CreateFrame("Frame", nil, layer)
  banner:SetSize(520, 60)
  banner:SetPoint("CENTER", parent, "TOPLEFT", x, y)
  banner:SetFrameLevel(level + 6)
  local band = banner:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints()
  band:SetColorTexture(0.03, 0.02, 0.01, 0.72)
  banner.text = UI.Text(banner, 24, "THICKOUTLINE")
  banner.text:SetPoint("CENTER", 0, 7)
  banner.sub = UI.Text(banner, 11)
  banner.sub:SetPoint("TOP", banner.text, "BOTTOM", 0, -3)
  banner.sub:SetTextColor(0.9, 0.86, 0.75)
  banner:Hide()
end
