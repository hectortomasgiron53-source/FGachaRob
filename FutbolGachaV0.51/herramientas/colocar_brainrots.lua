--[[
	COLOCAR BRAINROTS (para la barra de comandos de Roblox Studio: View > Command Bar)

	1. Importa los .glb: pestana Inicio (o Modelo) > "Importar 3D" > selecciona TODOS los archivos > Iniciar importacion.
	   Aparecen en el Workspace (los de Sketchfab, todos con el nombre "Sketchfab_Scene").
	2. Copia TODO este archivo, pegalo en la barra de comandos y pulsa Enter.
	3. Mira la Salida (Output): dice cuales ha colocado y cuales no ha reconocido.
	4. Guarda el sitio (Ctrl+S) y publica. Los modelos quedan en ReplicatedStorage > BrainrotModels.

	Como se reconoce cada uno (todos se llaman igual): por el nombre del archivo si lo conserva, por los nombres de
	sus piezas internas y, si no, por cuantas mallas tiene y su forma. Para modelos nuevos se anaden pistas aqui.
]]

-- 1) Trozo del nombre del modelo (si conserva el del archivo) -> Id
local POR_NOMBRE = {
	{ "jobjobjob", "job_job_job_sahur" },
	{ "meowl", "meowl" },
	{ "glorbo", "glorbo_fruttodrillo" },
	{ "sigmatung", "tung_tung_tung_sahur" },
	{ "ketupatkepataimodel", "ketupat_kepat_Evo2" }, -- (antes que "ketupat": es la evolucion de nivel 90)
	{ "alessio", "alessio_pallonetto" },
	{ "bobrini", "bobrini_cocosini" },
	{ "bonecaambalabu", "boneca_ambalabu" },
	{ "pigeon", "piccione_scalzino" },
	{ "chillinchili", "chillin_chili" },
	{ "chococino", "chococino_lavawalkini" },
	{ "duddudgendut", "dud_dud_gendut" },
	{ "frigocamello", "frigo_camelo" },
	{ "leruleru", "leru_leru_le" },
	{ "noobini", "noobini_pizzanini" },
	{ "personajedorado", "doratino_brillantino" },
	{ "rhinoboxing", "rinoceronte_boxerino" },
	{ "67steal", "sessantasette" },
	{ "avocado", "avocadorilla" },
	{ "bombardiro", "bombardiro_crocodilo" },
	{ "finalboss", "boss_finalissimo" },
	{ "karkerkar", "karkerkar_kurkur" },
	{ "raffalello", "raffalello_il_porcello" },
	{ "celularcini", "celularcini_viciosini" },
	{ "ketupat", "ketupat_kepat" },
	{ "santteo", "santteo" },
	{ "swagsoda", "swag_soda" },
	{ "tototosahur", "to_to_to_sahur" },
	{ "udindin", "udin_din_din_dun" },
}

-- 2) Trozo del nombre de alguna pieza interna -> Id
local POR_PIEZA = {
	-- Lote 5
	{ "42efb85bdf4a425a", "trippi_troppi" },
	{ "patapim_render", "brr_brr_patapim" },
	{ "12662c153d394c86", "tralalero_tralala" },
	{ "tralalero", "tralalero_tralala" },
	-- Lote 4
	{ "jorge_23265", "orcalero_orcala" },
	{ "skibidi", "skibidi_toilet" },
	{ "modelobjcleaner", "brr_es_teh_patipum" },
	{ "muscle_fruit", "budi_dididun" },
	{ "a9e6fa4dfb2340", "gatto_melonino" },
	-- Lote 3
	{ "tripo_convert_10c69dd7", "job_job_job_sahur" },
	{ "croc_im_arm", "glorbo_fruttodrillo" },
	{ "759581d7652c4914", "tung_tung_tung_sahur" },
	{ "retopo_tripo_node_c013d3b3", "tung_tung_tung_sahur" },
	-- Lote 2
	{ "tripo_convert_8ea20e35", "alessio_pallonetto" },
	{ "tripo_convert_b80841d3", "ketupat_kepat_Evo2" },
	{ "meshy_ai_barefoot_pigeon", "piccione_scalzino" },
	{ "32002_0", "chillin_chili" },
	{ "smoking_cartoon_strol", "dud_dud_gendut" },
	{ "cactus_cowboy_penguin", "leru_leru_le" },
	{ "noobini_piz", "noobini_pizzanini" },
	{ "cuerpo_dorado", "doratino_brillantino" },
	{ "mesh_0_0", "rinoceronte_boxerino" },
	-- Lote 1
	{ "e9c84fadcc8544", "sessantasette" },
	{ "avocadogorilla", "avocadorilla" },
	{ "5b71e63e9fc844", "bombardiro_crocodilo" },
	{ "tripo_node_31eb24ed", "boss_finalissimo" },
	{ "9bcfcee395d44a", "karkerkar_kurkur" },
	{ "node_id56", "raffalello_il_porcello" },
	{ "brainrot_0", "udin_din_din_dun" },
}

