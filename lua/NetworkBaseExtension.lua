local tps_send = NetworkBaseExtension.send

function NetworkBaseExtension:send(func, ...)
    if ThirdPerson:is_local(self._unit) then
        ThirdPerson:mirror(func, ...)
    end

    return tps_send(self, func, ...)
end
