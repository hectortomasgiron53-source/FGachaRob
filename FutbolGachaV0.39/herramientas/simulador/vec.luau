-- Vector3 de imitacion (para ejecutar el codigo del juego fuera de Roblox)
local V = {}
local sqrt = math.sqrt
local function new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__index = function(t, k)
	if k == "Magnitude" then
		return sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m < 1e-12 then
			return new(0 / 0, 0 / 0, 0 / 0)
		end
		return new(t.X / m, t.Y / m, t.Z / m)
	end
	return rawget(V, k)
end
V.__add = function(a, b) return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return new(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return new(a.X * b, a.Y * b, a.Z * b) end
	return new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b)
	if type(b) == "number" then return new(a.X / b, a.Y / b, a.Z / b) end
	return new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V.__unm = function(a) return new(-a.X, -a.Y, -a.Z) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Cross(a, b) return new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V.Lerp(a, b, t) return new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
local Vector3 = { new = new, zero = new(0, 0, 0), xAxis = new(1, 0, 0), yAxis = new(0, 1, 0), zAxis = new(0, 0, 1) }
local Color3 = { fromRGB = function() return {} end, new = function() return {} end }
return { Vector3 = Vector3, Color3 = Color3 }
