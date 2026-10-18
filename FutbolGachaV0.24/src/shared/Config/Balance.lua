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
	Slide = 2.2,
	Juke = 0.9,
	Flick = 1.6,
}

local Balance = {
	Match = {
		Duration = 180, -- segundos de partido
		GoldenGoalSeconds = 60, -- tiempo extra si hay empate
		CountdownSeconds = 3,
		GoalCelebrationSeconds = 4,
		GoalConfirmSeconds = 0.35, -- el balon debe seguir dentro de la porteria este tiempo antes de dar el gol (compensa el retraso de replicacion: el cliente ve el balon un poco despues que el servidor)
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
		WallHeight = 30, -- altura total del cerramiento (muro bajo + red)
		BoardHeight = 4, -- parte baja y solida del muro: la unica que hace rebotar el balon
		CornerSize = 8, -- esquinas cortadas a 45 grados para que el balon no se atasque
		LineWidth = 0.5, -- grosor de las lineas pintadas. La linea de gol acaba justo en su borde exterior
		PenaltyDepth = 18, -- area grande (largo hacia dentro del campo)
		PenaltyWidth = 44,
		SixYardDepth = 7, -- area pequena
		SixYardWidth = 28,
		CenterCircleRadius = 10,
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
		DribbleReleaseRange = 8, -- si el balon se aleja mas de esto, lo suelta
		DribbleDistance = 3.2, -- el balon se mantiene a esta distancia delante
		DribbleStrength = 18,
		DribbleResponse = 0.6, -- 0..1, cuanto corrige por fotograma (mas alto = balon mas pegado)
		DribbleLead = 0.1, -- segundos de anticipacion: el objetivo se adelanta segun la velocidad del jugador
		DribbleFrontDot = 0.2, -- el balon debe estar delante del jugador
		MaxCatchSpeed = 65, -- un balon mas rapido que esto no se controla (el balon ya no choca con los jugadores)
		MaxControlHeight = 3.5,
		KickLockSeconds = 0.4, -- tras golpear no puede recoger el balon al instante
		ChargeSeconds = 1.0, -- tiempo para cargar el tiro al maximo
		TackleRange = 5,
		TackleBaseChance = 0.5,
		TackleStunSeconds = 0.35, -- aturdimiento de quien FALLA una entrada contra un rival (sin rival no hay aturdimiento)
		TackleWhiffCooldown = 0.5, -- espera si pulsas Q sin ningun rival con balon a tu alcance
		TackledStunSeconds = 0.3,
		Cooldowns = Cooldowns,

		-- Segada (sin balon): el jugador se lanza hacia delante unos instantes
		SlideSeconds = 0.5,
		SlideSpeed = 38,
		SlideRecoverySeconds = 0.5, -- tiempo en el que no puede actuar tras la segada
		SlideHitRange = 5.5,
		SlideHitDot = 0.3,
		SlideBaseChance = 0.65,
		SlidePokeSpeed = 45, -- si toca un balon suelto, lo empuja con esta velocidad
		SlideStunSeconds = 0.7, -- aturdimiento del rival al que se le roba el balon

		-- Regates (con balon)
		JukeSeconds = 0.22,
		JukeSpeedMultiplier = 2,
		JukeForwardBias = 0.4, -- 0 = lateral puro
		JukeImmuneSeconds = 0.4, -- no se le puede robar durante este tiempo
		FlickForward = 26,
		FlickUp = 48,
		FlickImmuneSeconds = 0.5,
		FlickProtectSeconds = 1.2, -- solo tu puedes recoger el balon tras el sombrero
		FlickLockSeconds = 0.5,
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

	Camera = {
		Height = 42,
		Back = 34,
		Smoothing = 8, -- solo suaviza el adelanto hacia el balon y el zoom; la posicion del jugador se sigue sin retraso
		LeadFactor = 0.5, -- cuanto se adelanta la vista hacia el balon (0 = centrada en el jugador)
		MaxLead = 22, -- adelanto maximo en studs
		ZoomOutStart = 30, -- a partir de esta distancia jugador-balon se aleja la camara...
		ZoomOutRange = 50, -- ...y llega al maximo tras este rango extra
		ZoomOutMax = 0.6, -- +60 % de distancia como maximo
		Sensitivity = 0.0035, -- radianes por pixel al girar con el click derecho
		MinPitchDeg = 30,
		MaxPitchDeg = 80,
		ReturnOnRelease = false, -- true = al soltar el click derecho la camara vuelve a la vista por defecto
	},
}

return Balance
