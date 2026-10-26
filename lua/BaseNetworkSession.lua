local tps_send_to_peers_synched = BaseNetworkSession.send_to_peers_synched
local tps_peer_by_unit = BaseNetworkSession.peer_by_unit

-- Some of what the player sends to the others is not a unit network call (e.g. the melee swing), mirror it onto the ghost.
function BaseNetworkSession:send_to_peers_synched(func, unit, ...)
    if func == "play_distance_interact_redirect" and ThirdPerson:is_local(unit) then
        ThirdPerson:mirror_session(func, ...)
    end

    return tps_send_to_peers_synched(self, func, unit, ...)
end

-- The ghost belongs to no peer. While one of its melee callbacks runs it is the local peer, the callbacks read the melee weapon from it.
function BaseNetworkSession:peer_by_unit(unit)
    if ThirdPerson._ghost_peer and unit == ThirdPerson.ghost then
        return self:local_peer()
    end

    return tps_peer_by_unit(self, unit)
end
