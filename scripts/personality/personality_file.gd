class_name PersonalityFile
extends RefCounted
## 性格檔(`<名稱>.personality.json`):讀取、驗證、把精簡寫法編譯成事件積木、列出內建與自訂性格、匯入、匯出。
## 格式說明見 docs/性格檔格式.md。所有欄位逐項驗證(型別、範圍、長度、數量上限),壞的項目略過並記在 report,不往外拋錯。
## 事件是「另外一層」:性格帶進來的事件積木不會寫進使用者自己的積木檔,兩邊互不覆蓋(見 LogicInterpreter.set_personality_layer)。

const FILE_TYPE := "slime_pet_personality"
const VERSION := 1
const PRESET_DIR := "res://personalities/"
const CUSTOM_DIR := "user://personalities/"
const EXTENSION := ".personality.json"
const MAX_FILE_BYTES := 600_000
const MAX_ENTRIES := 300
const MAX_LINES_PER_ENTRY := 40
const MAX_LINE_CHARS := 400
const MAX_VALUE_DEFS := 60
const MAX_BLOCKS := 200
const MAX_BLOCK_DEPTH := 40
const MAX_ARRAY := 200
## 閒聊的情境(見 LogicInterpreter.say_something):平常 / 休息中 / 睡眠中 / 某個狀態鏡生效中。
const CHAT_TAGS: Array[String] = ["chat", "rest", "sleep", "lens"]
## 「反應」的觸發:桌寵的動作名稱(interact 被摸、drag 被拖曳、enter 登場、sleep 開始睡…),或下面這些遊戲相關的專用名稱。
const GAME_TRIGGERS: Array[String] = ["game_win", "game_lose", "game_tie", "invite_accept", "invite_refuse"]
## 原始事件積木(`blocks` 區塊)只允許這幾種頂層事件(其他種類的事件屬於使用者自己的積木檔,不進性格)。
const CHAT_HAT := "event_when_chat"
const REACTION_HATS: Array[String] = ["event_when_action", "event_when_dice_contest", "event_when_rps", "event_when_game_invited"]

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


# --- 讀取與驗證 ---

## 讀一個性格檔。回傳 {ok, personality, report};失敗 ok = false、report 說明原因。
static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "personality": {}, "report": [TranslationServer.translate("讀不了檔案:%s") % path.get_file()]}
	if file.get_length() > MAX_FILE_BYTES:
		return {"ok": false, "personality": {}, "report": [TranslationServer.translate("性格檔太大(上限 %d KB):%s") % [MAX_FILE_BYTES / 1000, path.get_file()]]}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "personality": {}, "report": [TranslationServer.translate("不是有效的 JSON 物件:%s") % path.get_file()]}
	return validate(parsed)


## 驗證並整理一份性格資料。只有「不是性格檔」「版本比程式新」這種整份不能用的情況才失敗,其他壞項目略過。
static func validate(data: Dictionary) -> Dictionary:
	var report: Array[String] = []
	if str(data.get("fileType", "")) != FILE_TYPE:
		return {"ok": false, "personality": {}, "report": [TranslationServer.translate("這不是性格檔(fileType 應為 %s)") % FILE_TYPE]}
	var version := int(data["personalityVersion"]) if data.get("personalityVersion") is float or data.get("personalityVersion") is int else 0
	if version < 1 or version > VERSION:
		return {"ok": false, "personality": {}, "report": [TranslationServer.translate("性格檔版本 %s 不支援(這個程式認得到版本 %d)") % [str(data.get("personalityVersion")), VERSION]]}
	var id := clean_id(str(data.get("id", "")))
	if id == "":
		return {"ok": false, "personality": {}, "report": ["性格檔缺少 id(只能用英數、底線、連字號、中文)"]}
	var sections: Dictionary = data.get("sections", {}) if data.get("sections") is Dictionary else {}
	var personality := {
		"id": id,
		"name": str(data.get("name", id)).strip_edges().left(40),
		"description": str(data.get("description", "")).strip_edges().left(400),
		"author": str(data.get("author", "")).strip_edges().left(60),
		"revision": int(data["revision"]) if data.get("revision") is float or data.get("revision") is int else 1,
		"params": _validate_params(sections.get("params"), report),
		"valueDefs": _validate_definitions(sections.get("valueDefs"), true, report),
		"lenses": _validate_definitions(sections.get("lenses"), false, report),
		"chat": _validate_chat(sections.get("chat"), report),
		"reactions": _validate_reactions(sections.get("reactions"), report),
		"blocks": _validate_blocks(sections.get("blocks"), report),
		"dialogueTranslations": _validate_translations(data.get("dialogueTranslations"), report),
	}
	if personality["name"] == "":
		personality["name"] = id
	return {"ok": true, "personality": personality, "report": report}


