local tps_send = NetworkBaseExtension.send

function NetworkBaseExtension:send(func, ...)
    -- The ghost is local only: whatever its code wants to send has no counterpart on the other peers.
    if self._unit == ThirdPerson.ghost then
        return
    end

    if ThirdPerson:is_local(self._unit) then
        ThirdPerson:mirror(func, ...)

        -- ghost weapon sync: nothing to tell the other peers
        if ThirdPerson._local_only and func == "set_equipped_weapon" then
            return
        end

        ThirdPerson:count_send(func)
    end

    return tps_send(self, func, ...)
end
