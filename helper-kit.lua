script_name('Helper Kit')
script_author('Daniel Adler | Kami')

local mad = require('MoonAdditions')
local sampev = require 'lib.samp.events'
local _result, _moonloader = pcall(require, "lib.moonloader")
if not _result then error("ModuleErr: 'moonloader' does not exist.") end

local _result, crypto = pcall(require, "crypto_lua")
if not _result then error("ModuleErr: 'crypto_lua' does not exist.") end

local http = require('socket.http')
local https = require('ssl.https')
local ltn12 = require('ltn12')
local url = require('socket.url')
local ti = require "tabler_icons"
local encoding = require 'encoding'
local events = require('samp.events')

imgui, handle = require('imgui'), PLAYER_HANDLE


encoding.default = 'CP1251'
u8 = encoding.UTF8

local ti_fontProp = {
    font = nil,
    fSize = 15.0,
    config = imgui.ImFontConfig(),
    glyphRanges = imgui.ImGlyphRanges({ti.min_range, ti.max_range})
}

ti_fontProp.config.MergeMode = true
ti_fontProp.config.PixelSnapH = true
ti_fontProp.config.FontDataOwnedByAtlas = false
ti_fontProp.config.GlyphOffset.y = 0.7

local ToScreen = convertGameScreenCoordsToWindowScreenCoords
local sX, sY = ToScreen(630, 438)
local message = {}
local IsNotifActive = false

local userConfigPath = 'moonloader\\config\\helper-kit\\settings.json'

local dictPath = 'moonloader\\config\\helper-kit\\dict.json'
local dict = {}

local locationsPath = 'moonloader\\config\\helper-kit\\locations.json'
local locations = {}

local checkpoint, blip

local ServerTour = {
    Locations = {
        { name = "Unity Station", desc = "The starting location of newbies." },
        { name = "Unity 24/7", desc = "24/7 to get set up for Cellphone and Phonebook" },
        { name = "Junkers Dealership", desc = "The Cheapest dealership on the server ranging $1,000 - $3,000 of vehicles." },
        { name = "BHT HQ", desc = "One of the oldest gangs in the server." },
        { name = "City Hall", desc = "Main City Hall of Los Santos. You can buy a license via [/getlicenses]." },
        { name = "Los Santos Police Department Headquarters", desc = "Main Law Enforcement Faction of the server, the LSPD is a starter faction." },
        { name = "All Saints General Hospital", desc = "All Saints Hospital one of the famous hospital to set your insurance to."},
        { name = "Bank of Los Santos", desc = "Main Bank of Los Santos, [/balance - /withdraw - /deposit - /bankhelp - /atmhelp]" },
        { name = "Paintball", desc = "One of the best places to hang out and test your firearm skills." },
        { name = "Maximus Club", desc = "A donator place for players who have a donator perk [/donate] for information." },
        { name = "Pizza Stacks", desc = "Best place to hang out with other players, known for its location." },
        { name = "Ganton Gym", desc = "Known for the bodyguard job and different fighting styles [/train]." },
        { name = "Willowfield Craftsman Sweepers", desc = "Get them started for [/ww] and [/gps] crafting." }
    },
    CurrentLocation = 1,
    IsActiveTour = false
}

local Settings = {
    Visible = {
        Main = imgui.ImBool(false),
        SelectedWindow = imgui.ImBool(false)
    }
}

local searchQuery = imgui.ImBuffer(256)
local newbinput = imgui.ImBuffer(256)
local hcinput = imgui.ImBuffer(256)

local SelectedSettings = {
    Tab = imgui.ImInt(0),
    Dictionary = "",
    Keyword = "",
    Location = "",
    HelprequestID = "",
    HelprequestName = ""
}

local UserSettings = {
    ShowTabs = {
        Definitions = true,
        Locations = true,
        Level1s = true,
        HelpRequests = true,
        ServerTour = true,
        HelperRoster = true,
        LvlCalculator = true
    },
    Configurations = {
        Notifications = {
            Show = true,
            Sound = true,
            DefaultDuration = 5,
            Messages = true,
            NumberOfNotifications = 2,
            Position = { x = 0, y = 0 }
        },
    }
}

local IsSelectedDict = imgui.ImBool(false)
local helpRequests = {}
local HelperRole = ""
local HelperRoster = {}
local OnlineHelpers = {}
local CachedSortedRoster = {}
local LastPlayerName = ""
local HasHelperRosterLoaded = false
local HasHelperStatsLoaded = false
local desc = ""

local time = 0

local isPlayerWhitelisted = false

local GITHUB_REPO = "cjkamii/hkit41225"
local SCRIPT_NAME = "helper-kit.lua"
local CURRENT_VERSION = 1.0
local BRANCH = "main"

local ENCRYPTED_TOKEN = "faKFo0UfQMZT5oZyR2DGJyytzkfeLm6M+nIUHvoJJn2ZGh5JqIIADz40OCJpS1cXQS1kSiMgRubma6iiz4vwvKiqDc3tkVYRP4HCol12TCaaXbqjcnXnsHoaBtfJ"
local AES_KEY = "VZibkuNELm826/wdsEv8BygN2An734zBTy4/uAcr2vw="
local AES_IV = "rfzmABubuEC75YWR//14LQ=="

local FORUM_LOGIN = "Adler"
local FORUM_PASSWORD = "GClleEoRUtrD2YnPMwjY9pOgh"
local FORUM_BASE = "https://forums.hzgaming.net"
local LOGIN_URL = FORUM_BASE .. "/login.php?do=login"
local TARGET_URL = FORUM_BASE .. "/showthread.php/119521-Helper-Roster"

