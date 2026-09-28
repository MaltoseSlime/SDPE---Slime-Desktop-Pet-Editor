class_name PetProfile
extends RefCounted
## 桌寵設定檔的存讀(企劃書「專案儲存:結構化 Resource 與 JSON」):把創作者在管理介面設好的數值定義與狀態鏡
## 存成 JSON(user://profiles/<辨識代號>.json),全域數值定義另存 _global.json。
## 用 JSON 而不是 .tres,是因為之後 .pet 分享包會匯入別人的檔案,Resource 檔可以夾帶腳本,JSON 只是資料,
## 載入時逐欄驗證型別與範圍,壞掉的欄位退回預設,絕不讓錯誤往上拋出。

const PROFILE_DIR := "user://profiles/"
const GLOBAL_FILE := "_global.json"
const MAX_FILE_BYTES := 1_000_000
const MAX_ENTRIES := 500
## 自動閒聊間隔的下限(秒),避免設成 0 之類的值讓桌寵一直講話。
const MIN_AUTO_CHAT_SECONDS := 10.0


## 角色設定檔的位置:角色庫裡的角色在自己資料夾的 character/profile.json(見 CharacterFiles),其他(範例、立繪、庫外素材包)在 user://profiles/<辨識代號>.json。
static func profile_path(pet: Node) -> String:
	var folder := CharacterFiles.folder_of(pet)
	if folder != "":
		return CharacterFiles.profile_in(folder)
	var name: String = pet.recognition_tag if pet.recognition_tag != "" else pet.display_name
	return PROFILE_DIR + name.validate_filename() + ".json"


static func save_pet(pet: Node) -> Error:
	var error := _write(profile_path(pet), snapshot_pet(pet))
	if error == OK:
		# 設定檔已經只記得目前採用的聲音檔,舊的(重新導入、清除後留下的)可以刪了。
		PetVoice.cleanup(pet)
	return error


## 本體的「執行狀態」(局部數值、Flag、啟用中的狀態鏡),另存 <辨識代號>_state.json;之後新放出來的同角色從它開始。
static func state_path(pet: Node) -> String:
	var folder := CharacterFiles.folder_of(pet)
	if folder != "":
		return CharacterFiles.state_in(folder)
	return profile_path(pet).replace(".json", "_state.json")


static func save_state(pet: Node) -> Error:
	return _write(state_path(pet), state_snapshot(pet))


## 本體執行狀態的快照(存檔與 SaveScheduler 共用);uptime = 累計在場分鐘數。
static func state_snapshot(pet: Node) -> Dictionary:
	return {"version": 1, "values": pet.local_values, "flags": pet.flags, "texts": pet.text_values, "lenses": pet.active_lens_names(), "games": pet.game_stats, "uptime": pet.uptime_minutes, "move_mode": int(pet.move_mode)}


## 刪掉已存的本體狀態檔(重置記憶時「一併清除已存狀態」用,免得下次啟動又讀回舊記憶)。
static func delete_state(pet: Node) -> void:
	var path := state_path(pet)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 讀取本體狀態套到這隻;只接受已宣告的鏡片名稱、數值型別驗證。沒有檔案回傳 false。
