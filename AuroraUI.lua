--[[
	Aurora UI  —  a minimal-dark Luau UI library for Roblox executors
	Sidebar tab layout · full component set · draggable · keybind toggle
	notifications · config save/load · runtime accent picker

	Usage:
		local Aurora = loadstring(game:HttpGet("<raw-url>/AuroraUI.luau"))()
		local Window = Aurora:CreateWindow({ Title = "vertex", SubTitle = "discord.gg/vertex" })
		local Tab    = Window:CreateTab({ Name = "Combat", Icon = "⚔" })
		local Sec    = Tab:CreateSection("General")
		Sec:AddToggle({ Name = "Auto Farm", Flag = "autofarm", Default = false,
			Callback = function(v) print(v) end })

	This library only builds UI. It contains no game logic.
--]]

--// Services -----------------------------------------------------------------
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local TextService       = game:GetService("TextService")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--// Executor compatibility ----------------------------------------------------
local function getParentGui()
	local ok, hidden = pcall(function() return gethui and gethui() end)
	if ok and hidden then return hidden end
	local ok2, cg = pcall(function() return CoreGui end)
	if ok2 and cg then return cg end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function protect(gui)
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		elseif protect_gui then
			protect_gui(gui)
		end
	end)
end

local hasFiles = (typeof(writefile) == "function")
	and (typeof(readfile) == "function")
	and (typeof(isfile) == "function")

--// Design tokens --------------------------------------------------------------
local RADIUS = { sm = 4, md = 7, lg = 10, xl = 14 }
local SPACE  = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }

local Theme = {
	Background   = Color3.fromRGB(10, 10, 12),
	Chrome       = Color3.fromRGB(13, 13, 16),
	Sidebar      = Color3.fromRGB(15, 15, 18),
	SidebarAlt   = Color3.fromRGB(19, 19, 23),
	Panel        = Color3.fromRGB(18, 18, 21),
	Element      = Color3.fromRGB(24, 24, 28),
	ElementHover = Color3.fromRGB(30, 30, 35),
	Border       = Color3.fromRGB(28, 28, 33),
	BorderSoft   = Color3.fromRGB(24, 24, 28),
	Text         = Color3.fromRGB(235, 235, 238),
	TextDim      = Color3.fromRGB(122, 122, 132),
	TextFaint    = Color3.fromRGB(72, 72, 80),
	Accent       = Color3.fromRGB(151, 105, 255),
	AccentDim    = Color3.fromRGB(96, 68, 168),
}

local TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FONT       = Enum.Font.Gotham
local FONT_MED   = Enum.Font.GothamMedium
local FONT_BOLD  = Enum.Font.GothamBold

--// Small helpers -------------------------------------------------------------
local function tween(obj, props, info)
	info = info or TWEEN
	local ok, t = pcall(function() return TweenService:Create(obj, info, props) end)
	if ok and t and pcall(function() t:Play() end) then return t end
	pcall(function()
		for k, v in pairs(props) do obj[k] = v end
	end)
	return nil
end

local function make(class, props, children)
	local inst = Instance.new(class)
	local parent = props and props.Parent
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				local ok, err = pcall(function() inst[k] = v end)
				if not ok then
					warn("[AuroraUI] " .. class .. "." .. tostring(k) .. " failed: " .. tostring(err))
				end
			end
		end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or RADIUS.md), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return make("UIStroke", {
		Color = color or Theme.Border,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function pad(parent, all)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, all), PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all), PaddingRight = UDim.new(0, all),
		Parent = parent,
	})
end

-- subtle top-to-bottom depth gradient; keeps flat panels from reading as
-- one dead shade of grey
local function depth(parent, lightness)
	return make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(
			Color3.new(1, 1, 1),
			Color3.fromRGB(255 * (1 - lightness), 255 * (1 - lightness), 255 * (1 - lightness))
		),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - lightness),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = parent,
	})
end

