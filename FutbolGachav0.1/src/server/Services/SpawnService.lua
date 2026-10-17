
--!strict
--[[
    SpawnService:
    Gestiona el punto de aparicion del lobby.
    Los jugadores aparecen aqui al entrar o reaparecer.
    El lobby esta separado de los campos de futbol.
]]

local Players = game:GetService("Players")

local SpawnService = {}

local LOBBY_POSITION = Vector3.new(0, 0, 0)

local function createLobby()
    local lobby = workspace:FindFirstChild("Lobby")

    if lobby then
        return
    end

    lobby = Instance.new("Folder")
    lobby.Name = "Lobby"
    lobby.Parent = workspace

    -- Suelo del lobby
    local floor = Instance.new("Part")
    floor.Name = "LobbyFloor"
    floor.Size = Vector3.new(160, 1, 160)
    floor.Position = LOBBY_POSITION - Vector3.new(0, 0.5, 0)
    floor.Anchored = true
    floor.Material = Enum.Material.Grass
    floor.Color = Color3.fromRGB(75, 145, 75)
    floor.Parent = lobby

    -- Punto de aparicion
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "LobbySpawn"
    spawn.Size = Vector3.new(12, 1, 12)
    spawn.Position = LOBBY_POSITION + Vector3.new(0, 0.5, 0)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Enabled = true
    spawn.Duration = 0
    spawn.Transparency = 0.25
    spawn.Material = Enum.Material.Neon
    spawn.Color = Color3.fromRGB(50, 200, 100)
    spawn.Parent = lobby
end

local function moveToLobby(character: Model)
    local root = character:WaitForChild("HumanoidRootPart", 10)

    if not root or not root:IsA("BasePart") then
        return
    end

    -- Si el jugador esta en un partido, no lo sacamos del campo.
    local player = Players:GetPlayerFromCharacter(character)

    if player and player:GetAttribute("MatchId") ~= nil then
        return
    end

    character:PivotTo(CFrame.new(LOBBY_POSITION + Vector3.new(0, 4, 0)))
end

function SpawnService.start()
    createLobby()

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            task.spawn(moveToLobby, character)
        end)

        -- Por si el personaje ya existe.
        if player.Character then
            task.spawn(moveToLobby, player.Character)
        end
    end)

    -- Por si el servicio se inicia con jugadores presentes.
    for _, player in Players:GetPlayers() do
        player.CharacterAdded:Connect(function(character)
            task.spawn(moveToLobby, character)
        end)

        if player.Character then
            task.spawn(moveToLobby, player.Character)
        end
    end

    print("[SpawnService] Spawn del lobby iniciado")
end

return SpawnService
