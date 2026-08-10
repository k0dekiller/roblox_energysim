local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

local TycoonSaveData = DataStoreService:GetDataStore("EnergyTycoon_SaveSystem_v1")

local function fmt(n)
	n = math.floor(tonumber(n) or 0)

	if n < 1000 then
		return tostring(n)
	elseif n < 1000000 then
		local s = tostring(n)
		local k
		repeat s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1.%2") until k == 0
		return s
	else
		local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi"}
		local suffixIndex = 1
		local num = n

		while num >= 1000 and suffixIndex < #suffixes do
			num = num / 1000
			suffixIndex = suffixIndex + 1
		end

		local formatted = string.format("%.1f", num):gsub("%.0$", "")
		return formatted .. suffixes[suffixIndex]
	end
end

local EnergyGame = ReplicatedStorage:FindFirstChild("EnergyGame")
if not EnergyGame then
	EnergyGame = Instance.new("Folder")
	EnergyGame.Name = "EnergyGame"
	EnergyGame.Parent = ReplicatedStorage
end

local RemoteEvents = EnergyGame:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = EnergyGame
end

local function getOrCreateEvent(name)
	local ev = RemoteEvents:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = RemoteEvents
	end
	return ev
end

local BuyGeneratorEvent     = getOrCreateEvent("BuyGenerator")
local SellEnergyEvent       = getOrCreateEvent("SellEnergy")
local UpgradeGeneratorEvent = getOrCreateEvent("UpgradeGenerator")
local SellGeneratorEvent    = getOrCreateEvent("SellGenerator")
local SyncDataEvent         = getOrCreateEvent("SyncData")
local GoldenConvertEvent    = getOrCreateEvent("GoldenConvert")
local PriceChangeEvent      = getOrCreateEvent("PriceChangeEvent")
local currentEnergyRate = 1.0

local Config = require(EnergyGame:WaitForChild("EnergyConfig"))

local playerData = {}
local MAX_GENERATORS = 8

local function calculateOutput(player)
	local data = playerData[player]
	if not data or not data.hasPlot then return 0 end
	local total = 0
	for i, gen in ipairs(data.generators) do
		if i > MAX_GENERATORS then break end
		local genConf = Config.Generators[gen.type]
		if genConf then
			local mult = gen.golden and 2 or 1
			total = total + (genConf.BaseOutput * gen.level * mult)
		end
	end
	return total
end

local function getPlotCFrame(plot)
	if plot:IsA("BasePart") then
		return plot.CFrame
	elseif plot:IsA("Model") then
		if plot.PrimaryPart then
			return plot.PrimaryPart.CFrame
		else
			return plot:GetPivot()
		end
	end
	return CFrame.new(0, 0, 0)
end