static func load_state(pet: Node) -> bool:
	var data := _read(state_path(pet), "state")
	if data.is_empty():
		return false
	var values: Variant = data.get("values")
	if values is Dictionary:
		for key in values:
			if _number(values[key], NAN) == _number(values[key], NAN):
				pet.local_values[str(key)] = float(values[key])
	var flags: Variant = data.get("flags")
	if flags is Dictionary:
		for key in flags:
			pet.flags[str(key)] = bool(flags[key])
	var uptime: Variant = data.get("uptime")
	if (uptime is float or uptime is int) and is_finite(float(uptime)):
		pet.uptime_minutes = clampf(float(uptime), 0.0, 100_000.0)
	var games: Variant = data.get("games")
	if games is Dictionary:
		for kind: String in pet.GAME_KIND_NAMES:
			if games.get(kind) is Dictionary:
				var entry := {}
				for outcome: String in ["win", "lose", "tie"]:
					entry[outcome] = maxi(int(_number(games[kind].get(outcome), 0.0)), 0)
				pet.game_stats[kind] = entry
	var texts: Variant = data.get("texts")
	if texts is Dictionary:
		for key in texts:
			var clean_key := PetText.sanitize_key(str(key))
			if clean_key != "" and texts[key] is String:
				pet.text_values[clean_key] = PetText.sanitize(texts[key], PetText.HARD_MAX_LENGTH)
	for lens_name in _array(data.get("lenses")):
		pet.enable_lens(str(lens_name))
	var move_mode: Variant = data.get("move_mode")
	if (move_mode is int or move_mode is float) and int(move_mode) >= 0 and int(move_mode) <= Pet.MoveMode.STATIONARY:
		pet.remembered_move_mode = int(move_mode)
	return true


static func save_globals() -> Error:
	return _write(PROFILE_DIR + GLOBAL_FILE, snapshot_globals())


## 這隻桌寵目前所有可編輯設定的快照(純資料字典,與存檔內容相同)。管理視窗用它記住「上次儲存的狀態」,
## 按叉叉放棄變更時用 restore_pet() 還原。
static func snapshot_pet(pet: Node) -> Dictionary:
	return {
		"version": 1,
		"values": pet.value_defs.map(value_to_dict),
		"lenses": pet.state_lenses.map(lens_to_dict),
		"ui_style": style_to_dict(pet.ui_style),
		"chat": {"enabled": pet.auto_chat_enabled, "min": pet.auto_chat_interval.x, "max": pet.auto_chat_interval.y},
		"dance": {"enabled": pet.auto_dance_enabled, "chance": pet.auto_dance_chance, "follow": pet.auto_dance_follow_enabled},
		"keywords": Array(pet.keywords),
		"userKeywords": Array(pet.user_keywords),
		"interaction": pet.interaction_rules.duplicate(true),
		"accessories": pet.disabled_accessories.duplicate(),
		"mute": {"auto_unmute": pet.auto_unmute_enabled},
		"status": {"energy": pet.status_show_energy, "mood": pet.status_show_mood},
		"effects": {"sleep_z": pet.sleep_z.enabled, "all": pet.effects.enabled, "auto": pet.effects.auto_enabled, "styles": pet.effects.styles_to_dict(), "links": pet.effects.links_to_dict(), "trail": pet.effects.trail_mode},
		"body": {"scale": pet.params.scale_multiplier, "art_flipped": pet.art_flipped, "drag_fixed": pet.drag_when_fixed, "climb": pet.climb_enabled, "breath": pet.breathing_enabled, "land_for_props": pet.land_for_props, "fly_behavior": pet.FLY_BEHAVIOR_NAMES[pet.fly_behavior], "no_fatigue": pet.fatigue_disabled, "bottom": pet.bottom_anchored, "hitbox": [pet.hitbox_size.x, pet.hitbox_size.y, pet.hitbox_offset.x, pet.hitbox_offset.y]},
		"voice": PetVoice.to_dict(pet),
		"dice": {"sides": pet.dice_sides, "mod": pet.dice_mod, "dc": pet.dice_dc_percent, "best_of": pet.game_best_of, "auto_invite": pet.auto_game_enabled, "always_refuse": pet.game_always_refuse},
		"personality": PersonalityApplier.to_data(pet),
		"timer": {"sound": pet.timer_sound},
		"dialogue_locale": pet.dialogue_locale,
		"user_nicknames": pet.user_nicknames.duplicate(),
		"defaults": DefaultsUpdater.to_data(pet),
	}


static func snapshot_globals() -> Dictionary:
	return {"version": 1, "values": _state().global_value_defs.map(value_to_dict)}


static func restore_pet(pet: Node, data: Dictionary) -> void:
	_apply_pet_data(pet, data.duplicate(true))


