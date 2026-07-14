--[[
	Aurora UI  —  a minimal-dark Luau UI library for Roblox executors
	Top tab-bar layout · full component set · draggable · keybind toggle
	notifications · config save/load · runtime accent picker

	Usage:
		local Aurora = loadstring(game:HttpGet("<raw-url>/AuroraUI.luau"))()
		local Window = Aurora:CreateWindow({ Title = "vertex", SubTitle = "discord.gg/vxt" })
		local Tab    = Window:CreateTab({ Name = "Main", Icon = "" })
		local Sec    = Tab:CreateSection("General")
		Sec:AddToggle({ Name = "Auto Farm", Flag = "autofarm", Default = false,
			Callback = function(v) print(v) end })

	This library only builds UI. It contains no game logic.
--]]

--// Services -----------------------------------------------------------------
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local TextService       = game:GetService("TextService")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--// Executor compatibility ----------------------------------------------------
local function getParentGui()
	-- Prefer a hidden, protected container; fall back gracefully.
	local ok, hidden = pcall(function()
		return gethui and gethui()
	end)
	if ok and hidden then
		return hidden
	end
	local ok2, cg = pcall(function()
		return CoreGui
	end)
	if ok2 and cg then
		return cg
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function protect(gui)
	-- Try common protection APIs; ignore if unsupported.
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		elseif protect_gui then
			protect_gui(gui)
		end
	end)
end

-- File API feature-detection (config system degrades if missing).
local hasFiles = (typeof(writefile) == "function")
	and (typeof(readfile) == "function")
	and (typeof(isfile) == "function")

--// Theme ---------------------------------------------------------------------
local Theme = {
	Background = Color3.fromRGB(13, 13, 15),
	Panel      = Color3.fromRGB(21, 21, 23),
	Element    = Color3.fromRGB(26, 26, 29),
	ElementHover = Color3.fromRGB(32, 32, 36),
	Border     = Color3.fromRGB(31, 31, 35),
	Text       = Color3.fromRGB(232, 232, 234),
	TextDim    = Color3.fromRGB(110, 110, 118),
	Accent     = Color3.fromRGB(138, 92, 246),
}

local TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FONT  = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

--// Small helpers -------------------------------------------------------------
local function apply(obj, props)
	-- Set properties directly, each guarded so one unsupported property can
	-- never halt construction of the rest of the UI.
	for k, v in pairs(props) do
		local ok, err = pcall(function() obj[k] = v end)
		if not ok then
			warn("[AuroraUI] could not set " .. tostring(k) .. ": " .. tostring(err))
		end
	end
end

local function tween(obj, props, info)
	info = info or TWEEN
	local ok, t = pcall(function()
		return TweenService:Create(obj, info, props)
	end)
	if ok and t and pcall(function() t:Play() end) then
		return t
	end
	apply(obj, props) -- fallback: apply instantly if tweening fails
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
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent -- parent last so children exist before layout runs
	end
	return inst
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

local function stroke(parent, color, thickness)
	return make("UIStroke", {
		Color = color or Theme.Border,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function pad(parent, all)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
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
	_accentObjects = {},   -- { {obj=, prop=} } — updated when accent changes
	_flags = {},           -- flag -> value  (config)
	_windows = {},
	Theme = Theme,
}

-- Register an object property that should follow the accent colour.
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
	local ok, s = pcall(function()
		return game:GetService("HttpService"):JSONEncode(tbl)
	end)
	return ok and s or nil
end

local function decode(s)
	local ok, t = pcall(function()
		return game:GetService("HttpService"):JSONDecode(s)
	end)
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
		local setter = self._flagSetters and self._flagSetters[flag]
		if setter then
			setter(value)   -- updates element + fires callback
		else
			self._flags[flag] = value
		end
	end
	self:Notify({ Title = "Config", Text = "Loaded '" .. (name or "default") .. "'", Duration = 3 })
	return true
end

Aurora._flagSetters = {}   -- flag -> function(value) that updates the live element

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
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = notifyHolder,
})

