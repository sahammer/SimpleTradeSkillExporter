-- SimpleWowExportersLib.lua
-- Author: Hamma
-- Shared export window UI and row/header renderer for Simple*Exporter addons.
-- Loaded by each addon's TOC before the addon's own Lua file.
-- Attached to the addon namespace (ns.SWE) — no globals written.

local _, ns = ...
ns.SWE = {}
local SWE = ns.SWE

-- SWE.RenderRow(format, values) -> string
-- format: "text" | "csv" | "markdown" | "md-table"
-- values: array of strings or {label=string, url=string} tables
-- For "markdown": only values[1] is used (list format).
-- For "text": values are joined with tab.
-- For "csv": values are quoted; {label,url} entries become =HYPERLINK(...).
-- For "md-table": values are pipe-separated; {label,url} entries become [label](url).
function SWE.RenderRow(format, values)
    if format == "csv" then
        local parts = {}
        for _, v in ipairs(values) do
            local label = type(v) == "table" and v.label or v
            local url   = type(v) == "table" and v.url   or nil
            if url then
                table.insert(parts, '=HYPERLINK("' .. url .. '","' .. label .. '")')
            else
                table.insert(parts, '"' .. tostring(label):gsub('"', '""') .. '"')
            end
        end
        return table.concat(parts, ",") .. "\n"
    elseif format == "markdown" then
        local v     = values[1]
        local label = type(v) == "table" and v.label or tostring(v)
        local url   = type(v) == "table" and v.url   or nil
        if url then
            return "- [" .. label .. "](" .. url .. ")\n"
        else
            return "- " .. label .. "\n"
        end
    elseif format == "md-table" then
        local parts = {}
        for _, v in ipairs(values) do
            local label = type(v) == "table" and v.label or tostring(v)
            local url   = type(v) == "table" and v.url   or nil
            if url then
                table.insert(parts, "[" .. label .. "](" .. url .. ")")
            else
                table.insert(parts, label)
            end
        end
        return "| " .. table.concat(parts, " | ") .. " |\n"
    else -- text
        local parts = {}
        for _, v in ipairs(values) do
            table.insert(parts, type(v) == "table" and v.label or tostring(v))
        end
        return table.concat(parts, "\t") .. "\n"
    end
end

-- SWE.RenderHeader(format, columns) -> string
-- Renders a header row + separator for "md-table", a quoted row for "csv".
-- Returns "" for all other formats.
-- columns: array of strings (column names)
function SWE.RenderHeader(format, columns)
    if format == "md-table" then
        local separators = {}
        for _ in ipairs(columns) do
            table.insert(separators, "---")
        end
        return "| " .. table.concat(columns, " | ") .. " |\n" ..
               "| " .. table.concat(separators, " | ") .. " |\n"
    elseif format == "csv" then
        local parts = {}
        for _, col in ipairs(columns) do
            table.insert(parts, '"' .. col .. '"')
        end
        return table.concat(parts, ",") .. "\n"
    else
        return ""
    end
end

-- SWE.CreateExportWindow(config) -> frame
--
-- config: {
--   buttons  = { {label=string, value=string, disabled=bool}, ... },
--   defaultFormat = string,           -- initial active button value
--   hasScope = bool,                  -- show "All expansions" checkbox
--   onRefresh = function(format, scope) -> text, title
-- }
--
-- Returns a frame. Call frame:Open(format, scope) to set state and show.
function SWE.CreateExportWindow(config)
    local selectedFormat = config.defaultFormat or "text"
    local selectedScope  = false

    local frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(640, 480)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(400, 300)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, 5, 0)

    -- Format toggle buttons
    frame.formatButtons = {}
    for i, btnCfg in ipairs(config.buttons) do
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(72, 22)
        btn:SetText(btnCfg.label)
        btn.value = btnCfg.value

        if i == 1 then
            btn:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 4, -4)
        else
            btn:SetPoint("LEFT", frame.formatButtons[i - 1], "RIGHT", 4, 0)
        end

        if btnCfg.disabled then
            btn:Disable()
        else
            btn:SetScript("OnClick", function()
                selectedFormat = btn.value
                frame.updateControls()
                frame.refresh()
            end)
        end

        frame.formatButtons[i] = btn
    end

    -- Optional "All expansions" scope checkbox
    if config.hasScope then
        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetPoint("LEFT", frame.formatButtons[#frame.formatButtons], "RIGHT", 10, 0)
        cb:SetChecked(false)
        cb.text:SetText("All expansions")
        cb:SetScript("OnClick", function()
            selectedScope = cb:GetChecked()
            frame.refresh()
        end)
        frame.scopeCheckbox = cb
    end

    -- Scroll frame
    frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT",     frame.InsetBg, "TOPLEFT",     4,  -34)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -3,   30)
    frame.scrollFrame.ScrollBar:SetPoint("TOPLEFT",     frame.scrollFrame, "TOPRIGHT",    -20, -22)
    frame.scrollFrame.ScrollBar:SetPoint("BOTTOMRIGHT", frame.scrollFrame, "BOTTOMRIGHT", -15,  22)

    -- Edit box
    frame.editBox = CreateFrame("EditBox", nil, frame.scrollFrame)
    frame.editBox:SetPoint("TOPLEFT", frame.scrollFrame, 5, -5)
    frame.editBox:SetFontObject(ChatFontNormal)
    frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    frame.editBox:SetAutoFocus(true)
    frame.editBox:SetMultiLine(true)
    frame.editBox:SetMaxLetters(99999)
    frame.editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    frame.scrollFrame:SetScrollChild(frame.editBox)

    -- Resize handle anchored to bottom-right corner
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizeButton:SetScript("OnMouseUp",   function() frame:StopMovingOrSizing() end)

    -- Keep edit box width in sync with scroll frame as the window resizes
    frame:SetScript("OnSizeChanged", function()
        frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    end)

    local function hideTooltip() GameTooltip:Hide() end

    -- Select All button
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

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetText("Close")
    closeBtn:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -4, 4)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Syncs button pushed state and text colour to selectedFormat.
    -- Selected: white (1,1,1). Unselected: WoW gold (1,0.82,0).
    frame.updateControls = function()
        for _, btn in ipairs(frame.formatButtons) do
            local selected = btn.value == selectedFormat
            btn:SetButtonState(selected and "PUSHED" or "NORMAL", selected)
            btn:GetFontString():SetTextColor(
                selected and 1 or 1,
                selected and 1 or 0.82,
                selected and 1 or 0
            )
        end
        if frame.scopeCheckbox then
            frame.scopeCheckbox:SetChecked(selectedScope)
        end
    end

    -- Calls config.onRefresh and updates the edit box and title.
    frame.refresh = function()
        local text, title = config.onRefresh(selectedFormat, selectedScope)
        if title then frame.title:SetText(title) end
        frame.editBox:SetText(text or "")
        frame.editBox:HighlightText()
    end

    frame:SetScript("OnShow", function() frame.updateControls() end)

    -- Public: set format + scope, then show.
    function frame:Open(format, scope)
        selectedFormat = format or selectedFormat
        selectedScope  = scope  or false
        frame.updateControls()
        frame.refresh()
        frame:Show()
    end

    return frame
end
