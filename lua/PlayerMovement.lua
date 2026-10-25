local tps_post_init = PlayerMovement.post_init
local tps_pre_destroy = PlayerMovement.pre_destroy

function PlayerMovement:post_init(...)
    local ret = tps_post_init(self, ...)

    ThirdPerson:safe(ThirdPerson.spawn_ghost, ThirdPerson, self._unit)

    return ret
end

if tps_pre_destroy then
    function PlayerMovement:pre_destroy(...)
        ThirdPerson:on_player_destroyed(self._unit)

        return tps_pre_destroy(self, ...)
    end
end
