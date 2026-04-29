-- SimpleTradeSkillExporter
-- Author: Hamma
-- Description: Exports trade skill recipes to plain text, CSV, or Markdown format.
--              Supports all classic WoW flavors (Vanilla, TBC, Wrath, Cata, MoP).
--              Use /tsexport or the Export button on the tradeskill window.

local addonName, tse = ...
local SWE = tse.SWE -- loaded by SimpleWowExportersLib.lua via TOC

-- WOW_PROJECT_* constants are only defined on their respective clients.
-- Use numeric literals as table keys to avoid nil key errors on other clients.
-- Values sourced from https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID
local PROJECT_MAINLINE   = 1
local PROJECT_CLASSIC    = 2
local PROJECT_TBC        = 5
local PROJECT_WRATH      = 11
local PROJECT_CATA       = 14
local PROJECT_MISTS      = 19

local isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local wowheadUrls = {
	[PROJECT_MAINLINE] = "https://www.wowhead.com/",
	[PROJECT_MISTS]    = "https://wowhead.com/mop-classic/",
	[PROJECT_CATA]     = "https://wowhead.com/cata/",
	[PROJECT_WRATH]    = "https://wowhead.com/wotlk/",
	[PROJECT_TBC]      = "https://wowhead.com/tbc/",
	[PROJECT_CLASSIC]  = "https://wowhead.com/classic/",
}
tse.wowheadBase = wowheadUrls[WOW_PROJECT_ID]

local expansionItemIdFloors = {
	[PROJECT_MAINLINE] = 210000, -- The War Within
	[PROJECT_MISTS]    = 71000,
	[PROJECT_CATA]     = 52000,
	[PROJECT_WRATH]    = 35000,
	[PROJECT_TBC]      = 24000,
	[PROJECT_CLASSIC]  = nil,
}
tse.expansionItemIdFloor = expansionItemIdFloors[WOW_PROJECT_ID]

local exportWindow

local validFormats = { text = true, csv = true, markdown = true }

