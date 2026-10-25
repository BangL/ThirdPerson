local tps_destroy = GameSetup.destroy

function GameSetup:destroy(...)
    ThirdPerson:safe(ThirdPerson.shutdown, ThirdPerson)

    return tps_destroy(self, ...)
end
