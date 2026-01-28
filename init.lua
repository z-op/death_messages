--[[
death_messages - A Minetest mod which sends a chat message when a player dies.
Copyright (C) 2016  EvergreenTree

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

--------------------------------------------------------------------------------
-- MOD INITIALIZATION
--------------------------------------------------------------------------------
local MOD_NAME     = "death_messages"
local MOD_TITLE    = "Death Messages"
local MOD_VERSION  = "0.1.5"
local S            = minetest.get_translator(MOD_NAME)

-- Load configuration settings
dofile(minetest.get_modpath(MOD_NAME) .. "/settings.txt")
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- DEATH MESSAGE DATABASE
--------------------------------------------------------------------------------
-- Contains categorized death messages. First entry in each category is used
-- when RANDOM_MESSAGES is disabled.
local messages = {
    -- Lava-related deaths
    lava = {
        "melted into a ball of fire.",
        "thought lava was cool.",
        "melted into a ball of fire.",
        "couldn't resist that warm glow of lava.",
        "dug straight down.",
        "didn't know lava was hot."
    },

    -- Water/drowning deaths
    water = {
        "drowned.",
        "ran out of air.",
        "failed at swimming lessons.",
        "tried to impersonate an anchor.",
        "forgot he wasn't a fish.",
        "blew one too many bubbles."
    },

    -- Fire/burning deaths
    fire = {
        "burned to a crisp.",
        "got a little too warm.",
        "got too close to the camp fire.",
        "just got roasted, hotdog style.",
        "got burned up. More light that way."
    },

    -- Mob-related deaths
    mob = {
        "was slain by @1.",
        "fell to the might of @1.",
        "was defeated by @1.",
        "met their end at the hands of @1.",
        "was killed by @1."
    },

    -- Generic/other deaths
    other = {
        "died.",
        "did something fatal.",
        "gave up on life.",
        "is somewhat dead now.",
        "passed out -permanently."
    }
}
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------
-- Returns a death message based on message type and configuration
-- @param mtype: Message category (lava, water, fire, mob, other)
-- @return: Selected death message string
local function get_message(mtype)
    if RANDOM_MESSAGES then
        return messages[mtype][math.random(1, #messages[mtype])]
    else
        return messages[mtype][1] -- First message is default
    end
end

-- Checks if an entity is a mob from mobs_redo mod
-- @param entity: Lua entity to check
-- @return: Boolean indicating if entity is a mobs_redo mob
local function is_mobs_redo_mob(entity)
    if not entity then return false end

    -- Check for mobs_redo specific flag
    if entity._cmi_is_mob then
        return true
    end

    -- Check by entity name pattern
    if entity.name and string.find(entity.name, "^mobs:") then
        return true
    end

    return false
end

-- Extracts display name from a mob entity
-- @param entity: Mob entity object
-- @return: Human-readable mob name
local function get_mob_display_name(entity)
    local mob_name = "a monster"

    -- Use entity description if available
    if entity.description and entity.description ~= "" then
        mob_name = entity.description
    elseif entity.name then
        -- Parse entity name to create readable version
        local name_parts = string.split(entity.name, ":")
        if name_parts and name_parts[2] then
            mob_name = name_parts[2]:gsub("_", " ")
            -- Capitalize first letter
            mob_name = mob_name:gsub("^%l", string.upper)
        end
    end

    return mob_name
end
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- DAMAGE TRACKING SYSTEM
--------------------------------------------------------------------------------
-- Table storing information about recent damage sources for players
local last_damage = {}

-- Global step function to clean up old damage records
minetest.register_globalstep(function(dtime)
    local current_time = os.time()
    for player_name, data in pairs(last_damage) do
        -- Remove records older than 10 seconds
        if current_time - data.time > 10 then
            last_damage[player_name] = nil
        end
    end
end)

-- HP change handler to track mob attacks on players
minetest.register_on_player_hpchange(function(player, hp_change, reason)
    -- Only process damage events (negative HP change)
    if hp_change < 0 then
        local player_name = player:get_player_name()

        -- Check if damage came from a punch attack
        if reason.type == "punch" and reason.object then
            local attacker = reason.object
            local attacker_entity = attacker:get_luaentity()

            -- Verify attacker is a mobs_redo mob
            if attacker_entity and is_mobs_redo_mob(attacker_entity) then
                local mob_name = get_mob_display_name(attacker_entity)

                -- Store damage information
                last_damage[player_name] = {
                    mob_name = mob_name,
                    time = os.time(),
                    attacker_id = tostring(attacker) -- Unique attacker identifier
                }

                -- Log for debugging
                minetest.log("action", "[death_messages] Player " .. player_name ..
                    " was attacked by mob: " .. mob_name .. " (" .. attacker_entity.name .. ")")
            end
        end
    end

    return hp_change
end, true)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- DEATH EVENT HANDLER
--------------------------------------------------------------------------------
-- Main handler triggered when player dies
minetest.register_on_dieplayer(function(player)
    local player_name = player:get_player_name()
    local pos = player:get_pos()
    local node = pos and minetest.registered_nodes[
        minetest.get_node(pos).name
    ]

    -- Determine display name (use "You" in singleplayer)
    local display_name = player_name
    if minetest.is_singleplayer() then
        display_name = "You"
    end

    -- Check for mob-related death
    if last_damage[player_name] then
        local mob_name = last_damage[player_name].mob_name
        local message = get_message("mob")
        -- Minetest uses $1, $2 etc for parameters in translation
        local translated_message = S(message, mob_name)
        minetest.chat_send_all(display_name .. " " .. translated_message)

        -- Log event
        minetest.log("action", "[death_messages] " .. display_name ..
            " was killed by mob: " .. mob_name)

        -- Clear damage record
        last_damage[player_name] = nil

    -- Check for lava death
    elseif node and node.groups and node.groups.lava ~= nil then
        minetest.chat_send_all(display_name .. " " .. S(get_message("lava")))

    -- Check for drowning death
    elseif player:get_breath() == 0 then
        minetest.chat_send_all(display_name .. " " .. S(get_message("water")))

    -- Check for fire death
    elseif node and node.name == "fire:basic_flame" then
        minetest.chat_send_all(display_name .. " " .. S(get_message("fire")))

    -- Generic death
    else
        minetest.chat_send_all(display_name .. " " .. S(get_message("other")))
    end
end)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- MOD LOAD CONFIRMATION
--------------------------------------------------------------------------------
print("[Mod] " .. MOD_TITLE .. " [" .. MOD_VERSION .. "] [" .. MOD_NAME .. "] Loaded...")
--------------------------------------------------------------------------------
