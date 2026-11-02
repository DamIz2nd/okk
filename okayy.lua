-- LocalScript → StarterPlayer > StarterPlayerScripts
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local FLAT = Vector3.new(1, 0, 1)

----------------------------------------------------------------
-- AJUSTES FIJOS (editables aquí)
----------------------------------------------------------------
local SAMPLE_INTERVAL = 0.1
local EVAL_HORIZON = 0.5
local SYMBOL_STEP = 0.5
local LOW_U = 30             -- imprevisibilidad menor = "Lento"
local HIGH_U = 60            -- imprevisibilidad mayor = "Rápido"
local SEGMENTS = 10
local PUZZLE_IMAGE_ID = ""   -- opcional: "rbxassetid://TU_ID"

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local cfg = {
	line = {
		enabled = true, showSelf = true, origin = "Cabeza",
		length = 15, width = 0.2, startOffset = 0.6,
		h = 0.33, s = 1, v = 1,
		rainbow = false, neon = true, transparency = 0.2, stopAtWalls = false,
	},
	pred = {
		path = true, endMarker = true, horizon = 1.5, useAccel = false,
		width = 0.15, transparency = 0.2,
		lead = false, projectileSpeed = 80,
		trail = false, trailTime = 2,
		highlight = false, throughWalls = true,
		hud = false, hudCount = 5, maxDistance = 200,
	},
	route = {
		frontEnabled = false, frontRange = 30, frontCone = 50, frontLength = 18,
		wSafe = 0.5, wUnp = 0.35, wProg = 0.3, forwardMode = "Personaje",
		safeEnabled = false, nearDist = 40, groupMin = 2, safeDist = 9, pathLength = 35,
		showZones = false, onlyEnemies = false, width = 0.25,
	},
	tags = {
		enabled = true, showSelf = false,
		showReason = true, showScore = false, showSpeed = false, showDistance = false,
		smooth = true, interval = 50, sensitivity = 1, maxDistance = 150,
	},
	tab = { ballEnabled = true, ballName = "Ball", possDist = 6, sortBy = "Distancia", maxRows = 10 },
	text = { tagSize = 18, subSize = 12, hudSize = 12, font = "Gotham", outline = 0.45 },
	fx = { enabled = true, density = 14, speed = 1, size = 1, opacity = 0.5, hue = 0.6 },
	ui = { accentHue = 0.72, panelTransparency = 0.05, scale = 1 },
}

local FONT_MAP = {
	Gotham = { bold = Enum.Font.GothamBold, normal = Enum.Font.Gotham },
	Arial = { bold = Enum.Font.ArialBold, normal = Enum.Font.Arial },
	["Código"] = { bold = Enum.Font.Code, normal = Enum.Font.Code },
	Fredoka = { bold = Enum.Font.FredokaOne, normal = Enum.Font.FredokaOne },
}

----------------------------------------------------------------
-- TEMA / ACENTO / UTILIDADES
----------------------------------------------------------------
local THEME = {
	bg = Color3.fromRGB(16, 16, 22),
	surface = Color3.fromRGB(27, 27, 37),
	off = Color3.fromRGB(70, 70, 88),
	text = Color3.fromRGB(240, 240, 250),
	subtext = Color3.fromRGB(150, 150, 172),
	accent = Color3.fromHSV(cfg.ui.accentHue, 0.65, 1),
}

local accentFns = {}
local function onAccent(fn)
	table.insert(accentFns, fn)
	fn()
end
local function setAccent(hue)
	THEME.accent = Color3.fromHSV(hue, 0.65, 1)
	for _, fn in ipairs(accentFns) do fn() end
end

local function clamp01(x) return math.clamp(x, 0, 1) end

local function sectorOf(v) -- dirección -> sector 1..8
	local ang = math.atan2(v.Z, v.X)
	return math.floor(((ang + math.pi + math.pi / 8) / (2 * math.pi)) * 8) % 8 + 1
end

local function rotateY(v, ang)
	return CFrame.Angles(0, ang, 0):VectorToWorldSpace(v)
end

local function distToSegment(p, a, b) -- distancia en el plano
	local ab = (b - a) * FLAT
	local ap = (p - a) * FLAT
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp(ap:Dot(ab) / len2, 0, 1) or 0
	return (ap - ab * t).Magnitude
end

