-- Push any edits to k0dekiller/roblox_energysim

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local EnergyGame = ReplicatedStorage:WaitForChild("EnergyGame")
local Config = require(EnergyGame:WaitForChild("EnergyConfig"))
local RemoteEvents = EnergyGame:WaitForChild("RemoteEvents")
local BuyGeneratorEvent     = RemoteEvents:WaitForChild("BuyGenerator")
local SellEnergyEvent       = RemoteEvents:WaitForChild("SellEnergy")
local UpgradeGeneratorEvent = RemoteEvents:WaitForChild("UpgradeGenerator")
local SellGeneratorEvent    = RemoteEvents:WaitForChild("SellGenerator")
local SyncDataEvent         = RemoteEvents:WaitForChild("SyncData")
local GoldenConvertEvent    = RemoteEvents:WaitForChild("GoldenConvert")
local PriceChangeEvent      = RemoteEvents:WaitForChild("PriceChangeEvent")

local Sounds = EnergyGame:WaitForChild("Sounds", 5)
local function playSound(name)
	if not Sounds then return end
	local s = Sounds:FindFirstChild(name)
	if s then s:Play() end
end

local function fmt(n)
	n = math.floor(tonumber(n) or 0)

	if n < 1000 then
		return tostring(n)
	elseif n < 1000000 then
		-- Inserisce il punto per le migliaia (es: 150.000)
		local s = tostring(n)
		local k
		repeat s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1.%2") until k == 0
		return s
	else
		-- Da 1 Milione in su usa M, B, T, Qa, Qi
		local suffixes = {"", "K", "M", "B", "T", "Qa", "Qi"}
		local suffixIndex = 1
		local num = n

		while num >= 1000 and suffixIndex < #suffixes do
			num = num / 1000
			suffixIndex = suffixIndex + 1
		end

		-- format("%.1f") mantiene 1 decimale. gsub("%.0$", "") rimuove lo .0 se il numero è intero (es. 30.0B diventa 30B)
		local formatted = string.format("%.1f", num):gsub("%.0$", "")
		return formatted .. suffixes[suffixIndex]
	end
end

local topGUI       = playerGui:WaitForChild("topGUI", 10)
local risorseGUI   = playerGui:WaitForChild("risorseGUI", 10)
local shopGUI      = playerGui:WaitForChild("ShopGUI", 10)
local vipGUI       = playerGui:WaitForChild("VIPGUI", 10)
local goldenGUI    = playerGui:WaitForChild("GoldenGUI", 10)
local inventoryGUI = playerGui:WaitForChild("InventoryGUI", 10)
local notificaGUI = playerGui:WaitForChild("NotificheGUI", 10)
local notificationBox = notificaGUI and notificaGUI:WaitForChild("NotificationBox")
local messageText = notificationBox and notificationBox:WaitForChild("MessageText")

if not (topGUI and risorseGUI and shopGUI and vipGUI and goldenGUI and inventoryGUI) then
	warn("[EnergyTycoonClient] Una o più GUI mancanti in PlayerGui. Script terminato.")
	return
end

local invBtn      = topGUI:WaitForChild("INVbutton")
local plotBtn     = topGUI:WaitForChild("PLOTbutton")
local sellBtn     = topGUI:WaitForChild("SELLbutton")

local moneyLbl    = risorseGUI:WaitForChild("soldi")
local energyLbl   = risorseGUI:WaitForChild("energiaposseduta")
local outputLbl   = risorseGUI:WaitForChild("energia al secondo")

moneyLbl.Text = "Caricamento..."
energyLbl.Text = "..."
outputLbl.Text = "..."

-- Cerca il close button solo nel Frame (non nei suoi ScrollingFrame o entry)
local function findFrameClose(frame)
	local direct = frame:FindFirstChild("closebutton")
	if direct then return direct end
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("ScrollingFrame") then
			local found = child:FindFirstChild("closebutton", true)
			if found then return found end
		end
	end
	return nil
end

