local tps_muzzle = RaycastWeaponBase._spawn_muzzle_effect
local tps_muzzletrail = RaycastWeaponBase._spawn_muzzletrail_effect

-- The (hidden) first person weapon still spawns its muzzle effects at its own, camera-bound position.
-- The ghost's weapon spawns the visible ones.
local function is_hidden_fp_weapon(weapon_base)
    if not ThirdPerson:tps_on() then
        return false
    end

    local inventory = ThirdPerson.player_unit:inventory()

    return inventory and inventory:equipped_unit() == weapon_base._unit
end

function RaycastWeaponBase:_spawn_muzzle_effect(...)
    if is_hidden_fp_weapon(self) then
        return
    end

    return tps_muzzle(self, ...)
end

function RaycastWeaponBase:_spawn_muzzletrail_effect(...)
    if is_hidden_fp_weapon(self) then
        return
    end

    return tps_muzzletrail(self, ...)
end
