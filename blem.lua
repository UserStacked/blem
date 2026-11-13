--[[
	╔══════════════════════════════════════════════════════════════════╗
	║               BETTER LIFE EXPANSION MOD  ·  v1.0.0               ║
	║                         Created by BZM                           ║
	╚══════════════════════════════════════════════════════════════════╝

	Quality-of-life automation for the Sari-Sari Store game (PlaceId 104178853788462),
	run as a single script in the Velocity executor.

	How to run
	  Paste this whole file into Velocity and execute it (or save it in Velocity's workspace
	  folder and run: loadstring(readfile("BetterLifeExpansionMod.lua"))() ). RightShift
	  shows/hides the menu. Running it again replaces the previous copy.

	How it works
	  • Everything goes through the game's normal client interactions: proximity prompts
	    (ProximityPrompt:InputHoldBegin/End, held for their full time), real (virtual) mouse
	    clicks on the game's buttons, Humanoid movement and Tool:Activate(). No RemoteEvents
	    are called directly, no payment or balance is ever faked, and nothing hooks, disables
	    or hides from the game's scripts. Disabled or covered buttons are never pressed.
	  • Every action is verified: a step only counts as done when the game's state shows it
	    happened (window closed, box count dropped, pile gone, debt row gone, …). Anything
	    that can't be verified is left for you and explained in the Activity Logs.
	  • Plot features only act on a plot proven to be yours (owner marker). If the game shows
	    no owner marker, confirm your plot once per session: Settings → "This is my plot".
	  • All automation starts OFF. Turn features on from the menu.
	  • Settings → "Export game scan" writes what the mod can see of the game to a TXT file
	    (useful if a feature reports that something wasn't found).

	Use this only where the game owner permits automation (your own/private test place).
]]

local VERSION = "1.0.0"
local GAME_PLACE_ID = 104178853788462

--==================================================================================
-- 0. SINGLE INSTANCE: unload a previous copy before starting a new one
--==================================================================================
local GENV = (type(getgenv) == "function" and getgenv()) or _G
if type(GENV.BLEM) == "table" and type(GENV.BLEM.unload) == "function" then
	pcall(GENV.BLEM.unload, "reloaded")
end

--==================================================================================
-- 1. EXECUTOR CAPABILITIES (nothing is assumed; missing functions are reported)
--==================================================================================
local Env = {}

local function pickFn(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "function" then
			return f
		end
	end
	return nil
end

Env.getconnections = pickFn(getconnections, get_signal_cons)
Env.firesignal = pickFn(firesignal)
Env.fireproximityprompt = pickFn(fireproximityprompt)
Env.writefile = pickFn(writefile)
Env.readfile = pickFn(readfile)
Env.isfile = pickFn(isfile)
Env.isfolder = pickFn(isfolder)
Env.makefolder = pickFn(makefolder)
Env.gethui = pickFn(gethui, get_hidden_gui)
Env.setclipboard = pickFn(setclipboard, toclipboard, set_clipboard)
Env.identifyexecutor = pickFn(identifyexecutor, getexecutorname)
Env.ROOT = "BetterLifeMod"

local serviceCache = {}
local function service(name)
	if serviceCache[name] then
		return serviceCache[name]
	end
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	if ok and svc then
		serviceCache[name] = svc
		return svc
	end
	return nil
end

local Players = service("Players")
local RunService = service("RunService")
local UserInputService = service("UserInputService")
local PathfindingService = service("PathfindingService")
local HttpService = service("HttpService")
local GuiService = service("GuiService")
local CoreGui = service("CoreGui")
local Workspace = service("Workspace") or workspace

function Env.vim()
	return service("VirtualInputManager")
end

function Env.executorName()
	if Env.identifyexecutor then
		local ok, name, version = pcall(Env.identifyexecutor)
		if ok and name then
			return tostring(name) .. (version and (" " .. tostring(version)) or "")
		end
	end
	return "Unknown executor"
end

function Env.ensureFolder(path)
	if not (Env.makefolder and Env.isfolder) then
		return Env.writefile ~= nil
	end
	return (pcall(function()
		local acc = ""
		for part in string.gmatch(path, "[^/]+") do
			acc = (acc == "") and part or (acc .. "/" .. part)
			if not Env.isfolder(acc) then
				Env.makefolder(acc)
			end
		end
	end))
end

function Env.write(path, content)
	if not Env.writefile then
		return false, "this executor has no writefile()"
	end
	local folder = string.match(path, "^(.*)/[^/]+$")
	if folder then
		Env.ensureFolder(folder)
	end
	local ok, err = pcall(Env.writefile, path, content)
	if not ok then
		return false, tostring(err)
	end
	return true
end

function Env.read(path)
	if not (Env.readfile and Env.isfile) then
		return nil, "this executor has no readfile()/isfile()"
	end
	local ok, exists = pcall(Env.isfile, path)
	if not ok or not exists then
		return nil, "file not found"
	end
	local ok2, content = pcall(Env.readfile, path)
	if not ok2 then
		return nil, tostring(content)
	end
	return content
end

function Env.report()
	return {
		{ name = "getconnections", ok = Env.getconnections ~= nil, use = "pressing the game's buttons (main click method)" },
		{ name = "VirtualInputManager", ok = Env.vim() ~= nil, use = "real mouse clicks and aiming (fallback click method)" },
		{ name = "firesignal", ok = Env.firesignal ~= nil, use = "last-resort button presses" },
		{ name = "fireproximityprompt", ok = Env.fireproximityprompt ~= nil, use = "fallback for in-range prompts" },
		{ name = "writefile / readfile", ok = Env.writefile ~= nil and Env.readfile ~= nil, use = "saving settings, exporting TXT logs" },
		{ name = "makefolder / isfolder", ok = Env.makefolder ~= nil and Env.isfolder ~= nil, use = "creating the BetterLifeMod folder" },
		{ name = "gethui", ok = Env.gethui ~= nil, use = "keeping the menu separate from the game's own UI" },
		{ name = "setclipboard", ok = Env.setclipboard ~= nil, use = "copying logs to the clipboard" },
	}
end

local function enumItem(enum, name)
	local ok, v = pcall(function()
		return enum[name]
	end)
	return ok and v or nil
end

--==================================================================================
-- 2. UTILITIES
--==================================================================================
local Util = {}

function Util.timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end
function Util.clock()
	return os.date("%H:%M:%S")
end
function Util.fileStamp()
	return os.date("%Y%m%d_%H%M%S")
end
function Util.trim(s)
	return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1"))
end
function Util.norm(s)
	return (string.gsub(string.lower(tostring(s or "")), "[^%w]", ""))
end
function Util.lower(s)
	return string.lower(tostring(s or ""))
end
function Util.stripTags(s)
	return (string.gsub(tostring(s or ""), "<[^>]->", ""))
end

function Util.split(s, sep)
	local out = {}
	for piece in string.gmatch(tostring(s or ""), "([^" .. sep .. "]+)") do
		local t = Util.trim(piece)
		if t ~= "" then
			out[#out + 1] = t
		end
	end
	return out
end

function Util.keywords(s)
	local out = {}
	for _, w in ipairs(Util.split(s, ",")) do
		out[#out + 1] = string.lower(w)
	end
	return out
end

function Util.containsAny(text, words)
	local t = string.lower(tostring(text or ""))
	for _, w in ipairs(words) do
		if w ~= "" and string.find(t, w, 1, true) then
			return true, w
		end
	end
	return false, nil
end

function Util.find(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

local NEGATIONS = { ["not"] = true, ["no"] = true, ["hindi"] = true, ["di"] = true, ["never"] = true, ["without"] = true, ["un"] = true }

-- Whole-word/phrase match that ignores negated uses: "verified" matches "Payment verified" but not
-- "unverified" or "not verified". Returns true and the phrase.
function Util.hasWord(text, words)
	local t = string.lower(tostring(text or ""))
	for _, w in ipairs(words) do
		if w ~= "" then
			local pattern = "%f[%w]" .. string.gsub(w, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "%f[%W]"
			local init = 1
			while true do
				local s, e = string.find(t, pattern, init)
				if not s then
					break
				end
				local before = string.match(string.sub(t, 1, s - 1), "(%w+)%W*$")
				if not (before and NEGATIONS[before]) then
					return true, w
				end
				init = e + 1
			end
		end
	end
	return false, nil
end

function Util.merge(defaults, saved)
	local out = {}
	for k, v in pairs(defaults) do
		local s = (type(saved) == "table") and saved[k] or nil
		if type(v) == "table" then
			out[k] = Util.merge(v, s)
		elseif s ~= nil and type(s) == type(v) then
			out[k] = s
		else
			out[k] = v
		end
	end
	return out
end

-- First amount in a string: "₱1,234.50" -> 1234.5, "Change: 63" -> 63
function Util.parseMoney(s)
	if s == nil then
		return nil
	end
	local num = string.match(Util.stripTags(s), "%d[%d,]*%.?%d*")
	if not num then
		return nil
	end
	num = string.gsub(num, ",", "")
	num = string.gsub(num, "%.$", "")
	return tonumber(num)
end

function Util.parseFraction(s)
	local a, b = string.match(Util.stripTags(s or ""), "(%d+)%s*/%s*(%d+)")
	if a then
		return tonumber(a), tonumber(b)
	end
	return nil, nil
end

function Util.hasLetters(s)
	return string.find(tostring(s or ""), "%a") ~= nil
end

function Util.formatMoney(n)
	if n == nil then
		return "—"
	end
	local neg = n < 0
	local formatted = tostring(math.floor(math.abs(n) + 0.5))
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return (neg and "-₱" or "₱") .. formatted
end

function Util.ago(t)
	if not t then
		return "never"
	end
	local d = math.max(0, math.floor(os.clock() - t))
	if d < 60 then
		return d .. "s ago"
	end
	if d < 3600 then
		return math.floor(d / 60) .. "m ago"
	end
	return math.floor(d / 3600) .. "h ago"
end

--[[ Change-making plan: the bills/coins to click so the total equals `amount`.
     Uses the fewest pieces (dynamic programming up to ₱5,000, greedy above). ]]
function Util.changePlan(amount, values)
	amount = math.floor((amount or 0) + 0.5)
	if amount < 0 then
		return nil
	end
	if amount == 0 then
		return {}
	end
	local vals = {}
	for _, v in ipairs(values) do
		if v > 0 then
			vals[#vals + 1] = v
		end
	end
	table.sort(vals, function(a, b)
		return a > b
	end)
	if #vals == 0 then
		return nil
	end
	local plan = {}
	if amount <= 5000 then
		local best, from = { [0] = 0 }, {}
		for a = 1, amount do
			for _, v in ipairs(vals) do
				if v <= a and best[a - v] ~= nil then
					local c = best[a - v] + 1
					if best[a] == nil or c < best[a] then
						best[a] = c
						from[a] = v
					end
				end
			end
		end
		if best[amount] == nil then
			return nil
		end
		local a = amount
		while a > 0 do
			plan[#plan + 1] = from[a]
			a = a - from[a]
		end
	else
		local rest = amount
		for _, v in ipairs(vals) do
			while rest >= v do
				plan[#plan + 1] = v
				rest = rest - v
			end
		end
		if rest ~= 0 then
			return nil
		end
	end
	table.sort(plan, function(x, y)
		return x > y
	end)
	return plan
end

function Util.alive(inst)
	if inst == nil then
		return false
	end
	local ok, parent = pcall(function()
		return inst.Parent
	end)
	return ok and parent ~= nil
end

function Util.fullName(inst)
	if inst == nil then
		return "(nil)"
	end
	local ok, name = pcall(function()
		return inst:GetFullName()
	end)
	return ok and name or tostring(inst)
end

function Util.position(inst)
	if inst == nil then
		return nil
	end
	local kind = typeof(inst)
	if kind == "Vector3" then
		return inst
	end
	if kind == "CFrame" then
		return inst.Position
	end
	if kind ~= "Instance" then
		return nil
	end
	local ok, pos = pcall(function()
		if inst:IsA("BasePart") then
			return inst.Position
		elseif inst:IsA("Model") then
			return inst:GetPivot().Position
		elseif inst:IsA("Attachment") then
			return inst.WorldPosition
		elseif inst:IsA("ProximityPrompt") or inst:IsA("Humanoid") then
			return Util.position(inst.Parent)
		end
		local part = inst:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end)
	return ok and pos or nil
end

function Util.distance(a, b)
	local pa, pb = Util.position(a), Util.position(b)
	if not pa or not pb then
		return math.huge
	end
	return (pa - pb).Magnitude
end

-- On screen: the object and every GUI ancestor visible, and its ScreenGui enabled.
function Util.guiVisible(obj)
	if not Util.alive(obj) then
		return false
	end
	local ok, res = pcall(function()
		local cur = obj
		while cur and cur ~= game do
			if cur:IsA("GuiObject") then
				if not cur.Visible then
					return false
				end
			elseif cur:IsA("LayerCollector") then
				return cur.Enabled
			end
			cur = cur.Parent
		end
		return false
	end)
	return ok and res or false
end

--==================================================================================
-- 3. MAID (cleanup tracking) & SIGNAL
--==================================================================================
local Maid = {}
Maid.__index = Maid

local function cleanupTask(t)
	local kind = typeof(t)
	if kind == "RBXScriptConnection" then
		pcall(function()
			t:Disconnect()
		end)
	elseif kind == "Instance" then
		pcall(function()
			t:Destroy()
		end)
	elseif kind == "thread" then
		pcall(task.cancel, t)
	elseif type(t) == "function" then
		pcall(t)
	elseif type(t) == "table" then
		if type(t.Disconnect) == "function" then
			pcall(t.Disconnect, t)
		elseif type(t.Destroy) == "function" then
			pcall(t.Destroy, t)
		end
	end
end

function Maid.new()
	return setmetatable({ _tasks = {}, _keyed = {} }, Maid)
end

-- A task given with a key replaces the previous task under that key (no duplicate connections).
function Maid:give(t, key)
	if t == nil then
		return nil
	end
	if key ~= nil then
		if self._keyed[key] ~= nil then
			cleanupTask(self._keyed[key])
		end
		self._keyed[key] = t
	else
		self._tasks[#self._tasks + 1] = t
	end
	return t
end

function Maid:connect(signal, fn, key)
	return self:give(signal:Connect(fn), key)
end

function Maid:clean(key)
	local t = self._keyed[key]
	if t ~= nil then
		self._keyed[key] = nil
		cleanupTask(t)
	end
end

function Maid:destroy()
	local tasks, keyed = self._tasks, self._keyed
	self._tasks, self._keyed = {}, {}
	for i = #tasks, 1, -1 do
		cleanupTask(tasks[i])
	end
	for _, t in pairs(keyed) do
		cleanupTask(t)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { fn = fn, on = true }
	local list = self._handlers
	list[#list + 1] = handler
	return {
		Disconnect = function()
			handler.on = false
			for i, h in ipairs(list) do
				if h == handler then
					table.remove(list, i)
					break
				end
			end
		end,
	}
end

function Signal:Fire(...)
	local snapshot = {}
	for i, h in ipairs(self._handlers) do
		snapshot[i] = h
	end
	for _, h in ipairs(snapshot) do
		if h.on then
			local ok, err = pcall(h.fn, ...)
			if not ok then
				warn("[BLEM] handler error: " .. tostring(err))
			end
		end
	end
end

--==================================================================================
-- 4. SETTINGS (saved to BetterLifeMod/config.json when the executor allows files)
--==================================================================================
local DEFAULTS = {
	-- Transaction Management
	shortcutEnabled = false,
	-- Cashier Automation
	cashierEnabled = false,
	payCash = true,
	payKashG = true,
	utangAccept = false,
	utangDecline = false,
	kashgPolicy = "Verified only",
	kashgDeclineInvalid = false,
	requireCustomer = true,
	customerRadius = 16,
	successWords = "success,successful,paid,payment received,received,sent,completed,confirmed,verified,approved",
	failWords = "failed,insufficient,declined,fake,invalid,error,pending,expired,scam,kulang,not enough,unverified,unpaid,not received,not paid,cancelled",
	-- Auto Stack
	stackEnabled = false,
	stackThreshold = 50,
	stackPickup = true,
	stackStoreLeftovers = false,
	-- Auto Order
	orderEnabled = false,
	orderQty = 1,
	orderMaxProducts = 5,
	orderMinMoney = 0,
	orderPendingMin = 10,
	orderUseAlert = true,
	orderInterval = 45,
	-- Utang Collection
	utangEnabled = false,
	utangInterval = 60,
	utangPriority = "Largest first",
	-- NPC / Thief
	thiefEnabled = false,
	thiefSwings = 3,
	thiefRounds = 3,
	thiefReturn = true,
	thiefRadius = 120,
	thiefRange = 6,
	thiefWords = "thief,magnanakaw,shoplifter,snatcher,robber,kawatan,holdaper",
	-- Ice Cream & Taho
	bonusReapply = false,
	bonusItem = "Any",
	-- Auto Cleaning
	cleanEnabled = false,
	cleanIndoor = true,
	cleanOutdoor = true,
	-- Settings
	movement = "Walk",
	actionDelay = 0.3,
	clickMethod = "Auto",
	settingsVersion = 2,
	manualOverride = true,
	overrideSeconds = 4,
	toggleKey = "RightShift",
	plotChoice = "Auto",
	debugLog = false,
}

-- Feature switches always start OFF when the script loads (never resume automation silently).
local ENABLE_KEYS = {
	shortcutEnabled = true,
	cashierEnabled = true,
	stackEnabled = true,
	orderEnabled = true,
	utangEnabled = true,
	thiefEnabled = true,
	bonusReapply = true,
	cleanEnabled = true,
}

local CONFIG_PATH = Env.ROOT .. "/config.json"
local Cfg = Util.merge(DEFAULTS, nil)
local CfgChanged = Signal.new()
local saveQueued = false

local function saveConfig()
	if not Env.writefile or not HttpService then
		return false
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode(Cfg)
	end)
	if not ok then
		return false
	end
	return Env.write(CONFIG_PATH, json)
end

local function loadConfig()
	local content = Env.read(CONFIG_PATH)
	if content and HttpService then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(content)
		end)
		if ok and type(data) == "table" then
			Cfg = Util.merge(DEFAULTS, data)
		end
	end
	for k in pairs(ENABLE_KEYS) do
		Cfg[k] = false
	end
	-- Plot names are handed out per server, so a plot picked last time may belong to someone else now.
	Cfg.plotChoice = "Auto"
	-- Older settings files kept the shorter failure-word list; add the negated words.
	if (tonumber(Cfg.settingsVersion) or 1) < 2 then
		Cfg.failWords = DEFAULTS.failWords
		Cfg.settingsVersion = 2
	end
end

local function setCfg(key, value)
	if Cfg[key] == value then
		return
	end
	Cfg[key] = value
	CfgChanged:Fire(key, value)
	if not saveQueued then
		saveQueued = true
		task.delay(1, function()
			saveQueued = false
			saveConfig()
		end)
	end
end

--==================================================================================
-- 5. ACTIVITY LOG (categories, levels, filtering, TXT export)
--==================================================================================
local Log = { entries = {}, max = 2000, nextId = 1, added = Signal.new(), total = 0 }
Log.CATEGORIES = { "System", "Player", "Transaction", "Cashier", "Stack", "Order", "Utang", "Thief", "Bonus", "Clean" }
Log.LEVELS = { "INFO", "SUCCESS", "WARN", "ERROR", "DEBUG" }

function Log.add(category, level, message)
	if level == "DEBUG" and not Cfg.debugLog then
		return nil
	end
	message = tostring(message)
	local now = os.clock()
	local last = Log.entries[#Log.entries]
	-- Collapse identical consecutive messages (loops never spam the log).
	if last and last.category == category and last.level == level and last.message == message and now - last.t < 15 then
		last.repeats = last.repeats + 1
		last.t = now
		last.date = Util.timestamp()
		last.stamp = Util.clock()
		Log.added:Fire(last, true)
		return last
	end
	local e = {
		id = Log.nextId,
		t = now,
		date = Util.timestamp(),
		stamp = Util.clock(),
		category = category,
		level = level,
		message = message,
		repeats = 1,
	}
	Log.nextId = Log.nextId + 1
	Log.total = Log.total + 1
	Log.entries[#Log.entries + 1] = e
	while #Log.entries > Log.max do
		table.remove(Log.entries, 1)
	end
	Log.added:Fire(e, false)
	return e
end

function Log.info(c, m)
	return Log.add(c, "INFO", m)
end
function Log.success(c, m)
	return Log.add(c, "SUCCESS", m)
end
function Log.warn(c, m)
	return Log.add(c, "WARN", m)
end
function Log.error(c, m)
	return Log.add(c, "ERROR", m)
end
function Log.debug(c, m)
	return Log.add(c, "DEBUG", m)
end

function Log.format(e)
	local rep = e.repeats > 1 and (" (x" .. e.repeats .. ")") or ""
	return string.format("[%s] [%-7s] [%-11s] %s%s", e.date, e.level, e.category, e.message, rep)
end

function Log.matches(e, category, level, search)
	if category and category ~= "All" and e.category ~= category then
		return false
	end
	if level and level ~= "All" then
		if level == "Problems" then
			if e.level ~= "WARN" and e.level ~= "ERROR" then
				return false
			end
		elseif e.level ~= level then
			return false
		end
	end
	if search and search ~= "" and not string.find(string.lower(e.message), string.lower(search), 1, true) then
		return false
	end
	return true
end

function Log.filter(category, level, search)
	local out = {}
	for _, e in ipairs(Log.entries) do
		if Log.matches(e, category, level, search) then
			out[#out + 1] = e
		end
	end
	return out
end

function Log.export(list, filterLabel)
	local lines = {
		"BETTER LIFE EXPANSION MOD v" .. VERSION .. " · Created by BZM",
		"Activity log export · " .. Util.timestamp(),
		"Filter: " .. (filterLabel or "All"),
		"Entries: " .. #list,
		string.rep("=", 90),
	}
	local byCat = {}
	for _, e in ipairs(list) do
		byCat[e.category] = (byCat[e.category] or 0) + 1
	end
	local summary = {}
	for _, c in ipairs(Log.CATEGORIES) do
		if byCat[c] then
			summary[#summary + 1] = c .. " " .. byCat[c]
		end
	end
	lines[#lines + 1] = "By category: " .. (#summary > 0 and table.concat(summary, " · ") or "—")
	lines[#lines + 1] = string.rep("=", 90)
	for _, e in ipairs(list) do
		lines[#lines + 1] = Log.format(e)
	end
	local path = Env.ROOT .. "/logs/BLEM_log_" .. Util.fileStamp() .. ".txt"
	local ok, err = Env.write(path, table.concat(lines, "\n") .. "\n")
	if ok then
		return path
	end
	return nil, err
end

--==================================================================================
-- 6. SHARED STATE (what the dashboard shows)
--==================================================================================
local State = {
	features = {},
	order = {},
	pending = { customers = 0, piles = 0, stands = 0, orders = 0, utang = 0, thieves = 0 },
	transaction = { stage = "Idle", kind = "—", amount = nil, since = nil },
	history = {},
	tx = { cash = 0, change = 0, kashg = 0, utang = 0, declined = 0, manual = 0, failed = 0 },
	utang = { count = nil, total = nil, rows = {}, lastRead = nil, collected = 0, collectedTotal = 0 },
	stock = { stands = {}, boxes = {}, deliveries = {}, lastScan = nil },
	orders = { pending = {}, catalog = {}, lastOrder = nil, lastNeeds = {} },
	bonus = { status = "Checking…", active = nil, source = nil, lastUsed = nil, lastItem = nil },
	thief = { last = nil, stopped = 0, escaped = 0, swings = 0, seen = {} },
	clean = { cleaned = 0, lastPile = nil },
	totals = { completed = 0, failed = 0 },
}

function State.feature(key, title, category)
	if not State.features[key] then
		State.features[key] = {
			key = key,
			title = title,
			category = category,
			status = "OFF",
			detail = "",
			completed = 0,
			failed = 0,
			lastError = nil,
		}
		State.order[#State.order + 1] = key
	end
	return State.features[key]
end

function State.set(key, status, detail)
	local f = State.features[key]
	if f then
		f.status = status
		f.detail = detail or ""
	end
end

function State.complete(key, n)
	n = n or 1
	local f = State.features[key]
	if f then
		f.completed = f.completed + n
	end
	State.totals.completed = State.totals.completed + n
end

function State.fail(key, msg)
	local f = State.features[key]
	if f then
		f.failed = f.failed + 1
		f.lastError = msg
	end
	State.totals.failed = State.totals.failed + 1
end

--==================================================================================
-- 7. PLAYER (local player, character, respawns)
--==================================================================================
local P = { player = nil, character = nil, humanoid = nil, root = nil, gui = nil, alive = false, generation = 0 }
P.respawned = Signal.new()

function P.init(maid)
	P.player = Players.LocalPlayer
	while not P.player do
		task.wait(0.1)
		P.player = Players.LocalPlayer
	end
	P.gui = P.player:WaitForChild("PlayerGui", 30)

	local function bind(char)
		P.generation = P.generation + 1
		local gen = P.generation
		P.character = char
		P.alive = false
		local hum = char:WaitForChild("Humanoid", 15)
		local root = char:WaitForChild("HumanoidRootPart", 15)
		if gen ~= P.generation then
			return -- replaced by a newer character while waiting
		end
		if not hum or not root then
			Log.error("Player", "Character loaded without a Humanoid/HumanoidRootPart; waiting for the next respawn.")
			return
		end
		P.humanoid, P.root = hum, root
		P.alive = hum.Health > 0
		maid:connect(hum.Died, function()
			if gen == P.generation then
				P.alive = false
				Log.warn("Player", "Your character died. Automation pauses until you respawn.")
			end
		end, "humanoidDied")
		Log.info("Player", "Character ready (" .. P.player.Name .. ").")
		P.respawned:Fire(char)
	end

	if P.player.Character then
		task.spawn(bind, P.player.Character)
	end
	maid:connect(P.player.CharacterAdded, function(char)
		task.spawn(bind, char)
	end)
	maid:connect(P.player.CharacterRemoving, function(char)
		if char == P.character then
			P.alive = false
			P.humanoid, P.root, P.character = nil, nil, nil
		end
	end)
end

function P.ready()
	return P.alive and Util.alive(P.root) and Util.alive(P.humanoid) and P.humanoid.Health > 0
end

function P.backpack()
	return P.player and P.player:FindFirstChildOfClass("Backpack")
end

function P.tools()
	local out = {}
	for _, container in ipairs({ P.character, P.backpack() }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") then
					out[#out + 1] = t
				end
			end
		end
	end
	return out
end

function P.findTool(pred)
	for _, t in ipairs(P.tools()) do
		local ok, res = pcall(pred, t)
		if ok and res then
			return t
		end
	end
	return nil
end

function P.toolNamed(name)
	local want = Util.norm(name)
	return P.findTool(function(t)
		return Util.norm(t.Name) == want
	end)
end

function P.equipped()
	return P.character and P.character:FindFirstChildOfClass("Tool") or nil
end

local moneyCache = { t = -100, value = nil, source = nil }
local MONEY_NAMES = { "money", "cash", "pera", "coins", "balance", "wallet", "peso" }

-- Reads the player's money from leaderstats or the wallet HUD (read-only, cached 2 s).
function P.money()
	if os.clock() - moneyCache.t < 2 then
		return moneyCache.value, moneyCache.source
	end
	moneyCache.t = os.clock()
	moneyCache.value, moneyCache.source = nil, nil
	local ls = P.player and P.player:FindFirstChild("leaderstats")
	if ls then
		for _, v in ipairs(ls:GetChildren()) do
			if v:IsA("ValueBase") and Util.containsAny(v.Name, MONEY_NAMES) then
				local n = tonumber(v.Value)
				if n then
					moneyCache.value, moneyCache.source = n, "leaderstats." .. v.Name
					return n, moneyCache.source
				end
			end
		end
	end
	if P.gui then
		for _, g in ipairs(P.gui:GetChildren()) do
			if g:IsA("ScreenGui") and string.find(string.lower(g.Name), "wallet", 1, true) and g.Enabled then
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("TextLabel") and Util.guiVisible(d) then
						local text = d.Text
						if string.find(text, "₱", 1, true) or string.find(text, "%d") then
							local n = Util.parseMoney(text)
							if n then
								moneyCache.value, moneyCache.source = n, g.Name .. " HUD"
								return n, moneyCache.source
							end
						end
					end
				end
			end
		end
	end
	return nil, nil
end

--==================================================================================
-- 8. PLOT (your own plot + an index of its proximity prompts)
--==================================================================================
local Plot = { model = nil, method = "not found", prompts = {}, changed = Signal.new(), maid = Maid.new() }

local function classifyPrompt(p)
	local name = p.Name
	local action = Util.lower(p.ActionText)
	local object = Util.lower(p.ObjectText)
	local path = Util.lower(Util.fullName(p))
	if name == "RegisterPrompt" or action == "checkout" then
		return "register"
	elseif name == "UtangPrompt" or string.find(object, "utang", 1, true) then
		return "utangBook"
	elseif name == "LaptopPrompt" or action == "open shop" then
		return "laptop"
	elseif name == "OpenClosePrompt" then
		return "sign"
	elseif name == "CleanPilePrompt" then
		return "pile", (string.find(path, "leaf", 1, true) and "leaf" or "dust")
	elseif name == "CleaningPrompt" or (action == "use" and string.find(object, "broom", 1, true)) then
		local leaf = string.find(object, "stick", 1, true) or string.find(path, "broomstick", 1, true)
		return "broomStand", (leaf and "leaf" or "dust")
	elseif name == "PickupPrompt" or action == "pick up" then
		return "pickup"
	elseif name == "RestockPrompt" or action == "restock" then
		return "restock"
	elseif name == "BoxPrompt" or string.find(object, "box shelf", 1, true) then
		return "boxShelf"
	elseif name == "PisoWifiPrompt" then
		return "pisowifi"
	elseif name == "PhonePrompt" then
		return "phone"
	end
	return "other"
end

--[[ Ownership of a plot. Returns score, how, foreign:
     100/90 = an owner attribute/value equal to you; 50 = an owner sign whose whole text is your
     name (or "<name>'s …"); foreign = true when an owner marker names somebody else. ]]
local function plotOwnerScore(plot)
	local plr = P.player
	local uid, uname, dname = plr.UserId, plr.Name, plr.DisplayName
	local foreign = false
	local function matches(v)
		if v == plr then
			return true
		end
		if type(v) == "number" then
			return v == uid
		end
		if type(v) == "string" then
			return v == uname or v == tostring(uid) or (dname ~= nil and v == dname)
		end
		return false
	end
	local function isOwnerKey(name)
		local lk = string.lower(name)
		return string.find(lk, "owner", 1, true) ~= nil or lk == "userid" or lk == "player"
	end
	local ok, attrs = pcall(function()
		return plot:GetAttributes()
	end)
	if ok then
		for k, v in pairs(attrs) do
			if isOwnerKey(k) then
				if matches(v) then
					return 100, "owner attribute '" .. k .. "'", false
				elseif v ~= nil and v ~= "" and v ~= 0 then
					foreign = true
				end
			end
		end
	end
	for _, holder in ipairs({ plot, plot:FindFirstChild("Config"), plot:FindFirstChild("Settings"), plot:FindFirstChild("Data") }) do
		if holder then
			for _, c in ipairs(holder:GetChildren()) do
				if c:IsA("ValueBase") and isOwnerKey(c.Name) then
					local okv, val = pcall(function()
						return c.Value
					end)
					if okv and matches(val) then
						return 90, "owner value '" .. c.Name .. "'", false
					elseif okv and val ~= nil and val ~= "" and val ~= 0 then
						foreign = true
					end
				end
			end
		end
	end
	if foreign then
		return 0, nil, true
	end
	-- Owner sign: the whole text must be your name, or start with "<name>'s".
	local names = {}
	for _, n in ipairs({ uname, dname }) do
		if n and n ~= "" then
			names[#names + 1] = string.lower(n)
		end
	end
	local okd, descendants = pcall(function()
		return plot:GetDescendants()
	end)
	if okd then
		for _, d in ipairs(descendants) do
			if d:IsA("TextLabel") and d.Text ~= "" then
				local t = string.lower(Util.trim(Util.stripTags(d.Text)))
				for _, n in ipairs(names) do
					if t == n or string.sub(t, 1, #n + 2) == n .. "'s" or string.sub(t, 1, #n + 4) == n .. "’s" then
						return 50, "owner sign '" .. Util.trim(Util.stripTags(d.Text)) .. "'", false
					end
				end
			end
		end
	end
	return 0, nil, false
end

function Plot.list()
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then
		return {}
	end
	local out = {}
	for _, p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") or p:IsA("Folder") then
			out[#out + 1] = p
		end
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

function Plot.center(plot)
	plot = plot or Plot.model
	if not plot then
		return nil
	end
	if plot:IsA("Model") then
		local ok, cf = pcall(function()
			return plot:GetPivot()
		end)
		if ok then
			return cf.Position
		end
	end
	local reg = Plot.first("register")
	if reg then
		return Util.position(reg.prompt)
	end
	return Util.position(plot)
end

-- Returns plot, method, trusted. Features that act on a plot only run when trusted is true.
function Plot.detect()
	local plots = Plot.list()
	if #plots == 0 then
		return nil, "Workspace.Plots not found", false
	end
	if Cfg.plotChoice ~= "Auto" then
		for _, p in ipairs(plots) do
			if p.Name == Cfg.plotChoice then
				local score, how, foreign = plotOwnerScore(p)
				if foreign then
					Log.error("System", p.Name .. " belongs to another player; ignoring your manual choice.")
					break
				end
				if score > 0 then
					return p, "chosen in Settings, confirmed by " .. how, true
				end
				return p, "chosen in Settings (no owner marker to confirm it)", true
			end
		end
	end
	local best, bestScore, bestHow, tie = nil, 0, nil, false
	for _, p in ipairs(plots) do
		local score, how = plotOwnerScore(p)
		if score > bestScore then
			best, bestScore, bestHow, tie = p, score, how, false
		elseif score > 0 and score == bestScore then
			tie = true
		end
	end
	if best and not tie then
		return best, bestHow, true
	end
	if tie then
		return nil, "several plots look like yours; pick yours in Settings → Plot", false
	end
	-- Not proven: show the nearest plot, but don't act on it until you confirm it in Settings.
	local pos = P.root and P.root.Position
	if pos then
		local nearest, nd = nil, math.huge
		for _, p in ipairs(plots) do
			local score, _, foreign = plotOwnerScore(p)
			local c = Util.position(p)
			if not foreign and c and (c - pos).Magnitude < nd then
				nearest, nd = p, (c - pos).Magnitude
			end
		end
		if nearest then
			return nearest, "GUESS: nearest plot (no owner marker) — confirm it in Settings → Plot", false
		end
	end
	return nil, "no plot owner marker found", false
end

-- Whether plot-acting features may run, and why not.
function Plot.usable()
	if not Plot.model or not Util.alive(Plot.model) then
		return false, "Your plot wasn't found — pick it in Settings → Plot"
	end
	if not Plot.trusted then
		return false, "Not sure " .. Plot.model.Name .. " is yours — confirm it in Settings → Plot"
	end
	return true
end

-- Your plot's bounding box (cached) and a containment test with a margin in studs.
function Plot.contains(pos, margin)
	local plot = Plot.model
	if not (plot and pos) then
		return false
	end
	margin = margin or 0
	if not Plot.boxCF or Plot.boxFor ~= plot or os.clock() - (Plot.boxAt or -100) > 30 then
		local ok, cf, size = pcall(function()
			return plot:GetBoundingBox()
		end)
		if ok and cf then
			Plot.boxCF, Plot.boxSize, Plot.boxFor, Plot.boxAt = cf, size, plot, os.clock()
		else
			Plot.boxCF = nil
		end
	end
	if not Plot.boxCF then
		local c = Plot.center()
		return c ~= nil and (pos - c).Magnitude <= Cfg.thiefRadius
	end
	local rel = Plot.boxCF:PointToObjectSpace(pos)
	local half = Plot.boxSize / 2
	return math.abs(rel.X) <= half.X + margin and math.abs(rel.Y) <= half.Y + margin + 20 and math.abs(rel.Z) <= half.Z + margin
end

function Plot.addPrompt(p)
	if Plot.prompts[p] then
		return
	end
	local ok, kind, sub = pcall(classifyPrompt, p)
	if not ok then
		return
	end
	Plot.prompts[p] = { prompt = p, kind = kind, sub = sub }
end

function Plot.bind(plot, method, trusted)
	Plot.maid:destroy()
	Plot.prompts = {}
	Plot.model, Plot.method, Plot.trusted = plot, method, trusted and true or false
	Plot.boxCF = nil
	if not plot then
		Plot.changed:Fire()
		return
	end
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			Plot.addPrompt(d)
		end
	end
	Plot.maid:connect(plot.DescendantAdded, function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(function()
				Plot.addPrompt(d)
				Plot.changed:Fire()
			end)
		end
	end)
	Plot.maid:connect(plot.DescendantRemoving, function(d)
		if Plot.prompts[d] then
			Plot.prompts[d] = nil
			Plot.changed:Fire()
		end
	end)
	Plot.maid:connect(plot.AncestryChanged, function()
		if not plot.Parent then
			Log.warn("System", "Your plot was removed; re-detecting…")
			task.defer(Plot.refresh)
		end
	end)
	Plot.changed:Fire()
end

function Plot.refresh(quiet)
	local plot, method, trusted = Plot.detect()
	if quiet and plot == Plot.model and trusted == Plot.trusted then
		return plot -- nothing changed
	end
	Plot.bind(plot, method, trusted)
	if plot then
		local counts = {}
		for _, info in pairs(Plot.prompts) do
			counts[info.kind] = (counts[info.kind] or 0) + 1
		end
		local parts = {}
		for k, n in pairs(counts) do
			parts[#parts + 1] = k .. " " .. n
		end
		table.sort(parts)
		Log.add("System", trusted and "INFO" or "WARN", "Plot: " .. plot.Name .. " (" .. method .. "). Prompts found: " .. table.concat(parts, ", ")
			.. (trusted and "" or ". Plot features stay paused until you confirm the plot in Settings → Plot."))
	else
		Log.error("System", "Couldn't find your plot: " .. tostring(method) .. ".")
	end
	return plot
end

-- Live prompts of one kind (optionally a sub-kind) on your plot, nearest to you first.
function Plot.find(kind, sub)
	local out = {}
	for p, info in pairs(Plot.prompts) do
		if info.kind == kind and (sub == nil or info.sub == sub) then
			if Util.alive(p) then
				out[#out + 1] = info
			else
				Plot.prompts[p] = nil
			end
		end
	end
	local from = P.root and P.root.Position
	table.sort(out, function(a, b)
		if from then
			local da, db = Util.distance(from, a.prompt), Util.distance(from, b.prompt)
			if da ~= db then
				return da < db
			end
		end
		return Util.fullName(a.prompt) < Util.fullName(b.prompt)
	end)
	return out
end

function Plot.first(kind, sub)
	return Plot.find(kind, sub)[1]
end

--==================================================================================
-- 9. NPC REGISTRY (one scan + events; shared by cashier and thief features)
--==================================================================================
local NPC = { models = {}, added = Signal.new() }

local function considerHumanoid(h)
	local m = h.Parent
	if m and m:IsA("Model") and not Players:GetPlayerFromCharacter(m) then
		if not NPC.models[m] then
			NPC.models[m] = h
			NPC.added:Fire(m, h)
		end
	end
end

function NPC.init(maid)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.ClassName == "Humanoid" then
			considerHumanoid(d)
		end
	end
	maid:connect(Workspace.DescendantAdded, function(d)
		if d.ClassName == "Humanoid" then
			task.defer(considerHumanoid, d)
		end
	end)
	maid:connect(Workspace.DescendantRemoving, function(d)
		if d.ClassName == "Humanoid" and d.Parent then
			NPC.models[d.Parent] = nil
		end
	end)
end

function NPC.list()
	local out = {}
	for m, h in pairs(NPC.models) do
		if Util.alive(m) and Util.alive(h) and not Players:GetPlayerFromCharacter(m) then
			out[#out + 1] = { model = m, humanoid = h }
		else
			NPC.models[m] = nil
		end
	end
	return out
end

function NPC.near(pos, radius)
	local out = {}
	if not pos then
		return out
	end
	for _, n in ipairs(NPC.list()) do
		local p = Util.position(n.model)
		if p then
			local d = (p - pos).Magnitude
			if d <= radius then
				n.distance = d
				out[#out + 1] = n
			end
		end
	end
	table.sort(out, function(a, b)
		return a.distance < b.distance
	end)
	return out
end

--==================================================================================
-- 10. SCHEDULER (feature loops, cancellation, and one shared "body" lock)
--==================================================================================
-- Only one feature can move the character / hold tools / use a game window at a time.
-- Higher priority wins; a waiting higher-priority request asks the holder to pause at
-- its next safe point (thief > cashier > utang > bonus > clean > stack > order).
local CANCEL = setmetatable({}, {
	__tostring = function()
		return "cancelled"
	end,
})
local PREEMPT = setmetatable({}, {
	__tostring = function()
		return "paused for a higher-priority task"
	end,
})

local Token = {}
Token.__index = Token

function Token.new(name)
	return setmetatable({ name = name, cancelled = false, wake = false, handle = nil }, Token)
end

function Token:cancel(reason)
	self.cancelled = true
	self.reason = reason
end

function Token:check()
	if self.cancelled then
		error(CANCEL, 0)
	end
	local h = self.handle
	if h and h.preempted and h.preemptible then
		error(PREEMPT, 0)
	end
end

local Sched = { features = {}, holder = nil, waiters = {}, lastUserInput = -1000 }

function Sched.userActive()
	return Cfg.manualOverride and (os.clock() - Sched.lastUserInput) < Cfg.overrideSeconds
end

-- Cancellable wait (never cut short by "… now" buttons, so a prompt hold always lasts its full time).
function Sched.wait(token, seconds)
	local deadline = os.clock() + (seconds or 0)
	repeat
		token:check()
		task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
	until os.clock() >= deadline
	token:check()
end

-- The pause between a feature's passes; a "… now" button (wake) ends it early.
function Sched.sleep(token, seconds)
	local deadline = os.clock() + (seconds or 0)
	repeat
		token:check()
		if token.wake then
			token.wake = false
			return
		end
		task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
	until os.clock() >= deadline
	token:check()
end

-- Waits until pred() returns a truthy value (returned) or the timeout passes (nil).
function Sched.waitFor(token, pred, timeout, step)
	local deadline = os.clock() + (timeout or 5)
	while true do
		token:check()
		local ok, res = pcall(pred)
		if ok and res then
			return res
		end
		if os.clock() >= deadline then
			return nil
		end
		task.wait(step or 0.1)
	end
end

-- Waiting raises a request's effective priority (+10 per 30 s, up to +40) so nothing starves;
-- preemption still uses the base priority.
local function effectivePriority(w)
	return w.priority + math.min(40, math.floor((os.clock() - w.since) / 30) * 10)
end

local function topWaiter()
	local best, bestP = nil, -math.huge
	for _, w in ipairs(Sched.waiters) do
		local ep = effectivePriority(w)
		if ep > bestP then
			best, bestP = w, ep
		end
	end
	return best
end

local function removeWaiter(req)
	for i, w in ipairs(Sched.waiters) do
		if w == req then
			table.remove(Sched.waiters, i)
			return
		end
	end
end

function Sched.acquire(token, feature, priority, timeout, noPreempt)
	local req = { feature = feature, priority = priority, token = token, since = os.clock() }
	Sched.waiters[#Sched.waiters + 1] = req
	local deadline = os.clock() + (timeout or 20)
	while true do
		if token.cancelled then
			removeWaiter(req)
			error(CANCEL, 0)
		end
		local holder = Sched.holder
		if holder and holder.released then
			Sched.holder, holder = nil, nil
		end
		if holder == nil and topWaiter() == req and not Sched.userActive() and P.ready() then
			removeWaiter(req)
			local h = {
				feature = feature,
				priority = priority,
				token = token,
				since = os.clock(),
				cleanups = {},
				preempted = false,
				preemptible = true,
				released = false,
			}
			Sched.holder = h
			return h
		end
		if holder and priority > holder.priority and not noPreempt then
			holder.preempted = true
		end
		if os.clock() >= deadline then
			removeWaiter(req)
			return nil
		end
		task.wait(0.1)
	end
end

function Sched.release(h)
	if not h or h.released then
		return
	end
	h.released = true
	for i = #h.cleanups, 1, -1 do
		pcall(h.cleanups[i])
	end
	if Sched.holder == h then
		Sched.holder = nil
	end
end

-- Runs fn(handle) while holding the body lock; the lock is always released afterwards.
function Sched.withBody(token, feature, priority, fn, timeout, noPreempt)
	local h = Sched.acquire(token, feature, priority, timeout, noPreempt)
	if not h then
		return false, "busy"
	end
	token.handle = h
	local ok, res = pcall(fn, h)
	token.handle = nil
	Sched.release(h)
	if not ok then
		error(res, 0)
	end
	return true, res
end

function Sched.defer(token, fn)
	local h = token.handle
	if h then
		h.cleanups[#h.cleanups + 1] = fn
	end
end

function Sched.register(def)
	Sched.features[def.key] = def
	State.feature(def.key, def.title, def.category)
end

local function runFeature(f, token)
	local errors = 0
	while not token.cancelled do
		local force = f.forceNext and true or false
		f.forceNext = false
		local ok, res = pcall(f.step, token, force)
		if token.cancelled then
			break
		end
		local sleep
		if ok then
			errors = 0
			sleep = tonumber(res) or 1
		elseif res == CANCEL then
			break
		elseif res == PREEMPT then
			State.set(f.key, "PAUSED", "Paused for a higher-priority task")
			sleep = 0.5
		else
			errors = errors + 1
			local msg = tostring(res)
			Log.error(f.category, f.title .. ": " .. msg)
			State.fail(f.key, msg)
			State.set(f.key, "ERROR", msg)
			sleep = math.min(5 * errors, 30)
		end
		if not pcall(Sched.sleep, token, sleep) then
			break
		end
	end
end

function Sched.isRunning(key)
	local f = Sched.features[key]
	return f ~= nil and f.token ~= nil and not f.token.cancelled
end

function Sched.setEnabled(key, on)
	local f = Sched.features[key]
	if not f then
		return
	end
	if on then
		if Sched.isRunning(key) then
			return -- already running: never start a second loop
		end
		if f.onceToken then
			f.onceToken:cancel("feature turned on") -- the loop takes over from a manual run
		end
		local token = Token.new(key)
		f.token = token
		State.set(key, "STARTING", "")
		Log.info(f.category, f.title .. " turned ON.")
		f.thread = task.spawn(runFeature, f, token)
	else
		if f.onceToken then
			f.onceToken:cancel("turned off")
		end
		if not Sched.isRunning(key) then
			return
		end
		-- Cooperative stop only: the loop ends at its next check and always releases what it holds.
		f.token:cancel("turned off")
		f.thread = nil
		State.set(key, "OFF", "")
		Log.info(f.category, f.title .. " turned OFF.")
		if f.onStop then
			pcall(f.onStop)
		end
	end
end

-- Run a pass now: wakes a running feature (skipping its interval) or runs one pass when it is off.
function Sched.runNow(key)
	local f = Sched.features[key]
	if not f then
		return
	end
	if Sched.isRunning(key) then
		f.forceNext = true
		f.token.wake = true
		return
	end
	if f.onceThread and coroutine.status(f.onceThread) ~= "dead" then
		Log.info(f.category, f.title .. ": a manual run is already in progress.")
		return
	end
	local token = Token.new(key .. "-once")
	f.onceToken = token
	f.onceThread = task.spawn(function()
		local ok, res = pcall(f.step, token, true)
		if not ok and res ~= CANCEL then
			if res == PREEMPT then
				Log.info(f.category, f.title .. ": manual run paused for a higher-priority task.")
			else
				Log.error(f.category, f.title .. " (manual run): " .. tostring(res))
			end
		end
		if not Sched.isRunning(key) then
			State.set(key, "OFF", "Manual run finished")
		end
	end)
end

function Sched.stopAll()
	for key, f in pairs(Sched.features) do
		Sched.setEnabled(key, false)
		if f.onceToken then
			f.onceToken:cancel("unload")
		end
	end
	if Sched.holder then
		Sched.release(Sched.holder)
	end
end

--==================================================================================
-- 11. ACTIONS (walking, prompts, button clicks, tools) — every one verified
--==================================================================================
local Actions = { shown = setmetatable({}, { __mode = "k" }), mouseBusy = false }
local UIHooks = { hideAt = nil, restore = nil } -- set by the GUI so a real mouse click never lands on the menu
local ProximityPromptService = service("ProximityPromptService")

-- Tracks which prompts the engine is currently showing you (only those accept input).
function Actions.init(maid)
	if ProximityPromptService then
		maid:connect(ProximityPromptService.PromptShown, function(p)
			Actions.shown[p] = true
		end)
		maid:connect(ProximityPromptService.PromptHidden, function(p)
			Actions.shown[p] = nil
		end)
		Actions.tracking = true
	end
end

function Actions.stop()
	if P.humanoid and P.root then
		pcall(function()
			P.humanoid:MoveTo(P.root.Position)
		end)
	end
end

local function requireReady()
	if not P.ready() then
		error("your character isn't ready (dead or respawning)", 0)
	end
end

-- Pauses while you are moving the character yourself (manual override).
local function yieldToPlayer(token)
	local told = false
	while Sched.userActive() do
		if not told then
			Actions.stop()
			told = true
		end
		Sched.wait(token, 0.25)
	end
end

local PATH_OK = enumItem(Enum.PathStatus, "Success")
local WAYPOINT_JUMP = enumItem(Enum.PathWaypointAction, "Jump")

function Actions.path(from, to)
	if not PathfindingService then
		return nil
	end
	local ok, path = pcall(function()
		return PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
	end)
	if not ok or not path then
		return nil
	end
	if not pcall(function()
		path:ComputeAsync(from, to)
	end) then
		return nil
	end
	if path.Status == PATH_OK then
		local wps = path:GetWaypoints()
		if #wps >= 2 then
			return wps
		end
	end
	return nil
end

local function horizontalHalfSize(target)
	local ok, size = pcall(function()
		if typeof(target) ~= "Instance" then
			return nil
		end
		if target:IsA("BasePart") then
			return target.Size
		elseif target:IsA("Model") then
			return target:GetExtentsSize()
		end
		return nil
	end)
	if ok and size then
		return math.max(size.X, size.Z) / 2
	end
	return 1
end

-- A walkable point on the floor next to `target`, on your side of it (paths to the centre of a
-- counter or shelf usually fail because that point is inside the object).
local function standingSpot(target, goal)
	local rp = P.root.Position
	local dir = Vector3.new(rp.X - goal.X, 0, rp.Z - goal.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, 1)
	end
	local spot = goal + dir.Unit * (horizontalHalfSize(target) + 2)
	local floorY = rp.Y
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { P.character }
		local hit = Workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
		if hit then
			floorY = hit.Position.Y + 3
		end
	end)
	return Vector3.new(spot.X, floorY, spot.Z)
end

-- Follows MoveTo toward `pos` until close, stuck, or timed out. Returns true when reached.
local function moveTowards(token, pos, timeout, radius, goal)
	local t0 = os.clock()
	local lastPos, lastMove, lastIssue = P.root.Position, os.clock(), 0
	while os.clock() - t0 < timeout do
		yieldToPlayer(token)
		requireReady()
		if os.clock() - lastIssue > 1 then
			P.humanoid:MoveTo(pos)
			lastIssue = os.clock()
		end
		Sched.wait(token, 0.1)
		requireReady()
		local rp = P.root.Position
		if goal and (rp - goal).Magnitude <= radius then
			return true
		end
		if Vector3.new(rp.X - pos.X, 0, rp.Z - pos.Z).Magnitude < 2.5 then
			return true
		end
		if (rp - lastPos).Magnitude > 0.4 then
			lastPos, lastMove = rp, os.clock()
		elseif os.clock() - lastMove > 1 then
			P.humanoid.Jump = true
			if os.clock() - lastMove > 2.2 then
				return false
			end
		end
	end
	return false
end

-- Walks (pathfinding) to within `radius` studs of `target`. Teleport is only used when
-- you choose it in Settings. Returns true when the character actually arrived.
function Actions.walkTo(token, target, radius, opts)
	opts = opts or {}
	radius = radius or 4
	requireReady()
	local goal = Util.position(target)
	if not goal then
		return false, "the target has no position"
	end
	local function dist()
		return P.root and (P.root.Position - goal).Magnitude or math.huge
	end
	if dist() <= radius then
		return true
	end
	Sched.defer(token, Actions.stop)

	if Cfg.movement == "Teleport" and opts.allowTeleport ~= false then
		local spot = standingSpot(target, goal)
		pcall(function()
			P.character:PivotTo(CFrame.new(spot, Vector3.new(goal.X, spot.Y, goal.Z)))
		end)
		Sched.wait(token, 0.25)
		if dist() <= radius + 1 then
			return true
		end
	end

	local deadline = os.clock() + (opts.timeout or 30)
	for _ = 1, 4 do
		if os.clock() >= deadline then
			break
		end
		yieldToPlayer(token)
		requireReady()
		local spot = standingSpot(target, goal)
		local wps = Actions.path(P.root.Position, spot)
		if wps then
			for i = 2, #wps do
				local wp = wps[i]
				if WAYPOINT_JUMP and wp.Action == WAYPOINT_JUMP then
					P.humanoid.Jump = true
				end
				local reached = moveTowards(token, wp.Position, 3.5, radius, goal)
				if dist() <= radius then
					Actions.stop()
					return true
				end
				if not reached or os.clock() >= deadline then
					break
				end
			end
		else
			moveTowards(token, spot, math.min(6, math.max(1, deadline - os.clock())), radius, goal)
		end
		if dist() <= radius then
			Actions.stop()
			return true
		end
		P.humanoid.Jump = true
		Sched.wait(token, 0.3)
	end
	Actions.stop()
	if dist() <= radius then
		return true
	end
	return false, string.format("couldn't reach the spot (%.0f studs away; path blocked?)", dist())
end

--[[ Uses a ProximityPrompt the normal way: walk into range until the game shows the prompt,
     InputHoldBegin, hold for its full HoldDuration, InputHoldEnd. Success is decided by
     opts.verify (the game's state), or by the Triggered event when no verify is given.
     fireproximityprompt is only used for instant (no-hold) prompts the game is showing. ]]
function Actions.trigger(token, prompt, opts)
	opts = opts or {}
	if not Util.alive(prompt) then
		return false, "the prompt no longer exists"
	end
	if not prompt.Enabled then
		return false, "the prompt is disabled"
	end
	local maxd = prompt.MaxActivationDistance or 10
	local okWalk, why = Actions.walkTo(token, prompt.Parent, math.max(2, maxd - 2), opts)
	if not okWalk then
		return false, why
	end
	local gen = P.generation
	-- Wait for the game to show this prompt; step closer and face it if another one is in front.
	if Actions.tracking and not Actions.shown[prompt] then
		Actions.face(Util.position(prompt))
		if not Sched.waitFor(token, function()
			return Actions.shown[prompt]
		end, 0.6) then
			Actions.walkTo(token, prompt.Parent, math.min(4, math.max(2, maxd - 2)), opts)
			Actions.face(Util.position(prompt))
			Sched.waitFor(token, function()
				return Actions.shown[prompt]
			end, 1)
		end
	end
	if not Util.alive(prompt) then
		return false, "the prompt disappeared"
	end
	if not prompt.Enabled then
		return false, "the prompt turned off before it could be used"
	end
	local isShown = (not Actions.tracking) or Actions.shown[prompt] == true

	local fired = false
	local conn = prompt.Triggered:Connect(function(plr)
		if plr == P.player then
			fired = true
		end
	end)
	local function holdEnd()
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end
	Sched.defer(token, holdEnd)
	Sched.defer(token, function()
		conn:Disconnect()
	end)
	local function done()
		if P.generation ~= gen or not P.ready() then
			return false -- died or respawned: nothing done by this character counts
		end
		if opts.verify then
			local ok, r = pcall(opts.verify)
			return ok and r
		end
		return fired
	end

	local hold = prompt.HoldDuration or 0
	local success = false
	if pcall(function()
		prompt:InputHoldBegin()
	end) then
		Sched.wait(token, hold + 0.15)
		holdEnd()
		requireReady()
		success = Sched.waitFor(token, done, opts.timeout or 2) ~= nil
	end
	-- Fallback for instant prompts only, never for hold prompts, and only while the game shows it.
	if not success and not fired and Env.fireproximityprompt and hold <= 0 and isShown and Util.alive(prompt)
		and prompt.Enabled and P.root and (ProximityPromptService == nil or ProximityPromptService.Enabled ~= false)
		and (P.root.Position - (Util.position(prompt) or Vector3.new(1e9, 0, 0))).Magnitude <= maxd then
		pcall(Env.fireproximityprompt, prompt)
		success = Sched.waitFor(token, done, opts.timeout or 2) ~= nil
	end
	conn:Disconnect()
	if success then
		return true
	end
	if fired then
		return false, "the prompt was used but the game didn't respond as expected"
	end
	if not isShown then
		return false, "the game isn't showing this prompt (another prompt is in front or it's blocked)"
	end
	return false, "the prompt didn't respond"
end

-- ---------- GUI button presses ----------
local CLICK_SIGNALS = { "MouseButton1Click", "Activated", "MouseButton1Up", "MouseButton1Down" }
local GAME_SOURCES = { "playerscripts", "playergui", "replicatedstorage", "replicatedfirst", "startergui", "starterplayer", "players.", "workspace." }

-- Connections made by the game's own scripts (skips executor scripts such as loggers).
-- Uses debug.info (read-only) rather than getfenv, which would de-optimise the game's scripts.
local function isGameConnection(c)
	local okE, enabled = pcall(function()
		return c.Enabled
	end)
	if okE and enabled == false then
		return false
	end
	local fn = nil
	pcall(function()
		fn = c.Function
	end)
	if type(fn) ~= "function" then
		return false
	end
	if debug and debug.info then
		local okS, src = pcall(debug.info, fn, "s")
		if okS and type(src) == "string" then
			return Util.containsAny(src, GAME_SOURCES)
		end
	end
	return true
end

local function fireConnections(button)
	if not Env.getconnections then
		return false
	end
	local center = button.AbsolutePosition + button.AbsoluteSize / 2
	for _, sigName in ipairs(CLICK_SIGNALS) do
		local okSig, sig = pcall(function()
			return button[sigName]
		end)
		if okSig and sig then
			local okC, conns = pcall(Env.getconnections, sig)
			if okC and type(conns) == "table" then
				local list = {}
				for _, c in ipairs(conns) do
					if isGameConnection(c) then
						list[#list + 1] = c
					end
				end
				if #list > 0 then
					for _, c in ipairs(list) do
						task.spawn(function()
							pcall(function()
								local args = {}
								if sigName == "Activated" then
									args = { nil, 1 }
								elseif sigName == "MouseButton1Up" or sigName == "MouseButton1Down" then
									args = { center.X, center.Y }
								end
								if type(c.Fire) == "function" then
									c:Fire(unpack(args))
								else
									c.Function(unpack(args))
								end
							end)
						end)
					end
					return true, sigName
				end
			end
		end
	end
	return false
end

local function insetOf(button)
	local sg = button:FindFirstAncestorWhichIsA("ScreenGui")
	if sg and sg.IgnoreGuiInset then
		return Vector2.new(0, 0), true
	end
	if GuiService then
		local ok, inset = pcall(function()
			return GuiService:GetGuiInset()
		end)
		if ok and inset then
			return inset, false
		end
	end
	return Vector2.new(0, 0), false
end

-- Is the button the top-most thing under its centre (nothing else from the game covering it)?
local function onTop(button)
	local center = button.AbsolutePosition + button.AbsoluteSize / 2
	local inset, ignores = insetOf(button)
	local guiPoint = ignores and (center - inset) or center
	local ok, list = pcall(function()
		return P.gui:GetGuiObjectsAtPosition(guiPoint.X, guiPoint.Y)
	end)
	if not ok or type(list) ~= "table" or #list == 0 then
		return true -- can't tell; the state check after the click still decides
	end
	for _, o in ipairs(list) do
		if o == button or o:IsDescendantOf(button) then
			return true
		end
		if o:IsA("GuiButton") or o:IsA("TextBox") or o.Active then
			return false, o
		end
	end
	return true
end

local function vimClick(button)
	local vim = Env.vim()
	if not vim then
		return false
	end
	local t0 = os.clock()
	while Actions.mouseBusy and os.clock() - t0 < 2 do
		task.wait()
	end
	Actions.mouseBusy = true
	local inset = insetOf(button)
	local pos = button.AbsolutePosition + button.AbsoluteSize / 2 + inset
	local x, y = pos.X, pos.Y
	if UIHooks.hideAt then
		UIHooks.hideAt(x, y)
	end
	pcall(function()
		vim:SendMouseMoveEvent(x, y, game)
		vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
	end)
	task.wait(0.05)
	pcall(function()
		vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
	task.wait() -- let the engine process the release before the menu comes back
	task.wait()
	if UIHooks.restore then
		UIHooks.restore()
	end
	Actions.mouseBusy = false
	return true
end

local function pressable(button)
	local ok, why = pcall(function()
		if button:IsA("GuiButton") and button.Active == false then
			return "the button is disabled"
		end
		local okI, interactable = pcall(function()
			return button.Interactable
		end)
		if okI and interactable == false then
			return "the button is disabled"
		end
		return nil
	end)
	if ok and why then
		return false, why
	end
	return true
end

--[[ Presses one of the game's buttons like a player would.
     Default ("Auto"): a real (virtual) mouse click, so the game's own input checks apply; the
     button must be visible, enabled and not covered. The game's handlers are only fired directly
     when the executor has no VirtualInputManager (or "Game signals" is chosen).
     With opts.verify the press only counts when the game's state changes. A button is never
     pressed a second time after an unconfirmed press unless opts.retrySafe says that's harmless. ]]
function Actions.click(token, button, opts)
	opts = opts or {}
	if not Util.guiVisible(button) then
		return false, "the button isn't on screen"
	end
	Sched.wait(token, Cfg.actionDelay)
	if not Util.guiVisible(button) then
		return false, "the button disappeared"
	end
	local okP, whyP = pressable(button)
	if not okP then
		return false, whyP
	end
	local function verified(seconds)
		if not opts.verify then
			return true
		end
		return Sched.waitFor(token, opts.verify, seconds or opts.timeout or 1.5) ~= nil
	end
	local useMouse = Env.vim() ~= nil and Cfg.clickMethod ~= "Game signals"
	local useSignals = Env.getconnections ~= nil and (Cfg.clickMethod == "Game signals" or (Cfg.clickMethod == "Auto" and not useMouse))
	local attempts = 0
	for _ = 1, (opts.retrySafe and 2 or 1) do
		if useMouse then
			local top, cover = onTop(button)
			if not top then
				return false, "the button is covered by '" .. tostring(cover and cover.Name) .. "'"
			end
			vimClick(button)
			attempts = attempts + 1
		elseif useSignals then
			if not fireConnections(button) then
				return false, "no game handler found on the button"
			end
			attempts = attempts + 1
		elseif Env.firesignal then
			pcall(function()
				Env.firesignal(button.MouseButton1Click)
			end)
			attempts = attempts + 1
		else
			return false, "this executor can't press buttons (needs VirtualInputManager or getconnections)"
		end
		if verified() then
			return true
		end
		if not Util.guiVisible(button) then
			break
		end
	end
	if attempts == 0 then
		return false, "the button couldn't be pressed"
	end
	-- One last look: a slow game may still apply the press.
	if verified(1) then
		return true
	end
	return false, opts.retrySafe and "the button was pressed but nothing changed"
		or "the button was pressed once but nothing changed (not pressed again, to avoid a double press)"
end

-- Immediate, non-yielding press used in cleanups (e.g. closing a window after a cancel).
function Actions.rawClick(button)
	if not Util.guiVisible(button) or not pressable(button) then
		return
	end
	if Env.vim() and Cfg.clickMethod ~= "Game signals" then
		task.spawn(vimClick, button)
	elseif Env.getconnections then
		fireConnections(button)
	end
end

-- ---------- tools ----------
function Actions.equip(token, tool)
	requireReady()
	if not Util.alive(tool) then
		return false
	end
	if tool.Parent == P.character then
		return true
	end
	pcall(function()
		P.humanoid:EquipTool(tool)
	end)
	return Sched.waitFor(token, function()
		return tool.Parent == P.character
	end, 2) ~= nil
end

function Actions.unequip(token)
	if P.humanoid then
		pcall(function()
			P.humanoid:UnequipTools()
		end)
	end
	if token then
		Sched.wait(token, 0.1)
	end
end

function Actions.face(pos)
	if P.root and pos then
		pcall(function()
			local rp = P.root.Position
			P.root.CFrame = CFrame.new(rp, Vector3.new(pos.X, rp.Y, pos.Z))
		end)
	end
end

-- Points the mouse at a world position when it is on screen (tools that aim with the mouse).
function Actions.aim(pos)
	local vim = Env.vim()
	local cam = Workspace.CurrentCamera
	if not (vim and cam and pos) or Actions.mouseBusy then
		return false
	end
	local ok, v, onScreen = pcall(function()
		local p, vis = cam:WorldToViewportPoint(pos)
		return p, vis
	end)
	if ok and onScreen then
		pcall(function()
			vim:SendMouseMoveEvent(v.X, v.Y, game)
		end)
		return true
	end
	return false
end

function Actions.useTool(token, tool, aimPos)
	if aimPos then
		Actions.face(aimPos)
		if Actions.aim(aimPos) then
			task.wait() -- the engine applies the mouse move on its next input step
			task.wait()
		end
	end
	return (pcall(function()
		tool:Activate()
	end))
end

--==================================================================================
-- 12. GAME GUI READING (read-only helpers for the game's own windows)
--==================================================================================
local GG = {}

function GG.path(...)
	local cur = P.gui
	for _, name in ipairs({ ... }) do
		if not cur then
			return nil
		end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

-- A visible descendant named `name` inside the ScreenGui `guiName` (tolerates layout changes).
function GG.visibleNamed(guiName, name)
	local g = P.gui and P.gui:FindFirstChild(guiName)
	if not g then
		return nil
	end
	local d = (g.Name == name) and g or g:FindFirstChild(name, true)
	if d and Util.guiVisible(d) then
		return d
	end
	return nil
end

local function isTextObject(d)
	return d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")
end

local function excluded(d, exclude)
	if not exclude then
		return false
	end
	local cur = d
	while cur do
		if exclude[cur] then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- Visible text objects under root: { {obj, text}, … } (rich-text tags removed).
function GG.texts(root, exclude)
	local out = {}
	if not root then
		return out
	end
	for _, d in ipairs(root:GetDescendants()) do
		if isTextObject(d) and not excluded(d, exclude) then
			local t = Util.trim(Util.stripTags(d.Text))
			if t ~= "" and Util.guiVisible(d) then
				out[#out + 1] = { obj = d, text = t }
			end
		end
	end
	return out
end

function GG.allText(root, exclude)
	local parts = {}
	for _, t in ipairs(GG.texts(root, exclude)) do
		parts[#parts + 1] = t.text
	end
	return string.lower(table.concat(parts, " | "))
end

-- Snapshot of every visible number shown under root: map obj -> value.
function GG.numbers(root, exclude)
	local out = {}
	for _, t in ipairs(GG.texts(root, exclude)) do
		local n = Util.parseMoney(t.text)
		if n then
			out[t.obj] = n
		end
	end
	return out
end

local function countDescendants(root)
	local ok, list = pcall(function()
		return root:GetDescendants()
	end)
	return ok and #list or 0
end
GG.countDescendants = countDescendants

--[[ Finds an amount labelled by one of `keywords`, e.g. "Change: ₱63", a "Change" label
     next to a "₱63" label, or a label named "ChangeAmount". Labels containing any of
     `avoid` are skipped. Returns value, label, score (nil when nothing matches). ]]
function GG.labelled(root, keywords, exclude, avoid)
	if not root then
		return nil
	end
	local best, bestObj, bestScore = nil, nil, 0
	local function consider(value, obj, score)
		if value ~= nil and score > bestScore then
			best, bestObj, bestScore = value, obj, score
		end
	end
	for _, t in ipairs(GG.texts(root, exclude)) do
		local lt = string.lower(t.text)
		local ln = string.lower(t.obj.Name)
		local avoidHit = avoid and (Util.containsAny(lt, avoid) or Util.containsAny(ln, avoid))
		if not avoidHit then
			local hasKey = Util.containsAny(lt, keywords)
			local nameKey = Util.containsAny(ln, keywords)
			local n = Util.parseMoney(t.text)
			if n and hasKey then
				consider(n, t.obj, 3)
			elseif n and nameKey then
				consider(n, t.obj, 3)
			elseif hasKey and not n then
				-- caption label: look for a number in a sibling
				local parent = t.obj.Parent
				if parent then
					for _, s in ipairs(parent:GetChildren()) do
						if s ~= t.obj and isTextObject(s) and Util.guiVisible(s) and not excluded(s, exclude) then
							local sn = Util.parseMoney(s.Text)
							if sn and not Util.hasLetters((string.gsub(Util.stripTags(s.Text), "PHP", ""))) then
								consider(sn, s, 2)
							elseif sn then
								consider(sn, s, 1)
							end
						end
					end
				end
			elseif n then
				local parent = t.obj.Parent
				if parent and Util.containsAny(string.lower(parent.Name), keywords) then
					consider(n, t.obj, 2)
				end
			end
		end
	end
	return best, bestObj, bestScore
end

-- First visible button under root whose name is in `names` or whose text contains one of `texts`.
function GG.findButton(root, names, texts)
	if not root then
		return nil
	end
	local wantNames = {}
	for _, n in ipairs(names or {}) do
		wantNames[string.lower(n)] = true
	end
	local fallback = nil
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiButton") and Util.guiVisible(d) then
			if wantNames[string.lower(d.Name)] then
				return d
			end
			if not fallback and texts then
				local txt = d:IsA("TextButton") and d.Text or ""
				if txt == "" then
					local lbl = d:FindFirstChildWhichIsA("TextLabel", true)
					txt = lbl and lbl.Text or ""
				end
				if Util.containsAny(Util.stripTags(txt), texts) then
					fallback = d
				end
			end
		end
	end
	return fallback
end

-- Plain-text outline of a GUI tree (for the "Export game scan" diagnostics file).
function GG.dump(root, maxDepth, lines, depth)
	lines = lines or {}
	depth = depth or 0
	if not root or depth > (maxDepth or 8) or #lines > 1500 then
		return lines
	end
	local info = root.ClassName .. " " .. root.Name
	pcall(function()
		if root:IsA("GuiObject") then
			info = info .. (root.Visible and "" or " [hidden]")
		elseif root:IsA("LayerCollector") then
			info = info .. (root.Enabled and "" or " [disabled]")
		end
		if isTextObject(root) and root.Text ~= "" then
			info = info .. '  "' .. Util.stripTags(root.Text) .. '"'
		end
	end)
	lines[#lines + 1] = string.rep("  ", depth) .. info
	for _, c in ipairs(root:GetChildren()) do
		GG.dump(c, maxDepth, lines, depth + 1)
	end
	return lines
end

--==================================================================================
-- 13. TRANSACTIONS (shared by Cashier Automation and the Completion Shortcut)
--==================================================================================
-- Game windows (paths taken from the game's own logs):
--   PlayerGui.CashierGui.Frame.Content.BillsPanel  (Bills/Coins.Cell_<value>, ButtonRow.Undo/Confirm, Header.CloseBtn)
--   PlayerGui.KashGGui.Backdrop.Panel              (Accept / Decline)
--   PlayerGui.UtangGui.Backdrop.AskPanel           (Card.Buttons.Accept / Decline)
local Tx = { busy = false, manual = nil, fails = 0, backoffUntil = 0, noCustomerSince = nil, hinted = false, seenKashG = {} }

local KEY_DUE = { "change", "sukli", "suklian" }
local KEY_TOTAL = { "total", "amount due", "price", "kabuuan", "babayaran" }
local KEY_PAID = { "paid", "received", "tendered", "bayad", "cash given", "customer gave", "payment" }
local KEY_COUNTED = { "counted", "given", "your change", "selected", "tray", "binigay", "current" }

-- res.cash is the area that is read (labels may sit outside the bills panel);
-- res.cashBills is the panel whose visibility says whether the cash window is open.
function Tx.panels()
	local res = {}
	local bills = GG.visibleNamed("CashierGui", "BillsPanel")
	if bills then
		res.cashBills = bills
		res.cash = GG.path("CashierGui", "Frame") or bills
		if not Util.guiVisible(res.cash) then
			res.cash = bills
		end
	end
	local kg = GG.path("KashGGui", "Backdrop", "Panel")
	if kg and Util.guiVisible(kg) then
		res.kashg = kg
	else
		local acc = GG.visibleNamed("KashGGui", "Accept")
		if acc then
			res.kashg = acc.Parent
		end
	end
	local ask = GG.visibleNamed("UtangGui", "AskPanel")
	if ask then
		res.ask = ask
	end
	return res
end

function Tx.anyPanel(p)
	p = p or Tx.panels()
	return p.cash or p.kashg or p.ask
end

function Tx.record(kind, outcome, amount, note, started)
	local item = {
		time = Util.clock(),
		kind = kind,
		outcome = outcome,
		amount = amount,
		note = note or "",
		seconds = started and (os.clock() - started) or nil,
	}
	table.insert(State.history, 1, item)
	while #State.history > 40 do
		table.remove(State.history)
	end
	if outcome == "Completed" then
		if kind == "Cash" then
			State.tx.cash = State.tx.cash + 1
			State.tx.change = State.tx.change + (amount or 0)
		elseif kind == "KashG" then
			State.tx.kashg = State.tx.kashg + 1
		elseif kind == "Utang" then
			State.tx.utang = State.tx.utang + 1
		end
	elseif outcome == "Declined" then
		State.tx.declined = State.tx.declined + 1
	elseif outcome == "Manual" then
		State.tx.manual = State.tx.manual + 1
	elseif outcome == "Failed" then
		State.tx.failed = State.tx.failed + 1
	end
end

-- Leaves a window for you to finish: never touched again until it closes.
function Tx.leaveManual(panel, kind, reason, alreadyRecorded)
	if Tx.manual and Tx.manual.panel == panel then
		return
	end
	Tx.manual = { panel = panel, kind = kind, reason = reason, since = os.clock() }
	if not alreadyRecorded then
		Tx.record(kind, "Manual", nil, reason)
	end
	Log.warn("Transaction", kind .. " left for you to finish: " .. reason)
end

function Tx.manualPending(p)
	if Tx.manual then
		if Util.guiVisible(Tx.manual.panel) then
			return true
		end
		Tx.manual = nil
	end
	return false
end

local function cellsOf(panel)
	local out = {}
	for _, d in ipairs(panel:GetDescendants()) do
		local v = string.match(d.Name, "^Cell_(%d+)$")
		if v then
			local btn = d:IsA("GuiButton") and d or d:FindFirstChildWhichIsA("GuiButton", true)
			if btn and Util.guiVisible(btn) then
				out[#out + 1] = { value = tonumber(v), button = btn, cell = d }
			end
		end
	end
	table.sort(out, function(a, b)
		return a.value > b.value
	end)
	return out
end

-- Presses Confirm/Accept/Decline and waits for `closes` (default: the panel) to disappear.
local function confirmClose(token, panel, names, texts, kind, closes)
	local btn = GG.findButton(panel, names, texts)
	if not btn then
		return false, "couldn't find the " .. names[1] .. " button"
	end
	local watch = closes or panel
	local ok, why = Actions.click(token, btn, {
		verify = function()
			return not Util.guiVisible(watch)
		end,
		timeout = 4,
	})
	if ok then
		return true
	end
	return false, names[1] .. ": " .. tostring(why) .. " (the " .. kind .. " window stayed open)"
end

--[[ CASH: read the change due, count it out with the fewest bills/coins, check every
     click against the panel's numbers, then Confirm and wait for the panel to close.
     mode "shortcut": only Confirm when the counted change already equals the change due. ]]
function Tx.handleCash(token, panel, mode, bills)
	bills = bills or panel
	local cells = cellsOf(panel)
	if #cells == 0 then
		if mode == "shortcut" then
			return "Skip"
		end
		return "Manual", nil, "no bill/coin buttons were found in the cashier window"
	end
	local exclude = {}
	local values = {}
	for _, c in ipairs(cells) do
		exclude[c.cell] = true
		values[#values + 1] = c.value
	end
	local due, dueObj = GG.labelled(panel, KEY_DUE, exclude, KEY_COUNTED)
	local how = "change label"
	if due == nil then
		local total = GG.labelled(panel, KEY_TOTAL, exclude)
		local paid = GG.labelled(panel, KEY_PAID, exclude)
		if total and paid and paid >= total then
			due, how = paid - total, "amount paid − total"
		end
	end
	if due == nil then
		if mode == "shortcut" then
			return "Skip"
		end
		return "Manual", nil, "couldn't read the change due from the cashier window"
	end
	local counted, countedObj = GG.labelled(panel, KEY_COUNTED, exclude)
	if countedObj == dueObj then
		counted, countedObj = nil, nil
	end
	State.transaction = { stage = "Counting change", kind = "Cash", amount = due, since = os.clock() }

	if mode == "shortcut" then
		if countedObj and math.abs((counted or 0) - due) < 0.01 then
			Log.info("Transaction", "Shortcut: change already counted (" .. Util.formatMoney(due) .. "); confirming.")
			local ok, why = confirmClose(token, panel, { "Confirm" }, { "confirm", "done" }, "cashier", bills)
			if ok then
				return "Completed", due
			end
			return "Failed", due, why
		end
		return "Skip"
	end

	local need = due - (counted or 0)
	if need < -0.01 then
		return "Manual", due, "more change is already counted than is due; fix it with Undo"
	end
	local plan = Util.changePlan(need, values)
	if not plan then
		return "Manual", due, "that amount can't be made with the bills/coins on the panel"
	end
	if #plan > 40 then
		return "Manual", due, "the change needs more than 40 bills/coins"
	end
	Log.debug("Cashier", "Change due " .. Util.formatMoney(due) .. " (" .. how .. "); counting " .. #plan .. " pieces.")

	local byValue = {}
	for _, c in ipairs(cells) do
		byValue[c.value] = c
	end
	local undoBtn = GG.findButton(panel, { "Undo" }, { "undo" })
	local clicked = 0
	local remainingStyle = false

	local function abort(reason)
		if undoBtn and clicked > 0 then
			for _ = 1, clicked do
				local before = GG.numbers(panel, exclude)
				local beforeCount = countDescendants(panel)
				Actions.click(token, undoBtn, {
					verify = function()
						local now = GG.numbers(panel, exclude)
						for obj, v in pairs(before) do
							if now[obj] ~= v then
								return true
							end
						end
						return countDescendants(panel) ~= beforeCount
					end,
					timeout = 1,
				})
			end
			reason = reason .. " (the counted bills/coins were taken back with Undo)"
		end
		return "Manual", due, reason
	end

	for _, v in ipairs(plan) do
		local cell = byValue[v]
		local before = GG.numbers(panel, exclude)
		local beforeCount = countDescendants(panel)
		local ok = Actions.click(token, cell.button, {
			verify = function()
				local now = GG.numbers(panel, exclude)
				for obj, val in pairs(before) do
					if now[obj] ~= val then
						return true
					end
				end
				return countDescendants(panel) ~= beforeCount
			end,
			timeout = 1.2,
		})
		if not Util.guiVisible(bills) then
			return "Failed", due, "the cashier window closed while counting"
		end
		if not ok then
			return abort("a " .. Util.formatMoney(v) .. " press didn't register")
		end
		clicked = clicked + 1
		local after = GG.numbers(panel, exclude)
		if dueObj and before[dueObj] and after[dueObj] and math.abs(after[dueObj] - before[dueObj]) > 0.01 then
			if math.abs((before[dueObj] - after[dueObj]) - v) < 0.01 then
				remainingStyle = true -- the label counts down what is still owed
			else
				return abort("the change-due label changed unexpectedly")
			end
		end
		if countedObj then
			if not (before[countedObj] and after[countedObj] and math.abs((after[countedObj] - before[countedObj]) - v) < 0.01) then
				return abort("the counted total didn't go up by " .. Util.formatMoney(v))
			end
		else
			for obj, val in pairs(after) do
				if obj ~= dueObj and before[obj] and math.abs((val - before[obj]) - v) < 0.01 then
					countedObj = obj -- found the running total
					break
				end
			end
		end
		-- Without a running total (or a count-down) on screen the change can't be checked: stop.
		if not countedObj and not remainingStyle then
			return abort("the cashier window doesn't show a running total, so the change can't be verified")
		end
	end

	-- Final check before handing the change over.
	local final = GG.numbers(panel, exclude)
	if remainingStyle and dueObj and final[dueObj] and final[dueObj] > 0.01 then
		return abort("the panel still shows " .. Util.formatMoney(final[dueObj]) .. " owed")
	end
	if countedObj and final[countedObj] and not remainingStyle and math.abs(final[countedObj] - due) > 0.01 then
		return abort("the counted total (" .. Util.formatMoney(final[countedObj]) .. ") doesn't match the change due")
	end
	State.transaction.stage = "Confirming"
	local ok, why = confirmClose(token, panel, { "Confirm" }, { "confirm", "done" }, "cashier", bills)
	if ok then
		return "Completed", due
	end
	return "Failed", due, why
end

-- KASHG (the game's e-wallet, ≈ GCash): only accepted when the window shows a verified payment.
function Tx.handleKashG(token, panel, mode)
	local text = GG.allText(panel)
	if not Tx.seenKashG[text] then
		Tx.seenKashG[text] = true
		Log.debug("Cashier", "KashG window says: " .. string.sub(text, 1, 200))
	end
	-- Whole words only, and negated phrases ("not received", "unverified") never count as success.
	local bad, badWord = Util.hasWord(text, Util.keywords(Cfg.failWords))
	local good, goodWord = Util.hasWord(text, Util.keywords(Cfg.successWords))
	local total = GG.labelled(panel, KEY_TOTAL)
	local paid = GG.labelled(panel, { "paid", "sent", "amount", "received" }, nil, KEY_TOTAL)
	local mismatch = total and paid and (paid + 0.01 < total)
	local verdict = (bad or mismatch) and "invalid" or (good and "verified" or "unclear")
	local amount = total or paid
	State.transaction = { stage = "Checking KashG payment", kind = "KashG", amount = amount, since = os.clock() }

	local function press(names, texts, outcome, note)
		local ok, why = confirmClose(token, panel, names, texts, "KashG")
		if ok then
			return outcome, amount, note
		end
		return "Failed", amount, why
	end

	local reasonBad = bad and ("it says '" .. badWord .. "'")
		or (mismatch and ("paid " .. Util.formatMoney(paid) .. " is less than the total " .. Util.formatMoney(total)))
		or ""
	if mode == "shortcut" then
		-- The shortcut respects your KashG choices and windows already left for you.
		if Cfg.kashgPolicy == "Manual review" or not Cfg.payKashG or (Tx.manual and Tx.manual.panel == panel) then
			return "Skip"
		end
		if verdict == "verified" then
			Log.info("Transaction", "Shortcut: KashG payment shows '" .. goodWord .. "'; accepting.")
			return press({ "Accept" }, { "accept" }, "Completed", "verified: " .. goodWord)
		end
		return "Skip"
	end
	local policy = Cfg.kashgPolicy
	if policy == "Manual review" then
		return "Manual", amount, "KashG policy is 'Manual review'"
	end
	if verdict == "invalid" then
		if Cfg.kashgDeclineInvalid then
			return press({ "Decline" }, { "decline", "reject" }, "Declined", "invalid: " .. reasonBad)
		end
		return "Manual", amount, "the KashG payment doesn't look valid (" .. reasonBad .. ")"
	end
	if verdict == "verified" then
		return press({ "Accept" }, { "accept" }, "Completed", "verified: " .. goodWord)
	end
	if policy == "Accept unless invalid" then
		return press({ "Accept" }, { "accept" }, "Completed", "no warning signs found")
	end
	return "Manual", amount, "couldn't confirm the KashG payment went through (no success text found)"
end

-- UTANG request (customer wants to pay later).
function Tx.handleAsk(token, panel)
	State.transaction = { stage = "Utang request", kind = "Utang", amount = GG.labelled(panel, KEY_TOTAL), since = os.clock() }
	local amount = State.transaction.amount
	if Cfg.utangAccept then
		local ok, why = confirmClose(token, panel, { "Accept" }, { "accept", "oo", "yes" }, "utang request")
		if ok then
			return "Completed", amount, "credit given"
		end
		return "Failed", amount, why
	elseif Cfg.utangDecline then
		local ok, why = confirmClose(token, panel, { "Decline", "Reject", "No", "Deny" }, { "decline", "reject", "hindi", "deny" }, "utang request")
		if ok then
			return "Declined", amount, "utang declined (setting)"
		end
		return "Failed", amount, why
	end
	return "Manual", amount, "utang accept/decline are both off"
end

-- Processes whichever transaction window is open. Returns the outcome string.
function Tx.process(token, p, mode)
	if Tx.busy then
		return "Busy"
	end
	Tx.busy = true
	local started = os.clock()
	local kind, panel, outcome, amount, note
	local ok, err = pcall(function()
		if p.cash then
			kind, panel = "Cash", p.cashBills or p.cash
			if mode ~= "shortcut" and not Cfg.payCash then
				outcome, note = "Manual", "Cash automation is off"
			else
				outcome, amount, note = Tx.handleCash(token, p.cash, mode, p.cashBills)
			end
		elseif p.kashg then
			kind, panel = "KashG", p.kashg
			if mode ~= "shortcut" and not Cfg.payKashG then
				outcome, note = "Manual", "GCash/KashG automation is off"
			else
				outcome, amount, note = Tx.handleKashG(token, panel, mode)
			end
		elseif p.ask then
			kind, panel = "Utang", p.ask
			if mode == "shortcut" then
				outcome = "Skip"
			else
				outcome, amount, note = Tx.handleAsk(token, panel)
			end
		end
	end)
	Tx.busy = false
	State.transaction = { stage = "Idle", kind = "—", amount = nil, since = nil }
	if not ok then
		error(err, 0)
	end
	if not kind or outcome == "Skip" then
		return outcome or "None"
	end
	if outcome == "Manual" then
		Tx.leaveManual(panel, kind, note or "needs your attention")
		return outcome
	end
	Tx.record(kind, outcome, amount, note, started)
	local amt = amount and (" " .. Util.formatMoney(amount)) or ""
	if outcome == "Completed" then
		local what = kind == "Cash" and ("Cash sale done, change" .. amt .. " handed over")
			or kind == "KashG" and ("KashG payment accepted" .. amt .. " (" .. (note or "") .. ")")
			or ("Utang accepted" .. amt .. " — it goes in the Utang Book")
		Log.success("Transaction", what .. string.format(" in %.1fs.", os.clock() - started))
		State.complete(mode == "shortcut" and "shortcut" or "cashier")
	elseif outcome == "Declined" then
		Log.info("Transaction", kind .. " declined" .. amt .. " (" .. (note or "") .. ").")
		State.complete(mode == "shortcut" and "shortcut" or "cashier")
	else
		Log.error("Transaction", kind .. " failed" .. amt .. ": " .. tostring(note))
		State.fail(mode == "shortcut" and "shortcut" or "cashier", tostring(note))
		-- Never retry a failed window automatically (no repeated Confirm/Accept presses).
		if Util.guiVisible(panel) then
			Tx.leaveManual(panel, kind, "it failed once: " .. tostring(note), true)
		end
	end
	return outcome
end

function Tx.customersNear(reg)
	local pos = Util.position(reg.prompt)
	return #NPC.near(pos, Cfg.customerRadius)
end

--==================================================================================
-- 14. FEATURE: CASHIER AUTOMATION (Cash · GCash/KashG · Utang)
--==================================================================================
local Cashier = { key = "cashier", title = "Cashier Automation", category = "Cashier" }

function Cashier.step(token)
	if not (Cfg.payCash or Cfg.payKashG or Cfg.utangAccept or Cfg.utangDecline) then
		State.set("cashier", "WAITING", "Turn on at least one payment method")
		return 2
	end
	local p = Tx.panels()
	if Tx.manualPending(p) then
		State.set("cashier", "WAITING", "Waiting for you to finish: " .. Tx.manual.reason)
		return 1
	end
	if Tx.anyPanel(p) then
		State.set("cashier", "WORKING", "Handling an open transaction window")
		-- Window-only work: hold the character still if it's free, but never interrupt another task for it.
		local ok = Sched.withBody(token, "cashier", 80, function(h)
			h.preemptible = false
			Tx.process(token, Tx.panels(), "auto")
		end, 1.5, true)
		if not ok then
			Tx.process(token, Tx.panels(), "auto")
		end
		return 0.3
	end
	local usable, why = Plot.usable()
	if not usable then
		State.set("cashier", "WAITING", why)
		return 3
	end
	local reg = Plot.first("register")
	if not reg then
		State.set("cashier", "UNAVAILABLE", "Cash register not found on your plot")
		State.pending.customers = 0
		return 5
	end
	if not reg.prompt.Enabled then
		State.pending.customers = 0
		State.set("cashier", "IDLE", "No customer at the register")
		Tx.noCustomerSince = nil
		return 1
	end
	local near = Tx.customersNear(reg)
	State.pending.customers = near
	if Cfg.requireCustomer and near == 0 then
		Tx.noCustomerSince = Tx.noCustomerSince or os.clock()
		if not Tx.hinted and os.clock() - Tx.noCustomerSince > 20 then
			Tx.hinted = true
			Log.info("Cashier", "The register prompt is on but no customer model is near it. If customers are waiting, turn off 'Require a customer nearby'.")
		end
		State.set("cashier", "IDLE", "No customer near the register")
		return 1
	end
	if os.clock() < Tx.backoffUntil then
		return 0.5
	end
	State.set("cashier", "WORKING", "Ringing up a customer")
	local got, res = Sched.withBody(token, "cashier", 80, function(h)
		local ok, why = Actions.trigger(token, reg.prompt, {
			verify = function()
				return Tx.anyPanel()
			end,
			timeout = 4,
		})
		if not ok then
			return why
		end
		h.preemptible = false
		Tx.process(token, Tx.panels(), "auto")
		return true
	end, 10)
	if not got then
		State.set("cashier", "WAITING", "Waiting for the character (another task is using it)")
		return 0.5
	end
	if res ~= true then
		Tx.fails = Tx.fails + 1
		Tx.backoffUntil = os.clock() + math.min(3 * Tx.fails, 15)
		Log.warn("Cashier", "Register: " .. tostring(res))
	else
		Tx.fails = 0
	end
	return 0.3
end

function Cashier.onStop()
	State.pending.customers = 0
end

--==================================================================================
-- 15. FEATURE: TRANSACTION COMPLETION SHORTCUT
--==================================================================================
-- When a payment window is already in a verified-complete state — the exact change is
-- already counted, or the KashG window shows a successful payment — it skips straight
-- to Confirm/Accept. It never invents a payment and never touches unverified windows.
local Shortcut = { key = "shortcut", title = "Completion Shortcut", category = "Transaction" }

function Shortcut.step(token)
	if Tx.busy then
		return 0.5
	end
	local p = Tx.panels()
	if not (p.cash or p.kashg) then
		State.set("shortcut", "IDLE", "No payment window open")
		return 0.5
	end
	if Tx.manualPending(p) and Tx.manual.kind ~= "Cash" then
		State.set("shortcut", "WAITING", "A window is left for you: " .. Tx.manual.reason)
		return 0.5
	end
	State.set("shortcut", "WATCHING", "Waiting for a verified-complete payment")
	Tx.process(token, p, "shortcut")
	return 0.4
end

--==================================================================================
-- 16. FEATURE: AUTO STACK (deliveries → produce stands / shelves, leftovers → box rack)
--==================================================================================
-- Stands are found by their RestockPrompt (e.g. Plot.ProduceBins.E3_ProduceBin_8.Base.RestockPrompt),
-- delivery boxes by PickupPrompt (ObjectText "18x Apple"), carried boxes are Tools named
-- "Box: <Product> (<count>)". A restock only counts when the box count actually drops.
local Stack = { key = "stack", title = "Auto Stack", category = "Stack", tried = {}, warned = {}, pickFail = {}, learned = {} }

local GENERIC_WORDS = {
	"restock", "stock", "produce stand", "stand", "shelf", "empty", "full", "price", "sold out", "out of stock", "low",
}

-- "18x Apple", "₱25 Pita 3/10" -> "Apple", "Pita" (keeps letters such as the x in "Xtra")
local function cleanProductText(s)
	local t = Util.stripTags(s)
	t = string.gsub(t, "₱", " ")
	t = string.gsub(t, "%d+%s*[xX]%f[%W]", " ")
	t = string.gsub(t, "[%d/%%%.,:%-%(%)]", " ")
	t = string.gsub(t, "%s+", " ")
	return Util.trim(t)
end

-- The stand a restock prompt belongs to: its nearest Model ancestor below the plot
-- (e.g. ProduceBins.E3_ProduceBin_8), never a whole folder of stands.
local function standOf(prompt)
	local plot = Plot.model
	local cur = prompt.Parent
	while cur and cur ~= plot and cur ~= Workspace do
		if cur:IsA("Model") then
			return cur
		end
		cur = cur.Parent
	end
	return prompt.Parent
end

local function productFromAttributes(inst)
	local ok, attrs = pcall(function()
		return inst:GetAttributes()
	end)
	if not ok then
		return nil
	end
	for k, v in pairs(attrs) do
		local lk = string.lower(k)
		if type(v) == "string" and v ~= "" then
			if string.find(lk, "product", 1, true) or string.find(lk, "item", 1, true) or string.find(lk, "fruit", 1, true)
				or string.find(lk, "goods", 1, true) or lk == "type" or (string.find(lk, "stock", 1, true) and string.find(lk, "name", 1, true)) then
				return v, "attribute " .. k
			end
		end
	end
	return nil
end

function Stack.readProduct(stand, prompt)
	for _, inst in ipairs({ stand, prompt.Parent, prompt }) do
		local v, how = productFromAttributes(inst)
		if v then
			return v, how
		end
	end
	for _, c in ipairs(stand:GetDescendants()) do
		if c:IsA("StringValue") then
			local ln = string.lower(c.Name)
			if (string.find(ln, "product", 1, true) or string.find(ln, "item", 1, true)) and c.Value ~= "" then
				return c.Value, "value " .. c.Name
			end
		end
	end
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" then
			local t = Util.trim(Util.stripTags(d.Text))
			local word = cleanProductText(t)
			if Util.hasLetters(word) and #word <= 30 and not Util.containsAny(word, GENERIC_WORDS) then
				return word, "sign '" .. t .. "'"
			end
		end
	end
	local named = string.match(stand.Name, "_([%a][%a ]+)$")
	if named and not string.find(string.lower(named), "bin", 1, true) then
		return named, "name"
	end
	if Stack.learned[stand] then
		return Stack.learned[stand], "learned from a successful restock"
	end
	return nil, nil
end

function Stack.readStock(stand)
	local stock, cap
	local ok, attrs = pcall(function()
		return stand:GetAttributes()
	end)
	if ok then
		for k, v in pairs(attrs) do
			local lk = string.lower(k)
			if type(v) == "number" then
				if string.find(lk, "max", 1, true) or string.find(lk, "capacity", 1, true) or string.find(lk, "limit", 1, true) then
					cap = v
				elseif string.find(lk, "stock", 1, true) or string.find(lk, "amount", 1, true) or string.find(lk, "count", 1, true)
					or string.find(lk, "quantity", 1, true) or string.find(lk, "current", 1, true) then
					stock = v
				end
			end
		end
	end
	if stock == nil then
		for _, c in ipairs(stand:GetChildren()) do
			if c:IsA("IntValue") or c:IsA("NumberValue") then
				local ln = string.lower(c.Name)
				if string.find(ln, "max", 1, true) or string.find(ln, "capacity", 1, true) then
					cap = cap or c.Value
				elseif string.find(ln, "stock", 1, true) or string.find(ln, "amount", 1, true) or string.find(ln, "count", 1, true) then
					stock = c.Value
				end
			end
		end
	end
	if stock == nil then
		for _, d in ipairs(stand:GetDescendants()) do
			if d:IsA("TextLabel") then
				local a, b = Util.parseFraction(d.Text)
				if a then
					stock, cap = a, b
					break
				end
			end
		end
	end
	return stock, cap
end

local function parseBox(tool)
	local product, count = string.match(tool.Name, "^Box:%s*(.-)%s*%((%d+)%)%s*$")
	if product then
		return product, tonumber(count)
	end
	product = string.match(tool.Name, "^Box:%s*(.-)%s*$")
	if product then
		return product, nil
	end
	return nil
end

function Stack.scan()
	local stands = {}
	for _, info in ipairs(Plot.find("restock")) do
		local prompt = info.prompt
		local stand = standOf(prompt)
		local product, how = Stack.readProduct(stand, prompt)
		local stock, cap = Stack.readStock(stand)
		local need, status
		if stock ~= nil and cap ~= nil and cap > 0 then
			local pct = stock / cap * 100
			need = pct < Cfg.stackThreshold
			status = stock == 0 and "Empty" or (need and string.format("Low (%d/%d)", stock, cap) or string.format("OK (%d/%d)", stock, cap))
		elseif stock ~= nil then
			need = stock == 0
			status = need and "Empty" or ("Has " .. stock)
		else
			need, status = nil, "Unknown level"
		end
		-- "Incorrectly stocked": the sign shows a different product than the stand's setting.
		local attrProduct = productFromAttributes(stand)
		if attrProduct and product and Util.norm(attrProduct) ~= Util.norm(product) then
			status = "Mismatch: shows " .. product .. ", set to " .. attrProduct
			if not Stack.warned[stand] then
				Stack.warned[stand] = true
				Log.warn("Stack", stand.Name .. " shows '" .. product .. "' but is set up for '" .. attrProduct .. "'.")
			end
		end
		stands[#stands + 1] = {
			stand = stand,
			prompt = prompt,
			name = stand.Name,
			product = product,
			productHow = how,
			stock = stock,
			cap = cap,
			need = need,
			status = status,
		}
	end
	local boxes = {}
	for _, t in ipairs(P.tools()) do
		local product, count = parseBox(t)
		if product then
			boxes[#boxes + 1] = { tool = t, product = product, count = count }
		end
	end
	local deliveries = {}
	for _, info in ipairs(Plot.find("pickup")) do
		local n, product = string.match(info.prompt.ObjectText, "^(%d+)%s*[xX]%s*(.+)$")
		local failedAt = Stack.pickFail[info.prompt]
		deliveries[#deliveries + 1] = {
			prompt = info.prompt,
			product = product or info.prompt.ObjectText,
			count = tonumber(n),
			enabled = info.prompt.Enabled and not (failedAt and os.clock() - failedAt < 60),
		}
	end
	State.stock = { stands = stands, boxes = boxes, deliveries = deliveries, lastScan = os.clock() }
	local needing = 0
	for _, s in ipairs(stands) do
		if s.need then
			needing = needing + 1
		end
	end
	State.pending.stands = needing
	return State.stock
end

local function triedRecently(stand, product)
	local t = Stack.tried[stand]
	return t and t[Util.norm(product)] and os.clock() - t[Util.norm(product)] < 600
end

local function markTried(stand, product)
	Stack.tried[stand] = Stack.tried[stand] or {}
	Stack.tried[stand][Util.norm(product)] = os.clock()
end

local function boxFor(boxes, product)
	for _, b in ipairs(boxes) do
		if Util.norm(b.product) == Util.norm(product) and (b.count == nil or b.count > 0) then
			return b
		end
	end
	return nil
end

-- Picks up one delivery box from the truck bay; returns the new box tool.
function Stack.pickUp(token, delivery)
	local before = {}
	for _, t in ipairs(P.tools()) do
		before[t] = true
	end
	local ok, why = Actions.trigger(token, delivery.prompt, {
		verify = function()
			for _, t in ipairs(P.tools()) do
				if not before[t] and parseBox(t) then
					return t
				end
			end
			return nil
		end,
		timeout = 3,
	})
	if not ok then
		Stack.pickFail[delivery.prompt] = os.clock() -- back off for a minute instead of retrying at once
		return nil, why
	end
	for _, t in ipairs(P.tools()) do
		if not before[t] and parseBox(t) then
			Log.success("Stack", "Picked up the delivery '" .. delivery.prompt.ObjectText .. "' from the truck bay.")
			State.complete("stack")
			return t
		end
	end
	return nil, "no box appeared in your inventory"
end

-- Restocks one stand from one box. Success = the box count dropped (or the box was used up).
function Stack.restock(token, s, box)
	local tool = box.tool
	local before = select(2, parseBox(tool))
	if not Actions.equip(token, tool) then
		return false, "couldn't take the box out"
	end
	local gen = P.generation
	local function moved()
		if P.generation ~= gen or not P.ready() then
			return false -- the box vanished because you died/respawned, not because it was used
		end
		if not Util.alive(tool) or tool.Parent == nil then
			return true
		end
		local _, now = parseBox(tool)
		return before and now and now < before
	end
	local ok, why = Actions.trigger(token, s.prompt, { verify = moved, timeout = 3 })
	if ok then
		local after = nil
		if Util.alive(tool) then
			after = select(2, parseBox(tool))
		end
		local n = (before and after) and (before - after) or before
		if not s.product then
			Stack.learned[s.stand] = box.product -- the game accepted it, so this stand sells that product
		end
		Log.success("Stack", "Restocked " .. s.name .. " with " .. (n and (n .. "× ") or "") .. box.product
			.. (after and (" (" .. after .. " left in the box)") or " (box used up)") .. ".")
		State.complete("stack")
		return true
	end
	markTried(s.stand, box.product)
	Log.warn("Stack", "Restocking " .. s.name .. " with " .. box.product .. " didn't move any stock (" .. tostring(why)
		.. "). Skipping that pair for 10 minutes.")
	return false, why
end

function Stack.storeLeftover(token, box)
	local shelf = Plot.first("boxShelf")
	if not shelf or not Util.alive(box.tool) then
		return
	end
	if not Actions.equip(token, box.tool) then
		return
	end
	local ok = Actions.trigger(token, shelf.prompt, {
		verify = function()
			return not Util.alive(box.tool) or (box.tool.Parent ~= P.character and box.tool.Parent ~= P.backpack())
		end,
		timeout = 3,
	})
	if ok then
		Log.success("Stack", "Stored the leftover " .. box.product .. " box on the box shelf.")
		State.complete("stack")
	else
		Log.warn("Stack", "Couldn't store the leftover " .. box.product .. " box on the shelf.")
	end
end

function Stack.step(token, manual)
	local usable, whyNot = Plot.usable()
	if not usable then
		State.set("stack", "WAITING", whyNot)
		return 3
	end
	local snap = Stack.scan()
	if #snap.stands == 0 then
		State.set("stack", "UNAVAILABLE", "No restock prompts found on your plot")
		return 10
	end
	-- Choose one job: the emptiest stand that has a matching box (or a matching delivery).
	local order = {}
	for _, s in ipairs(snap.stands) do
		if s.need ~= false and Util.alive(s.prompt) then
			order[#order + 1] = s
		end
	end
	table.sort(order, function(a, b)
		local fa = (a.stock and a.cap and a.cap > 0) and (a.stock / a.cap) or 0.5
		local fb = (b.stock and b.cap and b.cap > 0) and (b.stock / b.cap) or 0.5
		return fa < fb
	end)
	local job = nil
	for _, s in ipairs(order) do
		if s.product then
			if not triedRecently(s.stand, s.product) then
				local box = boxFor(snap.boxes, s.product)
				if box then
					job = { stand = s, box = box }
					break
				end
				if Cfg.stackPickup then
					for _, d in ipairs(snap.deliveries) do
						if d.enabled and Util.norm(d.product) == Util.norm(s.product) then
							job = { stand = s, delivery = d }
							break
						end
					end
					if job then
						break
					end
				end
			end
		elseif s.need == nil or s.need == true then
			-- Product unknown: try a carried box this stand hasn't refused recently.
			for _, b in ipairs(snap.boxes) do
				if not triedRecently(s.stand, b.product) then
					job = { stand = s, box = b, guess = true }
					break
				end
			end
			if job then
				break
			end
		end
	end
	-- Nothing to restock but a delivery is waiting: bring it in.
	local pickupOnly = nil
	if not job and Cfg.stackPickup then
		for _, d in ipairs(snap.deliveries) do
			if d.enabled then
				pickupOnly = d
				break
			end
		end
	end
	if not job and not pickupOnly then
		State.set("stack", "IDLE", State.pending.stands > 0 and (State.pending.stands .. " stand(s) low; no matching boxes") or "Shelves look stocked")
		return manual and 0 or 4
	end
	State.set("stack", "WORKING", job and ("Restocking " .. job.stand.name) or "Picking up a delivery")
	Sched.withBody(token, "stack", 30, function()
		Sched.defer(token, function()
			-- don't leave a box in hand for the next task if this one is interrupted
			local held = P.equipped()
			if held and parseBox(held) and P.humanoid then
				pcall(function()
					P.humanoid:UnequipTools()
				end)
			end
		end)
		if pickupOnly then
			local _, why = Stack.pickUp(token, pickupOnly)
			if why then
				Log.warn("Stack", "Pick-up failed: " .. tostring(why))
			end
			return
		end
		local box = job.box
		if job.delivery then
			local tool, why = Stack.pickUp(token, job.delivery)
			if not tool then
				Log.warn("Stack", "Pick-up failed: " .. tostring(why))
				return
			end
			local product, count = parseBox(tool)
			box = { tool = tool, product = product, count = count }
		end
		Stack.restock(token, job.stand, box)
		-- Leftovers go to the box shelf only when no other stand wants them.
		if Cfg.stackStoreLeftovers and Util.alive(box.tool) and (box.tool.Parent == P.character or box.tool.Parent == P.backpack()) then
			local wanted = false
			for _, s in ipairs(Stack.scan().stands) do
				if s.need and s.product and Util.norm(s.product) == Util.norm(box.product) then
					wanted = true
				end
			end
			if not wanted then
				Stack.storeLeftover(token, box)
			end
		end
		Actions.unequip(token)
	end, 20)
	return 0.5
end

--==================================================================================
-- 17. FEATURE: AUTO ORDER (laptop → Orders tab → ProductRow_<id>.Plus → Cart.ConfirmBtn)
--==================================================================================
local Order = { key = "order", title = "Auto Order", category = "Order", lastRun = -1000, alertCache = nil, alertAt = -1000 }

local ALERT_SKIP = { "stock alert", "low stock", "out of stock", "close", "alert", "items", "restock", "running low", "sold out" }

-- Reads the game's Stock Alert list (opens it if needed, closes it again). Only called while
-- the mod holds the character and no transaction window is open.
function Order.readAlert(token)
	if Order.alertCache and os.clock() - Order.alertAt < 60 then
		return Order.alertCache
	end
	local panel = GG.path("StockAlertPanel", "Backdrop", "Panel")
	local opened = false
	if not (panel and Util.guiVisible(panel)) then
		local btn = GG.path("StockAlertGui", "StockAlertBtn")
		if not (btn and Util.guiVisible(btn)) then
			return nil
		end
		Actions.click(token, btn, {
			verify = function()
				local pnl = GG.path("StockAlertPanel", "Backdrop", "Panel")
				return pnl and Util.guiVisible(pnl)
			end,
			timeout = 2,
			retrySafe = true,
		})
		panel = GG.path("StockAlertPanel", "Backdrop", "Panel")
		opened = true
		Sched.defer(token, function()
			local pnl = GG.path("StockAlertPanel", "Backdrop", "Panel")
			local close = pnl and Util.guiVisible(pnl) and GG.findButton(pnl, { "CloseButton", "CloseBtn", "Close" }, { "close" })
			if close then
				Actions.rawClick(close)
			end
		end)
	end
	if not (panel and Util.guiVisible(panel)) then
		return nil
	end
	local header = panel:FindFirstChild("Header")
	local names, seen = {}, {}
	for _, t in ipairs(GG.texts(panel, header and { [header] = true } or nil)) do
		local word = cleanProductText(t.text)
		if Util.hasLetters(word) and #word <= 30 and not Util.containsAny(word, ALERT_SKIP) and not seen[Util.norm(word)] then
			seen[Util.norm(word)] = true
			names[#names + 1] = word
		end
	end
	if opened then
		local close = GG.findButton(panel, { "CloseButton", "CloseBtn", "Close" }, { "close" })
		if close then
			Actions.click(token, close, {
				verify = function()
					return not Util.guiVisible(panel)
				end,
				timeout = 2,
				retrySafe = true,
			})
		end
	end
	Order.alertCache, Order.alertAt = names, os.clock()
	return names
end

local function haveSet(snap)
	local have = {}
	for _, b in ipairs(snap.boxes) do
		have[Util.norm(b.product)] = true
	end
	for _, d in ipairs(snap.deliveries) do
		have[Util.norm(d.product)] = true
	end
	return have
end

-- Products that need ordering, from the shelves (and, when given, the Stock Alert list):
-- skipped when a box is carried, a delivery is waiting, or an order is still pending.
function Order.needs(alertNames)
	local snap = (State.stock.lastScan and os.clock() - State.stock.lastScan < 5) and State.stock or Stack.scan()
	local have = haveSet(snap)
	for key, o in pairs(State.orders.pending) do
		if have[key] then
			State.orders.pending[key] = nil
			Log.info("Order", "Order for " .. o.product .. " arrived.")
		elseif os.clock() - o.at > Cfg.orderPendingMin * 60 then
			State.orders.pending[key] = nil
			Log.warn("Order", "Order for " .. o.product .. " hasn't arrived after " .. Cfg.orderPendingMin .. " min; it may be ordered again.")
		end
	end
	local list, seen = {}, {}
	local function add(product, why)
		local key = Util.norm(product)
		if key ~= "" and not seen[key] and not have[key] and not State.orders.pending[key] then
			seen[key] = true
			list[#list + 1] = { product = product, key = key, why = why }
		end
	end
	for _, s in ipairs(snap.stands) do
		if s.need and s.product then
			add(s.product, s.status .. " on " .. s.name)
		end
	end
	for _, name in ipairs(alertNames or {}) do
		add(name, "Stock Alert")
	end
	local pend = 0
	for _ in pairs(State.orders.pending) do
		pend = pend + 1
	end
	State.pending.orders = pend
	State.orders.lastNeeds = list
	return list
end

local function laptopPanel()
	local panel = GG.path("LaptopShopGui", "Backdrop", "Panel")
	if panel and Util.guiVisible(panel) then
		return panel
	end
	return nil
end

-- Exact match on the product id or its display name; a partial match is used only when it is
-- the single candidate (so "apple" never buys "pineapple" by accident).
local function matchRow(catalog, product)
	local key = Util.norm(product)
	for _, r in pairs(catalog) do
		if r.key == key or (r.name ~= "" and Util.norm(r.name) == key) then
			return r
		end
	end
	local found = nil
	for _, r in pairs(catalog) do
		local nm = Util.norm(r.name)
		if #key >= 4 and (string.find(r.key, key, 1, true) or (nm ~= "" and string.find(nm, key, 1, true))) then
			if found then
				return nil -- ambiguous
			end
			found = r
		end
	end
	return found
end

function Order.readCatalog(panel)
	local products = panel:FindFirstChild("Products", true)
	local catalog = {}
	if not products then
		return catalog
	end
	for _, row in ipairs(products:GetChildren()) do
		local id = string.match(row.Name, "^ProductRow_(.+)$")
		if id then
			local plus = row:FindFirstChild("Plus", true)
			local name, price = "", nil
			for _, t in ipairs(GG.texts(row)) do
				if name == "" and Util.hasLetters(t.text) and not Util.containsAny(t.text, { "+", "add", "locked", "unlock" }) then
					name = t.text
				end
				if not price and (string.find(t.text, "₱", 1, true) or string.find(string.lower(t.text), "php", 1, true)) then
					price = Util.parseMoney(t.text)
				end
			end
			local locked = Util.containsAny(GG.allText(row), { "locked", "unlock", "level" }) and not (plus and Util.guiVisible(plus))
			catalog[Util.norm(id)] = { id = id, key = Util.norm(id), name = name, price = price, row = row, plus = plus, locked = locked }
		end
	end
	State.orders.catalog = catalog
	return catalog
end

local function cartTotal(cart)
	if not cart then
		return nil
	end
	local v = GG.labelled(cart, { "total", "kabuuan" })
	if v ~= nil then
		return v
	end
	local sum, any = 0, false
	for _, n in pairs(GG.numbers(cart)) do
		sum, any = sum + n, true
	end
	return any and sum or nil
end

-- One ordering run while holding the character: Stock Alert (optional) → laptop → cart → Confirm.
function Order.run(token, needs)
	local laptop = Plot.first("laptop")
	if not laptop then
		return false, "laptop prompt not found on your plot"
	end
	local placed = false
	local ok, res = Sched.withBody(token, "order", 20, function(h)
		if Cfg.orderUseAlert and not Tx.busy and not Tx.anyPanel() then
			local alert = Order.readAlert(token)
			needs = Order.needs(alert)
		end
		if #needs == 0 then
			return "nothing needs ordering"
		end
		Sched.defer(token, function()
			local panel = laptopPanel()
			local close = panel and GG.findButton(panel, { "CloseBtn" }, { "close" })
			if close then
				Actions.rawClick(close)
			end
		end)
		local okT, why = Actions.trigger(token, laptop.prompt, { verify = laptopPanel, timeout = 4 })
		if not okT then
			return "couldn't open the laptop: " .. tostring(why)
		end
		local panel = laptopPanel()
		local tab = GG.findButton(panel, { "Tab_Orders" }, { "orders" })
		if tab then
			Actions.click(token, tab, {
				verify = function()
					local pr = panel:FindFirstChild("Products", true)
					return pr and Util.guiVisible(pr)
				end,
				timeout = 2,
				retrySafe = true,
			})
		end
		local catalog = Order.readCatalog(panel)
		if next(catalog) == nil then
			return "the Orders tab shows no products"
		end
		local cart = panel:FindFirstChild("Cart", true)
		local existing = cartTotal(cart)
		if existing and existing > 0 then
			return "the cart already has items (" .. Util.formatMoney(existing) .. ") from before; confirm or clear it yourself"
		end
		-- From the first '+' to Confirm the order is finished as one unit (no interruption).
		h.preemptible = false
		local money = P.money()
		local budget = money and (money - Cfg.orderMinMoney) or nil
		local added = {}
		for _, need in ipairs(needs) do
			if #added >= Cfg.orderMaxProducts then
				break
			end
			local row = matchRow(catalog, need.product)
			if not row then
				Log.info("Order", "'" .. need.product .. "' isn't in the order list (not sold, not unlocked, or the name is ambiguous).")
			elseif row.locked or not (row.plus and Util.guiVisible(row.plus)) then
				Log.info("Order", "'" .. need.product .. "' can't be ordered yet (locked).")
			elseif budget and row.price and row.price * Cfg.orderQty > budget then
				Log.warn("Order", "Skipped " .. need.product .. ": it costs " .. Util.formatMoney(row.price * Cfg.orderQty)
					.. " and would take you below your minimum of " .. Util.formatMoney(Cfg.orderMinMoney) .. ".")
			else
				local n = 0
				for _ = 1, Cfg.orderQty do
					local beforeRow = GG.allText(row.row)
					local beforeCart = cart and GG.allText(cart) or ""
					local okC = Actions.click(token, row.plus, {
						verify = function()
							return GG.allText(row.row) ~= beforeRow or (cart and GG.allText(cart) ~= beforeCart)
						end,
						timeout = 1.5,
					})
					if okC then
						n = n + 1
					else
						break
					end
				end
				if n > 0 then
					added[#added + 1] = { product = need.product, key = need.key, qty = n, row = row }
					if budget and row.price then
						budget = budget - row.price * n
					end
				end
			end
		end
		if #added == 0 then
			return "nothing could be added to the cart"
		end
		local confirm = cart and cart:FindFirstChild("ConfirmBtn", true) or GG.findButton(panel, { "ConfirmBtn" }, { "confirm", "order" })
		if not confirm then
			return "the order Confirm button wasn't found (the cart is left as it is)"
		end
		local beforeCart = cart and GG.allText(cart) or ""
		local beforeMoney = P.money()
		local okConf = Actions.click(token, confirm, {
			verify = function()
				if not laptopPanel() then
					return true
				end
				if cart and GG.allText(cart) ~= beforeCart then
					return true
				end
				local m = P.money()
				return beforeMoney and m and m < beforeMoney
			end,
			timeout = 4,
		})
		if not okConf then
			return "Confirm didn't go through (the cart is left as it is for you to check)"
		end
		local names = {}
		for _, a in ipairs(added) do
			State.orders.pending[a.key] = { product = a.product, qty = a.qty, at = os.clock(), clock = Util.clock() }
			names[#names + 1] = a.qty .. "× " .. a.product
		end
		State.orders.lastOrder = Util.clock() .. " — " .. table.concat(names, ", ")
		Log.success("Order", "Ordered " .. table.concat(names, ", ") .. ".")
		State.complete("order", #added)
		placed = true
		h.preemptible = true
		local close = GG.findButton(panel, { "CloseBtn" }, { "close" })
		if close and laptopPanel() then
			Actions.click(token, close, {
				verify = function()
					return not laptopPanel()
				end,
				timeout = 2,
				retrySafe = true,
			})
		end
		return true
	end, 30)
	if not ok then
		return false, "the character was busy"
	end
	if res ~= true then
		return false, res
	end
	return placed
end

function Order.step(token, manual)
	local usable, whyNot = Plot.usable()
	if not usable then
		State.set("order", "WAITING", whyNot)
		return 3
	end
	if not manual and os.clock() - Order.lastRun < Cfg.orderInterval then
		State.set("order", "IDLE", "Next stock check in " .. math.ceil(Cfg.orderInterval - (os.clock() - Order.lastRun)) .. "s")
		return math.min(5, Cfg.orderInterval - (os.clock() - Order.lastRun))
	end
	Order.lastRun = os.clock()
	State.set("order", "CHECKING", "Checking stock levels")
	local needs = Order.needs(nil)
	if #needs == 0 and not Cfg.orderUseAlert then
		State.set("order", "IDLE", "Nothing needs ordering")
		return manual and 0 or 5
	end
	State.set("order", "WORKING", #needs > 0 and ("Ordering " .. #needs .. " product(s)") or "Checking the Stock Alert list")
	local ok, why = Order.run(token, needs)
	if not ok then
		if why == "nothing needs ordering" then
			State.set("order", "IDLE", "Nothing needs ordering")
		else
			Log.warn("Order", "Order not placed: " .. tostring(why))
			State.fail("order", tostring(why))
		end
	end
	return 5
end

--==================================================================================
-- 18. FEATURE: UTANG COLLECTION (Utang Book → UtangRow<N>.Collect)
--==================================================================================
local Utang = { key = "utang", title = "Utang Collection", category = "Utang", lastRun = -1000, collected = {} }

local function bookPanel()
	local p = GG.visibleNamed("UtangGui", "BookPanel")
	return p
end

function Utang.readRows(panel)
	local rows = {}
	for _, d in ipairs(panel:GetDescendants()) do
		if string.match(d.Name, "^UtangRow") and d:IsA("GuiObject") and Util.guiVisible(d) then
			local btn = d:FindFirstChild("Collect", true) or GG.findButton(d, {}, { "collect", "singilin" })
			local name, amount = "", nil
			for _, t in ipairs(GG.texts(d)) do
				if not (btn and (t.obj == btn or t.obj:IsDescendantOf(btn))) then
					if name == "" and Util.hasLetters(t.text) and not string.find(t.text, "₱", 1, true) then
						name = t.text
					end
					if amount == nil and (string.find(t.text, "₱", 1, true) or not Util.hasLetters(t.text)) then
						amount = Util.parseMoney(t.text)
					end
				end
			end
			local eligible = btn and Util.guiVisible(btn) and btn:IsA("GuiButton") and btn.Active ~= false
			if eligible then
				local bt = string.lower(GG.allText(btn) .. " " .. (btn:IsA("TextButton") and btn.Text or ""))
				if Util.containsAny(bt, { "wait", "later", "not yet", "paid", "unavailable" }) then
					eligible = false
				end
			end
			rows[#rows + 1] = { row = d, name = name, amount = amount, button = btn, eligible = eligible and true or false, index = tonumber(string.match(d.Name, "(%d+)$")) or 0 }
		end
	end
	table.sort(rows, function(a, b)
		return a.index < b.index
	end)
	return rows
end

function Utang.summarize(rows)
	local count, total = 0, 0
	for _, r in ipairs(rows) do
		count = count + 1
		total = total + (r.amount or 0)
	end
	State.utang.count, State.utang.total, State.utang.rows, State.utang.lastRead = count, total, rows, os.clock()
	local collectable = 0
	for _, r in ipairs(rows) do
		if r.eligible then
			collectable = collectable + 1
		end
	end
	State.pending.utang = collectable
end

function Utang.step(token, manual)
	if not manual and os.clock() - Utang.lastRun < Cfg.utangInterval then
		State.set("utang", "IDLE", "Next check in " .. math.ceil(Cfg.utangInterval - (os.clock() - Utang.lastRun)) .. "s")
		return math.min(5, Cfg.utangInterval - (os.clock() - Utang.lastRun))
	end
	local usable, whyNot = Plot.usable()
	if not usable then
		State.set("utang", "WAITING", whyNot)
		return 3
	end
	if Tx.busy or Tx.anyPanel() then
		State.set("utang", "WAITING", "Waiting for the current transaction to finish")
		return 2
	end
	local book = Plot.first("utangBook")
	if not book then
		State.set("utang", "UNAVAILABLE", "Utang Book not found on your plot")
		return 10
	end
	Utang.lastRun = os.clock()
	State.set("utang", "WORKING", "Checking the Utang Book")
	Sched.withBody(token, "utang", 60, function()
		Sched.defer(token, function()
			local panel = bookPanel()
			local close = panel and GG.findButton(panel, { "Close" }, { "close" })
			if close then
				Actions.rawClick(close)
			end
		end)
		local wasOpen = bookPanel() ~= nil
		if not wasOpen then
			local ok, why = Actions.trigger(token, book.prompt, { verify = bookPanel, timeout = 4 })
			if not ok then
				Log.warn("Utang", "Couldn't open the Utang Book: " .. tostring(why))
				return
			end
		end
		local panel = bookPanel()
		local rows = Utang.readRows(panel)
		Utang.summarize(rows)
		local eligible = {}
		for _, r in ipairs(rows) do
			local key = r.name .. "|" .. tostring(r.amount)
			if r.eligible and not (Utang.collected[key] and os.clock() - Utang.collected[key] < 90) then
				r.key = key
				eligible[#eligible + 1] = r
			end
		end
		if Cfg.utangPriority == "Largest first" then
			table.sort(eligible, function(a, b)
				return (a.amount or 0) > (b.amount or 0)
			end)
		end
		for _, r in ipairs(eligible) do
			if not Util.alive(r.button) or not Util.guiVisible(r.button) then
				break -- the list re-ordered; the next check picks up the rest
			end
			local moneyBefore = P.money()
			local amountLabel = nil
			for _, t in ipairs(GG.texts(r.row)) do
				if not (t.obj == r.button or t.obj:IsDescendantOf(r.button)) and Util.parseMoney(t.text) == r.amount then
					amountLabel = t.obj
					break
				end
			end
			-- Collected = the row went away, its amount went down, or your money went up.
			-- A button that just changes to "Wait"/"Not yet" is a refusal, not a collection.
			local function collected()
				if not Util.alive(r.row) or not Util.guiVisible(r.row) then
					return true
				end
				if amountLabel and Util.alive(amountLabel) then
					local now = Util.parseMoney(amountLabel.Text)
					if now and r.amount and now < r.amount then
						return true
					end
				end
				moneyCache.t = -100
				local m = P.money()
				return moneyBefore and m and m > moneyBefore
			end
			local ok = Actions.click(token, r.button, { verify = collected, timeout = 2.5 })
			Utang.collected[r.key] = os.clock() -- never pressed twice for the same debt, even if unverified
			if ok then
				State.utang.collected = State.utang.collected + 1
				State.utang.collectedTotal = State.utang.collectedTotal + (r.amount or 0)
				Log.success("Utang", "Collected " .. (r.amount and Util.formatMoney(r.amount) or "a debt") .. (r.name ~= "" and (" from " .. r.name) or "") .. ".")
				State.complete("utang")
			else
				Log.warn("Utang", "Collect" .. (r.name ~= "" and (" for " .. r.name) or "") .. " didn't go through (the customer may not be able to pay yet).")
			end
		end
		if bookPanel() then
			Utang.summarize(Utang.readRows(bookPanel()))
		end
		if #eligible == 0 then
			Log.info("Utang", "Utang Book checked: " .. (State.utang.count or 0) .. " debt(s), " .. Util.formatMoney(State.utang.total or 0) .. " outstanding, none collectable now.")
		end
		if not wasOpen and bookPanel() then
			local close = GG.findButton(bookPanel(), { "Close" }, { "close" })
			if close then
				Actions.click(token, close, {
					verify = function()
						return bookPanel() == nil
					end,
					timeout = 2,
				})
			end
		end
	end, 20)
	State.set("utang", "IDLE", "Last check " .. Util.clock())
	return 2
end

--==================================================================================
-- 19. FEATURE: NPC / THIEF MANAGEMENT (Tsinelas, 3 swings, verify, return)
--==================================================================================
-- A target must (1) not be a player, (2) be near your plot, and (3) be marked as a thief by
-- its name, an attribute, an overhead label, or a highlight during a shoplift alert.
-- Customers and other NPCs are never targeted.
local Thief = { key = "thief", title = "Thief Management", category = "Thief", cooldown = {}, alertUntil = 0, alertSeen = {}, reasons = {} }

local ALERT_WORDS = { "shoplift", "thief", "magnanakaw", "robbed", "nakaw", "kawatan" }

function Thief.classify(model)
	if not Util.alive(model) or Players:GetPlayerFromCharacter(model) then
		return false
	end
	local words = Util.keywords(Cfg.thiefWords)
	if Util.containsAny(model.Name, words) then
		return true, "name '" .. model.Name .. "'"
	end
	local ok, attrs = pcall(function()
		return model:GetAttributes()
	end)
	if ok then
		for k, v in pairs(attrs) do
			local lk = string.lower(k)
			local flagged = Util.containsAny(lk, words) or string.find(lk, "steal", 1, true) or string.find(lk, "shoplift", 1, true)
			if flagged and (v == true or (type(v) == "number" and v > 0) or (type(v) == "string" and v ~= "" and string.lower(v) ~= "false")) then
				return true, "attribute " .. k
			end
			if type(v) == "string" and Util.containsAny(v, words) then
				return true, "attribute " .. k .. "='" .. v .. "'"
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" and Util.containsAny(d.Text, words) then
			return true, "label '" .. Util.stripTags(d.Text) .. "'"
		end
	end
	if os.clock() < Thief.alertUntil and model:FindFirstChildOfClass("Highlight") then
		return true, "highlighted during a shoplift alert"
	end
	return false
end

-- The game's own shoplift / robbery alerts (read-only). One log line per alert episode.
function Thief.checkAlerts()
	if not P.gui then
		return
	end
	local active = false
	for _, g in ipairs(P.gui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and Util.containsAny(g.Name, ALERT_WORDS) then
			local text = GG.allText(g)
			if text ~= "" then
				active = true
				Thief.alertUntil = os.clock() + 20
				local key = g.Name .. "|" .. string.gsub(text, "%d+", "#")
				if not Thief.alertSeen[key] then
					Thief.alertSeen[key] = true
					Log.warn("Thief", "Game alert (" .. g.Name .. "): " .. string.sub(text, 1, 120))
				end
			end
		end
	end
	if not active and os.clock() > Thief.alertUntil then
		Thief.alertSeen = {} -- episode over; the next alert is logged again
	end
	for m, t in pairs(Thief.cooldown) do
		if os.clock() > t or not Util.alive(m) then
			Thief.cooldown[m] = nil
		end
	end
end

-- Thieves inside your own plot's area only (never a neighbour's store).
function Thief.targets()
	local center = Plot.center()
	local out = {}
	if not center then
		return out
	end
	for _, n in ipairs(NPC.near(center, Cfg.thiefRadius)) do
		if n.humanoid.Health > 0 and not (Thief.cooldown[n.model] and os.clock() < Thief.cooldown[n.model])
			and Plot.contains(Util.position(n.model), 6) then
			local yes, why = Thief.classify(n.model)
			if yes then
				n.reason = why
				out[#out + 1] = n
			end
		end
	end
	return out
end

local DEAD = enumItem(Enum.HumanoidStateType, "Dead")

local function stopped(t)
	if not Util.alive(t.model) or not Util.alive(t.humanoid) then
		if (t.lastHealth or 1) <= 0 then
			return true, "knocked out"
		end
		return false, "disappeared" -- vanished while still healthy: escaped or despawned, not stopped
	end
	t.lastHealth = t.humanoid.Health
	if t.humanoid.Health <= 0 then
		return true, "knocked out"
	end
	local okS, st = pcall(function()
		return t.humanoid:GetState()
	end)
	if okS and DEAD and st == DEAD then
		return true, "knocked out"
	end
	-- The game cleared the thief marker (attribute/label) → it's no longer stealing.
	if not string.find(t.reason or "", "name", 1, true) and not Thief.classify(t.model) then
		return true, "no longer marked as a thief"
	end
	return false
end

local function escaped(t)
	if not Util.alive(t.model) then
		return (t.lastHealth or 1) > 0
	end
	local pos = Util.position(t.model)
	return pos ~= nil and not Plot.contains(pos, 12)
end

function Thief.engage(token, t)
	local tsinelas = P.findTool(function(tool)
		return string.find(string.lower(tool.Name), "tsinelas", 1, true) ~= nil
	end)
	if not tsinelas then
		State.set("thief", "UNAVAILABLE", "No Tsinelas in your inventory")
		Log.error("Thief", "Thief spotted (" .. t.model.Name .. ") but you have no Tsinelas.")
		Thief.cooldown[t.model] = os.clock() + 30
		return
	end
	t.lastHealth = t.humanoid.Health
	local result = nil
	Sched.withBody(token, "thief", 100, function(h)
		h.preemptible = false
		local savedPos = P.root.Position
		local previous = P.equipped()
		Log.warn("Thief", "Going after " .. t.model.Name .. " (" .. tostring(t.reason) .. ").")
		State.set("thief", "WORKING", "Chasing " .. t.model.Name)
		if not Actions.equip(token, tsinelas) then
			result = "couldn't take out the Tsinelas"
			return
		end
		local swings = 0
		for _ = 1, Cfg.thiefRounds do
			for _ = 1, Cfg.thiefSwings do
				local done, how = stopped(t)
				if done then
					result = "stopped (" .. how .. ")"
					break
				end
				if escaped(t) then
					result = "escaped"
					break
				end
				-- Close the distance (thieves move, so re-aim every step); never leave your plot.
				local deadline = os.clock() + 8
				while os.clock() < deadline do
					if not P.ready() then
						error("your character isn't ready (dead or respawning)", 0)
					end
					local tp = Util.position(t.model)
					if not tp or escaped(t) then
						break
					end
					if (P.root.Position - tp).Magnitude <= Cfg.thiefRange then
						break
					end
					if Cfg.movement == "Teleport" then
						local back = (P.root.Position - tp)
						back = Vector3.new(back.X, 0, back.Z)
						if back.Magnitude < 0.1 then
							back = Vector3.new(0, 0, 1)
						end
						pcall(function()
							P.character:PivotTo(CFrame.new(tp + back.Unit * 3, tp))
						end)
					else
						P.humanoid:MoveTo(tp)
					end
					Sched.wait(token, 0.2)
				end
				if not P.ready() then
					error("your character isn't ready (dead or respawning)", 0)
				end
				local tp = Util.position(t.model)
				if tp and (P.root.Position - tp).Magnitude <= Cfg.thiefRange + 2 then
					Actions.stop()
					Actions.useTool(token, tsinelas, tp)
					swings = swings + 1
					State.thief.swings = State.thief.swings + 1
					Sched.wait(token, 0.45)
				end
			end
			if result then
				break
			end
		end
		if not result then
			local done, how = stopped(t)
			if done then
				result = "stopped (" .. how .. ")"
			elseif escaped(t) then
				result = "escaped"
			else
				result = "still active after " .. swings .. " swing(s)"
			end
		end
		if Cfg.thiefReturn and P.ready() then
			State.set("thief", "WORKING", "Returning to where you were")
			Actions.walkTo(token, savedPos, 4, { timeout = 20 })
		end
		if previous and Util.alive(previous) and previous ~= tsinelas then
			Actions.equip(token, previous)
		elseif not previous then
			Actions.unequip(token)
		end
	end, 5)
	if not result then
		return
	end
	State.thief.last = Util.clock() .. " — " .. t.model.Name .. ": " .. result
	if string.find(result, "stopped", 1, true) then
		State.thief.stopped = State.thief.stopped + 1
		State.complete("thief")
		Log.success("Thief", "Thief " .. t.model.Name .. " " .. result .. ".")
	elseif result == "escaped" then
		State.thief.escaped = State.thief.escaped + 1
		Log.warn("Thief", "Thief " .. t.model.Name .. " got away (left your plot or disappeared).")
		Thief.cooldown[t.model] = os.clock() + 60
	else
		State.fail("thief", result)
		Log.warn("Thief", "Thief " .. t.model.Name .. ": " .. result .. ". Trying again in 15 s.")
		Thief.cooldown[t.model] = os.clock() + 15
	end
end

function Thief.step(token)
	Thief.checkAlerts()
	local usable, whyNot = Plot.usable()
	if not usable then
		State.set("thief", "WAITING", whyNot)
		return 3
	end
	local targets = Thief.targets()
	State.pending.thieves = #targets
	State.thief.seen = targets
	if #targets == 0 then
		State.set("thief", "WATCHING", os.clock() < Thief.alertUntil and "Shoplift alert! Looking for the thief…" or "No thieves near your store")
		return 0.5
	end
	table.sort(targets, function(a, b)
		return Util.distance(P.root, a.model) < Util.distance(P.root, b.model)
	end)
	Thief.engage(token, targets[1])
	return 0.3
end

--==================================================================================
-- 20. FEATURE: ICE CREAM & TAHO BONUS (preserve, display, optional re-use)
--==================================================================================
-- The mod never consumes, drops or unequips these items on its own. The bonus status is
-- read from whatever the game exposes (attributes or HUD text); if it exposes nothing,
-- the dashboard says so and auto re-use stays unavailable.
local Bonus = { key = "bonus", title = "Bonus Re-use", category = "Bonus", labels = {}, labelsAt = -1000, attempts = 0, nextTry = 0, ever = false, maid = Maid.new() }

local BONUS_ITEM_WORDS = { "taho", "ice cream", "icecream" }

local function isBonusItem(tool)
	return Util.containsAny(tool.Name, BONUS_ITEM_WORDS)
end

function Bonus.detect()
	for _, inst in ipairs({ P.player, P.character }) do
		if inst then
			local ok, attrs = pcall(function()
				return inst:GetAttributes()
			end)
			if ok then
				for k, v in pairs(attrs) do
					local lk = string.lower(k)
					if Util.containsAny(lk, { "boost", "bonus", "buff", "multiplier", "taho", "icecream" }) then
						local active = (v == true) or (type(v) == "string" and v ~= "")
						if type(v) == "number" then
							active = string.find(lk, "multiplier", 1, true) and v > 1 or v > 0
						end
						return { found = true, active = active and true or false, source = "attribute " .. k .. " = " .. tostring(v) }
					end
				end
			end
		end
	end
	-- HUD text such as "+10% Sales" or "Taho 02:31" (candidate list refreshed every 15 s,
	-- or at once when a cached label was replaced, e.g. after a respawn).
	local stale = false
	for _, d in ipairs(Bonus.labels) do
		if not Util.alive(d) then
			stale = true
			break
		end
	end
	if (stale or os.clock() - Bonus.labelsAt > 15) and P.gui then
		Bonus.labelsAt = os.clock()
		Bonus.labels = {}
		for _, d in ipairs(P.gui:GetDescendants()) do
			if d:IsA("TextLabel") and not (UIHooks.root and d:IsDescendantOf(UIHooks.root)) then
				local lt = string.lower(d.Text)
				if string.find(lt, "10%", 1, true) or Util.containsAny(lt, { "bonus", "boost", "taho", "ice cream" }) then
					Bonus.labels[#Bonus.labels + 1] = d
				end
			end
		end
	end
	local hudHidden = false
	for _, d in ipairs(Bonus.labels) do
		if Util.guiVisible(d) then
			local lt = string.lower(Util.stripTags(d.Text))
			local pct = string.find(lt, "%+%s*10%s*%%") or (string.find(lt, "%%") and Util.containsAny(lt, { "sales", "bonus", "boost", "benta" }))
			local timer = string.find(lt, "%d+:%d%d") and Util.containsAny(lt, { "taho", "ice cream", "bonus", "boost" })
			if pct or timer then
				Bonus.absentSince = nil
				return { found = true, active = true, source = "HUD text '" .. Util.stripTags(d.Text) .. "'" }
			end
		else
			local sg = Util.alive(d) and d:FindFirstAncestorWhichIsA("LayerCollector")
			if sg and not sg.Enabled then
				hudHidden = true -- e.g. a full-screen window hides the HUD: that's "unknown", not "over"
			end
		end
	end
	if Bonus.ever then
		if hudHidden then
			return { found = true, active = nil, source = "HUD hidden right now" }
		end
		-- Only call it over once the indicator has been missing for 5 s in a row.
		Bonus.absentSince = Bonus.absentSince or os.clock()
		if os.clock() - Bonus.absentSince < 5 then
			return { found = true, active = nil, source = "checking…" }
		end
		return { found = true, active = false, source = "the indicator seen earlier is gone" }
	end
	return { found = false, active = nil, source = nil }
end

function Bonus.refresh()
	local r = Bonus.detect()
	if r.found and r.active then
		Bonus.ever = true
	end
	State.bonus.active = r.active
	State.bonus.source = r.source
	if not r.found then
		State.bonus.status = "Not exposed by the game (no bonus indicator found) — left untouched"
	elseif r.active then
		State.bonus.status = "ACTIVE (+10% sales)"
	elseif r.active == nil then
		State.bonus.status = "Unknown right now (" .. tostring(r.source) .. ")"
	else
		State.bonus.status = "Not active"
	end
	return r
end

-- Logs whenever Avocado Ice Cream / Classic Taho is used (by you or the mod).
function Bonus.watchTools()
	local function hook(tool)
		if tool:IsA("Tool") and isBonusItem(tool) then
			Bonus.maid:connect(tool.Activated, function()
				State.bonus.lastUsed = os.clock()
				State.bonus.lastItem = tool.Name
				Log.info("Bonus", tool.Name .. " used (sales bonus item).")
			end, tool)
		end
	end
	local function watch(container)
		if not container then
			return
		end
		for _, t in ipairs(container:GetChildren()) do
			hook(t)
		end
		Bonus.maid:connect(container.ChildAdded, hook, "add:" .. container:GetFullName())
	end
	watch(P.backpack())
	watch(P.character)
end

function Bonus.step(token)
	local r = Bonus.refresh()
	if not r.found then
		State.set("bonus", "UNAVAILABLE", "The game doesn't expose the bonus status, so re-use can't be timed")
		return 5
	end
	if r.active then
		Bonus.attempts = 0
		State.set("bonus", "IDLE", "Bonus active")
		return 3
	end
	if r.active == nil then
		State.set("bonus", "WAITING", "Bonus status unknown right now (" .. tostring(r.source) .. ")")
		return 2
	end
	if os.clock() < Bonus.nextTry then
		State.set("bonus", "WAITING", "Next re-use attempt in " .. math.ceil(Bonus.nextTry - os.clock()) .. "s")
		return 2
	end
	if Bonus.attempts >= 3 then
		State.set("bonus", "ERROR", "Re-use didn't bring the bonus back after 3 tries; stopped retrying")
		return 10
	end
	local item = P.findTool(function(t)
		if not isBonusItem(t) then
			return false
		end
		if Cfg.bonusItem == "Any" then
			return true
		end
		return Util.norm(t.Name) == Util.norm(Cfg.bonusItem)
	end)
	if not item then
		State.set("bonus", "UNAVAILABLE", "No " .. (Cfg.bonusItem == "Any" and "ice cream or taho" or Cfg.bonusItem) .. " in your inventory")
		return 5
	end
	State.set("bonus", "WORKING", "Using " .. item.Name)
	local used = false
	local got = Sched.withBody(token, "bonus", 50, function()
		local previous = P.equipped()
		-- Last check right before using it: never spend an item while the bonus is running.
		Bonus.labelsAt = -1000
		if Bonus.detect().active ~= false then
			return
		end
		if Actions.equip(token, item) then
			local fired = false
			local conn = item.Activated:Connect(function()
				fired = true
			end)
			Actions.useTool(token, item)
			Sched.wait(token, 1.5)
			conn:Disconnect()
			used = fired
		end
		if previous and Util.alive(previous) and previous ~= item then
			Actions.equip(token, previous)
		else
			Actions.unequip(token)
		end
	end, 10)
	if not got or not used then
		State.set("bonus", "WAITING", "Re-use didn't happen this time; will check again")
		return 3
	end
	Bonus.attempts = Bonus.attempts + 1
	Bonus.nextTry = os.clock() + 30
	if Bonus.refresh().active then
		Bonus.attempts = 0
		Log.success("Bonus", "Sales bonus is active again (" .. item.Name .. ").")
		State.complete("bonus")
	else
		Log.warn("Bonus", "Used " .. item.Name .. " but the bonus indicator didn't come back yet.")
	end
	return 2
end

--==================================================================================
-- 21. FEATURE: AUTO CLEANING (Broom → dust piles inside, BroomStick → leaf piles outside)
--==================================================================================
local Clean = { key = "clean", title = "Auto Cleaning", category = "Clean", failed = {} }

local TOOL_FOR = { dust = "Broom", leaf = "BroomStick" }

-- A pile is dirty while its prompt exists and the pile is visible (or its prompt is on).
local function pileDirty(info)
	local p = info.prompt
	if not Util.alive(p) then
		return false
	end
	if p.Enabled then
		return true
	end
	local holder = p.Parent
	local visible = false
	pcall(function()
		if holder:IsA("BasePart") then
			visible = holder.Transparency < 0.95
		else
			for _, d in ipairs(holder:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 0.95 then
					visible = true
					break
				end
			end
		end
	end)
	return visible
end

function Clean.piles()
	local out = {}
	for _, kind in ipairs({ "dust", "leaf" }) do
		local on = (kind == "dust" and Cfg.cleanIndoor) or (kind == "leaf" and Cfg.cleanOutdoor)
		if on then
			for _, info in ipairs(Plot.find("pile", kind)) do
				local f = Clean.failed[info.prompt]
				if pileDirty(info) and not (f and os.clock() - f < 30) then
					out[#out + 1] = info
				end
			end
		end
	end
	return out
end

function Clean.getTool(token, kind)
	local name = TOOL_FOR[kind]
	local tool = P.toolNamed(name)
	if tool then
		return tool
	end
	local stand = Plot.first("broomStand", kind)
	if not stand then
		return nil, "the " .. name .. " stand wasn't found"
	end
	local ok, why = Actions.trigger(token, stand.prompt, {
		verify = function()
			return P.toolNamed(name)
		end,
		timeout = 3,
	})
	if not ok then
		return nil, "couldn't pick up the " .. name .. ": " .. tostring(why)
	end
	return P.toolNamed(name)
end

local function pileClean(info)
	return not pileDirty(info) or not info.prompt.Enabled
end

function Clean.step(token, manual)
	local usable, whyNot = Plot.usable()
	if not usable then
		State.set("clean", "WAITING", whyNot)
		return 3
	end
	local piles = Clean.piles()
	State.pending.piles = #piles
	if #piles == 0 then
		State.set("clean", "IDLE", "Store is clean")
		return manual and 0 or 3
	end
	-- Work on the pile type nearest to you first (fewer tool swaps, shorter walks).
	table.sort(piles, function(a, b)
		return Util.distance(P.root, a.prompt) < Util.distance(P.root, b.prompt)
	end)
	local kind = piles[1].sub
	State.set("clean", "WORKING", "Sweeping " .. (kind == "dust" and "dust inside" or "leaves outside"))
	Sched.withBody(token, "clean", 40, function()
		local tool, why = Clean.getTool(token, kind)
		if not tool then
			Log.warn("Clean", tostring(why))
			State.fail("clean", tostring(why))
			Clean.failed[piles[1].prompt] = os.clock()
			return
		end
		if not Actions.equip(token, tool) then
			Log.warn("Clean", "Couldn't take out the " .. TOOL_FOR[kind] .. ".")
			return
		end
		local swept, started = 0, os.clock()
		while true do
			-- Give other features a turn now and then (the loop picks up again right away).
			if swept >= 6 or os.clock() - started > 60 then
				break
			end
			local remaining = {}
			for _, info in ipairs(Clean.piles()) do
				if info.sub == kind then
					remaining[#remaining + 1] = info
				end
			end
			State.pending.piles = #Clean.piles()
			if #remaining == 0 then
				break
			end
			table.sort(remaining, function(a, b)
				return Util.distance(P.root, a.prompt) < Util.distance(P.root, b.prompt)
			end)
			local info = remaining[1]
			if not Util.alive(tool) then
				break -- the game took the broom back (job done)
			end
			if tool.Parent ~= P.character then
				Actions.equip(token, tool)
			end
			local name = info.prompt.Parent and info.prompt.Parent.Name or "pile"
			if not info.prompt.Enabled then
				-- Visible but the game hasn't switched its prompt on: skip quietly for a while.
				Clean.failed[info.prompt] = os.clock()
				Log.debug("Clean", name .. " isn't sweepable right now (its prompt is off).")
				break
			end
			swept = swept + 1
			local ok, err = Actions.trigger(token, info.prompt, {
				verify = function()
					return pileClean(info)
				end,
				timeout = 2.5,
			})
			if ok then
				State.clean.cleaned = State.clean.cleaned + 1
				State.clean.lastPile = Util.clock() .. " — " .. name
				Log.success("Clean", "Swept " .. name .. ".")
				State.complete("clean")
			else
				Clean.failed[info.prompt] = os.clock()
				Log.warn("Clean", "Couldn't sweep " .. name .. ": " .. tostring(err) .. " (will retry in 30 s).")
				State.fail("clean", tostring(err))
			end
		end
	end, 20)
	return 0.5
end

--==================================================================================
-- 22. GUI (BETTER LIFE EXPANSION MOD · Created by BZM)
--==================================================================================
local UI = { maid = Maid.new(), pages = {}, nav = {}, refreshers = {}, watchers = {}, current = nil, visible = true }
local C = {
	bg = Color3.fromRGB(15, 17, 24),
	side = Color3.fromRGB(20, 23, 32),
	card = Color3.fromRGB(26, 30, 42),
	card2 = Color3.fromRGB(33, 38, 53),
	stroke = Color3.fromRGB(50, 56, 76),
	text = Color3.fromRGB(236, 239, 247),
	sub = Color3.fromRGB(148, 156, 178),
	accent = Color3.fromRGB(255, 183, 77),
	accentDark = Color3.fromRGB(196, 122, 30),
	on = Color3.fromRGB(52, 199, 123),
	off = Color3.fromRGB(72, 78, 98),
	warn = Color3.fromRGB(245, 190, 40),
	err = Color3.fromRGB(235, 87, 87),
	info = Color3.fromRGB(96, 165, 250),
}
local STATUS_COLOR = {
	OFF = C.off, IDLE = C.on, WATCHING = C.on, WORKING = C.accent, CHECKING = C.accent, STARTING = C.info,
	WAITING = C.warn, PAUSED = C.warn, ERROR = C.err, UNAVAILABLE = C.err,
}
local LEVEL_COLOR = { INFO = C.sub, SUCCESS = C.on, WARN = C.warn, ERROR = C.err, DEBUG = C.info }
local FONT = Enum.Font.Gotham
local FONT_MED = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local AUTO_Y = Enum.AutomaticSize.Y

local function new(class, props)
	local o = Instance.new(class)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			o[k] = v
		end
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(parent, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = parent })
end

local function stroke(parent, color)
	return new("UIStroke", { Color = color or C.stroke, Thickness = 1, Parent = parent })
end

local function pad(parent, a, b)
	b = b or a
	return new("UIPadding", {
		PaddingTop = UDim.new(0, a),
		PaddingBottom = UDim.new(0, a),
		PaddingLeft = UDim.new(0, b),
		PaddingRight = UDim.new(0, b),
		Parent = parent,
	})
end

local function vlist(parent, gap)
	return new("UIListLayout", { Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = parent })
end

local function hex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function esc(s)
	s = string.gsub(tostring(s), "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

local function label(parent, text, size, color, font, props)
	local l = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AUTO_Y,
		BackgroundTransparency = 1,
		Font = font or FONT,
		TextSize = size or 13,
		TextColor3 = color or C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = text or "",
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function binding(key)
	if type(key) == "table" then
		return key.get, key.set
	end
	return function()
		return Cfg[key]
	end, function(v)
		setCfg(key, v)
	end
end

function UI.watch(key, fn)
	if type(key) ~= "string" then
		return
	end
	UI.watchers[key] = UI.watchers[key] or {}
	table.insert(UI.watchers[key], fn)
end

function UI.onRefresh(page, fn)
	UI.refreshers[page] = UI.refreshers[page] or {}
	table.insert(UI.refreshers[page], fn)
end

-- ---------- widgets ----------
function UI.page(name)
	local page = new("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.stroke,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = AUTO_Y,
		Visible = false,
		Parent = UI.content,
	})
	pad(page, 14, 16)
	vlist(page, 10)
	UI.pages[name] = page
	return page
end

function UI.card(page, title, subtitle)
	local card = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundColor3 = C.card, Parent = page })
	corner(card, 10)
	stroke(card)
	pad(card, 12, 14)
	vlist(card, 8)
	if title then
		label(card, title, 15, C.accent, FONT_BOLD)
	end
	if subtitle then
		label(card, subtitle, 12, C.sub)
	end
	return card
end

function UI.text(parent, text, color, size)
	return label(parent, text, size or 12, color or C.sub)
end

function UI.toggle(parent, title, desc, key, onClick)
	local get, set = binding(key)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundColor3 = C.card2, Parent = parent })
	corner(row, 8)
	pad(row, 9, 12)
	local holder = new("Frame", { Size = UDim2.new(1, -60, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, Parent = row })
	vlist(holder, 2)
	label(holder, title, 14, C.text, FONT_MED)
	if desc and desc ~= "" then
		label(holder, desc, 12, C.sub)
	end
	local sw = new("Frame", { Size = UDim2.fromOffset(44, 22), Position = UDim2.new(1, -44, 0.5, -11), BackgroundColor3 = C.off, Parent = row })
	corner(sw, 11)
	local knob = new("Frame", { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sw })
	corner(knob, 9)
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = row })
	local function render()
		local on = get() and true or false
		sw.BackgroundColor3 = on and C.on or C.off
		knob.Position = on and UDim2.fromOffset(24, 2) or UDim2.fromOffset(2, 2)
	end
	UI.maid:connect(hit.MouseButton1Click, function()
		set(not get())
		render()
		if onClick then
			onClick(get())
		end
	end)
	UI.watch(key, render)
	render()
	return row, render
end

local function controlRow(parent, title, desc)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundColor3 = C.card2, Parent = parent })
	corner(row, 8)
	pad(row, 9, 12)
	local holder = new("Frame", { Size = UDim2.new(1, -170, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, Parent = row })
	vlist(holder, 2)
	label(holder, title, 13, C.text, FONT_MED)
	if desc and desc ~= "" then
		label(holder, desc, 11, C.sub)
	end
	return row
end

local function smallButton(parent, text, pos, size, color)
	local b = new("TextButton", {
		Size = size,
		Position = pos,
		BackgroundColor3 = color or C.bg,
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = C.text,
		Text = text,
		AutoButtonColor = true,
		Parent = parent,
	})
	corner(b, 6)
	return b
end

function UI.stepper(parent, title, desc, key, min, max, step, suffix)
	local get, set = binding(key)
	local row = controlRow(parent, title, desc)
	local minus = smallButton(row, "−", UDim2.new(1, -160, 0.5, -13), UDim2.fromOffset(30, 26))
	local value = new("TextLabel", {
		Size = UDim2.fromOffset(90, 26),
		Position = UDim2.new(1, -126, 0.5, -13),
		BackgroundTransparency = 1,
		Font = FONT_MED,
		TextSize = 13,
		TextColor3 = C.accent,
		Parent = row,
	})
	local plus = smallButton(row, "+", UDim2.new(1, -32, 0.5, -13), UDim2.fromOffset(30, 26))
	local function fmt(v)
		if step < 1 then
			return string.format("%.1f", v) .. (suffix or "")
		end
		return tostring(math.floor(v + 0.5)) .. (suffix or "")
	end
	local function render()
		value.Text = fmt(get())
	end
	local function bump(dir)
		local v = get() + dir * step
		v = math.floor(v / step + 0.5) * step
		if v < min then
			v = min
		end
		if v > max then
			v = max
		end
		set(v)
		render()
	end
	UI.maid:connect(minus.MouseButton1Click, function()
		bump(-1)
	end)
	UI.maid:connect(plus.MouseButton1Click, function()
		bump(1)
	end)
	UI.watch(key, render)
	render()
	return row
end

function UI.choice(parent, title, desc, key, options, onChange)
	local get, set = binding(key)
	local row = controlRow(parent, title, desc)
	local btn = smallButton(row, "", UDim2.new(1, -160, 0.5, -13), UDim2.fromOffset(160, 26), C.bg)
	btn.TextColor3 = C.accent
	btn.Font = FONT_MED
	local function opts()
		return type(options) == "function" and options() or options
	end
	local function render()
		btn.Text = "‹  " .. tostring(get()) .. "  ›"
	end
	UI.maid:connect(btn.MouseButton1Click, function()
		local list = opts()
		local idx = Util.find(list, get()) or 0
		local nextValue = list[(idx % #list) + 1]
		set(nextValue)
		render()
		if onChange then
			onChange(nextValue)
		end
	end)
	UI.watch(key, render)
	render()
	return row, render
end

function UI.input(parent, title, desc, key, onCommit)
	local get, set = binding(key)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundColor3 = C.card2, Parent = parent })
	corner(row, 8)
	pad(row, 9, 12)
	vlist(row, 4)
	label(row, title, 13, C.text, FONT_MED)
	if desc and desc ~= "" then
		label(row, desc, 11, C.sub)
	end
	local box = new("TextBox", {
		Size = UDim2.new(1, 0, 0, 28),
		AutomaticSize = AUTO_Y,
		BackgroundColor3 = C.bg,
		Font = FONT,
		TextSize = 12,
		TextColor3 = C.text,
		PlaceholderColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ClearTextOnFocus = false,
		Text = tostring(get() or ""),
		Parent = row,
	})
	corner(box, 6)
	pad(box, 6, 8)
	UI.maid:connect(box.FocusLost, function()
		if type(get()) == "number" then
			local n = tonumber((string.gsub(box.Text, "[^%d%.]", "")))
			if n then
				set(n)
			end
			box.Text = tostring(get())
		else
			set(box.Text)
		end
		if onCommit then
			onCommit(box.Text)
		end
	end)
	UI.watch(key, function()
		box.Text = tostring(get() or "")
	end)
	return row, box
end

function UI.buttons(parent, defs)
	local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, Parent = parent })
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	local out = {}
	for i, d in ipairs(defs) do
		local b = new("TextButton", {
			Size = UDim2.new(0, d.width or 150, 1, 0),
			BackgroundColor3 = d.color or C.accentDark,
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = C.text,
			Text = d.text,
			LayoutOrder = i,
			Parent = holder,
		})
		corner(b, 7)
		UI.maid:connect(b.MouseButton1Click, function()
			local ok, err = pcall(d.fn, b)
			if not ok then
				Log.error("System", "Button '" .. d.text .. "' failed: " .. tostring(err))
			end
		end)
		out[i] = b
	end
	return holder, out
end

-- Key/value line; returns a setter (text, color).
function UI.kv(parent, key)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, Parent = parent })
	label(row, key, 12, C.sub, FONT, { Size = UDim2.new(0.38, 0, 0, 0) })
	local v = label(row, "—", 12, C.text, FONT_MED, { Size = UDim2.new(0.62, 0, 0, 0), Position = UDim2.fromScale(0.38, 0) })
	return function(text, color)
		v.Text = tostring(text)
		v.TextColor3 = color or C.text
	end
end

-- Multi-line block; returns a setter taking a list of {text, color} or strings.
function UI.lines(parent)
	local l = label(parent, "", 12, C.text, FONT, { RichText = true })
	return function(lines)
		local parts = {}
		for _, item in ipairs(lines) do
			if type(item) == "table" then
				parts[#parts + 1] = '<font color="' .. hex(item[2] or C.text) .. '">' .. esc(item[1]) .. "</font>"
			else
				parts[#parts + 1] = esc(item)
			end
		end
		l.Text = #parts > 0 and table.concat(parts, "\n") or '<font color="' .. hex(C.sub) .. '">—</font>'
	end
end

local function pill(parent, text, color, props)
	local p = new("TextLabel", {
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = C.bg,
		Text = text,
		Parent = parent,
	})
	corner(p, 10)
	pad(p, 0, 8)
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return p
end

function UI.statusLine(parent, featureKey)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, Parent = parent })
	local p = pill(row, "OFF", C.off)
	local d = label(row, "", 12, C.sub, FONT, { Size = UDim2.new(1, -110, 0, 0), Position = UDim2.fromOffset(104, 2) })
	return function()
		local f = State.features[featureKey]
		if not f then
			return
		end
		p.Text = f.status
		p.BackgroundColor3 = STATUS_COLOR[f.status] or C.off
		local extra = string.format("  ·  done %d  ·  failed %d", f.completed, f.failed)
		d.Text = (f.detail ~= "" and f.detail or "—") .. extra
	end
end

-- ---------- window ----------
local NAV = {
	{ "Dashboard", "◆" },
	{ "Transaction Management", "₱" },
	{ "Auto Stack", "▤" },
	{ "Auto Order", "✚" },
	{ "Cashier Automation", "▣" },
	{ "Utang Collection", "✎" },
	{ "NPC / Thief Management", "⚑" },
	{ "Ice Cream & Taho Bonus", "❄" },
	{ "Auto Cleaning", "✧" },
	{ "Settings", "⚙" },
	{ "Activity Logs", "≡" },
}
local NAV_FEATURE = {
	["Transaction Management"] = "shortcut",
	["Auto Stack"] = "stack",
	["Auto Order"] = "order",
	["Cashier Automation"] = "cashier",
	["Utang Collection"] = "utang",
	["NPC / Thief Management"] = "thief",
	["Ice Cream & Taho Bonus"] = "bonus",
	["Auto Cleaning"] = "clean",
}

function UI.show(name)
	for n, page in pairs(UI.pages) do
		page.Visible = (n == name)
	end
	for n, b in pairs(UI.nav) do
		b.BackgroundColor3 = (n == name) and C.card2 or C.side
		b.TextColor3 = (n == name) and C.accent or C.text
	end
	UI.current = name
	UI.refresh()
end

function UI.setVisible(on)
	UI.visible = on
	if UI.main then
		UI.main.Visible = on and not UI.minimized
	end
	if UI.mini then
		UI.mini.Visible = on and UI.minimized
	end
end

local function makeDraggable(handle, target)
	local dragging, startInput, startPos = false, nil, nil
	UI.maid:connect(handle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startInput, startPos = true, input.Position, target.Position
			UI.dragMoved = 0
		end
	end)
	UI.maid:connect(handle.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UI.maid:connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - startInput
			UI.dragMoved = math.max(UI.dragMoved or 0, math.abs(delta.X) + math.abs(delta.Y))
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

function UI.build(onUnload)
	local gui = new("ScreenGui", {
		Name = "BLEM_BZM",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999,
	})
	local parent = nil
	if Env.gethui then
		local ok, h = pcall(Env.gethui)
		if ok and h then
			parent = h
		end
	end
	if not parent and CoreGui then
		local ok = pcall(function()
			gui.Parent = CoreGui
		end)
		if ok and gui.Parent == CoreGui then
			parent = CoreGui
		end
	end
	gui.Parent = parent or P.gui
	UI.gui = gui
	UIHooks.root = gui
	UI.maid:give(gui)

	local main = new("Frame", {
		Name = "Main",
		Size = UDim2.fromOffset(760, 500),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.bg,
		Active = true, -- clicks on the menu never reach the game world (no accidental tool use)
		Parent = gui,
	})
	corner(main, 12)
	stroke(main, C.stroke)
	UI.main = main

	local header = new("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = C.side, Active = true, Parent = main })
	corner(header, 12)
	new("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = C.side, BorderSizePixel = 0, Parent = header })
	local badge = new("TextLabel", {
		Size = UDim2.fromOffset(42, 42),
		Position = UDim2.fromOffset(10, 8),
		BackgroundColor3 = C.accent,
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = C.bg,
		Text = "BZM",
		Parent = header,
	})
	corner(badge, 10)
	label(header, "BETTER LIFE EXPANSION MOD", 17, C.accent, FONT_BOLD, {
		Size = UDim2.new(1, -260, 0, 22),
		AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.fromOffset(62, 9),
	})
	local hint = label(header, "", 11, C.sub, FONT, {
		Size = UDim2.new(1, -260, 0, 16),
		AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.fromOffset(62, 33),
	})
	local function renderHint()
		hint.Text = "Created by BZM  ·  v" .. VERSION .. "  ·  " .. tostring(Cfg.toggleKey) .. " hides/shows"
	end
	renderHint()
	UI.watch("toggleKey", renderHint)
	UI.headerPill = pill(header, "0 running", C.off, { Position = UDim2.new(1, -184, 0, 19) })
	local minBtn = smallButton(header, "–", UDim2.new(1, -84, 0, 15), UDim2.fromOffset(32, 28), C.card2)
	local closeBtn = smallButton(header, "×", UDim2.new(1, -44, 0, 15), UDim2.fromOffset(32, 28), C.card2)
	makeDraggable(header, main)

	local side = new("ScrollingFrame", {
		Size = UDim2.new(0, 200, 1, -66),
		Position = UDim2.fromOffset(0, 62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = AUTO_Y,
		Parent = main,
	})
	pad(side, 4, 8)
	vlist(side, 4)
	UI.content = new("Frame", {
		Size = UDim2.new(1, -206, 1, -66),
		Position = UDim2.fromOffset(204, 62),
		BackgroundColor3 = C.side,
		Parent = main,
	})
	corner(UI.content, 10)
	UI.navDots = {}
	for i, item in ipairs(NAV) do
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = C.side,
			Font = FONT_MED,
			TextSize = 13,
			TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "   " .. item[2] .. "   " .. item[1],
			LayoutOrder = i,
			AutoButtonColor = true,
			Parent = side,
		})
		corner(b, 7)
		if NAV_FEATURE[item[1]] then
			local dot = new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.new(1, -16, 0.5, -4), BackgroundColor3 = C.off, Parent = b })
			corner(dot, 4)
			UI.navDots[NAV_FEATURE[item[1]]] = dot
		end
		UI.nav[item[1]] = b
		UI.maid:connect(b.MouseButton1Click, function()
			UI.show(item[1])
		end)
	end

	-- Minimized pill
	local mini = new("TextButton", {
		Size = UDim2.fromOffset(190, 34),
		Position = UDim2.new(0, 16, 1, -60),
		BackgroundColor3 = C.bg,
		Font = FONT_BOLD,
		TextSize = 13,
		TextColor3 = C.accent,
		Text = "BZM · Better Life  ▲",
		Visible = false,
		Parent = gui,
	})
	corner(mini, 17)
	local miniStroke = stroke(mini, C.accent)
	miniStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	UI.mini = mini
	makeDraggable(mini, mini)
	UI.maid:connect(minBtn.MouseButton1Click, function()
		UI.minimized = true
		UI.setVisible(true)
	end)
	UI.maid:connect(mini.MouseButton1Click, function()
		if (UI.dragMoved or 0) > 6 then
			return -- that was a drag, not a click
		end
		UI.minimized = false
		UI.setVisible(true)
	end)
	local armed = false
	UI.maid:connect(closeBtn.MouseButton1Click, function()
		if not armed then
			armed = true
			closeBtn.Text = "?"
			closeBtn.BackgroundColor3 = C.err
			Log.info("System", "Press × again within 3 seconds to unload the mod.")
			task.delay(3, function()
				armed = false
				if closeBtn.Parent then
					closeBtn.Text = "×"
					closeBtn.BackgroundColor3 = C.card2
				end
			end)
		else
			onUnload("closed from the menu")
		end
	end)

	-- Never let a real (virtual) mouse click land on this menu or its minimized pill.
	UIHooks.hideAt = function(x, y)
		for _, f in ipairs({ UI.main, UI.mini }) do
			if f and f.Visible then
				local p, s = f.AbsolutePosition, f.AbsoluteSize
				if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
					UI.hiddenForClick = true
					gui.Enabled = false
					return
				end
			end
		end
	end
	UIHooks.restore = function()
		if UI.hiddenForClick then
			UI.hiddenForClick = false
			gui.Enabled = true
		end
	end

	UI.buildPages()
	UI.show("Dashboard")
end

-- ---------- pages ----------
local function featureHeader(page, key, title, desc)
	local card = UI.card(page, title, desc)
	return card
end

function UI.buildPages()
	-- DASHBOARD -------------------------------------------------------------
	local dash = UI.page("Dashboard")
	local pc = UI.card(dash, "Player")
	local setName = UI.kv(pc, "Player")
	local setId = UI.kv(pc, "User ID")
	local setChar = UI.kv(pc, "Character")
	local setPlot = UI.kv(pc, "Plot")
	local setMoney = UI.kv(pc, "Money")
	local setExec = UI.kv(pc, "Executor")

	local sc = UI.card(dash, "Automation status")
	local statusSetters = {}
	for _, key in ipairs(State.order) do
		local f = State.features[key]
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, Parent = sc })
		label(row, f.title, 12, C.text, FONT_MED, { Size = UDim2.new(0, 160, 0, 0) })
		local p = pill(row, "OFF", C.off, { Position = UDim2.fromOffset(164, 0) })
		local d = label(row, "", 11, C.sub, FONT, { Size = UDim2.new(1, -270, 0, 0), Position = UDim2.fromOffset(266, 3) })
		statusSetters[key] = function()
			p.Text = f.status
			p.BackgroundColor3 = STATUS_COLOR[f.status] or C.off
			d.Text = f.detail ~= "" and f.detail or "—"
		end
	end

	local ac = UI.card(dash, "Activity")
	local setDone = UI.kv(ac, "Completed activities")
	local setPending = UI.kv(ac, "Pending tasks")
	local setFailed = UI.kv(ac, "Failed operations")
	local tc = UI.card(dash, "Current transaction")
	local setStage = UI.kv(tc, "Now")
	local setLastTx = UI.kv(tc, "Last transaction")
	local setTxTotals = UI.kv(tc, "This session")
	local uc = UI.card(dash, "Outstanding utang")
	local setUtang = UI.kv(uc, "Outstanding")
	local setUtangCol = UI.kv(uc, "Collected (session)")
	local ic = UI.card(dash, "Inventory & restocking")
	local setStands = UI.kv(ic, "Shelves")
	local setBoxes = UI.kv(ic, "Boxes carried")
	local setDeliv = UI.kv(ic, "Deliveries waiting")
	local setOrders = UI.kv(ic, "Pending orders")
	local bc = UI.card(dash, "Ice Cream & Taho bonus")
	local setBonus = UI.kv(bc, "Status")
	local wc = UI.card(dash, "Errors & warnings")
	local setWarn = UI.lines(wc)

	UI.onRefresh("Dashboard", function()
		local plr = P.player
		setName(plr and (plr.DisplayName .. " (@" .. plr.Name .. ")") or "—")
		setId(plr and plr.UserId or "—")
		if P.ready() then
			setChar(string.format("Alive · %d/%d HP", math.floor(P.humanoid.Health), math.floor(P.humanoid.MaxHealth)), C.on)
		else
			setChar("Not ready (dead or respawning)", C.err)
		end
		if Plot.model then
			setPlot(Plot.model.Name .. "  (" .. Plot.method .. ")" .. (Plot.trusted and "" or " — plot features paused until you confirm it in Settings"),
				Plot.trusted and C.text or C.warn)
		else
			setPlot("Not found — choose it in Settings", C.err)
		end
		local m, src = P.money()
		setMoney(m and (Util.formatMoney(m) .. "  (" .. src .. ")") or "Not shown by the game")
		setExec(Env.executorName())
		for _, fn in pairs(statusSetters) do
			fn()
		end
		local parts = {}
		for _, key in ipairs(State.order) do
			local f = State.features[key]
			if f.completed > 0 then
				parts[#parts + 1] = f.title .. " " .. f.completed
			end
		end
		setDone(State.totals.completed .. (#parts > 0 and ("  (" .. table.concat(parts, ", ") .. ")") or ""))
		local pd = State.pending
		local total = pd.customers + pd.piles + pd.stands + pd.orders + pd.utang + pd.thieves
		setPending(total .. string.format("  (customers %d · piles %d · low shelves %d · orders %d · utang %d · thieves %d)",
			pd.customers, pd.piles, pd.stands, pd.orders, pd.utang, pd.thieves), total > 0 and C.warn or C.text)
		setFailed(State.totals.failed, State.totals.failed > 0 and C.err or C.text)
		local tx = State.transaction
		setStage(tx.stage .. (tx.kind ~= "—" and (" · " .. tx.kind) or "") .. (tx.amount and (" · " .. Util.formatMoney(tx.amount)) or ""),
			tx.stage == "Idle" and C.text or C.accent)
		local h = State.history[1]
		setLastTx(h and (h.time .. " · " .. h.kind .. " · " .. h.outcome .. (h.amount and (" · " .. Util.formatMoney(h.amount)) or "")) or "—")
		local t = State.tx
		setTxTotals(string.format("cash %d (change %s) · KashG %d · utang %d · declined %d · left for you %d · failed %d",
			t.cash, Util.formatMoney(t.change), t.kashg, t.utang, t.declined, t.manual, t.failed))
		local u = State.utang
		setUtang(u.count and (u.count .. " debt(s) · " .. Util.formatMoney(u.total) .. " · read " .. Util.ago(u.lastRead)) or "Not read yet (turn on Utang Collection or press 'Collect now')")
		setUtangCol(u.collected .. " · " .. Util.formatMoney(u.collectedTotal))
		local st = State.stock
		if st.lastScan then
			setStands(#st.stands .. " found · " .. State.pending.stands .. " low/empty · scanned " .. Util.ago(st.lastScan))
			local bx = {}
			for _, b in ipairs(st.boxes) do
				bx[#bx + 1] = b.product .. (b.count and (" (" .. b.count .. ")") or "")
			end
			setBoxes(#bx > 0 and table.concat(bx, ", ") or "none")
			setDeliv(#st.deliveries)
		else
			setStands("Not scanned yet (Auto Stack → Scan shelves)")
		end
		local po = {}
		for _, o in pairs(State.orders.pending) do
			po[#po + 1] = o.qty .. "× " .. o.product
		end
		setOrders(#po > 0 and table.concat(po, ", ") or "none")
		setBonus(State.bonus.status, State.bonus.active and C.on or C.sub)
		local probs = {}
		for i = #Log.entries, 1, -1 do
			local e = Log.entries[i]
			if e.level == "WARN" or e.level == "ERROR" then
				probs[#probs + 1] = { e.stamp .. "  " .. e.category .. ": " .. e.message, LEVEL_COLOR[e.level] }
				if #probs >= 6 then
					break
				end
			end
		end
		setWarn(probs)
	end)

	-- TRANSACTION MANAGEMENT -------------------------------------------------
	local txp = UI.page("Transaction Management")
	local c1 = featureHeader(txp, "shortcut", "Completion Shortcut",
		"When a payment window is already complete and verified — the exact change is already counted, or the KashG window shows a successful payment — it goes straight to Confirm/Accept instead of repeating the whole sequence. It never creates a payment, never skips the game's own checks, and leaves anything unverified alone.")
	UI.toggle(c1, "Completion Shortcut", "Also finishes windows you opened yourself once they're verified.", "shortcutEnabled")
	local stShort = UI.statusLine(c1, "shortcut")
	local c2 = UI.card(txp, "Transactions this session")
	local setNow = UI.kv(c2, "Current")
	local setTot = UI.kv(c2, "Totals")
	local c3 = UI.card(txp, "Recent transactions")
	local setHist = UI.lines(c3)
	UI.onRefresh("Transaction Management", function()
		stShort()
		local tx = State.transaction
		setNow(tx.stage .. (tx.kind ~= "—" and (" · " .. tx.kind) or "") .. (tx.amount and (" · " .. Util.formatMoney(tx.amount)) or ""))
		local t = State.tx
		setTot(string.format("Cash %d (change %s) · KashG %d · Utang %d · Declined %d · Left for you %d · Failed %d",
			t.cash, Util.formatMoney(t.change), t.kashg, t.utang, t.declined, t.manual, t.failed))
		local lines = {}
		for i = 1, math.min(15, #State.history) do
			local h = State.history[i]
			local color = (h.outcome == "Completed" and C.on) or (h.outcome == "Failed" and C.err) or (h.outcome == "Manual" and C.warn) or C.sub
			lines[#lines + 1] = {
				string.format("%s  %-6s %-9s %s%s%s", h.time, h.kind, h.outcome, h.amount and Util.formatMoney(h.amount) or "",
					h.seconds and string.format(" · %.1fs", h.seconds) or "", h.note ~= "" and (" · " .. h.note) or ""),
				color,
			}
		end
		setHist(lines)
	end)

	-- AUTO STACK --------------------------------------------------------------
	local sp = UI.page("Auto Stack")
	local s1 = featureHeader(sp, "stack", "Auto Stack",
		"Brings delivery boxes in from the truck bay, takes each box to the stand that sells that product, holds Restock, and checks that the box count actually dropped. Stands that refuse a product are skipped for 10 minutes so nothing is processed over and over.")
	UI.toggle(s1, "Auto Stack", "Restock low or empty shelves automatically.", "stackEnabled")
	local stStack = UI.statusLine(s1, "stack")
	UI.stepper(s1, "Restock below", "A stand counts as low when it is below this fill level (when the game shows its stock).", "stackThreshold", 10, 100, 10, "%")
	UI.toggle(s1, "Pick up deliveries", "Collect delivery boxes from the truck bay.", "stackPickup")
	UI.toggle(s1, "Store leftover boxes", "Put a partly used box on the box shelf when no stand needs it.", "stackStoreLeftovers")
	UI.buttons(s1, {
		{ text = "Scan shelves now", fn = function()
			Stack.scan()
			Log.info("Stack", "Shelf scan: " .. #State.stock.stands .. " stand(s), " .. State.pending.stands .. " low/empty, "
				.. #State.stock.boxes .. " box(es) carried, " .. #State.stock.deliveries .. " delivery(ies) waiting.")
		end },
		{ text = "Restock now", fn = function()
			Sched.runNow("stack")
		end },
	})
	local s2 = UI.card(sp, "Shelves")
	local setShelves = UI.lines(s2)
	local s3 = UI.card(sp, "Boxes & deliveries")
	local setBoxList = UI.lines(s3)
	UI.onRefresh("Auto Stack", function()
		stStack()
		local lines = {}
		for _, s in ipairs(State.stock.stands) do
			local color = (s.need and C.warn) or (s.need == false and C.on) or C.sub
			if string.find(s.status, "Mismatch", 1, true) then
				color = C.err
			end
			lines[#lines + 1] = { s.name .. "  ·  " .. (s.product or "product unknown") .. "  ·  " .. s.status, color }
		end
		if not State.stock.lastScan then
			lines = { { "Press 'Scan shelves now' or turn on Auto Stack.", C.sub } }
		end
		setShelves(lines)
		local b = {}
		for _, x in ipairs(State.stock.boxes) do
			b[#b + 1] = "Carrying: " .. x.product .. (x.count and (" (" .. x.count .. " inside)") or "")
		end
		for _, d in ipairs(State.stock.deliveries) do
			b[#b + 1] = { "At the truck bay: " .. tostring(d.prompt.ObjectText) .. (d.enabled and "" or " (not available yet)"), C.accent }
		end
		setBoxList(b)
	end)

	-- AUTO ORDER --------------------------------------------------------------
	local op = UI.page("Auto Order")
	local o1 = featureHeader(op, "order", "Auto Order",
		"Watches the shelves and the game's Stock Alert list, then orders what's missing from the laptop's Orders tab. Products already in a box, waiting at the truck bay, or already ordered are skipped, so nothing is ordered twice.")
	UI.toggle(o1, "Auto Order", "Order low or out-of-stock products automatically.", "orderEnabled")
	local stOrder = UI.statusLine(o1, "order")
	UI.stepper(o1, "Quantity per product", "How many times '+' is pressed for each product.", "orderQty", 1, 10, 1)
	UI.stepper(o1, "Products per order", "Most products in one order.", "orderMaxProducts", 1, 20, 1)
	UI.input(o1, "Keep at least (₱)", "Skip a product if buying it would leave you with less money than this. Type an amount.", "orderMinMoney")
	UI.stepper(o1, "Check every", "", "orderInterval", 15, 600, 15, " s")
	UI.stepper(o1, "Re-order after", "If an order hasn't arrived after this long, it may be ordered again.", "orderPendingMin", 1, 60, 1, " min")
	UI.toggle(o1, "Use the Stock Alert list", "Also order whatever the game's Stock Alert lists.", "orderUseAlert")
	UI.buttons(o1, {
		{ text = "Check what's needed", fn = function()
			local list = Order.needs(nil)
			local names = {}
			for _, n in ipairs(list) do
				names[#names + 1] = n.product .. " (" .. n.why .. ")"
			end
			Log.info("Order", #names > 0 and ("Needed: " .. table.concat(names, "; ")) or "From the shelves, nothing needs ordering right now.")
		end },
		{ text = "Order now", fn = function()
			Sched.runNow("order")
		end },
	})
	local o2 = UI.card(op, "Orders")
	local setNeeds = UI.kv(o2, "Needed now")
	local setPend = UI.kv(o2, "Pending (not delivered yet)")
	local setLast = UI.kv(o2, "Last order")
	local setCat = UI.kv(o2, "Products on the laptop")
	UI.onRefresh("Auto Order", function()
		stOrder()
		local n = {}
		for _, x in ipairs(State.orders.lastNeeds) do
			n[#n + 1] = x.product
		end
		setNeeds(#n > 0 and table.concat(n, ", ") or "nothing")
		local p = {}
		for _, o in pairs(State.orders.pending) do
			p[#p + 1] = o.qty .. "× " .. o.product .. " (" .. o.clock .. ")"
		end
		setPend(#p > 0 and table.concat(p, ", ") or "none")
		setLast(State.orders.lastOrder or "—")
		local c = 0
		for _ in pairs(State.orders.catalog) do
			c = c + 1
		end
		setCat(c > 0 and (c .. " products read") or "Not read yet (read when the laptop is opened)")
	end)

	-- CASHIER AUTOMATION ----------------------------------------------------------
	local cp = UI.page("Cashier Automation")
	local k1 = featureHeader(cp, "cashier", "Cashier Automation",
		"Rings up waiting customers at the register and handles the payment window the game opens. Each payment type has its own switch. A sale only counts once the game closes the window; anything it can't verify is left for you and shown here.")
	UI.toggle(k1, "Auto Checkout", "Use the register when a customer is waiting.", "cashierEnabled")
	local stCash = UI.statusLine(k1, "cashier")
	local k2 = UI.card(cp, "Payment methods")
	UI.toggle(k2, "Cash", "Count the exact change (sukli) with the fewest bills/coins, then Confirm.", "payCash")
	UI.toggle(k2, "GCash (KashG)", "Accept KashG e-wallet payments (see the KashG check below).", "payKashG")
	UI.toggle(k2, "Accept Utang", "Let customers who ask pay later (goes in the Utang Book).", "utangAccept")
	UI.toggle(k2, "Decline Utang requests", "Turn this on to refuse every pay-later request.", "utangDecline")
	local k3 = UI.card(cp, "KashG check")
	UI.choice(k3, "Accept KashG when", "Verified only = the window must show a success word.", "kashgPolicy", { "Verified only", "Accept unless invalid", "Manual review" })
	UI.toggle(k3, "Decline invalid KashG", "Decline payments whose window shows a failure word or a short amount.", "kashgDeclineInvalid")
	UI.input(k3, "Success words", "Comma-separated; any of these in the KashG window counts as verified.", "successWords")
	UI.input(k3, "Failure words", "Comma-separated; any of these marks the payment invalid.", "failWords")
	local k4 = UI.card(cp, "Customers")
	UI.toggle(k4, "Require a customer nearby", "Only use the register when a customer is standing near it.", "requireCustomer")
	UI.stepper(k4, "Customer distance", "", "customerRadius", 6, 40, 2, " studs")
	local k5 = UI.card(cp, "Status")
	local setWaiting = UI.kv(k5, "Customers waiting")
	local setLastK = UI.kv(k5, "Last result")
	local setManual = UI.kv(k5, "Needs you")
	UI.onRefresh("Cashier Automation", function()
		stCash()
		setWaiting(State.pending.customers)
		local h = State.history[1]
		setLastK(h and (h.time .. " · " .. h.kind .. " · " .. h.outcome .. (h.note ~= "" and (" · " .. h.note) or "")) or "—")
		setManual(Tx.manual and (Tx.manual.kind .. ": " .. Tx.manual.reason) or "nothing", Tx.manual and C.warn or C.text)
	end)

	-- UTANG COLLECTION --------------------------------------------------------------
	local upg = UI.page("Utang Collection")
	local u1 = featureHeader(upg, "utang", "Utang Collection",
		"Opens the Utang Book on a timer and presses Collect on debts the game lets you collect, largest first. A debt only counts as collected when its row changes, and the same debt is never pressed twice.")
	UI.toggle(u1, "Auto Collect Utang", "", "utangEnabled")
	local stUtang = UI.statusLine(u1, "utang")
	UI.stepper(u1, "Check every", "", "utangInterval", 15, 600, 15, " s")
	UI.choice(u1, "Order", "", "utangPriority", { "Largest first", "Book order" })
	UI.buttons(u1, { { text = "Collect now", fn = function()
		Sched.runNow("utang")
	end } })
	local u2 = UI.card(upg, "Utang Book (last read)")
	local setOut = UI.kv(u2, "Outstanding")
	local setCol = UI.kv(u2, "Collected (session)")
	local setRows = UI.lines(u2)
	UI.onRefresh("Utang Collection", function()
		stUtang()
		local u = State.utang
		setOut(u.count and (u.count .. " debt(s) · " .. Util.formatMoney(u.total) .. " · " .. State.pending.utang .. " collectable · read " .. Util.ago(u.lastRead)) or "Not read yet")
		setCol(u.collected .. " · " .. Util.formatMoney(u.collectedTotal))
		local lines = {}
		for _, r in ipairs(u.rows or {}) do
			lines[#lines + 1] = { (r.name ~= "" and r.name or "(no name)") .. "  ·  " .. (r.amount and Util.formatMoney(r.amount) or "?") .. "  ·  " .. (r.eligible and "collectable" or "not yet"), r.eligible and C.on or C.sub }
		end
		setRows(lines)
	end)

	-- NPC / THIEF ------------------------------------------------------------------
	local tp = UI.page("NPC / Thief Management")
	local t1 = featureHeader(tp, "thief", "Thief Management",
		"Watches for thieves near your store, takes out the Tsinelas, closes in and swings (3 by default), checking before every swing whether the thief has been stopped. Players, customers and other NPCs are never targeted. Afterwards it walks back and puts your previous item back in your hand.")
	UI.toggle(t1, "Auto stop thieves", "", "thiefEnabled")
	local stThief = UI.statusLine(t1, "thief")
	UI.stepper(t1, "Swings per round", "", "thiefSwings", 1, 5, 1)
	UI.stepper(t1, "Rounds", "Rounds of swings before giving up for 15 s.", "thiefRounds", 1, 5, 1)
	UI.stepper(t1, "Swing distance", "", "thiefRange", 3, 12, 1, " studs")
	UI.stepper(t1, "Watch radius", "How far from your store to look for thieves.", "thiefRadius", 40, 300, 10, " studs")
	UI.toggle(t1, "Return afterwards", "Walk back to where you were.", "thiefReturn")
	UI.input(t1, "Thief words", "An NPC counts as a thief when its name, an attribute or its overhead label contains one of these.", "thiefWords")
	local t2 = UI.card(tp, "Incidents")
	local setNowT = UI.kv(t2, "Thieves near you")
	local setStopped = UI.kv(t2, "Stopped / escaped")
	local setLastT = UI.kv(t2, "Last incident")
	local setTs = UI.kv(t2, "Tsinelas")
	UI.onRefresh("NPC / Thief Management", function()
		stThief()
		local names = {}
		for _, n in ipairs(State.thief.seen or {}) do
			names[#names + 1] = n.model.Name .. " (" .. tostring(n.reason) .. ")"
		end
		setNowT(#names > 0 and table.concat(names, ", ") or "none", #names > 0 and C.warn or C.text)
		setStopped(State.thief.stopped .. " / " .. State.thief.escaped .. "  ·  " .. State.thief.swings .. " swings")
		setLastT(State.thief.last or "—")
		local ts = P.findTool(function(t)
			return string.find(string.lower(t.Name), "tsinelas", 1, true) ~= nil
		end)
		setTs(ts and "in your inventory" or "not found", ts and C.on or C.err)
	end)

	-- ICE CREAM & TAHO -------------------------------------------------------------------
	local bp = UI.page("Ice Cream & Taho Bonus")
	local b1 = UI.card(bp, "Ice Cream & Taho sales bonus (+10%)",
		"The mod never uses, drops or puts away these items by itself, so the game's bonus is never removed or overridden. Other features only take out the item they need and give your previous item back.")
	local setBS = UI.kv(b1, "Bonus")
	local setSrc = UI.kv(b1, "Read from")
	local setUsed = UI.kv(b1, "Last used")
	local setItems = UI.kv(b1, "Items you have")
	local b2 = featureHeader(bp, "bonus", "Optional: re-use when the bonus ends",
		"Only works when the game shows the bonus status; otherwise it stays unavailable instead of guessing.")
	UI.toggle(b2, "Auto re-use bonus item", "", "bonusReapply")
	local stBonus = UI.statusLine(b2, "bonus")
	UI.choice(b2, "Item to use", "", "bonusItem", { "Any", "Avocado Ice Cream", "Classic Taho" })
	UI.onRefresh("Ice Cream & Taho Bonus", function()
		Bonus.refresh()
		stBonus()
		setBS(State.bonus.status, State.bonus.active and C.on or C.sub)
		setSrc(State.bonus.source or "—")
		setUsed(State.bonus.lastUsed and (State.bonus.lastItem .. " · " .. Util.ago(State.bonus.lastUsed)) or "not seen this session")
		local items = {}
		for _, t in ipairs(P.tools()) do
			if isBonusItem(t) then
				items[#items + 1] = t.Name
			end
		end
		setItems(#items > 0 and table.concat(items, ", ") or "none")
	end)

	-- AUTO CLEANING -------------------------------------------------------------------
	local clp = UI.page("Auto Cleaning")
	local l1 = featureHeader(clp, "clean", "Auto Cleaning",
		"Finds dirty spots on your plot, gets the right broom (Broom for dust inside, BroomStick for leaves outside), and sweeps the nearest pile first. A pile only counts once the game removes it; clean spots are never swept again.")
	UI.toggle(l1, "Auto Clean", "", "cleanEnabled")
	local stClean = UI.statusLine(l1, "clean")
	UI.toggle(l1, "Indoor dust", "", "cleanIndoor")
	UI.toggle(l1, "Outdoor leaves", "", "cleanOutdoor")
	UI.buttons(l1, { { text = "Clean now", fn = function()
		Sched.runNow("clean")
	end } })
	local l2 = UI.card(clp, "Store")
	local setDirty = UI.kv(l2, "Dirty piles")
	local setCleaned = UI.kv(l2, "Swept (session)")
	local setBrooms = UI.kv(l2, "Brooms")
	UI.onRefresh("Auto Cleaning", function()
		stClean()
		local d, l = 0, 0
		for _, info in ipairs(Clean.piles()) do
			if info.sub == "dust" then
				d = d + 1
			else
				l = l + 1
			end
		end
		setDirty(d .. " dust · " .. l .. " leaves", (d + l) > 0 and C.warn or C.on)
		setCleaned(State.clean.cleaned .. (State.clean.lastPile and ("  ·  last " .. State.clean.lastPile) or ""))
		setBrooms("Broom " .. (P.toolNamed("Broom") and "✓" or "—") .. "   BroomStick " .. (P.toolNamed("BroomStick") and "✓" or "—")
			.. "   ·  stands found: " .. #Plot.find("broomStand"))
	end)

	-- SETTINGS -------------------------------------------------------------------------
	local stp = UI.page("Settings")
	local g1 = UI.card(stp, "Behaviour")
	UI.choice(g1, "Movement", "Teleport moves your character instantly; only use it where it's allowed.", "movement", { "Walk", "Teleport" }, function(v)
		if v == "Teleport" then
			Log.warn("System", "Teleport movement is on. Only use it where the game owner allows it.")
		end
	end)
	UI.stepper(g1, "Delay between clicks", "Human-like pause before each button press.", "actionDelay", 0.1, 2, 0.1, " s")
	UI.choice(g1, "Click method", "Auto = real (virtual) mouse clicks, so the game's own input checks apply; the game's button handlers are only used if your executor has no VirtualInputManager.", "clickMethod", { "Auto", "Virtual mouse", "Game signals" })
	UI.toggle(g1, "Pause while I move", "Automation stops moving your character while you use WASD/Space.", "manualOverride")
	UI.stepper(g1, "Pause length", "", "overrideSeconds", 1, 15, 1, " s")
	UI.choice(g1, "Menu key", "", "toggleKey", { "RightShift", "RightControl", "Insert", "End", "F6" })
	UI.toggle(g1, "Debug log", "Also record DEBUG details (e.g. what the KashG window says).", "debugLog")
	local g2 = UI.card(stp, "Your plot")
	UI.choice(g2, "Plot", "Auto detects your plot by its owner marker.", "plotChoice", function()
		local list = { "Auto" }
		for _, p in ipairs(Plot.list()) do
			list[#list + 1] = p.Name
		end
		return list
	end, function()
		Plot.refresh()
	end)
	local setPlotS = UI.kv(g2, "Current")
	UI.buttons(g2, {
		{ text = "Re-detect plot", fn = function()
			setCfg("plotChoice", "Auto")
			Plot.refresh()
		end },
		{ text = "This is my plot", width = 160, fn = function()
			if not Plot.model then
				Log.warn("System", "No plot is shown yet; stand on your plot and press Re-detect, or pick it in the list.")
				return
			end
			setCfg("plotChoice", Plot.model.Name)
			Plot.refresh()
		end },
	})
	local g3 = UI.card(stp, "Files & tools")
	local setFiles = UI.kv(g3, "Saved in")
	UI.buttons(g3, {
		{ text = "Save settings", fn = function()
			local ok, err = saveConfig()
			if ok then
				Log.success("System", "Settings saved to " .. CONFIG_PATH .. ".")
			else
				Log.error("System", "Couldn't save settings: " .. tostring(err))
			end
		end },
		{ text = "Export game scan", width = 160, fn = function()
			UI.exportScan()
		end },
		{ text = "Unload mod", color = C.err, fn = function()
			UI.unloadCallback("unloaded from Settings")
		end },
	})
	local g4 = UI.card(stp, "Executor compatibility (" .. Env.executorName() .. ")")
	local compat = {}
	for _, r in ipairs(Env.report()) do
		compat[#compat + 1] = { (r.ok and "✓ " or "✗ ") .. r.name .. " — " .. r.use, r.ok and C.on or C.err }
	end
	UI.lines(g4)(compat)
	UI.onRefresh("Settings", function()
		if Plot.model then
			setPlotS(Plot.model.Name .. " (" .. Plot.method .. ")" .. (Plot.trusted and "" or " — plot features paused"), Plot.trusted and C.text or C.warn)
		else
			setPlotS("not found — " .. tostring(Plot.method), C.err)
		end
		setFiles(Env.writefile and ("executor workspace/" .. Env.ROOT .. "/") or "Your executor can't write files (settings won't be saved)")
	end)

	-- ACTIVITY LOGS ------------------------------------------------------------------
	local lp = UI.page("Activity Logs")
	local filter = { cat = "All", level = "All", search = "" }
	local lc = UI.card(lp, "Activity Logs", "Every automation action, transaction, completed task and failure, newest at the bottom.")
	local cats = { "All" }
	for _, c in ipairs(Log.CATEGORIES) do
		cats[#cats + 1] = c
	end
	UI.choice(lc, "Category", "", { get = function()
		return filter.cat
	end, set = function(v)
		filter.cat = v
	end }, cats, function()
		UI.renderLogs()
	end)
	UI.choice(lc, "Level", "Problems = warnings and errors.", { get = function()
		return filter.level
	end, set = function(v)
		filter.level = v
	end }, { "All", "Problems", "SUCCESS", "INFO", "WARN", "ERROR", "DEBUG" }, function()
		UI.renderLogs()
	end)
	UI.input(lc, "Search", "", { get = function()
		return filter.search
	end, set = function(v)
		filter.search = v
	end }, function()
		UI.renderLogs()
	end)
	local setLogInfo = UI.kv(lc, "Showing")
	UI.buttons(lc, {
		{ text = "Export TXT", fn = function()
			local list = Log.filter(filter.cat, filter.level, filter.search)
			local path, err = Log.export(list, "category " .. filter.cat .. ", level " .. filter.level .. (filter.search ~= "" and (", search '" .. filter.search .. "'") or ""))
			if path then
				Log.success("System", "Exported " .. #list .. " log entries to " .. path .. ".")
			else
				Log.error("System", "Export failed: " .. tostring(err))
			end
		end },
		{ text = "Copy to clipboard", fn = function()
			if not Env.setclipboard then
				Log.error("System", "This executor has no setclipboard().")
				return
			end
			local lines = {}
			for _, e in ipairs(Log.filter(filter.cat, filter.level, filter.search)) do
				lines[#lines + 1] = Log.format(e)
			end
			Env.setclipboard(table.concat(lines, "\n"))
			Log.info("System", "Copied " .. #lines .. " log entries.")
		end },
		{ text = "Clear", color = C.card2, width = 90, fn = function()
			Log.entries = {}
			UI.renderLogs()
		end },
	})
	local listFrame = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 300),
		BackgroundColor3 = C.bg,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = AUTO_Y,
		Parent = lp,
	})
	corner(listFrame, 8)
	pad(listFrame, 8, 10)
	vlist(listFrame, 2)
	UI.logList, UI.logRows, UI.logOrder, UI.logFilter = listFrame, {}, {}, filter
	local function rowText(e)
		return '<font color="' .. hex(C.sub) .. '">' .. e.stamp .. '</font>  <font color="' .. hex(LEVEL_COLOR[e.level] or C.text) .. '">'
			.. e.level .. '</font>  <font color="' .. hex(C.accent) .. '">' .. e.category .. "</font>  " .. esc(e.message)
			.. (e.repeats > 1 and ('  <font color="' .. hex(C.sub) .. '">×' .. e.repeats .. "</font>") or "")
	end
	local LOG_ROWS = 250
	local function addRow(e)
		local l = label(listFrame, rowText(e), 12, C.text, FONT, { RichText = true, LayoutOrder = e.id })
		UI.logRows[e.id] = l
		UI.logOrder[#UI.logOrder + 1] = e.id
		while #UI.logOrder > LOG_ROWS do
			local old = table.remove(UI.logOrder, 1)
			if UI.logRows[old] then
				UI.logRows[old]:Destroy()
				UI.logRows[old] = nil
			end
		end
	end
	function UI.renderLogs()
		for _, l in pairs(UI.logRows) do
			l:Destroy()
		end
		UI.logRows, UI.logOrder = {}, {}
		local list = Log.filter(filter.cat, filter.level, filter.search)
		for i = math.max(1, #list - LOG_ROWS + 1), #list do
			addRow(list[i])
		end
		setLogInfo(math.min(#list, LOG_ROWS) .. " of " .. #list .. " matching (" .. #Log.entries .. " kept, " .. Log.total .. " recorded this session)")
		task.defer(function()
			if listFrame.Parent then
				listFrame.CanvasPosition = Vector2.new(0, 1e6)
			end
		end)
	end
	UI.maid:give(Log.added:Connect(function(e, isRepeat)
		if not Log.matches(e, filter.cat, filter.level, filter.search) then
			return
		end
		if isRepeat and UI.logRows[e.id] then
			UI.logRows[e.id].Text = rowText(e)
		elseif not isRepeat then
			-- Follow new entries only when you're already at the bottom of the list.
			local atBottom = listFrame.CanvasPosition.Y + listFrame.AbsoluteSize.Y >= listFrame.AbsoluteCanvasSize.Y - 40
			addRow(e)
			if UI.current == "Activity Logs" and atBottom then
				task.defer(function()
					if listFrame.Parent then
						listFrame.CanvasPosition = Vector2.new(0, 1e6)
					end
				end)
			end
		end
	end))
	UI.renderLogs()
end

-- Writes what the mod can see of the game to a TXT file (helps tune detection).
function UI.exportScan()
	local L = {
		"BETTER LIFE EXPANSION MOD v" .. VERSION .. " · game scan · " .. Util.timestamp(),
		"PlaceId " .. tostring(game.PlaceId) .. " · Executor " .. Env.executorName(),
		"Player " .. (P.player and P.player.Name or "?") .. " · Plot " .. (Plot.model and Plot.model.Name or "none") .. " (" .. Plot.method .. ")",
		"",
		"== PROMPTS ON YOUR PLOT ==",
	}
	local list = {}
	for p, info in pairs(Plot.prompts) do
		if Util.alive(p) then
			list[#list + 1] = string.format("[%s%s] %s | Action '%s' | Object '%s' | Enabled %s | Hold %.1fs | Range %d",
				info.kind, info.sub and ("/" .. info.sub) or "", Util.fullName(p), p.ActionText, p.ObjectText, tostring(p.Enabled), p.HoldDuration, math.floor(p.MaxActivationDistance))
		end
	end
	table.sort(list)
	for _, s in ipairs(list) do
		L[#L + 1] = s
	end
	L[#L + 1] = ""
	L[#L + 1] = "== SHELVES (as read) =="
	for _, s in ipairs(Stack.scan().stands) do
		L[#L + 1] = s.name .. " | product " .. tostring(s.product) .. " (" .. tostring(s.productHow) .. ") | stock " .. tostring(s.stock) .. "/" .. tostring(s.cap) .. " | " .. s.status
	end
	L[#L + 1] = ""
	L[#L + 1] = "== TOOLS =="
	for _, t in ipairs(P.tools()) do
		L[#L + 1] = t.Name .. " (" .. (t.Parent == P.character and "in hand" or "backpack") .. ")"
	end
	L[#L + 1] = ""
	L[#L + 1] = "== NPCs WITHIN 150 STUDS OF YOUR PLOT =="
	for _, n in ipairs(NPC.near(Plot.center(), 150)) do
		local attrs = {}
		pcall(function()
			for k, v in pairs(n.model:GetAttributes()) do
				attrs[#attrs + 1] = k .. "=" .. tostring(v)
			end
		end)
		local yes, why = Thief.classify(n.model)
		L[#L + 1] = string.format("%s | %.0f studs | HP %d | attrs {%s} | thief: %s", Util.fullName(n.model), n.distance, math.floor(n.humanoid.Health), table.concat(attrs, ", "), yes and why or "no")
	end
	L[#L + 1] = ""
	L[#L + 1] = "== PLAYER ATTRIBUTES / LEADERSTATS =="
	pcall(function()
		for k, v in pairs(P.player:GetAttributes()) do
			L[#L + 1] = "player." .. k .. " = " .. tostring(v)
		end
		local ls = P.player:FindFirstChild("leaderstats")
		if ls then
			for _, v in ipairs(ls:GetChildren()) do
				if v:IsA("ValueBase") then
					L[#L + 1] = "leaderstats." .. v.Name .. " = " .. tostring(v.Value)
				end
			end
		end
	end)
	for _, name in ipairs({ "CashierGui", "KashGGui", "UtangGui", "LaptopShopGui", "StockAlertGui", "StockAlertPanel", "HotbarGui" }) do
		L[#L + 1] = ""
		L[#L + 1] = "== GUI: " .. name .. " =="
		local g = P.gui and P.gui:FindFirstChild(name)
		if g then
			for _, line in ipairs(GG.dump(g, 9)) do
				L[#L + 1] = line
			end
		else
			L[#L + 1] = "(not present right now)"
		end
	end
	L[#L + 1] = ""
	L[#L + 1] = "== OTHER SCREEN GUIS =="
	if P.gui then
		for _, g in ipairs(P.gui:GetChildren()) do
			L[#L + 1] = g.ClassName .. " " .. g.Name
		end
	end
	local path = Env.ROOT .. "/scans/BLEM_scan_" .. Util.fileStamp() .. ".txt"
	local ok, err = Env.write(path, table.concat(L, "\n") .. "\n")
	if ok then
		Log.success("System", "Game scan saved to " .. path .. " (open a cashier/KashG/utang window first to include it).")
	else
		Log.error("System", "Couldn't save the game scan: " .. tostring(err))
	end
end

function UI.refresh()
	if not UI.main then
		return
	end
	local running = 0
	for _, key in ipairs(State.order) do
		local f = State.features[key]
		if f.status ~= "OFF" then
			running = running + 1
		end
		local dot = UI.navDots[key]
		if dot then
			dot.BackgroundColor3 = STATUS_COLOR[f.status] or C.off
		end
	end
	UI.headerPill.Text = running .. " running"
	UI.headerPill.BackgroundColor3 = running > 0 and C.on or C.off
	local fns = UI.refreshers[UI.current]
	if fns and UI.main.Visible then
		for _, fn in ipairs(fns) do
			local ok, err = pcall(fn)
			if not ok then
				Log.debug("System", "UI refresh error on " .. UI.current .. ": " .. tostring(err))
			end
		end
	end
end

function UI.destroy()
	UIHooks.hideAt, UIHooks.restore, UIHooks.root = nil, nil, nil
	UI.maid:destroy()
	UI.main, UI.mini, UI.gui = nil, nil, nil
end

--==================================================================================
-- 23. START-UP & UNLOAD
--==================================================================================
local Main = { maid = Maid.new(), unloaded = false }

local FEATURE_KEYS = {
	shortcutEnabled = "shortcut",
	cashierEnabled = "cashier",
	stackEnabled = "stack",
	orderEnabled = "order",
	utangEnabled = "utang",
	thiefEnabled = "thief",
	bonusReapply = "bonus",
	cleanEnabled = "clean",
}

function Main.unload(reason)
	if Main.unloaded then
		return
	end
	Main.unloaded = true
	pcall(Sched.stopAll)
	pcall(function()
		Actions.stop()
	end)
	pcall(function()
		Bonus.maid:destroy()
		Plot.maid:destroy()
		Main.maid:destroy()
	end)
	pcall(UI.destroy)
	if GENV.BLEM and GENV.BLEM.unload == Main.unload then
		GENV.BLEM = nil
	end
	print("[BLEM] Better Life Expansion Mod unloaded (" .. tostring(reason or "unload") .. ").")
end

local function boot()
	loadConfig()
	-- Small scripting API: getgenv().BLEM.set("cleanEnabled", true), .get(key), .runNow("clean"), .unload()
	GENV.BLEM = {
		unload = Main.unload,
		version = VERSION,
		set = setCfg,
		get = function(key)
			return Cfg[key]
		end,
		runNow = function(feature)
			Sched.runNow(feature)
		end,
		state = State,
		log = Log,
		internals = { Tx = Tx, Sched = Sched, Plot = Plot, UI = UI, Stack = Stack, Order = Order, Clean = Clean, Thief = Thief, Bonus = Bonus, Actions = Actions, P = P },
	}
	Log.info("System", "Better Life Expansion Mod v" .. VERSION .. " · Created by BZM · " .. Env.executorName())
	for _, r in ipairs(Env.report()) do
		if not r.ok then
			Log.warn("System", "Executor is missing " .. r.name .. " (used for " .. r.use .. ").")
		end
	end
	if game.PlaceId ~= GAME_PLACE_ID then
		Log.warn("System", "This place (" .. tostring(game.PlaceId) .. ") isn't the Sari-Sari Store game (" .. GAME_PLACE_ID
			.. "). If it's your own test copy that's fine; otherwise detection may fail.")
	end

	-- Player first: nothing automated runs until the character exists.
	P.init(Main.maid)
	Log.info("Player", "Player: " .. P.player.DisplayName .. " (@" .. P.player.Name .. ", " .. P.player.UserId .. ").")
	local t0 = os.clock()
	while not P.ready() and os.clock() - t0 < 20 and not Main.unloaded do
		task.wait(0.2)
	end
	if Main.unloaded then
		return -- a newer copy was started while this one was waiting
	end
	if not P.ready() then
		Log.warn("Player", "Character not ready yet; features wait for it automatically.")
	end

	Actions.init(Main.maid)
	Plot.refresh()
	NPC.init(Main.maid)
	Bonus.watchTools()
	Main.maid:give(P.respawned:Connect(function()
		Bonus.watchTools()
		if not Plot.model or not Util.alive(Plot.model) then
			Plot.refresh()
		end
	end))

	Sched.register(Shortcut)
	Sched.register(Cashier)
	Sched.register(Stack)
	Sched.register(Order)
	Sched.register(Utang)
	Sched.register(Thief)
	Sched.register(Bonus)
	Sched.register(Clean)

	-- Feature switches ↔ loops. Turning one off never touches the others.
	Main.maid:give(CfgChanged:Connect(function(key, value)
		local feature = FEATURE_KEYS[key]
		if feature then
			Sched.setEnabled(feature, value and true or false)
		end
		if key == "utangAccept" and value and Cfg.utangDecline then
			setCfg("utangDecline", false)
		elseif key == "utangDecline" and value and Cfg.utangAccept then
			setCfg("utangAccept", false)
		elseif key == "debugLog" then
			Log.info("System", "Debug logging " .. (value and "on" or "off") .. ".")
		end
		local fns = UI.watchers[key]
		if fns then
			for _, fn in ipairs(fns) do
				pcall(fn)
			end
		end
	end))

	-- Your own movement pauses automation (manual override) + the menu key.
	local MOVE_KEYS = { W = true, A = true, S = true, D = true, Space = true, Up = true, Down = true, Left = true, Right = true }
	Main.maid:connect(UserInputService.InputBegan, function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if processed then
			return -- typing in chat or a text box
		end
		local name = input.KeyCode.Name
		if MOVE_KEYS[name] then
			Sched.lastUserInput = os.clock()
		end
		if name == Cfg.toggleKey then
			UI.setVisible(not UI.visible)
		end
	end)

	if Main.unloaded then
		return
	end
	UI.build(Main.unload)
	UI.unloadCallback = Main.unload

	-- One light refresh loop for the whole menu.
	local acc = 0
	Main.maid:connect(RunService.Heartbeat, function(dt)
		acc = acc + dt
		if acc >= 0.5 then
			acc = 0
			pcall(UI.refresh)
		end
	end)
	-- Bonus status is shown even when its optional re-use feature is off; an unconfirmed plot is
	-- re-checked every 10 s (owner markers can appear a little after you join).
	task.spawn(function()
		local lastPlotCheck = os.clock()
		while not Main.unloaded do
			pcall(Bonus.refresh)
			if not Plot.trusted and Cfg.plotChoice == "Auto" and os.clock() - lastPlotCheck > 10 then
				lastPlotCheck = os.clock()
				pcall(Plot.refresh, true)
			end
			task.wait(3)
		end
	end)

	Log.success("System", "Ready. All automation is OFF — turn features on from the menu (" .. Cfg.toggleKey .. " shows/hides it).")
end

local ok, err = pcall(boot)
if not ok then
	warn("[BLEM] Better Life Expansion Mod failed to start: " .. tostring(err))
	pcall(Log.error, "System", "Start-up failed: " .. tostring(err))
	pcall(Main.unload, "start-up failed")
end
