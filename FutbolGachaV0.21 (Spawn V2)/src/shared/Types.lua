--!strict
--[[
	Types: tipos de Luau compartidos entre servidor y cliente.
]]

export type Stats = {
	Speed: number,
	Shooting: number,
	Passing: number,
	Dribbling: number,
	Defense: number,
	Stamina: number,
	Goalkeeping: number,
}

export type Character = {
	Id: string,
	Name: string,
	Role: string,
	Rarity: string,
	Stats: Stats,
}

-- Base del perfil del jugador. DataService (Fase 6) lo ampliara.
export type Profile = {
	Coins: number,
	Points: number,
	Pulls: number,
	Owned: { [string]: number }, -- id de personaje -> numero de copias
	Team: { string },
	Captain: string,
}

export type Scorer = {
	Team: number,
	Name: string,
	Time: number,
}

-- Winner: 1 o 2 = equipo ganador, 0 = empate
export type MatchResult = {
	Winner: number,
	Score: { number },
	Scorers: { Scorer },
	Duration: number,
	Mode: string,
}

-- Un "actor" es cualquier personaje dentro de un partido (humano, bot o muneco).
export type Actor = {
	Name: string,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Team: number,
	Slot: number,
	Player: Player?,
	Controllable: boolean, -- false = muneco quieto (hasta la Fase 3 con bots)
	Stats: Stats,
	Stamina: number,
	Exhausted: boolean,
	SprintWanted: boolean,
	LastSprintAt: number,
	StunnedUntil: number,
	ReleaseAt: number, -- hasta este instante no puede recoger el balon
	NextActionAt: { [string]: number },
}

return {}