local shopFrame       = shopGUI:WaitForChild("Frame")
local shopClose       = findFrameClose(shopFrame)
local shopScroll      = shopFrame:WaitForChild("ScrollingFrame")

local vipFrame        = vipGUI:WaitForChild("Frame")
local vipClose        = findFrameClose(vipFrame)
local vipScroll       = vipFrame:WaitForChild("ScrollingFrame")

local goldenFrame     = goldenGUI:WaitForChild("Frame")
local goldenClose     = findFrameClose(goldenFrame)
local goldenScroll    = goldenFrame:WaitForChild("ScrollingFrame")
local entryTemplate   = goldenScroll:WaitForChild("entryTemplate")
entryTemplate.Visible = false
entryTemplate.LayoutOrder = 9999

local invFrame          = inventoryGUI:WaitForChild("Frame")
local invClose          = findFrameClose(invFrame)
local invScroll         = invFrame:WaitForChild("ScrollingFrame")
local invEntryTemplate  = invScroll:WaitForChild("entryTemplate")
invEntryTemplate.Visible = false
invEntryTemplate.LayoutOrder = 9999

local currentData = nil
local updateGoldenUI -- forward declaration
local updateInventoryUI -- forward declaration

local shopLabels = {
	pannelloLabel      = 1,
	trubinaLabel       = 2,
	hydroelectricLabel = 3,
	nuclearLabel       = 4,
	quantumLabel       = 5,
}

local generatorImages = {
	[1] = "rbxassetid://109781759571911",
	[2] = "rbxassetid://86744633205226",
	[3] = "rbxassetid://117144540071611",
	[4] = "rbxassetid://80456270530242",
	[5] = "rbxassetid://127785416980940",
}

local function showGui(gui)
	shopGUI.Enabled      = gui == shopGUI
	vipGUI.Enabled       = gui == vipGUI
	goldenGUI.Enabled    = gui == goldenGUI
	inventoryGUI.Enabled = gui == inventoryGUI
end

local function hideAll()
	shopGUI.Enabled      = false
	vipGUI.Enabled       = false
	goldenGUI.Enabled    = false
	inventoryGUI.Enabled = false
end

hideAll()

local function teleportToSellPad()
	local sellObj = Workspace:FindFirstChild("SellTerminal", true) or Workspace:FindFirstChild("SellPad", true)
	if not sellObj then
		warn("[EnergyTycoonClient] SellTerminal/SellPad non trovato in Workspace")
		return
	end
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local targetCFrame = sellObj:IsA("BasePart") and sellObj.CFrame or (sellObj:IsA("Model") and sellObj:GetPivot())
		if targetCFrame then
			char.HumanoidRootPart.CFrame = targetCFrame + Vector3.new(0, 3.5, 0)
		end
	end
end

local function safeFire(remote, ...)
	local ok, err = pcall(function(...) remote:FireServer(...) end, ...)
	if not ok then warn("[EnergyTycoonClient] FireServer fallito: " .. tostring(err)) end
end

local function teleportToMyPlot()
	if currentData and currentData.plotName then
		local plotFolder = Workspace:FindFirstChild("Plot")
		local plot = (plotFolder and plotFolder:FindFirstChild(currentData.plotName))
			or Workspace:FindFirstChild(currentData.plotName, true)
		if plot then
			local claimPad = plot:FindFirstChild("ClaimPad", true) or plot:FindFirstChild("Pad", true)
			local char = player.Character
			if char and char:FindFirstChild("HumanoidRootPart") and claimPad then
				char.HumanoidRootPart.CFrame = claimPad.CFrame + Vector3.new(0, 3.5, 0)
			end
		end
	end
end

sellBtn.MouseButton1Click:Connect(function()
	playSound("Click")
	teleportToSellPad()
	safeFire(SellEnergyEvent)
end)

plotBtn.MouseButton1Click:Connect(function()
	playSound("Click")
	teleportToMyPlot()
end)

