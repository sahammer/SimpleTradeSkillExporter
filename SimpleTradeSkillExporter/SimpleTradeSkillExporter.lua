SLASH_SIMPLETRADESKILLEXPORTER1 = "/tsexport"
SlashCmdList["SIMPLETRADESKILLEXPORTER"] = function(msg)
	if msg == "help" then 
		print("\124cff00FF00tsexport:\124r \124cff00FF00S\124rimple \124cff00FF00T\124rradeskill \124cff00FF00E\124rxporter - Help")
		print("\124cff00FF00tsexport:\124r Type '/tsexport help' to show this message")
		print("\124cff00FF00tsexport:\124r Open a tradeskill window then type one of the following commands")
		print("\124cff00FF00tsexport:\124r Type '/tsexport' to export a simple text list")
		print("\124cff00FF00tsexport:\124r Type '/tsexport csv' to export a Comma Separated Value formatted list")
		print("\124cff00FF00tsexport:\124r Type '/tsexport markdown' to export a Markdown formatted list")
	else
		local tsName, tsRank, _ = GetTradeSkillLine()
		if(tsRank == 0 and tsRank == 0) then
			print("\124cffFF0000Error:\124r Must open a tradeskill window. Type /tsexport help for more information.")
		else
			local text = ''
			local recipeCount = 0
			for i = 1,GetNumTradeSkills() do
				local name, type, _, _, _, _ = GetTradeSkillInfo(i)		
				if (name and type ~= "header") then
					local itemLink = getItemLink(i)
					if itemLink then
					    if msg == "csv" then
							text = text .. '=HYPERLINK("https://wowhead.com/cata/' .. itemLink .. '";"' .. name .. '")\n'
						elseif msg == "markdown" then
							text = text .. "- " .. "[" .. name .. "]" .. "(" .. "https://wowhead.com/cata/" .. itemLink .. ")" .. '\n'							
						else
							text = text .. name .. "\n" 
						end
					end
					recipeCount = recipeCount + 1
				end
			end
			openSimpleTradeSkillExporterWindow(tsName, tsRank, text, recipeCount, msg)
		end 
	end
end

function openSimpleTradeSkillExporterWindow(tradeskillName, rank, text, recipeCount, exportType) 
	if not SimpleTradeSkillExporterWindow then
		createSimpleTradeSkillExporterWindow()
	end 
	local playerName, realm = UnitName("player")
	local playerRace = UnitRace("player")
	local playerClass = UnitClass("player")
	local playerLevel = UnitLevel("player")
	local guildName, guildRankName, guildRankIndex = GetGuildInfo("player")
	local gameVersion = GetBuildInfo();
	local serverName = GetRealmName();
	if(guildName == nil) then
		guildName='-'
	end
	local editText = 
		"Player: " .. playerName .. "," .. " Level " .. playerLevel .. " " .. playerRace .. " " .. playerClass .. "\n" ..
		"Guild: " .. guildName .. "\n" ..
		"Server: " .. serverName .. "\n"
	if(rank > 0) then
		SimpleTradeSkillExporterWindow.title:SetText(tradeskillName .. " skill " .. rank .. " - " .. recipeCount .. " recipes - Press CTRL-C to copy.")
		editText = editText .. tradeskillName ..  " skill " .. rank .. ", " .. recipeCount .. " total recipes" .. "\n"
	end
	editText = editText .. "---------------------" .. "\n" .. text
	if exportType then
		if exportType == "markdown" then
			editText = 
				"# Player: " .. playerName .. "," .. " Level " .. playerLevel .. " " .. playerRace .. " " .. playerClass .. "\n" ..
				"## Guild: " .. guildName .. "\n" ..
				"## Server: " .. serverName .. "\n"
			if(rank > 0) then
				editText = editText .. "### " .. tradeskillName .. " skill " .. rank .. ", " .. recipeCount .. " total recipes" .. "\n"
			end
			editText = editText .. "---------------------" .. "\n" .. text
		elseif exportType == "csv" then
			editText = "Recipe" .. "\n" .. text
		end
	end
	SimpleTradeSkillExporterWindow.editBox:SetText(editText)
	SimpleTradeSkillExporterWindow.editBox:HighlightText()
	SimpleTradeSkillExporterWindow:Show()
end
-- Look to switch to UIPanelDialogTemplate
function createSimpleTradeSkillExporterWindow()
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
	frame.scrollFrame = CreateFrame("ScrollFrame", "SimpleTradeSkillExporterScrollFrame", SimpleTradeSkillExporterWindow, "UIPanelScrollFrameTemplate")
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

function getItemLink(index)
	local itemLink, itemID, name
    itemLink = GetTradeSkillItemLink(index)
	if itemLink then 
		itemID = itemLink:match("item:(%d+)")
		if (not itemID) then 
			itemID = itemLink:match("enchant:(%d+)") 
		end
		if itemID then 
			return "item=" .. tonumber(itemID)
		end
	end
	itemLink = GetTradeSkillRecipeLink(index)
	if itemLink then 
		itemID = itemLink:match("item:(%d+)")
		if (not itemID) then 
			itemID = itemLink:match("enchant:(%d+)") 
		end
		if itemID then 
			return "spell=" .. tonumber(itemID)
		else
			print("|cffFF0000[TSE]: Unable to process entry " .. index)
			itemLink = GetTradeSkillItemLink(index)
			print(itemLink)
			if itemLink then
				print(itemLink:gsub('\124','\124\124'))
			end
			itemLink = GetTradeSkillRecipeLink(index)
			print(itemLink)
			if itemLink then
				print(itemLink:gsub('\124','\124\124'))
			end
			return nil
		end
	end
end
