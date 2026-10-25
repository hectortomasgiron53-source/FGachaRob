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
	Stat: number, -- estadistica base en los partidos (1-100) a nivel 1 (ya jugable: el nivel la cambia poco)
	Height: number, -- altura del modelo (studs) en la granja (sin evolucionar)
	-- Subir de nivel (exponencial). Cuanto mas raro, mas caro, pero tambien rinde mas:
	LevelGrowth: number, -- monedas por segundo x esto en cada nivel (1.045 = +4,5 % por nivel, compuesto)
	LevelCost: number, -- coste de subir del nivel 1 al 2 = monedas por segundo base x esto...
	LevelCostGrowth: number, -- ...y cada nivel cuesta esto veces mas que el anterior
}

-- Evoluciones: al llegar a este nivel el brainrot cambia de forma (mas grande y con adornos nuevos, pero se le sigue
-- reconociendo) y da mas monedas. Los multiplicadores se acumulan (a nivel 90: x1,5 x2 = x3).
-- Modelos propios: si en ReplicatedStorage > BrainrotModels hay "<Id>_Evo1" o "<Id>_Evo2", se usan para esa
-- evolucion; si no, se usa el modelo normal con los adornos de la evolucion.
export type Evolution = {
	Level: number,
	Name: string,
	Tag: string, -- se muestra junto al nombre
	Scale: number, -- tamano del modelo (x)
	Income: number, -- monedas por segundo (x)
	Stat: number, -- puntos extra en todas las estadisticas (poco: el nivel casi no cambia el partido)
	LevelCostFactor: number, -- el nivel que evoluciona cuesta esto veces mas
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
	Disabled: boolean?, -- desactivado (Disabled abajo): no sale en las cajas ni en los rivales, pero quien ya lo tenga lo conserva
}

local Rarities: { Rarity } = {
	-- stylua: ignore start
	{ Id = "Comun", Name = "Común", Color = Color3.fromRGB(176, 182, 194), MinFame = 0, Income = 25, Stat = 58, Height = 4,
		LevelGrowth = 1.045, LevelCost = 15, LevelCostGrowth = 1.110 },
	{ Id = "Raro", Name = "Raro", Color = Color3.fromRGB(75, 140, 255), MinFame = 30, Income = 70, Stat = 62, Height = 4.4,
		LevelGrowth = 1.048, LevelCost = 16, LevelCostGrowth = 1.112 },
	{ Id = "Epico", Name = "Épico", Color = Color3.fromRGB(160, 80, 255), MinFame = 50, Income = 200, Stat = 66, Height = 4.8,
		LevelGrowth = 1.051, LevelCost = 17, LevelCostGrowth = 1.114 },
	{ Id = "Legendario", Name = "Legendario", Color = Color3.fromRGB(235, 75, 200), MinFame = 70, Income = 550, Stat = 70, Height = 5.3,
		LevelGrowth = 1.054, LevelCost = 18, LevelCostGrowth = 1.116 },
	{ Id = "Mitico", Name = "Mítico", Color = Color3.fromRGB(235, 60, 60), MinFame = 85, Income = 1500, Stat = 74, Height = 5.9,
		LevelGrowth = 1.057, LevelCost = 19, LevelCostGrowth = 1.118 },
	{ Id = "Secreto", Name = "Secreto", Color = Color3.fromRGB(255, 196, 40), MinFame = 95, Income = 4500, Stat = 78, Height = 6.6,
		LevelGrowth = 1.060, LevelCost = 20, LevelCostGrowth = 1.120 },
	-- stylua: ignore end
}

local Evolutions: { Evolution } = {
	{ Level = 50, Name = "Evolucionado", Tag = "★", Scale = 1.1, Income = 1.5, Stat = 2, LevelCostFactor = 5 },
	{ Level = 90, Name = "Ascendido", Tag = "★★", Scale = 1.2, Income = 2, Stat = 2, LevelCostFactor = 8 },
}

local Variants: { Variant } = {
	{ Id = "Normal", Name = "Normal", Income = 1, Stat = 0, Chance = 0.925, Color = Color3.fromRGB(235, 240, 250) },
	{ Id = "Oro", Name = "Oro", Income = 1.5, Stat = 2, Chance = 0.06, Color = Color3.fromRGB(255, 200, 60) },
	{ Id = "Diamante", Name = "Diamante", Income = 2.5, Stat = 4, Chance = 0.015, Color = Color3.fromRGB(110, 230, 255) },
}