local function textWidth(text, font, size)
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(1000, 100))
	end)
	return ok and v.X or (#text * size * 0.5)
end

--// Library root --------------------------------------------------------------
local Aurora = {
	_accentObjects = {},
	_flags = {},
	_flagSetters = {},
	_windows = {},
	Theme = Theme,
}

function Aurora:_bindAccent(obj, prop)
	table.insert(self._accentObjects, { obj = obj, prop = prop })
	obj[prop] = Theme.Accent
end

function Aurora:SetAccent(color)
	Theme.Accent = color
	for _, entry in ipairs(self._accentObjects) do
		if entry.obj and entry.obj.Parent then
			tween(entry.obj, { [entry.prop] = color })
		end
	end
end

function Aurora:GetConfig()
	return self._flags
end

--// Config: save / load -------------------------------------------------------
local CONFIG_FOLDER = "AuroraUI"

local function ensureFolder()
	if not hasFiles then return false end
	pcall(function()
		if isfolder and not isfolder(CONFIG_FOLDER) and makefolder then
			makefolder(CONFIG_FOLDER)
		end
	end)
	return true
end

local function encode(tbl)
	local ok, s = pcall(function() return game:GetService("HttpService"):JSONEncode(tbl) end)
	return ok and s or nil
end

local function decode(s)
	local ok, t = pcall(function() return game:GetService("HttpService"):JSONDecode(s) end)
	return ok and t or nil
end

function Aurora:SaveConfig(name)
	if not ensureFolder() then
		self:Notify({ Title = "Config", Text = "File API unavailable", Duration = 3 })
		return false
	end
	local path = CONFIG_FOLDER .. "/" .. (name or "default") .. ".json"
	local data = encode(self._flags)
	if data then
		pcall(writefile, path, data)
		self:Notify({ Title = "Config", Text = "Saved '" .. (name or "default") .. "'", Duration = 3 })
		return true
	end
	return false
end

function Aurora:LoadConfig(name)
	if not hasFiles then return false end
	local path = CONFIG_FOLDER .. "/" .. (name or "default") .. ".json"
	if not isfile(path) then
		self:Notify({ Title = "Config", Text = "No config '" .. (name or "default") .. "'", Duration = 3 })
		return false
	end
	local data = decode(readfile(path))
	if not data then return false end
	for flag, value in pairs(data) do
		local setter = self._flagSetters[flag]
		if setter then setter(value) else self._flags[flag] = value end
	end
	self:Notify({ Title = "Config", Text = "Loaded '" .. (name or "default") .. "'", Duration = 3 })
	return true
end

--// Root ScreenGui ------------------------------------------------------------
local ScreenGui = make("ScreenGui", {
	Name = "AuroraUI_" .. tostring(math.random(1000, 9999)),
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
})
protect(ScreenGui)
ScreenGui.Parent = getParentGui()
Aurora._screen = ScreenGui

--// Notifications -------------------------------------------------------------
local notifyHolder = make("Frame", {
	Name = "Notifications",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 300, 1, -32),
	BackgroundTransparency = 1,
	Parent = ScreenGui,
})
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, SPACE.sm),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = notifyHolder,
})

function Aurora:Notify(cfg)
	cfg = cfg or {}
	local title, body, dur = cfg.Title or "Notice", cfg.Text or "", cfg.Duration or 4

	local card = make("Frame", {
		BackgroundColor3 = Theme.Panel,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})
	corner(card, RADIUS.md)
	local st = stroke(card, Theme.Border, 1, 1)
	pad(card, SPACE.md)
	make("UIListLayout", { Padding = UDim.new(0, SPACE.xs), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
	make("UIPadding", { PaddingLeft = UDim.new(0, SPACE.md + 6), PaddingTop = UDim.new(0, SPACE.md),
		PaddingBottom = UDim.new(0, SPACE.md), PaddingRight = UDim.new(0, SPACE.md), Parent = card })

	local accentBar = make("Frame", {
		Size = UDim2.new(0, 3, 1, -8), Position = UDim2.new(0, 6, 0, 4),
		BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = card,
	})
	corner(accentBar, RADIUS.sm)
	Aurora:_bindAccent(accentBar, "BackgroundColor3")

	make("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
		Font = FONT_BOLD, Text = title, TextColor3 = Theme.Text, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, LayoutOrder = 1, Parent = card,
	})
	if body ~= "" then
		make("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, Font = FONT, Text = body,
			TextColor3 = Theme.TextDim, TextSize = 12, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, LayoutOrder = 2, Parent = card,
		})
	end

	card.Parent = notifyHolder
	tween(card, { BackgroundTransparency = 0 })
	tween(st, { Transparency = 0 })
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextLabel") then tween(d, { TextTransparency = 0 }) end
	end

	task.delay(dur, function()
		if not card.Parent then return end
		tween(card, { BackgroundTransparency = 1 })
		tween(st, { Transparency = 1 })
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then tween(d, { TextTransparency = 1 }) end
		end
		task.wait(0.2)
		card:Destroy()
	end)
