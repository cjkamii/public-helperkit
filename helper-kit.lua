script_name('Helper Kit')
script_version('1.7')
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
local socket = require('socket')
local url = require('socket.url')

local events = require('samp.events')

imgui, handle = require('imgui'), PLAYER_HANDLE

local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

local ti = require "tabler_icons"

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

local dictPath = 'moonloader\\config\\helper-kit\\dict.json'
local dict = {}

local locationsPath = 'moonloader\\config\\helper-kit\\locations.json'
local locations = {}

local checkpoint, blip

local ServerTour = {
    Locations = {
        { name = "Unity Station", desc = "The starting location of newbies." },
        { name = "Taxi Job", desc = "Good for newbie jobs for starters and to interact with other players." },
        { name = "BHT HQ", desc = "One of the oldest gangs in the server." },
        { name = "City Hall", desc = "Main City Hall of Los Santos. You can buy a license via [/getlicenses]." },
        { name = "Los Santos Police Department Headquarters", desc = "Main Law Enforcement Faction of the server, the LSPD is a starter faction." },
        { name = "Paintball", desc = "One of the best places to hang out and test your firearm skills." },
        { name = "Maximus Club", desc = "A donator place for players who have a donator perk [/donate] for information." },
        { name = "Pizza Stacks", desc = "Best place to hang out with other players, known for its location." },
        { name = "Ganton Gym", desc = "Known for the bodyguard job and different fighting styles [/train]." }
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
local IsSelectedDict = imgui.ImBool(false)
local helpRequests = {}
local HelperRole = ""
local HelperRoster = {}
local HasHelperRosterLoaded = false
local HasHelperStatsLoaded = false
local desc = ""

local time = 0

local isPlayerWhitelisted = false

local GITHUB_REPO = "cjkamii/hkit41225"
local SCRIPT_NAME = "helper-kit.lua"
local CURRENT_VERSION = 1.0
local BRANCH = "main"

local ENCRYPTED_TOKEN = "-"
local AES_KEY = "-"
local AES_IV = "-"

local FORUM_LOGIN = "-"
local FORUM_PASSWORD = "-"
local FORUM_BASE = "https://forums.hzgaming.net"
local LOGIN_URL = FORUM_BASE .. "/login.php?do=login"
local TARGET_URL = FORUM_BASE .. "/showthread.php/119521-Helper-Roster"

function getPlayerNameSafe()
    local success, result = pcall(function()
        local result, ped = getPlayerChar(PLAYER_HANDLE)
        if not result or not ped or ped == 0 then
            return nil
        end

        local result, playerId = sampGetPlayerIdByCharHandle(ped)
        if not result or not playerId then
            return nil
        end

        local name = sampGetPlayerNickname(playerId)
        if not name or name == "" then
            return nil
        end
        local normalizedPlayerName = name:gsub("_", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
        return normalizedPlayerName
    end)

    if not success or not result then
        return nil
    end
    return result
end

function fetchGitHubWhitelist()
    local content = downloadGitHubFile("whitelist.txt")
    if not content then return nil, "Failed to fetch GitHub whitelist" end

    local success, whitelist = pcall(function()
        return decodeJson(content)
    end)

    if not success or type(whitelist) ~= "table" then
        return nil, "Invalid whitelist format"
    end

    local normalizedWhitelist = {}
    for _, name in ipairs(whitelist) do
        local normalizedName = name:gsub("_", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1"):lower()
        table.insert(normalizedWhitelist, normalizedName)
    end
    return normalizedWhitelist
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

    local gitHubWhitelist, err = fetchGitHubWhitelist()
    if not gitHubWhitelist then
        return false, nil, err
    end

    local isWhitelisted, playerRole = isPlayerWhitelisted(helperList)
    local isInGitHubWhitelist = isPlayerInGitHubWhitelist(gitHubWhitelist)

    if isWhitelisted then
        return true, playerRole, "Helper Team"
    elseif isInGitHubWhitelist then
        return true, "Whitelisted", "Github Whitelist"
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
            specialRoles = {
                ["#ffaa65"] = "Helper Manager",
                ["#fdee00"] = "Helper Manager", 
                ["#d5010b"] = "Director",
                ["#BCBCBC"] = "Assistant Director",
                ["Q&A Moderator"] = "Q&A Moderator"
            }
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
                for liBlock in roleSection:gmatch('<li[^>]*>(.-)</li>') do
                    local color, name = liBlock:match('<font color="(#%x+)">(.-)</font>')
                    name = name and name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("_", " ")
                    
                    if name and name ~= "" then
                        local specificRole = liBlock:match("Q&A Moderator") and "Q&A Moderator" or
                                           roleData.specialRoles[color] or
                                           "Helper Manager"
                        
                        local member = {
                            name = name,
                            stats = ""
                        }
                        table.insert(extractedHelpers[specificRole], member)
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
                count = #helpers
            })
        end
    end

    HelperRoster = formattedHelpers

    return formattedHelpers
end

function authenticateForum()
    local content, code, headers = httpRequest(LOGIN_URL)
    
    if not content then
        return nil, "Cannot access login page"
    end
    
    local f = io.open("moonloader/config/helper-kit/logs/login_page.html", "w")
    if f then f:write(content); f:close() end
    
    local securityToken = content:match('name="securitytoken" value="([^"]+)"') or
                         content:match('name="token" value="([^"]+)"') or
                         content:match('var SECURITYTOKEN = "([^"]+)"')
    
    if not securityToken then
        return nil, "Security token missing"
    end
    
    local postData = {
        "vb_login_username=" .. url.escape(FORUM_LOGIN),
        "vb_login_password=" .. url.escape(FORUM_PASSWORD),
        "securitytoken=" .. url.escape(securityToken),
        "cookieuser=1",
        "do=login",
        "s=",
        "url=/index.php"
    }
    postData = table.concat(postData, "&")
    
    local loginContent, loginCode, loginHeaders = httpRequest(
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
    
    if not loginContent then
        return nil, "Login submission failed"
    end
    
    local cookies = loginHeaders and (loginHeaders["set-cookie"] or loginHeaders["Set-Cookie"])
    if not cookies then
        return nil, "No session cookies"
    end
    local protectedContent, protectedCode = httpRequest(
        TARGET_URL,
        "GET",
        {
            ["Cookie"] = cookies,
            ["User-Agent"] = "Mozilla/5.0",
            ["Referer"] = LOGIN_URL
        }
    )
    
    if not protectedContent then
        return nil, "Cannot access protected content"
    end
    
    local f = io.open("moonloader/config/helper-kit/logs/protected_page.html", "w")
    if f then f:write(protectedContent); f:close() end

    local isLoggedIn = false
    if protectedContent then
        local verificationPatterns = {
            "logout%.php",
            "login%.php%?do=logout",
            "signout",
            "log out",
            "sign out",
            "Logout",
            "Log Out",
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
    else
    end
    
    if not isLoggedIn then
        return nil, "Login verification failed"
    end

    local helperList, extractErr = extractHelperRoster(protectedContent)
    if not helperList then
        return nil, extractErr
    end

    return cookies, helperList
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

function downloadGitHubFile(path)
    local response_chunks = {}
    local api_url = "https://api.github.com/repos/"..GITHUB_REPO.."/contents/"..path
    local raw_url = "https://raw.githubusercontent.com/"..GITHUB_REPO.."/"..BRANCH.."/"..path
    
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
        
        if status ~= 200 then return nil, "HTTP "..status end
        
        local data = decodeJson(response)
        if not data or not data.content then return nil, "Invalid GitHub response" end
        
        response = crypto.base64_decode(data.content:gsub("\n", ""))
    end
    
    return response
end

function checkUpdate()
    local content = downloadGitHubFile("version.txt")
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

function writeVersionConfig(file_path, config, changelog)
    local file = io.open(file_path, "w")
    if not file then return false, "Failed to open file for writing" end

    file:write("VERSION = " .. config.VERSION .. "\n")
    file:write("UPDATE = " .. (config.UPDATE or "true") .. "\n")
    file:write("CHANGELOG:" .. (changelog or "- No changes listed") .. "\n")

    file:close()
    return true
end

function performUpdate(remote_version, changelog)
    local content = downloadGitHubFile(SCRIPT_NAME)
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

    addNotification(("Script updated to v%s"):format(remote_version), "Update", 5)

    thisScript():reload()
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
                    addNotification(string.format("You have arrived at the %s", bm.keywords[1]), "Arrived", 5)
                    currentlocation = nil
                    return
                end
                wait(100)
            end
        end)
    end)
    sampAddChatMessage(string.format('Follow the checkpoint to %s.', bm.keywords[1]), -1)
    addNotification(string.format("Follow the checkpoint to %s", bm.keywords[1]), "Locate", 5)
end

function cmdLvl(level)
    level = tonumber(level)
    if level == nil or level < 2 then
        sampAddChatMessage('USAGE: /lvl [n>=2]', 0xAFAFAF)
        return
    end
    local rp = 8 + (level - 2) * 4
    local mon = 5000 + (level - 2) * 2500
    local rpsum = (level - 1) * (8 + rp) / 2
    local monsum = (level - 1) * (5000 + mon) / 2
    sampAddChatMessage(string.format("{33CCFF}Level %s:{FFFFFF} %s respect points + $%s | {33CCFF}Total:{FFFFFF} %s respect points + $%s",
        numWithCommas(level),
        numWithCommas(rp),
        numWithCommas(mon),
        numWithCommas(rpsum),
        numWithCommas(monsum)
    ), -1)
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
            addNotification("Server Tour is already running!", "Startservertour", 5)
            return
        end

        cleanupTourResources()
        
        ServerTour.CurrentLocation = 1
        ServerTour.IsTourActive = true
        addNotification("Server Tour started! Follow the checkpoints.", "Startservertour", 5)
        
        proceedToNextLocation()
    end)

    if not success then
        addNotification("Error in startServerTour: " .. tostring(err), "Startservertour", 5)
        cleanupTourResources()
    end
end

function exitServerTour()
    local success, err = pcall(function()
        if not ServerTour.IsTourActive then addNotification("There are no server tour on-going.", "Exitservertour", 5) return end
        
        ServerTour.IsTourActive = false
        ServerTour.CurrentLocation = 1
        cleanupTourResources()
        addNotification("You have exited the Server Tour.", "Exitservertour", 5)
    end)

    if not success then
        addNotification("Error in exitServerTour: " .. tostring(err), "Exitservertour", 5)
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
        addNotification("Server Tour Complete!", "Servertour", 5)
        ServerTour.IsTourActive = false
        ServerTour.CurrentLocation = 1
        cleanupTourResources()
        return
    end

    local locationData = ServerTour.Locations[ServerTour.CurrentLocation]
    if not locationData then
        addNotification("Error: Invalid location data.", "Servertour", 5)
        exitServerTour()
        return
    end

    local locationName, description = locationData.name, locationData.desc

    local bm = getMatch(locations, locationName)
    if not bm then
        addNotification(string.format("Error: Location '%s' not found", locationName), "Servertour", 5)
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
                        addNotification(string.format("Now heading to: %s", ServerTour.Locations[ServerTour.CurrentLocation + 1] and ServerTour.Locations[ServerTour.CurrentLocation + 1].name or "None"), "Servertour", 5)
                    end
                    addNotification(string.format("Current Location: %s", locationName), "Servertour", 5)
                    addNotification(string.format("%s", description), "Servertour", 5)
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
            addNotification("Tour error: " .. tostring(errThread), "Servertour", 5)
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
        addNotification("Error in getLocationKey: " .. tostring(result), "Getlocationkey", 5)
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
        addNotification("Failed to open Locations.JSON for reading", "Addlocation", 5)
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
        addNotification(string.format("%s has been added", Arg), "Addlocation", 5)
    else
        addNotification(string.format("%s has been failed to be added", Arg), "Addlocation", 5)
    end
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
    AdminsList = {"Daniel Adler"},
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

function imgui.OnDrawFrame()
    width, height = getScreenResolution()
    local windowWidth, windowHeight = 500, 600

    time = time + 0.0005
    local hue = (time % 1)
    local r, g, b = hsvToRgb(hue, 1, 1)


    imgui.PushStyleColor(imgui.Col.TitleBg, rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.TitleBgActive, rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.TitleBgCollapsed, rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.Button, rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.ButtonActive, rgbToImVec4(r, g, b, 1))
    imgui.PushStyleColor(imgui.Col.Text, rgbToImVec4(255, 255, 255, 1))
    imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 10)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 10)
    imgui.PushStyleVar(imgui.StyleVar.FrameRounding, 10)

    
    if IsNotifActive then
        local count = 0
        local currentTime = os.clock()
        local totalHeight = 0
    
        local screenWidth, screenHeight = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
        local margin = 20 
        local rightPosition = screenWidth - margin 
        local notifWidth = 200
    
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0, 0, 0, 0))
    
        imgui.SetNextWindowPos(imgui.ImVec2(rightPosition - notifWidth - 10, screenHeight / 2 - 150), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(notifWidth + 20, 600)) 
    
        imgui.Begin("##notif_container", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)
    
        local drawList = imgui.GetWindowDrawList()
    
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
    
            if count < 4 then
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
                                addNotification(string.format("You have accepted %s's (ID:%d) Help request.", name, id), nil, 5)
                                sampSendChat("/accepthelp " .. id)
                                helpRequests[requestKey].IsStatus = true
                                helpRequests[requestKey].isHandled = true
                            end
                    
                            imgui.SameLine(0, spacing)
                    
                            if imgui.Button(u8("Trash"), imgui.ImVec2(buttonWidth, 20)) then
                                addNotification(string.format("You have trashed %s's (ID:%d) Help request.", name, id), nil, 5)
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
        imgui.End()
        imgui.PopStyleColor(2)
    
        if count == 0 and #message == 0 then
            lua_thread.create(function()
                wait(5000)
                if #message == 0 then
                    IsNotifActive = false
                end
            end)
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
                imgui.BeginChild("Sidebar", imgui.ImVec2(100, 550), true)
                local textWidth = imgui.CalcTextSize('List').x
                imgui.SetCursorPosX((100) / 2 - textWidth / 2)
                imgui.Text(u8("List"))
    
                imgui.Separator()
    
                if imgui.Selectable(ti.ICON_BOOK, SelectedSettings.Tab == 1, imgui.ImGuiSelectableFlags_DontClosePopups) then
                    SelectedSettings.Tab = 1
                    Settings.Visible.SelectedWindow = imgui.ImBool(true)
                end imgui.SameLine(0, 0) imgui.Text(" Definitions")
    
                if imgui.Selectable(ti.ICON_MAP_PIN, SelectedSettings.Tab == 2, imgui.ImGuiSelectableFlags_DontClosePopups) then
                    SelectedSettings.Tab = 2
                    Settings.Visible.SelectedWindow = imgui.ImBool(true)
                end imgui.SameLine(0, 0) imgui.Text(" Locations")
    
                if imgui.Selectable(ti.ICON_USER_EXCLAMATION, SelectedSettings.Tab == 3, imgui.ImGuiSelectableFlags_DontClosePopups) then
                    SelectedSettings.Tab = 3
                    Settings.Visible.SelectedWindow = imgui.ImBool(true)
                end imgui.SameLine(0, 0) imgui.Text(" Level1s")
    
                if imgui.Selectable(ti.ICON_MAILBOX, SelectedSettings.Tab == 4, imgui.ImGuiSelectableFlags_DontClosePopups) then
                    SelectedSettings.Tab = 4
                    Settings.Visible.SelectedWindow = imgui.ImBool(true)
                end imgui.SameLine(0, 0) imgui.Text(" Helprequests")
    
                imgui.Separator()
    
                if imgui.Selectable(ti.ICON_MAP_2, SelectedSettings.Tab == 5, imgui.ImGuiSelectableFlags_DontClosePopups) then
                    SelectedSettings.Tab = 5
                    Settings.Visible.SelectedWindow = imgui.ImBool(true)
                end imgui.SameLine(0, 0) imgui.Text(" Server Tour")

                if imgui.Selectable(ti.ICON_ARTBOARD, SelectedSettings.Tab == 6, imgui.ImGuiSelectableFlags_DontClosePopups) then
                    SelectedSettings.Tab = 6
                    Settings.Visible.SelectedWindow = imgui.ImBool(true)
                    HasHelperRosterLoaded = true
                    if not HasHelperStatsLoaded then
                        sampSendChat("/helpers")
                        HasHelperStatsLoaded = true
                    end
                end imgui.SameLine(0, 0) imgui.Text(" Helper Roster")

                local PlayerName = getPlayerNameSafe()

                for i, v in pairs(adminSettings.AdminsList) do
                    if v == PlayerName then
                        imgui.Separator()
                        adminSettings.Authenticated = true
                        if imgui.Selectable(ti.ICON_CROWN, SelectedSettings.Tab == 7, imgui.ImGuiSelectableFlags_DontClosePopups) then
                            SelectedSettings.Tab = 7
                            Settings.Visible.SelectedWindow = imgui.ImBool(true)
                        end imgui.SameLine(0, 0) imgui.Text(" Admin")
                    end
                end
    
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
    
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.23))
                imgui.BeginChild("Questions", imgui.ImVec2(0, windowSize.y * 0.175), true)
                imgui.EndChild()
    
                imgui.SetCursorPos(imgui.ImVec2(windowSize.x * 0.23, windowSize.y * 0.42))
                imgui.BeginChild("NewbPanel", imgui.ImVec2(0, windowSize.y * 0.175), true)
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
    
                if IsSelectedDict and SelectedSettings.Dictionary ~= nil then
                    imgui.SetNextWindowPos(imgui.ImVec2((width / 2) + (width / 3), height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
                    imgui.SetNextWindowSize(imgui.ImVec2(windowWidth * 0.8, 0), imgui.Cond.FirstUseEver)
                    imgui.Begin(SelectedSettings.Dictionary .. " | Definition", IsSelectedDict, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove)
                    imgui.Text(u8("Selected Dictionary: " .. SelectedSettings.Dictionary))
                    local MinimumText, SecondMinimumText = 60, 61
                    local tempText = SelectedSettings.Keyword 
                    local IncrementedSize = 0
                    while #tempText > MinimumText do
                        imgui.Text(u8(tempText:sub(1, MinimumText)))  
                        tempText = '-..' .. tempText:sub(SecondMinimumText) 
                        IncrementedSize = IncrementedSize + 0.03
                    end
                
                    if #tempText > 0 then
                        imgui.Text(u8(tempText))
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
                imgui.Text(u8("Selected Location: " .. (SelectedSettings.Location or "")))
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
                    imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), Description.name)
                    imgui.Text(u8(Description.desc))
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
                imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), "Helper Roster")
                imgui.BeginChild("HelperRoster", imgui.ImVec2(0, 0), true)
                
                local roleOrder = {
                    "Director",
                    "Assistant Director", 
                    "Helper Manager",
                    "Q&A Moderator",
                    "Head Helper",
                    "Senior Helper",
                    "Junior Helper"
                }
                
                if HasHelperRosterLoaded then
                    for _, roleName in ipairs(roleOrder) do
                        for _, roster in pairs(HelperRoster) do
                            if roster.role == roleName and #roster.members > 0 then
                                imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), roster.role .. " (" .. roster.count .. ")")
    
                                for _, helperData in ipairs(roster.members) do
                                    local helperName = helperData.name
                                    local helperStats = helperData.stats
                                    if roster.role == "Director" then
                                        imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), helperName)
                                    elseif roster.role == "Assistant Director" then
                                        imgui.TextColored(imgui.ImVec4(1.0, 0.0, 0.0, 1.0), helperName)
                                    else
                                        local playerName = getPlayerNameSafe()
                                        local isOnline = false
                                        local isYou = (helperName == playerName)
                                        
                                        if isYou then
                                            imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), helperName) imgui.SameLine(0, 0) if helperStats then imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), " " .. helperStats) end imgui.SameLine(0, 0) imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), " (You)")
                                        else
                                            for id = 0, sampGetMaxPlayerId(false) do
                                                if sampIsPlayerConnected(id) then
                                                    local nick = sampGetPlayerNickname(id)
                                                    if nick then
                                                        local normalizedPlayerName = nick:gsub("_", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
                                                        if normalizedPlayerName == helperName then
                                                            isOnline = true
                                                            break
                                                        end
                                                    end
                                                end
                                            end
                                            
                                            if isOnline then
                                                imgui.TextColored(imgui.ImVec4(0.0, 1.0, 0.0, 1.0), helperName) imgui.SameLine(0, 0) if helperStats then imgui.TextColored(imgui.ImVec4(1.0, 1.0, 1.0, 1.0), " " .. helperStats) end imgui.SameLine(0, 0) imgui.TextColored(imgui.ImVec4(0.0, 1.0, 0.0, 1.0), " (Online)")                
                                            else
                                                imgui.TextColored(imgui.ImVec4(0.6, 0.5, 0.5, 1.0), helperName)
                                            end
                                        end
                                    end
                                end
                                
                                imgui.Separator()
                                imgui.Spacing()
                            end
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
                                        HelperRoster[selectedRole] = {members = {}, count = 0}
                                    end

                                    local exists = false
                                    for _, name in ipairs(HelperRoster[selectedRole].members) do
                                        if name:lower() == helperName:lower() then
                                            exists = true
                                            break
                                        end
                                    end

                                    if not exists then
                                        table.insert(HelperRoster[selectedRole].members, helperName)
                                        HelperRoster[selectedRole].count = #HelperRoster[selectedRole].members
                                        addNotification("Added "..helperName.." as "..selectedRole, "Success", 3)
                                        adminSettings.Inputs.HelperName.v = ""
                                    else
                                        addNotification(helperName.." already exists in "..selectedRole, "Warning", 3)
                                    end
                                else
                                    addNotification("Invalid role selected", "Error", 3)
                                end
                            else
                                addNotification("Please enter a name", "Error", 3)
                            end
                        end

                        imgui.Separator()

                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Current Whitelist")
                        if imgui.BeginChild("WhitelistView", imgui.ImVec2(0, imgui.GetContentRegionAvail().y * 0.7), true) then
                            local roleOrder = {
                                "Director",
                                "Assistant Director", 
                                "Helper Manager",
                                "Q&A Moderator",
                                "Head Helper",
                                "Senior Helper",
                                "Junior Helper"
                            }

                            local toRemove = {}

                            for _, roleName in ipairs(roleOrder) do
                                for _, roster in pairs(HelperRoster) do
                                    if roster.role == roleName and roster.members and #roster.members > 0 then
                                        imgui.TextColored(imgui.ImVec4(0.2, 0.8, 1.0, 1.0), roster.role .. " (" .. roster.count .. ")")

                                        for i, helperName in ipairs(roster.members) do
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
                                                addNotification("Scheduled removal of "..helperName, "Info", 2)
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
                                        table.sort(indices, function(a,b) return a > b end)
                                        for _, i in ipairs(indices) do
                                            local removedName = table.remove(roster.members, i)
                                            roster.count = #roster.members
                                            addNotification("Removed "..removedName, "Success", 3)
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
                                addNotification("Fetching whitelist from forum...", "Info", 2)
                                local cookies, helperList = authenticateForum()
                                if helperList then
                                    for role, data in pairs(helperList) do
                                        if not HelperRoster[role] then
                                            HelperRoster[role] = {members = {}, count = 0}
                                        end
                                        for _, name in ipairs(data.members) do
                                            local exists = false
                                            for _, existingName in ipairs(HelperRoster[role].members) do
                                                if existingName:lower() == name:lower() then
                                                    exists = true
                                                    break
                                                end
                                            end
                                            if not exists then
                                                table.insert(HelperRoster[role].members, name)
                                            end
                                        end
                                        HelperRoster[role].count = #HelperRoster[role].members
                                    end
                                    addNotification("Whitelist refreshed from forum", "Success", 3)
                                else
                                    addNotification("Failed to refresh whitelist", "Error", 3)
                                end
                            end)
                        end

                        imgui.SameLine()

                        if imgui.Button("Save Whitelist##") then
                            addNotification("Whitelist saved to file", "Success", 3)
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
                                            addNotification("Definition added", "Success", 3)
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
                                                    addNotification("Location removed", "Success", 3)
                                                end)
                                                if not success_write then
                                                    addNotification("Write failed", "Error", 3)
                                                end
                                            else
                                                addNotification("File error: "..tostring(err_file), "Error", 3)
                                            end
                                        end)
                                        if not success_remove then
                                            addNotification("Remove error", "Error", 3)
                                        end
                                    end
                                    
                                    imgui.Separator()
                                end
                            end
                            imgui.EndChild()
                        end
                    end)
                    if not success then
                        addNotification("Location tab error: "..tostring(err), "Error", 3)
                    end
                
                elseif adminSettings.SelectedTab == "Tour" then
                    local success, err = pcall(function()
                        imgui.TextColored(imgui.ImVec4(1.0, 1.0, 0.0, 1.0), "Server Tour Management")
                        
                        imgui.Text("Tour Locations:")
                        
                        for i, location in ipairs(ServerTour.Locations) do
                            imgui.PushID("tourloc"..i)
                            
                            imgui.Text(string.format("%d. %s", i, location.name))
                            imgui.SameLine()
                            if imgui.SmallButton("Edit##editloc") then

                            end
                            imgui.SameLine()
                            if imgui.SmallButton("Remove##remloc") then
                                local success_remove = pcall(function()
                                    table.remove(ServerTour.Locations, i)
                                    addNotification("Tour location removed", "Success", 3)
                                end)
                                if not success_remove then
                                    addNotification("Remove error", "Error", 3)
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
                                    
                                    addNotification("Tour location added", "Success", 3)
                                end
                            end)
                            if not success_add then
                                addNotification("Add error: "..tostring(err_add), "Error", 3)
                            end
                            pcall(refreshconfigspath)
                        end
                        
                        imgui.Separator()
                        
                        if imgui.Button("Save Tour Configuration") then
                            local success_save = pcall(function()
                                addNotification("Tour configuration saved", "Success", 3)
                            end)
                            if not success_save then
                                addNotification("Save error", "Error", 3)
                            end
                        end
                    end)
                    if not success then
                        addNotification("Tour tab error: "..tostring(err), "Error", 3)
                    end
                end
                
                imgui.EndChild()
                imgui.End()
            end
    end
    imgui.PopStyleVar(3)
    imgui.PopStyleColor(7)
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

