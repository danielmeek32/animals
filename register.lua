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
		stepheight = 1.1,
		automatic_face_movement_dir = def.model.rotation or 0.0,

		mesh = def.model.mesh,
		textures = def.model.textures,
		collisionbox = def.model.collisionbox or {-0.4, 0, -0.4, 0.4, 1.25, 0.4},
		visual_size = def.model.scale or {x = 1, y = 1},
		backface_culling = true,
		collide_with_objects = def.model.collide_with_objects or true,

		stats = def.stats,
		model = def.model,
		sounds = def.sounds,
		modes = def.modes,
		drops = def.drops,
	}

	-- insert special mode "_run" which is used when in panic
	if def.modes.walk then
		local new = table.copy(new_def.modes["walk"])
		new.chance = 0
		new.duration = 3
		new.moving_speed = new.moving_speed * 2
		if def.stats.panic_speed then
			new.moving_speed = def.stats.panic_speed
		end
		new.update_yaw = 0.75
		new_def.modes["_run"] = new
		local new_anim = def.model.animations.panic
		if not new_anim then
			new_anim = table.copy(def.model.animations.walk)
			new_anim.speed = new_anim.speed * (new.moving_speed / new_def.modes["walk"].moving_speed)
		end
		new_def.model.animations._run = new_anim
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
		-- add api calls
		self.get_mode = function(self)
			return self.mode
		end
		self.set_mode = function(self, new_mode)
			animals.change_mode(self, new_mode)	-- TODO: this shouldn't be in the animals namespace
		end
		self.choose_random_mode = function(self)
			animals.change_mode(self)	-- TODO: this shouldn't be in the animals namespace
		end
		self.follow = function(self, target)
			self.target = target
			self.autofollowing = false
			animals.change_mode(self, "follow")
		end

		-- load static data into a table
		local staticdata_table = {}
		if staticdata then
			local table = minetest.deserialize(staticdata)
			if table and type(table) == "table" then
				staticdata_table = table
			end
		end

		-- create fields
		self.mob_name = def.name
		self.hp = staticdata_table.hp or def.stats.hp
		self.mode = ""	-- initialising with a blank mode will cause the mob to choose a random mode in the first tick
		self.tamed = staticdata_table.tamed or false
		self.owner_name = staticdata_table.owner_name or ""
		self.target = nil
		self.autofollowing = false

		-- create timers
		self.lifetimer = staticdata_table.lifetimer or 0
		if def.stats.breed_items then
			self.breedtimer = staticdata_table.breedtime or def.stats.breedtime
			self.lovetimer = staticdata_table.lovetime or def.stats.lovetime
		else
			self.breedtimer = 0
			self.lovetimer = 0
		end
		-- these timers are not saved in the static data
		self.modetimer = 0
		self.yawtimer = 0
		self.searchtimer = 0
		self.followtimer = 0
		self.soundtimer = 0
		self.swimtimer = 2

		-- set acceleration for on land (the mob will detect if it is in water in the first tick and respond appropriately)
		self.in_water = false
		self.object:setacceleration({x = 0, y = -15, z = 0})

		-- TODO: consider moving hp to clientside
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

	new_def.on_mode_change = function(self, new_mode)
		if def.on_mode_change then
			def.on_mode_change(self, new_mode)
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
