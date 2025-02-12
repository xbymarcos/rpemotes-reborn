local isSearching = false
local rightPosition = { x = 1430, y = 200 }
local leftPosition = { x = 0, y = 200 }
local menuPosition = { x = 0, y = 200 }
local menuHeader = "shopui_title_sm_hangar"

if GetAspectRatio() > 2.0 then
    rightPosition = { x = 1200, y = 100 }
    leftPosition = { x = -250, y = 100 }
end

if Config.MenuPosition then
    if Config.MenuPosition == "left" then
        menuPosition = leftPosition
    elseif Config.MenuPosition == "right" then
        menuPosition = rightPosition
    end
end

if Config.CustomMenuEnabled then
    local txd = CreateRuntimeTxd('Custom_Menu_Head')
    CreateRuntimeTextureFromImage(txd, 'Custom_Menu_Head', 'header.png')
    menuHeader = "Custom_Menu_Head"
end

local _menuPool = NativeUI.CreatePool()
local mainMenu = NativeUI.CreateMenu(Config.MenuTitle or "", "", menuPosition.x, menuPosition.y, menuHeader, menuHeader)
_menuPool:Add(mainMenu)

local menuTables = {}
local isSearching = false
local FavoriteEmote = ""

-- Animation type handlers
local AnimationHandlers = {
    animation = {
        createMenuItem = function(menu, emoteData, emoteKey)
            return NativeUI.CreateItem(emoteData[3], "/e (" .. emoteKey .. ")")
        end,
        onSelect = function(emoteKey, category, dataTable)
            EmoteMenuStart(emoteKey, "normalemote", nil, dataTable)
        end,
        onIndexChange = function(emoteKey, category, dataTable)
            if Config.PreviewPed then
                ClearPedTaskPreview()
                EmoteMenuStartClone(emoteKey, "normalemote", dataTable)
            end
        end
    },
    animation_with_options = {
        createMenuItem = function(menu, emoteData, emoteKey)
            if emoteData.AnimationOptions and emoteData.AnimationOptions.PropTextureVariations then
                return NativeUI.CreateListItem(emoteData[3],
                    emoteData.AnimationOptions.PropTextureVariations,
                    1,
                    "/e (" .. emoteKey .. ")")
            end
            return NativeUI.CreateItem(emoteData[3], "/e (" .. emoteKey .. ")")
        end,
        onSelect = function(emoteKey, textureIndex, dataTable)
            print(emoteKey, textureIndex, dataTable)
            EmoteMenuStart(emoteKey, "propemote", textureIndex, dataTable)
        end,
        onListSelect = function(emoteKey, listIndex, dataTable)
            print(emoteKey, listIndex, dataTable)
            EmoteMenuStart(emoteKey, "propemote", listIndex, dataTable)
        end,
        onIndexChange = function(emoteKey, category, dataTable)
            if Config.PreviewPed then
                ClearPedTaskPreview()
                EmoteMenuStartClone(emoteKey, "propemote", dataTable)
            end
        end
    },
    shared = {
        createMenuItem = function(menu, emoteData, emoteKey)
            local x, y, z, otheremotename = table.unpack(emoteData)
            local desc = "/nearby (~g~" .. emoteKey .. "~w~)" ..
                (otheremotename and " " .. Translate('makenearby') ..
                    " (~y~" .. otheremotename .. "~w~)" or "")
            return NativeUI.CreateItem(z, desc)
        end,
        onSelect = function(emoteKey, _, dataTable)
            local target, distance = GetClosestPlayer()
            if (distance ~= -1 and distance < 3) then
                TriggerServerEvent("ServerEmoteRequest", GetPlayerServerId(target), emoteKey, dataTable)
                SimpleNotify(Translate('sentrequestto') .. GetPlayerName(target))
            else
                SimpleNotify(Translate('nobodyclose'))
            end
        end
    }

}

-- Function to set up menu handlers
local function SetupMenuHandlers(menu, handler, config)
    if handler.onSelect then
        menu.OnItemSelect = function(sender, item, index)
            handler.onSelect(menuTables[config.name][index], config.name, config.dataTable)
        end
    end

    if handler.onIndexChange then
        menu.OnIndexChange = function(menu, newindex)
            handler.onIndexChange(menuTables[config.name][newindex], config.name, config.dataTable)
        end
    end

    if handler.onListSelect then
        menu.OnListSelect = function(menu, item, itemIndex, listIndex)
            handler.onListSelect(menuTables[config.name][itemIndex], listIndex - 1, config.dataTable)
        end
    end
end