function getPlayerNameSafe()
    local success, result = pcall(function()
        local ok, ped = getPlayerChar(PLAYER_HANDLE)
        if not ok or not ped or ped == 0 then
            return nil
        end

        local ok, playerId = sampGetPlayerIdByCharHandle(ped)
        if not ok or not playerId then
            return nil
        end

        local name = sampGetPlayerNickname(playerId)
        if not name or name == "" then
            return nil
        end

        if name:find("_") then
            return name:gsub("_", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
        else
            return name
        end
    end)

    if not success or not result then
        return nil
    end
    return result
end

function isPlayerInGitHubWhitelist(whitelist)
    if not whitelist then return false end

    local playerName = getPlayerNameSafe()
    if not playerName or playerName == "" then return false end

    local normalizedName = playerName:lower()
    for _, name in ipairs(whitelist) do
        if name == normalizedName then
            return true
        end
    end
    return false
end

function isPlayerWhitelisted(helperList)
    if not helperList then
        return false, nil
    end

    local playerName = getPlayerNameSafe()
    if not playerName or playerName == "" then
        return false, nil
    end
    
    for _, roleGroup in ipairs(helperList) do
        for _, helperName in ipairs(roleGroup.members) do
            local normalizedHelperName = helperName.name:gsub("_", " "):lower():gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            
            if normalizedHelperName == playerName:lower() then
                return true, roleGroup.role
            end
        end
    end

    return false, nil
end

function authenticateAndCheckWhitelist()
    local success, cookies, helperList = pcall(authenticateForum)
    if not success or not cookies then
        return false, nil, "Failed to authenticate"
    end

    local isWhitelisted, playerRole = isPlayerWhitelisted(helperList)

    if isWhitelisted then
        return true, {role = playerRole, team = "Helper Team"}, "Whitelisted"
    end

    return false, nil, "Not whitelisted"
end


function httpRequest(u, method, headers, postData, redirectHistory)
    redirectHistory = redirectHistory or {}
    local parsed = url.parse(u)
    local req = parsed.scheme == "https" and https or http
    local response = {}

    if #redirectHistory >= 5 then
        return nil, "Too many redirects"
    end
    
    local success, r, c, h = pcall(req.request, {
        url = u,
        method = method or "GET",
        headers = headers,
        source = postData and ltn12.source.string(postData),
        sink = ltn12.sink.table(response),
        redirect = false
    })

    if not success then
        return nil, "HTTP request failed"
    end
    
    if c == 303 or c == 302 or c == 301 then
        if not h or not h.location then
            return nil, "Redirect with no location"
        end
        
        local newUrl = url.absolute(u, h.location)
        
        for _, prevUrl in ipairs(redirectHistory) do
            if prevUrl == newUrl then
                return nil, "Redirect loop"
            end
        end
        
        table.insert(redirectHistory, u)
        return httpRequest(newUrl, method, headers, postData, redirectHistory)
    end
    
    return table.concat(response), c, h
end

function extractHelperRoster(htmlContent)
    if not htmlContent then
        return nil, "Empty HTML content"
    end

    local f = io.open("moonloader/config/helper-kit/logs/helper_roster.html", "w")
    if f then f:write(htmlContent); f:close() end

    local rolePatterns = {
        {
            pattern = '<img src="https://i%.imgur%.com/tclYuJM%.png"[^>]*>.-<ul>(.-)</ul>',
            role = "Helper Management",
        },
        {
            pattern = '<img src="https://forums%.hzgaming%.net/images/titles/z%-headhelper[^>]*>.-<ul>(.-)</ul>',
            role = "Head Helper"
        },
        {
            pattern = '<img src="https://forums%.hzgaming%.net/images/titles/z%-seniorhelper[^>]*>.-<ul>(.-)</ul>',
            role = "Senior Helper"
        },
        {
            pattern = '<img src="https://forums%.hzgaming%.net/images/titles/z%-juniorhelper[^>]*>.-<ul>(.-)</ul>',
            role = "Junior Helper"
        }
    }
    

    local extractedHelpers = {
        ["Director"] = {},
        ["Assistant Director"] = {},
        ["Helper Manager"] = {},
        ["Q&A Moderator"] = {},
        ["Head Helper"] = {},
        ["Senior Helper"] = {},
        ["Junior Helper"] = {},
        ["Unknown"] = {}
    }

    for _, roleData in ipairs(rolePatterns) do
        local roleSection = htmlContent:match(roleData.pattern)
        
        if roleSection then
            if roleData.role == "Helper Management" then
                local roleNameMap = {
                    ["Director of Helper Management"] = "Director",
                    ["Assistant Director of Helper Management"] = "Assistant Director",
                    ["Helper Manager"] = "Helper Manager",
                    ["Q&A Moderator"] = "Q&A Moderator"
                }
                
                for liBlock in roleSection:gmatch('<li[^>]*>(.-)</li>') do
                    local name = liBlock:match('<font color=".-">(.-)</font>') or
                                                liBlock:match('<a.->(.-)</a>') or
                                                liBlock:match('>([^<]+)<') or
                                                liBlock

                    local roleTitle = liBlock:match('<font size="1"><font color=".-">(.-)</font></font>') or
                                      liBlock:match('<font size="1">(.-)</font>')
                
                    name = name and name:gsub("<[^>]->", "")
                    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("_", " ")
                    roleTitle = roleTitle and roleTitle:gsub("&amp;", "&"):gsub("^%s+", ""):gsub("%s+$", "")
                
                    local specificRole = roleNameMap[roleTitle] or "Unknown"
                
                    if name and specificRole and specificRole ~= "Unknown" then
                        table.insert(extractedHelpers[specificRole], { name = name, stats = "" })
                    end
                end                    
            else
                for liBlock in roleSection:gmatch('<li[^>]*>(.-)</li>') do
                    local name = liBlock:match('<font color="#33CCFF">(.-)</font>') or
                               liBlock:match('<a.->(.-)</a>') or
                               liBlock:match('>([^<]+)<') or
                               liBlock

                    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("_", " ")

                    if name and name ~= "" then
                        local member = {
                            name = name,
                            stats = ""
                        }
                        table.insert(extractedHelpers[roleData.role], member)
                    end
                end
            end
        end
    end    

    local formattedHelpers = {}
    for roleName, helpers in pairs(extractedHelpers) do
        if #helpers > 0 then
            table.insert(formattedHelpers, {
                role = roleName,
                members = helpers,
                count = #helpers,
            })
        end
    end

    HelperRoster = formattedHelpers

    return formattedHelpers
end

function authenticateForum()
    local ok, content, code, headers = pcall(httpRequest, LOGIN_URL)
    if not ok or not content then
        return nil, "Failed to fetch login page: " .. tostring(code)
    end

    local fLogin = io.open("moonloader/config/helper-kit/logs/login_page.html", "w")
    if fLogin then fLogin:write(content); fLogin:close() end

    local securityToken = content:match('name="securitytoken" value="([^"]+)"')
                        or content:match('name="token" value="([^"]+)"')
                        or content:match('var SECURITYTOKEN = "([^"]+)"')

    if not securityToken then
        return nil, "Security token not found in login page."
    end

    local postData = table.concat({
        "vb_login_username=" .. url.escape(FORUM_LOGIN),
        "vb_login_password=" .. url.escape(FORUM_PASSWORD),
        "securitytoken=" .. url.escape(securityToken),
        "cookieuser=1",
        "do=login",
        "s=",
        "url=/index.php"
    }, "&")

    local ok2, loginContent, loginCode, loginHeaders = pcall(httpRequest,
        LOGIN_URL,
        "POST",
        {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Content-Length"] = #postData,
            ["User-Agent"] = "Mozilla/5.0",
            ["Origin"] = FORUM_BASE,
            ["Referer"] = LOGIN_URL
        },
        postData
    )

    if not ok2 or not loginContent or not loginHeaders then
        return nil, "Login request failed: " .. tostring(loginCode)
    end

    local cookies = loginHeaders["set-cookie"] or loginHeaders["Set-Cookie"]
    if not cookies then return nil, "No cookies received after login." end

    local ok3, protectedContent = pcall(httpRequest,
        TARGET_URL,
        "GET",
        {
            ["Cookie"] = cookies,
            ["User-Agent"] = "Mozilla/5.0",
            ["Referer"] = LOGIN_URL
        }
    )

    if not ok3 or not protectedContent then
        return nil, "Failed to load protected page"
    end

    local fProtected = io.open("moonloader/config/helper-kit/logs/helper_roster.html", "w")
    if fProtected then fProtected:write(protectedContent); fProtected:close() end

    local isLoggedIn = false
    local verificationPatterns = {
        "logout%.php", "login%.php%?do=logout", "signout", "log out", "sign out",
        "Logout", "Log Out",
        'class="username">'..FORUM_LOGIN,
        'Welcome,.-'..FORUM_LOGIN
    }

    for _, pattern in ipairs(verificationPatterns) do
        if protectedContent:find(pattern) then
            isLoggedIn = true
            break
        end
    end

    if not isLoggedIn then
        local usernamePattern = FORUM_LOGIN:gsub("%s+", "%%s+"):lower()
        if protectedContent:lower():find(usernamePattern) then
            isLoggedIn = true
        end
    end

    if isLoggedIn then
        local helperList, extractErr = extractHelperRoster(protectedContent)
        if helperList then
            return cookies, helperList
        else
            return nil, "Failed to extract roster: " .. tostring(extractErr)
        end
    end

    local localPath = "moonloader/config/helper-kit/logs/helper_roster.html"
    local f = io.open(localPath, "r")
    if f then
        local cachedContent = f:read("*a")
        f:close()
        if cachedContent and cachedContent:find("<html") then
            local helperList, err = extractHelperRoster(cachedContent)
            if helperList then
                return "LOCAL_FILE", helperList
            else
                return nil, "Failed to extract from local file: " .. tostring(err)
            end
        end
    end

    return nil, "All methods failed: forum login and local fallback."
end

function getToken()
    local success, decrypted = pcall(function()
        return crypto.aes_decode(ENCRYPTED_TOKEN, AES_KEY, AES_IV)
    end)
    if not success or not decrypted or not decrypted:match("^github_pat_") then
        error("Failed to decrypt valid GitHub token")
    end
    return decrypted
end

function downloadGitHubFile(path, repo)
    local response_chunks = {}
    local api_url = "https://api.github.com/repos/"..repo.."/contents/"..path
    local raw_url = "https://raw.githubusercontent.com/"..repo.."/main/"..path

    local headers = {
        ["Authorization"] = "token " .. getToken(),
        ["User-Agent"] = "MoonLoader Script",
        ["Accept"] = "application/vnd.github.v3.raw"
    }

    local _, status = https.request({
        url = raw_url,
        headers = headers,
        sink = ltn12.sink.table(response_chunks),
        protocol = "tlsv1_2",
        verify = "none"
    })

    local response = table.concat(response_chunks)

    if status ~= 200 then
        response_chunks = {}
        _, status = https.request({
            url = api_url,
            headers = headers,
            sink = ltn12.sink.table(response_chunks),
            protocol = "tlsv1_2",
            verify = "none"
        })
        response = table.concat(response_chunks)

        if status ~= 200 then
            return nil, "Failed to fetch file from GitHub. HTTP status: " .. status
        end

        local data = decodeJson(response)
        if not data or not data.content then
            return nil, "Invalid GitHub response, no content found."
        end
        response = crypto.base64_decode(data.content:gsub("\n", ""))
    end

    return response
end

function checkUpdate()
    local content = downloadGitHubFile("version.txt", GITHUB_REPO)
    if not content then return false, "Failed to check version" end

    local remote_version = tonumber(content:match("VERSION%s*=%s*([%d%.]+)"))
    local update_flag = content:match("UPDATE%s*=%s*(%a+)")

    if not remote_version then return false, "Invalid version format" end
    if not update_flag then return false, "Missing UPDATE flag" end

    local changelog = content:match("CHANGELOG:(.+)")
    changelog = changelog and changelog:gsub("\r", "") or "- No changelog available"

    local local_version = nil
    local version_file_path = "moonloader\\config\\helper-kit\\version.txt"
    local file = io.open(version_file_path, "r")

    if file then
        for line in file:lines() do
            local found_version = line:match("VERSION%s*=%s*([%d%.]+)")
            if found_version then
                local_version = tonumber(found_version)
                break
            end
        end
        file:close()
    end

    CURRENT_VERSION = local_version or 0

    local should_update = (update_flag:lower() == "true" and remote_version > CURRENT_VERSION)

    return should_update, remote_version, changelog
end

function checkAndDownloadLibraries()
    local libraries = {
        ["MoonAdditions"] = "lib/MoonAdditions.lua",
        ["lib.samp.events"] = "lib/lib/samp/events.lua",
        ["lib.moonloader"] = "lib/lib/moonloader.lua",
        ["crypto_lua"] = "lib/crypto_lua.lua",
        ["socket.http"] = "lib/socket/http.lua",
        ["ssl.https"] = "lib/ssl/https.lua",
        ["ltn12"] = "lib/ltn12.lua",
        ["socket.url"] = "lib/socket/url.lua",
        ["tabler_icons"] = "lib/tabler_icons.lua",
        ["encoding"] = "lib/encoding.lua",
        ["samp.events"] = "lib/samp/events.lua"
    }

    for lib, path in pairs(libraries) do
        local status, _ = pcall(require, lib)
        if not status then
            sampAddChatMessage(string.format("[Helper-Kit] {FFFF00}Library '%s' {FFFF00}not found. Attempting to download {33CCFF}'%s'...", lib, path), 0x33CCFF)
            local content, err = downloadGitHubFile(path, GITHUB_REPO)
            if not content then
                sampAddChatMessage(string.format("[Helper-Kit] {FF0000}Failed to download %s: {33CCFF}%s", path, err), 0x33CCFF)
            else
                local file = io.open(getWorkingDirectory() .. "\\" .. path, "wb")
                if file then
                    file:write(content)
                    file:close()
                    sampAddChatMessage(string.format("[Helper-Kit] {00FF00}Downloaded and saved: {33CCFF}%s", path), 0x33CCFF)
                else
                    sampAddChatMessage(string.format("[Helper-Kit] {00FF00}Cannot write file: {33CCFF}%s", path), 0x33CCFF)
                end
            end
        end
    end
end

function ensureVersionFileExists(file_path)
    local file = io.open(file_path, "r")
    if not file then
        file = io.open(file_path, "w")
        if file then
            file:write("VERSION = 1.0\nUPDATE = true\nCHANGELOG:\n- Initial version\n")
            file:close()
        else
            error("Failed to create version.txt")
        end
    else
        file:close()
    end
end

function readChangelogOnly(file_path)
    local file = io.open(file_path, "r")
    if not file then return nil end

    local lines = {}
    local isChangelog = false

    for line in file:lines() do
        if not isChangelog and line:match("^CHANGELOG:") then
            local inline = line:match("^CHANGELOG:%s*(.*)")
            if inline and inline ~= "" then
                table.insert(lines, inline)
            end
            isChangelog = true
        elseif isChangelog then
            if line:match("^%w+%s*=") then break end
            if line:match("%S") then
                table.insert(lines, line)
            end
        end
    end

    file:close()

    local seen = {}
    local finalLines = {}
    for _, line in ipairs(lines) do
        if not seen[line] then
            seen[line] = true
            table.insert(finalLines, line)
        end
    end

    return table.concat(finalLines, "\n")
end

function readVersionConfig(file_path)
    local file = io.open(file_path, "r")
    if not file then return nil, "File not found" end

    local config = {}
    for line in file:lines() do
        local key, value = line:match("(%w+)%s*=%s*(.+)")
        if key and value then
            config[key] = value
        end
    end

    file:close()
    return config
end

function writeVersionConfig(file_path, config, new_changelog_entry)
    local existing_changelog = readChangelogOnly(file_path) or ""
    local full_changelog = string.format("Version %s | Changelog:\n%s\n\n%s",
        config.VERSION,
        new_changelog_entry or "- No changes listed",
        existing_changelog
    )

    local file = io.open(file_path, "w")
    if not file then return false, "Failed to open file for writing" end

    file:write("VERSION = " .. config.VERSION .. "\n")
    file:write("UPDATE = " .. (config.UPDATE or "true") .. "\n")
    file:write("CHANGELOG:\n" .. full_changelog)

    Changelog = full_changelog

    file:close()
    return true
end


function performUpdate(remote_version, changelog)
    local content = downloadGitHubFile(SCRIPT_NAME, GITHUB_REPO)
    if not content then error("Download failed") end

    local script_file = io.open(thisScript().path, "w")
    if not script_file then error("File write failed") end
    script_file:write(content)
    script_file:close()

    local version_file_path = "moonloader\\config\\helper-kit\\version.txt"
    
    local config, error_message = readVersionConfig(version_file_path)
    if not config then
        error("Failed to read version.txt: " .. error_message)
    end

    config.VERSION = tostring(remote_version)

    local success, write_error = writeVersionConfig(version_file_path, config, changelog)
    if not success then
        error("Failed to update version.txt: " .. write_error)
    end

    CURRENT_VERSION = remote_version

    saveIni()
    thisScript():reload()
    addNotification(("Script updated to v%s"):format(remote_version), "Update", UserSettings.Configurations.Notifications.DefaultDuration)
    sampAddChatMessage(string.format("[Helper-Kit] {00FF00}Script updated to v%s", remote_version), 0x33CCFF)
    if Settings.Visible.Main.v == false then
        Settings.Visible.Main.v = true
        if imgui.ShowCursor == false then
            imgui.ShowCursor = true
        end
        SelectedSettings.Tab = 0
    end
    loadIni()
end

function getMatch(a, kw)
    kw = kw:lower():gsub(' ', ''):gsub('-', '')
    local bm, bmd
    for _, e in ipairs(a) do
        if e.keywords and type(e.keywords) == 'table' then
            for _, ekw in ipairs(e.keywords) do
                local ekws = ekw:lower():gsub(' ', ''):gsub('-', '')
                if kw == ekws:sub(1, #kw) then
                    local d = math.abs(#kw - #ekws)
                    if bmd == nil or d < bmd then
                        bmd = d
                        bm = e
                    end
                end
            end
        end
    end
    return bm
end

function numWithCommas(n)
    return tostring(math.floor(n)):reverse():gsub("(%d%d%d)","%1,"):gsub(",(%-?)$","%1"):reverse()
end

function cmdDef(kw)
    if #kw == 0 then
        sampAddChatMessage('USAGE: (/def)ine [query]', 0xAFAFAF)
        return
    end
    local bm = getMatch(dict, kw)
    if bm == nil then
        sampAddChatMessage('No match found.', -1)
        return
    end
    local msgt = {bm.keywords[1]}
    for n, v in pairs(bm) do
        if n == 'keywords' then goto continue end
        table.insert(msgt, string.format('%s: %s', n:sub(1, 1):upper() .. n:sub(2, #n), v))
        ::continue::
    end
    local msg = ''
    for i, v in pairs(msgt) do
        msg = msg .. v
        if i == #msgt then goto continue end
        msg = msg .. ' | '
        ::continue::
    end
    msgt = nil
    while #msg > 144 do
        sampAddChatMessage(msg:sub(1, 144), -1)
        msg = '-..' .. msg:sub(145, #msg)
    end
    sampAddChatMessage(msg, -1)
end

local currentlocation = nil

function cmdLoc(kw)
    if #kw == 0 then
        sampAddChatMessage('USAGE: (/loc)ate [query]', 0xAFAFAF)
        return
    end
    local bm = getMatch(locations, kw)
    if bm == nil then
        sampAddChatMessage('No match found.', -1)
        return
    end
    clearCheckpoint()
    blip = addBlipForCoord(bm.X, bm.Y, bm.Z)
    setCoordBlipAppearance(blip, 2)
    checkpoint = createCheckpoint(2, bm.X, bm.Y, bm.Z, bm.X, bm.Y, bm.Z, 15)

    if currentlocation then
        currentlocation:terminate()
        currentlocation = nil
    end

    currentlocation = lua_thread.create(function()
        local successThread, errThread = pcall(function()
            while checkpoint ~= nil and blip ~= nil do
                local cx, cy, cz = getCharCoordinates(PLAYER_PED)
                if getDistanceBetweenCoords3d(cx, cy, cz, bm.X, bm.Y, bm.Z) <= 15 then
                    clearCheckpoint()
                    addOneOffSound(cx, cy, cz, 1058)
                    sampAddChatMessage(string.format('[Helper-Kit]{FFFFFF} You have arrived at the{33CCFF} %s.', bm.keywords[1]), 0x33CCFF)
                    addNotification(string.format("You have arrived at the %s", bm.keywords[1]), "Arrived", UserSettings.Configurations.Notifications.DefaultDuration)
                    currentlocation = nil
                    return
                end
                wait(100)
            end
        end)
    end)
    sampAddChatMessage(string.format('Follow the checkpoint to %s.', bm.keywords[1]), -1)
    addNotification(string.format("Follow the checkpoint to %s", bm.keywords[1]), "Locate", UserSettings.Configurations.Notifications.DefaultDuration)
end

local LevelCalc = {
    playerID = imgui.ImBuffer("", 10),
    minLevel = imgui.ImBuffer("", 10),
    maxLevel = imgui.ImBuffer("", 10),
    resultText = "",
}
    

function cmdLvl(params)
    local startLvl, endLvl = params:match("(%d+)%s*(%d*)")
    
    if startLvl == nil or tonumber(startLvl) == nil then
        return sampAddChatMessage("[Helper-Kit] {FFFFFF}Usage: [/lvl 5 10] - [/lvl 25]", 0x33CCFF)
    end
	
    startLvl = tonumber(startLvl)
    if startLvl < 1 then
        return sampAddChatMessage("[Helper-Kit] {FFFFFF}The levels must be greater or equal to 1", 0x33CCFF)
    end

    if endLvl ~= "" then
        endLvl = tonumber(endLvl)
        if endLvl < 1 then
            return sampAddChatMessage("[Helper-Kit] {FFFFFF}The levels must be greater or equal to 1", 0x33CCFF)
        end
    else
        endLvl = 1
    end

    local smallerLvl, largerLvl = math.min(startLvl, endLvl), math.max(startLvl, endLvl)
	if(smallerLvl == largerLvl) then
		return sampAddChatMessage("[Helper-Kit] {FFFFFF}Usage: [/lvl 5 10]", 0x33CCFF)
	end
    local totalRP, totalCash = 0, 0
	local lvl = largerLvl

    repeat
        totalRP = largerLvl * 4 + totalRP
        totalCash = largerLvl * 2500 + totalCash
        largerLvl = largerLvl - 1
    until(smallerLvl == largerLvl)
	
    local formattedTotalCash = numWithCommas(totalCash)
	local formattedTotalRP = numWithCommas(totalRP)
    sampAddChatMessage("[Helper-Kit] {FFFFFF}For levels {33CCFF}" .. smallerLvl .. " to " .. lvl ..
                       "{FFFFFF}: Total Respect Points: {33CCFF}" .. formattedTotalRP ..
                       "{FFFFFF} Total Cash: {33CCFF}$" .. formattedTotalCash, 0x33CCFF)
end

function cmdN(msg)
    if #msg == 0 then
        sampAddChatMessage('USAGE: (/n)ewbie [text]', 0xAFAFAF)
        return
    end
    sampSendChat('/newb ' .. msg)
end

function cmdHrs()
    sampSendChat('/helprequests')
end

function cmdAhr(params)
    if #params == 0 then
        sampAddChatMessage('USAGE: (/a)ccept(h)elp(r)equest [playerid]', 0xAFAFAF)
        return
    end
    sampSendChat('/accepthelp ' .. params)
end

function cmdLvl1s()
    local lvl1s = {}
    for id = 0, sampGetMaxPlayerId(false), 1 do
        if sampIsPlayerConnected(id) then
            if sampGetPlayerScore(id) == 1 then
                if string.find(sampGetPlayerNickname(id), '_') then
                    table.insert(lvl1s, id)
                end
            end
        end
    end
    if #lvl1s == 0 then
        sampAddChatMessage('No level 1 player is online, but this may be a mistake. Try pressing TAB and waiting a few moments.', -1)
        return
    end
    sampAddChatMessage('Level 1 Players Online:', 0xFFA500)
    local final = {}
    local team = {}
    local r = 1
    for i, id in pairs(lvl1s) do
        if r == 4 then
            r = 1
            table.insert(final, team)
            team = {}
        end
        table.insert(team, string.format('{33CCFF}(%i){FFFFFF} %s', id, string.gsub(sampGetPlayerNickname(id), '_', ' ')))
        r = r + 1
    end
    for i, team in pairs(final) do
        sampAddChatMessage(table.concat(team, " | "), -1)
    end
end

function cmdHkhelp()
    sampAddChatMessage('_______________________________________', 0x33CCFF)
    sampAddChatMessage('*** HELPER KIT HELP *** {FFFFFF}- type a command for more infomation.', 0x33ccff)
    sampAddChatMessage('*** HELPER KIT ALL *** {FFFFFF}/hkit /def /loc /lvl /n /lvl1s /addloc', 0x33ccff)
    sampAddChatMessage('*** HELPER KIT SENIORS *** {FFFFFF}/ahr /hrs /sst /est', 0x33ccff)
end

local tourThread = nil
local isTourInProgress = false
local tourMonitorThread = nil

function startServerTour()
    local success, err = pcall(function()
        if ServerTour.IsTourActive then
            addNotification("Server Tour is already running!", "Startservertour", UserSettings.Configurations.Notifications.DefaultDuration)
            return
        end

        cleanupTourResources()
        
        ServerTour.CurrentLocation = 1
        ServerTour.IsTourActive = true
        addNotification("Server Tour started! Follow the checkpoints.", "Startservertour", UserSettings.Configurations.Notifications.DefaultDuration)
        
        proceedToNextLocation()
    end)

    if not success then
        addNotification("Error in startServerTour: " .. tostring(err), "Startservertour", UserSettings.Configurations.Notifications.DefaultDuration)
        cleanupTourResources()
    end
end

function exitServerTour()
    local success, err = pcall(function()
        if not ServerTour.IsTourActive then addNotification("There are no server tour on-going.", "Exitservertour", UserSettings.Configurations.Notifications.DefaultDuration) return end
        
        ServerTour.IsTourActive = false
        ServerTour.CurrentLocation = 1
        cleanupTourResources()
        addNotification("You have exited the Server Tour.", "Exitservertour", UserSettings.Configurations.Notifications.DefaultDuration)
    end)

    if not success then
        addNotification("Error in exitServerTour: " .. tostring(err), "Exitservertour", UserSettings.Configurations.Notifications.DefaultDuration)
    end
end

function cleanupTourResources()
    clearCheckpoint()
    checkpoint, blip = nil, nil
    
    if tourThread then
        tourThread:terminate()
        tourThread = nil
    end
    
    isTourInProgress = false
end

function proceedToNextLocation()
    if not ServerTour.IsTourActive then return end
    if isTourInProgress then return end
    if tourThread then
        tourThread:terminate()
        tourThread = nil
    end

    if ServerTour.CurrentLocation > #ServerTour.Locations then
        addNotification("Server Tour Complete!", "Servertour", UserSettings.Configurations.Notifications.DefaultDuration)
        ServerTour.IsTourActive = false
        ServerTour.CurrentLocation = 1
        cleanupTourResources()
        return
    end

    local locationData = ServerTour.Locations[ServerTour.CurrentLocation]
    if not locationData then
        addNotification("Error: Invalid location data.", "Servertour", UserSettings.Configurations.Notifications.DefaultDuration)
        exitServerTour()
        return
    end

    local locationName, description = locationData.name, locationData.desc

    local bm = getMatch(locations, locationName)
    if not bm then
        addNotification(string.format("Error: Location '%s' not found", locationName), "Servertour", UserSettings.Configurations.Notifications.DefaultDuration)
        exitServerTour()
        return
    end

    cleanupTourResources()
    
    blip = addBlipForCoord(bm.X, bm.Y, bm.Z)
    setCoordBlipAppearance(blip, 2)
    checkpoint = createCheckpoint(2, bm.X, bm.Y, bm.Z, bm.X, bm.Y, bm.Z, 15)

    isTourInProgress = true

    tourThread = lua_thread.create(function()
        local successThread, errThread = pcall(function()
            local function checkPlayerDistance()
                local cx, cy, cz = getCharCoordinates(PLAYER_PED)
                return getDistanceBetweenCoords3d(cx, cy, cz, bm.X, bm.Y, bm.Z) <= 15
            end

            while ServerTour.IsTourActive do
                if checkPlayerDistance() then
                    if ServerTour.CurrentLocation ~= #ServerTour.Locations then
                        addNotification(string.format("Now heading to: %s", ServerTour.Locations[ServerTour.CurrentLocation + 1] and ServerTour.Locations[ServerTour.CurrentLocation + 1].name or "None"), "Servertour", UserSettings.Configurations.Notifications.DefaultDuration)
                    end
                    addNotification(string.format("Current Location: %s", locationName), "Servertour", UserSettings.Configurations.Notifications.DefaultDuration)
                    addNotification(string.format("%s", description), "Servertour", UserSettings.Configurations.Notifications.DefaultDuration)
                    addOneOffSound(bm.X, bm.Y, bm.Z, 1058)
                    
                    ServerTour.CurrentLocation = ServerTour.CurrentLocation + 1
                    wait(1500)
                    
                    cleanupTourResources()
                    return
                end
                
                wait(100)
            end
        end)

        if not successThread then
            addNotification("Tour error: " .. tostring(errThread), "Servertour", UserSettings.Configurations.Notifications.DefaultDuration)
            cleanupTourResources()
        end
    end)
end

if not tourMonitorThread then
    tourMonitorThread = lua_thread.create(function()
        while true do
            if ServerTour.IsTourActive and not isTourInProgress then
                proceedToNextLocation()
            end
            wait(500)
        end
    end)
end

function clearCheckpoint()
    if blip then
        removeBlip(blip)
        blip = nil
    end
    if checkpoint then
        deleteCheckpoint(checkpoint)
        checkpoint = nil
    end
end

function getLocationKey(index)
    local success, result = pcall(function()
        local count = 1
        for key, _ in pairs(ServerTour.Locations) do
            if count == index then
                return key
            end
            count = count + 1
        end
        return nil
    end)

    if not success then
        addNotification("Error in getLocationKey: " .. tostring(result), "Getlocationkey", UserSettings.Configurations.Notifications.DefaultDuration)
        return nil
    end

    return result
end

function cmdaddloc(Arg)
    if #Arg == 0 then
        sampAddChatMessage('USAGE: (/addloc)ation [Location]', 0xAFAFAF)
        return
    end

    local result1, Ped = getPlayerChar(handle)
    local result2, PlayerID = sampGetPlayerIdByCharHandle(Ped)
    local positionX, positionY, positionZ = getCharCoordinates(Ped)
    local City = getCityFromCoords(positionX,positionY,positionZ)
    local Zone = getNameOfZone(positionX,positionY,positionZ)

    local Locations = {}

    local fileopen = io.open(locationsPath, "r")
    if fileopen then
           local fileContent = fileopen:read("*a")
        Locations = decodeJson(fileContent)
        fileopen:close()
    else
        addNotification("Failed to open Locations.JSON for reading", "Addlocation", UserSettings.Configurations.Notifications.DefaultDuration)
        return
    end

    local newData = {
        keywords = { Arg },
        X = positionX,
        Y = positionY,
        Z = positionZ
    }

    table.insert(Locations, newData)

    local file = io.open(locationsPath, "w")
    if file then
        file:write(encodeJson(Locations))
        file:close()
        addNotification(string.format("%s has been added", Arg), "Addlocation", UserSettings.Configurations.Notifications.DefaultDuration)
    else
        addNotification(string.format("%s has been failed to be added", Arg), "Addlocation", UserSettings.Configurations.Notifications.DefaultDuration)
    end

    refreshconfigspath()
end

function rgbToImVec4(r, g, b, a)
    return imgui.ImVec4(r / 255, g / 255, b / 255, a or 1)
end

function hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b = 0, 0, 0
    if i % 6 == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end
    return r * 255, g * 255, b * 255
end

function imgui.BeforeDrawFrame()
    if ti and ti_fontProp.font == nil then
        ti_fontProp.font = imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(ti.get_font_data_base85(), ti_fontProp.fSize, ti_fontProp.config, ti_fontProp.glyphRanges)
    end
end

local adminSettings = {
    Password = "ADMIN123",
    Authenticated = false,
    PasswordInput = imgui.ImBuffer(256),
    whitelistEditMode = false,
    AdminsList = {},
    IsAdmin = false,
    SelectedTab = "Whitelist",
    helperRoleOrder = {
        "Director",
        "Assistant Director", 
        "Helper Manager",
        "Q&A Moderator",
        "Head Helper",
        "Senior Helper",
        "Junior Helper"
    },
    Inputs = {
        HelperName = imgui.ImBuffer(256),
        HelperRole = imgui.ImInt(1),
        Definition = imgui.ImBuffer(256),
        Keyword = imgui.ImBuffer(256),
    },
    HelperRosterCopy = {}
}

local updateInProgress = false
local updateMessage = ""
local IsPlacingNotif = false
local ShowDummyNotif = false

function imgui.OnDrawFrame()
    width, height = getScreenResolution()
    local windowWidth, windowHeight = 500, 600

    time = time + 0.0005
    local hue = (time * 0.5) % 1
    local brightness = 0.75 + 0.15 * math.sin(time * 2)
    
    local r, g, b = hsvToRgb(hue, 0.8, brightness)

    imgui.PushStyleColor(imgui.Col.TitleBg,         rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.TitleBgActive,   rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.TitleBgCollapsed,rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.Button,          rgbToImVec4(r, g, b, 0.7))
    imgui.PushStyleColor(imgui.Col.ButtonHovered,   rgbToImVec4(r, g, b, 0.7))
    imgui.PushStyleColor(imgui.Col.ButtonActive,    rgbToImVec4(r, g, b, 0.7))
    imgui.PushStyleColor(imgui.Col.Text,            rgbToImVec4(255, 255, 255, 1))
    imgui.PushStyleColor(imgui.Col.CheckMark,       rgbToImVec4(255, 255, 255, 0.8))
    imgui.PushStyleColor(imgui.Col.FrameBg,         rgbToImVec4(r, g, b, 0.7))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered,  rgbToImVec4(r, g, b, 0.7))
    imgui.PushStyleColor(imgui.Col.FrameBgActive,   rgbToImVec4(r, g, b, 0.7))

    imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 5)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 5)
    imgui.PushStyleVar(imgui.StyleVar.FrameRounding, 5)

    if UserSettings.Configurations.Notifications.Show then
        if IsNotifActive then
            if UserSettings.Configurations.Notifications.Position == nil then
                UserSettings.Configurations.Notifications.Position = { x = 0, y = 0 }
            end
            if IsPlacingNotif == nil then IsPlacingNotif = false end
            if ShowDummyNotif == nil then ShowDummyNotif = false end
                    
            local count = 0
            local currentTime = os.clock()
            local totalHeight = 0
                    
            local screenWidth, screenHeight = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
            local margin = 20 
            local rightPosition = screenWidth - margin 
            local notifWidth = 200
                    
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
            imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0, 0, 0, 0))
                    
            if UserSettings.Configurations.Notifications.Position.x == 0 and
               UserSettings.Configurations.Notifications.Position.y == 0 then
                UserSettings.Configurations.Notifications.Position = {
                    x = rightPosition - notifWidth - 10,
                    y = screenHeight / 2 - 150
                }
            end
            
            if IsPlacingNotif then
                local mousePos = imgui.GetMousePos()
                UserSettings.Configurations.Notifications.Position = {
                    x = mousePos.x,
                    y = mousePos.y
                }
    
                if imgui.IsMouseClicked(0) then
                    IsPlacingNotif = false
                    IsNotifActive = false
                end
            end
            
            local pos = UserSettings.Configurations.Notifications.Position
            imgui.SetNextWindowPos(imgui.ImVec2(pos.x, pos.y), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(notifWidth + 20, 600))    
            
            imgui.Begin("##notif_container", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)
            
            local drawList = imgui.GetWindowDrawList()
            
            if ShowDummyNotif and IsPlacingNotif then
                local maxNotifications = UserSettings.Configurations.Notifications.NumberOfNotifications or 2
            
                for i = 1, maxNotifications do
                    local dummyText = u8(string.format("This is a sample notification for positioning. %d/%d notifications shown.", i, maxNotifications))
            
                    local dummyTextSize = imgui.GetFont():CalcTextSizeA(imgui.GetFont().FontSize, notifWidth, notifWidth, dummyText)
                    local dummyLineHeight = imgui.GetFont().FontSize + imgui.GetStyle().ItemSpacing.y
                    local dummyTextHeight = math.ceil(dummyTextSize.y / dummyLineHeight) * dummyLineHeight
                    dummyTextHeight = math.max(dummyTextHeight, 30)
            
                    local spacing = (i == 1 and 8 or 13)
                    totalHeight = totalHeight + dummyTextHeight + spacing
            
                    local minX = imgui.GetCursorScreenPos().x
                    local minY = imgui.GetCursorScreenPos().y
                    local maxX = minX + notifWidth
                    local maxY = minY + dummyTextHeight + imgui.GetStyle().ItemSpacing.y + imgui.GetStyle().WindowPadding.y
                    local padding, margin = 4, 8
            
                    drawList:AddRectFilled(imgui.ImVec2(minX - padding, minY - padding), imgui.ImVec2(maxX + padding, maxY + padding), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.1, 0.1, 0.1, 0.9)), 6)
                    imgui.TextColored(imgui.ImVec4(0.6, 0.8, 1.0, 1.0), "[Preview]")
                    imgui.TextWrapped(dummyText)
                    imgui.SetCursorPosY(imgui.GetCursorPosY() + margin)
                end
            end                    

            if type(message) == "table" then
                for k = #message, 1, -1 do
                    local v = message[k]
                    local push = false
                    local fadeDuration = 2.0
                
                    if v.active and (currentTime >= v.time) then
                        v.active = false
                        v.fadeStart = currentTime
                    end
                
                    local alpha = 1.0
                    if v.fadeStart then
                        local fadeElapsed = currentTime - v.fadeStart
                        alpha = math.max(0, 1 - (fadeElapsed / v.fadeDuration))
                    
                        if alpha <= 0 then
                            table.remove(message, k)
                            goto continue
                        end
                    end

                    local maxNotifications = UserSettings.Configurations.Notifications.NumberOfNotifications or 2

                    if count < maxNotifications then
                        if v.active or v.fadeStart then
                            count = count + 1
                        
                            if alpha < 1 then
                                imgui.PushStyleVar(imgui.StyleVar.Alpha, alpha)
                                push = true
                            end
                        
                            local nText = u8(tostring(v.text))
                            local textSize = imgui.GetFont():CalcTextSizeA(imgui.GetFont().FontSize, notifWidth, notifWidth, nText)
                            local lineHeight = imgui.GetFont().FontSize + imgui.GetStyle().ItemSpacing.y
                            local textHeight = math.ceil(textSize.y / lineHeight) * lineHeight
                        
                            textHeight = math.max(textHeight, 30)
                            --[[if #nText >= 33 then textHeight = math.max(textHeight, 45) end
                            if #nText >= 97 then textHeight = math.max(textHeight, 70) end
                            if v.type == "Helprequest" then textHeight = math.max(textHeight, 110) end]]
                        
                            local spacing = (count == 1 and 8 or 13)
                            totalHeight = totalHeight + textHeight + spacing
                        
                            local minX = imgui.GetCursorScreenPos().x
                            local minY = imgui.GetCursorScreenPos().y
                            local maxX = minX + notifWidth
                            local maxY = minY + textHeight + imgui.GetStyle().ItemSpacing.y + imgui.GetStyle().WindowPadding.y
                            local padding, margin = 4, 8
                        
                            drawList:AddRectFilled(imgui.ImVec2(minX - padding, minY - padding), imgui.ImVec2(maxX + padding, maxY + padding), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0, 0, 0, 0.7)), 6)
                            imgui.TextColored(imgui.ImVec4(0.5, 0.5, 1.0, 1.0), "Helper-Kit") 
                            imgui.TextWrapped(nText)
                            imgui.SetCursorPosY(imgui.GetCursorPosY() + margin)
                        
                            local allowedRoles = {
                                ["Whitelisted"] = false,
                                ["Junior Helper"] = false,
                                ["Senior Helper"] = true,
                                ["Head Helper"] = true,
                                ["Helper Manager"] = true,
                                ["Director"] = true
                            }
                        
                            if v.type == "Helprequest" and allowedRoles[HelperRole] then
                                local name, id, message
                            
                                local patterns = {
                                    "^(.-)%s*%(%s*ID%s*:%s*(%d+)%s*%)%s*has requested a help! message:%s*(.+)$",
                                    "^(.-)%s*%(%s*ID%s*:%s*(%d+)%s*%)%s*[:%-]%s*(.+)$",
                                    "^(.-)%s*%(%s*(%d+)%s*%)%s*[:%-]%s*(.+)$",
                                    "^(.-)%s*%(%s*ID%s*:%s*(%d+)%s*%)%s*(.+)$"
                                }
                            
                                for _, pattern in ipairs(patterns) do
                                    name, id, message = nText:match(pattern)
                                    if name then break end
                                end
                            
                                name = name and name:gsub("^%s*(.-)%s*$", "%1") or "Unknown"
                                id = id and tonumber(id) or 0
                                message = message and message:gsub("^%s*(.-)%s*$", "%1") or nText
                            
                                local requestKey = id .. ":" .. name
                                if helpRequests[requestKey] and not helpRequests[requestKey].IsStatus then
                                    local windowWidth = imgui.GetContentRegionAvail().x
                                    local buttonWidth, spacing = 50, 15
                                    local totalWidth = (buttonWidth * 2) + spacing
                                    local topMargin = 5
                                
                                    imgui.SetCursorPosY(imgui.GetCursorPosY() + topMargin) 
                                    imgui.SetCursorPosX((windowWidth - totalWidth) / 2)
                                
                                    if imgui.Button(u8("Accept"), imgui.ImVec2(buttonWidth, 20)) then
                                        addNotification(string.format("You have accepted %s's (ID:%d) Help request.", name, id), nil, UserSettings.Configurations.Notifications.DefaultDuration)
                                        sampSendChat("/accepthelp " .. id)
                                        helpRequests[requestKey].IsStatus = true
                                        helpRequests[requestKey].isHandled = true
                                    end
                                
                                    imgui.SameLine(0, spacing)
                                
                                    if imgui.Button(u8("Trash"), imgui.ImVec2(buttonWidth, 20)) then
                                        addNotification(string.format("You have trashed %s's (ID:%d) Help request.", name, id), nil, UserSettings.Configurations.Notifications.DefaultDuration)
                                        sampSendChat("/trashhelp " .. id)
                                        helpRequests[requestKey].IsStatus = true
                                        helpRequests[requestKey].isHandled = true
                                    end
                                end
                            
                            elseif v.type == "Update" then
                                local buttonWidth = 100
                                local buttonHeight = 20
                                local availableWidth = imgui.GetContentRegionAvail().x
                                local topMargin = 5
                            
                                imgui.SetCursorPosY(imgui.GetCursorPosY() + topMargin)
                                imgui.SetCursorPosX((availableWidth - buttonWidth) / 2)
                            
                                if imgui.Button("Update Now##UpdateConfirm", imgui.ImVec2(buttonWidth, buttonHeight)) then
                                    imgui.ShowCursor = false
                                    local update_available, version_or_error, changelog = checkUpdate()
                                    performUpdate(version_or_error, changelog)
                                end
                            end                                     
                        
                            imgui.Dummy(imgui.ImVec2(1, margin))
                        
                            imgui.Spacing()
                        
                            if push then
                                imgui.PopStyleVar()
                            end
                        end
                    end
                    ::continue::
                end
            end
            imgui.End()
            imgui.PopStyleColor(2)
        
            if count == 0 and #message == 0 then
                lua_thread.create(function()
                    wait(5000)
                    if #message == 0 then
                        if IsPlacingNotif == false and ShowDummyNotif == false then
                            IsNotifActive = false
                        end
                    end
                end)
            end
        end
    end
    
    if not Settings.Visible.Main.v then
        imgui.ShowCursor = false
        HasHelperRosterLoaded = false
        HasHelperStatsLoaded = false
    end
    if not Settings.Visible.SelectedWindow.v then
        SelectedSettings.Tab = 0
        Settings.Visible.SelectedWindow = imgui.ImBool(false)
        HasHelperRosterLoaded = false
        HasHelperStatsLoaded = false
    end
    if Settings.Visible.Main.v then
        if SelectedSettings.Tab == 0 then
            imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
            imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
            local MainWindowOpen = imgui.Begin(u8("Helper Kit Advanced | Kami"), Settings.Visible.Main, imgui.WindowFlags.NoResize)
            if MainWindowOpen then
                imgui.BeginChild("Sidebar", imgui.ImVec2(110, 550), true)
                local textWidth = imgui.CalcTextSize('List').x
                imgui.SetCursorPosX((100) / 2 - textWidth / 2)
                imgui.Text(u8("List"))

                if UserSettings.ShowTabs.Definitions then
                    imgui.Separator()
                    if imgui.Selectable(ti.ICON_BOOK, SelectedSettings.Tab == 1, imgui.ImGuiSelectableFlags_DontClosePopups) then
                        SelectedSettings.Tab = 1
                        Settings.Visible.SelectedWindow = imgui.ImBool(true)
                    end imgui.SameLine(0, 0) imgui.Text(" Definitions")
                end 

                if UserSettings.ShowTabs.Locations then
                    if imgui.Selectable(ti.ICON_MAP_PIN, SelectedSettings.Tab == 2, imgui.ImGuiSelectableFlags_DontClosePopups) then
                        SelectedSettings.Tab = 2
                        Settings.Visible.SelectedWindow = imgui.ImBool(true)
                    end imgui.SameLine(0, 0) imgui.Text(" Locations")
                end 

                if UserSettings.ShowTabs.Level1s then               
                    imgui.Separator()
                    if imgui.Selectable(ti.ICON_USER_EXCLAMATION, SelectedSettings.Tab == 3, imgui.ImGuiSelectableFlags_DontClosePopups) then
                        SelectedSettings.Tab = 3
                        Settings.Visible.SelectedWindow = imgui.ImBool(true)
                    end imgui.SameLine(0, 0) imgui.Text(" Level1s")
                end 

                if UserSettings.ShowTabs.HelpRequests then
                    if imgui.Selectable(ti.ICON_MAILBOX, SelectedSettings.Tab == 4, imgui.ImGuiSelectableFlags_DontClosePopups) then
                        SelectedSettings.Tab = 4
                        Settings.Visible.SelectedWindow = imgui.ImBool(true)
                    end imgui.SameLine(0, 0) imgui.Text(" Help Requests")
                end 

                if UserSettings.ShowTabs.ServerTour then
                    imgui.Separator()
                    if imgui.Selectable(ti.ICON_MAP_2, SelectedSettings.Tab == 5, imgui.ImGuiSelectableFlags_DontClosePopups) then
                        SelectedSettings.Tab = 5
                        Settings.Visible.SelectedWindow = imgui.ImBool(true)
                    end imgui.SameLine(0, 0) imgui.Text(" Server Tour")
                end 

                if UserSettings.ShowTabs.HelperRoster then
                    if imgui.Selectable(ti.ICON_ARTBOARD, SelectedSettings.Tab == 6, imgui.ImGuiSelectableFlags_DontClosePopups) then
                        SelectedSettings.Tab = 6
                        Settings.Visible.SelectedWindow = imgui.ImBool(true)
                        HasHelperRosterLoaded = true
                        if not HasHelperStatsLoaded then
                            sampSendChat("/helpers")
                            UpdateOnlineHelpers()
                            HasHelperStatsLoaded = true
                        end
                    end imgui.SameLine(0, 0) imgui.Text(" Helper Roster")
                end 

                local PlayerName = getPlayerNameSafe()

                for i, v in pairs(adminSettings.AdminsList) do
                    if v == PlayerName then
                        imgui.Separator()
                        adminSettings.Authenticated = true
                        if imgui.Selectable(ti.ICON_CROWN, SelectedSettings.Tab == 7, imgui.ImGuiSelectableFlags_DontClosePopups) then
                            SelectedSettings.Tab = 7
                            Settings.Visible.SelectedWindow = imgui.ImBool(true)
                        end imgui.SameLine(0, 0) imgui.Text(" Admin")
                        break
                    end
                end

                if UserSettings.ShowTabs.LvlCalculator then
                    imgui.Separator()
                    if imgui.Selectable(ti.ICON_CALCULATOR, SelectedSettings.Tab == 8, imgui.ImGuiSelectableFlags_DontClosePopups) then
                        SelectedSettings.Tab = 8
                        Settings.Visible.SelectedWindow = imgui.ImBool(true)
                    end imgui.SameLine(0, 0) imgui.Text(" Lvl Calculator")
                end 

                imgui.Separator()
    
                if imgui.Selectable(ti.ICON_SETTINGS_AUTOMATION, SelectedSettings.Tab == 9, imgui.ImGuiSelectableFlags_DontClosePopups) then
                    SelectedSettings.Tab = 9
                    Settings.Visible.SelectedWindow = imgui.ImBool(true)
                end imgui.SameLine(0, 0) imgui.Text(" Configurations")
    
                imgui.EndChild()
    
                imgui.SameLine()
                local windowSize = imgui.GetWindowSize()
    
                imgui.BeginChild("Information", imgui.ImVec2(0, 100), true)
                imgui.Text(u8("Found a Bug? Have a concern?\n\nReach out to my discord")) if imgui.Button("@cjkamii##") then end imgui.SameLine(0,0) 

                if imgui.Button("Update##") and not updateInProgress then 
                    updateInProgress = true
                    local update_available, version_or_error, changelog = checkUpdate()
                    
                    if type(version_or_error) == "string" then
                        updateMessage = "Error: "..version_or_error
                    elseif update_available then
                        updateMessage = "Update to v"..version_or_error.." available!"
                    else
                        local remote_version = version_or_error
                        if remote_version == CURRENT_VERSION then
                            updateMessage = "You have the latest version (v"..CURRENT_VERSION..")"
                        else
                            updateMessage = "No updates available"
                        end
                    end
                end

                if updateInProgress and updateMessage ~= "" then
                    imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                    imgui.SetNextWindowSize(imgui.ImVec2(windowWidth * 0.45, windowHeight * 0.125), imgui.Cond.FirstUseEver)
                    imgui.Begin("Update Status", true, 
                        imgui.WindowFlags.NoResize + 
                        imgui.WindowFlags.NoTitleBar + 
                        imgui.WindowFlags.NoCollapse + 
                        imgui.WindowFlags.NoMove)

                    imgui.TextWrapped(u8(updateMessage))
                    imgui.Spacing()

                    if imgui.Button("OK##UpdateStatus", imgui.ImVec2(60, 20)) then
                        updateInProgress = false
                        updateMessage = ""
                    end

                    if updateMessage:find("available!") then
                        imgui.SameLine()
                        if imgui.Button("Install Now##UpdateConfirm", imgui.ImVec2(60, 20)) then
                            imgui.ShowCursor = false
                            local update_available, version_or_error, changelog = checkUpdate()
                            performUpdate(version_or_error, changelog)
                            updateInProgress = false
                            updateMessage = ""
                        end
                    end

                    imgui.End()
                end
                imgui.EndChild()
    
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.25, windowSize.y * 0.225))
                local versionPath = "moonloader\\config\\helper-kit\\version.txt"
                local changelogText = readChangelogOnly(versionPath)
                            
                imgui.BeginChild("Version Changelogs", imgui.ImVec2(imgui.GetContentRegionAvail().x, windowSize.y * 0.54), true)
                            
                imgui.Text(u8("Changelog:"))
                if changelogText and changelogText ~= "" then
                    for line in changelogText:gmatch("[^\r\n]+") do
                        imgui.TextColored(rgbToImVec4(r, g, b, 1), u8(line))
                    end
                else
                    imgui.TextWrapped("There's no new update to check for changelogs")
                end
                
                imgui.EndChild()
                

    
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.25, windowSize.y * 0.78))
                imgui.BeginChild("NewbPanel", imgui.ImVec2(imgui.GetContentRegionAvail().x, windowSize.y * 0.175), true)
                imgui.Text(u8("Newb:"))
                imgui.SameLine()
                imgui.InputText(u8("##newb_input"), newbinput)
                imgui.SameLine()
                if imgui.Button(u8("Send")) then
                    sampSendChat("/newb " .. newbinput.v)
                    newbinput.v = ""
                end
                imgui.Text(u8("Helper Chat:"))
                imgui.SameLine()
                imgui.InputText(u8("##helperchat_input"), hcinput)
                imgui.SameLine()
                if imgui.Button(u8("Chat")) then
                    sampSendChat("/hc " .. hcinput.v)
                    hcinput.v = ""
                end
                imgui.Text('Discord: cjkamii/Kami#7661')
                imgui.EndChild()
            end
            imgui.End()
        end 
            if SelectedSettings.Tab == 1 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Definition", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
                imgui.BeginChild("SidebarPanel", imgui.ImVec2(100, 0), true)
                if imgui.Selectable(ti.ICON_SETTINGS, true, imgui.ImGuiSelectableFlags_DontClosePopups) then
                end imgui.SameLine(0, 0) imgui.Text(" Settings")
                imgui.EndChild()
                imgui.SameLine()
                local windowSize = imgui.GetWindowSize()
    
                imgui.BeginChild("Information", imgui.ImVec2(0, 100), true)
                imgui.Text(u8("Usage:")) imgui.NewLine()
                imgui.Separator()
                imgui.Text(u8("CMD: /def DEFINITION ")) imgui.SameLine(0,0) imgui.TextColored(imgui.ImVec4(0.5, 0.5, 1.0, 1.0), "-> displays information.")
                imgui.Separator()
                imgui.EndChild()
    
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.26))
                imgui.Text(u8("Search:"))
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.29))
                imgui.InputText(u8("##search"), searchQuery, imgui.ImVec2(0, 0))
                local query = searchQuery.v:lower()
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.33))
                imgui.BeginChild("DefinitionPanel", imgui.ImVec2(0, windowHeight * 0.6), true)
                for _, entry in pairs(dict) do
                    if type(entry) == 'table' and type(entry.keywords) == 'table' then
                        local keywordsMatch = false
                        local first = true
                        desc = ""
                    
                        for k, v in pairs(entry) do
                            if k ~= "keywords" then
                                if not first then
                                    desc = desc .. ' | '
                                end
                                desc = desc .. k .. ': ' .. v
                                first = false
                            end
                        end
                    
                        local descMatch = query == "" or desc:lower():find(query)
                        for _, val in ipairs(entry.keywords) do
                            if query == "" or val:lower():find(query) then
                                keywordsMatch = true
                                break
                            end
                        end
                    
                        if keywordsMatch or descMatch then
                            for _, val in ipairs(entry.keywords) do
                                if imgui.Selectable(val, SelectedSettings.Dictionary == val, imgui.ImGuiSelectableFlags_DontClosePopups) then
                                    SelectedSettings.Dictionary = val
                                    SelectedSettings.Keyword = desc
                                    
                                    IsSelectedDict = true
                                end
                            end
                        
                            imgui.Separator()
                        end
                    end
                end
    
                if IsSelectedDict and SelectedSettings.Dictionary ~= "" then
                    imgui.SetNextWindowPos(imgui.ImVec2((width / 2) + (width / 3), height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                    imgui.SetNextWindowSize(imgui.ImVec2(windowWidth * 0.8, 0), imgui.Cond.FirstUseEver)
                    imgui.Begin(SelectedSettings.Dictionary .. " | Definition", IsSelectedDict, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove)
                    imgui.Text(u8("Selected Dictionary: ")) imgui.SameLine(0, 0) imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), (SelectedSettings.Dictionary or ""))
                    local tempText = SelectedSettings.Keyword 
                
                    if #tempText > 0 then
                        imgui.TextWrapped(u8(tempText))
                    end
                    imgui.End()
                end
    
                imgui.EndChild()
                imgui.End()
            elseif SelectedSettings.Tab == 2 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Location", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
                imgui.BeginChild("SidebarPanel", imgui.ImVec2(100, 0), true)
                if imgui.Selectable(ti.ICON_SETTINGS, true, imgui.ImGuiSelectableFlags_DontClosePopups) then
                end imgui.SameLine(0, 0) imgui.Text(" Settings")
                imgui.EndChild()
                imgui.SameLine()
                local windowSize = imgui.GetWindowSize()
    
                imgui.BeginChild("Information", imgui.ImVec2(0, 100), true)
                imgui.Text(u8("Usage:")) imgui.NewLine()
                imgui.Separator()
                imgui.Text(u8("CMD: /loc LOCATION ")) imgui.SameLine(0,0) imgui.TextColored(imgui.ImVec4(0.5, 0.5, 1.0, 1.0), "-> Spawns checkpoint on the Location.")
                imgui.Separator()
                imgui.EndChild()
    
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.26))
                imgui.Text(u8("Search:"))
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.29))
                imgui.InputText(u8("##search"), searchQuery, imgui.ImVec2(0, 0))
                local query = searchQuery.v:lower()
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.33))
                imgui.BeginChild("LocationPanel", imgui.ImVec2(0, windowHeight * 0.55), true)
                for index, entry in pairs(locations) do
                    if type(entry) == 'table' and type(entry.keywords) == 'table' then
                        for _, val in ipairs(entry.keywords) do
                            if query == "" or val:lower():find(query) then
                                local textWidth = imgui.CalcTextSize('Locate').x
                                imgui.SetCursorPosX((windowWidth - 150) / 2 - textWidth / 2)
                                imgui.NewLine()
                            
                                if imgui.Selectable(val, SelectedSettings.Location == val, imgui.SelectableFlags.DontClosePopups) then
                                    SelectedSettings.Location = val
                                end
                            
                                imgui.Separator()
                            end
                        end
                    end
                end
                imgui.EndChild()
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.92))
                imgui.Text(u8("Selected Location: ")) imgui.SameLine(0, 0) imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), (SelectedSettings.Location or ""))
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.95))
                if imgui.Button(u8"Locate##") then
                    lua_thread.create(function()
                        cmdLoc(SelectedSettings.Location)
                        wait(1000)
                    end)
                end
                imgui.End()
            elseif SelectedSettings.Tab == 3 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Level 1 Players", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
                local lvl1s = {}
                for id = 0, sampGetMaxPlayerId(false), 1 do
                    if sampIsPlayerConnected(id) then
                        if sampGetPlayerScore(id) == 1 then
                            if string.find(sampGetPlayerNickname(id), '_') then
                                table.insert(lvl1s, id)
                            end
                        end
                    end
                end     
                if #lvl1s == 0 then
                    local textWidth = imgui.CalcTextSize('No level 1 player is online, but this may be a mistake. Try pressing TAB and waiting a few moments.').x
                    imgui.SetCursorPosX((windowWidth) / 2 - textWidth / 2)
                    imgui.Text('No level 1 player is online, but this may be a mistake. Try pressing TAB and waiting a few moments.')
                    imgui.NewLine()
                    return
                end
                local textWidth = imgui.CalcTextSize('Level 1 Players Online:').x
                imgui.SetCursorPosX((windowWidth) / 2 - textWidth / 2)
                imgui.Text('Level 1 Players Online:')
                imgui.NewLine()
                imgui.BeginChild("Location Bar", imgui.ImVec2(0, windowHeight - 200), true)
                local final = {}
                local team = {}
                local r = 1
                for i, id in pairs(lvl1s) do
                    if r == 4 then
                        r = 1
                        table.insert(final, team)
                        team = {}
                    end
                    table.insert(team, string.format('(%i) %s', id, string.gsub(sampGetPlayerNickname(id), '_', ' ')))
                    r = r + 1
                end
                for i, team in pairs(final) do
                    local textWidth = imgui.CalcTextSize(table.concat(team, " | ")).x
                    imgui.SetCursorPosX((windowWidth) / 2 - textWidth / 2)
                    imgui.Text(table.concat(team, " | "))
                    imgui.NewLine()
                end
                imgui.EndChild()
                imgui.End()
            elseif SelectedSettings.Tab == 4 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Help Requests", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
                if not next(helpRequests) then
                    imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), "There's no active help requests right now.")
                else
                    imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), "Active Help Requests:")  
                end
                imgui.BeginChild("Helprequests", imgui.ImVec2(0, windowHeight * 0.8), true)

                if next(helpRequests) then
                    for key, entry in pairs(helpRequests) do
                        local text = string.format("%s (ID: %s):", entry.name, entry.id)
                    
                        local isSelected = (SelectedSettings.HelprequestID == entry.id)
                        if imgui.Selectable(u8(text .. "\n" .. entry.message), isSelected, imgui.ImGuiSelectableFlags_DontClosePopups) then
                            SelectedSettings.HelprequestID = entry.id
                            SelectedSettings.HelprequestName = entry.name
                        end
                    
                        imgui.Separator()
                    end
                end

                imgui.EndChild()

                if SelectedSettings.HelprequestID then
                    if imgui.Button(u8("Accept")) then 
                        sampSendChat("/accepthelp " .. SelectedSettings.HelprequestID) 
                    end
                    imgui.SameLine()
                    if imgui.Button(u8("Trash")) then 
                        sampSendChat("/trashhelp " .. SelectedSettings.HelprequestID) 
                    end
                    imgui.SameLine()
                    if imgui.Button(u8("Notify")) then 
                        sampSendChat("/hc HRS: [/ahr] " .. SelectedSettings.HelprequestName .. "(ID: " .. SelectedSettings.HelprequestID .. ")") 
                    end
                end
                imgui.End()
            elseif SelectedSettings.Tab == 5 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Server Tour", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
                imgui.BeginChild("SidebarPanel", imgui.ImVec2(100, 0), true)
                if imgui.Selectable(ti.ICON_SETTINGS, true, imgui.ImGuiSelectableFlags_DontClosePopups) then
                end imgui.SameLine(0, 0) imgui.Text(" Settings")
                imgui.EndChild()
                imgui.SameLine()
                local windowSize = imgui.GetWindowSize()
    
                imgui.BeginChild("Information", imgui.ImVec2(0, 100), true)
                imgui.Text(u8("Usage:")) imgui.NewLine()
                imgui.Separator()
                imgui.Text(u8("CMD: [/sst] ")) imgui.SameLine(0,0) imgui.TextColored(imgui.ImVec4(0.5, 0.5, 1.0, 1.0), "-> Starts the server tour.")
                imgui.Text(u8("CMD: [/est] ")) imgui.SameLine(0,0) imgui.TextColored(imgui.ImVec4(0.5, 0.5, 1.0, 1.0), "-> Exits the server tour.")
                imgui.Separator()
                imgui.EndChild()
    
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.26))
                imgui.BeginChild("ServerTourPanel", imgui.ImVec2(0, height * 0.5), true)
                
                for Locations, Description in pairs(ServerTour.Locations) do
                    imgui.TextColored(rgbToImVec4(r, g, b, 1), Description.name)
                    imgui.TextWrapped(u8(Description.desc))
                    imgui.Separator()
                end
                imgui.EndChild()
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.91))
                if imgui.Button(u8("Start Server Tour##")) then
                    startServerTour()
                end
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.95))
                if imgui.Button(u8("Exit Server Tour##")) then
                    exitServerTour()
                end
    
                imgui.End()

            elseif SelectedSettings.Tab == 6 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Helper Roster", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                    HasHelperRosterLoaded = false
                    HasHelperStatsLoaded = false
                end
                imgui.TextColored(rgbToImVec4(r, g, b, 1), "Helper Roster") imgui.SameLine(0, 0) 
                local buttonWidth = imgui.CalcTextSize("Refresh").x - 10
                local avail = imgui.GetContentRegionAvail().x
                
                imgui.SetCursorPosX(avail + buttonWidth)
                if imgui.Button("Refresh##") then
                    lua_thread.create(function()
                        addNotification("Fetching helper roster from forum...", "Info", UserSettings.Configurations.Notifications.DefaultDuration)
                        HasHelperRosterLoaded = false
                        local cookies, helperListOrError = authenticateForum()
                        if helperListOrError and type(helperListOrError) == "table" then
                            HasHelperRosterLoaded = true
                            HasHelperStatsLoaded = true
                            sampSendChat("/helpers")
                            UpdateOnlineHelpers()
                            updateSortedRoster()
                            addNotification("Helper roster refreshed successfully!", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                        else
                            addNotification("Failed to refresh helper roster. " .. tostring(helperListOrError), "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                        end
                    end)
                end
                imgui.BeginChild("HelperRoster", imgui.ImVec2(0, 0), true)
                
                if HasHelperRosterLoaded then
                    local playerName = getPlayerNameSafe()
                    if playerName ~= LastPlayerName then
                        updateSortedRoster()
                    end
                
                    local executiveRoles = {
                        ["Director"] = true,
                        ["Assistant Director"] = true,
                        ["Helper Manager"] = true,
                        ["Q&A Moderator"] = true
                    }
                
                    local nonExecutivesRoles = {
                        ["Head Helper"] = true,
                        ["Senior Helper"] = true,
                        ["Junior Helper"] = true
                    }
                
                    for _, roster in ipairs(CachedSortedRoster) do
                        local showRole = false
                
                        if executiveRoles[HelperRole] then
                            showRole = true
                        elseif nonExecutivesRoles[roster.role] then
                            showRole = true
                        end
                
                        if showRole then
                            local OnlineCount = 0
                            for _, helperData in ipairs(roster.members) do
                                if OnlineHelpers[helperData.name] then
                                    OnlineCount = OnlineCount + 1
                                end
                            end
                
                            imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), roster.role .. " (" .. roster.count .. ")")
                            if (OnlineCount > 0) then
                                imgui.SameLine(0, 0)
                                imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), " | ")
                                imgui.SameLine(0, 0)
                                imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), "Online: ")
                                imgui.SameLine(0, 0)
                                imgui.TextColored(imgui.ImVec4(0.0, 1.0, 0.0, 1.0), tostring(OnlineCount))
                            end
                
                            for _, helperData in ipairs(roster.members) do
                                local helperName = helperData.name
                                local helperStats = helperData.stats
                                local isYou = (helperName == playerName)
                                local isOnline = OnlineHelpers[helperName] ~= nil
                                local isDirector = roster.role == "Director" or roster.role == "Assistant Director"
                
                                if isYou then
                                    imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), helperName)
                                    imgui.SameLine(0, 0)
                                    if helperStats then imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), " " .. helperStats) end
                                    imgui.SameLine(0, 0)
                                    imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), " (You)")
                                elseif isOnline then
                                    imgui.TextColored(isDirector and imgui.ImVec4(1.0, 0.0, 0.0, 1.0) or imgui.ImVec4(0.0, 1.0, 0.0, 1.0), helperName)
                                    imgui.SameLine(0, 0)
                                    if helperStats then imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), " " .. helperStats) end
                                    if (not helperStats or helperStats == "") and not (roster.role == "Q&A Moderator" or roster.role == "Helper Manager" or isDirector) then
                                        imgui.SameLine(0, 0)
                                        imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), " (Suspended)")
                                    end
                                else
                                    imgui.TextColored(imgui.ImVec4(0.6, 0.5, 0.5, 1.0), helperName)
                                end
                            end
                
                            imgui.Separator()
                            imgui.Spacing()
                        end
                    end
                end
                
                imgui.EndChild()                      
                imgui.End()

            elseif SelectedSettings.Tab == 7 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Administrator", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
                
                imgui.BeginChild("SidebarPanel", imgui.ImVec2(100, 0), true)
                if imgui.Selectable(ti.ICON_CLIPBOARD_LIST, adminSettings.SelectedTab == "Whitelist", imgui.ImGuiSelectableFlags_DontClosePopups) then
                    adminSettings.SelectedTab = "Whitelist"
                end
                imgui.SameLine(0, 0)
                imgui.Text(" Whitelist")
                
                if imgui.Selectable(ti.ICON_BOOK, adminSettings.SelectedTab == "Definition", imgui.ImGuiSelectableFlags_DontClosePopups) then
                    adminSettings.SelectedTab = "Definition"
                end
                imgui.SameLine(0, 0)
                imgui.Text(" Definition")
                
                if imgui.Selectable(ti.ICON_MAP_PIN, adminSettings.SelectedTab == "Location", imgui.ImGuiSelectableFlags_DontClosePopups) then
                    adminSettings.SelectedTab = "Location"
                end
                imgui.SameLine(0, 0)
                imgui.Text(" Location")
                
                if imgui.Selectable(ti.ICON_MAP_2, adminSettings.SelectedTab == "Tour", imgui.ImGuiSelectableFlags_DontClosePopups) then
                    adminSettings.SelectedTab = "Tour"
                end
                imgui.SameLine(0, 0)
                imgui.Text(" Tour")
                imgui.EndChild()
                
                imgui.SameLine()
                
                imgui.BeginChild("AdminPanel", imgui.ImVec2(0, height * 0.5), true)
                
                if adminSettings.SelectedTab == "Whitelist" then
                    local success, err = pcall(function()
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Whitelist Management")
                
                        imgui.Text("Add New Helper:")
                        imgui.InputText(u8("Name##helper"), adminSettings.Inputs.HelperName)
                
                        if #adminSettings.helperRoleOrder > 0 then
                            local roleChanged, newRole = imgui.Combo(u8("Role##helper"), adminSettings.Inputs.HelperRole, adminSettings.helperRoleOrder)
                            if adminSettings.Inputs.HelperRole.v < 1 then
                                adminSettings.Inputs.HelperRole.v = 1
                            elseif adminSettings.Inputs.HelperRole.v > #adminSettings.helperRoleOrder then
                                adminSettings.Inputs.HelperRole.v = #adminSettings.helperRoleOrder
                            end
                        else
                            imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), "No roles configured!")
                        end
                
                        if imgui.Button("Add to Whitelist##") then
                            local helperName = tostring(adminSettings.Inputs.HelperName.v)
                            if helperName and helperName ~= "" then
                                if adminSettings.Inputs.HelperRole.i and adminSettings.Inputs.HelperRole.i >= 1 and adminSettings.Inputs.HelperRole.i <= #adminSettings.helperRoleOrder then
                                    local selectedRole = adminSettings.helperRoleOrder[adminSettings.Inputs.HelperRole.i]
                
                                    if not HelperRoster[selectedRole] then
                                        HelperRoster[selectedRole] = {members = {}, count = 0, role = selectedRole}
                                    end
                
                                    local exists = false
                                    for _, data in ipairs(HelperRoster[selectedRole].members) do
                                        if data.name:lower() == helperName:lower() then
                                            exists = true
                                            break
                                        end
                                    end
                
                                    if not exists then
                                        table.insert(HelperRoster[selectedRole].members, {name = helperName, stats = ""})
                                        HelperRoster[selectedRole].count = #HelperRoster[selectedRole].members
                                        addNotification("Added "..helperName.." as "..selectedRole, "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                                        adminSettings.Inputs.HelperName.v = ""
                                    else
                                        addNotification(helperName.." already exists in "..selectedRole, "Warning", UserSettings.Configurations.Notifications.DefaultDuration)
                                    end
                                else
                                    addNotification("Invalid role selected", "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                                end
                            else
                                addNotification("Please enter a name", "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                            end
                        end
                
                        imgui.Separator()
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Current Whitelist")
                
                        if imgui.BeginChild("WhitelistView", imgui.ImVec2(0, imgui.GetContentRegionAvail().y * 0.7), true) then
                            local roleOrder = {
                                "Director", "Assistant Director", "Helper Manager",
                                "Q&A Moderator", "Head Helper", "Senior Helper", "Junior Helper"
                            }
                
                            local toRemove = {}
                
                            for _, roleName in ipairs(roleOrder) do
                                for _, roster in pairs(HelperRoster) do
                                    if roster.role == roleName and #roster.members > 0 then
                                        imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), roster.role .. " (" .. roster.count .. ")")
                
                                        for i, helperData in ipairs(roster.members) do
                                            local helperName = helperData.name
                
                                            if roster.role == "Director" or roster.role == "Assistant Director" then
                                                imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), helperName)
                                            else
                                                imgui.Text(u8(helperName))
                                            end
                
                                            imgui.SameLine(imgui.GetWindowWidth() - 100)
                                            imgui.PushID("Remove"..roleName..i)
                                            if imgui.SmallButton("Remove") then
                                                toRemove[roster.role] = toRemove[roster.role] or {}
                                                table.insert(toRemove[roster.role], i)
                                                addNotification("Scheduled removal of "..helperName, "Info", UserSettings.Configurations.Notifications.DefaultDuration)
                                            end
                                            imgui.PopID()
                                        end
                
                                        imgui.Separator()
                                        imgui.Spacing()
                                    end
                                end
                            end

                            for roleName, indices in pairs(toRemove) do
                                for _, roster in pairs(HelperRoster) do
                                    if roster.role == roleName then
                                        table.sort(indices, function(a, b) return a > b end)
                                        for _, i in ipairs(indices) do
                                            local removedData = table.remove(roster.members, i)
                                            roster.count = #roster.members
                                            addNotification("Removed "..removedData.name, "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                                        end
                                        break
                                    end
                                end
                            end
                
                            local hasMembers = false
                            for _, roster in pairs(HelperRoster) do
                                if roster.members and #roster.members > 0 then
                                    hasMembers = true
                                    break
                                end
                            end
                
                            if not hasMembers then
                                imgui.TextColored(imgui.ImVec4(0.5, 0.5, 0.5, 1.0), "Whitelist is currently empty")
                            end
                
                            imgui.EndChild()
                        end
                
                        imgui.Spacing()
                
                        if imgui.Button("Refresh from Forum##") then
                            lua_thread.create(function()
                                addNotification("Fetching whitelist from forum...", "Info", UserSettings.Configurations.Notifications.DefaultDuration)
                                local cookies, helperList = authenticateForum()
                                if helperList then
                                    for role, data in pairs(helperList) do
                                        if not HelperRoster[role] then
                                            HelperRoster[role] = {members = {}, count = 0, role = role}
                                        end
                                        for _, name in ipairs(data.members) do
                                            local exists = false
                                            for _, existingData in ipairs(HelperRoster[role].members) do
                                                if existingData.name:lower() == name:lower() then
                                                    exists = true
                                                    break
                                                end
                                            end
                                            if not exists then
                                                table.insert(HelperRoster[role].members, {name = name, stats = ""})
                                            end
                                        end
                                        HelperRoster[role].count = #HelperRoster[role].members
                                    end
                                    addNotification("Whitelist refreshed from forum", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                                else
                                    addNotification("Failed to refresh whitelist", "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                                end
                            end)
                        end
                
                        imgui.SameLine()
                
                        if imgui.Button("Save Whitelist##") then
                            addNotification("Whitelist saved to file", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                        end
                    end)
                
                    if not success then
                        imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), "Error in whitelist section:")
                        imgui.TextWrapped(tostring(err))
                        imgui.Text("Please report this error to the developer")
                    end
                elseif adminSettings.SelectedTab == "Definition" then
                    local success, err = pcall(function()
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Definition Management")
                        
                        imgui.Text("Add New Definition:")
                        
                        imgui.InputText("Keyword##newdef", adminSettings.Inputs.Keyword)
                        imgui.InputText("Definition##newdef", adminSettings.Inputs.Definition)
                        
                        if imgui.Button("Add Definition") then
                            local keyword = tostring(adminSettings.Inputs.Keyword.v)
                            local definition = tostring(adminSettings.Inputs.Definition.v)
                            
                            if keyword ~= "" and definition ~= "" then
                                local success_add, err_add = pcall(function()
                                    table.insert(dict, {
                                        keywords = {keyword},
                                        definition = definition
                                    })
                                    
                                    local file, err_file = io.open(dictPath, "w")
                                    if file then
                                        local success_write, err_write = pcall(function()
                                            file:write(encodeJson(dict))
                                            file:close()
                                            addNotification("Definition added", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                                            adminSettings.Inputs.Keyword.v = ""
                                            adminSettings.Inputs.Definition.v = ""
                                        end)
                                        if not success_write then
                                            addNotification("Write error: "..tostring(err_write), "Error", 3)
                                        end
                                    else
                                        addNotification("File error: "..tostring(err_file), "Error", 3)
                                    end
                                end)
                                
                                if not success_add then
                                    addNotification("Add error: "..tostring(err_add), "Error", 3)
                                end
                            else
                                addNotification("Please enter both keyword and definition", "Error", 3)
                            end
                            pcall(refreshconfigspath)
                        end
                        
                        imgui.Separator()
                        
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Current Definitions")
                        if imgui.BeginChild("DefinitionList", imgui.ImVec2(0, height * 0.3), true) then
                            for i, entry in ipairs(dict) do
                                if entry.keywords and #entry.keywords > 0 then
                                    imgui.Text(entry.keywords[1])
                                    imgui.SameLine(imgui.GetWindowWidth() - 100)
                                    if imgui.SmallButton("Remove##def"..i) then
                                        local success_remove, err_remove = pcall(function()
                                            table.remove(dict, i)
                                            
                                            local file, err_file = io.open(dictPath, "w")
                                            if file then
                                                local success_write = pcall(function()
                                                    file:write(encodeJson(dict))
                                                    file:close()
                                                    addNotification("Definition removed", "Success", 3)
                                                end)
                                                if not success_write then
                                                    addNotification("Write failed", "Error", 3)
                                                end
                                            else
                                                addNotification("File error: "..tostring(err_file), "Error", 3)
                                            end
                                        end)
                                        if not success_remove then
                                            addNotification("Remove error: "..tostring(err_remove), "Error", 3)
                                        end
                                    end
                                    
                                    imgui.Separator()
                                end
                            end
                            imgui.EndChild()
                        end
                    end)
                    if not success then
                        addNotification("Definition tab error: "..tostring(err), "Error", 3)
                    end
                
                elseif adminSettings.SelectedTab == "Location" then
                    local success, err = pcall(function()
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Location Management")
                        
                        imgui.Text("Add New Location:")
                        local newLocName = imgui.ImBuffer(256)
                        
                        imgui.InputText("Location Name##newloc", newLocName)
                        
                        if imgui.Button("Add Current Position") then
                            local locName = tostring(newLocName.v)
                            if locName ~= "" then
                                local success_pos, err_pos = pcall(function()
                                    local result, ped = getPlayerChar(PLAYER_HANDLE)
                                    if result then
                                        local x, y, z = getCharCoordinates(ped)
                                        
                                        table.insert(locations, {
                                            keywords = {locName},
                                            X = x,
                                            Y = y,
                                            Z = z
                                        })
                                        
                                        local file, err_file = io.open(locationsPath, "w")
                                        if file then
                                            local success_write = pcall(function()
                                                file:write(encodeJson(locations))
                                                file:close()
                                                addNotification("Location added", "Success", 3)
                                                newLocName.v = ""
                                            end)
                                            if not success_write then
                                                addNotification("Write failed", "Error", 3)
                                            end
                                        else
                                            addNotification("File error: "..tostring(err_file), "Error", 3)
                                        end
                                    end
                                end)
                                if not success_pos then
                                    addNotification("Position error: "..tostring(err_pos), "Error", 3)
                                end
                            else
                                addNotification("Please enter a location name", "Error", 3)
                            end
                            pcall(refreshconfigspath)
                        end
                        
                        imgui.Separator()
                        
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Current Locations")
                        if imgui.BeginChild("LocationList", imgui.ImVec2(0, height * 0.3), true) then
                            for i, entry in ipairs(locations) do
                                if entry.keywords and #entry.keywords > 0 then
                                    imgui.Text(entry.keywords[1])
                                    imgui.SameLine(imgui.GetWindowWidth() - 100)
                                    if imgui.SmallButton("Remove##loc"..i) then
                                        local success_remove = pcall(function()
                                            table.remove(locations, i)
                                            
                                            local file, err_file = io.open(locationsPath, "w")
                                            if file then
                                                local success_write = pcall(function()
                                                    file:write(encodeJson(locations))
                                                    file:close()
                                                    addNotification("Location removed", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                                                end)
                                                if not success_write then
                                                    addNotification("Write failed", "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                                                end
                                            else
                                                addNotification("File error: "..tostring(err_file), "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                                            end
                                        end)
                                        if not success_remove then
                                            addNotification("Remove error", "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                                        end
                                    end
                                    
                                    imgui.Separator()
                                end
                            end
                            imgui.EndChild()
                        end
                    end)
                    if not success then
                        addNotification("Location tab error: "..tostring(err), "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                    end
                
                elseif adminSettings.SelectedTab == "Tour" then
                    local success, err = pcall(function()
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Server Tour Management")
                        
                        imgui.Text("Tour Locations:")
                        
                        for i, location in ipairs(ServerTour.Locations) do
                            imgui.PushID("tourloc"..i)
                            
                            imgui.Text(string.format("%d. %s", i, location.name))
                            imgui.SameLine()
                            if imgui.SmallButton("Edit##editloc" .. i) then

                            end
                            imgui.SameLine()
                            if imgui.SmallButton("Remove##remloc" .. i) then
                                local success_remove = pcall(function()
                                    table.remove(ServerTour.Locations, i)
                                    addNotification("Tour location removed", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                                end)
                                if not success_remove then
                                    addNotification("Remove error", "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                                end
                            end
                            
                            imgui.PopID()
                        end
                        
                        if imgui.Button("Add Current Position") then
                            local success_add, err_add = pcall(function()
                                local result, ped = getPlayerChar(PLAYER_HANDLE)
                                if result then
                                    local x, y, z = getCharCoordinates(ped)
                                    local zone = getNameOfZone(x, y, z)
                                    
                                    table.insert(ServerTour.Locations, {
                                        name = zone,
                                        desc = "Description for "..zone
                                    })
                                    
                                    addNotification("Tour location added", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                                end
                            end)
                            if not success_add then
                                addNotification("Add error: "..tostring(err_add), "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                            end
                            pcall(refreshconfigspath)
                        end
                        
                        imgui.Separator()
                        
                        if imgui.Button("Save Tour Configuration") then
                            local success_save = pcall(function()
                                addNotification("Tour configuration saved", "Success", UserSettings.Configurations.Notifications.DefaultDuration)
                            end)
                            if not success_save then
                                addNotification("Save error", "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                            end
                        end
                    end)
                    if not success then
                        addNotification("Tour tab error: "..tostring(err), "Error", UserSettings.Configurations.Notifications.DefaultDuration)
                    end
                end
                
                imgui.EndChild()
                imgui.End()

            elseif SelectedSettings.Tab == 8 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Level Calculator", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
            
                imgui.BeginChild("SidebarPanel", imgui.ImVec2(100, 0), true)
                if imgui.Selectable(ti.ICON_CALCULATOR, true, imgui.ImGuiSelectableFlags_DontClosePopups) then 
                    SelectedSettings.Tab = 8
                end imgui.SameLine(0, 0) imgui.Text(" Settings")
                imgui.EndChild()
                imgui.SameLine()

                local windowSize = imgui.GetWindowSize()
            
                imgui.BeginChild("InfoPanel", imgui.ImVec2(0, 100), true)
                imgui.Text(u8("Usage:")) imgui.NewLine()
                imgui.Separator()
                imgui.Text(u8("/lvl <MinLvl> <MaxLvl>"))
                imgui.SameLine(0,0)
                imgui.TextColored(imgui.ImVec4(0.5, 0.5, 1.0, 1.0), " -> Calculate total RP and Cash required.")
                imgui.Separator()
                imgui.EndChild()
            
                local playerId = tonumber(LevelCalc.playerID.v or "")
                local playerName = "P"
                local CurrentLevel = ""
                if playerId and sampIsPlayerConnected(playerId) then
                    playerName = string.format("%s", sampGetPlayerNickname(playerId))
                    playerName = playerName:gsub("_", " ")
                    CurrentLevel = string.format("%d", sampGetPlayerScore(playerId))
                    LevelCalc.minLevel.v = tostring(sampGetPlayerScore(playerId))
                    imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.25, windowSize.y * 0.26))
                    imgui.TextColored(imgui.ImVec4(0.0, 1.0, 0.0, 1.0), playerName)
                else
                    imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.25, windowSize.y * 0.29))
                    imgui.TextColored(imgui.ImVec4(0.6, 0.5, 0.5, 1.0), "Enter the ID...")
                end
                
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.25, windowSize.y * 0.29))
                if playerId and sampIsPlayerConnected(playerId) then
                    imgui.Text("Level: ") imgui.SameLine(0, 0) imgui.TextColored(imgui.ImVec4(0.0, 1.0, 0.0, 1.0), CurrentLevel)
                end
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.25, windowSize.y * 0.32))
                imgui.PushItemWidth(80)
                imgui.InputText("##PlayerID", LevelCalc.playerID)
                imgui.PopItemWidth()
                
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.50, windowSize.y * 0.29))
                imgui.Text("Minimum Level:")
                imgui.PushItemWidth(80)
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.50, windowSize.y * 0.32))
                imgui.InputText("##MinLevel", LevelCalc.minLevel)
                imgui.PopItemWidth()
                
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.75, windowSize.y * 0.29))
                imgui.Text("Maximum Level:")
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.75, windowSize.y * 0.32))
                imgui.PushItemWidth(80)
                imgui.InputText("##MaxLevel", LevelCalc.maxLevel)
                imgui.PopItemWidth()
                      
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.37))
                imgui.BeginChild("LevelResult", imgui.ImVec2(0, windowHeight * 0.3), true)
                if LevelCalc.resultText and LevelCalc.resultText ~= "" then
                    imgui.TextWrapped(LevelCalc.resultText)
                else
                    imgui.Text("Result will be displayed here.")
                end
                imgui.EndChild()

                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.50, windowSize.y * 0.7))
                if imgui.Button("Calculate##DoLevelCalc") then
                    local playerId = tonumber(LevelCalc.playerID.v or "")
                    local isValidID = playerId and sampIsPlayerConnected(playerId)
                    local maxLvl = tonumber(LevelCalc.maxLevel.v or "")
                
                    local minLvl = isValidID and sampGetPlayerScore(playerId) or tonumber(LevelCalc.minLevel.v or "")
                
                    if isValidID and not maxLvl then
                        LevelCalc.resultText = "Please enter a valid maximum level."
                    elseif not minLvl or not maxLvl or minLvl < 1 or maxLvl < 1 then
                        LevelCalc.resultText = "Please enter valid level numbers greater than 0."
                    elseif minLvl == maxLvl then
                        LevelCalc.resultText = "Minimum and maximum level cannot be the same."
                    elseif maxLvl < minLvl then
                        LevelCalc.resultText = "Maximum level must be greater than minimum level."
                    else
                        local totalRP, totalCash = 0, 0
                        for i = minLvl + 1, maxLvl do
                            totalRP = totalRP + (i * 4)
                            totalCash = totalCash + (i * 2500)
                        end
                
                        if isValidID then
                            local playerName = sampGetPlayerNickname(playerId)
                            playerName = playerName:gsub("_", " ")
                            LevelCalc.resultText = string.format(
                                "Player: %s (ID:%d) | Current Level: %d\nFrom level %d to %d:\n- Respect Points: %s\n- Cash: $%s",
                                playerName, playerId, minLvl,
                                minLvl, maxLvl,
                                numWithCommas(totalRP),
                                numWithCommas(totalCash)
                            )
                        else
                            LevelCalc.resultText = string.format(
                                "From level %d to %d:\n- Respect Points: %s\n- Cash: $%s",
                                minLvl, maxLvl,
                                numWithCommas(totalRP),
                                numWithCommas(totalCash)
                            )
                        end
                    end                
                end  

                imgui.End()
                
            elseif SelectedSettings.Tab == 9 then
                imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.FirstUseEver)
                imgui.Begin("Helper Kit | Settings", Settings.Visible.SelectedWindow, imgui.WindowFlags.NoResize)
            
                if imgui.Button(u8("<< Back##")) then
                    SelectedSettings.Tab = 0
                    Settings.Visible.SelectedWindow = imgui.ImBool(false)
                end
            
                imgui.BeginChild("SidebarPanel", imgui.ImVec2(120, 0), true)
                if imgui.Selectable(ti.ICON_SETTINGS, true, imgui.ImGuiSelectableFlags_DontClosePopups) then 
                    SelectedSettings.Tab = 9
                end
                imgui.SameLine(0, 0)
                imgui.Text(" Settings")
                imgui.EndChild()
            
                imgui.SameLine()
                imgui.BeginChild("SettingsPanel", imgui.ImVec2(0, 0), true)
            
                imgui.Text("Visible Tabs")
                imgui.Separator()
                for tabName, enabled in pairs(UserSettings.ShowTabs) do
                    local boolRef = imgui.ImBool(enabled)
                    imgui.PushStyleColor(imgui.Col.Text, UserSettings.ShowTabs[tabName] and imgui.ImVec4(0, 1, 0, 1) or imgui.ImVec4(1, 0, 0, 1))
                    imgui.Text(ti.ICON_SQUARE_DOT)
                    imgui.PopStyleColor()
                    imgui.SameLine()
                    imgui.Text(tabName)
                    imgui.SameLine()
                    if imgui.Checkbox("##" .. tabName, boolRef) then
                        UserSettings.ShowTabs[tabName] = boolRef.v
                    end
                end                
            
                imgui.Spacing()
                imgui.Text("Notifications")
                imgui.Separator()

                local notifs = UserSettings.Configurations.Notifications
                local showNotifs = imgui.ImBool(notifs.Show)
                local soundNotifs = imgui.ImBool(notifs.Sound)
                local msgNotifs = imgui.ImBool(notifs.Messages)

                imgui.PushStyleColor(imgui.Col.Text, notifs.Show and imgui.ImVec4(0, 1, 0, 1) or imgui.ImVec4(1, 0, 0, 1))
                imgui.Text(ti.ICON_SQUARE_DOT)
                imgui.PopStyleColor()
                imgui.SameLine()
                imgui.Text("Enable:")
                imgui.SameLine()
                if imgui.Checkbox("##EnableNotifs", showNotifs) then
                    notifs.Show = showNotifs.v
                end

                if notifs.Show then
                    imgui.SameLine()

                    imgui.SameLine(imgui.GetWindowWidth() - 70)
                    if imgui.Button("Position") then
                        IsPlacingNotif = true
                        ShowDummyNotif = true
                        IsNotifActive = true
                    end

                    imgui.PushStyleColor(imgui.Col.Text, notifs.Sound and imgui.ImVec4(0, 1, 0, 1) or imgui.ImVec4(1, 0, 0, 1))
                    imgui.Text(ti.ICON_SQUARE_DOT)
                    imgui.PopStyleColor()
                    imgui.SameLine()
                    imgui.Text("Sound:")
                    imgui.SameLine()
                    if imgui.Checkbox("##Sound", soundNotifs) then
                        notifs.Sound = soundNotifs.v
                    end

                    imgui.PushStyleColor(imgui.Col.Text, notifs.Messages and imgui.ImVec4(0, 1, 0, 1) or imgui.ImVec4(1, 0, 0, 1))
                    imgui.Text(ti.ICON_SQUARE_DOT)
                    imgui.PopStyleColor()
                    imgui.SameLine()
                    imgui.Text("Messages:")
                    imgui.SameLine()
                    if imgui.Checkbox("##MessagesNotifs", msgNotifs) then
                        notifs.Messages = msgNotifs.v
                    end

                    imgui.Text("Duration (seconds):")
                    local duration = tonumber(notifs.DefaultDuration or 5)
                    local AvailWidth = 90

                    imgui.SameLine(imgui.GetWindowWidth() - AvailWidth)
                    if imgui.Button(" - ") then
                        notifs.DefaultDuration = math.max(1, notifs.DefaultDuration - 1)
                    end
                    imgui.SameLine()

                    imgui.PushItemWidth(20)
                    local durationBuf = imgui.ImInt(notifs.DefaultDuration)
                    imgui.InputInt("##notifDuration", durationBuf, 0, 0, imgui.InputTextFlags.CharsDecimal)
                    notifs.DefaultDuration = clamp(durationBuf.v, 1, 15)
                    imgui.PopItemWidth()

                    imgui.SameLine()
                    if imgui.Button(" + ") then
                        notifs.DefaultDuration = math.min(15, notifs.DefaultDuration + 1)
                    end

                    imgui.Text("Number of Notifications:")
                    local numOfNotifs = tonumber(notifs.NumberOfNotifications or 2)

                    imgui.SameLine(imgui.GetWindowWidth() - AvailWidth)
                    if imgui.Button(" - ##MinusButtonNotifs") then
                        notifs.NumberOfNotifications = math.max(2, notifs.NumberOfNotifications - 1)
                    end
                    imgui.SameLine()

                    imgui.PushItemWidth(20)
                    local numOfNotifsBuf = imgui.ImInt(notifs.NumberOfNotifications)
                    imgui.InputInt("##notifCount", numOfNotifsBuf, 0, 0, imgui.InputTextFlags.CharsDecimal)
                    notifs.NumberOfNotifications = clamp(numOfNotifsBuf.v, 2, 5)
                    imgui.PopItemWidth()

                    imgui.SameLine()
                    if imgui.Button(" + ##PlusButtonNotifs") then
                        notifs.NumberOfNotifications = math.min(5, notifs.NumberOfNotifications + 1)
                    end
                end
                imgui.EndChild()
                imgui.End()
        end
    end
    imgui.PopStyleVar(3)
    imgui.PopStyleColor(11)
