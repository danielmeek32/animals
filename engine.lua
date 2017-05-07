--= Animals mod =--
-- Copyright (c) 2017 Daniel <https://github.com/danielmeek32>
--
-- engine.lua
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--

-- check if an item is in a list of items
local function check_item(item_name, item_list)
	for _, name in ipairs(item_list) do
		if name == item_name then
			return true
		end
	end
	return false
end

-- choose a random interval in a range
-- If min_interval and max_interval are non-nil, a random interval between min_interval and max_interval is chosen.
-- If min_interval and max_interval are nil, interval is returned.
-- Note that interval may be nil if both min_interval and max_interval are non-nil, otherwise interval is required to be non-nil.
local function generate_interval(min_interval, max_interval, interval)
	if min_interval and max_interval then
		local result = math.random() * (max_interval - min_interval) + min_interval
		if result > max_interval then
			return max_interval
		elseif result < min_interval then
			return min_interval
		else
			return result
		end
	else
		return interval
	end
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

-- get the correct speed for the current mode
local function get_target_speed(self)
	if self.mode == "follow" then
		if self.autofollowing == true and self.target and vector.distance(self.object:getpos(), self.target:getpos()) < self.parameters.follow_stop_distance then
			return 0
		else
			return self.parameters.follow_speed
		end
	else
		return self.modes[self.mode].moving_speed or 0
	end
end

-- set the current animation
local function set_animation(self, animation)
	self.object:set_animation({x = animation.start, y = animation.stop}, animation.speed, 0, animation.loop)
end

-- produce particles
local function spawn_particles(self, amount, time, position_offset, texture)
	local position = self.object:getpos()
	position.y = position.y + position_offset
	minetest.add_particlespawner({
		amount = amount,
		time = time,
		minpos = vector.add(position, -0.75),
		maxpos = vector.add(position, 0.75),
		minvel = vector.new(-0.1, 0, -0.1),
		maxvel = vector.new(0.1, 0, 0.1),
		minacc = vector.new(),
		maxacc = vector.new(),
		minexptime = 0.75,
		maxexptime = 1,
		minsize = 1,
		maxsize = 2.5,
		texture = texture,
	})
end

-- change the direction
-- If new_direction is nil, randomly chooses a new direction for the mob and sets it as the current direction.
-- If new_direction is non-nil, sets the current direction to new_direction. If the current mode requests that the mob is moving, it will begin moving at the mode's speed in the new direction. If the current mode requests that the mob is stationary, it will remain stationary while visually changing the direction that it is facing. Note that the mob's actual speed is ignored; only the speed according to the current mode is used.
local function change_direction(self, new_direction)
	if new_direction == nil then
		-- randomly choose a new direction
		local selected_direction = math.random() * math.pi * 2
		change_direction(self, selected_direction)
	else
		local speed = get_target_speed(self)

		-- update the mob
		if speed > 0 then
			-- move in the new direction
			self.object:setvelocity({x = -math.sin(new_direction) * speed, y = self.object:getvelocity().y, z = math.cos(new_direction) * speed})
		else
			-- the mob is not supposed to be moving, so stop it and set the yaw manually (allows the displayed direction to change even when the mob is stationary)
			self.object:setvelocity({x = 0, y = self.object:getvelocity().y, z = 0})
			self.object:setyaw(new_direction)
		end
	end
end

