local tps_set_customization = NetworkPeer.set_character_customization

-- Character customization changed (e.g. in the camp): the ghost must follow.
function NetworkPeer:set_character_customization(...)
    local ret = tps_set_customization(self, ...)

    if ThirdPerson:ghost_alive() and self == managers.network:session():local_peer() then
        ThirdPerson:safe(ThirdPerson.apply_outfit, ThirdPerson)
    end

    return ret
end
