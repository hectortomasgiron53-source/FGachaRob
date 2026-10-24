-- Simulador 2D de un partido 4v4 (3 bots de campo + portero por equipo) con el cerebro Tactics del juego.
-- Fisica aproximada a la del juego (Ball.lua / Match.lua). Escribe frames.csv y events.csv.
local __v = require("./vec")
local Vector3 = __v.Vector3
local cfg = require("./Balance")
local Tactics = require("./Tactics")

local args = { ... }
local SECONDS = tonumber(args[1]) or 120
local SEED = tonumber(args[2]) or 1
local HUMAN = tonumber(args[3]) == 1
DEBUG_OPTS = tonumber(args[4]) == 1
nextDebug = 0 -- el jugador 1 azul lo lleva un "humano" sencillo
math.randomseed(SEED)

local F = cfg.Field
local L, W, GW = F.Length, F.Width, F.GoalWidth
local R = cfg.Ball.Diameter / 2
local k = cfg.Ball.RollDamping
local C = cfg.Control
local K = cfg.Kick
local dt = 1 / 30

local STATS = {
	{ Speed = 60, Shooting = 70, Passing = 50, Dribbling = 65, Defense = 30, Stamina = 55 },
	{ Speed = 55, Shooting = 50, Passing = 70, Dribbling = 55, Defense = 50, Stamina = 70 },
	{ Speed = 50, Shooting = 30, Passing = 55, Dribbling = 35, Defense = 75, Stamina = 60 },
	{ Speed = 45, Shooting = 20, Passing = 45, Dribbling = 20, Defense = 50, Stamina = 60, Goalkeeping = 75 },
}

local function mapStat(stat, a, b)
	local t = math.clamp((stat - 1) / 99, 0, 1)
	return a + (b - a) * t
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function attackDir(team) return if team == 1 then 1 else -1 end

local players = {}
for team = 1, 2 do
	for slot = 1, 4 do
		local human = HUMAN and team == 1 and slot == 1
		local st = STATS[slot]
		table.insert(players, {
			Id = (team - 1) * 4 + slot, Team = team, Slot = slot, Keeper = slot == 4, Human = human, Bot = slot ~= 4 and not human,
			Pos = Vector3.zero, Vel = Vector3.zero, Look = Vector3.new(attackDir(team), 0, 0),
			RunSpeed = mapStat(st.Speed, cfg.Speed.Min, cfg.Speed.Max), Stats = st,
			StunnedUntil = 0, ReleaseAt = 0, ImmuneUntil = 0, ForceUntil = 0, ForceDir = Vector3.zero, ForceSpeed = 0,
			Stamina = 100, Exhausted = false, Stunned = false, CanControl = slot ~= 4,
		})
	end
end

local ball = { Pos = Vector3.zero, Vel = Vector3.zero, Controller = nil, LastTouch = nil, Dead = false, Stopped = true }
local state = Tactics.newState()
local now = 0
local score = { 0, 0 }
local kickoff = nil -- { Team, PassAt, Waiting, KeepOutUntil, Kicker, Receiver }
local kickoffTeam = 1
local keeperHold = nil -- { Keeper, Until }
local phase = "Playing"
local phaseTimer = 0
lastCall = nil -- ultimo bot que pidio el balon al "humano" ({ By, At })

local events = {}
local function event(kind, a, b, extra)
	table.insert(events, string.format("%.2f,%s,%s,%s,%s", now, kind, tostring(a or ""), tostring(b or ""), tostring(extra or "")))
end