-- Fama (0-100) segun lo conocido que es cada meme. Cambiala si quieres subir o bajar a alguno de calidad.
-- (V0.97: menos Secretos y Miticos; cada calidad bajo a sus menos famosos a la siguiente. Los comentarios de seccion de
-- abajo son orientativos: la calidad la decide la Fama.)
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
	{ Id = "bandito_bobritto", Name = "Bandito Bobritto", Fame = 28, Role = "Delantero", Rarity = "" },
	{ Id = "cacto_hipopotamo", Name = "Cacto Hipopotamo", Fame = 35, Role = "Portero", Rarity = "" },
	{ Id = "gangster_footera", Name = "Gangster Footera", Fame = 38, Role = "Delantero", Rarity = "" },
	{ Id = "ta_ta_ta_sahur", Name = "Ta Ta Ta Ta Sahur", Fame = 40, Role = "Defensa", Rarity = "" },
	{ Id = "tric_trac_baraboom", Name = "Tric Trac Baraboom", Fame = 42, Role = "Medio", Rarity = "" },
	{ Id = "trippi_troppi", Name = "Trippi Troppi", Fame = 46, Role = "Medio", Rarity = "" },
	{ Id = "dud_dud_gendut", Name = "Dud Dud Gendut", Fame = 27, Role = "Medio", Rarity = "" },
	{ Id = "bobrini_cocosini", Name = "Bobrini Cocosini", Fame = 29, Role = "Portero", Rarity = "" },
	{ Id = "leru_leru_le", Name = "Leru Leru Le", Fame = 29, Role = "Defensa", Rarity = "" },
	-- Lote 4 (V1.00)
	{ Id = "gatto_melonino", Name = "Gatto Melonino", Fame = 22, Role = "Medio", Rarity = "" },
	{ Id = "budi_dididun", Name = "Budi Dididun", Fame = 24, Role = "Defensa", Rarity = "" },
	{ Id = "brr_es_teh_patipum", Name = "Roncola Roncolini", Fame = 26, Role = "Delantero", Rarity = "" },
	{ Id = "skibidi_toilet", Name = "Skibidi Toilet", Fame = 41, Role = "Defensa", Rarity = "" },
	{ Id = "orcalero_orcala", Name = "Orcalero Orcala", Fame = 45, Role = "Delantero", Rarity = "" },
	-- Epicos
	{ Id = "perochello_lemonchello", Name = "Perochello Lemonchello", Fame = 45, Role = "Medio", Rarity = "" },
	{ Id = "bananita_dolphinita", Name = "Bananita Dolphinita", Fame = 46, Role = "Delantero", Rarity = "" },
	{ Id = "brri_brri_bicus", Name = "Brri Brri Bicus Dicus Bombicus", Fame = 47, Role = "Defensa", Rarity = "" },
	{ Id = "burbaloni_loliloli", Name = "Burbaloni Loliloli", Fame = 48, Role = "Portero", Rarity = "" },
	{ Id = "chef_crabracadabra", Name = "Chef Crabracadabra", Fame = 56, Role = "Defensa", Rarity = "" },
	{ Id = "boneca_ambalabu", Name = "Boneca Ambalabu", Fame = 49, Role = "Delantero", Rarity = "" },
	{ Id = "trulimero_trulicina", Name = "Trulimero Trulicina", Fame = 61, Role = "Medio", Rarity = "" },
	{ Id = "avocadorilla", Name = "Avocadorilla", Fame = 49, Role = "Defensa", Rarity = "" },
	{ Id = "raffalello_il_porcello", Name = "Raffalello Il Porcello", Fame = 29, Role = "Portero", Rarity = "" },
	{ Id = "piccione_scalzino", Name = "Piccione Scalzino", Fame = 49, Role = "Delantero", Rarity = "" },
	{ Id = "chococino_lavawalkini", Name = "Chococino Lavawalkini", Fame = 29, Role = "Medio", Rarity = "" },
	{ Id = "cappuccino_assassino", Name = "Cappuccino Assassino", Fame = 66, Role = "Delantero", Rarity = "" },
	-- Legendarios
	{ Id = "orangutini_ananassini", Name = "Orangutini Ananassini", Fame = 44, Role = "Defensa", Rarity = "" },
	{ Id = "glorbo_fruttodrillo", Name = "Glorbo Fruttodrillo", Fame = 49, Role = "Portero", Rarity = "" },
	{ Id = "frigo_camelo", Name = "Frigo Camelo", Fame = 65, Role = "Defensa", Rarity = "" },
	{ Id = "santteo", Name = "Santteo", Fame = 66, Role = "Medio", Rarity = "" },
	{ Id = "rinoceronte_boxerino", Name = "Rinoceronte Boxerino", Fame = 69, Role = "Defensa", Rarity = "" },
	{ Id = "doratino_brillantino", Name = "Neegy", Fame = 83, Role = "Portero", Rarity = "" },
	{ Id = "bombombini_gusini", Name = "Bombombini Gusini", Fame = 67, Role = "Delantero", Rarity = "" },
	{ Id = "udin_din_din_dun", Name = "Udin Din Din Dun", Fame = 69, Role = "Medio", Rarity = "" },
	{ Id = "lirili_larila", Name = "Lirilì Larilà", Fame = 78, Role = "Portero", Rarity = "" },
	{ Id = "karkerkar_kurkur", Name = "Karkerkar Kurkur", Fame = 68, Role = "Delantero", Rarity = "" },
	{ Id = "brr_brr_patapim", Name = "Brr Brr Patapim", Fame = 80, Role = "Defensa", Rarity = "" },
	{ Id = "chimpanzini_bananini", Name = "Chimpanzini Bananini", Fame = 82, Role = "Medio", Rarity = "" },
	-- Miticos
	{ Id = "cocofanto_elefanto", Name = "Cocofanto Elefanto", Fame = 80, Role = "Portero", Rarity = "" },
	{ Id = "la_vacca_saturno", Name = "La Vacca Saturno Saturnita", Fame = 81, Role = "Defensa", Rarity = "" },
	{ Id = "girafa_celestre", Name = "Girafa Celestre", Fame = 81, Role = "Medio", Rarity = "" },
	{ Id = "meowl", Name = "Meowl", Fame = 93, Role = "Medio", Rarity = "" },
	{ Id = "ketupat_kepat", Name = "Ketupat Kepat", Fame = 69, Role = "Defensa", Rarity = "" },
	{ Id = "swag_soda", Name = "Swag Soda", Fame = 83, Role = "Medio", Rarity = "" },
	{ Id = "to_to_to_sahur", Name = "To To To Sahur", Fame = 84, Role = "Delantero", Rarity = "" },
	{ Id = "alessio_pallonetto", Name = "Alessio Pallonetto", Fame = 84, Role = "Delantero", Rarity = "" },
	{ Id = "ballerina_cappuccina", Name = "Ballerina Cappuccina", Fame = 84, Role = "Medio", Rarity = "" },
	{ Id = "bombardiro_crocodilo", Name = "Bombardiro Crocodilo", Fame = 93, Role = "Delantero", Rarity = "" },
	-- Secretos
	{ Id = "celularcini_viciosini", Name = "Celularcini Viciosini", Fame = 94, Role = "Medio", Rarity = "" },
	{ Id = "sessantasette", Name = "67 Sessantasette", Fame = 94, Role = "Delantero", Rarity = "" },
	{ Id = "job_job_job_sahur", Name = "Job Job Job Sahur", Fame = 94, Role = "Defensa", Rarity = "" },
	{ Id = "chillin_chili", Name = "Chillin Chili", Fame = 97, Role = "Delantero", Rarity = "" },
	{ Id = "tung_tung_tung_sahur", Name = "Tung Tung Tung Sahur", Fame = 98, Role = "Defensa", Rarity = "" },
	{ Id = "tralalero_tralala", Name = "Tralalero Tralala", Fame = 99, Role = "Delantero", Rarity = "" },
	{ Id = "boss_finalissimo", Name = "Il Boss Finalissimo", Fame = 100, Role = "Defensa", Rarity = "" },
}