function Aurora:Notify(cfg)
	cfg = cfg or {}
	local title = cfg.Title or "Notice"
	local body  = cfg.Text or ""
	local dur   = cfg.Duration or 4

	local card = make("Frame", {
		BackgroundColor3 = Theme.Panel,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})
	corner(card, 8)
	local st = stroke(card, Theme.Border, 1)
	st.Transparency = 1
	pad(card, 12)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

	local accentBar = make("Frame", {
		Size = UDim2.new(0, 3, 1, -8),
		Position = UDim2.new(0, 0, 0, 4),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = card,
	})
	corner(accentBar, 2)
	Aurora:_bindAccent(accentBar, "BackgroundColor3")

	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Font = FONT_BOLD,
		Text = title,
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		LayoutOrder = 1,
		Parent = card,
	})
	if body ~= "" then
		make("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = FONT,
			Text = body,
			TextColor3 = Theme.TextDim,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = 1,
			LayoutOrder = 2,
			Parent = card,
		})
	end

	card.Parent = notifyHolder

	-- fade in
	tween(card, { BackgroundTransparency = 0 })
	tween(st, { Transparency = 0 })
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("TextLabel") then
			tween(d, { TextTransparency = 0 })
		end
	end

	task.delay(dur, function()
		tween(card, { BackgroundTransparency = 1 })
		tween(st, { Transparency = 1 })
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, { TextTransparency = 1 })
			end
		end
		task.wait(0.2)
		card:Destroy()
	end)
end