local function placeAll()
	for _, p in players do
		local a = attackDir(p.Team)
		local side = -a
		local x, z
		if p.Keeper then
			x, z = side * (L / 2 - cfg.Goalkeeper.LineOffset), 0
		else
			local form = cfg.Formation[p.Slot]
			local dist = form.X
			if p.Slot == 1 then
				dist = if p.Team == kickoffTeam then cfg.Kickoff.Near else cfg.Kickoff.Far
			end
			x = side * dist
			z = if p.Team == 1 then form.Z else -form.Z
			if p.Slot == 1 and p.Team == kickoffTeam then
				x = -side * dist -- el que saca, por detras del balon
			end
		end
		p.Pos = Vector3.new(x, 0, z)
		p.Vel = Vector3.zero
		p.Look = Vector3.new(a, 0, 0)
		p.StunnedUntil, p.ForceUntil = 0, 0
	end
	ball.Pos = Vector3.new(0, R, 0)
	ball.Vel = Vector3.zero
	ball.Controller = nil
	ball.Stopped = true
	ball.Dead = false
	keeperHold = nil
end

local function startKickoff()
	local team = kickoffTeam
	local kicker, mates = nil, {}
	for _, p in players do
		if p.Team == team and p.Slot == 1 then kicker = p end
	end
	for _, p in players do
		if p.Team == team and p ~= kicker then table.insert(mates, p) end
	end
	local receiver = mates[math.random(1, #mates)]
	kickoff = { Team = team, PassAt = now + cfg.Kickoff.PassDelay, Waiting = true, KeepOutUntil = math.huge, Kicker = kicker, Receiver = receiver }
end

placeAll()
startKickoff()

-- Golpeos ------------------------------------------------------------------
local pendingPass = nil -- para medir pases completados
local function launch(p, dir, speed, errorDeg)
	local err = math.rad((math.random() * 2 - 1) * errorDeg)
	local c, s = math.cos(err), math.sin(err)
	dir = Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
	ball.Vel = dir * speed
	ball.Controller = nil
	ball.LastTouch = p
	ball.Stopped = false
	ball.GraceUntil = now + C.KickGraceSeconds
	p.ReleaseAt = now + C.KickLockSeconds
end

local function doKick(p, exec)
	if ball.Controller ~= p and (flat(ball.Pos) - p.Pos).Magnitude > C.KickRange then
		return false
	end
	local toAim = flat(exec.Aim - p.Pos)
	if toAim.Magnitude < 0.1 then return false end
	p.Look = toAim.Unit
	if exec.Kind == "Pass" then
		local v0 = Tactics.passSpeed(cfg, exec.PassDistance or toAim.Magnitude)
		launch(p, p.Look, v0, mapStat(p.Stats.Passing, K.PassErrorMaxDeg, K.PassErrorMinDeg))
		if exec.Mate and not p.Human then Tactics.notePass(state, { Now = now }, cfg, p, exec.Mate, exec.Aim) end
		pendingPass = { From = p, To = exec.Mate }
		local dbg = state.Mem[p.Id] and state.Mem[p.Id].Debug or {}
		local ad = attackDir(p.Team)
		event("pass", p.Id, exec.Mate and exec.Mate.Id, string.format("%.0f;%.2f;%.2f;%.3f;%.2f;%.1f;%.1f", toAim.Magnitude, exec.Safe or -1, dbg.Keep or -1, dbg.Dribble or -1, dbg.Pressure or -1, p.Pos.X * ad, exec.Aim.X * ad))
	else
		local base = mapStat(p.Stats.Shooting, K.ShotSpeedMin, K.ShotSpeedMax)
		local speed = base * (K.ShotMinCharge + (1 - K.ShotMinCharge) * (exec.Value or 0.8))
		if exec.Kind == "ShootHigh" then speed *= K.HighSpeedFactor end
		launch(p, p.Look, speed, mapStat(p.Stats.Shooting, K.ErrorMaxDeg, K.ErrorMinDeg))
		ball.Chip = exec.Kind == "ShootHigh"
		ball.ShotBy = p
		ball.SaveChecked = false
		pendingPass = nil
		event("shot", p.Id, "", string.format("%.0f", toAim.Magnitude))
	end
	return true
end

-- Ayuda de robo de los bots cerca de su porteria (igual que Ball.homeFactor)
local function homeFactor(p)
	if p.Human then return 0 end
	local ownGoalX = -attackDir(p.Team) * L / 2
	local d = math.sqrt((p.Pos.X - ownGoalX) ^ 2 + p.Pos.Z ^ 2)
	return math.clamp(1 - d / (L * C.HomeStealRange), 0, 1)
end

local function doTackle(p, slide)
	local victim = ball.Controller
	if not victim or victim.Team == p.Team then return end
	local reach = math.min((victim.Pos - p.Pos).Magnitude, (flat(ball.Pos) - p.Pos).Magnitude)
	local range = if slide then C.SlideHitRange else C.TackleRange
	if slide then
		p.StunnedUntil = now + C.SlideSeconds + C.SlideRecoverySeconds
		p.ForceUntil = now + C.SlideSeconds
		p.ForceDir = p.Look
		p.ForceSpeed = C.SlideSpeed
	end
	if reach > range then return end
	if now < victim.ImmuneUntil then
		p.StunnedUntil = math.max(p.StunnedUntil, now + C.TackleStunSeconds)
		return
	end
	local base = if slide then C.SlideBaseChance else C.TackleBaseChance
	local home = homeFactor(p)
	local chance = math.clamp(base + (p.Stats.Defense - victim.Stats.Dribbling) / 200 + home * C.HomeTackleBonus, 0.15, 0.85 + home * C.HomeTackleBonus)
	if math.random() < chance then
		victim.ReleaseAt = now + 0.8
		victim.StunnedUntil = now + (if slide then C.SlideStunSeconds else C.TackledStunSeconds)
		ball.Controller = p
		ball.LastTouch = p
		event("tackle_won", p.Id, victim.Id)
	else
		p.StunnedUntil = math.max(p.StunnedUntil, now + C.TackleStunSeconds)
		event("tackle_fail", p.Id, victim.Id)
	end
end

-- Porteros (simplificado) --------------------------------------------------
-- Zona del portero con el balon en las manos (como Match._clearKeeperZone): profundidad desde su linea de gol
local function zoneDepth(p, keeper)
	local inward = attackDir(keeper.Team)
	return (p.Pos.X + inward * L / 2) * inward
end
local function zoneLimit()
	return L * cfg.Goalkeeper.ClearZoneFraction + cfg.Goalkeeper.ClearZoneMargin
end

local function keeperStep(kp)
	local a = attackDir(kp.Team)
	local goalX = -a * L / 2
	local goal = Vector3.new(goalX, 0, 0)
	local bp = flat(ball.Pos)
	if keeperHold and keeperHold.Keeper == kp then
		ball.Pos = kp.Pos + Vector3.new(a * 1.5, R, 0)
		ball.Vel = Vector3.zero
		if now >= keeperHold.Until then
			-- Saque: el mismo que en el juego (Tactics.keeperPass); si no hay pase seguro, despeja lejos
			local world = {
				Now = now,
				Field = { Length = L, Width = W, GoalWidth = GW, CenterRadius = F.CenterCircleRadius, AreaRadius = F.AreaRadius },
				Ball = { Pos = ball.Pos, Vel = ball.Vel, Controller = kp, LastTouch = kp },
				Players = players,
				Live = true,
			}
			local B = cfg.Bots
			local held = now - keeperHold.Since
			local lastChance = held >= B.KeeperMaxHold
			if not lastChance then
				for _, o in players do
					if o.Team ~= kp.Team and not o.Keeper and zoneDepth(o, kp) < zoneLimit() - cfg.Goalkeeper.ClearZoneMargin then
						keeperHold.Until = now + 0.25 -- rivales en su zona: espera
						return
					end
				end
			end
			local choice = Tactics.keeperPass(world, cfg, kp, if lastChance then B.KeeperPassLastSafe else B.KeeperPassMinSafe)
			if not choice and not lastChance then
				keeperHold.Until = now + 0.25 -- nadie desmarcado: espera un poco
				return
			end
			keeperHold = nil
			ball.Stopped = false
			if choice then
				local to = flat(choice.Aim - kp.Pos)
				kp.Look = to.Unit
				launch(kp, to.Unit, Tactics.passSpeed(cfg, to.Magnitude), 4)
				Tactics.notePass(state, world, cfg, kp, choice.Mate, choice.Aim)
				pendingPass = { From = kp, To = choice.Mate }
				event("keeper_out", kp.Id, choice.Mate.Id)
			else
				local dir = Vector3.new(a, 0, (math.random() - 0.5) * 0.8).Unit
				launch(kp, dir, cfg.Goalkeeper.ClearSpeed * 0.8, 6)
				event("keeper_clear", kp.Id)
			end
			kp.ReleaseAt = now + 1
		end
		return
	end
	local G = cfg.Goalkeeper
	local toBall = bp - goal
	local dist = toBall.Magnitude
	local dirToBall = if dist > 0.1 then toBall.Unit else Vector3.new(a, 0, 0)
	if dirToBall.X * a < 0.2 then dirToBall = Vector3.new(a * 0.2, 0, dirToBall.Z).Unit end
	local target = goal + dirToBall * math.clamp(dist * G.AdvanceFactor, G.LineOffset, G.NormalMaxAdvance)
	local speed = G.MoveSpeed
	local free = ball.Controller == nil and not ball.Stopped and not ball.Dead
	local ballSpeed = flat(ball.Vel).Magnitude
	local inArea = dist <= F.AreaRadius and (bp.X - goalX) * a > 0
	if free and ballSpeed < G.RushMaxSpeed and inArea and now >= kp.ReleaseAt then
		target = bp
		speed = G.RushSpeed
	end
	local to = target - kp.Pos
	if to.Magnitude > 0.2 then
		kp.Pos = kp.Pos + to.Unit * math.min(to.Magnitude, speed * dt)
	end
	-- Blocaje de balones lentos
	if free and ballSpeed < G.RushMaxSpeed and (bp - kp.Pos).Magnitude < 3 and now >= kp.ReleaseAt then
		keeperHold = { Keeper = kp, Until = now + 1.2, Since = now }
		ball.Controller = nil
		ball.Stopped = true
		ball.LastTouch = kp
		pendingPass = nil
		event("keeper_claim", kp.Id)
		return
	end
	-- Paradas: balon rapido hacia su porteria
	if free and ballSpeed > G.ShotMinSpeed and ball.Vel.X * -a > 0 and not ball.SaveChecked then
		local tLine = (goalX - bp.X) / ball.Vel.X
		if tLine > 0 and tLine < 1.2 then
			local zc = bp.Z + ball.Vel.Z * tLine
			if math.abs(zc) < GW / 2 + 1 and math.abs(bp.X - kp.Pos.X) < 4 then
				ball.SaveChecked = true
				local lateral = math.abs(zc - kp.Pos.Z)
				local difficulty = 0.45 * math.clamp((ballSpeed - 35) / 75, 0, 1) + 0.55 * math.clamp(lateral / 12, 0, 1)
				if ball.Chip then difficulty += 0.15 end
				if math.random() > difficulty then
					if ballSpeed < 55 then
						keeperHold = { Keeper = kp, Until = now + 1.2, Since = now }
						ball.Stopped = true
						ball.LastTouch = kp
						event("save_catch", kp.Id)
					else
						ball.Vel = Vector3.new(-ball.Vel.X * 0.45, 0, (math.random() - 0.5) * 30)
						ball.LastTouch = kp
						event("save_parry", kp.Id)
					end
				else
					event("save_miss", kp.Id)
				end
			end
		end
	end
end

-- Frames ----------------------------------------------------------------
local frames = { "t,bx,bz,ctrl," .. (function()
	local cols = {}
	for _, p in players do
		table.insert(cols, string.format("p%d_x,p%d_z,p%d_role,p%d_tx,p%d_tz", p.Id, p.Id, p.Id, p.Id, p.Id))
	end
	return table.concat(cols, ",")
end)() }

local nextFrame = 0
local steps = math.floor(SECONDS / dt)
for _ = 1, steps do
	now += dt
	-- Saque
	if kickoff and kickoff.Waiting and now >= kickoff.PassAt then
		kickoff.Waiting = false
		kickoff.KeepOutUntil = now + cfg.Kickoff.KeepOutSeconds
		local kicker, rec = kickoff.Kicker, kickoff.Receiver
		local to = flat(rec.Pos - ball.Pos)
		local d = to.Magnitude
		local arrive = cfg.Kickoff.ArriveSpeed
		if rec.Keeper then d = math.max(0, d - 6); arrive *= 0.5 end
		ball.Stopped = false
		launch(kicker, to.Unit, math.min(d * k + arrive, cfg.Ball.MaxSpeed), 0)
		event("kickoff", kicker.Id, rec.Id)
	end
	if kickoff and not kickoff.Waiting and now >= kickoff.KeepOutUntil then
		kickoff = nil
	end

	-- Foto para Tactics
	for _, p in players do
		p.Stunned = now < p.StunnedUntil
	end
	local world = {
		Now = now,
		Field = { Length = L, Width = W, GoalWidth = GW, CenterRadius = F.CenterCircleRadius, AreaRadius = F.AreaRadius },
		Ball = { Pos = ball.Pos, Vel = ball.Vel, Controller = ball.Controller or (if keeperHold then keeperHold.Keeper else nil), LastTouch = ball.LastTouch },
		Players = players,
		Kickoff = if kickoff then { Team = kickoff.Team, Waiting = kickoff.Waiting } else nil,
		Live = phase == "Playing",
		KeeperClear = if keeperHold then { Team = keeperHold.Keeper.Team, Depth = zoneLimit() + 2 } else nil,
	}
	Tactics.update(state, world, cfg)
	if DEBUG_OPTS and now >= (nextDebug or 0) and ball.Controller and ball.Controller.Bot and (Vector3.new(attackDir(ball.Controller.Team) * L / 2, 0, 0) - ball.Controller.Pos).Magnitude < 40 then
		local m = state.Mem[ball.Controller.Id]
		if m and m.Debug and m.Debug.Options then
			nextDebug = now + 1
			local opts = table.clone(m.Debug.Options)
			table.sort(opts, function(x, y) return x.Value > y.Value end)
			local ad = attackDir(ball.Controller.Team)
			local lines = { string.format("t=%.1f jugador %d (x'=%.0f) urgencia %.2f presion %.2fs", now, ball.Controller.Id, ball.Controller.Pos.X * ad, m.Debug.Urgency or -1, m.Debug.Pressure or -1) }
			for i = 1, math.min(8, #opts) do
				local o = opts[i]
				local tgt = o.Aim or o.Target
				table.insert(lines, string.format("   %-9s valor %.3f  seguro %s  destino x'=%.0f z=%.0f", o.Kind, o.Value, if o.Safe then string.format("%.2f", o.Safe) else "-", tgt and tgt.X * ad or 0, tgt and tgt.Z or 0))
			end
			print("DBG " .. table.concat(lines, "\nDBG "))
		end
	end

	-- "Humano" sencillo: va al balon si es el mas cercano de su equipo; con balon conduce hacia la porteria,
	-- tira cerca y pasa al companero mas adelantado al cabo de un rato
	if HUMAN then
		local h = players[1]
		local a = attackDir(h.Team)
		local out = { Role = "Human", Target = h.Pos, Urgent = true }
		local bp = flat(ball.Pos)
		if ball.Controller == h then
			h.HoldStart = h.HoldStart or now
			out.Target = h.Pos + Vector3.new(a * 10, 0, -h.Pos.Z * 0.2)
			local goal = Vector3.new(a * L / 2, 0, 0)
			if (goal - h.Pos).Magnitude < 28 then
				out.Execute = { Kind = "Shoot", Aim = goal + Vector3.new(0, 0, (math.random() - 0.5) * 16), Value = 0.8 }
			elseif lastCall and now - lastCall.At < 0.8 and math.random() < 0.15 then
				-- Un bot le pide el balon: se lo da (con un pequeno retraso de reaccion)
				local q = lastCall.By
				out.Execute = { Kind = "Pass", Aim = q.Pos + q.Vel * 0.35, Mate = q, PassDistance = (q.Pos - h.Pos).Magnitude }
				event("call_answered", h.Id, q.Id)
				lastCall = nil
			elseif now - h.HoldStart > 1.3 then
				local best, bx = nil, -math.huge
				for _, q in players do
					if q.Team == h.Team and q ~= h and not q.Keeper and q.Pos.X * a > bx then best, bx = q, q.Pos.X * a end
				end
				if best then out.Execute = { Kind = "Pass", Aim = best.Pos, Mate = best, PassDistance = (best.Pos - h.Pos).Magnitude } end
			end
		else
			h.HoldStart = nil
			local nearestMine = true
			for _, q in players do
				if q.Team == h.Team and q ~= h and not q.Keeper and (q.Pos - bp).Magnitude < (h.Pos - bp).Magnitude then nearestMine = false end
			end
			if nearestMine or (bp - h.Pos).Magnitude < 15 then
				out.Target = bp
			else
				out.Target = Vector3.new(math.clamp(bp.X + a * 20, -60, 60), 0, h.Pos.Z * 0.9)
			end
			if ball.Controller and ball.Controller.Team ~= h.Team and (ball.Controller.Pos - h.Pos).Magnitude < 4.5 and math.random() < 0.05 then
				out.Execute = { Kind = "Tackle", Aim = bp }
			end
		end
		h.Out = out
	end

	-- Acciones y movimiento
	for _, p in players do
		if p.Keeper then
			keeperStep(p)
			continue
		end
		local out = p.Out
		if out and out.Call then
			lastCall = { By = p, At = now }
			event("call", p.Id)
		end
		if out and out.Execute and not p.Stunned and phase == "Playing" then
			local ex = out.Execute
			if ex.Kind == "Pass" or ex.Kind == "Shoot" or ex.Kind == "ShootHigh" then
				doKick(p, ex)
			elseif ex.Kind == "Tackle" then
				if ex.Aim then p.Look = flat(ex.Aim - p.Pos).Unit end
				doTackle(p, false)
			elseif ex.Kind == "Slide" then
				if ex.Aim then p.Look = flat(ex.Aim - p.Pos).Unit end
				doTackle(p, true)
			elseif ex.Kind == "Juke" and ball.Controller == p then
				local right = Vector3.new(-p.Look.Z, 0, p.Look.X)
				p.ForceDir = (p.Look * C.JukeForwardBias + right * ex.Value).Unit
				p.ForceSpeed = p.RunSpeed * C.JukeSpeedMultiplier
				p.ForceUntil = now + C.JukeSeconds
				p.ImmuneUntil = now + C.JukeImmuneSeconds
				event("juke", p.Id)
			elseif ex.Kind == "Flick" and ball.Controller == p then
				-- Sombrero (simplificado): el balon sale suave hacia delante y solo el puede recogerlo un momento
				launch(p, p.Look, 10, 0)
				ball.ProtectedBy, ball.ProtectedUntil = p, now + C.FlickProtectSeconds
				p.ImmuneUntil = now + C.FlickImmuneSeconds
				event("flick", p.Id)
			end
		end
		local vel = Vector3.zero
		if keeperHold and p.Team ~= keeperHold.Keeper.Team and zoneDepth(p, keeperHold.Keeper) < zoneLimit() then
			-- Retirada obligada de la zona del portero
			p.ForceDir = Vector3.new(attackDir(keeperHold.Keeper.Team), 0, 0)
			p.ForceSpeed = p.RunSpeed * cfg.Goalkeeper.ClearRunFactor
			p.ForceUntil = now + dt * 1.5
		end
		if now < p.ForceUntil then
			vel = p.ForceDir * p.ForceSpeed
		elseif not p.Stunned and phase == "Playing" and not (kickoff and kickoff.Waiting and kickoff.Kicker == p) then
			local dir, pace, sprint, face
			if p.Human then
				local to = flat(p.Out.Target - p.Pos)
				dir = if to.Magnitude > 1 then to.Unit else Vector3.zero
				pace, sprint, face = 1, to.Magnitude > 6, if to.Magnitude > 1 then to.Unit else p.Look
			else
				dir, pace, sprint, face = Tactics.steer(state, p, flat(ball.Pos), dt, cfg, players)
			end
			-- Resistencia
			local moving = dir.Magnitude > 0.1 and pace > 0.1
			if sprint and moving and not p.Exhausted then
				p.Stamina = math.max(0, p.Stamina - (100 / mapStat(p.Stats.Stamina, 4, 10)) * dt)
				if p.Stamina <= 0 then p.Exhausted = true end
			else
				p.Stamina = math.min(100, p.Stamina + (100 / 8) * dt)
				if p.Exhausted and p.Stamina >= 25 then p.Exhausted = false end
				sprint = false
			end
			local speed = p.RunSpeed * (if sprint then cfg.Speed.SprintMultiplier else 1) * pace
			if ball.Controller == p then speed *= C.DribbleSpeedFactor end
			vel = dir * speed
			-- Giro del cuerpo hacia donde debe mirar
			if face and face.Magnitude > 0.1 then
				local cur = p.Look
				local ang = math.acos(math.clamp(cur:Dot(face), -1, 1))
				local step = cfg.Bots.FaceTurnRate * dt
				if ang <= step then
					p.Look = face.Unit
				else
					local c, s = math.cos(step), math.sin(step)
					local d1 = Vector3.new(cur.X * c - cur.Z * s, 0, cur.X * s + cur.Z * c)
					local d2 = Vector3.new(cur.X * c + cur.Z * s, 0, -cur.X * s + cur.Z * c)
					p.Look = (if d1:Dot(face) >= d2:Dot(face) then d1 else d2).Unit
				end
			end
		end
		p.Vel = vel
		p.Pos = p.Pos + vel * dt
		-- Saque: rivales fuera del circulo
		if kickoff and p.Team ~= kickoff.Team then
			local rr = F.CenterCircleRadius + cfg.Kickoff.KeepOutMargin
			if p.Pos.Magnitude < rr then p.Pos = p.Pos.Unit * rr end
		end
		p.Pos = Vector3.new(math.clamp(p.Pos.X, -L / 2 + 1, L / 2 - 1), 0, math.clamp(p.Pos.Z, -W / 2 + 1, W / 2 - 1))
	end
	-- Choques entre jugadores
	for i = 1, #players do
		for j = i + 1, #players do
			local a, b = players[i], players[j]
			local d = b.Pos - a.Pos
			local m = d.Magnitude
			if m < 2.6 and m > 1e-4 then
				local push = d.Unit * ((2.6 - m) / 2)
				a.Pos = a.Pos - push
				b.Pos = b.Pos + push
			end
		end
	end

	-- Balon
	if not ball.Stopped then
		local ctrl = ball.Controller
		if ctrl then
			if ctrl.Stunned or (flat(ball.Pos) - ctrl.Pos).Magnitude > C.DribbleReleaseRange then
				ball.Controller = nil
				ctrl = nil
			end
		end
		if ctrl then
			local target = ctrl.Pos + ctrl.Look * C.DribbleDistance
			local alpha = 1 - math.exp(-C.DribbleSnapRate * dt)
			local nb = flat(ball.Pos):Lerp(target, alpha)
			ball.Pos = Vector3.new(nb.X, R, nb.Z)
			ball.Vel = ctrl.Vel
			-- Robo por contacto
			if now >= ctrl.ImmuneUntil then
				for _, o in players do
					if o.Team ~= ctrl.Team and not o.Keeper and not o.Stunned and now >= o.ReleaseAt then
						if (flat(ball.Pos) - o.Pos).Magnitude <= C.ContactStealRange then
							local skill = math.clamp(1 + (o.Stats.Defense - ctrl.Stats.Dribbling) / 100, 0.4, 1.6)
							skill *= 1 + homeFactor(o) * C.HomeContactBonus
							if math.random() < C.ContactStealRate * skill * dt then
								ctrl.ReleaseAt = now + 0.8
								ctrl.StunnedUntil = now + C.TackledStunSeconds * 0.5
								ball.Controller = o
								ball.LastTouch = o
								event("steal", o.Id, ctrl.Id)
								break
							end
						end
					end
				end
			end
		else
			local f = math.max(0, 1 - k * dt)
			ball.Vel = Vector3.new(ball.Vel.X * f, 0, ball.Vel.Z * f)
			ball.Pos = ball.Pos + ball.Vel * dt
			-- Paredes
			if math.abs(ball.Pos.Z) > W / 2 - R then
				ball.Pos = Vector3.new(ball.Pos.X, R, math.sign(ball.Pos.Z) * (W / 2 - R))
				ball.Vel = Vector3.new(ball.Vel.X, 0, -ball.Vel.Z * cfg.Ball.Elasticity)
			end
			if math.abs(ball.Pos.X) > L / 2 - R and math.abs(ball.Pos.Z) > GW / 2 - R then
				ball.Pos = Vector3.new(math.sign(ball.Pos.X) * (L / 2 - R), R, ball.Pos.Z)
				ball.Vel = Vector3.new(-ball.Vel.X * cfg.Ball.Elasticity, 0, ball.Vel.Z)
			end
			-- Gol
			if math.abs(ball.Pos.X) > L / 2 + R and math.abs(ball.Pos.Z) < GW / 2 then
				local scorer = if ball.Pos.X > 0 then 1 else 2
				score[scorer] += 1
				event("goal", scorer, ball.LastTouch and ball.LastTouch.Id)
				kickoffTeam = 3 - scorer
				placeAll()
				state = Tactics.newState()
				startKickoff()
				pendingPass = nil
			else
				-- Control
				local speed = flat(ball.Vel).Magnitude
				if speed <= C.MaxCatchSpeed then
					local best, bd = nil, math.huge
					for _, p in players do
						if not p.Keeper and not p.Stunned and now >= p.ReleaseAt and (not ball.ProtectedBy or now >= ball.ProtectedUntil or ball.ProtectedBy == p) then
							local to = flat(ball.Pos) - p.Pos
							local d = to.Magnitude
							local bv = flat(ball.Vel)
							local grace = bv.Magnitude > C.FastBallSpeed and d > C.FastBallCloseRange and bv.Unit:Dot(-to.Unit) < C.FastBallFrontDot
							if not grace and d <= C.DribbleRange and d < bd and (d < 0.05 or p.Look:Dot(to.Unit) >= C.DribbleFrontDot) then
								best, bd = p, d
							end
						end
					end
					if best then
						ball.Controller = best
						if pendingPass then
							event(if best.Team == pendingPass.From.Team then "pass_ok" else "pass_lost", pendingPass.From.Id, best.Id)
							pendingPass = nil
						end
						if ball.LastTouch and ball.LastTouch.Team ~= best.Team then
							event("turnover", best.Team)
						end
						ball.LastTouch = best
					end
				end
			end
		end
	end

	-- Guardar frame cada 0.1 s
	if now >= nextFrame then
		nextFrame += 0.1
		local cols = { string.format("%.2f,%.2f,%.2f,%d", now, ball.Pos.X, ball.Pos.Z, if ball.Controller then ball.Controller.Id else (if keeperHold then keeperHold.Keeper.Id else 0)) }
		for _, p in players do
			local out = p.Out
			local role = if p.Keeper then "GK" elseif out then out.Role else "-"
			local tx, tz = p.Pos.X, p.Pos.Z
			if out and out.Target then tx, tz = out.Target.X, out.Target.Z end
			table.insert(cols, string.format("%.2f,%.2f,%s,%.2f,%.2f", p.Pos.X, p.Pos.Z, role, tx, tz))
		end
		table.insert(frames, table.concat(cols, ","))
	end
end

local fh = table.concat(frames, "\n")
print("SCORE", score[1], score[2])
-- Salida por stdout con marcadores (el CLI de Luau no escribe archivos)
print("===FRAMES===")
print(fh)
print("===EVENTS===")
print(table.concat(events, "\n"))