local function updatePlotVisuals(plot, generators)
	if not plot then return end
	local old = plot:FindFirstChild("VisualGenerators")
	if old then old:Destroy() end
	local visFolder = Instance.new("Folder")
	visFolder.Name = "VisualGenerators"
	visFolder.Parent = plot
	local generatorModels = EnergyGame:FindFirstChild("GeneratorModels")
	for i, gen in ipairs(generators) do
		local genConf = Config.Generators[gen.type]
		if genConf then
			local slotsFolder = plot:FindFirstChild("Slots")
			local slot = (slotsFolder and slotsFolder:FindFirstChild("Slot" .. i))
				or plot:FindFirstChild("Slot" .. i, true)
				or plot:FindFirstChild("Gen" .. i, true)
			local template = generatorModels and generatorModels:FindFirstChild(genConf.Name)
			local modelInstance
			if template then
				modelInstance = template:Clone()
				modelInstance.Name = "GeneratorModel_" .. i
				local targetPosition
				if slot and slot:IsA("BasePart") then
					targetPosition = slot.Position + Vector3.new(0, 1.5, 0)
				else
					local plotCFrame = getPlotCFrame(plot)
					local offsetX = ((i - 1) % 3) * 5 - 5
					local offsetZ = math.floor((i - 1) / 3) * -5
					targetPosition = plotCFrame.Position + Vector3.new(offsetX, 3, offsetZ - 5)
				end
				local templatePivot = template:GetPivot()
				modelInstance:PivotTo(CFrame.new(targetPosition) * CFrame.fromMatrix(Vector3.new(), templatePivot.XVector, templatePivot.YVector, templatePivot.ZVector))
				for _, p in ipairs(modelInstance:GetDescendants()) do
					if p:IsA("BasePart") then p.Anchored = true end
				end
				if gen.golden then
					for _, p in ipairs(modelInstance:GetDescendants()) do
						if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
							p.Color = Color3.fromRGB(255, 215, 0)
						end
					end
				end
				modelInstance.Parent = visFolder
			else
				local part = Instance.new("Part")
				part.Name = "GeneratorModel_" .. i
				part.Size = Vector3.new(4, 3, 4)
				part.Anchored = true
				part.Material = Enum.Material.Neon
				part.Color = gen.golden and Color3.fromRGB(255, 215, 0) or genConf.NeonColor
				local targetPosition
				if slot and slot:IsA("BasePart") then
					targetPosition = slot.Position + Vector3.new(0, 1.5, 0)
				else
					local plotCFrame = getPlotCFrame(plot)
					local offsetX = ((i - 1) % 3) * 5 - 5
					local offsetZ = math.floor((i - 1) / 3) * -5
					targetPosition = plotCFrame.Position + Vector3.new(offsetX, 3, offsetZ - 5)
				end
				part.CFrame = CFrame.new(targetPosition)
				part.Parent = visFolder
				modelInstance = part
			end
			local guiParent = (modelInstance:IsA("Model") and modelInstance.PrimaryPart) or modelInstance
			if guiParent then
				local outPerSec = genConf.BaseOutput * gen.level * (gen.golden and 2 or 1)
				local bbGui = Instance.new("BillboardGui")
				bbGui.Name = "GeneratorInfoGui"
				bbGui.Size = UDim2.new(0, 200, 0, 80)
				bbGui.StudsOffset = Vector3.new(0, 4.0, 0)
				bbGui.AlwaysOnTop = true
				bbGui.MaxDistance = 45
				bbGui.Parent = guiParent
				local textLbl = Instance.new("TextLabel")
				textLbl.Size = UDim2.new(1, 0, 1, 0)
				textLbl.BackgroundTransparency = 1
				textLbl.Text = (gen.golden and "⭐ " or "") .. genConf.Name .. "\nLvl " .. gen.level .. "\n⚡ +" .. outPerSec .. "/s"
				textLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
				textLbl.Font = Enum.Font.GothamBold
				textLbl.TextSize = 15
				textLbl.Parent = bbGui
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 2
				stroke.Color = Color3.fromRGB(0, 0, 0)
				stroke.Parent = textLbl
			end
		end
	end
end

local function syncData(player)
	local data = playerData[player]
	if not data then return end
	SyncDataEvent:FireClient(player, {
		money      = data.money,
		energy     = data.energy,
		output     = calculateOutput(player),
		generators = data.generators,
		hasPlot    = data.hasPlot,
		plotName   = data.plot and data.plot.Name or nil
	})
end

local function sync(player)
	local data = playerData[player]
	if not data then return end
	if data.hasPlot and data.plot then
		updatePlotVisuals(data.plot, data.generators)
	end
	syncData(player)
end

local function findClaimPad(plot)
	local names = {"ClaimPad", "Pad", "Claim", "PlotPad", "Claim Pad"}
	for _, name in ipairs(names) do
		local found = plot:FindFirstChild(name, true)
		if found then
			if found:IsA("BasePart") then return found
			elseif found:IsA("Model") then
				local primary = found.PrimaryPart or found:FindFirstChildWhichIsA("BasePart", true)
				if primary then return primary end
			end
		end
	end
	return nil
end

local function createPlotOwnerGui(claimPad, player)
	local oldGui = claimPad:FindFirstChild("PlotOwnerGui")
	if oldGui then oldGui:Destroy() end
	local bbGui = Instance.new("BillboardGui")
	bbGui.Name = "PlotOwnerGui"
	bbGui.Size = UDim2.new(0, 220, 0, 150)
	bbGui.StudsOffset = Vector3.new(0, 16.0, 0)
	bbGui.AlwaysOnTop = false
	bbGui.Parent = claimPad
	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = bbGui
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = mainFrame
	local avatarImg = Instance.new("ImageLabel")
	avatarImg.Name = "AvatarImage"
	avatarImg.Size = UDim2.new(0, 70, 0, 70)
	avatarImg.BackgroundColor3 = Color3.fromRGB(20, 25, 40)
	avatarImg.BackgroundTransparency = 0.2
	avatarImg.BorderSizePixel = 0
	avatarImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
	avatarImg.Parent = mainFrame
	local imgCorner = Instance.new("UICorner")
	imgCorner.CornerRadius = UDim.new(1, 0)
	imgCorner.Parent = avatarImg
	local imgStroke = Instance.new("UIStroke")
	imgStroke.Color = Color3.fromRGB(0, 210, 255)
	imgStroke.Thickness = 2
	imgStroke.Parent = avatarImg
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "OwnerTitle"
	titleLbl.Size = UDim2.new(1, 0, 0, 26)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = player.DisplayName .. "'s Plot"
	titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 18
	titleLbl.Parent = mainFrame
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 2
	textStroke.Parent = titleLbl