static func restore_globals(data: Dictionary) -> void:
	_apply_global_data(data.duplicate(true))


## 讀取這隻桌寵的設定檔並取代它目前的數值定義與狀態鏡。沒有檔案回傳 false(維持原本的內建範例)。
static func load_pet(pet: Node) -> bool:
	var data := _read(profile_path(pet))
	if data.is_empty():
		return false
	_apply_pet_data(pet, data)
	return true


static func load_globals() -> bool:
	var data := _read(PROFILE_DIR + GLOBAL_FILE, "globals")
	if data.is_empty():
		return false
	_apply_global_data(data)
	return true


static func _apply_global_data(data: Dictionary) -> void:
	var defs: Array = _state().global_value_defs
	defs.clear()
	for entry in _array(data.get("values")):
		var def := value_from_dict(entry)
		if def != null and def.is_global:
			defs.append(def)


static func _apply_pet_data(pet: Node, data: Dictionary) -> void:
	# 性格先還原(參數值、事件層),下面其他區塊(閒聊間隔、對戰設定…)是使用者可以另外改的,存了就以它們為準。
	PersonalityApplier.restore(pet, data.get("personality"))
	DefaultsUpdater.restore(pet, data.get("defaults"))
	pet.value_defs.clear()
	for entry in _array(data.get("values")):
		var def := value_from_dict(entry)
		if def != null and not def.is_global:
			pet.value_defs.append(def)
	pet.state_lenses.clear()
	for entry in _array(data.get("lenses")):
		var lens := lens_from_dict(entry)
		if lens != null:
			pet.state_lenses.append(lens)
	pet.reapply_lenses()
	ValueGateway.init_defaults(pet)
	apply_style(pet.ui_style, data.get("ui_style"))
	var chat: Variant = data.get("chat")
	if chat is Dictionary:
		pet.auto_chat_enabled = bool(chat.get("enabled", pet.auto_chat_enabled))
		var low := clampf(_number(chat.get("min"), pet.auto_chat_interval.x), MIN_AUTO_CHAT_SECONDS, 86400.0)
		var high := clampf(_number(chat.get("max"), pet.auto_chat_interval.y), low, 86400.0)
		pet.auto_chat_interval = Vector2(low, high)
	var dance: Variant = data.get("dance")
	if dance is Dictionary:
		pet.auto_dance_enabled = bool(dance.get("enabled", pet.auto_dance_enabled))
		pet.auto_dance_chance = clampf(_number(dance.get("chance"), pet.auto_dance_chance), 0.0, 1.0)
		pet.auto_dance_follow_enabled = bool(dance.get("follow", pet.auto_dance_follow_enabled))
	var body: Variant = data.get("body")
	if body is Dictionary:
		if body.get("scale") is float or body.get("scale") is int:
			pet.set_body_scale(float(body["scale"]))
		pet.set_art_flipped(bool(body.get("art_flipped", pet.art_flipped)))
		pet.drag_when_fixed = bool(body.get("drag_fixed", pet.drag_when_fixed))
		pet.set_climb_enabled(bool(body.get("climb", pet.climb_enabled)))
		pet.set_breathing(bool(body.get("breath", pet.breathing_enabled)))
		pet.land_for_props = bool(body.get("land_for_props", pet.land_for_props))
		var fly_index: int = pet.FLY_BEHAVIOR_NAMES.find(str(body.get("fly_behavior", pet.FLY_BEHAVIOR_NAMES[pet.fly_behavior])))
		pet.fly_behavior = maxi(fly_index, 0) as Pet.FlyBehavior
		pet.fatigue_disabled = bool(body.get("no_fatigue", pet.fatigue_disabled))
		pet.set_bottom_anchored(bool(body.get("bottom", pet.bottom_anchored)))
		var hitbox: Variant = body.get("hitbox")
		if hitbox is Array and hitbox.size() >= 4:
			# 判定框大小 0 = 自動;夾在合理範圍,壞值退回自動。
			var size := Vector2(clampf(_number(hitbox[0], 0.0), 0.0, 4096.0), clampf(_number(hitbox[1], 0.0), 0.0, 4096.0))
			pet.hitbox_size = size if size.x > 0.0 and size.y > 0.0 else Vector2.ZERO
			pet.hitbox_offset = Vector2(clampf(_number(hitbox[2], 0.0), -4096.0, 4096.0), clampf(_number(hitbox[3], 0.0), -4096.0, 4096.0))
	if data.get("keywords") is Array:
		pet.keywords = PetText.sanitize_keywords(data["keywords"])
	pet.set_interaction_rules(data.get("interaction"))
	pet.set_disabled_accessories(data.get("accessories"))
	if data.get("userKeywords") is Array:
		pet.user_keywords = PetText.sanitize_keywords(data["userKeywords"])
	var effects: Variant = data.get("effects")
	if effects is Dictionary:
		pet.sleep_z.enabled = bool(effects.get("sleep_z", pet.sleep_z.enabled))
		pet.effects.enabled = bool(effects.get("all", pet.effects.enabled))
		pet.effects.auto_enabled = bool(effects.get("auto", pet.effects.auto_enabled))
		if effects.has("styles"):
			pet.effects.apply_styles(effects["styles"])
		pet.effects.apply_links(effects.get("links"))
		pet.effects.set_trail_mode(str(effects.get("trail", "off")))
	var status: Variant = data.get("status")
	if status is Dictionary:
		pet.status_show_energy = bool(status.get("energy", pet.status_show_energy))
		pet.status_show_mood = bool(status.get("mood", pet.status_show_mood))
	var mute: Variant = data.get("mute")
	if mute is Dictionary:
		pet.auto_unmute_enabled = bool(mute.get("auto_unmute", pet.auto_unmute_enabled))
	PetVoice.apply_profile(pet, data.get("voice"))
	var timer_data: Variant = data.get("timer")
	if timer_data is Dictionary and SoundManager.has_sound(str(timer_data.get("sound", ""))):
		pet.timer_sound = str(timer_data["sound"])
	# "" = 預設(原始語言),或已註冊的語系代碼(見 AppSettings.available_languages);不認得的代碼(語系檔案被
	# 移除、匯出的舊設定檔)一律退回預設,不會讓程式壞掉。
	var locale_code := str(data.get("dialogue_locale", ""))
	pet.dialogue_locale = locale_code if locale_code == "" or AppSettings.available_languages().has(locale_code) else ""
	var nicknames_raw: Variant = data.get("user_nicknames")
	if nicknames_raw is Array:
		var cleaned: Array[String] = []
		for entry: Variant in (nicknames_raw as Array):
			var name := PetText.sanitize(str(entry), PetText.DEFAULT_MAX_LENGTH)
			if name != "" and not cleaned.has(name) and cleaned.size() < Pet.MAX_USER_NICKNAMES:
				cleaned.append(name)
		if not cleaned.is_empty():
			pet.user_nicknames = cleaned
	var dice: Variant = data.get("dice")
	if dice is Dictionary:
		pet.dice_sides = clampi(int(_number(dice.get("sides"), pet.dice_sides)), 2, 1000)
		pet.dice_mod = clampi(int(_number(dice.get("mod"), pet.dice_mod)), -100, 100)
		pet.dice_dc_percent = clampi(int(_number(dice.get("dc"), pet.dice_dc_percent)), 0, 100)
		var best_of := int(_number(dice.get("best_of"), pet.game_best_of))
		pet.game_best_of = best_of if pet.BEST_OF_CHOICES.has(best_of) else 1
		pet.auto_game_enabled = bool(dice.get("auto_invite", pet.auto_game_enabled))
		pet.game_always_refuse = bool(dice.get("always_refuse", pet.game_always_refuse))


