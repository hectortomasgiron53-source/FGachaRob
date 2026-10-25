--!strict
--[[
	Offers: las ofertas especiales de Robux (Economy.Offers) en el cliente. Las usan la tienda (Destacado), el Garaje
	y el aviso que sale a los jugadores nuevos.
	- Starter: pack de bienvenida, solo los primeros dias desde que entras y una vez por jugador.
	- LaunchVehicle: el vehiculo de lanzamiento, una vez por jugador.
	El precio en Robux se pide a Roblox (asi, si lo cambias en la web, aqui sale el nuevo).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local ClientData = require(script.Parent.ClientData)
local UiKit = require(script.Parent.UiKit)

local Offers = {}

local prices: { [number]: number } = {}
local asked: { [number]: boolean } = {}
local priceCallbacks: { () -> () } = {}

local function offer(name: string): any
	return (Economy.Offers :: any)[name]
end

function Offers.productOf(name: string): number
	local o = offer(name)
	return if o then tonumber(o.ProductId) or 0 else 0
end

-- Paises donde Roblox no deja vender "objetos aleatorios de pago" (PolicyService.ArePaidRandomItemsRestricted; lo
-- consulta el servidor en EconomyService): ahi no se venden gemas con Robux (las cajas se abren solo con gemas
-- ganadas jugando). Mientras no llega la respuesta se trata como restringido.
function Offers.paidRandomRestricted(): boolean
	return Players.LocalPlayer:GetAttribute("PaidRandomRestricted") ~= false
end

-- Segundos que le quedan al pack de bienvenida (0 = ya no esta; trae gemas, asi que no sale si esta restringido)
function Offers.starterSecondsLeft(): number
	local data = ClientData.get()
	if not data or Offers.productOf("Starter") == 0 or Offers.paidRandomRestricted() then
		return 0
	end
	if data.Offers and data.Offers.Starter then
		return 0 -- ya comprado
	end
	local untilTime = tonumber(data.StarterUntil) or 0
	return math.max(0, untilTime - Workspace:GetServerTimeNow())
end

function Offers.starterAvailable(): boolean
	return Offers.starterSecondsLeft() > 0
end

function Offers.launchAvailable(): boolean
	local data = ClientData.get()
	local o = offer("LaunchVehicle")
	if not data or not o or Offers.productOf("LaunchVehicle") == 0 then
		return false
	end
	return not (data.Vehicles and data.Vehicles[o.Vehicle])
end

-- Precio en Robux (o "fallback" mientras llega de Roblox)
function Offers.price(productId: number, fallback: number?): number?
	if productId == 0 then
		return fallback
	end
	if prices[productId] then
		return prices[productId]
	end
	if not asked[productId] then
		asked[productId] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				prices[productId] = info.PriceInRobux
				for _, callback in priceCallbacks do
					task.spawn(callback)
				end
			end
		end)
	end
	return fallback
end

-- Precio de oferta con el "precio real" tachado al lado (texto enriquecido: RichText = true en la etiqueta)
-- Ej.: "<s>R$ 149</s> R$ 19"
function Offers.priceRich(name: string, fallback: number): string
	local o = offer(name)
	local now = Offers.price(Offers.productOf(name), fallback) or fallback
	local real = if o then tonumber(o.RealPrice) else nil
	if real and real > now then
		return `<font color="#FFB3B3"><s>R$ {real}</s></font>  R$ {now}`
	end
	return `R$ {now}`
end

-- Descuento en % respecto al precio real (0 si no tiene)
function Offers.discount(name: string, fallback: number): number
	local o = offer(name)
	local now = Offers.price(Offers.productOf(name), fallback) or fallback
	local real = if o then tonumber(o.RealPrice) else nil
	if not real or real <= now then
		return 0
	end
	return math.floor((1 - now / real) * 100 + 0.5)
end

function Offers.onPrice(callback: () -> ())
	table.insert(priceCallbacks, callback)
end

-- (y al llegar el traductor del jugador: los botones con precio tachado se traducen a mano, ver UiKit.tr)
UiKit.onTranslated(function()
	for _, callback in priceCallbacks do
		task.spawn(callback)
	end
end)

-- (al llegar la respuesta de PolicyService se rehacen las ofertas y la tienda, como al llegar un precio)
Players.LocalPlayer:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(function()
	for _, callback in priceCallbacks do
		task.spawn(callback)
	end
end)

function Offers.buy(name: string)
	local productId = Offers.productOf(name)
	if productId ~= 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	end
end

-- "2d 13h", "5h 20m", "12m 30s"
function Offers.formatLeft(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local days, hours = seconds // 86400, (seconds % 86400) // 3600
	local minutes, secs = (seconds % 3600) // 60, seconds % 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m {secs}s`
end

return Offers
