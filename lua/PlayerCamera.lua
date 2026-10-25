local tps_set_rotation = PlayerCamera.set_rotation

function PlayerCamera:set_rotation(rot)
    tps_set_rotation(self, rot)

    if ThirdPerson:is_local(self._unit) and ThirdPerson:ghost_alive() then
        ThirdPerson:safe(ThirdPerson.patch_other_mods, ThirdPerson)

        local blend = ThirdPerson:safe(ThirdPerson.update_blend, ThirdPerson, TimerManager:main():delta_time())

        if blend and blend > 0 then
            ThirdPerson:safe(ThirdPerson.apply_camera, ThirdPerson, self, rot, blend)
        end
    end
end