static func value_to_dict(def: PetValueDef) -> Dictionary:
	return {
		"key": def.key, "display_name": def.display_name, "is_global": def.is_global,
		"default_value": def.default_value, "min_value": def.min_value, "max_value": def.max_value,
		"step": def.step, "icon_path": def.icon_path, "show_in_status": def.show_in_status,
		"sort_weight": def.sort_weight, "display_mode": int(def.display_mode), "gauge_reverse": def.gauge_reverse,
		"prefix": def.prefix, "suffix": def.suffix, "source": def.source, "source_hash": def.source_hash,
	}


## 逐欄驗證:key 必須是非空字串,數字欄位轉成 float 並確保 min <= max,顯示模式限定合法值。
static func value_from_dict(data: Variant) -> PetValueDef:
	if not data is Dictionary or str(data.get("key", "")).strip_edges() == "":
		return null
	var def := PetValueDef.new()
	def.key = str(data["key"]).strip_edges()
	def.display_name = str(data.get("display_name", ""))
	def.is_global = bool(data.get("is_global", false))
	def.min_value = _number(data.get("min_value"), def.min_value)
	def.max_value = maxf(_number(data.get("max_value"), def.max_value), def.min_value)
	def.default_value = clampf(_number(data.get("default_value"), 0.0), def.min_value, def.max_value)
	def.step = maxf(_number(data.get("step"), 1.0), 0.001)
	def.show_in_status = bool(data.get("show_in_status", false))
	def.sort_weight = int(_number(data.get("sort_weight"), 0.0))
	var mode_number := int(_number(data.get("display_mode"), 0.0))
	def.display_mode = mode_number if mode_number == PetValueDef.DisplayMode.BAR or mode_number == PetValueDef.DisplayMode.GAUGE else PetValueDef.DisplayMode.TEXT
	def.gauge_reverse = bool(data.get("gauge_reverse", false))
	def.prefix = str(data.get("prefix", ""))
	def.suffix = str(data.get("suffix", ""))
	def.set_icon_path(str(data.get("icon_path", "")))
	def.source = str(data.get("source", "")).left(60)
	def.source_hash = int(_number(data.get("source_hash"), 0.0))
	return def


