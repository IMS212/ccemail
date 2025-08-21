BASALT = require("basalt")

local G = _G or {}
local EMAIL_COUNT


local function setRedstone(side, value)
    local g = _G or {}
    local r = rawget(g, "rs") or rawget(g, "redstone")
    if r and r.setOutput then
        redstone.setAnalogOutput(side, value)
    end
end

MAIN_SCREEN = BASALT.getMainFrame()

local USERNAME = ""
if winter_email and winter_email.getUsername then
    local ok, res = pcall(winter_email.getUsername)
    local val = (ok and res) or ""
    if val == "<unknown>" then val = "" end
    USERNAME = val
end

local CURRENT_SCREEN = nil
local INBOX_REFRESH = nil

local function countUnreadEmails()
    local total = 0
    if winter_email and winter_email.getEmails then
        local ok, res = pcall(function() return winter_email.getEmails() end)
        total = (ok and tonumber(res)) or 0
    end
    local unread = 0
    for i = 0, total - 1 do
        local em = (winter_email and winter_email.getEmail and winter_email.getEmail(i)) or nil
        if em and em.hasRead and (not em:hasRead()) then
            unread = unread + 1
        end
    end
    return unread
end

local THEMES = {
    light = {
        bg = colors.lightGray,
        panel = colors.white,
        panelFg = colors.black,
        header = colors.blue,
        headerFg = colors.white,
        accent = colors.blue,
        inputBg = colors.lightGray,
        inputFg = colors.black,
        success = colors.lime,
        danger = colors.red,
        hint = colors.gray,
    },
    dark = {
        bg = colors.gray,
        panel = colors.black,
        panelFg = colors.white,
        header = colors.blue,
        headerFg = colors.white,
        accent = colors.blue,
        inputBg = colors.gray,
        inputFg = colors.white,
        success = colors.green,
        danger = colors.red,
        hint = colors.lightGray,
    }
}

local CURRENT_THEME_NAME = "light"
local PALETTE = THEMES[CURRENT_THEME_NAME]

local addUser
local mainScreen
local inboxScreen
local viewEmailScreen
local composeScreen

local function go(screenFn, ...)
    if MAIN_SCREEN and MAIN_SCREEN.clear then MAIN_SCREEN:clear() end
    screenFn(...)
end

local function onEmailReceived()
    setRedstone("top", countUnreadEmails())

    local dfpwm = require("cc.audio.dfpwm")
    local speaker = peripheral.find("speaker")

    if speaker ~= nil then
    local decoder = dfpwm.make_decoder()
        for chunk in io.lines("mail.dfpwm", 16 * 1024) do
            local buffer = decoder(chunk)

            while not speaker.playAudio(buffer) do
                os.pullEvent("speaker_audio_empty")
            end
        end
    end

    if CURRENT_SCREEN == "inbox" and INBOX_REFRESH then
        INBOX_REFRESH()
        return
    end
    if EMAIL_COUNT and EMAIL_COUNT.setText then
        EMAIL_COUNT:setText(function()
            local n = countUnreadEmails()
            if n == 0 then
                return "You have no unread emails."
            elseif n == 1 then
                return "You have 1 email."
            else
                return "You have " .. n .. " emails."
            end
        end)
        if EMAIL_COUNT.setForeground then
            local col = (countUnreadEmails() == 0) and PALETTE.success or PALETTE.danger
            EMAIL_COUNT:setForeground(col)
        end
        if MAIN_SCREEN.updateRender then MAIN_SCREEN:updateRender() end
    end
end

if BASALT and BASALT._events then
    BASALT._events["email_received"] = BASALT._events["email_received"] or {}
    table.insert(BASALT._events["email_received"], onEmailReceived)
end


local function formatUnix(ts)
    local n = tonumber(ts)
    if not n then return tostring(ts or "?") end
    if n > 1e12 then n = math.floor(n / 1000) end
    local ok, formatted = pcall(function() return os.date("%Y-%m-%d %H:%M:%S", n) end)
    if ok and formatted then return formatted end
    return tostring(ts)
end

local function setTheme(name)
    if THEMES[name] then
        CURRENT_THEME_NAME = name
        PALETTE = THEMES[name]
    end
end

