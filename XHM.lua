--[[============================================================================
	XHM-NEW-UI · Roblox 现代化本地 UI 库（单文件版）
	版本: 1.0.0

	特性
	  · 现代化深色玻璃质感界面，圆角 / 描边 / 投影 / 平滑补间动画
	  · 内置 Lucide 图标集（真实线稿图标，默认开启）
	      来源：https://github.com/latte-soft/lucide-roblox (MIT) + https://lucide.dev (ISC)
	      退回字形：XHM.Icons.useLucide(false)
	  · 可插拔图标系统，支持外部引入图标（优先级从高到低）
	      1) Icons.set(name, ...)        单个覆盖
	      2) Icons.loadSheet(...)        自己的精灵图集
	      3) Icons.loadAssets(...)       name -> assetId 映射表
	      4) Icons.loadRects(...)        多图集 + 每图标矩形
	      5) 内置 Lucide / Unicode 字形兜底
	  · 完整组件：Button / Toggle / Slider / Dropdown(单选+多选+搜索) / Input
	    / Keybind(Toggle+Hold) / ColorPicker(HSV) / Label / Paragraph / Divider
	  · 通知系统（带进度条、悬停暂停）
	  · Flag 系统 + 配置存档（writefile/readfile，无则自动降级为内存）
	  · 拖动吸附、最小化、快捷键开关（默认 RightShift）

	用法
	  local XHM = loadstring(readfile("界面库.lua"))()   -- 或直接粘贴本文件
	  local win = XHM.new({ Title = "My Hub", Subtitle = "v1.0" })
	  local tab = win:Tab({ Name = "Main", Icon = "house" })
	  local sec = tab:Section({ Name = "General", Icon = "settings" })
	  sec:Toggle({ Name = "Enable", Default = true, Flag = "enabled", Callback = print })
	  win:Notify({ Title = "已加载", Content = "欢迎", Type = "success" })
============================================================================]]

--!nonstrict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LOCAL_PLAYER = Players.LocalPlayer

--============================================================================
-- 0. 工具层
--============================================================================

local Util = {}

-- 创建实例并批量赋值属性
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

--============================================================================
-- 投影（UIShadow）
--
-- Roblox 2026 起有了原生投影类 UIShadow：挂在父级上，画在父级**下面**，
-- 自动跟随父级的尺寸 / UICorner 圆角 / Rotation，而且它是 UIComponent 而不是
-- 子 GuiObject —— 所以**不会被父级的 ClipsDescendants 裁掉**（窗口和通知卡片
-- 都开了 ClipsDescendants，这一点很关键，早先那个手搓的假投影就是被裁成黑楔形的）。
--
-- 老客户端没有这个类，所以探测一次：不支持就跳过并 warn（回退路径不该报错）。
--============================================================================

local SHADOW_SUPPORT = nil      -- nil 表示还没探测过
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

-- 给一个 GuiObject 挂投影
-- opts: { Enabled, Blur, Transparency, Drop, Spread, Color }
--   Blur / Drop / Spread 单位是像素；Transparency 0=全黑 1=完全透明
--   Spread 给负数 = 阴影轮廓缩到目标内侧（圆角缺口处就不会糊一块黑）
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

