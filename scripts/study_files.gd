class_name StudyFiles
extends RefCounted

# Playtest 07.11 (Andrei): every player keeps their own study files and sends
# them to the researcher, and the names must say whose data it is and what is in
# it. One folder per play session, named by date, time and player name:
#
#   research/2026-11-07_19-30_Andrei/
#     READ ME - what these files are.txt
#     Andrei_session-info.json                  list of files, build, settings
#     Andrei_all-levels_events.jsonl            every event of the session
#     Andrei_level-3_events.jsonl               one level (retries: _try-2, ...)
#     Andrei_level-3_mouse-and-taskload-60hz.csv
#     Andrei_nasa-tlx.json                      survey answers
#     Andrei_voice/Andrei_voice.wav             this player's microphone
#
# The names are only labels: the rows inside keep their ids (session_id,
# level_run_id, player key) for joining files from different players.

const ROOT := "user://research"
const README_NAME := "READ ME - what these files are.txt"

## The player's name as used in folder and file names: letters, numbers and
## hyphens only ("Andrei Toma" -> "Andrei-Toma"). Blank -> "Player".
static func label(player_name: String) -> String:
	var cleaned := ""
	for character in player_name.strip_edges().left(40):
		var code := character.unicode_at(0)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57): cleaned += character
		elif character in [" ", "-", "_"] and not cleaned.ends_with("-") and not cleaned.is_empty(): cleaned += "-"
	cleaned = cleaned.trim_suffix("-").left(24)
	return cleaned if not cleaned.is_empty() else "Player"

## A new session folder name, "2026-11-07_19-30_Andrei" (local time). If that
## folder already exists (two sessions in one minute) "_2", "_3"... is added.
static func new_session_name(player_label: String) -> String:
	var when := Time.get_datetime_dict_from_system() # local time
	var base := "%04d-%02d-%02d_%02d-%02d_%s" % [when.year, when.month, when.day, when.hour, when.minute, label(player_label)]
	var name := base
	var count := 1
	while DirAccess.dir_exists_absolute(ROOT.path_join(name)):
		count += 1
		name = "%s_%d" % [base, count]
	return name

## "Andrei_level-3" or, for the second try of that level, "Andrei_level-3_try-2".
static func level_base(player_label: String, level_number: int, attempt: int) -> String:
	var base := "%s_level-%d" % [label(player_label), level_number]
	return base if attempt <= 1 else "%s_try-%d" % [base, attempt]

## A file name in the session folder that is not taken yet: "Andrei_nasa-tlx.json",
## then "Andrei_nasa-tlx_2.json"...
static func free_name(folder: String, stem: String, extension: String) -> String:
	var name := "%s.%s" % [stem, extension]
	var count := 1
	while FileAccess.file_exists(folder.path_join(name)) or DirAccess.dir_exists_absolute(folder.path_join(name)):
		count += 1
		name = "%s_%d.%s" % [stem, count, extension]
	return name

## A folder name inside `folder` that is not taken yet: "Andrei_voice", then
## "Andrei_voice_2"... (the voice recording reopens after a reconnect).
static func free_folder(folder: String, stem: String) -> String:
	var name := stem
	var count := 1
	while DirAccess.dir_exists_absolute(folder.path_join(name)) or FileAccess.file_exists(folder.path_join(name)):
		count += 1
		name = "%s_%d" % [stem, count]
	return name

## A short guide next to the data, written once per session folder.
static func write_readme(folder: String, player_label: String) -> void:
	var path := folder.path_join(README_NAME)
	if FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	var p := label(player_label)
	file.store_string("\n".join([
		"Beacon Bay study files of one play session, recorded on this player's computer.",
		"Folder name: date and time the session started, then the player's name.",
		"",
		"%s_session-info.json" % p,
		"    Build, settings and the list of level files in this folder.",
		"%s_all-levels_events.jsonl" % p,
		"    Every recorded event of the session in order (one JSON object per line):",
		"    calls, dispatches, road events, this player's clicks, keys and mouse movement.",
		"%s_level-<N>_events.jsonl" % p,
		"    The same events, one file per level played. A level played again in the",
		"    same session gets _try-2, _try-3 ...",
		"%s_level-<N>_mouse-and-taskload-60hz.csv" % p,
		"    60 rows per second for that level: cursor position, what is under the",
		"    cursor, frame rate, and how many calls need this player's department.",
		"%s_nasa-tlx.json" % p,
		"    NASA-TLX survey answers (only if the player filled it in).",
		"%s_voice/" % p,
		"    This player's microphone during the levels (only if voice chat and",
		"    recording were on): %s_voice.wav, plus timing files and listen.html." % p,
		"",
		"Every row carries session_id, level_run_id and the player's key, so files from",
		"different players of the same team can be joined. See docs/research-data.md.",
		""]))
	file.close()
