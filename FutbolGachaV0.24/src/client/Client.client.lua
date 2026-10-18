--!strict
--[[
	Client: arranque del cliente. Carga los controladores en orden.
	Va en StarterPlayerScripts como LocalScript, junto a la carpeta Controllers.
]]
local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = { "MatchController", "BallVisual", "CameraController", "InputController", "UIController" }

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
