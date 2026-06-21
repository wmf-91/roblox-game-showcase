--This is the platform manager script responsible for the money collecting,leveling,picking up, placing mechanics for the items

local PlatformSystem = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local purchaserobux = RS.Events:WaitForChild("PurchaseRobux")
local stealconfig = require(RS.BrainrotConfiguration:WaitForChild("StealRarityPurchase"))

local collectvfx = RS.Events:WaitForChild("PlayCollectVFX")
local disableevent = RS.Events:WaitForChild("DisableScreen")
local stealingevent = RS.Events:WaitForChild("Stealing")
local vfx = RS.Events:WaitForChild("Vfxplayer")
local errorpopupevent = RS.Events:WaitForChild("ErrorPopup")

local BrainrotManager = require(
	RS.BrainrotConfiguration.BrainrotManager
)

local updateprompts = RS.Events:WaitForChild("UpdatePlatformPrompts")
local updatestealprompt = RS.Events:WaitForChild("UpdateStealPrompt")

local format = require(RS.NumberFormat)

local basePlatforms = {}




--// HELPERS

function PlatformSystem.GetBaseOwner(baseName)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Base") == baseName then
			return player
		end
	end

	return nil
end

function PlatformSystem.GetBaseFromPlatform(platform)

	local current = platform

	while current do
		current = current.Parent

		if not current then
			return nil
		end

		if current:IsA("Model") and current:GetAttribute("IsBase") then
			return current
		end
	end

	return nil
end




--// COLLECTOR RESET/PAYOUT

function PlatformSystem.PayoutCollector(player, platform)
	local collectorPart = platform.Parent:FindFirstChild("Collector1")
	if not collectorPart then return end

	local collector = collectorPart:FindFirstChild("button")
	if not collector then return end

	local valueObject = collector:FindFirstChild("Value")
	if not valueObject then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyStat = leaderstats and leaderstats:FindFirstChild("Money")

	if moneyStat and valueObject.Value > 0 then
		local vipmultiplier = 1
		local cashmultiplier = 1

		if player:GetAttribute("VIP") then
			vipmultiplier = 1.5
		end
		
		if player:GetAttribute("CashGamepass") then
			cashmultiplier = 2
		end

		moneyStat.Value = moneyStat.Value + (valueObject.Value * vipmultiplier * cashmultiplier)
	end

	valueObject.Value = 0

	local moneyGui = collector:FindFirstChild("MoneyValueGUI")

	if moneyGui then
		local moneyText = moneyGui.Frame:FindFirstChild("MoneyTextLabel")
		moneyGui.Enabled = false
		if moneyText then
			moneyText.Text = "$0"
		end
	end
end




--// PLATFORM SETUP
local PendingSteals = {}

function PlatformSystem.GetPendingSteal(userId)
	return PendingSteals[userId]
end