-- Function to create subcategory menu
local function CreateSubcategory(parentMenu, subcatConfig, parentName)
    local handler = AnimationHandlers[subcatConfig.type]
    if not handler then return end

    local subcatMenu = _menuPool:AddSubMenu(
        parentMenu,
        Translate(subcatConfig.label),
        subcatConfig.description and Translate(subcatConfig.description) or "",
        true,
        true
    )

    menuTables[subcatConfig.name] = {}

    -- Add items from data table
    for emoteKey, emoteData in PairsByKeys(RP[subcatConfig.dataTable]) do
        local menuItem = handler.createMenuItem(subcatMenu, emoteData, emoteKey)
        subcatMenu:AddItem(menuItem)
        table.insert(menuTables[subcatConfig.name], emoteKey)
    end

    -- Set up event handlers
    SetupMenuHandlers(subcatMenu, handler, subcatConfig)

    -- Create shared submenu if enabled
    if subcatConfig.sharedEnabled and Config.SharedEmotesEnabled then
        CreateSharedSubmenu(parentMenu, subcatConfig, menuTables[subcatConfig.name])
    end

    parentMenu.OnMenuClosed = function(menu)
        ClosePedMenu()
    end
end

-- Function to create menu structure from config
local function CreateMenuFromConfig(parentMenu)
    for _, category in ipairs(Config.MenuCategories) do
        if category.enabled ~= false then
            local submenu = _menuPool:AddSubMenu(
                parentMenu,
                Translate(category.label),
                category.description and Translate(category.description) or "",
                true,
                true
            )

            submenu.OnMenuClosed = function(menu)
                ClosePedMenu()
            end

            menuTables[category.name] = {}

            -- Add search if enabled
            if Config.Search and category.name == "emotes" then
                submenu:AddItem(NativeUI.CreateItem(Translate('searchemotes'), ""))
                table.insert(menuTables[category.name], Translate('searchemotes'))
            end

            -- Create subcategories
            if category.categories then
                for _, subcat in ipairs(category.categories) do
                    if subcat.enabled ~= false then
                        CreateSubcategory(submenu, subcat, category.name)
                    end
                end
            end
        end
    end
end


