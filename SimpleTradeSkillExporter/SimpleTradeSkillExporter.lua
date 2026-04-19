-- SimpleTradeSkillExporter
-- Author: Hamma
-- Description: Exports trade skill recipes to plain text, CSV, or Markdown format.
--              Supports all classic WoW flavors (Vanilla, TBC, Wrath, Cata, MoP).
--              Use /tsexport or the Export button on the tradeskill window.
-- Download on: Curse, Wago.io, GitHub
-- addonName: the addon's folder name injected by the WoW client.
-- tse: a shared namespace table for this addon; passed to every file via `...`.
local addonName, tse = ...

-- Map each supported WoW flavor to its Wowhead base URL.
-- WOW_PROJECT_ID is a client-injected global identifying which game flavor is running.
local wowheadUrls = {
	[WOW_PROJECT_MISTS_CLASSIC]           = "https://wowhead.com/mop-classic/",
	[WOW_PROJECT_CATACLYSM_CLASSIC]       = "https://wowhead.com/cata/",
	[WOW_PROJECT_WRATH_CLASSIC]           = "https://wowhead.com/wotlk/",
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC] = "https://wowhead.com/tbc/",
	[WOW_PROJECT_CLASSIC]                 = "https://wowhead.com/classic/",
}
tse.wowheadBase = wowheadUrls[WOW_PROJECT_ID]

-- Minimum item ID for crafted items introduced in each expansion.
-- Item IDs are assigned sequentially as content is added, making them a reliable expansion signal.
-- Vanilla has no floor since there are no prior expansions to filter out.
local expansionItemIdFloors = {
	[WOW_PROJECT_MISTS_CLASSIC]           = 71000,
	[WOW_PROJECT_CATACLYSM_CLASSIC]       = 52000,
	[WOW_PROJECT_WRATH_CLASSIC]           = 35000,
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC] = 24000,
	[WOW_PROJECT_CLASSIC]                 = nil,
}
tse.expansionItemIdFloor = expansionItemIdFloors[WOW_PROJECT_ID]

-- Session state for the export options popup — persists last-used format and scope.
local selectedExportFormat = "text"
local selectedExportAll = false

local exportWindow       -- main export text frame, created lazily on first export
local exportOptionsFrame -- export options popup, created lazily on first button click

local openExportWindow
local createExportWindow
local createExportOptionsFrame

