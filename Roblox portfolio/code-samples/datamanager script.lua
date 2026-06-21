--This script is responsible for saving and loads player's data upon joining or leaving

local DataManager = {}
local DataStoreService = game:GetService("DataStoreService")
local limitedStore = DataStoreService:GetDataStore("LimitedStock")
local playerData = DataStoreService:GetDataStore("PlayerData")

local BrainrotManager = require(game.ReplicatedStorage.BrainrotConfiguration:WaitForChild("BrainrotManager"))
local ServerStorage = game.ServerStorage
local ToolManager = require(game.ReplicatedStorage.ToolsConfiguration:WaitForChild("ToolManager"))

local MAX_RETRIES = 3
local RETRY_DELAY = 2

local playerDataCache = {} 

function DataManager.GetStock(itemKey)
	local success, stock = pcall(function()
		return limitedStore:GetAsync(itemKey)
	end)
	if not success then
		warn("Failed to get stock for:", itemKey)
		return nil
	end
	return stock
end

function DataManager.TryPurchaseLimited(itemKey, defaultStock)
	local purchased = false
	local success, err = pcall(function()
		limitedStore:UpdateAsync(itemKey, function(stock)
			stock = stock or defaultStock
			if stock <= 0 then
				return stock -- dont change, out of stock
			end
			purchased = true
			return stock - 1
		end)
	end)

	if not success then
		warn("Failed to purchase limited item:", itemKey, err)
		return false, nil
	end

	if not purchased then
		return false, 0 -- out of stock
	end

	-- get remaining stock
	local _, remaining = pcall(function()
		return limitedStore:GetAsync(itemKey)
	end)

	return true, remaining
end

function DataManager.RestockLimited(itemKey, amount)
	local success, err = pcall(function()
		limitedStore:UpdateAsync(itemKey, function(stock)
			return (stock or 0) + amount
		end)
	end)
	if not success then
		warn("Failed to restock:", itemKey, err)
	end
end

-- HELPER: save with retries
-- in DataManager, change saveWithRetry to not yield on PlayerRemoving
local function saveWithRetry(userId, data, isLeaving)
	for attempt = 1, MAX_RETRIES do
		local success, err = pcall(function()
			playerData:UpdateAsync(userId, function()
				return data
			end)
		end)

		if success then
			print("Data saved successfully on attempt", attempt)
			return true
		else
			warn("Save attempt", attempt, "failed:", err)
			if attempt < MAX_RETRIES then
				if isLeaving then
					-- cant yield too long on PlayerRemoving in live server
					task.wait(0.5)
				else
					task.wait(RETRY_DELAY)
				end
			end
		end
	end

	warn("All save attempts failed for userId:", userId)
	return false
end

-- HELPER: load with retries
local function loadWithRetry(userId)
	for attempt = 1, MAX_RETRIES do
		local success, data = pcall(function()
			return playerData:GetAsync(userId)
		end)

		if success then
			return true, data
		else
			warn("Load attempt", attempt, "failed:", data)
			if attempt < MAX_RETRIES then
				task.wait(RETRY_DELAY)
			end
		end
	end

	warn("All load attempts failed for userId:", userId)
	return false, nil
end

