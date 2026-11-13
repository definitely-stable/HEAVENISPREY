class_name UiText
extends RefCounted
## RU/EN UI strings. tools/content/ui_strings.py builds res://content/locale/strings.json from
## the Godot import CSV `.work/config/v7/translations.csv`; this class registers one Translation
## per locale in TranslationServer, so presentation code uses tr(KEY) or UiText.text(KEY).
## Presentation only: the simulation never reads strings.

const PATH: String = "res://content/locale/strings.json"
const SCHEMA_VERSION: int = 1
const LOCALES: PackedStringArray = ["en", "ru"]
const FALLBACK: String = "en"

## Why the last ensure_loaded() failed ("" after a success).
static var error: String = ""
static var _loaded_from: String = ""


## Registers the translations of `path` once; false when the file is missing or malformed.
static func ensure_loaded(path: String = PATH) -> bool:
	if _loaded_from == path:
		error = ""
		return true
	if not FileAccess.file_exists(path):
		error = "UI strings not found: " + path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		error = "UI strings not readable: " + path
		return false
	var data: Dictionary = parsed
	var strings: Variant = data.get("strings")
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION or typeof(strings) != TYPE_DICTIONARY:
		error = "UI strings have an unexpected format: " + path
		return false
	for locale: String in LOCALES:
		var translation: Translation = Translation.new()
		translation.locale = locale
		for key: Variant in (strings as Dictionary).keys():
			var texts: Dictionary = (strings as Dictionary)[key]
			translation.add_message(StringName(str(key)), StringName(str(texts.get(locale, key))))
		TranslationServer.add_translation(translation)
	_loaded_from = path
	error = ""
	return true


## "en" or "ru": an explicit preference wins, "auto" follows the OS language (RU for ru_*,
## otherwise EN).
static func pick_locale(preferred: String, os_language: String) -> String:
	if preferred in LOCALES:
		return preferred
	return "ru" if os_language == "ru" else FALLBACK


## Loads the strings and switches TranslationServer to the picked locale; returns it.
static func apply_locale(preferred: String = "auto") -> String:
	if not ensure_loaded():
		push_warning(error)
	var locale: String = pick_locale(preferred, OS.get_locale_language())
	TranslationServer.set_locale(locale)
	return locale


## The translated text of `key` in the current locale (the key itself when it is unknown).
static func text(key: String) -> String:
	return String(TranslationServer.translate(StringName(key)))
