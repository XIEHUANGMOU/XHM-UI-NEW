local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LOCAL_PLAYER = Players.LocalPlayer
local Util = {}
function Util.create(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
function Util.corner(inst, radius)
	return Util.create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = inst })
end
function Util.stroke(inst, color, thickness, transparency)
	return Util.create("UIStroke", {
		Color = color or Color3.fromRGB(60, 60, 72),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end
local SHADOW_SUPPORT = nil
local shadowWarned = false
local function shadowSupported()
	if SHADOW_SUPPORT == nil then
		SHADOW_SUPPORT = pcall(function()
			local probe = Instance.new("UIShadow")
			probe:Destroy()
		end)
		if not SHADOW_SUPPORT and not shadowWarned then
			shadowWarned = true
			warn("[XHM] 当前客户端没有 UIShadow（Roblox 2026 起才支持），已跳过投影")
		end
	end
	return SHADOW_SUPPORT
end
function Util.shadow(target, opts)
	opts = opts or {}
	if opts.Enabled == false or not target or not shadowSupported() then
		return nil
	end
	local spread = opts.Spread or 0
	local ok, shadow = pcall(function()
		return Util.create("UIShadow", {
			Name = "Shadow",
			Color = opts.Color or Color3.new(0, 0, 0),
			Transparency = opts.Transparency or 0.45,
			BlurRadius = UDim.new(0, opts.Blur or 16),
			Offset = UDim2.fromOffset(0, opts.Drop or 6),
			Spread = UDim2.fromOffset(spread, spread),
			Enabled = true,
			Parent = target,
		})
	end)
	if not ok then
		warn("[XHM] 投影创建失败，已跳过: " .. tostring(shadow))
		return nil
	end
	return shadow
end
function Util.shadowTwin(target, parent, opts, connections)
	opts = opts or {}
	local twin = Util.create("Frame", {
		Name = "ShadowTwin",
		AnchorPoint = target.AnchorPoint,
		Position = target.Position,
		Size = target.Size,
		BackgroundTransparency = 1,
		ZIndex = math.max(0, (target.ZIndex or 1) - 1),
		Parent = parent,
	})
	Util.corner(twin, opts.Radius or 10)
	local function sync()
		local size = target.AbsoluteSize
		twin.Position = target.Position
		twin.Size = UDim2.fromOffset(size.X, size.Y)
		twin.Visible = target.Visible
	end
	sync()
	task.delay(0, function()
		pcall(sync)
	end)
	if connections then
		table.insert(connections, target:GetPropertyChangedSignal("Position"):Connect(sync))
		table.insert(connections, target:GetPropertyChangedSignal("Size"):Connect(sync))
		table.insert(connections, target:GetPropertyChangedSignal("Visible"):Connect(sync))
		table.insert(connections, target:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync))
		if opts.Scale then
			table.insert(connections, opts.Scale:GetPropertyChangedSignal("Scale"):Connect(sync))
		end
	end
	return twin, Util.shadow(twin, opts)
end
local FONT_FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local FONT_WEIGHTS = {
	Regular = Enum.FontWeight.Regular,
	Medium = Enum.FontWeight.Medium,
	SemiBold = Enum.FontWeight.SemiBold,
	Bold = Enum.FontWeight.Bold,
}
local FONT_FALLBACK = {
	Regular = Enum.Font.Gotham,
	Medium = Enum.Font.GothamMedium,
	SemiBold = Enum.Font.GothamSemibold,
	Bold = Enum.Font.GothamBold,
}
function Util.font(obj, weight)
	weight = weight or "Regular"
	local ok = pcall(function()
		obj.FontFace = Font.new(FONT_FAMILY, FONT_WEIGHTS[weight] or Enum.FontWeight.Regular)
	end)
	if not ok then
		obj.Font = FONT_FALLBACK[weight] or Enum.Font.Gotham
	end
	return obj
end
function Util.tween(inst, duration, props, style, direction)
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end
function Util.set(inst, props)
	for k, v in pairs(props) do
		inst[k] = v
	end
end
function Util.round(value, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(value * mult + 0.5) / mult
end
function Util.httpGet(url)
	local requestFn = (syn and syn.request) or (http and http.request) or http_request or request
	if requestFn then
		local ok, res = pcall(requestFn, { Url = url, Method = "GET" })
		if ok and type(res) == "table" and res.Body then
			return res.Body
		end
	end
	local ok2, body = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok2 and type(body) == "string" then
		return body
	end
	local ok3, body3 = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if ok3 and type(body3) == "string" then
		return body3
	end
	error("[XHM] 无法请求地址: " .. tostring(url))
end
Util.FS = (function()
	local writeFn = writefile or (syn and syn.write_file) or (fluxus and fluxus.write_file)
	local readFn = readfile or (syn and syn.read_file) or (fluxus and fluxus.read_file)
	local existsFn = isfile or (syn and syn.is_file)
	local mkdirFn = makefolder or (syn and syn.make_folder)
	if not (writeFn and readFn) then
		return nil
	end
	return {
		write = writeFn,
		read = readFn,
		exists = existsFn,
		mkdir = mkdirFn,
	}
end)()
Util.CustomAssets = {}
local function shortHash(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + str:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end
local function getAssetConverter()
	return getcustomasset or getsynasset or (syn and syn.get_custom_asset)
end
local function isNativeAsset(url)
	return url:match("^rbxasset") ~= nil
		or url:match("^rbxthumb") ~= nil
		or url:match("^rbxassetid") ~= nil
end
local ASSET_EXTENSIONS = {
	png = true, jpg = true, jpeg = true, webp = true, tga = true, bmp = true, gif = true,
	ogg = true, mp3 = true, wav = true, flac = true,
}
function Util.isExternalAsset(source)
	if type(source) ~= "string" or source == "" then
		return false
	end
	if isNativeAsset(source) or source:match("^https?://") then
		return true
	end
	local ext = source:match("%.([%w]+)$")
	return ext ~= nil and ASSET_EXTENSIONS[ext:lower()] == true
end
function Util.customAsset(source, cacheKey)
	if type(source) ~= "string" or source == "" then
		return nil
	end
	if isNativeAsset(source) then
		return source
	end
	local key = cacheKey or source
	local cached = Util.CustomAssets[key]
	if cached ~= nil then
		return cached or nil
	end
	local converter = getAssetConverter()
	local writeFn = (Util.FS and Util.FS.write) or writefile
	if not source:match("^https?://") then
		if not converter then
			warn("[XHM] 当前执行器不支持 getcustomasset，无法加载本地图片: " .. source)
			Util.CustomAssets[key] = false
			return nil
		end
		local ok, asset = pcall(converter, source)
		if ok and type(asset) == "string" then
			Util.CustomAssets[key] = asset
			return asset
		end
		warn("[XHM] 本地图片转换失败: " .. source .. " -> " .. tostring(asset))
		Util.CustomAssets[key] = false
		return nil
	end
	if not (converter and writeFn) then
		warn("[XHM] 当前环境无法加载网络图片（需要执行器的 writefile + getcustomasset）: " .. source)
		Util.CustomAssets[key] = false
		return nil
	end
	local ok, asset = pcall(function()
		local body = Util.httpGet(source)
		if type(body) ~= "string" or #body == 0 then
			error("下载结果为空")
		end
		local ext = source:match("%.([%w]+)$")
		if not ext then
			local pathOnly = source:match("^[^?#]*") or source
			ext = pathOnly:match("%.([%w]+)$")
		end
		if not ext or #ext > 4 then
			ext = "png"
		end
		local fileName = "XHM_" .. shortHash(key) .. "." .. ext
		writeFn(fileName, body)
		return converter(fileName)
	end)
	if not ok or type(asset) ~= "string" then
		warn("[XHM] 图片加载失败: " .. source .. " -> " .. tostring(asset))
		Util.CustomAssets[key] = false
		return nil
	end
	Util.CustomAssets[key] = asset
	return asset
end
function Util.preloadAsset(source, cacheKey)
	return Util.customAsset(source, cacheKey)
end
function Util.safeParent(gui)
	local ok = pcall(function()
		if gethui then
			gui.Parent = gethui()
		else
			gui.Parent = game:GetService("CoreGui")
		end
	end)
	if not ok then
		local ok2 = pcall(function()
			gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui", 10)
		end)
		if not ok2 then
			warn("[XHM] 无法挂载 GUI，请检查执行器权限")
		end
	end
end
local Icons = {}
Icons.__index = Icons
Icons.Version = "1.0.0"
local GLYPHS = {
	["house"] = "⌂", ["home"] = "⌂", ["settings"] = "⚙", ["search"] = "⌕",
	["user"] = "👤", ["users"] = "👥", ["menu"] = "☰", ["list"] = "☰",
	["chevron-down"] = "⌄", ["chevron-up"] = "⌃", ["chevron-right"] = "›", ["chevron-left"] = "‹",
	["x"] = "✕", ["check"] = "✓", ["plus"] = "＋", ["minus"] = "－",
	["more-vertical"] = "⋮", ["dot"] = "•", ["circle"] = "●", ["square"] = "■", ["triangle"] = "▲",
	["trash"] = "🗑", ["pencil"] = "✎", ["edit"] = "✎", ["copy"] = "⧉", ["save"] = "💾",
	["download"] = "⬇", ["upload"] = "⬆", ["link"] = "🔗", ["external-link"] = "↗",
	["play"] = "▶", ["pause"] = "⏸", ["stop"] = "⏹", ["refresh"] = "⟳", ["power"] = "⏻",
	["maximize"] = "⛶", ["minimize"] = "—", ["wand"] = "🪄", ["filter"] = "⧩",
	["shield"] = "🛡", ["lock"] = "🔒", ["unlock"] = "🔓", ["key"] = "🔑",
	["eye"] = "👁", ["eye-off"] = "🙈", ["zap"] = "⚡", ["star"] = "★", ["heart"] = "♥",
	["bell"] = "🔔", ["flag"] = "⚑", ["info"] = "ⓘ", ["alert"] = "⚠",
	["circle-check"] = "✔", ["circle-x"] = "✖", ["circle-alert"] = "⚠", ["bug"] = "🐛",
	["palette"] = "🎨", ["image"] = "🖼", ["file"] = "📄", ["folder"] = "📁",
	["terminal"] = "⌨", ["code"] = "⟨⟩", ["box"] = "📦", ["gift"] = "🎁",
	["globe"] = "🌐", ["wifi"] = "📶", ["cpu"] = "🖥", ["activity"] = "📈",
	["sliders"] = "🎚", ["gauge"] = "⏱", ["clock"] = "🕐", ["target"] = "🎯",
	["crosshair"] = "⊕", ["map-pin"] = "📍", ["layout"] = "▤", ["layers"] = "▤",
	["sparkles"] = "✦", ["rocket"] = "🚀", ["sun"] = "☀", ["moon"] = "🌙",
	["gamepad"] = "🎮", ["volume"] = "🔊", ["camera"] = "📷", ["music"] = "🎵",
	["arrow-right"] = "→", ["arrow-left"] = "←", ["arrow-up"] = "↑", ["arrow-down"] = "↓",
}
local LUCIDE_ICONS = {
	["activity"] = { 16898612629, 48, 48, 514, 771 },
	["alert"] = { 16898613869, 48, 48, 967, 0 },
	["arrow-down"] = { 16898612629, 48, 48, 967, 49 },
	["arrow-left"] = { 16898612629, 48, 48, 98, 918 },
	["arrow-right"] = { 16898612629, 48, 48, 453, 820 },
	["arrow-up"] = { 16898612629, 48, 48, 967, 355 },
	["bell"] = { 16898612819, 48, 48, 820, 257 },
	["box"] = { 16898612819, 48, 48, 771, 196 },
	["bug"] = { 16898612819, 48, 48, 257, 967 },
	["camera"] = { 16898612819, 48, 48, 967, 563 },
	["check"] = { 16898612819, 48, 48, 710, 869 },
	["chevron-down"] = { 16898612819, 48, 48, 196, 918 },
	["chevron-left"] = { 16898612819, 48, 48, 404, 967 },
	["chevron-right"] = { 16898612819, 48, 48, 869, 759 },
	["chevron-up"] = { 16898612819, 48, 48, 710, 918 },
	["circle"] = { 16898613044, 48, 48, 771, 355 },
	["circle-alert"] = { 16898612819, 48, 48, 918, 808 },
	["circle-check"] = { 16898612819, 48, 48, 869, 955 },
	["circle-x"] = { 16898613044, 48, 48, 820, 306 },
	["clock"] = { 16898613044, 48, 48, 771, 661 },
	["code"] = { 16898613044, 48, 48, 355, 869 },
	["copy"] = { 16898613044, 48, 48, 918, 612 },
	["cpu"] = { 16898613044, 48, 48, 196, 869 },
	["crosshair"] = { 16898613044, 48, 48, 453, 869 },
	["dot"] = { 16898613044, 48, 48, 918, 808 },
	["download"] = { 16898613044, 48, 48, 820, 906 },
	["edit"] = { 16898613699, 48, 48, 820, 257 },
	["external-link"] = { 16898613353, 48, 48, 257, 820 },
	["eye"] = { 16898613353, 48, 48, 771, 563 },
	["eye-off"] = { 16898613353, 48, 48, 820, 514 },
	["file"] = { 16898613353, 48, 48, 820, 661 },
	["filter"] = { 16898613353, 48, 48, 612, 869 },
	["flag"] = { 16898613353, 48, 48, 98, 918 },
	["folder"] = { 16898613353, 48, 48, 404, 967 },
	["gamepad"] = { 16898613353, 48, 48, 967, 759 },
	["gauge"] = { 16898613353, 48, 48, 771, 955 },
	["gift"] = { 16898613353, 48, 48, 820, 955 },
	["globe"] = { 16898613509, 48, 48, 771, 563 },
	["heart"] = { 16898613509, 48, 48, 661, 771 },
	["home"] = { 16898613509, 48, 48, 820, 147 },
	["house"] = { 16898613509, 48, 48, 820, 147 },
	["image"] = { 16898613509, 48, 48, 306, 918 },
	["info"] = { 16898613509, 48, 48, 612, 869 },
	["key"] = { 16898613509, 48, 48, 869, 404 },
	["layers"] = { 16898613509, 48, 48, 98, 967 },
	["layout"] = { 16898613509, 48, 48, 967, 612 },
	["link"] = { 16898613509, 48, 48, 918, 453 },
	["list"] = { 16898613509, 48, 48, 869, 808 },
	["lock"] = { 16898613509, 48, 48, 918, 857 },
	["map-pin"] = { 16898613613, 48, 48, 820, 257 },
	["maximize"] = { 16898613613, 48, 48, 771, 563 },
	["menu"] = { 16898613613, 48, 48, 49, 820 },
	["minimize"] = { 16898613613, 48, 48, 918, 49 },
	["minus"] = { 16898613613, 48, 48, 771, 196 },
	["moon"] = { 16898613613, 48, 48, 306, 918 },
	["more-vertical"] = { 16898613613, 48, 48, 967, 514 },
	["music"] = { 16898613613, 48, 48, 967, 563 },
	["palette"] = { 16898613613, 48, 48, 453, 918 },
	["pause"] = { 16898613699, 48, 48, 0, 771 },
	["pencil"] = { 16898613699, 48, 48, 820, 257 },
	["play"] = { 16898613699, 48, 48, 918, 257 },
	["plus"] = { 16898613699, 48, 48, 257, 918 },
	["power"] = { 16898613699, 48, 48, 820, 147 },
	["refresh"] = { 16898613699, 48, 48, 404, 869 },
	["rocket"] = { 16898613699, 48, 48, 918, 147 },
	["save"] = { 16898613699, 48, 48, 918, 453 },
	["search"] = { 16898613699, 48, 48, 918, 857 },
	["settings"] = { 16898613777, 48, 48, 771, 257 },
	["shield"] = { 16898613777, 48, 48, 869, 0 },
	["sliders"] = { 16898613777, 48, 48, 404, 771 },
	["sparkles"] = { 16898613777, 48, 48, 918, 49 },
	["square"] = { 16898613777, 48, 48, 869, 710 },
	["star"] = { 16898613777, 48, 48, 967, 147 },
	["stop"] = { 16898613777, 48, 48, 869, 710 },
	["sun"] = { 16898613777, 48, 48, 967, 453 },
	["target"] = { 16898613869, 48, 48, 514, 771 },
	["terminal"] = { 16898613869, 48, 48, 820, 257 },
	["trash"] = { 16898613869, 48, 48, 918, 514 },
	["triangle"] = { 16898613869, 48, 48, 869, 98 },
	["unlock"] = { 16898613869, 48, 48, 771, 710 },
	["upload"] = { 16898613869, 48, 48, 612, 869 },
	["user"] = { 16898613869, 48, 48, 661, 869 },
	["users"] = { 16898613869, 48, 48, 967, 98 },
	["volume"] = { 16898613869, 48, 48, 661, 918 },
	["wand"] = { 16898613869, 48, 48, 404, 967 },
	["wifi"] = { 16898613869, 48, 48, 869, 808 },
	["x"] = { 16898613869, 48, 48, 869, 906 },
	["zap"] = { 16898613869, 48, 48, 918, 906 },
}
local Overrides = {}
local Sheet = nil
local Assets = {}
local Rects = {}
function Icons.resolve(name)
	if Overrides[name] then
		return Overrides[name]
	end
	if Sheet and Sheet.icons[name] then
		local cell = Sheet.icons[name]
		return {
			kind = "sheet",
			image = Sheet.image,
			offset = Vector2.new(cell.x * Sheet.cell.X, cell.y * Sheet.cell.Y),
			size = Sheet.cell,
		}
	end
	if Assets[name] then
		return { kind = "asset", image = Assets[name] }
	end
	if Rects[name] then
		local r = Rects[name]
		return {
			kind = "sheet",
			image = "rbxassetid://" .. r[1],
			offset = Vector2.new(r[4], r[5]),
			size = Vector2.new(r[2], r[3]),
		}
	end
	return { kind = "glyph", text = GLYPHS[name] or GLYPHS["dot"] or "•" }
end
local rawResolve = Icons.resolve
function Icons.resolve(name)
	if type(name) == "string" and Util.isExternalAsset(name) then
		local asset = Util.customAsset(name)
		if asset then
			return { kind = "asset", image = asset }
		end
		return { kind = "glyph", text = GLYPHS["alert"] or "!" }
	end
	return rawResolve(name)
end
function Icons.set(name, source)
	if type(source) == "table" then
		Overrides[name] = source
	elseif type(source) == "string" and Util.isExternalAsset(source) then
		local asset = Util.customAsset(source)
		if not asset then
			Overrides[name] = { kind = "glyph", text = GLYPHS["alert"] or "!" }
			Icons.refresh()
			return false
		end
		Overrides[name] = { kind = "asset", image = asset }
	else
		Overrides[name] = { kind = "glyph", text = tostring(source) }
	end
	Icons.refresh()
	return true
end
function Icons.setGlyphs(tbl)
	for k, v in pairs(tbl or {}) do
		if not GLYPHS[k] then
			GLYPHS[k] = v
		end
	end
	Icons.refresh()
end
function Icons.loadAssets(source, opts)
	opts = opts or {}
	local data = source
	if type(source) == "string" then
		local text = source
		if source:match("^https?://") then
			text = Util.httpGet(source)
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
		if not ok then
			error("[XHM] loadAssets 解析失败：" .. tostring(decoded))
		end
		data = decoded
	end
	data = data.icons or data
	local count = 0
	for name, id in pairs(data) do
		if type(id) == "string" or type(id) == "number" then
			Assets[name] = type(id) == "number" and ("rbxassetid://" .. id) or id
			count += 1
		elseif type(id) == "table" and id.id then
			Assets[name] = "rbxassetid://" .. tostring(id.id)
			count += 1
		end
	end
	Icons.refresh()
	return count
end
function Icons.loadSheet(source, opts)
	opts = opts or {}
	local data = source
	if type(source) == "string" then
		local text = source
		if source:match("^https?://") then
			text = Util.httpGet(source)
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
		if not ok then
			error("[XHM] loadSheet 解析失败：" .. tostring(decoded))
		end
		data = decoded
	end
	local image = opts.image or data.image or data.Image
	if not image then
		error("[XHM] loadSheet 缺少 image 字段")
	end
	if type(image) == "number" then
		image = "rbxassetid://" .. image
	end
	local cellRaw = opts.cell or data.cell or data.cellSize or { 64, 64 }
	local cell = Vector2.new(cellRaw[1] or cellRaw.X or 64, cellRaw[2] or cellRaw.Y or 64)
	local columns = opts.columns or data.columns or math.floor(2048 / cell.X)
	local icons = {}
	for name, entry in pairs(data.icons or data.Icons or {}) do
		if type(entry) == "number" then
			icons[name] = { x = entry % columns, y = math.floor(entry / columns) }
		elseif type(entry) == "table" then
			if entry.x and entry.y then
				icons[name] = { x = entry.x, y = entry.y }
			elseif entry.index then
				icons[name] = { x = entry.index % columns, y = math.floor(entry.index / columns) }
			end
		end
	end
	Sheet = { image = image, cell = cell, columns = columns, icons = icons }
	Icons.refresh()
	return Sheet
end
function Icons.loadRects(data, opts)
	opts = opts or {}
	local count = 0
	for name, entry in pairs(data or {}) do
		if type(entry) == "table" and type(entry[1]) == "number" and type(entry[4]) == "number" then
			Rects[name] = entry
			count += 1
		end
	end
	if opts.replace then
		for name in pairs(Rects) do
			if data[name] == nil then
				Rects[name] = nil
			end
		end
	end
	Icons.refresh()
	return count
end
function Icons.loadUrl(name, source)
	local asset = Util.customAsset(source)
	if not asset then
		return false
	end
	Overrides[name] = { kind = "asset", image = asset }
	Icons.refresh()
	return true
end
function Icons.useLucide(enabled)
	if enabled == false then
		for name in pairs(LUCIDE_ICONS) do
			Rects[name] = nil
		end
	else
		for name, entry in pairs(LUCIDE_ICONS) do
			Rects[name] = entry
		end
	end
	Icons.refresh()
	return enabled ~= false
end
function Icons.lucideEnabled()
	return next(Rects) ~= nil
end
function Icons.reset()
	Assets = {}
	Sheet = nil
	Overrides = {}
	Rects = {}
	Icons.refresh()
end
function Icons.has(name)
	return Overrides[name] ~= nil
		or Assets[name] ~= nil
		or Rects[name] ~= nil
		or (Sheet and Sheet.icons[name] ~= nil)
end
function Icons.list()
	local set = {}
	for name in pairs(GLYPHS) do
		set[name] = true
	end
	for name in pairs(Assets) do
		set[name] = true
	end
	for name in pairs(Overrides) do
		set[name] = true
	end
	for name in pairs(Rects) do
		set[name] = true
	end
	if Sheet then
		for name in pairs(Sheet.icons) do
			set[name] = true
		end
	end
	local out = {}
	for name in pairs(set) do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end
local LiveIcons = setmetatable({}, { __mode = "v" })
local function untrackIcon(icon)
	for i = #LiveIcons, 1, -1 do
		if LiveIcons[i] == icon then
			table.remove(LiveIcons, i)
			return
		end
	end
end
function Icons.refresh()
	for _, icon in ipairs(LiveIcons) do
		pcall(function()
			icon:render()
		end)
	end
end
Icons.useLucide(true)
local IconObject = {}
IconObject.__index = IconObject
local ICON_FONT_MAX = 60
function IconObject:render()
	local holder = self.Instance
	local res = Icons.resolve(self.Name)
	self._kind = res.kind
	for _, child in ipairs(holder:GetChildren()) do
		child:Destroy()
	end
	if res.kind == "glyph" then
		local label = Util.create("TextLabel", {
			Name = "Glyph",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = res.text,
			TextColor3 = self._color,
			TextTransparency = self._transparency,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			RichText = false,
			Parent = holder,
		})
		Util.create("UITextSizeConstraint", {
			MaxTextSize = ICON_FONT_MAX,
			MinTextSize = 6,
			Parent = label,
		})
		Util.font(label, "Regular")
		self._label = label
	else
		local image = Util.create("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = res.image,
			ImageColor3 = self._color,
			ImageTransparency = self._transparency,
			ScaleType = Enum.ScaleType.Fit,
			Parent = holder,
		})
		if res.kind == "sheet" then
			image.ImageRectOffset = res.offset
			image.ImageRectSize = res.size
		end
		self._image = image
	end
	if self._rotation ~= 0 then
		holder.Rotation = self._rotation
	end
end
function IconObject:set(name)
	self.Name = name
	self:render()
	return self
end
function IconObject:setColor(color)
	self._color = color
	if self._label then
		self._label.TextColor3 = color
	elseif self._image then
		self._image.ImageColor3 = color
	end
	return self
end
function IconObject:setTransparency(t)
	self._transparency = t
	if self._label then
		self._label.TextTransparency = t
	elseif self._image then
		self._image.ImageTransparency = t
	end
	return self
end
function IconObject:setSize(size)
	self.Instance.Size = size
	return self
end
function IconObject:setRotation(deg)
	self._rotation = deg
	self.Instance.Rotation = deg
	return self
end
function IconObject:setVisible(visible)
	self.Instance.Visible = visible
	return self
end
function IconObject:destroy()
	untrackIcon(self)
	self.Instance:Destroy()
end
function IconObject:raw()
	return self.Instance
end
function Icons.new(parent, name, props)
	props = props or {}
	local holder = Util.create("Frame", {
		Name = "Icon_" .. tostring(name),
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(16, 16),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Visible = props.Visible ~= false,
		ZIndex = props.ZIndex or 1,
		Parent = parent,
	})
	local obj = setmetatable({
		Instance = holder,
		Name = name,
		_color = props.Color or Color3.fromRGB(240, 240, 245),
		_transparency = props.Transparency or 0,
		_rotation = props.Rotation or 0,
	}, IconObject)
	obj:render()
	table.insert(LiveIcons, obj)
	return obj
end
Icons.Object = IconObject
local Theme = {
	Accent = Color3.fromRGB(99, 102, 241),
	AccentHover = Color3.fromRGB(129, 132, 255),
	Background = Color3.fromRGB(16, 16, 20),
	Surface = Color3.fromRGB(24, 24, 30),
	SurfaceAlt = Color3.fromRGB(32, 32, 40),
	SurfaceHover = Color3.fromRGB(42, 42, 52),
	Stroke = Color3.fromRGB(52, 52, 64),
	StrokeLight = Color3.fromRGB(70, 70, 86),
	Text = Color3.fromRGB(238, 238, 245),
	SubText = Color3.fromRGB(146, 146, 162),
	Muted = Color3.fromRGB(96, 96, 112),
	Success = Color3.fromRGB(52, 199, 123),
	Warning = Color3.fromRGB(240, 178, 50),
	Error = Color3.fromRGB(240, 82, 82),
	Radius = 8,
	TitleHeight = 36,
	RailWidth = 152,
	ElemHeight = 34,
	RowHeight = 32,
	Anim = 0.16,
	AnimSlow = 0.26,
}
function Util.viewport()
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		if size and size.X > 0 and size.Y > 0 then
			return size
		end
	end
	return Vector2.new(1920, 1080)
end
function Util.isSmallScreen()
	local vs = Util.viewport()
	return vs.X < 760 or vs.Y < 520
end
function Util.isPress(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end
function Util.isMove(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
end
function Util.inputX(input)
	if input and input.Position then
		return input.Position.X
	end
	return UserInputService:GetMouseLocation().X
end
function Util.inputY(input)
	if input and input.Position then
		return input.Position.Y
	end
	return UserInputService:GetMouseLocation().Y
end
function Util.findScroller(inst)
	local node = inst
	while node do
		if node.ClassName == "ScrollingFrame" then
			return node
		end
		node = node.Parent
	end
	return nil
end
function Util.dragSession(connections, callbacks)
	callbacks = callbacks or {}
	local active = nil
	local session = {}
	function session.begin(input)
		if not Util.isPress(input) or active then
			return
		end
		active = input
		if callbacks.start then
			callbacks.start(input)
		end
	end
	function session.finish()
		if not active then
			return
		end
		active = nil
		if callbacks.finish then
			callbacks.finish()
		end
	end
	function session.isActive()
		return active ~= nil
	end
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if active and Util.isMove(input) then
			if callbacks.move then
				callbacks.move(input)
			end
		end
	end))
	local function sameInput(a, b)
		if a == b then
			return true
		end
		if a.UserInputType == Enum.UserInputType.Touch then
			return false
		end
		return a.UserInputType == b.UserInputType
	end
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if active and sameInput(input, active) then
			session.finish()
		end
	end))
	return session