invBtn.MouseButton1Click:Connect(function()
	playSound("Click")
	if inventoryGUI.Enabled then
		hideAll()
	else
		updateInventoryUI()
		showGui(inventoryGUI)
	end
end)

if shopClose then
	shopClose.MouseButton1Click:Connect(function()
		playSound("Click")
		hideAll()
	end)
end

if vipClose then
	vipClose.MouseButton1Click:Connect(function()
		playSound("Click")
		hideAll()
	end)
end

if goldenClose then
	goldenClose.MouseButton1Click:Connect(function()
		playSound("Click")
		hideAll()
	end)
end

if invClose then
	invClose.MouseButton1Click:Connect(function()
		playSound("Click")
		hideAll()
	end)
end

local buyButtons = {}

for labelName, genType in pairs(shopLabels) do
	local labelFrame = shopScroll:FindFirstChild(labelName)
	if labelFrame then
		local buyBtn2 = labelFrame:FindFirstChild("BUYbutton")
		if buyBtn2 then
			buyButtons[genType] = buyBtn2
			buyBtn2.MouseButton1Click:Connect(function()
				if currentData and currentData.generators and #currentData.generators >= 8 then return end
				safeFire(BuyGeneratorEvent, genType)
				playSound("BuyGenerator")
			end)
		end
	end
end

local function updateShopButtons()
	local full = currentData and currentData.generators and #currentData.generators >= 8
	for _, btn in pairs(buyButtons) do
		btn.Active = not full
		local lbl = btn:FindFirstChildWhichIsA("TextLabel")
		if lbl then
			lbl.Text = full and "🔒 SLOT PIENI" or "COMPRA"
		end
	end
end

local vipLabels = {
	["2xenergyLabel"] = "DoubleEnergy",
	["2xmoneyLabel"]  = "DoubleMoney",
	["autosellLabel"] = "AutoSell",
}

for labelName, passKey in pairs(vipLabels) do
	local labelFrame = vipScroll:FindFirstChild(labelName)
	if labelFrame and Config.GamePasses then
		local gp = Config.GamePasses[passKey]
		if gp then
			local buyBtn2 = labelFrame:FindFirstChild("BUYbutton")
			if buyBtn2 then
				buyBtn2.MouseButton1Click:Connect(function()
					if gp.Id and gp.Id ~= 0 then
						MarketplaceService:PromptGamePassPurchase(player, gp.Id)
					end
				end)
			end
		end
	end
end

