--= Animals mod =--
-- Copyright (c) 2017 Daniel <https://github.com/danielmeek32>
--
-- pathfinding.lua
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

local collisionbox_surrounding_area_check_distance = tonumber(minetest.setting_get("animals_surrounding_area_check_distance")) or 2
local direct_path_scan_distance = tonumber(minetest.setting_get("animals_scan_distance")) or 0.25
local pathfind_intermediate_scans = tonumber(minetest.setting_get("animals_pathfinding_scan_precision")) or 3
local pathfind_max_iterations = tonumber(minetest.setting_get("animals_pathfinding_max_iterations")) or 1000
local pathfind_max_time = tonumber(minetest.setting_get("animals_pathfinding_max_time")) or 0.05

-- check if a node is water
local function check_node_water(node_def)
	if node_def and node_def.liquidtype ~= "none" then
		return true
	else
		return false
	end
end

-- check if there's enough space around the given position for the given collisionbox to fit
local node_cache = {}
local irregular_collisionbox_cache = {}
local function check_space(pos, collisionbox)
	-- the node cache allows the number of calls to minetest.get_node to be reduced
	-- once a node has been evaluated to be solid or not, this is stored in the cache so that the node does not need to be retrieved through the Minetest API again until the next tick
	-- this dramatically improves performance in situations where this function is called multiple times in one tick with similar or overlapping positions, which is pretty much any pathfinding-related situation
	-- the values in the cache may have one of three values
	-- true = the node is always guaranteed to obstruct us (i.e. it has a collisionbox equal to one full node and whether or not this is considered an obstruction does not depend on our position)
	-- false = the node is always guaranteed to never obstruct us (i.e. it is not solid and whether or not is is considered an obstruction does not depend on our position)
	-- nil = no cached value is available, or whether or not the node obstructs us depends on our position (e.g. the node has an irregular collisionbox) and needs to be evaluated each time

	local check_irregular_collisionbox = function(node_pos, node_name, node_def, node_collisionbox, node_param2)
		local node_collisionbox_boxes
		if irregular_collisionbox_cache[node_name] and irregular_collisionbox_cache[node_name][node_param2] then
			-- get collisionbox from cache
			node_collisionbox_boxes = irregular_collisionbox_cache[node_name][node_param2]
		else
			-- construct collisionbox from parameters
			local node_collisionbox_type = node_collisionbox.type
			node_collisionbox_boxes = {}
			local add_boxes = function(boxes)
				if boxes and #boxes > 0 then
					if type(boxes[1]) == "table" then
						for _, box in ipairs(boxes) do
							table.insert(node_collisionbox_boxes, { box[1], box[2], box[3], box[4], box[5], box[6] })
						end
					else
						table.insert(node_collisionbox_boxes, { boxes[1], boxes[2], boxes[3], boxes[4], boxes[5], boxes[6] })
					end
				end
			end
			if node_collisionbox_type == "fixed" or node_collisionbox_type == "leveled" or node_collisionbox_type == "connected" then
				add_boxes(node_collisionbox.fixed)
				if node_collisionbox_type == "fixed" then
					-- rotate nodeboxes by facedir
					if node_def.paramtype2 == "facedir" then
						local facedir = node_param2
						local axis = math.floor(facedir / 4)
						local face = facedir % 4
						for _, box in ipairs(node_collisionbox_boxes) do
							if face == 1 then
								box[1], box[3] = box[3], -box[1]
								box[4], box[6] = box[6], -box[4]
							elseif face == 2 then
								box[1] = -box[1]
								box[3] = -box[3]
								box[4] = -box[4]
								box[6] = -box[6]
							elseif face == 3 then
								box[1], box[3] = -box[3], box[1]
								box[4], box[6] = -box[6], box[4]
							end
							if axis == 1 then
								box[3], box[2] = box[2], -box[3]
								box[6], box[5] = box[5], -box[6]
							elseif axis == 2 then
								box[3], box[2] = -box[2], box[3]
								box[6], box[5] = -box[5], box[6]
							elseif axis == 3 then
								box[1], box[2] = box[2], -box[1]
								box[4], box[5] = box[5], -box[4]
							elseif axis == 4 then
								box[1], box[2] = -box[2], box[1]
								box[4], box[5] = -box[5], box[4]
							elseif axis == 5 then
								box[1] = -box[1]
								box[2] = -box[2]
								box[4] = -box[4]
								box[5] = -box[5]
							end
						end
					end
				elseif node_collisionbox_type == "leveled" then
					-- adjust nodeboxes for level
					if node_def.paramtype2 == "leveled" then
						for _, box in ipairs(node_collisionbox_boxes) do
							box[5] = node_param2 / 64 - 0.5
						end
					end
				elseif node_collisionbox_type == "connected" then
					-- get connected nodeboxes
					-- for efficiency we don't check which sides are actually connected
					add_boxes(node_collisionbox.connect_top)
					add_boxes(node_collisionbox.connect_bottom)
					add_boxes(node_collisionbox.connect_front)
					add_boxes(node_collisionbox.connect_left)
					add_boxes(node_collisionbox.connect_back)
					add_boxes(node_collisionbox.connect_right)
				end
			elseif node_collisionbox_type == "wallmounted" then
				if node_def.paramtype2 == "wallmounted" then
					-- get nodeboxes based on which wall it's attached to
					if node_param2 == 0 then
						add_boxes(node_collisionbox.wall_top)
					elseif node_param2 == 1 then
						add_boxes(node_collisionbox.wall_bottom)
					else
						add_boxes(node_collisionbox.wall_side)
						-- rotate nodeboxes based on which wall it's attached to
						for _, box in ipairs(node_collisionbox_boxes) do
							if node_param2 == 2 then
								box[1] = -box[1]
								box[3] = -box[3]
								box[4] = -box[4]
								box[6] = -box[6]
							elseif node_param2 == 4 then
								box[1], box[3] = box[3], -box[1]
								box[4], box[6] = box[6], -box[4]
							elseif node_param2 == 5 then
								box[1], box[3] = -box[3], box[1]
								box[4], box[6] = -box[6], box[4]
							end
						end
					end
				end
			end

			-- make sure that the co-ordinates are in the right order
			for _, box in ipairs(node_collisionbox_boxes) do
				if box[1] > box[4] then
					box[1], box[4] = box[4], box[1]
				end
				if box[2] > box[5] then
					box[2], box[5] = box[5], box[2]
				end
				if box[3] > box[6] then
					box[3], box[6] = box[6], box[3]
				end
			end

			-- save collisionbox in cache
			if not irregular_collisionbox_cache[node_name] then
				irregular_collisionbox_cache[node_name] = {}
			end
			irregular_collisionbox_cache[node_name][node_param2] = node_collisionbox_boxes
		end

		-- check each box for intersection with the given collisionbox
		for _, box in ipairs(node_collisionbox_boxes) do
			if
				box[1] + node_pos.x < collisionbox[4] + pos.x and box[4] + node_pos.x > collisionbox[1] + pos.x and
				box[2] + node_pos.y < collisionbox[5] + pos.y and box[5] + node_pos.y > collisionbox[2] + pos.y and
				box[3] + node_pos.z < collisionbox[6] + pos.z and box[6] + node_pos.z > collisionbox[3] + pos.z
			then
				return true
			end
		end
		return false
	end

	local corner_a = vector.round({ x = pos.x + collisionbox[1], y = pos.y + collisionbox[2], z = pos.z + collisionbox[3] })
	local corner_b = vector.round({ x = pos.x + collisionbox[4], y = pos.y + collisionbox[5], z = pos.z + collisionbox[6] })

	for x = corner_a.x - collisionbox_surrounding_area_check_distance, corner_b.x + collisionbox_surrounding_area_check_distance do
		for y = corner_a.y - collisionbox_surrounding_area_check_distance, corner_b.y + collisionbox_surrounding_area_check_distance do
			for z = corner_a.z - collisionbox_surrounding_area_check_distance, corner_b.z + collisionbox_surrounding_area_check_distance do
				local node_pos_hash = minetest.hash_node_position({ x = x, y = y, z = z })
				if x >= corner_a.x and x <= corner_b.x and y >= corner_a.y and y <= corner_b.y and z >= corner_a.z and z <= corner_b.z then
					-- check nodes within the collisionbox
					if node_cache[node_pos_hash] == true then
						return false
					elseif node_cache[node_pos_hash] == nil then
						local node = minetest.get_node({ x = x, y = y, z = z })
						local node_name = node.name
						local node_param2 = node.param2
						if node_name ~= "air" then	-- optimise air as it's very common
							if node_name == "ignore" then
								return false
							end

							local node_def = minetest.registered_nodes[node_name]
							if not node_def then
								return false
							end

							if node_def.walkable then
								if node_def.drawtype == "nodebox" or node_def.collision_box then
									-- the node has a collisionbox, so determine if it intersects with our collisionbox
									local node_collisionbox
									if node_def.collision_box then
										node_collisionbox = node_def.collision_box
									else
										node_collisionbox = node_def.node_box
									end
									if not node_collisionbox or node_collisionbox.type == "regular" then
										node_cache[node_pos_hash] = true	-- cache nodes with regular collisionbox as always being obstructed
										return false
									end
									-- check if node intersects with the collisionbox
									if x ~= corner_a.x and x ~= corner_b.x and y ~= corner_a.y and y ~= corner_b.y and z ~= corner_a.z and z ~= corner_b.z then	-- optimise nodes that falls completely inside the collisionbox
										return false
									elseif check_irregular_collisionbox({ x = x, y = y, z = z }, node_name, node_def, node_collisionbox, node_param2) then
										return false
									end
								else
									-- disallow walkable nodes with regular collisionbox
									node_cache[node_pos_hash] = true	-- cache nodes with regular collisionbox as always being obstructed
									return false
								end
							else
								-- don't allow liquid deeper than one block
								if y > corner_a.y and node_def.liquidtype ~= "none" then
									return false
								elseif node_def.liquidtype == "none" then
									-- cache non-walkable non-liquid nodes as always being unobstructed
									node_cache[node_pos_hash] = false
								end
							end
						else
							-- cache air as always being unobstructed
							node_cache[node_pos_hash] = false
						end
					end
				else
					-- check surrounding area for large nodes
					if node_cache[node_pos_hash] == nil then	-- skip nodes that are in the cache, as such nodes are always either non-walkable or have a regular collisionbox
						local node = minetest.get_node({ x = x, y = y, z = z })
						local node_name = node.name
						local node_param2 = node.param2
						if node_name ~= "air" and node_name ~= "ignore" then
							local node_def = minetest.registered_nodes[node_name]
							if node_def then
								if node_def.walkable then
									if node_def.drawtype == "nodebox" or node_def.collision_box then
										local node_collisionbox
										if node_def.collision_box then
											node_collisionbox = node_def.collision_box
										else
											node_collisionbox = node_def.node_box
										end
										if node_collisionbox and node_collisionbox.type ~= "regular" then
											if check_irregular_collisionbox({ x = x, y = y, z = z }, node_name, node_def, node_collisionbox, node_param2) then
												return false
											end
										else
											-- cache nodes with regular collisionbox as always being obstructed
											node_cache[node_pos_hash] = true
										end
									else
										-- cache nodes with regular collisionbox as always being obstructed
										node_cache[node_pos_hash] = true
									end
								elseif node_def.liquidtype == "none" then
									-- cache non-walkable non-liquid nodes as always being unobstructed
									node_cache[node_pos_hash] = false
								end
							end
						elseif node_name == "air" then
							-- cache air as always being unobstructed
							node_cache[node_pos_hash] = false
						end
					end
				end
			end
		end
	end

	return true