-- Giro (grados) de los modelos propios para que miren hacia la entrada de la granja.
-- OJO: el importador de Roblox ya les da media vuelta al importarlos (comprobado en Studio con
-- herramientas/diagnostico_giro.lua). Segun hacia donde miran en su archivo .glb: +Z = 0, -Z = 180, -X = 90, +X = 270.
-- Si alguno sale mal, sumale 180 (de espaldas) o prueba 90 / 270 (de lado). Panel Pruebas > "Revisar giros" ayuda.
local ModelYaw: { [string]: number } = {
	-- Miran hacia +Z en su archivo (el importador ya les da media vuelta): 0
	sessantasette = 0,
	avocadorilla = 0,
	karkerkar_kurkur = 0,
	raffalello_il_porcello = 0,
	ketupat_kepat = 0,
	to_to_to_sahur = 0,
	udin_din_din_dun = 0,
	-- Miran hacia -Z en su archivo: 180
	celularcini_viciosini = 180,
	santteo = 180,
	swag_soda = 180,
	-- De lado en su archivo
	bombardiro_crocodilo = 90, -- (mira hacia -X)
	boss_finalissimo = 270, -- (mira hacia +X)
	alessio_pallonetto = 270, -- (+X)
	ketupat_kepat_Evo2 = 270, -- (+X) evolucion de nivel 90 de Ketupat Kepat
	-- Lote 2 (miran hacia +Z): 0
	boneca_ambalabu = 0,
	frigo_camelo = 0,
	noobini_pizzanini = 0,
	bobrini_cocosini = 0,
	leru_leru_le = 0,
	piccione_scalzino = 0,
	chococino_lavawalkini = 0,
	rinoceronte_boxerino = 0,
	doratino_brillantino = 0,
	chillin_chili = 0,
	-- Lote 3
	job_job_job_sahur = 270, -- (+X)
	meowl = 0,
	glorbo_fruttodrillo = 0,
	tung_tung_tung_sahur = 0, -- (modelo "Sigma Tung Tung Sahur")
	-- Lote 4
	orcalero_orcala = 180, -- (-Z)
	orangutini_ananassini = 0,
	skibidi_toilet = 0,
	brr_es_teh_patipum = 0,
	ballerina_cappuccina = 0,
	budi_dididun = 0,
	gatto_melonino = 0,
	-- Lote 5
	trippi_troppi = 0,
	brr_brr_patapim = 0,
	tralalero_tralala = 0,
}