## id 只留英數、底線、連字號與中文;其他字元換成底線,最長 40 字。
static func clean_id(raw: String) -> String:
	var cleaned := ""
	for character in raw.strip_edges().left(40):
		var code := character.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character == "_" or character == "-" or (code >= 0x4E00 and code <= 0x9FFF):
			cleaned += character
		else:
			cleaned += "_"
	return cleaned.trim_prefix("_").trim_suffix("_") if cleaned.strip_edges().replace("_", "") != "" else ""


static func _validate_params(raw: Variant, report: Array[String]) -> Dictionary:
	var result := {}
	if raw == null:
		return result
	if not raw is Dictionary:
		report.append("params 必須是物件,已略過整個區塊")
		return result
	for key: Variant in raw:
		var value: Variant = PersonalityParams.normalize(str(key), raw[key])
		if value == null:
			report.append(TranslationServer.translate("參數「%s」不認得或值不合格(型別/範圍),已略過") % str(key))
		else:
			result[str(key)] = value
	return result


## 數值定義 / 狀態鏡:每一項交給 PetProfile 既有的驗證(value_from_dict / lens_from_dict),再轉回乾淨的字典。
static func _validate_definitions(raw: Variant, is_value: bool, report: Array[String]) -> Array:
	var result: Array = []
	if raw == null:
		return result
	if not raw is Array:
		report.append(TranslationServer.translate("%s 必須是陣列,已略過整個區塊") % ("valueDefs" if is_value else "lenses"))
		return result
	for item: Variant in (raw as Array).slice(0, MAX_VALUE_DEFS):
		if not item is Dictionary:
			report.append(TranslationServer.translate("%s 裡有不是物件的項目,已略過") % ("valueDefs" if is_value else "lenses"))
			continue
		if is_value:
			var def: PetValueDef = PetProfile.value_from_dict(item)
			if def == null or def.key == "":
				report.append("有一個數值定義不合格(缺名稱或格式錯誤),已略過")
				continue
			result.append(clean_definition(PetProfile.value_to_dict(def)))
		else:
			var lens: PetStateLens = PetProfile.lens_from_dict(item)
			if lens == null or lens.lens_name == "":
				report.append("有一個狀態鏡不合格(缺名稱或格式錯誤),已略過")
				continue
			result.append(clean_definition(PetProfile.lens_to_dict(lens)))
	return result


static func _clean_lines(raw: Variant) -> Array[String]:
	var lines: Array[String] = []
	var source: Array = raw if raw is Array else ([raw] if raw is String else [])
	for value: Variant in source.slice(0, MAX_LINES_PER_ENTRY):
		if value is String and str(value).strip_edges() != "":
			lines.append(str(value).strip_edges().left(MAX_LINE_CHARS))
	return lines


## 性格檔自帶的對話翻譯(dialogueTranslations,跟積木檔的格式一樣:「語言在最外層」的 {語言代碼: {原文: 翻譯}},
## 見 LogicInterpreter._index_translations/merge_translations)。原文/翻譯都要是非空字串,壞值整筆略過,不報錯中斷。
const MAX_TRANSLATION_LANGUAGES := 8
const MAX_TRANSLATION_ENTRIES := 400


static func _validate_translations(raw: Variant, report: Array[String]) -> Dictionary:
	var result := {}
	if raw == null:
		return result
	if not raw is Dictionary:
		report.append("dialogueTranslations 必須是物件,已略過")
		return result
	var lang_regex := RegEx.create_from_string("^[A-Za-z]{2,3}([-_][A-Za-z0-9]+)?$")
	for language: Variant in (raw as Dictionary).keys().slice(0, MAX_TRANSLATION_LANGUAGES):
		var lang_code := str(language)
		if lang_regex.search(lang_code) == null or not (raw as Dictionary)[language] is Dictionary:
			continue
		var entries := {}
		var source: Dictionary = (raw as Dictionary)[language]
		for original: Variant in source.keys().slice(0, MAX_TRANSLATION_ENTRIES):
			var text := str(original).strip_edges().left(MAX_LINE_CHARS)
			var translated: Variant = source[original]
			if text != "" and translated is String and str(translated).strip_edges() != "":
				entries[text] = str(translated).strip_edges().left(MAX_LINE_CHARS)
		if not entries.is_empty():
			result[lang_code] = entries
	return result