function PlatformSystem.SetupPlatform(platform)

	local placePrompt = platform:FindFirstChild("PlacePrompt", true)
	local pickupPrompt = platform:FindFirstChild("PickupPrompt", true)
	local stealPrompt = platform:FindFirstChild("StealPrompt", true)
	local lockprompt = platform:FindFirstChild("LockPrompt",true)

	if not placePrompt or not pickupPrompt then
		return
	end
	
	lockprompt.Triggered:Connect(function(player)
		local base = PlatformSystem.GetBaseFromPlatform(platform)
		if not base then return end

		if not platform:GetAttribute("Occupied") then return end

		local owner = PlatformSystem.GetBaseOwner(base.Name)

		if player ~= owner then
			return
		end
		
		local char = player.Character
		local padlock = char:FindFirstChildWhichIsA("Tool")
		
		if padlock and padlock:GetAttribute("ItemKey") == "Padlock" then
			
			if platform:GetAttribute("Locked") then 
				errorpopupevent:FireClient(player, "error","Brainrot already locked!")
			return end
			
			errorpopupevent:FireClient(player, "success","Brainrot has been locked!")
			
			platform:SetAttribute("Locked",true)
			padlock:Destroy()
			local model = platform:FindFirstChildWhichIsA("Model")
			local head = model:FindFirstChild("Head")
			model:SetAttribute("Locked",true)
			local gui = head:FindFirstChild("InfoGUI")
			local namelabel = gui:FindFirstChild("NameLabel")
			namelabel.Text = model.Name .." 🔒"
		end
	end)
	
	stealPrompt.Triggered:Connect(function(player)
		local base = PlatformSystem.GetBaseFromPlatform(platform)
		if not base then return end

		local owner = PlatformSystem.GetBaseOwner(base.Name)

		if owner == player then
			return
		end

		if platform:GetAttribute("Locked") then 
			errorpopupevent:FireClient(player, "error","Brainrot is locked!")
		return end

		local rarity = platform:GetAttribute("Rarity")
		local stealid = stealconfig[rarity]

		PendingSteals[player.UserId] = platform

		purchaserobux:FireClient(player,stealid)
	end)

	placePrompt.Triggered:Connect(function(player)

		local base = PlatformSystem.GetBaseFromPlatform(platform)
		if not base then return end

		local owner = PlatformSystem.GetBaseOwner(base.Name)

		if owner ~= player then
			return
		end

		local char = player.Character
		if not char then return end

		local tool = char:FindFirstChildWhichIsA("Tool")

		if not tool or not tool:GetAttribute("Key") then
			return
		end

		local key = tool:GetAttribute("Key")
		local level = tool:GetAttribute("Level") or 1
		local multiplier = tool:GetAttribute("MoneyMultiplier") or 1
		local rarity = tool:GetAttribute("Rarity")
		local lock = tool:GetAttribute("Locked") or false

		local exclusive = tool:GetAttribute("Exclusive")

		local config 

		if exclusive then
			config = BrainrotManager.getExclusiveConfig(key)

		else 
			config = BrainrotManager.getConfig(key)
		end

		if not config then
			return
		end

		-- replace existing
		if platform:GetAttribute("Occupied") then

			PlatformSystem.PayoutCollector(player, platform)

			local currentModel =
				platform:FindFirstChildWhichIsA("Model")

			if currentModel then

				local currentKey =
					platform:GetAttribute("BrainrotKey")

				local currentLevel =
					platform:GetAttribute("BrainrotLevel") or 1

				local exclusive = platform:GetAttribute("Exclusive")

				local currentConfig

				if exclusive then
					currentConfig =
						BrainrotManager.getExclusiveConfig(currentKey)
				else
					currentConfig =
						BrainrotManager.getConfig(currentKey)
				end

				if currentConfig then

					local convertedTool =
						BrainrotManager.convertToTool(
							currentModel,
							currentConfig,
							currentLevel
						)

					if convertedTool then
						if exclusive then convertedTool:SetAttribute("Exclusive",true) end
						convertedTool.Parent = player.Backpack

					end
				end

				platform:SetAttribute("Mutation", nil)
				platform:SetAttribute("MoneyMultiplier", nil)
				platform:SetAttribute("Exclusive", nil)
				platform:SetAttribute("Rarity", nil)
				platform:SetAttribute("Locked", false)
				currentModel:Destroy()
			end
		end

		local mutationName = tool:GetAttribute("Mutation")
		local mutation = mutationName and { name = mutationName } or nil
		local multiplier = tool:GetAttribute("MoneyMultiplier") or 1

		tool:Destroy()

		local folder 

		if exclusive then
			folder = ServerStorage.ExclusiveBrainrot:FindFirstChild(key)
		else
			folder = ServerStorage.BrainrotList:FindFirstChild(key)
		end

		if not folder then return end

		local model
		if exclusive then
			model = BrainrotManager.getModel(config, mutation,exclusive)
		else
			model = BrainrotManager.getModel(config, mutation)
		end

		if not model then return end

		local clone = model:Clone()
		clone.Parent = platform

		if exclusive then
			clone:SetAttribute("Exclusive", true)
		end
		
		if lock then
			clone:SetAttribute("Locked", true)
		end

		if mutation then
			clone:SetAttribute("Mutation", mutation.name)
			clone:SetAttribute("MoneyMultiplier", multiplier)
			platform:SetAttribute("Mutation", mutation.name)
			platform:SetAttribute("MoneyMultiplier", multiplier)
		end

		local vfxInstance = clone:FindFirstChild("VfxInstance")

		if vfxInstance and vfxInstance:IsA("BasePart") then

			local platformCF = platform:GetPivot()
			local platformPos = platformCF.Position

			local vfxHalfHeight = vfxInstance.Size.Y / 2
			local pivotOffset = clone:GetPivot().Position - vfxInstance.Position

			local facing = platform:GetAttribute("Facing") or "Inward"

			local lookDir = platformCF.LookVector

			if facing == "Outward" then
				lookDir = -lookDir
			end

			local cf = CFrame.lookAt(platformPos, platformPos + lookDir)

			clone:PivotTo(cf * CFrame.new(0, vfxHalfHeight + pivotOffset.Y, 0))
		end

		platform:SetAttribute("Occupied", true)
		platform:SetAttribute("BrainrotKey", key)
		platform:SetAttribute("BrainrotLevel", level)
		platform:SetAttribute("Loaded", true)
		platform:SetAttribute("Rarity", rarity)

		platform:SetAttribute(
			"MoneyPerSecond",
			BrainrotManager.calculateMoney(config, level,multiplier or 1)
		)

		if exclusive then
			platform:SetAttribute("Exclusive", true)
		end
		
		if lock then
			platform:SetAttribute("Locked", true)
		end

		BrainrotManager.setupGUI(clone, config, level)
	end)


	pickupPrompt.Triggered:Connect(function(player)

		local base = PlatformSystem.GetBaseFromPlatform(platform)
		if not base then return end

		local owner = PlatformSystem.GetBaseOwner(base.Name)

		if owner ~= player then
			return
		end

		if not platform:GetAttribute("Occupied") then
			return
		end

		local char = player.Character
		if not char then return end

		if char:FindFirstChildWhichIsA("Tool") then
			return
		end

		PlatformSystem.PayoutCollector(player, platform)

		local currentModel =
			platform:FindFirstChildWhichIsA("Model")

		if currentModel then
			currentModel:Destroy()
		end

		local key = platform:GetAttribute("BrainrotKey")
		local level = platform:GetAttribute("BrainrotLevel") or 1
		local exclusive = platform:GetAttribute("Exclusive")
		local rarity = platform:GetAttribute("Rarity")
		local mutationName = platform:GetAttribute("Mutation")
		local mutation = mutationName and mutationName ~= "" and { name = mutationName } or nil
		local multiplier = platform:GetAttribute("MoneyMultiplier") or 1
		local lock = platform:GetAttribute("Locked") or false

		local config

		if exclusive then
			config = BrainrotManager.getExclusiveConfig(key)
		else
			config = BrainrotManager.getConfig(key)
		end

		if config then
			local sourceModel

			if exclusive then
				sourceModel = ServerStorage.ExclusiveBrainrot
					:FindFirstChild(key)
					:FindFirstChildWhichIsA("Model")
			else
				sourceModel = BrainrotManager.getModel(config, mutation)
			end

			if not sourceModel then return end

			-- carry mutation attributes for convertToTool to pick up
			if mutation and mutationName ~= "" then
				sourceModel:SetAttribute("Mutation", mutationName)
				sourceModel:SetAttribute("MoneyMultiplier", platform:GetAttribute("MoneyMultiplier") or 1)
			end

			local convertedTool = BrainrotManager.convertToTool(sourceModel, config, level)

			-- clean up temp attributes on source model
			if mutation and mutationName ~= "" then
				sourceModel:SetAttribute("Mutation", nil)
				sourceModel:SetAttribute("MoneyMultiplier", nil)
			end

			if exclusive then
				convertedTool:SetAttribute("Exclusive", true)
			end
			
			if lock then
				convertedTool:SetAttribute("Locked", true)
			end

			if convertedTool then
				BrainrotManager.setupGUI(convertedTool, config, level)
				convertedTool.Parent = player.Backpack
			end
		end

		platform:SetAttribute("Occupied", false)
		platform:SetAttribute("BrainrotKey", "")
		platform:SetAttribute("BrainrotLevel", 0)
		platform:SetAttribute("MoneyPerSecond", 0)
		platform:SetAttribute("Exclusive", false)
		platform:SetAttribute("Rarity", "")
		platform:SetAttribute("Loaded", false)
		platform:SetAttribute("Locked", false)
		platform:SetAttribute("Mutation", "")
		platform:SetAttribute("MoneyMultiplier", 1)
	end)
