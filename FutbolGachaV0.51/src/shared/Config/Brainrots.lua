--!strict
--[[
	Brainrots: catalogo de personajes coleccionables.
	- Calidad (rareza): sale de la FAMA (0-100). Cuanto mas famoso, mejor calidad: Comun < Raro < Epico < Legendario <
	  Mitico < Secreto (los colores siguen la escalera de las cajas de CS:GO).
	- Role: en que puesto rinde mejor (cambia el reparto de sus estadisticas). Se puede poner en cualquier puesto.
	- Variante: cada copia puede salir Normal, Oro o Diamante (mas dinero por segundo y algo mejores stats).

	Modelos: por defecto se usa un muneco generico de colores (BrainrotModel). Para usar un modelo de verdad, mete un
	Model en ReplicatedStorage > BrainrotModels con el MISMO nombre que el Id (por ejemplo "tralalero_tralala").
	Se escala solo y se le quitan los scripts.

	Para anadir un brainrot nuevo basta con anadir una linea a List (Id unico, sin espacios ni tildes).
]]

export type Rarity = {
	Id: string,
	Name: string,
	Color: Color3,
	MinFame: number, -- fama minima para tener esta calidad
	Income: number, -- monedas por segundo a nivel 1 (en la granja)
	Stat: number, -- estadistica base en los partidos (1-100) a nivel 1
	Height: number, -- altura del modelo (studs) en la granja
	-- Subir de nivel (exponencial). Cuanto mas raro, mas caro, pero tambien rinde mas:
	LevelGrowth: number, -- monedas por segundo x esto en cada nivel (1.10 = +10 % por nivel, compuesto)
	LevelCost: number, -- coste de subir del nivel 1 al 2 = monedas por segundo base x esto...
	LevelCostGrowth: number, -- ...y cada nivel cuesta esto veces mas que el anterior
}

export type Variant = {
	Id: string,
	Name: string,
	Income: number, -- multiplicador de monedas por segundo
	Stat: number, -- puntos extra en todas las estadisticas
	Chance: number, -- probabilidad al abrir una caja
	Color: Color3,
}

export type Entry = {
	Id: string,
	Name: string,
	Fame: number,
	Role: string, -- "Delantero" | "Medio" | "Defensa" | "Portero"
	Rarity: string, -- se rellena solo a partir de la fama
}

local Rarities: { Rarity } = {
	-- stylua: ignore start
	{ Id = "Comun", Name = "Común", Color = Color3.fromRGB(176, 182, 194), MinFame = 0, Income = 3, Stat = 42, Height = 4,
		LevelGrowth = 1.10, LevelCost = 40, LevelCostGrowth = 1.20 },
	{ Id = "Raro", Name = "Raro", Color = Color3.fromRGB(75, 140, 255), MinFame = 30, Income = 8, Stat = 50, Height = 4.4,
		LevelGrowth = 1.115, LevelCost = 44, LevelCostGrowth = 1.21 },
	{ Id = "Epico", Name = "Épico", Color = Color3.fromRGB(160, 80, 255), MinFame = 50, Income = 22, Stat = 58, Height = 4.8,
		LevelGrowth = 1.13, LevelCost = 48, LevelCostGrowth = 1.22 },
	{ Id = "Legendario", Name = "Legendario", Color = Color3.fromRGB(235, 75, 200), MinFame = 70, Income = 60, Stat = 66, Height = 5.3,
		LevelGrowth = 1.145, LevelCost = 52, LevelCostGrowth = 1.23 },
	{ Id = "Mitico", Name = "Mítico", Color = Color3.fromRGB(235, 60, 60), MinFame = 85, Income = 160, Stat = 74, Height = 5.9,
		LevelGrowth = 1.16, LevelCost = 56, LevelCostGrowth = 1.24 },
	{ Id = "Secreto", Name = "Secreto", Color = Color3.fromRGB(255, 196, 40), MinFame = 95, Income = 450, Stat = 82, Height = 6.6,
		LevelGrowth = 1.18, LevelCost = 60, LevelCostGrowth = 1.25 },
	-- stylua: ignore end
}

local Variants: { Variant } = {
	{ Id = "Normal", Name = "Normal", Income = 1, Stat = 0, Chance = 0.925, Color = Color3.fromRGB(235, 240, 250) },
	{ Id = "Oro", Name = "Oro", Income = 1.5, Stat = 3, Chance = 0.06, Color = Color3.fromRGB(255, 200, 60) },
	{ Id = "Diamante", Name = "Diamante", Income = 2.5, Stat = 6, Chance = 0.015, Color = Color3.fromRGB(110, 230, 255) },
}