-- 影子孪生帧：给"自己开了 ClipsDescendants"的目标做投影用。
--
-- 为什么需要它：`ClipsDescendants` 的裁剪区是**矩形**，而 UIShadow 虽然是 UIComponent、
-- 不是子 GuiObject，挂在目标身上时依然会被这块矩形咬掉 —— 结果就是阴影只在
-- 四个圆角缺口处露出一块**硬边黑块**（用户报的"突出的黑色遮罩"）。
--
-- 所以：在**不裁剪的父级**上放一个和目标同位置、同尺寸的透明帧，投影挂它，
-- 位置/尺寸/可见性跟着目标走。返回 (twin, shadow)。
-- connections 传窗口的 _connections，销毁时一起断开。
function Util.shadowTwin(target, parent, opts, connections)
	opts = opts or {}
	local twin = Util.create("Frame", {
		Name = "ShadowTwin",
		AnchorPoint = target.AnchorPoint,
		Position = target.Position,
		Size = target.Size,
		BackgroundTransparency = 1,
		ZIndex = math.max(0, (target.ZIndex or 1) - 1),   -- 必须在目标下面
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
	-- 双保险：目标高度常常是 AutomaticSize 算出来的，创建那一刻可能还是 0。
	-- AbsoluteSize 的信号在真机上会补一次，这里再排一次延迟同步（下一帧布局已算完）。
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

-- 字体：优先 FontFace（新 API），失败回退到 Enum.Font
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

-- 立即应用（跳过动画）
function Util.set(inst, props)
	for k, v in pairs(props) do
		inst[k] = v
	end
end

function Util.round(value, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(value * mult + 0.5) / mult
end

-- 通用 HTTP GET（兼容执行器 / HttpService）
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

-- 文件 IO（执行器环境；Studio/无权限时自动降级）
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

--============================================================================
-- 外部图片加载（靠执行器 API）
--
-- Roblox 的 ImageLabel 不能直接显示网络图片，必须先下载到本地文件，
-- 再用执行器的 getcustomasset / getsynasset 转成 rbxasset:// 才能用。
-- 支持的名字：
--     https://...        网络图片，下载后缓存
--     myfile.png         执行器工作目录里的本地文件
--     rbxassetid://123   原样返回
--============================================================================

Util.CustomAssets = {}   -- cacheKey -> rbxasset://...

-- 纯 Lua 短哈希，用来给缓存文件起名（不用 bit32，Lua 5.1 没有）
local function shortHash(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + str:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

-- 取执行器的「自定义资源」转换函数
local function getAssetConverter()
	return getcustomasset or getsynasset or (syn and syn.get_custom_asset)
end

-- 判断是不是 Roblox 自己的资源地址（这种不需要下载）
local function isNativeAsset(url)
	return url:match("^rbxasset") ~= nil
		or url:match("^rbxthumb") ~= nil
		or url:match("^rbxassetid") ~= nil
end

-- 图片 / 音频的常见扩展名，用来区分「本地文件路径」和「图标名」
local ASSET_EXTENSIONS = {
	png = true, jpg = true, jpeg = true, webp = true, tga = true, bmp = true, gif = true,
	ogg = true, mp3 = true, wav = true, flac = true,
}

--[[
	判断一个字符串是「外部资源」还是「图标名」：
	  · https://...        网络资源
	  · rbxasset://...     已经是 Roblox 资源
	  · logo.png / bg.jpg  本地文件（按扩展名认）
	图标位、通知背景图、提示音都靠这个决定要不要走 Util.customAsset ——
	所以任何图标位都能直接塞 URL，不用先注册。
]]
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

--[[
	把一个外部地址/本地路径转成 ImageLabel 能用的资源字符串。
	失败返回 nil（并 warn），不会抛错。
]]
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
		-- false 是「之前失败过」的负缓存，避免反复重试刷警告
		return cached or nil
	end

	local converter = getAssetConverter()
	local writeFn = (Util.FS and Util.FS.write) or writefile

	-- 本地文件：直接转换
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

	-- 网络图片：下载 -> 落地 -> 转换
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

-- 预加载（可选的，提前把图下好，避免第一次显示时空白）
function Util.preloadAsset(source, cacheKey)
	return Util.customAsset(source, cacheKey)
end

-- GUI 父级选择（执行器优先 gethui）
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

--============================================================================
-- 1. 图标系统（可插拔 Provider）
--============================================================================

local Icons = {}
Icons.__index = Icons
Icons.Version = "1.0.0"

-- 内置字形表：名称统一采用 Lucide 命名，方便日后替换为真实精灵图
local GLYPHS = {
	-- 导航 / 通用
	["house"] = "⌂", ["home"] = "⌂", ["settings"] = "⚙", ["search"] = "⌕",
	["user"] = "👤", ["users"] = "👥", ["menu"] = "☰", ["list"] = "☰",
	["chevron-down"] = "⌄", ["chevron-up"] = "⌃", ["chevron-right"] = "›", ["chevron-left"] = "‹",
	["x"] = "✕", ["check"] = "✓", ["plus"] = "＋", ["minus"] = "－",
	["more-vertical"] = "⋮", ["dot"] = "•", ["circle"] = "●", ["square"] = "■", ["triangle"] = "▲",
	-- 操作
	["trash"] = "🗑", ["pencil"] = "✎", ["edit"] = "✎", ["copy"] = "⧉", ["save"] = "💾",
	["download"] = "⬇", ["upload"] = "⬆", ["link"] = "🔗", ["external-link"] = "↗",
	["play"] = "▶", ["pause"] = "⏸", ["stop"] = "⏹", ["refresh"] = "⟳", ["power"] = "⏻",
	["maximize"] = "⛶", ["minimize"] = "—", ["wand"] = "🪄", ["filter"] = "⧩",
	-- 安全 / 状态
	["shield"] = "🛡", ["lock"] = "🔒", ["unlock"] = "🔓", ["key"] = "🔑",
	["eye"] = "👁", ["eye-off"] = "🙈", ["zap"] = "⚡", ["star"] = "★", ["heart"] = "♥",
	["bell"] = "🔔", ["flag"] = "⚑", ["info"] = "ⓘ", ["alert"] = "⚠",
	["circle-check"] = "✔", ["circle-x"] = "✖", ["circle-alert"] = "⚠", ["bug"] = "🐛",
	-- 内容
	["palette"] = "🎨", ["image"] = "🖼", ["file"] = "📄", ["folder"] = "📁",
	["terminal"] = "⌨", ["code"] = "⟨⟩", ["box"] = "📦", ["gift"] = "🎁",
	["globe"] = "🌐", ["wifi"] = "📶", ["cpu"] = "🖥", ["activity"] = "📈",
	["sliders"] = "🎚", ["gauge"] = "⏱", ["clock"] = "🕐", ["target"] = "🎯",
	["crosshair"] = "⊕", ["map-pin"] = "📍", ["layout"] = "▤", ["layers"] = "▤",
	-- 主题
	["sparkles"] = "✦", ["rocket"] = "🚀", ["sun"] = "☀", ["moon"] = "🌙",
	["gamepad"] = "🎮", ["volume"] = "🔊", ["camera"] = "📷", ["music"] = "🎵",
	["arrow-right"] = "→", ["arrow-left"] = "←", ["arrow-up"] = "↑", ["arrow-down"] = "↓",
}

--[[============================================================================
	Lucide 图标集（内置，默认启用）

	数据来源：https://github.com/latte-soft/lucide-roblox 的 lib/Icons.luau（MIT）
	图标本体：Lucide Icons（ISC） — https://lucide.dev
	图集资源：由 Latte Softworks 上传的公开图片 spritesheet-1 ~ spritesheet-9

	这里只收录 XHM 用得到的 87 个图标，取 48px 档（UI 里图标实际渲染 13~18px，
	48px 足够清晰，且只涉及 9 张图集而非 256px 档的 175 张）。

	格式：内部图标名 = { 图集资源ID, 宽, 高, X, Y }

	与 Lucide 官方名不同的 4 个（因为本库的图标名是 Lucide 新版命名）：
	    house   -> home            alert   -> triangle-alert
	    refresh -> refresh-cw      stop    -> square
============================================================================]]
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

-- 已加载的图标数据源（优先级从高到低）
local Overrides = {} -- name -> { kind, ... }  单个覆盖，最高优先级
local Sheet = nil    -- { image, cell = Vector2, icons = { name = {x=, y=} } }  用户加载的整张图集
local Assets = {}    -- name -> "rbxassetid://..."  用户加载的独立图标
local Rects = {}     -- name -> { id, w, h, x, y }  内置 Lucide 数据（低于用户来源）

-- 解析某个图标名，返回绘制描述
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

--[[
	把一个「图标名」解析成绘制描述。
	如果传进来的直接是图片地址（URL / rbxassetid / 本地文件），就当成图片用 ——
	所以任何图标位（组件的 Icon、通知的 Icon、悬浮球的 LauncherIcon…）都能直接塞外链，
	不需要先 Icons.set 注册。
]]
local rawResolve = Icons.resolve
function Icons.resolve(name)
	if type(name) == "string" and Util.isExternalAsset(name) then
		local asset = Util.customAsset(name)
		if asset then
			return { kind = "asset", image = asset }
		end
		-- 加载失败就退回字形，至少不会留一个空白
		return { kind = "glyph", text = GLYPHS["alert"] or "!" }
	end
	return rawResolve(name)
end

-- 手动注册单个图标。
--   Icons.set("myicon", "rbxassetid://123")            -- Roblox 资源
--   Icons.set("myicon", "https://a.com/i.png")         -- 执行器外链
--   Icons.set("myicon", "icons/my.png")                -- 执行器工作目录里的文件
--   Icons.set("myicon", "★")                           -- 字形
function Icons.set(name, source)
	if type(source) == "table" then
		Overrides[name] = source
	elseif type(source) == "string" and Util.isExternalAsset(source) then
		local asset = Util.customAsset(source)
		if not asset then
			-- 加载不了就别把图标位弄成空白，回退字形
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

-- 批量注册字形：{ name = "★" }
function Icons.setGlyphs(tbl)
	for k, v in pairs(tbl or {}) do
		if not GLYPHS[k] then
			GLYPHS[k] = v
		end
	end
	Icons.refresh()
end

-- 外部引入：name -> assetId 映射表
--   source 可以是 table，也可以是 JSON 文本 / URL
function Icons.loadAssets(source, opts)
	opts = opts or {}
	local data = source
	if type(source) == "string" then
		local text = source
		-- 看起来像 URL 就去拉取
		if source:match("^https?://") then
			text = Util.httpGet(source)
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, text)
		if not ok then
			error("[XHM] loadAssets 解析失败：" .. tostring(decoded))
		end
		data = decoded
	end
	-- 允许 { icons = {...} } 或直接 { name = id }
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

-- 外部引入：精灵图集
--   source: table 或 JSON 文本 / URL
--   manifest 结构：
--     {
--       "image": "rbxassetid://123456",
--       "cell": [64, 64],              -- 单格像素尺寸
--       "columns": 32,                 -- 每行格子数（当 icons 用 index 时使用）
--       "icons": { "house": {"x":0,"y":0}, "settings": 5 }   -- 支持 {x,y} 或索引
--     }
--   opts.image 可覆盖 manifest 中的图片
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

-- 批量注册「自带图集矩形的图标」——一个图标一张图、并指定其在图内的位置
--   data = { [name] = { 图集ID, 宽, 高, X, Y } }
-- 内置的 Lucide 数据就是这个格式，也可以用来挂自己的多图集图标
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
		-- 只保留这次传入的
		for name in pairs(Rects) do
			if data[name] == nil then
				Rects[name] = nil
			end
		end
	end
	Icons.refresh()
	return count
end

-- 从外部 URL / 本地文件加载单个图标（依赖执行器的 writefile + getcustomasset）
--   Icons.loadUrl("我的图标", "https://example.com/icon.png")
--   Icons.loadUrl("我的图标", "icons/my.png")   -- 执行器工作目录里的文件
function Icons.loadUrl(name, source)
	local asset = Util.customAsset(source)
	if not asset then
		return false
	end
	Overrides[name] = { kind = "asset", image = asset }
	Icons.refresh()
	return true
end

-- 开关内置 Lucide 图标集（默认开启）
--   Icons.useLucide(false) 会退回内置 Unicode 字形
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

-- 恢复默认字形库（会连 Lucide 一起清掉）
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

-- 已注册的图标名列表
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

-- 所有已创建的图标实例（弱引用数组，主题/资源变更时统一刷新）
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

-- 默认启用内置 Lucide 图标集。
-- 想退回 Unicode 字形（例如资源被限制加载）：XHM.Icons.useLucide(false)
Icons.useLucide(true)

--============================================================================
-- 2. 图标实例
--============================================================================

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

-- 创建图标实例
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

--============================================================================
-- 3. 主题
--============================================================================

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
	TitleHeight = 36,        -- 标题栏高度（手机上尽量压扁）
	RailWidth = 152,         -- 侧边标签栏宽度
	ElemHeight = 34,         -- 单行元素高度
	RowHeight = 32,          -- 行内头部高度
	Anim = 0.16,
	AnimSlow = 0.26,
}

-- 当前视口尺寸（手机端自适应都靠它）
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

-- 屏幕是否偏小（手机 / 窄窗口），用于收紧尺寸
function Util.isSmallScreen()
	local vs = Util.viewport()
	return vs.X < 760 or vs.Y < 520
end

-- 统一的输入判定。手机上的触摸是 Enum.UserInputType.Touch，
-- 不是 MouseButton1 / MouseMovement —— 所有拖拽类交互都必须同时认这两种。
function Util.isPress(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

function Util.isMove(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
end

-- 取本次输入的屏幕坐标。
-- 注意：触摸时 UserInputService:GetMouseLocation() 拿到的是鼠标（通常停在原点），
-- 不是手指位置，必须用输入事件自带的 Position。
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

-- 向上找到所属的 ScrollingFrame。
-- 手机上在滑条/取色器上拖动时，外层滚动框会抢走手势去滚列表，
-- 所以拖拽期间要临时把它的滚动关掉。
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

--[[
	拖拽会话：把「按下 / 移动 / 松手」包起来，统一处理三件容易出错的事：

	  1. 只认「发起拖拽的那个输入对象」的结束事件。
	     元素是跟着手指/鼠标走的，一移动就可能从指针下方移开，
	     若按输入类型判断结束，拖拽会中途被自己的移动打断（表现是一卡一卡）。
	     多指操作时，另一根手指抬起也不该中断当前拖拽。
	  2. 拖拽开始后忽略重复的 InputBegan，避免中途重置锚点导致跳变。
	  3. 同时认鼠标与触摸。

	用法：
		local session = Util.dragSession(self._connections, {
			start  = function(input) ... end,
			move   = function(input) ... end,
			finish = function() ... end,
		})
		hit.InputBegan:Connect(session.begin)   -- 全局的 move/finish 由本函数接管
]]
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

	-- 主动结束（例如窗口被销毁）
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
		-- 触摸：Roblox 一次触摸全程复用同一个 InputObject，
		-- 可以严格比身份 —— 这样第二根手指抬起就不会打断当前拖拽。
		if a.UserInputType == Enum.UserInputType.Touch then
			return false
		end
		-- 鼠标：不确定 InputEnded 是否给同一个实例，退化为比类型。
		-- 只看类型会漏掉多指的情况，纯身份又怕鼠标那边对不上，所以分开处理。
		return a.UserInputType == b.UserInputType
	end

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if active and sameInput(input, active) then
			session.finish()
		end
	end))

	return session
end

--============================================================================
-- 4. 根入口
--============================================================================

local XHM = {}
XHM.__index = XHM
XHM.Version = "1.0.0"
-- 构建戳：standalone 打包时会被替换成内容哈希，用来确认「手上跑的是哪一版」
-- （print(XHM.Build)）。直接跑库本体时是 "source"。
XHM.Build = "source"
XHM.Icons = Icons
XHM.Theme = Theme
XHM.Util = Util

-- 投影风格：想统一调整改这里（窗口 / 通知卡片 / 拖动条各有自己的档）
--   Blur = 模糊半径(px)  Transparency = 0 全黑 … 1 全透明  Drop = 往下偏移(px)
--   Spread = 阴影轮廓的收缩量(px，负数=缩到目标内侧，圆角缺口更干净)
-- XHM.Shadow.supported() 可以查当前客户端有没有原生 UIShadow
XHM.Shadow = {
	supported = shadowSupported,
	Window = { Blur = 20, Transparency = 0.30, Drop = 8, Spread = -3, Radius = 10 },
	Card = { Blur = 14, Transparency = 0.38, Drop = 5, Spread = -3, Radius = 8 },
	-- 拖动条外面那圈白色柔光（拖动条本身是白的，靠它跟深色背景拉开）
	HandleGlow = { Color = Color3.new(1, 1, 1), Blur = 12, Transparency = 0.35, Drop = 0, Spread = 3 },
}

local Screens = setmetatable({}, { __mode = "k" })
XHM.Screens = Screens

--[[ 创建窗口
	config = {
		Title = "XHM",
		Subtitle = "",            -- 标题栏小字
		Icon = "sparkles",        -- 标题图标名
		Size = UDim2.fromOffset(640, 460),
		MinSize = Vector2.new(480, 340),
		Accent = Color3,          -- 覆盖主题色
		ToggleKey = Enum.KeyCode.RightShift,
		Resizable = true,
		Outline = true,           -- 窗口那圈 1px 描边；false = 不要描边
		Shadow = true,            -- 窗口投影（需要客户端支持 UIShadow）
		Center = true,
		Parent = Instance,        -- 自定义挂载点
	}
]]
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
	self._notifications = {}    -- 正在显示的通知（按显示顺序）
	self._notifyById = {}       -- Id -> 通知，用于原地更新
	self._notifyOrder = 0
	self._notifyConn = nil      -- 有通知时才挂心跳，空了就断开
	self._minimized = false
	self._destroyed = false
	self._locked = config.Locked == true
	self._visible = true

	if config.Accent then
		Theme.Accent = config.Accent
	end

	-- 尺寸自适应：手机上不能比屏幕还高，否则底部的缩放柄会被挤出可视区
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
		-- 显式指定也要夹到屏幕内
		size = UDim2.fromOffset(
			math.clamp(size.X.Offset, self._minSize.X, maxW),
			math.clamp(size.Y.Offset, self._minSize.Y, maxH)
		)
	else
		-- 默认尺寸：小屏（手机）自动收紧
		local defaultW = Util.isSmallScreen() and 460 or 640
		local defaultH = Util.isSmallScreen() and 340 or 440
		size = UDim2.fromOffset(
			math.clamp(defaultW, self._minSize.X, maxW),
			math.clamp(defaultH, self._minSize.Y, maxH)
		)
	end

	-- ScreenGui
	local screen = Util.create("ScreenGui", {
		Name = "XHM-NEW-UI_" .. tostring(config.Title or "Window"):gsub("%s+", "_"),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = config.DisplayOrder or 100,
	})
	self.Screen = screen

	-- 主容器
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

	-- 窗口描边：画在窗口**内侧**的一圈 1px 细线。
	--
	-- 千万不能直接给 main 挂 UIStroke：UIStroke 是骑在边界上画的，有一半落在窗口
	-- 外面；到了圆角处，抗锯齿又会把它和背后的场景混成一条发暗的锯齿边。
	-- 深色窗口压在浅色场景上时，看着就是"边框上多出一圈黑色的东西"
	-- （用户连着报了两轮的就是它，量过像素确认：那圈的 rgb(52,52,64) = Theme.Stroke）。
	--
	-- 改成"内缩 1px 的圆角框 + 描边"：线永远在窗口里面，不可能外溢；
	-- 圆角处混的也是窗口自己的深色底，不会出现黑边。半径比窗口的 10 少 1，与外轮廓同心。
	local rim = Util.create("Frame", {
		Name = "Rim",
		Position = UDim2.new(0, 1, 0, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundTransparency = 1,
		ZIndex = 2,   -- 要压在 Rail 上面，否则左/下两条边会被 Rail 盖住
		Parent = main,
	})
	Util.corner(rim, 9)
	self._rim = rim
	self._stroke = Util.stroke(rim, Theme.Stroke, 1)
	-- 描边不想要可以在创建时写 Outline = false（也可随时 SetOutline(false)）
	if config.Outline == false then
		self:SetOutline(false)
	end

	-- 整个窗口一个 UIScale，显示/隐藏动画直接缩放它（不参与任何布局）
	self._mainScale = Util.create("UIScale", { Name = "WindowScale", Scale = 1, Parent = main })

	-- 窗口投影：挂在"影子孪生帧"上，而不是 main 自己。
	--
	-- main 有 ClipsDescendants（内容不能溢出窗口），而裁剪区是矩形 —— UIShadow 挂在
	-- main 上会被这块矩形咬掉，只剩四个圆角缺口处露出的**硬边黑块**（就是用户说的"遮罩"）。
	-- 孪生帧挂在 ScreenGui 上（不裁剪），位置/尺寸跟着 main 走，阴影就能完整铺在窗口外面。
	-- 放在 _mainScale 之后创建：孪生帧要跟着那个 UIScale 的显隐动画一起缩放。
	if config.Shadow ~= false then
		self._shadowTwin, self._shadow = Util.shadowTwin(
			main, self.Screen, self:_shadowStyle(), self._connections)
	end

	-- 窗口描边就是深度感的全部来源。
	--
	-- （曾经这里还挂了一个 Name = "Shadow" 的「柔光投影」：比窗口大 6px 的 Frame
	--  + 6px 黑色 UIStroke。但 main 必须 ClipsDescendants（内容不能溢出窗口），
	--  而 ClipsDescendants 的裁剪区是矩形、不认 UICorner，于是：
	--    · 直边上的描边落在矩形外 → 被裁掉；
	--    · 四个圆角处的描边弧线落在矩形内 → 留在屏幕上，
	--  结果就是四个角上各出现一块"突出的黑色遮罩"。投影要成立必须放在不裁剪的祖先上，
	--  那要把拖动/缩放/显示动画全部搬到外层包装帧，不值当，所以直接去掉。）

	-- 顶部渐变高光
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

	-- 标题栏
	self:_buildTitleBar()

	-- 侧边栏 + 内容区
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

	-- 通知层
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

	-- 拖动 / 尺寸
	self:_bindDrag()
	if config.Resizable ~= false then
		self:_bindResize()
	end
	self:_bindToggleKey(config.ToggleKey)
	self:_buildLauncher()

	Screens[self] = true
	Util.safeParent(screen)

	-- 入场动画
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

--============================================================================
-- 5. 窗口内部：标题栏 / 拖动 / 缩放 / 热键
--============================================================================

function XHM:_buildTitleBar()
	local bar = Util.create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, Theme.TitleHeight),
		BackgroundTransparency = 1,
		Parent = self.Main,
	})
	self.TitleBar = bar

	-- 标题图标
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

	-- 底部细分割线
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

	-- 右上角按钮组（从右往左排）
	local buttons = {}
	self._titleButtons = buttons

	local function addButton(iconName, order, onClick)
		local btn = Util.create("TextButton", {
			Name = "TB_" .. iconName,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10 - (order - 1) * 32, 0.5, 0),
			Size = UDim2.fromOffset(28, 28),   -- 手指点得稳
			BackgroundColor3 = Theme.SurfaceAlt,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = bar,
		})
		Util.corner(btn, 7)
		-- 标题栏按钮是绝对定位的，缩放不会挤动别的元素，可以直接上 UIScale
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
		btn.MouseButton1Click:Connect(onClick)
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

	-- 关闭按钮悬停时变红
	self.CloseButton.MouseEnter:Connect(function()
		Util.tween(self.CloseButton, 0.14, { BackgroundColor3 = Theme.Error, BackgroundTransparency = 0.15 })
		self._closeIcon:setColor(Color3.fromRGB(255, 255, 255))
	end)
	self.CloseButton.MouseLeave:Connect(function()
		Util.tween(self.CloseButton, 0.16, { BackgroundColor3 = Theme.SurfaceAlt, BackgroundTransparency = 1 })
	end)

	-- 锁定时高亮提示
	self.LockButton.MouseEnter:Connect(function()
		if self._locked then
			self._lockIcon:setColor(Theme.Warning)
		end
	end)
	self:_refreshLockVisual()