local function renderRoot()
    if MAIN_SCREEN and MAIN_SCREEN.clear then MAIN_SCREEN:clear() end
    local uname = USERNAME
    if winter_email and winter_email.getUsername then
        local ok, res = pcall(winter_email.getUsername)
        if ok and type(res) == "string" then uname = res end
    end
    if uname == "<unknown>" then uname = "" end
    USERNAME = uname or ""
    if winter_email.hasUsername() then
        mainScreen()
    else
        addUser()
    end
end

local function addHeader(parent, title, onBack)
    local header = parent:addFrame("header"):setSize("{parent.width}", 3):setBackground(PALETTE.header)
    if onBack then
        header:addButton("back")
              :setPosition(1, 1)
              :setSize(7, 3)
              :setText("< Back")
              :setBackground(PALETTE.header)
              :setForeground(PALETTE.headerFg)
              :onClick(function()
            onBack()
        end)
    end

    header:addLabel("title")
          :setPosition(onBack and 10 or 2, 2)
          :setText(title or "Winter Mail")
          :setForeground(PALETTE.headerFg)

    header:addButton("themeToggle")
          :setPosition("{parent.width-12}", 1)
          :setSize(11, 3)
          :setText(CURRENT_THEME_NAME == "light" and "Dark Mode" or "Light Mode")
          :setBackground(PALETTE.header)
          :setForeground(PALETTE.headerFg)
          :onClick(function()
        setTheme(CURRENT_THEME_NAME == "light" and "dark" or "light")
        renderRoot()
    end)
end

addUser = function()
    CURRENT_SCREEN = "setup"; INBOX_REFRESH = nil
    local newScreen = MAIN_SCREEN:addFrame("newScreen"):setSize("{parent.width}", "{parent.height}"):setBackground(PALETTE.bg)
    addHeader(newScreen, "Setup", nil)

    local panel = newScreen:addFrame("setupCard")
                           :setSize(36, 9)
                           :setPosition(1, 4)
                           :setBackground(PALETTE.panel)
                           :setForeground(PALETTE.panelFg)

    panel:addLabel("hint")
         :setPosition(2, 2)
         :setForeground(PALETTE.hint)
         :setText("Use format: user@base_name")

    local input = panel:addTextBox("usernameInput")
                       :setSize(30, 1)
                       :setPosition(3, 4)
                       :setBackground(PALETTE.inputBg)
                       :setForeground(PALETTE.inputFg)

    local errorLbl = panel:addLabel("error")
                          :setPosition(3, 5)
                          :setForeground(PALETTE.danger)
                          :setText("")

    panel:addButton("createUser")
         :setPosition(3, 7)
         :setSize(12, 3)
         :setText("Create")
         :setBackground(PALETTE.accent)
         :setForeground(PALETTE.panelFg)
         :onClick(function()
        local text = input:getText()
        if text == nil or text == "" or not string.find(text, "@") then
            errorLbl:setText("Please enter a valid username.")
            return
        end
        errorLbl:setText("")
        winter_email.setUsername(text)
        USERNAME = text
        renderRoot()
    end)
end

mainScreen = function()
    CURRENT_SCREEN = "home"; INBOX_REFRESH = nil
    local user, domain = "user", ""
    if type(USERNAME) == "string" then
        local u, d = USERNAME:match("(.+)@(.+)")
        user, domain = (u or USERNAME), (d or "")
    end

    MAIN_SCREEN:setBackground(PALETTE.panel)
    addHeader(MAIN_SCREEN, "Home", nil)

    local panel = MAIN_SCREEN:addFrame("homeCard")
                             :setSize("{parent.width-6}", 11)
                             :setPosition(3, 5)
                             :setBackground(PALETTE.panel)
                             :setForeground(PALETTE.panelFg)

    panel:addLabel("welcome"):setPosition(2, 1):setText("Welcome, " .. (user or "user") .. "."):setForeground(PALETTE.panelFg)

    EMAIL_COUNT = panel:addLabel("emailCount"):setPosition(2, 3):setText(function()
        local n = countUnreadEmails()
        if n == 0 then
            return "You have no unread emails."
        elseif n == 1 then
            return "You have 1 email."
        else
            return "You have " .. n .. " emails."
        end
    end):setForeground((countUnreadEmails() == 0) and PALETTE.success or PALETTE.danger)

    panel:addButton("openInbox")
         :setPosition(2, 7)
         :setSize(14, 3)
         :setText("Open Inbox")
         :setBackground(PALETTE.accent)
         :setForeground(PALETTE.panelFg)
         :onClick(function()
        go(inboxScreen)
    end)

    panel:addButton("sendEmail")
         :setPosition(18, 7)
         :setSize(12, 3)
         :setText("Compose")
         :setBackground(PALETTE.accent)
         :setForeground(PALETTE.panelFg)
         :onClick(function()
        go(composeScreen)
    end)