static func _validate_chat(raw: Variant, report: Array[String]) -> Array:
	var result: Array = []
	if raw == null:
		return result
	if not raw is Array:
		report.append("chat 必須是陣列,已略過整個區塊")
		return result
	for item: Variant in (raw as Array).slice(0, MAX_ENTRIES):
		if not item is Dictionary:
			report.append("chat 裡有不是物件的項目,已略過")
			continue
		var tag := str(item.get("tag", "chat")).to_lower()
		if not CHAT_TAGS.has(tag):
			report.append(TranslationServer.translate("chat 項目的情境「%s」不認得(應為 chat / rest / sleep / lens),已略過") % tag)
			continue
		var say := _clean_lines(item.get("say"))
		var seq := _clean_lines(item.get("seq"))
		if say.is_empty() and seq.is_empty():
			report.append("chat 項目沒有台詞(say 或 seq),已略過")
			continue
		result.append({
			"tag": tag, "lens": str(item.get("lens", "")).strip_edges().left(40), "say": say, "seq": seq,
			"chance": clampf(float(item["chance"]), 0.0, 100.0) if item.get("chance") is float or item.get("chance") is int else 100.0,
			# 觸發率(跟同一個情境池裡其他閒聊事件競爭被抽中的權重,0~200,預設 100;不是獨立機率,見 LogicInterpreter._weighted_pick())。
			"weight": clampf(float(item["weight"]), 0.0, 200.0) if item.get("weight") is float or item.get("weight") is int else 100.0,
			"effects": _validate_effects(item),
		})
	return result


static func _validate_reactions(raw: Variant, report: Array[String]) -> Array:
	var result: Array = []
	if raw == null:
		return result
	if not raw is Array:
		report.append("reactions 必須是陣列,已略過整個區塊")
		return result
	for item: Variant in (raw as Array).slice(0, MAX_ENTRIES):
		if not item is Dictionary:
			report.append("reactions 裡有不是物件的項目,已略過")
			continue
		var trigger := str(item.get("on", "")).strip_edges().to_lower()
		if trigger == "" or trigger.length() > 30:
			report.append("reactions 項目缺少或有不合格的 on(觸發),已略過")
			continue
		var say := _clean_lines(item.get("say"))
		var effects := _validate_effects(item)
		if say.is_empty() and effects.is_empty():
			report.append(TranslationServer.translate("reactions 項目「%s」沒有台詞也沒有動作,已略過") % trigger)
			continue
		result.append({
			"on": trigger, "say": say,
			"chance": clampf(float(item["chance"]), 0.0, 100.0) if item.get("chance") is float or item.get("chance") is int else 100.0,
			"effects": effects,
		})
	return result


## 台詞之外的動作效果:action(播放動作)、hop(小跳幾下)、shiver(發抖幾秒)。
static func _validate_effects(item: Dictionary) -> Dictionary:
	var effects := {}
	if item.get("action") is String and str(item["action"]).strip_edges() != "":
		effects["action"] = str(item["action"]).strip_edges().left(40)
	if item.get("hop") is float or item.get("hop") is int:
		effects["hop"] = clampi(int(item["hop"]), 1, 5)
	if item.get("shiver") is float or item.get("shiver") is int:
		effects["shiver"] = clampf(float(item["shiver"]), 0.3, 6.0)
	return effects


## 性格檔裡的數值定義/狀態鏡不帶「來源」標記(來源是套用時才由 PersonalityApplier 加上去的)。
static func clean_definition(data: Dictionary) -> Dictionary:
	var cleaned := data.duplicate(true)
	cleaned.erase("source")
	cleaned.erase("source_hash")
	# 後來新增、值是預設值的狀態鏡欄位不算內容:免得以前套用的性格(當時還沒有這些欄位)被誤判成「使用者改過」,之後永遠更新不到。
	for key: String in ["continue_chance", "continue_decay", "max_rounds", "force_run", "mood_callable"]:
		var default_value: Variant = {"continue_chance": 0.0, "continue_decay": 0.6, "max_rounds": 6, "force_run": false, "mood_callable": -1}[key]
		if cleaned.has(key) and cleaned[key] == default_value:
			cleaned.erase(key)
	return cleaned


