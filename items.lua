--= Animals mod =--
-- Copyright (c) 2016 Daniel <https://github.com/danielmeek32>
--
-- Modified from Creatures MOB-Engine (cme)
-- Copyright (c) 2015 BlockMen <blockmen2015@gmail.com>
--
-- items.lua
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

core.register_craftitem("animals:flesh", {
	description = "Flesh",
	inventory_image = "animals_flesh.png",
	on_use = core.item_eat(2),
})

core.register_craftitem("animals:meat", {
	description = "Cooked Meat",
	inventory_image = "animals_meat.png",
	on_use = core.item_eat(4),
})

core.register_craft({
	type = "cooking",
	output = "animals:meat",
	recipe = "animals:flesh",
})
