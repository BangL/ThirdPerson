ThirdPerson = ThirdPerson or {}

if not ThirdPerson.setup then
    ThirdPerson.setup = true

    ThirdPerson._config_defaults_path = ModPath .. "default_config.json"
    ThirdPerson._config_path = SavePath .. "ThirdPerson.json"
    ThirdPerson._config = {}
    ThirdPerson._config_defaults = {}

    -- Camera offsets in cm, relative to the player's head (aim direction); filled from the config below.
    ThirdPerson.settings = {
        blend_speed = 8, -- ADS blend
        aim_range = 20000,
    }

    -- Config keys that are camera settings and are applied to ThirdPerson.settings as they are.
    ThirdPerson.SETTING_KEYS = { "dist", "side", "up", "ads_dist", "ads_side", "ads_up", "switch_time" }

    function ThirdPerson:LoadConfigDefaults()
        local file = io.open(self._config_defaults_path)

        if file then
            self._config_defaults = json.decode(file:read("*all"))
            file:close()
        end
    end

    function ThirdPerson:LoadConfig()
        self._config = clone(self._config_defaults)

        local file = io.open(self._config_path, "r")

        if file then
            local config = json.decode(file:read("*all"))

            file:close()

            if type(config) == "table" then
                for k, v in pairs(config) do
                    if self._config_defaults[k] ~= nil then
                        self._config[k] = v
                    end
                end
            end
        end

        self:ApplyConfig()
    end

    function ThirdPerson:SaveConfig()
        local file = io.open(self._config_path, "w+")

        if file then
            file:write(json.encode(self._config))
            file:close()
        end
    end

    function ThirdPerson:GetConfigOption(id)
        return self._config[id]
    end

    -- Returns true if the value changed.
    function ThirdPerson:SetConfigOption(id, value)
        if self._config[id] == value then
            return false
        end

        self._config[id] = value
        self:ApplyConfig()

        return true
    end

    -- Camera settings take effect immediately.
    function ThirdPerson:ApplyConfig()
        for _, key in ipairs(self.SETTING_KEYS) do
            self.settings[key] = self._config[key]
        end
    end

    ThirdPerson:LoadConfigDefaults()
    ThirdPerson:LoadConfig()

    -- Husk body for remote players (blackmarket npc_unit points to a unit that does not exist).
    ThirdPerson.GHOST_UNIT = "units/vanilla/characters/players/criminal_empty/player_criminal_empty_husk"
    -- Start view; the hotkey changes it for the session only.
    if ThirdPerson.enabled == nil then
        ThirdPerson.enabled = ThirdPerson._config.start_in_tps and true or false
    end

    ThirdPerson.player_unit = nil
    ThirdPerson.ghost = nil
    ThirdPerson.aim_point = nil
    ThirdPerson._ads_t = 0

    function ThirdPerson:log(msg)
        log("[ThirdPerson] " .. tostring(msg))
    end

    -- Runs f(...) and logs errors instead of crashing the engine.
    function ThirdPerson:safe(f, ...)
        local ok, err = blt.pcall(f, ...)

        if not ok then
            self:log("error: " .. tostring(err))
        end

        return ok and err or nil
    end

    function ThirdPerson:is_local(unit)
        return alive(unit) and unit == self.player_unit
    end

    function ThirdPerson:active()
        return alive(self.player_unit)
    end

    function ThirdPerson:ghost_alive()
        return alive(self.ghost)
    end

    -- Third person view is switched on (ghost exists and the hotkey did not turn it off).
    function ThirdPerson:tps_on()
        return self.enabled and alive(self.ghost)
    end

    local function set_tree_visible(unit, visible)
        unit:set_visible(visible)

        for _, child in ipairs(unit:children()) do
            set_tree_visible(child, visible)
        end
    end

    -- Live switch between third person and first person; the camera glides over settings.switch_time.
    function ThirdPerson:set_enabled(on)
        self.enabled = on and true or false
        self._ads_t = 0
    end

    -- Steps the switch blend (0 = first person, 1 = third person) and swaps what is visible once the
    -- camera is far enough from the head to hide the change.
    function ThirdPerson:update_blend(dt)
        local target = self.enabled and 1 or 0

        -- set_rotation runs several times per frame; only step once per frame.
        local t = TimerManager:main():time()

        if not self._blend then
            self._blend = target
        elseif t ~= self._blend_t then
            self._blend = math.step(self._blend, target, dt / self.settings.switch_time)
        end

        self._blend_t = t

        local vis = self._blend > 0.35

        if vis ~= self._vis then
            self._vis = vis

            if alive(self.ghost) then
                set_tree_visible(self.ghost, vis)
            end

            if not vis then
                self:restore_fp()
            end
        end

        -- smoothstep, so the move eases in and out
        local b = self._blend

        return b * b * (3 - 2 * b)
    end

    -- Spawns the husk model for the local player (async: unit package is loaded first).
    function ThirdPerson:spawn_ghost(player_unit)
        if self:ghost_alive() and self.player_unit == player_unit then
            return
        end

        self:remove_ghost()

        self.player_unit = player_unit

        if self:peers_syncing() then
            self._suspended = true

            return
        end

        self._suspended = nil
        self._spawn_token = (self._spawn_token or 0) + 1

        local session = managers.network and managers.network:session()
        local peer = session and session:local_peer()
        local unit_path = ThirdPerson.GHOST_UNIT
        local ids_unit = Idstring(unit_path)

        managers.dyn_resource:load(IDS_UNIT, ids_unit, DynamicResourceManager.DYN_RESOURCES_PACKAGE,
            callback(self, self, "_on_ghost_loaded", {
                token = self._spawn_token,
                ids_unit = ids_unit,
                player_unit = player_unit,
            }))
    end

    function ThirdPerson:_on_ghost_loaded(params)
        if params.token ~= self._spawn_token or not alive(params.player_unit) or self:ghost_alive() then
            return
        end

        self:safe(function()
            local pu = params.player_unit

            self._spawning = true
            local ok, ghost = blt.pcall(World.spawn_unit, World, params.ids_unit, pu:position(), pu:rotation())
            self._spawning = false

            if not ok or not alive(ghost) then
                error("spawn failed: " .. tostring(ghost))
            end

            self.ghost = ghost

            -- Slot 10 (mission_elements): not a target for bullets or AI. Slot 0 would delete the unit.
            ghost:set_slot(10)

            local machine = ghost:anim_state_machine()

            machine:set_global("husk", 1)

            self:apply_outfit()

            -- Mirror the equipped weapon. Only with a weapon in hand; otherwise update_ghost retries once the player has one.
            if pu:inventory() and pu:inventory()._send_equipped_weapon and alive(pu:inventory():equipped_unit()) then
                self:sync_ghost_weapon()
            end

            self:log("ghost spawned")
        end)
    end

    -- Replays the player's equipped weapon onto the ghost only. _send_equipped_weapon builds the arguments, the
    -- send hook (NetworkBaseExtension:send) mirrors them onto the ghost and, with this flag set, drops the packet:
    -- the other peers already know the weapon and must not get it again.
    function ThirdPerson:sync_ghost_weapon()
        local pu = self.player_unit

        if not (alive(pu) and pu:inventory() and pu:inventory()._send_equipped_weapon) then
            return
        end

        self._local_only = true
        self:safe(function() pu:inventory():_send_equipped_weapon() end)
        self._local_only = nil
    end

    -- A drop-in makes the engine sync every husk to the joining client, where the ghost would show up as a
    -- real (fake) player and crash the load. So the ghost only exists while no peer is being synced.
    function ThirdPerson:peers_syncing()
        local session = managers.network and managers.network:session()

        if not session or not Network:is_server() then
            return false
        end

        for _, peer in pairs(session:all_peers()) do
            if peer._syncing then
                return true
            end
        end

        return false
    end

    function ThirdPerson:suspend_ghost()
        if alive(self.player_unit) and (self:ghost_alive() or self._spawn_token) then
            local pu = self.player_unit

            self:remove_ghost()
            self.player_unit = pu
            self._suspended = true
        end
    end

    function ThirdPerson:resume_ghost()
        if self._suspended and alive(self.player_unit) and not self:peers_syncing() then
            self._suspended = nil
            self:spawn_ghost(self.player_unit)
        end
    end

    -- (Re)attaches head/upper/lower of the local peer's current character customization to the ghost.
    function ThirdPerson:apply_outfit()
        if not self:ghost_alive() then
            return
        end

        local peer = managers.network:session():local_peer()
        local outfit = peer:blackmarket_outfit()

        self.ghost:customization():attach_all_parts_to_character_by_parts_for_husk(
            outfit.character_customization_nationality or "american",
            outfit.character_customization_head,
            outfit.character_customization_upper,
            outfit.character_customization_lower,
            peer)
    end

    -- Game is shutting down: delete the ghost while the managers it depends on still exist.
    function ThirdPerson:shutdown()
        self.enabled = false
        self:remove_ghost(true)
        self.player_unit = nil
    end

    function ThirdPerson:remove_ghost(skip_orphans)
        self._spawn_token = (self._spawn_token or 0) + 1

        if alive(self.ghost) then
            self.ghost:set_slot(10)
            World:delete_unit(self.ghost)
        end

        self.ghost = nil
        self.aim_point = nil
        self._vis = nil
        self._hidden = nil

        if not skip_orphans then
            self:remove_orphans()
        end
    end

    -- Deletes ghost units this table no longer knows about (e.g. after a script reload or a respawn race).
    -- The other players' husks share the ghost's unit name, only units marked by HuskPlayerBase:post_init are ghosts.
    function ThirdPerson:remove_orphans()
        local key = Idstring(self.GHOST_UNIT):key()

        for _, unit in ipairs(World:find_units_quick("all")) do
            if alive(unit) and unit:name():key() == key and unit ~= self.ghost and unit:base() and unit:base()._tps_ghost then
                World:delete_unit(unit)
            end
        end
    end

    function ThirdPerson:on_player_destroyed(unit)
        if unit == self.player_unit then
            self:remove_ghost()
            self.player_unit = nil
            self._suspended = nil
        end
    end

    -- The raised-weapon (aim) stance overrides the reload and equip animations of the husk, so drop it first.
    -- The next set_stance from the local player (ADS again) raises it back.
    local function lower_stance(m)
        m._aim_up_expire_t = nil

        m:sync_stance(2)
    end

    -- Replays what the local player would send over the network onto the ghost.
    ThirdPerson.SHOT_FUNCS = {
        shot_blank = true,
        shot_blank_reliable = true,
        sync_start_auto_fire_sound = true,
        sync_stop_auto_fire_sound = true,
    }

    ThirdPerson.mirror_handlers = {
        set_stance = function(m, code)
            m:sync_stance(code)
        end,
        set_pose = function(m, code)
            m:sync_pose(code)
        end,
        shot_blank = function(m, impact)
            m:sync_shot_blank(impact)
        end,
        shot_blank_reliable = function(m, impact)
            m:sync_shot_blank(impact)
        end,
        sync_start_auto_fire_sound = function(m)
            m:sync_start_auto_fire_sound()
        end,
        sync_stop_auto_fire_sound = function(m)
            m:sync_stop_auto_fire_sound()
        end,
        reload_weapon = function(m)
            lower_stance(m)
            m:sync_reload_weapon()
        end,
    }

    -- Same for what the local player sends with managers.network:session():send_to_peers_synched.
    ThirdPerson.mirror_session_handlers = {
        play_distance_interact_redirect = function(m, redirect)
            m:play_redirect(redirect)
        end,
    }

    function ThirdPerson:mirror_session(func, ...)
        local handler = self:ghost_alive() and self.mirror_session_handlers[func]

        if handler then
            self:safe(handler, self.ghost:movement(), ...)
        end
    end

    -- Diagnosis: warns in the log if the local player sends one call way too often (flood).
    ThirdPerson.SEND_WARN_PER_SEC = 120

    function ThirdPerson:count_send(func)
        local sec = math.floor(TimerManager:wall():time())

        if self._send_sec ~= sec then
            self._send_sec = sec
            self._send_counts = {}
        end

        local n = (self._send_counts[func] or 0) + 1

        self._send_counts[func] = n

        if n == self.SEND_WARN_PER_SEC then
            self:log("warning: " .. tostring(func) .. " sent " .. n .. " times within a second")
        end
    end

    function ThirdPerson:mirror(func, ...)
        if not self:ghost_alive() then
            return
        end

        local ghost = self.ghost
        local args = { ... }

        if func == "set_equipped_weapon" then
            local peer = managers.network:session():local_peer()

            self:safe(function()
                lower_stance(ghost:movement())
                ghost:inventory():synch_equipped_weapon(args[1], args[2], args[3], args[4], args[5], peer)
            end)
        elseif func == "set_weapon_gadget_state" then
            self:safe(function()
                ghost:inventory():synch_weapon_gadget_state(args[1])
            end)
        else
            local handler = self.mirror_handlers[func]

            -- In first person the ghost is hidden but would still play shot sound, flash and tracer.
            if handler and (self._vis or not self.SHOT_FUNCS[func]) then
                self:safe(handler, ghost:movement(), unpack(args))
            end
        end
    end

    -- Camera ------------------------------------------------------------------------------

    local mvec_cam = Vector3()
    local mvec_tmp = Vector3()
    local mvec_target = Vector3()

    function ThirdPerson:_in_steelsight()
        local state = alive(self.player_unit) and self.player_unit:movement() and self.player_unit:movement():current_state()

        return state and state.in_steelsight and state:in_steelsight() or false
    end

    -- Moves the render camera behind the shoulder and stores the world point under the crosshair.
    function ThirdPerson:apply_camera(cam, rot, blend)
        if not blend then
            return
        end

        local s = self.settings
        local dt = TimerManager:main():delta_time()

        self._ads_t = math.step(self._ads_t, self:_in_steelsight() and 1 or 0, dt * s.blend_speed)

        local dist = math.lerp(s.dist, s.ads_dist, self._ads_t) * blend
        local side = math.lerp(s.side, s.ads_side, self._ads_t) * blend
        local up = math.lerp(s.up, s.ads_up, self._ads_t) * blend

        local head = cam._m_cam_pos

        mvector3.set(mvec_cam, rot:y())
        mvector3.multiply(mvec_cam, -dist)
        mvector3.set(mvec_tmp, rot:x())
        mvector3.multiply(mvec_tmp, side)
        mvector3.add(mvec_cam, mvec_tmp)
        mvector3.set(mvec_tmp, math.UP)
        mvector3.multiply(mvec_tmp, up)
        mvector3.add(mvec_cam, mvec_tmp)
        mvector3.add(mvec_cam, head)

        -- Keep the camera out of walls.
        self._cam_mask = self._cam_mask or managers.slot:get_mask("world_geometry")

        local hit = World:raycast("ray", head, mvec_cam, "slot_mask", self._cam_mask, "sphere_cast_radius", 12)

        if hit then
            mvector3.set(mvec_tmp, head)
            mvector3.subtract(mvec_tmp, mvec_cam)
            mvector3.normalize(mvec_tmp)
            mvector3.set(mvec_cam, hit.position)
            mvector3.multiply(mvec_tmp, 5)
            mvector3.add(mvec_cam, mvec_tmp)
        end

        local controller = cam._camera_controller

        controller:set_camera(mvec_cam)

        mvector3.set(mvec_target, rot:y())
        mvector3.multiply(mvec_target, 100000)
        mvector3.add(mvec_target, mvec_cam)
        controller:set_target(mvec_target)

        -- Aim point: what the crosshair (screen center) points at. Start in front of the
        -- player so geometry between camera and character does not count.
        local from = mvector3.copy(rot:y())

        mvector3.multiply(from, dist)
        mvector3.add(from, mvec_cam)

        local to = mvector3.copy(rot:y())

        mvector3.multiply(to, s.aim_range)
        mvector3.add(to, from)

        self._aim_mask = self._aim_mask or managers.slot:get_mask("bullet_impact_targets")

        local ray = World:raycast("ray", from, to, "slot_mask", self._aim_mask, "ignore_unit", self.player_unit)

        self.aim_point = ray and ray.position or to
        self.aim_hit = ray and true or false
    end

    -- Other mods that aim from the head (camera position + forward) hit beside the crosshair in third person.
    -- Patched lazily, once the other mod's globals exist. Does not touch the other mods' files.
    function ThirdPerson:patch_other_mods()
        if Pings and not Pings._tps_patched and Pings._get_aim_position then
            Pings._tps_patched = true

            local original = Pings._get_aim_position

            function Pings:_get_aim_position(...)
                if ThirdPerson:tps_on() and ThirdPerson.aim_point then
                    return ThirdPerson.aim_hit and ThirdPerson.aim_point or nil
                end

                return original(self, ...)
            end
        end
    end

    -- Re-applies the camera while the game is paused (options menu), so setting changes show up live.
    function ThirdPerson:preview()
        if not (self:tps_on() and alive(self.player_unit)) then
            return
        end

        local cam = self.player_unit:camera()

        cam:set_position(cam:position())
        cam:set_rotation(cam:rotation())
    end

    -- Muzzle of the ghost's weapon, or nil if there is none.
    function ThirdPerson:muzzle_position()
        if not self:tps_on() or self:in_turret() then
            return
        end

        local weapon = self.ghost:inventory():equipped_unit()

        if not alive(weapon) then
            return
        end

        -- The fire object lives on a weapon part; the weapon base resolves it (get_object on the root unit does not).
        local obj = weapon:base()._obj_fire

        if not alive(obj) then
            return
        end

        -- the shot origin is synced to the other peers: only take a sane one (finite, close to the player)
        local pos = obj:position()
        local head = alive(self.player_unit) and self.player_unit:movement():m_head_pos()

        if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z or not head or mvector3.distance(pos, head) > 300 then
            return
        end

        return pos
    end

    -- Direction from the muzzle to the crosshair point.
    function ThirdPerson:fire_direction(muzzle)
        if not muzzle or not self.aim_point then
            return
        end

        local dir = self.aim_point - muzzle

        if mvector3.length(dir) < 50 then
            return
        end

        mvector3.normalize(dir)

        return dir
    end

    -- Ghost locomotion --------------------------------------------------------------------

    function ThirdPerson:in_turret()
        local pu = self.player_unit

        return alive(pu) and pu:movement() and pu:movement():current_state_name() == "turret"
    end

    -- Static turret: the player is warped to the turret's view point (eye height) and shoots from the turret, so the
    -- normal 1:1 follow would put the ghost's feet at the eyes. Like a network husk, the ghost goes to the turret's
    -- third person placement and plays the enter animation, then aims the turret (standing stance).
    function ThirdPerson:update_ghost_turret(m, t, dt)
        local turret = m._tps_turret

        if not turret then
            local data = managers.player:get_turret_data_for_peer(managers.network:session():local_peer():id())

            if not (data and alive(data.turret_unit) and data.turret_unit.weapon) then
                return
            end

            -- the exit animation is gone from the turret data once the player left, so keep it now
            turret = { unit = data.turret_unit, exit_animation = data.exit_animation }
            m._tps_turret = turret
            m._tps_turret_exit = nil

            local ghost = self.ghost

            ghost:inventory():hide_equipped_unit()
            ghost:set_driving("animation")

            m._tps_down = nil
            m._tps_moving = nil
            m._tps_run = nil

            local placement = turret.unit:get_object(Idstring("third_person_placement"))

            if placement then
                m:set_rotation(placement:rotation())
                m:set_position(placement:position())
            end

            if data.enter_animation then
                m:play_redirect(data.enter_animation)
            end

            return
        end

        local turret_unit = turret.unit

        if not (alive(turret_unit) and turret_unit.weapon) then
            return
        end

        -- a late weapon sync (the player equips the turret slot) must not show a weapon in the ghost's hands
        self.ghost:inventory():hide_equipped_unit()

        if not self._vis then
            set_tree_visible(self.ghost, false)
        end

        local placement = turret_unit:get_object(Idstring("third_person_placement"))

        if placement then
            m:set_rotation(placement:rotation())
            m:set_position(placement:position())
        end

        local weapon = turret_unit:weapon()
        local fire_locator = weapon._get_fire_locator and weapon:_get_fire_locator()

        if fire_locator and weapon._puppet_stance == "standing" then
            local current_direction = fire_locator:rotation():y()

            mvector3.negate(current_direction)
            mvector3.multiply(current_direction, 1000)

            local original_direction = turret_unit:rotation():y()

            mvector3.multiply(original_direction, 1000)

            local deflection = original_direction:angle(current_direction)
            local deflection_direction = math.sign((original_direction - current_direction):to_polar_with_reference(current_direction, math.UP).spin)
            local spin_max = turret_unit:movement()._spin_max or deflection
            local deflection_normalized = spin_max ~= 0 and math.clamp(math.abs(deflection), 0, math.abs(spin_max)) / math.abs(spin_max) or 0
            local side = deflection_direction < 0 and "left" or "right"

            m._machine:set_parameter(Idstring("std/stand/so/idle/e_so_mg34_aim_" .. side), "t", deflection_normalized)
            m:play_redirect("e_so_mg34_aim_" .. side)
        end
    end

    -- The player is warped away at once, the ghost stays at the turret while the (sped up) exit animation plays.
    ThirdPerson.TURRET_EXIT_SPEED = 2
    ThirdPerson.TURRET_EXIT_TIME = 0.6

    function ThirdPerson:exit_ghost_turret(m, t)
        local turret = m._tps_turret

        m._tps_turret = nil

        if turret.exit_animation and alive(turret.unit) and m:play_redirect(turret.exit_animation) then
            m._machine:set_speed(m._machine:segment_state(m._ids_base), self.TURRET_EXIT_SPEED)

            m._tps_turret_exit = { unit = turret.unit, t_start = t, t_end = t + self.TURRET_EXIT_TIME }
        else
            self:finish_ghost_turret_exit(m)
        end
    end

    -- Returns true while the exit animation still owns the ghost.
    function ThirdPerson:update_ghost_turret_exit(m, t)
        local exit = m._tps_turret_exit

        if t < exit.t_end and alive(exit.unit) then
            local placement = exit.unit:get_object(Idstring("third_person_placement"))

            if placement then
                -- glide from the turret to wherever the player is by now, so the end is no jump
                local k = math.clamp((t - exit.t_start) / (exit.t_end - exit.t_start), 0, 1)
                local pos = Vector3()

                mvector3.lerp(pos, placement:position(), self.player_unit:position(), k * k * (3 - 2 * k))

                m:set_rotation(placement:rotation())
                m:set_position(pos)
            end

            self.ghost:inventory():hide_equipped_unit()

            return true
        end

        self:finish_ghost_turret_exit(m)

        return false
    end

    function ThirdPerson:finish_ghost_turret_exit(m)
        local ghost = self.ghost

        m._tps_turret_exit = nil
        m._tps_last_pos = nil

        m._machine:set_speed(m._machine:segment_state(m._ids_base), 1)
        ghost:set_driving("script")
        ghost:inventory():show_equipped_unit()

        if not m:play_redirect("stand") then
            m:play_state("std/stand/still/idle/look")
        end
    end

    -- Replaces HuskPlayerMovement:update for the ghost: the player moves, the ghost follows 1:1
    -- and only picks the matching animations (same helpers the network husk uses).
    function ThirdPerson:update_ghost(m, t, dt)
        local pu = self.player_unit

        if not alive(pu) or dt <= 0 then
            return
        end

        if self:in_turret() then
            return self:update_ghost_turret(m, t, dt)
        elseif m._tps_turret then
            self:exit_ghost_turret(m, t)
        end

        if m._tps_turret_exit and self:update_ghost_turret_exit(m, t) then
            return
        end

        -- Right after load the player has no weapon yet when the ghost spawns, so the first sync is lost
        -- and the ghost stays in T-pose until the player equips/shoots. Retry until it sticks.
        if not m._tps_synced then
            local weapon = pu:inventory() and pu:inventory():equipped_unit()

            if alive(weapon) then
                if not alive(self.ghost:inventory():equipped_unit()) and t >= (m._tps_retry_t or 0) then
                    -- local only (see sync_ghost_weapon), but still no per-frame spam; gives up after a few tries
                    m._tps_retries = (m._tps_retries or 0) + 1
                    m._tps_retry_t = t + 1

                    if m._tps_retries <= 5 then
                        self:sync_ghost_weapon()
                    elseif m._tps_retries == 6 then
                        self:log("ghost got no weapon after 5 tries, giving up")
                    end
                end

                if alive(self.ghost:inventory():equipped_unit()) then
                    m._tps_synced = true

                    m:sync_pose(pu:movement():current_state():ducking() and 2 or 1)
                    m:sync_stance(self:_in_steelsight() and 3 or 2)
                end
            end
        end

        -- Weapons equipped while in first person would show up on the hidden ghost.
        if not self._vis then
            set_tree_visible(self.ghost, false)
        end

        local pos = pu:position()
        local last = m._tps_last_pos or pos
        local vel = mvector3.copy(pos)

        mvector3.subtract(vel, last)
        mvector3.set_z(vel, 0)
        mvector3.divide(vel, dt)

        m._tps_last_pos = mvector3.copy(pos)

        m:set_position(pos)

        -- The ghost aims at the crosshair point, not parallel to the camera (camera is offset to the shoulder).
        local look = pu:camera():forward()

        if self.aim_point then
            local to_aim = self.aim_point - m._m_head_pos

            if mvector3.length(to_aim) > 150 then
                mvector3.normalize(to_aim)
                look = to_aim
            end
        end

        m:set_look_dir_instant(look)
        m:_calculate_m_pose()

        -- Legs follow the look direction with a max waist twist of 45 degrees.
        local look_flat = look:with_z(0)

        mvector3.normalize(look_flat)

        local waist_twist = look_flat:to_polar_with_reference(m._m_rot:y(), math.UP).spin
        local sign = math.sign(waist_twist)
        local adj = math.min(math.abs(waist_twist), 360 * dt)
        local twist_new = waist_twist - sign * adj

        if math.abs(twist_new) > 45 then
            twist_new = sign * 45
        end

        m:set_rotation(Rotation(look_flat, math.UP) * Rotation(-twist_new))

        m:_upd_stance(t)

        local ext_anim = m._ext_anim

        -- Downed: the husk update (which would start the bleedout animation) is replaced, so do it here.
        if pu:movement():current_state_name() == "bleed_out" then
            if not m._tps_down then
                m._tps_down = true

                m:play_redirect(managers.buff_effect:is_effect_active(BuffEffectManager.EFFECT_ONLY_MELEE_AVAILABLE) and "fatal" or "bleedout")
            end

            return
        elseif m._tps_down then
            m._tps_down = nil

            if not m:play_redirect("stand") then
                m:play_state("std/stand/still/idle/look")
            end
        end

        if m._pose_code == 1 then
            if not ext_anim.stand then
                m:play_redirect("stand")
            end
        elseif m._pose_code == 3 then
            if not ext_anim.prone then
                m:play_redirect("prone")
            end
        elseif not ext_anim.crouch then
            m:play_redirect("crouch")
        end

        -- Raw per-frame velocity jitters (running speed sits right on the sprint threshold), which made
        -- the ghost flip between animations. Smooth it and take sprint from the player's real state.
        m._tps_vel_len = math.lerp(m._tps_vel_len or 0, mvector3.length(vel), math.min(1, dt * 12))

        local vel_len = m._tps_vel_len

        m._tps_moving = vel_len > (m._tps_moving and 15 or 40)

        if m._tps_moving then
            local fwd = m._m_rot:y()
            local right = fwd:cross(math.UP)
            local dir = vel / vel_len
            local fwd_dot, right_dot = dir:dot(fwd), dir:dot(right)
            local side

            if math.abs(fwd_dot) > math.abs(right_dot) then
                side = fwd_dot > 0 and "fwd" or "bwd"
            else
                side = right_dot > 0 and "r" or "l"
            end

            local state = pu:movement():current_state()
            local sprinting = m._pose_code == 1 and state.running and state:running()

            m._tps_run = vel_len > (m._tps_run and 270 or 330)

            local speed_name = sprinting and "sprint" or m._tps_run and "run" or "walk"

            m:_adjust_move_anim(side, speed_name)

            local pose, stance = ext_anim.pose, m._stance.name
            local anims = m._walk_anim_velocities[pose]
            local animated = anims and anims[stance] and anims[stance][speed_name] and anims[stance][speed_name][side]

            if animated then
                m:_adjust_walk_anim_speed(dt, vel_len / animated)
            end
        elseif ext_anim.move then
            m:play_redirect("idle")
        end
    end

    -- Hides a unit and, recursively, everything attached to it (weapon parts, hands).
    -- Remembers what it hid so first person can restore exactly that.
    function ThirdPerson:_hide_tree(unit)
        if unit:visible() then
            unit:set_visible(false)
            self._hidden = self._hidden or {}
            self._hidden[#self._hidden + 1] = unit
        end

        for _, child in ipairs(unit:children()) do
            self:_hide_tree(child)
        end
    end

    function ThirdPerson:restore_fp()
        for _, unit in ipairs(self._hidden or {}) do
            if alive(unit) then
                unit:set_visible(true)
            end
        end

        self._hidden = nil
    end

    function ThirdPerson:hide_fp(camera_unit, player_unit)
        if not (self._vis and alive(self.ghost)) then
            return
        end

        self:_hide_tree(camera_unit)

        local fps = camera_unit:customizationfps()

        for _, attached in pairs(fps and fps._attached_units or {}) do
            if alive(attached) then
                self:_hide_tree(attached)
            end
        end

        local weapon = alive(player_unit) and player_unit:inventory() and player_unit:inventory():equipped_unit()

        if alive(weapon) then
            self:_hide_tree(weapon)
        end
    end
end
