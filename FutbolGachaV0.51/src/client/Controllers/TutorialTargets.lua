--!strict
--[[
	TutorialTargets: las piezas de la interfaz que el tutorial señala (cada controlador apunta aqui las suyas por
	nombre). Va aparte del tutorial para que cualquier panel pueda apuntar sus piezas sin depender de el.
]]
local TutorialTargets = {}

local targets: { [string]: GuiObject } = {}

function TutorialTargets.set(name: string, gui: GuiObject)
	targets[name] = gui
end

function TutorialTargets.get(name: string): GuiObject?
	local gui = targets[name]
	if gui and gui.Parent then
		return gui
	end
	return nil
end

return TutorialTargets