end
local XHM = {}
XHM.__index = XHM
XHM.Version = "1.0.0"
XHM.Build = "source"
XHM.Credits = "Icons: Lucide (ISC) https://lucide.dev | Roblox data: latte-soft/lucide-roblox (MIT)"
XHM.Icons = Icons
XHM.Theme = Theme
XHM.Util = Util
local B = "https://raw.githubusercontent.com/XIEHUANGMOU/UI-BackGround/main/"
local I = "https://raw.githubusercontent.com/XIEHUANGMOU/UI_Icon/main/"
local S = "https://raw.githubusercontent.com/XIEHUANGMOU/UI-Sound/main/"
XHM.Assets = {
	Repo = {
		Background = B,
		Icon = I,
		Sound = S,
	},
	Background = {
		Snow = B .. "Snow-Background.png",
		ChineseWallpaper = B .. "Chinese-wallpaper.png",
		Ultraman = B .. "Ultraman_TIGA.jpg",
		Amine = B .. "amine1st.png",
		Eva = B .. "eva-cartoon-character.png",
		Yechi = B .. "Yechi_icon.png",
		ScriptIcon = B .. "HMOU%20SCRIPT%20ICON.png",
	},
	Icon = {
		Search = I .. "Search_Icon.png",
		Correct = I .. "Correct_icon.png",
		Ultra = I .. "XHM_Ultra_Icon.jpg",
	},
	IconMap = {
		search = I .. "Search_Icon.png",
		check = I .. "Correct_icon.png",
	},
	Sound = {
		Notify = S .. "notify_sound.mp3",
		Error = S .. "error-UI-sound.mp3",
	},
}
XHM.Shadow = {
	supported = shadowSupported,
	Window = { Blur = 20, Transparency = 0.30, Drop = 8, Spread = -3, Radius = 10 },
	Card = { Blur = 14, Transparency = 0.38, Drop = 5, Spread = -3, Radius = 8 },
	HandleGlow = { Color = Color3.new(1, 1, 1), Blur = 12, Transparency = 0.35, Drop = 0, Spread = 3 },
}
local Screens = setmetatable({}, { __mode = "k" })
XHM.Screens = Screens
function XHM.new(config)
	config = config or {}
	assert(type(config) == "table", "[XHM] new() 需要 table 参数")
	local self = setmetatable({}, XHM)
	self.Config = config
	self.Flags = {}
	self._flagComponents = {}
	self._flagListeners = {}
	self._accentBindings = {}
	self._tabs = {}
	self._activeTab = nil
	self._connections = {}
	self._notifications = {}
	self._notifyById = {}
	self._notifyOrder = 0
	self._notifyConn = nil
	self._minimized = false
	self._destroyed = false
	self._locked = config.Locked == true
	self._visible = true
	self._sounds = {}
	for name, source in pairs(config.Sounds or {}) do
		if type(source) == "string" and source ~= "" then
			self._sounds[name] = source
		end
	end
	if config.Accent then
		Theme.Accent = config.Accent
	end
	local viewport = Util.viewport()
	local margin = 24
	local maxW = math.max(viewport.X - margin, 240)
	local maxH = math.max(viewport.Y - margin, 200)
	self._maxSize = Vector2.new(maxW, maxH)
	local wantMin = config.MinSize or Vector2.new(360, 260)
	self._minSize = Vector2.new(
		math.min(wantMin.X, maxW),
		math.min(wantMin.Y, maxH)
	)
	local size = config.Size
	if size then
		size = UDim2.fromOffset(
			math.clamp(size.X.Offset, self._minSize.X, maxW),
			math.clamp(size.Y.Offset, self._minSize.Y, maxH)
		)
	else
		local defaultW = Util.isSmallScreen() and 460 or 640
		local defaultH = Util.isSmallScreen() and 340 or 440
		size = UDim2.fromOffset(
			math.clamp(defaultW, self._minSize.X, maxW),
			math.clamp(defaultH, self._minSize.Y, maxH)
		)
	end
	local screen = Util.create("ScreenGui", {
		Name = "XHM-NEW-UI_" .. tostring(config.Title or "Window"):gsub("%s+", "_"),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = config.DisplayOrder or 100,
	})
	self.Screen = screen
	local main = Util.create("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = screen,
	})
	self.Main = main
	Util.corner(main, 10)
	local rim = Util.create("Frame", {
		Name = "Rim",
		Position = UDim2.new(0, 1, 0, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = main,
	})
	Util.corner(rim, 9)
	self._rim = rim
	self._stroke = Util.stroke(rim, Theme.Stroke, 1)
	if config.Outline == false then
		self:SetOutline(false)
	end
	self._mainScale = Util.create("UIScale", { Name = "WindowScale", Scale = 1, Parent = main })
	local bg = Util.create("ImageLabel", {
		Name = "WindowBackground",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ImageTransparency = 1,
		Visible = false,
		ZIndex = 0,
		Parent = main,
	})
	Util.corner(bg, 10)
	self._bgImage = bg
	if config.Background then
		self:SetBackground(config.Background, {
			Fit = config.BackgroundFit,
			Transparency = config.BackgroundTransparency,
		})
	end
	if config.Shadow ~= false then
		self._shadowTwin, self._shadow = Util.shadowTwin(
			main, self.Screen, self:_shadowStyle(), self._connections)
	end
	local sheen = Util.create("Frame", {
		Name = "Sheen",
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = main,
	})
	Util.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.94),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
		Parent = sheen,
	})
	Util.corner(sheen, 10)
	self:_buildTitleBar()
	self.Rail = Util.create("Frame", {
		Name = "TabRail",
		Position = UDim2.new(0, 0, 0, Theme.TitleHeight),
		Size = UDim2.new(0, Theme.RailWidth, 1, -Theme.TitleHeight),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = main,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.Rail,
	})
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = self.Rail,
	})
	self.Container = Util.create("Frame", {
		Name = "Pages",
		Position = UDim2.new(0, Theme.RailWidth, 0, Theme.TitleHeight),
		Size = UDim2.new(1, -Theme.RailWidth, 1, -Theme.TitleHeight),
		BackgroundTransparency = 1,
		Parent = main,
	})
	self._notifyHolder = Util.create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.new(0, 300, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = screen,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = self._notifyHolder,
	})
	self:_bindDrag()
	if config.Resizable ~= false then
		self:_bindResize()
	end
	self:_bindToggleKey(config.ToggleKey)
	self:_buildLauncher()
	Screens[self] = true
	Util.safeParent(screen)
	local targetSize = size
	if size.X.Offset > 0 and size.Y.Offset > 0 then
		main.Size = UDim2.new(
			size.X.Scale, math.max(size.X.Offset - 26, 120),
			size.Y.Scale, math.max(size.Y.Offset - 22, 120)
		)
	end
	main.BackgroundTransparency = 0.7
	Util.tween(main, 0.3, {
		Size = targetSize,
		BackgroundTransparency = 0,
	}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return self
end
function XHM:_buildTitleBar()
	local bar = Util.create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, Theme.TitleHeight),
		BackgroundTransparency = 1,
		Parent = self.Main,
	})
	self.TitleBar = bar
	self.TitleIcon = Icons.new(bar, self.Config.Icon or "sparkles", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = Theme.Accent,
	})
	local titleX = 42
	local subtitle = self.Config.Subtitle
	local titleSize = subtitle and UDim2.new(1, -180, 0, 18) or UDim2.new(1, -180, 1, 0)
	local title = Util.create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, titleX, 0, subtitle and 6 or 0),
		Size = titleSize,
		Text = self.Config.Title or "XHM-NEW-UI",
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = subtitle and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		Parent = bar,
	})
	Util.font(title, "SemiBold")
	self.TitleLabel = title
	if subtitle then
		local sub = Util.create("TextLabel", {
			Name = "Subtitle",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, titleX, 1, -20),
			Size = UDim2.new(1, -180, 0, 14),
			Text = subtitle,
			TextColor3 = Theme.SubText,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = bar,
		})
		Util.font(sub, "Regular")
		self.SubtitleLabel = sub
	end
	local line = Util.create("Frame", {
		Name = "Line",
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = bar,
	})
	self._titleLine = line
	local buttons = {}
	self._titleButtons = buttons
	local function addButton(iconName, order, onClick)
		local btn = Util.create("TextButton", {
			Name = "TB_" .. iconName,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10 - (order - 1) * 32, 0.5, 0),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = Theme.SurfaceAlt,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = bar,
		})
		Util.corner(btn, 7)
		local fx = Util.create("UIScale", { Name = "FX", Scale = 1, Parent = btn })
		local icon = Icons.new(btn, iconName, {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = Theme.SubText,
		})
		btn.MouseEnter:Connect(function()
			Util.tween(btn, 0.14, { BackgroundTransparency = 0.2 })
			Util.tween(fx, 0.24, { Scale = 1.16 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			icon:setColor(Theme.Text)
		end)
		btn.MouseLeave:Connect(function()
			Util.tween(btn, 0.16, { BackgroundTransparency = 1 })
			Util.tween(fx, 0.24, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			icon:setColor(Theme.SubText)
		end)
		btn.MouseButton1Down:Connect(function()
			Util.tween(fx, 0.08, { Scale = 0.78 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end)
		btn.MouseButton1Up:Connect(function()
			Util.tween(fx, 0.3, { Scale = 1.16 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
		btn.MouseButton1Click:Connect(function(...)
			self:PlaySound("Click")
			if onClick then
				onClick(...)
			end
		end)
		table.insert(buttons, btn)
		return btn, icon, fx
	end
	self.CloseButton, self._closeIcon = addButton("x", 1, function()
		self:RequestClose()
	end)
	self.MinButton = addButton("minus", 2, function()
		self:ToggleMinimize()
	end)
	self.LockButton, self._lockIcon = addButton("unlock", 3, function()
		self:SetLocked(not self._locked)
	end)
	self.HideButton, self._hideIcon = addButton("eye-off", 4, function()
		self:SetVisible(false)
	end)
	self.CloseButton.MouseEnter:Connect(function()
		Util.tween(self.CloseButton, 0.14, { BackgroundColor3 = Theme.Error, BackgroundTransparency = 0.15 })
		self._closeIcon:setColor(Color3.fromRGB(255, 255, 255))
	end)
	self.CloseButton.MouseLeave:Connect(function()
		Util.tween(self.CloseButton, 0.16, { BackgroundColor3 = Theme.SurfaceAlt, BackgroundTransparency = 1 })
	end)
	self.LockButton.MouseEnter:Connect(function()
		if self._locked then
			self._lockIcon:setColor(Theme.Warning)
		end
	end)
	self:_refreshLockVisual()
end
function XHM:SetLocked(locked)
	self._locked = locked and true or false
	self:_refreshLockVisual()
	return self._locked
end
function XHM:IsLocked()
	return self._locked
end
function XHM:SetOutline(enabled)
	enabled = enabled ~= false
	if self._stroke then
		self._stroke.Enabled = enabled
	end
	return enabled
end
function XHM:_shadowStyle()
	local style = {}
	for k, v in pairs(XHM.Shadow.Window) do
		style[k] = v
	end
	style.Scale = self._mainScale
	return style
end
function XHM:SetShadow(enabled)
	enabled = enabled ~= false
	if not enabled then
		if self._shadow then
			self._shadow.Enabled = false
		end
		return false
	end
	if not self._shadow then
		if not self._shadowTwin then
			self._shadowTwin, self._shadow = Util.shadowTwin(
				self.Main, self.Screen, self:_shadowStyle(), self._connections)
		else
			self._shadow = Util.shadow(self._shadowTwin, self:_shadowStyle())
		end
	end
	if self._shadow then
		self._shadow.Enabled = true
	end
	return true
end
function XHM:_refreshLockVisual()
	if not self._lockIcon then
		return
	end
	if self._locked then
		self._lockIcon:set("lock")
		self._lockIcon:setColor(Theme.Warning)
		self.LockButton.BackgroundTransparency = 0.45
	else
		self._lockIcon:set("unlock")
		self._lockIcon:setColor(Theme.SubText)
		self.LockButton.BackgroundTransparency = 1
	end
end
function XHM:_bindDrag()
	local bar = self.TitleBar
	local main = self.Main
	local dragStart, startPos
	local viaHandle = false
	local snapThreshold = 12
	local function snapToEdges()
		local screen = self:_screenSize()
		local size = main.AbsoluteSize
		local x = main.Position.X.Scale * screen.X + main.Position.X.Offset - size.X / 2
		local y = main.Position.Y.Scale * screen.Y + main.Position.Y.Offset - size.Y / 2
		if x < snapThreshold then
			x = 0
		elseif math.abs(x + size.X - screen.X) < snapThreshold then
			x = screen.X - size.X
		end
		if y < snapThreshold then
			y = 0
		elseif math.abs(y + size.Y - screen.Y) < snapThreshold then
			y = screen.Y - size.Y
		end
		x = math.clamp(x, -size.X + 80, screen.X - 80)
		y = math.clamp(y, 0, screen.Y - 40)
		self:_setAbsolute(math.round(x), math.round(y))
	end
	local HANDLE_GAP = 6
	local HANDLE_MIN, HANDLE_MAX = 120, 300
	local HANDLE_RATIO = 0.5
	local PILL_COLOR = Color3.new(1, 1, 1)
	local PILL_ALPHA = 0.1
	local handleHit = Util.create("TextButton", {
		Name = "DragHandle",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(HANDLE_MIN, 22),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 7,
		Parent = self.Screen,
	})
	local handle = Util.create("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = PILL_COLOR,
		BackgroundTransparency = PILL_ALPHA,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = handleHit,
	})
	Util.corner(handle, 3)
	Util.shadow(handle, XHM.Shadow.HandleGlow)
	self.DragHandle = handleHit
	self._dragPill = handle
	local function syncHandle()
		local size = main.AbsoluteSize
		local screen = self:_screenSize()
		local width = math.clamp(size.X * HANDLE_RATIO, HANDLE_MIN, HANDLE_MAX)
		handleHit.Size = UDim2.fromOffset(math.floor(width + 0.5), 22)
		local yPix = main.Position.Y.Scale * screen.Y + main.Position.Y.Offset
			+ size.Y / 2 + HANDLE_GAP
		local maxY = screen.Y - 22
		if yPix > maxY then
			yPix = maxY
		end
		handleHit.Position = UDim2.new(
			main.Position.X.Scale, main.Position.X.Offset,
			0, yPix
		)
		handleHit.Visible = main.Visible
	end
	self._syncDragHandle = syncHandle
	syncHandle()
	table.insert(self._connections, main:GetPropertyChangedSignal("Position"):Connect(syncHandle))
	table.insert(self._connections, main:GetPropertyChangedSignal("Size"):Connect(syncHandle))
	table.insert(self._connections, main:GetPropertyChangedSignal("Visible"):Connect(syncHandle))
	if self._mainScale then
		table.insert(self._connections,
			self._mainScale:GetPropertyChangedSignal("Scale"):Connect(syncHandle))
	end
	local function paintPill(color, transparency, time)
		Util.tween(handle, time, { BackgroundColor3 = color, BackgroundTransparency = transparency })
	end
	local session = Util.dragSession(self._connections, {
		start = function(input)
			dragStart = input.Position
			startPos = main.Position
			if viaHandle then
				paintPill(Theme.Accent, 0, 0.1)
			end
		end,
		move = function(input)
			local delta = input.Position - dragStart
			main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end,
		finish = function()
			snapToEdges()
			if viaHandle then
				paintPill(PILL_COLOR, PILL_ALPHA, 0.18)
			end
			viaHandle = false
		end,
	})
	table.insert(self._connections, bar.InputBegan:Connect(function(input)
		if self._locked then
			return
		end
		viaHandle = false
		session.begin(input)
	end))
	table.insert(self._connections, handleHit.InputBegan:Connect(function(input)
		if self._locked then
			return
		end
		viaHandle = true
		session.begin(input)
	end))
	handleHit.MouseEnter:Connect(function()
		paintPill(PILL_COLOR, 0, 0.12)
	end)
	handleHit.MouseLeave:Connect(function()
		if not session.isActive() then
			paintPill(PILL_COLOR, PILL_ALPHA, 0.16)
		end
	end)
end
function XHM:_screenSize()
	local size = self.Screen.AbsoluteSize
	if not size or size.X <= 0 or size.Y <= 0 then
		return Util.viewport()
	end
	return size
end
function XHM:_setAbsolute(x, y)
	local main = self.Main
	local parentSize = self:_screenSize()
	local ap = main.AnchorPoint
	main.Position = UDim2.new(
		(x + ap.X * main.AbsoluteSize.X) / parentSize.X,
		0,
		(y + ap.Y * main.AbsoluteSize.Y) / parentSize.Y,
		0
	)
end
function XHM:_bindResize()
	local main = self.Main
	local grip = Util.create("TextButton", {
		Name = "ResizeGrip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Theme.SurfaceAlt,
		BackgroundTransparency = 0.65,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
		Parent = main,
	})
	self._grip = grip
	Util.corner(grip, 8)
	Icons.new(grip, "chevron-down", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Muted,
		Rotation = -45,
	})
	local resizing = false
	local startInput, startSize, startPos
	grip.MouseEnter:Connect(function()
		Util.tween(grip, 0.15, { BackgroundTransparency = 0.25 })
	end)
	grip.MouseLeave:Connect(function()
		if not resizing then
			Util.tween(grip, 0.15, { BackgroundTransparency = 0.65 })
		end
	end)
	local session = Util.dragSession(self._connections, {
		start = function(input)
			resizing = true
			startInput = input.Position
			startSize = main.AbsoluteSize
			startPos = main.Position
			main.Size = UDim2.fromOffset(startSize.X, startSize.Y)
			Util.tween(grip, 0.15, { BackgroundTransparency = 0.1 })
		end,
		move = function(input)
			local delta = input.Position - startInput
			local w = math.clamp(startSize.X + delta.X, self._minSize.X, self._maxSize.X)
			local h = math.clamp(startSize.Y + delta.Y, self._minSize.Y, self._maxSize.Y)
			main.Size = UDim2.fromOffset(w, h)
			local dx = (w - startSize.X) / 2
			local dy = (h - startSize.Y) / 2
			main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + dx,
				startPos.Y.Scale, startPos.Y.Offset + dy
			)
		end,
		finish = function()
			resizing = false
			Util.tween(grip, 0.2, { BackgroundTransparency = 0.65 })
		end,
	})
	table.insert(self._connections, grip.InputBegan:Connect(function(input)
		if self._locked then
			return
		end
		session.begin(input)
	end))
end
function XHM:_setGripVisible(visible)
	local grip = self._grip
	if not grip then
		return
	end
	if visible then
		grip.Visible = true
		Util.tween(grip, 0.18, { BackgroundTransparency = 0.65 })
	else
		Util.tween(grip, 0.14, { BackgroundTransparency = 1 })
		task.delay(0.14, function()
			if self._minimized and not self._destroyed then
				grip.Visible = false
			end
		end)
	end
end
function XHM:_bindToggleKey(key)
	if not key then
		key = Enum.KeyCode.RightShift
	end
	self.ToggleKey = key
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == key then
			self:Toggle()
		end
	end))
end
function XHM:_applyLauncherContent()
	local launcher = self.Launcher
	if not launcher then
		return
	end
	local size = self.Config.LauncherSize or 46
	if not self._launcherIcon then
		self._launcherIcon = Icons.new(launcher, self.Config.LauncherIcon or self.Config.Icon or "sparkles", {
			Size = UDim2.fromOffset(math.floor(size * 0.46), math.floor(size * 0.46)),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Color = Color3.fromRGB(255, 255, 255),
			ZIndex = 2,
		})
	end
	local source = self.Config.LauncherImage
	local asset = source and Util.customAsset(source) or nil
	if asset then
		if not self._launcherImageLabel then
			self._launcherImageLabel = Util.create("ImageLabel", {
				Name = "LauncherImage",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 1,
				Parent = launcher,
			})
		end
		local image = self._launcherImageLabel
		image.Image = asset
		image.ImageColor3 = self.Config.LauncherImageColor or Color3.fromRGB(255, 255, 255)
		image.ScaleType = (self.Config.LauncherImageFit == "fit")
			and Enum.ScaleType.Fit or Enum.ScaleType.Crop
		image.Visible = true
		if self.Config.LauncherIcon then
			self._launcherIcon:set(self.Config.LauncherIcon)
			self._launcherIcon:setVisible(true)
		else
			self._launcherIcon:setVisible(false)
		end
	else
		if source then
			warn("[XHM] 悬浮球背景图加载失败，已回退到图标: " .. tostring(source))
		end
		if self._launcherImageLabel then
			self._launcherImageLabel.Visible = false
		end
		self._launcherIcon:setVisible(true)
	end
end
function XHM:SetLauncherImage(source)
	self.Config.LauncherImage = source
	self:_applyLauncherContent()
	local image = self._launcherImageLabel
	if image and image.Visible then
		return image.Image
	end
	return nil
end
function XHM:SetBackground(source, opts)
	opts = opts or {}
	local img = self._bgImage
	if not img then
		return nil
	end
	if not source or source == "" then
		img.Visible = false
		img.Image = ""
		return nil
	end
	local asset = Util.customAsset(source)
	if not asset then
		img.Visible = false
		warn("[XHM] 窗口背景图加载失败（需要执行器的 writefile + getcustomasset）: "
			.. tostring(source))
		return nil
	end
	img.Image = asset
	if opts.Fit ~= nil then
		img.ScaleType = (opts.Fit == "fit") and Enum.ScaleType.Fit or Enum.ScaleType.Crop
	end
	img.ImageTransparency = opts.Transparency or 0.25
	img.Visible = true
	return asset
end
function XHM:SetSound(name, source)
	self._sounds = self._sounds or {}
	self._sounds[name] = source
	self._soundAssets = self._soundAssets or {}
	self._soundAssets[name] = nil
	return source
end
function XHM:PlaySound(name, volume)
	local source = self._sounds and self._sounds[name]
	if not source or self._destroyed then
		return nil
	end
	local asset = Util.customAsset(source)
	if not asset then
		warn("[XHM] 音效加载失败: " .. tostring(name) .. " <- " .. tostring(source))
		return nil
	end
	local sound = Util.create("Sound", {
		Name = "XHM_Sound_" .. tostring(name),
		SoundId = asset,
		Volume = volume or self.Config.SoundVolume or 0.5,
		Parent = self.Screen,
	})
	sound:Play()
	local function cleanup()
		if sound.Parent then
			sound:Destroy()
		end
	end
	sound.Ended:Connect(cleanup)
	task.delay(20, cleanup)
	return sound
end
function XHM:_buildLauncher()
	local size = self.Config.LauncherSize or 46
	local launcher = Util.create("TextButton", {
		Name = "Launcher",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 16, 0, 60),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.08,
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 60,
		Parent = self.Screen,
	})
	Util.corner(launcher, size / 2)
	Util.stroke(launcher, Color3.fromRGB(255, 255, 255), 1, 0.8)
	self.Launcher = launcher
	local fx = Util.create("UIScale", { Name = "FX", Scale = 1, Parent = launcher })
	self._launcherScale = fx
	self:_applyLauncherContent()
	local dragStart, startPos
	local dragged = false
	local session = Util.dragSession(self._connections, {
		start = function(input)
			dragged = false
			dragStart = input.Position
			startPos = launcher.Position
			Util.tween(fx, 0.1, { Scale = 0.92 })
		end,
		move = function(input)
			dragged = true
			local delta = input.Position - dragStart
			launcher.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end,
		finish = function()
			Util.tween(fx, 0.24, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end,
	})
	launcher.InputBegan:Connect(session.begin)
	launcher.MouseEnter:Connect(function()
		Util.tween(launcher, 0.16, { BackgroundTransparency = 0 })
		Util.tween(fx, 0.2, { Scale = 1.08 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
	launcher.MouseLeave:Connect(function()
		Util.tween(launcher, 0.18, { BackgroundTransparency = 0.08 })
		Util.tween(fx, 0.2, { Scale = 1 })
	end)
	launcher.MouseButton1Click:Connect(function()
		if dragged then
			return
		end
		self:PlaySound("Click")
		self:SetVisible(true)
	end)
	self:OnAccent(function(color)
		launcher.BackgroundColor3 = color
	end)
	return launcher
end
function XHM:Toggle()
	self:SetVisible(not self._visible)
end
function XHM:IsVisible()
	return self._visible
end
function XHM:SetVisible(visible)
	visible = visible and true or false
	if self._destroyed or self._visible == visible then
		return
	end
	self._visible = visible
	local main = self.Main
	local scale = self._mainScale
	if visible then
		if self.Launcher then
			self.Launcher.Visible = false
		end
		main.Visible = true
		main.BackgroundTransparency = 0.6
		scale.Scale = 0
		Util.tween(main, 0.24, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Util.tween(scale, 0.34, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		if self.Launcher then
			self.Launcher.Visible = true
			self._launcherScale.Scale = 0
			task.delay(0.1, function()
				if self._destroyed or self._visible then
					return
				end
				Util.tween(self._launcherScale, 0.42, { Scale = 1 },
					Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end)
		end
		Util.tween(scale, 0.26, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		Util.tween(main, 0.26, { BackgroundTransparency = 1 })
		self._visibilityToken = (self._visibilityToken or 0) + 1
		local token = self._visibilityToken
		task.delay(0.3, function()
			if self._destroyed or self._visibilityToken ~= token or self._visible then
				return
			end
			main.Visible = false
			main.BackgroundTransparency = 0
			scale.Scale = 1
		end)
	end
end
function XHM:ToggleMinimize()
	self._minimized = not self._minimized
	local main = self.Main
	local rail = self.Rail
	local container = self.Container
	local titleH = Theme.TitleHeight
	if self._minimized then
		self._restoreSize = main.Size
		Util.tween(rail, 0.34, { BackgroundTransparency = 1 },
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Util.tween(main, 0.34, {
			Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, titleH),
		}, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		self:_setGripVisible(false)
		task.delay(0.34, function()
			if self._minimized and not self._destroyed then
				rail.Visible = false
				container.Visible = false
			end
		end)
	else
		local size = self._restoreSize or UDim2.fromOffset(640, 440)
		rail.Visible = true
		container.Visible = true
		rail.BackgroundTransparency = 1
		Util.tween(rail, 0.34, { BackgroundTransparency = 0.35 },
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Util.tween(main, 0.34, { Size = size },
			Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self:_setGripVisible(true)
	end
end
function XHM:SetAccent(color)
	Theme.Accent = color
	Theme.AccentHover = color:Lerp(Color3.new(1, 1, 1), 0.2)
	for _, fn in ipairs(self._accentBindings) do
		pcall(fn, color)
	end
end
function XHM:OnAccent(fn)
	table.insert(self._accentBindings, fn)
	pcall(fn, Theme.Accent)
	return fn
end
function XHM:SetTitle(text)
	self.TitleLabel.Text = text
end
function XHM:Tab(tabConfig)
	tabConfig = tabConfig or {}
	local self_ = self
	local tab = {}
	tab.Window = self
	tab.Name = tabConfig.Name or "Tab"
	tab.IconName = tabConfig.Icon or "dot"
	local page = Util.create("Frame", {
		Name = "Page_" .. tab.Name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = self.Container,
	})
	local left = Util.create("ScrollingFrame", {
		Name = "Left",
		Position = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.StrokeLight,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = page,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = left,
	})
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 6),
		Parent = left,
	})
	local right = Util.create("ScrollingFrame", {
		Name = "Right",
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.StrokeLight,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = page,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = right,
	})
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 12),
		Parent = right,
	})
	tab.Page = page
	tab.Left = left
	tab.Right = right
	tab._sections = {}
	tab._order = 0
	function tab:Section(sectionConfig)
		return self.Window:_createSection(self, sectionConfig)
	end
	function tab:Select()
		self.Window:SelectTab(self)
	end
	function tab:SetVisible(visible)
		self.Button.Visible = visible and true or false
	end
	local btn = Util.create("TextButton", {
		Name = "Tab_" .. tab.Name,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.SurfaceHover,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = #self._tabs + 1,
		Parent = self.Rail,
	})
	Util.corner(btn, 6)
	local indicator = Util.create("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = btn,
	})
	Util.corner(indicator, 2)
	local icon = Icons.new(btn, tab.IconName, {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = Theme.SubText,
	})
	local label = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 36, 0, 0),
		Size = UDim2.new(1, -44, 1, 0),
		Text = tab.Name,
		TextColor3 = Theme.SubText,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})
	Util.font(label, "Medium")
	tab.Button = btn
	tab.Icon = icon
	tab.Label = label
	tab.Indicator = indicator
	btn.MouseEnter:Connect(function()
		if self._activeTab ~= tab then
			Util.tween(btn, 0.12, { BackgroundTransparency = 0.5 })
		end
	end)
	btn.MouseLeave:Connect(function()
		if self._activeTab ~= tab then
			Util.tween(btn, 0.12, { BackgroundTransparency = 1 })
		end
	end)
	btn.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)
	local iconScale = Util.create("UIScale", { Name = "FX", Scale = 1, Parent = icon.Instance })
	btn.MouseButton1Down:Connect(function()
		Util.tween(btn, 0.08, { BackgroundTransparency = 0.35 })
		Util.tween(iconScale, 0.08, { Scale = 0.82 })
	end)
	btn.MouseButton1Up:Connect(function()
		Util.tween(btn, 0.18, { BackgroundTransparency = self._activeTab == tab and 0.15 or 1 })
		Util.tween(iconScale, 0.26, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
	table.insert(self._tabs, tab)
	if #self._tabs == 1 then
		self:SelectTab(tab, true)
	end
	return tab
end
function XHM:SelectTab(tab, instant)
	if self._activeTab == tab then
		return
	end
	local previous = self._activeTab
	self._activeTab = tab
	for _, t in ipairs(self._tabs) do
		local active = (t == tab)
		t.Page.Visible = active
		if active then
			Util.tween(t.Button, 0.15, { BackgroundTransparency = 0.15 })
			Util.tween(t.Label, 0.15, { TextColor3 = Theme.Text })
			t.Icon:setColor(Theme.Accent)
			Util.tween(t.Indicator, 0.2, { Size = UDim2.new(0, 3, 0, 16) })
		else
			Util.tween(t.Button, 0.15, { BackgroundTransparency = 1 })
			Util.tween(t.Label, 0.15, { TextColor3 = Theme.SubText })
			t.Icon:setColor(Theme.SubText)
			Util.tween(t.Indicator, 0.2, { Size = UDim2.new(0, 3, 0, 0) })
		end
	end
	if not instant then
		local slide = 14
		for _, column in ipairs({ tab.Left, tab.Right }) do
			local base = column.Position
			column.Position = UDim2.new(base.X.Scale, base.X.Offset + slide, base.Y.Scale, base.Y.Offset)
			Util.tween(column, 0.26, { Position = base },
				Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end
	return tab
end
function XHM:GetTab(name)
	for _, t in ipairs(self._tabs) do
		if t.Name == name then
			return t
		end
	end
	return nil
end
local Section = {}
Section.__index = Section
function XHM:_createSection(tab, cfg)
	cfg = cfg or {}
	local side = cfg.Side or "Left"
	local column = (side == "Right") and tab.Right or tab.Left
	if side == "Right" or cfg.TwoColumn then
		tab.Left.Size = UDim2.fromScale(0.5, 1)
		tab.Right.Visible = true
	end
	tab._order += 1
	local section = setmetatable({}, Section)
	section.Tab = tab
	section.Window = self
	section._order = 0
	section.Name = cfg.Name or "Section"
	local root = Util.create("Frame", {
		Name = "Section_" .. section.Name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = tab._order,
		Parent = column,
	})
	Util.corner(root, Theme.Radius)
	Util.stroke(root, Theme.Stroke, 1, 0.35)
	section.Root = root
	Util.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})
	local collapsed = cfg.Collapsed == true
	section._collapsed = collapsed
	local header = Util.create("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
		Parent = root,
	})
	Util.corner(header, Theme.Radius)
	section.Header = header
	local hx = 12
	if cfg.Icon then
		section.HeaderIcon = Icons.new(header, cfg.Icon, {
			Size = UDim2.fromOffset(15, 15),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = Theme.Accent,
		})
		hx = 34
	end
	local headerLabel = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, hx, 0, 0),
		Size = UDim2.new(1, -(hx + 40), 1, 0),
		Text = cfg.Name or "Section",
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = header,
	})
	Util.font(headerLabel, "SemiBold")
	section.HeaderLabel = headerLabel
	local chevronHolder = Util.create("Frame", {
		Name = "Chevron",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Parent = header,
	})
	local chevron = Icons.new(chevronHolder, "chevron-down", {
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Muted,
	})
	section.Chevron = chevron
	section.ChevronHolder = chevronHolder
	local content = Util.create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = collapsed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 2,
		Visible = not collapsed,
		Parent = root,
	})
	section.Content = content
	local inner = Util.create("Frame", {
		Name = "ContentInner",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = content,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = inner,
	})
	Util.create("UIPadding", {
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = inner,
	})
	section.ContentInner = inner
	if collapsed then
		chevronHolder.Rotation = -90
	end
	header.MouseEnter:Connect(function()
		Util.tween(header, 0.12, { BackgroundTransparency = 0.75 })
	end)
	header.MouseLeave:Connect(function()
		Util.tween(header, 0.12, { BackgroundTransparency = 1 })
	end)
	header.MouseButton1Click:Connect(function()
		section:SetCollapsed(not section._collapsed)
	end)
	header.MouseButton1Down:Connect(function()
		Util.tween(header, 0.08, { BackgroundTransparency = 0.5 })
	end)
	header.MouseButton1Up:Connect(function()
		Util.tween(header, 0.18, { BackgroundTransparency = 0.75 })
	end)
	table.insert(tab._sections, section)
	return section
