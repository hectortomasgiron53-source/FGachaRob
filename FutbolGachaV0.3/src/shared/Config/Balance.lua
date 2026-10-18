--!strict
--[[
	Balance: todos los numeros ajustables del juego.
	Regla de diseno: "datos en configuracion". Cambia valores AQUI, no dentro de la logica.
	Son valores iniciales; se ajustan al probar.
]]

local Cooldowns: { [string]: number } = {
	Pass = 0.3,
	Shoot = 0.5,
	ShootHigh = 0.5,
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
		TeamSize = 4, -- 4v4: 3 de campo + 1 portero
		GoalkeeperSlot = 4, -- este slot de cada equipo es SOLO portero
		MaxSimultaneous = 4, -- partidos a la vez por servidor
		ArenaSpacing = 300, -- studs entre campos (eje Z)
		ArenaBasePosition = Vector3.new(0, 500, 0), -- los campos flotan lejos del lobby
	},

	Field = {
		Length = 140, -- eje X
		Width = 80, -- eje Z
		GoalWidth = 28,
		GoalHeight = 11,
		GoalDepth = 8,
		WallThickness = 2,
		WallHeight = 30, -- altura total del cerramiento (muro bajo + red)
		BoardHeight = 4, -- parte baja y solida del muro: la unica que hace rebotar el balon
		CornerSize = 8, -- esquinas cortadas a 45 grados para que el balon no se atasque
		LineWidth = 0.5, -- grosor de las lineas pintadas. La linea de gol acaba justo en su borde exterior
		AreaRadius = 26, -- area grande: semicirculo con centro en el centro de la porteria (el portero se mueve dentro)
		SmallAreaDepth = 8, -- area pequena: rectangulo (largo hacia dentro del campo)...
		SmallAreaWidth = 40, -- ...y ancho (mas que la porteria)
		CenterCircleRadius = 10,
		GateWidth = 16, -- puerta de entrada al campo de exhibicion (lado que mira al lobby)
	},

	-- Posiciones de saque. X = distancia al centro hacia la propia porteria. Z = lateral.
	-- El slot 1 (delantero) usa Kickoff.Near o Kickoff.Far segun quien saque.
	Formation = {
		{ X = 0, Z = 0 },
		{ X = 26, Z = -16 },
		{ X = 26, Z = 16 },
	},
	Kickoff = { Near = 3, Far = 14 },

	-- Gradas alrededor del campo de partido: dos pisos, negras, curvas en las esquinas.
	-- Una esquina no tiene primer piso: es el tunel de vestuarios, con el segundo piso por encima.
	Stands = {
		Tier1Rows = 6,
		Tier2Rows = 6,
		RowDepth = 3,
		RowRise = 1.8,
		LandingDepth = 3, -- pasillo entre el primer y el segundo piso
		Color = Color3.fromRGB(16, 16, 18), -- negro
		SeatColor = Color3.fromRGB(34, 34, 38), -- asientos gris muy oscuro
		FanDensity = 0.12, -- fraccion de asientos con aficionado
		CornerSegments = 10, -- tramos de cada curva (mas = curva mas suave, mas piezas)
		TunnelWidth = 10,
		TunnelHeight = 7,
		TunnelInnerLength = 14,
		WingWallHeight = 7,
	},

	-- Portero (slot Match.GoalkeeperSlot). Se mueve solo por su linea de gol siguiendo el balon y para tiros.
	Goalkeeper = {
		-- Colocacion
		LineOffset = 2.5, -- lo minimo que se separa de su linea de gol (lo maximo es el borde del area)
		MoveSpeed = 18, -- studs/s colocandose
		AdvanceFactor = 0.2, -- cuanto sale hacia el balon (fraccion de la distancia balon-porteria)...
		NormalMaxAdvance = 7, -- ...como mucho esto, si no hay peligro
		OneOnOneDistance = 34, -- rival con balon a menos de esto de la porteria: sale a achicar (1v1)
		CloseDownGap = 5, -- al achicar se queda a esta distancia del balon
		RushSpeed = 26, -- studs/s saliendo a achicar o a por un balon suelto
		LungeDistance = 6, -- rival con balon a esta distancia: se tira a sus pies
		LungeTime = 0.35,
		LungeCooldown = 1.8,
		RushMaxSpeed = 25, -- sale a por balones sueltos dentro de su area que vayan mas lentos que esto
		-- Lectura del tiro
		ShotMinSpeed = 20, -- solo reacciona a balones que vienen hacia su porteria a mas de esta velocidad
		MaxPredictTime = 1.5, -- solo reacciona si el balon llegara en menos de este tiempo
		ReactionMax = 0.3, -- retraso de reaccion con Goalkeeping 0 (segundos)...
		ReactionMin = 0.1, -- ...y con Goalkeeping 100
		-- Acciones
		SetReach = 1.6, -- si el balon le llega a menos de esto de lado (y bajo), solo da un paso
		JumpReachZ = 2.5, -- si le llega a menos de esto de lado pero alto, salta
		JumpHeight = 4.5, -- altura maxima del salto
		JumpTime = 0.7,
		DiveReach = 8, -- lo maximo que se desplaza de lado en una estirada
		DiveTime = 0.5, -- duracion de la estirada (mas = mas lento, menos paradas a la escuadra)
		DiveMinHeight = 1.3, -- altura del cuerpo tumbado en una estirada a ras de suelo
		DiveMaxRise = 4.5, -- cuanto puede elevar el cuerpo en una estirada alta
		DownTime = 0.6, -- tiempo en el suelo tras la estirada
		GetUpTime = 0.45,
		-- Cuerpo (capsula de pies a manos) y contacto
		BodyRadius = 1.3,
		HandsOffset = 2.8, -- de la cadera a las manos (brazos estirados)
		FeetOffset = 2.6,
		CatchBase = 0.6, -- probabilidad de blocar (si no, despeja) con un balon a velocidad normal
		CatchSpeedFrom = 45, -- a partir de esta velocidad cuesta mas blocar...
		CatchSpeedRange = 120, -- ...y resta 1 (100 %) cada este tanto de velocidad extra
		ClaimMaxSpeed = 20, -- un balon mas lento que esto lo bloca siempre
		ParryFactor = 0.45, -- velocidad del rechace hacia el campo (fraccion de la del tiro)
		ParrySide = 0.3, -- velocidad del rechace hacia el lado
		ParryLift = 14,
		ParryCooldown = 0.35,
		-- Dificultad de cada parada (0 = facil, 1 = imposible). Probabilidad de pararla = 1 - dificultad.
		-- Si la para pero la dificultad pasa de CatchMaxDifficulty, no puede blocar: despeja.
		Difficulty = {
			SpeedWeight = 0.45, -- peso de la fuerza del balon al llegarle...
			SpeedFrom = 35, -- ...que empieza a contar a esta velocidad...
			SpeedRange = 70, -- ...y es maxima con este tanto mas
			PlaceWeight = 0.5, -- peso de la colocacion (palo, larguero y sobre todo escuadra)
			CloseWeight = 0.45, -- peso de la cercania (poco tiempo para reaccionar)
			CloseFull = 0.2, -- si vio el tiro hace menos de esto, cercania maxima (a bocajarro)...
			CloseRange = 0.5, -- ...y deja de contar con este tanto mas
			CatchMaxDifficulty = 0.3, -- por encima, aunque la pare no puede blocarla
			MinSave = 0.04,
			MaxSave = 0.97,
			LeakKeep = 0.8, -- si se le cuela, el balon conserva esta fraccion de su velocidad
		},
		-- Con el balon
		HoldSeconds = 1.0, -- tiempo con el balon en las manos (ya de pie) antes de sacar
		ReleaseCooldown = 1.2, -- tras sacar, tiempo sin poder volver a atrapar
		ClearSpeed = 55,
		ClearLift = 0.18,
	},

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
		AnnounceCooldown = 6, -- segundos minimos entre dos mensajes de "controla el balon" del mismo jugador
		KickRange = 5.5, -- alcance de golpeo (lo valida el servidor)
		DribbleRange = 4.5, -- a esta distancia el jugador "controla" el balon
		DribbleReleaseRange = 8, -- si el balon se aleja mas de esto, lo suelta
		DribbleDistance = 3.2, -- el balon se mantiene a esta distancia delante
		DribbleStrength = 18,
		DribbleResponse = 0.6, -- 0..1, cuanto corrige por fotograma (mas alto = balon mas pegado)
		DribbleLead = 0.1,
		DribbleSnapRate = 22, -- rapidez con la que el balon se recoloca delante del jugador al girar (mas = mas pegado) -- segundos de anticipacion: el objetivo se adelanta segun la velocidad del jugador
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
		HighUpMin = 25, -- tiro alto (G): velocidad HACIA ARRIBA sin cargar (vaselina baja)...
		HighUpMax = 90, -- ...y con carga completa (se va por encima del larguero)
		HighSpeedFactor = 0.85, -- el tiro alto sale algo mas lento que el raso
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

	-- Campo de exhibicion del lobby, abierto como "patio de juegos": entras, juegas solo con el balon, sin goles ni reglas.
	Playground = {
		Position = Vector3.new(-150, -0.5, 0), -- centro del campo (la cara superior del suelo queda a Y = -0.5)
		RotationY = math.pi / 2, -- el largo del campo va a lo largo del eje Z del mundo
		GoalResetSeconds = 1.5, -- si el balon se queda dentro de una porteria este tiempo, vuelve al centro
		EnterMargin = 1.5, -- entras al patio al pasar este margen dentro de las paredes...
		LeaveMargin = 2.5, -- ...y sales al pasar este margen fuera (evita entrar y salir en el umbral)
	},

	-- Sonidos. Sube los .mp3 de la carpeta "sonidos" a Roblox y pega aqui el ID de cada uno (solo el numero).
	-- Mientras Id este vacio se usa Fallback (un sonido que trae Roblox de serie) o, si no hay, no suena.
	Sounds = {
		KickPass = { Id = "94269892153222", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.8, Pitch = 1.6 },
		KickShot = { Id = "78241680373098", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Pitch = 1.25 },
		Bounce = { Id = "91033666319993", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.7, Pitch = 0.9 },
		Net = { Id = "139305215355493", Volume = 0.8 },
		KeeperCatch = { Id = "85090072602365", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.9, Pitch = 0.75 },
		Tackle = { Id = "126266812487678", Fallback = "rbxasset://sounds/oof.ogg", Volume = 0.5 },
		Whistle = { Id = "103549404171443", Volume = 0.7 },
		CrowdLoop = { Id = "135155746478827", Volume = 0.3 }, -- ambiente de publico en bucle durante el partido
		CrowdGoal = { Id = "106759829542324", Volume = 0.9 },
		CrowdOoh = { Id = "125255434672731", Volume = 0.7 },
		MaxDistance = 260, -- a partir de esta distancia los sonidos del campo ya no se oyen
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