end

function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
    end
    return success, result
end

function removeHexColors(text)
    return text:gsub("{[A-Fa-f0-9]+}", "")
end

local HasLoggedIn = false

function sampev.onServerMessage(color, text)
    --print("Color: " .. color .. " Text: " .. text)
    if color == -1446714113 and text == "Establishing connection to the {FFA500}Horizon Roleplay {A9C4E4}database - please wait a moment..." then

    end
    if text:match("HelpCmd:") then
        --sampAddChatMessage(string.format("Color: %s | Text: %s", tostring(color), text), -1)
    end 
    if color == -5963606 and text:match("Welcome to Horizon Roleplay, (.-)") then
        HasLoggedIn = true
    end    
    if text == "There are no active help requests right now." and color == -1347440726 then
        helpRequests = {} 
        --return false
    end

    if color == -8388353 then
        local helper, name, id = text:match("HelpCmd: (.-) has trashed (.-)'s %(ID: (%d+)%) help request.")
        local playerName = getPlayerNameSafe()
        if playerName ~= name then
            if helper and name and id then
                local requestKey = id .. ":" .. name
                if helpRequests[requestKey] and not helpRequests[requestKey].IsStatus then
                    helpRequests[requestKey].IsStatus = true
                    helpRequests[requestKey].isHandled = true
                 end
                addNotification(string.format("%s has trashed %s's (ID: %s) help request", helper, name, id), "RequestTrashed", UserSettings.Configurations.Notifications.DefaultDuration)
            end
            
            local helper, name, id = text:match("HelpCmd: (.-) has accepted (.-)'s %(ID: (%d+)%) help request.")
            if helper and name and id then
                local requestKey = id .. ":" .. name
                if helpRequests[requestKey] and not helpRequests[requestKey].IsStatus then
                    helpRequests[requestKey].IsStatus = true
                    helpRequests[requestKey].isHandled = true
                end
                addNotification(string.format("%s has accepted %s's (ID: %s) help request", helper, name, id), "RequestAccepted", UserSettings.Configurations.Notifications.DefaultDuration)
            end
        end
        if not UserSettings.Configurations.Notifications.Messages then
            return false
        end
    end
    
    if color == 869072810 then
        local name, id, message = text:match("HelpCmd: (.-) %((%d+)%) has just sent a request for help; (.+)")
        if name and id and message then
            local key = id .. ":" .. name
    
            if not helpRequests[key] then
                helpRequests[key] = { name = name, id = id, message = message, notification = false, IsStatus = false }

                if helpRequests[key].notification == false then
                    helpRequests[key].notification = true
                    addNotification(string.format("%s (ID:%s) has requested help! Message: %s", name, id, message), "Helprequest", 10)
                end
            else
                helpRequests[key].message = message
            end
    
            updateHelpRequests()
        end
    end

    if color == -5963606 and (text == "_____________________________________________________" or text == "Helpers Online:") then
        if HasHelperStatsLoaded then
            return false
        end
    end

    if color == 869072810 then
        local role, name, requests, tours = text:match("^(.- Helper) (.-) {%x+}| {%x+}Requests Accepted: {%x+}(%d+) | {%x+}Tours: {%x+}(%d+)")
        local jrole, jname, chats = text:match("^(Junior Helper) (.-) {%x+}| {%x+}Newbie Chats: {%x+}(%d+)")
        
        local function updateHelperName(roleToFind, nameToUpdate, statText)
            for _, group in ipairs(HelperRoster) do
                if group.role == roleToFind then
                    for i, member in ipairs(group.members) do
                        if member.name == nameToUpdate then
                            member.stats = statText
                            return true
                        end
                    end
                end
            end
            return false
        end        

        
    
        if role and name and requests and tours then
            updateHelperName(role, name, string.format("| Requestes: %s | Tours: %s", requests, tours))
        elseif jrole and jname and chats then
            updateHelperName(jrole, jname, string.format("| Newbie Chats: %s", chats))
        elseif text:match("^_+$") then
            HasHelperRosterLoaded = true
            UpdateOnlineHelpers()
        end

        if HasHelperStatsLoaded then
            return false
        end
    end      
