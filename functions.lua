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

local update_animation

local function get_def(self)
	return minetest.registered_entities[self.mob_name]
end

-- get the correct speed for the current mode
local function get_target_speed(self)
	local def = get_def(self)
	if self.mode == "follow" then
		if self.autofollowing == true and self.target and vector.distance(self.object:getpos(), self.target:getpos()) < def.stats.follow_stop_distance then
			return 0
		else
			return def.stats.follow_speed
		end
	else
		return def.modes[self.mode].moving_speed or 0
	end
end

-- change the direction
-- If new_direction is nil, randomly chooses a new direction for the mob and sets it as the current direction.
-- If new_direction is non-nil, sets the current direction to new_direction. If the current mode requests that the mob is moving, it will begin moving at the mode's speed in the new direction. If the current mode requests that the mob is stationary, it will remain stationary while visually changing the direction that it is facing. Note that the mob's actual speed is ignored; only the speed according to the current mode is used.
local function change_direction(self, new_direction)
	local def = get_def(self)

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
	local def = get_def(self)

	if new_mode == nil then
		local selected_mode

		local valid = false
		while valid == false do
			-- randomly choose a new mode
			selected_mode = animals.rnd(def.modes)

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
					for _, name in pairs(def.stats.eat_nodes) do
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
		self.yawtimer = 0
		self.followtimer = 0.6 + 0.1	-- TODO: 0.6 is the followtimer timeout, this is used here rather than 0 so that the mob will immediately seek out a path to the target instead of waiting for the timeout to elapse
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
		local anim_def = def.model.animations[self.mode]
		if self.in_water and def.model.animations["swim"] then
			anim_def = def.model.animations["swim"]
		end
		update_animation(self.object, anim_def)

		-- update the eaten node
		if self.eat_node then
			-- get the node
			local node = minetest.get_node_or_nil(self.eat_node)

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

			self.eat_node = nil
			self.on_eat(self)	-- call the on_eat callback
		end

		-- get the node which will be eaten when the mode changes again
		if self.mode == "eat" then
			local node_pos = self.object:getpos()
			node_pos.y = node_pos.y - 0.5
			local node = minetest.get_node_or_nil(node_pos)
			for _, name in pairs(def.stats.eat_nodes) do
				if node and node.name == name then
					self.eat_node = node_pos
					break
				end
			end
		end

		-- change direction if required
		if previous_mode == "follow" or (def.modes[self.mode] and def.modes[self.mode].change_direction_on_mode_change == true) then	-- the direction is changed when leaving follow mode otherwise the mob might keep walking in the same direction as before
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

local function on_hit(me)
	core.after(0.1, function()
		me:settexturemod("^[colorize:#c4000099")
	end)
	core.after(0.5, function()
		me:settexturemod("")
	end)
end

update_animation = function(obj_ref, anim_def)
	if anim_def and obj_ref then
		obj_ref:set_animation({x = anim_def.start, y = anim_def.stop}, anim_def.speed, 0, anim_def.loop)
	end
end

local function despawn_mob(me)
	if me then
		me:remove()
	end
end

local function kill_mob(me, def)
	if not def then
		despawn_mob(me)
	end
	local pos = me:getpos()
	me:setvelocity({x = 0, y = 0, z = 0})
	me:set_properties({collisionbox = {x = 0, y = 0, z = 0}})
	me:set_hp(0)

	if def.sounds and def.sounds.on_death then
		local death_snd = def.sounds.on_death
		core.sound_play(death_snd.name, {pos = pos, max_hear_distance = death_snd.distance or 5, gain = death_snd.gain or 1})
	end

	if def.model.animations.death then
		local dur = def.model.animations.death.duration or 0.5
		update_animation(me, def.model.animations["death"])
		core.after(dur, function()
			despawn_mob(me)
		end)
	else
		me:remove()
	end
	if def.drops then
		if type(def.drops) == "function" then
			def.drops(me:get_luaentity())
		elseif type(def.drops) == "table" then
			animals.dropItems(pos, def.drops)
		end
	end
end

local function limit(value, min, max)
	if value < min then
		return min
	end
	if value > max then
		return max
	end
	return value
end

local function calc_punch_damage(obj, actual_interval, tool_caps)
	local damage = 0
	if not tool_caps or not actual_interval then
		return 0
	end
	local my_armor = obj:get_armor_groups() or {}
	for group,_ in pairs(tool_caps.damage_groups) do
		damage = damage + (tool_caps.damage_groups[group] or 0) * limit(actual_interval / tool_caps.full_punch_interval, 0.0, 1.0) * ((my_armor[group] or 0) / 100.0)
	end
	return damage or 0
