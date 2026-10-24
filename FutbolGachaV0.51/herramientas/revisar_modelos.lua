--[[
	REVISAR MODELOS (barra de comandos de Roblox Studio: View > Command Bar)

	Copia TODO este archivo, pegalo en la barra de comandos y pulsa Enter. No cambia nada: solo escribe un informe
	en la Salida (Output). Copia el informe (clic derecho en la Salida > Copiar todo, o una captura) y pasaselo a Claude.

	Revisa: que cada brainrot activo tenga su modelo en ReplicatedStorage > BrainrotModels, modelos que sobran o con
	nombre raro, importaciones que se quedaron en el Workspace, piezas sin textura (saldrian grises), tamano y
	numero de piezas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Brainrots = require(ReplicatedStorage.Shared.Config.Brainrots)
local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")

local lines = { "===== REVISION DE MODELOS =====" }
local function out(text)
	table.insert(lines, text)
end

if not folder then
	out("ERROR: no existe ReplicatedStorage > BrainrotModels")
	print(table.concat(lines, "\n"))
	return
end

local function describe(model)
	local parts, meshes, untextured, bones = 0, 0, 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
		if d:IsA("MeshPart") then
			meshes += 1
			local hasSurface = d:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil
			if d.TextureID == "" and not hasSurface then
				untextured += 1
			end
		end
		if d:IsA("Bone") then
			bones += 1
		end
	end
	local size = Vector3.zero
	if model:IsA("Model") then
		local _, s = model:GetBoundingBox()
		size = s
	elseif model:IsA("BasePart") then
		size = model.Size
	end
	return string.format("%s, piezas=%d mallas=%d sinTextura=%d huesos=%d tam=%.1fx%.1fx%.1f",
		model.ClassName, parts, meshes, untextured, bones, size.X, size.Y, size.Z), untextured, meshes
end

-- 1) Brainrots activos, por calidad
local total, withModel = 0, 0
local order = { "Comun", "Raro", "Epico", "Legendario", "Mitico", "Secreto" }
for _, rarity in order do
	out("")
	out("--- " .. rarity .. " ---")
	for _, entry in Brainrots.ByRarity[rarity] or {} do
		total += 1
		local model = folder:FindFirstChild(entry.Id)
		if model then
			withModel += 1
			local text, untextured, meshes = describe(model)
			local warn = ""
			if meshes > 0 and untextured == meshes then
				warn = "  <-- OJO: ninguna malla tiene textura (gris?)"
			end
			out(string.format("OK  %-24s giro=%s  %s%s", entry.Id, tostring(Brainrots.ModelYaw[entry.Id] or 0), text, warn))
		else
			out(string.format("--  %-24s SIN MODELO", entry.Id))
		end
	end
end

-- 2) Lo que hay en la carpeta y no es un brainrot activo
out("")
out("--- Otros en BrainrotModels ---")
for _, child in folder:GetChildren() do
	local entry = Brainrots.ById[child.Name]
	if not entry then
		local base = string.gsub(child.Name, "_Evo%d+$", "")
		if Brainrots.ById[base] then
			out("evolucion  " .. child.Name .. "  " .. (describe(child)))
		else
			out("RARO: no es ningun brainrot -> " .. child.Name)
		end
	elseif entry.Disabled then
		out("desactivado (no sale en cajas) -> " .. child.Name)
	end
end

-- 3) Importaciones que se quedaron en el Workspace
local leftovers = {}
for _, child in workspace:GetChildren() do
	if string.find(string.lower(child.Name), "sketchfab", 1, true) then
		table.insert(leftovers, child.Name)
	end
end
out("")
out(if #leftovers > 0
	then "EN EL WORKSPACE SIN COLOCAR (" .. #leftovers .. "): " .. table.concat(leftovers, ", ")
	else "Workspace limpio (no quedan importaciones sin colocar)")

out("")
out(string.format("RESUMEN: %d de %d brainrots activos tienen modelo", withModel, total))
print(table.concat(lines, "\n"))