static func lens_to_dict(lens: PetStateLens) -> Dictionary:
	return {
		"name": lens.lens_name, "prefix": lens.prefix, "nature": Array(lens.nature),
		"movement_overrides": lens.movement_overrides, "behavior_overrides": lens.behavior_overrides, "timeout_min": lens.timeout_min, "timeout_max": lens.timeout_max,
		"continue_chance": lens.continue_chance, "continue_decay": lens.continue_decay, "max_rounds": lens.max_rounds, "force_run": lens.force_run, "mood_callable": lens.mood_callable,
		"source": lens.source, "source_hash": lens.source_hash,
	}


static func lens_from_dict(data: Variant) -> PetStateLens:
	if not data is Dictionary or str(data.get("name", "")).strip_edges() == "":
		return null
	var lens := PetStateLens.new()
	lens.lens_name = str(data["name"]).strip_edges()
	lens.prefix = str(data.get("prefix", ""))
	var nature := PackedStringArray()
	for tag in _array(data.get("nature")):
		if PetStateLens.NATURES.has(str(tag)) and not nature.has(str(tag)):
			nature.append(str(tag))
	lens.nature = nature
	var overrides := {}
	var raw: Variant = data.get("movement_overrides", {})
	if raw is Dictionary:
		for prop in raw:
			if PetStateLens.OVERRIDABLE.has(StringName(str(prop))):
				overrides[str(prop)] = _number(raw[prop], 0.0)
	lens.movement_overrides = overrides
	var behavior_overrides := {}
	var behavior_raw: Variant = data.get("behavior_overrides", {})
	if behavior_raw is Dictionary:
		for key in behavior_raw:
			if PetStateLens.BEHAVIOR_KEYS.has(str(key)):
				behavior_overrides[str(key)] = _number(behavior_raw[key], 1.0)
	lens.behavior_overrides = behavior_overrides
	lens.timeout_min = maxf(_number(data.get("timeout_min"), 0.0), 0.0)
	lens.timeout_max = maxf(_number(data.get("timeout_max"), 0.0), 0.0)
	lens.continue_chance = clampf(_number(data.get("continue_chance"), 0.0), 0.0, 1.0)
	lens.continue_decay = clampf(_number(data.get("continue_decay"), 0.6), 0.0, 1.0)
	lens.max_rounds = clampi(int(_number(data.get("max_rounds"), 6.0)), 1, 50)
	var force_run_raw: Variant = data.get("force_run", false)
	lens.force_run = force_run_raw if force_run_raw is bool else false
	lens.mood_callable = clampi(int(_number(data.get("mood_callable"), -1.0)), -1, 1)
	lens.source = str(data.get("source", "")).left(60)
	lens.source_hash = int(_number(data.get("source_hash"), 0.0))
	return lens


