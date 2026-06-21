--This is one of the core scripts used in managing player's base assignments and data loading

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SignModule = require(ReplicatedStorage:WaitForChild("SignModule"))
local ModelAligner = require(ReplicatedStorage:WaitForChild("ModelAligner"))
local DataManager = require(game.ServerScriptService.Modules.DataManager)
local PlatformSystem = require(game.ReplicatedStorage.Modules:WaitForChild("PlatformSystem"))
local rejoinupdate = game.ReplicatedStorage.Events:WaitForChild("UpgradeSignRejoin")

local soundfolder = ReplicatedStorage:WaitForChild("Sounds")
local bgm = soundfolder:WaitForChild("BGM")
bgm.Looped = true
bgm:Play()

PlatformSystem.Initialize()

local heldTools = {}

----------------------------------------------------
-- GUI FUNCTION
----------------------------------------------------
local function setBaseGui(plot, player, state)
	local displayPart = plot:FindFirstChild("ProfileIcon")
	if not displayPart then return end

	local gui = displayPart:FindFirstChild("ProfileGUI")
	if not gui then return end

	gui.Enabled = state

	if state and player then
		local imageLabel = gui:FindFirstChild("ProfilePicture")
		local textLabel = gui:FindFirstChild("Name")

		if textLabel then
			textLabel.Text = player.Name
		end

		if imageLabel then
			local content = Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)
			imageLabel.Image = content
		end
	end
end

----------------------------------------------------
-- PLAYER JOIN
----------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
	
	plr:SetAttribute("Chased", false)
	-- LEADERSTATS
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = plr

	local power = Instance.new("NumberValue")
	power.Name = "FirePower"
	power.Value = 500
	power.Parent = leaderstats

	local money = Instance.new("NumberValue")
	money.Name = "Money"
	money.Value = 500
	money.Parent = leaderstats

	local stage = Instance.new("IntValue")
	stage.Name = "Stage"
	stage.Value = 1
	stage.Parent = plr

	-- FOLDERS
	if not plr:FindFirstChild("OwnedTools") then
		local ownedTools = Instance.new("Folder")
		ownedTools.Name = "OwnedTools"
		ownedTools.Parent = plr
	end

	if not plr:FindFirstChild("EquippedTools") then
		local equippedTools = Instance.new("Folder")
		equippedTools.Name = "EquippedTools"
		equippedTools.Parent = plr
	end

	-- ASSIGN PLOT
	local plot
	for _, v in pairs(workspace.testplate:GetChildren()) do
		if v:FindFirstChild("Owner") and v.Owner.Value == "None" then
			plot = v
			break
		end
	end

	if not plot then
		warn("No free plot for", plr.Name)
		return
	end

	plot.Owner.Value = plr.Name
	plr:SetAttribute("Base", plot.Name)

	local function spawnCharacter(char)
		local base = workspace.testplate:FindFirstChild(plr:GetAttribute("Base"))
		if not base then return end

		local spawner = base:FindFirstChild("Spawner")
		if not spawner then return end

		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if not hrp then return end
		
		char:PivotTo(spawner.CFrame + Vector3.new(0, 5, 0))
	end

	plr.CharacterAdded:Connect(function(char)
		task.defer(spawnCharacter, char)
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and (
				child:GetAttribute("Key") or
					child:GetAttribute("ItemKey")
				) then
				heldTools[plr.UserId] = child
			end
		end)

		char.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") and (
				child:GetAttribute("Key") or
					child:GetAttribute("ItemKey")
				) then
				heldTools[plr.UserId] = nil
			end
		end)
	end)

	if plr.Character then
		task.defer(spawnCharacter, plr.Character)
	end

	DataManager.LoadPlayer(plr)

	repeat task.wait() until plr:GetAttribute("DataLoaded")
	plr:SetAttribute("CharacterLoaded",true)

	local playerStage = plr:GetAttribute("Stage") or 1

	plot.sign.sign.SignGUI.SignTextLabel.Text = plr.Name .. "'s Base"
	plot.upgradeSign.sign.UpgradeGUI.Enabled = true

	setBaseGui(plot, plr, true)
	SignModule.updateSign(plr)

	rejoinupdate:FireClient(plr, playerStage)

	-- LOAD STAGES
	local stageFolder = ReplicatedStorage:WaitForChild("Stages")

	if playerStage ~= 1 then
		for i = 2, playerStage do
			local stageModel = stageFolder:FindFirstChild("Stage" .. i)
			if stageModel then
				local clone = stageModel:Clone()
				clone.Parent = plot
				ModelAligner.AlignModelToBase(clone, plot)
			end
		end
	end

	task.wait(1)	
	DataManager.RestorePlatforms(plr)
