--= Animals mod =--
-- Copyright (c) 2016 Daniel <https://github.com/daniel-32>
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

-- Localizations

local function knockback(self_or_object, dir, old_dir, strengh)
	local object = self_or_object
	if self_or_object.mob_name then
		object = self_or_object.object
	end
	object:set_properties({automatic_face_movement_dir = false})
	object:setvelocity(vector.add(old_dir, {x = dir.x * strengh, y = 3.5, z = dir.z * strengh}))
	old_dir.y = 0
	core.after(0.4, function()
		object:set_properties({automatic_face_movement_dir = -90.0})
		object:setvelocity(old_dir)
		self_or_object.falltimer = nil
		if self_or_object.stunned == true then
			self_or_object.stunned = false
			self_or_object.mode = "_run"
			self_or_object.modetimer = 0
		end
	end)
end

local function on_hit(me)
	core.after(0.1, function()
		me:settexturemod("^[colorize:#c4000099")
	end)
	core.after(0.5, function()
		me:settexturemod("")
	end)
end

local function has_moved(pos1, pos2)
	return not animals.comparePos(pos1, pos2)
end

local function get_dir(pos1, pos2)
	local retval
	if pos1 and pos2 then
		retval = {x = pos2.x - pos1.x, y = pos2.y - pos1.y, z = pos2.z - pos1.z}
	end
	return retval
end

local function get_distance(vec)
	if not vec then
		return -1
	end
	return math.sqrt((vec.x)^2 + (vec.y)^2 + (vec.z)^2)
end

local function update_animation(obj_ref, anim_def)
	if anim_def and obj_ref then
		obj_ref:set_animation({x = anim_def.start, y = anim_def.stop}, anim_def.speed, 0, anim_def.loop)
	end
end

local function update_velocity(obj_ref, dir, speed, add)
	local velo = obj_ref:getvelocity()
	if not dir.y then
		dir.y = velo.y/speed
	end
	local new_velo = {x = dir.x * speed, y = dir.y * speed or velo.y , z = dir.z * speed}
	if add then
		new_velo = vector.add(velo, new_velo)
	end
	obj_ref:setvelocity(new_velo)
end