end
function Section:_contentNaturalHeight()
	local inner = self.ContentInner
	local height = inner and inner.AbsoluteSize.Y or 0
	if height <= 0 and self.Content then
		height = self.Content.AbsoluteSize.Y
	end
	if height <= 0 then
		height = self._contentHeight or 0
	end
	if height > 0 then
		self._contentHeight = height
	end
	return height
end
function Section:SetCollapsed(state)
	state = state and true or false
	if self._collapsed == state then
		return
	end
	self._collapsed = state
	local content = self.Content
	local inner = self.ContentInner
	Util.tween(self.ChevronHolder, 0.2, { Rotation = state and -90 or 0 },
		Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if state then
		local height = self:_contentNaturalHeight()
		inner.AutomaticSize = Enum.AutomaticSize.None
		inner.Size = UDim2.new(1, 0, 0, height)
		inner.Position = UDim2.new(0, 0, 0, 0)
		content.AutomaticSize = Enum.AutomaticSize.None
		content.Size = UDim2.new(1, 0, 0, height)
		Util.tween(content, 0.2, { Size = UDim2.new(1, 0, 0, 0) },
			Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		Util.tween(inner, 0.2, { Position = UDim2.new(0, 0, 0, -height) },
			Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		task.delay(0.2, function()
			if self._collapsed then
				content.Visible = false
				content.Size = UDim2.new(1, 0, 0, 0)
				inner.Position = UDim2.new(0, 0, 0, 0)
				inner.Size = UDim2.new(1, 0, 0, 0)
				inner.AutomaticSize = Enum.AutomaticSize.Y
			end
		end)
	else
		local target = self:_contentNaturalHeight()
		content.Visible = true
		content.AutomaticSize = Enum.AutomaticSize.None
		content.Size = UDim2.new(1, 0, 0, 0)
		inner.AutomaticSize = Enum.AutomaticSize.None
		inner.Size = UDim2.new(1, 0, 0, target)
		inner.Position = UDim2.new(0, 0, 0, -target)
		Util.tween(content, 0.22, { Size = UDim2.new(1, 0, 0, target) },
			Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Util.tween(inner, 0.22, { Position = UDim2.new(0, 0, 0, 0) },
			Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		task.delay(0.22, function()
			if not self._collapsed then
				inner.Position = UDim2.new(0, 0, 0, 0)
				inner.AutomaticSize = Enum.AutomaticSize.Y
				content.Size = UDim2.new(1, 0, 0, 0)
				content.AutomaticSize = Enum.AutomaticSize.Y
			end
		end)
	end
end
function Section:_row(height, flag)
	self._order += 1
	local frame = Util.create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self._order,
		Parent = self.ContentInner,
	})
	Util.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	local header = Util.create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.SurfaceHover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = frame,
	})
	Util.corner(header, 6)
	local indicator = Util.create("Frame", {
		Name = "Indicator",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 2, 0, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = header,
	})
	Util.corner(indicator, 1)
	local row = {
		Instance = frame,
		Header = header,
		Flag = flag,
	}
	function row:Destroy()
		frame:Destroy()
	end
	local hovering, pressing = false, false
	local function bg(target, time)
		Util.tween(header, time or Theme.Anim, { BackgroundTransparency = target })
	end
	local function paintIcon(color)
		if row.IconObj then
			row.IconObj:setColor(color)
		end
	end
	row.FX = {
		baseAlpha = 1,
		hoverAlpha = 0.72,
		pressAlpha = 0.5,
		enter = function()
			hovering = true
			bg(pressing and row.FX.pressAlpha or row.FX.hoverAlpha, 0.18)
			Util.tween(indicator, 0.24, { Size = UDim2.new(0, 2, 0, 16) },
				Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			paintIcon(Theme.Accent)
		end,
		leave = function()
			hovering = false
			bg(row.FX.baseAlpha, 0.2)
			Util.tween(indicator, 0.18, { Size = UDim2.new(0, 2, 0, 0) })
			paintIcon(Theme.SubText)
		end,
		press = function()
			pressing = true
			bg(row.FX.pressAlpha, 0.08)
		end,
		release = function()
			pressing = false
			bg(hovering and row.FX.hoverAlpha or row.FX.baseAlpha, 0.16)
		end,
	}
	header.MouseEnter:Connect(row.FX.enter)
	header.MouseLeave:Connect(row.FX.leave)
	return row
end
function Section:_title(row, cfg, padRight)
	local x = 8
	if cfg.Icon then
		row.IconObj = Icons.new(row.Header, cfg.Icon, {
			Size = UDim2.fromOffset(15, 15),
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = cfg.IconColor or Theme.SubText,
		})
		x += 22
	end
	local label = Util.create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, x, 0, 0),
		Size = UDim2.new(1, -(x + (padRight or 90)), 1, 0),
		Text = cfg.Name or "",
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row.Header,
	})
	Util.font(label, "Medium")
	row.TitleLabel = label
	return label