--// safe callback -------------------------------------------------------------
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
function Aurora:CreateWindow(cfg)
	cfg = cfg or {}
	local title    = cfg.Title or "Aurora"
	local subtitle = cfg.SubTitle or ""
	local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift

	local root = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 600, 0, 440),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = ScreenGui,
	})
	corner(root, 10)
	stroke(root, Theme.Border, 1)

	-- Topbar --------------------------------------------------------------
	local topbar = make("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Parent = root,
	})
	make("Frame", {  -- bottom hairline
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		Parent = topbar,
	})

	local titleLabel = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 0),
		Size = UDim2.new(0, 200, 1, 0),
		Font = FONT_BOLD,
		Text = title,
		TextColor3 = Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = topbar,
	})
	if subtitle ~= "" then
		titleLabel.Size = UDim2.new(0, 200, 0, 20)
		titleLabel.Position = UDim2.new(0, 16, 0, 4)
		make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 16, 0, 22),
			Size = UDim2.new(0, 200, 0, 14),
			Font = FONT,
			Text = subtitle,
			TextColor3 = Theme.TextDim,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = topbar,
		})
	end

	-- control buttons (right)
	local controls = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 80, 0, 24),
		BackgroundTransparency = 1,
		Parent = topbar,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = controls,
	})

	local function ctrlButton(symbol, order)
		local b = make("TextButton", {
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundColor3 = Theme.Element,
			Text = symbol,
			Font = FONT_BOLD,
			TextColor3 = Theme.TextDim,
			TextSize = 14,
			AutoButtonColor = false,
			LayoutOrder = order,
			Parent = controls,
		})
		corner(b, 6)
		b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = Theme.ElementHover, TextColor3 = Theme.Text }) end)
		b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.TextDim }) end)
		return b
	end

	-- Accent quick-picker
	local accentBtn = ctrlButton("", 1)
	local accentDot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 10, 0, 10),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = accentBtn,
	})
	corner(accentDot, 5)
	Aurora:_bindAccent(accentDot, "BackgroundColor3")

	local palette = { Color3.fromRGB(138,92,246), Color3.fromRGB(59,130,246),
		Color3.fromRGB(34,197,94), Color3.fromRGB(239,68,68),
		Color3.fromRGB(249,115,22), Color3.fromRGB(236,72,153) }
	local paletteIdx = 1
	accentBtn.MouseButton1Click:Connect(function()
		paletteIdx = (paletteIdx % #palette) + 1
		Aurora:SetAccent(palette[paletteIdx])
	end)

	local minBtn = ctrlButton("–", 2)
	local closeBtn = ctrlButton("✕", 3)

	-- Tab strip (its own row below the topbar) ---------------------------
	local tabStrip = make("Frame", {
		Name = "TabStrip",
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Parent = root,
	})
	make("Frame", {  -- bottom hairline
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		Parent = tabStrip,
	})

	local tabBar = make("Frame", {
		Name = "TabBar",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = tabStrip,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = tabBar })

	-- sliding underline indicator (lives in the strip, not the tabBar, so
	-- the tabBar's UIPadding doesn't shift it)
	local indicator = make("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = tabStrip,
	})
	corner(indicator, 2)
	Aurora:_bindAccent(indicator, "BackgroundColor3")

	-- Content holder ------------------------------------------------------
	local content = make("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 0, 0, 84),
		Size = UDim2.new(1, 0, 1, -84),
		BackgroundTransparency = 1,
		Parent = root,
	})

	-- Window object -------------------------------------------------------
	local Window = { _tabs = {}, _active = nil, _root = root }

	-- Dragging (topbar) ---------------------------------------------------
	do
		local dragging, dragStart, startPos
		topbar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				dragStart = input.Position
				startPos = root.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - dragStart
				root.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
	end

	-- Minimize / close ----------------------------------------------------
	local minimized = false
	local savedSize = root.Size
	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		if minimized then
			savedSize = root.Size
			tween(root, { Size = UDim2.new(savedSize.X.Scale, savedSize.X.Offset, 0, 44) })
		else
			tween(root, { Size = savedSize })
		end
	end)
	closeBtn.MouseButton1Click:Connect(function()
		tween(root, { Size = UDim2.new(0, savedSize.X.Offset, 0, 0) }).Completed:Connect(function()
			ScreenGui:Destroy()
		end)
	end)

	-- Toggle visibility keybind ------------------------------------------
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == toggleKey then
			root.Visible = not root.Visible
		end
	end)

	-- move the indicator under a given tab button
	local function moveIndicator(btn)
		-- Layout may not be resolved yet on the first activation; wait a frame
		-- until the button has a real size before measuring.
		if btn.AbsoluteSize.X == 0 then
			RunService.RenderStepped:Wait()
		end
		-- position relative to the tab strip (indicator's parent)
		local relX = btn.AbsolutePosition.X - tabStrip.AbsolutePosition.X
		tween(indicator, {
			Position = UDim2.new(0, relX, 1, 0),
			Size = UDim2.new(0, btn.AbsoluteSize.X, 0, 2),
		})
	end

	--== CreateTab =======================================================--
	function Window:CreateTab(tabCfg)
		tabCfg = tabCfg or {}
		local name = tabCfg.Name or ("Tab " .. (#self._tabs + 1))
		local icon = tabCfg.Icon or ""

		local labelText = (icon ~= "" and (icon .. "  ") or "") .. name
		local w = textWidth(labelText, FONT, 14) + 24

		local tabBtn = make("TextButton", {
			Size = UDim2.new(0, w, 1, 0),
			BackgroundTransparency = 1,
			Text = labelText,
			Font = FONT,
			TextColor3 = Theme.TextDim,
			TextSize = 14,
			AutoButtonColor = false,
			LayoutOrder = #self._tabs + 1,
			Parent = tabBar,
		})

		-- page (scrolling content)
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
		pad(page, 14)
		make("UIListLayout", {
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = page,
		})

		local Tab = { _page = page, _btn = tabBtn, _sections = 0 }

		local function activate()
			if Window._active == Tab then return end
			if Window._active then
				Window._active._page.Visible = false
				tween(Window._active._btn, { TextColor3 = Theme.TextDim })
			end
			Window._active = Tab
			page.Visible = true
			tween(tabBtn, { TextColor3 = Theme.Text })
			moveIndicator(tabBtn)
		end

		tabBtn.MouseButton1Click:Connect(activate)
		tabBtn.MouseEnter:Connect(function()
			if Window._active ~= Tab then
				tween(tabBtn, { TextColor3 = Theme.Text })
			end
		end)
		tabBtn.MouseLeave:Connect(function()
			if Window._active ~= Tab then
				tween(tabBtn, { TextColor3 = Theme.TextDim })
			end
		end)

		--== CreateSection ==============================================--
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
			corner(holder, 8)
			stroke(holder, Theme.Border, 1)
			pad(holder, 12)
			make("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = holder,
			})

			if secName then
				make("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 16),
					Font = FONT_BOLD,
					Text = secName,
					TextColor3 = Theme.Text,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 0,
					Parent = holder,
				})
			end

			local Section = { _holder = holder, _order = 1 }

			-- shared row builder
			local function row(height)
				local r = make("Frame", {
					Size = UDim2.new(1, 0, 0, height or 36),
					BackgroundColor3 = Theme.Element,
					BorderSizePixel = 0,
					LayoutOrder = Section._order,
					Parent = holder,
				})
				Section._order = Section._order + 1
				corner(r, 6)
				return r
			end

			local function rowLabel(parent, text)
				return make("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 12, 0, 0),
					Size = UDim2.new(1, -100, 1, 0),
					Font = FONT,
					Text = text,
					TextColor3 = Theme.Text,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = parent,
				})
			end

			--== Toggle ==============================================--
			function Section:AddToggle(c)
				c = c or {}
				local state = c.Default and true or false
				local r = row(36)
				rowLabel(r, c.Name or "Toggle")

				local track = make("Frame", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 40, 0, 20),
					BackgroundColor3 = Theme.Background,
					BorderSizePixel = 0,
					Parent = r,
				})
				corner(track, 10)
				local knob = make("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 2, 0.5, 0),
					Size = UDim2.new(0, 16, 0, 16),
					BackgroundColor3 = Theme.TextDim,
					BorderSizePixel = 0,
					Parent = track,
				})
				corner(knob, 8)

				local btn = make("TextButton", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Text = "",
					Parent = r,
				})

				local function render(animated)
					local info = animated and TWEEN or TweenInfo.new(0)
					if state then
						tween(track, { BackgroundColor3 = Theme.Accent }, info)
						tween(knob, { Position = UDim2.new(1, -18, 0.5, 0), BackgroundColor3 = Color3.fromRGB(255,255,255) }, info)
					else
						tween(track, { BackgroundColor3 = Theme.Background }, info)
						tween(knob, { Position = UDim2.new(0, 2, 0.5, 0), BackgroundColor3 = Theme.TextDim }, info)
					end
				end

				local function set(v, fire)
					state = v and true or false
					if c.Flag then Aurora._flags[c.Flag] = state end
					render(true)
					if fire ~= false then safeCall(c.Callback, state) end
				end

				btn.MouseButton1Click:Connect(function() set(not state) end)
				render(false)
				if c.Flag then
					Aurora._flags[c.Flag] = state
					Aurora._flagSetters[c.Flag] = function(v) set(v, true) end
				end

				return { Set = function(_, v) set(v) end, Get = function() return state end }
			end

			--== Button ==============================================--
			function Section:AddButton(c)
				c = c or {}
				local r = row(36)
				local btn = make("TextButton", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Font = FONT,
					Text = c.Name or "Button",
					TextColor3 = Theme.Text,
					TextSize = 13,
					AutoButtonColor = false,
					Parent = r,
				})
				make("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 12, 1, 0),
					BackgroundTransparency = 1,
					Font = FONT_BOLD,
					Text = "›",
					TextColor3 = Theme.TextDim,
					TextSize = 16,
					Parent = r,
				})
				btn.MouseEnter:Connect(function() tween(r, { BackgroundColor3 = Theme.ElementHover }) end)
				btn.MouseLeave:Connect(function() tween(r, { BackgroundColor3 = Theme.Element }) end)
				btn.MouseButton1Click:Connect(function()
					tween(r, { BackgroundColor3 = Theme.Accent }, TweenInfo.new(0.08))
					task.delay(0.12, function() tween(r, { BackgroundColor3 = Theme.ElementHover }) end)
					safeCall(c.Callback)
				end)
				return { Fire = function() safeCall(c.Callback) end }
			end

			--== Slider ==============================================--
			function Section:AddSlider(c)
				c = c or {}
				local min = c.Min or 0
				local max = c.Max or 100
				local decimals = c.Decimals or 0
				local value = math.clamp(c.Default or min, min, max)

				local r = row(48)
				make("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 12, 0, 6),
					Size = UDim2.new(1, -24, 0, 16),
					Font = FONT,
					Text = c.Name or "Slider",
					TextColor3 = Theme.Text,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = r,
				})
				local valueLabel = make("TextLabel", {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 6),
					Size = UDim2.new(0, 60, 0, 16),
					Font = FONT_BOLD,
					Text = tostring(value),
					TextColor3 = Theme.TextDim,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = r,
				})

				local bar = make("Frame", {
					Position = UDim2.new(0, 12, 1, -16),
					Size = UDim2.new(1, -24, 0, 6),
					BackgroundColor3 = Theme.Background,
					BorderSizePixel = 0,
					Parent = r,
				})
				corner(bar, 3)
				local fill = make("Frame", {
					Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
					BackgroundColor3 = Theme.Accent,
					BorderSizePixel = 0,
					Parent = bar,
				})
				corner(fill, 3)
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
				bar.InputBegan:Connect(function(i)
					if i.UserInputType == Enum.UserInputType.MouseButton1 then
						dragging = true
						update(i.Position.X)
					end
				end)
				UserInputService.InputChanged:Connect(function(i)
					if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
						update(i.Position.X)
					end
				end)
				UserInputService.InputEnded:Connect(function(i)
					if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
				end)

				set(value, false)
				if c.Flag then
					Aurora._flagSetters[c.Flag] = function(v) set(v, true) end
				end
				return { Set = function(_, v) set(v) end, Get = function() return value end }
			end

			--== Dropdown ============================================--
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
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -30, 0.5, 0),
					Size = UDim2.new(0, 120, 1, 0),
					BackgroundTransparency = 1,
					Font = FONT,
					Text = "—",
					TextColor3 = Theme.TextDim,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = r,
				})
				local arrow = make("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 12, 1, 0),
					BackgroundTransparency = 1,
					Font = FONT_BOLD,
					Text = "▾",
					TextColor3 = Theme.TextDim,
					TextSize = 12,
					Parent = r,
				})

				local listHolder = make("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Theme.Background,
					BorderSizePixel = 0,
					Visible = false,
					LayoutOrder = Section._order,
					Parent = holder,
				})
				Section._order = Section._order + 1
				corner(listHolder, 6)
				pad(listHolder, 4)
				make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = listHolder })

				local function summary()
					if multi then
						local t = {}
						for _, opt in ipairs(options) do
							if selected[opt] then table.insert(t, opt) end
						end
						return #t > 0 and table.concat(t, ", ") or "—"
					else
						return selected or "—"
					end
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
							Size = UDim2.new(1, 0, 0, 28),
							BackgroundColor3 = Theme.Element,
							Text = opt,
							Font = FONT,
							TextColor3 = Theme.TextDim,
							TextSize = 12,
							AutoButtonColor = false,
							LayoutOrder = i,
							Parent = listHolder,
						})
						corner(ob, 4)
						local function paint()
							local on = multi and selected[opt] or (selected == opt)
							tween(ob, { TextColor3 = on and Theme.Text or Theme.TextDim })
						end
						ob.MouseButton1Click:Connect(function()
							if multi then
								selected[opt] = not selected[opt] and true or nil
							else
								selected = opt
							end
							refreshLabel()
							for _, b in ipairs(optButtons) do
								local o = b.Text
								local on = multi and selected[o] or (selected == o)
								b.TextColor3 = on and Theme.Text or Theme.TextDim
							end
							if not multi then safeCall(c.Callback, selected) end
							if multi then safeCall(c.Callback, selected) end
						end)
						paint()
						table.insert(optButtons, ob)
					end
				end
				rebuild()

				local open = false
				local btn = make("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "", Parent = r })
				btn.MouseButton1Click:Connect(function()
					open = not open
					listHolder.Visible = open
					tween(arrow, { Rotation = open and 180 or 0 })
				end)

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

			--== Textbox =============================================--
			function Section:AddTextbox(c)
				c = c or {}
				local r = row(36)
				rowLabel(r, c.Name or "Input")
				local boxBg = make("Frame", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 120, 0, 24),
					BackgroundColor3 = Theme.Background,
					BorderSizePixel = 0,
					Parent = r,
				})
				corner(boxBg, 6)
				local box = make("TextBox", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -16, 1, 0),
					Position = UDim2.new(0, 8, 0, 0),
					Font = FONT,
					PlaceholderText = c.Placeholder or "…",
					PlaceholderColor3 = Theme.TextDim,
					Text = c.Default or "",
					TextColor3 = Theme.Text,
					TextSize = 12,
					ClearTextOnFocus = false,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = boxBg,
				})
				box.FocusLost:Connect(function(enter)
					if c.Flag then Aurora._flags[c.Flag] = box.Text end
					safeCall(c.Callback, box.Text, enter)
				end)
				if c.Flag then
					Aurora._flags[c.Flag] = box.Text
					Aurora._flagSetters[c.Flag] = function(v) box.Text = tostring(v) end
				end
				return { Set = function(_, v) box.Text = tostring(v) end, Get = function() return box.Text end }
			end

			--== Keybind =============================================--
			function Section:AddKeybind(c)
				c = c or {}
				local key = c.Default
				local r = row(36)
				rowLabel(r, c.Name or "Keybind")
				local kbBtn = make("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 80, 0, 24),
					BackgroundColor3 = Theme.Background,
					Font = FONT,
					Text = key and key.Name or "None",
					TextColor3 = Theme.TextDim,
					TextSize = 12,
					AutoButtonColor = false,
					Parent = r,
				})
				corner(kbBtn, 6)

				local listening = false
				kbBtn.MouseButton1Click:Connect(function()
					listening = true
					kbBtn.Text = "…"
					tween(kbBtn, { TextColor3 = Theme.Accent })
				end)
				UserInputService.InputBegan:Connect(function(input, gpe)
					if listening and input.UserInputType == Enum.UserInputType.Keyboard then
						listening = false
						key = input.KeyCode
						kbBtn.Text = key.Name
						tween(kbBtn, { TextColor3 = Theme.TextDim })
						if c.Flag then Aurora._flags[c.Flag] = key.Name end
					elseif not gpe and key and input.KeyCode == key then
						safeCall(c.Callback, key)
					end
				end)
				return { Set = function(_, k) key = k; kbBtn.Text = k and k.Name or "None" end, Get = function() return key end }
			end

			--== Label ===============================================--
			function Section:AddLabel(text)
				return make("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 18),
					Font = FONT,
					Text = text or "",
					TextColor3 = Theme.TextDim,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = Section._order,
					Parent = holder,
				})
			end

			--== Paragraph ===========================================--
			function Section:AddParagraph(c)
				c = c or {}
				local box = make("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Theme.Element,
					BorderSizePixel = 0,
					LayoutOrder = Section._order,
					Parent = holder,
				})
				Section._order = Section._order + 1
				corner(box, 6)
				pad(box, 10)
				make("UIListLayout", { Padding = UDim.new(0, 4), Parent = box })
				make("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 16),
					Font = FONT_BOLD,
					Text = c.Title or "Title",
					TextColor3 = Theme.Text,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = box,
				})
				make("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Font = FONT,
					Text = c.Text or "",
					TextColor3 = Theme.TextDim,
					TextSize = 12,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = box,
				})
				return box
			end

			return Section
		end

		table.insert(self._tabs, Tab)
		-- activate first tab automatically
		if #self._tabs == 1 then
			task.defer(activate)
		end
		return Tab
	end

	table.insert(Aurora._windows, Window)
	return Window
end

return Aurora