end

local function on_damage(self, hp)
	local me = self.object
	local def = core.registered_entities[self.mob_name]
	hp = hp or me:get_hp()

	if hp <= 0 then
		kill_mob(me, def)
	else
		on_hit(me) -- red flashing
		if def.sounds and def.sounds.on_damage then
			local dmg_snd = def.sounds.on_damage
			core.sound_play(dmg_snd.name, {pos = me:getpos(), max_hear_distance = dmg_snd.distance or 5, gain = dmg_snd.gain or 1})
		end
	end
end

local function change_hp(self, value)
	local me = self.object
	local hp = me:get_hp()
	hp = hp + math.floor(value)
	me:set_hp(hp)
	if value < 0 then
		on_damage(self, hp)
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

local tool_uses = {0, 30, 110, 150, 280, 300, 500, 1000}
local function add_wearout(player, tool_def)
	if not core.setting_getbool("creative_mode") then
		local item = player:get_wielded_item()
		if tool_def and tool_def.damage_groups and tool_def.damage_groups.fleshy then
			local uses = tool_uses[tool_def.damage_groups.fleshy] or 0
			if uses > 0 then
				local wear = 65535/uses
				item:add_wear(wear)
				player:set_wielded_item(item)
			end
		end
	end
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

local function tame(self, def, owner_name)
	self.tamed = true
	self.owner_name = owner_name
	self.breedtimer = def.stats.breedtime
	self.lovetimer = def.stats.lovetime
	local pos = self.object:getpos()
	spawn_particles({ x = pos.x, y = pos.y + 1.0, z = pos.z }, { x = 0, y = 1.0, z = 0 }, "heart.png")
	return true
end

local function breed(self, def)
	if self.breedtimer >= def.stats.breedtime then
		self.lovetimer = 0
		return true
	end
	return false
end

-- --
-- Default entity functions
-- --

animals.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
	change_hp(self, calc_punch_damage(self.object, time_from_last_punch, tool_capabilities) * -1)
	if puncher then
		if time_from_last_punch >= 0.5 then
			local velocity = self.object:getvelocity()
			self.object:setvelocity({x = velocity.x, y = velocity.y + 5.0, z = velocity.z})
			change_mode(self, "_run")

			-- add wearout to weapons/tools
			add_wearout(puncher, tool_capabilities)
		end
	end
end

animals.on_rightclick = function(self, clicker)
	local def = core.registered_entities[self.mob_name]
	if not def then
		animals.throwError("Can't load creature-definition")
		return
	end
	local item = clicker:get_wielded_item()
	if item then
		local name = item:get_name()
		if name then
			if not self.tamed then
				if def.stats.tame_items and check_wielded(name, def.stats.tame_items) then
					if tame(self, def, clicker:get_player_name()) then
						item:take_item()
						if not core.setting_getbool("creative_mode") then
							clicker:set_wielded_item(item)
						end
					end
				end
			else
				if def.stats.breed_items and check_wielded(name, def.stats.breed_items) then
					if breed(self, def) then
						item:take_item()
						if not core.setting_getbool("creative_mode") then
							clicker:set_wielded_item(item)
						end
					end
				end
			end
		end
	end
end