end

function UpdateOnlineHelpers()
    OnlineHelpers = {}
    for id = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(id) then
            local nick = sampGetPlayerNickname(id)
            if nick then
                local normalized = nick:gsub("_", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
                OnlineHelpers[normalized] = true
            end
        end
    end

    updateSortedRoster()
end

function updateSortedRoster()
    local roleOrder = {
        "Director",
        "Assistant Director", 
        "Helper Manager",
        "Q&A Moderator",
        "Head Helper",
        "Senior Helper",
        "Junior Helper"
    }

    CachedSortedRoster = {}
    local playerName = getPlayerNameSafe()
    LastPlayerName = playerName

    local fullAccessRoles = {
        ["Director"] = true,
        ["Assistant Director"] = true,
        ["Helper Manager"] = true,
        ["Q&A Moderator"] = true
    }

    local limitedAccessRoles = {
        ["Head Helper"] = true,
        ["Senior Helper"] = true,
        ["Junior Helper"] = true
    }

    local function hasAccessToRole(targetRole)
        if fullAccessRoles[HelperRole] then
            return true
        elseif limitedAccessRoles[HelperRole] and limitedAccessRoles[targetRole] then
            return true
        else
            return false
        end
    end

    for _, roleName in ipairs(roleOrder) do
        if hasAccessToRole(roleName) then
            for _, roster in pairs(HelperRoster) do
                if roster.role == roleName and #roster.members > 0 then
                    local youList, onlineList, offlineList = {}, {}, {}

                    for _, helperData in ipairs(roster.members) do
                        local helperName = helperData.name
                        if helperName == playerName then
                            table.insert(youList, helperData)
                        elseif OnlineHelpers[helperName] then
                            table.insert(onlineList, helperData)
                        else
                            table.insert(offlineList, helperData)
                        end
                    end

                    local merged = {}
                    for _, h in ipairs(youList) do table.insert(merged, h) end
                    for _, h in ipairs(onlineList) do table.insert(merged, h) end
                    for _, h in ipairs(offlineList) do table.insert(merged, h) end

                    table.insert(CachedSortedRoster, {
                        role = roleName,
                        count = #roster.members,
                        members = merged
                    })
                end
            end
        end
    end
end

function updateHelpRequests()
    safeCall(function ()
        local activeRequests = {}

        for key, entry in pairs(helpRequests) do
            if entry.name and entry.id and entry.message then
                activeRequests[key] = entry
            end
        end

        helpRequests = activeRequests
    end)
end

local isLoadingInterior = false
local last_request = 0
local helprequsttimer = 5

function sampev.onShowTextDraw(id, data)
    if data.text:match("~r~Objects loading...") then
        isLoadingInterior = true
    end

    if data.text:match("~g~Objects loaded!") then
        isLoadingInterior = false
    end
end

function addNotification(text, type, duration)
    if not UserSettings.Configurations.Notifications.Show then return end
    local showtime = duration or UserSettings.Configurations.DefaultDuration
    table.insert(message, {
        text = text,
        type = type,
        showtime = showtime,
        time = os.clock() + showtime,
        fadeStart = nil, 
        fadeDuration = 2.0, 
        active = true
    })
    IsNotifActive = true
    if UserSettings.Configurations.Notifications.Sound then
        local cx, cy, cz = getCharCoordinates(PLAYER_PED)
        addOneOffSound(cx, cy, cz, 1139)
    end
end

function refreshconfigspath()
    local function loadConfig(path)
        local file, content = io.open(path, 'rb')
        if not file then
            return nil
        end
        
        content = file:read('*a')
        file:close()
        
        local success, result = pcall(decodeJson, content)
        if not success then
            return nil
        end
        
        return result
    end

    dict = loadConfig(dictPath) or dict or {}
    
    locations = loadConfig(locationsPath) or locations or {}
end

function blankIni()
    UserSettings = {
        ShowTabs = {
            Definitions = true,
            Locations = true,
            Level1s = true,
            HelpRequests = true,
            ServerTour = true,
            HelperRoster = true,
            LvlCalculator = true
        },
        Configurations = {
            Notifications = {
                Show = true,
                Sound = true,
                DefaultDuration = 5,
                Messages = true,
                NumberOfNotifications = 2,
                Position = { x = 0, y = 0 }
            },
        }
    }
    saveIni()
end

function mergeDefaults(defaults, target)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            target[k] = target[k] or {}
            mergeDefaults(v, target[k])
        else
            if target[k] == nil then
                target[k] = v
            end
        end
    end
end


function loadIni()
    local f = io.open(userConfigPath, "r")
    if f then
        local content = f:read("*a")
        local success, data = pcall(decodeJson, content)
        if success and type(data) == "table" then
            UserSettings = data
            mergeDefaults(blankIniDefaults(), UserSettings)
        end
        f:close()
    else
        blankIni()
    end
end

function blankIniDefaults()
    return {
        ShowTabs = {
            Definitions = true,
            Locations = true,
            Level1s = true,
            HelpRequests = true,
            ServerTour = true,
            HelperRoster = true,
            LvlCalculator = true
        },
        Configurations = {
            Notifications = {
                Show = true,
                Sound = true,
                DefaultDuration = 5,
                Messages = true,
                NumberOfNotifications = 2,
                Position = { x = 0, y = 0 }
            }
        }
    }
end

function saveIni()
    if type(UserSettings) == "table" then
        local encoded = encodeJson(UserSettings)
        if not encoded then
            print("Failed to encode UserSettings to JSON")
            return
        end

        local f = io.open(userConfigPath, "w")
        if f then
            f:write(encoded)
            f:close()
            print("Saved settings to " .. userConfigPath)
        else
            print("Failed to open " .. userConfigPath .. " for writing")
        end
    end
end

function onScriptTerminate(scr, quitGame) 
	if scr == script.this then 
		saveIni()  
	end
end

function fastquit()
    adr = getModuleProcAddress("Kernel32.DLL", "ExitProcess")
    callFunction(adr, 1, 0, 0)
end

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

function clamp(value, min, max)
    return math.max(min, math.min(value, max))
end


function main()
    if doesFileExist(userConfigPath) then loadIni() else blankIni() end

    while not isSampAvailable() do wait(100) end

    local verifiedName = nil

    local status, err = pcall(function() checkAndDownloadLibraries() end)
    if not status then
        sampAddChatMessage("[HelperKit] {FF4444}Unable to load dependencies. Use /reloadhk to try again.", 0xFF4444)
    end

    local function registerVerifiedCommands(Authenticated)
        if Authenticated then
            sampRegisterChatCommand('hkit', function()
                SelectedSettings.Tab = 0
                Settings.Visible.Main.v = not Settings.Visible.Main.v
                imgui.ShowCursor = not imgui.ShowCursor
            end)
            sampRegisterChatCommand('def', cmdDef)
            sampRegisterChatCommand('notify', addNotification)
            sampRegisterChatCommand('loc', cmdLoc)
            sampRegisterChatCommand('sst', startServerTour)
            sampRegisterChatCommand('est', exitServerTour)
            sampRegisterChatCommand('addloc', cmdaddloc)
            sampRegisterChatCommand('n', cmdN)
            sampRegisterChatCommand('hrs', cmdHrs)
            sampRegisterChatCommand('ahr', cmdAhr)
            sampRegisterChatCommand('hkhelp', cmdHkhelp)
            sampRegisterChatCommand('lvl1s', cmdLvl1s)
            sampRegisterChatCommand('lvl', cmdLvl)
    
            if adminSettings.IsAdmin then
                sampRegisterChatCommand('debugauth', function()
                    lua_thread.create(function()
                        sampAddChatMessage("{FFFF00}Testing verification patterns...", -1)
                        local cookies, err = authenticateForum()
                        if cookies then
                            sampAddChatMessage("{00FF00}Verification successful!", -1)
                        else
                            sampAddChatMessage("{FF0000}Verification failed: " .. tostring(err), -1)
                            sampAddChatMessage("{FFFF00}Check helper_roster_failed.html", -1)
                        end
                    end)
                end)
    
                sampRegisterChatCommand('checkmyvef', function()
                    local name = getPlayerNameSafe()
                    sampAddChatMessage(string.format("[Helper-Kit] {FFFFFF}Hello {33CCFF}%s{FFFFFF}, You have been verified as %s of the Helper Team.", name, HelperRole), 0x33CCFF)
                    addNotification(string.format("Hello %s, You have been verified as %s of the Helper Team.", name, HelperRole), "Success", 8)
                end)
            end
    
            sampRegisterChatCommand('hrset', function(msg)
                local args = {}
                for word in msg:gmatch("%S+") do table.insert(args, word) end
                args[1] = args[1]:gsub("_", " ")
                HelperRole = args[1]
                addNotification(string.format('You have set the "HelperRole" to "%s"', args[1]), "Debug", UserSettings.Configurations.Notifications.DefaultDuration)
            end)
    
            sampRegisterChatCommand('addhr', function(msg)
                local args = {}
                for word in msg:gmatch("%S+") do table.insert(args, word) end
                args[2] = args[2]:gsub("_", " ")
                local key = args[1] .. ":" .. args[2]
                helpRequests[key] = {
                    name = args[2],
                    id = args[1],
                    message = "Help Request Test Number: " .. args[1],
                    notification = false
                }
                addNotification(string.format("%s (ID:%s) has requested a help! message: %s", helpRequests[key].name, helpRequests[key].id, helpRequests[key].message), "Helprequest", UserSettings.Configurations.Notifications.DefaultDuration)
            end)
        else
            sampUnregisterChatCommand('hkit')
            sampUnregisterChatCommand('def')
            sampUnregisterChatCommand('notify')
            sampUnregisterChatCommand('loc')
            sampUnregisterChatCommand('sst')
            sampUnregisterChatCommand('est')
            sampUnregisterChatCommand('addloc')
            sampUnregisterChatCommand('n')
            sampUnregisterChatCommand('hrs')
            sampUnregisterChatCommand('ahr')
            sampUnregisterChatCommand('hkhelp')
            sampUnregisterChatCommand('lvl1s')
            sampUnregisterChatCommand('lvl')
            sampUnregisterChatCommand('hrset')
            sampUnregisterChatCommand('addhr')

            sampUnregisterChatCommand('debugauth')
            sampUnregisterChatCommand('checkmyvef')
        end
    end

    sampRegisterChatCommand('reloadhk', function()
        saveIni()
        thisScript():reload()
        loadIni()
        sampAddChatMessage("[HelperKit] {FFFFFF}Script has been reloaded!", 0x33CCFF)
    end)

    sampRegisterChatCommand("q", fastquit)
    sampRegisterChatCommand("quit", fastquit)

    verifiedName = getPlayerNameSafe()
    local success, authResult, extraInfo = pcall(function()
        return authenticateAndCheckWhitelist()
    end)

    sampRegisterChatCommand('aduty', function()
        lua_thread.create(function()
            local success, err = pcall(function()
                sampSendChat("/aduty")
                wait(1000)
    
                local newName = getPlayerNameSafe()
                local foundRole = nil
    
                for _, roleData in pairs(HelperRoster) do
                    for _, member in ipairs(roleData.members) do
                        if member.name == newName then
                            foundRole = roleData.role
                            break
                        end
                    end
                    if foundRole then break end
                end
    
                if not foundRole then
                    sampAddChatMessage(string.format("[HelperKit] {FFFFFF}You're not whitelisted to use this modification after duty change, {FF4444}%s{FFFFFF}.", newName), 0x33CCFF)
                    addNotification(string.format("You're not whitelisted after duty change, %s.", newName), "Failed", 8)
                    verifiedName = nil
                    HelperRole = nil
                    registerVerifiedCommands(false)
                    return
                end
    
                verifiedName = newName
                HelperRole = foundRole
    
                for _, admin in pairs(adminSettings.AdminsList) do
                    if admin == newName then
                        adminSettings.IsAdmin = true
                        break
                    end
                end
    
                addNotification(string.format("Welcome back %s, you are verified as %s. You can use this modification.", newName, foundRole), "Success", 8)
                sampAddChatMessage(string.format("[Helper-Kit] {FFFFFF}Hello {33CCFF}%s{FFFFFF}, You have been verified as {33CCFF}%s{FFFFFF}.", newName, foundRole), 0x33CCFF)
    
                refreshconfigspath()
                registerVerifiedCommands(true)
            end)
    
            if not success then
                sampAddChatMessage(string.format("[HelperKit] {FF4444}An error occurred in /aduty | Err: %s", tostring(err)), 0x33CCFF)
                addNotification("Something went wrong while verifying after duty.", "Error", 8)
            end
        end)
    end)    

    if HasLoggedIn then
        
    end
    

    if not success then
        sampAddChatMessage("[HelperKit] {FFFFFF}Fatal error during authentication. Use /reloadhk to try again.", 0x33CCFF)
        return
    end

    local authStatus = authResult
    local authData = extraInfo

    if not authStatus then
        local failureReason = select(3, authenticateAndCheckWhitelist())
        if failureReason == "Failed to authenticate" then
            sampAddChatMessage("[HelperKit] {FFFFFF}Connection/authentication failed. Check your internet or forum access. Use {33CCFF}/reloadhk{FFFFFF} to retry.", 0x33CCFF)
            addNotification(string.format("Connection/authentication failed. Check your internet or forum access. Use /reloadhk to retry."), "Failed", 8)
        elseif failureReason == "Not whitelisted" then
            sampAddChatMessage(string.format("[HelperKit] {FFFFFF}Hello {33CCFF}%s{FFFFFF}, you're not whitelisted to use this modification.", verifiedName), 0x33CCFF)
            addNotification(string.format("Hello %s, you're not whitelisted to use this modification.", verifiedName), "Failed", 8)
        else
            sampAddChatMessage("[HelperKit] {FFFFFF}Unknown authentication error. Use {33CCFF}/reloadhk{FFFFFF} to try again.", 0x33CCFF)
            addNotification("Unknown authentication error. Use /reloadhk to try again.", "Failed", 8)
        end
    else
        local playerRole = authData.role
        local team = authData.team

        addNotification(string.format("Hello %s, you are authenticated as %s of %s. You can use this modification", verifiedName, playerRole, team), "Success", 8)
        sampAddChatMessage(string.format("[Helper-Kit] {FFFFFF}Hello {33CCFF}%s{FFFFFF}, You have been verified as {33CCFF}%s{FFFFFF} of the {33CCFF}%s.", verifiedName, playerRole, team), 0x33ccff)

        for _, Admins in pairs(adminSettings.AdminsList) do
            if Admins == verifiedName then
                adminSettings.IsAdmin = true
                break
            end
        end

        HelperRole = playerRole
        refreshconfigspath()
        registerVerifiedCommands(true)
    end

    imgui.Process = true
    imgui.ShowCursor = false
    imgui.SetMouseCursor(-1)

    lua_thread.create(function()
        while true do
            wait(5000)
            if not isLoadingInterior and helprequsttimer <= localClock() - last_request then
                last_request = localClock()
                pcall(function() updateHelpRequests() end)
                for key, request in pairs(helpRequests) do
                    if request.isHandled then
                        helpRequests[key] = nil
                    end
                end

                if HasHelperRosterLoaded and not HasHelperRoster then
                    HasHelperRoster = true
                    lua_thread.create(function()
                        wait(3000)
                        pcall(UpdateOnlineHelpers)
                        if not HasHelperStatsLoaded then
                            sampSendChat("/helpers")
                            pcall(UpdateOnlineHelpers)
                            HasHelperStatsLoaded = true
                        end
                    end)
                end
            end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(20000)
            local currentName = getPlayerNameSafe()
    
            if verifiedName and currentName ~= verifiedName then
                local foundRole = nil
    
                for _, roleData in ipairs(HelperRoster) do
                    for _, member in ipairs(roleData.members) do
                        if member.name == currentName then
                            foundRole = roleData.role
                            break
                        end
                    end
                    if foundRole then break end
                end
    
                if not foundRole then
                    sampAddChatMessage(string.format("[HelperKit] {FFFFFF}Access revoked. Name mismatch detected: {FF0000}%s{FFFFFF} (expected: {FF0000}%s{FFFFFF}).", currentName, verifiedName), 0x33CCFF)
                    addNotification("Name mismatch! Access to Helper Mod has been revoked.", "Warning", 8)
                    
                    verifiedName = nil
                    HelperRole = nil

                    registerVerifiedCommands(false)
    
                    break
                else
                    verifiedName = currentName
                    HelperRole = foundRole
    
                    sampAddChatMessage(string.format("[HelperKit] {FFFFFF}Name changed to {33CCFF}%s{FFFFFF}, still verified as {33CCFF}%s{FFFFFF}.", currentName, foundRole), 0x33CCFF)
                    addNotification(string.format("Name changed to %s, still verified as %s. Access remains granted.", currentName, foundRole), "Info", 8)
    
                    refreshconfigspath()
                    registerVerifiedCommands(true)
                end
            end
        end
    end)

    while true do wait(100) end
end

function events.onSendCommand(command)
    local cl = command:lower()
    if cl:sub(1, 4) == '/kcp' or cl:sub(1, 15) == '/killcheckpoint' then
        clearCheckpoint()
    end
end

