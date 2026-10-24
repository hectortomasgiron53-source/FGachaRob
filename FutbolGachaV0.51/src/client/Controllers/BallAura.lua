--!strict
--[[
	BallAura: contorno BLANCO alrededor de quien lleva el balon (persona o bot) y del propio balon, para saber de un
	vistazo quien lo tiene.
	- Cada jugador del partido ya lleva un resaltado del color de su equipo (MatchHighlight): al que lleva el balon se le
	  cambia el contorno a blanco (solo en tu pantalla) y se le devuelve el suyo al perderlo.
	- El balon que ves (BallVisual) lleva otro contorno blanco mientras alguien lo lleva.
	El servidor dice quien lo lleva con el ObjectValue "Holder" del balon (Ball._sync).
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchController = require(script.Parent.MatchController)
local BallVisual = require(script.Parent.BallVisual)

local BallAura = {}

local WHITE = Color3.new(1, 1, 1)

local current: Model? = nil
local changed: Highlight? = nil -- resaltado del equipo al que se le puso el contorno blanco
local oldOutline: Color3 = WHITE
local oldOutlineTransparency = 0
local own: Highlight? = nil -- si el jugador no tenia resaltado, uno nuestro
local ballHighlight: Highlight

local function release()
	if changed and changed.Parent then
		changed.OutlineColor = oldOutline
		changed.OutlineTransparency = oldOutlineTransparency
	end
	changed = nil
	if own then
		own:Destroy()
		own = nil
	end
	current = nil
end

local function mark(model: Model)
	release()
	current = model
	local highlight = model:FindFirstChild("MatchHighlight")
	if highlight and highlight:IsA("Highlight") then
		changed = highlight
		oldOutline = highlight.OutlineColor
		oldOutlineTransparency = highlight.OutlineTransparency
		highlight.OutlineColor = WHITE
		highlight.OutlineTransparency = 0
	else
		local h = Instance.new("Highlight")
		h.Name = "FG_HolderOutline"
		h.FillTransparency = 1
		h.OutlineColor = WHITE
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = model
		h.Parent = Workspace.CurrentCamera
		own = h
	end
end

function BallAura.start()
	ballHighlight = Instance.new("Highlight")
	ballHighlight.Name = "FG_BallOutline"
	ballHighlight.FillTransparency = 1
	ballHighlight.OutlineColor = WHITE
	ballHighlight.OutlineTransparency = 0
	ballHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	ballHighlight.Enabled = false
	ballHighlight.Parent = Workspace.CurrentCamera

	RunService.RenderStepped:Connect(function()
		local ball = if MatchController.isInMatch() then MatchController.getBall() else nil
		local holderValue = if ball then ball:FindFirstChild("Holder") else nil
		local holder = if holderValue and holderValue:IsA("ObjectValue") then holderValue.Value else nil
		local model = if holder and holder:IsA("Model") and holder.Parent then holder else nil
		if model ~= current then
			if model then
				mark(model)
			else
				release()
			end
		end
		-- El balon: contorno mientras alguien lo lleva
		local visible = BallVisual.getPart() or ball
		local show = current ~= nil and visible ~= nil
		if ballHighlight.Adornee ~= visible then
			ballHighlight.Adornee = visible
		end
		if ballHighlight.Enabled ~= show then
			ballHighlight.Enabled = show
		end
	end)
end

return BallAura
