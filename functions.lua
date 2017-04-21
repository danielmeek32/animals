--= Animals mod =--
-- Copyright (c) 2016 Daniel <https://github.com/danielmeek32>
--
-- Modified from Creatures MOB-Engine (cme)
-- Copyright (c) 2015 BlockMen <blockmen2015@gmail.com>
--
-- functions.lua
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

-- TODO: which functions should be local?
-- TODO: sounds
-- TODO: finish adding api calls (e.g. is_tamed(), get_owner_name(), is_following(), get_target(), get_position(), play_sound(), etc.)
-- TODO: spawning

local update_animation

-- get the correct speed for the current mode
local function get_target_speed(self)
	if self.mode == "follow" then
		if self.autofollowing == true and self.target and vector.distance(self.object:getpos(), self.target:getpos()) < self.stats.follow_stop_distance then
			return 0
		else
			return self.stats.follow_speed
		end
	else
		return self.modes[self.mode].moving_speed or 0
	end
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
-- If new_mode is non-nil, sets the current mode to new_mode. new_mode must refer to a mode that exists, and should be valid for the current mov state.
local function change_mode(self, new_mode)
	if new_mode == nil then
		local selected_mode

		local valid = false
		while valid == false do
			-- randomly choose a new mode
			selected_mode = animals.rnd(self.modes)

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
					for _, name in pairs(self.stats.eat_nodes) do
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
		self.mode_timer = 0
		self.direction_change_timer = 0
		self.follow_timer = 0.5 + 0.1	-- 0.5 is the follow_timer timeout, this is used here rather than 0 so that the mob will immediately seek out a path to the target instead of waiting for the timeout to elapse
		-- TODO: sound timer

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
		local anim_def = self.model.animations[self.mode]
		if self.in_water and self.model.animations["swim"] then
			anim_def = self.model.animations["swim"]
		end
		update_animation(self.object, anim_def)

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
			for _, name in pairs(self.stats.eat_nodes) do
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

		-- call mode change callback
		self.on_mode_change(self, self.mode)
	end
end

animals.change_mode = change_mode	-- TODO: this shouldn't be in the animals namespace

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

--

update_animation = function(obj_ref, anim_def)
	if anim_def and obj_ref then
		obj_ref:set_animation({x = anim_def.start, y = anim_def.stop}, anim_def.speed, 0, anim_def.loop)
	end
end

local function check_wielded(wielded, item_list)
	for s,w in pairs(item_list) do
		if w == wielded then
			return true
		end
	end
	return false
end

spawn_particles = function(pos, velocity, texture_str)
	local vel = vector.multiply(velocity, 0.5)
	vel.y = 0
	core.add_particlespawner({
		amount = 8,
		time = 1,
		minpos = vector.add(pos, -0.7),
		maxpos = vector.add(pos, 0.7),
		minvel = vector.add(vel, {x = -0.1, y = -0.01, z = -0.1}),
		maxvel = vector.add(vel, {x = 0.1, y = 0, z = 0.1}),
		minacc = vector.new(),
		maxacc = vector.new(),
		minexptime = 0.8,
		maxexptime = 1,
		minsize = 1,
		maxsize = 2.5,
		texture = texture_str,
	})
end

-- --
-- Default entity functions
-- --

