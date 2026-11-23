-- Trading cards with another player, over the addon whispers of Net.lua.
--
-- One trade at a time, like the game's own trade window. One side asks, the
-- other says yes, and both put up cards from their collection (at most
-- Collection.TRADE_MAX each; one side may put up nothing, to give a gift).
-- Any change to either offer takes back both acceptances.
--
-- Once both have accepted the same two offers, the side that asked (the
-- host) sends the deal. The other side checks it against what it accepted,
-- carries out its half and says so; only then does the host carry out its
-- own half. The host keeps the deal in its saved data until that answer
-- comes, and sends it again (also after a reload or a logout), so a lost
-- message or a disconnect never takes cards from one side without the other
-- side getting its due. If the other side no longer has that trade open, it
-- says no and nothing changes on either side.
--
-- Messages ("TYPE;field;field...", like Net.lua's):
--   TQ;tid;proto;cards;version     may we trade?
--   TX;tid                         the asker withdrew the question
--   TN;tid;reason;version          no: declined | busy | version | timeout,
--                                  or about a deal: changed | gone
--   TY;tid                         yes: the trade opens on both sides
--   TO;tid;rev;offer               my offer as of rev (it counts up each change)
--   TA;tid;rev;yourRev             I accept: my offer as of rev for yours as of yourRev
--   TC;tid                         cancelled (or: no such trade here)
--   TD;tid;hostOffer;guestOffer    the deal both accepted, from the host
--   TK;tid                         done on this side
-- An offer is its cards' codes (Net.CodeOf), sorted, with a "*" before a
-- holographic copy; "-" is an empty one.
local _, ns = ...
local L = ns.L
local N, C = ns.Net, ns.Collection

local T = {}
ns.Trade = T

T.PROTO = 1
T.ANSWER_SECONDS = 60          -- how long a request waits for an answer
T.RESEND = { 5, 15, 45, 120 }  -- seconds between resends of a deal with no answer
T.KEEP_DONE = 20               -- deals carried out for the other side, kept to answer resends

local send = N.Send
local short, same = N.Short, N.Same

local function now() return GetTime and GetTime() or 0 end
local function ui() return ns.UI.Trading end
local function refresh()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Offers on the wire
-- ---------------------------------------------------------------------------
-- A copy of each, in a fixed order (by card, a holographic copy last).
function T.Sorted(offer)
  local list = {}
  for i, e in ipairs(offer) do list[i] = { id = e.id, holo = e.holo and true or nil } end
  table.sort(list, function(a, b)
    if a.id ~= b.id then return a.id < b.id end
    return (a.holo and 1 or 0) < (b.holo and 1 or 0)
  end)
  return list
end

function T.Encode(offer)
  if #offer == 0 then return "-" end
  local out = {}
  for i, e in ipairs(T.Sorted(offer)) do out[i] = (e.holo and "*" or "") .. (N.CodeOf(e.id) or "??") end
  return table.concat(out)
end

-- The offer, or nil unless it's a list of known cards that fits in a trade.
function T.Decode(s)
  if s == "-" then return {} end
  if type(s) ~= "string" or s == "" then return nil end
  local list, shiny, i = {}, {}, 1
  while i <= #s do
    local holo = s:sub(i, i) == "*"
    if holo then i = i + 1 end
    local id = N.IdOf(s:sub(i, i + 1))
    if not id or (holo and shiny[id]) then return nil end
    if holo then shiny[id] = true end
    list[#list + 1] = { id = id, holo = holo or nil }
    i = i + 2
  end
  if #list > C.TRADE_MAX then return nil end
  return list
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
-- In the saved data: db.tradePending (the host's deals waiting for their
-- answer, by trade id), db.tradesDone (deals carried out for a host, by trade
-- id) and db.tradeOpen (the trade on screen, so the other side can be told
-- after a reload that it's gone).
local ask   -- the request you sent: { name, tid, at }
local inc   -- the one you got: { name, tid, at }
local cur   -- the open trade, see open()
local resends = {}   -- per trade id of a pending deal: { step, at }

local function pending() return (ns.db and ns.db.tradePending) or {} end

function T.Current() return cur end
function T.Outgoing() return ask and short(ask.name) or nil end
function T.Incoming() return inc and short(inc.name) or nil end
function T.Pending() return pending() end

local function open(name, tid, host)
  -- mine / theirs: the offers; myRev / theirRev: how many changes each has
  -- had; accepted: what you accepted (revisions and the offers on the wire);
  -- theyAccepted: they've accepted the offers as they are now; committing:
  -- the host has sent the deal and waits for the answer
  cur = { name = name, tid = tid, host = host, mine = {}, myRev = 0, theirs = {}, theirRev = 0 }
  ns.db.tradeOpen = { name = name, tid = tid }
  ui().OnOpen(short(name))
end

local function close(why)
  if not cur then return end
  cur = nil
  ns.db.tradeOpen = nil
  ui().OnClose(why)
end

-- ---------------------------------------------------------------------------
-- Asking
-- ---------------------------------------------------------------------------
function T.Ask(name)
  name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
  if name == "" then return false, L["Type a player's name, or target them first."] end
  if same(name, UnitName and UnitName("player")) then return false, L["You can't trade with yourself."] end
  if cur then return false, L["Finish your trade with %s first."]:format(short(cur.name)) end
  if ask then return false, L["You're already waiting for %s to answer."]:format(short(ask.name)) end
  if inc then return false, L["Answer %s's trade request first."]:format(short(inc.name)) end
  ask = { name = name, tid = tostring(math.random(100000000, 999999999)), at = now() }
  send(name, "TQ", ask.tid, T.PROTO, N.CardSum(), ns.VERSION)
  refresh()
  return true
end

function T.CancelAsk()
  if not ask then return end
  send(ask.name, "TX", ask.tid)
  ask = nil
  refresh()
end

-- Your answer to the request you got.
function T.Answer(accept)
  local q = inc
  if not q then return false end
  inc = nil
  if not accept or cur then
    send(q.name, "TN", q.tid, cur and "busy" or "declined", ns.VERSION)
    refresh()
    return not accept
  end
  send(q.name, "TY", q.tid)
  open(q.name, q.tid, false)
  return true
end

-- ---------------------------------------------------------------------------
-- The offers
-- ---------------------------------------------------------------------------
-- Your offer changed: they hear about it, and both acceptances are void.
local function changed()
  cur.myRev = cur.myRev + 1
  cur.accepted, cur.theyAccepted, cur.note = nil, nil, nil
  send(cur.name, "TO", cur.tid, cur.myRev, T.Encode(cur.mine))
  refresh()
end

local function editable() return cur and not cur.committing end

-- How many copies of id are in your offer: plain ones, holographic ones.
function T.Offered(id)
  local plain, holo = 0, 0
  for _, e in ipairs(cur and cur.mine or {}) do
    if e.id == id then
      if e.holo then holo = holo + 1 else plain = plain + 1 end
    end
  end
  return plain, holo
end

-- Puts a copy of id in your offer. holo: your holographic copy; otherwise a
-- plain one, or the holographic one when it's the only copy left.
function T.Offer(id, holo)
  if not editable() then return false end
  local c = ns.Cards.byId[id]
  if not (c and c.collectible) then return false, L["That card can't be traded."] end
  if #cur.mine >= C.TRADE_MAX then return false, L["A trade has room for %d cards from each side."]:format(C.TRADE_MAX) end
  local plain, shiny = C.Spare(ns.db, id)
  local offeredPlain, offeredHolo = T.Offered(id)
  plain, shiny = plain - offeredPlain, shiny and offeredHolo == 0
  if holo then
    if not shiny then return false, L["You have no holographic %s to offer."]:format(c.name) end
  elseif plain > 0 then
    holo = false
  elseif shiny then
    holo = true
  elseif C.Owned(ns.db, id) == 0 then
    return false, L["You don't have %s."]:format(c.name)
  else
    return false, L["You've offered every copy of %s you can."]:format(c.name)
  end
  cur.mine[#cur.mine + 1] = { id = id, holo = holo or nil }
  changed()
  return true
end

-- Takes a copy of id out of your offer: holo true / false picks which, nil
-- takes a plain one if there is one.
function T.Withdraw(id, holo)
  if not editable() then return false end
  local function find(h)
    for i = #cur.mine, 1, -1 do
      local e = cur.mine[i]
      if e.id == id and (e.holo and true or false) == h then return i end
    end
  end
  local i
  if holo == nil then i = find(false) or find(true) else i = find(holo) end
  if not i then return false end
  table.remove(cur.mine, i)
  changed()
  return true
end

-- ---------------------------------------------------------------------------
-- Accepting and the deal
-- ---------------------------------------------------------------------------
local function sendDeal(tid, d)
  send(d.name, "TD", tid, T.Encode(d.give), T.Encode(d.get))
end

-- The host, once both sides have accepted the offers as they are: the deal
-- goes out (and into the saved data until it's answered).
local function tryCommit()
  local c = cur
  if not (c and c.host and not c.committing and c.theyAccepted and c.accepted) then return end
  if c.accepted.myRev ~= c.myRev or c.accepted.theirRev ~= c.theirRev then return end
  c.committing = true
  local d = { name = c.name, give = T.Sorted(c.mine), get = T.Sorted(c.theirs), at = time and time() or 0 }
  ns.db.tradePending[c.tid] = d
  resends[c.tid] = { step = 1, at = now() + T.RESEND[1] }
  sendDeal(c.tid, d)
end

-- Both sides have accepted (the deal is going through).
function T.BothAccepted()
  return (cur and cur.accepted and cur.theyAccepted) and true or false
end

function T.Accept()
  if not editable() or cur.accepted then return false end
  if #cur.mine == 0 and #cur.theirs == 0 then return false, L["Nothing to trade yet: put up a card first."] end
  local ok, why = C.CanGive(ns.db, cur.mine)
  if not ok then return false, why end
  cur.accepted = { myRev = cur.myRev, theirRev = cur.theirRev, mine = T.Encode(cur.mine), theirs = T.Encode(cur.theirs) }
  cur.note = nil
  send(cur.name, "TA", cur.tid, cur.myRev, cur.theirRev)
  tryCommit()
  refresh()
  return true
end

function T.Cancel()
  if not editable() then return false end
  send(cur.name, "TC", cur.tid)
  close(nil)
  return true
end

-- Your half of a deal: carried out, and announced.
local function carryOut(name, give, get)
  local got, trimmed = C.ApplyTrade(ns.db, give, get)
  ui().OnDone(short(name), give, got, trimmed)
  if ns.CheckMilestones then ns.CheckMilestones() end
end

local function pruneDone()
  local done, ids = ns.db.tradesDone, {}
  for tid in pairs(done) do ids[#ids + 1] = tid end
  if #ids <= T.KEEP_DONE then return end
  table.sort(ids, function(a, b) return (done[a].at or 0) < (done[b].at or 0) end)
  for i = 1, #ids - T.KEEP_DONE do done[ids[i]] = nil end
end

-- ---------------------------------------------------------------------------
-- Incoming messages
-- ---------------------------------------------------------------------------
local H = {}

local REASONS = {
  declined = L["%s declined your trade request."],
  busy = L["%s is busy with another trade. Try again in a minute."],
  version = L["%s has a different version of Tradewinds (%s). You both need the same one."],
  timeout = L["%s didn't answer your trade request."],
}

-- Is it the open trade, with them?
local function ours(sender, tid)
  return (cur and cur.tid == tid and same(cur.name, sender)) and cur or nil
end

function H.TQ(sender, tid, proto, cards, version)
  if tonumber(proto) ~= T.PROTO or cards ~= N.CardSum() then
    send(sender, "TN", tid, "version", ns.VERSION)
    ns.Print(L["%s wants to trade cards, but you have different versions of Tradewinds (theirs %s, yours %s). You both need the same one."],
      short(sender), tostring(version), ns.VERSION)
    return
  end
  if cur or ask or (inc and not same(inc.name, sender)) then
    send(sender, "TN", tid, "busy", ns.VERSION)
    return
  end
  inc = { name = sender, tid = tid, at = now() }
  ui().OnRequest(short(sender))
end

function H.TX(sender, tid)
  if inc and inc.tid == tid and same(inc.name, sender) then
    inc = nil
    ui().OnRequestGone(L["%s withdrew the trade request."]:format(short(sender)))
  end
end

function H.TN(sender, tid, reason, version)
  if ask and ask.tid == tid and same(ask.name, sender) then
    ask = nil
    ns.Print(REASONS[reason] or L["%s can't trade right now."], short(sender), tostring(version))
    refresh()
    return
  end
  -- the answer to a deal: they didn't carry it out, so neither do we
  local d = pending()[tid]
  if not (d and same(d.name, sender)) then return end
  pending()[tid] = nil
  resends[tid] = nil
  local c = ours(sender, tid)
  if c and reason == "changed" then
    c.committing, c.accepted, c.theyAccepted = nil, nil, nil
    c.note = L["The offers changed before the trade went through. Check them and accept again."]
    refresh()
  elseif c then
    close(L["%s's side of the trade is gone, so it was cancelled. No cards changed hands."]:format(short(sender)))
  else
    ns.Print(L["Your trade with %s didn't go through. No cards changed hands."], short(sender))
  end
end

function H.TY(sender, tid)
  if ask and ask.tid == tid and same(ask.name, sender) then
    ask = nil
    open(sender, tid, true)
  end
end

function H.TO(sender, tid, rev, offer)
  local c = ours(sender, tid)
  if not c then
    send(sender, "TC", tid)   -- not open here (any more): theirs should close too
    return
  end
  local r, list = tonumber(rev), T.Decode(offer)
  if not (r and list) or r <= c.theirRev then return end
  c.theirs, c.theirRev = list, r
  c.accepted, c.theyAccepted, c.note = nil, nil, nil
  ui().OnTheirOffer()
end

function H.TA(sender, tid, rev, yourRev)
  local c = ours(sender, tid)
  if not c or tonumber(rev) ~= c.theirRev or tonumber(yourRev) ~= c.myRev then return end
  c.theyAccepted = true
  tryCommit()
  ui().OnTheyAccepted()
end

function H.TC(sender, tid)
  local c = ours(sender, tid)
  -- while the host waits for the answer to its deal, that answer settles it
  if c and not c.committing then
    close(L["%s cancelled the trade."]:format(short(sender)))
  end
end

-- The deal, at the side that didn't ask: carried out if it's what we
-- accepted (and only once).
function H.TD(sender, tid, hostOffer, guestOffer)
  local done = ns.db.tradesDone[tid]
  if done and same(done.name, sender) then
    send(sender, "TK", tid)
    return
  end
  local c = ours(sender, tid)
  if not c or c.host then
    send(sender, "TN", tid, "gone", ns.VERSION)
    return
  end
  -- (the deal itself says the host accepted)
  local a = c.accepted
  local give, get = T.Decode(guestOffer), T.Decode(hostOffer)
  if not (a and a.myRev == c.myRev and a.theirRev == c.theirRev and a.mine == guestOffer and a.theirs == hostOffer
      and give and get) then
    send(sender, "TN", tid, "changed", ns.VERSION)
    c.accepted, c.theyAccepted = nil, nil
    refresh()
    return
  end
  ns.db.tradesDone[tid] = { name = sender, at = time and time() or 0 }
  pruneDone()
  send(sender, "TK", tid)
  cur = nil
  ns.db.tradeOpen = nil
  carryOut(sender, give, get)
end

-- The answer to our deal: they've done their half, so we do ours.
function H.TK(sender, tid)
  local d = pending()[tid]
  if not (d and same(d.name, sender)) then return end
  pending()[tid] = nil
  resends[tid] = nil
  if ours(sender, tid) then
    cur = nil
    ns.db.tradeOpen = nil
  end
  carryOut(sender, d.give, d.get)
end

for kind, fn in pairs(H) do N.Handle(kind, fn) end

-- ---------------------------------------------------------------------------
-- Every second: timeouts and resends
-- ---------------------------------------------------------------------------
function T.Tick()
  local t = now()
  if ask and t - ask.at > T.ANSWER_SECONDS + 5 then
    ns.Print(L["%s didn't answer. They need to be online, with the same version of Tradewinds."], short(ask.name))
    ask = nil
    refresh()
  end
  if inc and t - inc.at > T.ANSWER_SECONDS then
    send(inc.name, "TN", inc.tid, "timeout", ns.VERSION)
    inc = nil
    ui().OnRequestGone(nil)
  end
  for tid, d in pairs(pending()) do
    local rs = resends[tid]
    if not rs then
      rs = { step = 1, at = t + T.RESEND[1] }
      resends[tid] = rs
    end
    if t >= rs.at then
      sendDeal(tid, d)
      rs.step = math.min(rs.step + 1, #T.RESEND)
      rs.at = t + T.RESEND[rs.step]
    end
  end
end

-- "No player named X is currently playing." after whispering X (from Net's
-- chat filter; bounced(name) tells if it's about that player). Returns true
-- if it was about a trade (the message is then hidden).
function T.Bounced(bounced)
  if ask and bounced(ask.name) then
    ns.Print(L["%s isn't online."], short(ask.name))
    ask = nil
    refresh()
    return true
  end
  if cur and bounced(cur.name) then
    if cur.committing then
      local name = short(cur.name)
      cur = nil
      ns.db.tradeOpen = nil
      ui().OnClose(L["%s went offline. Your trade will finish when you're both online again."]:format(name))
    else
      close(L["%s went offline, so the trade was cancelled."]:format(short(cur.name)))
    end
    return true
  end
  for _, d in pairs(pending()) do
    if bounced(d.name) then return true end
  end
  return false
end

function T.Init()
  local db = ns.db
  -- a trade that was open before the reload is gone: say so (unless its deal
  -- is out, which settles it)
  local o = db.tradeOpen
  if type(o) == "table" and type(o.name) == "string" and type(o.tid) == "string" and not db.tradePending[o.tid] then
    send(o.name, "TC", o.tid)
  end
  db.tradeOpen = nil
  -- deals still waiting for their answer: ask again
  for tid, d in pairs(db.tradePending) do
    sendDeal(tid, d)
    resends[tid] = { step = 1, at = now() + T.RESEND[1] }
    ns.Print(L["Your trade with %s will finish when you're both online."], short(d.name))
  end
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, T.Tick) end
end
