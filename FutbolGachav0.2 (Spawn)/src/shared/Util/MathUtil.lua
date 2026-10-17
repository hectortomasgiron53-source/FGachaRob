--!strict
local MathUtil = {}

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Convierte una estadistica (1 a 100) en un valor entre minValue (stat 1) y maxValue (stat 100).
-- Sirve tambien al reves: mapStat(stat, 8, 1) da un error angular que baja al subir la estadistica.
function MathUtil.mapStat(stat: number, minValue: number, maxValue: number): number
	local t = math.clamp((stat - 1) / 99, 0, 1)
	return minValue + (maxValue - minValue) * t
end

-- Quita la componente vertical de un vector.
function MathUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

return MathUtil
