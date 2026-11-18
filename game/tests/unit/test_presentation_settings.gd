extends GutTest
## Q1: the view-only settings store. Defaults equal settings.example.cfg, the store round-trips,
## clamps what it reads, falls back on a broken file and never treats a mistyped value as valid.

const PATH: String = "user://test_presentation_settings.cfg"


func before_each() -> void:
	_remove_file()


func after_each() -> void:
	_remove_file()


func _remove_file() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _write(config: ConfigFile) -> void:
	assert_eq(config.save(PATH), OK, "test config saved")


func test_a_missing_file_gives_the_example_defaults() -> void:
	var settings: PresentationSettings = PresentationSettings.load_from(PATH)
	assert_eq(settings.preferred_locale, "auto")
	assert_almost_eq(settings.vfx_intensity, 0.65, 0.0001)
	assert_almost_eq(settings.screenshake, 0.40, 0.0001)
	assert_almost_eq(settings.hit_flash, 1.0, 0.0001)
	assert_almost_eq(settings.own_skill_opacity, 0.8, 0.0001)
	assert_eq(settings.floating_damage_numbers, "aggregate")
	assert_almost_eq(settings.font_scale, 1.0, 0.0001)
	assert_false(settings.log_choices)


func test_save_and_load_round_trip() -> void:
	var settings: PresentationSettings = PresentationSettings.new()
	settings.preferred_locale = "ru"
	settings.vfx_intensity = 0.3
	settings.screenshake = 0.0
	settings.hit_flash = 0.5
	settings.own_skill_opacity = 0.25
	settings.floating_damage_numbers = "off"
	settings.font_scale = 1.5
	settings.log_choices = true
	assert_eq(settings.save_to(PATH), OK, "settings saved")
	var loaded: PresentationSettings = PresentationSettings.load_from(PATH)
	assert_eq(loaded.preferred_locale, "ru")
	assert_almost_eq(loaded.vfx_intensity, 0.3, 0.0001)
	assert_almost_eq(loaded.screenshake, 0.0, 0.0001)
	assert_almost_eq(loaded.hit_flash, 0.5, 0.0001)
	assert_almost_eq(loaded.own_skill_opacity, 0.25, 0.0001)
	assert_eq(loaded.floating_damage_numbers, "off")
	assert_almost_eq(loaded.font_scale, 1.5, 0.0001)
	assert_true(loaded.log_choices)


func test_values_are_clamped_when_loaded() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("graphics", "screenshake", 3.0)
	config.set_value("graphics", "hit_flash", -1.0)
	config.set_value("graphics", "own_skill_opacity", 0.05)
	config.set_value("graphics", "vfx_intensity", 1)
	config.set_value("accessibility", "font_scale", 9.0)
	_write(config)
	var settings: PresentationSettings = PresentationSettings.load_from(PATH)
	assert_almost_eq(settings.screenshake, 1.0, 0.0001)
	assert_almost_eq(settings.hit_flash, 0.0, 0.0001)
	assert_almost_eq(settings.own_skill_opacity, 0.2, 0.0001)
	assert_almost_eq(settings.vfx_intensity, 1.0, 0.0001, "an int is a number")
	assert_almost_eq(settings.font_scale, 2.0, 0.0001)


func test_wrong_types_and_values_fall_back_to_defaults() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("graphics", "screenshake", "strong")
	config.set_value("localization", "preferred_locale", "de")
	config.set_value("graphics", "floating_damage_numbers", "some")
	config.set_value("playtest", "log_choices", 1)
	config.set_value("accessibility", "font_scale", "big")
	_write(config)
	var settings: PresentationSettings = PresentationSettings.load_from(PATH)
	assert_almost_eq(settings.screenshake, 0.40, 0.0001)
	assert_eq(settings.preferred_locale, "auto")
	assert_eq(settings.floating_damage_numbers, "aggregate")
	assert_false(settings.log_choices)
	assert_almost_eq(settings.font_scale, 1.0, 0.0001)


func test_a_corrupt_file_gives_the_defaults() -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	assert_not_null(file, "test file opened")
	if file == null:
		return
	file.store_string("not [a config")
	file.close()
	var settings: PresentationSettings = PresentationSettings.load_from(PATH)
	assert_eq(settings.preferred_locale, "auto")
	assert_almost_eq(settings.vfx_intensity, 0.65, 0.0001)
	assert_almost_eq(settings.screenshake, 0.40, 0.0001)
	assert_almost_eq(settings.hit_flash, 1.0, 0.0001)
	assert_almost_eq(settings.own_skill_opacity, 0.8, 0.0001)
	assert_eq(settings.floating_damage_numbers, "aggregate")
	assert_almost_eq(settings.font_scale, 1.0, 0.0001)
	assert_false(settings.log_choices)


func test_unknown_sections_and_keys_are_ignored() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "volume", 0.5)
	config.set_value("graphics", "bloom", 1.0)
	config.set_value("graphics", "screenshake", 0.25)
	config.set_value("accessibility", "font_scale", 1.25)
	_write(config)
	var settings: PresentationSettings = PresentationSettings.load_from(PATH)
	assert_almost_eq(settings.screenshake, 0.25, 0.0001)
	assert_almost_eq(settings.font_scale, 1.25, 0.0001)
	assert_almost_eq(settings.vfx_intensity, 0.65, 0.0001, "bloom is not vfx_intensity")


func test_reference_turns_off_the_varying_amplifiers() -> void:
	var settings: PresentationSettings = PresentationSettings.reference_look()
	assert_eq(settings.screenshake, 0.0)
	assert_eq(settings.floating_damage_numbers, "off")
	assert_eq(settings.own_skill_opacity, 1.0)
	assert_almost_eq(settings.hit_flash, 1.0, 0.0001, "the current hit flash look is kept")
	assert_eq(settings.preferred_locale, "auto")
	assert_false(settings.log_choices)


func test_duplicate_settings_is_a_separate_copy() -> void:
	var settings: PresentationSettings = PresentationSettings.new()
	settings.preferred_locale = "en"
	settings.vfx_intensity = 0.3
	settings.screenshake = 0.0
	settings.hit_flash = 0.5
	settings.own_skill_opacity = 0.25
	settings.floating_damage_numbers = "all"
	settings.font_scale = 1.5
	settings.log_choices = true
	var copy: PresentationSettings = settings.duplicate_settings()
	assert_ne(copy, settings)
	assert_eq(copy.preferred_locale, "en")
	assert_almost_eq(copy.vfx_intensity, 0.3, 0.0001)
	assert_almost_eq(copy.screenshake, 0.0, 0.0001)
	assert_almost_eq(copy.hit_flash, 0.5, 0.0001)
	assert_almost_eq(copy.own_skill_opacity, 0.25, 0.0001)
	assert_eq(copy.floating_damage_numbers, "all")
	assert_almost_eq(copy.font_scale, 1.5, 0.0001)
	assert_true(copy.log_choices)
	copy.preferred_locale = "ru"
	copy.log_choices = false
	assert_eq(settings.preferred_locale, "en", "the original keeps its value")
	assert_true(settings.log_choices, "the original keeps its value")