end
function Section:Button(cfg)
	cfg = cfg or {}
	local row = self:_row(cfg.Height or 34, cfg.Flag)
	local x = 8
	if cfg.Icon then
		row.IconObj = Icons.new(row.Header, cfg.Icon, {
			Size = UDim2.fromOffset(15, 15),
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = cfg.IconColor or Theme.Text,
		})
		x += 22
	end
	local label = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, x, 0, 0),
		Size = UDim2.new(1, -(x + 40), 1, 0),
		Text = cfg.Name or "Button",
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = row.Header,
	})
	Util.font(label, "Medium")
	local chevron = Icons.new(row.Header, "chevron-right", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Color = Theme.Muted,
	})
	local btn = Util.create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = row.Header,
	})
	row.Header.BackgroundColor3 = Theme.SurfaceAlt
	row.Header.BackgroundTransparency = 0.35
	row.FX.baseAlpha = 0.35
	row.FX.hoverAlpha = 0.05
	row.FX.pressAlpha = 0
	btn.MouseEnter:Connect(function()
		row.FX.enter()
		chevron:setColor(Theme.Text)
		Util.tween(chevron.Instance, 0.2, { Position = UDim2.new(1, -6, 0.5, 0) })
	end)
	btn.MouseLeave:Connect(function()
		row.FX.leave()
		chevron:setColor(Theme.Muted)
		Util.tween(chevron.Instance, 0.2, { Position = UDim2.new(1, -10, 0.5, 0) })
	end)
	btn.MouseButton1Down:Connect(row.FX.press)
	btn.MouseButton1Up:Connect(row.FX.release)
	local obj = { Value = nil, Flag = cfg.Flag }
	obj.SetText = function(_, text)
		label.Text = text
	end
	obj.SetIcon = function(_, iconName)
		if row.IconObj then
			row.IconObj:set(iconName)
		else
			row.IconObj = Icons.new(row.Header, iconName, {
				Size = UDim2.fromOffset(15, 15),
				Position = UDim2.new(0, 8, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Color = Theme.Text,
			})
			label.Position = UDim2.new(0, 30, 0, 0)
			label.Size = UDim2.new(1, -70, 1, 0)
		end
	end
	obj.Destroy = function()
		row:Destroy()
	end
	btn.MouseButton1Click:Connect(function()
		row.FX.release()
		if cfg.Callback then
			task.spawn(cfg.Callback)
		end
	end)
	if cfg.Flag then
		self.Window._flagComponents[cfg.Flag] = { object = obj, setter = function() end }
	end
	return obj
end
function Section:Toggle(cfg)
	cfg = cfg or {}
	local row = self:_row(34, cfg.Flag)
	self:_title(row, cfg, 60)
	local trackW, trackH = 36, 20
	local track = Util.create("TextButton", {
		Name = "Track",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(trackW, trackH),
		BackgroundColor3 = Theme.SurfaceHover,
		Text = "",
		AutoButtonColor = false,
		Parent = row.Header,
	})
	Util.corner(track, trackH / 2)
	Util.stroke(track, Theme.Stroke, 1, 0.2)
	local knob = Util.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(trackH - 6, trackH - 6),
		BackgroundColor3 = Theme.SubText,
		BorderSizePixel = 0,
		Parent = track,
	})
	Util.corner(knob, (trackH - 6) / 2)
	local knobScale = Util.create("UIScale", { Name = "FX", Scale = 1, Parent = knob })
	local obj = { Value = cfg.Default == true, Flag = cfg.Flag }
	local animating = false
	local function apply(value, silent)
		obj.Value = value
		if not silent then
			Util.tween(knobScale, 0.08, { Scale = 0.78 })
			task.delay(0.08, function()
				Util.tween(knobScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end)
		end
		if value then
			Util.tween(track, Theme.Anim, { BackgroundColor3 = Theme.Accent })
			Util.tween(knob, Theme.Anim, {
				Position = UDim2.new(0, trackW - (trackH - 6) - 2, 0.5, 0),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			})
		else
			Util.tween(track, Theme.Anim, { BackgroundColor3 = Theme.SurfaceHover })
			Util.tween(knob, Theme.Anim, {
				Position = UDim2.new(0, 2, 0.5, 0),
				BackgroundColor3 = Theme.SubText,
			})
		end
		self.Window:_writeFlag(obj.Flag, value)
		if not silent and cfg.Callback then
			task.spawn(cfg.Callback, value)
		end
	end
	obj.Get = function()
		return obj.Value
	end
	obj.Set = function(_, value, silent)
		value = value and true or false
		if obj.Value == value then
			return
		end
		apply(value, silent)
	end
	obj.SetText = function(_, text)
		row.TitleLabel.Text = text
	end
	obj.Destroy = function()
		row:Destroy()
	end
	track.MouseButton1Click:Connect(function()
		apply(not obj.Value, false)
	end)
	self.Window:OnAccent(function(color)
		if obj.Value then
			track.BackgroundColor3 = color
		end
	end)
	if obj.Flag then
		self.Window._flagComponents[obj.Flag] = { object = obj, setter = obj.Set }
		self.Window:_writeFlag(obj.Flag, obj.Value)
	end
	if obj.Value then
		apply(true, true)
	end
	return obj
end
function Section:Slider(cfg)
	cfg = cfg or {}
	local min = cfg.Min or 0
	local max = cfg.Max or 100
	local decimals = cfg.Decimals or 0
	local suffix = cfg.Suffix or ""
	local step = cfg.Step
	local row = self:_row(46, cfg.Flag)
	local header = row.Header
	header.Size = UDim2.new(1, 0, 0, 46)
	local x = 8
	if cfg.Icon then
		row.IconObj = Icons.new(header, cfg.Icon, {
			Size = UDim2.fromOffset(15, 15),
			Position = UDim2.new(0, x, 0, 12),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = Theme.SubText,
		})
		x += 22
	end
	local label = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, x, 0, 6),
		Size = UDim2.new(1, -(x + 70), 0, 18),
		Text = cfg.Name or "Slider",
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = header,
	})
	Util.font(label, "Medium")
	local valueLabel = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.new(0, 90, 0, 18),
		Text = "0",
		TextColor3 = Theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = header,
	})
	Util.font(valueLabel, "Medium")
	local track = Util.create("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 8, 1, -16),
		Size = UDim2.new(1, -16, 0, 5),
		BackgroundColor3 = Theme.SurfaceHover,
		BorderSizePixel = 0,
		Parent = header,
	})
	Util.corner(track, 3)
	local fill = Util.create("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	Util.corner(fill, 3)
	local knob = Util.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})
	Util.corner(knob, 6)
	Util.stroke(knob, Theme.Accent, 2, 0)
	local hit = Util.create("TextButton", {
		Position = UDim2.new(0, -6, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, 12, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
		Parent = track,
	})
	local obj = { Value = cfg.Default or min, Flag = cfg.Flag }
	local function fmt(v)
		local s = tostring(Util.round(v, decimals))
		return s .. suffix
	end
	local function apply(v, silent)
		v = math.clamp(v, min, max)
		if step and step > 0 then
			v = math.floor((v - min) / step + 0.5) * step + min
		end
		v = math.clamp(Util.round(v, math.max(decimals, 0)), min, max)
		obj.Value = v
		local alpha = (max - min) == 0 and 0 or (v - min) / (max - min)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueLabel.Text = fmt(v)
		self.Window:_writeFlag(obj.Flag, v)
		if not silent and cfg.Callback then
			task.spawn(cfg.Callback, v)
		end
	end
	obj.Get = function()
		return obj.Value
	end
	obj.Set = function(_, v, silent)
		apply(v, silent)
	end
	obj.SetText = function(_, text)
		label.Text = text
	end
	obj.Destroy = function()
		row:Destroy()
	end
	local dragging = false
	local function updateFromInput(input)
		local pointerX = Util.inputX(input)
		local posX = track.AbsolutePosition.X
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((pointerX - posX) / width, 0, 1)
		apply(min + (max - min) * alpha, false)
	end
	local session = Util.dragSession(self.Window._connections, {
		start = function(input)
			dragging = true
			row.Scroller = row.Scroller or Util.findScroller(track)
			if row.Scroller then
				row.Scroller.ScrollingEnabled = false
			end
			Util.tween(knob, 0.1, { Size = UDim2.fromOffset(15, 15) })
			updateFromInput(input)
		end,
		move = updateFromInput,
		finish = function()
			dragging = false
			if row.Scroller then
				row.Scroller.ScrollingEnabled = true
			end
			Util.tween(knob, 0.1, { Size = UDim2.fromOffset(12, 12) })
		end,
	})
	hit.InputBegan:Connect(session.begin)
	track.MouseEnter:Connect(function()
		Util.tween(fill, 0.12, { BackgroundColor3 = Theme.AccentHover })
	end)
	track.MouseLeave:Connect(function()
		Util.tween(fill, 0.12, { BackgroundColor3 = Theme.Accent })
	end)
	self.Window:OnAccent(function(color)
		fill.BackgroundColor3 = color
		knob.UIStroke.Color = color
	end)
	if obj.Flag then
		self.Window._flagComponents[obj.Flag] = { object = obj, setter = obj.Set }
	end
	apply(obj.Value, true)
	return obj
end
function Section:Dropdown(cfg)
	cfg = cfg or {}
	local multi = cfg.Multi == true
	local searchable = cfg.Searchable == true and #(cfg.Options or {}) > 6
	local row = self:_row(34, cfg.Flag)
	self:_title(row, cfg, 120)
	local valueLabel = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -30, 0.5, 0),
		Size = UDim2.new(0, 110, 1, 0),
		Text = "",
		TextColor3 = Theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row.Header,
	})
	Util.font(valueLabel, "Medium")
	local arrowHolder = Util.create("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Parent = row.Header,
	})
	local arrow = Icons.new(arrowHolder, "chevron-down", {
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Muted,
	})
	local hit = Util.create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = row.Header,
	})
	local panel = Util.create("Frame", {
		Name = "Panel",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.SurfaceAlt,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Visible = false,
		Parent = row.Instance,
	})
	Util.corner(panel, 6)
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = panel,
	})
	local searchBox
	if searchable then
		local searchWrap = Util.create("Frame", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			LayoutOrder = 0,
			Parent = panel,
		})
		Util.corner(searchWrap, 5)
		Icons.new(searchWrap, "search", {
			Size = UDim2.fromOffset(13, 13),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = Theme.Muted,
		})
		searchBox = Util.create("TextBox", {
			Position = UDim2.new(0, 27, 0, 0),
			Size = UDim2.new(1, -35, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			PlaceholderText = cfg.SearchPlaceholder or "搜索...",
			PlaceholderColor3 = Theme.Muted,
			TextColor3 = Theme.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			Parent = searchWrap,
		})
		Util.font(searchBox, "Regular")
	end
	local listHolder = Util.create("Frame", {
		Name = "List",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = panel,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = listHolder,
	})
	local obj = { Flag = cfg.Flag, Options = {} }
	local optionButtons = {}
	local selected = {}
	local expanded = false
	local order = 0
	local window = self.Window
	local function getDisplayText()
		local names = {}
		for _, option in ipairs(obj.Options) do
			if selected[option] then
				table.insert(names, option)
			end
		end
		if #names == 0 then
			return cfg.Placeholder or (multi and "未选择" or "请选择")
		end
		if multi then
			if #names <= 2 then
				return table.concat(names, ", ")
			end
			return names[1] .. " +" .. (#names - 1)
		end
		return names[1]
	end
	local function refreshDisplay()
		valueLabel.Text = getDisplayText()
		for value, entry in pairs(optionButtons) do
			local on = selected[value] == true
			entry.Check:setVisible(on)
			Util.tween(entry.Label, 0.1, { TextColor3 = on and Theme.Text or Theme.SubText })
		end
	end
	local function computeValue()
		if multi then
			local result = {}
			for _, option in ipairs(obj.Options) do
				if selected[option] then
					table.insert(result, option)
				end
			end
			return result
		end
		for _, option in ipairs(obj.Options) do
			if selected[option] then
				return option
			end
		end
		return nil
	end
	local function fire()
		local result = computeValue()
		obj.Value = result
		window:_writeFlag(obj.Flag, result)
		if cfg.Callback then
			task.spawn(cfg.Callback, result)
		end
	end
	local function buildOption(value)
		order += 1
		local btn = Util.create("TextButton", {
			Name = "Opt_" .. tostring(value),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Theme.SurfaceHover,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			Parent = listHolder,
		})
		Util.corner(btn, 4)
		local text = Util.create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 8, 0, 0),
			Size = UDim2.new(1, -30, 1, 0),
			Text = tostring(value),
			TextColor3 = Theme.SubText,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = btn,
		})
		Util.font(text, "Regular")
		local check = Icons.new(btn, "check", {
			Size = UDim2.fromOffset(13, 13),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Color = Theme.Accent,
			Visible = false,
		})
		btn.MouseEnter:Connect(function()
			Util.tween(btn, 0.1, { BackgroundTransparency = 0.6 })
		end)
		btn.MouseLeave:Connect(function()
			Util.tween(btn, 0.1, { BackgroundTransparency = 1 })
		end)
		btn.MouseButton1Click:Connect(function()
			if multi then
				selected[value] = not selected[value] or nil
			else
				selected = {}
				selected[value] = true
			end
			refreshDisplay()
			fire()
			if not multi and cfg.CloseOnSelect ~= false then
				obj.SetExpanded(false)
			end
		end)
		optionButtons[value] = { Button = btn, Label = text, Check = check }
		return btn
	end
	function obj:SetOptions(options, keepSelection, silent)
		obj.Options = {}
		for _, v in ipairs(options or {}) do
			table.insert(obj.Options, v)
		end
		if not keepSelection then
			selected = {}
		else
			local filtered = {}
			for _, v in ipairs(obj.Options) do
				if selected[v] then
					filtered[v] = true
				end
			end
			selected = filtered
		end
		for _, entry in pairs(optionButtons) do
			entry.Button:Destroy()
		end
		optionButtons = {}
		order = searchable and 1 or 0
		for _, v in ipairs(obj.Options) do
			buildOption(v)
		end
		refreshDisplay()
		if silent then
			obj.Value = computeValue()
			window:_writeFlag(obj.Flag, obj.Value)
		else
			fire()
		end
	end
	function obj:SetExpanded(state)
		if expanded == state then
			return
		end
		expanded = state
		if state then
			panel.Visible = true
			panel.Size = UDim2.new(1, 0, 0, 0)
			panel.BackgroundTransparency = 1
			Util.tween(panel, 0.16, { BackgroundTransparency = 0.15 })
			Util.tween(arrowHolder, 0.2, { Rotation = 180 })
		else
			panel.Visible = false
			Util.tween(arrowHolder, 0.2, { Rotation = 0 })
		end
	end
	function obj:Get()
		return obj.Value
	end
	function obj:Set(value, silent)
		selected = {}
		if multi then
			for _, v in ipairs(value or {}) do
				selected[v] = true
			end
		elseif value ~= nil then
			selected[value] = true
		end
		refreshDisplay()
		if silent then
			obj.Value = value
			window:_writeFlag(obj.Flag, value)
		else
			fire()
		end
	end
	function obj:SetText(text)
		row.TitleLabel.Text = text
	end
	function obj:Destroy()
		row:Destroy()
	end
	hit.MouseButton1Click:Connect(function()
		obj:SetExpanded(not expanded)
	end)
	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local query = searchBox.Text:lower()
			for value, entry in pairs(optionButtons) do
				entry.Button.Visible = (query == "") or (tostring(value):lower():find(query, 1, true) ~= nil)
			end
		end)
	end
	obj.Options = {}
	obj.Value = nil
	obj:SetOptions(cfg.Options or {}, false, true)
	if cfg.Default ~= nil then
		obj:Set(cfg.Default, true)
	else
		refreshDisplay()
	end
	if obj.Flag then
		self.Window._flagComponents[obj.Flag] = { object = obj, setter = obj.Set }
	end
	return obj
