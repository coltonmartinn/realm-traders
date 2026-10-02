--!strict
-- Who stands where. Every building and prop claims a circle of ground as it's
-- placed, and anything placed after it (scattered trees, benches, lamps,
-- props) checks that its spot is free first. So nothing ends up inside
-- anything else, whatever order things are built in.

local Layout = {}

type Spot = { x: number, z: number, r: number }

local spots: { Spot } = {}

-- Marks a circle of ground (radius r around `at`) as taken.
function Layout.claim(at: Vector3, r: number)
	table.insert(spots, { x = at.X, z = at.Z, r = r })
end

-- Whether a circle of radius r around `at` is clear of every claim, with
-- `gap` studs to spare (1 by default).
function Layout.free(at: Vector3, r: number, gap: number?): boolean
	local g = gap or 1
	for _, s in spots do
		local dx, dz = s.x - at.X, s.z - at.Z
		local min = s.r + r + g
		if dx * dx + dz * dz < min * min then
			return false
		end
	end
	return true
end

-- Claims the spot if it's free. Returns whether it did.
function Layout.take(at: Vector3, r: number, gap: number?): boolean
	if Layout.free(at, r, gap) then
		Layout.claim(at, r)
		return true
	end
	return false
end

-- Claims a strip of ground (a path) as a row of circles.
function Layout.claimLine(from: Vector3, to: Vector3, halfWidth: number)
	local flat = Vector3.new(1, 0, 1)
	local a, b = from * flat, to * flat
	local length = (b - a).Magnitude
	local steps = math.max(1, math.ceil(length / halfWidth))
	for i = 0, steps do
		Layout.claim(a:Lerp(b, i / steps), halfWidth)
	end
end

return Layout