function sampev.onServerMessage(color, text)
    --print("Color: " .. color .. " Text: " .. text)
    if color == -1446714113 and text == "Establishing connection to the {FFA500}Horizon Roleplay {A9C4E4}database - please wait a moment..." then

    end
    if text:match("HelpCmd:") then
        --sampAddChatMessage(string.format("Color: %s | Text: %s", tostring(color), text), -1)
    end 
    if color == -5963606 then
        if text:match("Welcome to Horizon Roleplay, (.-)") then
        end
    end
    if text == "There are no active help requests right now." and color == -1347440726 then
        helpRequests = {} 
        --return false
    end

    if color == -8388353 then
        local helper, name, id = text:match("HelpCmd: (.-) has trashed (.-)'s %(ID: (%d+)%) help request.")
        if helper and name and id then
        local requestKey = id .. ":" .. name
            if helpRequests[requestKey] and not helpRequests[requestKey].IsStatus then
                helpRequests[requestKey].IsStatus = true
                helpRequests[requestKey].isHandled = true
            end
            addNotification(string.format("%s has trashed %s's (ID: %s) help request", helper, name, id), "RequestTrashed", 5)
        end
    
        local helper, name, id = text:match("HelpCmd: (.-) has accepted (.-)'s %(ID: (%d+)%) help request.")
        if helper and name and id then
            local requestKey = id .. ":" .. name
            if helpRequests[requestKey] and not helpRequests[requestKey].IsStatus then
                helpRequests[requestKey].IsStatus = true
                helpRequests[requestKey].isHandled = true
            end
            addNotification(string.format("%s has accepted %s's (ID: %s) help request", helper, name, id), "RequestAccepted", 5)
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

    if color == 869072810 and not HasHelperRoster then
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
            updateHelperName(role, name, string.format("| Requestes: %s | Tours: %s |", requests, tours))
        elseif jrole and jname and chats then
            updateHelperName(jrole, jname, string.format("| Newbie Chats: %s |", chats))
        elseif text:match("^_+$") then
            HasHelperRoster = true
        end

        if HasHelperStatsLoaded then
            return false
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
    local showtime = duration or 5
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
    local cx, cy, cz = getCharCoordinates(PLAYER_PED)
    addOneOffSound(cx, cy, cz, 1139)
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

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

