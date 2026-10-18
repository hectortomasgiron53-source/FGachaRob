--!strict
--[[
	Strings: todos los textos visibles. Espanol primero, ingles despues.
	Uso: Strings.t("goal")
]]
local tables: { [string]: { [string]: string } } = {
	es = {
		play_practice = "Jugar partido de práctica",
		team_blue = "AZUL",
		team_red = "ROJO",
		goal = "¡GOL!",
		go = "¡YA!",
		golden_goal = "GOL DE ORO",
		win = "¡VICTORIA!",
		lose = "DERROTA",
		draw = "EMPATE",
		busy = "Todos los campos están ocupados, prueba en unos segundos",
		btn_pass = "Pase",
		btn_shoot = "Tiro",
		btn_tackle = "Entrada",
		btn_slide = "Segada",
		btn_juke = "Croqueta",
		btn_flick = "Sombrero",
		btn_sprint = "Sprint",
		hint = "Con balón: E pase · F (mantén) tiro · R croqueta · T sombrero   |   Sin balón: Q entrada · C segada   |   Shift sprint · Click der. (mantén) girar cámara",
		stamina = "Resistencia",
	},
	en = {
		play_practice = "Play practice match",
		team_blue = "BLUE",
		team_red = "RED",
		goal = "GOAL!",
		go = "GO!",
		golden_goal = "GOLDEN GOAL",
		win = "VICTORY!",
		lose = "DEFEAT",
		draw = "DRAW",
		busy = "All fields are busy, try again in a few seconds",
		btn_pass = "Pass",
		btn_shoot = "Shoot",
		btn_tackle = "Tackle",
		btn_slide = "Slide",
		btn_juke = "Side step",
		btn_flick = "Flick",
		btn_sprint = "Sprint",
		hint = "With ball: E pass · F (hold) shoot · R side step · T flick   |   No ball: Q tackle · C slide   |   Shift sprint · Right-click (hold) rotate camera",
		stamina = "Stamina",
	},
}

local Strings = { Current = "es" }

function Strings.t(key: string): string
	local current = tables[Strings.Current] or tables.es
	return current[key] or tables.es[key] or key
end

return Strings
