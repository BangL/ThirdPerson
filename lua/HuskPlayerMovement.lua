local tps_update = HuskPlayerMovement.update
local tps_destroy = HuskPlayerMovement.destroy
local tps_save = HuskPlayerMovement.save

function HuskPlayerMovement:update(unit, t, dt)
    if self._tps_ghost then
        return ThirdPerson:safe(ThirdPerson.update_ghost, ThirdPerson, self, t, dt)
    end

    return tps_update(self, unit, t, dt)
end

if tps_destroy then
    function HuskPlayerMovement:destroy(...)
        if self._tps_ghost then
            return
        end

        return tps_destroy(self, ...)
    end
end

-- The melee callbacks look up the melee weapon of the peer that owns the husk, see BaseNetworkSession:peer_by_unit.
for _, name in ipairs({ "anim_cbk_set_melee_item_state_vars", "anim_cbk_spawn_melee_item" }) do
    local original = HuskPlayerMovement[name]

    HuskPlayerMovement[name] = function(self, ...)
        if not self._tps_ghost then
            return original(self, ...)
        end

        ThirdPerson._ghost_peer = true
        local ok, err = blt.pcall(original, self, ...)
        ThirdPerson._ghost_peer = nil

        if not ok then
            error(err)
        end
    end
end

-- A drop-in makes the engine save every husk. The ghost belongs to no peer, so the original would fail on
-- peer_by_unit(...):id() and take the game down with it. The ghost is local only (unit id -1), nothing to save.
function HuskPlayerMovement:save(data)
    if self._tps_ghost then
        return
    end

    return tps_save(self, data)
end
