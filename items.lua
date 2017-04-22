--= Animals mod =--
-- Copyright (c) 2017 Daniel <https://github.com/danielmeek32>
--
-- items.lua
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

minetest.register_craftitem("animals:flesh", {
	description = "Flesh",
	inventory_image = "animals_flesh.png",
	on_use = core.item_eat(2),
})

minetest.register_craftitem("animals:meat", {
	description = "Cooked Meat",
	inventory_image = "animals_meat.png",
	on_use = core.item_eat(4),
})

minetest.register_craft({
	type = "cooking",
	output = "animals:meat",
	recipe = "animals:flesh",
})
