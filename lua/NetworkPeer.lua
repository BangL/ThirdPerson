local tps_set_customization = NetworkPeer.set_character_customization

-- Character customization changed (e.g. in the camp): the ghost must follow.
function NetworkPeer:set_character_customization(...)
    local ret = tps_set_customization(self, ...)

    if ThirdPerson:ghost_alive() and self == managers.network:session():local_peer() then
        ThirdPerson:safe(ThirdPerson.apply_outfit, ThirdPerson)
    end

    return ret
end

local tps_on_sync_start = NetworkPeer.on_sync_start
local tps_set_synched = NetworkPeer.set_synched

-- Drop-in: the engine syncs every husk to the joining peer, the ghost must not exist meanwhile.
function NetworkPeer:on_sync_start(...)
    ThirdPerson:safe(ThirdPerson.suspend_ghost, ThirdPerson)

    return tps_on_sync_start(self, ...)
end

function NetworkPeer:set_synched(...)
    local ret = tps_set_synched(self, ...)

    ThirdPerson:safe(ThirdPerson.resume_ghost, ThirdPerson)

    return ret
end
