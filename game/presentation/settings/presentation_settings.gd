class_name PresentationSettings
extends RefCounted
## View-only settings from `user://settings.cfg` (Godot ConfigFile) with the keys of
## `.work/config/v7/settings.example.cfg`; nothing here may change the simulation.

const DEFAULT_PATH: String = "user://settings.cfg"
const LOCALES: PackedStringArray = ["auto", "en", "ru"]
const DAMAGE_NUMBER_MODES: PackedStringArray = ["off", "aggregate", "all"]
## Runtime clamps: the own-skill effect stays visible, the interface stays legible.
const MIN_OWN_SKILL_OPACITY: float = 0.2
const MIN_FONT_SCALE: float = 0.5
const MAX_FONT_SCALE: float = 2.0

var preferred_locale: String = "auto"
var vfx_intensity: float = 0.65
var screenshake: float = 0.40
var hit_flash: float = 1.0
var own_skill_opacity: float = 0.8
var floating_damage_numbers: String = "aggregate"
var font_scale: float = 1.0
var log_choices: bool = false


## The stored settings, or the defaults when the file is missing, unreadable or corrupt.
static func load_from(path: String = DEFAULT_PATH) -> PresentationSettings:
	var settings: PresentationSettings = PresentationSettings.new()
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return settings
	settings.preferred_locale = _text(config, "localization", "preferred_locale", LOCALES,
		settings.preferred_locale)
	settings.vfx_intensity = clampf(_number(config, "graphics", "vfx_intensity",
		settings.vfx_intensity), 0.0, 1.0)
	settings.screenshake = clampf(_number(config, "graphics", "screenshake",
		settings.screenshake), 0.0, 1.0)
	settings.hit_flash = clampf(_number(config, "graphics", "hit_flash",
		settings.hit_flash), 0.0, 1.0)
	settings.own_skill_opacity = clampf(_number(config, "graphics", "own_skill_opacity",
		settings.own_skill_opacity), MIN_OWN_SKILL_OPACITY, 1.0)
	settings.floating_damage_numbers = _text(config, "graphics", "floating_damage_numbers",
		DAMAGE_NUMBER_MODES, settings.floating_damage_numbers)
	settings.font_scale = clampf(_number(config, "accessibility", "font_scale",
		settings.font_scale), MIN_FONT_SCALE, MAX_FONT_SCALE)
	settings.log_choices = _flag(config, "playtest", "log_choices", settings.log_choices)
	return settings


## Writes all eight keys; unknown sections and keys are not carried over.
func save_to(path: String = DEFAULT_PATH) -> Error:
	var parent: String = path.get_base_dir()
	if parent != "user://":
		DirAccess.make_dir_recursive_absolute(parent)
	var config: ConfigFile = ConfigFile.new()
	config.set_value("localization", "preferred_locale", preferred_locale)
	config.set_value("graphics", "vfx_intensity", vfx_intensity)
	config.set_value("graphics", "screenshake", screenshake)
	config.set_value("graphics", "hit_flash", hit_flash)
	config.set_value("graphics", "own_skill_opacity", own_skill_opacity)
	config.set_value("graphics", "floating_damage_numbers", floating_damage_numbers)
	config.set_value("accessibility", "font_scale", font_scale)
	config.set_value("playtest", "log_choices", log_choices)
	return config.save(path)


## The look of tests, replays and reference captures: the current look whatever a player saved.
## No screen shake, a number on every blow (as before the setting existed) and fully opaque own
## effects; the rest are the defaults.
static func reference_look() -> PresentationSettings:
	var settings: PresentationSettings = PresentationSettings.new()
	settings.screenshake = 0.0
	settings.floating_damage_numbers = "all"
	settings.own_skill_opacity = 1.0
	return settings


## A separate copy with the same eight values.
func duplicate_settings() -> PresentationSettings:
	var copy: PresentationSettings = PresentationSettings.new()
	copy.preferred_locale = preferred_locale
	copy.vfx_intensity = vfx_intensity
	copy.screenshake = screenshake
	copy.hit_flash = hit_flash
	copy.own_skill_opacity = own_skill_opacity
	copy.floating_damage_numbers = floating_damage_numbers
	copy.font_scale = font_scale
	copy.log_choices = log_choices
	return copy


static func _text(config: ConfigFile, section: String, key: String, allowed: PackedStringArray,
		fallback: String) -> String:
	var value: Variant = config.get_value(section, key, fallback)
	if typeof(value) != TYPE_STRING:
		return fallback
	var text: String = value
	return text if allowed.has(text) else fallback


static func _number(config: ConfigFile, section: String, key: String, fallback: float) -> float:
	var value: Variant = config.get_value(section, key, fallback)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


static func _flag(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = config.get_value(section, key, fallback)
	if typeof(value) != TYPE_BOOL:
		return fallback
	var flag: bool = value
	return flag