-- Parses the slash command message into export format and whether to include all expansions.
-- Examples: "csv all" -> ("csv", true), "markdown" -> ("markdown", false), "" -> ("", false)
local function parseCommand(msg)
	local parts = {}
	for part in msg:gmatch("%S+") do
		table.insert(parts, part)
	end

	local exportAll = parts[#parts] == "all"
	if exportAll then table.remove(parts, #parts) end

	return parts[1] or "", exportAll
end

-- Returns the item ID of the item crafted by the recipe at the given index, or nil.
local function getCraftedItemId(index)
	local itemLink = GetTradeSkillItemLink(index)
	if not itemLink then return nil end
	local itemId = itemLink:match("item:(%d+)")
	return itemId and tonumber(itemId) or nil
end

-- Returns true if the recipe at index belongs to the current expansion.
-- Uses the crafted item's ID as a proxy for expansion (IDs are assigned sequentially).
-- Includes the recipe if the item ID cannot be determined.
local function isCurrentExpansionRecipe(index)
	if not tse.expansionItemIdFloor then return true end
	local itemId = getCraftedItemId(index)
	if itemId == nil then return true end
	return itemId >= tse.expansionItemIdFloor
end

-- Returns player info as a table for use in header building.
local function getPlayerInfo()
	local name = UnitName("player")
	local race = UnitRace("player")
	local class = UnitClass("player")
	local level = UnitLevel("player")
	local guild = GetGuildInfo("player") or "-"
	local server = GetRealmName()
	return { name = name, race = race, class = class, level = level, guild = guild, server = server }
end

-- Formats a single recipe entry based on the export type.
local function buildRecipeEntry(name, itemLink, exportType)
	if exportType == "csv" then
		return '=HYPERLINK("' .. tse.wowheadBase .. itemLink .. '","' .. name .. '")\n'
	elseif exportType == "markdown" then
		return "- [" .. name .. "](" .. tse.wowheadBase .. itemLink .. ")\n"
	else
		return name .. "\n"
	end
end

-- Builds the header block for the export window based on export type.
local function buildHeader(player, skillName, rank, recipeCount, exportType)
	local header

	if exportType == "markdown" then
		header =
			"**Player:** " ..
			player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"**Guild:** " .. player.guild .. "  \n" ..
			"**Server:** " .. player.server .. "  \n"
		if rank > 0 then
			header = header ..
			"**" .. skillName .. ":** Skill " .. rank .. ", " .. recipeCount .. " total recipes" .. "  \n"
		end
		header = header .. "\n"
	elseif exportType == "csv" then
		header = ""
	else
		header =
			"Player: " ..
			player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"Guild: " .. player.guild .. "  \n" ..
			"Server: " .. player.server .. "  \n"
		if rank > 0 then
			header = header .. skillName .. " skill " .. rank .. ", " .. recipeCount .. " total recipes" .. "  \n"
		end
		header = header .. "---------------------\n"
	end

	return header
end

-- Prints available slash commands to the chat window.
local function printHelp()
	print(
	"\124cff00FF00tsexport:\124r \124cff00FF00S\124rimple \124cff00FF00T\124rradeskill \124cff00FF00E\124rxporter - Help")
	print("\124cff00FF00tsexport:\124r Type '/tsexport help' to show this message")
	print("\124cff00FF00tsexport:\124r Open a tradeskill window, then type one of the following commands")
	print("\124cff00FF00tsexport:\124r By default, only recipes for the current expansion are exported")
	print("\124cff00FF00tsexport:\124r Append '\124cff00FF00all\124r' to include recipes from all expansions")
	print("\124cff00FF00tsexport:\124r '/tsexport' or '/tsexport all' - plain text list")
	print("\124cff00FF00tsexport:\124r '/tsexport csv' or '/tsexport csv all' - Comma Separated Value list")
	print("\124cff00FF00tsexport:\124r '/tsexport markdown' or '/tsexport markdown all' - Markdown list")
end

-- Returns the Wowhead query string for a tradeskill entry, or nil if it cannot be resolved.
local function getItemLink(index)
	local itemLink, itemId

	itemLink = GetTradeSkillItemLink(index)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then
			return "item=" .. tonumber(itemId)
		end
	end

	itemLink = GetTradeSkillRecipeLink(index)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then
			return "spell=" .. tonumber(itemId)
		else
			print("|cffFF0000[TSE]: Unable to process entry " .. index)
			local craftedLink = GetTradeSkillItemLink(index)
			local spellLink = GetTradeSkillRecipeLink(index)
			if craftedLink then print(craftedLink:gsub('\124', '\124\124')) end
			if spellLink then print(spellLink:gsub('\124', '\124\124')) end
			return nil
		end
	end

	return nil
end

-- Builds and opens the export window for the given format and scope.
local function runExport(exportType, exportAll)
	local skillName, skillRank = GetTradeSkillLine()
	if skillRank == 0 then
		print("\124cffFF0000Error:\124r Must open a tradeskill window. Type /tsexport help for more information.")
		return
	end

	if (exportType == "csv" or exportType == "markdown") and not tse.wowheadBase then
		print("\124cffFF0000Error:\124r CSV and Markdown exports are not supported on this version of WoW.")
		return
	end

	local recipeText = ""
	local recipeCount = 0
	for i = 1, GetNumTradeSkills() do
		local name, entryType = GetTradeSkillInfo(i)
		if name and entryType ~= "header" then
			if exportAll or isCurrentExpansionRecipe(i) then
				local itemLink = getItemLink(i)
				if itemLink then
					recipeText = recipeText .. buildRecipeEntry(name, itemLink, exportType)
				end
				recipeCount = recipeCount + 1
			end
		end
	end

	openExportWindow(skillName, skillRank, recipeText, recipeCount, exportType)
end

-- Creates and shows the export options popup.
createExportOptionsFrame = function()
	local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(230, 155)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("DIALOG")
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

	frame.title = frame:CreateFontString(nil, "OVERLAY")
	frame.title:SetFontObject("GameFontHighlight")
	frame.title:SetPoint("LEFT", frame.TitleBg, 5, 0)
	frame.title:SetText("Export Recipes")

	-- Format label
	local formatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	formatLabel:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 10, -12)
	formatLabel:SetText("Format:")

	-- Format toggle buttons — clicking one selects it and locks it pushed.
	local formats = {
		{ label = "Text",     value = "text" },
		{ label = "CSV",      value = "csv" },
		{ label = "Markdown", value = "markdown" },
	}

	frame.formatButtons = {}

	local function updateFormatButtons()
		for _, btn in ipairs(frame.formatButtons) do
			btn:SetButtonState(btn.value == selectedExportFormat and "PUSHED" or "NORMAL",
				btn.value == selectedExportFormat)
		end
	end

	for i, fmt in ipairs(formats) do
		local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		btn:SetSize(65, 22)
		btn:SetText(fmt.label)
		btn.value = fmt.value

		if i == 1 then
			btn:SetPoint("TOPLEFT", formatLabel, "BOTTOMLEFT", -2, -6)
		else
			btn:SetPoint("LEFT", frame.formatButtons[i - 1], "RIGHT", 4, 0)
		end

		if (fmt.value == "csv" or fmt.value == "markdown") and not tse.wowheadBase then
			btn:Disable()
		else
			btn:SetScript("OnClick", function()
				selectedExportFormat = btn.value
				updateFormatButtons()
			end)
		end

		frame.formatButtons[i] = btn
	end

	-- "Include all expansions" checkbox — hidden on Vanilla where all recipes are always included.
	local checkbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	checkbox:SetPoint("TOPLEFT", frame.formatButtons[1], "BOTTOMLEFT", 2, -8)
	checkbox:SetChecked(selectedExportAll)
	checkbox.text:SetText("Include all expansions")
	checkbox:SetScript("OnClick", function()
		selectedExportAll = checkbox:GetChecked()
	end)
	frame.allCheckbox = checkbox

	if not tse.expansionItemIdFloor then
		checkbox:Hide()
	end

	-- Export button
	local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	exportBtn:SetSize(90, 24)
	exportBtn:SetText("Export")
	exportBtn:SetPoint("BOTTOM", frame.InsetBg, "BOTTOM", 0, 8)
	exportBtn:SetScript("OnClick", function()
		frame:Hide()
		runExport(selectedExportFormat, selectedExportAll)
	end)

	updateFormatButtons()
	exportOptionsFrame = frame
end

-- Attaches the TSE button to TradeSkillFrame's title bar. Safe to call multiple times — creates once.
local function attachTradeSkillButton()
	if tse.tradeSkillButton then return end

	local button = CreateFrame("Button", nil, TradeSkillFrame, "UIPanelButtonTemplate")
	button:SetSize(72, 18)
	button:SetText("TSExport")
	-- Anchor to the right edge of the portrait so the button sits in the title bar without overlapping it.
	button:SetPoint("LEFT", TradeSkillFramePortrait, "RIGHT", 9, 12)
	button:SetScript("OnClick", function()
		if not exportOptionsFrame then
			createExportOptionsFrame()
		end
		-- Sync checkbox to current session state when re-opening.
		if exportOptionsFrame.allCheckbox then
			exportOptionsFrame.allCheckbox:SetChecked(selectedExportAll)
		end
		exportOptionsFrame:Show()
	end)

	tse.tradeSkillButton = button
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		local version = GetAddOnMetadata(addonName, "Version") or "unknown"
		print("\124cff00FF00SimpleTradeSkillExporter v" ..
		version .. "\124r loaded. Type \124cff00FF00/tsexport help\124r for usage.")
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "TRADE_SKILL_SHOW" then
		attachTradeSkillButton()
	end
end)