-- Fama (0-100) segun lo conocido que es cada meme. Cambiala si quieres subir o bajar a alguno de calidad.
local List: { Entry } = {
	-- Comunes
	{ Id = "noobini_pizzanini", Name = "Noobini Pizzanini", Fame = 12, Role = "Medio", Rarity = "" },
	{ Id = "pipi_kiwi", Name = "Pipi Kiwi", Fame = 16, Role = "Delantero", Rarity = "" },
	{ Id = "svinina_bombardino", Name = "Svinina Bombardino", Fame = 19, Role = "Defensa", Rarity = "" },
	{ Id = "talpa_di_fero", Name = "Talpa di Fero", Fame = 21, Role = "Portero", Rarity = "" },
	{ Id = "raccooni_jandelini", Name = "Raccooni Jandelini", Fame = 23, Role = "Delantero", Rarity = "" },
	{ Id = "tim_cheese", Name = "Tim Cheese", Fame = 25, Role = "Medio", Rarity = "" },
	{ Id = "fluriflura", Name = "Fluriflura", Fame = 27, Role = "Defensa", Rarity = "" },
	-- Raros
	{ Id = "bandito_bobritto", Name = "Bandito Bobritto", Fame = 33, Role = "Delantero", Rarity = "" },
	{ Id = "cacto_hipopotamo", Name = "Cacto Hipopotamo", Fame = 35, Role = "Portero", Rarity = "" },
	{ Id = "gangster_footera", Name = "Gangster Footera", Fame = 38, Role = "Delantero", Rarity = "" },
	{ Id = "ta_ta_ta_sahur", Name = "Ta Ta Ta Ta Sahur", Fame = 40, Role = "Defensa", Rarity = "" },
	{ Id = "tric_trac_baraboom", Name = "Tric Trac Baraboom", Fame = 42, Role = "Medio", Rarity = "" },
	{ Id = "trippi_troppi", Name = "Trippi Troppi", Fame = 46, Role = "Medio", Rarity = "" },
	-- Epicos
	{ Id = "perochello_lemonchello", Name = "Perochello Lemonchello", Fame = 50, Role = "Medio", Rarity = "" },
	{ Id = "bananita_dolphinita", Name = "Bananita Dolphinita", Fame = 52, Role = "Delantero", Rarity = "" },
	{ Id = "brri_brri_bicus", Name = "Brri Brri Bicus Dicus Bombicus", Fame = 53, Role = "Defensa", Rarity = "" },
	{ Id = "burbaloni_loliloli", Name = "Burbaloni Loliloli", Fame = 54, Role = "Portero", Rarity = "" },
	{ Id = "chef_crabracadabra", Name = "Chef Crabracadabra", Fame = 56, Role = "Defensa", Rarity = "" },
	{ Id = "boneca_ambalabu", Name = "Boneca Ambalabu", Fame = 58, Role = "Delantero", Rarity = "" },
	{ Id = "trulimero_trulicina", Name = "Trulimero Trulicina", Fame = 61, Role = "Medio", Rarity = "" },
	{ Id = "cappuccino_assassino", Name = "Cappuccino Assassino", Fame = 66, Role = "Delantero", Rarity = "" },
	-- Legendarios
	{ Id = "orangutini_ananassini", Name = "Orangutini Ananassini", Fame = 70, Role = "Defensa", Rarity = "" },
	{ Id = "glorbo_fruttodrillo", Name = "Glorbo Fruttodrillo", Fame = 71, Role = "Portero", Rarity = "" },
	{ Id = "frigo_camelo", Name = "Frigo Camelo", Fame = 72, Role = "Defensa", Rarity = "" },
	{ Id = "bombombini_gusini", Name = "Bombombini Gusini", Fame = 74, Role = "Delantero", Rarity = "" },
	{ Id = "udin_din_din_dun", Name = "Udin Din Din Dun", Fame = 76, Role = "Medio", Rarity = "" },
	{ Id = "lirili_larila", Name = "Lirilì Larilà", Fame = 78, Role = "Portero", Rarity = "" },
	{ Id = "brr_brr_patapim", Name = "Brr Brr Patapim", Fame = 80, Role = "Defensa", Rarity = "" },
	{ Id = "chimpanzini_bananini", Name = "Chimpanzini Bananini", Fame = 82, Role = "Medio", Rarity = "" },
	-- Miticos
	{ Id = "cocofanto_elefanto", Name = "Cocofanto Elefanto", Fame = 85, Role = "Portero", Rarity = "" },
	{ Id = "la_vacca_saturno", Name = "La Vacca Saturno Saturnita", Fame = 86, Role = "Defensa", Rarity = "" },
	{ Id = "girafa_celestre", Name = "Girafa Celestre", Fame = 87, Role = "Medio", Rarity = "" },
	{ Id = "ballerina_cappuccina", Name = "Ballerina Cappuccina", Fame = 90, Role = "Medio", Rarity = "" },
	{ Id = "bombardiro_crocodilo", Name = "Bombardiro Crocodilo", Fame = 93, Role = "Delantero", Rarity = "" },
	-- Secretos
	{ Id = "tung_tung_tung_sahur", Name = "Tung Tung Tung Sahur", Fame = 98, Role = "Defensa", Rarity = "" },
	{ Id = "tralalero_tralala", Name = "Tralalero Tralala", Fame = 99, Role = "Delantero", Rarity = "" },
}

local RarityById: { [string]: Rarity } = {}
local RarityIndex: { [string]: number } = {}
for index, rarity in Rarities do
	RarityById[rarity.Id] = rarity
	RarityIndex[rarity.Id] = index
end

local VariantById: { [string]: Variant } = {}
for _, variant in Variants do
	VariantById[variant.Id] = variant
end

local function rarityForFame(fame: number): string
	local result = Rarities[1].Id
	for _, rarity in Rarities do
		if fame >= rarity.MinFame then
			result = rarity.Id
		end
	end
	return result
end

local ById: { [string]: Entry } = {}
local ByRarity: { [string]: { Entry } } = {}
for _, rarity in Rarities do
	ByRarity[rarity.Id] = {}
end
for _, entry in List do
	entry.Rarity = rarityForFame(entry.Fame)
	assert(ById[entry.Id] == nil, "Brainrot repetido: " .. entry.Id)
	ById[entry.Id] = entry
	table.insert(ByRarity[entry.Rarity], entry)
end

return {
	Rarities = Rarities,
	RarityById = RarityById,
	RarityIndex = RarityIndex,
	Variants = Variants,
	VariantById = VariantById,
	List = List,
	ById = ById,
	ByRarity = ByRarity,
	rarityForFame = rarityForFame,
	-- Suplente: rellena un hueco vacio del equipo en los partidos (no se puede tener ni robar)
	Substitute = { Id = "suplente", Name = "Suplente", Fame = 0, Role = "Medio", Rarity = "Comun" } :: Entry,
}