end
function Section:Input(cfg)
	cfg = cfg or {}
	local row = self:_row(34, cfg.Flag)
	self:_title(row, cfg, cfg.Width or 160)
	local box = Util.create("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, cfg.Width or 150, 0, 26),
		BackgroundColor3 = Theme.SurfaceAlt,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = row.Header,
	})
	Util.corner(box, 6)
	local boxStroke = Util.stroke(box, Theme.Stroke, 1, 0.2)
	local defaultValue = cfg.Default
	if defaultValue == nil then
		defaultValue = cfg.Numeric and 0 or ""
	end
	local textbox = Util.create("TextBox", {
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(1, -16, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(defaultValue),
		PlaceholderText = cfg.Placeholder or "输入...",
		PlaceholderColor3 = Theme.Muted,
		TextColor3 = Theme.Text,
		TextSize = 12,
		TextXAlignment = cfg.Numeric and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = box,
	})
	Util.font(textbox, "Regular")
	local obj = { Value = defaultValue, Flag = cfg.Flag }
	local applying = false
	local function parse(text)
		if cfg.Numeric then
			local num = tonumber(text)
			if num == nil then
				return cfg.Default or 0
			end
			return num
		end
		return text
	end
	local function commit()
		if applying then
			return
		end
		local value = parse(textbox.Text)
		obj.Value = value
		self.Window:_writeFlag(obj.Flag, value)
		if cfg.Callback then
			task.spawn(cfg.Callback, value)
		end
	end
	textbox.Focused:Connect(function()
		Util.tween(boxStroke, 0.12, { Color = Theme.Accent, Transparency = 0 })
	end)
	textbox.FocusLost:Connect(function()
		Util.tween(boxStroke, 0.12, { Color = Theme.Stroke, Transparency = 0.2 })
		commit()
	end)
	textbox:GetPropertyChangedSignal("Text"):Connect(function()
		if cfg.OnChange and not applying then
			task.spawn(cfg.OnChange, parse(textbox.Text))
		end
	end)
	obj.Get = function()
		return obj.Value
	end
	obj.Set = function(_, value, silent)
		applying = true
		obj.Value = value
		textbox.Text = value ~= nil and tostring(value) or ""
		applying = false
		self.Window:_writeFlag(obj.Flag, value)
		if not silent and cfg.Callback then
			task.spawn(cfg.Callback, value)
		end
	end
	obj.SetText = function(_, text)
		row.TitleLabel.Text = text
	end
	obj.Destroy = function()
		row:Destroy()
	end
	if obj.Flag then
		self.Window._flagComponents[obj.Flag] = { object = obj, setter = obj.Set }
		self.Window:_writeFlag(obj.Flag, obj.Value)
	end
	return obj
end
function Section:Keybind(cfg)
	cfg = cfg or {}
	local mode = cfg.Mode or "Toggle"
	local row = self:_row(34, cfg.Flag)
	self:_title(row, cfg, 120)
	local btn = Util.create("TextButton", {
		Name = "KeyBtn",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, cfg.Width or 100, 0, 26),
		BackgroundColor3 = Theme.SurfaceAlt,
		BackgroundTransparency = 0.1,
		Text = "",
		AutoButtonColor = false,
		Parent = row.Header,
	})
	Util.corner(btn, 6)
	Util.stroke(btn, Theme.Stroke, 1, 0.2)
	local keyLabel = Util.create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "未绑定",
		TextColor3 = Theme.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = btn,
	})
	Util.font(keyLabel, "Medium")
	local obj = {
		Value = cfg.Default,
		Flag = cfg.Flag,
		Mode = mode,
		KeyName = nil,
		Held = false,
	}
	local listening = false
	local inputConn
	local function keyToName(key)
		if typeof(key) == "EnumItem" then
			if key.EnumType == Enum.KeyCode then
				return key.Name
			elseif key.EnumType == Enum.UserInputType then
				return key.Name
			end
		end
		return tostring(key)
	end
	local function nameToKey(name)
		if not name then
			return nil
		end
		local ok, key = pcall(function()
			return Enum.KeyCode[name]
		end)
		if ok and key then
			return key
		end
		local ok2, inputType = pcall(function()
			return Enum.UserInputType[name]
		end)
		if ok2 and inputType then
			return inputType
		end
		return nil
	end
	local function display()
		if inputConn then
			inputConn:Disconnect()
			inputConn = nil
		end
		local name = keyToName(obj.Value)
		keyLabel.Text = (obj.Value == nil) and "未绑定" or name
		keyLabel.TextColor3 = (obj.Value == nil) and Theme.Muted or Theme.Text
		if obj.Value and mode == "Hold" then
			inputConn = UserInputService.InputBegan:Connect(function(input, processed)
				if processed then
					return
				end
				if input.KeyCode == obj.Value and not obj.Held then
					obj.Held = true
					Util.tween(btn, 0.1, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.2 })
					if cfg.Callback then
						task.spawn(cfg.Callback, true)
					end
				end
			end)
			local conn2 = UserInputService.InputEnded:Connect(function(input)
				if input.KeyCode == obj.Value and obj.Held then
					obj.Held = false
					Util.tween(btn, 0.1, { BackgroundColor3 = Theme.SurfaceAlt, BackgroundTransparency = 0.1 })
					if cfg.Callback then
						task.spawn(cfg.Callback, false)
					end
				end
			end)
			local first = inputConn
			inputConn = {
				Disconnect = function()
					first:Disconnect()
					conn2:Disconnect()
				end,
			}
		elseif obj.Value and mode == "Toggle" then
			inputConn = UserInputService.InputBegan:Connect(function(input, processed)
				if processed then
					return
				end
				if UserInputService:GetFocusedTextBox() then
					return
				end
				if input.KeyCode == obj.Value then
					obj.Held = not obj.Held
					Util.tween(btn, 0.1, {
						BackgroundColor3 = obj.Held and Theme.Accent or Theme.SurfaceAlt,
						BackgroundTransparency = obj.Held and 0.2 or 0.1,
					})
					if cfg.Callback then
						task.spawn(cfg.Callback, obj.Held)
					end
				end
			end)
		end
	end
	obj.Get = function()
		return obj.Value
	end
	obj.Set = function(_, value, silent)
		obj.Value = value
		display()
		self.Window:_writeFlag(obj.Flag, value)
	end
	obj.SetText = function(_, text)
		row.TitleLabel.Text = text
	end
	obj.Destroy = function()
		if inputConn then
			inputConn:Disconnect()
		end
		row:Destroy()
	end
	btn.MouseButton1Click:Connect(function()
		if listening then
			return
		end
		listening = true
		keyLabel.Text = "按下按键..."
		keyLabel.TextColor3 = Theme.Accent
		local connBegan, connEnded
		connBegan = UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.Escape then
				listening = false
				connBegan:Disconnect()
				connEnded:Disconnect()
				display()
				return
			end
			if input.UserInputType == Enum.UserInputType.Keyboard
				or input.UserInputType == Enum.UserInputType.MouseButton then
				if processed then
					return
				end
				obj.Value = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or input.UserInputType
				listening = false
				connBegan:Disconnect()
				connEnded:Disconnect()
				self.Window:_writeFlag(obj.Flag, obj.Value)
				display()
				if cfg.Callback and mode == "Always" then
					task.spawn(cfg.Callback, obj.Value)
				end
			end
		end)
		connEnded = UserInputService.InputEnded:Connect(function() end)
	end)
	if mode == "Always" and obj.Value then
		table.insert(self.Window._connections, UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == obj.Value and cfg.Callback then
				task.spawn(cfg.Callback)
			end
		end))
	end
	display()
	if obj.Flag then
		self.Window._flagComponents[obj.Flag] = { object = obj, setter = obj.Set }
		self.Window:_writeFlag(obj.Flag, obj.Value)
	end
	self.Window:OnAccent(function(color)
		if obj.Held then
			btn.BackgroundColor3 = color
		end
	end)
	return obj
