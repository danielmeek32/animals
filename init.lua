--= Animals mod =--
-- Copyright (c) 2017 Daniel <https://github.com/danielmeek32>
--
-- init.lua
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

animals = {}

local modpath = minetest.get_modpath("animals")

-- mob engine
dofile(modpath .."/engine.lua")

-- items
dofile(modpath .."/items.lua")