-- change the mode
-- If new_mode is nil, randomly selects a mode that is valid in the current mob state and sets it as the current mode.
-- If new_mode is non-nil, sets the current mode to new_mode. new_mode must refer to a mode that exists, and should be valid for the current mob state.
local function change_mode(self, new_mode)
	if new_mode == nil then
		local selected_mode

		local valid = false
		while valid == false do
			-- randomly choose a new mode
			local random = math.random()
			local total = 0
			for name, mode in pairs(self.modes) do
				total = total + mode.chance
				if random <= total then
					selected_mode = name
					break
				end
			end

			-- check that the new mode is valid
			valid = true
			if selected_mode == "eat" then
				if self.in_water == true then
					valid = false
				else
					local node_pos = self.object:getpos()
					node_pos.y = node_pos.y - 0.5
					local node = minetest.get_node_or_nil(node_pos)
					valid = false
					for _, name in pairs(self.parameters.eat_nodes) do
						if node and name == node.name then
							valid = true
							break
						end
					end
				end
			end
		end

		-- change the mode to the selected mode
		change_mode(self, selected_mode)
	else
		-- set mode to requested mode
		local previous_mode = self.mode
		self.mode = new_mode

		-- reset timers
		if self.mode ~= "follow" and ((self.modes[self.mode].min_duration and self.modes[self.mode].max_duration) or self.modes[self.mode].duration) then
			self.mode_timer = generate_interval(self.modes[self.mode].min_duration, self.modes[self.mode].max_duration, self.modes[self.mode].duration)
		end
		if self.mode ~= "follow" and ((self.modes[self.mode].min_direction_change_interval and self.modes[self.mode].max_direction_change_interval) or self.modes[self.mode].direction_change_interval) then
			self.direction_change_timer = generate_interval(self.modes[self.mode].min_direction_change_interval, self.modes[self.mode].max_direction_change_interval, self.modes[self.mode].direction_change_interval)
		end
		if self.mode == "follow" then
			self.follow_timer = 0.5 + 0.1	-- 0.5 is the follow_timer timeout, this is used here rather than 0 so that the mob will immediately seek out a path to the target instead of waiting for the timeout to elapse
		end
		if self.sounds[self.mode] and ((self.sounds[self.mode].min_interval and self.sounds[self.mode].max_interval) or self.sounds[self.mode].interval) then
			self.sound_timer = generate_interval(self.sounds[self.mode].min_interval, self.sounds[self.mode].max_interval, self.sounds[self.mode].interval)
		end

		-- set speed
		local speed = get_target_speed(self)
		if speed > 0 then
			-- get current direction
			local direction = self.object:getyaw()
			-- move in the current direction at the calculated speed
			self.object:setvelocity({x = -math.sin(direction) * speed, y = self.object:getvelocity().y, z = math.cos(direction) * speed})
		else
			-- stop moving
			self.object:setvelocity({x = 0, y = self.object:getvelocity().y, z = 0})
		end

		-- set animation
		local animation = self.animations[self.mode]
		if self.in_water and self.animations["swim"] then
			animation = self.animations["swim"]
		end
		set_animation(self, animation)

		-- update the eaten node
		if self.eat_node then
			-- get the node
			local node = minetest.get_node_or_nil(self.eat_node)

			if node then
				-- determine the correct replacement node
				local node_def = minetest.registered_nodes[node.name]
				local replacement_name = node.name
				if node_def then
					 if node_def.drop and type(node_def.drop) == "string" then
						 replacement_name = node_def.drop
					 elseif not node_def.walkable then
						 replacement_name = "air"
					 end
				end

				-- replace the node
				if replacement_name and replacement_name ~= node.name and minetest.registered_nodes[replacement_name] then
					minetest.set_node(self.eat_node, {name = replacement_name})
					if node_def.sounds and node_def.sounds.dug then
						minetest.sound_play(node_def.sounds.dug, {pos = self.eat_node, max_hear_distance = 5, gain = 1})
					end
				end

				-- call the eat callback
				self.on_eat(self, node.name)
			end

			self.eat_node = nil
		end

		-- get the node which will be eaten when the mode changes again
		if self.mode == "eat" then
			local node_pos = self.object:getpos()
			node_pos.y = node_pos.y - 0.5
			local node = minetest.get_node_or_nil(node_pos)
			for _, name in pairs(self.parameters.eat_nodes) do
				if node and node.name == name then
					self.eat_node = node_pos
					break
				end
			end
		end

		-- change direction if required
		if previous_mode == "follow" or (self.modes[self.mode] and self.modes[self.mode].change_direction_on_mode_change == true) then	-- the direction is changed when leaving follow mode otherwise the mob might keep walking in the same direction as before
			change_direction(self)
		else
			change_direction(self, self.object:getyaw())
		end

		-- play sound if required
		if self.sounds[self.mode] and self.sounds[self.mode].play_on_mode_change == true then
			self:play_sound(self.mode)
		end

		-- call mode change callback
		self.on_mode_change(self, self.mode)
	end
