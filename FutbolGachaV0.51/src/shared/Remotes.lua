--!strict
--[[
	Remotes: acceso centralizado a los RemoteEvents.
	El servidor los crea (Boot los pide todos al arrancar); el cliente espera a que existan.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- Action: cliente -> servidor (pase, tiro, entrada, sprint)
-- RequestMatch: cliente -> servidor (pedir un partido)
-- MatchEvent: servidor -> cliente (gol, final, aviso)
-- BallControl: servidor -> todos los clientes (burbuja al controlar la pelota)
-- Debug: cliente -> servidor, SOLO funciona en Studio
-- Fx: servidor -> clientes del partido (sonidos y animaciones sencillas)
-- Data: servidor -> cliente (tus datos: brainrots, granja, equipo, diario...)
-- Notify: servidor -> cliente (avisos: recompensas, robos, subir de nivel)
Remotes.Names = { "Action", "RequestMatch", "MatchEvent", "BallControl", "Debug", "Fx", "Data", "Notify" }
-- Economy (RemoteFunction): cliente -> servidor con respuesta (abrir caja, subir nivel, vender, equipo, diario...)
Remotes.FunctionNames = { "Economy", "Admin" } -- (Admin: panel de administrador, ver AdminService)

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.get(name: string): RemoteEvent
	local folder = getFolder()
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.getFunction(name: string): RemoteFunction
	local folder = getFolder()
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteFunction
		end
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
