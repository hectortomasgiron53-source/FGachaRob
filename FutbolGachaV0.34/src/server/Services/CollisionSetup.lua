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
CollisionSetup.BALL_ONLY = "BallOnlyBarrier" -- paredes que solo frenan al balon (puerta del campo de exhibicion)

local ready = false

function CollisionSetup.setup()
	if ready then
		return
	end
	ready = true
	for _, name in { CollisionSetup.BALL, CollisionSetup.ACTOR, CollisionSetup.BALL_ONLY } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.BALL, CollisionSetup.ACTOR, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.BALL, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.ACTOR, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.BALL_ONLY, CollisionSetup.BALL, true)
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.BALL_ONLY, CollisionSetup.ACTOR, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionSetup.BALL_ONLY, "Default", false)
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