end
function Section:ColorPicker(cfg)
	cfg = cfg or {}
	local row = self:_row(34, cfg.Flag)
	self:_title(row, cfg, 60)
	local swatch = Util.create("TextButton", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(52, 22),
		BackgroundColor3 = cfg.Default or Theme.Accent,
		Text = "",
		AutoButtonColor = false,
		Parent = row.Header,
	})
	Util.corner(swatch, 5)
	Util.stroke(swatch, Theme.Stroke, 1, 0.1)
	local panel = Util.create("Frame", {
		Name = "Panel",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.SurfaceAlt,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Visible = false,
		Parent = row.Instance,
	})
	Util.corner(panel, 6)
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = panel,
	})
	local obj = {
		Value = cfg.Default or Theme.Accent,
		Flag = cfg.Flag,
		_H = 0, _S = 0, _V = 0,
	}
	local h, s, v = Color3.toHSV(obj.Value)
	obj._H, obj._S, obj._V = h, s, v
	local svArea = Util.create("Frame", {
		Name = "SV",
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = obj.Value,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = panel,
	})
	Util.corner(svArea, 5)
	local whiteOverlay = Util.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = svArea,
	})
	Util.corner(whiteOverlay, 5)
	Util.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 0,
		Parent = whiteOverlay,
	})
	local blackOverlay = Util.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = svArea,
	})
	Util.corner(blackOverlay, 5)
	Util.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Rotation = 90,
		Parent = blackOverlay,
	})
	local svCursor = Util.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = svArea,
	})
	Util.corner(svCursor, 6)
	Util.stroke(svCursor, Color3.new(1, 1, 1), 2, 0)
	local svHit = Util.create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 4,
		Parent = svArea,
	})
	local hueWrap = Util.create("Frame", {
		Name = "Hue",
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = panel,
	})
	Util.corner(hueWrap, 4)
	Util.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
		}),
		Parent = hueWrap,
	})
	local hueCursor = Util.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(6, 18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = hueWrap,
	})
	Util.corner(hueCursor, 3)
	Util.stroke(hueCursor, Color3.fromRGB(20, 20, 24), 1, 0)
	local hueHit = Util.create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 4,
		Parent = hueWrap,
	})
	local hexBox = Util.create("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Parent = panel,
	})
	Util.corner(hexBox, 5)
	local hexInput = Util.create("TextBox", {
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(1, -16, 1, 0),
		BackgroundTransparency = 1,
		Text = "#FFFFFF",
		PlaceholderText = "#RRGGBB",
		PlaceholderColor3 = Theme.Muted,
		TextColor3 = Theme.Text,
		TextSize = 12,
		ClearTextOnFocus = false,
		Parent = hexBox,
	})
	Util.font(hexInput, "Regular")
	local function toHex(color)
		return string.format("#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5))
	end
	local function fromHex(text)
		local r, g, b = text:match("^#?(%x%x)(%x%x)(%x%x)$")
		if r then
			return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
		end
		return nil
	end
	local updatingText = false
	local function redraw(silent)
		local color = Color3.fromHSV(obj._H, obj._S, obj._V)
		obj.Value = color
		svArea.BackgroundColor3 = Color3.fromHSV(obj._H, 1, 1)
		svCursor.Position = UDim2.new(obj._S, 0, 1 - obj._V, 0)
		hueCursor.Position = UDim2.new(obj._H, 0, 0.5, 0)
		swatch.BackgroundColor3 = color
		if not updatingText then
			updatingText = true
			hexInput.Text = toHex(color)
			updatingText = false
		end
		self.Window:_writeFlag(obj.Flag, color)
		if not silent and cfg.Callback then
			task.spawn(cfg.Callback, color)
		end
	end
	local draggingSV, draggingHue = false, false
	local function updateSV(input)
		local px, py = Util.inputX(input), Util.inputY(input)
		local pos = svArea.AbsolutePosition
		local size = svArea.AbsoluteSize
		obj._S = math.clamp((px - pos.X) / math.max(size.X, 1), 0, 1)
		obj._V = math.clamp(1 - (py - pos.Y) / math.max(size.Y, 1), 0, 1)
		redraw(false)
	end
	local function updateHue(input)
		local px = Util.inputX(input)
		local pos = hueWrap.AbsolutePosition
		local size = hueWrap.AbsoluteSize
		obj._H = math.clamp((px - pos.X) / math.max(size.X, 1), 0, 1)
		redraw(false)
	end
	local scroller = Util.findScroller(svArea)
	local pendingHue = false
	local session = Util.dragSession(self.Window._connections, {
		start = function(input)
			if scroller then
				scroller.ScrollingEnabled = false
			end
			if pendingHue then
				draggingHue = true
				updateHue(input)
			else
				draggingSV = true
				updateSV(input)
			end
		end,
		move = function(input)
			if draggingSV then
				updateSV(input)
			elseif draggingHue then
				updateHue(input)
			end
		end,
		finish = function()
			if scroller then
				scroller.ScrollingEnabled = true
			end
			draggingSV, draggingHue = false, false
		end,
	})
	svHit.InputBegan:Connect(function(input)
		pendingHue = false
		session.begin(input)
	end)
	hueHit.InputBegan:Connect(function(input)
		pendingHue = true
		session.begin(input)
	end)
	hexInput.FocusLost:Connect(function()
		local color = fromHex(hexInput.Text)
		if color then
			obj:Set(color)
		else
			redraw(true)
		end
	end)
	hexInput:GetPropertyChangedSignal("Text"):Connect(function()
		if updatingText then
			return
		end
		local color = fromHex(hexInput.Text)
		if color then
			obj:Set(color, true)
		end
	end)
	local expanded = false
	swatch.MouseButton1Click:Connect(function()
		expanded = not expanded
		panel.Visible = expanded
	end)
	obj.Get = function()
		return obj.Value
	end
	obj.Set = function(_, color, silent)
		if typeof(color) == "table" then
			color = Color3.new(color[1] or color.R or 0, color[2] or color.G or 0, color[3] or color.B or 0)
		end
		obj._H, obj._S, obj._V = Color3.toHSV(color)
		redraw(silent)
	end
	obj.SetText = function(_, text)
		row.TitleLabel.Text = text
	end
	obj.Destroy = function()
		row:Destroy()
	end
	if obj.Flag then
		self.Window._flagComponents[obj.Flag] = { object = obj, setter = obj.Set }
	end
	redraw(true)
	return obj
end
function Section:Label(cfg)
	cfg = cfg or {}
	local row = self:_row(cfg.Height or 24, cfg.Flag)
	local x = 8
	if cfg.Icon then
		Icons.new(row.Header, cfg.Icon, {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = cfg.IconColor or Theme.SubText,
		})
		x = 28
	end
	local label = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, x, 0, 0),
		Size = UDim2.new(1, -(x + 8), 1, 0),
		Text = cfg.Name or cfg.Text or "",
		TextColor3 = cfg.Color or Theme.Text,
		TextSize = cfg.TextSize or 13,
		TextXAlignment = cfg.Align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = cfg.RichText == true,
		Parent = row.Header,
	})
	Util.font(label, cfg.Weight or "Medium")
	local obj = {}
	obj.SetText = function(_, text)
		label.Text = text
	end
	obj.SetColor = function(_, color)
		label.TextColor3 = color
	end
	obj.Destroy = function()
		row:Destroy()
	end
	return obj