## 原始事件積木:只留允許的頂層事件種類,而且巢狀深度與陣列長度要在上限內。
static func _validate_blocks(raw: Variant, report: Array[String]) -> Array:
	var result: Array = []
	if raw == null:
		return result
	if not raw is Array:
		report.append("blocks 必須是陣列,已略過整個區塊")
		return result
	for block: Variant in (raw as Array).slice(0, MAX_BLOCKS):
		if not block is Dictionary:
			continue
		var type := str(block.get("type", ""))
		if type != CHAT_HAT and not REACTION_HATS.has(type):
			report.append(TranslationServer.translate("blocks 裡的事件種類「%s」不屬於性格(只允許閒聊與反應類事件),已略過") % type)
			continue
		if not _within_limits(block, 0):
			report.append("blocks 裡有一個事件太大或巢狀太深,已略過")
			continue
		result.append(block)
	return result


static func _within_limits(node: Variant, depth: int) -> bool:
	if depth > MAX_BLOCK_DEPTH:
		return false
	if node is Dictionary:
		for value: Variant in (node as Dictionary).values():
			if not _within_limits(value, depth + 1):
				return false
	elif node is Array:
		if (node as Array).size() > MAX_ARRAY:
			return false
		for value: Variant in node:
			if not _within_limits(value, depth + 1):
				return false
	return true


# --- 編譯成事件積木 ---

## 閒聊區塊的事件:精簡寫法編譯出的閒聊事件 + 原始積木裡的閒聊事件。
static func chat_hats(personality: Dictionary) -> Array:
	var hats: Array = []
	var id := str(personality["id"])
	var index := 0
	for entry: Dictionary in personality["chat"]:
		var label := _label(personality, "chat/%s" % entry["tag"], entry)
		var hat := {"type": CHAT_HAT, "id": "pers:%s:chat:%d" % [id, index], "fields": {"TAG": entry["tag"], "LENS": entry["lens"], "WEIGHT": entry.get("weight", 100.0), "NAME": label}}
		hat["inputs"] = {"DO": {"block": _body("pers:%s:chat:%d" % [id, index], entry)}}
		hats.append(hat)
		index += 1
	for block: Dictionary in personality["blocks"]:
		if str(block.get("type", "")) == CHAT_HAT:
			hats.append(block)
	return hats


## 反應區塊的事件:精簡寫法編譯出的反應事件 + 原始積木裡的反應類事件。遊戲相關的觸發會分別編譯給猜拳與拚骰。
static func reaction_hats(personality: Dictionary) -> Array:
	var hats: Array = []
	var id := str(personality["id"])
	var index := 0
	for entry: Dictionary in personality["reactions"]:
		var trigger: String = entry["on"]
		var base_id := "pers:%s:react:%d" % [id, index]
		var label := _label(personality, TranslationServer.translate("反應/%s") % trigger, entry)
		var body := _body(base_id, entry)
		match trigger:
			"game_win", "game_lose", "game_tie":
				var result := trigger.trim_prefix("game_")
				for hat_type: String in ["event_when_rps", "event_when_dice_contest"]:
					hats.append({"type": hat_type, "id": "%s:%s" % [base_id, hat_type], "fields": {"RESULT": result, "NAME": label}, "inputs": {"DO": {"block": body.duplicate(true)}}})
			"invite_accept", "invite_refuse":
				hats.append({"type": "event_when_game_invited", "id": base_id, "fields": {"ANSWER": "accept" if trigger == "invite_accept" else "refuse", "GAME": "any", "NAME": label}, "inputs": {"DO": {"block": body}}})
			_:
				hats.append({"type": "event_when_action", "id": base_id, "fields": {"ACTION": trigger, "NAME": label}, "inputs": {"DO": {"block": body}}})
		index += 1
	for block: Dictionary in personality["blocks"]:
		if REACTION_HATS.has(str(block.get("type", ""))):
			hats.append(block)
	return hats


