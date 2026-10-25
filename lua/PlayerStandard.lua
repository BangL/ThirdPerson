local tps_get_pos = PlayerStandard.get_fire_weapon_position
local tps_get_dir = PlayerStandard.get_fire_weapon_direction

-- Shots leave the ghost's muzzle and travel to the point under the crosshair.
function PlayerStandard:get_fire_weapon_position()
    if ThirdPerson:is_local(self._unit) then
        local pos = ThirdPerson:muzzle_position()

        if pos then
            return pos
        end
    end

    return tps_get_pos(self)
end

function PlayerStandard:get_fire_weapon_direction()
    if ThirdPerson:is_local(self._unit) then
        local dir = ThirdPerson:fire_direction(ThirdPerson:muzzle_position())

        if dir then
            return dir
        end
    end

    return tps_get_dir(self)
end

local tps_update_crosshair = PlayerStandard._update_crosshair_offset

-- The game hides crosshair and dot while aiming down sights; in third person we need them, so
-- the crosshair logic sees the hip stance instead.
function PlayerStandard:_update_crosshair_offset()
    if not (ThirdPerson:is_local(self._unit) and ThirdPerson:tps_on() and ThirdPerson:GetConfigOption("keep_hud_in_ads") and self._state_data.in_steelsight) then
        return tps_update_crosshair(self)
    end

    self._state_data.in_steelsight = false

    local ok, err = blt.pcall(tps_update_crosshair, self)

    self._state_data.in_steelsight = true

    if not ok then
        log("[ThirdPerson] crosshair error: " .. tostring(err))
    end
end