end
function Section:Paragraph(cfg)
	cfg = cfg or {}
	local text = cfg.Content or cfg.Text or ""
	local row = self:_row(0, cfg.Flag)
	row.Header.AutomaticSize = Enum.AutomaticSize.Y
	row.Header.Size = UDim2.new(1, 0, 0, 0)
	local label = Util.create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 4),
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextColor3 = cfg.Color or Theme.SubText,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = cfg.RichText == true,
		Parent = row.Header,
	})
	Util.font(label, "Regular")
	Util.create("UIPadding", {
		PaddingBottom = UDim.new(0, 4),
		Parent = row.Header,
	})
	local obj = {}
	obj.SetText = function(_, t)
		label.Text = t
	end
	obj.Destroy = function()
		row:Destroy()
	end
	return obj
end
function Section:Divider(cfg)
	cfg = cfg or {}
	local row = self:_row(cfg.Height or 8, nil)
	local line = Util.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = row.Header,
	})
	return {
		Destroy = function()
			row:Destroy()
		end,
	}
end
function Section:Space(cfg)
	cfg = cfg or {}
	self._order += 1
	local spacer = Util.create("Frame", {
		Size = UDim2.new(1, 0, 0, cfg.Height or 6),
		BackgroundTransparency = 1,
		LayoutOrder = self._order,
		Parent = self.ContentInner,
	})
	return {
		Destroy = function()
			spacer:Destroy()
		end,
	}
end
local TYPE_STYLE = {
	info = { Icon = "info", Color = Color3.fromRGB(88, 140, 255) },
	success = { Icon = "circle-check", Color = Theme.Success },
	warning = { Icon = "alert", Color = Theme.Warning },
	error = { Icon = "circle-x", Color = Theme.Error },
}
local EXIT_TIME = 0.2
local Notification = {}
Notification.__index = Notification
function Notification:_paintProgress()
	if self._duration <= 0 then
		self._progress.Visible = false
		return
	end
	self._progress.Visible = true
	local remain = math.max(self._duration - self._elapsed, 0)
	self._fill.Size = UDim2.new(remain / self._duration, 0, 1, 0)
end
function Notification:_step(dt)
	if self._paused or self._dismissed or self._duration <= 0 then
		return
	end
	self._elapsed = self._elapsed + dt
	self:_paintProgress()
	if self._elapsed >= self._duration then
		self:dismiss()
	end
end
function Notification:_setContent(text)
	local has = text ~= nil and text ~= ""
	self._content.Visible = has
	self._content.Text = has and tostring(text) or ""
	self._content.Size = has and UDim2.new(1, -26, 0, 0) or UDim2.new(0, 0, 0, 0)
end
function Notification:_applyStyle()
	self._icon:set(self._iconName)
	self._icon:setColor(self._accent)
	self._fill.BackgroundColor3 = self._accent
end
function Notification:update(cfg)
	if self._dismissed then
		return self
	end
	cfg = cfg or {}
	if cfg.Type and TYPE_STYLE[cfg.Type] then
		self._accent = TYPE_STYLE[cfg.Type].Color
		self._iconName = cfg.Icon or TYPE_STYLE[cfg.Type].Icon
	end
	if cfg.Icon then
		self._iconName = cfg.Icon
	end
	if cfg.Color then
		self._accent = cfg.Color
	end
	if cfg.Title ~= nil then
		self._title.Text = tostring(cfg.Title)
	end
	if cfg.Content ~= nil then
		self:_setContent(cfg.Content)
	end
	if cfg.Duration ~= nil then
		self._duration = cfg.Duration
	end
	if cfg.OnClick ~= nil then
		self._onClick = cfg.OnClick
	end
	if cfg.Background ~= nil then
		self:_setBackground(cfg.Background, cfg)
	end
	if cfg.Sound then
		self._soundSource = cfg.Sound
		self._soundVolume = cfg.SoundVolume
		self:_playSound(cfg.Sound, cfg.SoundVolume)
	elseif self._window and type(self._window._sounds) == "table" then
		local src = (self.Type == "error" and self._window._sounds.Error)
			or self._window._sounds.Notify
		if src and src ~= self._soundSource then
			self._soundSource = src
			self:_playSound(src, cfg.SoundVolume)
		end
	end
	self._elapsed = 0
	self:_applyStyle()
	self:_paintProgress()
	self._card.BackgroundColor3 = Theme.SurfaceAlt
	Util.tween(self._card, 0.6, { BackgroundColor3 = Theme.Surface })
	return self