## 顏色存成 #RRGGBBAA(大寫,含 Alpha),與 HTML 端 Schema 的格式一致。
static func color_to_hex(color: Color) -> String:
	return "#" + color.to_html(true).to_upper()


static func style_to_dict(style: PetUiStyle) -> Dictionary:
	return {
		"background": color_to_hex(style.background), "border": color_to_hex(style.border),
		"text": color_to_hex(style.text), "option": color_to_hex(style.option),
		"border_width": style.border_width, "corner_radius": style.corner_radius,
		"ui_scale": style.ui_scale, "default_font": style.default_font, "font_scale": style.font_scale,
		"option_wait_seconds": style.option_wait_seconds,
		"thought_background": color_to_hex(style.thought_background), "thought_border": color_to_hex(style.thought_border),
		"thought_text": color_to_hex(style.thought_text), "thought_option": color_to_hex(style.thought_option),
	}


## 把存檔裡的介面風格逐欄驗證後套用到既有的風格資源上(缺欄位/壞值就保留現值)。
static func apply_style(style: PetUiStyle, data: Variant) -> void:
	if not data is Dictionary:
		return
	style.background = _color(data.get("background"), style.background)
	style.border = _color(data.get("border"), style.border)
	style.text = _color(data.get("text"), style.text)
	style.option = _color(data.get("option"), style.option)
	style.thought_background = _color(data.get("thought_background"), style.thought_background)
	style.thought_border = _color(data.get("thought_border"), style.thought_border)
	style.thought_text = _color(data.get("thought_text"), style.thought_text)
	style.thought_option = _color(data.get("thought_option"), style.thought_option)
	style.border_width = clampi(int(_number(data.get("border_width"), style.border_width)), 0, PetUiStyle.MAX_BORDER_WIDTH)
	style.corner_radius = clampi(int(_number(data.get("corner_radius"), style.corner_radius)), 0, PetUiStyle.MAX_CORNER_RADIUS)
	style.ui_scale = PetUiStyle.nearest_scale_step(int(_number(data.get("ui_scale"), style.ui_scale)))
	style.font_scale = PetUiStyle.nearest_scale_step(int(_number(data.get("font_scale"), style.font_scale)))
	var font_name := str(data.get("default_font", style.default_font))
	if UiFonts.FONT_NAMES.has(font_name):
		style.default_font = font_name
	style.option_wait_seconds = clampf(_number(data.get("option_wait_seconds"), style.option_wait_seconds), PetUiStyle.MIN_OPTION_WAIT, PetUiStyle.MAX_OPTION_WAIT)


static func _color(value: Variant, fallback: Color) -> Color:
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return fallback


static func _state() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/DesktopShellState")


static func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	return fallback


static func _array(value: Variant) -> Array:
	if value is Array:
		return value.slice(0, MAX_ENTRIES)
	return []


static func _write(path: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


## 讀檔並升到目前的格式版本(見 ProfileMigrations);kind = profile / state / globals。
static func _read(path: String, kind := "profile") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return ProfileMigrations.migrate(kind, parsed) if parsed is Dictionary else {}