end

-- check if a collisionbox at position pos1 intersects with a node at position pos2
-- Note that pos2 is rounded to the nearest node and intersection checking is performed at the node level
local function check_collisionbox_intersection(pos1, pos2, collisionbox)
	local corner_a = vector.round({ x = pos1.x + collisionbox[1], y = pos1.y + collisionbox[2], z = pos1.z + collisionbox[3] })
	local corner_b = vector.round({ x = pos1.x + collisionbox[4], y = pos1.y + collisionbox[5], z = pos1.z + collisionbox[6] })

	if pos2.x >= corner_a.x - 0.49 and pos2.x <= corner_b.x + 0.49 and pos2.y >= corner_a.y - 0.49 and pos2.y <= corner_b.y + 0.49 and pos2.z >= corner_a.z - 0.49 and pos2.z <= corner_b.z + 0.49 then
		return true
	else
		return false
	end
end

-- check if it is possible to walk to a particular position
-- return true, step_height if it is, otherwise returns false
-- allows limiting step height
local function check_walkable(pos, collisionbox, max_step_up_height, max_step_down_height)
	local new_pos = { x = pos.x, y = pos.y, z = pos.z }
	if check_space(new_pos, collisionbox) then
		if not check_space({ x = new_pos.x, y = new_pos.y - 1, z = new_pos.z }, collisionbox) then
			return true, 0
		elseif max_step_down_height > 0 then
			for step_down = 1, max_step_down_height do
				new_pos.y = new_pos.y - 1
				if check_space(new_pos, collisionbox) and not check_space({ x = new_pos.x, y = new_pos.y - 1, z = new_pos.z }, collisionbox) then
					return true, -step_down
				end
			end
		end
	else
		if max_step_up_height > 0 then
			for step_up = 1, max_step_up_height do
				new_pos.y = new_pos.y + 1
				if check_space(new_pos, collisionbox) then
					return true, step_up
				end
			end
		end
	end
	return false