-- HELPER: collect all tools including currently held
local function getTools(player)
	local result = {}
	local seen = {}

	local function scanTool(tool)
		if not tool:IsA("Tool") then return end
		local key = tool:GetAttribute("Key")
		local itemkey = tool:GetAttribute("ItemKey")

		if not key and not itemkey then return end 
		if seen[tool] then return end
		seen[tool] = true
		print("Saving tool:", tool.Name, "key:", tool:GetAttribute("Key"), "level:", tool:GetAttribute("Level"))
		if key then
			table.insert(result, {
				key = tool:GetAttribute("Key"),
				level = tool:GetAttribute("Level") or 1,
				exclusive = tool:GetAttribute("Exclusive") or false,
				mutation = tool:GetAttribute("Mutation") or "",
				moneyMultiplier = tool:GetAttribute("MoneyMultiplier") or 1,
				lock = tool:GetAttribute("Locked") or false,
			})
		elseif itemkey then
			table.insert(result, {
				itemkey = tool:GetAttribute("ItemKey"),
			})
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			scanTool(tool)
		end
	end

	print("Total tools saved:", #result)
	return result
end

local function loadBackpack(player, toolList)
	local backpack = player:WaitForChild("Backpack")
	for _, toolData in ipairs(toolList or {}) do
		if toolData.key then
			local config
			local folder
			if toolData.exclusive then
				config = BrainrotManager.getExclusiveConfig(toolData.key)
				folder = ServerStorage.ExclusiveBrainrot:FindFirstChild(toolData.key)
			else
				config = BrainrotManager.getConfig(toolData.key)
			end
			if not config then warn("No config for key:", toolData.key) continue end

			local mutation = toolData.mutation and toolData.mutation ~= "" 
				and { name = toolData.mutation, moneyMultiplier = toolData.moneyMultiplier or 1 } 
				or nil

			local sourceModel
			if toolData.exclusive then
				if not folder then warn("No folder for key:", toolData.key) continue end
				sourceModel = folder:FindFirstChildWhichIsA("Model")
			else
				sourceModel = BrainrotManager.getModel(config, mutation)
			end

			if not sourceModel then warn("No model for key:", toolData.key) continue end

			-- set mutation attributes on source model before converting
			if mutation then
				sourceModel:SetAttribute("Mutation", mutation.name)
				sourceModel:SetAttribute("MoneyMultiplier", mutation.moneyMultiplier)
			end

			local tool = BrainrotManager.convertToTool(sourceModel, config, toolData.level or 1)

			if mutation then
				sourceModel:SetAttribute("Mutation", nil)
				sourceModel:SetAttribute("MoneyMultiplier", nil)
			end

			if toolData.exclusive then
				tool:SetAttribute("Exclusive", true)
			end
			
			if toolData.lock then
				tool:SetAttribute("Locked", true)
			end

			if tool then
				BrainrotManager.setupGUI(tool, config, toolData.level or 1)
				tool.Parent = backpack
			end

		elseif toolData.itemkey then
			local itemtemplate = game.ReplicatedStorage:WaitForChild("Items")
			local item = itemtemplate:FindFirstChild(toolData.itemkey)
			if item and item:IsA("Tool") then
				local clone = item:Clone()
				clone:SetAttribute("ItemKey", toolData.itemkey)
				clone.Parent = player.Backpack
			end
		end
	end
end

function DataManager.SavePlayer(player,isLeaving,heldTool)
	
	if not player:GetAttribute("DataLoaded") then
		warn("Refusing save - data never loaded for:", player.Name)
		return false
	end
	
	local data = {
		speedUpgrade = player:GetAttribute("SpeedUpgrade") or 25,
		firePower = player.leaderstats.FirePower.Value,
		money = player.leaderstats.Money.Value,
		stage = player:GetAttribute("Stage"),
		ownedTools = {},
		backpackTools = {},
		equippedTool = "",
		platforms = {},
		firepowerBoostExpiresAt = player:GetAttribute("FirepowerBoostExpiresAt"),
	}

	-- save owned tools
	local ownedFolder = player:FindFirstChild("OwnedTools")
	if ownedFolder then
		for _, v in ipairs(ownedFolder:GetChildren()) do
			table.insert(data.ownedTools, v.Name)
		end
	end

	-- equipped tool
	local equippedFolder = player:FindFirstChild("EquippedTools")
	if equippedFolder then
		local equipped = equippedFolder:FindFirstChildWhichIsA("StringValue")
		if equipped then
			data.equippedTool = equipped.Name
		end
	end

	-- save ALL tools including currently held one
	data.backpackTools = getTools(player)
	
	if heldTool then
		local alreadySaved = false
		for _, t in ipairs(data.backpackTools) do
			if t.key == heldTool:GetAttribute("Key") or t.itemkey == heldTool:GetAttribute("ItemKey") then
				alreadySaved = true
				break
			end
		end
		if not alreadySaved then
			if heldTool:GetAttribute("Key") then
			table.insert(data.backpackTools, {
				key = heldTool:GetAttribute("Key"),
				level = heldTool:GetAttribute("Level") or 1,
				exclusive = heldTool:GetAttribute("Exclusive") or false,
				mutation = heldTool:GetAttribute("Mutation") or "",
				moneyMultiplier = heldTool:GetAttribute("MoneyMultiplier") or 1,
			})
			
			elseif heldTool:GetAttribute("ItemKey") then
				table.insert(data.backpackTools, {
					itemkey = heldTool:GetAttribute("ItemKey"),
				})
			end
		end
	end
	
	-- save platform data
	local baseName = player:GetAttribute("Base")
	local base = baseName and workspace.testplate:FindFirstChild(baseName)
	if base then
		for _, child in ipairs(base:GetDescendants()) do
			if child:IsA("Model") and child.Name:match("^plat%d+$") then
				local platform = child:FindFirstChild("Platform")
				if platform then
					data.platforms[child.Name] = {
						key = platform:GetAttribute("BrainrotKey") or "",
						level = platform:GetAttribute("BrainrotLevel") or 0,
						exclusive = platform:GetAttribute("Exclusive") or false,
						mutation = platform:GetAttribute("Mutation") or "",
						moneyMultiplier = platform:GetAttribute("MoneyMultiplier") or 1,
						locked = platform:GetAttribute("Locked") or false,
					}
				end
			end
		end
	end

	return saveWithRetry(player.UserId, data,isLeaving)
end

function DataManager.LoadPlayer(player)

	local success, data = loadWithRetry(player.UserId)

	if not success then
		player:Kick("Failed to load data. Please rejoin.")
		return
	end

	if not data then
		
		data = {
			speedUpgrade = 25,
			firePower = 500,
			money = 500,
			stage = 1,
			ownedTools = {},
			backpackTools = {},
			equippedTool = "",
			platforms = {},
			firepowerBoostExpiresAt = player:GetAttribute("FirepowerBoostExpiresAt"),
		}
	end
	
	if data.firepowerBoostExpiresAt then
		player:SetAttribute("FirepowerBoostExpiresAt", data.firepowerBoostExpiresAt)
	end
	-- apply stats
	player:SetAttribute("SpeedUpgrade", data.speedUpgrade or 25)
	player:SetAttribute("Stage", data.stage or 1)
	player.leaderstats.FirePower.Value = data.firePower or 500
	player.leaderstats.Money.Value = data.money or 500

	-- restore owned tools
	local ownedFolder = player:FindFirstChild("OwnedTools")
	if ownedFolder then
		for _, key in ipairs(data.ownedTools or {}) do
			local tag = Instance.new("StringValue")
			tag.Name = key
			tag.Parent = ownedFolder
		end
	end

	local function restoreTools(player, data)
		task.defer(function()
			if data.equippedTool and data.equippedTool ~= "" then
				ToolManager.EquipTool(player, data.equippedTool, true)
				local equippedFolder = player:FindFirstChild("EquippedTools")
				if equippedFolder then
					local tag = Instance.new("StringValue")
					tag.Name = data.equippedTool
					tag.Parent = equippedFolder
				end
			end
			loadBackpack(player, data.backpackTools)
		end)
	end

	if player.Character then
		restoreTools(player, data)
	else
		player.CharacterAdded:Once(function()
			restoreTools(player, data)
		end)
	end

	player:SetAttribute("DataLoaded", true)
	print("Loaded data for", player.Name)
	
	playerDataCache[player.UserId] = data
end




function DataManager.RestorePlatforms(player)

	local data = playerDataCache[player.UserId]

	if not data then
		warn("No cached data for:", player.Name)
		player:SetAttribute("PlatformsLoaded", true)
		return
	end
	
	if not data.platforms or next(data.platforms) == nil then
		player:SetAttribute("PlatformsLoaded", true)
		playerDataCache[player.UserId] = nil
		return
	end

	local baseName = player:GetAttribute("Base")
	local base = baseName and workspace.testplate:FindFirstChild(baseName)

	if base and data.platforms then
		for platName, platData in pairs(data.platforms) do
			if platData.key == "" then continue end

			local plat = base:FindFirstChild(platName, true)
			if not plat then
				warn("Platform not found:", platName)
				continue
			end

			local platform = plat:FindFirstChild("Platform")
			if not platform then continue end

			local config
			if platData.exclusive then
				config = BrainrotManager.getExclusiveConfig(platData.key)
			else
				config = BrainrotManager.getConfig(platData.key)
			end

			if not config then
				warn("No config for platform key:", platData.key)
				continue
			end
			local rarity = config.rarity

			local folder
			if platData.exclusive then
				folder = ServerStorage.ExclusiveBrainrot:FindFirstChild(platData.key)
			else
				folder = ServerStorage.BrainrotList:FindFirstChild(platData.key)
			end

			local mutation = platData.mutation ~= "" and { name = platData.mutation, moneyMultiplier = platData.moneyMultiplier } or nil
			local mutationName = mutation and { name = mutation } or nil
	
			local model
			
			if platData.exclusive then
				model = BrainrotManager.getModel(config, mutation, platData.exclusive)
			else
				model = BrainrotManager.getModel(config, mutation)
			end
			
			if not model then
				warn("No model for platform key:", platData.key)
				continue
			end

			local clone = model:Clone()
			clone.Parent = platform

			local vfxInstance = clone:FindFirstChild("VfxInstance")
			if vfxInstance and vfxInstance:IsA("BasePart") then
				local platformCF = platform:GetPivot()
				local platformPos = platformCF.Position
				local vfxHalfHeight = vfxInstance.Size.Y / 2
				local pivotOffset = clone:GetPivot().Position - vfxInstance.Position
				local facing = platform:GetAttribute("Facing") or "Inward"
				local lookDir = platformCF.LookVector
				if facing == "Outward" then lookDir = -lookDir end
				local cf = CFrame.lookAt(platformPos, platformPos + lookDir)
				clone:PivotTo(cf * CFrame.new(0, vfxHalfHeight + pivotOffset.Y, 0))
			end

			if platData.mutation and platData.mutation ~= "" then
				clone:SetAttribute("Mutation", platData.mutation)
				clone:SetAttribute("MoneyMultiplier", platData.moneyMultiplier or 1)
				platform:SetAttribute("Mutation", platData.mutation)
				platform:SetAttribute("MoneyMultiplier", platData.moneyMultiplier or 1)
			end
			
			if platData.locked then
				platform:SetAttribute("Locked", true)
				clone:SetAttribute("Locked", true)
			end

			platform:SetAttribute("Occupied", true)
			platform:SetAttribute("BrainrotKey", platData.key)
			platform:SetAttribute("Rarity", rarity)
			platform:SetAttribute("BrainrotLevel", platData.level)
			platform:SetAttribute("MoneyPerSecond", BrainrotManager.calculateMoney(config, platData.level, platData.moneyMultiplier or 1))
			BrainrotManager.setupGUI(clone, config, platData.level)

			if platData.exclusive then
				platform:SetAttribute("Exclusive", true)
			end
			
			task.defer(function()
				platform:SetAttribute("Loaded", true)
			end)
		end
	end

	player:SetAttribute("PlatformsLoaded", true)
	playerDataCache[player.UserId] = nil
end

return DataManager