end

local function safeCall(fn, ...)
	if typeof(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then
		Aurora:Notify({ Title = "Callback error", Text = tostring(err), Duration = 5 })
	end
end

--============================================================================--
--  WINDOW
--============================================================================--
local CHROME_H  = 32
local SIDEBAR_W = 190
local TAB_H     = 34
local TAB_GAP   = 4

function Aurora:CreateWindow(cfg)
	cfg = cfg or {}
	local title      = cfg.Title or "Aurora"
	local subtitle   = cfg.SubTitle or ""
	local toggleKey  = cfg.ToggleKey or Enum.KeyCode.RightShift

	local connections = {}
	local function track(conn) table.insert(connections, conn); return conn end

	local root = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 640, 0, 420),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = ScreenGui,
	})
	corner(root, RADIUS.lg)
	stroke(root, Theme.Border, 1)

	-- soft outer glow so the window doesn't sit flat against the game world
	local glow = make("ImageLabel", {
		Image = "rbxassetid://6015897843",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.4,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 4),
		Size = UDim2.new(1, 40, 1, 44),
		BackgroundTransparency = 1,
		ZIndex = -1,
		Parent = root,
	})
	glow.Parent = root

	-- Chrome: thin draggable strip, controls top-right -------------------
	local chrome = make("Frame", {
		Name = "Chrome",
		Size = UDim2.new(1, 0, 0, CHROME_H),
		BackgroundColor3 = Theme.Chrome,
		BorderSizePixel = 0,
		Parent = root,
	})
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Theme.BorderSoft, BorderSizePixel = 0, Parent = chrome,
	})

	local controls = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 84, 0, 22),
		BackgroundTransparency = 1,
		Parent = chrome,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, SPACE.xs + 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = controls,
	})

	local function ctrlButton(symbol, order, size)
		local b = make("TextButton", {
			Size = UDim2.new(0, size or 22, 0, size or 22),
			BackgroundColor3 = Theme.Element,
			Text = symbol, Font = FONT_BOLD, TextColor3 = Theme.TextDim, TextSize = 12,
			AutoButtonColor = false, LayoutOrder = order, Parent = controls,
		})
		corner(b, RADIUS.sm)
		track(b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = Theme.ElementHover, TextColor3 = Theme.Text }) end))
		track(b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.TextDim }) end))
		return b
	end

	local accentBtn = ctrlButton("", 1, 22)
	local accentDot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 9, 0, 9), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = accentBtn,
	})
	corner(accentDot, RADIUS.sm)
	Aurora:_bindAccent(accentDot, "BackgroundColor3")

	local palette = {
		Color3.fromRGB(151, 105, 255), Color3.fromRGB(78, 145, 255),
		Color3.fromRGB(64, 200, 145), Color3.fromRGB(235, 96, 96),
		Color3.fromRGB(255, 158, 68), Color3.fromRGB(255, 105, 180),
	}
	local paletteIdx = 1
	track(accentBtn.MouseButton1Click:Connect(function()
		paletteIdx = (paletteIdx % #palette) + 1
		Aurora:SetAccent(palette[paletteIdx])
	end))

	local minBtn   = ctrlButton("–", 2, 22)
	local closeBtn = ctrlButton("✕", 3, 22)

	-- Body: sidebar + content ---------------------------------------------
	local body = make("Frame", {
		Name = "Body",
		Position = UDim2.new(0, 0, 0, CHROME_H),
		Size = UDim2.new(1, 0, 1, -CHROME_H),
		BackgroundTransparency = 1,
		Parent = root,
	})

	local sidebar = make("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_W, 1, 0),
		BackgroundColor3 = Theme.Sidebar,
		BorderSizePixel = 0,
		Parent = body,
	})
	depth(sidebar, 0.05)
	make("Frame", {
		Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0),
		BackgroundColor3 = Theme.BorderSoft, BorderSizePixel = 0, Parent = sidebar,
	})

	-- brand block
	local brand = make("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	local mark = make("Frame", {
		Position = UDim2.new(0, SPACE.md, 0, 14),
		Size = UDim2.new(0, 24, 0, 24),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = brand,
	})
	corner(mark, RADIUS.sm)
	Aurora:_bindAccent(mark, "BackgroundColor3")
	make("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(0, 0, 0)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = mark,
	})
	make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, SPACE.md + 32, 0, 12),
		Size = UDim2.new(1, -(SPACE.md * 2 + 32), 0, 16),
		Font = FONT_BOLD, Text = title, TextColor3 = Theme.Text, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = brand,
	})
	if subtitle ~= "" then
		make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, SPACE.md + 32, 0, 28),
			Size = UDim2.new(1, -(SPACE.md * 2 + 32), 0, 14),
			Font = FONT, Text = subtitle, TextColor3 = Theme.TextDim, TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = brand,
		})
	end
	make("Frame", {
		Position = UDim2.new(0, SPACE.md, 0, 51), Size = UDim2.new(1, -SPACE.md * 2, 0, 1),
		BackgroundColor3 = Theme.BorderSoft, BorderSizePixel = 0, Parent = sidebar,
	})

	-- tab list
	local tabList = make("Frame", {
		Name = "TabList",
		Position = UDim2.new(0, 0, 0, 60),
		Size = UDim2.new(1, 0, 1, -68),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, TAB_GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabList,
	})
	make("UIPadding", {
		PaddingLeft = UDim.new(0, SPACE.sm), PaddingRight = UDim.new(0, SPACE.sm),
		PaddingTop = UDim.new(0, SPACE.xs), Parent = tabList,
	})

	-- sliding accent indicator, position computed analytically per tab index
	local indicator = make("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, 3, 0, 18),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Visible = false,
		Parent = sidebar,
	})
	corner(indicator, RADIUS.sm)
	Aurora:_bindAccent(indicator, "BackgroundColor3")

	local function indicatorY(index)
		-- tabList top offset (60) + list top padding (SPACE.xs) + n full tab
		-- rows above it, centred on the (index)th row
		return 60 + SPACE.xs + (index - 1) * (TAB_H + TAB_GAP) + TAB_H / 2
	end

	-- Content ---------------------------------------------------------------
	local content = make("Frame", {
		Name = "Content",
		Position = UDim2.new(0, SIDEBAR_W, 0, 0),
		Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
		BackgroundTransparency = 1,
		Parent = body,
	})

	local Window = { _tabs = {}, _active = nil, _root = root }

	-- Dragging (chrome strip) ---------------------------------------------
	do
		local dragging, dragStart, startPos
		track(chrome.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging, dragStart, startPos = true, input.Position, root.Position
				local changedConn
				changedConn = input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
						changedConn:Disconnect()
					end
				end)
			end
		end))
		track(UserInputService.InputChanged:Connect(function(input)
			if not root.Parent then return end
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - dragStart
				root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end))
	end

	-- Minimize / close ------------------------------------------------------
	local minimized = false
	local savedSize = root.Size
	track(minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		if minimized then
			savedSize = root.Size
			tween(root, { Size = UDim2.new(savedSize.X.Scale, savedSize.X.Offset, 0, CHROME_H) })
		else
			tween(root, { Size = savedSize })
		end
	end))
	track(closeBtn.MouseButton1Click:Connect(function()
		local t = tween(root, { Size = UDim2.new(0, savedSize.X.Offset, 0, 0) })
		local function finish()
			for _, c in ipairs(connections) do
				pcall(function() c:Disconnect() end)
			end
			ScreenGui:Destroy()
		end
		if t then t.Completed:Connect(finish) else finish() end
	end))

	-- Toggle visibility keybind ---------------------------------------------
	track(UserInputService.InputBegan:Connect(function(input, gpe)
		if not root.Parent then return end
		if gpe then return end
		if input.KeyCode == toggleKey then
			root.Visible = not root.Visible
		end
	end))

	local function activateTab(tab)
		if Window._active == tab then return end
		if Window._active then
			Window._active._page.Visible = false
			tween(Window._active._item, { BackgroundColor3 = Theme.Sidebar })
			tween(Window._active._label, { TextColor3 = Theme.TextDim })
			if Window._active._iconLabel then tween(Window._active._iconLabel, { TextColor3 = Theme.TextDim }) end
		end
		Window._active = tab
		tab._page.Visible = true
		tween(tab._item, { BackgroundColor3 = Theme.SidebarAlt })
		tween(tab._label, { TextColor3 = Theme.Text })
		if tab._iconLabel then tween(tab._iconLabel, { TextColor3 = Theme.Accent }) end
		indicator.Visible = true
		tween(indicator, { Position = UDim2.new(0, 0, 0, indicatorY(tab._index)) })
	end

	--== CreateTab =========================================================--
	function Window:CreateTab(tabCfg)
		tabCfg = tabCfg or {}
		local name = tabCfg.Name or ("Tab " .. (#self._tabs + 1))
		local icon = tabCfg.Icon or ""
		local index = #self._tabs + 1

		local item = make("TextButton", {
			Size = UDim2.new(1, 0, 0, TAB_H),
			BackgroundColor3 = Theme.Sidebar,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = index,
			Parent = tabList,
		})
		corner(item, RADIUS.sm)

		local iconLabel
		local labelX = SPACE.sm + 6
		if icon ~= "" then
			iconLabel = make("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, SPACE.sm, 0, 0),
				Size = UDim2.new(0, 18, 1, 0),
				Font = FONT_MED, Text = icon, TextColor3 = Theme.TextDim, TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = item,
			})
			labelX = SPACE.sm + 22
		end
		local label = make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, labelX, 0, 0),
			Size = UDim2.new(1, -(labelX + SPACE.sm), 1, 0),
			Font = FONT_MED, Text = name, TextColor3 = Theme.TextDim, TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = item,
		})

		local page = make("ScrollingFrame", {
			Name = name,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Border,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y,
			Visible = false,
			Parent = content,
		})
		pad(page, SPACE.lg)
		make("UIListLayout", { Padding = UDim.new(0, SPACE.md), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })

		local Tab = { _page = page, _item = item, _label = label, _iconLabel = iconLabel, _index = index, _sections = 0 }

		track(item.MouseButton1Click:Connect(function() activateTab(Tab) end))
		track(item.MouseEnter:Connect(function()
			if Window._active ~= Tab then tween(item, { BackgroundColor3 = Theme.ElementHover }) end
		end))
		track(item.MouseLeave:Connect(function()
			if Window._active ~= Tab then tween(item, { BackgroundColor3 = Theme.Sidebar }) end
		end))

		--== CreateSection ==================================================--
		function Tab:CreateSection(secName)
			local holder = make("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Theme.Panel,
				BorderSizePixel = 0,
				LayoutOrder = self._sections + 1,
				Parent = page,
			})
			self._sections = self._sections + 1
			corner(holder, RADIUS.md)
			stroke(holder, Theme.Border, 1)
			depth(holder, 0.03)
			pad(holder, SPACE.md)
			make("UIListLayout", { Padding = UDim.new(0, SPACE.sm), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })

			if secName then
				make("TextLabel", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
					Font = FONT_BOLD, Text = secName, TextColor3 = Theme.Text, TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, Parent = holder,
				})
			end

			local Section = { _holder = holder, _order = 1 }

			local function row(height)
				local r = make("Frame", {
					Size = UDim2.new(1, 0, 0, height or 36),
					BackgroundColor3 = Theme.Element,
					BorderSizePixel = 0,
					LayoutOrder = Section._order,
					Parent = holder,
				})
				Section._order = Section._order + 1
				corner(r, RADIUS.sm)
				return r
			end

			local function rowLabel(parent, text)
				return make("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, SPACE.md, 0, 0),
					Size = UDim2.new(1, -100, 1, 0),
					Font = FONT, Text = text, TextColor3 = Theme.Text, TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
				})
			end

			--== Toggle =======================================================--
			function Section:AddToggle(c)
				c = c or {}
				local state = c.Default and true or false
				local r = row(36)
				rowLabel(r, c.Name or "Toggle")

				local track_ = make("Frame", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -SPACE.md, 0.5, 0),
					Size = UDim2.new(0, 38, 0, 20), BackgroundColor3 = Theme.Background,
					BorderSizePixel = 0, Parent = r,
				})
				corner(track_, RADIUS.lg)
				local knob = make("Frame", {
					AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0),
					Size = UDim2.new(0, 16, 0, 16), BackgroundColor3 = Theme.TextDim,
					BorderSizePixel = 0, Parent = track_,
				})
				corner(knob, RADIUS.lg)

				local btn = make("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", Parent = r })

				local function render(animated)
					local info = animated and TWEEN or TweenInfo.new(0)
					if state then
						tween(track_, { BackgroundColor3 = Theme.Accent }, info)
						tween(knob, { Position = UDim2.new(1, -18, 0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255) }, info)
					else
						tween(track_, { BackgroundColor3 = Theme.Background }, info)
						tween(knob, { Position = UDim2.new(0, 2, 0.5, 0), BackgroundColor3 = Theme.TextDim }, info)
					end
				end

				local function set(v, fire)
					state = v and true or false
					if c.Flag then Aurora._flags[c.Flag] = state end
					render(true)
					if fire ~= false then safeCall(c.Callback, state) end
				end

				track(btn.MouseButton1Click:Connect(function() set(not state) end))
				render(false)
				if c.Flag then
					Aurora._flags[c.Flag] = state
					Aurora._flagSetters[c.Flag] = function(v) set(v, true) end
				end
				return { Set = function(_, v) set(v) end, Get = function() return state end }
			end

			--== Button =======================================================--
			function Section:AddButton(c)
				c = c or {}
				local r = row(36)
				local btn = make("TextButton", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
					Font = FONT, Text = c.Name or "Button", TextColor3 = Theme.Text, TextSize = 13,
					AutoButtonColor = false, Parent = r,
				})
				local pad_ = make("UIPadding", { PaddingLeft = UDim.new(0, SPACE.md), Parent = btn })
				make("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -SPACE.md, 0.5, 0),
					Size = UDim2.new(0, 12, 1, 0), BackgroundTransparency = 1,
					Font = FONT_BOLD, Text = "›", TextColor3 = Theme.TextDim, TextSize = 16, Parent = r,
				})
				track(btn.MouseEnter:Connect(function() tween(r, { BackgroundColor3 = Theme.ElementHover }) end))
				track(btn.MouseLeave:Connect(function() tween(r, { BackgroundColor3 = Theme.Element }) end))
				track(btn.MouseButton1Click:Connect(function()
					tween(r, { BackgroundColor3 = Theme.Accent }, TweenInfo.new(0.08))
					task.delay(0.12, function()
						if r.Parent then tween(r, { BackgroundColor3 = Theme.ElementHover }) end
					end)
					safeCall(c.Callback)
				end))
				return { Fire = function() safeCall(c.Callback) end }
			end

			--== Slider =======================================================--
			function Section:AddSlider(c)
				c = c or {}
				local min, max, decimals = c.Min or 0, c.Max or 100, c.Decimals or 0
				local value = math.clamp(c.Default or min, min, max)

				local r = row(48)
				make("TextLabel", {
					BackgroundTransparency = 1, Position = UDim2.new(0, SPACE.md, 0, 6),
					Size = UDim2.new(1, -SPACE.md * 2, 0, 16), Font = FONT, Text = c.Name or "Slider",
					TextColor3 = Theme.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = r,
				})
				local valueLabel = make("TextLabel", {
					BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -SPACE.md, 0, 6), Size = UDim2.new(0, 60, 0, 16),
					Font = FONT_BOLD, Text = tostring(value), TextColor3 = Theme.TextDim, TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right, Parent = r,
				})

				local bar = make("Frame", {
					Position = UDim2.new(0, SPACE.md, 1, -16), Size = UDim2.new(1, -SPACE.md * 2, 0, 6),
					BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Parent = r,
				})
				corner(bar, RADIUS.sm)
				local fill = make("Frame", {
					Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
					BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = bar,
				})
				corner(fill, RADIUS.sm)
				Aurora:_bindAccent(fill, "BackgroundColor3")

				local function round(v)
					local m = 10 ^ decimals
					return math.floor(v * m + 0.5) / m
				end

				local function set(v, fire)
					value = math.clamp(round(v), min, max)
					local a = (value - min) / (max - min)
					tween(fill, { Size = UDim2.new(a, 0, 1, 0) }, TweenInfo.new(0.06))
					valueLabel.Text = tostring(value) .. (c.Suffix or "")
					if c.Flag then Aurora._flags[c.Flag] = value end
					if fire ~= false then safeCall(c.Callback, value) end
				end

				local dragging = false
				local function update(inputX)
					local a = math.clamp((inputX - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
					set(min + a * (max - min))
				end
				track(bar.InputBegan:Connect(function(i)
					if i.UserInputType == Enum.UserInputType.MouseButton1 then
						dragging = true
						update(i.Position.X)
					end
				end))
				track(UserInputService.InputChanged:Connect(function(i)
					if not bar.Parent then return end
					if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then update(i.Position.X) end
				end))
				track(UserInputService.InputEnded:Connect(function(i)
					if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
				end))

				set(value, false)
				if c.Flag then Aurora._flagSetters[c.Flag] = function(v) set(v, true) end end
				return { Set = function(_, v) set(v) end, Get = function() return value end }
			end

			--== Dropdown =====================================================--
			function Section:AddDropdown(c)
				c = c or {}
				local options = c.Options or {}
				local multi = c.Multi and true or false
				local selected = multi and {} or (c.Default or nil)
				if multi and c.Default then
					for _, v in ipairs(c.Default) do selected[v] = true end
				end

				local r = row(36)
				rowLabel(r, c.Name or "Dropdown")
				local valueLabel = make("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -30, 0.5, 0),
					Size = UDim2.new(0, 120, 1, 0), BackgroundTransparency = 1, Font = FONT,
					Text = "—", TextColor3 = Theme.TextDim, TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Parent = r,
				})
				local arrow = make("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -SPACE.md, 0.5, 0),
					Size = UDim2.new(0, 12, 1, 0), BackgroundTransparency = 1, Font = FONT_BOLD,
					Text = "▾", TextColor3 = Theme.TextDim, TextSize = 12, Parent = r,
				})

				local listHolder = make("Frame", {
					Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Theme.Background, BorderSizePixel = 0, Visible = false,
					LayoutOrder = Section._order, Parent = holder,
				})
				Section._order = Section._order + 1
				corner(listHolder, RADIUS.sm)
				pad(listHolder, SPACE.xs)
				make("UIListLayout", { Padding = UDim.new(0, SPACE.xs / 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = listHolder })

				local function summary()
					if multi then
						local t = {}
						for _, opt in ipairs(options) do
							if selected[opt] then table.insert(t, opt) end
						end
						return #t > 0 and table.concat(t, ", ") or "—"
					end
					return selected or "—"
				end

				local function refreshLabel()
					valueLabel.Text = summary()
					if c.Flag then Aurora._flags[c.Flag] = selected end
				end

				local optButtons = {}
				local function rebuild()
					for _, b in ipairs(optButtons) do b:Destroy() end
					optButtons = {}
					for i, opt in ipairs(options) do
						local ob = make("TextButton", {
							Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.Element,
							Text = opt, Font = FONT, TextColor3 = Theme.TextDim, TextSize = 12,
							AutoButtonColor = false, LayoutOrder = i, Parent = listHolder,
						})
						corner(ob, RADIUS.sm)
						local function paint()
							local on = multi and selected[opt] or (selected == opt)
							ob.TextColor3 = on and Theme.Text or Theme.TextDim
						end
						track(ob.MouseButton1Click:Connect(function()
							if multi then
								selected[opt] = not selected[opt] and true or nil
							else
								selected = opt
							end
							refreshLabel()
							for _, b in ipairs(optButtons) do
								local on = multi and selected[b.Text] or (selected == b.Text)
								b.TextColor3 = on and Theme.Text or Theme.TextDim
							end
							safeCall(c.Callback, selected)
						end))
						paint()
						table.insert(optButtons, ob)
					end
				end
				rebuild()

				local open = false
				local btn = make("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", Parent = r })
				track(btn.MouseButton1Click:Connect(function()
					open = not open
					listHolder.Visible = open
					tween(arrow, { Rotation = open and 180 or 0 })
				end))

				refreshLabel()
				if c.Flag then
					Aurora._flagSetters[c.Flag] = function(v)
						selected = v
						refreshLabel()
						rebuild()
					end
				end
				return {
					Set = function(_, v) selected = v; refreshLabel(); rebuild() end,
					Get = function() return selected end,
					Refresh = function(_, newOpts) options = newOpts; rebuild() end,
				}
			end

			--== Textbox ======================================================--
			function Section:AddTextbox(c)
				c = c or {}
				local r = row(36)
				rowLabel(r, c.Name or "Input")
				local boxBg = make("Frame", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -SPACE.md, 0.5, 0),
					Size = UDim2.new(0, 120, 0, 24), BackgroundColor3 = Theme.Background,
					BorderSizePixel = 0, Parent = r,
				})
				corner(boxBg, RADIUS.sm)
				local box = make("TextBox", {
					BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0),
					Font = FONT, PlaceholderText = c.Placeholder or "…", PlaceholderColor3 = Theme.TextDim,
					Text = c.Default or "", TextColor3 = Theme.Text, TextSize = 12,
					ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = boxBg,
				})
				track(box.FocusLost:Connect(function(enter)
					if c.Flag then Aurora._flags[c.Flag] = box.Text end
					safeCall(c.Callback, box.Text, enter)
				end))
				if c.Flag then
					Aurora._flags[c.Flag] = box.Text
					Aurora._flagSetters[c.Flag] = function(v) box.Text = tostring(v) end
				end
				return { Set = function(_, v) box.Text = tostring(v) end, Get = function() return box.Text end }
			end

			--== Keybind ======================================================--
			function Section:AddKeybind(c)
				c = c or {}
				local key = c.Default
				local r = row(36)
				rowLabel(r, c.Name or "Keybind")
				local kbBtn = make("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -SPACE.md, 0.5, 0),
					Size = UDim2.new(0, 80, 0, 24), BackgroundColor3 = Theme.Background,
					Font = FONT, Text = key and key.Name or "None", TextColor3 = Theme.TextDim, TextSize = 12,
					AutoButtonColor = false, Parent = r,
				})
				corner(kbBtn, RADIUS.sm)

				local listening = false
				track(kbBtn.MouseButton1Click:Connect(function()
					listening = true
					kbBtn.Text = "…"
					tween(kbBtn, { TextColor3 = Theme.Accent })
				end))
				track(UserInputService.InputBegan:Connect(function(input, gpe)
					if not kbBtn.Parent then return end
					if listening and input.UserInputType == Enum.UserInputType.Keyboard then
						listening = false
						key = input.KeyCode
						kbBtn.Text = key.Name
						tween(kbBtn, { TextColor3 = Theme.TextDim })
						if c.Flag then Aurora._flags[c.Flag] = key.Name end
					elseif not gpe and key and input.KeyCode == key then
						safeCall(c.Callback, key)
					end
				end))
				return {
					Set = function(_, k) key = k; kbBtn.Text = k and k.Name or "None" end,
					Get = function() return key end,
				}
			end

			--== Label ========================================================--
			function Section:AddLabel(text)
				return make("TextLabel", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18),
					Font = FONT, Text = text or "", TextColor3 = Theme.TextDim, TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
					AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = Section._order, Parent = holder,
				})
			end

			--== Paragraph ====================================================--
			function Section:AddParagraph(c)
				c = c or {}
				local box = make("Frame", {
					Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Theme.Element, BorderSizePixel = 0,
					LayoutOrder = Section._order, Parent = holder,
				})
				Section._order = Section._order + 1
				corner(box, RADIUS.sm)
				pad(box, SPACE.sm + 2)
				make("UIListLayout", { Padding = UDim.new(0, SPACE.xs), Parent = box })
				make("TextLabel", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
					Font = FONT_BOLD, Text = c.Title or "Title", TextColor3 = Theme.Text, TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left, Parent = box,
				})
				make("TextLabel", {
					BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y, Font = FONT, Text = c.Text or "",
					TextColor3 = Theme.TextDim, TextSize = 12, TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left, Parent = box,
				})
				return box
			end

			return Section
		end

		table.insert(self._tabs, Tab)
		if #self._tabs == 1 then
			task.defer(function() activateTab(Tab) end)
		end
		return Tab
	end

	table.insert(Aurora._windows, Window)
	return Window
end

return Aurora