if Config.Search then
    local ignoredCategories = {
        ["Walks"] = true,
        ["Expressions"] = true,
        ["Shared"] = not Config.SharedEmotesEnabled
    }

    function EmoteMenuSearch(lastMenu)
        ClosePedMenu()
        local favEnabled = not Config.SqlKeybinding and Config.FavKeybindEnabled
        AddTextEntry("PM_NAME_CHALL", Translate('searchinputtitle'))
        DisplayOnscreenKeyboard(1, "PM_NAME_CHALL", "", "", "", "", "", 30)
        while UpdateOnscreenKeyboard() == 0 do
            DisableAllControlActions(0)
            Wait(100)
        end
        local input = GetOnscreenKeyboardResult()
        if input ~= nil then
            local results = {}
            for k, v in pairs(RP) do
                if not ignoredCategories[k] then
                    for a, b in pairs(v) do
                        if string.find(string.lower(a), string.lower(input)) or (b[3] ~= nil and string.find(string.lower(b[3]), string.lower(input))) then
                            table.insert(results, { table = k, name = a, data = b })
                        end
                    end
                end
            end

            if #results > 0 then
                isSearching = true

                local searchMenu = _menuPool:AddSubMenu(lastMenu,
                    string.format('%s ' .. Translate('searchmenudesc') .. ' ~r~%s~w~', #results, input), "", true, true)
                local sharedDanceMenu
                if favEnabled then
                    searchMenu:AddItem(NativeUI.CreateItem(Translate('rfavorite'), Translate('rfavorite')))
                end

                if Config.SharedEmotesEnabled then
                    sharedDanceMenu = _menuPool:AddSubMenu(searchMenu, Translate('sharedanceemotes'), "", true, true)
                end

                table.sort(results, function(a, b) return a.name < b.name end)
                for k, v in pairs(results) do
                    local desc = ""
                    if v.table == "Shared" then
                        local otheremotename = v.data[4]
                        if otheremotename == nil then
                            desc = "/nearby (~g~" .. v.name .. "~w~)"
                        else
                            desc = "/nearby (~g~" ..
                                v.name .. "~w~) " .. Translate('makenearby') .. " (~y~" .. otheremotename .. "~w~)"
                        end
                    else
                        desc = "/e (" .. v.name .. ")" .. (favEnabled and "\n" .. Translate('searchshifttofav') or "")
                    end

                    if v.data.AnimationOptions and v.data.AnimationOptions.PropTextureVariations then
                        searchMenu:AddItem(NativeUI.CreateListItem(v.data[3],
                            v.data.AnimationOptions.PropTextureVariations, 1, desc))
                    else
                        searchMenu:AddItem(NativeUI.CreateItem(v.data[3], desc))
                    end

                    if v.table == "Dances" and Config.SharedEmotesEnabled then
                        sharedDanceMenu:AddItem(NativeUI.CreateItem(v.data[3], ""))
                    end
                end

                if favEnabled then
                    table.insert(results, 1, Translate('rfavorite'))
                end


                searchMenu.OnMenuChanged = function(menu, newmenu, forward)
                    isSearching = false
                    ShowPedMenu()
                end


                searchMenu.OnIndexChange = function(menu, newindex)
                    local data = results[newindex]

                    ClearPedTaskPreview()
                    if data.table == "Emotes" or data.table == "Dances" then
                        EmoteMenuStartClone(data.name, string.lower(data.table))
                    elseif data.table == "PropEmotes" then
                        EmoteMenuStartClone(data.name, "props")
                    elseif data.table == "AnimalEmotes" then
                        EmoteMenuStartClone(data.name, "animals")
                    end
                end


                searchMenu.OnItemSelect = function(sender, item, index)
                    local data = results[index]

                    if data == Translate('sharedanceemotes') then return end
                    if data == Translate('rfavorite') then
                        FavoriteEmote = ""
                        SimpleNotify(Translate('rfavorite'))
                        return
                    end

                    if favEnabled and IsControlPressed(0, 21) then
                        if data.table ~= "Shared" then
                            FavoriteEmote = data.name
                            SimpleNotify("~o~" .. FirstToUpper(data.name) .. Translate('newsetemote'))
                        else
                            SimpleNotify(Translate('searchcantsetfav'))
                        end
                    elseif data.table == "Emotes" or data.table == "Dances" then
                        EmoteMenuStart(data.name, string.lower(data.table))
                    elseif data.table == "PropEmotes" then
                        EmoteMenuStart(data.name, "props")
                    elseif data.table == "AnimalEmotes" then
                        EmoteMenuStart(data.name, "animals")
                    elseif data.table == "Shared" then
                        local target, distance = GetClosestPlayer()
                        if (distance ~= -1 and distance < 3) then
                            TriggerServerEvent("ServerEmoteRequest", GetPlayerServerId(target), data.name)
                            SimpleNotify(Translate('sentrequestto') .. GetPlayerName(target))
                        else
                            SimpleNotify(Translate('nobodyclose'))
                        end
                    end
                end

                searchMenu.OnListSelect = function(menu, item, itemIndex, listIndex)
                    EmoteMenuStart(results[itemIndex].name, "props", item:IndexToItem(listIndex).Value)
                end

                if Config.SharedEmotesEnabled then
                    if #sharedDanceMenu.Items > 0 then
                        table.insert(results, (favEnabled and 2 or 1), Translate('sharedanceemotes'))
                        sharedDanceMenu.OnItemSelect = function(sender, item, index)
                            if not LocalPlayer.state.canEmote then return end

                            local data = results[index]
                            local target, distance = GetClosestPlayer()
                            if (distance ~= -1 and distance < 3) then
                                TriggerServerEvent("ServerEmoteRequest", GetPlayerServerId(target), data.name, 'Dances')
                                SimpleNotify(Translate('sentrequestto') .. GetPlayerName(target))
                            else
                                SimpleNotify(Translate('nobodyclose'))
                            end
                        end
                    else
                        sharedDanceMenu:Clear()
                        searchMenu:RemoveItemAt((favEnabled and 2 or 1))
                    end
                end

                searchMenu.OnMenuClosed = function()
                    searchMenu:Clear()
                    lastMenu:RemoveItemAt(#lastMenu.Items)
                    _menuPool:RefreshIndex()
                    results = {}
                end

                _menuPool:RefreshIndex()
                _menuPool:CloseAllMenus()
                searchMenu:Visible(true)
                ShowPedMenu()
            else
                SimpleNotify(string.format(Translate('searchnoresult') .. ' ~r~%s~w~', input))
            end
        end
    end
end

function AddCancelEmote(menu)
    local newitem = NativeUI.CreateItem(Translate('cancelemote'), Translate('cancelemoteinfo'))
    menu:AddItem(newitem)
    newitem.Activated = function()
        EmoteCancel()
        DestroyAllProps()
    end
end

ShowPedPreview = function(menu)
    menu.OnItemSelect = function(sender, item, index)
        if (index == 1) then
            isSearching = false
            ShowPedMenu()
        elseif index == 4 then
            ShowPedMenu(true)
        end
    end
end

function AddWalkMenu(menu)
    local submenu = _menuPool:AddSubMenu(menu, Translate('walkingstyles'), "", true, true)

    -- Need to inizialitze the table
    menuTables["Walk"] = {}

    local walkreset = NativeUI.CreateItem(Translate('normalreset'), Translate('resetdef'))
    submenu:AddItem(walkreset)

    table.insert(menuTables["Walk"], Translate('resetdef'))

    local sortedWalks = {}
    for a, b in PairsByKeys(RP.Walks) do
        local x, label = table.unpack(b)
        if x == "move_m@injured" then
            table.insert(sortedWalks, 1, { label = label or a, anim = x })
        else
            table.insert(sortedWalks, { label = label or a, anim = x })
        end
    end

    for _, walk in ipairs(sortedWalks) do
        submenu:AddItem(NativeUI.CreateItem(walk.label, "/walk (" .. string.lower(walk.label) .. ")"))
        table.insert(menuTables["Walk"], walk.anim)
    end

    submenu.OnItemSelect = function(sender, item, index)
        if item == walkreset then
            ResetWalk()
            DeleteResourceKvp("walkstyle")
        else
            WalkMenuStart(menuTables["Walk"][index])
        end
    end
end

function AddFaceMenu(menu)
    local submenu = _menuPool:AddSubMenu(menu, Translate('moods'), "", true, true)

    -- Need to inizialitze the table
    menuTables["Face"] = {}

    local facereset = NativeUI.CreateItem(Translate('normalreset'), Translate('resetdef'))
    submenu:AddItem(facereset)
    table.insert(menuTables["Face"], "")

    for name, data in PairsByKeys(RP.Expressions) do
        local faceitem = NativeUI.CreateItem(data[2] or name, "")
        submenu:AddItem(faceitem)
        table.insert(menuTables["Face"], name)
    end


    submenu.OnMenuClosed = function(menu)
        ClosePedMenu()
    end

    submenu.OnIndexChange = function(menu, newindex)
        EmoteMenuStartClone(menuTables["Face"][newindex], "expression")
    end

    submenu.OnItemSelect = function(sender, item, index)
        if item ~= facereset then
            EmoteMenuStart(menuTables["Face"][index], "expression")
        else
            DeleteResourceKvp("expression")
            ClearFacialIdleAnimOverride(PlayerPedId())
        end
    end
end

function AddInfoMenu(menu)
    infomenu = _menuPool:AddSubMenu(menu, Translate('infoupdate'), "~h~~y~The RPEmotes Team & Collaborators~h~~y~", true,
        true)

    for _, v in ipairs(Config.Credits) do
        local item = NativeUI.CreateItem(v.title, v.subtitle or "")
        infomenu:AddItem(item)
    end
end

LoadAddonEmotes()
-- Initialize menu
CreateMenuFromConfig(mainMenu)
AddCancelEmote(mainMenu)
if Config.PreviewPed then
    ShowPedPreview(mainMenu)
end

if Config.WalkingStylesEnabled then
    AddWalkMenu(mainMenu)
end

if Config.ExpressionsEnabled then
    AddFaceMenu(mainMenu)
end

AddInfoMenu(mainMenu)
_menuPool:RefreshIndex()

-- Menu processing
local isMenuProcessing = false
function ProcessMenu()
    if isMenuProcessing then return end
    isMenuProcessing = true
    while _menuPool:IsAnyMenuOpen() do
        _menuPool:ProcessMenus()
        Wait(0)
    end
    isMenuProcessing = false
end

-- Event handlers
RegisterNetEvent("rp:Update", function(state)
    UpdateAvailable = state
    AddInfoMenu(mainMenu)
    _menuPool:RefreshIndex()
end)

function OpenEmoteMenu()
    if IsEntityDead(PlayerPedId()) then
        -- show in chat
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = { "RPEmotes", Translate('dead') }
        })
        return
    end
    if (IsPedSwimming(PlayerPedId()) or IsPedSwimmingUnderWater(PlayerPedId())) and not Config.AllowInWater then
        -- show in chat
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = { "RPEmotes", Translate('swimming') }
        })
        return
    end
    if _menuPool:IsAnyMenuOpen() then
        _menuPool:CloseAllMenus()
    else
        mainMenu:Visible(true)
        ProcessMenu()
    end
end

RegisterNetEvent("rp:RecieveMenu", function()
    OpenEmoteMenu()
end)


-- Menu state check thread
CreateThread(function()
    while true do
        Wait(500)
        if IsEntityDead(PlayerPedId()) then
            _menuPool:CloseAllMenus()
        end
        if (IsPedSwimming(PlayerPedId()) or IsPedSwimmingUnderWater(PlayerPedId()))
            and not Config.AllowInWater then
            if IsInAnimation then
                EmoteCancel()
            end
            _menuPool:CloseAllMenus()
        end
    end
end)
