--= Animals mod =--
-- Copyright (c) 2016 Daniel <https://github.com/danielmeek32>
--
-- Modified from Creatures MOB-Engine (cme)
-- Copyright (c) 2015 BlockMen <blockmen2015@gmail.com>
--
-- register.lua
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

local function translate_def(def)
	local new_def = {
		physical = true,
		visual = "mesh",
		stepheight = 0.6, -- ensure we get over slabs/stairs
		automatic_face_movement_dir = def.model.rotation or 0.0,

		mesh = def.model.mesh,
		textures = def.model.textures,
		collisionbox = def.model.collisionbox or {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		visual_size = def.model.scale or {x = 1, y = 1},
		backface_culling = false,
		collide_with_objects = def.model.collide_with_objects,

		stats = def.stats,
		model = def.model,
		sounds = def.sounds,
		modes = {},
		drops = def.drops,
	}

	-- Tanslate modes to better accessable format
	for key, mode in pairs(def.modes) do
		local name = tostring(key)
		new_def.modes[name] = mode
	end
	-- insert special mode "_run" which is used when in panic
	if def.modes.walk then
		local new = table.copy(new_def.modes["walk"])
		new.chance = 0
		new.duration = 3
		new.moving_speed = new.moving_speed * 2
		if def.stats.panic_speed then
			new.moving_speed = def.stats.panic_speed
		end
		new.update_yaw = 0.7
		new_def.modes["_run"] = new
		local new_anim = def.model.animations.panic
		if not new_anim then
			new_anim = table.copy(def.model.animations.walk)
			new_anim.speed = new_anim.speed * 2
		end
		new_def.model.animations._run = new_anim
	end

	if def.stats.jump_height and type(def.stats.jump_height) == "number" then
		if def.stats.jump_height > 0 then
			new_def.stepheight = def.stats.jump_height + 0.1
		end
	end

	new_def.makes_footstep_sound = not def.stats.silent

	new_def.get_staticdata = function(self)
		local main_table = animals.get_staticdata(self)
		-- is own staticdata function defined? If so, merge results
		if def.get_staticdata then
			local data = def.get_staticdata(self)
			if data and type(data) == "table" then
				for key, value in pairs(data) do
					main_table[key] = value
				end
			end
		end

		-- return data serialized
		return core.serialize(main_table)
	end

	new_def.on_activate = function(self, staticdata)
		self.mob_name = def.name
		self.hp = def.stats.hp
		self.mode = "idle"
		self.stunned = false
		self.tamed = false
		self.owner_name = ""
		self.target = nil
		self.in_water = false
		self.autofollowing = false

		-- Timers
		self.lifetimer = 0
		if def.stats.breed_items then
			self.breedtimer = def.stats.breedtime
			self.lovetimer = def.stats.lovetime
		else
			self.breedtimer = 0
			self.lovetimer = 0
		end

		self.nodetimer = 2
		self.modetimer = math.random()
		self.yawtimer = 0
		self.searchtimer = 0
		self.followtimer = 0
		self.soundtimer = math.random()
		self.swimtimer = 2

		-- Other things
		if staticdata then
			local table = core.deserialize(staticdata)
			if table and type(table) == "table" then
				for key, value in pairs(table) do
					self[tostring(key)] = value
				end
			end
		end

		if self.mode == "follow" and self.target == nil then
			self.autofollowing = false
			self.mode = "idle"
		end

		if not self.in_water then
			self.object:setacceleration({x = 0, y = -15, z = 0})
		end

		self.object:set_hp(self.hp)

		-- immortal is needed to disable clientside smokepuff
		self.object:set_armor_groups({fleshy = 100, immortal = 1})

		-- call custom on_activate if defined
		if def.on_activate then
			def.on_activate(self, staticdata)
		end
	end

	new_def.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if def.on_punch and def.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir) == true then
			return
		end
		animals.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
	end

	new_def.on_rightclick = function(self, clicker)
		if self.tamed and clicker:get_player_name() ~= self.owner_name then
			return
		end
		if def.on_rightclick and def.on_rightclick(self, clicker) == true then
			return
		end
		animals.on_rightclick(self, clicker)
	end

	new_def.on_step = function(self, dtime)
		if def.on_step and def.on_step(self, dtime) == true then
			return
		end
		animals.on_step(self, dtime)
	end

	new_def.on_follow_start = function(self)
		if def.on_follow_start then
			def.on_follow_start(self)
		end
	end

	new_def.on_follow_end = function(self)
		if def.on_follow_end then
			def.on_follow_end(self)
		end
	end

	new_def.on_eat = function(self)
		if def.on_eat then
			def.on_eat(self)
		end
	end

	return new_def
