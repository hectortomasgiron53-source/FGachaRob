--!strict
--[[
	CollisionSetup: grupos de colision.
	- "MatchBall": el balon. Choca con el campo, pero NO con los jugadores (asi nadie se sube al balon).
	  El contacto con el balon se resuelve por logica (recoger, pase, tiro, entrada), no por fisica.
	- "MatchActor": los personajes de un partido. Chocan entre si y con el campo.
]]
local PhysicsService = game:GetService("PhysicsService")

local CollisionSetup = {}

CollisionSetup.BALL = "MatchBall"
CollisionSetup.ACTOR = "MatchActor"

local ready = false

function CollisionSetup.setup()
	if ready then
		return
	end
	ready = true
	for _, name in { CollisionSetup.BALL, CollisionSetup.ACTOR } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.BALL, CollisionSetup.ACTOR, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.BALL, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.ACTOR, "Default", true)
end

-- Pone al personaje (y a lo que se le anada despues: accesorios, herramientas) en el grupo MatchActor.
-- Devuelve la conexion para poder cerrarla al terminar el partido.
function CollisionSetup.applyToActor(model: Model): RBXScriptConnection
	CollisionSetup.setup()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionSetup.ACTOR
		end
	end
	return model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CollisionSetup.ACTOR
		end
	end)
end

-- Al terminar el partido el personaje del jugador vuelve al lobby con colisiones normales.
function CollisionSetup.resetActor(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CollisionGroup == CollisionSetup.ACTOR then
			descendant.CollisionGroup = "Default"
		end
	end
end

return CollisionSetup
