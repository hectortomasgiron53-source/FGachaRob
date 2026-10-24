--!strict
--[[
	EconomyMath: formulas puras de la economia (sin servicios de Roblox): las usan el servidor (que decide) y el
	cliente (que solo muestra). Se pueden probar fuera de Roblox.
]]
local ReplicatedStorage = game and game:GetService("ReplicatedStorage")
local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots) :: any
local Economy = require(ReplicatedStorage.Shared.Config.Economy) :: any

local EconomyMath = {}

export type Record = { Id: string, Level: number, Variant: string }

-- Numero pseudoaleatorio estable a partir de un texto (0..1): misma entrada, mismo resultado
function EconomyMath.hash01(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = (h * 16777619) % 4294967296
	end
	return (h % 100000) / 100000
end

function EconomyMath.entryOf(id: string): any
	return Brainrots.ById[id] or Brainrots.Substitute
end

function EconomyMath.rarityOf(id: string): any
	local entry = EconomyMath.entryOf(id)
	return Brainrots.RarityById[entry.Rarity] or Brainrots.Rarities[1]
end

function EconomyMath.variantOf(variant: string?): any
	return Brainrots.VariantById[variant or "Normal"] or Brainrots.Variants[1]
end

-- ---------------------------------------------------------------------------
-- Evoluciones (nivel 50 y 90, ver Brainrots.Evolutions)
-- ---------------------------------------------------------------------------

-- Evolucion que tiene un brainrot a ese nivel: 0 = ninguna, 1 = primera, 2 = segunda...
function EconomyMath.evolutionOf(level: number): number
	local stage = 0
	for index, evolution in Brainrots.Evolutions do
		if level >= evolution.Level then
			stage = index
		end
	end
	return stage
end

-- Datos de la evolucion (nil si no ha evolucionado)
function EconomyMath.evolution(level: number): any
	local stage = EconomyMath.evolutionOf(level)
	return if stage > 0 then Brainrots.Evolutions[stage] else nil
end

-- Siguiente evolucion que le falta (nil si ya tiene todas)
function EconomyMath.nextEvolution(level: number): any
	for _, evolution in Brainrots.Evolutions do
		if level < evolution.Level then
			return evolution
		end
	end
	return nil
end

-- Multiplicador de monedas por las evoluciones (se acumulan)
local function evolutionIncome(level: number): number
	local factor = 1
	for _, evolution in Brainrots.Evolutions do
		if level >= evolution.Level then
			factor *= evolution.Income
		end
	end
	return factor
end

-- Tamano del modelo por la evolucion (1 = normal)
function EconomyMath.evolutionScale(level: number): number
	local evolution = EconomyMath.evolution(level)
	return if evolution then evolution.Scale else 1
end

-- Texto corto de la evolucion ("", "★", "★★")
function EconomyMath.evolutionTag(level: number): string
	local evolution = EconomyMath.evolution(level)
	return if evolution then evolution.Tag else ""
end

-- ---------------------------------------------------------------------------
-- Monedas y niveles
-- ---------------------------------------------------------------------------

-- Monedas por segundo de un brainrot colocado en la granja
function EconomyMath.income(record: Record): number
	local rarity = EconomyMath.rarityOf(record.Id)
	local variant = EconomyMath.variantOf(record.Variant)
	local level = math.max(1, record.Level)
	return rarity.Income * rarity.LevelGrowth ^ (level - 1) * variant.Income * evolutionIncome(level)
end

-- Coste de pasar de "level" a "level + 1" (sin mirar el nivel maximo)
local function costAt(rarity: any, level: number): number
	local cost = rarity.Income * rarity.LevelCost * rarity.LevelCostGrowth ^ (level - 1)
	for _, evolution in Brainrots.Evolutions do
		if level + 1 == evolution.Level then
			cost *= evolution.LevelCostFactor -- el nivel que evoluciona cuesta mas
		end
	end
	return math.floor(cost + 0.5)
end

-- Coste en monedas de subirlo un nivel (nil si ya esta al maximo)
function EconomyMath.levelCost(record: Record): number?
	if record.Level >= Economy.Brainrot.MaxLevel then
		return nil
	end
	return costAt(EconomyMath.rarityOf(record.Id), math.max(1, record.Level))
end

-- Coste de subir hasta "count" niveles (sin pasar del maximo). Devuelve (coste total, niveles que se suben).
function EconomyMath.levelCostMany(record: Record, count: number): (number, number)
	local rarity = EconomyMath.rarityOf(record.Id)
	local level = math.max(1, record.Level)
	local total, levels = 0, 0
	while levels < count and level + levels < Economy.Brainrot.MaxLevel do
		total += costAt(rarity, level + levels)
		levels += 1
	end
	return total, levels
end

-- Monedas gastadas en total para llevarlo del nivel 1 a su nivel actual
function EconomyMath.invested(record: Record): number
	local rarity = EconomyMath.rarityOf(record.Id)
	local total = 0
	for level = 1, math.max(1, record.Level) - 1 do
		total += costAt(rarity, level)
	end
	return total
end

-- Monedas que te dan al venderlo
function EconomyMath.sellValue(record: Record): number
	local rarity = EconomyMath.rarityOf(record.Id)
	local variant = EconomyMath.variantOf(record.Variant)
	local B = Economy.Brainrot
	return math.floor(rarity.Income * B.SellFactor * variant.Income + EconomyMath.invested(record) * B.SellRefund + 0.5)
end

-- Reparto de estadisticas segun su puesto ideal
local PROFILES: { [string]: { [string]: number } } = {
	Delantero = { Speed = 6, Shooting = 12, Passing = 0, Dribbling = 8, Defense = -15, Stamina = 0, Goalkeeping = -30 },
	Medio = { Speed = 2, Shooting = -2, Passing = 12, Dribbling = 4, Defense = 0, Stamina = 10, Goalkeeping = -30 },
	Defensa = { Speed = 0, Shooting = -12, Passing = 2, Dribbling = -8, Defense = 15, Stamina = 5, Goalkeeping = -30 },
	Portero = { Speed = -6, Shooting = -20, Passing = 0, Dribbling = -20, Defense = 5, Stamina = 0, Goalkeeping = 18 },
}
EconomyMath.StatNames = { "Speed", "Shooting", "Passing", "Dribbling", "Defense", "Stamina", "Goalkeeping" }

-- Estadisticas de partido (1-100): calidad + variante + puesto ideal + un pequeno toque propio de cada uno. El nivel
-- y las evoluciones suman muy poco (el partido es jugable desde el nivel 1; subir de nivel es sobre todo dinero).
function EconomyMath.stats(record: Record): { [string]: number }
	local entry = EconomyMath.entryOf(record.Id)
	local rarity = EconomyMath.rarityOf(record.Id)
	local variant = EconomyMath.variantOf(record.Variant)
	local level = math.max(1, record.Level)
	local base = rarity.Stat + Economy.Brainrot.StatPerLevel * (level - 1) + variant.Stat
	for _, evolution in Brainrots.Evolutions do
		if level >= evolution.Level then
			base += evolution.Stat
		end
	end
	local profile = PROFILES[entry.Role] or PROFILES.Medio
	local stats: { [string]: number } = {}
	for _, name in EconomyMath.StatNames do
		local jitter = (EconomyMath.hash01(entry.Id .. name) - 0.5) * 8
		stats[name] = math.clamp(math.floor(base + (profile[name] or 0) + jitter + 0.5), 1, 100)
	end
	return stats
end

-- Valoracion general (para mostrar): media de las 6 estadisticas de campo, o la de portero si es portero
function EconomyMath.overall(record: Record): number
	local stats = EconomyMath.stats(record)
	local entry = EconomyMath.entryOf(record.Id)
	if entry.Role == "Portero" then
		return math.floor((stats.Goalkeeping * 2 + stats.Defense + stats.Passing) / 4 + 0.5)
	end
	local sum = 0
	for _, name in { "Speed", "Shooting", "Passing", "Dribbling", "Defense", "Stamina" } do
		sum += stats[name]
	end
	return math.floor(sum / 6 + 0.5)
end

-- XP necesaria para pasar de "level" a "level + 1"
function EconomyMath.xpForLevel(level: number): number
	local P = Economy.PlayerLevel
	return P.XPBase + P.XPPerLevel * (level - 1)
end

-- Recompensa al LLEGAR al nivel "level"
function EconomyMath.levelReward(level: number): (number, number)
	local P = Economy.PlayerLevel
	local gems = math.min(P.RewardGemsBase + P.RewardGemsPerLevel * level, P.RewardGemsMax)
	return P.RewardCoinsPerLevel * level, gems
end

-- Suma XP: devuelve el nivel y la XP nuevos y la lista de niveles alcanzados
function EconomyMath.addXP(level: number, xp: number, gained: number): (number, number, { number })
	local reached = {}
	xp += gained
	while xp >= EconomyMath.xpForLevel(level) do
		xp -= EconomyMath.xpForLevel(level)
		level += 1
		table.insert(reached, level)
	end
	return level, xp, reached
end

-- Numero de dia (cambia a la hora DailyResetHourUTC)
function EconomyMath.dayIndex(unixTime: number): number
	return math.floor((unixTime - Economy.DailyResetHourUTC * 3600) / 86400)
end

-- Precio en monedas de un canje de gemas segun el nivel de cuenta: Coins (el minimo, en el nivel 1) x ExchangeLevelGrowth
-- por cada nivel
function EconomyMath.exchangeMultiplier(level: number): number
	return (Economy.ExchangeLevelGrowth or 1.1) ^ (math.max(1, level) - 1)
end

function EconomyMath.exchangeCost(offer: any, level: number): number
	return math.floor(offer.Coins * EconomyMath.exchangeMultiplier(level))
end

-- Recompensa de partido: "outcome" = "Win" | "Draw" | "Loss"
function EconomyMath.matchReward(outcome: string, goals: number): (number, number, number)
	local base = Economy.Match[outcome] or Economy.Match.Loss
	local per = Economy.Match.PerGoal
	goals = math.max(0, goals)
	return base.Coins + per.Coins * goals, base.Gems + per.Gems * goals, base.XP + per.XP * goals
end

function EconomyMath.caseById(id: string): any
	for _, case in Economy.Cases do
		if case.Id == id then
			return case
		end
	end
	return nil
end

-- Tirada: calidad segun las probabilidades de la caja. "r" = numero aleatorio 0..1
function EconomyMath.rollRarity(case: any, r: number): string
	local total = 0
	for _, rarity in Brainrots.Rarities do
		total += case.Odds[rarity.Id] or 0
	end
	local pick = r * total
	local last = Brainrots.Rarities[1].Id
	for _, rarity in Brainrots.Rarities do
		local odds = case.Odds[rarity.Id] or 0
		if odds > 0 then
			last = rarity.Id
			if pick < odds then
				return rarity.Id
			end
			pick -= odds
		end
	end
	return last
end

-- Un brainrot al azar de esa calidad (si no hubiera ninguno, baja de calidad)
function EconomyMath.pickOfRarity(rarityId: string, r: number): any
	local index = Brainrots.RarityIndex[rarityId] or 1
	while index >= 1 do
		local list = Brainrots.ByRarity[Brainrots.Rarities[index].Id]
		if list and #list > 0 then
			return list[math.clamp(math.floor(r * #list) + 1, 1, #list)]
		end
		index -= 1
	end
	return Brainrots.List[1]
end

function EconomyMath.rollVariant(r: number): string
	local acc = 0
	for i = #Brainrots.Variants, 2, -1 do -- de la mas rara a la menos
		local variant = Brainrots.Variants[i]
		acc += variant.Chance
		if r < acc then
			return variant.Id
		end
	end
	return "Normal"
end

-- 1234 -> "1.2K", 3400000 -> "3.4M"
function EconomyMath.format(n: number): string
	n = math.floor(n)
	local abs = math.abs(n)
	local suffixes: { { any } } = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, s in suffixes do
		if abs >= s[1] then
			local value = n / (s[1] :: number)
			local text = if math.abs(value) >= 100 then string.format("%d", math.floor(value)) else string.format("%.1f", value)
			text = string.gsub(text, "%.0$", "")
			return text .. s[2]
		end
	end
	return tostring(n)
end

return EconomyMath
