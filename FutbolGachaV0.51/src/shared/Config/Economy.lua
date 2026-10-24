--!strict
--[[
	Economy: todos los numeros de la economia (monedas, gemas, cajas, recompensas, granjas y robos).
	Regla de diseno: "datos en configuracion". Cambia valores AQUI, no dentro de la logica.

	Monedas: salen solas de los brainrots de tu granja, de los partidos, del diario y de subir de nivel.
	         Sirven para subir de nivel a los brainrots y para canjearlas (caro) por gemas.
	Gemas:   salen de los partidos, del diario, de subir de nivel tu cuenta, del canje de monedas y de la tienda (Robux).
	         Sirven para abrir cajas.

	V0.70: numeros mas grandes (unas 10 veces) y niveles de brainrot hasta 100 con evoluciones a nivel 50 y 90
	(ver Brainrots.lua). Las cuentas guardadas con la economia antigua se convierten solas al entrar (DataService).
]]

local Economy = {
	-- Guardado (DataStore). En Studio necesitas: Game Settings > Security > "Enable Studio Access to API Services".
	-- Si no esta activado, el juego funciona igual pero no guarda (lo avisa en la Salida).
	Data = {
		StoreName = "FutbolGacha_Datos_v1",
		AutosaveSeconds = 90,
		ResetInStudio = false, -- true = empiezas de cero cada vez que pulsas Play en Studio (para probar)
		Version = 2, -- version de los datos guardados (2 = economia V0.70: monedas y gemas x10)
		MigrateV1Factor = 10, -- al pasar de la version 1 a la 2, tus monedas y gemas se multiplican por esto
	},

	-- Iconos de la interfaz. Sube tu imagen (PNG) a Roblox y pega aqui su ID (solo el numero).
	-- Vacio = se dibuja el icono por defecto (moneda dorada redonda / gema azul).
	Icons = {
		Coins = "79584327840734", -- monedas (imagenes/moneda.png)
		Gems = "94093997558824", -- gemas (imagenes/diamante.png)
	},

	-- Saltar la animacion de las cajas: un Game Pass de pago unico (crealo en create.roblox.com > tu juego >
	-- Monetizacion > Pases, ponle 99 Robux y pega aqui su ID). Con 0 el boton "Saltar" no aparece.
	SkipSpinGamePassId = 2044208922,

	-- Cuenta nueva
	Start = {
		Coins = 5000,
		Gems = 5000, -- justo para abrir 5 cajas basicas de una vez (lo hace el tutorial)
		-- Brainrots al entrar por primera vez: NINGUNO (los primeros salen de las 5 cajas basicas del tutorial).
		-- Si pones Ids aqui, se colocan en la granja y en el equipo.
		Brainrots = {},
	},

	Brainrot = {
		MaxLevel = 100,
		-- Las monedas por segundo y el coste de cada nivel suben de forma EXPONENCIAL, con numeros distintos por
		-- calidad: ver LevelGrowth, LevelCost y LevelCostGrowth en Brainrots.lua (Rarities). Las evoluciones (nivel
		-- 50 y 90) multiplican las monedas y cuestan mas (Brainrots.lua, Evolutions).
		StatPerLevel = 0.06, -- puntos de estadistica por nivel: el nivel casi no cambia el partido (100 niveles = +6)
		SellFactor = 120, -- venta = monedas por segundo base x esto x variante...
		SellRefund = 0.4, -- ...mas el 40 % de lo que te gastaste en subirlo de nivel
		MaxInventory = 200,
		MaxLevelsPerClick = 10, -- el boton "+10" sube hasta 10 niveles de una vez (si llegan las monedas)
	},

	-- Cajas (se abren con gemas). Probabilidades en % por calidad (deben sumar 100).
	Cases = {
		{
			Id = "Basica",
			Name = "Caja Básica",
			Price = 1000,
			Color = Color3.fromRGB(120, 150, 190),
			Odds = { Comun = 62, Raro = 26, Epico = 9, Legendario = 2.5, Mitico = 0.45, Secreto = 0.05 },
		},
		{
			Id = "Epica",
			Name = "Caja Épica",
			Price = 3000,
			Color = Color3.fromRGB(160, 80, 255),
			Odds = { Comun = 25, Raro = 38, Epico = 25, Legendario = 9, Mitico = 2.6, Secreto = 0.4 },
		},
		{
			Id = "Legendaria",
			Name = "Caja Legendaria",
			Price = 8000,
			Color = Color3.fromRGB(255, 196, 40),
			Odds = { Comun = 0, Raro = 25, Epico = 40, Legendario = 24, Mitico = 9, Secreto = 2 },
		},
	},
	CaseSpinSeconds = 9, -- duracion de la ruleta al abrir una caja (V0.75: antes 5,5). Se salta con el pase SkipSpinGamePassId
	MaxCasesAtOnce = 5, -- cajas que se pueden abrir de una vez (botones x1 y x5)

	-- Recompensas por partido (solo si el partido llega al final)
	Match = {
		Win = { Coins = 5000, Gems = 120, XP = 120 },
		Draw = { Coins = 2500, Gems = 70, XP = 70 },
		Loss = { Coins = 1200, Gems = 40, XP = 45 },
		PerGoal = { Coins = 750, Gems = 10, XP = 15 }, -- por cada gol que marques tu
	},

	-- Nivel de la cuenta del jugador
	PlayerLevel = {
		XPBase = 100, -- XP para pasar del nivel 1 al 2...
		XPPerLevel = 60, -- ...y cada nivel pide esto mas
		RewardGemsBase = 200, -- gemas al subir de nivel = base + por nivel x nivel (con tope)
		RewardGemsPerLevel = 20,
		RewardGemsMax = 600,
		RewardCoinsPerLevel = 2500, -- monedas al subir de nivel = esto x nivel
	},

	-- Recompensa diaria: 7 dias seguidos (si fallas un dia, vuelves al 1). El dia 8 vuelve a empezar.
	Daily = {
		{ Coins = 3000, Gems = 100, Case = "Epica" }, -- (Case: caja gratis ese dia: Basica, Epica o Legendaria)
		{ Coins = 5000, Gems = 150, Case = "Legendaria" },
		{ Coins = 8000, Gems = 200, Case = "Basica" },
		{ Coins = 12000, Gems = 300, Case = "Basica" },
		{ Coins = 18000, Gems = 400, Case = "Epica" },
		{ Coins = 25000, Gems = 500, Case = "Basica" },
		{ Coins = 40000, Gems = 1000, Case = "Legendaria" },
	},
	DailyResetHourUTC = 0, -- hora (UTC) a la que cambia el dia

	-- Canje de monedas por gemas. El precio depende de tu NIVEL DE CUENTA: en el nivel 1 cuesta "Coins" (el minimo) y
	-- cada nivel lo multiplica por ExchangeLevelGrowth (x1,1 por nivel: nivel 10 = x2,4; nivel 30 = x16; nivel 50 = x106;
	-- nivel 100 = x12.500). Asi sigue la subida de lo que ganas, pero sale mucho mas rapido que antes (antes era lo que
	-- ganaba tu granja en 30 min, 8 h o 36 h).
	ExchangeLevelGrowth = 1.1,
	Exchange = {
		{ Id = "ex1", Coins = 1000000, Gems = 100 },
		{ Id = "ex2", Coins = 5000000, Gems = 500 },
		{ Id = "ex3", Coins = 25000000, Gems = 2000 },
	},

	-- Gemas con Robux. Crea los "Developer Products" en create.roblox.com (tu juego > Monetizacion > Productos de
	-- desarrollador) y pega aqui su ID. Con ProductId = 0 el pack aparece desactivado en la tienda.
	RobuxProducts = {
		{ ProductId = 3720766894, Gems = 1000, Label = "Puñado de gemas" }, -- 49 R$
		{ ProductId = 3720767113, Gems = 5500, Label = "Bolsa de gemas" }, -- 199 R$
		{ ProductId = 3720767278, Gems = 12000, Label = "Cofre de gemas" }, -- 399 R$
		{ ProductId = 3720767451, Gems = 26000, Label = "Montaña de gemas" }, -- 699 R$
	},

	-- Ofertas especiales con Robux: cada jugador puede comprar cada una UNA vez. Tambien son "Productos de
	-- desarrollador" (crealos igual que los packs de gemas y pega aqui su ID; con 0 la oferta no aparece).
	--   Starter: pack de bienvenida super barato, solo durante los primeros Days dias desde que entras al juego.
	--   LaunchVehicle: el vehiculo de lanzamiento (Vehicles.lua, "launchbolt"). Para quitar la oferta, ProductId = 0.
	Offers = {
		Starter = {
			ProductId = 3721077884, -- 19 R$
			Gems = 2500,
			Coins = 50000,
			Days = 3,
			Label = "Pack de bienvenida",
			Value = "x6", -- lo que se ve en la etiqueta ("6 veces mas que un pack normal")
			RealPrice = 149, -- "precio real" que se ve TACHADO al lado del de oferta (lo que costaria en packs normales)
		},
		LaunchVehicle = {
			ProductId = 3721078059, -- 49 R$
			Vehicle = "launchbolt",
			RealPrice = 199, -- (tachado al lado del de oferta)
			Label = "Oferta de lanzamiento",
		},
	},

	-- Codigos promocionales (ventana "Codigos"). La clave es el codigo EN MAYUSCULAS (al canjear da igual como lo
	-- escriba el jugador). Cada jugador puede canjear cada codigo una sola vez.
	--   Coins / Gems: lo que da. Brainrot: Id de un brainrot que regala (opcional).
	--   Expires: fecha de caducidad opcional, como os.time (segundos desde 1970, hora UTC). nil = no caduca.
	-- Para anadir uno nuevo basta con anadir una linea; para quitarlo, borrala.
	Codes = {
		BIENVENIDO = { Coins = 10000, Gems = 500 },
		GOLAZO = { Coins = 25000 },
		BRAINROT = { Gems = 1000 },
	} :: { [string]: { Coins: number?, Gems: number?, Brainrot: string?, Expires: number? } },

	-- Ganancias mientras no estas: un porcentaje de lo que generaria tu granja, con un tope de horas
	Offline = { Fraction = 0.25, MaxHours = 3 },

	-- Granjas (repartidas alrededor del spawn, lejos unas de otras) y robos
	Farm = {
		Plots = 8, -- granjas por servidor (pon el tamano del servidor a 8 en Game Settings > Places)
		Slots = 10, -- pedestales por granja
		RingRadius = 260, -- distancia del spawn (centro del mapa) a cada granja
		ConveyorSpeed = 24, -- cintas de los caminos (ida a la granja / vuelta al spawn): se suma a lo que andas
		LockSeconds = 90, -- bloqueo de la granja (pisa el boton rojo de tu granja)
		LockCooldown = 60, -- espera desde que acaba un bloqueo hasta poder bloquear otra vez
		-- Partidos: al entrar a un partido tu granja se bloquea sola. Si ya estaba bloqueada, ese bloqueo se congela
		-- (no corre mientras juegas) y al volver te queda esta fraccion de lo que te quedaba (60 s -> 30 s).
		LockWhileInMatch = true,
		MatchLockResumeFactor = 0.5,
		StealHoldSeconds = 1.5, -- mantener E/clic para coger un brainrot ajeno
		StealSeconds = 75, -- tiempo para llevarlo a tu granja (si no, vuelve a su dueno). Las granjas estan lejos.
		ReturnRange = 6, -- si el dueno se acerca a esta distancia del ladron, lo recupera
		ThiefSpeed = 0.7, -- el ladron va mas lento (x0.7)
		NewPlayerShieldSeconds = 120, -- al entrar al servidor tu granja esta protegida este tiempo
	},
}

return Economy
