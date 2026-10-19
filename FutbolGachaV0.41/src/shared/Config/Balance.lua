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
	Tackle = 1.0,
	Slide = 2.2,
	Juke = 0.9,
	Flick = 1.6,
}

local Balance = {
	Version = "V0.41", -- se escribe en la Salida al arrancar: asi sabes que version esta ejecutando Studio
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
		Length = 165, -- eje X (V0.39: antes 140)
		Width = 95, -- eje Z (V0.39: antes 80)
		GoalWidth = 28,
		GoalHeight = 11,
		GoalDepth = 8,
		WallThickness = 2,
		WallHeight = 30, -- altura total del cerramiento (muro bajo + red)
		BoardHeight = 4, -- parte baja y solida del muro: la unica que hace rebotar el balon
		CornerSize = 9, -- esquinas cortadas a 45 grados para que el balon no se atasque
		LineWidth = 0.5, -- grosor de las lineas pintadas. La linea de gol acaba justo en su borde exterior
		AreaRadius = 30, -- area grande: semicirculo con centro en el centro de la porteria (el portero se mueve dentro)
		SmallAreaDepth = 9, -- area pequena: rectangulo (largo hacia dentro del campo)...
		SmallAreaWidth = 44, -- ...y ancho (mas que la porteria)
		CenterCircleRadius = 12,
		GateWidth = 16, -- puerta de entrada al campo de exhibicion (lado que mira al lobby)
	},

	-- Posiciones de saque. X = distancia al centro hacia la propia porteria. Z = lateral.
	-- El slot 1 (delantero) usa Kickoff.Near o Kickoff.Far segun quien saque.
	Formation = {
		{ X = 0, Z = 0 },
		{ X = 31, Z = -19 },
		{ X = 31, Z = 19 },
	},
	-- Saque de centro: el que saca (delantero) la pasa SIEMPRE hacia atras, a un companero al azar (portero incluido).
	-- Los rivales no pueden entrar en el circulo central hasta que el balon se ha puesto en juego.
	Kickoff = {
		Near = 3, -- distancia al balon del delantero que saca
		Far = 15, -- distancia del delantero rival (fuera del circulo central)
		PassDelay = 0.7, -- segundos tras el silbato hasta que el delantero pasa
		ArriveSpeed = 12, -- velocidad con la que el pase llega al companero (el resto lo frena el cesped)
		ProtectSeconds = 3, -- mientras viaja el pase, solo el companero elegido puede controlarlo
		KeepOutSeconds = 2, -- tras el pase, los rivales siguen sin poder entrar en el circulo este tiempo
		KeepOutMargin = 1.5, -- margen extra fuera del circulo central
	},

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
		DribbleDistance = 2.6, -- el balon se mantiene a esta distancia delante (centro del balon, desde el centro del jugador)
		DribbleStrength = 18,
		DribbleResponse = 0.6, -- 0..1, cuanto corrige por fotograma (mas alto = balon mas pegado)
		DribbleLead = 0.06, -- solo para humanos en el servidor: compensa que el servidor ve al jugador con retraso
		DribbleSpeedFactor = 0.9, -- con el balon se corre un poco mas lento (asi se le puede alcanzar)
		DribbleSnapRate = 22, -- rapidez con la que el balon se recoloca delante del jugador al girar (mas = mas pegado) -- segundos de anticipacion: el objetivo se adelanta segun la velocidad del jugador
		DribbleFrontDot = 0.2, -- el balon debe estar delante del jugador
		MaxCatchSpeed = 65, -- un balon mas rapido que esto no se controla (el balon ya no choca con los jugadores)
		MaxControlHeight = 3.5,
		KickLockSeconds = 0.4, -- tras golpear no puede recoger el balon al instante
		KickGraceSeconds = 0.15, -- (sin uso desde V0.39: lo sustituye la regla de balon rapido)
		FastBallSpeed = 12, -- un balon mas rapido que esto solo lo controla quien lo tiene viniendole de frente...
		FastBallFrontDot = 0.2, -- ...(dentro de un cono de unos 78 grados respecto a su trayectoria)...
		FastBallCloseRange = 2, -- ...o quien esta pegado a el
		ChargeSeconds = 0.55, -- tiempo para cargar el tiro (y el pase) al maximo (V0.41: antes 1.0)
		TackleRange = 5, -- alcance de la entrada (al jugador o al balon, lo que este mas cerca)
		TackleBaseChance = 0.6,
		-- Robo por contacto: si un rival pone el cuerpo junto al balon, puede quitarlo sin pulsar nada
		ContactStealRange = 2.6, -- distancia del rival al balon
		ContactStealRate = 0.9, -- probabilidad por segundo (se ajusta con Defensa vs Regate)
		TackleStunSeconds = 0.35, -- aturdimiento de quien FALLA una entrada contra un rival (sin rival no hay aturdimiento)
		TackleWhiffCooldown = 0.5, -- espera si pulsas Q sin ningun rival con balon a tu alcance
		-- V0.41: la entrada (Q) es un pequeno impulso hacia el balon; durante el impulso intenta robar en cada fotograma
		TackleLungeSeconds = 0.28, -- duracion del impulso
		TackleLungeSpeed = 30, -- velocidad del impulso
		TackleAimRange = 14, -- si el rival con balon esta a menos de esto, el impulso va hacia el (aunque no le mires)
		RequestBallSeconds = 2.5, -- "pedir el balon" (E sin balon): durante este tiempo tus companeros bots buscan pasartela
		TackledStunSeconds = 0.3,
		-- Ayuda para robar siendo humano: el servidor ve tu personaje con algo de retraso (los bots no tienen ese problema)
		HumanLagSeconds = 0.1, -- se adelanta tu posicion segun tu velocidad para compensar el retraso
		HumanTackleRangeBonus = 2, -- alcance extra de la entrada (Q)
		HumanTackleFacingDot = -0.2, -- no hace falta mirar exacto al balon (-1 = da igual hacia donde mires, 1 = exacto)
		HumanTackleChanceBonus = 0.12, -- probabilidad extra de robar en entradas y segadas
		HumanSlideRangeBonus = 2, -- alcance extra de la segada (C)
		HumanSlideHitDot = 0, -- la segada vale aunque el balon no este justo delante
		HumanContactBonus = 1.3, -- robo por contacto algo mas facil para humanos
		BotVsHumanFactor = 0.85, -- los bots roban algo menos a los humanos
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
		PassSpeedMax = 70,
		-- Pase de un humano (mantener E para cargar): toque corto sin cargar, pase largo con la carga completa
		PassSpeedTap = 36, -- sin cargar (V0.41: antes 24)
		PassSpeedFull = 92, -- carga completa (V0.41: antes 72)
		PassDefaultCharge = 0.35, -- si llega un pase sin carga (por ejemplo, un boton tactil antiguo)
		PassStatMin = 0.9, -- la estadistica de Pase cambia la fuerza entre x0.9 (Pase 1)...
		PassStatMax = 1.1, -- ...y x1.1 (Pase 100)
		PassAssistCone = 32, -- ayuda de pase: si un companero esta dentro de este cono (grados)...
		PassAssist = 1, -- ...el pase se orienta hacia el (0 = sin ayuda, 1 = directo a el)
		-- "Mini-iman" (V0.41): mientras viaja, el pase se curva un poco hacia el companero al que va y frena al llegar,
		-- para que lo controle en vez de pasarse de largo
		MagnetMaxAngle = 40, -- solo si el balon va mas o menos hacia el (grados)
		MagnetTurnRate = 75, -- giro maximo del balon (grados por segundo)
		MagnetArriveSpeed = 30, -- velocidad maxima con la que llega al companero...
		MagnetBrakePerStud = 1.6, -- ...mas esto por cada stud que le falte (lejos no frena)
		MagnetBrakeRate = 5, -- rapidez del frenado
		MagnetSeconds = 3, -- el iman dura como mucho esto
		PassAssistLead = 0.35, -- segundos de anticipacion si el companero va corriendo
		PassLift = 0.02,
		PassErrorMaxDeg = 6,
		PassErrorMinDeg = 1,
		ShotSpeedMin = 56,
		ShotSpeedMax = 100, -- V0.39: algo mas lentos (antes 60 / 110)
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
		Position = Vector3.zero, -- se calcula abajo segun el tamano del campo (pegado al paseo del lobby)
		RotationY = math.pi / 2, -- el largo del campo va a lo largo del eje Z del mundo
		GoalResetSeconds = 1.5, -- si el balon se queda dentro de una porteria este tiempo, vuelve al centro
		EnterMargin = 1.5, -- entras al patio al pasar este margen dentro de las paredes...
		LeaveMargin = 2.5, -- ...y sales al pasar este margen fuera (evita entrar y salir en el umbral)
	},

	-- Sonidos. Sube los .mp3 de la carpeta "sonidos" a Roblox y pega aqui el ID de cada uno (solo el numero).
	-- Mientras Id este vacio se usa Fallback (un sonido que trae Roblox de serie) o, si no hay, no suena.
	Sounds = {
		KickPass = { Id = "94269892153222", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.8 },
		KickShot = { Id = "78241680373098", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 1 },
		Bounce = { Id = "91033666319993", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.7 },
		Net = { Id = "139305215355493", Volume = 0.8 },
		KeeperCatch = { Id = "85090072602365", Fallback = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.9 },
		Tackle = { Id = "126266812487678", Fallback = "rbxasset://sounds/oof.ogg", Volume = 0.8 },
		Whistle = { Id = "103549404171443", Volume = 0.7 },
		CrowdLoop = { Id = "135155746478827", Volume = 0.3 }, -- ambiente de publico en bucle durante el partido
		CrowdGoal = { Id = "106759829542324", Volume = 0.9 },
		CrowdOoh = { Id = "125255434672731", Volume = 0.7 },
		CoinFlip = { Id = "133847220112766", Volume = 0.8 }, -- sorteo: la moneda sale despedida (coin_flip.mp3)
		CoinLand = { Id = "90645859976105", Volume = 0.8 }, -- sorteo: la moneda cae en la mesa (coin_land.mp3)
		Call = { Id = "", Fallback = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5 }, -- pedir el balon (E); pon tu ID si quieres otro
		MaxDistance = 260, -- a partir de esta distancia los sonidos del campo ya no se oyen
		MasterVolume = 1, -- multiplicador general (el volumen de cada jugador se ajusta en el menu de Configuracion)
	},

	-- Bots de campo (cerebro tactico: Tactics.lua). Los porteros siguen en Goalkeeper.
	Bots = {
		Enabled = true,
		-- Posicion de cada slot y su zona de actividad (profundidad: -1 = su porteria, 0 = medio campo, 1 = porteria rival)
		Positions = { "Delantero", "Medio", "Defensa" },
		Zones = {
			Delantero = { Min = -0.3, Max = 1 }, -- arriba: presiona y hace de pivot; no se hunde en su area
			Medio = { Min = -0.8, Max = 0.55 }, -- ala en ataque, corta pases en defensa; no se descuelga arriba
			Defensa = { Min = -1, Max = 0.15 }, -- atras: cierre en ataque y cubre la espalda; no pasa mucho del medio campo
		},
		ZonePenalty = 0.25, -- cuanto le cuesta salirse de su zona (por cada 10 studs fuera)
		-- Quien presiona: se suma este "retraso" al tiempo que tarda cada uno (menos = presiona antes)
		PressBias = { Delantero = 0, Medio = 1.4, Defensa = 1.0 }, -- V0.41: el medio casi no presiona (antes 0.4)
		PressCloseTime = 0.45, -- fuera de nuestro tercio solo presiona el delantero, salvo que otro ya este encima
		PressBiasDeep = { Delantero = 0.5, Medio = 0.35, Defensa = 0.15 }, -- si el rival ya esta en nuestro tercio
		MedioBehind = 8, -- el medio se queda al menos esto por detras del delantero (en ataque y en defensa)
		RequestBonus = 0.3, -- valor extra de pasar al humano que pide el balon (E)...
		RequestMinSafe = 0.3, -- ...si el pase es minimamente seguro
		HoldFactor = { Delantero = 1.2, Medio = 1, Defensa = 0.6 }, -- el defensa suelta el balon antes
		CierreBehind = 16, -- en ataque, el defensa (cierre) se queda esto por detras del balon...
		CierreRadius = 12, -- ...buscando hueco cerca de ese puesto
		BackFactor = 0.55, -- en defensa, el defensa cubre la espalda a esta fraccion del camino balon-porteria...
		BackMin = 12,
		BackMax = 38,
		LaneBallSide = 0.3, -- el medio corta el pase: entre el atacante peligroso y el balon
		ScreenDistance = 10, -- el delantero que no presiona tapa la salida a esta distancia del balon...
		ScreenMinDepth = -0.3, -- ...sin bajar de esta profundidad
		PlanInterval = 0.2, -- cada cuanto reparte papeles cada equipo (tambien es su tiempo de reaccion)
		DecisionInterval = 0.25, -- cada cuanto decide el que lleva el balon
		FirstTouchDelay = 0.3, -- tras recibir, espera esto antes de decidir
		AimTime = 0.2, -- tiempo perfilandose antes de pasar o tirar
		Reaction = 0.2, -- tiempo de reaccion que se le supone al rival al calcular si un pase es seguro
		-- Movimiento
		TurnRate = 8, -- giro maximo corriendo (radianes por segundo)
		TurnRateWithBall = 5, -- giro maximo con balon
		FaceTurnRate = 10, -- giro del cuerpo (mirar al balon, perfilarse)
		ArriveDistance = 1.5, -- a esta distancia de su sitio se para
		SlowDownDistance = 6, -- empieza a frenar a esta distancia de su sitio
		JogFactor = 0.75, -- velocidad al recolocarse sin prisa (respecto a la normal)
		SprintDistance = 16, -- si su sitio esta mas lejos que esto, corre a tope
		-- Pases
		PassArrive = 15, -- velocidad con la que llega un pase raso (V0.41: antes 12)...
		PassArrivePerStud = 0.18, -- ...mas esto por cada stud de distancia (los largos llegan con mas fuerza)
		MaxPassDistance = 75,
		PassBias = 1.15, -- cuanto le gusta pasar frente a conducir (mas = mas pases)
		LossWeight = 0.8, -- miedo a perder el balon (mas = juego mas seguro)
		PossessionValue = 0.06, -- lo que vale tener el balon (perderlo cuesta esto como poco)
		SafetyCenter = 0.15, -- calibrado con el simulador: margen de tiempo (s) con el que un pase es "50 % seguro"...
		SafetyScale = 0.12, -- ...y cuanto cambia la seguridad con cada decima de margen
		HoldSeconds = 1.5, -- si lleva el balon mas que esto, prefiere moverlo
		ProgressBonus = 0.15, -- premio por avanzar hacia la porteria rival (pases y conducciones)
		StallSeconds = 8, -- tras este tiempo con el balon sin llegar al ultimo tercio, urgencia maxima (arriesgan mas)
		HoldPenalty = 0.75,
		DecisionNoise = 0.012, -- azar en las decisiones (mas = menos predecible, mas errores)
		-- Tiro
		ShootRange = 48,
		MinShotXG = 0.035,
		BlockedShotFactor = 0.55, -- un rival en la linea de tiro reduce la probabilidad de gol a esto -- probabilidad de gol minima para plantearse tirar
		ShootBias = 3.0, -- ganas de tirar (mas = tiran antes en vez de buscar otro pase)
		JukePressure = 0.35, -- croqueta posible si un rival le llegaria en menos de esto (segundos)...
		JukeKeep = 0.5, -- ...y se valora como conservar el balon con esta probabilidad
		JukeCooldown = 6, -- segundos entre croquetas del mismo bot
		DuelLossChance = 0.55, -- si un rival le alcanza conduciendo, probabilidad de perderlo (en el juego, mas o menos la mitad)
		OwnGoalAvoid = 0.8, -- cuanto evita conducir hacia su propia porteria
		WallMargin = 7, -- conducir a menos de esto de una pared (o a una esquina) se penaliza
		-- Ataque sin balon (desmarques)
		PivotAhead = 26, -- el pivot busca sitio alrededor de un punto por delante del balon...
		PivotMinDepth = -12, -- ...y como poco a esta altura (0 = medio campo, negativo = en su campo)...
		PivotGoalGap = 16, -- ...y como mucho a esto de la linea de gol rival (centrado, delante del area)
		PivotRadius = 14, -- el pivot busca hueco cerca de su puesto (no se va hacia el balon)
		SupportAhead = 2, -- el ala, a la altura del balon (o un poco por delante)...
		SupportMaxBehind = 10, -- ...sin quedarse mucho mas atras que el balon
		SupportAheadDeep = 16, -- con el balon en su porteria el ala sube hasta esto mas (salida por fuera de la presion)...
		SupportWideDeep = 10, -- ...y se abre esto mas hacia la banda
		SupportWide = 21, -- ...y abierto hacia una banda
		AnchorWeight = 0.008, -- cuanto le cuesta alejarse de su puesto al buscar hueco
		SupportRadius = 26, -- radio de busqueda alrededor de su puesto
		GridStep = 4, -- separacion entre los puntos que prueba
		IdealPassMin = 12, -- distancia de pase comoda (min y max)
		IdealPassMax = 47,
		MinSpacing = 16, -- distancia minima entre companeros
		WeightSafe = 0.6, -- peso de "me pueden pasar sin que la corten"
		WeightThreat = 1.0, -- peso de "desde ahi hago dano"
		WeightSpace = 0.15, -- peso de "llego antes que los rivales"
		KeepBonus = 0.04, -- preferencia por no cambiar de sitio por poco
		-- Defensa
		JockeyDistance = 2.2, -- el que presiona se pone a esto del rival, por el lado de su porteria
		CoverFactor = 0.45, -- cobertura: a esta fraccion del camino entre balon y porteria...
		CoverMin = 9,
		CoverMax = 26,
		MarkDistance = 3.5, -- marcaje: a esto del rival, por el lado de la porteria...
		MarkBallSide = 0.15, -- ...y un poco hacia el balon para cortar el pase
		MarkDangerMin = 0.03, -- solo se marca a atacantes con algo de peligro
		CounterPressSeconds = 2, -- tras perder el balon, presion inmediata durante este tiempo
		HumanEngagedTime = 0.6, -- un companero humano solo cuenta como "el que va" si llega en menos de esto
		TackleChance = 0.4, -- probabilidad de intentar la entrada cada vez que tiene al rival a tiro
		DangerZoneThreat = 0.18, -- cerca de su porteria (zona de peligro) entran mas y mas a menudo
		TackleInterval = 1.0, -- tiempo minimo entre intentos
		SlideChance = 0.1,
	},

	-- Sorteo de saque con moneda antes de cada partido (el que gana decide si saca o cede el saque)
	CoinToss = {
		Enabled = true,
		ChooseSeconds = 12, -- tiempo para elegir cara o cruz (si no, se elige al azar)
		FlipSeconds = 3.9, -- duracion de la animacion de la moneda (lanzar, volar, caer y mostrar el lado)
		DecideSeconds = 10, -- tiempo para elegir sacar o ceder (si no, saca)
		ResultSeconds = 2.5, -- tiempo mostrando quien saca antes de la cuenta atras
		AIKickChance = 0.75, -- si gana la maquina, probabilidad de que elija sacar
		TablePosition = Vector3.new(0, 0, -10), -- mesa del sorteo, respecto al centro del campo
	},

	-- Volumenes por defecto del menu de Configuracion (0 a 1). Cada jugador los cambia para si mismo.
	AudioDefaults = {
		Master = 0.8,
		Effects = 1,
		Crowd = 0.8,
	},

	Camera = {
		Height = 36, -- V0.39: camara algo mas cercana (antes 42 / 34)
		Back = 29,
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

-- Campo de exhibicion del lobby: su muro con la puerta (lado +Z del campo, que mira al lobby) queda pegado al paseo
-- del lobby (X = -108). Si cambias el tamano del campo, el campo de exhibicion se recoloca solo.
Balance.Playground.Position = Vector3.new(-(108 + Balance.Field.Width / 2 + Balance.Field.WallThickness), -0.5, 0)

return Balance
