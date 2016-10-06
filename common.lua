--= Animals mod =--
-- Copyright (c) 2016 Daniel <https://github.com/daniel-32>
--
-- Modified from Creatures MOB-Engine (cme)
-- Copyright (c) 2015 BlockMen <blockmen2015@gmail.com>
--
-- common.lua
--
-- This software is provided 'as-is', without any express or implied warranty. In no
-- event will the authors be held liable for any damages arising from the use of
-- this software.
--
-- Permission is granted to anyone to use this software for any purpose, including
-- commercial applications, and to alter it and redistribute it freely, subject to the
-- following restrictions:
--
-- 1. The origin of this software must not be misrepresented; you must not
-- claim that you wrote the original software. If you use this software in a
-- product, an acknowledgment in the product documentation is required.
-- 2. Altered source versions must be plainly marked as such, and must not
-- be misrepresented as being the original software.
-- 3. This notice may not be removed or altered from any source distribution.
--

-- constants
nullVec = {x = 0, y = 0, z = 0}
DEGTORAD = math.pi / 180.0

-- common functions
function animals.rnd(table, errval)
	if not errval then
		errval = false
	end

	local res = 1000000000
	local rn = math.random(0, res - 1)
	local retval = nil

	local psum = 0
	for s,w in pairs(table) do
		psum = psum + ((tonumber(w) or w.chance or 0) * res)
		if psum > rn then
			retval = s
			break
		end
	end

	return retval
end

function animals.throwError(msg)
	core.log("error", "#Animals: ERROR: " .. msg)
end

function animals.comparePos(pos1, pos2)
	if not pos1 or not pos2 then
		return false
	end
	if pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z then
		return true
	end
	return false
end

function animals.findTarget(search_obj, pos, radius, target_type, owner_name, xray)
	local mobs = {}
	for _,obj in ipairs(core.get_objects_inside_radius(pos, radius)) do
		if obj ~= search_obj then
			if xray or core.line_of_sight(pos, obj:getpos()) == true then
				local is_player = obj:is_player()
				local entity = obj:get_luaentity()
				local isItem = (entity and entity.name == "__builtin:item") or false

				if target_type == "player" then
					if is_player then
						if owner_name == "" or obj:get_player_name() == owner_name then
							table.insert(mobs, obj)
						end
					end
				else
					if not isItem and entity and entity.mob_name and entity.mob_name == target_type then
						if owner_name == "" or (entity.owner_name and entity.owner_name == owner_name) then
							table.insert(mobs, obj)
						end
					end
				end
			end
		end
	end
	return mobs
end

function animals.dropItems(pos, drops)
	if not pos or not drops then
		return
	end

	-- convert drops table
	local tab = {}
	for _,elem in pairs(drops) do
		local name = tostring(elem[1])
		local v = elem[2]
		local chance = elem.chance
		local amount = ""
		-- check if drops depending on defined chance
		if name and chance then
			local ct = {}
			ct[name] = chance
			ct["_fake"] = 1 - chance
			local res = animals.rnd(ct)
			if res == "_fake" then
				name = nil
			end
		end
		-- get amount
		if name and v then
			if type(v) == "table" then
				amount = math.random(v.min or 1, v.max or 1) or 1
			elseif type(v) == "number" then
				amount = v
			end
			if amount > 0 then
				amount = " " .. amount
			end
		end
		if name then
			local obj = core.add_item(pos, name .. amount)
			if not obj then
				throw_error("Could not drop item '" .. name .. amount .. "'")
			end
		end
	end
end