-- Examples: "csv" -> ("csv", true), "csv current" -> ("csv", false), "" -> ("text", true)
-- All expansions is the default. Append "current" to limit to current expansion only.
-- Unknown format values are normalised to "text" with a warning printed to chat.
local function parseCommand(msg)
	local parts = {}
	for part in msg:gmatch("%S+") do table.insert(parts, part) end

	local exportAll = parts[#parts] ~= "current"
	if not exportAll then table.remove(parts, #parts) end

	local format = parts[1] or "text"
	if not validFormats[format] then
		print("|cffFF0000[TSE]:|r Unknown format '" .. format .. "', defaulting to text.")
		format = "text"
	end

	return format, exportAll
end

local function getCraftedOutputId(indexOrRecipeID)
	local itemLink
	if isRetail then
		itemLink = C_TradeSkillUI.GetRecipeItemLink(indexOrRecipeID)
	else
		itemLink = GetTradeSkillItemLink(indexOrRecipeID)
	end
	if not itemLink then return nil end
	local id = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
	return id and tonumber(id) or nil
end

local function isCurrentExpansionRecipe(indexOrRecipeID)
	if not tse.expansionItemIdFloor then return true end
	local outputId = getCraftedOutputId(indexOrRecipeID)
	if outputId == nil then return true end
	return outputId >= tse.expansionItemIdFloor
end

local function getPlayerInfo()
	local name   = UnitName("player")
	local race   = UnitRace("player")
	local class  = UnitClass("player")
	local level  = UnitLevel("player")
	local guild  = GetGuildInfo("player") or "-"
	local server = GetRealmName()
	return { name = name, race = race, class = class, level = level, guild = guild, server = server }
end

local function buildHeader(player, skillName, rank, recipeCount, exportType)
	if exportType == "markdown" then
		local h =
			"**Player:** " ..
			player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"**Guild:** " .. player.guild .. "  \n" ..
			"**Server:** " .. player.server .. "  \n"
		if rank > 0 then
			h = h .. "**" .. skillName .. ":** Skill " .. rank .. ", " .. recipeCount .. " total recipes  \n"
		end
		return h .. "\n"
	elseif exportType == "csv" then
		return ""
	else
		local h =
			"Player: " ..
			player.name .. ", Level " .. player.level .. " " .. player.race .. " " .. player.class .. "  \n" ..
			"Guild: " .. player.guild .. "  \n" ..
			"Server: " .. player.server .. "  \n"
		if rank > 0 then
			h = h .. skillName .. " skill " .. rank .. ", " .. recipeCount .. " total recipes  \n"
		end
		return h .. "---------------------\n"
	end
end

local function printHelp()
	print(
	"\124cff00FF00TSE:\124r \124cff00FF00S\124rimple \124cff00FF00T\124rradeskill \124cff00FF00E\124rxporter - Help")
	print("\124cff00FF00TSE:\124r Type '/tsexport help' to show this message")
	print("\124cff00FF00TSE:\124r Open a tradeskill window, then type one of the following commands")
	print("\124cff00FF00TSE:\124r By default, all expansions are exported")
	print("\124cff00FF00TSE:\124r Append '\124cff00FF00current\124r' to limit to current expansion only")
	print("\124cff00FF00TSE:\124r '/tsexport' or '/tsexport current' - plain text list")
	print("\124cff00FF00TSE:\124r '/tsexport csv' or '/tsexport csv current' - Comma Separated Value list")
	print("\124cff00FF00TSE:\124r '/tsexport markdown' or '/tsexport markdown current' - Markdown list")
end

local function getItemLink(indexOrRecipeID)
	local itemLink, itemId

	if isRetail then
		itemLink = C_TradeSkillUI.GetRecipeItemLink(indexOrRecipeID)
		if itemLink then
			itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
			if itemId then return "item=" .. tonumber(itemId) end
		end
		-- Fall back to the spell link for the recipe itself
		itemLink = C_TradeSkillUI.GetRecipeLink(indexOrRecipeID)
		if itemLink then
			itemId = itemLink:match("spell:(%d+)")
			if itemId then return "spell=" .. tonumber(itemId) end
		end
		return nil
	end

	itemLink = GetTradeSkillItemLink(indexOrRecipeID)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then return "item=" .. tonumber(itemId) end
	end

	itemLink = GetTradeSkillRecipeLink(indexOrRecipeID)
	if itemLink then
		itemId = itemLink:match("item:(%d+)") or itemLink:match("enchant:(%d+)")
		if itemId then
			return "spell=" .. tonumber(itemId)
		else
			print("|cffFF0000[TSE]: Unable to process entry " .. indexOrRecipeID)
			if itemLink then print(itemLink:gsub('\124', '\124\124')) end
			return nil
		end
	end

	return nil
end

local function captureRecipeData()
	if isRetail then
		local profInfo = C_TradeSkillUI.GetChildProfessionInfo()
		if not profInfo or not profInfo.professionID then return false end

		local skillName = profInfo.professionName or "Unknown"
		-- Retail has no single skill rank — pass 0 (buildHeader guards with "if rank > 0")
		local skillRank = 0

		local recipeIDs = C_TradeSkillUI.GetFilteredRecipeIDs()
		if not recipeIDs or #recipeIDs == 0 then return false end

		-- GetFilteredRecipeIDs() returns recipes across ALL expansion skill lines for this
		-- profession. Use IsRecipeInSkillLine to tag which recipes belong to the currently
		-- open expansion (e.g. "War Within Tailoring" vs "Dragonflight Tailoring").
		local childProfessionID = profInfo.professionID
		local recipes = {}
		for _, recipeID in ipairs(recipeIDs) do
			local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
			if info and info.learned and info.name then
				local expInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
				table.insert(recipes, {
					name               = info.name,
					itemLink           = getItemLink(recipeID),
					expansionName      = expInfo and expInfo.expansionName or nil,
					isCurrentExpansion = C_TradeSkillUI.IsRecipeInSkillLine(recipeID, childProfessionID),
				})
			end
		end

		tse.recipeData = {
			skillName = skillName,
			skillRank = skillRank,
			player    = getPlayerInfo(),
			recipes   = recipes,
		}
		return true
	end

	local skillName, skillRank = GetTradeSkillLine()
	if skillRank == 0 then return false end

	local recipes = {}
	for i = 1, GetNumTradeSkills() do
		local name, entryType = GetTradeSkillInfo(i)
		if name and entryType ~= "header" then
			table.insert(recipes, {
				name               = name,
				itemLink           = getItemLink(i),
				isCurrentExpansion = isCurrentExpansionRecipe(i),
			})
		end
	end

	tse.recipeData = {
		skillName = skillName,
		skillRank = skillRank,
		player    = getPlayerInfo(),
		recipes   = recipes,
	}

	return true
end

-- onRefresh callback passed to SWE.CreateExportWindow.
-- Builds the full export text from tse.recipeData for the given format and scope.
local function buildExportText(format, scope)
	tse.lastFormat = format
	tse.lastScope  = scope
	if not tse.recipeData then return "", "" end
	local data = tse.recipeData

	-- Collect recipes that pass the scope filter
	local filtered = {}
	for _, recipe in ipairs(data.recipes) do
		if (scope or recipe.isCurrentExpansion) and recipe.itemLink then
			table.insert(filtered, recipe)
		end
	end

	local lines = {}
	local count = #filtered

	-- On retail, recipes carry expansionName — group by expansion with section headers.
	-- On classic, recipes have no expansionName — emit a flat list as before.
	local hasExpansionGroups = isRetail and filtered[1] and filtered[1].expansionName ~= nil

	if hasExpansionGroups then
		-- CSV: emit column header with Expansion column first
		if format == "csv" then
			lines[#lines + 1] = SWE.RenderHeader(format, { "Expansion", "Recipe" })
		end

		local currentExpansion = nil
		for _, recipe in ipairs(filtered) do
			local expName = recipe.expansionName or "Unknown"
			if expName ~= currentExpansion then
				currentExpansion = expName
				if format == "markdown" then
					lines[#lines + 1] = "\n## " .. expName .. "\n\n"
				elseif format == "text" then
					lines[#lines + 1] = "\n--- " .. expName .. " ---\n"
				end
				-- csv: no section header — expansion is a column value instead
			end
			local url = tse.wowheadBase and (tse.wowheadBase .. recipe.itemLink) or nil
			if format == "csv" then
				lines[#lines + 1] = SWE.RenderRow(format, { expName, { label = recipe.name, url = url } })
			else
				lines[#lines + 1] = SWE.RenderRow(format, { { label = recipe.name, url = url } })
			end
		end
	else
		for _, recipe in ipairs(filtered) do
			local url = tse.wowheadBase and (tse.wowheadBase .. recipe.itemLink) or nil
			lines[#lines + 1] = SWE.RenderRow(format, { { label = recipe.name, url = url } })
		end
	end

	local header = buildHeader(data.player, data.skillName, data.skillRank, count, format)
	local title  = data.skillName .. " skill " .. data.skillRank .. " - " .. count .. " recipes"
	return header .. table.concat(lines), title
end

local function runExport(exportType, exportAll)
	if (exportType == "csv" or exportType == "markdown") and not tse.wowheadBase then
		print("\124cffFF0000Error:\124r CSV and Markdown exports are not supported on this version of WoW.")
		return
	end

	if not captureRecipeData() then
		print("\124cffFF0000Error:\124r Must open a tradeskill window. Type /tsexport help for more information.")
		return
	end

	if not exportWindow then
		exportWindow = SWE.CreateExportWindow({
			buttons       = {
				{ label = "Text",     value = "text" },
				{ label = "CSV",      value = "csv",      disabled = not tse.wowheadBase },
				{ label = "Markdown", value = "markdown", disabled = not tse.wowheadBase },
			},
			defaultFormat = "text",
			hasScope      = tse.expansionItemIdFloor ~= nil or isRetail,
			onRefresh     = buildExportText,
		})
	end

	tse.lastFormat = exportType
	tse.lastScope  = exportAll
	exportWindow:Open(exportType, exportAll)
end

local function attachTradeSkillButton()
	if tse.tradeSkillButton then return end

	if isRetail then
		if not ProfessionsFrame then return end
		local button = CreateFrame("Button", nil, ProfessionsFrame, "UIPanelButtonTemplate")
		button:SetSize(72, 18)
		button:SetText("TSExport")
		button:SetPoint("RIGHT", ProfessionsFrame.MaximizeMinimize, "LEFT", -2, 0)
		button:SetScript("OnClick", function()
			runExport(tse.lastFormat or "text", tse.lastScope ~= false)
		end)
		tse.tradeSkillButton = button
		return
	end

	local button = CreateFrame("Button", nil, TradeSkillFrame, "UIPanelButtonTemplate")
	button:SetSize(72, 18)
	button:SetText("TSExport")
	button:SetPoint("LEFT", TradeSkillFramePortrait, "RIGHT", 9, 12)
	button:SetScript("OnClick", function()
		runExport(tse.lastFormat or "text", tse.lastScope ~= false)
	end)

	tse.tradeSkillButton = button
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		if not tse.SWE then
			print(
			"\124cffFF0000[TSE] Error:\124r SimpleWowExportersLib failed to load. Ensure SimpleWowExportersLib.lua is in the addon folder.")
			self:UnregisterEvent("ADDON_LOADED")
			self:UnregisterEvent("TRADE_SKILL_SHOW")
			return
		end
		local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
		local version = getMetadata and getMetadata(addonName, "Version")
		SWE.RegisterAddon("SimpleTradeSkillExporter", version, "/tsexport help")
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