end

--STEAL MECHANICS

function PlatformSystem.PlaceBrainrotFromTool(platform, tool)
	if not platform or not tool then
		return false
	end

	local key = tool:GetAttribute("Key")
	if not key then
		return false
	end

	local level = tool:GetAttribute("Level") or 1
	local multiplier = tool:GetAttribute("MoneyMultiplier") or 1
	local rarity = tool:GetAttribute("Rarity")
	local exclusive = tool:GetAttribute("Exclusive")

	local config

	if exclusive then
		config = BrainrotManager.getExclusiveConfig(key)
	else
		config = BrainrotManager.getConfig(key)
	end

	if not config then
		return false
	end

	local mutationName = tool:GetAttribute("Mutation")
	local mutation = mutationName and mutationName ~= "" and {name = mutationName} or nil

	local model

	if exclusive then
		model = BrainrotManager.getModel(config, mutation, true)
	else
		model = BrainrotManager.getModel(config, mutation)
	end

	if not model then
		return false
	end

	local clone = model:Clone()
	clone.Parent = platform

	if exclusive then
		clone:SetAttribute("Exclusive", true)
	end

	if mutation then
		clone:SetAttribute("Mutation", mutation.name)
		clone:SetAttribute("MoneyMultiplier", multiplier)

		platform:SetAttribute("Mutation", mutation.name)
		platform:SetAttribute("MoneyMultiplier", multiplier)
	end

	local vfxInstance = clone:FindFirstChild("VfxInstance")

	if vfxInstance and vfxInstance:IsA("BasePart") then
		local platformCF = platform:GetPivot()
		local platformPos = platformCF.Position

		local vfxHalfHeight = vfxInstance.Size.Y / 2
		local pivotOffset = clone:GetPivot().Position - vfxInstance.Position

		local facing = platform:GetAttribute("Facing") or "Inward"
		local lookDir = platformCF.LookVector

		if facing == "Outward" then
			lookDir = -lookDir
		end

		local cf = CFrame.lookAt(platformPos, platformPos + lookDir)

		clone:PivotTo(
			cf * CFrame.new(0, vfxHalfHeight + pivotOffset.Y, 0)
		)
	end

	platform:SetAttribute("Occupied", true)
	platform:SetAttribute("BrainrotKey", key)
	platform:SetAttribute("BrainrotLevel", level)
	platform:SetAttribute("Loaded", true)
	platform:SetAttribute("Rarity", rarity)

	platform:SetAttribute(
		"MoneyPerSecond",
		BrainrotManager.calculateMoney(config, level, multiplier)
	)

	if exclusive then
		platform:SetAttribute("Exclusive", true)
	end

	BrainrotManager.setupGUI(clone, config, level)

	return true
