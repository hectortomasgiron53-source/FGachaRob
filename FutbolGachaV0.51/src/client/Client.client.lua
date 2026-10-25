--!strict
--[[
	Client: arranque del cliente. Carga los controladores en orden.
	Va en StarterPlayerScripts como LocalScript, junto a la carpeta Controllers.
]]
local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"MatchController",
	"BallVisual",
	"BallAura", -- contorno blanco en quien lleva el balon (y en el balon)
	"CameraController",
	"InputController",
	"UIController",
	"FxController",
	"SettingsController",
	"CoinTossController", -- sorteo de saque con moneda antes de cada partido
	"EconomyController", -- monedas, gemas, brainrots, cajas, tienda y diario
	"FarmController", -- granjas y robos (avisos, animaciones)
	"LobbyController", -- animaciones decorativas del lobby (balon, portal)
	"AdminPanel", -- panel de administrador (solo el creador del juego; permisos en AdminService)
	"DebugPanel", -- panel de pruebas (solo en Studio)
}

for _, name in ORDER do
	local moduleScript = Controllers:WaitForChild(name)
	local ok, result = pcall(function()
		local controller = require(moduleScript :: ModuleScript) :: any
		controller.start()
	end)
	if not ok then
		warn(`[Client] Error al cargar {name}: {result}`)
	end
end