static func _label(personality: Dictionary, kind: String, entry: Dictionary) -> String:
	var lines: Array = entry.get("say", []) if not (entry.get("say", []) as Array).is_empty() else entry.get("seq", [])
	var sample := str(lines[0]).left(14) if not lines.is_empty() else "(動作)"
	return TranslationServer.translate("性格·%s · %s · %s") % [personality["name"], kind, sample]


## 一個項目的內容:先做動作效果,再說話。機率(chance)套在說話上;沒有台詞就只做動作。
static func _body(base_id: String, entry: Dictionary) -> Dictionary:
	var blocks: Array[Dictionary] = []
	var effects: Dictionary = entry.get("effects", {})
	if effects.has("action"):
		blocks.append({"type": "action_play", "id": base_id + ":action", "fields": {"ACTION": effects["action"], "VARIANT": ""}})
	if effects.has("hop"):
		blocks.append({"type": "phys_jump_small", "id": base_id + ":hop", "fields": {"N": effects["hop"], "NOWAIT": true}})
	if effects.has("shiver"):
		blocks.append({"type": "phys_shiver", "id": base_id + ":shiver", "fields": {"SEC": effects["shiver"], "NOWAIT": true}})
	var seq: Array = entry.get("seq", [])
	var say: Array = entry.get("say", [])
	if not seq.is_empty():
		var previous: Dictionary = {}
		for i in range(seq.size() - 1, -1, -1):
			var line := {"type": "dialogue_line", "id": "%s:seq%d" % [base_id, i], "fields": {"TEXT": seq[i], "WAIT": true, "AUTOSEC": 0, "TYPEWRITER": true}}
			if not previous.is_empty():
				line["next"] = {"block": previous}
			previous = line
		blocks.append(previous)
	elif not say.is_empty():
		blocks.append({"type": "say_random", "id": base_id + ":say", "fields": {"LINES": say, "PCT": entry.get("chance", 100.0)}})
	# 依序串成 next 鏈(最後一顆的 next 留給前面的 seq 已經串好的內容)
	for i in range(blocks.size() - 2, -1, -1):
		blocks[i]["next"] = {"block": blocks[i + 1]}
	return blocks[0] if not blocks.is_empty() else {}


# --- 白話描述(給管理視窗顯示每個區塊「這個性格在這裡會怎樣」)---

## 反應觸發的白話名稱。
const TRIGGER_LABELS := {
	"interact": "被觸摸", "drag": "被拖曳", "enter": "登場", "sleep": "開始睡覺", "sit": "坐下", "dance": "跳舞",
	"game_win": "猜拳/拚骰贏了", "game_lose": "猜拳/拚骰輸了", "game_tie": "猜拳/拚骰平手",
	"invite_accept": "接受對戰邀請", "invite_refuse": "拒絕對戰邀請", "tired": "覺得累", "wake": "睡醒",
	"ball_found": "發現球", "ball_invite": "邀請其他桌寵玩球", "ball_join": "加入玩球", "ball_decline": "不參與玩球",
	"ball_playing": "正在玩球", "ball_end": "結束玩球", "ball_watch": "看到別人在玩球",
}
const CHAT_TAG_LABELS := {"chat": "平常", "rest": "休息中", "sleep": "睡覺中", "lens": "特定狀態"}


static func trigger_label(trigger: String) -> String:
	return str(TRIGGER_LABELS.get(trigger, TranslationServer.translate("「%s」動作") % trigger))


## 參數名稱的短版(去掉括號裡的補充說明)。要先翻譯再截斷:反過來的話,截斷後的片段幾乎不可能剛好等於
## translations/ui_strings.csv 裡的完整原文,查表永遠對不上(2026-09-30 使用者回報桌寵管理→性格分頁的
## 參數列表大半沒翻譯到,只有原文剛好沒有括號、截斷等於沒截的那幾項才翻得到,根因就是這個)。
static func short_label(key: String) -> String:
	return TranslationServer.translate(PersonalityParams.label_of(key)).split("(")[0].strip_edges()