-- 2b) Nombre de pieza EXACTO (son tan cortos que como trozo saldrian en otros)
local POR_PIEZA_EXACTA = {
	["_0"] = "boneca_ambalabu", -- (Ballerina Cappuccina tambien tiene "_0": se distinguen abajo por el numero de mallas)
}

-- 3) Los de "steal a brainrot" del mismo autor tienen las piezas con los mismos nombres: por numero de mallas
local POR_MALLAS = {
	[4] = "to_to_to_sahur",
	[5] = "piccione_scalzino", -- (por si el importador pierde el nombre "Meshy_AI_Barefoot_Pigeon"; Chococino tambien tiene 5 pero se reconoce antes)
	[7] = "ketupat_kepat",
	[11] = "santteo",
	-- 15 mallas: Celularcini Viciosini o Swag Soda (se distinguen por la forma, abajo)
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "BrainrotModels"
	folder.Parent = ReplicatedStorage
end

local function plain(text)
	return (string.lower(text):gsub("[^%w_]", ""))
end

local function idFor(item)
	local name = plain(item.Name):gsub("_", "")
	for _, pista in POR_NOMBRE do
		if string.find(name, pista[1], 1, true) then
			return pista[2]
		end
	end
	local meshes = 0
	local baseObj = false -- Bobrini, Frigo Camello, Chococino y Meowl (del mismo programa) tienen la pieza "base.obj..."
	local exacta = nil
	for _, d in item:GetDescendants() do
		local dname = plain(d.Name)
		if POR_PIEZA_EXACTA[dname] then
			exacta = POR_PIEZA_EXACTA[dname]
		end
		if string.sub(dname, 1, 14) == "baseobjcleaner" then
			baseObj = true
		end
		for _, pista in POR_PIEZA do
			if string.find(dname, pista[1], 1, true) then
				return pista[2]
			end
		end
		if d:IsA("MeshPart") then
			meshes += 1
		end
	end
	if exacta == "boneca_ambalabu" and meshes >= 3 then
		return "ballerina_cappuccina" -- (Boneca tiene 1 malla; Ballerina, 4)
	elseif exacta then
		return exacta
	end
	if baseObj and item:IsA("Model") then
		if meshes >= 6 then
			return "meowl" -- (7 mallas)
		elseif meshes >= 3 then
			return "chococino_lavawalkini" -- (5 mallas)
		end
		local _, size = item:GetBoundingBox()
		-- Orangutini Ananassini (la naranja) es casi tan ancho como largo; Frigo y Bobrini, mucho mas largos que anchos
		if math.min(size.X, size.Z) / math.max(size.X, size.Z, 0.001) > 0.85 then
			return "orangutini_ananassini"
		end
		-- Frigo Camello es alto (alto / ancho ~1,1); Bobrini, mas bajo y alargado (~0,8)
		return if size.Y / math.max(size.X, size.Z, 0.001) > 0.95 then "frigo_camelo" else "bobrini_cocosini"
	end
	if POR_MALLAS[meshes] then
		return POR_MALLAS[meshes]
	end
	if meshes == 15 and item:IsA("Model") then
		-- Celularcini es mas alargado (lado mayor / lado menor ~3,2) que Swag Soda (~2,3)
		local _, size = item:GetBoundingBox()
		local dims = { size.X, size.Y, size.Z }
		table.sort(dims)
		return if dims[3] / math.max(dims[1], 0.001) > 2.7 then "celularcini_viciosini" else "swag_soda"
	end
	return nil
end

local placed, unknown = {}, {}
for _, item in workspace:GetChildren() do
	if not (item:IsA("Model") or item:IsA("MeshPart")) or item:FindFirstChildOfClass("Humanoid") then
		continue
	end
	if item:IsA("Model") and not item:FindFirstChildWhichIsA("MeshPart", true) then
		continue -- (no es un modelo importado)
	end
	local id = idFor(item)
	if not id then
		if string.find(item.Name, "Sketchfab", 1, true) then
			table.insert(unknown, item.Name)
		end
		continue
	end
	if placed[id] then
		warn(`[Brainrots] Hay dos modelos que parecen {id}: deja solo uno (el segundo se queda en el Workspace)`)
		continue
	end
	local old = folder:FindFirstChild(id)
	if old then
		old:Destroy() -- se cambia por el nuevo
	end
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	if item:IsA("BasePart") then
		item.Anchored = true
		item.CanCollide = false
	end
	item.Name = id
	item.Parent = folder
	placed[id] = true
	print(`[Brainrots] Colocado: {id}`)
end
local count = 0
for _ in placed do
	count += 1
end
print(`[Brainrots] {count} modelos colocados en ReplicatedStorage > BrainrotModels`)
if #unknown > 0 then
	warn(`[Brainrots] Sin reconocer (renombralos a mano con su Id y muevelos a BrainrotModels): {#unknown}`)
end