end

local function in_range(min_max, value)
	if not value or not min_max or not min_max.min or not min_max.max then
		return false
	end
	if (value >= min_max.min and value <= min_max.max) then
		return true
	end
	return false
end

local function check_space(pos, height)
	for i = 0, height do
		local n = core.get_node_or_nil({x = pos.x, y = pos.y + i, z = pos.z})
		if not n or n.name ~= "air" then
			return false
		end
	end
	return true
end

local time_taker = 0
local function step(tick)
	core.after(tick, step, tick)
	time_taker = time_taker + tick
end
step(0.5)

local function stop_abm_flood()
	if time_taker == 0 then
		return true
	end
	time_taker = 0
end

local function group_spawn(pos, mob, group, nodes, range, max_loops)
	local cnt = 0
	local cnt2 = 0

	local nodes = core.find_nodes_in_area({x = pos.x - range, y = pos.y - range, z = pos.z - range},
		{x = pos.x + range, y = pos.y, z = pos.z + range}, nodes)
	local number = #nodes - 1
	if max_loops and type(max_loops) == "number" then
		number = max_loops
	end
	while cnt < group and cnt2 < number do
		cnt2 = cnt2 + 1
		local p = nodes[math.random(1, number)]
		p.y = p.y + 1
		if check_space(p, mob.size) == true then
			cnt = cnt + 1
			core.add_entity(p, mob.name)
		end
	end
	if cnt < group then
		return false
	end
end

local function register_spawn(spawn_def)
	if not spawn_def or not spawn_def.abm_nodes then
		throw_error("No valid definition given.")
		return false
	end

	if not spawn_def.abm_nodes.neighbors then
		spawn_def.abm_nodes.neighbors = {}
	end
	table.insert(spawn_def.abm_nodes.neighbors, "air")

	core.register_abm({
		nodenames = spawn_def.abm_nodes.spawn_on,
		neighbors = spawn_def.abm_nodes.neighbors,
		interval = spawn_def.abm_interval or 44,
		chance = spawn_def.abm_chance or 7000,
		action = function(pos, node, active_object_count, active_object_count_wider)
			-- prevent abm-"feature"
			if stop_abm_flood() == true then
				return
			end

			-- time check
			local tod = core.get_timeofday() * 24000
			if spawn_def.time_range then
				local wanted_res = false
				local range = table.copy(spawn_def.time_range)
				if range.min > range.max and range.min <= tod then
					wanted_res = true
				end
				if in_range(range, tod) == wanted_res then
					return
				end
			end

			-- position check
			if spawn_def.height_limit and not in_range(spawn_def.height_limit, pos.y) then
				return
			end

			-- light check
			pos.y = pos.y + 1
			local llvl = core.get_node_light(pos)
			if spawn_def.light and not in_range(spawn_def.light, llvl) then
				return
			end
			-- creature count check
			local max
			if active_object_count_wider > (spawn_def.max_number or 1) then
				local mates_num = #animals.findTarget(nil, pos, 16, spawn_def.mob_name, "", true)
				if (mates_num or 0) >= spawn_def.max_number then
					return
				else
					max = spawn_def.max_number - mates_num
				end
			end

			-- ok everything seems fine, spawn creature
			local height_min = (spawn_def.mob_size[5] or 2) - (spawn_def.mob_size[2] or 0)
			height_min = math.ceil(height_min)

			local number = 0
			if type(spawn_def.number) == "table" then
				number = math.random(spawn_def.number.min, spawn_def.number.max)
			else
				number = spawn_def.number or 1
			end

			if max and number > max then
				number = max
			end

			if number > 1 then
				group_spawn(pos, {name = spawn_def.mob_name, size = height_min}, number, spawn_def.abm_nodes.spawn_on, 5)
			else
			-- space check
				if not check_space(pos, height_min) then
					return
				end
				core.add_entity(pos, spawn_def.mob_name)
			end
		end,
	})

	return true
end

function animals.registerMob(def) -- returns true if successful
	if not def or not def.name then
		throw_error("Can't register mob. No name or Definition given.")
		return false
	end

	local mob_def = translate_def(def)

	core.register_entity(":" .. def.name, mob_def)

	-- register spawn
	if def.spawning then
		local spawn_def = def.spawning
		spawn_def.mob_name = def.name
		spawn_def.mob_size = def.model.collisionbox
		if register_spawn(spawn_def) ~= true then
			throw_error("Couldn't register spawning for '" .. def.name .. "'")
		end
	end

	return true
end