## 一個參數值相對預設值的白話註解(偏快/偏慢…);沒有特別的就回空字串。
static func _param_hint(key: String, value: Variant) -> String:
	var spec: Dictionary = PersonalityParams.SPECS.get(key, {})
	var default_value: Variant = PersonalityParams.default_of(key)
	if PersonalityParams.same(value, default_value):
		return "和預設一樣"
	match str(spec.get("kind", "")):
		"float":
			return TranslationServer.translate("比預設(%s)%s") % [PersonalityParams.to_text(default_value), "高" if float(value) > float(default_value) else "低"]
		"range":
			var mid := ((value as Vector2).x + (value as Vector2).y) * 0.5
			var default_mid := ((default_value as Vector2).x + (default_value as Vector2).y) * 0.5
			return TranslationServer.translate("預設 %s,%s") % [PersonalityParams.to_text(default_value), "偏長" if mid > default_mid else "偏短"]
		"bool":
			return TranslationServer.translate("預設是%s") % ("會" if bool(default_value) else "不會")
		"weights":
			return TranslationServer.translate("預設 %s") % PersonalityParams.to_text(default_value)
	return ""


## 這個性格在某個區塊會做什麼(白話描述)。full = true 逐項列出,false 只列前幾項。空的區塊會明說「沒有」。
static func section_description(personality: Dictionary, section: String, full := false) -> String:
	if personality.is_empty():
		return ""
	match section:
		"params":
			var params: Dictionary = personality.get("params", {})
			if params.is_empty():
				return "這個性格不調整任何參數(維持你目前的設定)。"
			var lines: Array[String] = []
			for key: String in PersonalityParams.keys():
				if params.has(key):
					var value_text := PersonalityParams.to_text(params[key])
					if str(PersonalityParams.SPECS[key]["kind"]) == "range":
						value_text += " 秒"
					lines.append("%s %s(%s)" % [short_label(key), value_text, _param_hint(key, params[key])])
			return _join_limited(TranslationServer.translate("調整 %d 項參數:") % lines.size(), lines, full, 5, "、", "\n  ")
		"valueDefs":
			var defs: Array = personality.get("valueDefs", [])
			if defs.is_empty():
				return "這個性格沒有數值定義(不會替桌寵新增任何數值)。"
			var names: Array[String] = []
			for item: Variant in defs:
				names.append("%s(%s~%s)" % [str((item as Dictionary).get("display_name", (item as Dictionary).get("key", "?"))), str((item as Dictionary).get("min_value", "")), str((item as Dictionary).get("max_value", ""))])
			return _join_limited(TranslationServer.translate("新增 %d 個數值:") % defs.size(), names, full, 6, "、", "\n  ")
		"lenses":
			var lenses: Array = personality.get("lenses", [])
			if lenses.is_empty():
				return "這個性格沒有狀態鏡(不會替桌寵新增任何狀態)。"
			var lens_names: Array[String] = []
			for item: Variant in lenses:
				var natures: Array = (item as Dictionary).get("nature", []) if (item as Dictionary).get("nature") is Array else []
				lens_names.append("%s%s" % [str((item as Dictionary).get("name", "?")), "(%s)" % "、".join(PackedStringArray(natures)) if not natures.is_empty() else ""])
			return _join_limited(TranslationServer.translate("新增 %d 個狀態鏡:") % lenses.size(), lens_names, full, 6, "、", "\n  ")
		"chat":
			var entries: Array = personality.get("chat", [])
			var raw_count := 0
			for block: Variant in personality.get("blocks", []):
				if block is Dictionary and str(block.get("type", "")) == CHAT_HAT:
					raw_count += 1
			if entries.is_empty() and raw_count == 0:
				return "這個性格沒有對話池(不會多出任何閒聊台詞)。"
			var counts := {}
			var samples: Array[String] = []
			for entry: Dictionary in entries:
				counts[entry["tag"]] = int(counts.get(entry["tag"], 0)) + 1
				var lines_of_entry: Array = entry["say"] if not (entry["say"] as Array).is_empty() else entry["seq"]
				samples.append("[%s]「%s」" % [CHAT_TAG_LABELS.get(entry["tag"], entry["tag"]), str(lines_of_entry[0]).left(18)])
			var parts: Array[String] = []
			for tag: String in CHAT_TAGS:
				if counts.has(tag):
					parts.append("%s %d" % [CHAT_TAG_LABELS[tag], counts[tag]])
			var head := TranslationServer.translate("共 %d 個閒聊項目(%s%s)。") % [entries.size() + raw_count, "、".join(PackedStringArray(parts)), TranslationServer.translate("、進階積木 %d") % raw_count if raw_count > 0 else ""]
			return head + ("\n  例:" + "\n  ".join(PackedStringArray(samples.slice(0, 12 if full else 3))) if not samples.is_empty() else "")
		"reactions":
			var reactions: Array = personality.get("reactions", [])
			var raw_reactions := 0
			for block: Variant in personality.get("blocks", []):
				if block is Dictionary and REACTION_HATS.has(str(block.get("type", ""))):
					raw_reactions += 1
			if reactions.is_empty() and raw_reactions == 0:
				return "這個性格沒有反應事件(採用內建反應)。"
			var triggers: Array[String] = []
			var samples: Array[String] = []
			for entry: Dictionary in reactions:
				var label := trigger_label(str(entry["on"]))
				if not triggers.has(label):
					triggers.append(label)
				var say: Array = entry["say"]
				var effects: Dictionary = entry["effects"]
				var extra: Array[String] = []
				if effects.has("hop"):
					extra.append(TranslationServer.translate("跳 %d 下") % int(effects["hop"]))
				if effects.has("shiver"):
					extra.append("發抖")
				if effects.has("action"):
					extra.append(TranslationServer.translate("播放 %s") % str(effects["action"]))
				samples.append("%s → %s%s%s" % [label, "「%s」" % str(say[0]).left(16) if not say.is_empty() else "(不說話)", "(%s)" % "、".join(PackedStringArray(extra)) if not extra.is_empty() else "", TranslationServer.translate("  機率 %d%%") % int(entry["chance"]) if float(entry["chance"]) < 100.0 else ""])
			return TranslationServer.translate("共 %d 個反應,涵蓋:%s%s。") % [reactions.size() + raw_reactions, "、".join(PackedStringArray(triggers)), TranslationServer.translate("、進階積木 %d") % raw_reactions if raw_reactions > 0 else ""] + ("\n  " + "\n  ".join(PackedStringArray(samples.slice(0, 40 if full else 3))) if not samples.is_empty() else "")
	return ""


