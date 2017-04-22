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

local function get_entity_def(mob_def)
	local entity_def = {
		physical = true,
		stepheight = 1.1,
		makes_footstep_sound = not mob_def.stats.silent,

		visual = "mesh",
		mesh = mob_def.model.mesh,
		backface_culling = true,
		visual_size = mob_def.model.scale or {x = 1, y = 1},
		textures = mob_def.model.textures,
		automatic_face_movement_dir = mob_def.model.rotation or 0.0,
		collide_with_objects = mob_def.model.collide_with_objects or true,
		collisionbox = mob_def.model.collisionbox or {-0.4, 0, -0.4, 0.4, 1.25, 0.4},

		mob_name = mob_def.name,
		stats = mob_def.stats,
		model = mob_def.model,
		sounds = mob_def.sounds,
		modes = mob_def.modes,
		drops = mob_def.drops,
	}

	-- create "panic" mode and animations if they don't already exist
	if not entity_def.modes["panic"] then
		local panic_mode = table.copy(entity_def.modes["walk"])
		panic_mode.chance = 0
		panic_mode.duration = 3
		panic_mode.moving_speed = mob_def.stats.panic_speed or entity_def.modes["walk"].moving_speed * 2
		panic_mode.change_direction_on_mode_change = true
		panic_mode.direction_change_interval = 0.75
		entity_def.modes["panic"] = panic_mode
	end
	if not entity_def.model.animations["panic"] then
		local panic_animation = table.copy(entity_def.model.animations["walk"])
		panic_animation.speed = panic_animation.speed * (entity_def.modes["panic"].moving_speed / entity_def.modes["walk"].moving_speed)
		entity_def.model.animations["panic"] = panic_animation
	end

	-- create "death" mode (overwriting any existing mode with the same)
	local death_mode = {
		chance = 0,
		duration = mob_def.stats.death_duration,
		moving_speed = 0,
	}
	entity_def.modes["death"] = death_mode

	-- add convenience wrappers for mob callbacks

	entity_def.on_mode_change = function(self, new_mode)
		if mob_def.on_mode_change then
			mob_def.on_mode_change(self, new_mode)
		end
	end

	entity_def.on_eat = function(self, node_name)
		if mob_def.on_eat then
			mob_def.on_eat(self, node_name)
		end
	end

	entity_def.on_die = function(self)
		if mob_def.on_die then
			mob_def.on_die(self)
		end
	end

	entity_def.on_tame = function(self, owner_name)
		if mob_def.on_tame then
			return mob_def.on_tame(self, owner_name)
		else
			return true
		end
	end

	entity_def.on_breed = function(self, mate)
		if mob_def.on_breed then
			return mob_def.on_breed(self, mate)
		else
			return true
		end
	end

	-- add functions

	entity_def.on_activate = function(self, staticdata)
		-- add api calls
		-- mode changing and following
		self.get_mode = function(self)
			return self.mode
		end
		self.set_mode = function(self, new_mode)
			animals.change_mode(self, new_mode)	-- TODO: this shouldn't be in the animals namespace
		end
		self.choose_random_mode = function(self)
			animals.change_mode(self)	-- TODO: this shouldn't be in the animals namespace
		end
		self.is_following = function(self)
			if self.mode == "follow" then
				return true
			else
				return false
			end
		end
		self.get_target = function(self)
			return self.target
		end
		self.follow = function(self, target)
			self.target = target
			self.autofollowing = false
			animals.change_mode(self, "follow")
		end
		-- breeding and taming
		self.is_tame = function(self)
			return self.tamed
		end
		self.get_owner_name = function(self)
			return self.owner_name
		end
		-- sounds and drops
		self.play_sound = function(self, sound_name)
			if self.sounds[sound_name] then
				minetest.sound_play(self.sounds[sound_name].name, {object = self.object, max_hear_distance = self.sounds[sound_name].max_hear_distance, gain = self.sounds[sound_name].gain})
			end
		end
		self.drop_items = function(self, items)
			for _, item in ipairs(items) do
				-- decide if the item should be dropped
				local dropping = false
				if item.chance then
					if math.random() <= item.chance then
						dropping = true
					end
				else
					dropping = true
				end

				if dropping == true then
					-- choose quantity
					local quantity
					if item.min and item.max then
						quantity = math.random(item.min, item.max)
					else
						quantity = 1
					end

					-- drop item
					minetest.add_item(self.object:getpos(), item.name .. " " .. quantity)
				end
			end
		end
		-- environment
		self.get_luaentity = function(self)
			return self.object
		end
		self.get_position = function(self)
			return self.object:getpos()
		end
		self.find_objects = function(self, radius, type, xray)
			local objects = {}
			local my_pos = self.object:getpos()
			for _, object in ipairs(minetest.get_objects_inside_radius(my_pos, radius)) do
				if object ~= self.object then
					if xray == true or minetest.line_of_sight(my_pos, object:getpos()) == true then
						if type == "player" and object:is_player() then
							table.insert(objects, object)
						elseif type == "owner" and object:is_player() and self.tamed and object:get_player_name() == self.owner_name then
							table.insert(objects, object)
						else
							local entity = object:get_luaentity()
							if entity and entity.mob_name == type then
								table.insert(objects, object)
							end
						end
					end
				end
			end
			return objects
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
		self.mode = ""	-- initialising with a blank mode will cause the mob to choose a random mode in the first tick
		self.tamed = staticdata_table.tamed or false
		self.owner_name = staticdata_table.owner_name or ""

		-- create timers
		self.life_timer = staticdata_table.life_timer or 0
		self.breed_cooldown_timer = staticdata_table.breed_cooldown_timer or 0
		-- these timers are not saved in the static data
		self.mode_timer = 0
		self.direction_change_timer = 0
		self.search_timer = 0
		self.follow_timer = 0
		self.sound_timer = 0
		self.swim_timer = 0
		self.breed_timer = 0

		-- set acceleration for on land (the mob will detect if it is in water in the first tick and respond appropriately)
		self.in_water = false
		self.object:setacceleration({x = 0, y = -15, z = 0})

		self.object:set_hp(staticdata_table.hp or mob_def.stats.hp)
		self.object:set_armor_groups({fleshy = 100, immortal = 1})	-- immortal is needed to disable automatic damage handling

		-- call custom on_activate if defined
		if mob_def.on_activate then
			mob_def.on_activate(self, staticdata)
		end
	end

	entity_def.on_step = function(self, dtime)
		if mob_def.on_step and mob_def.on_step(self, dtime) == true then
			return
		end
		animals.on_step(self, dtime)
	end

	entity_def.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if mob_def.on_punch and mob_def.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir) == true then
			return
		end
		animals.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
	end

	entity_def.on_rightclick = function(self, clicker)
		if self.tamed and clicker:get_player_name() ~= self.owner_name then
			return
		end
		if mob_def.on_rightclick and mob_def.on_rightclick(self, clicker) == true then
			return
		end
		animals.on_rightclick(self, clicker)
	end

	entity_def.get_staticdata = function(self)
		local data = animals.get_staticdata(self)
		if mob_def.get_staticdata then
			local extra_data = mob_def.get_staticdata(self)
			if extra_data and type(extra_data) == "table" then
				for key, value in pairs(extra_data) do
					data[key] = value
				end
			end
		end
		return minetest.serialize(data)
	end

	return entity_def
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

function animals.registerMob(mob_def)
	if not mob_def or not mob_def.name then
		throw_error("Can't register mob. No name or Definition given.")
		return false
	end

	minetest.register_entity(":" .. mob_def.name, get_entity_def(mob_def))

	-- register spawn
	if mob_def.spawning then
		local spawn_def = mob_def.spawning
		spawn_def.mob_name = mob_def.name
		spawn_def.mob_size = mob_def.model.collisionbox
		if register_spawn(spawn_def) ~= true then
			throw_error("Couldn't register spawning for '" .. mob_def.name .. "'")
		end
	end

	return true
end
