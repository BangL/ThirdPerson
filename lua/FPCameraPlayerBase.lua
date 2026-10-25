local tps_update = FPCameraPlayerBase.update

function FPCameraPlayerBase:update(unit, t, dt)
    tps_update(self, unit, t, dt)

    if ThirdPerson:is_local(self._parent_unit) then
        ThirdPerson:hide_fp(self._unit, self._parent_unit)
    end
end
