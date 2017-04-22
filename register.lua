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
		animations = mob_def.animations,
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
	if not entity_def.animations["panic"] then
		local panic_animation = table.copy(entity_def.animations["walk"])
		panic_animation.speed = panic_animation.speed * (entity_def.modes["panic"].moving_speed / entity_def.modes["walk"].moving_speed)
		entity_def.animations["panic"] = panic_animation
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

-- check that there's enough space around the given position for the given collisionbox to fit
local function check_space(pos, collisionbox)
	for x = collisionbox[1], collisionbox[4] do
		for y = collisionbox[2], collisionbox[5] do
			for z = collisionbox[3], collisionbox[6] do
				if minetest.get_node({x = pos.x + x, y = pos.y + y + 1, z = pos.z + z}).name ~= "air" then
					return false
				end
			end
		end
	end
	return true
end

function animals.registerMob(mob_def)
	-- register entity
	minetest.register_entity(":" .. mob_def.name, get_entity_def(mob_def))

	-- register abm
	minetest.register_abm({
		nodenames = mob_def.spawning.nodes,
		neighbours = {"air"},
		interval = mob_def.spawning.interval,
		chance = mob_def.spawning.chance,
		catch_up = false,
		action = function(pos, node, active_object_count, active_object_count_wider)
			-- check time
			local timeofday = minetest.get_timeofday() * 24000
			if mob_def.spawning.min_time and mob_def.spawning.max_time and (timeofday < mob_def.spawning.min_time or timeofday > mob_def.spawning.max_time) then
				return
			end

			-- check height
			if mob_def.spawning.min_height and mob_def.spawning.max_height and (pos.y < mob_def.spawning.min_height or pos.y > mob_def.spawning.max_height) then
				return
			end

			-- check light
			local light = minetest.get_node_light({x = pos.x, y = pos.y + 1, z = pos.z})
			if mob_def.spawning.min_light and mob_def.spawning.max_light and (light < mob_def.spawning.min_light or light > mob_def.spawning.max_light) then
				return
			end

			-- check surrounding mob count
			if mob_def.spawning.surrounding_distance and mob_def.spawning.max_surrounding_count then
				local objects = minetest.get_objects_inside_radius(pos, mob_def.spawning.surrounding_distance)
				local object_count = 0
				for _, object in ipairs(objects) do
					local entity = object:get_luaentity()
					if entity and entity.mob_name == mob_def.name then
						object_count = object_count + 1
					end
				end
				if object_count > mob_def.spawning.max_surrounding_count then
					return
				end
			end

			-- choose a spawn count
			local count
			if mob_def.spawning.min_spawn_count and mob_def.spawning.max_spawn_count then
				count = math.random(mob_def.spawning.min_spawn_count, mob_def.spawning.max_spawn_count)
			else
				count = mob_def.spawning.spawn_count
			end

			if count == 1 then
				-- check space
				if check_space(pos, mob_def.model.collisionbox) == true then
					-- spawn a single mob
					minetest.add_entity({x = pos.x, y = pos.y + 1, z = pos.z}, mob_def.name)
				end
			elseif count > 1 then
				local spawn_area = mob_def.spawning.spawn_area

				-- find surrounding nodes to spawn on
				local nodes = minetest.find_nodes_in_area({x = pos.x - spawn_area, y = pos.y - spawn_area, z = pos.z - spawn_area}, {x = pos.x + spawn_area, y = pos.y + spawn_area, z = pos.z + spawn_area}, mob_def.spawning.nodes)
				local valid_nodes = {}
				for _, node in ipairs(nodes) do
					if check_space(node, mob_def.model.collisionbox) == true then
						table.insert(valid_nodes, node)
					end
				end

				-- determine final spawn count
				if count > #valid_nodes then
					count = #valid_nodes
				end

				-- spawn mobs
				for completed = 1, count do
					-- choose a random node from the list
					local node_index = math.random(1, #valid_nodes)

					-- spawn the mob
					minetest.add_entity({x = valid_nodes[node_index].x, y = valid_nodes[node_index].y + 1, z = valid_nodes[node_index].z}, mob_def.name)

					-- remove the node from the list so that each node is only used once
					table.remove(valid_nodes, node_index)
				end
			end
		end,
	})
end
