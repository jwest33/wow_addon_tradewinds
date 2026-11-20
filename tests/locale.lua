-- Translation checks. Run with tests/run_tests.py:
--
--   python tests/run_tests.py locale         check
--   python tests/run_tests.py locale write   regenerate Locales/enUS.lua
--
-- 1. Every text the addon looks up in L (L["..."] in the code, the two forms
--    given to ns.Plural, and the card, opponent, keyword and tutorial text
--    that goes through L when it's defined) is in the template,
--    Locales/enUS.lua, and nothing else is.
-- 2. Every language file (the Locales/ files in the .toc) translates every
--    key and nothing else, keeping the placeholders, colour codes and line
--    breaks of the English, and its card face text fits.
-- tests/locale_smoke.lua then plays the addon in each language.
local ROOT = ROOT or "."
local WRITE = ARGS and ARGS[1] == "write"

local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label) end
end

-- ---------------------------------------------------------------------------
-- Keys in the code
-- ---------------------------------------------------------------------------
-- A small Lua lexer: names, strings (unescaped) and single-character symbols;
-- comments and numbers are skipped.
local function lex(src)
  local toks, i, n = {}, 1, #src
  local function longClose(at)
    local eq = src:match("^%[(=*)%[", at)
    local close = src:find("]" .. eq .. "]", at, true)
    return close + #eq + 2, at + #eq + 2, close - 1
  end
  while i <= n do
    local c = src:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif src:sub(i, i + 1) == "--" then
      if src:match("^%[=*%[", i + 2) then
        i = longClose(i + 2)
      else
        local nl = src:find("\n", i, true)
        i = nl and nl + 1 or n + 1
      end
    elseif c == '"' or c == "'" then
      local j = i + 1
      while true do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c then break
        elseif d == "" or d == "\n" then error("unfinished string at " .. i)
        else j = j + 1 end
      end
      toks[#toks + 1] = { t = "str", v = assert(loadstring("return " .. src:sub(i, j)))(), at = i }
      i = j + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local after, from, to = longClose(i)
      toks[#toks + 1] = { t = "str", v = src:sub(from, to), at = i }
      i = after
    elseif c:match("[%a_]") then
      local name = src:match("^[%w_]+", i)
      toks[#toks + 1] = { t = "name", v = name, at = i }
      i = i + #name
    elseif c:match("%d") then
      i = i + #src:match("^[%w%.]+", i)
    else
      toks[#toks + 1] = { t = "sym", v = c, at = i }
      i = i + 1
    end
  end
  return toks
end

local files = {}
local localeFiles = {}
for line in io.lines(ROOT .. "/Deckhand.toc") do
  local f = line:match("^%s*([^#].-%.lua)%s*$")
  if f then
    f = f:gsub("\\", "/")
    files[#files + 1] = f
    local code = f:match("^Locales/(%a%a%a%a)%.lua$")
    if code then localeFiles[#localeFiles + 1] = { code = code, path = f } end
  end
end
-- every language file on disk is loaded by the game
for _, f in ipairs(LOCALE_FILES or {}) do
  local listed = false
  for _, l in ipairs(localeFiles) do if l.path == "Locales/" .. f then listed = true end end
  check(listed or f == "enUS.lua" or f == "Locale.lua", "Locales/" .. f .. " is in the .toc")
end

local found = {}       -- key -> first file it's used in
local foundOrder = {}  -- file -> keys, in order
local plurals = {}     -- singular key -> plural key
local function addKey(key, file)
  if found[key] then return end
  found[key] = file
  foundOrder[file] = foundOrder[file] or {}
  table.insert(foundOrder[file], key)
end

for _, f in ipairs(files) do
  if not f:match("^Locales/") then
    local src = assert(io.open(ROOT .. "/" .. f, "rb")):read("*a")
    local toks = lex(src)
    for k, a in ipairs(toks) do
      local b, c, d = toks[k + 1], toks[k + 2], toks[k + 3]
      if a.t == "name" and a.v == "L" and b and b.v == "[" and c and c.t == "str" and d and d.v == "]" then
        addKey(c.v, f)
      elseif a.t == "name" and a.v == "Plural" and b and b.v == "(" then
        local depth, j, strs = 1, k + 2, {}
        while depth > 0 and toks[j] do
          local t = toks[j]
          if t.t == "sym" and t.v == "(" then depth = depth + 1
          elseif t.t == "sym" and t.v == ")" then depth = depth - 1
          elseif t.t == "str" and depth == 1 then strs[#strs + 1] = t.v end
          j = j + 1
        end
        if #strs > 0 then
          check(#strs == 2, f .. ": ns.Plural with two literal forms")
          addKey(strs[1], f)
          if strs[2] then
            addKey(strs[2], f)
            plurals[strs[1]] = strs[2]
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Keys in the data: load the addon (English) and record every key looked up
-- while it loads.
-- ---------------------------------------------------------------------------
dofile(ROOT .. "/tests/wowmock.lua")
local ns = {}
local loaded = {}
for _, f in ipairs(files) do
  assert(loadfile(ROOT .. "/" .. f))("Deckhand", ns)
  if f == "Locales/Locale.lua" then
    setmetatable(ns.L, { __index = function(_, k) loaded[k] = true; return k end })
  end
end
check(ns.LOCALE == "enUS", "the mock client is English")
local R, Cards = ns.Rules, ns.Cards

-- ---------------------------------------------------------------------------
-- The template
-- ---------------------------------------------------------------------------
local NOTES = {
  ["%s, %s"] = "a card's type and rarity: \"Beast unit, Rare\"",
  ["%s: %s"] = "a label and its value",
  ["%d %s"] = "a number and a word: \"3 holographic\"",
  ["\"%s\""] = "a quotation; use your language's quotation marks",
  ["%s: \"%s\""] = "someone says something: \"Dorn: \"Deal 'em.\"\"",
  ["%s: |cffffffff%s|r"] = "a keyword and its rules",
  ["%s unit"] = "a tribe's unit: \"Beast unit\"",
  ["holographic"] = "an adjective, used inside other sentences",
  ["Holographic"] = "a card that shines (a cosmetic version)",
  ["Lock In"] = "button: commit your plan for the round",
  ["click"] = "on the back of an unopened card",
  ["dies"] = "tag on a card that the forecast says will die",
  ["%s Fix it in the Cards tab."] = "%s is a sentence saying what's wrong with the deck",
  ["Supply"] = "the resource you spend on cards each round",
  ["Morale"] = "each player's life total",
  ["on"] = "an option's state, shown after a command such as /deckhand sound on",
  ["off"] = "an option's state, shown after a command such as /deckhand sound off",
  ["victory"] = "a reason for a reward: \"+4 shards (victory)\"",
}

local function quote(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

local out, emitted = {}, {}
local function line(s) out[#out + 1] = s end
local function emit(key, note)
  if emitted[key] or key == "" then return end
  emitted[key] = true
  note = note or NOTES[key]
  local pl = plurals[key]
  if pl then note = (note and note .. "; " or "") .. "plural: one of a pair, see below" end
  for single, many in pairs(plurals) do
    if many == key then note = (note and note .. "; " or "") .. "plural of " .. quote(single) end
  end
  line(("L[%s] = %s%s"):format(quote(key), quote(key), note and ("   -- " .. note) or ""))
end

line("-- Deckhand's text in English: the template for translations.")
line("-- Generated by `python tests/run_tests.py locale write`; don't edit by hand.")
line("-- This file isn't loaded by the game (English is built in).")
line("--")
line("-- To translate: copy it to Locales/<code>.lua, put the code in the NewLocale")
line("-- line, add the file to Deckhand.toc after Locales\\Locale.lua, and replace")
line("-- each right-hand side. `python tests/run_tests.py locale` checks the result.")
line("--  * Keep the placeholders (%s, %d, %.1f) in the same order; the code fills")
line("--    them in that order (no %1$s).")
line("--  * Keep colour codes (|cffrrggbb ... |r) around the matching words, and")
line("--    line breaks (\\n).")
line("--  * Chat commands (/deckhand ...) stay in English, also the words typed")
line("--    after them (on, off, play, ...).")
line("--  * Cards, characters and places from World of Warcraft: use the official")
line("--    name in your language's client where there is one.")
line("--  * Use one word for each keyword (Guard, Swift, ...) everywhere: card")
line("--    text, the tutorial and the Guide.")
line("--  * Plural pairs (\"%d card pack\" / \"%d card packs\"): the first is used for")
line("--    1, the second for every other number. If your language needs more")
line("--    forms, word both so they work for any number (\"Card packs: %d\").")
line("--  * Card faces are small: a card's name about 24 letters at most, the")
line("--    short rules text about 40 (half that in Chinese and Korean). Longer")
line("--    text is printed smaller.")
line("local _, ns = ...")
line("local L = ns.NewLocale(\"enUS\")")
line("if not L then return end")

line("")
line("-- == Keywords ==")
for _, k in ipairs(R.KEYWORDS) do
  emit(k.name, "keyword")
  emit(k.text, "what " .. quote(k.name) .. " does")
end

line("")
line("-- == Cards == (name, card face text, tooltip text, flavour)")
for _, c in ipairs(Cards.list) do
  local what = c.type == "unit" and ("unit %d/%d"):format(c.atk, c.hp) or "tactic"
  line(("-- %s: %s, cost %d, %s%s"):format(c.id, what, c.cost, c.collectible and c.rarity or "token",
    c.tribe and (", " .. c.tribe) or ""))
  emit(c.name, "name")
  if c.short then emit(c.short, "card face (short)") end
  if c.text then emit(c.text, "tooltip") end
  if c.flavor then emit(c.flavor, "flavour") end
end

line("")
line("-- == Opponents == (name, short name, title, and what they say)")
local OPP_NOTE = { name = "full name", short = "short name", title = "who they are", hello = "a match starts",
  win = "they win", lose = "you win", hit = "they hit your Morale hard", hurt = "you hit theirs hard",
  low = "they're close to losing", rematch = "a heroic rematch starts" }
for _, o in ipairs(ns.Opponents) do
  line("-- " .. o.id)
  for _, k in ipairs(ns.OPPONENT_TEXT) do
    if o[k] then emit(o[k], OPP_NOTE[k]) end
  end
end

line("")
line("-- == Tutorial == (Dorn coaches you through four rounds)")
for i, r in ipairs(ns.Tutorial.ROUNDS) do
  emit(r.say, ("round %d, while you plan"):format(i))
  emit(r.watch, ("round %d, while it plays out"):format(i))
  emit(r.after, ("round %d, afterwards"):format(i))
end
emit(ns.Tutorial.FREE, "after round 4")

for _, f in ipairs(files) do
  local keys = foundOrder[f]
  if keys then
    local any = false
    for _, key in ipairs(keys) do if not emitted[key] then any = true end end
    if any then
      line("")
      line("-- == " .. f .. " ==")
      for _, key in ipairs(keys) do emit(key) end
    end
  end
end

-- keys looked up while loading that nothing above covers
local stray = {}
for key in pairs(loaded) do if not emitted[key] then stray[#stray + 1] = key end end
table.sort(stray)
check(#stray == 0, "every key looked up while loading is in the template (" .. table.concat(stray, " | ") .. ")")

local template = table.concat(out, "\n") .. "\n"
local path = ROOT .. "/Locales/enUS.lua"
if WRITE then
  local fh = assert(io.open(path, "wb"))
  fh:write(template)
  fh:close()
  print("wrote Locales/enUS.lua")
else
  local fh = io.open(path, "rb")
  local cur = fh and fh:read("*a")
  if fh then fh:close() end
  check(cur == template, "Locales/enUS.lua is up to date (python tests/run_tests.py locale write)")
end

local keys = {}
for key in pairs(emitted) do keys[#keys + 1] = key end
table.sort(keys)
print(("%d texts in the template"):format(#keys))

-- ---------------------------------------------------------------------------
-- The language files
-- ---------------------------------------------------------------------------
local function specs(s)
  local list = {}
  for spec in s:gmatch("%%[-+ #0]*%d*%.?%d*[cdiouxXeEfgGqs%%]") do list[#list + 1] = spec end
  return table.concat(list, " ")
end
local function count(s, pat)
  local n = 0
  for _ in s:gmatch(pat) do n = n + 1 end
  return n
end
-- width in "letters": Chinese, Japanese and Korean characters count double
local function width(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local w = 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local b = ch:byte(1)
    w = w + ((b >= 0xE3 and b <= 0xED) and 2 or 1)
  end
  return w
end

local cardText = {}
for _, c in ipairs(Cards.list) do
  cardText[c.name] = "name"
  if c.short then cardText[c.short] = "short" end
end
local LIMIT = { name = 30, short = 46 }

for _, lf in ipairs(localeFiles) do
  local T, codes = {}, nil
  local fake = { NewLocale = function(...) codes = { ... }; return T end }
  local ok, err = pcall(assert(loadfile(ROOT .. "/" .. lf.path)), "Deckhand", fake)
  check(ok, lf.path .. " loads (" .. tostring(err) .. ")")
  local claims = false
  for _, c in ipairs(codes or {}) do if c == lf.code then claims = true end end
  check(claims, lf.path .. " is for " .. lf.code)
  local missing, extra, bad, same = {}, {}, {}, 0
  for _, key in ipairs(keys) do
    local v = T[key]
    if v == nil then
      missing[#missing + 1] = key
    elseif type(v) ~= "string" or v == "" then
      bad[#bad + 1] = "not text: " .. key
    else
      if v == key then same = same + 1 end
      if specs(v) ~= specs(key) then bad[#bad + 1] = ("placeholders: %s => %s"):format(key, v) end
      if v:find("%%%d+%$") then bad[#bad + 1] = "numbered placeholder: " .. v end
      if count(v, "|c%x%x%x%x%x%x%x%x") ~= count(key, "|c%x%x%x%x%x%x%x%x") or count(v, "|r") ~= count(key, "|r") then
        bad[#bad + 1] = ("colour codes: %s => %s"):format(key, v)
      end
      if count(v, "\n") ~= count(key, "\n") then bad[#bad + 1] = ("line breaks: %s => %s"):format(key, v) end
      local kind = cardText[key]
      if kind and width(v) > LIMIT[kind] then
        bad[#bad + 1] = ("too long for a card (%d > %d): %s"):format(width(v), LIMIT[kind], v)
      end
    end
  end
  for key in pairs(T) do
    if not emitted[key] then extra[#extra + 1] = key end
  end
  table.sort(extra)
  local function first(list)
    local t = {}
    for i = 1, math.min(5, #list) do t[i] = list[i] end
    return table.concat(t, "\n    ")
  end
  check(#missing == 0, ("%s: %d texts not translated:\n    %s"):format(lf.code, #missing, first(missing)))
  check(#extra == 0, ("%s: %d texts that aren't in the template:\n    %s"):format(lf.code, #extra, first(extra)))
  check(#bad == 0, ("%s: %d problems:\n    %s"):format(lf.code, #bad, first(bad)))
  print(("%s: %d of %d translated, %d the same as the English"):format(lf.code, #keys - #missing, #keys, same))
end

print(("%d passed, %d failed"):format(passed, failed))
RESULT = failed > 0
