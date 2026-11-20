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

local MATERIALS = {}
local MAX_OPTIONS = 0
for _, options in pairs(CRATES) do
	for _, option in ipairs(options) do
		MATERIALS[option[2]] = true
	end
	MAX_OPTIONS = math.max(MAX_OPTIONS, #options)
end

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
	GameTooltip:AddLine(string.format("Have %d out of %d", self.have, self.need), 1, 0.82, 0)
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
	row:SetSize(ICON + GAP + NAME_WIDTH + MAX_OPTIONS * (ICON + GAP), ICON)
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
	for j = 1, MAX_OPTIONS do
		row.options[j] = CreateOption(row, j)
	end
	rows[i] = row
	return row
end

local function FillRow(row, crate, stacks, repeatMacro)
	row.crate.crate = crate
	row.crate.icon:SetTexture(crate.icon)
	row.crate.count:SetText(crate.count > 1 and crate.count or "")
	row.name:SetText(CrateName(crate))
	local options = CRATES[crate.id]
	for j, b in ipairs(row.options) do
		local option = options[j]
		if option then
			local need, material = option[1], option[2]
			local stack, have, split = PickStack(stacks[material], need)
			b.crate, b.material, b.need, b.have, b.split = crate.id, material, need, have, split
			b.icon:SetTexture(C_Item.GetItemIconByID(material))
			b.icon:SetDesaturated(not stack)
			b.icon:SetAlpha(stack and 1 or 0.4)
			b.count:SetText(have .. "/" .. need)
			if stack then
				b.count:SetTextColor(1, 1, 1)
			else
				b.count:SetTextColor(1, 0.3, 0.3)
			end
			local macro = stack and string.format("/use %d %d\n/use %d %d", crate.bag, crate.slot, stack.bag, stack.slot)
			b:SetAttribute("macrotext1", macro)
			if crate.id == lastCrate and material == lastMaterial then
				repeatMacro = macro
			end
			b:Show()
		else
			b:SetAttribute("macrotext1", nil)
			b:Hide()
		end
	end
	row:Show()
	return repeatMacro
end

local function Refresh()
	queued = false
	if InCombatLockdown() then
		return
	end
	local crates, stacks = ScanBags()
	local repeatMacro
	for i, crate in ipairs(crates) do
		repeatMacro = FillRow(rows[i] or CreateRow(i), crate, stacks, repeatMacro)
	end
	nextButton:SetAttribute("macrotext1", repeatMacro)
	for i = #crates + 1, #rows do
		rows[i]:Hide()
	end
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