end
function Notification:dismiss()
	if self._dismissed then
		return
	end
	self._dismissed = true
	local window = self._window
	local list = window._notifications
	for i = #list, 1, -1 do
		if list[i] == self then
			table.remove(list, i)
		end
	end
	if self._id ~= nil and window._notifyById[self._id] == self then
		window._notifyById[self._id] = nil
	end
	local height = self._card.AbsoluteSize.Y
	self._card.AutomaticSize = Enum.AutomaticSize.None
	self._card.Size = UDim2.new(1, 0, 0, height)
	Util.tween(self._card, EXIT_TIME, { Position = UDim2.new(0, 40, 0, 0) },
		Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Util.tween(self._card, EXIT_TIME, { Size = UDim2.new(1, 0, 0, 0) })
	task.delay(EXIT_TIME + 0.02, function()
		self._holder:Destroy()
	end)
end
function Notification:_setBackground(source, cfg)
	cfg = cfg or {}
	if source == nil or source == false then
		if self._background then
			self._background.Visible = false
		end
		return
	end
	if not self._background then
		self._background = Util.create("ImageLabel", {
			Name = "Background",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 0,
			Parent = self._card,
		})
	end
	local image = self._background
	local resolved = Util.customAsset(source)
	if not resolved then
		warn("[XHM] 通知背景图加载失败: " .. tostring(source))
		image.Visible = false
		return
	end
	image.Image = resolved
	image.ImageColor3 = cfg.BackgroundColor or Color3.fromRGB(255, 255, 255)
	image.ImageTransparency = cfg.BackgroundTransparency or 0.35
	image.ScaleType = (cfg.BackgroundFit == "fit") and Enum.ScaleType.Fit or Enum.ScaleType.Crop
	image.Visible = true
	self._backgroundSource = source
end
function Notification:_playSound(source, volume)
	if self._dismissed then
		return
	end
	local resolved = Util.customAsset(source)
	if not resolved then
		warn("[XHM] 通知音效加载失败: " .. tostring(source))
		return
	end
	local screen = self._window.Screen
	if not screen then
		return
	end
	local sound = Util.create("Sound", {
		Name = "NotifySound",
		SoundId = resolved,
		Volume = volume or 0.5,
		Parent = screen,
	})
	sound:Play()
	local function cleanup()
		if sound.Parent then
			sound:Destroy()
		end
	end
	sound.Ended:Connect(cleanup)
	task.delay(20, cleanup)
	return sound
end
function Notification:isDismissed()
	return self._dismissed
end
function XHM:_notifyTick(dt)
	local list = self._notifications
	for i = #list, 1, -1 do
		if not list[i]._dismissed then
			list[i]:_step(dt)
		end
	end
	if #list == 0 and self._notifyConn then
		self._notifyConn:Disconnect()
		self._notifyConn = nil
	end
end
function XHM:_ensureNotifyTick()
	if self._notifyConn then
		return
	end
	self._notifyConn = RunService.Heartbeat:Connect(function(dt)
		self:_notifyTick(dt)
	end)
end
function XHM:_createNotification(cfg)
	local style = TYPE_STYLE[cfg.Type or "info"] or TYPE_STYLE.info
	local accent = cfg.Color or style.Color
	local iconName = cfg.Icon or style.Icon
	local duration = cfg.Duration or 4
	self._notifyOrder += 1
	local holder = Util.create("Frame", {
		Name = "Notify",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self._notifyOrder,
		Parent = self._notifyHolder,
	})
	local card = Util.create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 40, 0, 0),
		Parent = holder,
	})
	Util.corner(card, 8)
	Util.stroke(card, Theme.Stroke, 1, 0.75)
	card.ClipsDescendants = true
	Util.shadowTwin(card, holder, {
		Blur = XHM.Shadow.Card.Blur,
		Transparency = XHM.Shadow.Card.Transparency,
		Drop = XHM.Shadow.Card.Drop,
		Spread = XHM.Shadow.Card.Spread,
		Radius = XHM.Shadow.Card.Radius,
	}, self._connections)
	local inner = Util.create("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	})
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = inner,
	})
	local icon = Icons.new(inner, iconName, {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(0, 0, 0, 1),
		Color = accent,
	})
	local title = Util.create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 26, 0, 0),
		Size = UDim2.new(1, -26, 0, 18),
		Text = cfg.Title and tostring(cfg.Title) or "提示",
		TextColor3 = Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = inner,
	})
	Util.font(title, "Medium")
	local content = Util.create("TextLabel", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 26, 0, 20),
		Size = UDim2.new(0, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextColor3 = Theme.SubText,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = inner,
	})
	Util.font(content, "Regular")
	local progress = Util.create("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -12, 1, 10),
		Size = UDim2.new(1, 24, 0, 2),
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = inner,
	})
	local fill = Util.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = progress,
	})
	local hit = Util.create("TextButton", {
		Name = "Hit",
		Position = UDim2.new(0, -12, 0, -10),
		Size = UDim2.new(1, 24, 1, 20),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
		Parent = inner,
	})
	local self_ = self
	local notification = setmetatable({
		Instance = holder,
		Card = card,
		Id = cfg.Id,
		_window = self_,
		_holder = holder,
		_card = card,
		_icon = icon,
		_title = title,
		_content = content,
		_progress = progress,
		_fill = fill,
		_iconName = iconName,
		_accent = accent,
		_duration = duration,
		_elapsed = 0,
		_paused = false,
		_dismissed = false,
		_onClick = cfg.OnClick,
	}, Notification)
	notification:_setContent(cfg.Content)
	notification:_paintProgress()
	notification:_setBackground(cfg.Background, cfg)
	local soundSource = cfg.Sound
	if not soundSource and type(self._sounds) == "table" then
		soundSource = (cfg.Type == "error" and self._sounds.Error) or self._sounds.Notify
	end
	if soundSource then
		notification._soundSource = soundSource
		notification._soundVolume = cfg.SoundVolume
		notification:_playSound(soundSource, cfg.SoundVolume)
	end
	hit.MouseButton1Click:Connect(function()
		if notification._dismissed then
			return
		end
		if notification._onClick then
			task.spawn(notification._onClick)
		end
		notification:dismiss()
	end)
	hit.MouseEnter:Connect(function()
		notification._paused = true
	end)
	hit.MouseLeave:Connect(function()
		notification._paused = false
	end)
	Util.tween(card, 0.28, { Position = UDim2.new(0, 0, 0, 0) },
		Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	return notification
end
function XHM:Notify(cfg)
	if type(cfg) == "string" then
		cfg = { Title = cfg }
	end
	cfg = cfg or {}
	if self._destroyed then
		return nil
	end
	if cfg.Id ~= nil and self._notifyById[cfg.Id] then
		return self._notifyById[cfg.Id]:update(cfg)
	end
	local notification = self:_createNotification(cfg)
	table.insert(self._notifications, notification)
	if cfg.Id ~= nil then
		self._notifyById[cfg.Id] = notification
	end
	local limit = self.Config.MaxNotifications or 4
	while #self._notifications > limit do
		local oldest = self._notifications[1]
		if oldest == notification then
			break
		end
		oldest:dismiss()
	end
	self:_ensureNotifyTick()
	return notification
end
function XHM:DismissNotification(id)
	local notification = self._notifyById[id]
	if not notification then
		return false
	end
	notification:dismiss()
	return true
end
function XHM:ClearNotifications()
	for i = #self._notifications, 1, -1 do
		self._notifications[i]:dismiss()
	end
end
function XHM:NotificationCount()
	return #self._notifications
end
local function serializeValue(value)
	if typeof(value) == "Color3" then
		return { __type = "Color3", R = value.R, G = value.G, B = value.B }
	end
	return value
end
local function deserializeValue(value)
	if type(value) == "table" and value.__type == "Color3" then
		return Color3.new(value.R, value.G, value.B)
	end
	return value
end
function XHM:GetFlag(flag)
	return self.Flags[flag]
end
function XHM:_writeFlag(flag, value)
	if flag == nil then
		return
	end
	local old = self.Flags[flag]
	self.Flags[flag] = value
	if old ~= value then
		for _, cb in ipairs(self._flagListeners[flag] or {}) do
			task.spawn(cb, value, old)
		end
	end
end
function XHM:SetFlag(flag, value, silent)
	local entry = self._flagComponents[flag]
	if entry then
		entry.setter(entry.object, value, true)
	else
		self:_writeFlag(flag, value)
	end
end
function XHM:OnFlagChanged(flag, callback)
	self._flagListeners[flag] = self._flagListeners[flag] or {}
	table.insert(self._flagListeners[flag], callback)
end
function XHM:GetConfigData()
	local out = {}
	for flag, value in pairs(self.Flags) do
		if value ~= nil then
			out[flag] = serializeValue(value)
		end
	end
	return out
end
function XHM:ApplyConfigData(data)
	for flag, value in pairs(data or {}) do
		self:SetFlag(flag, deserializeValue(value), true)
	end
end
function XHM:SaveConfig(path)
	local data = self:GetConfigData()
	local encoded = HttpService:JSONEncode(data)
	if Util.FS and path then
		local ok, err = pcall(Util.FS.write, path, encoded)
		if not ok then
			warn("[XHM] 配置保存失败: " .. tostring(err))
			return false
		end
		return true
	end
	return encoded
end
function XHM:LoadConfig(path)
	if Util.FS and path and (not Util.FS.exists or Util.FS.exists(path)) then
		local ok, content = pcall(Util.FS.read, path)
		if not ok then
			warn("[XHM] 配置读取失败: " .. tostring(content))
			return false
		end
		local ok2, data = pcall(HttpService.JSONDecode, HttpService, content)
		if not ok2 then
			warn("[XHM] 配置解析失败")
			return false
		end
		self:ApplyConfigData(data)
		return true
	end
	return false
end
function XHM:Confirm(cfg)
	cfg = cfg or {}
	local main = self.Main
	if not main or self._destroyed then
		return nil
	end
	if self._confirm then
		pcall(function()
			self._confirm:Destroy()
		end)
		self._confirm = nil
	end
	local overlay = Util.create("TextButton", {
		Name = "ConfirmOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 200,
		Parent = main,
	})
	local card = Util.create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.82, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		ZIndex = 201,
		Parent = overlay,
	})
	Util.corner(card, 10)
	Util.stroke(card, Theme.Stroke, 1, 0.15)
	Util.shadow(card, XHM.Shadow.Card)
	local cardScale = Util.create("UIScale", { Name = "FX", Scale = 0.85, Parent = card })
	local body = Util.create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 202,
		Parent = card,
	})
	Util.create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})
	Util.create("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		Parent = body,
	})
	local title = Util.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = cfg.Title or "确认操作",
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		LayoutOrder = 1,
		ZIndex = 202,
		Parent = body,
	})
	Util.font(title, "SemiBold")
	if cfg.Content then
		local content = Util.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = cfg.Content,
			TextColor3 = Theme.SubText,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 2,
			ZIndex = 202,
			Parent = body,
		})
		Util.font(content, "Regular")
	end
	local row = Util.create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 202,
		Parent = body,
	})
	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local accent = cfg.Danger and Theme.Error or Theme.Accent
	local function makeButton(text, order, isPrimary, onClick)
		local btn = Util.create("TextButton", {
			Name = "Btn_" .. text,
			Size = UDim2.fromOffset(isPrimary and 84 or 70, 32),
			BackgroundColor3 = isPrimary and accent or Theme.SurfaceAlt,
			BackgroundTransparency = isPrimary and 0.1 or 0.9,
			Text = text,
			TextColor3 = isPrimary and Color3.fromRGB(255, 255, 255) or Theme.Text,
			TextSize = 12,
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 203,
			Parent = row,
		})
		Util.corner(btn, 7)
		Util.font(btn, "Medium")
		local btnScale = Util.create("UIScale", { Name = "FX", Scale = 1, Parent = btn })
		btn.MouseEnter:Connect(function()
			Util.tween(btn, 0.14, {
				BackgroundTransparency = isPrimary and 0 or 0.75,
			})
			Util.tween(btnScale, 0.22, { Scale = 1.06 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
		btn.MouseLeave:Connect(function()
			Util.tween(btn, 0.16, {
				BackgroundTransparency = isPrimary and 0.1 or 0.9,
			})
			Util.tween(btnScale, 0.22, { Scale = 1 })
		end)
		btn.MouseButton1Down:Connect(function()
			Util.tween(btnScale, 0.08, { Scale = 0.9 })
		end)
		btn.MouseButton1Up:Connect(function()
			Util.tween(btnScale, 0.26, { Scale = 1.06 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
		btn.MouseButton1Click:Connect(function(...)
			self:PlaySound("Click")
			if onClick then
				onClick(...)
			end
		end)
		return btn
	end
	local closing = false
	local function dismiss(callback)
		if closing then
			return
		end
		closing = true
		if self._confirm == overlay then
			self._confirm = nil
		end
		Util.tween(overlay, 0.16, { BackgroundTransparency = 1 })
		Util.tween(card, 0.16, { BackgroundTransparency = 1 })
		Util.tween(cardScale, 0.16, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.18, function()
			overlay:Destroy()
			if callback then
				task.spawn(callback)
			end
		end)
	end
	makeButton(cfg.CancelText or "取消", 1, false, function()
		dismiss(cfg.OnCancel)
	end)
	makeButton(cfg.ConfirmText or "确定", 2, true, function()
		dismiss(cfg.OnConfirm)
	end)
	overlay.MouseButton1Click:Connect(function()
		dismiss(cfg.OnCancel)
	end)
	Util.tween(overlay, 0.2, { BackgroundTransparency = 0.45 })
	Util.tween(cardScale, 0.34, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	self._confirm = overlay
	return {
		Instance = overlay,
		Close = function()
			dismiss(nil)
		end,
	}
end
function XHM:RequestClose()
	if self._destroyed then
		return
	end
	if self.Config.ConfirmClose == false then
		self:Destroy()
		return
	end
	self:Confirm({
		Title = self.Config.ConfirmCloseTitle or "确认关闭",
		Content = self.Config.ConfirmCloseText or "关闭后需要重新执行脚本才能再次打开。",
		ConfirmText = self.Config.ConfirmText or "关闭",
		CancelText = self.Config.CancelText or "取消",
		Danger = true,
		OnConfirm = function()
			self:Destroy()
		end,
	})
end
function XHM:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, conn in ipairs(self._connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	self._connections = {}
	if self._notifyConn then
		pcall(function()
			self._notifyConn:Disconnect()
		end)
		self._notifyConn = nil
	end
	self._notifications = {}
	self._notifyById = {}
	self._confirm = nil
	Screens[self] = nil
	pcall(function()
		self.Screen:Destroy()
	end)
end
function XHM.Create(config)
	local window = XHM.new(config)
	local tab = window:Tab({ Name = (config and config.DefaultTab) or "Main", Icon = "house" })
	local section = window:_createSection(tab, { Name = "通用", Icon = "settings" })
	return window, tab, section
end
function XHM.Section(tab, cfg)
	return tab.Window:_createSection(tab, cfg)
end
return XHM
