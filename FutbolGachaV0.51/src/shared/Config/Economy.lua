--!strict
--[[
	Economy: todos los numeros de la economia (monedas, gemas, cajas, recompensas, granjas y robos).
	Regla de diseno: "datos en configuracion". Cambia valores AQUI, no dentro de la logica.

	Monedas: salen solas de los brainrots de tu granja, de los partidos, del diario y de subir de nivel.
	         Sirven para subir de nivel a los brainrots y para canjearlas (caro) por gemas.
	Gemas:   salen de los partidos, del diario, de subir de nivel tu cuenta, del canje de monedas y de la tienda (Robux).
	         Sirven para abrir cajas.
]]

local Economy = {
	-- Guardado (DataStore). En Studio necesitas: Game Settings > Security > "Enable Studio Access to API Services".
	-- Si no esta activado, el juego funciona igual pero no guarda (lo avisa en la Salida).
	Data = {
		StoreName = "FutbolGacha_Datos_v1",
		AutosaveSeconds = 90,
		ResetInStudio = false, -- true = empiezas de cero cada vez que pulsas Play en Studio (para probar)
	},

	-- Iconos de la interfaz. Sube tu imagen (PNG) a Roblox y pega aqui su ID (solo el numero).
	-- Vacio = se dibuja el icono por defecto (moneda dorada redonda / gema azul).
	Icons = {
		Coins = "", -- monedas
		Gems = "", -- gemas
	},

	-- Saltar la animacion de las cajas: un Game Pass de pago unico (crealo en create.roblox.com > tu juego >
	-- Monetizacion > Pases, ponle 99 Robux y pega aqui su ID). Con 0 el boton "Saltar" no aparece.
	SkipSpinGamePassId = 0,

	-- Cuenta nueva
	Start = {
		Coins = 500,
		Gems = 150, -- llega para abrir la primera caja basica
		-- Equipo inicial (4 comunes: delantero, medio, defensa, portero). Se colocan en la granja y en el equipo.
		Brainrots = { "pipi_kiwi", "tim_cheese", "svinina_bombardino", "talpa_di_fero" },
	},

	Brainrot = {
		MaxLevel = 25,
		-- Las monedas por segundo y el coste de cada nivel suben de forma EXPONENCIAL, con numeros distintos por
		-- calidad: ver LevelGrowth, LevelCost y LevelCostGrowth en Brainrots.lua (Rarities)
		StatPerLevel = 0.8, -- puntos de estadistica por nivel
		SellFactor = 120, -- venta = monedas por segundo base x esto x variante...
		SellRefund = 0.4, -- ...mas el 40 % de lo que te gastaste en subirlo de nivel
		MaxInventory = 200,
	},

	-- Cajas (se abren con gemas). Probabilidades en % por calidad (deben sumar 100).
	Cases = {
		{
			Id = "Basica",
			Name = "Caja Básica",
			Price = 100,
			Color = Color3.fromRGB(120, 150, 190),
			Odds = { Comun = 62, Raro = 26, Epico = 9, Legendario = 2.5, Mitico = 0.45, Secreto = 0.05 },
		},
		{
			Id = "Epica",
			Name = "Caja Épica",
			Price = 300,
			Color = Color3.fromRGB(160, 80, 255),
			Odds = { Comun = 25, Raro = 38, Epico = 25, Legendario = 9, Mitico = 2.6, Secreto = 0.4 },
		},
		{
			Id = "Legendaria",
			Name = "Caja Legendaria",
			Price = 800,
			Color = Color3.fromRGB(255, 196, 40),
			Odds = { Comun = 0, Raro = 25, Epico = 40, Legendario = 24, Mitico = 9, Secreto = 2 },
		},
	},
	CaseSpinSeconds = 5.5, -- duracion de la ruleta al abrir una caja

	-- Recompensas por partido (solo si el partido llega al final)
	Match = {
		Win = { Coins = 400, Gems = 12, XP = 120 },
		Draw = { Coins = 200, Gems = 7, XP = 70 },
		Loss = { Coins = 100, Gems = 4, XP = 45 },
		PerGoal = { Coins = 60, Gems = 1, XP = 15 }, -- por cada gol que marques tu
	},

	-- Nivel de la cuenta del jugador
	PlayerLevel = {
		XPBase = 100, -- XP para pasar del nivel 1 al 2...
		XPPerLevel = 60, -- ...y cada nivel pide esto mas
		RewardGemsBase = 20, -- gemas al subir de nivel = base + por nivel x nivel (con tope)
		RewardGemsPerLevel = 2,
		RewardGemsMax = 60,
		RewardCoinsPerLevel = 250, -- monedas al subir de nivel = esto x nivel
	},

	-- Recompensa diaria: 7 dias seguidos (si fallas un dia, vuelves al 1). El dia 8 vuelve a empezar.
	Daily = {
		{ Coins = 300, Gems = 10 },
		{ Coins = 500, Gems = 15 },
		{ Coins = 800, Gems = 20 },
		{ Coins = 1200, Gems = 30 },
		{ Coins = 1800, Gems = 40 },
		{ Coins = 2500, Gems = 50 },
		{ Coins = 4000, Gems = 100 },
	},
	DailyResetHourUTC = 0, -- hora (UTC) a la que cambia el dia

	-- Canje de monedas por gemas (a proposito caro: es mas rentable jugar partidos)
	Exchange = {
		{ Id = "ex1", Coins = 15000, Gems = 25 },
		{ Id = "ex2", Coins = 60000, Gems = 110 },
		{ Id = "ex3", Coins = 200000, Gems = 400 },
	},

	-- Gemas con Robux. Crea los "Developer Products" en create.roblox.com (tu juego > Monetizacion > Productos de
	-- desarrollador) y pega aqui su ID. Con ProductId = 0 el pack aparece desactivado en la tienda.
	RobuxProducts = {
		{ ProductId = 0, Gems = 100, Label = "Puñado de gemas" },
		{ ProductId = 0, Gems = 550, Label = "Bolsa de gemas" },
		{ ProductId = 0, Gems = 1200, Label = "Cofre de gemas" },
		{ ProductId = 0, Gems = 2600, Label = "Montaña de gemas" },
	},

	-- Ganancias mientras no estas: un porcentaje de lo que generaria tu granja, con un tope de horas
	Offline = { Fraction = 0.25, MaxHours = 3 },

	-- Granjas (a la izquierda del spawn) y robos
	Farm = {
		Plots = 8, -- granjas por servidor (pon el tamano del servidor a 8 en Game Settings > Places)
		Slots = 10, -- pedestales por granja
		LockSeconds = 60, -- bloqueo de la granja (pisa el boton rojo de tu granja)
		LockCooldown = 60, -- espera desde que acaba un bloqueo hasta poder bloquear otra vez
		ProtectWhileInMatch = true, -- mientras juegas un partido nadie puede robarte
		StealHoldSeconds = 1.5, -- mantener E/clic para coger un brainrot ajeno
		StealSeconds = 45, -- tiempo para llevarlo a tu granja (si no, vuelve a su dueno)
		ReturnRange = 6, -- si el dueno se acerca a esta distancia del ladron, lo recupera
		ThiefSpeed = 0.7, -- el ladron va mas lento (x0.7)
		NewPlayerShieldSeconds = 120, -- al entrar al servidor tu granja esta protegida este tiempo
	},
}

return Economy