function main()
    while not isSampAvailable() do wait(100) end

    local update_available, version_or_error, changelog = checkUpdate()
    if update_available then
        addNotification(string.format("There's an update available to v%s", version_or_error), "Update", 30)
    end

    local PlayerName = getPlayerNameSafe()
    local authSuccess, playerRole, Team = authenticateAndCheckWhitelist()
    if not authSuccess then
        addNotification(string.format("Hello %s, you are not part of the %s, therefore you can't use this modification.", PlayerName, Team), "Error", 8)
        return
    end

    if authSuccess and PlayerName and playerRole and Team then
        addNotification(string.format("Hello %s, You have been verified as %s of the %s, you can use this modification", PlayerName, playerRole, Team), "Success", 8)
        
    sampAddChatMessage(string.format("[Helper-Kit] {FFFFFF}Hello {33CCFF}%s{FFFFFF}, You have been verified as {33CCFF}%s{FFFFFF} of the {33CCFF}%s.", PlayerName, playerRole, Team), 0x33ccff)

    HelperRole = playerRole
    end

    refreshconfigspath()

    imgui.Process = true
    imgui.ShowCursor = false
	imgui.SetMouseCursor(-1)

    sampRegisterChatCommand('debugauth', function()
        for List, Admins in pairs(adminSettings.AdminsList) do
            if Admins == PlayerName then
                lua_thread.create(function()
                    sampAddChatMessage("{FFFF00}Testing verification patterns...", -1)
                    
                    local cookies, err = authenticateForum()
                    if cookies then
                        sampAddChatMessage("{00FF00}Verification successful!", -1)
                    else
                        sampAddChatMessage("{FF0000}Verification failed: "..tostring(err), -1)
                        sampAddChatMessage("{FFFF00}Check protected_page_failed.html", -1)
                    end
                end)
            end
        end
    end)

    sampRegisterChatCommand('checkmyvef', function()
        for List, Admins in pairs(adminSettings.AdminsList) do
            if Admins == PlayerName then
                if not authSuccess then
                    addNotification(string.format("Hello %s, you are not part of the Helper Team, therefore you can't use this modification.", PlayerName), "Error", 8)
                    return
                end
            
                addNotification(string.format("Hello %s, You have been verified as %s of the Helper Team.", PlayerName, playerRole), "Success", 8)
                    
                sampAddChatMessage(string.format("[Helper-Kit] {FFFFFF}Hello {33CCFF}%s{FFFFFF}, You have been verified as %s of the Helper Team.", PlayerName, playerRole), 0x33ccff)
            
            end
        end
    end)
    
    sampRegisterChatCommand('def', cmdDef)
    sampRegisterChatCommand('notify', addNotification)
    sampRegisterChatCommand('loc', cmdLoc)
    sampRegisterChatCommand('sst', startServerTour)
    sampRegisterChatCommand('est', exitServerTour)
    sampRegisterChatCommand('hkit', function()
        SelectedSettings.Tab = 0
        Settings.Visible.Main.v = not Settings.Visible.Main.v
        imgui.ShowCursor = not imgui.ShowCursor
    end)
    
    sampRegisterChatCommand('addloc', cmdaddloc)
    sampRegisterChatCommand('n', cmdN)
    sampRegisterChatCommand('addhr', function (msg)
        local args = {}
        
        for word in msg:gmatch("%S+") do
            table.insert(args, word)
        end

        args[2] = args[2]:gsub("_", " ")
    
        local key = args[1] .. ":" .. args[2]
        
        helpRequests[key] = {
            name = args[2],
            id = args[1],
            message = "Help Request Test Number: " .. args[1],
            notification = false
        }
    
        addNotification(string.format("%s (ID:%s) has requested a help! message: %s", helpRequests[key].name, helpRequests[key].id, helpRequests[key].message), "Helprequest", 10)
    end)

    sampRegisterChatCommand('reloadhk', function()
        thisScript():reload()
        sampAddChatMessage("[Helper-Kit] {FFFFFF}Script has been reloaded!", 0x33ccff)
    end)
    sampRegisterChatCommand('hrs', cmdHrs)
    sampRegisterChatCommand('ahr', cmdAhr)
    sampRegisterChatCommand('hkhelp', cmdHkhelp)
    sampRegisterChatCommand('lvl1s', cmdLvl1s)
    sampRegisterChatCommand('fetchwl', fetchWhitelistFromForum)

    lua_thread.create(function()
        while true do
            wait(5000)  
            if not isLoadingInterior and helprequsttimer <= localClock() - last_request then
                last_request = localClock()
                pcall(function()
                    updateHelpRequests()
                end)
            end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(5000)
    
            for key, request in pairs(helpRequests) do
                if request.isHandled then
                    helpRequests[key] = nil
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