-- Modelos 3D prohibidos: aunque sigan en ReplicatedStorage > BrainrotModels, NO se usan nunca (se ve el modelo de
-- siempre, el generico). Para contenido que Roblox no permite (tabaco, etc.).
local BannedModels: { [string]: boolean } = {
	dud_dud_gendut = true, -- (fuma un cigarro)
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

-- Desactivados (V0.97; V1.02: el catalogo se queda en 38, todos con modelo 3D). No salen en las cajas ni en los equipos rivales, pero
-- V1.00: Orangutini Ananassini vuelve (ahora Raro, con modelo) y salen 6 sin modelo para dejar sitio al lote 4.
-- siguen existiendo (quien ya tenga alguno lo conserva). Para volver a activar uno (p. ej. al conseguir su modelo 3D),
-- quitalo de esta lista.
local Disabled: { [string]: boolean } = {
	-- Comunes
	raccooni_jandelini = true, fluriflura = true, bandito_bobritto = true,
	pipi_kiwi = true, svinina_bombardino = true, talpa_di_fero = true, -- (V1.00: su hueco es para los modelos del lote 4)
	tim_cheese = true, -- (V1.02: sin modelo; el catalogo se queda en 38, todos con modelo)
	dud_dud_gendut = true, -- (V1.11: su modelo fuma; Roblox lo avisa. Ver tambien BannedModels)
	-- Raros
	cacto_hipopotamo = true, perochello_lemonchello = true, brri_brri_bicus = true, burbaloni_loliloli = true,
	gangster_footera = true, ta_ta_ta_sahur = true, tric_trac_baraboom = true, -- (V1.00)
	bananita_dolphinita = true, -- (V1.02)
	-- Epicos
	chef_crabracadabra = true, trulimero_trulicina = true, cappuccino_assassino = true,
	bombombini_gusini = true,
	-- Legendarios
	lirili_larila = true, chimpanzini_bananini = true, cocofanto_elefanto = true, la_vacca_saturno = true,
	girafa_celestre = true,
}

local ById: { [string]: Entry } = {}
local ByRarity: { [string]: { Entry } } = {}
for _, rarity in Rarities do
	ByRarity[rarity.Id] = {}
end
for _, entry in List do
	entry.Rarity = rarityForFame(entry.Fame)
	assert(ById[entry.Id] == nil, "Brainrot repetido: " .. entry.Id)
	ById[entry.Id] = entry
	if Disabled[entry.Id] then
		entry.Disabled = true -- (sigue en ById: quien lo tenga lo conserva)
	else
		table.insert(ByRarity[entry.Rarity], entry)
	end
end

return {
	Rarities = Rarities,
	RarityById = RarityById,
	RarityIndex = RarityIndex,
	Variants = Variants,
	VariantById = VariantById,
	Evolutions = Evolutions,
	List = List,
	ById = ById,
	ByRarity = ByRarity,
	rarityForFame = rarityForFame,
	ModelYaw = ModelYaw,
	BannedModels = BannedModels,
	-- Suplente: rellena un hueco vacio del equipo en los partidos (no se puede tener ni robar)
	Substitute = { Id = "suplente", Name = "Suplente", Fame = 0, Role = "Medio", Rarity = "Comun" } :: Entry,
}
