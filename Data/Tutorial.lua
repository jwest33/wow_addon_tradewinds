-- The tutorial: a match against Flightmaster Dorn with stacked decks. The
-- first four rounds are scripted: Dorn tells you what to play and plays a set
-- hand himself. Each round teaches one thing: lanes and Morale, blocking,
-- tactics landing after the reveal, and the Guard keyword. From round 5 on he
-- plays for real (the easy AI) and you finish the match.
--
-- tests/engine.lua plays the script and checks that every round turns out the
-- way the coach's text says it does. Change the decks, plays or card stats and
-- that test tells you which line has become untrue.
local _, ns = ...
local L = ns.L
local R = ns.Rules

local T = {}
ns.Tutorial = T

T.OPP = "dorn"
T.SEED = 1
T.GUIDED = 4         -- scripted rounds
T.LEVEL = "easy"     -- Dorn afterwards

-- In draw order: the first four are the opening hand, then one per round.
T.DECKS = {
  { "thug", "fireball", "grunt", "croc",            -- opening hand
    "kobold", "wolf", "bear", "strider",            -- rounds 1-4
    "spider", "boar", "murloc", "fireball", "kobold", "wolf", "thug", "grunt", "croc", "spider", "boar", "strider" },
  { "strider", "raptor", "boar", "potion",
    "kobold", "wolf", "spider", "croc",
    "vulture", "strider", "bat", "wolf", "boar", "spider", "croc", "kobold", "vulture", "shout", "shout", "potion" },
}

local W = "|cffffffff"   -- names in the coach's text
local K = "|cff7fbfff"   -- keywords

-- you: what Dorn asks you to play (the round can't be locked in until it's
-- all planned, and nothing else can be). dorn: what he plays. say: shown
-- while you plan. watch: while the round plays out. after: once it's over,
-- until you click Next.
T.ROUNDS = {
  {
    you = { { id = "kobold", lane = 2 } },
    dorn = { { id = "kobold", lane = 4 } },
    say = "Welcome to the table! I'm Dorn, and I'll show you how this works before we play for real. " ..
      "Each column is a lane. In combat every unit strikes the enemy unit straight across from it, " ..
      "or the enemy's Morale if nothing is there. You have 1 Supply to spend. Play your " .. W ..
      "Kobold Vermin|r in " .. W .. "your lane 2|r (the bottom row), then press Lock In.",
    watch = "We both reveal at the same time. Watch where my unit goes.",
    after = "Your Kobold had nothing across from it, so it hit my Morale for 1. Mine was in lane 4 with " ..
      "nothing across, so it hit yours. A unit with nothing across keeps doing that every round. " ..
      "Whoever runs out of Morale loses.",
  },
  {
    you = { { id = "thug", lane = 4 } },
    dorn = { { id = "strider", lane = 2 } },
    say = "My Kobold in lane 4 will keep hitting you. Block it: put your " .. W .. "Defias Thug|r in " .. W ..
      "your lane 4|r, right across from it. The marker between the rows shows what each lane will do; " ..
      "it turns from a red arrow into crossed swords.",
    watch = "Units that face each other fight. Both strike at the same time.",
    after = "Blocked! Your Thug destroyed my Kobold. Damage stays on a unit until it dies, so a battered " ..
      "unit is easy to finish off. My Plainstrider's Arrive effect gave me some Morale back when it came in.",
  },
  {
    you = { { id = "fireball", lane = 3 }, { id = "wolf", lane = 1 } },
    dorn = { { id = "raptor", lane = 3 } },
    say = "Tactics are different: they go off after both sides' new units arrive, so a tactic aimed at an " ..
      "empty lane hits whatever lands there. Psst, I'm about to put a beast in lane 3. Cast " .. W ..
      "Fireball|r at " .. W .. "my lane 3|r (the top row), and play your " .. W .. "Young Wolf|r in " .. W ..
      "your lane 1|r.",
    watch = "Watch the order: new units arrive first, then tactics, then combat.",
    after = "See that? My Lashtail arrived in lane 3 and your Fireball hit it before it could strike. " ..
      "Usually you won't know where I'll play. Guessing right is half the game.",
  },
  {
    you = { { id = "bear", lane = 2 } },
    dorn = { { id = "boar", lane = 3 } },
    say = "You can't block every lane. A unit with " .. K .. "Guard|r covers the lanes beside it: an enemy " ..
      "with nothing across that's next to your Guard strikes the Guard instead of your Morale. Play your " ..
      W .. "Grizzled Black Bear|r in " .. W .. "your lane 2|r.",
    watch = "Keep an eye on lane 3.",
    after = "My Boar had nothing across in lane 3, but your Bear stepped in and took the hit, so your Morale " ..
      "is safe. Keywords like Guard are printed on the card. Hover any card to see what they do.",
  },
}

T.FREE = "That's the basics. From here on I play for real. Win this one and you're ready for the circuit. " ..
  "Hover the markers between the rows to see what each lane will do; the Guide tab explains the rest."

-- The coach's text in the client's language (Locales/Locale.lua).
T.TEXT = { "say", "watch", "after" }
for _, r in ipairs(T.ROUNDS) do
  for _, k in ipairs(T.TEXT) do r[k] = L[r[k]] end
end
T.FREE = L[T.FREE]

-- The game: stacked decks, you with initiative in round 1.
function T.NewGame(names)
  local decks = {}
  for p = 1, 2 do
    local src, d = T.DECKS[p], {}
    for i = #src, 1, -1 do d[#d + 1] = src[i] end   -- draws take the last card
    decks[p] = d
  end
  return R.NewGame({ seed = T.SEED, decks = decks, names = names, first = 1, stacked = true })
end

-- A plan (hand indexes) for player p playing the listed cards from their
-- hand. Returns nil if a card isn't in the hand.
function T.PlanFor(st, p, list)
  local used, plan = {}, {}
  for _, want in ipairs(list) do
    local found
    for h, id in ipairs(st.players[p].hand) do
      if id == want.id and not used[h] then found = h; break end
    end
    if not found then return nil end
    used[found] = true
    plan[#plan + 1] = { h = found, id = want.id, lane = want.lane }
  end
  return plan
end

-- The scripted round, if this round is one.
function T.Round(st)
  return st.round <= T.GUIDED and T.ROUNDS[st.round] or nil
end

-- What the coach still wants planned this round, given your plan so far
-- (entries with an id and a lane). Empty when it's all there; nil when the
-- round isn't scripted.
function T.Remaining(st, plan)
  local r = T.Round(st)
  if not r then return nil end
  local used, out = {}, {}
  for _, want in ipairs(r.you) do
    local ok = false
    for i, a in ipairs(plan) do
      if not used[i] and a.id == want.id and a.lane == want.lane then used[i] = true; ok = true; break end
    end
    if not ok then out[#out + 1] = want end
  end
  return out
end

-- Is this placement one the coach asked for (and not done yet)?
function T.Allowed(st, plan, id, lane)
  local rest = T.Remaining(st, plan)
  if not rest then return true end
  for _, want in ipairs(rest) do
    if want.id == id and (lane == nil or want.lane == lane) then return true end
  end
  return false
end
