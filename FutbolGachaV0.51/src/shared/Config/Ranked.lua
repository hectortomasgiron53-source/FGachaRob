--!strict
--[[
	Ranked: partidos ONLINE entre jugadores (RankedService en el servidor, RankedPanel en el cliente).
	- Cola: pulsas "JUGAR ONLINE" y el servidor junta a los que estan buscando en dos equipos de hasta 3 humanos
	  (el portero siempre es un bot). Los huecos se rellenan con bots que juegan con los brainrots del capitan.
	- Grupos: invita hasta 2 amigos del servidor y jugareis siempre en el mismo equipo.
	- Copas: sistema Elo. Ganar a rivales mejores da mas copas; perder contra peores quita mas. Abandonar un partido
	  cuenta como derrota. Las copas dan tu rango (Bronce ... Leyenda) y salen en la clasificacion mundial.
	- Igualdad: en online las estadisticas de los brainrots se acercan a la media de los 8 del partido
	  (StatEqualize): tu equipo sigue importando, pero gana quien juega mejor.
]]

export type Tier = { Id: string, Name: string, Emoji: string, Min: number, Color: Color3 }

local Tiers: { Tier } = {
	{ Id = "Bronce", Name = "Bronce", Emoji = "🥉", Min = 0, Color = Color3.fromRGB(205, 127, 70) },
	{ Id = "Plata", Name = "Plata", Emoji = "🥈", Min = 900, Color = Color3.fromRGB(200, 210, 225) },
	{ Id = "Oro", Name = "Oro", Emoji = "🥇", Min = 1100, Color = Color3.fromRGB(255, 200, 40) },
	{ Id = "Platino", Name = "Platino", Emoji = "💠", Min = 1300, Color = Color3.fromRGB(70, 215, 200) },
	{ Id = "Diamante", Name = "Diamante", Emoji = "💎", Min = 1500, Color = Color3.fromRGB(110, 170, 255) },
	{ Id = "Campeon", Name = "Campeón", Emoji = "👑", Min = 1750, Color = Color3.fromRGB(190, 110, 255) },
	{ Id = "Leyenda", Name = "Leyenda", Emoji = "🔥", Min = 2000, Color = Color3.fromRGB(255, 90, 60) },
}

local Ranked = {
	Enabled = true,

	-- Equipos
	MaxPerTeam = 3, -- humanos por equipo (el 4o puesto es el portero, siempre bot)
	PartyMax = 3, -- jugadores por grupo de amigos
	InviteSeconds = 30, -- lo que dura una invitacion

	-- Cola (el servidor la mira cada QueueTick segundos)
	QueueTick = 1,
	-- Cola GLOBAL: se empareja con gente de TODOS los servidores del juego (MemoryStore). Si los elegidos estan en el
	-- mismo servidor se juega alli; si no, viajan juntos a un servidor reservado para el partido y al acabar vuelven
	-- a su servidor. En Studio no se puede viajar: alli la cola es la del servidor.
	Global = true,
	GlobalTick = 2, -- cada cuanto se habla con la cola global (segundos)
	MatchServerWait = 40, -- el servidor del partido espera esto como mucho a que lleguen todos
	FillSeconds = 12, -- desde que ya se puede jugar, espera esto a que entren mas (empieza antes si hay 6)
	UnevenAfter = 25, -- tras esperar esto, se permite un equipo con un humano mas (el otro lleva un bot mas)
	VeryUnevenAfter = 50, -- ...y tras esto, hasta dos de diferencia (p. ej. un grupo de 3 contra uno solo con 2 bots)
	RatingGapBase = 250, -- diferencia maxima de copas medias entre equipos al empezar a buscar...
	RatingGapPerSecond = 20, -- ...que crece con la espera (en un servidor con poca gente acaba jugando cualquiera)
	MaxGroupsConsidered = 8, -- grupos de la cola que se combinan a la vez (los mas antiguos)

	-- Igualdad de estadisticas (0 = cada uno con las suyas, 1 = todos iguales)
	StatEqualize = 0.5,

	-- Copas (Elo)
	StartRating = 1000,
	KFactor = 30,
	PlacementK = 48, -- primeros partidos: se sube y se baja mas rapido hasta tu sitio
	PlacementMatches = 5,
	MinGain = 8, -- al ganar, como minimo
	MinLoss = 5, -- al perder, como minimo
	StreakBonus = 2, -- copas extra por victoria seguida (a partir de la 2a)...
	StreakBonusMax = 10, -- ...con tope
	LeavePenaltyExtra = 5, -- abandonar: derrota y esto de mas

	-- Recompensas (sobre las de un partido de practica, Economy.Match)
	RewardFactor = 1.5, -- monedas y XP
	GemFactor = 1.25,
	MvpGems = 50, -- al mejor jugador del partido (mas goles; solo humanos)
	MinDurationForBonus = 60, -- segundos jugados: si el rival abandona antes, recompensa normal de practica

	-- Clasificacion mundial (OrderedDataStore)
	LeaderboardStore = "FG_Copas_v1",
	LeaderboardSize = 10,
	LeaderboardRefresh = 90,

	Tiers = Tiers,
}

-- Rango de unas copas: tier, division (3, 2, 1; 0 en Leyenda), progreso dentro de la division (0..1) y texto
function Ranked.tierOf(rating: number): (Tier, number, number, string)
	local index = 1
	for i, tier in Tiers do
		if rating >= tier.Min then
			index = i
		end
	end
	local tier = Tiers[index]
	local nextTier = Tiers[index + 1]
	if not nextTier then
		return tier, 0, 1, `{tier.Emoji} {tier.Name}`
	end
	local span = (nextTier.Min - tier.Min) / 3
	local step = math.clamp(math.floor((rating - tier.Min) / span), 0, 2)
	local division = 3 - step
	local progress = math.clamp((rating - tier.Min - step * span) / span, 0, 1)
	local roman = ({ "I", "II", "III" })[division]
	return tier, division, progress, `{tier.Emoji} {tier.Name} {roman}`
end

-- Texto corto del rango ("🥇 Oro II")
function Ranked.label(rating: number): string
	local _, _, _, text = Ranked.tierOf(rating)
	return text
end

return Ranked