end

local activePlotPlayers = {}
local function claimPlot(plot, player)
	local data = playerData[player]
	if not data or data.hasPlot then return end
	data.hasPlot = true
	data.plot = plot
	activePlotPlayers[player] = true
	plot:SetAttribute("Owner", player.Name)
	if #data.generators == 0 then
		table.insert(data.generators, { type = 1, level = 1, golden = false })
	end
	local claimPad = findClaimPad(plot)
	if claimPad then
		claimPad.Transparency = 1
		claimPad.CanTouch = false
		for _, child in ipairs(claimPad:GetDescendants()) do
			if child:IsA("ProximityPrompt") then child.Enabled = false end
		end
		createPlotOwnerGui(claimPad, player)
	end
	sync(player)
end

local function getAvailablePlots()
	local available = {}
	local plotFolder = Workspace:FindFirstChild("Plot")
	local plotList = plotFolder and plotFolder:GetChildren() or {}
	if #plotList == 0 then
		for _, obj in ipairs(Workspace:GetChildren()) do
			if string.find(string.lower(obj.Name), "plot") or string.match(obj.Name, "^P%d+$") then
				table.insert(plotList, obj)
			end
		end
	end
	for _, plot in ipairs(plotList) do
		local ownerAttr = plot:GetAttribute("Owner")
		if not ownerAttr or ownerAttr == "" then
			table.insert(available, plot)
		end
	end
	return available
end