end)

----------------------------------------------------
-- PLAYER LEAVE CLEANUP
----------------------------------------------------
local function cleanupBase(plr)
	local baseName = plr:GetAttribute("Base")
	if not baseName or baseName == "" then return end

	local base = workspace.testplate:FindFirstChild(baseName)
	if not base then return end

	base.Owner.Value = "None"
	base.sign.sign.SignGUI.SignTextLabel.Text = "Empty Base"
	plr:SetAttribute("Base", "")

	local gui = base.upgradeSign.sign:FindFirstChild("UpgradeGUI")
	if gui then
		gui.Enabled = false
	end

	setBaseGui(base, nil, false)

	for _, child in pairs(base:GetChildren()) do
		if child.Name:match("Stage") then
			child:Destroy()
		end
	end

	for _, child in pairs(base:GetDescendants()) do
		if child:IsA("Model") and child.Name:match("^plat%d+$") then
			local platform = child:FindFirstChild("Platform")
			if not platform then continue end
			
			platform:SetAttribute("CollectorSetup", false)

			local levelpart = platform:FindFirstChild("LevelGUI")
			if levelpart then
				local levelGUI = levelpart:FindFirstChild("LevelUp")
				levelpart.Transparency = 1
				if levelGUI then levelGUI.Enabled = false end
			end

			for _, obj in pairs(platform:GetChildren()) do
				if obj:IsA("Model") then
					obj:Destroy()
				end
			end

			platform:SetAttribute("Occupied", false)
			platform:SetAttribute("BrainrotKey", "")
			platform:SetAttribute("BrainrotLevel", 0)
			platform:SetAttribute("MoneyPerSecond", 0)
			platform:SetAttribute("Rarity", "")
			platform:SetAttribute("Loaded", false)
			platform:SetAttribute("Exclusive", nil)
			platform:SetAttribute("Locked", false)
			platform:SetAttribute("Mutation", "")
			platform:SetAttribute("MoneyMultiplier", 1)
		end
	end
end

Players.PlayerRemoving:Connect(function(plr)
	local character = plr.Character
	
	if plr:GetAttribute("Chased") == true then
		plr:SetAttribute("Chased", false)
		local char = plr.Character
		if char then
			local tool = char:FindFirstChildOfClass("Tool")
			if tool and tool:GetAttribute("Key") ~= nil then
				tool:Destroy()
			end
		end
	end
	
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end

	DataManager.SavePlayer(plr, true, heldTools[plr.UserId])
	heldTools[plr.UserId] = nil
	cleanupBase(plr)
	plr:SetAttribute("DataLoaded", nil)
end)

----------------------------------------------------
-- BIND TO CLOSE
----------------------------------------------------
game:BindToClose(function()
	local threads = {}

	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(threads, task.spawn(function()
			if player:GetAttribute("Chased") == true then
				player:SetAttribute("Chased", false)
				local char = player.Character
				if char then
					local tool = char:FindFirstChildOfClass("Tool")
					if tool and tool:GetAttribute("Key") ~= nil then
						tool:Destroy()
					end
				end
			end
			DataManager.SavePlayer(player, false, heldTools[player.UserId])
		end))
	end

	-- wait for all saves to finish
	for _, thread in ipairs(threads) do
		task.wait()
	end

	task.wait(3)
end)

----------------------------------------------------
-- AUTOSAVE
----------------------------------------------------
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				DataManager.SavePlayer(player, false, heldTools[player.UserId])
			end)
		end
	end
end)