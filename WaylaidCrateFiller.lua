local CRATES = {
	[248682] = {{20, 2447}, {20, 765}, {10, 2449}, {10, 785}, {10, 2450}},
	[248683] = {{20, 2770}, {20, 2771}},
	[248684] = {{40, 2589}, {20, 2318}},
	[248685] = {{20, 10940}, {4, 10939}, {6, 10978}, {2, 11084}},
	[248686] = {{10, 3820}, {10, 2453}, {10, 3355}, {10, 3369}, {10, 3356}},
	[248687] = {{10, 2775}, {20, 2772}},
	[248688] = {{20, 2592}, {40, 4306}, {20, 2319}},
	[248689] = {{20, 11083}, {4, 11082}, {6, 11138}, {2, 11139}},
	[248690] = {{20, 3357}, {10, 3818}, {10, 3821}, {10, 3358}},
	[248691] = {{10, 3819}, {10, 4625}, {20, 8831}, {10, 8836}},
	[248692] = {{10, 2776}, {20, 3858}},
	[248693] = {{40, 4338}, {20, 4234}},
	[248694] = {{20, 11137}, {4, 11135}, {6, 11177}, {2, 11178}},
	[248695] = {{10, 13464}, {20, 8838}, {10, 8839}, {10, 8845}, {10, 8846}},
	[248696] = {{20, 13463}, {20, 13465}, {20, 13466}, {20, 13467}},
	[248697] = {{10, 7911}, {20, 10620}, {20, 11370}},
	[248698] = {{40, 14047}, {20, 4304}, {20, 8170}},
	[248699] = {{20, 11176}, {4, 11175}, {6, 14343}, {2, 14344}},
	[248702] = {{2, 4231}, {20, 2996}},
	[248703] = {{20, 2840}, {20, 3576}, {10, 2841}},
	[248704] = {{16, 4359}, {16, 4361}, {4, 4363}},
	[248705] = {{6, 2997}, {10, 4305}, {2, 4233}},
	[248706] = {{10, 2842}, {20, 3575}},
	[248707] = {{8, 4371}, {7, 4375}, {4, 4382}, {45, 10558}},
	[248708] = {{8, 4339}, {2, 4236}},
	[248709] = {{20, 3860}, {15, 3859}, {10, 3577}},
	[248710] = {{8, 4387}, {5, 10559}, {12, 10560}, {5, 10561}},
	[248711] = {{8, 14048}, {2, 8172}},
	[248712] = {{2, 11371}, {10, 6037}, {20, 12359}},
	[248713] = {{5, 15994}, {5, 18631}, {2, 16000}},
}

local RECEIPT = 262902