end

-- returns true if there is an unobstructed path directly from pos1 to pos2, taking into account jumps, doors, walkable nodes, cliffs, water, etc.
local function direct_path(pos1, pos2, collisionbox)
	local pos1_flat = { x = pos1.x, y = 0, z = pos1.z }
	local pos2_flat = { x = pos2.x, y = 0, z = pos2.z }
	local direction = vector.direction(pos1_flat, pos2_flat)
	direction = vector.normalize(direction)
	local scan_pos = { x = pos1.x, y = pos1.y, z = pos1.z }
	local scan_step = vector.multiply(direction, direct_path_scan_distance)

	while vector.distance({ x = scan_pos.x, y = 0, z = scan_pos.z }, pos2_flat) > direct_path_scan_distance * 2 do
		local walkable, step_height = check_walkable(scan_pos, collisionbox, 1, 2)
		if not walkable then
			return false
		end
		scan_pos.y = scan_pos.y + step_height
		scan_pos = vector.add(scan_pos, scan_step)
	end

	if vector.distance(scan_pos, pos2) > 2 then	-- allow fairly large range here to allow for players jumping in the air
		return false
	end

	return true
end

-- disable pathfinding for a mob
local function disable_pathfinding(self)
	self.pathfinding_enabled = false
end

-- find a path from a mob's curreent position to its target position
-- path is returned as a series of 2D waypoints in the mob's self.path field, and the mob will be automatically configured for pathfinding
-- path will always contain mob's own position as start waypoint and target position as end waypoint, unless pathfinding fails, in which case pathfinding is disabled on this particular mob
local function pathfind(self)
	local my_pos = self.object:getpos()
	local target_pos = self.target:getpos()
	my_pos = vector.round(my_pos)
	target_pos = vector.round(target_pos)
	my_pos.y = my_pos.y - 0.49	-- subtract 0.49 from y co-ordinate as mob should be on the ground, not floating halfway up the node
	target_pos.y = target_pos.y - 0.49	-- subtract 0.49 from y co-ordinate as mob should be on the ground, not floating halfway up the node

	-- A*

	local collisionbox = self.collisionbox

	-- returns the "cost" of moving one node in direction dir
	local get_cost = function(dir)
		if dir.y == 0 then
			if dir.x == 0 or dir.z == 0 then
				return 1
			else
				return 1.4
			end
		else
			if dir.x == 0 or dir.z == 0 then
				return 1.4
			else
				return 1.7
			end
		end
	end

	-- returns the estimated cost to get from pos to target
	local get_heuristic = function(pos)
		return math.abs(target_pos.x - pos.x) + math.abs(target_pos.y - pos.y) + math.abs(target_pos.z - pos.z)
	end

	-- returns true if a list of points contains a particular position, also returns index if it is in the list
	local is_in_list = function(list, pos)
		for index, point in ipairs(list) do
			if point.pos.x == pos.x and point.pos.y == pos.y and point.pos.z == pos.z then
				return true, index
			end
		end
		return false
	end

	-- reconstructs the path after pathfinding has finished
	local build_path = function(list, pos)
		local find_in_list = function(list, pos)
			for index, point in ipairs(list) do
				if point.pos.x == pos.x and point.pos.y == pos.y and point.pos.z == pos.z then
					return  index
				end
			end
			return nil
		end

		local reverse_path = {}
		local current_pos = pos
		local parent = list[find_in_list(list, current_pos)].parent
		while parent ~= nil do
			table.insert(reverse_path, { x = current_pos.x, z = current_pos.z })
			current_pos = parent
			parent = list[find_in_list(list, current_pos)].parent
		end
		table.insert(reverse_path, { x = current_pos.x, z = current_pos.z })

		self.path = {}
		for index = #reverse_path, 1, -1 do
			table.insert(self.path, reverse_path[index])
		end
	end

	-- perform A* pathfinding
	local search_dirs = {{ x = 0, z = 1 }, { x = 1, z = 0 }, { x = 0, z = -1 }, { x = -1, z = 0 }, { x = 1, z = 1 }, { x = 1, z = -1 }, { x = -1, z = -1 }, { x = -1, z = 1 }}
	local open_list = {}
	local closed_list = {}
	table.insert(open_list, { pos = my_pos, cost = 0, score = get_heuristic(my_pos), parent = nil })
	local walkable_cache = {}
	local step_height_cache = {}
	local iterations = 0
	local start_time = os.clock()
	while #open_list > 0 and iterations < pathfind_max_iterations and os.clock() - start_time < pathfind_max_time do
		iterations = iterations + 1

		-- find the point in the open list with the lowest score
		local lowest_index
		local lowest_score = 10000
		for index, point in ipairs(open_list) do
			if point.score < lowest_score then
				lowest_index = index
				lowest_score = point.score
			end
		end
		local point = table.remove(open_list, lowest_index)
		table.insert(closed_list, point)
		local pos = point.pos

		-- check if the point matches the target position
		if check_collisionbox_intersection(pos, target_pos, collisionbox) then
			build_path(closed_list, pos)

			self.path_index = 1
			self.last_waypoint_pos = nil
			self.waypoint_approach_direction = nil
			self.pathfinding_enabled = true
			return
		end

		-- consider points adjacent to the selected point
		for _, dir in ipairs(search_dirs) do
			local check_pos = { x = pos.x + dir.x, y = pos.y, z = pos.z + dir.z }
			local check_pos_hash = minetest.hash_node_position(check_pos)
			local walkable, step_height = walkable_cache[check_pos_hash], step_height_cache[check_pos_hash]
			if walkable == nil then
				walkable, step_height = check_walkable(check_pos, collisionbox, 1, 2)
				walkable_cache[check_pos_hash] = walkable
				step_height_cache[check_pos_hash] = step_height
			end
			if walkable == true then
				local intermediate_walkable = true
				if pathfind_intermediate_scans > 0 then
					for intermediate_scan = 1, pathfind_intermediate_scans do
						local scan_check_pos = { x = pos.x + dir.x * (intermediate_scan / (pathfind_intermediate_scans + 1)), y = pos.y, z = pos.z + dir.z * (intermediate_scan / (pathfind_intermediate_scans + 1)) }
						local scan_check_pos_hash = minetest.hash_node_position(scan_check_pos)
						local scan_walkable, scan_step_height = walkable_cache[scan_check_pos_hash], step_height_cache[scan_check_pos_hash]
						if scan_walkable == nil then
							scan_walkable, scan_step_height = check_walkable(scan_check_pos, collisionbox, 1, 2)
							walkable_cache[scan_check_pos_hash] = scan_walkable
							step_height_cache[scan_check_pos_hash] = scan_step_height
						end
						if scan_walkable == false or (scan_step_height ~= 0 and scan_step_height ~= step_height) then
							intermediate_walkable = false
							break
						end
					end
				end
				if intermediate_walkable == true then
					local next_pos = { x = pos.x + dir.x, y = pos.y + step_height, z = pos.z + dir.z }
					if not is_in_list(closed_list, next_pos) then
						local cost = point.cost + get_cost(vector.direction(pos, next_pos))
						local score = cost + get_heuristic(next_pos)
						local in_list, index = is_in_list(open_list, next_pos)
						if in_list then
							if score < open_list[index].score then
								open_list[index].cost = cost
								open_list[index].score = score
								open_list[index].parent = { x = pos.x, y = pos.y, z = pos.z }
							end
						else
							table.insert(open_list, { pos = { x = next_pos.x, y = next_pos.y, z = next_pos.z }, cost = cost, score = score, parent = { x = pos.x, y = pos.y, z = pos.z } })
						end
					end
				end
			end
		end
	end

	disable_pathfinding(self)
end

-- export functions
pathfinding = {
	clear_node_cache = function() node_cache = {} end,
	check_node_water = check_node_water,
	check_space = check_space,
	check_walkable = check_walkable,
	direct_path = direct_path,
	disable_pathfinding = disable_pathfinding,
	pathfind = pathfind,
}
