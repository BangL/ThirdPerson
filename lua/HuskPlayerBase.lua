local tps_post_init = HuskPlayerBase.post_init
local tps_pre_destroy = HuskPlayerBase.pre_destroy

-- The ghost is a purely visual husk: no group AI registration, no attention object, no nav tracker.
function HuskPlayerBase:post_init()
    if not ThirdPerson._spawning then
        return tps_post_init(self)
    end

    local m = self._unit:movement()

    self._ext_anim = self._unit:anim_data()
    self._lod_stage = 1
    self._allow_invisible = true
    self._tps_ghost = true

    managers.occlusion:remove_occlusion(self._unit)
    self:set_anim_lod(1)

    m._tps_ghost = true
    -- Teardown code calls into the attention handler; give it a no-op stub.
    m._attention_handler = setmetatable({}, { __index = function() return function() end end })
    m._ext_anim = self._unit:anim_data()

    self._unit:inventory():add_listener("HuskPlayerMovement", { "equip" }, callback(m, m, "clbk_inventory_event"))
    m:set_player_class(SkillTreeTweakData.CLASS_RECON)
    m:play_state("std/stand/still/idle/look")
end

function HuskPlayerBase:pre_destroy(unit)
    if self._tps_ghost then
        return UnitBase.pre_destroy(self, unit)
    end

    return tps_pre_destroy(self, unit)
end