local function escapeRich(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

----------------------------------------------------------------
-- LÍNEA (cabeza o pecho)
----------------------------------------------------------------
local lineFolder = Instance.new("Folder")
lineFolder.Name = "LineasJugadores"
lineFolder.Parent = workspace

local lines = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getOriginPart(character)
	if not character then return nil end
	if cfg.line.origin == "Cabeza" then
		return character:FindFirstChild("Head")
	end
	return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end

local function getLine(player)
	local part = lines[player]
	if part and part.Parent then return part end
	part = Instance.new("Part")
	part.Name = player.Name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = lineFolder
	lines[player] = part
	return part
end

local function removeLine(player)
	if lines[player] then
		lines[player]:Destroy()
		lines[player] = nil
	end
end

local function updateLines()
	local l = cfg.line
	local color = l.rainbow and Color3.fromHSV((os.clock() * 0.25) % 1, 1, 1)
		or Color3.fromHSV(l.h, l.s, l.v)

	for _, player in ipairs(Players:GetPlayers()) do
		local origin = getOriginPart(player.Character)
		local visible = l.enabled and origin ~= nil and (player ~= LocalPlayer or l.showSelf)

		if visible then
			local part = getLine(player)
			local length = l.length
			local startCF = origin.CFrame * CFrame.new(0, 0, -l.startOffset)

			if l.stopAtWalls then
				rayParams.FilterDescendantsInstances = { lineFolder, player.Character }
				local hit = workspace:Raycast(startCF.Position, startCF.LookVector * length, rayParams)
				if hit then length = math.max(hit.Distance, 0.05) end
			end

			part.Color = color
			part.Material = l.neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
			part.Transparency = l.transparency
			part.Size = Vector3.new(l.width, l.width, length)
			part.CFrame = startCF * CFrame.new(0, 0, -length / 2)
		else
			removeLine(player)
		end
	end
end

----------------------------------------------------------------
-- BALÓN (para saber quién lo tiene cerca)
----------------------------------------------------------------
local ballPart, ballCheck = nil, 0

local function findBall()
	local name = cfg.tab.ballName
	if name == "" then return nil end
	if ballPart and ballPart.Parent then return ballPart end
	if os.clock() - ballCheck < 1 then return nil end
	ballCheck = os.clock()
	local inst = workspace:FindFirstChild(name, true)
	if inst then
		if inst:IsA("BasePart") then
			ballPart = inst
		elseif inst:IsA("Model") then
			ballPart = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		end
	end
	return ballPart
end

----------------------------------------------------------------
-- ANÁLISIS DE PREDECIBILIDAD + PERFIL + DEBILIDADES
----------------------------------------------------------------
local tracker = {}

local TAG_COLORS = {
	Lento = Color3.fromRGB(90, 175, 255),
	Normal = Color3.fromRGB(255, 214, 70),
	["Rápido"] = Color3.fromRGB(255, 85, 85),
}
local NEUTRAL = Color3.fromRGB(225, 225, 238)

local W = { pat = 0.45, geo = 0.25, turns = 0.10, stops = 0.10, jumps = 0.10 }
local REASONS = {
	pat = "patrón impredecible",
	geo = "difícil de anticipar",
	turns = "giros bruscos",
	stops = "arranca y frena",
	jumps = "saltos frecuentes",
}

local function labelColor(d)
	return d and TAG_COLORS[d.label] or NEUTRAL
end

local function newData(hrp)
	return {
		hrp = hrp, lastPos = hrp.Position,
		vel = Vector3.zero, acc = Vector3.zero, speed = 0, walk = 16,
		wasMoving = false, wasJumping = false,
		elapsed = 0, moveTime = 0, stops = 0, jumps = 0, sharp = 0,
		geoSum = 0, geoN = 0, pending = {},
		headings = {}, lastTurn = -10,
		symAcc = 0, symStart = hrp.Position, prevSym = nil, markov = {},
		patHits = 0, patN = 0,
		speedSum = 0, yawSum = 0, misSum = 0, misN = 0, latR = 0, latL = 0, lastLook = nil,
		nearBall = false, possTime = 0, possSpeedSum = 0, possMove = 0, possSharp = 0, possStops = 0,
		label = "Analizando...", reason = "reuniendo datos",
		score = 0, U = 0, hasResult = false,
		profile = nil, gaze = "—", weakAcc = {}, weakText = "—",
	}
end

local function symScore(guess, actual)
	if guess == actual then return 1 end
	if guess ~= 0 and actual ~= 0 then
		local diff = math.abs(guess - actual)
		if math.min(diff, 8 - diff) == 1 then return 0.5 end
	end
	return 0
end

local function buildProfile(d, el, moveSec)
	local p = {}
	p.moveRatio = d.moveTime / el
	p.avgSpeed = d.moveTime > 0 and d.speedSum / d.moveTime or 0
	p.possFrac = d.possTime / el
	p.possSpeed = d.possTime > 0.5 and d.possSpeedSum / d.possTime or nil
	p.possDribble = d.possMove > 1 and d.possSharp / d.possMove or nil
	p.possStops = d.possTime > 0.5 and d.possStops / (d.possTime / 10) or nil
	p.yawRate = d.moveTime > 1 and d.yawSum / d.moveTime or nil
	p.misalign = d.misN > 5 and d.misSum / d.misN or nil
	local lat = d.latR + d.latL
	p.bias = lat > 2 and (d.latR - d.latL) / lat or 0
	p.stopsPer10 = d.stops / (el / 10)
	p.jumpsPer10 = d.jumps / (el / 10)
	p.sharpRate = d.sharp / moveSec
	p.U = d.U
	return p
end

local function gazeText(p)
	if not p.yawRate then return "—" end
	if p.yawRate < 20 then return "fija" end
	if p.yawRate < 60 then return "normal" end
	return "muy activa"
end

local function evaluateWeaknesses(p)
	local out = {}
	local function add(score, text) table.insert(out, { score = score, text = text }) end

	if p.possFrac > 0.12 and p.possSpeed and p.possDribble then
		if p.possSpeed > 11 and p.possDribble < 0.15 then
			add(0.9, "avanza demasiado con el balón y casi no regatea")
		end
		if p.possDribble > 0.45 and p.possSpeed < 9 then
			add(0.8, "regatea mucho pero avanza poco con el balón")
		end
		if p.possStops and p.possStops > 3 then
			add(0.75, "se detiene con el balón: fácil de presionar")
		end
	end
	if p.moveRatio > 0.25 and p.U < LOW_U then
		add(0.7 + (LOW_U - p.U) / 100, "trayectoria muy predecible: se puede anticipar")
	end
	if math.abs(p.bias) > 0.55 then
		add(0.6 + math.abs(p.bias) * 0.2,
			"casi siempre se desvía hacia su " .. (p.bias > 0 and "derecha" or "izquierda"))
	end
	if p.yawRate and p.yawRate < 20 then
		add(0.55, "casi no gira la vista: vulnerable por los costados")
	end
	if p.misalign and p.misalign > 45 then
		add(0.4, "corre de lado o hacia atrás mirando al frente: tarda en cambiar de dirección")
	end
	if p.stopsPer10 > 3 then
		add(0.5, "se detiene seguido: fácil de presionar cuando para")
	end
	if p.sharpRate > 0.5 and p.avgSpeed < 8 then
		add(0.45, "muchos giros pero avanza lento")
	end
	if p.jumpsPer10 < 0.1 and p.moveRatio > 0.3 then
		add(0.35, "casi no salta: vulnerable a balones aéreos")
	end
	return out
end

local function updateWeaknesses(d, list)
	for k, v in pairs(d.weakAcc) do d.weakAcc[k] = v * 0.6 end -- olvido gradual
	for _, w in ipairs(list) do
		d.weakAcc[w.text] = (d.weakAcc[w.text] or 0) + w.score
	end
	local arr = {}
	for text, score in pairs(d.weakAcc) do
		if score > 0.35 then table.insert(arr, { text = text, score = score }) end
	end
	table.sort(arr, function(a, b) return a.score > b.score end)
	if #arr == 0 then
		d.weakText = "sin debilidad clara todavía"
	else
		d.weakText = arr[1].text .. (arr[2] and (" · " .. arr[2].text) or "")
	end
end

local function classify(d)
	local el = d.elapsed
	local moveRatio = d.moveTime / el
	local moveSec = math.max(d.moveTime, 1)

	local comp = {
		pat = d.patN > 0 and clamp01((1 - d.patHits / d.patN) / 0.6) or 0,
		geo = d.geoN > 0 and clamp01((d.geoSum / d.geoN) / 0.5) or 0,
		turns = clamp01((d.sharp / moveSec) / 0.5),
		stops = clamp01((d.stops / (el / 10)) / 4),
		jumps = clamp01((d.jumps / (el / 10)) / 3),
	}

	local raw, topKey, topVal = 0, "pat", -1
	for key, value in pairs(comp) do
		local contrib = value * W[key] * 100
		raw += contrib
		if contrib > topVal then topKey, topVal = key, contrib end
	end

	if cfg.tags.smooth and d.hasResult then
		d.U = d.U * 0.35 + raw * 0.65
	else
		d.U = raw
	end

	local score = math.clamp(d.U * cfg.tags.sensitivity, 0, 100)
	local label, reason
	if score < LOW_U then
		label = "Lento"
		if moveRatio < 0.1 then
			reason = "casi inmóvil"
		elseif d.sharp / moveSec > 0.25 then
			reason = "patrón repetitivo"
		else
			reason = "trayectoria predecible"
		end
	elseif score >= HIGH_U then
		label = "Rápido"
		reason = REASONS[topKey]
	else
		label = "Normal"
		reason = "moderado: " .. REASONS[topKey]
	end
	d.label, d.reason, d.score, d.hasResult = label, reason, score, true

	-- perfil y debilidades (antes de reiniciar contadores)
	local profile = buildProfile(d, el, moveSec)
	d.profile = profile
	d.gaze = gazeText(profile)
	updateWeaknesses(d, evaluateWeaknesses(profile))

	d.elapsed, d.moveTime, d.stops, d.jumps, d.sharp = 0, 0, 0, 0, 0
	d.geoSum, d.geoN, d.patHits, d.patN = 0, 0, 0, 0
	d.speedSum, d.yawSum, d.misSum, d.misN, d.latR, d.latL = 0, 0, 0, 0, 0, 0
	d.possTime, d.possSpeedSum, d.possMove, d.possSharp, d.possStops = 0, 0, 0, 0, 0
end

local function sampleMovement(player, dt, now, ballPos)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		tracker[player] = nil
		return
	end

	local d = tracker[player]
	if not d or d.hrp ~= hrp then
		d = newData(hrp)
		tracker[player] = d
	end

	local pos = hrp.Position
	local delta = (pos - d.lastPos) * FLAT
	d.lastPos = pos

	if delta.Magnitude > 60 then -- teletransporte
		d.vel, d.acc, d.pending, d.headings = Vector3.zero, Vector3.zero, {}, {}
		d.prevSym, d.symAcc, d.symStart, d.lastLook = nil, 0, pos, nil
		return
	end

	local newVel = d.vel:Lerp(delta / dt, 0.5)
	d.acc = d.acc:Lerp((newVel - d.vel) / dt, 0.2)
	if d.acc.Magnitude > 30 then d.acc = d.acc.Unit * 30 end
	d.vel = newVel
	local speed = newVel.Magnitude
	d.speed = speed
	d.walk = hum.WalkSpeed

	d.elapsed += dt
	local moving = (d.wasMoving and speed > 2) or speed > 4
	if moving then
		d.moveTime += dt
		d.speedSum += speed * dt
	end

	-- balón cerca
	local near = false
	if ballPos then
		near = ((ballPos - pos) * FLAT).Magnitude <= cfg.tab.possDist and math.abs(ballPos.Y - pos.Y) < 8
	end
	d.nearBall = near
	if near then
		d.possTime += dt
		d.possSpeedSum += speed * dt
		if moving then d.possMove += dt end
	end

	if moving ~= d.wasMoving then
		d.stops += 1
		if not moving and near then d.possStops += 1 end
		d.wasMoving = moving
	end

	-- error de predicción lineal a 0.5 s
	table.insert(d.pending, { due = now + EVAL_HORIZON, pos = pos + newVel * EVAL_HORIZON })
	while d.pending[1] and d.pending[1].due <= now do
		local p = table.remove(d.pending, 1)
		local err = ((pos - p.pos) * FLAT).Magnitude
		local scale = math.max(hum.WalkSpeed, 8) * EVAL_HORIZON
		d.geoSum += math.min(err / scale, 2)
		d.geoN += 1
	end

	-- giros bruscos
	if speed > 5 then
		local dir = newVel.Unit
		table.insert(d.headings, dir)
		if #d.headings > 4 then table.remove(d.headings, 1) end
		if #d.headings == 4 and now - d.lastTurn > 0.5 then
			local ang = math.acos(math.clamp(dir:Dot(d.headings[1]), -1, 1))
			if ang > math.rad(50) then
				d.sharp += 1
				d.lastTurn = now
				if near then d.possSharp += 1 end
			end
		end
	else
		d.headings = {}
	end

	-- mirada estimada (cabeza o cuerpo) y movimiento lateral
	local head = char:FindFirstChild("Head")
	local look = ((head or hrp).CFrame.LookVector * FLAT)
	if look.Magnitude < 0.1 then look = hrp.CFrame.LookVector * FLAT end
	look = look.Magnitude > 0.01 and look.Unit or nil
	if look and d.lastLook and moving then
		local cross = d.lastLook:Cross(look).Y
		local dot = d.lastLook:Dot(look)
		d.yawSum += math.abs(math.deg(math.atan2(cross, dot)))
	end
	if look and moving and speed > 4 then
		d.misSum += math.deg(math.acos(math.clamp(look:Dot(newVel.Unit), -1, 1)))
		d.misN += 1
	end
	d.lastLook = look
	if moving then
		local lat = newVel:Dot(hrp.CFrame.RightVector)
		if lat > 3 then d.latR += dt elseif lat < -3 then d.latL += dt end
	end

	-- patrón (Markov sobre dirección cada 0.5 s)
	d.symAcc += dt
	if d.symAcc >= SYMBOL_STEP then
		local disp = (pos - d.symStart) * FLAT
		local sym = 0
		if disp.Magnitude / d.symAcc > 3 then sym = sectorOf(disp) end
		if d.prevSym ~= nil then
			local row = d.markov[d.prevSym]
			local guess = d.prevSym
			if row then
				local best = 0
				for s, c in pairs(row) do
					if c > best then best, guess = c, s end
				end
			else
				row = {}
				d.markov[d.prevSym] = row
			end
			d.patN += 1
			d.patHits += symScore(guess, sym)
			row[sym] = (row[sym] or 0) + 1
		end
		d.prevSym = sym
		d.symAcc = 0
		d.symStart = pos
	end

	local jumping = hum:GetState() == Enum.HumanoidStateType.Jumping
	if jumping and not d.wasJumping then d.jumps += 1 end
	d.wasJumping = jumping

	if d.elapsed >= cfg.tags.interval then
		classify(d)
	end
end

----------------------------------------------------------------
-- ETIQUETAS SOBRE LA CABEZA
----------------------------------------------------------------
local tagFolder = Instance.new("Folder")
tagFolder.Name = "EtiquetasMovimiento"
tagFolder.Parent = workspace
local tags = {}

local function removeTag(player)
	local t = tags[player]
	if t then
		t.gui:Destroy()
		tags[player] = nil
	end
end

local function getTag(player, head)
	local t = tags[player]
	if t and t.gui.Parent and t.gui.Adornee == head then return t end
	if t then t.gui:Destroy() end

	local g = Instance.new("BillboardGui")
	g.Adornee = head
	g.Parent = tagFolder

	local main = Instance.new("TextLabel")
	main.BackgroundTransparency = 1
	main.Parent = g

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.TextWrapped = true
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.TextColor3 = Color3.fromRGB(215, 215, 230)
	sub.Parent = g

	t = { gui = g, main = main, sub = sub }
	tags[player] = t
	return t
end

local function updateTag(player)
	local t = cfg.tags
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local d = tracker[player]

	if not (t.enabled and head and d and (player ~= LocalPlayer or t.showSelf)) then
		removeTag(player)
		return
	end

	local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local tag = getTag(player, head)
	local tx = cfg.text
	local fonts = FONT_MAP[tx.font] or FONT_MAP.Gotham

	tag.gui.Size = UDim2.fromOffset(380, tx.tagSize + tx.subSize * 2 + 14)
	tag.gui.StudsOffset = Vector3.new(0, 2.4 + (tx.tagSize + tx.subSize * 2) / 30, 0)
	tag.gui.MaxDistance = t.maxDistance
	tag.gui.AlwaysOnTop = cfg.pred.throughWalls

	tag.main.Size = UDim2.new(1, 0, 0, tx.tagSize + 6)
	tag.main.Font = fonts.bold
	tag.main.TextSize = tx.tagSize
	tag.main.TextStrokeTransparency = tx.outline
	tag.main.Text = d.label
	tag.main.TextColor3 = labelColor(d)

	tag.sub.Position = UDim2.fromOffset(0, tx.tagSize + 6)
	tag.sub.Size = UDim2.new(1, 0, 0, tx.subSize * 2 + 8)
	tag.sub.Font = fonts.normal
	tag.sub.TextSize = tx.subSize
	tag.sub.TextStrokeTransparency = math.min(tx.outline + 0.05, 1)

	local parts = {}
	if not d.hasResult then
		table.insert(parts, string.format("analizando %d/%d s", math.floor(d.elapsed), t.interval))
	else
		if t.showScore then
			table.insert(parts, string.format("imprevisibilidad %d%%", math.floor(d.score + 0.5)))
		end
		if t.showReason then table.insert(parts, d.reason) end
	end
	if t.showSpeed then
		table.insert(parts, string.format("%d studs/s", math.floor(d.speed + 0.5)))
	end
	if t.showDistance and myHRP then
		table.insert(parts, string.format("%d studs", math.floor((d.hrp.Position - myHRP.Position).Magnitude + 0.5)))
	end
	tag.sub.Text = table.concat(parts, "  •  ")
end

----------------------------------------------------------------
-- PREDICCIÓN VISUAL
----------------------------------------------------------------
local vizFolder = Instance.new("Folder")
vizFolder.Name = "PrediccionViz"
vizFolder.Parent = workspace

local viz = {}

local function makePart(shape)
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Parent = vizFolder
	return p
end

local function drawPoly(pool, points, width, color, baseT)
	local n = #points - 1
	for i = 1, n do
		local seg = pool[i]
		if not seg or not seg.Parent then
			seg = makePart()
			pool[i] = seg
		end
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		if len > 0.01 then
			seg.Color = color
			seg.Transparency = baseT + (1 - baseT) * (i / n) * 0.7
			seg.Size = Vector3.new(width, width, len)
			seg.CFrame = CFrame.lookAt((a + b) / 2, b)
		else
			seg.Transparency = 1
		end
	end
	for i = #pool, n + 1, -1 do
		pool[i]:Destroy()
		pool[i] = nil
	end
end

local function clearPool(pool)
	for i = #pool, 1, -1 do
		pool[i]:Destroy()
		pool[i] = nil
	end
end

local function hidePart(v, key)
	if v[key] then
		v[key]:Destroy()
		v[key] = nil
	end
end

local function clearViz(player)
	local v = viz[player]
	if v then
		clearPool(v.segs)
		hidePart(v, "endBall")
		hidePart(v, "leadBall")
		viz[player] = nil
	end
end

local function updatePrediction()
	local pr = cfg.pred
	local myChar = LocalPlayer.Character
	local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local d = tracker[player]
			local hrp = d and d.hrp
			local active = (pr.path or pr.lead) and myHRP and hrp and hrp.Parent
				and (hrp.Position - myHRP.Position).Magnitude <= pr.maxDistance
				and d.vel.Magnitude > 1

			if active then
				local v = viz[player]
				if not v then
					v = { segs = {} }
					viz[player] = v
				end
				local color = labelColor(d)
				local base = hrp.Position - Vector3.new(0, 2.6, 0)

				if pr.path then
					local points = {}
					for i = 0, SEGMENTS do
						local t = pr.horizon * i / SEGMENTS
						local p = base + d.vel * t
						if pr.useAccel then p += d.acc * (0.5 * t * t) end
						points[i + 1] = p
					end
					drawPoly(v.segs, points, pr.width, color, pr.transparency)
					if pr.endMarker then
						local ball = v.endBall
						if not ball or not ball.Parent then
							ball = makePart(Enum.PartType.Ball)
							v.endBall = ball
						end
						ball.Color = color
						ball.Size = Vector3.one * (pr.width * 3 + 0.4)
						ball.Transparency = pr.transparency
						ball.Position = points[SEGMENTS + 1]
					else
						hidePart(v, "endBall")
					end
				else
					clearPool(v.segs)
					hidePart(v, "endBall")
				end

				local leadPos
				if pr.lead then
					local D = hrp.Position - myHRP.Position
					local V = d.vel
					local s = pr.projectileSpeed
					local a = V:Dot(V) - s * s
					local b = 2 * D:Dot(V)
					local c = D:Dot(D)
					local t
					if math.abs(a) < 1e-4 then
						if b < 0 then t = -c / b end
					else
						local disc = b * b - 4 * a * c
						if disc >= 0 then
							local sq = math.sqrt(disc)
							local t1, t2 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
							if t1 > 0 and t2 > 0 then
								t = math.min(t1, t2)
							elseif t1 > 0 then
								t = t1
							elseif t2 > 0 then
								t = t2
							end
						end
					end
					if t and t > 0 and t <= 4 then leadPos = hrp.Position + V * t end
				end
				if leadPos then
					local ball = v.leadBall
					if not ball or not ball.Parent then
						ball = makePart(Enum.PartType.Ball)
						v.leadBall = ball
					end
					ball.Color = Color3.fromRGB(255, 170, 60)
					ball.Size = Vector3.one * 1.4
					ball.Transparency = 0.15
					ball.Position = leadPos
				else
					hidePart(v, "leadBall")
				end
			else
				clearViz(player)
			end
		end
	end
end

local trails = {}
local function removeTrail(player)
	local t = trails[player]
	if t then
		t.trail:Destroy()
		t.a0:Destroy()
		t.a1:Destroy()
		trails[player] = nil
	end
end

local function updateTrail(player)
	local d = tracker[player]
	local hrp = d and d.hrp
	if not (cfg.pred.trail and hrp and hrp.Parent and player ~= LocalPlayer) then
		removeTrail(player)
		return
	end
	local t = trails[player]
	if not t or t.trail.Parent ~= hrp then
		removeTrail(player)
		local a0 = Instance.new("Attachment")
		a0.Name = "PanelTrailA0"
		a0.Position = Vector3.new(0, 0.4, 0)
		a0.Parent = hrp
		local a1 = Instance.new("Attachment")
		a1.Name = "PanelTrailA1"
		a1.Position = Vector3.new(0, -0.4, 0)
		a1.Parent = hrp
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.FaceCamera = true
		tr.LightEmission = 1
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		tr.Parent = hrp
		t = { a0 = a0, a1 = a1, trail = tr }
		trails[player] = t
	end
	t.trail.Lifetime = cfg.pred.trailTime
	t.trail.Color = ColorSequence.new(labelColor(d))
end

local highlights = {}
local function removeHighlight(player)
	if highlights[player] then
		highlights[player]:Destroy()
		highlights[player] = nil
	end
end

local function updateHighlight(player)
	local char = player.Character
	local d = tracker[player]
	if not (cfg.pred.highlight and char and d and player ~= LocalPlayer) then
		removeHighlight(player)
		return
	end
	local h = highlights[player]
	if not h or h.Parent ~= char then
		if h then h:Destroy() end
		h = Instance.new("Highlight")
		h.Name = "PanelHighlight"
		h.Parent = char
		highlights[player] = h
	end
	local c = labelColor(d)
	h.FillColor, h.OutlineColor = c, c
	h.FillTransparency, h.OutlineTransparency = 0.85, 0.25
	h.DepthMode = cfg.pred.throughWalls and Enum.HighlightDepthMode.AlwaysOnTop
		or Enum.HighlightDepthMode.Occluded
end

----------------------------------------------------------------
-- RUTAS: más impredecible (jugador enfrente) y camino seguro (grupo)
----------------------------------------------------------------
local FRONT_COLOR = Color3.fromRGB(120, 255, 140)
local SAFE_COLOR = Color3.fromRGB(70, 230, 200)
local WARN_COLOR = Color3.fromRGB(255, 130, 80)

local routeViz = { front = {}, frontBall = nil, safe = {}, safeBall = nil, zones = {} }
local routeState = { dir = nil }

local function clearFront()
	clearPool(routeViz.front)
	hidePart(routeViz, "frontBall")
	routeState.dir = nil
end

local function clearSafe()
	clearPool(routeViz.safe)
	hidePart(routeViz, "safeBall")
	for player, part in pairs(routeViz.zones) do
		part:Destroy()
		routeViz.zones[player] = nil
	end
end

local function isEnemy(player)
	if not cfg.route.onlyEnemies then return true end
	return not (player.Team ~= nil and player.Team == LocalPlayer.Team)
end

local function getForward(hrp)
	local look
	local cam = workspace.CurrentCamera
	if cfg.route.forwardMode == "Cámara" and cam then
		look = cam.CFrame.LookVector
	else
		look = hrp.CFrame.LookVector
	end
	look = look * FLAT
	if look.Magnitude < 0.01 then look = hrp.CFrame.LookVector * FLAT end
	return look.Unit
end

local function habitProbability(myData, dir)
	if not myData or myData.prevSym == nil then return 0.3 end
	local row = myData.markov[myData.prevSym]
	if not row then return 0.3 end
	local total = 0
	for _, c in pairs(row) do total += c end
	if total <= 0 then return 0.3 end
	local s = sectorOf(dir)
	local p = (row[s] or 0) + 0.5 * ((row[(s % 8) + 1] or 0) + (row[((s - 2) % 8) + 1] or 0))
	return clamp01(p / total)
end

-- Elige la dirección que los rivales de enfrente menos esperan
local function pickUnpredictable(myPos, forward, walk, myVel, myData, front)
	local rt = cfg.route
	local expectDir = myVel.Magnitude > 3 and myVel.Unit or forward
	local bestScore, bestDir = -math.huge, forward

	for k = -6, 6 do
		local dir = rotateY(forward, math.rad(k * 15))
		local minDist = math.huge
		for j = 1, 6 do
			local t = j * 0.2
			local me = myPos + dir * walk * t
			local expected = myPos + expectDir * walk * t -- donde me esperan
			for _, o in ipairs(front) do
				local op = o.d.hrp.Position
				local toExp = (expected - op) * FLAT
				local travel = math.min(toExp.Magnitude, math.max(o.d.walk, 8) * t)
				local oPos = op + (toExp.Magnitude > 0.01 and toExp.Unit or Vector3.zero) * travel
				minDist = math.min(minDist, ((me - oPos) * FLAT).Magnitude)
			end
		end
		local safe = clamp01(minDist / rt.safeDist)
		local angDiff = math.acos(math.clamp(dir:Dot(expectDir), -1, 1))
		local unp = 0.6 * clamp01(angDiff / (math.pi / 2)) + 0.4 * (1 - habitProbability(myData, dir))
		local progress = math.max(0, dir:Dot(forward))
		local score = rt.wSafe * safe + rt.wUnp * unp + rt.wProg * progress
		if score > bestScore then bestScore, bestDir = score, dir end
	end
	return bestDir
end

-- Camino que rodea al grupo manteniendo distancia
local function computeSafePath(startPos, forward, walk, nearList)
	local rt = cfg.route
	local step = 5
	local n = math.max(2, math.floor(rt.pathLength / step))
	local pts = { startPos }
	local cur, heading, tCum = startPos, forward, 0
	local pathMin = math.huge

	for _ = 1, n do
		local bestScore, bestDir, bestClear = -math.huge, heading, 0
		for k = -4, 4 do
			local dir = rotateY(heading, math.rad(k * 15))
			local nxt = cur + dir * step
			local t = tCum + step / walk
			local clearance = math.huge
			for _, o in ipairs(nearList) do
				local op = o.d.hrp.Position + o.d.vel * math.min(t, 1.5)
				clearance = math.min(clearance, distToSegment(op, cur, nxt))
			end
			local safe = math.min(clearance, rt.safeDist) / rt.safeDist
			local score = safe * 3 + dir:Dot(forward) - (math.abs(k) / 4) * 0.35
			if clearance < 3 then score -= 5 end
			if score > bestScore then bestScore, bestDir, bestClear = score, dir, clearance end
		end
		heading = bestDir
		cur = cur + bestDir * step
		tCum += step / walk
		pathMin = math.min(pathMin, bestClear)
		table.insert(pts, cur)
	end
	return pts, pathMin
end

local function updateRoutes()
	local rt = cfg.route
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	if not (hrp and hum) or not (rt.frontEnabled or rt.safeEnabled) then
		clearFront()
		clearSafe()
		return
	end

	local myPos = hrp.Position
	local base = myPos - Vector3.new(0, 2.6, 0)
	local forward = getForward(hrp)
	local walk = math.max(hum.WalkSpeed, 8)
	local myData = tracker[LocalPlayer]
	local myVel = myData and myData.vel or Vector3.zero

	local others = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and isEnemy(player) then
			local d = tracker[player]
			if d and d.hrp and d.hrp.Parent then
				local off = d.hrp.Position - myPos
				table.insert(others, { player = player, d = d, off = off, dist = (off * FLAT).Magnitude })
			end
		end
	end

	-- 1) Ruta más impredecible con un jugador enfrente
	if rt.frontEnabled then
		local front = {}
		for _, o in ipairs(others) do
			if o.dist <= rt.frontRange and o.dist > 0.5 then
				local dirTo = (o.off * FLAT).Unit
				local ang = math.deg(math.acos(math.clamp(dirTo:Dot(forward), -1, 1)))
				if ang <= rt.frontCone then table.insert(front, o) end
			end
		end
		if #front > 0 then
			local best = pickUnpredictable(myPos, forward, walk, myVel, myData, front)
			local smoothed = routeState.dir and routeState.dir:Lerp(best, 0.25) or best
			if smoothed.Magnitude < 0.01 then smoothed = best end
			routeState.dir = smoothed.Unit

			local pts = {}
			for i = 0, SEGMENTS do
				pts[i + 1] = base + routeState.dir * (rt.frontLength * i / SEGMENTS)
			end
			drawPoly(routeViz.front, pts, rt.width, FRONT_COLOR, 0.1)

			local ball = routeViz.frontBall
			if not ball or not ball.Parent then
				ball = makePart(Enum.PartType.Ball)
				routeViz.frontBall = ball
			end
			ball.Color = FRONT_COLOR
			ball.Size = Vector3.one * (rt.width * 3 + 0.5)
			ball.Transparency = 0.1
			ball.Position = pts[#pts]
		else
			clearFront()
		end
	else
		clearFront()
	end

	-- 2) Camino seguro entre un grupo cercano
	if rt.safeEnabled then
		local nearList = {}
		for _, o in ipairs(others) do
			if o.dist <= rt.nearDist then table.insert(nearList, o) end
		end
		if #nearList >= rt.groupMin then
			local pts, pathMin = computeSafePath(base, forward, walk, nearList)
			local color = WARN_COLOR:Lerp(SAFE_COLOR, clamp01(pathMin / rt.safeDist))
			drawPoly(routeViz.safe, pts, rt.width, color, 0.1)

			local ball = routeViz.safeBall
			if not ball or not ball.Parent then
				ball = makePart(Enum.PartType.Ball)
				routeViz.safeBall = ball
			end
			ball.Color = color
			ball.Size = Vector3.one * (rt.width * 3 + 0.5)
			ball.Transparency = 0.1
			ball.Position = pts[#pts]

			-- zonas de peligro alrededor de cada jugador del grupo
			local inNear = {}
			if rt.showZones then
				for _, o in ipairs(nearList) do
					inNear[o.player] = true
					local zone = routeViz.zones[o.player]
					if not zone or not zone.Parent then
						zone = makePart(Enum.PartType.Cylinder)
						routeViz.zones[o.player] = zone
					end
					zone.Color = Color3.fromRGB(255, 90, 90)
					zone.Transparency = 0.82
					zone.Size = Vector3.new(0.12, rt.safeDist * 2, rt.safeDist * 2)
					zone.CFrame = CFrame.new(o.d.hrp.Position - Vector3.new(0, 2.7, 0))
						* CFrame.Angles(0, 0, math.pi / 2)
				end
			end
			for player, zone in pairs(routeViz.zones) do
				if not inNear[player] then
					zone:Destroy()
					routeViz.zones[player] = nil
				end
			end
		else
			clearSafe()
		end
	else
		clearSafe()
	end
end

Players.PlayerRemoving:Connect(function(player)
	removeLine(player)
	removeTag(player)
	clearViz(player)
	removeTrail(player)
	removeHighlight(player)
	tracker[player] = nil
end)

----------------------------------------------------------------
-- HELPERS DE UI
----------------------------------------------------------------
local activeSlider = nil
local panelDrag = nil

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
	return c
end

local function round(inst)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = inst
end

local function newLabel(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = font or Enum.Font.Gotham
	l.TextColor3 = color or THEME.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function nextOrder(page)
	local n = (page:GetAttribute("n") or 0) + 1
	page:SetAttribute("n", n)
	return n
end

local function fmtPct(v) return math.floor(v * 100 + 0.5) .. "%" end
local function fmtDeg(v) return math.floor(v * 360 + 0.5) .. "°" end

local rainbowKeys = {}
for i = 0, 6 do
	table.insert(rainbowKeys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
end
local RAINBOW = ColorSequence.new(rainbowKeys)

----------------------------------------------------------------
-- EFECTO: PIEZAS DE ROMPECABEZAS AZULES (estilo Isagi)
----------------------------------------------------------------
local fxGui = Instance.new("ScreenGui")
fxGui.Name = "EfectoPuzzle"
fxGui.ResetOnSpawn = false
fxGui.IgnoreGuiInset = true
fxGui.DisplayOrder = 1
fxGui.Parent = PlayerGui

local pieces = {}
local rng = Random.new()
local fxTime = 0

local function recolorPiece(p)
	local h = cfg.fx.hue
	local base = Color3.fromHSV(h, 0.75, 1)
	local light = Color3.fromHSV(h, 0.35, 1)
	local dark = Color3.fromHSV(h, 0.9, 0.5)
	for _, f in ipairs(p.fills) do f.BackgroundColor3 = base end
	if p.grad then p.grad.Color = ColorSequence.new(light, base) end
	for _, s in ipairs(p.sockets) do s.BackgroundColor3 = dark end
	for _, img in ipairs(p.images) do img.ImageColor3 = base end
end

local function recolorAllPieces()
	for _, p in ipairs(pieces) do recolorPiece(p) end
end

local function resetPiece(p, anywhere)
	p.x0 = rng:NextNumber(0.03, 0.97)
	p.y = anywhere and rng:NextNumber(-0.05, 1.05) or rng:NextNumber(1.05, 1.25)
	p.speed = rng:NextNumber(0.045, 0.12)
	p.phase = rng:NextNumber(0, math.pi * 2)
	p.freq = rng:NextNumber(0.4, 1.0)
	p.amp = rng:NextNumber(0.01, 0.035)
	p.rot = rng:NextNumber(0, 360)
	p.rotSpeed = rng:NextNumber(-30, 30)
	p.scale = rng:NextNumber(0.6, 1.3)
	p.alpha = rng:NextNumber(0.5, 1)
end

local function createPiece()
	local g = Instance.new("CanvasGroup")
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	g.GroupTransparency = 1
	g.Parent = fxGui

	local p = { group = g, fills = {}, sockets = {}, images = {} }

	local function circle(cx, cy, d, socket)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(cx, cy)
		f.Size = UDim2.fromScale(d, d)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = socket and 0.35 or 0
		f.Parent = g
		round(f)
		table.insert(socket and p.sockets or p.fills, f)
	end

	if PUZZLE_IMAGE_ID ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = PUZZLE_IMAGE_ID
		img.Parent = g
		table.insert(p.images, img)
	else
		local body = Instance.new("Frame")
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.Position = UDim2.fromScale(0.5, 0.5)
		body.Size = UDim2.fromScale(0.7, 0.7)
		body.BorderSizePixel = 0
		body.Parent = g
		corner(body, 4)
		local grad = Instance.new("UIGradient")
		grad.Rotation = 45
		grad.Parent = body
		p.grad = grad
		table.insert(p.fills, body)

		circle(0.5, 0.15, 0.30, false)
		circle(0.85, 0.5, 0.30, false)
		circle(0.24, 0.5, 0.20, true)
		circle(0.5, 0.76, 0.20, true)
	end

	recolorPiece(p)
	resetPiece(p, true)
	return p
end

local function updateFx(dt)
	fxGui.Enabled = cfg.fx.enabled
	if not cfg.fx.enabled then return end
	fxTime += dt

	while #pieces < cfg.fx.density do
		table.insert(pieces, createPiece())
	end
	while #pieces > cfg.fx.density do
		table.remove(pieces).group:Destroy()
	end

	for _, p in ipairs(pieces) do
		p.y -= p.speed * cfg.fx.speed * dt
		if p.y < -0.12 then resetPiece(p, false) end
		p.rot += p.rotSpeed * dt

		local prog = (1.08 - p.y) / 1.2
		local fade = math.clamp(math.min(prog / 0.12, (1 - prog) / 0.25), 0, 1)
		local size = 44 * p.scale * cfg.fx.size

		p.group.Size = UDim2.fromOffset(size, size)
		p.group.Position = UDim2.fromScale(p.x0 + math.sin(fxTime * p.freq + p.phase) * p.amp, p.y)
		p.group.Rotation = p.rot
		p.group.GroupTransparency = 1 - cfg.fx.opacity * p.alpha * fade
	end
end

----------------------------------------------------------------
-- PANEL PRINCIPAL (más ancho)
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PanelPro"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = PlayerGui

local panel = Instance.new("CanvasGroup")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(500, 540)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0, 270, 0.5, 0)
panel.BackgroundColor3 = THEME.bg
panel.BackgroundTransparency = cfg.ui.panelTransparency
panel.BorderSizePixel = 0
panel.GroupTransparency = 1
panel.Visible = false
panel.Parent = gui
corner(panel, 14)

local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.4
panelStroke.Parent = panel
onAccent(function() panelStroke.Color = THEME.accent end)

local panelScale = Instance.new("UIScale")
panelScale.Scale = 0.9 * cfg.ui.scale
panelScale.Parent = panel

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundTransparency = 1
header.Parent = panel

local title = newLabel(header, "Panel de herramientas", 17, THEME.text, Enum.Font.GothamBold)
title.Position = UDim2.fromOffset(18, 0)
title.Size = UDim2.new(1, -130, 1, 0)

local hint = newLabel(header, "[ - ] cerrar", 12, THEME.subtext)
hint.AnchorPoint = Vector2.new(1, 0)
hint.Position = UDim2.new(1, -18, 0, 0)
hint.Size = UDim2.fromOffset(90, 46)
hint.TextXAlignment = Enum.TextXAlignment.Right

header.InputBegan:Connect(function(input)
	if isPointer(input) then
		panelDrag = { start = input.Position, pos = panel.Position }
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if activeSlider then activeSlider(input.Position.X) end
	if panelDrag then
		local d = input.Position - panelDrag.start
		local p = panelDrag.pos
		panel.Position = UDim2.new(p.X.Scale, p.X.Offset + d.X, p.Y.Scale, p.Y.Offset + d.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if isPointer(input) then
		activeSlider = nil
		panelDrag = nil
	end
end)

local TAB_NAMES = { "Línea", "Predicción", "Rutas", "Etiquetas", "Tabla", "Visual" }

local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(0, 46)
tabBar.Size = UDim2.new(1, 0, 0, 34)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local indicator = Instance.new("Frame")
indicator.AnchorPoint = Vector2.new(0, 1)
indicator.Size = UDim2.new(1 / #TAB_NAMES, -14, 0, 3)
indicator.Position = UDim2.new(0, 7, 1, 0)
indicator.BorderSizePixel = 0
indicator.Parent = tabBar
corner(indicator, 2)
onAccent(function() indicator.BackgroundColor3 = THEME.accent end)

local pageHolder = Instance.new("Frame")
pageHolder.Position = UDim2.fromOffset(0, 84)
pageHolder.Size = UDim2.new(1, 0, 1, -84)
pageHolder.BackgroundTransparency = 1
pageHolder.ClipsDescendants = true
pageHolder.Parent = panel

local function newPage()
	local p = Instance.new("ScrollingFrame")
	p.Size = UDim2.fromScale(1, 1)
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	p.ScrollBarThickness = 3
	p.CanvasSize = UDim2.new()
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.Visible = false
	p.Parent = pageHolder
	onAccent(function() p.ScrollBarImageColor3 = THEME.accent end)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = p

	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 10)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = p
	return p
end

local pages, tabButtons = {}, {}

local function selectTab(i)
	for j, page in ipairs(pages) do
		page.Visible = (j == i)
		TweenService:Create(tabButtons[j], TweenInfo.new(0.15), {
			TextColor3 = (j == i) and THEME.text or THEME.subtext,
		}):Play()
	end
	TweenService:Create(indicator, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new((i - 1) / #TAB_NAMES, 7, 1, 0),
	}):Play()
end

for i, name in ipairs(TAB_NAMES) do
	pages[i] = newPage()
	local b = Instance.new("TextButton")
	b.Text = name
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.TextColor3 = THEME.subtext
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Position = UDim2.fromScale((i - 1) / #TAB_NAMES, 0)
	b.Size = UDim2.fromScale(1 / #TAB_NAMES, 1)
	b.Parent = tabBar
	b.Activated:Connect(function() selectTab(i) end)
	tabButtons[i] = b
end

----------------------------------------------------------------
-- CONTROLES
----------------------------------------------------------------
local function section(page, text)
	local l = newLabel(page, text, 13, THEME.subtext, Enum.Font.GothamBold)
	l.Size = UDim2.new(1, 0, 0, 20)
	l.LayoutOrder = nextOrder(page)
end

local function note(page, text)
	local l = newLabel(page, text, 12, THEME.subtext)
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.LayoutOrder = nextOrder(page)
	return l
end

local function toggle(page, text, tbl, key)
	local row = Instance.new("TextButton")
	row.Text = ""
	row.AutoButtonColor = false
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundColor3 = THEME.surface
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder(page)
	row.Parent = page
	corner(row)

	local label = newLabel(row, text, 13)
	label.Position = UDim2.fromOffset(14, 0)
	label.Size = UDim2.new(1, -76, 1, 0)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -14, 0.5, 0)
	track.Size = UDim2.fromOffset(40, 22)
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 11)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(16, 16)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 8)

	local function refresh(animate)
		local on = tbl[key]
		local info = TweenInfo.new(animate and 0.18 or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(track, info, { BackgroundColor3 = on and THEME.accent or THEME.off }):Play()
		TweenService:Create(knob, info, {
			Position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end

	row.Activated:Connect(function()
		tbl[key] = not tbl[key]
		refresh(true)
	end)
	onAccent(function() refresh(false) end)
end

local function choice(page, text, tbl, key, options)
	local row = Instance.new("TextButton")
	row.Text = ""
	row.AutoButtonColor = false
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundColor3 = THEME.surface
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder(page)
	row.Parent = page
	corner(row)

	local label = newLabel(row, text, 13)
	label.Position = UDim2.fromOffset(14, 0)
	label.Size = UDim2.new(0.55, 0, 1, 0)

	local value = newLabel(row, "", 13, THEME.accent, Enum.Font.GothamBold)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -14, 0, 0)
	value.Size = UDim2.new(0.45, 0, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right

	local function refresh() value.Text = tbl[key] .. "  ›" end
	row.Activated:Connect(function()
		local idx = table.find(options, tbl[key]) or 0
		tbl[key] = options[(idx % #options) + 1]
		refresh()
	end)
	onAccent(function() value.TextColor3 = THEME.accent end)
	refresh()
end

local function textInput(page, text, tbl, key, onChange)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = THEME.surface
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder(page)
	row.Parent = page
	corner(row)

	local label = newLabel(row, text, 13)
	label.Position = UDim2.fromOffset(14, 0)
	label.Size = UDim2.new(0.5, 0, 1, 0)

	local box = Instance.new("TextBox")
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, -14, 0.5, 0)
	box.Size = UDim2.new(0.42, 0, 0, 26)
	box.BackgroundColor3 = THEME.off
	box.BorderSizePixel = 0
	box.TextColor3 = THEME.text
	box.PlaceholderColor3 = THEME.subtext
	box.PlaceholderText = "nombre..."
	box.Font = Enum.Font.Gotham
	box.TextSize = 13
	box.ClearTextOnFocus = false
	box.Text = tbl[key]
	box.Parent = row
	corner(box, 6)

	box.FocusLost:Connect(function()
		tbl[key] = box.Text
		if onChange then onChange(box.Text) end
	end)
end

local function slider(page, text, tbl, key, min, max, step, opts)
	opts = opts or {}

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 52)
	holder.BackgroundColor3 = THEME.surface
	holder.BorderSizePixel = 0
	holder.LayoutOrder = nextOrder(page)
	holder.Parent = page
	corner(holder)

	local name = newLabel(holder, text, 13)
	name.Position = UDim2.fromOffset(14, 6)
	name.Size = UDim2.new(0.65, 0, 0, 18)

	local valueLabel = newLabel(holder, "", 13, THEME.subtext, Enum.Font.GothamMedium)
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -14, 0, 6)
	valueLabel.Size = UDim2.new(0.35, 0, 0, 18)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(14, 26)
	hit.Size = UDim2.new(1, -28, 0, 22)
	hit.Parent = holder

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.Size = UDim2.new(1, 0, 0, 6)
	bar.BackgroundColor3 = THEME.off
	bar.BorderSizePixel = 0
	bar.Parent = hit
	corner(bar, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	corner(fill, 3)

	if opts.gradient then
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = opts.gradient
		g.Parent = bar
		fill.Visible = false
	else
		onAccent(function() fill.BackgroundColor3 = THEME.accent end)
	end

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = bar
	corner(knob, 7)

	local function setValue(v, fromUser)
		v = math.clamp(min + math.round((v - min) / step) * step, min, max)
		tbl[key] = v
		local a = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		valueLabel.Text = opts.format and opts.format(v)
			or (string.format("%g", v) .. (opts.suffix or ""))
		if fromUser and opts.onChange then opts.onChange(v) end
	end

	local function update(x)
		local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		setValue(min + (max - min) * a, true)
	end

	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			activeSlider = update
			update(input.Position.X)
		end
	end)

	setValue(tbl[key], false)
end

local function colorPicker(page, text, tbl)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = THEME.surface
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder(page)
	row.Parent = page
	corner(row)

	local label = newLabel(row, text, 13)
	label.Position = UDim2.fromOffset(14, 0)
	label.Size = UDim2.new(0.6, 0, 1, 0)

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(1, 0.5)
	swatch.Position = UDim2.new(1, -14, 0.5, 0)
	swatch.Size = UDim2.fromOffset(50, 18)
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	corner(swatch, 9)

	local function refresh() swatch.BackgroundColor3 = Color3.fromHSV(tbl.h, tbl.s, tbl.v) end
	refresh()

	slider(page, "Tono", tbl, "h", 0, 1, 0.01, { gradient = RAINBOW, format = fmtDeg, onChange = refresh })
	slider(page, "Saturación", tbl, "s", 0, 1, 0.01, { format = fmtPct, onChange = refresh })
	slider(page, "Brillo", tbl, "v", 0, 1, 0.01, { format = fmtPct, onChange = refresh })
end

----------------------------------------------------------------
-- HUD: jugadores cercanos
----------------------------------------------------------------
local hud = Instance.new("Frame")
hud.Name = "HudJugadores"
hud.AnchorPoint = Vector2.new(1, 0)
hud.Position = UDim2.new(1, -16, 0, 16)
hud.Size = UDim2.fromOffset(270, 0)
hud.AutomaticSize = Enum.AutomaticSize.Y
hud.BackgroundColor3 = THEME.bg
hud.BackgroundTransparency = 0.25
hud.BorderSizePixel = 0
hud.Visible = false
hud.Parent = gui
corner(hud, 10)

local hudTitle
do
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = hud
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 3)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = hud
	hudTitle = newLabel(hud, "Jugadores cercanos", 12, THEME.subtext, Enum.Font.GothamBold)
	hudTitle.Size = UDim2.new(1, 0, 0, 16)
	hudTitle.LayoutOrder = 0
end

local hudRows = {}
local function getHudRow(i)
	local r = hudRows[i]
	if not r then
		r = newLabel(hud, "", 12, THEME.text)
		r.RichText = true
		r.LayoutOrder = i
		hudRows[i] = r
	end
	return r
end

local function updateHud()
	if not cfg.pred.hud then
		hud.Visible = false
		return
	end
	local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not myHRP then
		hud.Visible = false
		return
	end

	local size = cfg.text.hudSize
	local fonts = FONT_MAP[cfg.text.font] or FONT_MAP.Gotham
	hud.Size = UDim2.fromOffset(250 + (size - 12) * 14, 0)
	hudTitle.TextSize = size
	hudTitle.Font = fonts.bold
	hudTitle.Size = UDim2.new(1, 0, 0, size + 4)

	local list = {}
	for player, d in pairs(tracker) do
		if player ~= LocalPlayer and d.hrp and d.hrp.Parent then
			local dist = (d.hrp.Position - myHRP.Position).Magnitude
			if dist <= cfg.pred.maxDistance then
				table.insert(list, { player = player, d = d, dist = dist })
			end
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	hud.Visible = #list > 0

	for i = 1, math.max(cfg.pred.hudCount, #hudRows) do
		local item = (i <= cfg.pred.hudCount) and list[i] or nil
		if item then
			local row = getHudRow(i)
			row.Visible = true
			row.TextSize = size
			row.Font = fonts.normal
			row.Size = UDim2.new(1, 0, 0, size + 4)
			local d = item.d
			local pct = d.hasResult and string.format("%d%%", math.floor(d.score + 0.5)) or "..."
			row.Text = string.format(
				'%s  <font color="#%s">%s</font>  %s  %d studs',
				escapeRich(string.sub(item.player.DisplayName, 1, 12)),
				labelColor(d):ToHex(), d.label, pct, math.floor(item.dist + 0.5)
			)
		elseif hudRows[i] then
			hudRows[i].Visible = false
		end
	end
end

----------------------------------------------------------------
-- CONTENIDO DE LAS PESTAÑAS
----------------------------------------------------------------
local pLine, pPred, pRoute, pTags, pTable, pVis = pages[1], pages[2], pages[3], pages[4], pages[5], pages[6]

-- Línea
section(pLine, "General")
toggle(pLine, "Línea activada", cfg.line, "enabled")
toggle(pLine, "Mostrar mi propia línea", cfg.line, "showSelf")
choice(pLine, "Sale desde", cfg.line, "origin", { "Cabeza", "Pecho" })
section(pLine, "Tamaño")
slider(pLine, "Largo", cfg.line, "length", 1, 150, 1, { suffix = " studs" })
slider(pLine, "Ancho", cfg.line, "width", 0.05, 2, 0.05)
slider(pLine, "Separación del inicio", cfg.line, "startOffset", 0, 5, 0.1)
section(pLine, "Apariencia")
colorPicker(pLine, "Color", cfg.line)
toggle(pLine, "Modo arcoíris", cfg.line, "rainbow")
toggle(pLine, "Efecto neón", cfg.line, "neon")
slider(pLine, "Transparencia", cfg.line, "transparency", 0, 1, 0.05, { format = fmtPct })
toggle(pLine, "Cortar al chocar con paredes", cfg.line, "stopAtWalls")

-- Predicción
section(pPred, "Trayectoria predicha")
note(pPred, "Proyecta dónde estará cada jugador según su velocidad. Colores: azul = Lento, amarillo = Normal, rojo = Rápido.")
toggle(pPred, "Mostrar trayectoria", cfg.pred, "path")
toggle(pPred, "Marcador al final", cfg.pred, "endMarker")
toggle(pPred, "Usar aceleración", cfg.pred, "useAccel")
slider(pPred, "Tiempo a predecir", cfg.pred, "horizon", 0.3, 3, 0.1, { suffix = " s" })
slider(pPred, "Grosor", cfg.pred, "width", 0.05, 0.6, 0.05)
slider(pPred, "Transparencia", cfg.pred, "transparency", 0, 0.9, 0.05, { format = fmtPct })
section(pPred, "Intercepción")
note(pPred, "Marca naranja: hacia dónde pasar o apuntar para llegar a un jugador que se mueve.")
toggle(pPred, "Mostrar punto de intercepción", cfg.pred, "lead")
slider(pPred, "Velocidad del balón/proyectil", cfg.pred, "projectileSpeed", 10, 400, 5, { suffix = " studs/s" })
section(pPred, "Rastro y resaltado")
toggle(pPred, "Estela de movimiento", cfg.pred, "trail")
slider(pPred, "Duración de la estela", cfg.pred, "trailTime", 0.5, 6, 0.5, { suffix = " s" })
toggle(pPred, "Resaltar según etiqueta", cfg.pred, "highlight")
toggle(pPred, "Etiquetas/resaltado a través de paredes", cfg.pred, "throughWalls")
section(pPred, "Lista de jugadores (HUD)")
toggle(pPred, "Mostrar lista", cfg.pred, "hud")
slider(pPred, "Jugadores en la lista", cfg.pred, "hudCount", 3, 8, 1)
slider(pPred, "Distancia máxima", cfg.pred, "maxDistance", 20, 500, 10, { suffix = " studs" })

-- Rutas
section(pRoute, "Ruta más impredecible (jugador enfrente)")
note(pRoute, "Si hay un rival enfrente, dibuja una línea verde hacia la dirección que menos espera: se aleja de donde te interceptaría, evita tus hábitos de movimiento y aun así avanza.")
toggle(pRoute, "Mostrar ruta impredecible", cfg.route, "frontEnabled")
slider(pRoute, "Alcance del rival", cfg.route, "frontRange", 8, 80, 1, { suffix = " studs" })
slider(pRoute, "Ángulo de 'enfrente'", cfg.route, "frontCone", 15, 90, 1, { suffix = "°" })
slider(pRoute, "Largo de la línea", cfg.route, "frontLength", 5, 50, 1, { suffix = " studs" })
slider(pRoute, "Prioridad: seguridad", cfg.route, "wSafe", 0, 1, 0.05)
slider(pRoute, "Prioridad: impredecible", cfg.route, "wUnp", 0, 1, 0.05)
slider(pRoute, "Prioridad: avanzar", cfg.route, "wProg", 0, 1, 0.05)
choice(pRoute, "Avanzo hacia", cfg.route, "forwardMode", { "Personaje", "Cámara" })
section(pRoute, "Camino seguro entre varios jugadores")
note(pRoute, "Si hay un grupo cerca, traza un camino que los rodea sin acercarte demasiado. Verde azulado = seguro, naranja = ajustado.")
toggle(pRoute, "Mostrar camino seguro", cfg.route, "safeEnabled")
slider(pRoute, "Distancia de 'cerca'", cfg.route, "nearDist", 10, 150, 1, { suffix = " studs" })
slider(pRoute, "Jugadores para formar grupo", cfg.route, "groupMin", 2, 8, 1)
slider(pRoute, "Distancia segura mínima", cfg.route, "safeDist", 3, 25, 1, { suffix = " studs" })
slider(pRoute, "Largo del camino", cfg.route, "pathLength", 10, 100, 5, { suffix = " studs" })
toggle(pRoute, "Mostrar zonas de peligro", cfg.route, "showZones")
toggle(pRoute, "Solo enemigos (otro equipo)", cfg.route, "onlyEnemies")
slider(pRoute, "Grosor de las líneas", cfg.route, "width", 0.05, 0.8, 0.05)

-- Etiquetas
section(pTags, "Análisis de movimiento")
note(pTags, "Lento = predecible · Normal = punto medio · Rápido = impredecible. Moverse mucho no cuenta como Rápido si lo hace con un patrón anticipable.")
toggle(pTags, "Etiquetas activadas", cfg.tags, "enabled")
toggle(pTags, "Incluirme a mí", cfg.tags, "showSelf")
toggle(pTags, "Mostrar la razón", cfg.tags, "showReason")
toggle(pTags, "Mostrar imprevisibilidad (%)", cfg.tags, "showScore")
toggle(pTags, "Mostrar velocidad", cfg.tags, "showSpeed")
toggle(pTags, "Mostrar distancia", cfg.tags, "showDistance")
toggle(pTags, "Suavizar entre análisis", cfg.tags, "smooth")
slider(pTags, "Intervalo de análisis", cfg.tags, "interval", 10, 120, 5, { suffix = " s" })
slider(pTags, "Sensibilidad", cfg.tags, "sensitivity", 0.5, 2, 0.1)
slider(pTags, "Distancia máxima", cfg.tags, "maxDistance", 30, 500, 10, { suffix = " studs" })

-- Tabla
section(pTable, "Detección de balón")
note(pTable, "Escribe el nombre exacto del balón en el Workspace (parte o modelo). Así se sabe quién lo tiene cerca y se detectan debilidades con balón.")
toggle(pTable, "Detectar balón", cfg.tab, "ballEnabled")
textInput(pTable, "Nombre del balón", cfg.tab, "ballName", function() ballPart = nil end)
slider(pTable, "Distancia para 'tiene el balón'", cfg.tab, "possDist", 2, 15, 1, { suffix = " studs" })
section(pTable, "Tabla de jugadores")
note(pTable, "La mirada se estima con la orientación de la cabeza/cuerpo (Roblox no comparte la cámara real de otros). Las debilidades aparecen tras completar un análisis.")
choice(pTable, "Ordenar por", cfg.tab, "sortBy", { "Distancia", "Imprevisibilidad", "Nombre" })
slider(pTable, "Jugadores en la tabla", cfg.tab, "maxRows", 3, 12, 1)

local emptyNote = newLabel(pTable, "No hay otros jugadores analizados todavía.", 12, THEME.subtext)
emptyNote.Size = UDim2.new(1, 0, 0, 20)
emptyNote.LayoutOrder = 499

local tableRows = {}
local function getTableRow(i)
	local r = tableRows[i]
	if r then return r end

	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = THEME.surface
	f.BorderSizePixel = 0
	f.LayoutOrder = 500 + i
	f.Parent = pTable
	corner(f)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = f
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 3)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = f

	local l1 = newLabel(f, "", 13)
	l1.RichText = true
	l1.TextWrapped = true
	l1.Size = UDim2.new(1, 0, 0, 0)
	l1.AutomaticSize = Enum.AutomaticSize.Y
	l1.LayoutOrder = 1

	local l2 = newLabel(f, "", 12, THEME.subtext)
	l2.RichText = true
	l2.TextWrapped = true
	l2.Size = UDim2.new(1, 0, 0, 0)
	l2.AutomaticSize = Enum.AutomaticSize.Y
	l2.LayoutOrder = 2

	r = { frame = f, l1 = l1, l2 = l2 }
	tableRows[i] = r
	return r
end

local function updateTable()
	local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local list = {}
	for player, d in pairs(tracker) do
		if player ~= LocalPlayer and d.hrp and d.hrp.Parent then
			local dist = myHRP and (d.hrp.Position - myHRP.Position).Magnitude or 0
			table.insert(list, { player = player, d = d, dist = dist })
		end
	end

	local sortBy = cfg.tab.sortBy
	table.sort(list, function(a, b)
		if sortBy == "Imprevisibilidad" then
			return a.d.score > b.d.score
		elseif sortBy == "Nombre" then
			return a.player.DisplayName:lower() < b.player.DisplayName:lower()
		end
		return a.dist < b.dist
	end)

	local size = cfg.text.hudSize
	local fonts = FONT_MAP[cfg.text.font] or FONT_MAP.Gotham
	local ballFound = ballPart ~= nil and ballPart.Parent ~= nil
	emptyNote.Visible = #list == 0

	for i = 1, math.max(#tableRows, cfg.tab.maxRows) do
		local item = (i <= cfg.tab.maxRows) and list[i] or nil
		if item then
			local r = getTableRow(i)
			r.frame.Visible = true
			r.l1.TextSize = size + 1
			r.l1.Font = fonts.normal
			r.l2.TextSize = size
			r.l2.Font = fonts.normal

			local d = item.d
			local pct = d.hasResult and string.format("%d%%", math.floor(d.score + 0.5)) or "..."
			local ballTxt = ""
			if ballFound and d.profile then
				ballTxt = string.format("  •  balón %d%%", math.floor(d.profile.possFrac * 100 + 0.5))
			end
			r.l1.Text = string.format(
				'<b>%s</b>   <font color="#%s">%s</font>   imprev. %s   %d studs/s   %d studs%s',
				escapeRich(string.sub(item.player.DisplayName, 1, 16)),
				labelColor(d):ToHex(), d.label, pct,
				math.floor(d.speed + 0.5), math.floor(item.dist + 0.5), ballTxt
			)
			if d.hasResult then
				r.l2.Text = string.format(
					'Mirada: %s\n<font color="#FFB86B">Debilidad:</font> %s',
					d.gaze, escapeRich(d.weakText)
				)
			else
				r.l2.Text = string.format("analizando %d/%d s…", math.floor(d.elapsed), cfg.tags.interval)
			end
		elseif tableRows[i] then
			tableRows[i].frame.Visible = false
		end
	end
end

-- Visual
section(pVis, "Efecto piezas azules")
note(pVis, "Piezas de rompecabezas que suben suavemente por la pantalla. Solo decoración: no bloquean clics.")
toggle(pVis, "Efecto activado", cfg.fx, "enabled")
slider(pVis, "Cantidad", cfg.fx, "density", 4, 30, 1)
slider(pVis, "Velocidad", cfg.fx, "speed", 0.3, 2, 0.1)
slider(pVis, "Tamaño", cfg.fx, "size", 0.6, 1.8, 0.1)
slider(pVis, "Opacidad", cfg.fx, "opacity", 0.1, 1, 0.05, { format = fmtPct })
slider(pVis, "Color (tono)", cfg.fx, "hue", 0, 1, 0.01, {
	gradient = RAINBOW, format = fmtDeg, onChange = recolorAllPieces,
})
section(pVis, "Texto")
slider(pVis, "Tamaño de la etiqueta", cfg.text, "tagSize", 10, 36, 1)
slider(pVis, "Tamaño del detalle (bajo la etiqueta)", cfg.text, "subSize", 8, 24, 1)
slider(pVis, "Tamaño del texto de HUD y tabla", cfg.text, "hudSize", 9, 22, 1)
slider(pVis, "Contorno del texto", cfg.text, "outline", 0, 1, 0.05, { format = fmtPct })
choice(pVis, "Fuente", cfg.text, "font", { "Gotham", "Arial", "Código", "Fredoka" })
section(pVis, "Interfaz")
slider(pVis, "Tamaño del menú", cfg.ui, "scale", 0.7, 1.3, 0.05, {
	format = fmtPct,
	onChange = function(v)
		if panel.Visible then panelScale.Scale = v end
	end,
})
slider(pVis, "Color de acento", cfg.ui, "accentHue", 0, 1, 0.01, {
	gradient = RAINBOW, format = fmtDeg, onChange = function(v) setAccent(v) end,
})
slider(pVis, "Transparencia del panel", cfg.ui, "panelTransparency", 0, 0.6, 0.05, {
	format = fmtPct, onChange = function(v) panel.BackgroundTransparency = v end,
})

----------------------------------------------------------------
-- ABRIR / CERRAR CON "-"
----------------------------------------------------------------
local isOpen = false
local openTweens = {}

local function setOpen(open)
	isOpen = open
	for _, t in ipairs(openTweens) do t:Cancel() end
	table.clear(openTweens)

	if open then panel.Visible = true end

	local scaleInfo = open
		and TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		or TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local t1 = TweenService:Create(panelScale, scaleInfo, {
		Scale = open and cfg.ui.scale or 0.9 * cfg.ui.scale,
	})
	local t2 = TweenService:Create(panel, TweenInfo.new(open and 0.22 or 0.18), {
		GroupTransparency = open and 0 or 1,
	})
	table.insert(openTweens, t1)
	table.insert(openTweens, t2)

	t2.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not isOpen then
			panel.Visible = false
		end
	end)

	t1:Play()
	t2:Play()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end -- (también evita abrir/cerrar mientras escribes en una caja de texto)
	if input.KeyCode == Enum.KeyCode.Minus or input.KeyCode == Enum.KeyCode.KeypadMinus then
		setOpen(not isOpen)
	end
end)

----------------------------------------------------------------
-- BUCLES PRINCIPALES
----------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	updateLines()
	updatePrediction()
	updateRoutes()
	updateFx(dt)
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < SAMPLE_INTERVAL then return end
	local step = acc
	acc = 0
	local now = os.clock()

	local ball = cfg.tab.ballEnabled and findBall() or nil
	local ballPos = ball and ball.Position or nil

	for _, player in ipairs(Players:GetPlayers()) do
		sampleMovement(player, step, now, ballPos)
		updateTag(player)
		updateTrail(player)
		updateHighlight(player)
	end
	updateHud()
	if isOpen and pTable.Visible then updateTable() end
end)

selectTab(1)
setOpen(true)
-- ===== PARCHE (pégalo AL FINAL del script anterior) =====
do
	local rawSetOpen = setOpen
	setOpen = function(open)
		-- si el panel activo es el de combate, "-" no abre este
		if LocalPlayer:GetAttribute("PanelMode") == "combate" then return end
		rawSetOpen(open)
	end
	shared.PanelA = {
		setOpen = rawSetOpen,
		panel = panel, pageHolder = pageHolder,
		tracker = tracker, labelColor = labelColor,
		THEME = THEME, onAccent = onAccent, corner = corner,
	}
end
-- LocalScript → StarterPlayer > StarterPlayerScripts  ("PanelCombate")
-- REEMPLAZA al PanelCombate anterior. El parche del script de análisis no cambia.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local FLAT = Vector3.new(1, 0, 1)

local LOCK_KEY = Enum.KeyCode.Y    -- activa/desactiva "mirar al objetivo"
local SWITCH_KEY = Enum.KeyCode.H  -- cambia de objetivo
local SAMPLE = 0.1

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local cfg = {
	lock = {
		enabled = false, mode = "Más cercano", range = 60, fov = 360,
		onlyEnemies = true, includeNpcs = true, los = true, sticky = true, turnSpeed = 540,
		camera = false, camStrength = 0.15,
		marker = true, markerHue = 0.0, markerSize = 26,
	},
	hud = { enabled = true, showStates = true, showDmg = true, showWeak = true, showAttack = true, showPlan = true, size = 13 },
	combat = {
		ringA = false, radiusA = 6, ringB = false, radiusB = 18,
		ringEnemy = false, radiusEnemy = 7, zoneLine = false, observed = false,
		dpsWindow = 5, comboGap = 1.5, finisher = true, finisherPct = 25,
	},
	npc = { enabled = true, range = 150, maxCount = 20 },
	alerts = {
		attack = true, attackRange = 25, onlyFacing = true, flash = false, onlyEnemies = true, npcAttacks = true,
		surround = true, surroundCount = 3, surroundDist = 20,
		radar = false, radarNpcs = true, radarObjects = true, radarSize = 170, radarRange = 80,
	},
	cue = { enabled = false, range = 30, onlyFacing = true, showName = true, size = 150 },
	objects = {
		projectiles = false, projRange = 80, projMinSpeed = 25,
		keywordsOn = false, keywords = "Chest,Item,Pickup,Orb,Drop,Heal",
		prompts = false, tools = false, range = 60, maxLabels = 10, size = 12,
	},
	states = {
		keywords = "Block,Stun,Ragdoll,Parry,Dash,Cooldown,Invincible,IFrame,Guard,Ult,Awakening,Domain",
		forcefield = true, showTag = true, tagSize = 13, recordMoves = true,
	},
	screen = { fovOn = false, fov = 70, zoomOn = false, maxZoom = 60, calm = false, perf = false },
	ui = { accentHue = 0.55, panelTransparency = 0.05, scale = 1 },
}

----------------------------------------------------------------
-- UTILIDADES COMPARTIDAS
----------------------------------------------------------------
local THEME = {
	bg = Color3.fromRGB(16, 16, 22),
	surface = Color3.fromRGB(27, 27, 37),
	off = Color3.fromRGB(70, 70, 88),
	text = Color3.fromRGB(240, 240, 250),
	subtext = Color3.fromRGB(150, 150, 172),
	accent = Color3.fromHSV(cfg.ui.accentHue, 0.65, 1),
}

local accentFns, uiRefresh = {}, {}
local function onAccent(fn) table.insert(accentFns, fn); fn() end
local function setAccent(h)
	THEME.accent = Color3.fromHSV(h, 0.65, 1)
	for _, f in ipairs(accentFns) do f() end
end
local function refreshUI() for _, f in ipairs(uiRefresh) do f() end end

local function clamp01(x) return math.clamp(x, 0, 1) end
local function rotateY(v, a) return CFrame.Angles(0, a, 0):VectorToWorldSpace(v) end
local function escapeRich(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
local function fmtPct(v) return math.floor(v * 100 + 0.5) .. "%" end
local function fmtDeg(v) return math.floor(v * 360 + 0.5) .. "°" end

local function parseList(s)
	local out = {}
	for w in string.gmatch(s, "[^,]+") do
		w = w:lower():gsub("^%s+", ""):gsub("%s+$", "")
		if w ~= "" then table.insert(out, w) end
	end
	return out
end

local function hasAny(list, name)
	local n = name:lower()
	for _, kw in ipairs(list) do
		if n:find(kw, 1, true) then return true end
	end
	return false
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
	return c
end

local function newLabel(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = font or Enum.Font.Gotham
	l.TextColor3 = color or THEME.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function isEnemyBy(key, flag)
	if not flag then return true end
	if typeof(key) == "Instance" and key:IsA("Player") then
		return not (key.Team ~= nil and key.Team == LocalPlayer.Team)
	end
	return true -- los NPCs siempre cuentan como rivales
end

local rk = {}
for i = 0, 6 do table.insert(rk, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1))) end
local RAINBOW = ColorSequence.new(rk)

local NPC_COLOR = Color3.fromRGB(255, 170, 60)
local A = nil -- panel de análisis (script 1), si está disponible

local M = { state = { target = nil, surroundN = 0, flashUntil = 0 }, lists = {}, radarItems = {}, threats = {}, cue = nil }
M.folder = Instance.new("Folder")
M.folder.Name = "CombateViz"
M.folder.Parent = workspace

----------------------------------------------------------------
-- ENTIDADES (jugadores + NPCs): estados, ataques, daño, análisis profundo
----------------------------------------------------------------
do
	local ext, npcs, impact = {}, {}, {}
	M.ext, M.impact = ext, impact
	M.lists.states = parseList(cfg.states.keywords)

	local STUN_WORDS = { "stun", "ragdoll", "knock", "aturd", "freeze", "paraly" }
	local BLOCK_WORDS = { "block", "guard", "parry" }
	local SKIP_ANIMS = { "emote", "dance", "idle", "walk", "run", "jump", "fall", "climb", "swim", "sit", "pose" }
	local ACTION_PRIORITIES = {
		[Enum.AnimationPriority.Action] = true, [Enum.AnimationPriority.Action2] = true,
		[Enum.AnimationPriority.Action3] = true, [Enum.AnimationPriority.Action4] = true,
	}

	local function has(n, words)
		for _, w in ipairs(words) do
			if n:find(w, 1, true) then return true end
		end
		return false
	end

	local function readStates(key, char, hum)
		local s = { list = {}, stun = false, air = false, blocking = false }
		local function add(text, name)
			table.insert(s.list, text)
			local n = name:lower()
			if has(n, STUN_WORDS) then s.stun = true end
			if has(n, BLOCK_WORDS) then s.blocking = true end
		end
		local hs = hum:GetState()
		if hum.PlatformStand then s.stun = true; table.insert(s.list, "Aturdido") end
		if hs == Enum.HumanoidStateType.Ragdoll or hs == Enum.HumanoidStateType.FallingDown
			or hs == Enum.HumanoidStateType.Physics then
			s.stun = true
			table.insert(s.list, "Caído")
		end
		if hum.FloorMaterial == Enum.Material.Air
			and (hs == Enum.HumanoidStateType.Freefall or hs == Enum.HumanoidStateType.Jumping) then
			s.air = true
		end
		if cfg.states.forcefield and char:FindFirstChildOfClass("ForceField") then
			table.insert(s.list, "Invulnerable")
		end
		local function scanAttrs(inst)
			for name, value in pairs(inst:GetAttributes()) do
				if hasAny(M.lists.states, name) then
					if value == true then
						add(name, name)
					elseif type(value) == "number" and value > 0 then
						add(string.format("%s %.1f", name, value), name)
					end
				end
			end
		end
		scanAttrs(char); scanAttrs(hum)
		if key ~= char then scanAttrs(key) end
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("BoolValue") and c.Value and hasAny(M.lists.states, c.Name) then
				add(c.Name, c.Name)
			elseif c:IsA("NumberValue") and c.Value > 0 and hasAny(M.lists.states, c.Name) then
				add(string.format("%s %.1f", c.Name, c.Value), c.Name)
			end
		end
		return s
	end

	local function detectAttacks(e, hum, now)
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then return end
		local current = {}
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			current[track] = true
			if not e.tracks[track] and ACTION_PRIORITIES[track.Priority] and track.Length > 0.15 then
				local name = track.Name ~= "" and track.Name or (track.Animation and track.Animation.Name) or "ataque"
				if not has(name:lower(), SKIP_ANIMS) then
					e.attack = { name = name, start = now, dur = track.Length / math.max(track.Speed, 0.1) }
					e.attackTrack = track
					e.atkEnd = nil
					e.atkCount += 1
					table.insert(e.atkDist, e.dist or 0)
					if #e.atkDist > 40 then table.remove(e.atkDist, 1) end
					if e.lastMove then
						local row = e.moveMarkov[e.lastMove]
						if not row then row = {}; e.moveMarkov[e.lastMove] = row end
						row[name] = (row[name] or 0) + 1
					end
					local last = e.lastUse[name]
					if last then
						local gap = now - last
						if gap > 0.3 then e.minGap[name] = math.min(e.minGap[name] or gap, gap) end
					end
					e.lastUse[name] = now
					e.lastMove, e.lastMoveT = name, now
					if cfg.states.recordMoves then e.moves[name] = (e.moves[name] or 0) + 1 end
				end
			end
		end
		e.tracks = current
		if e.attackTrack and not current[e.attackTrack] then
			e.atkEnd = e.atkEnd or now
			e.attackTrack = nil
		end
	end

	local function sampleEntity(key, char, isNPC, dt, now, myHRP)
		local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or (isNPC and hum.Health <= 0) then
			ext[key] = nil
			return
		end

		local e = ext[key]
		if not e or e.hrp ~= hrp then
			e = {
				key = key, char = char, hrp = hrp, isNPC = isNPC, name = "",
				lastPos = hrp.Position, vel = Vector3.zero,
				hp = hum.Health, maxHp = hum.MaxHealth, lastHp = hum.Health,
				dmg = {}, comboCount = 0, comboDmg = 0, lastHit = -100,
				states = { list = {}, stun = false, air = false, blocking = false }, stunSince = nil,
				tracks = {}, attack = nil, attackTrack = nil, atkEnd = nil, atkCount = 0,
				moves = {}, moveMarkov = {}, lastUse = {}, minGap = {}, lastMove = nil, lastMoveT = 0,
				atkDist = {}, recover = nil, recoverN = 0,
				dodge = { toward = 0, away = 0, side = 0 }, lastDodge = -10, burstActive = false,
				trackedTime = 0, blockTime = 0, approachTime = 0,
				dist = nil, closing = 0, alertedStart = nil,
			}
			ext[key] = e
		end
		e.char = char
		e.name = isNPC and char.Name or key.DisplayName

		local delta = (hrp.Position - e.lastPos) * FLAT
		e.lastPos = hrp.Position
		e.vel = delta.Magnitude < 60 and e.vel:Lerp(delta / dt, 0.5) or Vector3.zero

		if myHRP then
			local dist = ((hrp.Position - myHRP.Position) * FLAT).Magnitude
			if e.dist == nil then e.dist = dist end
			e.closing = e.closing * 0.6 + ((e.dist - dist) / dt) * 0.4
			e.dist = dist
		else
			e.dist = e.dist or 999
		end

		e.hp, e.maxHp = hum.Health, hum.MaxHealth
		if hum.Health < e.lastHp - 0.01 then
			local amount = e.lastHp - hum.Health
			table.insert(e.dmg, { t = now, a = amount })
			if now - e.lastHit > cfg.combat.comboGap then e.comboCount, e.comboDmg = 0, 0 end
			e.comboCount += 1
			e.comboDmg += amount
			e.lastHit = now
		end
		e.lastHp = hum.Health
		while e.dmg[1] and now - e.dmg[1].t > 15 do table.remove(e.dmg, 1) end

		e.states = readStates(key, char, hum)
		if e.states.stun then e.stunSince = e.stunSince or now else e.stunSince = nil end

		detectAttacks(e, hum, now)

		-- tiempo de recuperación tras atacar
		if e.atkEnd then
			local lag = now - e.atkEnd
			if e.vel.Magnitude > 6 or (e.attack and e.attack.start > e.atkEnd) or lag > 3 then
				if lag <= 3 then
					e.recover = e.recover and (e.recover * 0.6 + lag * 0.4) or lag
					e.recoverN += 1
				end
				e.atkEnd = nil
			end
		end

		-- métricas de comportamiento
		e.trackedTime += dt
		if e.states.blocking then e.blockTime += dt end
		if e.closing > 2 then e.approachTime += dt end

		local speed = e.vel.Magnitude
		local burstTh = math.max(hum.WalkSpeed * 1.7, 26)
		if speed > burstTh and not e.burstActive and now - e.lastDodge > 0.8 and myHRP then
			e.burstActive = true
			e.lastDodge = now
			local toMe = (myHRP.Position - hrp.Position) * FLAT
			if toMe.Magnitude > 0.1 then
				local dot = e.vel.Unit:Dot(toMe.Unit)
				if dot > 0.5 then e.dodge.toward += 1
				elseif dot < -0.5 then e.dodge.away += 1
				else e.dodge.side += 1 end
			end
		elseif speed < burstTh * 0.6 then
			e.burstActive = false
		end
	end

	-- Descubrimiento de NPCs
	local function tryAddNpc(inst)
		if not inst:IsA("Humanoid") then return end
		local model = inst.Parent
		if model and model:IsA("Model") and model ~= LocalPlayer.Character
			and not Players:GetPlayerFromCharacter(model) then
			npcs[model] = true
		end
	end
	workspace.DescendantAdded:Connect(tryAddNpc)
	workspace.DescendantRemoving:Connect(function(inst)
		if inst:IsA("Humanoid") then npcs[inst.Parent] = nil end
	end)
	task.spawn(function()
		local n = 0
		for _, inst in ipairs(workspace:GetDescendants()) do
			tryAddNpc(inst)
			n += 1
			if n % 4000 == 0 then task.wait() end
		end
	end)

	function M.sampleAll(step, now, myHRP)
		local seen = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character then
				sampleEntity(p, p.Character, false, step, now, myHRP)
				seen[p] = true
			end
		end
		if cfg.npc.enabled then
			local list = {}
			for model in pairs(npcs) do
				if model.Parent and not Players:GetPlayerFromCharacter(model) then
					local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
					if hrp then
						local dist = myHRP and (hrp.Position - myHRP.Position).Magnitude or 0
						if dist <= cfg.npc.range then table.insert(list, { model = model, dist = dist }) end
					end
				else
					npcs[model] = nil
				end
			end
			table.sort(list, function(a, b) return a.dist < b.dist end)
			for i = 1, math.min(#list, cfg.npc.maxCount) do
				sampleEntity(list[i].model, list[i].model, true, step, now, myHRP)
				seen[list[i].model] = true
			end
		end
		for key in pairs(ext) do
			if not seen[key] then ext[key] = nil end
		end
	end

	-- Tiempo al impacto aprendido por ataque
	function M.estDelay(atk)
		local rec = impact[atk.name]
		return rec and rec.delay or atk.dur * 0.35
	end

	local myHpPrev = nil
	function M.trackMyHealth(myHum, now)
		if not myHum then myHpPrev = nil return end
		if myHpPrev and myHum.Health < myHpPrev - 0.5 then
			local bestE, bestDelay
			for _, e in pairs(ext) do
				local atk = e.attack
				if atk and (e.dist or 999) < 40 then
					local delay = now - atk.start
					if delay >= 0.03 and delay <= 1.5 and (not bestDelay or delay < bestDelay) then
						bestE, bestDelay = e, delay
					end
				end
			end
			if bestE then
				local rec = impact[bestE.attack.name]
				if rec then
					rec.delay = rec.delay * 0.6 + bestDelay * 0.4
					rec.n += 1
				else
					impact[bestE.attack.name] = { delay = bestDelay, n = 1 }
				end
			end
		end
		myHpPrev = myHum.Health
	end

	function M.dpsOf(e, now)
		local sum = 0
		for _, h in ipairs(e.dmg) do
			if now - h.t <= cfg.combat.dpsWindow then sum += h.a end
		end
		return sum / cfg.combat.dpsWindow
	end

	local function percentile(list, p)
		if #list == 0 then return nil end
		local t = table.clone(list)
		table.sort(t)
		return t[math.clamp(math.ceil(#t * p), 1, #t)]
	end

	function M.reach(e)
		if #e.atkDist < 3 then return nil end
		return percentile(e.atkDist, 0.9)
	end

	local function predictNext(e)
		local row = e.lastMove and e.moveMarkov[e.lastMove]
		if not row then return nil end
		local total, best, bestN = 0, nil, 0
		for name, n in pairs(row) do
			total += n
			if n > bestN then best, bestN = name, n end
		end
		if total < 2 then return nil end
		return best, bestN / total
	end

	local DODGE_NAMES = { toward = "hacia ti", away = "hacia atrás", side = "de lado" }

	function M.suggestions(e, now, d)
		local out = {}
		if e.stunSince then table.insert(out, "Está aturdido: ¡aprovecha para combo!") end
		local p90 = M.reach(e)
		if p90 then
			table.insert(out, string.format("Su ataque llega hasta ~%d studs: mantente a más de %d o entra justo después de que ataque",
				math.floor(p90 + 0.5), math.floor(p90 + 3.5)))
		end
		if e.recover and e.recoverN >= 2 then
			table.insert(out, string.format("Queda expuesto ~%.1f s tras atacar: castiga en ese momento", e.recover))
		end
		local nm, prob = predictNext(e)
		if nm then
			table.insert(out, string.format("Siguiente ataque probable: %s (%d%%)", nm, math.floor(prob * 100 + 0.5)))
		end
		if e.lastMove and e.minGap[e.lastMove] then
			local remain = e.minGap[e.lastMove] - (now - e.lastUse[e.lastMove])
			if remain > 0.2 then
				table.insert(out, string.format("%s está en recarga ~%.1f s: es más seguro acercarse", e.lastMove, remain))
			end
		end
		local dg = e.dodge
		local tot = dg.toward + dg.away + dg.side
		if tot >= 3 then
			local topK, topN = "side", -1
			for k, n in pairs(dg) do
				if n > topN then topK, topN = k, n end
			end
			table.insert(out, string.format("Suele esquivar %s (%d%%): corta ese lado", DODGE_NAMES[topK], math.floor(topN / tot * 100 + 0.5)))
		end
		if e.trackedTime > 20 then
			local blockPct = e.blockTime / e.trackedTime
			if blockPct > 0.35 then
				table.insert(out, string.format("Bloquea el %d%% del tiempo: usa agarres o ataques que rompan guardia", math.floor(blockPct * 100 + 0.5)))
			end
			local aggr = e.approachTime / e.trackedTime
			if aggr > 0.5 then
				table.insert(out, "Muy agresivo: aguanta su ataque y contraataca")
			elseif aggr < 0.15 then
				table.insert(out, "Pasivo: te toca presionar")
			end
		end
		if d and d.hasResult and d.weakText and d.weakText ~= "sin debilidad clara todavía" then
			table.insert(out, "Debilidad: " .. d.weakText)
		end
		return out
	end

	function M.analysisText(e, now, d)
		local lines = {}
		local function add(s) table.insert(lines, s) end
		add(string.format("<b>%s</b>%s   HP %d/%d", escapeRich(e.name), e.isNPC and "  (NPC)" or "",
			math.floor(e.hp + 0.5), math.floor(e.maxHp + 0.5)))
		add(string.format("Observado: %d s   •   Ataques: %d (%.1f por minuto)", math.floor(e.trackedTime),
			e.atkCount, e.trackedTime > 5 and e.atkCount / (e.trackedTime / 60) or 0))

		local arr = {}
		for name, n in pairs(e.moves) do table.insert(arr, { name = name, n = n }) end
		table.sort(arr, function(a, b) return a.n > b.n end)
		local tops = {}
		for i = 1, math.min(3, #arr) do table.insert(tops, string.format("%s (%d)", escapeRich(arr[i].name), arr[i].n)) end
		add("Movimientos más usados: " .. (#tops > 0 and table.concat(tops, ", ") or "—"))

		local p90 = M.reach(e)
		add("Alcance de ataque observado: " .. (p90 and string.format("hasta ~%d studs", math.floor(p90 + 0.5)) or "—"))
		add("Recuperación tras atacar: " .. (e.recover and string.format("~%.1f s (%d muestras)", e.recover, e.recoverN) or "—"))

		local cds = {}
		for name, gap in pairs(e.minGap) do table.insert(cds, string.format("%s ~%.1f s", escapeRich(name), gap)) end
		add("Recargas estimadas: " .. (#cds > 0 and table.concat(cds, ", ", 1, math.min(4, #cds)) or "—"))

		local dg = e.dodge
		local tot = dg.toward + dg.away + dg.side
		add("Esquivas: " .. (tot > 0 and string.format("hacia ti %d, hacia atrás %d, de lado %d", dg.toward, dg.away, dg.side) or "—"))
		if e.trackedTime > 5 then
			add(string.format("Bloqueo: %d%% del tiempo   •   Agresividad: %d%%",
				math.floor(e.blockTime / e.trackedTime * 100 + 0.5), math.floor(e.approachTime / e.trackedTime * 100 + 0.5)))
		end
		local imp = {}
		for name, rec in pairs(impact) do
			table.insert(imp, string.format("%s %.2f s", escapeRich(name), rec.delay))
		end
		add("Tiempo al impacto aprendido: " .. (#imp > 0 and table.concat(imp, ", ", 1, math.min(4, #imp)) or "—"))

		add("")
		add('<font color="#FFB86B"><b>Plan sugerido</b></font>')
		local sug = M.suggestions(e, now, d)
		if #sug == 0 then
			add("Aún faltan datos: observa unos segundos más.")
		else
			for _, s in ipairs(sug) do add("• " .. escapeRich(s)) end
		end
		return table.concat(lines, "\n")
	end
end

----------------------------------------------------------------
-- OBJETIVO + "MIRAR SIEMPRE AL OBJETIVO"
----------------------------------------------------------------
do
	M.lockState = { target = nil, forced = nil }
	local rotOverride = false
	local losParams = RaycastParams.new()
	losParams.FilterType = Enum.RaycastFilterType.Exclude

	local function camLook()
		local cam = workspace.CurrentCamera
		if not cam then return nil end
		local l = cam.CFrame.LookVector * FLAT
		if l.Magnitude < 0.01 then return nil end
		return l.Unit
	end

	local function hasLOS(origin, e)
		losParams.FilterDescendantsInstances = { LocalPlayer.Character, e.char }
		return workspace:Raycast(origin, e.hrp.Position - origin, losParams) == nil
	end

	function M.candidateList(myHRP)
		local lk = cfg.lock
		local look = camLook()
		local list = {}
		for key, e in pairs(M.ext) do
			if e.hrp.Parent and e.hp > 0 and (not e.isNPC or lk.includeNpcs) and isEnemyBy(key, lk.onlyEnemies) then
				local off = (e.hrp.Position - myHRP.Position) * FLAT
				local dist = off.Magnitude
				if dist <= lk.range and dist > 0.5 then
					local ang = look and math.deg(math.acos(math.clamp(off.Unit:Dot(look), -1, 1))) or 0
					if ang <= lk.fov / 2 and (not lk.los or hasLOS(myHRP.Position, e)) then
						table.insert(list, {
							key = key, dist = dist, ang = ang,
							hpPct = e.maxHp > 0 and e.hp / e.maxHp or 1,
						})
					end
				end
			end
		end
		return list
	end

	function M.chooseTarget(myHRP)
		local lk = cfg.lock
		local ls = M.lockState
		local list = M.candidateList(myHRP)
		local by = {}
		for _, c in ipairs(list) do by[c.key] = c end

		if ls.forced then
			if by[ls.forced] then return ls.forced end
			ls.forced = nil
		end
		if lk.mode:sub(1, 6) == "Manual" then return nil end
		if lk.sticky and ls.target and by[ls.target] then return ls.target end

		local best, bestKey
		for _, c in ipairs(list) do
			local k
			if lk.mode == "Centro de pantalla" then k = c.ang + c.dist * 0.01
			elseif lk.mode == "Menor vida" then k = c.hpPct * 1000 + c.dist
			else k = c.dist end
			if not bestKey or k < bestKey then best, bestKey = c.key, k end
		end
		return best
	end

	function M.cycleTarget(myHRP)
		local list = M.candidateList(myHRP)
		table.sort(list, function(a, b) return a.dist < b.dist end)
		if #list == 0 then return end
		local idx = 0
		for i, c in ipairs(list) do
			if c.key == M.state.target then idx = i end
		end
		M.lockState.forced = list[(idx % #list) + 1].key
	end

	function M.applyLock(dt)
		local lk = cfg.lock
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum) then return end

		local e = M.state.target and M.ext[M.state.target]
		if not (lk.enabled and e and e.hrp.Parent) then
			if rotOverride then
				hum.AutoRotate = true
				rotOverride = false
			end
			return
		end

		local st = hum:GetState()
		if hum.PlatformStand or st == Enum.HumanoidStateType.Ragdoll
			or st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.FallingDown then
			return
		end

		local dir = (e.hrp.Position - hrp.Position) * FLAT
		local look = hrp.CFrame.LookVector * FLAT
		if dir.Magnitude < 0.5 or look.Magnitude < 0.01 then return end

		if hum.AutoRotate then
			hum.AutoRotate = false
			rotOverride = true
		end
		look, dir = look.Unit, dir.Unit
		local ang = math.atan2(look:Cross(dir).Y, look:Dot(dir))
		local step = math.rad(lk.turnSpeed) * dt
		local newLook = rotateY(look, math.clamp(ang, -step, step))
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + newLook)
	end

	RunService:BindToRenderStep("PanelLockCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local lk = cfg.lock
		local e = M.state.target and M.ext[M.state.target]
		local cam = workspace.CurrentCamera
		if not (lk.enabled and lk.camera and e and cam) then return end
		local goal = CFrame.lookAt(cam.CFrame.Position, e.hrp.Position + Vector3.new(0, 1, 0))
		cam.CFrame = cam.CFrame:Lerp(goal, lk.camStrength)
	end)
end

----------------------------------------------------------------
-- VISUALES DE COMBATE: anillos, línea de zona, alcance observado, marcador
----------------------------------------------------------------
do
	local rings = {}

	local function newPart(shape)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Parent = M.folder
		return p
	end

	local function ring(name, radius, color, transp, pos)
		local p = rings[name]
		if not p or not p.Parent then
			p = newPart(Enum.PartType.Cylinder)
			rings[name] = p
		end
		p.Color = color
		p.Transparency = transp
		p.Size = Vector3.new(0.1, radius * 2, radius * 2)
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	end

	local function hideRing(name)
		if rings[name] then
			rings[name]:Destroy()
			rings[name] = nil
		end
	end

	function M.updateCombatViz()
		local cb = cfg.combat
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			for _, n in ipairs({ "A", "B", "E", "Z", "O" }) do hideRing(n) end
			return
		end
		local foot = hrp.Position - Vector3.new(0, 2.75, 0)
		local e = M.state.target and M.ext[M.state.target]
		local dist = e and ((e.hrp.Position - hrp.Position) * FLAT).Magnitude

		if cb.ringA then
			local inside = dist and dist <= cb.radiusA
			ring("A", cb.radiusA, inside and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(230, 230, 255), inside and 0.7 or 0.88, foot)
		else hideRing("A") end

		if cb.ringB then
			local inside = dist and dist <= cb.radiusB
			ring("B", cb.radiusB, inside and Color3.fromRGB(110, 180, 255) or Color3.fromRGB(150, 160, 200), 0.9, foot - Vector3.new(0, 0.02, 0))
		else hideRing("B") end

		if cb.ringEnemy and e then
			ring("E", cb.radiusEnemy, Color3.fromRGB(255, 80, 80), dist <= cb.radiusEnemy and 0.7 or 0.88, e.hrp.Position - Vector3.new(0, 2.75, 0))
		else hideRing("E") end

		local reach = e and M.reach(e)
		if cb.observed and reach then
			ring("O", math.clamp(reach, 2, 80), Color3.fromRGB(255, 150, 60), dist <= reach and 0.6 or 0.85, e.hrp.Position - Vector3.new(0, 2.72, 0))
		else hideRing("O") end

		if cb.zoneLine and e then
			local inMine, inEnemy = dist <= cb.radiusA, dist <= cb.radiusEnemy
			local color = Color3.fromRGB(130, 150, 200)
			if inMine and inEnemy then color = Color3.fromRGB(255, 220, 80)
			elseif inMine then color = Color3.fromRGB(90, 255, 120)
			elseif inEnemy then color = Color3.fromRGB(255, 80, 80) end
			local z = rings.Z
			if not z or not z.Parent then
				z = newPart(Enum.PartType.Block)
				rings.Z = z
			end
			local a, b = hrp.Position, e.hrp.Position
			local len = (b - a).Magnitude
			if len > 0.2 then
				z.Color = color
				z.Transparency = 0.2
				z.Size = Vector3.new(0.12, 0.12, len)
				z.CFrame = CFrame.lookAt((a + b) / 2, b)
			end
		else hideRing("Z") end
	end

	local markerGui = Instance.new("BillboardGui")
	markerGui.AlwaysOnTop = true
	markerGui.StudsOffset = Vector3.new(0, 3.8, 0)
	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Rotation = 45
	diamond.BorderSizePixel = 0
	diamond.Parent = markerGui
	corner(diamond, 4)
	local ds = Instance.new("UIStroke")
	ds.Color = Color3.new(1, 1, 1)
	ds.Thickness = 2
	ds.Parent = diamond

	function M.updateMarker()
		local e = M.state.target and M.ext[M.state.target]
		local head = e and e.char and e.char:FindFirstChild("Head")
		if not (cfg.lock.marker and head) then
			markerGui.Parent = nil
			return
		end
		local sz = cfg.lock.markerSize
		markerGui.Size = UDim2.fromOffset(sz * 1.6, sz * 1.6)
		diamond.Size = UDim2.fromOffset(sz * 0.7, sz * 0.7)
		local finisher = cfg.combat.finisher and e.maxHp > 0 and (e.hp / e.maxHp) * 100 <= cfg.combat.finisherPct
		diamond.BackgroundColor3 = finisher and Color3.fromRGB(255, 40, 40) or Color3.fromHSV(cfg.lock.markerHue, 0.8, 1)
		markerGui.Adornee = head
		markerGui.Parent = M.folder
	end
end

----------------------------------------------------------------
-- OBJETOS: proyectiles entrantes, objetos por nombre, prompts, herramientas
----------------------------------------------------------------
do
	M.lists.objects = parseList(cfg.objects.keywords)
	local reg = { keyword = {}, prompt = {}, tool = {} }
	local proj, projCount = {}, 0
	local labelPool, threatPool = {}, {}
	local lastKwOn = false

	local function inCharacter(inst)
		local cur = inst.Parent
		while cur and cur ~= workspace do
			if cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then return true end
			cur = cur.Parent
		end
		return false
	end

	local function adorneeOf(inst)
		if inst:IsA("BasePart") then return inst end
		if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
		if inst:IsA("Tool") then return inst:FindFirstChild("Handle") end
		if inst:IsA("ProximityPrompt") then
			local p = inst.Parent
			if p and (p:IsA("BasePart") or p:IsA("Attachment")) then return p end
			if p and p:IsA("Model") then return p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart", true) end
		end
		return nil
	end

	local function posOf(ad)
		return ad:IsA("Attachment") and ad.WorldPosition or ad.Position
	end

	local function matchKeyword(inst)
		if (inst:IsA("BasePart") or inst:IsA("Model")) and hasAny(M.lists.objects, inst.Name) and not inCharacter(inst) then
			local par = inst.Parent
			if not (par and par:IsA("Model") and hasAny(M.lists.objects, par.Name)) then
				reg.keyword[inst] = true
			end
		end
	end

	local function register(inst)
		if inst:IsA("ProximityPrompt") then
			reg.prompt[inst] = true
		elseif inst:IsA("Tool") then
			local par = inst.Parent
			if par and not par:FindFirstChildOfClass("Humanoid") then reg.tool[inst] = true end
		end
		if cfg.objects.keywordsOn then matchKeyword(inst) end
		if cfg.objects.projectiles and inst:IsA("BasePart") and projCount < 150 and not proj[inst]
			and inst.Size.Magnitude < 30 then
			proj[inst] = { lastPos = inst.Position, vel = Vector3.zero, born = os.clock(), char = nil }
			projCount += 1
		end
	end
	workspace.DescendantAdded:Connect(register)

	local function scanAll(kwOnly)
		task.spawn(function()
			local n = 0
			for _, inst in ipairs(workspace:GetDescendants()) do
				if kwOnly then
					if cfg.objects.keywordsOn then matchKeyword(inst) end
				else
					if inst:IsA("ProximityPrompt") then reg.prompt[inst] = true
					elseif inst:IsA("Tool") and inst.Parent and not inst.Parent:FindFirstChildOfClass("Humanoid") then
						reg.tool[inst] = true
					end
				end
				n += 1
				if n % 3000 == 0 then task.wait() end
			end
		end)
	end
	scanAll(false)

	function M.rescanObjects()
		reg.keyword = {}
		scanAll(true)
	end

	local COLORS = { keyword = Color3.fromRGB(120, 220, 255), prompt = Color3.fromRGB(150, 255, 150), tool = Color3.fromRGB(255, 220, 90) }

	local function makeBillboard(width, height)
		local g = Instance.new("BillboardGui")
		g.Size = UDim2.fromOffset(width, height)
		g.AlwaysOnTop = true
		g.StudsOffset = Vector3.new(0, 1.5, 0)
		g.Enabled = false
		g.Parent = M.folder
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextStrokeTransparency = 0.4
		l.Parent = g
		return { gui = g, label = l }
	end

	function M.updateObjects(dt, now, myHRP)
		local ob = cfg.objects
		M.threats = {}
		M.radarItems = {}

		if ob.keywordsOn and not lastKwOn then M.rescanObjects() end
		lastKwOn = ob.keywordsOn

		if not myHRP then
			for _, l in ipairs(labelPool) do l.gui.Enabled = false end
			for _, l in ipairs(threatPool) do l.gui.Enabled = false end
			return
		end
		local myPos = myHRP.Position

		-- proyectiles entrantes
		local threats = {}
		if ob.projectiles then
			for part, info in pairs(proj) do
				if not part.Parent or not part:IsDescendantOf(workspace) then
					proj[part] = nil
					projCount -= 1
				else
					local pos = part.Position
					info.vel = info.vel:Lerp((pos - info.lastPos) / dt, 0.5)
					info.lastPos = pos
					local speed = info.vel.Magnitude
					if now - info.born > 3 and speed < 3 then
						proj[part] = nil
						projCount -= 1
					elseif speed >= ob.projMinSpeed then
						if info.char == nil then info.char = inCharacter(part) end
						if not info.char then
							local toMe = myPos - pos
							local dist = toMe.Magnitude
							if dist <= ob.projRange and dist > 0.5 then
								local closing = info.vel:Dot(toMe.Unit)
								if closing > 5 then
									local miss = (toMe - info.vel.Unit * toMe:Dot(info.vel.Unit)).Magnitude
									table.insert(threats, { part = part, eta = dist / closing, miss = miss, dist = dist })
								end
							end
						end
					end
				end
			end
			table.sort(threats, function(a, b) return a.eta < b.eta end)
		elseif projCount > 0 then
			proj, projCount = {}, 0
		end
		M.threats = threats

		for i = 1, math.max(4, #threatPool) do
			local th = threats[i]
			if th and i <= 4 and th.miss < 8 then
				local l = threatPool[i]
				if not l then
					l = makeBillboard(110, 26)
					l.label.TextSize = 16
					l.label.TextColor3 = Color3.fromRGB(255, 80, 70)
					threatPool[i] = l
				end
				l.gui.Adornee = th.part
				l.gui.Enabled = true
				l.label.Text = string.format("⚠ %.1f s", th.eta)
			elseif threatPool[i] then
				threatPool[i].gui.Enabled = false
			end
		end
		for _, th in ipairs(threats) do
			if th.miss < 8 and #M.radarItems < 60 then
				table.insert(M.radarItems, { pos = th.part.Position, color = Color3.fromRGB(255, 70, 60), danger = true })
			end
		end

		-- objetos con etiqueta
		local cands = {}
		local function addCand(inst, text, color)
			local ad = adorneeOf(inst)
			if not ad or not ad.Parent then return end
			local pos = posOf(ad)
			local dist = (pos - myPos).Magnitude
			if dist <= ob.range then
				table.insert(cands, { ad = ad, text = text, color = color, dist = dist, pos = pos })
			end
		end
		if ob.keywordsOn then
			for inst in pairs(reg.keyword) do
				if inst.Parent then addCand(inst, inst.Name, COLORS.keyword) else reg.keyword[inst] = nil end
			end
		end
		if ob.prompts then
			for inst in pairs(reg.prompt) do
				if inst.Parent then
					local text = inst.ActionText ~= "" and inst.ActionText or inst.Name
					if inst.ObjectText ~= "" then text = inst.ObjectText .. ": " .. text end
					addCand(inst, text, COLORS.prompt)
				else reg.prompt[inst] = nil end
			end
		end
		if ob.tools then
			for inst in pairs(reg.tool) do
				if inst.Parent then addCand(inst, "Herramienta: " .. inst.Name, COLORS.tool) else reg.tool[inst] = nil end
			end
		end
		table.sort(cands, function(a, b) return a.dist < b.dist end)

		for i = 1, math.max(ob.maxLabels, #labelPool) do
			local c = cands[i]
			if c and i <= ob.maxLabels then
				local l = labelPool[i]
				if not l then
					l = makeBillboard(240, 24)
					labelPool[i] = l
				end
				l.gui.Adornee = c.ad
				l.gui.Enabled = true
				l.label.TextSize = ob.size
				l.label.TextColor3 = c.color
				l.label.Text = string.format("%s  (%d)", c.text, math.floor(c.dist + 0.5))
			elseif labelPool[i] then
				labelPool[i].gui.Enabled = false
			end
		end
		for i = 1, math.min(#cands, 40) do
			table.insert(M.radarItems, { pos = cands[i].pos, color = cands[i].color })
		end
	end
end

----------------------------------------------------------------
-- HUD DEL OBJETIVO, ALERTAS, AVISO DE BLOQUEO, RADAR, ESTADOS
----------------------------------------------------------------
do
	local hudGui = Instance.new("ScreenGui")
	hudGui.Name = "HudObjetivo"
	hudGui.ResetOnSpawn = false
	hudGui.DisplayOrder = 8
	hudGui.Parent = PlayerGui

	local hudFrame = Instance.new("Frame")
	hudFrame.AnchorPoint = Vector2.new(0.5, 0)
	hudFrame.Position = UDim2.new(0.5, 0, 0, 14)
	hudFrame.Size = UDim2.fromOffset(380, 0)
	hudFrame.AutomaticSize = Enum.AutomaticSize.Y
	hudFrame.BackgroundColor3 = THEME.bg
	hudFrame.BackgroundTransparency = 0.2
	hudFrame.BorderSizePixel = 0
	hudFrame.Visible = false
	hudFrame.Parent = hudGui
	corner(hudFrame, 10)

	local hudLabels = {}
	local hName, hpFill, hHp, hMove, hState, hCombo, hAtk, hWeak, hPlan, hFin
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		pad.Parent = hudFrame
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 4)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = hudFrame

		local function line(order, bold)
			local l = newLabel(hudFrame, "", cfg.hud.size, THEME.text, bold and Enum.Font.GothamBold or Enum.Font.Gotham)
			l.RichText = true
			l.TextWrapped = true
			l.Size = UDim2.new(1, 0, 0, 0)
			l.AutomaticSize = Enum.AutomaticSize.Y
			l.LayoutOrder = order
			table.insert(hudLabels, l)
			return l
		end
		hName = line(1, true)
		local hpBack = Instance.new("Frame")
		hpBack.Size = UDim2.new(1, 0, 0, 8)
		hpBack.BackgroundColor3 = THEME.off
		hpBack.BorderSizePixel = 0
		hpBack.LayoutOrder = 2
		hpBack.Parent = hudFrame
		corner(hpBack, 4)
		hpFill = Instance.new("Frame")
		hpFill.Size = UDim2.fromScale(1, 1)
		hpFill.BorderSizePixel = 0
		hpFill.Parent = hpBack
		corner(hpFill, 4)
		hHp, hMove, hState, hCombo, hAtk, hWeak, hPlan = line(3), line(4), line(5), line(6), line(7), line(8), line(9)
		hFin = line(10, true)
		hFin.Text = "¡REMATAR!"
		hFin.TextColor3 = Color3.fromRGB(255, 70, 70)
	end

	function M.updateTargetHud(now)
		local hd = cfg.hud
		local key = M.state.target
		local e = key and M.ext[key]
		if not (hd.enabled and e) then
			hudFrame.Visible = false
			return
		end
		hudFrame.Visible = true
		for _, l in ipairs(hudLabels) do l.TextSize = hd.size end
		hName.TextSize = hd.size + 3
		hFin.TextSize = hd.size + 2

		local d = A and not e.isNPC and A.tracker[key]
		local color = e.isNPC and NPC_COLOR or (d and A.labelColor(d) or Color3.fromRGB(225, 225, 238))
		local labelText = e.isNPC and "NPC" or (d and d.label or "—")
		hName.Text = string.format('<b>%s</b>   <font color="#%s">%s</font>', escapeRich(e.name), color:ToHex(), labelText)

		local pct = e.maxHp > 0 and clamp01(e.hp / e.maxHp) or 0
		hpFill.Size = UDim2.fromScale(pct, 1)
		hpFill.BackgroundColor3 = Color3.fromRGB(255, 80, 80):Lerp(Color3.fromRGB(90, 230, 120), pct)
		hHp.Text = string.format("HP %d / %d  (%d%%)", math.floor(e.hp + 0.5), math.floor(e.maxHp + 0.5), math.floor(pct * 100 + 0.5))

		local trend = "distancia estable"
		if e.closing > 1.5 then trend = string.format("se acerca %d st/s", math.floor(e.closing + 0.5))
		elseif e.closing < -1.5 then trend = string.format("se aleja %d st/s", math.floor(-e.closing + 0.5)) end
		hMove.Text = string.format("%d studs  •  %d st/s  •  %s", math.floor((e.dist or 0) + 0.5), math.floor(e.vel.Magnitude + 0.5), trend)

		hState.Visible = hd.showStates
		if hd.showStates then
			local parts = {}
			if e.states.air then table.insert(parts, "en el aire") end
			if e.stunSince then table.insert(parts, string.format("aturdido %.1f s", now - e.stunSince)) end
			for _, s in ipairs(e.states.list) do
				if not (e.stunSince and (s == "Aturdido" or s == "Caído")) then table.insert(parts, s) end
			end
			hState.Text = #parts > 0 and ("Estado: " .. escapeRich(table.concat(parts, " • "))) or "Estado: normal"
		end

		hCombo.Visible = hd.showDmg
		if hd.showDmg then
			local combo = "Combo —"
			if now - e.lastHit <= cfg.combat.comboGap + 1.5 then
				combo = string.format("Combo x%d (%d daño)", e.comboCount, math.floor(e.comboDmg + 0.5))
			end
			hCombo.Text = string.format("%s  •  DPS %d", combo, math.floor(M.dpsOf(e, now) + 0.5))
		end

		hAtk.Visible = hd.showAttack
		if hd.showAttack then
			if e.lastMove then
				local fav, favN = e.lastMove, 0
				for name, n in pairs(e.moves) do
					if n > favN then fav, favN = name, n end
				end
				hAtk.Text = string.format("Último ataque: %s (hace %.1f s)  •  Más usado: %s (%d)",
					escapeRich(e.lastMove), now - e.lastMoveT, escapeRich(fav), favN)
			else
				hAtk.Text = "Ataques: sin registros todavía"
			end
		end

		hWeak.Visible = hd.showWeak and d ~= nil and d ~= false
		if hWeak.Visible then
			hWeak.Text = d.hasResult and ('<font color="#FFB86B">Debilidad:</font> ' .. escapeRich(d.weakText)) or "Debilidad: analizando…"
		end

		hPlan.Visible = hd.showPlan
		if hd.showPlan then
			local sug = M.suggestions(e, now, nil)
			local shown = {}
			for i = 1, math.min(2, #sug) do table.insert(shown, "• " .. escapeRich(sug[i])) end
			hPlan.Visible = #shown > 0
			hPlan.Text = '<font color="#8FD3FF">Plan:</font> ' .. table.concat(shown, "\n")
		end

		hFin.Visible = cfg.combat.finisher and pct * 100 <= cfg.combat.finisherPct
	end

	-- Alertas sobre los rivales
	local alertGuis, stateGuis = {}, {}

	local function removeAlert(k)
		if alertGuis[k] then alertGuis[k].gui:Destroy(); alertGuis[k] = nil end
	end
	local function removeState(k)
		if stateGuis[k] then stateGuis[k].gui:Destroy(); stateGuis[k] = nil end
	end

	local function facesMe(e, myHRP)
		local toMe = (myHRP.Position - e.hrp.Position) * FLAT
		local fwd = e.hrp.CFrame.LookVector * FLAT
		if toMe.Magnitude > 0.1 and fwd.Magnitude > 0.1 then
			return toMe.Unit:Dot(fwd.Unit) > 0.34
		end
		return true
	end

	local function updateAttackAlert(key, e, now, myHRP)
		local al = cfg.alerts
		local atk = e.attack
		local show = al.attack and atk and (now - atk.start) < (atk.dur + 0.1)
			and (e.dist or 999) <= al.attackRange and isEnemyBy(key, al.onlyEnemies)
			and (not e.isNPC or al.npcAttacks)
		if show and al.onlyFacing and myHRP then show = facesMe(e, myHRP) end
		local head = e.char and e.char:FindFirstChild("Head")
		if not (show and head) then
			removeAlert(key)
			return
		end
		local a = alertGuis[key]
		if not a or not a.gui.Parent or a.gui.Adornee ~= head then
			removeAlert(key)
			local g = Instance.new("BillboardGui")
			g.Size = UDim2.fromOffset(280, 30)
			g.StudsOffset = Vector3.new(0, 6.4, 0)
			g.AlwaysOnTop = true
			g.Adornee = head
			g.Parent = M.folder
			local l = Instance.new("TextLabel")
			l.Size = UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBold
			l.TextSize = 17
			l.TextColor3 = Color3.fromRGB(255, 80, 70)
			l.TextStrokeTransparency = 0.3
			l.Parent = g
			a = { gui = g, label = l }
			alertGuis[key] = a
		end
		a.label.Text = string.format("¡ATAQUE!  %s  %.1fs", atk.name, math.max(atk.dur - (now - atk.start), 0))
		if e.alertedStart ~= atk.start then
			e.alertedStart = atk.start
			M.state.flashUntil = now + 0.3
		end
	end

	local function updateStateTag(key, e)
		local parts = {}
		if cfg.states.showTag then
			for _, s in ipairs(e.states.list) do table.insert(parts, s) end
			if e.states.air then table.insert(parts, "Aire") end
		end
		if #parts == 0 then
			removeState(key)
			return
		end
		local s = stateGuis[key]
		if not s or not s.gui.Parent or s.gui.Adornee ~= e.hrp then
			removeState(key)
			local g = Instance.new("BillboardGui")
			g.Size = UDim2.fromOffset(280, 44)
			g.StudsOffset = Vector3.new(0, 0.2, 0)
			g.AlwaysOnTop = true
			g.Adornee = e.hrp
			g.Parent = M.folder
			local l = Instance.new("TextLabel")
			l.Size = UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBold
			l.TextColor3 = Color3.fromRGB(255, 225, 110)
			l.TextStrokeTransparency = 0.35
			l.TextWrapped = true
			l.Parent = g
			s = { gui = g, label = l }
			stateGuis[key] = s
		end
		s.label.TextSize = cfg.states.tagSize
		s.label.Text = table.concat(parts, " • ")
	end

	-- Aviso de bloqueo (cuenta atrás; NO bloquea por ti)
	local function computeCue(now, myHRP)
		M.cue = nil
		if not (cfg.cue.enabled and myHRP) then return end
		local best
		for key, e in pairs(M.ext) do
			local atk = e.attack
			if atk and e.hp > 0 and (e.dist or 999) <= cfg.cue.range and isEnemyBy(key, cfg.alerts.onlyEnemies)
				and (not e.isNPC or cfg.alerts.npcAttacks) and now < atk.start + atk.dur + 0.1
				and (not cfg.cue.onlyFacing or facesMe(e, myHRP)) then
				local delay = M.estDelay(atk)
				local remain = atk.start + delay - now
				if remain > -0.15 and (not best or remain < best.remain) then
					best = { name = atk.name, impactAt = atk.start + delay, total = math.max(delay, 0.15), remain = remain }
				end
			end
		end
		for _, th in ipairs(M.threats) do
			if th.miss < 7 and (not best or th.eta < best.remain) then
				best = { name = "Proyectil", impactAt = now + th.eta, total = 1.0, remain = th.eta }
			end
		end
		M.cue = best
	end

	function M.updateAlerts(now, myHRP)
		M.state.surroundN = 0
		for key, e in pairs(M.ext) do
			if myHRP and e.hp > 0 and (e.dist or 999) <= cfg.alerts.surroundDist and isEnemyBy(key, cfg.alerts.onlyEnemies) then
				M.state.surroundN += 1
			end
			updateAttackAlert(key, e, now, myHRP)
			updateStateTag(key, e)
		end
		for k in pairs(alertGuis) do if not M.ext[k] then removeAlert(k) end end
		for k in pairs(stateGuis) do if not M.ext[k] then removeState(k) end end
		computeCue(now, myHRP)
	end

	local alertsGui = Instance.new("ScreenGui")
	alertsGui.Name = "AlertasCombate"
	alertsGui.ResetOnSpawn = false
	alertsGui.IgnoreGuiInset = true
	alertsGui.DisplayOrder = 7
	alertsGui.Parent = PlayerGui

	local function edgeFrame(color)
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.Parent = alertsGui
		local s = Instance.new("UIStroke")
		s.Thickness = 26
		s.Color = color
		s.Transparency = 1
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
		return s
	end
	local vigStroke = edgeFrame(Color3.fromRGB(255, 40, 40))
	local flashStroke = edgeFrame(Color3.fromRGB(255, 160, 40))

	local surroundLabel = newLabel(alertsGui, "", 22, Color3.fromRGB(255, 90, 80), Enum.Font.GothamBold)
	surroundLabel.AnchorPoint = Vector2.new(0.5, 0)
	surroundLabel.Position = UDim2.new(0.5, 0, 0.16, 0)
	surroundLabel.Size = UDim2.fromOffset(300, 30)
	surroundLabel.TextXAlignment = Enum.TextXAlignment.Center
	surroundLabel.TextStrokeTransparency = 0.4
	surroundLabel.Visible = false

	function M.updateAlertVisuals(now)
		local al = cfg.alerts
		if al.surround and M.state.surroundN >= al.surroundCount then
			vigStroke.Transparency = 0.35 + 0.25 * math.sin(now * 8)
			surroundLabel.Visible = true
			surroundLabel.Text = string.format("¡RODEADO!  (%d)", M.state.surroundN)
		else
			vigStroke.Transparency = 1
			surroundLabel.Visible = false
		end
		if al.flash and now < M.state.flashUntil then
			flashStroke.Transparency = 0.15 + 0.85 * (1 - (M.state.flashUntil - now) / 0.3)
		else
			flashStroke.Transparency = 1
		end
	end

	-- Anillo del aviso de bloqueo
	local cueFrame = Instance.new("Frame")
	cueFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	cueFrame.Position = UDim2.fromScale(0.5, 0.62)
	cueFrame.BackgroundTransparency = 1
	cueFrame.Visible = false
	cueFrame.Parent = alertsGui

	local cueRing = Instance.new("Frame")
	cueRing.AnchorPoint = Vector2.new(0.5, 0.5)
	cueRing.Position = UDim2.fromScale(0.5, 0.5)
	cueRing.BackgroundTransparency = 1
	cueRing.Parent = cueFrame
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = cueRing
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 5
	ringStroke.Parent = cueRing

	local cueTarget = Instance.new("Frame")
	cueTarget.AnchorPoint = Vector2.new(0.5, 0.5)
	cueTarget.Position = UDim2.fromScale(0.5, 0.5)
	cueTarget.BackgroundTransparency = 1
	cueTarget.Parent = cueFrame
	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0.5, 0)
	tCorner.Parent = cueTarget
	local tStroke = Instance.new("UIStroke")
	tStroke.Thickness = 2
	tStroke.Color = Color3.new(1, 1, 1)
	tStroke.Parent = cueTarget

	local cueText = newLabel(cueFrame, "", 15, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	cueText.AnchorPoint = Vector2.new(0.5, 0)
	cueText.TextXAlignment = Enum.TextXAlignment.Center
	cueText.TextStrokeTransparency = 0.4

	function M.updateCue(now)
		local c = M.cue
		if not (cfg.cue.enabled and c) then
			cueFrame.Visible = false
			return
		end
		local remain = c.impactAt - now
		if remain < -0.15 then
			cueFrame.Visible = false
			return
		end
		local size = cfg.cue.size
		cueFrame.Visible = true
		cueFrame.Size = UDim2.fromOffset(size, size)
		local progress = clamp01(1 - math.max(remain, 0) / c.total)
		local ringSize = size * (1 - 0.72 * progress)
		cueRing.Size = UDim2.fromOffset(ringSize, ringSize)
		cueTarget.Size = UDim2.fromOffset(size * 0.28, size * 0.28)
		local color = Color3.fromRGB(255, 220, 80):Lerp(Color3.fromRGB(255, 50, 50), progress)
		ringStroke.Color = color
		cueText.Position = UDim2.new(0.5, 0, 1, 6)
		cueText.Size = UDim2.fromOffset(size * 2, 20)
		cueText.TextColor3 = color
		cueText.Text = (cfg.cue.showName and (c.name .. "  ") or "") .. string.format("%.2f s", math.max(remain, 0))
	end

	-- Radar (jugadores, NPCs, objetos y amenazas)
	local radarFrame = Instance.new("Frame")
	radarFrame.Position = UDim2.fromOffset(16, 16)
	radarFrame.BackgroundColor3 = THEME.bg
	radarFrame.BackgroundTransparency = 0.3
	radarFrame.BorderSizePixel = 0
	radarFrame.Visible = false
	radarFrame.Parent = alertsGui
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = radarFrame
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Transparency = 0.4
		s.Parent = radarFrame
		onAccent(function() s.Color = THEME.accent end)
		local me = Instance.new("Frame")
		me.AnchorPoint = Vector2.new(0.5, 0.5)
		me.Position = UDim2.fromScale(0.5, 0.5)
		me.Size = UDim2.fromOffset(8, 8)
		me.BackgroundColor3 = Color3.new(1, 1, 1)
		me.BorderSizePixel = 0
		me.Parent = radarFrame
		corner(me, 4)
	end
	local radarDots, radarObj = {}, {}

	function M.updateRadar()
		local rd = cfg.alerts
		radarFrame.Visible = rd.radar
		if not rd.radar then return end
		radarFrame.Size = UDim2.fromOffset(rd.radarSize, rd.radarSize)
		local cam = workspace.CurrentCamera
		local char = LocalPlayer.Character
		local myHRP = char and char:FindFirstChild("HumanoidRootPart")
		if not (cam and myHRP) then return end
		local look = cam.CFrame.LookVector * FLAT
		if look.Magnitude < 0.01 then return end
		look = look.Unit
		local right = look:Cross(Vector3.yAxis)
		local radius = rd.radarSize / 2

		local function toRadar(pos)
			local off = (pos - myHRP.Position) * FLAT
			local v = Vector2.new(off:Dot(right), -off:Dot(look)) / rd.radarRange * radius
			local outside = v.Magnitude > radius - 6
			if outside then v = v.Unit * (radius - 6) end
			return v, outside
		end

		local want = {}
		for key, e in pairs(M.ext) do
			if (not e.isNPC) or rd.radarNpcs then
				want[key] = true
				local dot = radarDots[key]
				if not dot then
					dot = Instance.new("Frame")
					dot.AnchorPoint = Vector2.new(0.5, 0.5)
					dot.BorderSizePixel = 0
					dot.Parent = radarFrame
					local c = Instance.new("UICorner")
					c.CornerRadius = e.isNPC and UDim.new(0, 2) or UDim.new(0.5, 0)
					c.Parent = dot
					radarDots[key] = dot
				end
				local v, outside = toRadar(e.hrp.Position)
				dot.Position = UDim2.new(0.5, v.X, 0.5, v.Y)
				local d = A and not e.isNPC and A.tracker[key]
				dot.BackgroundColor3 = e.isNPC and NPC_COLOR or (d and A.labelColor(d) or Color3.fromRGB(230, 230, 240))
				dot.BackgroundTransparency = outside and 0.55 or 0
				local size = (key == M.state.target) and 13 or 8
				dot.Size = UDim2.fromOffset(size, size)
			end
		end
		for key, dot in pairs(radarDots) do
			if not want[key] then
				dot:Destroy()
				radarDots[key] = nil
			end
		end

		local items = rd.radarObjects and M.radarItems or {}
		for i = 1, math.max(#items, #radarObj) do
			local it = items[i]
			if it then
				local dot = radarObj[i]
				if not dot then
					dot = Instance.new("Frame")
					dot.AnchorPoint = Vector2.new(0.5, 0.5)
					dot.BorderSizePixel = 0
					dot.Rotation = 45
					dot.Parent = radarFrame
					radarObj[i] = dot
				end
				local v, outside = toRadar(it.pos)
				dot.Visible = true
				dot.Position = UDim2.new(0.5, v.X, 0.5, v.Y)
				dot.BackgroundColor3 = it.color
				dot.BackgroundTransparency = outside and 0.6 or 0
				local s = it.danger and 9 or 6
				dot.Size = UDim2.fromOffset(s, s)
			elseif radarObj[i] then
				radarObj[i].Visible = false
			end
		end
	end

	-- Rendimiento
	local perfLabel = newLabel(alertsGui, "", 13, Color3.fromRGB(220, 230, 240), Enum.Font.GothamMedium)
	perfLabel.AnchorPoint = Vector2.new(1, 1)
	perfLabel.Position = UDim2.new(1, -12, 1, -10)
	perfLabel.Size = UDim2.fromOffset(200, 18)
	perfLabel.TextXAlignment = Enum.TextXAlignment.Right
	perfLabel.TextStrokeTransparency = 0.5
	perfLabel.Visible = false
	local fpsAvg, perfT = 60, 0

	function M.updatePerf(dt, now)
		perfLabel.Visible = cfg.screen.perf
		if not cfg.screen.perf then return end
		fpsAvg = fpsAvg * 0.9 + (1 / math.max(dt, 1e-3)) * 0.1
		if now - perfT < 0.5 then return end
		perfT = now
		local ok, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
		perfLabel.Text = string.format("FPS %d  •  Ping %d ms", math.floor(fpsAvg + 0.5), ok and math.floor(ping + 0.5) or 0)
	end

	Players.PlayerRemoving:Connect(function(p)
		removeAlert(p)
		removeState(p)
	end)
end

----------------------------------------------------------------
-- PANTALLA: FOV, zoom, claridad
----------------------------------------------------------------
do
	local origFov, origZoom
	local postOrig = setmetatable({}, { __mode = "k" })
	local lastScan = 0

	function M.scanEffects(now)
		if cfg.screen.calm then
			for eff in pairs(postOrig) do
				if eff.Parent and eff.Enabled then eff.Enabled = false end
			end
			if now - lastScan < 1 then return end
			lastScan = now
			local function handle(container)
				for _, c in ipairs(container:GetChildren()) do
					if c:IsA("PostEffect") then
						if postOrig[c] == nil then postOrig[c] = c.Enabled end
						c.Enabled = false
					end
				end
			end
			handle(Lighting)
			if workspace.CurrentCamera then handle(workspace.CurrentCamera) end
		else
			for eff, was in pairs(postOrig) do
				if eff.Parent then eff.Enabled = was end
				postOrig[eff] = nil
			end
		end
	end

	function M.applyScreen()
		local sc = cfg.screen
		local cam = workspace.CurrentCamera
		if cam then
			if sc.fovOn then
				origFov = origFov or cam.FieldOfView
				cam.FieldOfView = sc.fov
			elseif origFov then
				cam.FieldOfView = origFov
				origFov = nil
			end
		end
		if sc.zoomOn then
			origZoom = origZoom or LocalPlayer.CameraMaxZoomDistance
			LocalPlayer.CameraMaxZoomDistance = sc.maxZoom
		elseif origZoom then
			LocalPlayer.CameraMaxZoomDistance = origZoom
			origZoom = nil
		end
	end
end

----------------------------------------------------------------
-- PANEL DE COMBATE (UI)
----------------------------------------------------------------
do
	local activeSlider, panelDrag = nil, nil

	local function isPointer(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	local function nextOrder(page)
		local n = (page:GetAttribute("n") or 0) + 1
		page:SetAttribute("n", n)
		return n
	end

	local function section(page, text)
		local l = newLabel(page, text, 13, THEME.subtext, Enum.Font.GothamBold)
		l.Size = UDim2.new(1, 0, 0, 20)
		l.LayoutOrder = nextOrder(page)
	end

	local function note(page, text)
		local l = newLabel(page, text, 12, THEME.subtext)
		l.Size = UDim2.new(1, 0, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true
		l.LayoutOrder = nextOrder(page)
	end

	local function makeRow(page, h, clickable)
		local row = Instance.new(clickable and "TextButton" or "Frame")
		if clickable then
			row.Text = ""
			row.AutoButtonColor = false
		end
		row.Size = UDim2.new(1, 0, 0, h)
		row.BackgroundColor3 = THEME.surface
		row.BorderSizePixel = 0
		row.LayoutOrder = nextOrder(page)
		row.Parent = page
		corner(row)
		return row
	end

	local function toggle(page, text, tbl, key)
		local row = makeRow(page, 38, true)
		local label = newLabel(row, text, 13)
		label.Position = UDim2.fromOffset(14, 0)
		label.Size = UDim2.new(1, -76, 1, 0)

		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -14, 0.5, 0)
		track.Size = UDim2.fromOffset(40, 22)
		track.BorderSizePixel = 0
		track.Parent = row
		corner(track, 11)

		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Size = UDim2.fromOffset(16, 16)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.BorderSizePixel = 0
		knob.Parent = track
		corner(knob, 8)

		local function refresh(animate)
			local on = tbl[key]
			local info = TweenInfo.new(animate and 0.18 or 0)
			TweenService:Create(track, info, { BackgroundColor3 = on and THEME.accent or THEME.off }):Play()
			TweenService:Create(knob, info, {
				Position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			}):Play()
		end
		row.Activated:Connect(function()
			tbl[key] = not tbl[key]
			refresh(true)
		end)
		onAccent(function() refresh(false) end)
		table.insert(uiRefresh, function() refresh(true) end)
	end

	local function choice(page, text, tbl, key, options)
		local row = makeRow(page, 38, true)
		local label = newLabel(row, text, 13)
		label.Position = UDim2.fromOffset(14, 0)
		label.Size = UDim2.new(0.5, 0, 1, 0)
		local value = newLabel(row, "", 13, THEME.accent, Enum.Font.GothamBold)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -14, 0, 0)
		value.Size = UDim2.new(0.5, 0, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		local function refresh() value.Text = tbl[key] .. "  ›" end
		row.Activated:Connect(function()
			local idx = table.find(options, tbl[key]) or 0
			tbl[key] = options[(idx % #options) + 1]
			refresh()
		end)
		onAccent(function() value.TextColor3 = THEME.accent end)
		refresh()
	end

	local function textInput(page, text, tbl, key, onChange)
		local row = makeRow(page, 40, false)
		local label = newLabel(row, text, 13)
		label.Position = UDim2.fromOffset(14, 0)
		label.Size = UDim2.new(0.3, 0, 1, 0)
		local box = Instance.new("TextBox")
		box.AnchorPoint = Vector2.new(1, 0.5)
		box.Position = UDim2.new(1, -14, 0.5, 0)
		box.Size = UDim2.new(0.66, 0, 0, 26)
		box.BackgroundColor3 = THEME.off
		box.BorderSizePixel = 0
		box.TextColor3 = THEME.text
		box.Font = Enum.Font.Gotham
		box.TextSize = 12
		box.ClearTextOnFocus = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.Text = tbl[key]
		box.Parent = row
		corner(box, 6)
		box.FocusLost:Connect(function()
			tbl[key] = box.Text
			if onChange then onChange(box.Text) end
		end)
	end

	local function slider(page, text, tbl, key, min, max, step, opts)
		opts = opts or {}
		local holder = makeRow(page, 52, false)
		local name = newLabel(holder, text, 13)
		name.Position = UDim2.fromOffset(14, 6)
		name.Size = UDim2.new(0.65, 0, 0, 18)
		local valueLabel = newLabel(holder, "", 13, THEME.subtext, Enum.Font.GothamMedium)
		valueLabel.AnchorPoint = Vector2.new(1, 0)
		valueLabel.Position = UDim2.new(1, -14, 0, 6)
		valueLabel.Size = UDim2.new(0.35, 0, 0, 18)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right

		local hit = Instance.new("TextButton")
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.Position = UDim2.fromOffset(14, 26)
		hit.Size = UDim2.new(1, -28, 0, 22)
		hit.Parent = holder

		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.fromScale(0, 0.5)
		bar.Size = UDim2.new(1, 0, 0, 6)
		bar.BackgroundColor3 = THEME.off
		bar.BorderSizePixel = 0
		bar.Parent = hit
		corner(bar, 3)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BorderSizePixel = 0
		fill.Parent = bar
		corner(fill, 3)
		if opts.gradient then
			bar.BackgroundColor3 = Color3.new(1, 1, 1)
			local g = Instance.new("UIGradient")
			g.Color = opts.gradient
			g.Parent = bar
			fill.Visible = false
		else
			onAccent(function() fill.BackgroundColor3 = THEME.accent end)
		end

		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Size = UDim2.fromOffset(14, 14)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.BorderSizePixel = 0
		knob.ZIndex = 2
		knob.Parent = bar
		corner(knob, 7)

		local function setValue(v, fromUser)
			v = math.clamp(min + math.round((v - min) / step) * step, min, max)
			tbl[key] = v
			local a = (v - min) / (max - min)
			fill.Size = UDim2.fromScale(a, 1)
			knob.Position = UDim2.fromScale(a, 0.5)
			valueLabel.Text = opts.format and opts.format(v) or (string.format("%g", v) .. (opts.suffix or ""))
			if fromUser and opts.onChange then opts.onChange(v) end
		end
		local function update(x)
			setValue(min + (max - min) * clamp01((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X), true)
		end
		hit.InputBegan:Connect(function(input)
			if isPointer(input) then
				activeSlider = update
				update(input.Position.X)
			end
		end)
		setValue(tbl[key], false)
	end

	-- Ventana
	local gui = Instance.new("ScreenGui")
	gui.Name = "PanelCombate"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 11
	gui.Parent = PlayerGui

	local panel = Instance.new("CanvasGroup")
	panel.Size = UDim2.fromOffset(500, 540)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0, 270, 0.5, 0)
	panel.BackgroundColor3 = THEME.bg
	panel.BackgroundTransparency = cfg.ui.panelTransparency
	panel.BorderSizePixel = 0
	panel.GroupTransparency = 1
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Thickness = 1.5
	panelStroke.Transparency = 0.4
	panelStroke.Parent = panel
	onAccent(function() panelStroke.Color = THEME.accent end)

	local panelScale = Instance.new("UIScale")
	panelScale.Scale = 0.9 * cfg.ui.scale
	panelScale.Parent = panel

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 46)
	header.BackgroundTransparency = 1
	header.Parent = panel
	local title = newLabel(header, "Panel de combate", 17, THEME.text, Enum.Font.GothamBold)
	title.Position = UDim2.fromOffset(18, 0)
	title.Size = UDim2.new(1, -130, 1, 0)
	local hint = newLabel(header, "[ - ] cerrar", 12, THEME.subtext)
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, -18, 0, 0)
	hint.Size = UDim2.fromOffset(90, 46)
	hint.TextXAlignment = Enum.TextXAlignment.Right

	header.InputBegan:Connect(function(input)
		if isPointer(input) then panelDrag = { start = input.Position, pos = panel.Position } end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if activeSlider then activeSlider(input.Position.X) end
		if panelDrag then
			local d = input.Position - panelDrag.start
			local p = panelDrag.pos
			panel.Position = UDim2.new(p.X.Scale, p.X.Offset + d.X, p.Y.Scale, p.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then
			activeSlider = nil
			panelDrag = nil
		end
	end)

	local TAB_NAMES = { "Objetivo", "Combate", "Análisis", "Alertas", "Objetos", "Estados", "Pantalla" }
	local tabBar = Instance.new("Frame")
	tabBar.Position = UDim2.fromOffset(0, 46)
	tabBar.Size = UDim2.new(1, 0, 0, 34)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel

	local indicator = Instance.new("Frame")
	indicator.AnchorPoint = Vector2.new(0, 1)
	indicator.Size = UDim2.new(1 / #TAB_NAMES, -14, 0, 3)
	indicator.Position = UDim2.new(0, 7, 1, 0)
	indicator.BorderSizePixel = 0
	indicator.Parent = tabBar
	corner(indicator, 2)
	onAccent(function() indicator.BackgroundColor3 = THEME.accent end)

	local FOOTER_H = 54
	local pageHolder = Instance.new("Frame")
	pageHolder.Position = UDim2.fromOffset(0, 84)
	pageHolder.Size = UDim2.new(1, 0, 1, -84 - FOOTER_H)
	pageHolder.BackgroundTransparency = 1
	pageHolder.ClipsDescendants = true
	pageHolder.Parent = panel

	local pages, tabButtons = {}, {}
	local function newPage()
		local p = Instance.new("ScrollingFrame")
		p.Size = UDim2.fromScale(1, 1)
		p.BackgroundTransparency = 1
		p.BorderSizePixel = 0
		p.ScrollBarThickness = 3
		p.CanvasSize = UDim2.new()
		p.AutomaticCanvasSize = Enum.AutomaticSize.Y
		p.Visible = false
		p.Parent = pageHolder
		onAccent(function() p.ScrollBarImageColor3 = THEME.accent end)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 16)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 20)
		pad.Parent = p
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 10)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = p
		return p
	end

	local function selectTab(i)
		for j, page in ipairs(pages) do
			page.Visible = (j == i)
			TweenService:Create(tabButtons[j], TweenInfo.new(0.15), {
				TextColor3 = (j == i) and THEME.text or THEME.subtext,
			}):Play()
		end
		TweenService:Create(indicator, TweenInfo.new(0.28, Enum.EasingStyle.Quint), {
			Position = UDim2.new((i - 1) / #TAB_NAMES, 7, 1, 0),
		}):Play()
	end

	for i, name in ipairs(TAB_NAMES) do
		pages[i] = newPage()
		local b = Instance.new("TextButton")
		b.Text = name
		b.Font = Enum.Font.GothamMedium
		b.TextSize = 12
		b.TextColor3 = THEME.subtext
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Position = UDim2.fromScale((i - 1) / #TAB_NAMES, 0)
		b.Size = UDim2.fromScale(1 / #TAB_NAMES, 1)
		b.Parent = tabBar
		b.Activated:Connect(function() selectTab(i) end)
		tabButtons[i] = b
	end

	local footer = Instance.new("TextButton")
	footer.AnchorPoint = Vector2.new(0.5, 1)
	footer.Position = UDim2.new(0.5, 0, 1, -10)
	footer.Size = UDim2.new(1, -36, 0, 38)
	footer.Font = Enum.Font.GothamBold
	footer.TextSize = 14
	footer.TextColor3 = Color3.new(1, 1, 1)
	footer.Text = "‹  Volver al panel de análisis"
	footer.BorderSizePixel = 0
	footer.Parent = panel
	corner(footer, 10)
	onAccent(function() footer.BackgroundColor3 = THEME.accent end)
	footer.Activated:Connect(function() LocalPlayer:SetAttribute("PanelMode", "analisis") end)

	----------------------------------------------------------------
	-- CONTENIDO
	----------------------------------------------------------------
	local p1, p2, p3, p4, p5, p6, p7 = pages[1], pages[2], pages[3], pages[4], pages[5], pages[6], pages[7]

	-- Objetivo
	section(p1, "Mirar siempre al objetivo")
	note(p1, "Tu personaje (y opcionalmente la cámara) giran hacia el objetivo, como un lock-on. Tecla Y: activar/desactivar. Tecla H: cambiar de objetivo.")
	toggle(p1, "Mirar siempre al objetivo", cfg.lock, "enabled")
	choice(p1, "Selección", cfg.lock, "mode", { "Más cercano", "Centro de pantalla", "Menor vida", "Manual (Y/H)" })
	slider(p1, "Alcance", cfg.lock, "range", 10, 200, 5, { suffix = " studs" })
	slider(p1, "Ángulo máximo desde mi cámara", cfg.lock, "fov", 30, 360, 10, { suffix = "°" })
	toggle(p1, "Solo enemigos (otro equipo)", cfg.lock, "onlyEnemies")
	toggle(p1, "Incluir NPCs como objetivo", cfg.lock, "includeNpcs")
	toggle(p1, "Exigir línea de visión", cfg.lock, "los")
	toggle(p1, "Mantener objetivo mientras esté en alcance", cfg.lock, "sticky")
	slider(p1, "Velocidad de giro", cfg.lock, "turnSpeed", 90, 1440, 30, { suffix = "°/s" })
	toggle(p1, "La cámara también mira al objetivo", cfg.lock, "camera")
	slider(p1, "Fuerza de la cámara", cfg.lock, "camStrength", 0.05, 1, 0.05, { format = fmtPct })
	section(p1, "NPCs")
	note(p1, "Detecta modelos con Humanoid que no son jugadores (enemigos, jefes, bots). Para cuidar el rendimiento solo se analizan los más cercanos.")
	toggle(p1, "Detectar NPCs", cfg.npc, "enabled")
	slider(p1, "Alcance de detección de NPCs", cfg.npc, "range", 30, 400, 10, { suffix = " studs" })
	slider(p1, "Máximo de NPCs analizados", cfg.npc, "maxCount", 3, 50, 1)
	section(p1, "Marcador")
	toggle(p1, "Marcador sobre el objetivo", cfg.lock, "marker")
	slider(p1, "Color del marcador", cfg.lock, "markerHue", 0, 1, 0.01, { gradient = RAINBOW, format = fmtDeg })
	slider(p1, "Tamaño del marcador", cfg.lock, "markerSize", 14, 60, 1)
	section(p1, "Panel del objetivo")
	toggle(p1, "Mostrar panel del objetivo", cfg.hud, "enabled")
	toggle(p1, "Estados", cfg.hud, "showStates")
	toggle(p1, "Combo, daño y DPS", cfg.hud, "showDmg")
	toggle(p1, "Ataques y movimientos", cfg.hud, "showAttack")
	toggle(p1, "Debilidad (del panel de análisis)", cfg.hud, "showWeak")
	toggle(p1, "Plan sugerido contra el objetivo", cfg.hud, "showPlan")
	slider(p1, "Tamaño del texto", cfg.hud, "size", 10, 22, 1)

	-- Combate
	section(p2, "Rangos")
	note(p2, "Discos en el suelo para medir distancias. El tuyo se pone verde cuando el objetivo está a tu alcance; el del rival, rojo cuando estás a su alcance.")
	toggle(p2, "Anillo de mi alcance (golpes)", cfg.combat, "ringA")
	slider(p2, "Radio de mi alcance", cfg.combat, "radiusA", 2, 40, 1, { suffix = " studs" })
	toggle(p2, "Anillo de mi habilidad", cfg.combat, "ringB")
	slider(p2, "Radio de la habilidad", cfg.combat, "radiusB", 5, 80, 1, { suffix = " studs" })
	toggle(p2, "Anillo de alcance del rival (manual)", cfg.combat, "ringEnemy")
	slider(p2, "Radio del rival", cfg.combat, "radiusEnemy", 2, 40, 1, { suffix = " studs" })
	toggle(p2, "Línea al objetivo según zona", cfg.combat, "zoneLine")
	note(p2, "Línea: verde = solo yo alcanzo · rojo = solo él alcanza · amarillo = ambos · gris = nadie.")
	section(p2, "Daño y combos")
	slider(p2, "Ventana para calcular DPS", cfg.combat, "dpsWindow", 2, 10, 1, { suffix = " s" })
	slider(p2, "Pausa máxima entre golpes de un combo", cfg.combat, "comboGap", 0.5, 3, 0.1, { suffix = " s" })
	toggle(p2, "Aviso de remate (poca vida)", cfg.combat, "finisher")
	slider(p2, "Remate por debajo de", cfg.combat, "finisherPct", 5, 50, 1, { suffix = "%" })

	-- Análisis
	section(p3, "Análisis del objetivo")
	note(p3, "Con el tiempo aprende cómo juega el objetivo: ataques favoritos, qué ataque suele seguir a cuál, a qué distancia pega, cuánto tarda en recuperarse, recargas, esquivas, guardia y agresividad. Con eso arma un plan en su contra.")
	toggle(p3, "Anillo de alcance de ataque observado", cfg.combat, "observed")
	toggle(p3, "Plan sugerido en el panel del objetivo", cfg.hud, "showPlan")
	local live = newLabel(p3, "", 13)
	live.RichText = true
	live.TextWrapped = true
	live.Size = UDim2.new(1, 0, 0, 0)
	live.AutomaticSize = Enum.AutomaticSize.Y
	live.LayoutOrder = 999

	-- Alertas
	section(p4, "Ataques")
	note(p4, "Detecta cuándo un rival inicia una animación de tipo Acción (golpes, habilidades) y lo avisa sobre su cabeza con el nombre y el tiempo restante.")
	toggle(p4, "Alerta de ataque", cfg.alerts, "attack")
	slider(p4, "Distancia de aviso", cfg.alerts, "attackRange", 5, 80, 1, { suffix = " studs" })
	toggle(p4, "Solo si me está mirando", cfg.alerts, "onlyFacing")
	toggle(p4, "Solo enemigos (otro equipo)", cfg.alerts, "onlyEnemies")
	toggle(p4, "Incluir ataques de NPCs", cfg.alerts, "npcAttacks")
	toggle(p4, "Destello en los bordes de la pantalla", cfg.alerts, "flash")
	section(p4, "Aviso de bloqueo (cuenta atrás)")
	note(p4, "NO bloquea por ti. Muestra un anillo que se cierra justo cuando se estima que llegará el golpe; tú pulsas el bloqueo. Aprende cuánto tarda cada ataque en pegarte cada vez que te hieren.")
	toggle(p4, "Mostrar aviso de bloqueo", cfg.cue, "enabled")
	slider(p4, "Distancia máxima", cfg.cue, "range", 8, 80, 1, { suffix = " studs" })
	toggle(p4, "Solo si me está mirando", cfg.cue, "onlyFacing")
	toggle(p4, "Mostrar nombre del ataque", cfg.cue, "showName")
	slider(p4, "Tamaño del anillo", cfg.cue, "size", 80, 260, 5, { suffix = " px" })
	section(p4, "Rodeado")
	toggle(p4, "Alerta de rodeado", cfg.alerts, "surround")
	slider(p4, "Rivales para avisar", cfg.alerts, "surroundCount", 2, 8, 1)
	slider(p4, "Distancia de 'cerca'", cfg.alerts, "surroundDist", 8, 60, 1, { suffix = " studs" })
	section(p4, "Radar")
	toggle(p4, "Mostrar radar", cfg.alerts, "radar")
	toggle(p4, "Mostrar NPCs en el radar (cuadrados naranja)", cfg.alerts, "radarNpcs")
	toggle(p4, "Mostrar objetos y amenazas en el radar", cfg.alerts, "radarObjects")
	slider(p4, "Tamaño del radar", cfg.alerts, "radarSize", 100, 260, 5, { suffix = " px" })
	slider(p4, "Alcance del radar", cfg.alerts, "radarRange", 30, 200, 5, { suffix = " studs" })

	-- Objetos
	section(p5, "Proyectiles y ataques entrantes")
	note(p5, "Sigue las partes pequeñas que aparecen y se mueven rápido (proyectiles, efectos). Si vienen hacia ti, marca el tiempo estimado de llegada y los muestra en el radar en rojo.")
	toggle(p5, "Detectar proyectiles entrantes", cfg.objects, "projectiles")
	slider(p5, "Distancia de detección", cfg.objects, "projRange", 20, 200, 5, { suffix = " studs" })
	slider(p5, "Velocidad mínima", cfg.objects, "projMinSpeed", 10, 120, 5, { suffix = " studs/s" })
	section(p5, "Objetos del mapa")
	note(p5, "Marca objetos cuyo nombre contenga alguna palabra (separadas por comas), prompts de interacción y herramientas sueltas.")
	toggle(p5, "Buscar objetos por nombre", cfg.objects, "keywordsOn")
	textInput(p5, "Palabras", cfg.objects, "keywords", function(text)
		M.lists.objects = parseList(text)
		M.rescanObjects()
	end)
	toggle(p5, "Mostrar prompts de interacción", cfg.objects, "prompts")
	toggle(p5, "Mostrar herramientas sueltas", cfg.objects, "tools")
	slider(p5, "Distancia máxima", cfg.objects, "range", 10, 300, 5, { suffix = " studs" })
	slider(p5, "Etiquetas a la vez", cfg.objects, "maxLabels", 3, 30, 1)
	slider(p5, "Tamaño del texto", cfg.objects, "size", 9, 22, 1)

	-- Estados
	section(p6, "Estados de los jugadores y NPCs")
	note(p6, "Busca estados en atributos y valores del personaje (Bool/Number) cuyo nombre contenga una de estas palabras (separadas por comas). Añade las que use tu juego.")
	textInput(p6, "Palabras", cfg.states, "keywords", function(text) M.lists.states = parseList(text) end)
	toggle(p6, "Detectar ForceField (invulnerable)", cfg.states, "forcefield")
	toggle(p6, "Mostrar estados sobre los personajes", cfg.states, "showTag")
	slider(p6, "Tamaño del texto de estados", cfg.states, "tagSize", 10, 22, 1)
	toggle(p6, "Registrar movimientos usados", cfg.states, "recordMoves")
	note(p6, "Aturdido, caído y en el aire se detectan solos con el estado del Humanoid. Los estados que contengan 'block', 'guard' o 'parry' cuentan para medir cuánto bloquea.")

	-- Pantalla
	section(p7, "Cámara")
	toggle(p7, "Cambiar campo de visión", cfg.screen, "fovOn")
	slider(p7, "Campo de visión (FOV)", cfg.screen, "fov", 40, 120, 1)
	toggle(p7, "Limitar zoom de la cámara", cfg.screen, "zoomOn")
	slider(p7, "Distancia máxima de zoom", cfg.screen, "maxZoom", 10, 200, 5, { suffix = " studs" })
	section(p7, "Claridad")
	toggle(p7, "Reducir efectos de pantalla (blur, bloom...)", cfg.screen, "calm")
	toggle(p7, "Mostrar FPS y ping", cfg.screen, "perf")
	section(p7, "Interfaz")
	slider(p7, "Tamaño del menú", cfg.ui, "scale", 0.7, 1.3, 0.05, {
		format = fmtPct, onChange = function(v) if panel.Visible then panelScale.Scale = v end end,
	})
	slider(p7, "Color de acento", cfg.ui, "accentHue", 0, 1, 0.01, {
		gradient = RAINBOW, format = fmtDeg, onChange = function(v) setAccent(v) end,
	})
	slider(p7, "Transparencia del panel", cfg.ui, "panelTransparency", 0, 0.6, 0.05, {
		format = fmtPct, onChange = function(v) panel.BackgroundTransparency = v end,
	})

	----------------------------------------------------------------
	-- ABRIR / CERRAR Y CAMBIO ENTRE PANELES
	----------------------------------------------------------------
	local isOpenB = false
	local openTweens = {}

	local function openB(open)
		isOpenB = open
		for _, t in ipairs(openTweens) do t:Cancel() end
		table.clear(openTweens)
		if open then
			panel.Visible = true
			refreshUI()
		end
		local scaleInfo = open and TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			or TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local t1 = TweenService:Create(panelScale, scaleInfo, { Scale = open and cfg.ui.scale or 0.9 * cfg.ui.scale })
		local t2 = TweenService:Create(panel, TweenInfo.new(open and 0.22 or 0.18), { GroupTransparency = open and 0 or 1 })
		table.insert(openTweens, t1)
		table.insert(openTweens, t2)
		t2.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not isOpenB then panel.Visible = false end
		end)
		t1:Play()
		t2:Play()
	end

	function M.updateLive(now)
		if not (isOpenB and p3.Visible) then return end
		local key = M.state.target
		local e = key and M.ext[key]
		if not e then
			live.Text = "Sin objetivo. Activa el lock (Y) o acércate a un rival."
			return
		end
		live.Text = M.analysisText(e, now, (A and not e.isNPC) and A.tracker[key] or nil)
	end

	LocalPlayer:GetAttributeChangedSignal("PanelMode"):Connect(function()
		if LocalPlayer:GetAttribute("PanelMode") == "combate" then
			if A then A.setOpen(false) end
			openB(true)
		else
			openB(false)
			if A then A.setOpen(true) end
		end
	end)

	task.spawn(function()
		local t0 = os.clock()
		while not shared.PanelA and os.clock() - t0 < 8 do task.wait(0.2) end
		A = shared.PanelA
		if A then
			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(0.5, 1)
			btn.Position = UDim2.new(0.5, 0, 1, -10)
			btn.Size = UDim2.new(1, -36, 0, 38)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 14
			btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Text = "Ir al panel de combate  ›"
			btn.BorderSizePixel = 0
			btn.Parent = A.panel
			A.corner(btn, 10)
			A.onAccent(function() btn.BackgroundColor3 = A.THEME.accent end)
			A.pageHolder.Size = UDim2.new(1, 0, 1, -84 - FOOTER_H)
			btn.Activated:Connect(function() LocalPlayer:SetAttribute("PanelMode", "combate") end)
			if LocalPlayer:GetAttribute("PanelMode") == nil then
				LocalPlayer:SetAttribute("PanelMode", "analisis")
			end
		else
			footer.Visible = false
			pageHolder.Size = UDim2.new(1, 0, 1, -84)
			LocalPlayer:SetAttribute("PanelMode", "combate")
			openB(true)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		local kc = input.KeyCode
		if (kc == Enum.KeyCode.Minus or kc == Enum.KeyCode.KeypadMinus)
			and LocalPlayer:GetAttribute("PanelMode") == "combate" then
			openB(not isOpenB)
		elseif kc == LOCK_KEY then
			cfg.lock.enabled = not cfg.lock.enabled
			local char = LocalPlayer.Character
			local myHRP = char and char:FindFirstChild("HumanoidRootPart")
			if cfg.lock.enabled and cfg.lock.mode:sub(1, 6) == "Manual" and not M.lockState.forced and myHRP then
				local list = M.candidateList(myHRP)
				table.sort(list, function(a, b) return a.ang < b.ang end)
				if list[1] then M.lockState.forced = list[1].key end
			end
			if not cfg.lock.enabled then M.lockState.forced = nil end
			refreshUI()
		elseif kc == SWITCH_KEY then
			local char = LocalPlayer.Character
			local myHRP = char and char:FindFirstChild("HumanoidRootPart")
			if myHRP then M.cycleTarget(myHRP) end
		end
	end)

	selectTab(1)
end

----------------------------------------------------------------
-- BUCLES
----------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	M.applyLock(dt)
	M.applyScreen()
	M.updateCombatViz()
	M.updateRadar()
	M.updateAlertVisuals(now)
	M.updateCue(now)
	M.updatePerf(dt, now)
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < SAMPLE then return end
	local step = acc
	acc = 0
	local now = os.clock()
	local char = LocalPlayer.Character
	local myHRP = char and char:FindFirstChild("HumanoidRootPart")
	local myHum = char and char:FindFirstChildOfClass("Humanoid")

	M.sampleAll(step, now, myHRP)
	M.trackMyHealth(myHum, now)

	M.state.target = myHRP and M.chooseTarget(myHRP) or nil
	M.lockState.target = M.state.target

	M.updateObjects(step, now, myHRP)
	M.updateAlerts(now, myHRP)
	M.updateTargetHud(now)
	M.updateMarker()
	M.scanEffects(now)
	M.updateLive(now)
end)