static func _join_limited(head: String, items: Array[String], full: bool, limit: int, separator: String, full_separator: String) -> String:
	if full or items.size() <= limit:
		return head + (full_separator + full_separator.join(PackedStringArray(items)) if full else separator.join(PackedStringArray(items)))
	return head + separator.join(PackedStringArray(items.slice(0, limit))) + TranslationServer.translate("…(還有 %d 項)") % (items.size() - limit)


# --- 存回性格檔 ---

## 把驗證過的性格(validate 的結果)轉回檔案格式(給管理視窗的性格編輯器存檔用)。空的區塊不寫,機率 100 不寫。
static func to_file_data(personality: Dictionary) -> Dictionary:
	var sections := {}
	if not (personality.get("params", {}) as Dictionary).is_empty():
		var params := {}
		for key: String in personality["params"]:
			params[key] = PersonalityParams.to_json(personality["params"][key])
		sections["params"] = params
	for section: String in ["valueDefs", "lenses", "blocks"]:
		if not (personality.get(section, []) as Array).is_empty():
			sections[section] = (personality[section] as Array).duplicate(true)
	var chat: Array = []
	for entry: Dictionary in personality.get("chat", []):
		var item := {"tag": entry["tag"]}
		if str(entry.get("lens", "")) != "":
			item["lens"] = entry["lens"]
		_store_lines(item, entry)
		chat.append(item)
	if not chat.is_empty():
		sections["chat"] = chat
	var reactions: Array = []
	for entry: Dictionary in personality.get("reactions", []):
		var item := {"on": entry["on"]}
		_store_lines(item, entry)
		reactions.append(item)
	if not reactions.is_empty():
		sections["reactions"] = reactions
	var result := {
		"fileType": FILE_TYPE, "personalityVersion": VERSION, "id": personality["id"], "name": personality["name"],
		"description": personality.get("description", ""), "author": personality.get("author", ""), "revision": int(personality.get("revision", 1)),
		"sections": sections,
	}
	if not (personality.get("dialogueTranslations", {}) as Dictionary).is_empty():
		result["dialogueTranslations"] = (personality["dialogueTranslations"] as Dictionary).duplicate(true)
	return result