end

-- 固定 / 解锁 UI：锁定后不能拖动、不能缩放
function XHM:SetLocked(locked)
	self._locked = locked and true or false
	self:_refreshLockVisual()
	return self._locked
end

function XHM:IsLocked()
	return self._locked
end

-- 窗口描边开关（默认开）。
--
-- 描边画在窗口**内侧**（`Rim` 帧，内缩 1px），所以它不会像挂在 main 上的 UIStroke
-- 那样溢到窗口外面、在圆角处糊成一条发暗的锯齿边（那正是"边框上的黑色"）。
-- 不想要就 SetOutline(false)，或创建时写 Outline = false。
function XHM:SetOutline(enabled)
	enabled = enabled ~= false
	if self._stroke then
		self._stroke.Enabled = enabled
	end
	return enabled
end

-- 窗口投影的参数（复制一份，别改到共享的默认表上）
function XHM:_shadowStyle()
	local style = {}
	for k, v in pairs(XHM.Shadow.Window) do
		style[k] = v
	end
	style.Scale = self._mainScale      -- 显隐动画缩放时要跟着一起缩
	return style
end

-- 窗口投影开关（默认开）。关掉就是一块没有层次的深色。
-- 创建时写 Shadow = false 也一样。老客户端没有 UIShadow 时这里是空操作。
function XHM:SetShadow(enabled)
	enabled = enabled ~= false
	if not enabled then
		if self._shadow then
			self._shadow.Enabled = false
		end
		return false
	end
	if not self._shadow then
		-- 创建时关掉了、或者当时客户端还不支持：现在补上
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
	local viaHandle = false     -- 这次拖拽是从底部拖动条发起的吗
	local snapThreshold = 12   -- 吸附阈值别太大，否则轻轻一放就被拽走

	-- 松手：边缘吸附
	--
	-- 这里刻意不读 main.AbsolutePosition：ScreenGui 开了 IgnoreGuiInset 之后，
	-- AbsolutePosition 到底含不含顶部那条 inset 是有歧义的。如果它比 Position
	-- 的实际值少了 36px，每次松手都会把窗口往上推 36px，连拖几次就"弹"到屏幕顶端。
	-- 改成从 main.Position 反算左上角，坐标系前后一致，不依赖任何 inset 语义。
	local function snapToEdges()
		local screen = self:_screenSize()
		local size = main.AbsoluteSize
		-- Position 描述的是锚点（中心）位置，反算左上角要减半个身位
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

		-- 不许把标题栏拖出屏幕，否则就抓不回来了
		x = math.clamp(x, -size.X + 80, screen.X - 80)
		y = math.clamp(y, 0, screen.Y - 40)

		self:_setAbsolute(math.round(x), math.round(y))
	end

	-- 底部拖动条：挂在窗口**外面**、下边缘下方的一条"长药丸"细线。
	--
	-- 为什么需要它：窗口被拖到屏幕上边缘（甚至压进顶部 inset）时，标题栏不好抓；
	-- 最小化到只剩标题栏时更明显 —— 这时候就没有能下手的地方，窗口"拉不下来"了。
	-- 底部这条永远够得着，按住拖动就是把整个窗口挪走。
	--
	-- 为什么挂在 ScreenGui 上而不是窗口里：main 有 ClipsDescendants，挂在里面就
	-- 只能在窗口内部画，探出窗口的那截会被裁掉。挂外面才是"窗口下方悬着一条"。
	-- 代价是它得自己跟着窗口走：位置/长度由 syncHandle 从 main 反算
	-- （main.Position 描述的是中心点，见 _setAbsolute），
	-- 并在 main 的位置/尺寸/可见性、以及窗口那个 UIScale 变化时各同步一次 —— 不做常驻循环。
	--
	-- 视觉是一条 5px 细线，但触摸热区要 22px 高 —— 手指按 5px 的东西按不住。
	-- 颜色用纯白：它是悬在窗口外面的一条细线，深色 + 半透明在场景上根本看不清；
	-- 再加一圈白色柔光（UIShadow，颜色改成白）跟背景拉开。
	local HANDLE_GAP = 6              -- 距窗口下边缘
	local HANDLE_MIN, HANDLE_MAX = 120, 300
	local HANDLE_RATIO = 0.5          -- 长度 = 窗口宽度的一半（想更长就调大这个）
	local PILL_COLOR = Color3.new(1, 1, 1)
	local PILL_ALPHA = 0.1            -- 常态透明度（按住会到 0，即全白）

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
		-- 正常是贴窗口下边缘 6px；但小屏上窗口几乎占满高度时，这条手柄会被顶到
		-- 屏幕外面去（实测某台设备视口只有 ~359 单位、窗口 ~335 高），
		-- 那它就彻底失去意义了 —— 所以要夹回屏幕内（此时会压在窗口下边缘上）。
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

	-- 用统一的拖拽会话：只认发起拖拽的那个输入对象结束，
	-- 免得窗口跟手移动后指针离开标题栏，把自己打断
	local session = Util.dragSession(self._connections, {
		start = function(input)
			dragStart = input.Position
			startPos = main.Position
			if viaHandle then
				-- 按住拖动条时高光：告诉用户"抓住了"，也让细线在手指下看得见
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

-- ScreenGui 的实际尺寸（Position 的坐标系就是它）。
-- 刚创建还没渲染时可能是 0，退回相机视口。
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

	-- 触摸热区要够大，26px 手指才点得稳
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
			-- 尺寸先落成纯偏移，后面就不必再读绝对坐标
			main.Size = UDim2.fromOffset(startSize.X, startSize.Y)
			Util.tween(grip, 0.15, { BackgroundTransparency = 0.1 })
		end,
		move = function(input)
			local delta = input.Position - startInput
			local w = math.clamp(startSize.X + delta.X, self._minSize.X, self._maxSize.X)
			local h = math.clamp(startSize.Y + delta.Y, self._minSize.Y, self._maxSize.Y)
			main.Size = UDim2.fromOffset(w, h)

			-- AnchorPoint 是 (0.5, 0.5)，想让左上角一动不动，中心就得挪半个增量。
			-- 注意位移只能在 scale 或 offset 里加一次：
			-- 同时加的话，scale 那份换算成像素后和 offset 那份叠加，实际位移翻倍，
			-- 表现就是"一边放大一边往右下漂"。这里统一用 offset。
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

-- 收起 / 放回缩放手柄。
-- 最小化后窗口只剩一条标题栏，手柄还挂着的话就变成"悬在标题栏右下角的一块方块"，
-- 既难看又容易被误点（点上去还会把窗口拉高），所以最小化时收掉。
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
			-- 期间又恢复了就别再藏
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

--============================================================================
-- 6. 窗口公开方法
--============================================================================

-- 悬浮唤出按钮：UI 隐藏后它还留在屏幕上，手机上没键盘也能点回来
-- 悬浮球内容：优先用背景图（URL / 本地文件 / rbxassetid），没有就退回图标。
-- 图片和图标都只创建一次，之后靠 Visible 切换，避免反复销毁重建。
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

		-- 有背景图时默认不再叠图标，除非显式给了 LauncherIcon
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

-- 运行时更换悬浮球背景图：URL / 本地文件 / rbxassetid；传 nil 换回图标。
-- 返回实际生效的资源字符串；失败或回退到图标时返回 nil。
function XHM:SetLauncherImage(source)
	self.Config.LauncherImage = source
	self:_applyLauncherContent()
	local image = self._launcherImageLabel
	if image and image.Visible then
		return image.Image
	end
	return nil
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
		ClipsDescendants = true,   -- 背景图要裁进圆角里
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

	-- 可以拖着挪位置，免得挡住别的按钮
	local dragStart, startPos
	local dragged = false   -- 拖动过就不算点击，否则挪个位置就把面板打开了

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

-- 显示 / 隐藏：整体做缩放淡出，隐藏后留下悬浮按钮可以点回来
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
		-- 从中心一点长到完整尺寸
		scale.Scale = 0
		Util.tween(main, 0.24, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Util.tween(scale, 0.34, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		-- 四周向中心收缩：整体缩到 0，再真正隐藏
		if self.Launcher then
			self.Launcher.Visible = true
			self._launcherScale.Scale = 0
			-- 稍等一下再长出来，让「收缩 -> 弹出」有先后节奏
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

		-- 等动画播完再真正隐藏；用 token 防止用户快速反复切换时状态错乱
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

		-- 完整版上下收缩：
		-- Rail / Container 的尺寸都是「相对 main 的 scale 再减去标题栏高度」，
		-- 所以 main 高度收到标题栏高度时，它们自动收到 0，配合 main 的
		-- ClipsDescendants 就是一次完整的「上下向中间收拢」，
		-- 不需要逐个元素做动画，也不会露出半截内容。
		Util.tween(rail, 0.34, { BackgroundTransparency = 1 },
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Util.tween(main, 0.34, {
			Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, titleH),
		}, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)

		-- 缩放手柄跟着一起收：窗口只剩标题栏高度时它已经没有立足之地
		self:_setGripVisible(false)

		-- 收拢完再彻底隐藏，省得里层继续渲染
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
		-- 展开用 Back 缓出，收尾有一点回弹
		Util.tween(rail, 0.34, { BackgroundTransparency = 0.35 },
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Util.tween(main, 0.34, { Size = size },
			Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		-- 放回来：窗口恢复原尺寸，手柄重新出现在右下角
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

-- 注册主题色变更回调
function XHM:OnAccent(fn)
	table.insert(self._accentBindings, fn)
	pcall(fn, Theme.Accent)
	return fn
end

-- 修改窗口标题
function XHM:SetTitle(text)
	self.TitleLabel.Text = text
end

--============================================================================
-- 7. 标签页
--============================================================================

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

	-- 左右两栏
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

	-- 便捷方法
	function tab:Section(sectionConfig)
		return self.Window:_createSection(self, sectionConfig)
	end

	function tab:Select()
		self.Window:SelectTab(self)
	end

	function tab:SetVisible(visible)
		self.Button.Visible = visible and true or false
	end

	-- 侧边栏按钮
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

	-- 按下时图标轻微弹一下（图标是绝对定位的子级，缩放不会挤动别的元素）
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

	-- 新页面从右侧轻微滑入（两栏都是绝对定位，滑动不影响布局）
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

--============================================================================
-- 8. 区段（Section）
--============================================================================

local Section = {}
Section.__index = Section

function XHM:_createSection(tab, cfg)
	cfg = cfg or {}
	local side = cfg.Side or "Left"
	local column = (side == "Right") and tab.Right or tab.Left

	-- 一旦使用右栏，就切成两列布局
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

	-- 折叠面板状态
	local collapsed = cfg.Collapsed == true
	section._collapsed = collapsed

	-- 头部
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

	-- 折叠箭头
	--
	-- 转的是这个外层 holder（AnchorPoint 是 (0.5, 0.5)，也就是它的中心），
	-- 而不是 Icons.new 里那个 AnchorPoint 为 (0,0) 的内层 holder：
	-- 以内层为轴转 -90° 时图标会绕着左上角甩出去，位置和 "⌄" 对不上。
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

	-- 内容容器（折叠动画的「视口」）。
	--
	-- 这里刻意用 Frame 而不是 CanvasGroup：CanvasGroup 会把整棵子树先渲染到一张
	-- 离屏贴图再画出来，Roblox 上这个过程会明显软化文字与细线 —— 而这个容器正好
	-- 包住了区段里的全部元素，用 CanvasGroup 会让整个区段看起来发糊。
	--
	-- 折叠靠「视口高度收到 0」+「内层整体上移」两条补间同时跑，不依赖 GroupTransparency。
	local content = Util.create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = collapsed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,   -- 高度收缩时把子元素真正裁掉，而不是让它们悬在框外
		LayoutOrder = 2,
		Visible = not collapsed,
		Parent = root,
	})
	section.Content = content

	-- 内层：真正装行的地方，所有行都挂在它下面。
	--
	-- 为什么要多这一层：只补间 content 的高度，行会被 UIListLayout 钉在容器顶部原地不动，
	-- 看起来就是「区段框缩了、里面的元素却一动不动地溢出在外面」。
	-- 补间内层的 Position（上移同样的高度）才能让整块内容跟着一起收上去，
	-- 配合 content 的 ClipsDescendants 就是一次完整的上下收拢。
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

	-- 创建时就是折叠态的话，直接把角度摆好，不走动画
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

-- 量出内容的自然高度。
-- 内层是 AutomaticSize，量它最准；量不到（极端时机）再退到视口高度、最后退到上次缓存。
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
	-- 箭头旋转要和内容收缩同步。
	-- 以前这里是瞬间 setRotation：内容在慢慢滑，箭头却"啪"地翻过去，
	-- 而下面几行的箭头（Button 的 ">"、Dropdown 的 "⌄"）都是有动画的。
	-- 转的是外层居中 holder，所以它是在原地打转，不会跟着内容一起跑位。
	Util.tween(self.ChevronHolder, 0.2, { Rotation = state and -90 or 0 },
		Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- 折叠动画靠补间高度：AutomaticSize 打开时高度是被算出来的、补不了，
	-- 所以动画期间两个 AutomaticSize 都关掉、高度交给补间接管，收尾再还原。
	--
	-- 两条补间必须同时跑且参数一致：
	--   · content 高度 → 0（视口收起来，把子元素裁掉）
	--   · inner 位置 → -height（内容整块上移，视觉上元素跟着一起收）
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
				-- 折叠态固定成「高度 0 + 不可见」：不依赖引擎对「不可见子级是否计入
				-- AutomaticSize」的处理，区段框一定只剩头部。
				content.Size = UDim2.new(1, 0, 0, 0)
				inner.Position = UDim2.new(0, 0, 0, 0)
				-- 内层的 AutomaticSize 要还回去：折叠期间行还可能被增删，
				-- 下次展开要量到最新高度，而不是这次冻结下来的旧值。
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

-- 创建一行容器（头部 + 可选展开面板）
-- 返回的是「行句柄」普通表而非实例：Roblox 实例不允许挂自定义字段，
-- 所以 Header / TitleLabel / IconObj / Flag 这些都存在句柄上。
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

	-- 左侧强调条：悬停时从上下滑入（绝对定位，不参与 UIListLayout，不会挤动邻居）
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

	-- 统一的悬停 / 按下动效，所有组件复用
	-- base/hover/press 是背景透明度档位，Button 这类实心行会覆盖成更实的值
	local hovering, pressing = false, false
	local function bg(target, time)
		Util.tween(header, time or Theme.Anim, { BackgroundTransparency = target })
	end
	local function paintIcon(color)
		if row.IconObj then
			row.IconObj:setColor(color)
		end
	end

	-- 注意：透明度档位一律带 Alpha 后缀。
	-- 早先这里叫 press，和下面的 press() 函数同名，字面量里后者覆盖前者，
	-- 后来 Button 再写 row.FX.press = 0 就把函数覆盖成数字，Connect 直接报错。
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

-- 行内左侧标题
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

--============================================================================
-- 9. 组件
--============================================================================

-- ---------------------------------------------------------------- Button
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

	-- 实心按钮行：覆盖 FX 的透明度档位
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

-- ---------------------------------------------------------------- Toggle
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

		-- 旋钮弹一下，让切换有「手感」
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
		-- Flag 始终写入（静默设置也要同步），只有 Callback 受 silent 控制
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

-- ---------------------------------------------------------------- Slider
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

	-- 命中区域（加大点击范围）
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
		-- Flag 始终写入（静默设置也要同步），只有 Callback 受 silent 控制
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
			-- 拖滑条时别让外层滚动框抢走手势
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

-- ---------------------------------------------------------------- Dropdown
function Section:Dropdown(cfg)
	cfg = cfg or {}
	local multi = cfg.Multi == true
	local searchable = cfg.Searchable == true and #(cfg.Options or {}) > 6

	local row = self:_row(34, cfg.Flag)
	self:_title(row, cfg, 120)

	-- 当前值显示
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

	-- 展开面板
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

	-- 搜索框
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
	local selected = {}   -- 单选: [value]=true，多选: 集合
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

	-- 根据当前选中集合推算值（单选返回字符串，多选返回数组）
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

	-- silent 为 true 时只同步值与 Flag，不触发 Callback（构造阶段用）
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
	-- 构造阶段静默建列表，避免用 nil 触发一次无意义的 Callback
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

-- ---------------------------------------------------------------- Input
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

	-- Flag 初值与输入框显示保持一致：文本为空串，数字为 0
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

-- ---------------------------------------------------------------- Keybind
function Section:Keybind(cfg)
	cfg = cfg or {}
	local mode = cfg.Mode or "Toggle" -- Toggle | Hold | Always

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
			-- 合并到 inputConn 以便重绑时释放
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

-- ---------------------------------------------------------------- 颜色选择器
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

	-- 色相饱和区
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

	-- 色相条
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

	-- 十六进制输入
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
		-- 触摸时不能用 GetMouseLocation()，那是鼠标的位置不是手指的
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
	local pendingHue = false   -- 这一次按下是冲着色相条来的吗

	local session = Util.dragSession(self.Window._connections, {
		start = function(input)
			-- 取色时别让外层滚动框抢走手势
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

-- ---------------------------------------------------------------- 文本类

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

--============================================================================
-- 10. 通知
--
-- 设计原则：一条通知只保留 4 个元素 —— 图标 / 标题 / 正文（可选）/ 底部进度条。
--   · 没有关闭按钮：点卡片本身就关掉（有 OnClick 时先执行回调再关）
--   · 没有左侧色条、没有图标底座、没有描边，靠图标颜色区分类型
--   · 悬停是「真的」暂停计时，进度条同步停住，不是只暂停动画
--
-- 逻辑：
--   · 同 Id 的通知原地更新，不重复堆叠
--   · 超过 MaxNotifications 时挤掉最旧的一条
--   · Duration = 0 表示常驻，不自动消失
--============================================================================

local TYPE_STYLE = {
	info = { Icon = "info", Color = Color3.fromRGB(88, 140, 255) },
	success = { Icon = "circle-check", Color = Theme.Success },
	warning = { Icon = "alert", Color = Theme.Warning },
	error = { Icon = "circle-x", Color = Theme.Error },
}

local EXIT_TIME = 0.2

local Notification = {}
Notification.__index = Notification

--============================================================================
-- 通知实例
--============================================================================

function Notification:_paintProgress()
	if self._duration <= 0 then
		self._progress.Visible = false
		return
	end
	self._progress.Visible = true
	local remain = math.max(self._duration - self._elapsed, 0)
	self._fill.Size = UDim2.new(remain / self._duration, 0, 1, 0)
end

-- 每个心跳推进一次；悬停期间完全不累加，所以是真暂停
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

-- 正文可有可无：没有正文时把它的高度也收掉，不留空档
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

-- 原地更新：内容变了就刷新，并把计时重置
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
		-- 传 false 撤掉背景图
		self:_setBackground(cfg.Background, cfg)
	end
	if cfg.Sound then
		self._soundSource = cfg.Sound
		self._soundVolume = cfg.SoundVolume
		self:_playSound(cfg.Sound, cfg.SoundVolume)
	end

	self._elapsed = 0
	self:_applyStyle()
	self:_paintProgress()

	-- 闪一下背景，提示「还是同一条，内容变了」
	self._card.BackgroundColor3 = Theme.SurfaceAlt
	Util.tween(self._card, 0.6, { BackgroundColor3 = Theme.Surface })
	return self
end

-- 收起一条通知：先滑出淡出，再收高度，最后销毁
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

	-- 固定住当前高度，才能把「收高度」做成动画
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

-- 设置/更新背景图。支持 rbxassetid 与执行器外链（URL / 本地文件）。
-- 传 nil 表示撤掉背景图。
function Notification:_setBackground(source, cfg)
	cfg = cfg or {}
	-- source 传 false 表示明确撤掉背景图（nil 无法和「没传这个字段」区分）
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

-- 播放提示音。支持 rbxassetid 与执行器外链（URL / 本地文件）。
-- 挂在 ScreenGui 上而不是卡片上：卡片很快就没了，声音不该被腰斩。
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

	-- 播完自清理；再兜一个超时，防止 Ended 没触发时泄漏
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

--============================================================================
-- 窗口侧：管理多条通知
--============================================================================

function XHM:_notifyTick(dt)
	local list = self._notifications
	for i = #list, 1, -1 do
		if not list[i]._dismissed then
			list[i]:_step(dt)
		end
	end
	-- 没有通知了就断掉心跳，别空转
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

	-- holder 只是布局项，card 在里面单独做滑动动画
	local holder = Util.create("Frame", {
		Name = "Notify",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = self._notifyOrder,
		Parent = self._notifyHolder,
	})

	-- 卡片用 Frame 不用 CanvasGroup：CanvasGroup 会把子树渲染到离屏贴图，
	-- 通知里的文字会被软化。出入场改成「滑入滑出 + 高度收放」，不依赖 GroupTransparency。
	local card = Util.create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 40, 0, 0),   -- 从右侧滑入
		Parent = holder,
	})
	Util.corner(card, 8)
	Util.stroke(card, Theme.Stroke, 1, 0.75)
	card.ClipsDescendants = true
	-- 卡片投影：卡片自己开 ClipsDescendants（进度条要贴着圆角裁），所以投影挂在
	-- holder 里的孪生帧上，跟着卡片的滑入一起走，且不会被卡片裁掉
	Util.shadowTwin(card, holder, {
		Blur = XHM.Shadow.Card.Blur,
		Transparency = XHM.Shadow.Card.Transparency,
		Drop = XHM.Shadow.Card.Drop,
		Spread = XHM.Shadow.Card.Spread,
		Radius = XHM.Shadow.Card.Radius,
	}, self._connections)

	-- CanvasGroup 上没有按钮事件（它继承 GuiObject 而非 GuiButton），
	-- 所以点击/悬停挂在下面这个透明 TextButton 上。
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

	-- 图标：直接用类型色，不再套一个底座方块
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

	-- 进度条：唯一的时间指示，没有它用户不知道还剩多久。
	-- 挂在 inner 里并抵消 padding，正好贴着卡片底边。
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

	-- 透明点击层：盖住整张卡片（含 padding 与进度条），
	-- 这样「点卡片任意位置都能关」才成立。它本身不可见，不算多余元素。
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

	-- 背景图 / 提示音：都支持 rbxassetid 与执行器外链
	notification:_setBackground(cfg.Background, cfg)

	if cfg.Sound then
		notification._soundSource = cfg.Sound
		notification._soundVolume = cfg.SoundVolume
		notification:_playSound(cfg.Sound, cfg.SoundVolume)
	end

	-- 点击卡片：有回调先跑回调，然后关掉
	hit.MouseButton1Click:Connect(function()
		if notification._dismissed then
			return
		end
		if notification._onClick then
			task.spawn(notification._onClick)
		end
		notification:dismiss()
	end)

	-- 悬停真的暂停计时
	hit.MouseEnter:Connect(function()
		notification._paused = true
	end)
	hit.MouseLeave:Connect(function()
		notification._paused = false
	end)

	-- 入场：从右侧滑入
	Util.tween(card, 0.28, { Position = UDim2.new(0, 0, 0, 0) },
		Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	return notification
end

--[[
	发一条通知

	cfg = {
		Id = "loading",        -- 可选：同 Id 的通知原地更新，不会堆叠
		Title = "标题",
		Content = "正文，可省略",
		Type = "info",         -- info | success | warning | error（决定图标与颜色）
		Icon = "bell",         -- 可选：覆盖类型默认图标
		Color = Color3,        -- 可选：覆盖类型颜色
		Duration = 4,          -- 秒；0 = 常驻不自动消失
		OnClick = function() end,
	}
]]
function XHM:Notify(cfg)
	if type(cfg) == "string" then
		cfg = { Title = cfg }
	end
	cfg = cfg or {}
	if self._destroyed then
		return nil
	end

	-- 同 Id 原地更新
	if cfg.Id ~= nil and self._notifyById[cfg.Id] then
		return self._notifyById[cfg.Id]:update(cfg)
	end

	local notification = self:_createNotification(cfg)
	table.insert(self._notifications, notification)
	if cfg.Id ~= nil then
		self._notifyById[cfg.Id] = notification
	end

	-- 超出上限就挤掉最旧的
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

-- 按 Id 关掉某条通知
function XHM:DismissNotification(id)
	local notification = self._notifyById[id]
	if not notification then
		return false
	end
	notification:dismiss()
	return true
end

-- 关掉全部通知
function XHM:ClearNotifications()
	for i = #self._notifications, 1, -1 do
		self._notifications[i]:dismiss()
	end
end

-- 当前还在显示的通知数量
function XHM:NotificationCount()
	return #self._notifications
end

--============================================================================
-- 11. 配置读写
--============================================================================

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

-- 内部写入 Flag（允许 flag 为 nil，并触发 OnFlagChanged 监听）
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

-- 监听某个 flag 变化（用户交互、SetFlag、载入配置均会触发）
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

-- 保存到文件（无 writefile 时降级为返回 JSON 字符串）
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

--============================================================================
-- 12. 析构
--============================================================================

--[[
	通用二次确认框（同一个窗口同时只保留一个）

	cfg = {
		Title = "确认关闭",
		Content = "关闭后需要重新执行脚本才能再次打开。",
		ConfirmText = "关闭", CancelText = "取消",
		Danger = true,               -- 确认按钮用红色
		OnConfirm = function() end,
		OnCancel = function() end,
	}
]]
function XHM:Confirm(cfg)
	cfg = cfg or {}
	local main = self.Main
	if not main or self._destroyed then
		return nil
	end

	-- 同一时间只留一个
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
	-- 确认框也是一张浮起来的卡，给同样的投影（不然它看着像贴在窗口上）
	Util.shadow(card, XHM.Shadow.Card)
	-- 整卡片缩放，不参与任何布局
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

	-- 标题
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

	-- 正文
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

	-- 按钮行
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
		btn.MouseButton1Click:Connect(onClick)
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

	-- 主按钮在右（后加的排右边）
	makeButton(cfg.CancelText or "取消", 1, false, function()
		dismiss(cfg.OnCancel)
	end)
	makeButton(cfg.ConfirmText or "确定", 2, true, function()
		dismiss(cfg.OnConfirm)
	end)

	-- 点背景 = 取消
	overlay.MouseButton1Click:Connect(function()
		dismiss(cfg.OnCancel)
	end)

	-- 入场：背景淡入 + 卡片从 0.85 弹到 1
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

-- 关闭请求：默认先弹二次确认
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

--============================================================================
-- 13. 便捷包装：直接建窗口 + 默认 Tab
--============================================================================

--[[
	快捷创建：XHM.Create({ Title = "xxx" }) 返回 (window, tab, section)
]]
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
