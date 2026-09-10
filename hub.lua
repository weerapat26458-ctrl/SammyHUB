local HttpService = game:GetService("HttpService")
-- ==============================================
-- Unload Old Instances
-- ==============================================
if getgenv()._AutoRollRunning then
    getgenv()._AutoRollRunning = false
    task.wait(0.5)
end
getgenv()._AutoRollRunning = true

pcall(function()
    local MarketplaceService = game:GetService("MarketplaceService")
    local mt = getrawmetatable(game)
    if mt and mt.__namecall then
        local oldNamecall = mt.__namecall
        if setreadonly then setreadonly(mt, false) end
        
        mt.__namecall = function(self, ...)
            local method = getnamecallmethod()
            if self == MarketplaceService and (method == "PromptProductPurchase" or method == "PromptPurchase" or method == "PromptGamePassPurchase" or method == "PromptPremiumPurchase") then
                if _G_State and (_G_State.AutoUpgrade or _G_State.AutoPrestige) then
                    return nil
                end
            end
            return oldNamecall(self, ...)
        end
        if setreadonly then setreadonly(mt, true) end
    end
end)

pcall(function()
    local coreGui = game:GetService("CoreGui")
    task.spawn(function()
        while task.wait(0.2) do
            if _G_State and (_G_State.AutoUpgrade or _G_State.AutoPrestige) then
                pcall(function()
                    local pp = coreGui:FindFirstChild("PurchasePrompt")
                    if pp then
                        for _, btn in ipairs(pp:GetDescendants()) do
                            if btn:IsA("ImageButton") or btn:IsA("TextButton") then
                                local nm = string.lower(btn.Name)
                                local txt = ""
                                pcall(function() txt = string.lower(tostring(btn.Text)) end)
                                
                                if nm:match("close") or nm:match("cancel") or nm == "x" or txt:match("cancel") or txt:match("close") then
                                    if getconnections then
                                        for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
                                        for _, conn in ipairs(getconnections(btn.Activated)) do conn:Fire() end
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end
    end)
end)

if getgenv()._RayfieldWindow then
    pcall(function()
        local coreGui = game:GetService("CoreGui")
        for _, ui in pairs(coreGui:GetChildren()) do
            if ui.Name == "Rayfield" then
                ui:Destroy()
            end
        end
    end)
end

-- ==============================================
-- Fetch Database
-- ==============================================
local RS = game:GetService("ReplicatedStorage")
local ConfirmedRollRequest = RS:FindFirstChild("ConfirmedRollRequestEvent", true)

local UnitDB, TraitDB
local UnitsByRarity = {
    Common = {}, Uncommon = {}, Rare = {}, Epic = {},
    Legendary = {}, Mythic = {}, Secret = {},
    Divine = {}, Cosmic = {}, Exclusive = {}, Limited = {}, Unknown = {}
}
local BuffList = {"Diamond", "Gold", "Angelic", "Genius", "Blossom", "Honored"}

pcall(function()
    local dbFolder = RS:WaitForChild("Databases", 5)
    if dbFolder then
        local uDB = dbFolder:FindFirstChild("UnitDatabase")
        if uDB then UnitDB = require(uDB) end
        
        local tDB = dbFolder:FindFirstChild("TraitDatabase")
        if tDB then TraitDB = require(tDB) end
    end
end)

-- Group by Rarity
if UnitDB then
    for id, data in pairs(UnitDB) do
        if type(data) == "table" then
            local name = tostring(data.Name or data.DisplayName or id)
            local rarity = tostring(data.Rarity or "Unknown")
            if not UnitsByRarity[rarity] then UnitsByRarity[rarity] = {} end
            table.insert(UnitsByRarity[rarity], name)
        end
    end
else
    UnitsByRarity.Mythic = {"Blood"}
    UnitsByRarity.Common = {"Sange", "Gobu"}
end


local UI_BuffOptions = {"Any", "No Buff"}
for _, b in ipairs(BuffList) do table.insert(UI_BuffOptions, b) end

-- ==============================================
-- State Variables
-- ==============================================
local _G_State = {
    AutoRoll = false,
    RollDelay = 2.5,
    AutoBuy = false,
    CheckDelay = 0.5,
    BuyRarities = {},
    BuyAll = {},
    BuyChars = {},
    BuyBuffs = {},
    AutoZone = false,
    ZoneDelay = 2,
    AutoPotion = false,
    PotionTypes = {},
    AutoChallenge = false,
    ChallengeTypes = {},
    InChallenge = false
}

for rarity, _ in pairs(UnitsByRarity) do
    _G_State.BuyAll[rarity] = false
    _G_State.BuyChars[rarity] = {}
    _G_State.BuyBuffs[rarity] = {"Any"}
end

-- ==============================================
-- Helper Functions
-- ==============================================
local function getOwnBase(player)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local closestPrompt = nil
    local minDist = math.huge
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and (prompt.ActionText == "Roll" or prompt.ActionText == "Collect") then
            local part = prompt.Parent
            if part and part:IsA("BasePart") then
                local dist = (root.Position - part.Position).Magnitude
                if dist < minDist and dist < 50 then
                    minDist = dist
                    closestPrompt = prompt
                end
            end
        end
    end
    if closestPrompt then
        local current = closestPrompt
        local bestModel = current.Parent
        while current and current ~= workspace do
            if current:IsA("Model") then
                bestModel = current
            end
            current = current.Parent
        end
        return bestModel
    end
    return nil
end

local function isPlayersObject(obj, player)
    local base = getOwnBase(player)
    if base then
        if obj:IsDescendantOf(base) then return true end
    end

    local current = obj
    while current and current ~= game do
        local lowerCurrent = string.lower(current.Name)
        local lowerPlayer = string.lower(player.Name)
        
        if lowerCurrent == lowerPlayer or lowerCurrent == lowerPlayer .. "'s stand" or current.Name == tostring(player.UserId) then
            return true
        end
        
        local ownerVal = current:FindFirstChild("Owner") or current:FindFirstChild("owner") or current:FindFirstChild("OwnerUserId")
        if ownerVal then
            if ownerVal:IsA("ObjectValue") and ownerVal.Value == player then return true end
            if (ownerVal:IsA("StringValue") or ownerVal:IsA("IntValue")) and (ownerVal.Value == player.Name or tostring(ownerVal.Value) == tostring(player.UserId)) then return true end
        end
        current = current.Parent
    end
    return false
end

local function isGameInChallenge()
    local player = game:GetService("Players").LocalPlayer
    if not player then return false end
    
    if player:GetAttribute("InChallenge") == true then return true end
    if player:GetAttribute("ChallengeMode") == true then return true end
    
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        local chalHUD = playerGui:FindFirstChild("ChallengeHUD") or playerGui:FindFirstChild("ChallengeHUD", true)
        if chalHUD then
            if chalHUD:IsA("ScreenGui") and chalHUD.Enabled then return true end
            if chalHUD:IsA("Frame") and chalHUD.Visible and chalHUD.AbsolutePosition.X > 0 then return true end
        end
    end
    return false
end

local function getUnitRarity(unitName)
    if UnitDB then
        for id, data in pairs(UnitDB) do
            if type(data) == "table" then
                local nameInDB = tostring(data.Name or data.DisplayName or id)
                if nameInDB == unitName or string.find(unitName, nameInDB) then
                    return tostring(data.Rarity)
                end
            end
        end
    end
    return "Unknown"
end

local function getUnitBuffs(model)
    local buffs = {}
    for _, obj in pairs(model:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local text = obj.Text
            for _, buffName in ipairs(BuffList) do
                if string.find(string.lower(text), string.lower(buffName)) then
                    table.insert(buffs, buffName)
                end
            end
        end
    end
    return buffs
end

-- ==============================================
-- Fluent UI System
-- ==============================================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

-- Clean UI
if getgenv()._FluentWindow then
    pcall(function()
        for _, ui in pairs(game:GetService("CoreGui"):GetChildren()) do
            if ui:FindFirstChild("Frame") and ui.Frame:FindFirstChild("CanvasGroup") then
                ui:Destroy()
            end
        end
    end)
end

-- ==============================================
-- Anti-Robux Prompt
-- ==============================================
pcall(function()
    if not getgenv()._RobuxHooked then
        getgenv()._RobuxHooked = true
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if _G_State.AutoZone and (method == "PromptProductPurchase" or method == "PromptPurchase" or method == "PromptGamePassPurchase") then
                return -- Block robux purchase
            end
            return oldNamecall(self, ...)
        end)
    end
end)

-- ==============================================
-- Anti-Roll Warning
-- ==============================================
pcall(function()
    if not getgenv()._AntiWarningHooked then
        getgenv()._AntiWarningHooked = true
        local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        
        local function handleDescendant(desc)
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local function onTextChanged()
                    local text = tostring(desc.Text)
                    if string.find(text, "Roll Warning") or string.find(text, "Roll Anyway") then
                        -- Find Root UI
                        local rootUI = desc.Parent
                        for i = 1, 5 do
                            if rootUI and rootUI.Parent and not rootUI:IsA("ScreenGui") and rootUI.Parent.Name ~= "PlayerGui" then
                                rootUI = rootUI.Parent
                            else
                                break
                            end
                        end
                        
                        if rootUI then
                            if rootUI:IsA("ScreenGui") then rootUI.Enabled = false else rootUI.Visible = false end
                            
                            -- Lock visibility
                            local prop = rootUI:IsA("ScreenGui") and "Enabled" or "Visible"
                            rootUI:GetPropertyChangedSignal(prop):Connect(function()
                                if rootUI[prop] then rootUI[prop] = false end
                            end)
                        end
                        
                        -- Click Roll Anyway
                        if string.find(text, "Roll Anyway") then
                            local btn = desc
                            if desc:IsA("TextLabel") and desc.Parent:IsA("GuiButton") then btn = desc.Parent end
                            if btn:IsA("GuiButton") and getconnections then
                                for _, c in pairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
                                for _, c in pairs(getconnections(btn.Activated)) do c:Fire() end
                            end
                        end
                    end
                end
                onTextChanged()
                desc:GetPropertyChangedSignal("Text"):Connect(onTextChanged)
            end
        end
        
        for _, desc in pairs(playerGui:GetDescendants()) do handleDescendant(desc) end
        playerGui.DescendantAdded:Connect(handleDescendant)
    end
end)


local function LoadFluentUI()
    local Window = Fluent:CreateWindow({
        Title = "SAMMYHUB",
        SubTitle = "Defeat Anime RNG",
        TabWidth = 160,
        Size = UDim2.fromOffset(580, 460),
        Acrylic = true,
        Theme = "Darker",
        MinimizeKey = Enum.KeyCode.RightControl
    })
    getgenv()._FluentWindow = Window

    local Tabs = {
        Automation = Window:AddTab({ Title = "Automation", Icon = "home" }),
        Buy = Window:AddTab({ Title = "Auto Buy", Icon = "shopping-cart" }),
        Fuse = Window:AddTab({ Title = "Auto Fuse", Icon = "zap" }),
        Zone = Window:AddTab({ Title = "Auto Zone", Icon = "map" }),
        Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
    }

    -- ==============================================
    -- Tab 1: Automation
    -- ==============================================
    local RollToggle = Tabs.Automation:AddToggle("AutoRollToggle", {
        Title = "Auto Roll",
        Default = false
    })
    
    RollToggle:OnChanged(function()
        _G_State.AutoRoll = RollToggle.Value
        if _G_State.AutoRoll then
            task.spawn(function()
                while _G_State.AutoRoll and getgenv()._AutoRollRunning do
                    pcall(function()
                        local player = game:GetService("Players").LocalPlayer
                        local rolled = false
                        local character = player.Character
                        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                        for _, prompt in pairs(workspace:GetDescendants()) do
                            if prompt:IsA("ProximityPrompt") and prompt.ActionText == "Roll" then
                                if isPlayersObject(prompt, player) then
                                    local promptPart = prompt.Parent
                                    if rootPart and promptPart and promptPart:IsA("BasePart") then
                                        local maxDist = prompt.MaxActivationDistance or 10
                                        local distance = (rootPart.Position - promptPart.Position).Magnitude
                                        
                                        if distance > maxDist then
                                            rootPart.CFrame = CFrame.new(promptPart.Position + Vector3.new(0, 3, 0))
                                            task.wait(0.1) -- Allow physics and server to register position
                                        end
                                        
                                        fireproximityprompt(prompt)
                                        rolled = true
                                        break
                                    else
                                        fireproximityprompt(prompt)
                                        rolled = true
                                        break
                                    end
                                end
                            end
                        end
                        
                        if rolled then
                            if ConfirmedRollRequest then
                                ConfirmedRollRequest:FireServer()
                            end
                        end
                    end)
                    task.wait(_G_State.RollDelay)
                end
            end)
        end
    end)

    Tabs.Automation:AddSlider("RollDelaySlider", {
        Title = "Roll Delay (s)",
        Default = 2.5,
        Min = 0,
        Max = 5,
        Rounding = 1,
        Callback = function(Value)
            _G_State.RollDelay = Value
        end
    })

    _G_State.AutoPrestige = false
    local PrestigeToggle = Tabs.Automation:AddToggle("AutoPrestigeToggle", {
        Title = "Auto Prestige (Rebirth)",
        Default = false
    })
    
    PrestigeToggle:OnChanged(function()
        _G_State.AutoPrestige = PrestigeToggle.Value
        if _G_State.AutoPrestige then
            task.spawn(function()
                while _G_State.AutoPrestige and getgenv()._AutoRollRunning do
                    pcall(function()
                        local player = game:GetService("Players").LocalPlayer
                        
                        local canPrestige = false
                        local foundPrestigeBtn = nil
                        
                        -- 1. Smart UI Detection (Read "X / Y Levels" text)
                        if player and player:FindFirstChild("PlayerGui") then
                            for _, gui in ipairs(player.PlayerGui:GetDescendants()) do
                                -- Check for Progress Text like "16 / 10 Levels"
                                if gui:IsA("TextLabel") and gui.Visible then
                                    local txt = gui.Text
                                    local curr, req = string.match(txt, "(%d+)%s*/%s*(%d+)%s*Levels?")
                                    if curr and req then
                                        if tonumber(curr) >= tonumber(req) then
                                            canPrestige = true
                                        end
                                    end
                                end
                                
                                -- Find the Prestige button
                                if gui:IsA("TextButton") and gui.Visible then
                                    local txt = string.lower(string.gsub(tostring(gui.Text or gui.ContentText), "<[^>]+>", ""))
                                    if (string.find(txt, "prestige") or string.find(txt, "rebirth")) and not string.find(txt, "shop") and not string.find(txt, "store") then
                                        foundPrestigeBtn = gui
                                    end
                                end
                            end
                        end
                        
                        if canPrestige then
                            -- Method 1: Remote Fire (Fastest but might be changed by devs)
                            local pRemote = RS:FindFirstChild("Prestige", true) or RS:FindFirstChild("PrestigeRequest", true) or RS:FindFirstChild("PrestigeEvent", true)
                            if pRemote then
                                if pRemote:IsA("RemoteEvent") then pRemote:FireServer() else pRemote:InvokeServer() end
                            end
                            
                            -- Method 2: Smart Click (Safest, simulates real player click)
                            if foundPrestigeBtn and getconnections then
                                for _, conn in ipairs(getconnections(foundPrestigeBtn.MouseButton1Click)) do conn:Fire() end
                                for _, conn in ipairs(getconnections(foundPrestigeBtn.Activated)) do conn:Fire() end
                            end
                        end
                    end)
                    task.wait(3) -- Check every 3 seconds
                end
            end)
        end
    end)

    _G_State.AutoUpgrade = false
    local UpgradeToggle = Tabs.Automation:AddToggle("AutoUpgradeToggle", {
        Title = "Auto Upgrade (Skill Tree)",
        Default = false
    })
    
    UpgradeToggle:OnChanged(function()
        _G_State.AutoUpgrade = UpgradeToggle.Value
        if _G_State.AutoUpgrade then
            task.spawn(function()
                while _G_State.AutoUpgrade and getgenv()._AutoRollRunning do
                    pcall(function()
                        local player = game:GetService("Players").LocalPlayer
                        if player and player:FindFirstChild("PlayerGui") then
                            local pRemote = RS:FindFirstChild("UpgradeRequestEvent", true) or RS:FindFirstChild("UpgradePurchase", true) or RS:FindFirstChild("Upgrade", true) or RS:FindFirstChild("pUpgrade", true)
                            
                            if pRemote and player.PlayerGui then
                                -- Load the game's actual upgrade data
                                local success, upgradeConfig = pcall(function()
                                    return require(RS:WaitForChild("Databases"):WaitForChild("UpgradeConfig"))
                                end)
                                
                                if success and type(upgradeConfig) == "table" then
                                    local attrs = player:GetAttributes()
                                    local moneyVal = player:FindFirstChild("Money", true) or (player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Money"))
                                    local currentMoney = attrs.Money or (moneyVal and moneyVal.Value) or 0
                                    
                                    local nodesToBuy = {}

                                    -- Check standard upgrades using hard data
                                    for key, config in pairs(upgradeConfig) do
                                        if type(config) == "table" then
                                            local currentLevel = attrs[key] or 0
                                            local maxLevel = config.MaxLevel or 0
                                            
                                            -- If not maxed
                                            if currentLevel < maxLevel then
                                                local canAfford = false -- Default to false to completely block Robux prompts
                                                
                                                if config.Prices then
                                                    local cost = config.Prices[currentLevel + 1] or config.Prices[tostring(currentLevel + 1)]
                                                    if cost and currentMoney >= cost then
                                                        canAfford = true
                                                    end
                                                elseif config.BasePrice and config.GrowthRate then
                                                    local expOffset = config.ExponentOffset or 0
                                                    local cost = config.BasePrice * math.pow(config.GrowthRate, currentLevel + expOffset)
                                                    if currentMoney >= cost then
                                                        canAfford = true
                                                    end
                                                end
                                                
                                                if canAfford then
                                                    table.insert(nodesToBuy, key)
                                                end
                                            end
                                        end
                                    end

                                    -- Fire remotes for verified affordable upgrades
                                    for _, key in ipairs(nodesToBuy) do
                                        pcall(function()
                                            if pRemote:IsA("RemoteEvent") then pRemote:FireServer(key) else pRemote:InvokeServer(key) end
                                        end)
                                        task.wait(0.05) -- Fast, but safe delay
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(1.5)
                end
            end)
        end
    end)

    -- ==============================================
    -- Auto Potion (Weather Event)
    -- ==============================================
    local PotionToggle = Tabs.Automation:AddToggle("AutoPotionToggle", {
        Title = "Auto Potion (On Weather Event)",
        Default = false
    })

    local PotionDrop = Tabs.Automation:AddDropdown("PotionTypeDrop", {
        Title = "Select Potions",
        Values = {"Luck Potion", "Gold Potion", "XP Potion"},
        Multi = true,
        Default = {}
    })

    PotionDrop:OnChanged(function(Value)
        local selected = {}
        for k, v in pairs(Value) do if v then table.insert(selected, k) end end
        _G_State.PotionTypes = selected
    end)

    PotionToggle:OnChanged(function()
        _G_State.AutoPotion = PotionToggle.Value
        if _G_State.AutoPotion then
            task.spawn(function()
                local lastWeatherState = false
                
                while _G_State.AutoPotion and getgenv()._AutoRollRunning do
                    pcall(function()
                        local player = game:GetService("Players").LocalPlayer
                        local playerGui = player:FindFirstChild("PlayerGui")
                        if not playerGui then return end
                        
                        -- Check if any Weather Event is active (Precise Path Detection)
                        local isWeatherActive = false
                        local statStuff = playerGui:FindFirstChild("StatStuff")
                        if statStuff then
                            local stats = statStuff:FindFirstChild("Stats")
                            if stats then
                                local weatherTimer = stats:FindFirstChild("WeatherTimer")
                                -- Check if the weather timer icon is actually visible on screen
                                if weatherTimer and weatherTimer:IsA("GuiObject") and weatherTimer.Visible then
                                    isWeatherActive = true
                                end
                            end
                        end
                        
                        if isWeatherActive and not lastWeatherState then
                            -- Weather just started! Use potions.
                            local pRemote = RS:FindFirstChild("UsePotion", true) or RS:FindFirstChild("UsePotionRequest", true) or RS:FindFirstChild("UsePotionRequestFunction", true)
                            if pRemote then
                                for _, potion in ipairs(_G_State.PotionTypes) do
                                    for i = 1, 2 do -- Use 2 times
                                        pcall(function()
                                            if pRemote:IsA("RemoteFunction") then
                                                pRemote:InvokeServer(potion)
                                            elseif pRemote:IsA("RemoteEvent") then
                                                pRemote:FireServer(potion)
                                            end
                                        end)
                                        task.wait(0.5)
                                    end
                                end
                            end
                            lastWeatherState = true
                        elseif not isWeatherActive then
                            lastWeatherState = false
                        end
                    end)
                    task.wait(2)
                end
            end)
        end
    end)

    -- ==============================================
    -- Auto Challenges
    -- ==============================================
    local ChallengeToggle = Tabs.Automation:AddToggle("AutoChallengeToggle", {
        Title = "Auto Challenges",
        Default = false
    })

    local ChallengeDrop = Tabs.Automation:AddDropdown("ChallengeTypeDrop", {
        Title = "Challenge Types",
        Values = {"Regular", "Daily", "Weekly"},
        Multi = true,
        Default = {}
    })

    ChallengeDrop:OnChanged(function(Value)
        local selected = {}
        for k, v in pairs(Value) do if v then table.insert(selected, k) end end
        _G_State.ChallengeTypes = selected
    end)

    ChallengeToggle:OnChanged(function()
        _G_State.AutoChallenge = ChallengeToggle.Value
        if _G_State.AutoChallenge then
            task.spawn(function()
                local chalRemote = RS:FindFirstChild("ChallengeStartRequestFunction", true)

                while _G_State.AutoChallenge and getgenv()._AutoRollRunning do
                    pcall(function()
                        if not chalRemote then
                            chalRemote = RS:FindFirstChild("ChallengeStartRequestFunction", true)
                        end
                        if not chalRemote or #_G_State.ChallengeTypes == 0 then return end

                        local player = game:GetService("Players").LocalPlayer

                        for _, chalType in ipairs(_G_State.ChallengeTypes) do
                            if not _G_State.AutoChallenge then break end

                            local started = false
                            local char = player.Character
                            local oldPos = char and char.PrimaryPart and char.PrimaryPart.Position
                            
                            pcall(function()
                                chalRemote:InvokeServer(chalType)
                            end)
                            
                            task.wait(2.5) -- Wait for teleport
                            
                            char = player.Character
                            local newPos = char and char.PrimaryPart and char.PrimaryPart.Position
                            
                            if oldPos and newPos and (oldPos - newPos).Magnitude > 50 then
                                started = true
                            end

                            if not started then continue end

                            _G_State.InChallenge = true
                            task.wait(5)

                            -- Wait for challenge completion (max 600s)
                            local startTime = tick()
                            while (tick() - startTime) < 600 and _G_State.AutoChallenge do
                                task.wait(3)
                                if not isGameInChallenge() then
                                    break
                                end
                            end

                            _G_State.InChallenge = false
                            task.wait(3)
                        end
                    end)
                    task.wait(15)
                end
                _G_State.InChallenge = false
            end)
        end
    end)

    -- ==============================================
    -- Tab 2: Auto Buy (Dynamic)
    -- ==============================================

    local BuyToggle = Tabs.Buy:AddToggle("AutoBuyToggle", {
        Title = "Enable Auto Buy",
        Default = false
    })

    BuyToggle:OnChanged(function()
        _G_State.AutoBuy = BuyToggle.Value
        if _G_State.AutoBuy then
            task.spawn(function()
                while _G_State.AutoBuy and getgenv()._AutoRollRunning do
                    pcall(function()
                        local player = game:GetService("Players").LocalPlayer
                        for _, prompt in pairs(workspace:GetDescendants()) do
                            if prompt:IsA("ProximityPrompt") and prompt.ActionText == "Collect" then
                                if isPlayersObject(prompt, player) then
                                    local unitName = prompt.ObjectText
                                    if unitName == "" or not unitName then unitName = prompt.Parent.Name end
                                    local rarity = getUnitRarity(unitName)
                                    
                                    local shouldCollect = false
                                    if _G_State.BuyRarities[rarity] then
                                        if not _G_State.BuyChars[rarity] or #_G_State.BuyChars[rarity] == 0 or table.find(_G_State.BuyChars[rarity], "All") then
                                            shouldCollect = true
                                        else
                                            for _, selChar in ipairs(_G_State.BuyChars[rarity]) do
                                                if string.find(unitName, selChar, 1, true) then
                                                    shouldCollect = true
                                                    break
                                                end
                                            end
                                        end
                                    end
                                    
                                    if shouldCollect then
                                        local rarityBuffs = _G_State.BuyBuffs[rarity]
                                        if rarityBuffs and #rarityBuffs > 0 and not table.find(rarityBuffs, "Any") then
                                            local hasReqBuff = false
                                            local unitModel = prompt.Parent
                                            if unitModel:IsA("BasePart") then unitModel = unitModel.Parent end
                                            
                                            local foundBuffs = getUnitBuffs(unitModel)
                                            if table.find(rarityBuffs, "No Buff") and #foundBuffs == 0 then
                                                hasReqBuff = true
                                            end
                                            for _, reqBuff in ipairs(rarityBuffs) do
                                                if table.find(foundBuffs, reqBuff) then hasReqBuff = true; break end
                                            end
                                            if not hasReqBuff then shouldCollect = false end
                                        end
                                    end
                                    
                                    if shouldCollect then
                                        fireproximityprompt(prompt)
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(_G_State.CheckDelay)
                end
            end)
        end
    end)

    local orderedRarities = {"Exclusive", "Limited", "Cosmic", "Divine", "Secret", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common", "Unknown"}
    
    local RarityDrop = Tabs.Buy:AddDropdown("BuyRarityFilter", {
        Title = "Rarity Filter",
        Values = orderedRarities,
        Multi = true,
        Default = {}
    })
    
    local BuyDropdowns = {}
    for _, rarity in ipairs(orderedRarities) do
        if UnitsByRarity[rarity] and #UnitsByRarity[rarity] > 0 then
            BuyDropdowns[rarity] = {}
            
            -- Character
            local dropVals = {"All"}
            for _, c in ipairs(UnitsByRarity[rarity]) do table.insert(dropVals, c) end
            
            local charDrop = Tabs.Buy:AddDropdown("BuyChar_" .. rarity, {
                Title = "Character (" .. rarity .. ")",
                Values = dropVals,
                Multi = true,
                Default = {}
            })
            BuyDropdowns[rarity].CharDrop = charDrop
            
            charDrop:OnChanged(function(Value)
                local selected = {}
                for k, v in pairs(Value) do if v then table.insert(selected, k) end end
                _G_State.BuyChars[rarity] = selected
            end)
            
            -- Buff
            local buffDrop = Tabs.Buy:AddDropdown("BuyBuff_" .. rarity, {
                Title = "Buff (" .. rarity .. ")",
                Values = UI_BuffOptions,
                Multi = true,
                Default = {}
            })
            BuyDropdowns[rarity].BuffDrop = buffDrop
            
            buffDrop:OnChanged(function(Value)
                local selected = {}
                for k, v in pairs(Value) do if v then table.insert(selected, k) end end
                _G_State.BuyBuffs[rarity] = selected
            end)
            
            -- Hide frames until selected
            task.spawn(function()
                task.wait(0.5)
                for _, obj in pairs(game:GetService("CoreGui"):GetDescendants()) do
                    if obj:IsA("TextLabel") then
                        if obj.Text == "Character (" .. rarity .. ")" or obj.Text == "Buff (" .. rarity .. ")" then
                            local root = obj
                            while root and root.Parent do
                                if root.Parent:IsA("ScrollingFrame") then break end
                                root = root.Parent
                            end
                            if root and root.Parent and root.Parent:IsA("ScrollingFrame") then
                                local isSelected = RarityDrop.Value and RarityDrop.Value[rarity] == true
                                if string.find(obj.Text, "Character") then
                                    charDrop.UIFrame = root
                                    root.Visible = isSelected
                                else
                                    buffDrop.UIFrame = root
                                    root.Visible = isSelected
                                end
                                
                                pcall(function()
                                    if not root:FindFirstChild("UIScale") then
                                        local scale = Instance.new("UIScale", root)
                                        scale.Scale = 0.92
                                    end
                                end)
                            end
                        end
                    end
                end
            end)
        end
    end
    
    RarityDrop:OnChanged(function(Value)
        local selectedRarities = {}
        for k, v in pairs(Value) do if v then selectedRarities[k] = true end end
        _G_State.BuyRarities = selectedRarities
        
        for r, drops in pairs(BuyDropdowns) do
            if drops.CharDrop and drops.CharDrop.UIFrame then
                drops.CharDrop.UIFrame.Visible = (selectedRarities[r] == true)
            end
            if drops.BuffDrop and drops.BuffDrop.UIFrame then
                drops.BuffDrop.UIFrame.Visible = (selectedRarities[r] == true)
            end
        end
    end)



    -- ==============================================
    -- Tab 3: Auto Fuse
    -- ==============================================
    local FuseRequest = RS:FindFirstChild("FuseRequestFunction", true)
    local allUnitsList = {}
    for rarity, chars in pairs(UnitsByRarity) do
        for _, char in ipairs(chars) do
            table.insert(allUnitsList, char)
        end
    end
    table.sort(allUnitsList)
    
    _G_State.AutoFuse = false
    _G_State.FuseDelay = 2
    _G_State.FuseTargetChar = {"Any"}
    _G_State.FuseTargetBuff = {"Any"}
    _G_State.FuseTargetStars = {"Any"}
    _G_State.FuseKeepLimit = 1

    local UI_FuseChars = {"Any"}
    for _, c in ipairs(allUnitsList) do table.insert(UI_FuseChars, c) end

    local UI_FuseBuffs = {"Any", "No Buff"}
    for _, b in ipairs(BuffList) do table.insert(UI_FuseBuffs, b) end

    local UI_FuseStars = {"Any"}
    for i = 0, 15 do table.insert(UI_FuseStars, tostring(i) .. " Stars") end

    local FuseToggle = Tabs.Fuse:AddToggle("AutoFuseToggle", {
        Title = "Enable Auto Fuse",
        Default = false
    })
    
    FuseToggle:OnChanged(function()
        _G_State.AutoFuse = FuseToggle.Value
        if _G_State.AutoFuse then
            task.spawn(function()
                while _G_State.AutoFuse do
                    local success, err = pcall(function()
                        local player = game:GetService("Players").LocalPlayer
                        local backpack = player:FindFirstChild("Backpack")
                        local fuseRemote = RS:FindFirstChild("FuseRequestFunction", true)
                        
                        if backpack and fuseRemote then
                            local tools = backpack:GetChildren()
                            
                            local function getToolStars(t)
                                local keys = {"Stars", "Star", "Level", "Tier", "Upgrade"}
                                for _, k in ipairs(keys) do
                                    local attr = t:GetAttribute(k)
                                    if attr then return tonumber(attr) or 0 end
                                    local child = t:FindFirstChild(k)
                                    if child and (child:IsA("IntValue") or child:IsA("NumberValue")) then return child.Value end
                                end
                                return 0
                            end
                            
                            local function getToolBuff(t)
                                local keys = {"Buff", "Trait", "Trait1", "Mutation", "Enchant"}
                                for _, k in ipairs(keys) do
                                    local attr = t:GetAttribute(k)
                                    if attr then return tostring(attr) end
                                    local child = t:FindFirstChild(k)
                                    if child and child:IsA("StringValue") then return child.Value end
                                end
                                return "None"
                            end
                            
                            local toolGroups = {}
                            for _, tool in ipairs(tools) do
                                if tool:IsA("Tool") then
                                    local stars = getToolStars(tool)
                                    local buff = getToolBuff(tool)
                                    local key = tool.Name .. "_" .. tostring(stars) .. "_" .. buff
                                    if not toolGroups[key] then toolGroups[key] = {} end
                                    table.insert(toolGroups[key], tool)
                                end
                            end
                            
                            for key, group in pairs(toolGroups) do
                                if #group > _G_State.FuseKeepLimit then
                                    local baseTool = group[1]
                                    local tName = baseTool.Name
                                    local tStars = getToolStars(baseTool)
                                    local tBuff = getToolBuff(baseTool)
                                    
                                    local matchChar = table.find(_G_State.FuseTargetChar, "Any") or table.find(_G_State.FuseTargetChar, tName)
                                    local matchBuff = false
                                    if table.find(_G_State.FuseTargetBuff, "Any") then
                                        matchBuff = true
                                    elseif table.find(_G_State.FuseTargetBuff, "No Buff") and tBuff == "None" then
                                        matchBuff = true
                                    elseif table.find(_G_State.FuseTargetBuff, tBuff) then
                                        matchBuff = true
                                    end
                                    local matchStar = table.find(_G_State.FuseTargetStars, "Any") or table.find(_G_State.FuseTargetStars, tostring(tStars) .. " Stars")
                                    
                                    if matchChar and matchBuff and matchStar then
                                        local toolsToFuse = {}
                                        for i = _G_State.FuseKeepLimit + 1, #group do
                                            table.insert(toolsToFuse, group[i])
                                        end
                                        if #toolsToFuse > 0 then
                                            fuseRemote:InvokeServer(baseTool, toolsToFuse)
                                            task.wait(1)
                                        end
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(_G_State.FuseDelay)
                end
            end)
        end
    end)

    Tabs.Fuse:AddSlider("FuseDelaySlider", {
        Title = "Scan Delay (s)",
        Default = 2,
        Min = 0.5,
        Max = 10,
        Rounding = 1,
        Callback = function(Value)
            _G_State.FuseDelay = Value
        end
    })

    Tabs.Fuse:AddSlider("FuseKeepLimitSlider", {
        Title = "Keep Limit",
        Default = 1,
        Min = 0,
        Max = 20,
        Rounding = 0,
        Callback = function(Value)
            _G_State.FuseKeepLimit = Value
        end
    })

    local FuseCharDrop = Tabs.Fuse:AddDropdown("FuseCharDrop", {
        Title = "Target Character",
        Values = UI_FuseChars,
        Multi = true,
        Default = {}
    })
    FuseCharDrop:OnChanged(function(Value)
        local selected = {}
        for k, v in pairs(Value) do if v then table.insert(selected, k) end end
        _G_State.FuseTargetChar = selected
        if #_G_State.FuseTargetChar == 0 then table.insert(_G_State.FuseTargetChar, "Any") end
    end)

    local FuseBuffDrop = Tabs.Fuse:AddDropdown("FuseBuffDrop", {
        Title = "Target Buff",
        Values = UI_FuseBuffs,
        Multi = true,
        Default = {}
    })
    FuseBuffDrop:OnChanged(function(Value)
        local selected = {}
        for k, v in pairs(Value) do if v then table.insert(selected, k) end end
        _G_State.FuseTargetBuff = selected
        if #_G_State.FuseTargetBuff == 0 then table.insert(_G_State.FuseTargetBuff, "Any") end
    end)

    local FuseStarDrop = Tabs.Fuse:AddDropdown("FuseStarDrop", {
        Title = "Target Stars",
        Values = UI_FuseStars,
        Multi = true,
        Default = {}
    })
    FuseStarDrop:OnChanged(function(Value)
        local selected = {}
        for k, v in pairs(Value) do if v then table.insert(selected, k) end end
        _G_State.FuseTargetStars = selected
        if #_G_State.FuseTargetStars == 0 then table.insert(_G_State.FuseTargetStars, "Any") end
    end)

    -- ==============================================
    -- Tab 4: Auto Zone
    -- ==============================================

    local ZoneToggle = Tabs.Zone:AddToggle("AutoZoneToggle", {
        Title = "Enable Auto Zone",
        Default = false
    })

    ZoneToggle:OnChanged(function()
        _G_State.AutoZone = ZoneToggle.Value
        if _G_State.AutoZone then
            task.spawn(function()
                while _G_State.AutoZone and getgenv()._AutoRollRunning do
                    pcall(function()
                        local player = game:GetService("Players").LocalPlayer
                        local playerGui = player:FindFirstChild("PlayerGui")
                        if playerGui then
                            local zonesPanel = nil
                            for _, gui in pairs(playerGui:GetDescendants()) do
                                if gui:IsA("TextLabel") and (gui.Text == "Zones" or gui.Name == "Zones") then
                                    zonesPanel = gui.Parent
                                    break
                                end
                            end
                            
                            if zonesPanel then
                                for _, btn in pairs(zonesPanel:GetDescendants()) do
                                    if btn:IsA("GuiButton") and btn.Visible then
                                        local text = btn.Text
                                        if text == "" or text == "Button" then
                                            local label = btn:FindFirstChildOfClass("TextLabel")
                                            if label then text = label.Text end
                                        end
                                        
                                        if text and string.find(text, "¥") then
                                            -- Extract cost string right after the yen symbol
                                            local costStr = string.match(text, "¥%s*([%d%,%.]+%s*[kmbKMB]?)")
                                            local cost = nil
                                            
                                            if costStr then
                                                local txtStr = string.lower(costStr)
                                                local val, suffix = string.match(txtStr, "([%d%.]+)%s*([kmb])")
                                                if val and suffix then
                                                    local n = tonumber(val)
                                                    if n then
                                                        if suffix == "k" then cost = n * 1000
                                                        elseif suffix == "m" then cost = n * 1000000
                                                        elseif suffix == "b" then cost = n * 1000000000
                                                        end
                                                    end
                                                else
                                                    local c = string.gsub(txtStr, "[^%d]", "")
                                                    cost = tonumber(c)
                                                end
                                            end
                                            
                                            -- Get current money safely
                                            local currentMoney = player:GetAttribute("Money") or 0
                                            if currentMoney == 0 then
                                                local mVal = player:FindFirstChild("Money", true) or (player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Money"))
                                                if mVal then currentMoney = mVal.Value end
                                            end
                                            
                                            -- Only click if cost is verified and affordable
                                            if cost and currentMoney >= cost then
                                                if getconnections then
                                                    for _, conn in pairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
                                                    for _, conn in pairs(getconnections(btn.Activated)) do conn:Fire() end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(_G_State.ZoneDelay)
                end
            end)
        end
    end)

    Tabs.Zone:AddSlider("ZoneDelaySlider", {
        Title = "ความหน่วงเช็ค Zone (วินาที)",
        Default = 2,
        Min = 1,
        Max = 10,
        Rounding = 1,
        Callback = function(Value)
            _G_State.ZoneDelay = Value
        end
    })

    -- ==============================================
    -- Tab 5: Settings (Presets)
    -- ==============================================
    local HttpService = game:GetService("HttpService")
    local PresetFolder = "AutoRollPro_Presets"

    if not isfolder(PresetFolder) then
        makefolder(PresetFolder)
    end

    local function getPresets()
        local presets = {}
        if isfolder(PresetFolder) then
            for _, file in ipairs(listfiles(PresetFolder)) do
                if file:match("%.json$") then
                    local name = file:match("([^/\\]+)%.json$")
                    if name then table.insert(presets, name) end
                end
            end
        end
        if #presets == 0 then table.insert(presets, "None") end
        return presets
    end

    local CurrentPresetName = ""
    local SelectedPreset = "None"

    -- Helper to turn any list or dictionary into Fluent's multi-dropdown format {[option] = true}
    local function toMultiDict(data)
        local dict = {}
        if type(data) == "table" then
            for k, v in pairs(data) do
                if type(k) == "number" then
                    dict[v] = true
                elseif v == true then
                    dict[k] = true
                end
            end
        end
        return dict
    end

    local function applyStateToUI()
        local o = Fluent.Options
        if not o then return end
        
        pcall(function()
            -- Automation Tab
            if o.AutoRollToggle and _G_State.AutoRoll ~= nil then o.AutoRollToggle:SetValue(_G_State.AutoRoll) end
            if o.RollDelaySlider and _G_State.RollDelay ~= nil then o.RollDelaySlider:SetValue(_G_State.RollDelay) end
            if o.AutoPrestigeToggle and _G_State.AutoPrestige ~= nil then o.AutoPrestigeToggle:SetValue(_G_State.AutoPrestige) end
            if o.AutoUpgradeToggle and _G_State.AutoUpgrade ~= nil then o.AutoUpgradeToggle:SetValue(_G_State.AutoUpgrade) end
            
            -- Potions
            if o.AutoPotionToggle and _G_State.AutoPotion ~= nil then o.AutoPotionToggle:SetValue(_G_State.AutoPotion) end
            if o.PotionTypeDrop and _G_State.PotionTypes then 
                o.PotionTypeDrop:SetValue(toMultiDict(_G_State.PotionTypes)) 
            end
            
            -- Auto Challenge
            if o.AutoChallengeToggle and _G_State.AutoChallenge ~= nil then o.AutoChallengeToggle:SetValue(_G_State.AutoChallenge) end
            if o.ChallengeTypeDrop and _G_State.ChallengeTypes then 
                o.ChallengeTypeDrop:SetValue(toMultiDict(_G_State.ChallengeTypes)) 
            end
            
            -- Buy Tab
            if o.AutoBuyToggle and _G_State.AutoBuy ~= nil then o.AutoBuyToggle:SetValue(_G_State.AutoBuy) end
            
            local activeRarities = toMultiDict(_G_State.BuyRarities)
            if o.BuyRarityFilter and _G_State.BuyRarities then
                o.BuyRarityFilter:SetValue(activeRarities)
            end
            
            for rarity, _ in pairs(UnitsByRarity) do
                local drops = BuyDropdowns[rarity]
                local isRaritySelected = (activeRarities[rarity] == true)

                if drops then
                    if drops.CharDrop then
                        if _G_State.BuyChars and _G_State.BuyChars[rarity] then
                            drops.CharDrop:SetValue(toMultiDict(_G_State.BuyChars[rarity]))
                        end
                        if drops.CharDrop.UIFrame then
                            drops.CharDrop.UIFrame.Visible = isRaritySelected
                        end
                    end

                    if drops.BuffDrop then
                        if _G_State.BuyBuffs and _G_State.BuyBuffs[rarity] then
                            drops.BuffDrop:SetValue(toMultiDict(_G_State.BuyBuffs[rarity]))
                        end
                        if drops.BuffDrop.UIFrame then
                            drops.BuffDrop.UIFrame.Visible = isRaritySelected
                        end
                    end
                end
            end
            
            -- Fuse Tab
            if o.AutoFuseToggle and _G_State.AutoFuse ~= nil then o.AutoFuseToggle:SetValue(_G_State.AutoFuse) end
            if o.FuseDelaySlider and _G_State.FuseDelay ~= nil then o.FuseDelaySlider:SetValue(_G_State.FuseDelay) end
            if o.FuseKeepLimitSlider and _G_State.FuseKeepLimit ~= nil then o.FuseKeepLimitSlider:SetValue(_G_State.FuseKeepLimit) end
            if o.FuseCharDrop and _G_State.FuseTargetChar then 
                o.FuseCharDrop:SetValue(toMultiDict(_G_State.FuseTargetChar)) 
            end
            if o.FuseBuffDrop and _G_State.FuseTargetBuff then 
                o.FuseBuffDrop:SetValue(toMultiDict(_G_State.FuseTargetBuff)) 
            end
            if o.FuseStarDrop and _G_State.FuseTargetStars then 
                o.FuseStarDrop:SetValue(toMultiDict(_G_State.FuseTargetStars)) 
            end
            
            -- Zone Tab
            if o.AutoZoneToggle and _G_State.AutoZone ~= nil then o.AutoZoneToggle:SetValue(_G_State.AutoZone) end
            if o.ZoneDelaySlider and _G_State.ZoneDelay ~= nil then o.ZoneDelaySlider:SetValue(_G_State.ZoneDelay) end
        end)
    end

    local PresetInput = Tabs.Settings:AddInput("PresetNameInput", {
        Title = "New Preset Name",
        Placeholder = "Enter preset name...",
        Callback = function(Text)
            CurrentPresetName = Text
        end
    })

    Tabs.Settings:AddButton({
        Title = "Create Preset",
        Callback = function()
            if CurrentPresetName ~= "" then
                local data = HttpService:JSONEncode(_G_State)
                writefile(PresetFolder .. "/" .. CurrentPresetName .. ".json", data)
                Fluent:Notify({Title = "Preset Saved", Content = "Saved Preset: " .. CurrentPresetName, Duration = 3})
            else
                Fluent:Notify({Title = "Error", Content = "Please enter a preset name first", Duration = 3})
            end
        end
    })

    local PresetDropdown = Tabs.Settings:AddDropdown("PresetDropdown", {
        Title = "Select Preset",
        Values = getPresets(),
        Multi = false,
        Default = "None"
    })
    
    PresetDropdown:OnChanged(function(Value)
        SelectedPreset = Value
    end)

    Tabs.Settings:AddButton({
        Title = "Refresh Presets",
        Callback = function()
            PresetDropdown:SetValues(getPresets())
        end
    })

    Tabs.Settings:AddButton({
        Title = "Load Preset",
        Callback = function()
            if SelectedPreset ~= "None" and isfile(PresetFolder .. "/" .. SelectedPreset .. ".json") then
                local data = readfile(PresetFolder .. "/" .. SelectedPreset .. ".json")
                local success, decoded = pcall(function() return HttpService:JSONDecode(data) end)
                if success and type(decoded) == "table" then
                    for k, v in pairs(decoded) do
                        _G_State[k] = v
                    end
                    applyStateToUI()
                    Fluent:Notify({Title = "Preset Loaded", Content = "Loaded Preset: " .. SelectedPreset .. " Successfully!", Duration = 3})
                end
            end
        end
    })

    Tabs.Settings:AddButton({
        Title = "Overwrite Preset",
        Callback = function()
            if SelectedPreset ~= "None" then
                local data = HttpService:JSONEncode(_G_State)
                writefile(PresetFolder .. "/" .. SelectedPreset .. ".json", data)
                Fluent:Notify({Title = "Preset Overwritten", Content = "Overwritten Preset: " .. SelectedPreset, Duration = 3})
            end
        end
    })

    Tabs.Settings:AddButton({
        Title = "Delete Preset",
        Callback = function()
            if SelectedPreset ~= "None" and isfile(PresetFolder .. "/" .. SelectedPreset .. ".json") then
                delfile(PresetFolder .. "/" .. SelectedPreset .. ".json")
                Fluent:Notify({Title = "Preset Deleted", Content = "Deleted Preset: " .. SelectedPreset, Duration = 3})
                PresetDropdown:SetValues(getPresets())
            end
        end
    })

    local AutoloadFile = PresetFolder .. "/autoload.txt"
    if isfile(AutoloadFile) then
        local autoName = readfile(AutoloadFile)
        if isfile(PresetFolder .. "/" .. autoName .. ".json") then
            local data = readfile(PresetFolder .. "/" .. autoName .. ".json")
            local success, decoded = pcall(function() return HttpService:JSONDecode(data) end)
            if success and type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    _G_State[k] = v
                end
                applyStateToUI()
                Fluent:Notify({Title = "Autoload", Content = "Autoloaded from: " .. autoName, Duration = 3})
            end
        end
    end

    local AutoloadToggle = Tabs.Settings:AddToggle("AutoloadToggle", {
        Title = "Enable Auto Load",
        Default = isfile(AutoloadFile)
    })
    
    AutoloadToggle:OnChanged(function()
        if AutoloadToggle.Value then
            if SelectedPreset ~= "None" then
                writefile(AutoloadFile, SelectedPreset)
                Fluent:Notify({Title = "Autoload Set", Content = "Autoload set to: " .. SelectedPreset, Duration = 3})
            else
                Fluent:Notify({Title = "Autoload Error", Content = "Please select a preset to Auto Load", Duration = 3})
            end
        else
            if isfile(AutoloadFile) then delfile(AutoloadFile) end
            Fluent:Notify({Title = "Autoload Disabled", Content = "Auto Load disabled", Duration = 3})
        end
    end)

    Tabs.Settings:AddButton({
        Title = "Unload Script",
        Callback = function()
            _G_State.AutoRoll = false
            _G_State.AutoBuy = false
            _G_State.AutoPrestige = false
            _G_State.AutoUpgrade = false
            _G_State.AutoFuse = false
            _G_State.AutoZone = false
            _G_State.AutoChallenge = false
            _G_State.AutoPotion = false
            getgenv()._AutoRollRunning = false
            pcall(function() Window:Destroy() end)
            pcall(function()
                for _, ui in pairs(game:GetService("CoreGui"):GetChildren()) do
                    if ui:FindFirstChild("Frame") and ui.Frame:FindFirstChild("CanvasGroup") then
                        ui:Destroy()
                    end
                end
            end)
        end
    })

    Window:SelectTab(1)
    Fluent:Notify({
        Title = "Script Ready",
        Content = "Fluent UI loaded successfully!",
        Duration = 5
    })
end

LoadFluentUI()