static func _store_lines(item: Dictionary, entry: Dictionary) -> void:
	var say: Array = entry.get("say", [])
	var seq: Array = entry.get("seq", [])
	if not seq.is_empty():
		item["seq"] = seq.duplicate()
	if not say.is_empty():
		item["say"] = say[0] if say.size() == 1 else say.duplicate()
	if float(entry.get("chance", 100.0)) < 100.0:
		item["chance"] = entry["chance"]
	if float(entry.get("weight", 100.0)) != 100.0:
		item["weight"] = entry["weight"]
	var effects: Dictionary = entry.get("effects", {})
	for key: String in ["action", "hop", "shiver"]:
		if effects.has(key):
			item[key] = effects[key]


# --- 列出、尋找 ---

## 內建(res://personalities/)+ 自訂(user://personalities/)的性格,每項 {id, name, description, path, builtin}。內建的排前面。
static func list_all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for builtin in [true, false]:
		var folder := PRESET_DIR if builtin else CUSTOM_DIR
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		var names: Array[String] = []
		for file_name in dir.get_files():
			if file_name.ends_with(EXTENSION):
				names.append(file_name)
		names.sort()
		for file_name in names:
			var loaded := _load_cached(folder + file_name)
			if bool(loaded["ok"]):
				var personality: Dictionary = loaded["personality"]
				result.append({"id": personality["id"], "name": personality["name"], "description": personality["description"], "path": folder + file_name, "builtin": builtin})
	return result


static func _load_cached(path: String) -> Dictionary:
	if not _cache.has(path):
		_cache[path] = load_file(path)
	return _cache[path]


## 依 id 找性格(內建優先);找不到回 {}。回傳 {personality, path, builtin}。
static func find(id: String) -> Dictionary:
	for item in list_all():
		if item["id"] == id:
			var loaded := _load_cached(str(item["path"]))
			return {"personality": loaded["personality"], "path": item["path"], "builtin": item["builtin"]}
	return {}


# --- 匯入與匯出 ---

## 匯入自訂性格:驗證通過就複製進 user://personalities/(id 撞到現有的會加序號)。回傳 {ok, id, report}。
static func import_file(source_path: String) -> Dictionary:
	var loaded := load_file(source_path)
	if not bool(loaded["ok"]):
		return {"ok": false, "id": "", "report": loaded["report"]}
	var personality: Dictionary = loaded["personality"]
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var existing_ids: Array[String] = []
	for item in list_all():
		existing_ids.append(str(item["id"]))
	var id: String = personality["id"]
	var unique := id
	var counter := 2
	while existing_ids.has(unique):
		unique = "%s_%d" % [id, counter]
		counter += 1
	if unique != id:
		(raw as Dictionary)["id"] = unique
		(loaded["report"] as Array).append(TranslationServer.translate("id「%s」已經有了,改存成「%s」") % [id, unique])
	DirAccess.make_dir_recursive_absolute(CUSTOM_DIR)
	var file := FileAccess.open(CUSTOM_DIR + unique + EXTENSION, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "id": "", "report": [TranslationServer.translate("無法寫入 %s") % CUSTOM_DIR]}
	file.store_string(JSON.stringify(raw, "  ") + "\n")
	file.close()
	clear_cache()
	return {"ok": true, "id": unique, "report": loaded["report"]}


## 把桌寵目前的設定做成性格檔資料:參數(全部目前的值)、數值定義、狀態鏡,以及使用者自己的閒聊/反應事件積木。
## 不含桌寵狀態(數值目前值、Flag、戰績)。
static func export_pet(pet: Node, id: String, display_name: String, description := "") -> Dictionary:
	var params := {}
	for key in PersonalityParams.keys():
		params[key] = PersonalityParams.to_json(PersonalityParams.get_value(pet, key))
	var value_defs: Array = []
	for def: PetValueDef in pet.value_defs:
		value_defs.append(clean_definition(PetProfile.value_to_dict(def)))
	var lenses: Array = []
	for lens: PetStateLens in pet.state_lenses:
		lenses.append(clean_definition(PetProfile.lens_to_dict(lens)))
	var blocks: Array = []
	for block: Variant in pet.logic.top_blocks():
		if block is Dictionary and (str(block.get("type", "")) == CHAT_HAT or REACTION_HATS.has(str(block.get("type", "")))):
			blocks.append(block)
	return {
		"fileType": FILE_TYPE, "personalityVersion": VERSION, "id": clean_id(id) if clean_id(id) != "" else "custom", "name": display_name, "description": description,
		"revision": 1, "sections": {"params": params, "valueDefs": value_defs, "lenses": lenses, "blocks": blocks},
	}


static func write_file(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	return OK
