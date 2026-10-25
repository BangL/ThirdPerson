local tps_is_ads_fade = HUDManager.is_motion_dot_ads_fade

-- The motion dot is hidden while aiming down sights; in third person it stays.
function HUDManager:is_motion_dot_ads_fade()
    if ThirdPerson:tps_on() and ThirdPerson:GetConfigOption("keep_hud_in_ads") then
        return false
    end

    return tps_is_ads_fade(self)
end