end

function PlatformSystem.Steal(player, platform)
	if not player or not platform then
		return false
	end

	local base = PlatformSystem.GetBaseFromPlatform(platform)
	if not base then
		return false
	end

	local owner = PlatformSystem.GetBaseOwner(base.Name)
	if not owner then
		return false
	end

	PlatformSystem.PayoutCollector(owner, platform)

	player:SetAttribute("Stealing", true)

	local currentModel = platform:FindFirstChildWhichIsA("Model")

	if currentModel then
		currentModel:Destroy()
	end

	local key = platform:GetAttribute("BrainrotKey")
	local level = platform:GetAttribute("BrainrotLevel") or 1
	local exclusive = platform:GetAttribute("Exclusive")
	local mutationName = platform:GetAttribute("Mutation")
	local mutation = mutationName and mutationName ~= "" and { name = mutationName } or nil

	local config

	if exclusive then
		config = BrainrotManager.getExclusiveConfig(key)
	else
		config = BrainrotManager.getConfig(key)
	end

	if not config then
		return false
	end

	local sourceModel

	if exclusive then
		local folder = ServerStorage.ExclusiveBrainrot:FindFirstChild(key)

		if not folder then
			return false
		end

		sourceModel = folder:FindFirstChildWhichIsA("Model")
	else
		sourceModel = BrainrotManager.getModel(config, mutation)
	end

	if not sourceModel then
		return false
	end

	if mutation then
		sourceModel:SetAttribute("Mutation", mutationName)
		sourceModel:SetAttribute(
			"MoneyMultiplier",
			platform:GetAttribute("MoneyMultiplier") or 1
		)
	end

	local convertedTool =
		BrainrotManager.convertToTool(sourceModel, config, level)

	if mutation then
		sourceModel:SetAttribute("Mutation", nil)
		sourceModel:SetAttribute("MoneyMultiplier", nil)
	end

	if not convertedTool then
		return false
	end

	if exclusive then
		convertedTool:SetAttribute("Exclusive", true)
	end

	BrainrotManager.setupGUI(convertedTool, config, level)
	convertedTool.Parent = player.Backpack

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		task.defer(function()
			if convertedTool and convertedTool.Parent == player.Backpack then
				humanoid:EquipTool(convertedTool)
			end
		end)
	end

	local slaptoolfolder = RS:WaitForChild("SlapTool")
	local slaptool = slaptoolfolder:FindFirstChild("SlapTool")

	local cloneslaptool = slaptool:Clone()
	cloneslaptool.Parent = owner.Backpack
	local ownercharacter = owner.Character
	local humanoid = ownercharacter and ownercharacter:FindFirstChildOfClass("Humanoid")

	if humanoid then
		task.defer(function()
			if cloneslaptool and cloneslaptool.Parent == owner.Backpack then
				humanoid:EquipTool(cloneslaptool)
			end
		end)
	end

	owner:SetAttribute("Stealed",true)

	disableevent:FireClient(player, "stealstart")
	stealingevent:FireClient(player, "stealing", owner)
	stealingevent:FireClient(owner, "stealed", player)


	player:GetAttributeChangedSignal("StealSlapped"):Connect(function()

		if player:GetAttribute("StealSlapped",true) then

			owner:SetAttribute("Stealed",false)
			player:SetAttribute("Stealing",false)

			stealingevent:FireClient(player, "stealend")
			stealingevent:FireClient(owner, "stealend")
			errorpopupevent:FireClient(player, "error","Failed to steal brainrot.")

			local tool = player.Character:FindFirstChildWhichIsA("Tool")
			if tool and tool:GetAttribute("Key") then
				if platform:GetAttribute("Occupied") then
					tool.Parent = owner.Backpack
				else
					PlatformSystem.PlaceBrainrotFromTool(platform,tool)
					tool:Destroy()
				end
			end

			task.defer(function()
				player:SetAttribute("StealSlapped",false)
				local slaptool = ownercharacter:FindFirstChildWhichIsA("Tool")
				if slaptool and not slaptool:GetAttribute("Key") then
					slaptool:Destroy()
				end
			end)
		end

	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("Key") then
			if player:GetAttribute("StealSlapped") then return end

			disableevent:FireClient(player, "stealend")

			owner:SetAttribute("Stealed",false)
			player:SetAttribute("Stealing",false)

			vfx:FireClient(player,"success","Brainrot!")

			stealingevent:FireClient(player, "stealend")
			stealingevent:FireClient(owner, "stealend")
			errorpopupevent:FireClient(owner, "error","Failed to save brainrot.")

			local slaptool = ownercharacter:FindFirstChildWhichIsA("Tool")
			if slaptool and not slaptool:GetAttribute("Key") then
				slaptool:Destroy()
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if player:GetAttribute("Stealing") then
			player:SetAttribute("StealSlapped",true)
			local tool = character:FindFirstChildOfClass("Tool")
			if tool and tool:GetAttribute("Key") then
				PlatformSystem.PlaceBrainrotFromTool(platform,tool)
				tool:Destroy()
			end

			owner:SetAttribute("Stealed",false)
			player:SetAttribute("Stealing",false)

			stealingevent:FireClient(player, "stealend")
			stealingevent:FireClient(owner, "stealend")

			local slaptool = ownercharacter:FindFirstChildWhichIsA("Tool")
			if slaptool and not slaptool:GetAttribute("Key") then
				slaptool:Destroy()
			end

			task.defer(function()
				player:SetAttribute("StealSlapped",false)
			end)
		end
	end)

	platform:SetAttribute("Occupied", false)
	platform:SetAttribute("BrainrotKey", "")
	platform:SetAttribute("BrainrotLevel", 0)
	platform:SetAttribute("MoneyPerSecond", 0)
	platform:SetAttribute("Exclusive", false)
	platform:SetAttribute("Rarity", "")
	platform:SetAttribute("Loaded", false)
	platform:SetAttribute("Mutation", "")
	platform:SetAttribute("MoneyMultiplier", 1)

	return true
