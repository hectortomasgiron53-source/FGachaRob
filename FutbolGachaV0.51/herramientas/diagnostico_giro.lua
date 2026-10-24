-- DIAGNOSTICO DEL GIRO (barra de comandos de Studio, sin darle a Play). Copia TODO, pegalo, Ejecutar, y pasale a
-- Claude lo que salga en la Salida.
local RS = game:GetService("ReplicatedStorage")
local ID = "sessantasette"
local source = RS.BrainrotModels:FindFirstChild(ID)
print("=== DIAG", ID, "clase:", source and source.ClassName)
if not source then return end
local counts = {}
for _, d in source:GetDescendants() do
	counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
end
local list = {}
for k, v in counts do table.insert(list, k .. "=" .. v) end
print("Contenido:", table.concat(list, ", "))
print("PrimaryPart:", source:IsA("Model") and tostring(source.PrimaryPart) or "-")
if source:IsA("Model") then
	local rx, ry, rz = source:GetPivot():ToOrientation()
	print("Pivote giro:", math.deg(rx), math.deg(ry), math.deg(rz))
end
for i, d in source:GetDescendants() do
	if d:IsA("BasePart") and i < 40 then
		local rx, ry, rz = d.CFrame:ToOrientation()
		print("  pieza", d.ClassName, d.Name, "giro", math.floor(math.deg(rx)), math.floor(math.deg(ry)), math.floor(math.deg(rz)), "tam", d.Size)
	end
end
local Brainrots = require(RS.Shared.Config.Brainrots)
local BrainrotModel = require(RS.Shared.Util.BrainrotModel)
print("ModelYaw actual:", Brainrots.ModelYaw[ID])
local function facing(yaw)
	local old = Brainrots.ModelYaw[ID]
	Brainrots.ModelYaw[ID] = yaw
	local ok, m = pcall(BrainrotModel.build, ID, "Normal", 5)
	Brainrots.ModelYaw[ID] = old
	if not ok then
		print("  ERROR al crear:", m)
		return nil
	end
	local root = m.PrimaryPart
	local first
	for _, d in m:GetDescendants() do
		if d:IsA("MeshPart") then first = d break end
	end
	if not first then
		print("  sin MeshPart")
		return nil
	end
	local rel = root.CFrame:ToObjectSpace(first.CFrame)
	local _, ry = rel:ToOrientation()
	local look = rel.LookVector
	print(`  giro {yaw}: pieza {first.Name} gira {math.floor(math.deg(ry))} · mira hacia ({math.floor(look.X * 100) / 100}, {math.floor(look.Z * 100) / 100}) · pos ({math.floor(rel.X * 10) / 10}, {math.floor(rel.Z * 10) / 10})`)
	m:Destroy()
	return rel
end
facing(0)
facing(180)
print("=== FIN DIAG")
