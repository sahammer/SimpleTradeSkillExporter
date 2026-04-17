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

local openExportWindow
local createExportWindow

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
			"**Player:** " .. player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"**Guild:** " .. player.guild .. "  \n" ..
			"**Server:** " .. player.server .. "  \n"
		if rank > 0 then
			header = header .. "**" .. skillName .. ":** Skill " .. rank .. ", " .. recipeCount .. " total recipes" .. "  \n"
		end
		header = header .. "\n"
	elseif exportType == "csv" then
		header = ""
	else
		header =
			"Player: " .. player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
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
	print("\124cff00FF00tsexport:\124r \124cff00FF00S\124rimple \124cff00FF00T\124rradeskill \124cff00FF00E\124rxporter - Help")
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
			local itemLinkRaw = GetTradeSkillItemLink(index)
			local recipeLinkRaw = GetTradeSkillRecipeLink(index)
			print(itemLinkRaw)
			if itemLinkRaw then print(itemLinkRaw:gsub('\124', '\124\124')) end
			print(recipeLinkRaw)
			if recipeLinkRaw then print(recipeLinkRaw:gsub('\124', '\124\124')) end
			return nil
		end
	end
end

local loadedFrame = CreateFrame("Frame")
loadedFrame:RegisterEvent("ADDON_LOADED")
loadedFrame:SetScript("OnEvent", function(self, event, loadedAddon)
	if loadedAddon == addonName then
		local version = GetAddOnMetadata(addonName, "Version") or "unknown"
		print("\124cff00FF00SimpleTradeSkillExporter v" .. version .. "\124r loaded. Type \124cff00FF00/tsexport help\124r for usage.")
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

SLASH_SIMPLETRADESKILLEXPORTER1 = "/tsexport"
SlashCmdList["SIMPLETRADESKILLEXPORTER"] = function(msg)
	if msg == "help" then
		printHelp()
		return
	end

	local skillName, skillRank, _ = GetTradeSkillLine()
	if skillRank == 0 then
		print("\124cffFF0000Error:\124r Must open a tradeskill window. Type /tsexport help for more information.")
		return
	end

	local exportType, exportAll = parseCommand(msg)

	if (exportType == "csv" or exportType == "markdown") and not tse.wowheadBase then
		print("\124cffFF0000Error:\124r CSV and Markdown exports are not supported on this version of WoW.")
		return
	end

	local recipeText = ''
	local recipeCount = 0
	for i = 1, GetNumTradeSkills() do
		local name, entryType, _, _, _, _ = GetTradeSkillInfo(i)
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

openExportWindow = function(skillName, rank, recipeText, recipeCount, exportType)
	if not SimpleTradeSkillExporterWindow then
		createExportWindow()
	end

	local player = getPlayerInfo()

	if rank > 0 then
		SimpleTradeSkillExporterWindow.title:SetText(skillName ..
			" skill " .. rank .. " - " .. recipeCount .. " recipes - Press CTRL-C to copy.")
	end

	local exportText = buildHeader(player, skillName, rank, recipeCount, exportType) .. recipeText

	SimpleTradeSkillExporterWindow.editBox:SetText(exportText)
	SimpleTradeSkillExporterWindow.editBox:HighlightText()
	SimpleTradeSkillExporterWindow:Show()
end

-- Look to switch to UIPanelDialogTemplate
createExportWindow = function()
	local frame = CreateFrame("Frame", "SimpleTradeSkillExporterWindow", UIParent, "BasicFrameTemplateWithInset")
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
	frame.scrollFrame = CreateFrame("ScrollFrame", "SimpleTradeSkillExporterScrollFrame", SimpleTradeSkillExporterWindow,
		"UIPanelScrollFrameTemplate")
	frame.scrollFrame:SetPoint("TOPLEFT", SimpleTradeSkillExporterWindow.InsetBg, "TOPLEFT", 4, -8)
	frame.scrollFrame:SetPoint("BOTTOMRIGHT", SimpleTradeSkillExporterWindow.InsetBg, "BOTTOMRIGHT", -3, 4)
	frame.scrollFrame.ScrollBar:SetPoint("TOPLEFT", frame.scrollFrame, "TOPRIGHT", -20, -22)
	frame.scrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", frame.scrollFrame, "BOTTOMRIGHT", -15, 22)
	frame.editBox = CreateFrame("EditBox", "SimpleTradeSkillExporterEditBox", SimpleTradeSkillExporterScrollFrame)
	frame.editBox:SetPoint("TOPLEFT", frame.scrollFrame, 5, -5)
	frame.editBox:SetFontObject(ChatFontNormal)
	frame.editBox:SetWidth(780)
	frame.editBox:SetAutoFocus(true)
	frame.editBox:SetMultiLine(true)
	frame.editBox:SetMaxLetters(99999)
	frame.editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
	frame.scrollFrame:SetScrollChild(frame.editBox)
end