end


--// COLLECTOR SETUP

function PlatformSystem.SetupCollector(platform)

	if platform:GetAttribute("CollectorSetup") then return end
	platform:SetAttribute("CollectorSetup", true)

	local collectorPart = platform.Parent:FindFirstChild("Collector1")
	local collector = collectorPart:FindFirstChild("button")
	if not collector then return end

	local moneyGui = collector:WaitForChild("MoneyValueGUI")
	local moneyText = moneyGui.Frame.MoneyTextLabel

	local originalCFrame = collector.CFrame

	local debounce = false
	local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function press()
		local pressedCFrame = originalCFrame + Vector3.new(0, -0.2, 0)

		local down = TweenService:Create(collector, tweenInfo, {CFrame = pressedCFrame})
		local up = TweenService:Create(collector, tweenInfo, {CFrame = originalCFrame})

		down:Play()
		down.Completed:Wait()
		up:Play()
	end

	-- create value object if missing
	local valueObject = collector:FindFirstChild("Value")

	-- reset when removed
	platform:GetAttributeChangedSignal("Occupied"):Connect(function()
		if not platform:GetAttribute("Occupied") then
			moneyGui.Enabled = false
			valueObject.Value = 0
			moneyText.Text = "$0"
		end
	end)

	local generating = true

	collector.Touched:Connect(function(hit)
		if debounce then return end
		if not platform:GetAttribute("Occupied") then return end
		if valueObject.Value <= 0 then return end

		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then return end

		local base = PlatformSystem.GetBaseFromPlatform(platform)
		if not base then return end

		local owner = PlatformSystem.GetBaseOwner(base.Name)
		if owner ~= player then return end

		local leaderstats = player:FindFirstChild("leaderstats")
		local moneyStat = leaderstats and leaderstats:FindFirstChild("Money")

		if not moneyStat then return end

		debounce = true
		generating = false

		local vipmultiplier = 1
		local cashmultiplier = 1

		if player:GetAttribute("VIP") then
			vipmultiplier = 1.5
		end
		
		if player:GetAttribute("CashGamepass") then
			cashmultiplier = 2
		end

		moneyStat.Value = moneyStat.Value + (valueObject.Value * vipmultiplier * cashmultiplier)

		valueObject.Value = 0
		moneyText.Text = "$0"

		press()
		collectvfx:FireClient(player,collector.Position)

		task.wait(1)
		generating = true
		debounce = false
	end)

	task.spawn(function()
		while collector.Parent do
			task.wait(1)

			if platform:GetAttribute("Occupied") and generating then
				moneyGui.Enabled = true
				local moneyPerSecond = platform:GetAttribute("MoneyPerSecond") or 0
				valueObject.Value += moneyPerSecond
				moneyText.Text = "$" .. format.Format(valueObject.Value)
			end
		end
	end)