local function assignPlotToPlayer(player)
	local data = playerData[player]
	if not data or data.hasPlot then return end
	if data.savedPlotName then
		local plotFolder = Workspace:FindFirstChild("Plot")
		local savedPlot = (plotFolder and plotFolder:FindFirstChild(data.savedPlotName))
			or Workspace:FindFirstChild(data.savedPlotName, true)
		if savedPlot then
			local ownerAttr = savedPlot:GetAttribute("Owner")
			if not ownerAttr or ownerAttr == "" then
				claimPlot(savedPlot, player)
				return
			end
		end
		warn("Plot salvato '" .. data.savedPlotName .. "' non disponibile per " .. player.Name)
	end
	local availablePlots = getAvailablePlots()
	if #availablePlots > 0 then
		local chosenPlot = availablePlots[math.random(1, #availablePlots)]
		claimPlot(chosenPlot, player)
	else
		warn("Nessun plot libero per " .. player.Name)
	end
end

local function teleportPlayerToPlot(player, char)
	local data = playerData[player]
	if data and data.hasPlot and data.plot then
		local claimPad = findClaimPad(data.plot)
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp and claimPad then
			hrp.CFrame = claimPad.CFrame + Vector3.new(0, 3.5, 0)
		end
	end
end

local function saveData(player)
	local data = playerData[player]
	if not data then return end
	local success, err = pcall(function()
		local plotName = data.plot and data.plot.Name or ""
		TycoonSaveData:SetAsync("Player_" .. player.UserId, {
			money      = data.money,
			energy     = data.energy,
			generators = data.generators,
			plotName   = plotName
		})
	end)
	if not success then
		warn("Errore di salvataggio per " .. player.Name .. ": " .. tostring(err))
	end
end

local function onPlayerJoined(player)
	if playerData[player] then return end
	local defaultData = {
		money         = 100,
		energy        = 0,
		generators    = {},
		plot          = nil,
		hasPlot       = false,
		savedPlotName = nil,
		gamepasses    = {}
	}
	local success, loadedData = pcall(function()
		return TycoonSaveData:GetAsync("Player_" .. player.UserId)
	end)
	if success and loadedData then
		defaultData.money      = loadedData.money or 100
		defaultData.energy     = loadedData.energy or 0
		defaultData.generators = loadedData.generators or {}
		local pn = loadedData.plotName
		defaultData.savedPlotName = (pn and pn ~= "") and pn or nil
	else
		warn("DataStore loading failed for player \"" .. player.Name .. "\": " .. tostring(loadedData))
	end

	playerData[player] = defaultData

	-- Controllo GamePass all'ingresso
	for passKey, passInfo in pairs(Config.GamePasses) do
		if passInfo.Id and passInfo.Id ~= 0 then
			pcall(function()
				if MarketplaceService:UserOwnsGamePassAsync(player.UserId, passInfo.Id) then
					playerData[player].gamepasses[passKey] = true
				end
			end)
		end
	end

	local plotFolder = Workspace:FindFirstChild("Plot")
	if not plotFolder then
		plotFolder = Workspace:WaitForChild("Plot", 10)
	end
	if not plotFolder then
		warn("Plot folder not found for player \"" .. player.Name .. "\"")
	end

	assignPlotToPlayer(player)
	sync(player)

	if player.Character then
		teleportPlayerToPlot(player, player.Character)
	end

	player.CharacterAdded:Connect(function(char)
		task.wait(0.3)
		teleportPlayerToPlot(player, char)
	end)
end

Players.PlayerAdded:Connect(onPlayerJoined)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerJoined, p)
end

local function releasePlot(plot)
	if not plot then return end
	plot:SetAttribute("Owner", nil)
	local visFolder = plot:FindFirstChild("VisualGenerators")
	if visFolder then visFolder:Destroy() end
	local claimPad = findClaimPad(plot)
	if claimPad then
		claimPad.Transparency = 0
		claimPad.CanTouch = true
		for _, child in ipairs(claimPad:GetDescendants()) do
			if child:IsA("ProximityPrompt") then child.Enabled = true end
		end
		local oldGui = claimPad:FindFirstChild("PlotOwnerGui")
		if oldGui then oldGui:Destroy() end
	end
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	local data = playerData[player]
	if data and data.plot then
		releasePlot(data.plot)
	end
	playerData[player] = nil
	activePlotPlayers[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

BuyGeneratorEvent.OnServerEvent:Connect(function(player, genType)
	local data = playerData[player]
	if not data or not data.hasPlot then return end
	if type(genType) ~= "number" then return end
	local genConf = Config.Generators[genType]
	if not genConf then return end
	if #data.generators >= MAX_GENERATORS then return end
	if data.money >= genConf.BaseCost then
		data.money = data.money - genConf.BaseCost
		table.insert(data.generators, { type = genType, level = 1, golden = false })
		sync(player)
	end
end)

SellEnergyEvent.OnServerEvent:Connect(function(player)
	local data = playerData[player]
	if not data then return end
	if data.energy > 0 then
		local guadagno = math.floor(data.energy * currentEnergyRate)

		if data.gamepasses["DoubleMoney"] then
			guadagno = guadagno * 2
		end

		data.money  = data.money + guadagno
		data.energy = 0
		sync(player)
	end
end)

UpgradeGeneratorEvent.OnServerEvent:Connect(function(player, index)
	local data = playerData[player]
	if not data then return end
	if type(index) ~= "number" or index < 1 or index > #data.generators then return end
	if not data.generators[index] then return end
	local genData = data.generators[index]
	local genConf = Config.Generators[genData.type]
	if not genConf then return end
	local upCost = math.floor(genConf.BaseCost * genData.level * 1.5)
	if data.money >= upCost then
		data.money    = data.money - upCost
		genData.level = genData.level + 1
		sync(player)
	end
end)

SellGeneratorEvent.OnServerEvent:Connect(function(player, index)
	local data = playerData[player]
	if not data then return end
	if type(index) ~= "number" or index < 1 or index > #data.generators then return end
	if not data.generators[index] then return end
	local genData = data.generators[index]
	local genConf = Config.Generators[genData.type]
	if not genConf then return end
	local refund = math.floor((genConf.BaseCost * genData.level) * 0.7)
	data.money = data.money + refund
	table.remove(data.generators, index)
	sync(player)
end)

GoldenConvertEvent.OnServerEvent:Connect(function(player, index)
	local data = playerData[player]
	if not data then return end
	if type(index) ~= "number" or index < 1 or index > #data.generators then return end
	if not data.generators[index] then return end
	local genData = data.generators[index]
	if genData.golden then return end
	local genConf = Config.Generators[genData.type]
	if not genConf then return end
	local goldCost = Config.GetGoldenCost(genData.type, genData.level)
	if data.money >= goldCost then
		data.money     = data.money - goldCost
		genData.golden = true
		sync(player)
	end
end)

-- Leaderboard Loop
task.spawn(function()
	local board = Workspace:FindFirstChild("Leaderboard", true)
	local surfaceGui = board and board:FindFirstChildWhichIsA("SurfaceGui", true)
	if not surfaceGui then return end
	surfaceGui.CanvasSize = Vector2.new(400, 620)
	surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	for _, c in ipairs(surfaceGui:GetChildren()) do c:Destroy() end
	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
	bg.BorderSizePixel = 0
	bg.Parent = surfaceGui
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 70)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.BackgroundColor3 = Color3.fromRGB(255, 185, 0)
	header.BorderSizePixel = 0
	header.Parent = bg
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 10)
	hCorner.Parent = header
	local hTitle = Instance.new("TextLabel")
	hTitle.Size = UDim2.new(1, 0, 1, 0)
	hTitle.BackgroundTransparency = 1
	hTitle.Text = "🏆 TOP RICCHI"
	hTitle.TextColor3 = Color3.fromRGB(40, 20, 0)
	hTitle.Font = Enum.Font.GothamBold
	hTitle.TextSize = 32
	hTitle.Parent = header
	local rowContainer = Instance.new("Frame")
	rowContainer.Name = "Rows"
	rowContainer.Size = UDim2.new(1, -16, 1, -80)
	rowContainer.Position = UDim2.new(0, 8, 0, 76)
	rowContainer.BackgroundTransparency = 1
	rowContainer.Parent = bg
	local rowList = Instance.new("UIListLayout")
	rowList.Padding = UDim.new(0, 6)
	rowList.Parent = rowContainer
	local rows = {}
	for i = 1, 10 do
		local rowBg = Instance.new("Frame")
		rowBg.Name = "Row" .. i
		rowBg.Size = UDim2.new(1, 0, 0, 50)
		local rc = i == 1 and Color3.fromRGB(255, 185, 0)
			or i == 2 and Color3.fromRGB(180, 180, 180)
			or i == 3 and Color3.fromRGB(180, 100, 40)
			or Color3.fromRGB(35, 30, 55)
		rowBg.BackgroundColor3 = rc
		rowBg.BackgroundTransparency = i > 3 and 0.3 or 0.15
		rowBg.BorderSizePixel = 0
		rowBg.Visible = false
		rowBg.Parent = rowContainer
		local rCorner = Instance.new("UICorner")
		rCorner.CornerRadius = UDim.new(0, 8)
		rCorner.Parent = rowBg
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.Size = UDim2.new(0, 40, 0, 40)
		avatar.Position = UDim2.new(0, 5, 0.5, -20)
		avatar.BackgroundColor3 = Color3.fromRGB(30, 25, 50)
		avatar.BorderSizePixel = 0
		avatar.Parent = rowBg
		local avCorner = Instance.new("UICorner")
		avCorner.CornerRadius = UDim.new(1, 0)
		avCorner.Parent = avatar
		local rankLbl = Instance.new("TextLabel")
		rankLbl.Name = "Rank"
		rankLbl.Size = UDim2.new(0, 36, 1, 0)
		rankLbl.Position = UDim2.new(0, 48, 0, 0)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Text = "#" .. i
		rankLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		rankLbl.Font = Enum.Font.GothamBold
		rankLbl.TextSize = 18
		rankLbl.Parent = rowBg
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "PlayerName"
		nameLbl.Size = UDim2.new(0, 160, 0.5, 0)
		nameLbl.Position = UDim2.new(0, 86, 0, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = ""
		nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 16
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = rowBg
		local moneyLbl = Instance.new("TextLabel")
		moneyLbl.Name = "Money"
		moneyLbl.Size = UDim2.new(0, 160, 0.5, 0)
		moneyLbl.Position = UDim2.new(0, 86, 0.5, 0)
		moneyLbl.BackgroundTransparency = 1
		moneyLbl.Text = ""
		moneyLbl.TextColor3 = Color3.fromRGB(100, 255, 150)
		moneyLbl.Font = Enum.Font.Gotham
		moneyLbl.TextSize = 14
		moneyLbl.TextXAlignment = Enum.TextXAlignment.Left
		moneyLbl.Parent = rowBg
		rows[i] = { bg = rowBg, avatar = avatar, rank = rankLbl, name = nameLbl, money = moneyLbl }
	end
	local lastSignature = ""
	while true do
		task.wait(5)
		local entries = {}
		for plr, data in pairs(playerData) do
			table.insert(entries, { name = plr.DisplayName, userId = plr.UserId, money = data.money })
		end
		table.sort(entries, function(a, b) return a.money > b.money end)
		local sigParts = {}
		for _, e in ipairs(entries) do
			table.insert(sigParts, e.userId .. ":" .. e.money)
		end
		local signature = table.concat(sigParts, "|")
		if signature == lastSignature then continue end
		lastSignature = signature
		for i, row in ipairs(rows) do
			local e = entries[i]
			if e then
				row.bg.Visible = true
				row.avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. e.userId .. "&w=150&h=150"
				row.rank.Text = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or ("#" .. i)
				row.name.Text = e.name
				row.money.Text = "💰 $" .. fmt(e.money)
			else
				row.bg.Visible = false
			end
		end
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	local data = playerData[player]
	if not data then return end

	for passKey, passInfo in pairs(Config.GamePasses) do
		if passInfo.Id == gamePassId then
			data.gamepasses[passKey] = true
			if passKey == "StarterPack" then
				data.money = data.money + 10000
				table.insert(data.generators, { type = 1, level = 1, golden = false })
			end
			sync(player)
			print(player.Name .. " has bought the " .. passKey .. " GamePass")
		end
	end
end)

-- Energy Production Loop
task.spawn(function()
	local autoSellInterval = 5 
	local elapsedTime = 0
	local syncTimer = 0 -- Nuovo timer per ridurre il lag di rete

	while true do
		task.wait(1)
		elapsedTime = elapsedTime + 1
		syncTimer = syncTimer + 1 -- Aumenta di 1 ogni secondo

		for player in pairs(activePlotPlayers) do
			local data = playerData[player]
			if data and data.hasPlot then
				local out = calculateOutput(player)

				if out > 0 then
					if data.gamepasses["DoubleEnergy"] then
						out = out * 2
					end

					data.energy = data.energy + out

					local didAutoSell = false

					-- L'autosell controlla se è arrivato il momento giusto in base ai secondi impostati
					if data.gamepasses["AutoSell"] and elapsedTime >= autoSellInterval then
						local guadagno = math.floor(data.energy * currentEnergyRate)
						if data.gamepasses["DoubleMoney"] then
							guadagno = guadagno * 2
						end
						data.money = data.money + guadagno
						data.energy = 0 
						didAutoSell = true
					end

					-- OTTIMIZZAZIONE ANTI-LAG: Sincronizza i dati col client solo ogni 3 sec O se ha appena fatto autosell
					if syncTimer >= 3 or didAutoSell then
						syncData(player)
					end
				end
			else
				activePlotPlayers[player] = nil
			end
		end

		-- Resetta il contatore dell'autosell
		if elapsedTime >= autoSellInterval then
			elapsedTime = 0
		end

		-- Resetta il contatore del sync di rete
		if syncTimer >= 3 then
			syncTimer = 0
		end
	end
end)

-- Price Board Setup & Loop
local modelloPrezzi = Workspace:FindFirstChild("prezzi")
local timerLabel = nil

if modelloPrezzi then
	local surfaceGui = modelloPrezzi:FindFirstChildWhichIsA("SurfaceGui", true)
	if surfaceGui then
		timerLabel = surfaceGui:FindFirstChild("TextLabel")
		if timerLabel then
			timerLabel.Text = "Updating prices..."
		end
	end
else
	warn("ATTENZIONE: Modello 'prezzi' non trovato nel Workspace!")
end

task.spawn(function()
	local timeRemaining = 300

	while true do
		task.wait(1)
		timeRemaining = timeRemaining - 1

		local minutes = math.floor(timeRemaining / 60)
		local seconds = timeRemaining % 60
		local timeString = string.format("%02d:%02d", minutes, seconds)

		if timerLabel then
			timerLabel.Text = "Next price change:\n" .. timeString .. "\n\nCurrent price: " .. tostring(currentEnergyRate)
		end

		if timeRemaining <= 0 then
			currentEnergyRate = math.random(5, 20) / 10
			PriceChangeEvent:FireAllClients(currentEnergyRate)
			timeRemaining = 300
		end
	end
end)
