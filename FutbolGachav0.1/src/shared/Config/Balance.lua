--!strict
--[[
	Balance: todos los numeros ajustables del juego.
	Regla de diseno: "datos en configuracion". Cambia valores AQUI, no dentro de la logica.
	Son valores iniciales; se ajustan al probar.
]]

local Cooldowns: { [string]: number } = {
	Pass = 0.3,
	Shoot = 0.5,
	Tackle = 1.4,
}

local Balance = {
	Match = {
		Duration = 180, -- segundos de partido
		GoldenGoalSeconds = 60, -- tiempo extra si hay empate
		CountdownSeconds = 3,
		GoalCelebrationSeconds = 4,
		FinalSeconds = 5, -- tiempo mostrando el resultado antes de volver al lobby
		TeamSize = 3,
		MaxSimultaneous = 4, -- partidos a la vez por servidor
		ArenaSpacing = 300, -- studs entre campos (eje Z)
		ArenaBasePosition = Vector3.new(0, 500, 0), -- los campos flotan lejos del lobby
	},

	Field = {
		Length = 140, -- eje X
		Width = 80, -- eje Z
		GoalWidth = 20,
		GoalHeight = 8,
		GoalDepth = 8,
		WallThickness = 2,
		WallHeight = 30,
		CornerSize = 8, -- esquinas cortadas a 45 grados para que el balon no se atasque
	},

	-- Posiciones de saque. X = distancia al centro hacia la propia porteria. Z = lateral.
	-- El slot 1 (delantero) usa Kickoff.Near o Kickoff.Far segun quien saque.
	Formation = {
		{ X = 0, Z = 0 },
		{ X = 26, Z = -16 },
		{ X = 26, Z = 16 },
	},
	Kickoff = { Near = 3, Far = 14 },

	Ball = {
		Diameter = 3,
		Density = 0.5,
		Friction = 0.3,
		Elasticity = 0.55,
		RollDamping = 0.7, -- frenado del balon rodando (por segundo)
		AngularDamping = 2.5,
		MaxSpeed = 140,
	},

	Control = {
		KickRange = 5.5, -- alcance de golpeo (lo valida el servidor)
		DribbleRange = 4.5, -- a esta distancia el jugador "controla" el balon
		DribbleReleaseRange = 6.5, -- si el balon se aleja mas de esto, lo suelta
		DribbleDistance = 3.2, -- el balon se mantiene a esta distancia delante
		DribbleStrength = 14,
		DribbleResponse = 0.35,
		DribbleFrontDot = 0.2, -- el balon debe estar delante del jugador
		MaxCatchSpeed = 55, -- un balon mas rapido que esto no se controla
		MaxControlHeight = 3.5,
		KickLockSeconds = 0.4, -- tras golpear no puede recoger el balon al instante
		ChargeSeconds = 1.0, -- tiempo para cargar el tiro al maximo
		TackleRange = 5,
		TackleBaseChance = 0.5,
		TackleStunSeconds = 0.8, -- aturdimiento de quien falla la entrada
		TackledStunSeconds = 0.3,
		Cooldowns = Cooldowns,
	},

	Kick = {
		PassSpeedMin = 35,
		PassSpeedMax = 60,
		PassLift = 0.02,
		PassErrorMaxDeg = 6,
		PassErrorMinDeg = 1,
		ShotSpeedMin = 60,
		ShotSpeedMax = 110,
		ShotMinCharge = 0.45, -- un tiro sin cargar sale al 45 % de potencia
		ShotLiftMin = 0.05,
		ShotLiftMax = 0.2,
		ErrorMaxDeg = 8,
		ErrorMinDeg = 1,
		AimAssist = 0.5, -- 0 = sin ayuda, 1 = apunta directo a la porteria
		AimAssistConeDegrees = 40,
	},

	Speed = { Min = 15, Max = 21, SprintMultiplier = 1.3 },

	Stamina = {
		Max = 100,
		DurationMin = 4, -- segundos de sprint con Resistencia 1
		DurationMax = 10, -- segundos de sprint con Resistencia 100
		RegenSeconds = 8, -- segundos para recargar la barra entera
		RegenDelay = 1,
		ResumeAt = 25, -- tras agotarse, puede volver a esprintar con 25 de barra
	},

	Camera = { Height = 42, Back = 34, Smoothing = 8 },
}

return Balance