end




--// BASE SETUP

function PlatformSystem.SetupBase(base)

	local platforms = {}

	for _, child in ipairs(base:GetChildren()) do

		if not child:IsA("Model") then
			continue
		end

		if not child.Name:match("^plat%d+$") then
			continue
		end

		local platformModel = child:FindFirstChild("Platform")

		if not platformModel then
			continue
		end

		table.insert(platforms, platformModel)

		PlatformSystem.SetupPlatform(platformModel)
		PlatformSystem.SetupCollector(platformModel)
	end

	if #platforms > 0 then
		basePlatforms[base.Name] = platforms
	end
end

--Stages
function PlatformSystem.RegisterPlatforms(container)

	local base = container.Parent
	if not base then return end

	basePlatforms[base.Name] = basePlatforms[base.Name] or {}

	for _, child in ipairs(container:GetChildren()) do

		if not child:IsA("Model") then
			continue
		end

		if not child.Name:match("^plat%d+$") then
			continue
		end

		local platform = child:FindFirstChild("Platform")

		if not platform then
			continue
		end

		basePlatforms[base.Name] = basePlatforms[base.Name] or {}

		for _, existing in ipairs(basePlatforms[base.Name]) do
			if existing == platform then
				return
			end
		end

		table.insert(basePlatforms[base.Name], platform)

		PlatformSystem.SetupPlatform(platform)
		PlatformSystem.SetupCollector(platform)
	end
