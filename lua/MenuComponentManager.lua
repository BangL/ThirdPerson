-- options menu

ThirdPersonMenu = ThirdPersonMenu or class(BLTMenu)

function ThirdPersonMenu:Init(root)
	self._something_changed = false

	self:_MakePreviewBackground()

	self:_MakeHeader()

	self:EnableScrolling() -- header stays fixed, everything below scrolls

	self:AutoBindNamedControlsBegin()

	self:_MakeSeparator("tps_cat_general", true, 16)

	self:_MakeOptionToggle("start_in_tps")
	self:_MakeOptionToggle("keep_hud_in_ads")
	self:_MakeOptionSlider("switch_time", 0.05, 1, 2)

	self:_MakeSeparator("tps_cat_camera", true, 16)

	self:_MakeOptionSlider("dist", 50, 400, 0)
	self:_MakeOptionSlider("side", -100, 100, 0)
	self:_MakeOptionSlider("up", -50, 100, 0)

	self:_MakeSeparator("tps_cat_ads", true, 16)

	self:_MakeOptionSlider("ads_dist", 30, 300, 0)
	self:_MakeOptionSlider("ads_side", -100, 100, 0)
	self:_MakeOptionSlider("ads_up", -50, 100, 0)

	self._reset_btn = self:_MakeResetButton()
	self:AutoBindNamedControlsEnd()
end

-- In game, the menu background (blur, grayscale, vignette) covers the whole screen. Replace it by a dark
-- gradient behind the options only, so the middle shows the game with the current camera settings.
function ThirdPersonMenu:_MakePreviewBackground()
	if RaidMenuCallbackHandler:is_in_main_menu() or not alive(ThirdPerson.player_unit) then
		return
	end

	self._background_hidden = true
	self:HideBackground()

	-- The menu workspace is clipped to the safe rect. The menu background lives in its own fullscreen
	-- workspace (below the menu), so the shade goes there, which lets it reach the screen edge.
	local background = managers.raid_menu._background_image
	local parent = background and background._hud_panel

	-- (alive() is for units; gui objects are plain userdata)
	if not parent then
		return
	end

	self._shade_parent = parent
	self._preview_shade = parent:gradient({
		name = "tps_preview_shade",
		x = 0,
		y = 0,
		w = math.min(900, parent:w()),
		h = parent:h(),
		layer = 1,
		orientation = "horizontal",
	})

	self._preview_shade:set_gradient_points({
		0,
		Color(0.8, 0, 0, 0),
		0.65,
		Color(0.55, 0, 0, 0),
		1,
		Color(0, 0, 0, 0),
	})
end

function ThirdPersonMenu:Update(t, dt)
	if self._background_hidden then
		ThirdPerson:safe(ThirdPerson.preview, ThirdPerson)
	end
end

function ThirdPersonMenu:_additional_active_controls()
	return {
		self._reset_btn
	}
end

function ThirdPersonMenu:_MakeHeader()
	self:Title({
		text = "tps_title",
	})
	self:Label({
		text = nil,
		localize = false,
		h = 8,
	})
end

function ThirdPersonMenu:_MakeResetButton()
	return self:LongRoundedButton2({
		name = "tps_reset",
		text = "tps_reset",
		localize = true,
		callback = callback(self, self, "Reset"),
		ignore_align = true,
		y = 832,
		x = 1472,
		auto_select_on_hover = true
	})
end

function ThirdPersonMenu:_MakeSeparator(text, localize, y_offset)
	self:SubTitle({ text = text, localize = localize, y_offset = y_offset and y_offset or (text and 0 or 8) })
end

function ThirdPersonMenu:_MakeOptionToggle(option)
	local id = "tps_" .. option
	self:Toggle({
		name = id,
		text = managers.localization:text(id),
		localize = false,
		localized = false,
		desc = managers.localization:text(id .. "_desc"),
		localize_desc = false,
		localized_desc = false,
		value = ThirdPerson:GetConfigOption(option),
		callback = callback(self, self, "OnOptionChanged", option),
		auto_select_on_hover = true
	})
end

function ThirdPersonMenu:_MakeOptionSlider(option, min, max, decimals)
	local id = "tps_" .. option
	self:Slider({
		name = id,
		text = id,
		desc = id .. "_desc",
		value = ThirdPerson:GetConfigOption(option),
		callback = callback(self, self, "OnOptionChanged", option),
		min = min or 0,
		max = max or 100,
		value_format = "%." .. (decimals or 0) .. "f",
		auto_select_on_hover = true
	})
end

function ThirdPersonMenu:OnOptionChanged(option, value)
	if ThirdPerson:SetConfigOption(option, (type(value) == "table") and value.value or value) then
		self._something_changed = true
	end
end

function ThirdPersonMenu:Reset(value, item)
	QuickMenu:new(
		managers.localization:text("tps_reset"),
		managers.localization:text("tps_reset_confirm"),
		{
			{
				text = managers.localization:text("dialog_yes"),
				callback = function()
					-- reset config
					ThirdPerson._config = clone(ThirdPerson._config_defaults)
					ThirdPerson:ApplyConfig()
					ThirdPerson:SaveConfig()
					-- reset menu
					self._something_changed = false
					self:ReloadMenu()
				end,
			},
			{
				text = managers.localization:text("dialog_no"),
				is_cancel_button = true,
			},
		},
		true
	)
end

function ThirdPersonMenu:Close()
	if self._something_changed then
		ThirdPerson:SaveConfig()
	end

	if self._preview_shade and self._shade_parent then
		blt.pcall(self._shade_parent.remove, self._shade_parent, self._preview_shade)
	end

	self._preview_shade = nil
	self._shade_parent = nil

	if self._background_hidden then
		self._background_hidden = false
		self:ShowBackground()
	end
end

Hooks:Add("MenuComponentManagerInitialize", "ThirdPerson_MenuComponentManagerInitialize",
	function(self)
		RaidMenuHelper:CreateMenu({
			name = "tps_options",
			name_id = "tps_title",
			inject_list = "blt_options",
			icon = "waypoint_special_escape",
			class = ThirdPersonMenu
		})
	end
)