end

-- calculate a polar direction from a direction vector
-- The y component is ignored and the direction is calculated using the x and z components as if the vector was two-dimensional.
local function get_polar_direction(direction)
	if direction.x == 0 then
		if direction.z > 0 then
			return 0
		elseif direction.z < 0 then
			return math.pi
		else
			return 0
		end
	elseif direction.z == 0 then
		if direction.x > 0 then
			return math.pi * 1.5
		elseif direction.x < 0 then
			return math.pi * 0.5
		else
			return 0
		end
	else
		if direction.x < 0 and direction.z > 0 then
			return math.atan(math.abs(direction.x) / math.abs(direction.z))
		elseif direction.x < 0 and direction.z < 0 then
			return math.atan(math.abs(direction.z) / math.abs(direction.x)) + math.pi * 0.5
		elseif direction.x > 0 and direction.z < 0 then
			return math.atan(math.abs(direction.x) / math.abs(direction.z)) + math.pi
		elseif direction.x > 0 and direction.z > 0 then
			return math.atan(math.abs(direction.z) / math.abs(direction.x)) + math.pi * 1.5
		else
			return 0
		end
	end
end

-- default on_step callback
local function default_on_step(self, dtime)
	-- timer updates
	self.life_timer = self.life_timer + dtime
	if self.breed_cooldown_timer > 0 then	-- prevents the timer from wrapping around over long periods of time
		self.breed_cooldown_timer = self.breed_cooldown_timer - dtime
	end

	self.mode_timer = self.mode_timer - dtime
	self.direction_change_timer = self.direction_change_timer - dtime
	self.search_timer = self.search_timer + dtime
	self.follow_timer = self.follow_timer + dtime
	self.sound_timer = self.sound_timer - dtime
	self.swim_timer = self.swim_timer + dtime
	if self.breed_timer > 0 then	-- prevents the timer from wrapping around over long periods of time
		self.breed_timer = self.breed_timer - dtime
	end

	-- despawn if life timer has expired
	if self.life_timer > self.parameters.life_time then
		self.life_timer = 0
		if self.tamed == false then
			self.object:remove()
		end
	end

	-- breed if in breeding mode and a mate is nearby
	if self.parameters.breed_items and self.tamed and self.breed_timer > 0 then
		local mates = self:find_objects(self.parameters.breed_distance, self.mob_name, false)
		if #mates >= 1 then
			for _, mate in ipairs(mates) do
				local mate_entity = mate:get_luaentity()
				if mate_entity.tamed and mate_entity.breed_timer > 0 then	-- check that the mate is ready to breed
					if self.on_breed(self, mate_entity) == true and mate_entity.on_breed(mate_entity, self) == true then	-- call self and mate's breed callbacks and check that they both return true
						-- create the child
						local child = minetest.add_entity(self.object:getpos(), self.mob_name)

						-- set the child properties
						local child_entity = child:get_luaentity()
						child_entity.tamed = true
						child_entity.owner_name = self.owner_name
						child_entity.breed_cooldown_timer = self.parameters.breed_cooldown_time	-- prevents the child from being able to breed immediately

						-- disable breeding mode for self and mate
						self.breed_timer = 0
						mate_entity.breed_timer = 0

						break
					end
				end
			end
		end

		-- show that breed mode is active
		spawn_particles(self, 1, 0.25, 1.0, "heart.png")
	end

	-- update current node
	local node_pos = self.object:getpos()
	node_pos.y = node_pos.y + 0.25
	self.current_node = minetest.get_node(node_pos)

	-- handle water
	if self.current_node.name == "default:water_source" or self.current_node.name == "default:water_flowing" or self.current_node.name == "default:river_water_source" or self.current_node.name == "default:river_water_flowing" then
		if self.in_water == false then
			self.in_water = true
			self.swim_timer = 0

			-- set animation
			if self.animations["swim"] then
				set_animation(self, self.animations["swim"])
			end

			-- set acceleration for in water
			self.object:setacceleration({x = 0, y = -0.25, z = 0})
		end
		if self.swim_timer > 0.25 then
			self.swim_timer = 0

			-- set velocity to produce bobbing effect
			local velocity = self.object:getvelocity()
			self.object:setvelocity({x = velocity.x, y = 0.75, z = velocity.z})

			-- play swimming sounds
			self:play_sound("swim")

			-- show particles
			spawn_particles(self, 10, 0.25, 0, "bubble.png")
		end
	else
		if self.in_water == true then
			self.in_water = false

			-- set animation
			if self.animations["swim"] then
				set_animation(self, self.animations[self.mode])
			end

			-- set acceleration for on land
			self.object:setacceleration({x = 0, y = -15, z = 0})
		end
	end

	-- change mode randomly
	if self.mode == "" or (self.mode ~= "follow" and ((self.modes[self.mode].min_duration and self.modes[self.mode].max_duration) or self.modes[self.mode].duration) and self.mode_timer <= 0) then
		change_mode(self)
	end

	-- change direction randomly
	if self.mode ~= "follow" and ((self.modes[self.mode].min_direction_change_interval and self.modes[self.mode].max_direction_change_interval) or self.modes[self.mode].direction_change_interval) and self.direction_change_timer <= 0 then
		self.direction_change_timer = generate_interval(self.modes[self.mode].min_direction_change_interval, self.modes[self.mode].max_direction_change_interval, self.modes[self.mode].direction_change_interval)
		change_direction(self)
	end

	-- determine if the mob is stuck
	if get_target_speed(self) > 0 then
		local velocity = self.object:getvelocity()
		velocity.y = 0
		local actual_speed = vector.length(velocity)
		local target_speed = get_target_speed(self)
		if actual_speed < target_speed - 0.1 then
			self.stuck = true
		else
			local node_pos = self.object:getpos()
			node_pos.y = node_pos.y + 0.5
			local direction = self.object:getyaw()
			node_pos.x = node_pos.x + (-math.sin(direction) * 0.5)
			node_pos.z = node_pos.z + (math.cos(direction) * 0.5)
			local next_node1 = minetest.get_node(node_pos)
			node_pos.y = node_pos.y - 1.0
			local next_node2 = minetest.get_node(node_pos)
			node_pos.y = node_pos.y - 1.0
			local next_node3 = minetest.get_node(node_pos)
			if next_node1.name == "air" and next_node2.name == "air" and next_node3.name == "air" then
				self.stuck = true
			else
				self.stuck = false
			end
		end
	else
		self.stuck = false
	end

	-- perform actions for random modes
	if self.mode ~= "follow" then
		-- change direction if stuck
		if self.stuck == true then
			change_direction(self)
		end

		-- look for a target to follow
		if self.parameters.follow_items then
			if self.search_timer > 0.5 then
				self.search_timer = 0
				local targets
				if self.tamed then
					targets = self:find_objects(self.parameters.follow_distance, "owner", false)
				else
					targets = self:find_objects(self.parameters.follow_distance, "player", false)
				end
				local target = nil
				if #targets > 1 then
					target = targets[math.random(1, #targets)]
				elseif #targets == 1 then
					target = targets[1]
				end
				if target ~= nil then
					local item_name = target:get_wielded_item():get_name()
					if item_name and check_item(item_name, self.parameters.follow_items) == true then
						self.target = target
						self.autofollowing = true
						change_mode(self, "follow")
					end
				end
			end
		end
	end

	-- perform actions for follow mode (this can't be an else clause because follow mode may have been enabled in the previous block)
	if self.mode == "follow" then
		if self.target and self.follow_timer > 0.5 then
			self.follow_timer = 0

			-- get the distance and direction to the target
			local my_pos = self.object:getpos()
			local target_pos = self.target:getpos()
			local direction = vector.direction(my_pos, target_pos)
			direction.y = 0
			direction = vector.normalize(direction)
			local distance = vector.distance(my_pos, target_pos)

			-- stop following if autofollowing and the target is out of range or is no longer wielding the correct item
			if self.autofollowing == true then
				local item_name = self.target:get_wielded_item():get_name()
				if distance > self.parameters.follow_distance or (item_name and check_item(item_name, self.parameters.follow_items) == false) then
					change_mode(self)
				end
			end

			if self.mode == "follow" then	-- detects if the current mode was changed in the previous block
				-- update the direction
				local polar_direction = get_polar_direction(direction)
				change_direction(self, polar_direction)

				-- update the animation
				local speed = get_target_speed(self)
				if speed > 0 then
					local animation = self.animations["follow"]
					if self.in_water and self.animations["swim"] then
						animation = self.animations["swim"]
					end
					set_animation(self, animation)
				else
					set_animation(self, self.animations["idle"])
				end
			end
		end
	end

	-- play random sounds
	if self.sounds[self.mode] and ((self.sounds[self.mode].min_interval and self.sounds[self.mode].max_interval) or self.sounds[self.mode].interval) and self.sound_timer <= 0 then
		self.sound_timer = generate_interval(self.sounds[self.mode].min_interval, self.sounds[self.mode].max_interval, self.sounds[self.mode].interval)
		self:play_sound(self.mode)
	end
end

-- default on_punch callback
local function default_on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
	-- calculate damage (see minetest lua_api.txt)
	local damage = 0
	if tool_capabilities and time_from_last_punch then
		local armor_groups = self.object:get_armor_groups()
		for group_name in pairs(tool_capabilities.damage_groups) do
			damage = damage + (tool_capabilities.damage_groups[group_name] or 0) * math.min(math.max(time_from_last_punch / tool_capabilities.full_punch_interval, 0.0), 1.0) * ((armor_groups[group_name] or 0) / 100.0)
		end
	end

	-- change hp
	local hp = self.object:get_hp()
	hp = hp - damage
	hp = math.floor(hp)	--make sure hp is an integer
	self.object:set_hp(hp)

	if hp > 0 then
		-- show damage

		-- make the mob jump into the air
		local velocity = self.object:getvelocity()
		self.object:setvelocity({x = velocity.x, y = velocity.y + 5.0, z = velocity.z})

		-- change to panic mode
		change_mode(self, "panic")

		-- flash red
		self.object:settexturemod("^[colorize:#C000007F")
		minetest.after(0.5, function()
			self.object:settexturemod("")
		end)

		-- play damage sound
		self:play_sound("damage")
	else
		-- perform death actions

		-- change to death mode
		change_mode(self, "death")

		-- allow the mob to be passed through
		self.object:set_properties({collide_with_objects = false, collisionbox = {x = 0, y = 0, z = 0}})

		-- play death sound
		self:play_sound("death")

		-- remove the mob after the death duration
		minetest.after(self.parameters.death_duration, function()
			self.object:remove()
		end)

		-- drop drops
		if self.drops then
			local drops
			if type(self.drops) == "function" then
				drops = self.drops(self)
			elseif type(self.drops) == "table" then
				drops = self.drops
			end
			self:drop_items(drops)
		end

		-- call die callback
		self.on_die(self)
	end

	-- add wear to tools
	if puncher then
		if not minetest.setting_getbool("creative_mode") then
			local item = puncher:get_wielded_item()
			if item and tool_capabilities and tool_capabilities.damage_groups and tool_capabilities.damage_groups.fleshy then
				-- get the maximum uses from the most efficient node group (since there's no uses field for entity damage groups)
				local best_uses = 0
				for name, value in pairs(tool_capabilities.groupcaps) do
					local uses = value.uses * (3 ^ (value.maxlevel or 0))	-- see minetest lua_api.txt
					if uses > best_uses then
						best_uses = uses
					end
				end

				-- calculate and apply wear
				if best_uses > 0 then
					local wear = 65536 / best_uses
					item:add_wear(wear)
					puncher:set_wielded_item(item)
				end
			end
		end
	end
end

-- default on_rightclick callback
local function default_on_rightclick(self, clicker)
	local item = clicker:get_wielded_item()
	if item then
		local item_name = item:get_name()
		if item_name then
			if self.tamed == false then
				-- tame mob
				if self.parameters.tame_items and check_item(item_name, self.parameters.tame_items) == true then
					if self.on_tame(self, clicker:get_player_name()) then	-- check that the tame callback returns true
						-- set properties
						self.tamed = true
						self.owner_name = clicker:get_player_name()

						-- show that the mob has been tamed
						spawn_particles(self, 10, 1, 1.0, "heart.png")

						-- remove the item used to tame the mob
						if not minetest.setting_getbool("creative_mode") then
							item:take_item()
							clicker:set_wielded_item(item)
						end
					end
				end
			else
				-- put mob into breeding mode
				if self.parameters.breed_items and check_item(item_name, self.parameters.breed_items) == true and self.breed_cooldown_timer <= 0 then
					-- reset the breeding cooldown timer
					self.breed_cooldown_timer = self.parameters.breed_cooldown_time

					-- enable breeding mode
					self.breed_timer = self.parameters.breed_time

					-- remove the item used to breed the mob
					if not minetest.setting_getbool("creative_mode") then
						item:take_item()
						clicker:set_wielded_item(item)
					end
				end
			end
		end
	end
end

-- default get_staticdata callback
local function default_get_staticdata(self)
	return {
		hp = self.object:get_hp(),
		tamed = self.tamed,
		owner_name = self.owner_name,

		life_timer = self.life_timer,
		breed_cooldown_timer = self.breed_cooldown_timer,
	}
end

-- create an entity def from a mob def
local function get_entity_def(mob_def)
	local entity_def = {
		physical = true,
		stepheight = 1.1,
		makes_footstep_sound = not mob_def.parameters.silent,

		visual = "mesh",
		mesh = mob_def.model.mesh,
		backface_culling = true,
		visual_size = mob_def.model.scale or {x = 1, y = 1},
		textures = mob_def.model.textures,
		automatic_face_movement_dir = mob_def.model.rotation or 0.0,
		collide_with_objects = mob_def.model.collide_with_objects or false,
		collisionbox = mob_def.model.collisionbox or {-0.25, 0, -0.25, 0.25, 1.25, 0.25},

		mob_name = mob_def.name,
		parameters = mob_def.parameters,
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
		panic_mode.moving_speed = mob_def.parameters.panic_speed or entity_def.modes["walk"].moving_speed * 2
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
		duration = mob_def.parameters.death_duration,
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
			change_mode(self, new_mode)
		end
		self.choose_random_mode = function(self)
			change_mode(self)
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
			change_mode(self, "follow")
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

		self.object:set_hp(staticdata_table.hp or mob_def.parameters.hp)
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
		default_on_step(self, dtime)
	end

	entity_def.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if mob_def.on_punch and mob_def.on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir) == true then
			return
		end
		default_on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir)
	end

	entity_def.on_rightclick = function(self, clicker)
		if self.tamed and clicker:get_player_name() ~= self.owner_name then
			return
		end
		if mob_def.on_rightclick and mob_def.on_rightclick(self, clicker) == true then
			return
		end
		default_on_rightclick(self, clicker)
	end

	entity_def.get_staticdata = function(self)
		local data = default_get_staticdata(self)
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

function animals.register(mob_def)
	local entity_def = get_entity_def(mob_def)

	-- register entity
	minetest.register_entity(":" .. mob_def.name, entity_def)

	-- register abm for spawning
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
				if check_space(pos, entity_def.collisionbox) == true then
					-- spawn a single mob
					minetest.add_entity({x = pos.x, y = pos.y + 1, z = pos.z}, mob_def.name)
				end
			elseif count > 1 then
				local spawn_area = mob_def.spawning.spawn_area

				-- find surrounding nodes to spawn on
				local nodes = minetest.find_nodes_in_area({x = pos.x - spawn_area, y = pos.y - spawn_area, z = pos.z - spawn_area}, {x = pos.x + spawn_area, y = pos.y + spawn_area, z = pos.z + spawn_area}, mob_def.spawning.nodes)
				local valid_nodes = {}
				for _, node in ipairs(nodes) do
					if check_space(node, entity_def.collisionbox) == true then
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