end


--// INITIALIZE

function PlatformSystem.Initialize()

	-- existing bases
	for _, base in ipairs(workspace:GetDescendants()) do

		if not base:IsA("Model") then
			continue
		end

		if not base:GetAttribute("IsBase") then
			continue
		end

		PlatformSystem.SetupBase(base)
	end

	-- future bases/stages
	workspace.DescendantAdded:Connect(function(descendant)

		if descendant:GetAttribute("IsStage") then

			task.wait()

			PlatformSystem.RegisterPlatforms(descendant)
		end
	end)
end

function PlatformSystem.StartPromptUpdater(updatePrompts)
	RunService.Heartbeat:Connect(function()
		for baseName, platforms in pairs(basePlatforms) do
			local owner = PlatformSystem.GetBaseOwner(baseName)

			for _, platform in ipairs(platforms) do
				local placePrompt = platform:FindFirstChild("PlacePrompt", true)
				local pickupPrompt = platform:FindFirstChild("PickupPrompt", true)
				local stealPrompt = platform:FindFirstChild("StealPrompt", true)
				local lockprompt = platform:FindFirstChild("LockPrompt",true)
				if not placePrompt or not pickupPrompt then continue end

				placePrompt.Enabled = false
				pickupPrompt.Enabled = false

				if not owner then continue end 

				if owner then
					for _, player in ipairs(game.Players:GetPlayers()) do
						local canSeeSteal = player ~= owner and platform:GetAttribute("Occupied") == true

						updatestealprompt:FireClient(player, platform, canSeeSteal)
					end
				end


				local char = owner.Character
				if not char then continue end

				local hrp = char:FindFirstChild("HumanoidRootPart")
				if not hrp then continue end

				local tool = char:FindFirstChildWhichIsA("Tool")
				local isHoldingBrainrot = tool and tool:GetAttribute("Key") ~= nil
				local distance = (hrp.Position - platform:GetPivot().Position).Magnitude
				local isNearby = distance <= 20
				local isOccupied = platform:GetAttribute("Occupied") == true
				local isHoldingLock = tool and tool:GetAttribute("ItemKey") == "Padlock"

				updateprompts:FireClient(
					owner,
					platform,
					isNearby,
					isOccupied,
					isHoldingBrainrot,
					tool and tool.Name or "",
					isHoldingLock
				)
			end
		end
	end)
end

return PlatformSystem