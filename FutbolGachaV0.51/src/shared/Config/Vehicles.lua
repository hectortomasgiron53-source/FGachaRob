--!strict
--[[
	Vehicles: los vehiculos para moverte por el mapa (fuera de los partidos). Se compran en el Garaje.
	- Cada 25 niveles de tu CUENTA se desbloquea un escalon nuevo (nivel 1, 25, 50, 75 y 100).
	- En cada escalon hay dos: uno con MONEDAS y otro con GEMAS. El de gemas es algo mejor (un poco mas rapido, salta
	  algo mas y deja estela), pero NUNCA mejor que el de monedas del escalon siguiente: subir de nivel siempre compensa.
	  Cuesta muchas gemas: las gemas salen de los partidos, del diario y de la tienda (Robux).
	- Montar / bajar: tecla V o el boton "Montar" de la pantalla. Al empezar un partido o al robar un brainrot te bajas.
	Speed: velocidad andando (lo normal son 16). Jump: fuerza de salto (lo normal son 50).
	Kind: forma del modelo (VehicleModel.lua). Lift: cuanto te eleva (studs) para ir de pie encima.
]]

export type Vehicle = {
	Id: string,
	Name: string,
	Emoji: string,
	Level: number, -- nivel de cuenta necesario
	Currency: string, -- "Coins" | "Gems" | "Robux" (oferta especial: su producto esta en Economy.Offers)
	Price: number,
	Speed: number,
	Jump: number,
	Kind: string,
	Lift: number,
	Color: Color3,
	Accent: Color3,
	Trail: boolean, -- deja estela de luz (los de gemas)
	Description: string,
}

local List: { Vehicle } = {
	-- stylua: ignore start
	-- Oferta de LANZAMIENTO (Robux, se ve arriba del Garaje y en la tienda): para cualquier nivel, como un hoverboard
	-- de nivel 50. Su ProductId esta en Economy.Offers.LaunchVehicle.
	{ Id = "launchbolt", Name = "Rayo de Lanzamiento", Emoji = "⚡", Level = 1, Currency = "Robux", Price = 49, Speed = 31, Jump = 60,
		Kind = "Hover", Lift = 1.9, Color = Color3.fromRGB(255, 205, 40), Accent = Color3.fromRGB(60, 230, 255), Trail = true,
		Description = "Edición limitada de lanzamiento. Rápido desde el nivel 1 y con estela." },
	-- Nivel 1
	{ Id = "skate", Name = "Monopatín", Emoji = "🛹", Level = 1, Currency = "Coins", Price = 25000, Speed = 22, Jump = 50,
		Kind = "Skate", Lift = 0.5, Color = Color3.fromRGB(230, 120, 50), Accent = Color3.fromRGB(40, 40, 46), Trail = false,
		Description = "Clásico y ágil. Para empezar a moverte rápido." },
	{ Id = "escooter", Name = "Patinete Eléctrico", Emoji = "🛴", Level = 1, Currency = "Gems", Price = 2500, Speed = 24, Jump = 53,
		Kind = "Scooter", Lift = 0.5, Color = Color3.fromRGB(60, 200, 255), Accent = Color3.fromRGB(30, 30, 40), Trail = true,
		Description = "Algo más rápido que el monopatín, salta más y deja estela." },
	-- Nivel 25
	{ Id = "bike", Name = "Bicicleta", Emoji = "🚲", Level = 25, Currency = "Coins", Price = 1000000, Speed = 26, Jump = 54,
		Kind = "Bike", Lift = 1.4, Color = Color3.fromRGB(220, 50, 60), Accent = Color3.fromRGB(35, 35, 40), Trail = false,
		Description = "Dos ruedas y buen ritmo." },
	{ Id = "turbobike", Name = "Bici Turbo", Emoji = "🚴", Level = 25, Currency = "Gems", Price = 6000, Speed = 28, Jump = 57,
		Kind = "Bike", Lift = 1.4, Color = Color3.fromRGB(255, 200, 40), Accent = Color3.fromRGB(255, 90, 200), Trail = true,
		Description = "Bici eléctrica con luces de neón. Vuela por los caminos." },
	-- Nivel 50
	{ Id = "hoverboard", Name = "Hoverboard", Emoji = "🛸", Level = 50, Currency = "Coins", Price = 25000000, Speed = 30, Jump = 58,
		Kind = "Hover", Lift = 1.8, Color = Color3.fromRGB(150, 160, 180), Accent = Color3.fromRGB(80, 220, 255), Trail = false,
		Description = "Flota sobre el suelo. ¡El futuro!" },
	{ Id = "neonhover", Name = "Hoverboard Neón", Emoji = "✨", Level = 50, Currency = "Gems", Price = 15000, Speed = 32, Jump = 61,
		Kind = "Hover", Lift = 2, Color = Color3.fromRGB(150, 80, 255), Accent = Color3.fromRGB(255, 80, 220), Trail = true,
		Description = "Hoverboard de competición con estela de luz." },
	-- Nivel 75
	{ Id = "moto", Name = "Moto", Emoji = "🏍️", Level = 75, Currency = "Coins", Price = 500000000, Speed = 34, Jump = 62,
		Kind = "Moto", Lift = 1.8, Color = Color3.fromRGB(40, 120, 230), Accent = Color3.fromRGB(30, 30, 36), Trail = false,
		Description = "Potencia pura sobre dos ruedas." },
	{ Id = "skymoto", Name = "Moto Voladora", Emoji = "🚀", Level = 75, Currency = "Gems", Price = 35000, Speed = 36, Jump = 65,
		Kind = "Moto", Lift = 2.6, Color = Color3.fromRGB(30, 30, 36), Accent = Color3.fromRGB(80, 255, 160), Trail = true,
		Description = "Sin ruedas: flota y deja una estela verde." },
	-- Nivel 100
	{ Id = "carpet", Name = "Alfombra Mágica", Emoji = "🧞", Level = 100, Currency = "Coins", Price = 10000000000, Speed = 38, Jump = 66,
		Kind = "Carpet", Lift = 1.6, Color = Color3.fromRGB(200, 40, 60), Accent = Color3.fromRGB(255, 200, 60), Trail = false,
		Description = "Una leyenda de los cuentos." },
	{ Id = "rocketboard", Name = "Tabla Cohete", Emoji = "🔥", Level = 100, Currency = "Gems", Price = 80000, Speed = 41, Jump = 70,
		Kind = "Rocket", Lift = 2.2, Color = Color3.fromRGB(240, 240, 250), Accent = Color3.fromRGB(255, 120, 30), Trail = true,
		Description = "El vehículo más rápido del juego. Propulsión a fuego." },
	-- stylua: ignore end
}

local ById: { [string]: Vehicle } = {}
for _, vehicle in List do
	assert(ById[vehicle.Id] == nil, "Vehiculo repetido: " .. vehicle.Id)
	ById[vehicle.Id] = vehicle
end

-- Escalones (niveles en los que se desbloquean vehiculos nuevos), en orden
local Tiers: { number } = {}
for _, vehicle in List do
	if vehicle.Currency ~= "Robux" and not table.find(Tiers, vehicle.Level) then
		table.insert(Tiers, vehicle.Level)
	end
end
table.sort(Tiers)

return {
	List = List,
	ById = ById,
	Tiers = Tiers,
	RideKey = Enum.KeyCode.V, -- tecla para montar / bajar
}