end

inboxScreen = function()

    CURRENT_SCREEN = "inbox"
    MAIN_SCREEN:setBackground(PALETTE.bg)
    addHeader(MAIN_SCREEN, "Inbox", function()
        go(mainScreen)
    end)

    local panel = MAIN_SCREEN:addFrame("inboxPanel")
                             :setSize("{parent.width-4}", "{parent.height-3}")
                             :setPosition(2, 4)
                             :setBackground(PALETTE.panel)
                             :setForeground(PALETTE.panelFg)

    local title = panel:addLabel("title"):setPosition(2, 2):setText("Inbox"):setForeground(PALETTE.panelFg)

    local list = panel:addList("emailList")
                      :setPosition(2, 4)
                      :setSize("{parent.width-6}", "{parent.height-8}")
                      :setBackground(PALETTE.panel)
                      :setForeground(PALETTE.inputFg)

    local vbar = panel:addScrollbar("listScroll")
                      :setPosition("{parent.width-2}", 3)
                      :setSize(1, "{parent.height-5}")
                      :setBackground(PALETTE.panel)
                      :setForeground(PALETTE.panelFg)
    if vbar.attach then
        vbar:attach(list, {
            property = "offset",
            min = 0,
            max = function()
                local items = (list.get and list.get("items")) or {}
                local h = (list.get and list.get("height")) or 0
                return math.max(0, (#items) - h)
            end
        })
    end

    local footer = panel:addFrame("footer")
                        :setPosition(2, "{parent.height-2}")
                        :setSize("{parent.width-4}", 3)
                        :setBackground(PALETTE.panel)
                        :setForeground(PALETTE.panelFg)

    local status = footer:addLabel("status"):setPosition(1, 2):setText("")

    local indexMap = {}
    local function refresh()
        list:clear()
        indexMap = {}
        local n = winter_email.getEmails()
        title:setText("Inbox (" .. tostring(n) .. ")")
        setRedstone("top", 0)
        for i = 0, (n - 1) do
            local em = winter_email.getEmail(i)
            local unread = ""
            if not em:hasRead() then
                unread = "(New!) "
                setRedstone("top", countUnreadEmails())
            end
            local senderName = "?"
            if em.getSender then
                local sid = em:getSender()
                if winter_email.getNameFor then
                    senderName = winter_email.getNameFor(sid) or ("ID " .. tostring(sid))
                else
                    senderName = tostring(sid)
                end
            end
            local subj = (em.getSubject and em:getSubject()) or "(no subject)"
            local line = unread .. senderName .. " - " .. subj
            list:addItem(line)
            indexMap[#indexMap + 1] = i
        end
        status:setText(n == 0 and "No emails." or "")

        local h = (list.get and list.get("height")) or 0
        local maxOffset = math.max(0, n - h)
        if maxOffset <= 0 then
            if vbar.setVisible then vbar:setVisible(false) end
            vbar:setSize(1, 1)
        else
            if vbar.setVisible then vbar:setVisible(true) end
            vbar:setSize(1, h)
        end
    end

    INBOX_REFRESH = refresh

    footer:addButton("open")
          :setPosition(1, 1)
          :setSize(10, 3)
          :setText("Open")
          :setBackground(PALETTE.accent)
          :setForeground(PALETTE.panelFg)
          :onClick(function()
        local selected = list.getSelectedItems and list:getSelectedItems() or nil
        local first = selected and selected[1]
        local selIdx = first and first.index
        if selIdx then
            local emailIdx = indexMap[selIdx]
            if emailIdx then
                local emOpen = winter_email.getEmail(emailIdx)
                emOpen:markRead()
                go(viewEmailScreen, emailIdx)
            end
        end
    end)

    footer:addButton("delete")
          :setPosition(12, 1)
          :setSize(10, 3)
          :setText("Delete")
          :setBackground(PALETTE.danger)
          :setForeground(PALETTE.panelFg)
          :onClick(function()
        local selected = list.getSelectedItems and list:getSelectedItems() or nil
        local first = selected and selected[1]
        local selIdx = first and first.index
        if selIdx then
            local emailIdx = indexMap[selIdx]
            if emailIdx then
                winter_email.deleteEmail(emailIdx)
                refresh()
            end
        end
    end)

    footer:addButton("compose")
          :setPosition("{parent.width-10}", 1)
          :setSize(12, 3)
          :setText("Compose")
          :setBackground(PALETTE.accent)
          :setForeground(PALETTE.panelFg)
          :onClick(function()
        go(composeScreen)
    end)

    list:onSelect(function(idx)
        local emailIdx = indexMap[idx]
        if emailIdx then
            local emOpen = winter_email.getEmail(emailIdx)
            emOpen:markRead()
            go(viewEmailScreen, emailIdx)
        end
    end)

    refresh()
end

-- i spent an hour on this :(
viewEmailScreen = function(emailIndex)
    CURRENT_SCREEN = "view"; INBOX_REFRESH = nil
    MAIN_SCREEN:setBackground(PALETTE.bg)
    addHeader(MAIN_SCREEN, "Email", function()
        go(inboxScreen)
    end)

    local panel = MAIN_SCREEN:addFrame("viewPanel")
                             :setSize("{parent.width-4}", "{parent.height-3}")
                             :setPosition(2, 4)
                             :setBackground(PALETTE.panel)
                             :setForeground(PALETTE.panelFg)

    local em = winter_email.getEmail(emailIndex)
    em:markRead()

    local senderId = em and em.getSender and em:getSender()
    local recipId = em and em.getRecipient and em:getRecipient()
    local sender = winter_email.getNameFor(senderId) or tostring(senderId or "?")
    local recip = winter_email.getNameFor(recipId) or tostring(recipId or "?")
    local subject = (em and em.getSubject and em:getSubject()) or "(no subject)"
    local body = (em and em.getBody and em:getBody()) or ""
    local ts = (em and em.getTimestamp and em:getTimestamp()) or ""

    panel:addLabel("from"):setPosition(2, 2):setText("From: " .. sender):setForeground(PALETTE.panelFg)
    panel:addLabel("to"):setPosition(2, 3):setText("To:   " .. recip):setForeground(PALETTE.panelFg)
    panel:addLabel("when"):setPosition(2, 4):setText("Time: " .. formatUnix(ts)):setForeground(PALETTE.panelFg)
    panel:addLabel("subj"):setPosition(2, 5):setText("Subj: " .. subject):setForeground(PALETTE.panelFg)

    local bodyBox = panel:addTextBox("body")
                         :setPosition(2, 7)
                         :setSize("{parent.width-6}", "{parent.height-8}")
                         :setBackground(PALETTE.inputBg)
                         :setForeground(PALETTE.inputFg)
                         :setText(body)

    local function countLines(text)
        local n = 1
        for _ in string.gmatch(text or "", "\n") do n = n + 1 end
        return n
    end

    local bodyBar = panel:addScrollbar("bodyScroll")
                         :setPosition("{parent.width-2}", 6)
                         :setSize(1, "{parent.height-8}")
                         :setBackground(PALETTE.panel)
                         :setForeground(PALETTE.panelFg)
    if bodyBar.attach then
        bodyBar:attach(bodyBox, {
            property = "scrollY",
            min = 0,
            max = function()
                local h = (bodyBox.get and bodyBox.get("height")) or 0
                local lines = countLines(bodyBox:getText())
                return math.max(0, lines - h + 2)
            end
        })
    end

    panel:addButton("delete")
         :setPosition(2, "{parent.height-3}")
         :setSize(10, 3)
         :setText("Delete")
         :setBackground(PALETTE.danger)
         :setForeground(PALETTE.panelFg)
         :onClick(function()
        winter_email.deleteEmail(emailIndex)
        go(inboxScreen)
    end)

    panel:addButton("reply")
         :setPosition(13, "{parent.height-3}")
         :setSize(10, 3)
         :setText("Reply")
         :setBackground(PALETTE.accent)
         :setForeground(PALETTE.panelFg)
         :onClick(function()
        local replyTo = sender
        local replySubj = (subject:sub(1, 4) == "Re: " and subject) or ("Re: " .. subject)
        local quoted = "\n\n--- On " .. formatUnix(ts) .. " " .. sender .. " wrote: ---\n" .. body
        go(composeScreen, replyTo, replySubj, quoted)
    end)
end

composeScreen = function(presetTo, presetSubject, presetBody)
    CURRENT_SCREEN = "compose"; INBOX_REFRESH = nil
    MAIN_SCREEN:setBackground(PALETTE.bg)
    addHeader(MAIN_SCREEN, "Compose", function()
        go(mainScreen)
    end)

    local panel = MAIN_SCREEN:addFrame("composePanel")
                             :setSize("{parent.width-4}", "{parent.height-3}")
                             :setPosition(2, 4)
                             :setBackground(PALETTE.panel)
                             :setForeground(PALETTE.panelFg)

    panel:addLabel("toL"):setPosition(2, 2):setText("To"):setForeground(PALETTE.panelFg)


    local toIn = panel:addInput("to")
                      :setPosition(6, 2)
                      :setSize("{parent.width-8}", 1)
                      :setBackground(PALETTE.inputBg)
                      :setForeground(PALETTE.inputFg)
                      :setText(presetTo or "")

    toIn.placeholder = "user@base"

    local toDropdown
    toDropdown = panel:addDropdown("toDropdown")
                      :setPosition("{parent.width-18}", 2)
                      :setBackground(PALETTE.inputBg)
                      :setForeground(colors.blue)
                      :onSelect(function(index, item)
        toIn:setText(winter_email.getUserByIndex(item - 1))
        toDropdown.items[item].selected = false
    end)

    for i = 0, winter_email.getUserCount() - 1 do
        local name = winter_email.getUserByIndex(i);
        toDropdown:addItem(name)
    end

    toDropdown.isOpen = false
    toDropdown.selectedText = "...or select"



    panel:addLabel("subjL"):setPosition(2, 4):setText("Subject"):setForeground(PALETTE.panelFg)
    local subjIn = panel:addTextBox("subject")
                        :setPosition(10, 4)
                        :setSize("{parent.width-12}", 1)
                        :setBackground(PALETTE.inputBg)
                        :setForeground(PALETTE.inputFg)
                        :setText(presetSubject or "")

    panel:addLabel("bodyL"):setPosition(2, 6):setText("Body"):setForeground(PALETTE.panelFg)
    local bodyIn = panel:addTextBox("body")
                        :setPosition(2, 7)
                        :setSize("{parent.width-6}", "{parent.height-10}")
                        :setBackground(PALETTE.inputBg)
                        :setForeground(PALETTE.inputFg)
                        :setText(presetBody or "")

    local cfooter = panel:addFrame("composeFooter")
                         :setPosition(2, "{parent.height-3}")
                         :setSize("{parent.width-4}", 4)
                         :setBackground(PALETTE.panel)
                         :setForeground(PALETTE.panelFg)

    local status = cfooter:addLabel("status"):setPosition(1, 1):setText("")

    local cbar = panel:addScrollbar("composeScroll")
                      :setPosition("{parent.width-2}", 7)
                      :setSize(1, "{parent.height-10}")
                      :setBackground(PALETTE.panel)
                      :setForeground(PALETTE.panelFg)
    if cbar.attach then
        cbar:attach(bodyIn, {
            property = "scrollY",
            min = 0,
            max = function()
                local text = bodyIn:getText() or ""
                local lines = 1; for _ in string.gmatch(text, "\n") do lines = lines + 1 end
                local h = (bodyIn.get and bodyIn.get("height")) or 0
                return math.max(0, lines - h + 2)
            end
        })
    end

    cfooter:addButton("send")
           :setPosition(1, 2)
           :setSize(12, 3)
           :setText("Send")
           :setBackground(PALETTE.accent)
           :setForeground(PALETTE.panelFg)
           :onClick(function()
        local to = toIn:getText() or ""
        local subj = subjIn:getText() or ""
        local body = bodyIn:getText() or ""
        if to == "" or not string.find(to, "@") or not winter_email.userExists(to) then
            status:setText("Enter a valid user@domain.")
            return
        end
        local ok, err = pcall(function()
            winter_email.sendEmail(to, subj, body)
        end)
        if ok then
            status:setText("Sent!")
            go(inboxScreen)
        else
            status:setText("Send failed: " .. tostring(err))
        end
    end)

    cfooter:addButton("cancel")
           :setPosition(14, 2)
           :setSize(12, 3)
           :setText("Cancel")
           :setBackground(PALETTE.danger)
           :setForeground(PALETTE.panelFg)
           :onClick(function()
        go(mainScreen)
    end)
end

renderRoot()

BASALT.run()