local MATERIALS = {[RECEIPT] = true}
local MAX_OPTIONS = 0
for _, options in pairs(CRATES) do
	for _, option in ipairs(options) do
		MATERIALS[option[2]] = true
	end
	MAX_OPTIONS = math.max(MAX_OPTIONS, #options)
end

local TURN_INS = {
	[91899] = true, [91900] = true, [91901] = true, [91902] = true,
	[91904] = true, [91905] = true, [91906] = true, [91907] = true,
}
local TURN_IN_TITLES = {["A Sealed Crate"] = true, ["Crate Return"] = true}

local ICON, GAP, ROW, NAME_WIDTH, PAD = 32, 4, 36, 150, 16

local db, frame, empty, nextButton, lastCrate, lastMaterial
local rows = {}
local dismissed, queued, wheelBound = false, false, false

BINDING_HEADER_WAYLAIDCRATEFILLER = "Waylaid Crate Filler"
_G["BINDING_NAME_CLICK WaylaidCrateFillerNext:LeftButton"] = "Repeat last fill"

local function ScanBags()
	local crates, order, stacks = {}, {}, {}
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and CRATES[id] then
				local crate = crates[id]
				if not crate then
					crate = {id = id, bag = bag, slot = slot, count = 0, icon = info.iconFileID}
					crates[id] = crate
					order[#order + 1] = crate
				end
				crate.count = crate.count + info.stackCount
			elseif id and MATERIALS[id] and not info.isLocked then
				local list = stacks[id] or {}
				stacks[id] = list
				list[#list + 1] = {bag = bag, slot = slot, count = info.stackCount}
			end
		end
	end
	table.sort(order, function(a, b)
		return a.id < b.id
	end)
	return order, stacks
end

local function PickStack(list, need)
	local total, best, largest = 0, nil, nil
	for _, stack in ipairs(list or {}) do
		total = total + stack.count
		if stack.count >= need and (not best or stack.count < best.count) then
			best = stack
		end
		if not largest or stack.count > largest.count then
			largest = stack
		end
	end
	if best then
		return best, total, false
	end
	if total >= need then
		return largest, total, true
	end
	return nil, total, false
end

local function CrateName(crate)
	local name = C_Item.GetItemNameByID(crate.id)
	return name and name:gsub("^Waylaid Crate: ", "") or "..."
end

local function OptionTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(self.material)
	GameTooltip:AddLine(" ")
	if self.material == RECEIPT then
		GameTooltip:AddLine(string.format("Have %d", self.have), 1, 0.82, 0)
	else
		GameTooltip:AddLine(string.format("Have %d out of %d", self.have, self.need), 1, 0.82, 0)
	end
	if self.split then
		GameTooltip:AddLine("Split across stacks", 1, 0.5, 0.25)
	end
	GameTooltip:Show()
end

local function CrateTooltip(self)
	if not self.crate then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(self.crate.bag, self.crate.slot)
	GameTooltip:Show()
end

local function Ready(use)
	for _, part in ipairs(use) do
		local info = C_Container.GetContainerItemInfo(part[1], part[2])
		if not info or info.itemID ~= part[3] or info.isLocked then
			return false
		end
	end
	return true
end

local function PreClick(self)
	if InCombatLockdown() then
		return
	end
	local use = self.use
	self:SetAttribute("macrotext1", use and Ready(use) and use.macro or nil)
end

local function CreateOption(row, i)
	local b = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
	b:SetSize(ICON, ICON)
	b:SetPoint("LEFT", row, "LEFT", ICON + GAP + NAME_WIDTH + (i - 1) * (ICON + GAP), 0)
	b:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type1", "macro")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.25)
	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.count:SetPoint("BOTTOMRIGHT", -1, 2)
	b:SetScript("PreClick", PreClick)
	b:SetScript("PostClick", function(self)
		if self:GetAttribute("macrotext1") then
			lastCrate, lastMaterial = self.crate, self.material
		end
	end)
	b:SetScript("OnEnter", OptionTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function CreateRow(i)
	local row = CreateFrame("Frame", nil, frame)
	row:SetSize(ICON + GAP + NAME_WIDTH + (MAX_OPTIONS + 1) * (ICON + GAP), ICON)
	row:SetPoint("TOPLEFT", PAD, -40 - (i - 1) * ROW)
	row.crate = CreateFrame("Button", nil, row)
	row.crate:SetSize(ICON, ICON)
	row.crate:SetPoint("LEFT")
	row.crate.icon = row.crate:CreateTexture(nil, "ARTWORK")
	row.crate.icon:SetAllPoints()
	row.crate.count = row.crate:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	row.crate.count:SetPoint("BOTTOMRIGHT", -2, 2)
	row.crate:SetScript("OnEnter", CrateTooltip)
	row.crate:SetScript("OnLeave", GameTooltip_Hide)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.crate, "RIGHT", 6, 0)
	row.name:SetWidth(NAME_WIDTH - 10)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(true)
	row.options = {}
	for j = 1, MAX_OPTIONS + 1 do
		row.options[j] = CreateOption(row, j)
	end
	rows[i] = row
	return row
end

local function FillRow(row, crate, stacks, repeatUse)
	row.crate.crate = crate
	row.crate.icon:SetTexture(crate.icon)
	row.crate.count:SetText(crate.count > 1 and crate.count or "")
	row.name:SetText(CrateName(crate))
	local options = CRATES[crate.id]
	for j, b in ipairs(row.options) do
		local option = options[j]
		local receipt = not option and j == #options + 1 and stacks[RECEIPT]
		if option or receipt then
			local need, material = 1, RECEIPT
			if option then
				need, material = option[1], option[2]
			end
			local stack, have, split = PickStack(stacks[material], need)
			b.crate, b.material, b.need, b.have, b.split = crate.id, material, need, have, split
			b.icon:SetTexture(C_Item.GetItemIconByID(material))
			b.icon:SetDesaturated(not stack)
			b.icon:SetAlpha(stack and 1 or 0.4)
			b.count:SetText(receipt and have or have .. "/" .. need)
			if stack then
				b.count:SetTextColor(1, 1, 1)
			else
				b.count:SetTextColor(1, 0.3, 0.3)
			end
			local use
			if receipt then
				use = {{stack.bag, stack.slot, RECEIPT}, {crate.bag, crate.slot, crate.id}}
			elseif stack then
				use = {{crate.bag, crate.slot, crate.id}, {stack.bag, stack.slot, material}}
			end
			if use then
				use.macro = string.format("/stopspelltarget\n/use %d %d\n/use %d %d", use[1][1], use[1][2], use[2][1], use[2][2])
			end
			b.use = use
			b:SetAttribute("macrotext1", use and use.macro)
			if crate.id == lastCrate and material == lastMaterial then
				repeatUse = use
			end
			b:Show()
		else
			b.use = nil
			b:SetAttribute("macrotext1", nil)
			b:Hide()
		end
	end
	row:Show()
	return repeatUse
end

local function Refresh()
	queued = false
	if InCombatLockdown() then
		return
	end
	local crates, stacks = ScanBags()
	local repeatUse
	for i, crate in ipairs(crates) do
		repeatUse = FillRow(rows[i] or CreateRow(i), crate, stacks, repeatUse)
	end
	nextButton.use = repeatUse
	nextButton:SetAttribute("macrotext1", repeatUse and repeatUse.macro)
	for i = #crates + 1, #rows do
		rows[i]:Hide()
	end
	local columns = MAX_OPTIONS + (stacks[RECEIPT] and 1 or 0)
	frame:SetWidth(PAD * 2 + ICON + GAP + NAME_WIDTH + columns * (ICON + GAP))
	empty:SetShown(#crates == 0)
	frame:SetHeight(40 + math.max(#crates, 1) * ROW + 10)
	frame:SetShown(not dismissed and (#crates > 0 or frame.pinned))
end

local function QueueRefresh()
	if queued then
		return
	end
	queued = true
	C_Timer.After(0.2, Refresh)
end

local function SetWheel(on)
	if on == wheelBound or InCombatLockdown() then
		return
	end
	wheelBound = on
	if on then
		SetOverrideBindingClick(frame, true, "MOUSEWHEELUP", "WaylaidCrateFillerNext")
		SetOverrideBindingClick(frame, true, "MOUSEWHEELDOWN", "WaylaidCrateFillerNext")
	else
		ClearOverrideBindings(frame)
	end
end

local function CreateMain()
	nextButton = CreateFrame("Button", "WaylaidCrateFillerNext", UIParent, "SecureActionButtonTemplate")
	nextButton:RegisterForClicks("AnyDown")
	nextButton:SetAttribute("useOnKeyDown", true)
	nextButton:SetAttribute("type1", "macro")
	nextButton:SetScript("PreClick", PreClick)

	frame = CreateFrame("Frame", "WaylaidCrateFillerFrame", UIParent, "BackdropTemplate")
	frame:SetSize(PAD * 2 + ICON + GAP + NAME_WIDTH + MAX_OPTIONS * (ICON + GAP), 100)
	frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
	frame:SetFrameStrata("MEDIUM")
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = {left = 11, right = 12, top = 12, bottom = 11},
	})
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.point = {point, relPoint, x, y}
	end)
	frame:SetScript("OnUpdate", function(self)
		SetWheel(db.wheel and self:IsMouseOver())
	end)
	frame:SetScript("OnHide", function()
		SetWheel(false)
	end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 20, -18)
	title:SetText("Waylaid Crates")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		if InCombatLockdown() then
			return
		end
		dismissed = true
		frame.pinned = false
		frame:Hide()
	end)

	empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOPLEFT", PAD + 4, -50)
	empty:SetText("No crates in your bags")
	frame:Hide()
end

local function IsTurnIn(questID, title)
	return TURN_INS[questID] or TURN_IN_TITLES[title]
end

local function AutoTurnIn()
	return db and db.turnin and not IsModifiedClick("AUTOLOOTTOGGLE")
end

local QUEST_EVENTS = {
	GOSSIP_SHOW = function()
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests()) do
			if quest.isComplete and IsTurnIn(quest.questID, quest.title) then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
			if IsTurnIn(quest.questID, quest.title) then
				C_GossipInfo.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end,
	QUEST_GREETING = function()
		for i = 1, GetNumActiveQuests() do
			local title, isComplete = GetActiveTitle(i)
			if isComplete and IsTurnIn(GetActiveQuestID(i), title) then
				SelectActiveQuest(i)
				return
			end
		end
		for i = 1, GetNumAvailableQuests() do
			local questID = select(5, GetAvailableQuestInfo(i))
			if IsTurnIn(questID, GetAvailableTitle(i)) then
				SelectAvailableQuest(i)
				return
			end
		end
	end,
	QUEST_DETAIL = function()
		if IsTurnIn(GetQuestID(), GetTitleText()) then
			AcceptQuest()
		end
	end,
	QUEST_PROGRESS = function()
		if IsTurnIn(GetQuestID(), GetTitleText()) and IsQuestCompletable() then
			CompleteQuest()
		end
	end,
	QUEST_COMPLETE = function()
		local choices = GetNumQuestChoices()
		if choices <= 1 and IsTurnIn(GetQuestID(), GetTitleText()) then
			GetQuestReward(choices)
		end
	end,
}

local questEvents = CreateFrame("Frame")
for event in pairs(QUEST_EVENTS) do
	questEvents:RegisterEvent(event)
end
questEvents:SetScript("OnEvent", function(_, event)
	if AutoTurnIn() then
		QUEST_EVENTS[event]()
	end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		WaylaidCrateFillerDB = WaylaidCrateFillerDB or {}
		db = WaylaidCrateFillerDB
		db.point = db.point or {"CENTER", "CENTER", 0, 120}
		if db.wheel == nil then
			db.wheel = true
		end
		if db.turnin == nil then
			db.turnin = true
		end
		CreateMain()
		self:RegisterEvent("BAG_UPDATE_DELAYED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	end
	QueueRefresh()
end)

SLASH_WAYLAIDCRATEFILLER1 = "/crates"
SlashCmdList.WAYLAIDCRATEFILLER = function(msg)
	if msg:lower():match("^%s*wheel") then
		db.wheel = not db.wheel
		print("Waylaid Crate Filler: scroll to fill " .. (db.wheel and "on" or "off"))
		return
	end
	if msg:lower():match("^%s*turnin") then
		db.turnin = not db.turnin
		print("Waylaid Crate Filler: auto turn-in " .. (db.turnin and "on" or "off"))
		return
	end
	if InCombatLockdown() then
		return
	end
	if frame:IsShown() then
		dismissed = true
		frame.pinned = false
	else
		dismissed = false
		frame.pinned = true
	end
	Refresh()
end