local function get_yaw(dir_or_yaw)
	local yaw = 360 * math.random()
	if dir_or_yaw and type(dir_or_yaw) == "table" then
		yaw = math.atan(dir_or_yaw.z / dir_or_yaw.x) + math.pi^2 - 2
		if dir_or_yaw.x > 0 then
			yaw = yaw + math.pi
		end
	elseif dir_or_yaw and type(dir_or_yaw) == "number" then
		-- here could be a value based on given yaw
	end

	return yaw
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
	me:setvelocity(nullVec)
	me:set_properties({collisionbox = nullVec})
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
		self.stunned = true
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
	if self.stunned == true then
		return
	end

	local me = self.object
	local mypos = me:getpos()

	change_hp(self, calc_punch_damage(me, time_from_last_punch, tool_capabilities) * -1)
	if puncher then
		if time_from_last_punch >= 0.45 and self.stunned == false then
			local v = me:getvelocity()
			v.y = 0
			me:setacceleration({x = 0, y = -15, z = 0})
			knockback(self, dir, v, 5)
			self.stunned = true

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
	self.nodetimer = self.nodetimer + dtime
	self.swimtimer = self.swimtimer + dtime
	self.yawtimer = self.yawtimer + dtime
	self.modetimer = self.modetimer + dtime
	self.soundtimer = self.soundtimer + dtime
	self.followtimer = self.followtimer + dtime
	self.searchtimer = self.searchtimer + dtime
	self.envtimer = self.envtimer + dtime
	if def.stats.breed_items and self.breedtimer < def.stats.breedtime then
		self.breedtimer = self.breedtimer + dtime
	end
	if def.stats.breed_items and self.lovetimer < def.stats.lovetime then
		self.lovetimer = self.lovetimer + dtime
	end

	-- main
	if self.stunned == true then
		return
	end

	if self.lifetimer > def.stats.lifetime and not (self.mode == "attack" and self.target) then
		self.lifetimer = 0
		if not self.tamed or (self.tamed and def.stats.dies_when_tamed) then
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

	-- localize some things
	local modes = def.modes
	local current_mode = self.mode
	local me = self.object
	local current_pos = me:getpos()
	current_pos.y = current_pos.y + 0.5
	local moved = has_moved(current_pos, self.last_pos) or false

	if current_mode ~= "" then
		-- update position and current node
		if moved == true or not self.last_pos then
			self.last_pos = current_pos
			if self.nodetimer > 0.2 then
				self.nodetimer = 0
				local current_node = core.get_node_or_nil(current_pos)
				self.last_node = current_node
			end
		else
			if (current_mode ~= "follow" and (modes[current_mode].moving_speed or 0) > 0) or current_mode == "follow" then
				update_velocity(me, nullVec, 0)
				if modes["idle"] and not current_mode == "follow" then
					current_mode = "idle"
					self.modetimer = 0
				end
			end
		end

		-- follow target
		if self.target and self.followtimer > 0.6 then
			self.followtimer = 0
			local p2 = self.target:getpos()
			local dir = get_dir(current_pos, p2)
			local dist = get_distance(dir)
			local name = self.target:get_wielded_item():get_name()
			if name and check_wielded(name, def.stats.follow_items) == false then
				dist = -1
			end
			if self.autofollowing == true and (dist == -1 or dist > def.stats.follow_radius) then
				self.target = nil
				self.autofollowing = false
				self.mode = ""
				self.on_follow_end(self)
				current_mode = self.mode
			else
				if current_mode == "follow" then
					self.dir = vector.normalize(dir)
					me:setyaw(get_yaw(dir))
					if self.in_water then
						self.dir.y = me:getvelocity().y
					end
					local speed
					if self.autofollowing == true and (dist < def.stats.follow_stop_distance) then
						speed = 0
						update_animation(me, def.model.animations["idle"])
					else
						speed = def.stats.follow_speed
						local anim_def = def.model.animations["follow"]
						if self.in_water and def.model.animations["swim"] then
							anim_def = def.model.animations["swim"]
						end
						update_animation(me, anim_def)
					end
					update_velocity(me, self.dir, speed or 0)
				end
			end
		end

		-- search for a target to follow
		if not self.target and def.stats.follow_items then
			if self.searchtimer > 0.6 then
				self.searchtimer = 0
				local targets = animals.findTarget(me, current_pos, def.stats.follow_radius, "player", self.owner_name, false)
				if #targets > 1 then
					self.target = targets[math.random(1, #targets)]
				elseif #targets == 1 then
					self.target = targets[1]
				end
				if self.target then
					local name = self.target:get_wielded_item():get_name()
					if name and check_wielded(name, def.stats.follow_items) == true then
						self.autofollowing = true
						self.on_follow_start(self)
						current_mode = "follow"
					else
						self.target = nil
					end
				end
			end
		end

		-- check for a node to eat
		if current_mode == "eat" and not self.eat_node then
			local node_pos = {x = current_pos.x, y = current_pos.y - 1, z = current_pos.z}
			local node = core.get_node_or_nil(node_pos)
			for _, name in pairs(def.stats.eat_nodes) do
				if node and node.name == name then
					self.eat_node = node_pos
					break
				end
			end
			if not self.eat_node then
				current_mode = ""
			end
		end
	end

	-- change mode
	if current_mode == "" or (current_mode ~= "follow" and self.modetimer > modes[current_mode].duration and modes[current_mode].duration > 0) then
		self.modetimer = 0

		local new_mode = animals.rnd(modes)
		if new_mode == "eat" and self.in_water == true then
			new_mode = "idle"
		end
		current_mode = new_mode

		-- change eaten node when mode changes
		if self.eat_node then
			local node = core.get_node_or_nil(self.eat_node)
			local node_name = node.name
			local node_def = core.registered_nodes[node_name]
			if node_def then
				 if node_def.drop and type(node_def.drop) == "string" then
					 node_name = node_def.drop
				 elseif not node_def.walkable then
					 node_name = "air"
				 end
			end
			if node_name and node_name ~= node.name and core.registered_nodes[node_name] then
				core.set_node(self.eat_node, {name = node_name})
				local sounds = node_def.sounds
				if sounds and sounds.dug then
					core.sound_play(sounds.dug, {pos = self.eat_node, max_hear_distance = 5, gain = 1})
				end
			end
			self.eat_node = nil
			self.on_eat(self)
		end
	end

	-- mode has changed, do things
	if current_mode ~= self.last_mode then
		self.last_mode = current_mode

		local moving_speed
		if current_mode == "follow" then
			moving_speed = def.stats.follow_speed
		else
			moving_speed = modes[current_mode].moving_speed or 0
		end
		if moving_speed > 0 then
			local yaw = (get_yaw(me:getyaw()) + 90.0) * DEGTORAD
			me:setyaw(yaw + 4.73)
			self.dir = {x = math.cos(yaw), y = 0, z = math.sin(yaw)}
			if self.in_water == true then
				moving_speed = moving_speed * 0.7
			end
		else
			self.dir = nullVec
		end
		update_velocity(me, self.dir, moving_speed)

		local anim_def = def.model.animations[current_mode]
		if self.in_water and def.model.animations["swim"] then
			anim_def = def.model.animations["swim"]
		end
		update_animation(me, anim_def)
	end

	-- update yaw
	if current_mode ~= "follow" then
		if modes[current_mode].update_yaw and self.yawtimer > modes[current_mode].update_yaw then
			self.yawtimer = 0
			local mod = nil
			if current_mode == "_run" then
				mod = me:getyaw()
			end
			local yaw = (get_yaw(mod) + 90.0) * DEGTORAD
			me:setyaw(yaw + 4.73)
			local moving_speed = modes[current_mode].moving_speed or 0
			if moving_speed > 0 then
				self.dir = {x = math.cos(yaw), y = nil, z = math.sin(yaw)}
				update_velocity(me, self.dir, moving_speed)
			end
		end
	end

	--swim
	if self.swimtimer > 0.8 and self.last_node then
		self.swimtimer = 0
		local name = self.last_node.name
		if name then
			if name == "default:water_source" then
				local vel = me:getvelocity()
				update_velocity(me, {x = vel.x, y = 0.75, z = vel.z}, 1)
				me:setacceleration({x = 0, y = -0.5, z = 0})
				self.in_water = true
				-- play swimming sounds
				if def.sounds and def.sounds.swim then
					local swim_snd = def.sounds.swim
					core.sound_play(swim_snd.name, {pos = current_pos, gain = swim_snd.gain or 1, max_hear_distance = swim_snd.distance or 10})
				end
				spawn_particles(current_pos, vel, "bubble.png")
			else
				if self.in_water == true then
					self.in_water = false
					me:setacceleration({x = 0, y = -0.75, z = 0})
				end
			end
		end
	end

	-- Add damage when drowning or in lava
	if self.envtimer > 1 and self.last_node then
		self.envtimer = 0
		local name = self.last_node.name
		if name == "fire:basic_flame" or name == "default:lava_source" then
			change_hp(self, -4)
		end
	end

	-- Random sounds
	if def.sounds and def.sounds.random[current_mode] then
		local rnd_sound = def.sounds.random[current_mode]
		if not self.snd_rnd_time then
			self.snd_rnd_time = math.random((rnd_sound.time_min or 5), (rnd_sound.time_max or 35))
		end
		if rnd_sound and self.soundtimer > self.snd_rnd_time + math.random() then
			self.soundtimer = 0
			self.snd_rnd_time = nil
			core.sound_play(rnd_sound.name, {pos = current_pos, gain = rnd_sound.gain or 1, max_hear_distance = rnd_sound.distance or 30})
		end
	end

	self.mode = current_mode
end


animals.get_staticdata = function(self)
	return {
		hp = self.object:get_hp(),
		mode = self.mode,
		stunned = self.stunned,
		tamed = self.tamed,
		owner_name = self.owner_name,
		dir = self.dir,
		in_water = self.in_water,
		autofollowing = self.autofollowing,

		lifetimer = self.lifetimer,
		yawtimer = self.yawtimer,
		modetimer = self.modetimer,
		soundtimer = self.soundtimer,
		breedtimer = self.breedtimer,
		lovetimer = self.lovetimer,
	}
end