SLASH_SIMPLETRADESKILLEXPORTER1 = "/tsexport"
SlashCmdList["SIMPLETRADESKILLEXPORTER"] = function(msg)
	if msg == "help" then
		printHelp()
		return
	end

	local exportType, exportAll = parseCommand(msg)
	runExport(exportType, exportAll)
end

openExportWindow = function(skillName, rank, recipeText, recipeCount, exportType)
	if not exportWindow then
		createExportWindow()
	end

	local player = getPlayerInfo()

	if rank > 0 then
		exportWindow.title:SetText(skillName .. " skill " .. rank .. " - " .. recipeCount .. " recipes")
	end

	local exportText = buildHeader(player, skillName, rank, recipeCount, exportType) .. recipeText

	exportWindow.editBox:SetText(exportText)
	exportWindow.editBox:HighlightText()
	exportWindow:Show()
end

createExportWindow = function()
	local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(640, 480)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("HIGH")
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

	frame.title = frame:CreateFontString(nil, "OVERLAY")
	frame.title:SetFontObject("GameFontHighlight")
	frame.title:SetPoint("LEFT", frame.TitleBg, 5, 0)

	-- Scroll frame leaves 30px at the bottom for the button row.
	frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	frame.scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 4, -8)
	frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -3, 30)
	frame.scrollFrame.ScrollBar:SetPoint("TOPLEFT", frame.scrollFrame, "TOPRIGHT", -20, -22)
	frame.scrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", frame.scrollFrame, "BOTTOMRIGHT", -15, 22)

	frame.editBox = CreateFrame("EditBox", nil, frame.scrollFrame)
	frame.editBox:SetPoint("TOPLEFT", frame.scrollFrame, 5, -5)
	frame.editBox:SetFontObject(ChatFontNormal)
	frame.editBox:SetWidth(780)
	frame.editBox:SetAutoFocus(true)
	frame.editBox:SetMultiLine(true)
	frame.editBox:SetMaxLetters(99999)
	frame.editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
	frame.scrollFrame:SetScrollChild(frame.editBox)

	local function hideTooltip() GameTooltip:Hide() end

	-- "Select All" button — re-focuses and re-highlights if the user clicked elsewhere.
	local selectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	selectAllBtn:SetSize(100, 22)
	selectAllBtn:SetText("Select All")
	selectAllBtn:SetPoint("BOTTOMLEFT", frame.InsetBg, "BOTTOMLEFT", 4, 4)
	selectAllBtn:SetScript("OnClick", function()
		frame.editBox:SetFocus()
		frame.editBox:HighlightText()
	end)
	selectAllBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Select all text, then press Ctrl+C to copy.", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	selectAllBtn:SetScript("OnLeave", hideTooltip)

	-- "Close" button
	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	closeBtn:SetSize(80, 22)
	closeBtn:SetText("Close")
	closeBtn:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -4, 4)
	closeBtn:SetScript("OnClick", function() frame:Hide() end)

	exportWindow = frame
end