updateInventoryUI = function()
	for _, child in ipairs(invScroll:GetChildren()) do
		if child:IsA("ImageLabel") and child ~= invEntryTemplate then
			child:Destroy()
		end
	end

	if not currentData or not currentData.generators or #currentData.generators == 0 then
		return
	end

	local tplPos = invEntryTemplate.Position
	local tplSize = invEntryTemplate.Size
	local spacing = tplSize.Y.Offset + 10

	for idx, gen in ipairs(currentData.generators) do
		local genConfig = Config.Generators[gen.type]
		if genConfig then
			local entry = invEntryTemplate:Clone()
			entry.Name = "InvEntry_" .. idx
			entry.Visible = true
			entry.LayoutOrder = idx
			entry.Position = UDim2.new(tplPos.X.Scale, tplPos.X.Offset, tplPos.Y.Scale, tplPos.Y.Offset + (idx - 1) * spacing)
			entry.Parent = invScroll

			local textLabels = {}
			for _, child in ipairs(entry:GetChildren()) do
				if child:IsA("TextLabel") then
					table.insert(textLabels, child)
				end
			end

			local titleText = (gen.golden and "⭐ " or "") .. genConfig.Name .. "  Lvl " .. gen.level
			local outPerSec = genConfig.BaseOutput * gen.level * (gen.golden and 2 or 1)

			local function applyScaled(lbl, minS, maxS, yOffset)
				lbl.RichText = true
				lbl.TextScaled = true
				lbl.TextWrapped = false
				lbl.TextXAlignment = Enum.TextXAlignment.Left
				lbl.TextYAlignment = Enum.TextYAlignment.Center
				lbl.ClipsDescendants = false
				local c = lbl:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
				c.MinTextSize = minS
				c.MaxTextSize = maxS
				c.Parent = lbl
				if yOffset then
					local p = lbl.Position
					lbl.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + yOffset)
				end
			end
			if textLabels[1] then
				textLabels[1].Text = titleText
				applyScaled(textLabels[1], 18, 26, 6)
			end
			if textLabels[2] then
				textLabels[2].Text = "⚡ +" .. fmt(outPerSec) .. "/s"
				applyScaled(textLabels[2], 16, 24, 6)
			end

			local entryImg = entry:FindFirstChildWhichIsA("ImageLabel")
			if entryImg and generatorImages[gen.type] then
				entryImg.Image = generatorImages[gen.type]
			end

			local upgradeBtn = entry:FindFirstChild("UPGRADEbutton")
			if upgradeBtn then
				local upCost = math.floor(genConfig.BaseCost * gen.level * 1.5)
				local upLbl = upgradeBtn:FindFirstChildWhichIsA("TextLabel")
				if upLbl then upLbl.Text = "⬆ $" .. fmt(upCost) end
				upgradeBtn.MouseButton1Click:Connect(function()
					safeFire(UpgradeGeneratorEvent, idx)
					playSound("Click")
				end)
			end

			local sellEntryBtn = entry:FindFirstChild("SELLbutton")
			if sellEntryBtn then
				local refund = math.floor((genConfig.BaseCost * gen.level) * 0.7)
				local sLbl = sellEntryBtn:FindFirstChildWhichIsA("TextLabel")
				if sLbl then sLbl.Text = "💸 $" .. fmt(refund) end
				sellEntryBtn.MouseButton1Click:Connect(function()
					safeFire(SellGeneratorEvent, idx)
					playSound("Click")
				end)
			end
		end
	end
end

updateGoldenUI = function()
	for _, child in ipairs(goldenScroll:GetChildren()) do
		if child:IsA("ImageLabel") and child ~= entryTemplate then
			child:Destroy()
		end
	end

	if not currentData or not currentData.generators or #currentData.generators == 0 then
		return
	end

	local tplPos = entryTemplate.Position
	local tplSize = entryTemplate.Size
	local spacing = tplSize.Y.Offset + 10

	for idx, gen in ipairs(currentData.generators) do
		local genConfig = Config.Generators[gen.type]
		if genConfig then
			local entry = entryTemplate:Clone()
			entry.Name = "GoldenEntry_" .. idx
			entry.Visible = true
			entry.LayoutOrder = idx
			entry.Position = UDim2.new(tplPos.X.Scale, tplPos.X.Offset, tplPos.Y.Scale, tplPos.Y.Offset + (idx - 1) * spacing)
			entry.Parent = goldenScroll

			local textLabels = {}
			for _, child in ipairs(entry:GetChildren()) do
				if child:IsA("TextLabel") then
					table.insert(textLabels, child)
				end
			end

			local titleText = (gen.golden and "⭐ " or "") .. genConfig.Name .. "  Lvl " .. gen.level
			local outPerSec = genConfig.BaseOutput * gen.level * (gen.golden and 2 or 1)

			local function applyScaled(lbl, minS, maxS, yOffset)
				lbl.RichText = true
				lbl.TextScaled = true
				lbl.TextWrapped = false
				lbl.TextXAlignment = Enum.TextXAlignment.Left
				lbl.TextYAlignment = Enum.TextYAlignment.Center
				lbl.ClipsDescendants = false
				local c = lbl:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
				c.MinTextSize = minS
				c.MaxTextSize = maxS
				c.Parent = lbl
				if yOffset then
					local p = lbl.Position
					lbl.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + yOffset)
				end
			end
			if textLabels[1] then
				textLabels[1].Text = titleText
				applyScaled(textLabels[1], 18, 26, 6)
			end
			if textLabels[2] then
				textLabels[2].Text = "⚡ +" .. fmt(outPerSec) .. "/s"
				applyScaled(textLabels[2], 16, 24, 6)
			end

			local entryImg = entry:FindFirstChildWhichIsA("ImageLabel")
			if entryImg and generatorImages[gen.type] then
				entryImg.Image = generatorImages[gen.type]
			end

			local convertBtn = entry:FindFirstChild("CONVERTbutton")
			if convertBtn then
				local btnLbl = convertBtn:FindFirstChildWhichIsA("TextLabel")
				if gen.golden then
					convertBtn.Active = false
					if btnLbl then btnLbl.Text = "✓ ATTIVO" end
				else
					local goldCost = math.floor(genConfig.BaseCost * 2.5)
					if btnLbl then btnLbl.Text = "⭐ $" .. fmt(goldCost) end
					convertBtn.MouseButton1Click:Connect(function()
						safeFire(GoldenConvertEvent, idx)
						playSound("GoldenConvert")
					end)
				end
			end
		end
	end
