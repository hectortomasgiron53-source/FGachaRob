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
	Controllable: boolean,
	IsGoalkeeper: boolean, -- solo portero: no sale de su linea de gol -- false = muneco quieto (hasta la Fase 3 con bots)
	Stats: Stats,
	Stamina: number,
	Exhausted: boolean,
	SprintWanted: boolean,
	LastSprintAt: number,
	StunnedUntil: number,
	ReleaseAt: number, -- hasta este instante no puede recoger el balon
	ImmuneUntil: number, -- hasta este instante no se le puede robar el balon (regates)
	ForcedMoveUntil: number, -- movimiento impuesto (segada, regate lateral): hasta cuando
	ForcedMoveDir: Vector3,
	ForcedMoveSpeed: number,
	SlideUntil: number, -- ventana en la que la segada puede tocar balon o rival
	SlideDir: Vector3,
	SlideResolved: boolean, -- la segada ya tuvo su contacto (solo cuenta una vez)
	TackleUntil: number, -- ventana del impulso de la entrada (Q): intenta robar en cada fotograma
	TackleResolved: boolean, -- la entrada ya tuvo su resultado
	RequestBallUntil: number, -- hasta cuando esta pidiendo el balon (E sin balon)
	NextActionAt: { [string]: number },
}

return {}
