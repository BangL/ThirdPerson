local tps_update = HuskPlayerMovement.update
local tps_destroy = HuskPlayerMovement.destroy

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