end

local function checkMatch(obj, keyword)
	if not obj then return false end
	local keyLower = string.lower(keyword)
	if string.find(string.lower(obj.Name), keyLower) then return true end
	if obj:IsA("ProximityPrompt") then
		if string.find(string.lower(obj.ActionText or ""), keyLower) or string.find(string.lower(obj.ObjectText or ""), keyLower) then
			return true
		end
	end
	return false
end

local connectedPrompts = {}
local function setupTerminalPrompt(prompt)
	if connectedPrompts[prompt] then return end
	connectedPrompts[prompt] = true
	prompt.AncestryChanged:Connect(function(_, parent)
		if not parent then connectedPrompts[prompt] = nil end
	end)
	prompt.Triggered:Connect(function(who)
		if who ~= player then return end
		local parent = prompt.Parent
		local grandParent = parent and parent.Parent
		if checkMatch(prompt, "sell") or checkMatch(parent, "sell") or checkMatch(grandParent, "sell") then
			safeFire(SellEnergyEvent)
			playSound("SellEnergy")
		elseif checkMatch(prompt, "vip") or checkMatch(parent, "vip") or checkMatch(grandParent, "vip") then
			showGui(vipGUI)
		elseif checkMatch(prompt, "shop") or checkMatch(parent, "shop") or checkMatch(grandParent, "shop") then
			showGui(shopGUI)
		elseif checkMatch(prompt, "gold") or checkMatch(parent, "gold") or checkMatch(grandParent, "gold") then
			updateGoldenUI()
			showGui(goldenGUI)
		end
	end)
end

for _, desc in ipairs(Workspace:GetDescendants()) do
	if desc:IsA("ProximityPrompt") then
		setupTerminalPrompt(desc)
	end
end

local descendantAddedConn
descendantAddedConn = Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("ProximityPrompt") then
		setupTerminalPrompt(desc)
	end
end)

player.AncestryChanged:Connect(function(_, parent)
	if not parent and descendantAddedConn then
		descendantAddedConn:Disconnect()
		descendantAddedConn = nil
	end
end)

SyncDataEvent.OnClientEvent:Connect(function(data)
	currentData = data
	if data.hasPlot then
		moneyLbl.Text  = "$" .. fmt(data.money)
		energyLbl.Text = fmt(data.energy)
		outputLbl.Text = "+" .. fmt(data.output) .. "/s"
		updateShopButtons()
		updateGoldenUI()
		updateInventoryUI()
	else
		moneyLbl.Text  = "$0"
		energyLbl.Text = "0"
		outputLbl.Text = "+0/s"
	end
end)

PriceChangeEvent.OnClientEvent:Connect(function(newRate)
	if notificationBox and messageText then
		messageText.Text = "⚠️ ENERGY RATE CHANGED TO: " .. tostring(newRate) .. "!"
		notificationBox.Visible = true
		playSound("Click")
		task.delay(5, function()
			notificationBox.Visible = false
		end)
	end
end)