animals.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
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
	hp = math.ceil(hp)	--make sure hp is an integer
	self.object:set_hp(hp)

	-- show damage/death
	if hp > 0 then
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
		if self.sounds and self.sounds.on_damage then
			minetest.sound_play(self.sounds.on_damage.name, {pos = self.object:getpos(), max_hear_distance = self.sounds.on_damage.distance or 5, gain = self.sounds.on_damage.gain or 1})
		end
	else
		-- change to death mode
		change_mode(self, "death")

		-- allow the mob to be passed through
		self.object:set_properties({collisionbox = {x = 0, y = 0, z = 0}})

		-- play death sound
		if self.sounds and self.sounds.on_death then
			minetest.sound_play(self.sounds.on_death.name, {pos = self.object:getpos(), max_hear_distance = self.sounds.on_death.distance or 5, gain = self.sounds.on_death.gain or 1})
		end

		-- remove the mob after the death duration
		minetest.after(self.stats.death_duration, function()
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
			animals.dropItems(self.object:getpos(), drops)
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

animals.on_rightclick = function(self, clicker)
	local item = clicker:get_wielded_item()
	if item then
		local item_name = item:get_name()
		if item_name then
			if self.tamed == false then
				-- tame mob
				if self.stats.tame_items and check_wielded(item_name, self.stats.tame_items) then
					if self.on_tame(slef, clicker:get_player_name()) then	-- check that the tame callback returns true
						-- set properties
						self.tamed = true
						self.owner_name = clicker:get_player_name()

						-- show that the mob has been tamed
						local pos = self.object:getpos()
						spawn_particles({ x = pos.x, y = pos.y + 1.0, z = pos.z }, { x = 0, y = 1.0, z = 0 }, "heart.png")

						-- remove the item used to tame the mob
						if not minetest.setting_getbool("creative_mode") then
							item:take_item()
							clicker:set_wielded_item(item)
						end
					end
				end
			else
				-- put mob into breeding mode
				if self.stats.breed_items and self.breed_cooldown_timer <= 0 then
					-- reset the breeding cooldown timer
					self.breed_cooldown_timer = self.stats.breed_cooldown_time

					-- enable breeding mode
					self.breed_timer = self.stats.breed_time

					-- remove the item used to breed the mob
					if self.stats.breed_items and check_wielded(name, self.stats.breed_items) then
						if not minetest.setting_getbool("creative_mode") then
							item:take_item()
							clicker:set_wielded_item(item)
						end
					end
				end
			end
		end
	end
end

animals.on_step = function(self, dtime)
	-- timer updates
	self.life_timer = self.life_timer + dtime
	if self.breed_cooldown_timer > 0 then	-- prevents the timer from wrapping around over long periods of time
		self.breed_cooldown_timer = self.breed_cooldown_timer - dtime
	end

	self.mode_timer = self.mode_timer + dtime
	self.direction_change_timer = self.direction_change_timer + dtime
	self.search_timer = self.search_timer + dtime
	self.follow_timer = self.follow_timer + dtime
	self.sound_timer = self.sound_timer + dtime
	self.swim_timer = self.swim_timer + dtime
	if self.breed_timer > 0 then	-- prevents the timer from wrapping around over long periods of time
		self.breed_timer = self.breed_timer - dtime
	end

	-- despawn if life timer has expired
	if self.life_timer > self.stats.life_time then
		self.life_timer = 0
		if self.tamed == false then
			self.object:remove()
		end
	end

	-- breed if in breeding mode and a mate is nearby
	if self.stats.breed_items and self.tamed and self.breed_timer > 0 then
		local mates = animals.findTarget(self.object, self.object:getpos(), self.stats.breed_distance, self.mob_name, self.owner_name, false)
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
						child_entity.breed_cooldown_timer = self.stats.breed_cooldown_time	-- prevents the child from being able to breed immediately

						-- disable breeding mode for self and mate
						self.breed_timer = 0
						mate_entity.breed_timer = 0

						break
					end
				end
			end
		end

		-- show that breed mode is active
		local pos = self.object:getpos()
		spawn_particles({ x = pos.x, y = pos.y + 1.0, z = pos.z }, { x = 0, y = 1.0, z = 0 }, "heart.png")
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
			self.object:setacceleration({x = 0, y = -0.25, z = 0})	-- set acceleration for in water
		end
		if self.swim_timer > 0.25 then
			self.swim_timer = 0

			-- set velocity to produce bobbing effect
			local vel = self.object:getvelocity()
			self.object:setvelocity({x = vel.x, y = 0.75, z = vel.z})

			-- play swimming sounds
			if self.sounds and self.sounds.swim then
				local swim_snd = self.sounds.swim
				minetest.sound_play(swim_snd.name, {pos = self.object:getpos(), gain = swim_snd.gain or 1, max_hear_distance = swim_snd.distance or 10})
			end
			spawn_particles(self.object:getpos(), vel, "bubble.png")
		end
	else
		if self.in_water == true then
			self.in_water = false
			self.object:setacceleration({x = 0, y = -15, z = 0})	-- set acceleration for on land
		end
	end

	-- change mode randomly
	if self.mode == "" or (self.mode ~= "follow" and self.modes[self.mode].duration and self.mode_timer > self.modes[self.mode].duration) then
		change_mode(self)
	end

	-- change yaw randomly
	if self.mode ~= "follow" and self.modes[self.mode].direction_change_interval and self.direction_change_timer > self.modes[self.mode].direction_change_interval then
		self.direction_change_timer = 0
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
			self.stuck = false
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
		if self.stats.follow_items then
			if self.search_timer > 0.5 then
				self.search_timer = 0
				local targets = animals.findTarget(self.object, self.object:getpos(), self.stats.follow_distance, "player", self.owner_name, false)
				local target = nil
				if #targets > 1 then
					target = targets[math.random(1, #targets)]
				elseif #targets == 1 then
					target = targets[1]
				end
				if target ~= nil then
					local item_name = target:get_wielded_item():get_name()
					if item_name and check_wielded(item_name, self.stats.follow_items) == true then
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
				if distance > self.stats.follow_distance or (item_name and check_wielded(item_name, self.stats.follow_items) == false) then
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
					local anim_def = self.model.animations["follow"]
					if self.in_water and self.model.animations["swim"] then
						anim_def = self.model.animations["swim"]
					end
					update_animation(self.object, anim_def)
				else
					update_animation(self.object, self.model.animations["idle"])
				end
			end
		end
	end

--	-- Random sounds
--	if self.sounds and self.sounds.random[self.mode] then
--		local rnd_sound = self.sounds.random[self.mode]
--		if not self.snd_rnd_time then
--			self.snd_rnd_time = math.random((rnd_sound.time_min or 5), (rnd_sound.time_max or 35))
--		end
--		if rnd_sound and self.sound_timer > self.snd_rnd_time + math.random() then
--			self.sound_timer = 0
--			self.snd_rnd_time = nil
--			core.sound_play(rnd_sound.name, {pos = me:getpos(), gain = rnd_sound.gain or 1, max_hear_distance = rnd_sound.distance or 30})
--		end
--	end
end

animals.get_staticdata = function(self)
	return {
		hp = self.object:get_hp(),
		tamed = self.tamed,
		owner_name = self.owner_name,

		life_timer = self.life_timer,
		breed_cooldown_timer = self.breed_cooldown_timer,
	}
end
