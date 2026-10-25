-- The local player's own (hidden) first person weapon already plays the shot sounds,
-- so the ghost's weapon stays silent.
local function is_ghost_weapon(weapon_base)
    local setup = weapon_base._setup

    return setup and ThirdPerson.ghost and setup.user_unit == ThirdPerson.ghost
end

for _, name in ipairs({ "_sound_singleshot", "_sound_autofire_start", "_sound_autofire_end" }) do
    local original = NewNPCRaycastWeaponBase[name]

    if original then
        NewNPCRaycastWeaponBase[name] = function(self, ...)
            if is_ghost_weapon(self) then
                return
            end

            return original(self, ...)
        end
    end
end