animals.on_step = function(self, dtime)
	local def = core.registered_entities[self.mob_name]
	if not def then
		animals.throwError("Can't load creature-definition")
		return
	end

	-- timer updates
	self.lifetimer = self.lifetimer + dtime
	if def.stats.breed_items and self.breedtimer < def.stats.breedtime then
		self.breedtimer = self.breedtimer + dtime
	end
	if def.stats.breed_items and self.lovetimer < def.stats.lovetime then
		self.lovetimer = self.lovetimer + dtime
	end

	self.modetimer = self.modetimer + dtime
	self.yawtimer = self.yawtimer + dtime
	self.searchtimer = self.searchtimer + dtime
	self.followtimer = self.followtimer + dtime
	self.soundtimer = self.soundtimer + dtime
	self.swimtimer = self.swimtimer + dtime

	-- main
	if self.lifetimer > def.stats.lifetime then
		self.lifetimer = 0
		if self.tamed == false then
			despawn_mob(self.object)
		end
	end

	-- breeding
	if def.stats.breed_items then
		if self.lovetimer < def.stats.lovetime then
			self.breedtimer = 0
			local mates = animals.findTarget(self.object, self.object:getpos(), 4, self.object:get_luaentity().mob_name, self.owner_name, false)
			if #mates >= 1 then
				for _, mate in ipairs(mates) do
					local mate_entity = mate:get_luaentity()
					if mate_entity.lovetimer < def.stats.lovetime then
						local child = core.add_entity(self.object:getpos(), self.object:get_luaentity().mob_name)
						local entity = child:get_luaentity()
						entity.tamed = true
						entity.owner_name = self.owner_name
						entity.breedtimer = 0
						entity.lovetimer = def.stats.lovetime
						self.lovetimer = self.stats.lovetime
						mate_entity.lovetimer = def.stats.lovetime
					end
				end
			end
			local pos = self.object:getpos()
			spawn_particles({ x = pos.x, y = pos.y + 1.0, z = pos.z }, { x = 0, y = 1.0, z = 0 }, "heart.png")
		end
	end

	-- update current node
	local node_pos = self.object:getpos()
	node_pos.y = node_pos.y + 0.25
	self.current_node = core.get_node_or_nil(node_pos)

	-- handle water
	if self.current_node.name == "default:water_source" or self.current_node.name == "default:water_flowing" or self.current_node.name == "default:river_water_source" or self.current_node.name == "default:river_water_flowing" then
		if self.in_water == false then
			self.in_water = true
			self.swimtimer = 0
			self.object:setacceleration({x = 0, y = -0.25, z = 0})	-- set acceleration for in water
		end
		if self.swimtimer > 0.25 then
			self.swimtimer = 0

			-- set velocity to produce bobbing effect
			local vel = self.object:getvelocity()
			self.object:setvelocity({x = vel.x, y = 0.75, z = vel.z})

			-- play swimming sounds
			if def.sounds and def.sounds.swim then
				local swim_snd = def.sounds.swim
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
	if self.mode == "" or (self.mode ~= "follow" and self.modetimer > def.modes[self.mode].duration and def.modes[self.mode].duration > 0) then
		self.modetimer = 0
		change_mode(self)
	end

	-- change yaw randomly
	if self.mode ~= "follow" and def.modes[self.mode].update_yaw and self.yawtimer > def.modes[self.mode].update_yaw then
		self.yawtimer = 0
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
	end

	-- perform actions for random modes
	if self.mode ~= "follow" then
		-- change direction if stuck
		if self.stuck == true then
			change_direction(self)
		end

		-- look for a target to follow
		if def.stats.follow_items then
			if self.searchtimer > 0.6 then
				self.searchtimer = 0
				local targets = animals.findTarget(self.object, self.object:getpos(), def.stats.follow_radius, "player", self.owner_name, false)
				local target = nil
				if #targets > 1 then
					target = targets[math.random(1, #targets)]
				elseif #targets == 1 then
					target = targets[1]
				end
				if target ~= nil then
					local item_name = target:get_wielded_item():get_name()
					if item_name and check_wielded(item_name, def.stats.follow_items) == true then
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
		if self.target and self.followtimer > 0.6 then
			self.followtimer = 0

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
				if distance > def.stats.follow_radius or (item_name and check_wielded(item_name, def.stats.follow_items) == false) then
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
					local anim_def = def.model.animations["follow"]
					if self.in_water and def.model.animations["swim"] then
						anim_def = def.model.animations["swim"]
					end
					update_animation(self.object, anim_def)
				else
					update_animation(self.object, def.model.animations["idle"])
				end
			end
		end
	end

--	-- Random sounds
--	if def.sounds and def.sounds.random[self.mode] then
--		local rnd_sound = def.sounds.random[self.mode]
--		if not self.snd_rnd_time then
--			self.snd_rnd_time = math.random((rnd_sound.time_min or 5), (rnd_sound.time_max or 35))
--		end
--		if rnd_sound and self.soundtimer > self.snd_rnd_time + math.random() then
--			self.soundtimer = 0
--			self.snd_rnd_time = nil
--			core.sound_play(rnd_sound.name, {pos = me:getpos(), gain = rnd_sound.gain or 1, max_hear_distance = rnd_sound.distance or 30})
--		end
--	end
end

animals.get_staticdata = function(self)
	local mode = self.mode
	if mode == "follow" then
		mode = "idle"
	end

	return {
		hp = self.object:get_hp(),
		mode = mode,
		tamed = self.tamed,
		owner_name = self.owner_name,

		lifetimer = self.lifetimer,
		breedtimer = self.breedtimer,
	}
end
