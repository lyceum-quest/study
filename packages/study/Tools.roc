## The study tools a passage offers (per-word glosses and the two
## translations) and the presets that switch them, ported from the `Preset`,
## `ModuleId`, `ModuleMode` and `ModuleSettings` types of `src/Main.elm` and the
## functions over them.
Tools := [].{

	Preset : [ReadPreset, AssistedPreset, IntensivePreset, CustomPreset]

	ModuleId : [GlossModule, LiteralModule, ProseModule]

	ModuleMode : [ModuleOff, OnDemand]

	ModuleSettings : { gloss : ModuleMode, literal : ModuleMode, prose : ModuleMode }

	## The Elm app starts with the Assisted preset.
	default_preset : Preset
	default_preset = AssistedPreset

	read_settings : ModuleSettings
	read_settings = { gloss: OnDemand, literal: ModuleOff, prose: ModuleOff }

	assisted_settings : ModuleSettings
	assisted_settings = { gloss: OnDemand, literal: ModuleOff, prose: OnDemand }

	intensive_settings : ModuleSettings
	intensive_settings = { gloss: OnDemand, literal: OnDemand, prose: OnDemand }

	## The custom preset keeps the `current` settings.
	settings_for_preset : Preset, ModuleSettings -> ModuleSettings
	settings_for_preset = |preset, current|
		match preset {
			ReadPreset => read_settings
			AssistedPreset => assisted_settings
			IntensivePreset => intensive_settings
			CustomPreset => current
		}

	preset_label : Preset -> Str
	preset_label = |preset|
		match preset {
			ReadPreset => "Read"
			AssistedPreset => "Assisted"
			IntensivePreset => "Intensive"
			CustomPreset => "Custom"
		}

	module_mode : ModuleId, ModuleSettings -> ModuleMode
	module_mode = |module_id, settings|
		match module_id {
			GlossModule => settings.gloss
			LiteralModule => settings.literal
			ProseModule => settings.prose
		}

	set_module_mode : ModuleId, ModuleMode, ModuleSettings -> ModuleSettings
	set_module_mode = |module_id, mode, settings|
		match module_id {
			GlossModule => { ..settings, gloss: mode }
			LiteralModule => { ..settings, literal: mode }
			ProseModule => { ..settings, prose: mode }
		}

	## The modules not switched off, in tray order.
	enabled_modules : ModuleSettings -> List(ModuleId)
	enabled_modules = |settings| [GlossModule, LiteralModule, ProseModule].keep_if(|module_id| module_mode(module_id, settings) != ModuleOff)

	module_key : ModuleId -> Str
	module_key = |module_id|
		match module_id {
			GlossModule => "gloss"
			LiteralModule => "literal"
			ProseModule => "prose"
		}

	module_from_key : Str -> [Some(ModuleId), None]
	module_from_key = |key|
		match key {
			"gloss" => Some(GlossModule)
			"literal" => Some(LiteralModule)
			"prose" => Some(ProseModule)
			_ => None
		}

	module_name : ModuleId -> Str
	module_name = |module_id|
		match module_id {
			GlossModule => "Glosses"
			LiteralModule => "Literal translation"
			ProseModule => "Prose translation"
		}
}
