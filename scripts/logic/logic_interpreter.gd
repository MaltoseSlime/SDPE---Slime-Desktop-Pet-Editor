extends Node
## 邏輯 JSON 直譯器(主企劃書第四章模組 C 流程四):讀取 HTML 積木編輯器導出的
## `slime_pet_logic_export` 檔,讓桌寵執行裡面的積木。每隻桌寵一個實例(Pet.logic)。
##
## 積木格式:`workspaceState` 是 Blockly 標準序列化(blocks.blocks 為頂層積木陣列,
## 每顆積木有 type / id / fields / inputs / next),積木 type 對照見 docs/html_side_progress/。
##
## 防呆(流程四):找不到的動作由 Pet.play_action 降級為 idle_0;找不到的數值視為 0;
## 不支援或尚未實作的積木(狀態鏡、小道具事件、對話選項等)靜默略過並只警告一次,
## 不會讓程式中斷。匯入前先驗證檔案類型、大小、巢狀深度與陣列長度上限。
##
## 中斷:每條積木鏈開始時記下 Pet.action_generation,每次等待醒來或執行下一顆前都比對,
## 拖曳、interact 等即時互動會讓世代加一,舊的鏈就此中止(避免舊積木延時觸發造成邏輯錯亂)。

const FILE_TYPE := "slime_pet_logic_export"
const MAX_FILE_BYTES := 4_000_000
const MAX_DEPTH := 64
const MAX_ARRAY_LENGTH := 20000
const MAX_LOOP_ITERATIONS := 10000
const DEFAULT_DIALOGUE_SECONDS := 2.0

var _pet: CharacterBody2D
var _state: Node
var _translations: Dictionary = {}
var _translation_by_block: Dictionary = {}
var _translation_by_text: Dictionary = {}
## 積木檔 knownCharacters 裡的角色名單(辨識代號 → 項目),只用來對引用了未知角色代號的積木發警告。
var _known_characters: Dictionary = {}
var _action_hats: Dictionary = {}
var _timers: Array[Timer] = []
var _running: Dictionary = {}
var _warned: Dictionary = {}
var _run_stamp := 0
const STATE_POLL_SECONDS := 0.5
## 雙人對話中雙方站定的時間:一句還在顯示時用 CONVERSE_HOLD(等點擊可能很久),句子結束後只再停留 CONVERSE_LINGER 秒,
## 下一句(對方的台詞)會重新拉長。
const CONVERSE_HOLD := 60.0
const CONVERSE_LINGER := 1.0
## WAIT=false 的句子不會等到說完,雙方先站定這麼久(下一句會重新拉長,最後一句之後自然放行)。
const NO_WAIT_STAND := 5.0
var _state_hats: Array[Dictionary] = []
var _state_timer: Timer
var _state_last: Dictionary = {}
## 由「事件觸發的自主靜音」登記的解除條件:每筆 {fields = 觸發它的 event_when_pet_state 的欄位};條件消失就自動解除靜音。
var _mute_releases: Array[Dictionary] = []
## 積木 id → 它所屬的頂層事件積木(載入時建立),用來知道「這顆 pet_mute 是在哪個事件裡執行的」。
var _hat_of_block: Dictionary = {}
var _memory_hats: Array[Dictionary] = []
## 小遊戲結果事件(event_when_dice_contest / event_when_rps):遊戲結束時依結果觸發,見 run_game_hats。
var _game_hats: Array[Dictionary] = []
## 邀請對戰事件(event_when_game_invited):這隻桌寵「被邀請」而接受/拒絕時,用自己的台詞取代內建那一句,見 run_invite_hats。
var _invite_hats: Array[Dictionary] = []
## 小道具事件(event_prop_collected / event_prop_rubbed / event_prop_candidate):見 run_prop_hats。
var _prop_hats: Array[Dictionary] = []
## 特效事件(event_when_effect):有人的 PetEffects 開始播放特效時觸發,見 _on_effect_played。
var _effect_hats: Array[Dictionary] = []
## 家具使用事件(event_furniture_join / event_furniture_leave):有人開始/結束使用家具時觸發,見 _on_furniture_use_changed。
var _furniture_hats: Array[Dictionary] = []
## 性格帶進來的事件(頂層積木)。和使用者自己的積木檔(_top_blocks)是兩個獨立的層:換性格只換這一層,絕不會動到使用者寫的內容。
var _personality_blocks: Array = []
## 規則層:桌寵管理「交互行為」頁籤編出來的事件(見 InteractionRules.compile),和性格層一樣不動使用者的積木檔。
var _rule_blocks: Array = []
## 「只用性格的」:true 時使用者自己的閒聊事件(chat)/反應類事件(reactions)暫時停用(沒有被刪,關掉就恢復)。
var _skip_own := {"chat": false, "reactions": false}
const REACTION_HAT_TYPES: Array[String] = ["event_when_action", "event_when_dice_contest", "event_when_rps", "event_when_game_invited"]
var _duet_partner: Node
var _duet_partner_msec := 0
var _top_blocks: Array = []
var _every_hats: Array[Dictionary] = []
var _chat_hats: Array[Dictionary] = []
var _chat_running := false

# --- 失控保護(看門狗) ---
## 積木失控(死循環、事件被過度頻繁觸發、對話洗版)時的處理:第一時間中止目前所有積木鏈、停用肇事的事件、寫一筆錯誤紀錄
## (PetErrorLog);在 STRIKE_WINDOW_MSEC 內累積 MAX_STRIKES 次就強制這隻桌寵退場(DesktopShellState.pet_ejected)。
## 正常使用碰不到這些門檻:事件觸發率上限約每秒 24 次(SEC 下限 0.1 的計時事件剛好在線內)、對話每秒 12 句。
const HAT_RUNS_LIMIT := 120
const HAT_RUNS_WINDOW_MSEC := 5000
const DIALOGUES_LIMIT := 12
const DIALOGUES_WINDOW_MSEC := 1000
## 一影格內最多執行這麼多顆積木,超過就讓出這一影格(避免一條超長/超巢狀的鏈卡住整個程式)。
const STEPS_PER_FRAME := 2000
## 迴圈連續這麼多圈都沒有真正的等待/對話/輸入(純空轉)就當死循環(測試會調小它)。迴圈每圈至少讓出一影格,所以預設大約是 50 秒的空轉。
var busy_loop_limit := 3000
const MAX_STRIKES := 3
const STRIKE_WINDOW_MSEC := 600000
var _rates: Dictionary = {}
var _disabled_hats: Dictionary = {}
var _strikes: Array[int] = []
var _ejected := false
var _budget_frame := -1
var _frame_steps := 0
## 每次有「真正的等待」(等待積木、對話、文字輸入)就加一;迴圈用它判斷這一圈有沒有讓時間流動。
var _progress_stamp := 0


func setup(pet: CharacterBody2D) -> void:
	_pet = pet
	_state = get_node("/root/DesktopShellState")
	pet.action_started.connect(_on_action_started)
	pet.memory_reset.connect(_on_memory_reset)


## 從檔案載入。失敗回傳 false 並保留原本已載入的積木。
func load_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		push_warning("積木檔無法開啟或超過大小上限: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("積木檔不是有效的 JSON 物件: %s" % path)
		return false
	return load_data(parsed)


func load_data(data: Dictionary) -> bool:
	if data.get("fileType", "") != FILE_TYPE:
		push_warning("這不是桌寵邏輯匯出檔(fileType 不符)")
		return false
	if not _within_limits(data, 0):
		push_warning("積木檔的巢狀深度或陣列長度超過上限,已拒絕匯入")
		return false
	var tag: String = data.get("recognitionTag", "")
	if tag != "" and tag != _pet.recognition_tag:
		push_warning("積木檔的辨識代號 '%s' 與這隻桌寵 '%s' 不同,仍照常載入" % [tag, _pet.recognition_tag])
	clear()
	_translations = data.get("dialogueTranslations", {}) if data.get("dialogueTranslations") is Dictionary else {}
	_index_translations()
	# 標準格式是 Blockly 的 {blocks: {languageVersion, blocks: [...]}};手寫/舊檔常少包一層(blocks 直接是陣列),兩種都接受。
	var blocks: Array = []
	var workspace: Variant = data.get("workspaceState", {})
	if workspace is Dictionary:
		var container: Variant = workspace.get("blocks", [])
		if container is Array:
			blocks = container
		elif container is Dictionary and container.get("blocks") is Array:
			blocks = container["blocks"]
	_top_blocks = blocks
	for block: Dictionary in blocks:
		if not _own_skipped(block):
			_register_hat(block)
		LensChecker._walk(block, func(inner: Dictionary) -> void:
			if inner.has("id"):
				_hat_of_block[str(inner["id"])] = block)
	for block: Dictionary in _personality_blocks:
		_register_hat(block)
	for block: Dictionary in _rule_blocks:
		_register_hat(block)
	_load_known_characters(data)
	return true


## 整理翻譯表:標準格式 {對話id: {語言: 文字, __blockId}} 建 __blockId 索引;
## 「語言在最外層」的舊格式 {語言: {鍵: 文字}} 則以「其中一個語言的原文」當線索,建立 原文 → {語言: 文字} 的別名表。
func _index_translations() -> void:
	for entry in _translations.values():
		if entry is Dictionary and entry.has("__blockId"):
			_translation_by_block[str(entry["__blockId"])] = entry
	var language_first := not _translations.is_empty()
	for key in _translations:
		if not (RegEx.create_from_string("^[A-Za-z]{2,3}([-_][A-Za-z0-9]+)?$").search(str(key)) != null and _translations[key] is Dictionary):
			language_first = false
			break
	if not language_first:
		return
	var by_key := {}
	for language: String in _translations:
		for text_key: String in _translations[language]:
			if not by_key.has(text_key):
				by_key[text_key] = {}
			by_key[text_key][language] = str(_translations[language][text_key])
	for text_key in by_key:
		# 積木的 TEXT 可能直接放翻譯鍵(如 T03_CHAT_1),也可能放某個語言的原文,兩種都能對到。
		_translation_by_text[text_key] = by_key[text_key]
		for text in by_key[text_key].values():
			_translation_by_text[text] = by_key[text_key]


## 讀積木檔的選用頂層欄位 knownCharacters(HTML 端的角色名單),並對「積木引用了、但不在名單也不在場」的辨識代號警告一次
## (不阻擋,只是提醒創作者可能打錯字)。沒有名單就完全不檢查。
func _load_known_characters(data: Dictionary) -> void:
	var roster: Variant = data.get("knownCharacters")
	if not roster is Array:
		return
	for entry in roster:
		if entry is Dictionary and str(entry.get("recognitionTag", "")) != "":
			_known_characters[str(entry["recognitionTag"])] = entry
	if _known_characters.is_empty():
		return
	var present := get_tree().get_nodes_in_group("pets").map(func(p: Node) -> String: return p.recognition_tag)
	for hat in _top_blocks:
		LensChecker._walk(hat, func(block: Dictionary) -> void:
			var fields: Dictionary = block.get("fields", {})
			# 只有真的用來指定「角色」的積木才檢查(event_when_chat 的 TAG 是閒聊情境標籤,不是角色代號)。
			var type := str(block.get("type", ""))
			if type == "dialogue_line" and str(fields.get("SPEAKER", "")).strip_edges() != "":
				var speaker_tag := str(fields["SPEAKER"]).strip_edges()
				if not _known_characters.has(speaker_tag) and not present.has(speaker_tag):
					_warn_once("積木引用了角色代號「%s」,但它不在積木檔的角色名單(knownCharacters)、目前場上也沒有這個角色" % speaker_tag)
				return
			if not (type == "cond_pet_present" or type == "toggle_follow_start" or (type == "phys_temp_state" and str(fields.get("MODE", "")) in ["跟隨", "follow"])):
				return
			for tag in _character_tags(fields):
				if not _known_characters.has(tag) and not present.has(tag):
					_warn_once("積木引用了角色代號「%s」,但它不在積木檔的角色名單(knownCharacters)、目前場上也沒有這個角色" % tag))


## 一顆積木的欄位裡引用的角色辨識代號:TAGS(逗號/頓號/空白分隔)優先,沒有就用 TAG;toggle_follow_start、SPEAKER 同理。
func _character_tags(fields: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	var raw := str(fields.get("TAGS", "")).strip_edges()
	if raw == "":
		raw = str(fields.get("TAG", "")).strip_edges()
	for part in raw.replace("、", ",").replace(" ", ",").split(",", false):
		tags.append(part.strip_edges())
	return tags


## 佔位閒聊(臨時內容):HTML 端「當閒聊時」積木完成、匯入過閒聊事件之前,「說點什麼」先用這三句(都是 chat 標籤)。
## 一旦匯入的積木檔裡有任何閒聊事件,就完全改用匯入的內容,這三句不再出現。
const PLACEHOLDER_CHAT: Array[String] = ["今天天氣不錯呢。", "你在忙什麼呀?", "……(伸了個懶腰)"]


## 「說點什麼」永遠有話可說(至少有佔位內容),所以選單項目不會是灰的。
func has_chat_lines() -> bool:
	return true


func _placeholder_chat_hats() -> Array[Dictionary]:
	var hats: Array[Dictionary] = []
	for i in PLACEHOLDER_CHAT.size():
		var line := {"type": "dialogue_line", "id": "placeholder_line_%d" % i, "fields": {"TEXT": PLACEHOLDER_CHAT[i], "TYPEWRITER": true, "AUTOSEC": 3.0}}
		hats.append({"type": "event_when_chat", "id": "placeholder_%d" % i, "fields": {"TAG": "chat"}, "inputs": {"DO": {"block": line}}})
	return hats


## 說點什麼:從「當閒聊時」事件裡挑一個符合目前情境的,隨機抽一個執行。
## 情境標籤:chat 閒聊(平常)、rest 休息中(沒有專屬的休息中對話時退回閒聊)、sleep 睡眠中(不退回閒聊,
## 睡著了就不該講平常的話)、lens 特殊差分(狀態鏡生效中;LENS 空白代表任何鏡片,否則要是目前生效的那個)。
## 鏡片對話與狀態對話混在同一個抽獎池裡。已經有一段閒聊在進行時回傳 false,不重複開口。
## context_override 只給測試者模式用:指定 chat/rest/sleep 來強制用該情境的池子抽(空字串 = 依桌寵目前實際情境);
## 強制抽時也會無視「已經有閒聊在進行」(先清掉舊的)。
func say_something(context_override := "") -> bool:
	if _chat_running and context_override == "":
		return false
	var pool := _eligible_chat_hats(context_override)
	if pool.is_empty():
		return false
	if context_override != "":
		_pet.interrupt_scripts()
		_chat_running = false
	_run_chat(pool.pick_random())
	return true


## 測試者模式:目前載入的所有事件積木(頂層帽子),每項 {kind, label, hat}。閒聊事件在沒有匯入內容時列出佔位的三句。
func list_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for action: StringName in _action_hats:
		for hat: Dictionary in _action_hats[action]:
			events.append({"kind": "action", "label": _named(tr("當角色正在 [%s] 時") % action, hat), "hat": hat})
	for hat in _every_hats:
		events.append({"kind": "timer", "label": _named(tr("每 %s 秒") % str(hat.get("fields", {}).get("SEC", "?")), hat), "hat": hat})
	for hat in _state_hats:
		events.append({"kind": "state", "label": _named(tr("當場內有人的狀態是 [%s %s]") % [hat.get("fields", {}).get("KIND", ""), hat.get("fields", {}).get("VALUE", "")], hat), "hat": hat})
	for hat in _game_hats:
		var game_fields: Dictionary = hat.get("fields", {})
		events.append({"kind": "game", "label": _named(tr("遊戲結果 [%s · %s]") % ["拚骰" if str(hat.get("type", "")) == "event_when_dice_contest" else "猜拳", game_fields.get("RESULT", "any")], hat), "hat": hat})
	for hat in _invite_hats:
		var invite_fields: Dictionary = hat.get("fields", {})
		events.append({"kind": "game", "label": _named(tr("被邀請對戰 [%s · %s]") % [invite_fields.get("GAME", "any"), invite_fields.get("ANSWER", "any")], hat), "hat": hat})
	for hat in _prop_hats:
		var prop_type := str(hat.get("type", "")).trim_prefix("event_prop_")
		var prop_fields: Dictionary = hat.get("fields", {})
		events.append({"kind": "prop", "label": _named(tr("當道具 [%s] %s 時") % [str(prop_fields.get("PROP", "")) if str(prop_fields.get("PROP", "")) != "" else "任何", {"collected": "被拾取/吃掉", "rubbed": "被摩擦", "candidate": "成為候選對象"}.get(prop_type, prop_type)], hat), "hat": hat})
	for hat in _effect_hats:
		var effect_fields: Dictionary = hat.get("fields", {})
		events.append({"kind": "effect", "label": _named(tr("當 [%s] 播放特效 [%s] 時") % [str(effect_fields.get("TAGS", "")) if str(effect_fields.get("TAGS", "")) != "" else "其他桌寵", str(effect_fields.get("EFFECT", "")) if str(effect_fields.get("EFFECT", "")) != "" else "任何"], hat), "hat": hat})
	var chats: Array[Dictionary] = _chat_hats if not _chat_hats.is_empty() else _placeholder_chat_hats()
	for hat in chats:
		var fields: Dictionary = hat.get("fields", {})
		var tag :=str(fields.get("TAG", "chat"))
		var lens := str(fields.get("LENS", ""))
		var suffix := " · " + lens if lens != "" else ""
		events.append({"kind": "chat", "label": _named(tr("閒聊 [%s%s] · %s") % [tag, suffix, _first_text(hat)], hat), "hat": hat})
	return events


## 測試者模式:積木檔裡所有對話積木(不管在哪個事件底下),每項 {label, block}。
func list_dialogues() -> Array[Dictionary]:
	var dialogues: Array[Dictionary] = []
	var blocks: Array = _top_blocks
	if _chat_hats.is_empty():
		blocks = blocks + _placeholder_chat_hats()
	for top in blocks:
		LensChecker._walk(top, func(block: Dictionary) -> void:
			if block.get("type", "") == "dialogue_line":
				var who := str(block.get("fields", {}).get("SPEAKER", "")).strip_edges()
				dialogues.append({"label": ("[%s] " % who if who != "" else "") + _resolve_text(block).replace("\n", " ").left(28), "block": block}))
	return dialogues


## 強制執行一個事件積木:先中止目前的積木鏈與動作佔用,再無視「同一事件已在執行」的保護直接跑。
func force_run_hat(hat: Dictionary) -> void:
	_pet.interrupt_scripts()
	_disabled_hats.erase(str(hat.get("id", hat.hash())))
	_running.erase(str(hat.get("id", hat.hash())))
	_chat_running = false
	_run_hat(hat)


## 強制播放單獨一句對話積木(含它的選項與 GOTO,但不接後面的 next)。
func force_dialogue(block: Dictionary) -> void:
	var single := block.duplicate(false)
	single.erase("next")
	force_run_hat({"type": "event_forced", "id": "forced_dialogue", "inputs": {"DO": {"block": single}}})


## 事件積木有 NAME 欄位(創作者取的名字)就用「名字 — 說明」,方便在測試者視窗辨認。
func _named(description: String, hat: Dictionary) -> String:
	var event_name := str(hat.get("fields", {}).get("NAME", "")).strip_edges()
	return "%s — %s" % [event_name, description] if event_name != "" else description


func _first_text(hat: Dictionary) -> String:
	var found := [""]
	LensChecker._walk(hat, func(block: Dictionary) -> void:
		if found[0] == "" and block.get("type", "") == "dialogue_line":
			found[0] = _resolve_text(block).replace("\n", " ").left(20))
	return found[0]


func _eligible_chat_hats(context_override := "") -> Array[Dictionary]:
	var context := context_override if context_override != "" else str(_pet.chat_context())
	var lens_name: String = _pet.current_lens_name()
	var by_state: Array[Dictionary] = []
	var chat_tier: Array[Dictionary] = []
	var lens_tier: Array[Dictionary] = []
	var hats: Array[Dictionary] = _chat_hats if not _chat_hats.is_empty() else _placeholder_chat_hats()
	for hat in hats:
		# 資格檢查:條件不成立(例如指定的桌寵不在場)的閒聊事件不進抽獎池,免得抽中了卻什麼都不說。
		if not _chat_guard_passes(hat):
			continue
		var fields: Dictionary = hat.get("fields", {})
		var tag := _normalize_chat_tag(str(fields.get("TAG", "chat")))
		if tag == "lens":
			var wanted := str(fields.get("LENS", ""))
			if lens_name != "" and (wanted == "" or wanted == lens_name):
				lens_tier.append(hat)
		elif tag == context:
			by_state.append(hat)
		elif tag == "chat":
			chat_tier.append(hat)
	if by_state.is_empty() and context == "rest":
		by_state = chat_tier
	var pool: Array[Dictionary] = []
	pool.append_array(by_state)
	pool.append_array(lens_tier)
	return pool


## 閒聊事件的「對象檢查/資格檢查」:如果事件的內容一開頭就是一個「如果…那麼」(controls_if,沒有否則、後面沒有其他積木),
## 或直接是一個條件積木包著內容(例如「如果桌寵 [某某] 在場那麼:…」),而且條件只由「不帶隨機」的積木組成
## (在場判斷、時間/日期/星期、數值比較、Flag、狀態鏡、比較與邏輯運算),就把它當成抽選資格:條件現在不成立就不進池子。
## 機率條件(有 X% 的機率)不算資格,因為抽中後執行時還會再擲一次,這裡先擲會變成擲兩次。其他形式的事件一律視為有資格。
const PURE_CONDITION_TYPES: Array[String] = [
	"cond_pet_present", "cond_pet_state", "cond_pet_sleeping", "cond_move_mode", "cond_holding_prop", "cond_text_set", "cond_time_between", "cond_date_is", "cond_weekday_is", "cond_value_compare", "flag_check",
	"cond_game_stat", "cond_target_is", "cond_lens_active", "cond_lens_active_over", "cond_mood_compare", "cond_mood_zone", "cond_energy_compare", "cond_rest_state", "cond_lens_nature", "cond_loss_streak", "cond_ball_play", "cond_timer_running", "logic_compare", "logic_operation", "logic_boolean", "math_number", "math_random_between", "text",
	"cond_furniture_using", "cond_furniture_sharing", "cond_furniture_state",
]


func _chat_guard_passes(hat: Dictionary) -> bool:
	var first := _statement(hat, "DO")
	if first.is_empty() or not first.get("next", {}).get("block", {}).is_empty():
		return true
	var type := str(first.get("type", ""))
	var inputs: Dictionary = first.get("inputs", {})
	var condition: Dictionary
	if type == "controls_if":
		if inputs.has("ELSE") or inputs.has("IF1"):
			return true
		condition = inputs.get("IF0", {}).get("block", {})
	elif PURE_CONDITION_TYPES.has(type) and inputs.has("DO"):
		condition = first
	else:
		return true
	if condition.is_empty() or not _is_pure_condition(condition):
		return true
	return _truthy(_eval_block(condition))


func _is_pure_condition(block: Dictionary) -> bool:
	if not PURE_CONDITION_TYPES.has(str(block.get("type", ""))):
		return false
	for input_name in block.get("inputs", {}):
		if input_name == "DO":
			continue
		var entry: Variant = block["inputs"][input_name]
		if entry is Dictionary:
			var inner: Dictionary = entry.get("block", entry.get("shadow", {}))
			if not inner.is_empty() and not _is_pure_condition(inner):
				return false
	return true


## 標籤容許英文代號或中文名稱(HTML 端下拉選單的最終格式確定前的寬鬆解析)。
func _normalize_chat_tag(tag: String) -> String:
	var normalized := tag.strip_edges().to_lower()
	match normalized:
		"閒聊", "chat", "":
			return "chat"
		"休息中", "休息", "rest":
			return "rest"
		"睡眠中", "睡眠", "sleep":
			return "sleep"
		"特殊差分", "lens", "state_lens":
			return "lens"
	return normalized


func _run_chat(hat: Dictionary) -> void:
	_chat_running = true
	await _run_hat(hat)
	_chat_running = false


## 目前載入的頂層積木(唯讀用途:設定檢查工具掃描狀態鏡的啟用/解除關係)。
func top_blocks() -> Array:
	return _top_blocks


## 設定性格層:blocks = 性格帶進來的頂層事件積木(閒聊與反應),skip_own_chat / skip_own_reactions = 暫時停用使用者自己的同類事件。
## 只重新登記事件,不動使用者的積木檔內容。
func set_personality_layer(blocks: Array, skip_own_chat: bool, skip_own_reactions: bool) -> void:
	_personality_blocks = blocks
	_skip_own["chat"] = skip_own_chat
	_skip_own["reactions"] = skip_own_reactions
	var user_blocks := _top_blocks
	_clear_registrations()
	_top_blocks = user_blocks
	for block: Dictionary in user_blocks:
		if not _own_skipped(block):
			_register_hat(block)
	for block: Dictionary in _personality_blocks:
		_register_hat(block)
	for block: Dictionary in _rule_blocks:
		_register_hat(block)


## 設定規則層(見 InteractionRules.compile):只重新登記事件,不動使用者的積木檔內容。
func set_rule_layer(blocks: Array) -> void:
	_rule_blocks = blocks
	set_personality_layer(_personality_blocks, bool(_skip_own["chat"]), bool(_skip_own["reactions"]))


## 使用者自己的這顆事件現在是不是被「只用性格的」暫時停用。
func _own_skipped(block: Dictionary) -> bool:
	var type := str(block.get("type", ""))
	return (type == "event_when_chat" and bool(_skip_own["chat"])) or (REACTION_HAT_TYPES.has(type) and bool(_skip_own["reactions"]))


## 目前生效的性格層事件數(給介面與測試看)。
func personality_block_count() -> int:
	return _personality_blocks.size()


func clear() -> void:
	_top_blocks = []
	_clear_registrations()
	_translations = {}
	_translation_by_block = {}
	_translation_by_text = {}
	_known_characters = {}


## 把性格檔自帶的對話翻譯(personality.json 的 dialogueTranslations,格式跟積木檔的一樣:「語言在最外層」的
## {語言: {原文: 翻譯}})併進來,不清掉使用者自己匯入積木檔帶的翻譯表(見 _index_translations)。
## PersonalityApplier.rebuild_layer() 每次重建性格事件層時呼叫;原文碰撞時使用者自己的翻譯優先,不會被蓋掉。
## clear()(重新匯入積木檔)會把這裡合併進來的內容一起清掉,呼叫端要記得在那之後重跑一次 rebuild_layer()
## (現有的性格套用/存讀流程本來就會這樣做,不是這個功能新增的責任)。
func merge_translations(table: Dictionary) -> void:
	for language: String in table:
		if not table[language] is Dictionary:
			continue
		for original_text: String in table[language]:
			if not _translation_by_text.has(original_text):
				_translation_by_text[original_text] = {}
			var entry: Dictionary = _translation_by_text[original_text]
			if not entry.has(language):
				entry[language] = str(table[language][original_text])


## 把所有事件登記(帽子、計時器…)清掉,不動積木內容本身、翻譯表。
func _clear_registrations() -> void:
	_memory_hats.clear()
	_game_hats.clear()
	_invite_hats.clear()
	_effect_hats.clear()
	_furniture_hats.clear()
	_prop_hats.clear()
	_state_hats.clear()
	_state_last.clear()
	_mute_releases.clear()
	_hat_of_block.clear()
	if _state_timer != null:
		_state_timer.queue_free()
		_state_timer = null
	_every_hats.clear()
	_chat_hats.clear()
	_chat_running = false
	for timer in _timers:
		timer.queue_free()
	_timers.clear()
	_action_hats.clear()
	_running.clear()


func _within_limits(node: Variant, depth: int) -> bool:
	if depth > MAX_DEPTH:
		return false
	if node is Dictionary:
		for value in node.values():
			if not _within_limits(value, depth + 1):
				return false
	elif node is Array:
		if node.size() > MAX_ARRAY_LENGTH:
			return false
		for value in node:
			if not _within_limits(value, depth + 1):
				return false
	return true


func _register_hat(block: Dictionary) -> void:
	var fields: Dictionary = block.get("fields", {})
	match block.get("type", ""):
		"event_when_action":
			var action := StringName(str(fields.get("ACTION", "")))
			if not _action_hats.has(action):
				_action_hats[action] = []
			_action_hats[action].append(block)
		"event_every_seconds":
			_every_hats.append(block)
			var timer := Timer.new()
			timer.wait_time = maxf(_number(fields.get("SEC", 1.0)), 0.1)
			timer.timeout.connect(_run_hat.bind(block))
			add_child(timer)
			timer.start()
			_timers.append(timer)
		"event_when_chat":
			# 閒聊事件不會自己觸發,只在「說點什麼」時依目前情境被抽中。
			_chat_hats.append(block)
		"event_when_memory_reset":
			_memory_hats.append(block)
		"event_when_dice_contest", "event_when_rps":
			_game_hats.append(block)
		"event_when_game_invited":
			_invite_hats.append(block)
		"event_when_effect":
			_effect_hats.append(block)
			if _state != null and not _state.effect_played.is_connected(_on_effect_played):
				_state.effect_played.connect(_on_effect_played)
		"event_furniture_join", "event_furniture_leave":
			_furniture_hats.append(block)
			if _state != null and not _state.furniture_use_changed.is_connected(_on_furniture_use_changed):
				_state.furniture_use_changed.connect(_on_furniture_use_changed)
		"event_when_pet_state":
			# 「當場內有人的狀態是…」:邊緣觸發,只有載入了這類事件才會建立低頻輪詢計時器(沒有就完全不耗效能)。
			_state_hats.append(block)
			if _state_timer == null:
				_state_timer = Timer.new()
				_state_timer.wait_time = STATE_POLL_SECONDS
				_state_timer.timeout.connect(_poll_pet_states)
				add_child(_state_timer)
				_state_timer.start()
		"event_prop_collected", "event_prop_rubbed", "event_prop_candidate":
			_prop_hats.append(block)
		_:
			pass


## 小遊戲(kind = "dice_contest" 拚骰 / "rps" 猜拳)結束後,這隻桌寵的結果(win / lose / tie)有對應的事件就執行,
## 回傳有沒有事件接手(沒有的話呼叫端用內建反應)。事件的 RESULT 欄位:win / lose / tie(猜拳的 draw 也算 tie)/ any。
func run_game_hats(kind: String, outcome: String) -> bool:
	var hat_type := "event_when_dice_contest" if kind == "dice_contest" else "event_when_rps"
	var handled := false
	for hat in _game_hats:
		if str(hat.get("type", "")) != hat_type:
			continue
		var wanted := str(hat.get("fields", {}).get("RESULT", "any")).to_lower()
		wanted = "tie" if wanted == "draw" else wanted
		if wanted == "any" or wanted == outcome:
			handled = true
			_run_hat(hat)
	return handled


## 被邀請對戰(GameInvite)而決定接受/拒絕時呼叫:有符合的邀請事件就(隨機挑一個)跑完它,回傳 true 代表內建那句台詞不用說了。
## 事件欄位(都可省略):GAME any(預設)/ rps / dice、ANSWER any(預設)/ accept / refuse、FROM 邀請者的辨識代號(空白 = 任何人)。
## 同一種情況寫多個事件 = 多種台詞隨機輪替。必須等事件跑完才回來,邀請流程才不會在對方講到一半時就開打。
func run_invite_hats(game: String, answer: String, inviter_tag: String) -> bool:
	var matching: Array[Dictionary] = []
	for hat in _invite_hats:
		var fields: Dictionary = hat.get("fields", {})
		var wanted_game := str(fields.get("GAME", "any")).to_lower()
		wanted_game = "dice" if wanted_game == "dice_contest" else wanted_game
		var wanted_answer := str(fields.get("ANSWER", "any")).to_lower()
		wanted_answer = "refuse" if wanted_answer == "reject" else wanted_answer
		var wanted_from := str(fields.get("FROM", "")).strip_edges()
		if wanted_game in ["any", game] and wanted_answer in ["any", answer] and (wanted_from == "" or wanted_from == inviter_tag):
			matching.append(hat)
	if matching.is_empty():
		return false
	await _run_hat(matching.pick_random())
	return true


## 擲骰(dice_roll):骰 COUNT 顆 SIDES 面骰 + MOD,和檢定值 DC(0 = 不檢定)比,結果存進 KEY(對話用 {roll:KEY}、條件用 cond_dice_pass / cond_dice_compare),
## SHOW 是否顯示在氣泡,SEC 是擲之前的懸念秒數(桌寵抖動)。
func _exec_dice_roll(block: Dictionary, token: int) -> String:
	var fields: Dictionary = block.get("fields", {})
	var key := PetText.sanitize_key(str(fields.get("KEY", "roll")))
	if key == "":
		key = "roll"
	var sides := clampi(int(_number(fields.get("SIDES", 20))), DiceGame.MIN_SIDES, DiceGame.MAX_SIDES)
	var count := clampi(int(_number(fields.get("COUNT", 1))), 1, DiceGame.MAX_COUNT)
	await DiceGame.roll_and_show(_pet, sides, count, int(_number(fields.get("MOD", 0))), maxi(int(_number(fields.get("DC", 0))), 0), key,
			_truthy(fields.get("SHOW", true)), clampf(_number(fields.get("SEC", 1.0)), 0.0, 5.0))
	return "abort" if _pet.action_generation != token else ""


## 拚骰(dice_contest):參加者 = 自己(INCLUDE_SELF)+ TAGS 指定的桌寵(空白 = 場內所有其他桌寵);
## TIE = reroll(並列第一的重擲)或 draw(直接平手)。結束後每個參加者的 event_when_dice_contest 會被觸發。
func _exec_dice_contest(block: Dictionary, token: int) -> String:
	var fields: Dictionary = block.get("fields", {})
	var wanted := _character_tags(fields)
	var pets: Array = []
	if _truthy(fields.get("INCLUDE_SELF", true)):
		pets.append(_pet)
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other != _pet and not other.is_queued_for_deletion() and (wanted.is_empty() or wanted.has(other.recognition_tag)):
			pets.append(other)
	var key := PetText.sanitize_key(str(fields.get("KEY", "contest")))
	await DiceGame.contest(_pet, pets, clampi(int(_number(fields.get("SIDES", 20))), DiceGame.MIN_SIDES, DiceGame.MAX_SIDES),
			clampi(int(_number(fields.get("COUNT", 1))), 1, DiceGame.MAX_COUNT), int(_number(fields.get("MOD", 0))),
			"draw" if str(fields.get("TIE", "reroll")).to_lower() == "draw" else "reroll", key if key != "" else "contest", _best_of(fields))
	return "abort" if _pet.action_generation != token else ""


## 賽制欄位 BEST_OF:auto / 空白 / 0 = 用這隻桌寵右鍵選單的「賽制」,否則 1(一戰定勝負)、3(三戰兩勝)、5(五戰三勝)。
func _best_of(fields: Dictionary) -> int:
	var raw := str(fields.get("BEST_OF", "auto")).strip_edges().to_lower()
	var wanted := int(raw) if raw.is_valid_int() else 0
	return wanted if _pet.BEST_OF_CHOICES.has(wanted) else _pet.game_best_of


## 猜拳(rps_play):WITH 空白或 user = 跟使用者玩(氣泡按鈕出拳),否則是另一隻桌寵的辨識代號(找不到就略過)。
func _exec_rps(block: Dictionary, token: int) -> String:
	var opponent_tag := str(block.get("fields", {}).get("WITH", "user")).strip_edges()
	var best_of := _best_of(block.get("fields", {}))
	if opponent_tag == "" or opponent_tag.to_lower() == "user":
		await RpsGame.play_user(_pet, best_of)
	else:
		var other := _nearest_pet_by_tag(opponent_tag)
		if other == null:
			_warn_once("猜拳對象「%s」不在場,已略過" % opponent_tag)
		else:
			await RpsGame.play_pets(_pet, other, best_of)
	return "abort" if _pet.action_generation != token else ""


## 用「|」把一串備選拆開,但大括號 { } 裡面的「|」不算分隔(例如 {pick:甲|乙} 是文字裡的單字池,整個算一項)。前後空白去掉、空的略過。
static func split_pool(text: String, separator := "|") -> Array:
	var pieces: Array = []
	var depth := 0
	var current := ""
	for character in text:
		if character == "{":
			depth += 1
		elif character == "}":
			depth = maxi(depth - 1, 0)
		if character == separator and depth == 0:
			if current.strip_edges() != "":
				pieces.append(current.strip_edges())
			current = ""
		else:
			current += character
	if current.strip_edges() != "":
		pieces.append(current.strip_edges())
	return pieces


## 隨機說一句(say_random):性格編譯出來的事件用,網頁也有這顆(G34)。LINES 隨機挑一句——性格編譯的是字串陣列,網頁積木是用「|」隔開的一個字串;
## PCT = 這次真的開口的機率(0~100,預設 100)。走一般對話積木同一條路(氣泡、排隊、插值 {數值}、被打斷都一樣)。
func _exec_say_random(block: Dictionary, token: int) -> String:
	var fields: Dictionary = block.get("fields", {})
	var lines: Variant = fields.get("LINES")
	if lines is String:
		lines = split_pool(lines as String)
	if not lines is Array or (lines as Array).is_empty():
		return ""
	var chance: Variant = fields.get("PCT", 100.0)
	if (chance is float or chance is int) and randf() * 100.0 >= float(chance):
		return ""
	var say := {"type": "dialogue_line", "id": str(block.get("id", "")) + ":line", "fields": {"TEXT": str((lines as Array).pick_random()), "WAIT": true, "AUTOSEC": 0, "TYPEWRITER": true, "BUBBLE": str(fields.get("BUBBLE", "speech"))}}
	return await _dialogue_line(say, token)


## 邀請對戰(game_invite):像桌寵自己發起的邀請一樣,對方會依狀況接受或拒絕(睡覺必拒、忙/心情差機率高、使用者設了「一律拒絕」必拒),
## 接受就開打並等整場結束才做下一顆;拒絕就結束。WITH = 對方的辨識代號(空白 = 場上隨機一隻別的桌寵)、GAME = rps / dice / random(預設)、
## BEST_OF = auto(用右鍵選單的賽制,預設)/ 1 / 3 / 5 / random(邀請者自己決定,和自動邀請一樣)。對象不在場就略過。
func _exec_game_invite(block: Dictionary, token: int) -> String:
	var fields: Dictionary = block.get("fields", {})
	var tag := str(fields.get("WITH", "")).strip_edges()
	var target: Node = null
	if tag == "":
		var others: Array = get_tree().get_nodes_in_group("pets").filter(func(p: Node) -> bool: return p != _pet and not p.is_queued_for_deletion() and not p.entering)
		if not others.is_empty():
			target = others.pick_random()
	else:
		target = _nearest_pet_by_tag(tag)
	if target == null:
		_warn_once("邀請對戰的對象「%s」不在場,已略過" % (tag if tag != "" else "任何桌寵"))
		return ""
	var game := str(fields.get("GAME", "random")).to_lower()
	game = "dice" if game == "dice_contest" else game
	if not game in ["rps", "dice"]:
		game = "rps" if randf() < 0.5 else "dice"
	var best_of: int = _pet.pick_invite_best_of() if str(fields.get("BEST_OF", "auto")).strip_edges().to_lower() == "random" else _best_of(fields)
	# 選用欄位 SAY:自己寫的邀請的話,可以用 {self}、{other}(對方)、{pick:甲|乙} 等標記;空白 = 內建台詞。
	var custom_line := ""
	if str(fields.get("SAY", "")).strip_edges() != "":
		_pet.set_counterpart("invitee", target)
		custom_line = _interpolate(str(fields["SAY"]).replace("\\n", "\n"))
	_progress_stamp += 1
	await GameInvite.invite(_pet, target, game, best_of, true, custom_line)
	return "abort" if _pet.action_generation != token else ""


func _nearest_pet_by_tag(tag: String) -> Node:
	var best: Node = null
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other != _pet and other.recognition_tag == tag and not other.is_queued_for_deletion():
			if best == null or absf(other.global_position.x - _pet.global_position.x) < absf(best.global_position.x - _pet.global_position.x):
				best = other
	return best


## 「當記憶被重置時」:重置完成後執行這些事件(例如說一句「咦?我們認識嗎?」)。
func _on_memory_reset() -> void:
	for hat in _memory_hats:
		_run_hat(hat)


## 向使用者要一段文字;回傳 [文字, 是否接受]。沒有輸入介面(測試環境)、被略過、被打斷都回 ["", false]。
## prompt 是純文字問句(輸入視窗用),bubble_text 是同一句問句的氣泡版(BBCode)。
## 桌寵自己(積木)發起的提問不會直接跳出視窗打擾使用者:UiManager 先用氣泡問,使用者按了「回答」才開輸入視窗。
## 輸入視窗開著(ticket.typing)期間,桌寵被點擊/拖曳打斷不會取消輸入。
func _ask_user_text(prompt: String, bubble_text: String, default_text: String, max_length: int) -> Array:
	if _state.text_input_requested.get_connections().is_empty():
		return ["", false]
	_progress_stamp += 1
	var ticket := InputTicket.new()
	var on_cut := func() -> void:
		if not ticket.typing:
			ticket.finish("", false)
	_pet.interrupted.connect(on_cut)
	# 先掛好接收結果的連線再送出請求:輸入介面可能在 emit 當下就同步回覆,那時再 await 就等不到了。
	var result: Array = ["", false]
	ticket.finished.connect(func(text: String, accepted: bool) -> void:
		result[0] = text
		result[1] = accepted)
	_state.text_input_requested.emit(_pet, {"prompt": prompt, "bubble_text": bubble_text, "default": default_text, "max_length": max_length, "direct": false}, ticket)
	if not ticket.closed:
		await ticket.finished
	if is_instance_valid(_pet) and _pet.interrupted.is_connected(on_cut):
		_pet.interrupted.disconnect(on_cut)
	return result


## dialogue_ask_text:桌寵問一句話(PROMPT);使用者輸入的文字(消毒後、最多 MAXLEN 字)存進文字變數 KEY,
## 之後對話裡用 {text:KEY} 顯示。略過就保留原本的值(還沒有值且有 DEFAULT 才設成 DEFAULT)。
## 什麼都沒有也沒關係:KEY 空白(純粹問著玩、不打算記住)照樣會問,只是答案不存;問句空白就用一句通用的問話;
## 使用者略過、關掉、逾時、沒有輸入介面,都只是「沒有答案」,積木鏈照常往下走。
func _exec_ask_text(block: Dictionary, token: int) -> String:
	var fields: Dictionary = block.get("fields", {})
	var key := PetText.sanitize_key(str(fields.get("KEY", "")))
	var max_length := int(_number(fields.get("MAXLEN", PetText.DEFAULT_MAX_LENGTH)))
	max_length = clampi(max_length if max_length > 0 else PetText.DEFAULT_MAX_LENGTH, 1, PetText.HARD_MAX_LENGTH)
	var default_text := PetText.sanitize(str(fields.get("DEFAULT", "")), max_length)
	var prompt := _resolve_text(block, "PROMPT")
	if prompt.strip_edges() == "":
		prompt = "可以告訴我嗎?"
	# 選用欄位 FRESH:每次都重新問,先清掉上次存的答案(這次取消或沒填就是「沒有答案」,不會拿舊答案當這次的)。
	if _truthy(fields.get("FRESH", false)) and key != "":
		_pet.text_values.erase(key)
	var previous := str(_pet.text_values.get(key, default_text)) if key != "" else default_text
	var got := await _ask_user_text(_interpolate(prompt, false), _interpolate(prompt), previous, max_length)
	# 使用者已經打好的答案先存起來,再看是不是中途被打斷(被打斷只會讓後面的積木不再執行)。
	var answer := PetText.sanitize(str(got[0]), max_length)
	# 使用者按了送出卻什麼都沒填:桌寵回一句、取消這次寫入,不執行後面的積木(免得記到沒有意義的空值)。EMPTY_REPLY 欄位可以自訂那句話。
	if bool(got[1]) and answer == "" and _pet.action_generation == token:
		var reply := str(fields.get("EMPTY_REPLY", "")).strip_edges()
		await _dialogue_line({"fields": {"TEXT": reply if reply != "" else tr("你剛剛說得太小聲了,我沒有聽清楚耶..."), "WAIT": true, "AUTOSEC": 3, "TYPEWRITER": true}}, token)
		return "abort"
	if key != "":
		if bool(got[1]) and answer != "":
			_pet.text_values[key] = answer
		elif not _pet.text_values.has(key) and default_text != "":
			_pet.text_values[key] = default_text
	if _pet.action_generation != token:
		return "abort"
	return ""


## keyword_learn:把文字變數 KEY(通常是「詢問使用者文字」剛存下來的答案)記進關鍵詞庫。LIST = pet(桌寵有興趣的,預設;桌寵向使用者學新知識)/ user(使用者有興趣的;桌寵想更了解你)。
## 空白、超長、重複的、庫已滿的都不寫;寫入後立刻存檔。使用者事後可以在桌寵管理 → 性格 → 關鍵詞庫自己維護。
func _exec_keyword_learn(block: Dictionary) -> void:
	var fields: Dictionary = block.get("fields", {})
	var key := PetText.sanitize_key(str(fields.get("KEY", "")))
	var raw := str(_pet.text_values.get(key, "")) if key != "" else ""
	var cleaned := PetText.sanitize_keywords([raw])
	if cleaned.is_empty():
		return
	var word := cleaned[0]
	if str(fields.get("LIST", "pet")).strip_edges().to_lower() == "user":
		var user_list: PackedStringArray = _pet.user_keywords
		if not user_list.has(word) and user_list.size() < PetText.MAX_KEYWORDS:
			user_list.append(word)
			_pet.user_keywords = user_list
	else:
		var pet_list: PackedStringArray = _pet.keywords
		if not pet_list.has(word) and pet_list.size() < PetText.MAX_KEYWORDS:
			pet_list.append(word)
			_pet.keywords = pet_list
	PetProfile.save_pet(_pet)


## random_pick:從選項裡隨機抽一個,結果存進文字變數 KEY(之後用 {text:KEY} 顯示)。
## SOURCE = list(預設,選項寫在 OPTIONS 欄位)或 ask(執行時請使用者輸入選項,PROMPT 是問句);
## 選項用換行、逗號、頓號、分號或豎線分隔。SEC 是抽籤前的懸念秒數(桌寵會抖動一下),預設 1 秒。
func _exec_random_pick(block: Dictionary, token: int) -> String:
	var fields: Dictionary = block.get("fields", {})
	var raw := str(fields.get("OPTIONS", ""))
	if str(fields.get("SOURCE", "list")).to_lower() == "ask":
		var prompt := _interpolate(_resolve_text(block, "PROMPT"), false)
		var question := prompt if prompt != "" else "請輸入幾個選項,用逗號分隔"
		var got := await _ask_user_text(question, PetText.escape_bbcode(question), "", PetText.HARD_MAX_LENGTH)
		if _pet.action_generation != token:
			return "abort"
		if not bool(got[1]):
			return ""
		raw = str(got[0])
	var options := PetText.parse_options(raw)
	if options.is_empty():
		_warn_once("random_pick 沒有可用的選項,已略過")
		return ""
	var suspense := clampf(_number(fields.get("SEC", 1.0)), 0.0, 10.0)
	if suspense > 0.0:
		_pet.shiver(suspense)
		await _wait(suspense)
		if _pet.action_generation != token:
			return "abort"
	var key := PetText.sanitize_key(str(fields.get("KEY", "")))
	if key != "":
		_pet.text_values[key] = options.pick_random()
	return ""


## 引擎自己觸發「當角色正在 [動作] 時」事件(不是真的播動作):精力機制用它發 tired(累了)、wake(睡醒),性格的反應事件可以接。
func fire_event(action: StringName) -> void:
	_on_action_started(action)


## 有沒有寫了這個系統事件(當角色正在 [動作/系統事件] 時)的事件積木。內建的反應(例如計時完成的提醒台詞)可以先問這個,有就交給積木、沒有才用內建台詞。
func has_action_hat(action: StringName) -> bool:
	return not (_action_hats.get(action, []) as Array).is_empty()


## 積木「幫使用者計時」:KIND = countdown 計時器 / stopwatch 計時,TIME = 時間文字(見 PetTimer.parse_duration;計時可以留空 = 記到叫停),SOUND = 時間到的音效(內建音效名稱,空白 = 用這隻桌寵選單設的)。
func _exec_timer_start(fields: Dictionary) -> void:
	var timer_kind := PetTimer.Kind.STOPWATCH if str(fields.get("KIND", "countdown")).to_lower() == "stopwatch" else PetTimer.Kind.COUNTDOWN
	var seconds := PetTimer.parse_duration(str(fields.get("TIME", "")))
	if seconds < 0.0 or (timer_kind == PetTimer.Kind.COUNTDOWN and seconds <= 0.0):
		_warn_once("計時的時間「%s」看不懂或是 0,已略過(可以寫「10 分鐘」「90 秒」「25:00」)" % str(fields.get("TIME", "")))
		return
	var alert_sound := str(fields.get("SOUND", "")).strip_edges()
	if not _pet.pet_timer.start(timer_kind, seconds, alert_sound):
		_warn_once("已經在計時了,新的計時積木已略過")


func _on_action_started(action: StringName) -> void:
	for hat: Dictionary in _action_hats.get(action, []):
		_run_hat(hat)


func _run_hat(hat: Dictionary) -> void:
	var id: String = str(hat.get("id", hat.hash()))
	if _ejected or _disabled_hats.has(id) or _running.has(id):
		return
	if _rate_exceeded("hat:" + id, HAT_RUNS_LIMIT, HAT_RUNS_WINDOW_MSEC):
		_runaway(tr("事件在 %d 秒內被觸發超過 %d 次(疑似事件互相觸發的死循環)") % [HAT_RUNS_WINDOW_MSEC / 1000, HAT_RUNS_LIMIT], hat)
		return
	_running[id] = true
	_keyword_order.clear()   # 每個事件重新洗一次 {kw:N} 的順序
	_user_keyword_order.clear()
	await _run_chain(_statement(hat, "DO"), _pet.action_generation)
	_running.erase(id)


## 依序執行一條積木鏈;回傳 "" 表示正常結束,"break"/"continue" 是迴圈流程控制,"abort" 是被即時互動中斷。
func _run_chain(first: Dictionary, token: int) -> String:
	var current := first
	while not current.is_empty():
		if not is_instance_valid(_pet) or _pet.action_generation != token:
			_settle_after_abort(current)
			return "abort"
		if _over_budget():
			await get_tree().process_frame
			continue
		var flow: String = await _exec(current, token)
		if flow != "":
			if flow == "abort":
				_settle_after_abort(current.get("next", {}).get("block", {}))
			return flow
		current = current.get("next", {}).get("block", {})
	return ""


## 長期狀態的回正:積木鏈被打斷(拖曳、點擊、interact、強制觸發…)時,剩下沒跑到的部分不再執行,
## 但其中「關閉/解除」類的積木(關閉 run、解除狀態鏡、解除所有負面、停止跟隨)仍然照做——
## 否則像「開啟 run → 等 10 秒 → 關閉 run」這種鏈在等待中被打斷,run 就會永遠開著。
## 「啟用」類與其他積木(對話、動作、數值增減…)不會補跑,避免打斷反而觸發獎勵或新狀態。
func _settle_after_abort(first: Dictionary) -> void:
	if not is_instance_valid(_pet):
		return
	var current := first
	while not current.is_empty():
		var fields: Dictionary = current.get("fields", {})
		match str(current.get("type", "")):
			"toggle_run":
				if str(fields.get("STATE", "")).to_lower() not in ["on", "true", "1"]:
					_set_run(false)
			"lens_disable":
				_pet.disable_lens(str(fields.get("LENS", "")))
			"lens_disable_all_negative":
				_pet.disable_negative_lenses()
			"lens_disable_all_positive":
				_pet.disable_positive_lenses()
			"toggle_follow_stop":
				_pet.stop_follow()
			"effect_trail":
				if str(fields.get("STATE", "")).to_lower() not in ["on", "true", "1"]:
					_pet.effects.set_trail_forced(false)
			"pet_mute":
				if str(fields.get("STATE", "on")).to_lower() in ["off", "false", "0"]:
					_exec_mute(current)
		current = current.get("next", {}).get("block", {})


func _exec(block: Dictionary, token: int) -> String:
	var type: String = block.get("type", "")
	var fields: Dictionary = block.get("fields", {})
	match type:
		"action_play":
			var variant := str(fields.get("VARIANT", ""))
			# 積木指定的動作一律是 SCRIPTED 優先級(打斷自主行為、佔用至少一個動畫循環);FORCE 勾選目前不改變行為,
			# 留給之後「隨機時跳過」差分過濾上線後,強制略過該過濾。
			_pet.play_action(StringName(str(fields.get("ACTION", "idle"))), int(variant) if variant.is_valid_int() else -1, true)
		"dialogue_line":
			return await _dialogue_line(block, token)
		"dialogue_wait":
			await _wait(_number(fields.get("SEC", 0.0)), true)
		"value_set":
			# 選用的值積木輸入 VAL_IN(例如「隨機數 a ~ b」)有接東西就用它算出來的值,否則用欄位 VAL。
			var set_amount := _number(_eval_input(block, "VAL_IN")) if _has_input(block, "VAL_IN") else _number(fields.get("VAL", 0.0))
			_set_value(str(fields.get("SCOPE", "")), str(fields.get("KEY", "")), set_amount)
		"value_change":
			var scope := str(fields.get("SCOPE", ""))
			var key := str(fields.get("KEY", ""))
			var delta := _number(_eval_input(block, "DELTA_IN")) if _has_input(block, "DELTA_IN") else _number(fields.get("DELTA", 0.0))
			_set_value(scope, key, _get_value(scope, key) + delta)
		"value_random":
			var low := _number(fields.get("MIN", 0.0))
			var high := _number(fields.get("MAX", 0.0))
			_set_value(str(fields.get("SCOPE", "")), str(fields.get("KEY", "")), randf_range(minf(low, high), maxf(low, high)))
		"flag_set":
			_pet.flags[str(fields.get("FLAG", ""))] = _truthy(fields.get("VAL", false))
		"toggle_run":
			_set_run(str(fields.get("STATE", "")).to_lower() in ["on", "true", "1"])
		"toggle_follow_start":
			_pet.start_follow(str(fields.get("TAG", "")))
		"toggle_follow_stop":
			_pet.stop_follow()
		"effect_trail":
			_pet.effects.set_trail_forced(str(fields.get("STATE", "")).to_lower() in ["on", "true", "1"])
		"phys_jump_small", "phys_jump_big":
			_pet.release_hold()
			_pet.perform_hops(int(_number(fields.get("N", 1.0))), type == "phys_jump_big")
			var waited := 0.0
			# 選用欄位 NOWAIT(性格編譯出來的事件用,網頁積木 G34 起也有勾選框):不等跳完就繼續,才能一邊跳一邊說話。
			while not _truthy(fields.get("NOWAIT", false)) and _pet.hops_left > 0 and waited < 20.0 and _pet.action_generation == token:
				await get_tree().process_frame
				waited += get_process_delta_time()
		"phys_shiver":
			var seconds := _number(fields.get("SEC", 1.0))
			_pet.shiver(seconds)
			if not _truthy(fields.get("NOWAIT", false)):
				await _wait(seconds, true)
		"phys_toward_mouse", "phys_away_from_mouse":
			var seek_seconds := _number(fields.get("SEC", 1.0))
			_pet.release_hold()
			_pet.seek_mouse(seek_seconds, type == "phys_away_from_mouse")
			await _wait(seek_seconds)
		"phys_temp_state":
			_temp_state(fields)
		"effect_play":
			var effect_name := str(fields.get("EFFECT", ""))
			if not _pet.effects.play(effect_name):
				_warn_once("不認得的特效「%s」(可用:%s)" % [effect_name, "、".join(PetEffects.CATALOG)])
			_state.effect_requested.emit(_pet, effect_name)
		"sound_play":
			_state.sound_requested.emit(_pet, str(fields.get("SOUND", "")))
		"controls_if":
			return await _exec_if(block, token)
		"controls_repeat_ext":
			return await _exec_repeat(block, token)
		"controls_whileUntil":
			return await _exec_while(block, token)
		"controls_flow_statements":
			return str(fields.get("FLOW", "BREAK")).to_lower()
		"pet_mute":
			_exec_mute(block)
		"pet_flip":
			_exec_flip(block)
		"dice_roll":
			return await _exec_dice_roll(block, token)
		"dice_contest":
			return await _exec_dice_contest(block, token)
		"rps_play":
			return await _exec_rps(block, token)
		"game_invite":
			return await _exec_game_invite(block, token)
		"say_random":
			return await _exec_say_random(block, token)
		"keyword_learn":
			_exec_keyword_learn(block)
		"dialogue_ask_text":
			return await _exec_ask_text(block, token)
		"random_pick":
			return await _exec_random_pick(block, token)
		"cond_prob_percent", "cond_pet_present", "cond_pet_state", "cond_pet_sleeping", "cond_move_mode", "cond_text_set", "cond_time_between", "cond_date_is", "cond_weekday_is", \
		"cond_lens_active", "cond_lens_active_over", "cond_holding_prop", "cond_value_compare", "flag_check", "cond_game_stat", "cond_target_is", \
		"cond_mood_compare", "cond_mood_zone", "cond_energy_compare", "cond_rest_state", "cond_lens_nature", "cond_loss_streak", "cond_ball_play", "cond_timer_running", \
			"cond_furniture_using", "cond_furniture_sharing", "cond_furniture_state":
			# (積木語法裡狀態鏡條件是回傳布林的值積木,這裡只是同時容許有 DO 語句輸入的寫法)
			# 條件積木當成「如果…那麼」的 C 型積木使用:成立才執行裡面的積木。
			if _eval_block(block):
				return await _run_chain(_statement(block, "DO"), token)
		"dialogue_option":
			pass # 選項積木由所屬的 dialogue_line 收集與執行,單獨出現在鏈上沒有作用。
		"lens_enable":
			_pet.enable_lens(str(fields.get("LENS", "")))
		"lens_disable":
			_pet.disable_lens(str(fields.get("LENS", "")))
		"lens_disable_all_negative":
			_pet.disable_negative_lenses()
		"lens_disable_all_positive":
			_pet.disable_positive_lenses()
		"lens_enable_by_nature":
			# 依性質啟用一個狀態鏡:優先用性格頁「心情高 / 低時的狀態鏡」指定的,沒指定就在勾了「可以被心情門檻叫出來」的狀態鏡裡隨機挑。
			if _pet.vitality != null and not _pet.vitality.enter_mood_lens(str(fields.get("NATURE", "positive")).to_lower() != "negative"):
				_warn_once("這隻桌寵沒有可以用的「%s」狀態鏡(要有該性質、且勾了「可以被心情門檻叫出來」),已略過" % ("負面" if str(fields.get("NATURE", "positive")).to_lower() == "negative" else "正面"))
		"mood_change":
			# 直接增減心情值(不受好感度、狀態鏡的倍率影響,精確加減),夾在 0~100。
			if _pet.vitality != null:
				_pet.vitality.mood = clampf(_pet.vitality.mood + _number(fields.get("DELTA", 0.0)), 0.0, 100.0)
		"energy_change":
			if _pet.vitality != null:
				_pet.vitality.energy = clampf(_pet.vitality.energy + _number(fields.get("DELTA", 0.0)), 0.0, PetVitality.MAX_ENERGY)
		"pet_rest":
			if _pet.vitality == null or not _pet.vitality.rest_now(str(fields.get("STAGE", "resting")).to_lower()):
				_warn_once("現在沒辦法休息(要開了疲勞機制、地面模式、站在地上、沒在忙),已略過")
		"pet_wake":
			if _pet.vitality != null:
				_pet.vitality.wake_quietly()
		"timer_start":
			_exec_timer_start(fields)
		"timer_stop":
			_pet.pet_timer.stop()
		"ball_play_start":
			if not _pet.ball_play.force_start():
				_warn_once("現在沒辦法玩球(場上沒有球、或桌寵不想玩 / 不能玩),已略過")
		"action_drop_held_prop":
			_pet.drop_held_prop()
		"action_furniture_join":
			_exec_furniture_join(fields)
		"action_furniture_leave":
			_pet.stop_using_furniture()
		"action_furniture_invite":
			_exec_furniture_invite(fields)
		"action_furniture_extend":
			_pet.extend_furniture_use(_number(fields.get("SECONDS", 0.0)))
		"action_furniture_toggle":
			_exec_furniture_toggle(fields)
		_:
			_warn_once("不支援的積木類型 %s,已略過" % type)
	return ""


func _exec_if(block: Dictionary, token: int) -> String:
	var index := 0
	while block.get("inputs", {}).has("IF%d" % index):
		if _truthy(_eval_input(block, "IF%d" % index)):
			return await _run_chain(_statement(block, "DO%d" % index), token)
		index += 1
	return await _run_chain(_statement(block, "ELSE"), token)


func _exec_repeat(block: Dictionary, token: int) -> String:
	var requested := int(_number(_eval_input(block, "TIMES")))
	var times := mini(requested, MAX_LOOP_ITERATIONS)
	if requested > MAX_LOOP_ITERATIONS:
		_log_once(tr("重複次數 %d 超過上限,已截成 %d 次") % [requested, MAX_LOOP_ITERATIONS])
	var busy := 0
	for i in times:
		var stamp := _progress_stamp
		var flow: String = await _run_chain(_statement(block, "DO"), token)
		if flow == "abort":
			return flow
		if flow == "break":
			break
		busy = busy + 1 if _progress_stamp == stamp else 0
		if busy >= busy_loop_limit:
			_runaway(tr("「重複」迴圈連續 %d 圈都沒有任何等待或對話(疑似死循環)") % busy, null)
			return "abort"
		await get_tree().process_frame
	return ""


func _exec_while(block: Dictionary, token: int) -> String:
	var until := str(block.get("fields", {}).get("MODE", "WHILE")).to_upper() == "UNTIL"
	var busy := 0
	for i in MAX_LOOP_ITERATIONS:
		if _truthy(_eval_input(block, "BOOL")) == until:
			return ""
		var stamp := _progress_stamp
		var flow: String = await _run_chain(_statement(block, "DO"), token)
		if flow == "abort":
			return flow
		if flow == "break":
			return ""
		busy = busy + 1 if _progress_stamp == stamp else 0
		if busy >= busy_loop_limit:
			_runaway(tr("「當…/直到…」迴圈連續 %d 圈都沒有任何等待或對話(疑似死循環)") % busy, null)
			return "abort"
		await get_tree().process_frame
	_log_once(tr("「當…/直到…」迴圈跑滿 %d 圈上限,已強制結束") % MAX_LOOP_ITERATIONS)
	return ""


## 一句對話:先播綁定動作,再請對話介面顯示並等它結束(點擊推進、自動跳下一句、選了選項)。
## 有選項時,依選擇套用該選項的數值/Flag 變更,接著執行該選項 GOTO 裡的積木鏈。
func _dialogue_line(block: Dictionary, token: int) -> String:
	var fields: Dictionary = block.get("fields", {})
	if _rate_exceeded("dialogue", DIALOGUES_LIMIT, DIALOGUES_WINDOW_MSEC):
		_runaway(tr("對話在 %d 秒內出現超過 %d 句(疑似洗版死循環)") % [DIALOGUES_WINDOW_MSEC / 1000, DIALOGUES_LIMIT], null)
		return "abort"
	# 雙人對話:SPEAKER 指定由哪個角色說這句(空白 = 執行這條鏈的桌寵自己),氣泡、說話聲、配色、綁定動作都用說話者自己的;
	# WAIT 預設 true = 等這句說完才執行下一顆;false = 一出現就繼續(下一顆若是對方的台詞,兩個氣泡就同時存在,此時不處理選項)。
	var speaker := _resolve_speaker(str(fields.get("SPEAKER", "")).strip_edges())
	var wait := _truthy(fields.get("WAIT", true))
	var bound := str(fields.get("BIND_ACTION", ""))
	if bound != "":
		speaker.play_action(StringName(bound), -1, true)
	var duet := speaker != _pet
	# 對話夥伴:這句是別隻說的就是它;是自己說的,則沿用最近(20 秒內)同一段對話裡的夥伴,
	# 讓對方在聽自己說話時也保持面向、站著不走。
	if duet:
		_duet_partner = speaker
		_duet_partner_msec = Time.get_ticks_msec()
	var partner: Node = _duet_partner if is_instance_valid(_duet_partner) and Time.get_ticks_msec() - _duet_partner_msec < 20000 else null
	if partner != null:
		_face_each_other(partner, CONVERSE_HOLD if wait else NO_WAIT_STAND)
	var options: Array[Dictionary] = []
	if wait:
		options = _collect_options(block)
	var labels: Array[String] = []
	for option in options:
		labels.append(_interpolate(_resolve_text(option, "LABEL"), false))
	var auto_seconds := _number(fields.get("AUTOSEC", 0.0))
	_pending_effects.clear()
	var text := _interpolate(_resolve_text(block))
	# 文字裡的 {fx:…} 特效標記:這一句要出現的當下播(整句只有特效標記、沒有字時,不冒氣泡,特效照播)。
	_flush_pending_effects()
	# 內容是空的(文字空白、或只有還沒有值的 {text:…})又沒有選項:不冒出空氣泡,直接接著往下做。
	if options.is_empty() and PetText.is_blank_bbcode(text):
		return ""
	var line := {
		"text": text,
		# HTML 端用 "__default__" 表示「沿用桌寵預設字體」,底線開頭的都視為空白(不指定)。
		"font": "" if str(fields.get("FONT", "")).begins_with("__") else str(fields.get("FONT", "")),
		"typewriter": _truthy(fields.get("TYPEWRITER", true)),
		"auto_seconds": auto_seconds,
		# 選用欄位 CLICK_WAIT(網頁積木已有勾選框,G33):true = 這句要等使用者點擊才前進(桌寵向使用者提出的重要對話)。
		"wait_click": _truthy(fields.get("CLICK_WAIT", false)),
		"bind_action": bound,
		"options": labels,
		# 選用欄位 BUBBLE(G39):speech(預設,一般對話框)/ thought(思考泡泡,配色與尾巴不同)。
		"bubble": "thought" if str(fields.get("BUBBLE", "speech")).strip_edges().to_lower() == "thought" else "speech",
	}
	if not wait:
		_send_line(speaker, line)
		return ""
	# 說話者(別隻)被使用者打斷 → 整段對話結束(連自己的鏈一起中止),不讓對話在對方被打斷後繼續唸下去。
	var speaker_cut := [false]
	var on_cut := func() -> void: speaker_cut[0] = true
	if duet:
		speaker.interrupted.connect(on_cut)
	var choice := await _show_line(speaker, line, auto_seconds)
	if duet and is_instance_valid(speaker) and speaker.interrupted.is_connected(on_cut):
		speaker.interrupted.disconnect(on_cut)
	if speaker_cut[0]:
		_pet.interrupt_scripts()
		return "abort"
	if _pet.action_generation != token:
		# 自己被打斷:對話對象也一起收尾(收氣泡、恢復走動),不留下站著不動的對方。
		if duet and is_instance_valid(speaker):
			speaker.interrupt_scripts()
		return "abort"
	if is_instance_valid(partner):
		_face_each_other(partner, CONVERSE_LINGER, true)
	if choice < 0 or choice >= options.size():
		return ""
	_apply_option(options[choice])
	SaveScheduler.request("choice")
	return await _run_chain(_statement(options[choice], "GOTO"), token)


## 送出對話請求並等它結束,回傳被點選的選項索引(沒有選擇為 -1)。
## 沒有任何對話介面訂閱時(例如尚未建立 UI 的測試環境)改用計時器,不會讓積木鏈卡住。
func _show_line(speaker: Node, line: Dictionary, auto_seconds: float) -> int:
	_progress_stamp += 1
	if _state.dialogue_line_requested.get_connections().is_empty():
		await _wait(auto_seconds if auto_seconds > 0.0 else DEFAULT_DIALOGUE_SECONDS, speaker == _pet)
		return -1
	var ticket := DialogueTicket.new()
	_state.dialogue_line_requested.emit(speaker, line, ticket)
	if ticket.closed:
		return -1
	return await ticket.finished


## 不等待的一句(WAIT=false):送出去就走,票據沒人等。
func _send_line(speaker: Node, line: Dictionary) -> void:
	if not _state.dialogue_line_requested.get_connections().is_empty():
		# 「不等說完」的句子(WAIT=false)一出現就要顯示、可以取代目前的氣泡;一般的句子則會在對話介面排隊等前一個氣泡收掉。
		line["interrupts"] = true
		_state.dialogue_line_requested.emit(speaker, line, DialogueTicket.new())


## 依辨識代號找說話者:空白或就是自己的代號 = 自己;有多隻同代號時取離自己最近的別隻;
## 找不到(對方不在場)就退回由自己說並警告一次,不讓整段對話中斷。
func _resolve_speaker(tag: String) -> Node:
	if tag == "" or tag == _pet.recognition_tag:
		return _pet
	var best: Node = null
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other != _pet and other.recognition_tag == tag:
			if best == null or other.global_position.distance_to(_pet.global_position) < best.global_position.distance_to(_pet.global_position):
				best = other
	if best == null:
		_warn_once("對話的說話者「%s」不在場,這句改由自己說" % tag)
		return _pet
	return best


## 雙人對話:雙方互相面向並站定(seconds 秒內不自己走動);replace 用來在一句結束後縮短成短暫停留。
func _face_each_other(speaker: Node, seconds: float, replace := false) -> void:
	speaker.converse(_pet.global_position.x, seconds, replace)
	_pet.converse(speaker.global_position.x, seconds, replace)


## 對話積木的 OPTIONS 陣列輸入:一串用 next 相連的 dialogue_option。
func _collect_options(block: Dictionary) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var current := _statement(block, "OPTIONS")
	while not current.is_empty():
		if current.get("type", "") == "dialogue_option":
			options.append(current)
		current = current.get("next", {}).get("block", {})
	return options


## 選項的效果:Local/Global 數值加上 DELTA;Flag 則 DELTA 為負設為假、其餘設為真。
func _apply_option(option: Dictionary) -> void:
	var fields: Dictionary = option.get("fields", {})
	var scope := str(fields.get("SCOPE", ""))
	var key := str(fields.get("KEY", ""))
	if key == "":
		return
	var delta := _number(fields.get("DELTA", 0.0))
	if scope.to_lower() == "flag":
		_pet.flags[key] = delta >= 0.0
	else:
		_set_value(scope, key, _get_value(scope, key) + delta)


## 暫時進入狀態(既有「啟用」語法的限時包裝):MODE 是 state_lens / run / 跟隨。秒數空白或 0 = 不限時,
## 等同直接啟用;有秒數則到時自動解除——除非期間已被其他積木提前解除或重新啟用(那就不動它)。
## 「跟隨」需要目標辨識代號,這個積木沒有該欄位,所以無法執行(警告一次、略過)。
func _temp_state(fields: Dictionary) -> void:
	var mode := str(fields.get("MODE", "")).to_lower()
	var seconds := _number(fields.get("SEC", 0.0))
	if mode == "run":
		_set_run(true)
		if seconds > 0.0:
			var stamp := _run_stamp
			get_tree().create_timer(seconds).timeout.connect(func() -> void:
				if is_instance_valid(_pet) and _run_stamp == stamp:
					_pet.run_enabled = false)
	elif mode == "state_lens":
		var lens_name := str(fields.get("LENS", ""))
		if _pet.enable_lens(lens_name) and seconds > 0.0:
			var lens_stamp: int = _pet.lens_stamp(lens_name)
			get_tree().create_timer(seconds).timeout.connect(func() -> void:
				if is_instance_valid(_pet) and _pet.lens_stamp(lens_name) == lens_stamp:
					_pet.disable_lens(lens_name))
	elif mode == "跟隨" or mode == "follow":
		# 跟隨目標取 TAG 欄位;限時就在時間到時停止跟隨(除非期間跟隨關係已被別的積木改掉)。
		var target := str(fields.get("TAG", "")).strip_edges()
		if target == "" or not _pet.start_follow(target):
			_warn_once("暫時跟隨:目標「%s」不存在、是自己或會形成循環,已略過" % target)
		elif seconds > 0.0:
			var follow_stamp: int = _pet.follow_stamp()
			get_tree().create_timer(seconds).timeout.connect(func() -> void:
				if is_instance_valid(_pet) and _pet.follow_stamp() == follow_stamp:
					_pet.stop_follow())
	else:
		_warn_once("暫時進入狀態「%s」不認得,已略過" % mode)


## 設定奔跑開關;每次設定都換新的時間戳,讓舊的限時解除計時器知道自己已被取代。
func _set_run(enabled: bool) -> void:
	_run_stamp += 1
	_pet.run_enabled = enabled


## 等待秒數。hold_pose 為 true 時,若桌寵正擺著積木指定的動作,就讓它維持這個姿勢直到等待結束。
## 這個名稱的動作在 window_msec 內是不是已經發生超過 limit 次(順便記下這一次)。
func _rate_exceeded(bucket: String, limit: int, window_msec: int) -> bool:
	var now := Time.get_ticks_msec()
	var stamps: Array = _rates.get(bucket, [])
	stamps.append(now)
	while not stamps.is_empty() and now - int(stamps[0]) > window_msec:
		stamps.pop_front()
	_rates[bucket] = stamps
	return stamps.size() > limit


## 一影格內的積木執行數超過 STEPS_PER_FRAME 就回 true(呼叫端要讓出這一影格)。
func _over_budget() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_frame_steps = 0
	_frame_steps += 1
	return _frame_steps > STEPS_PER_FRAME


## 只寫進錯誤紀錄一次的提示(不算失控,例如迴圈次數被截斷)。
func _log_once(message: String) -> void:
	if _warned.has("log:" + message):
		return
	_warned["log:" + message] = true
	PetErrorLog.write(_pet.get_label(), message)


## 失控處理。hat 是肇事的事件積木(找不到特定事件就傳 null,此時停用目前正在執行的所有事件)。
## 中止目前所有積木鏈、停用肇事事件、寫紀錄;短時間內累積太多次就請求強制退場。
func _runaway(reason: String, hat: Variant) -> void:
	if _ejected or not is_instance_valid(_pet):
		return
	var culprits: Array[String] = []
	if hat is Dictionary:
		culprits.append(str(hat.get("id", hat.hash())))
	else:
		for running_id: String in _running:
			culprits.append(running_id)
	var names: Array[String] = []
	for id in culprits:
		_disabled_hats[id] = true
		var owner_hat: Dictionary = hat if hat is Dictionary else {}
		if owner_hat.is_empty():
			for candidate: Dictionary in _top_blocks:
				if str(candidate.get("id", candidate.hash())) == id:
					owner_hat = candidate
					break
		var event_name := str(owner_hat.get("fields", {}).get("NAME", "")).strip_edges()
		names.append("%s(%s)" % [event_name if event_name != "" else "未命名", str(owner_hat.get("type", "?"))])
	var now := Time.get_ticks_msec()
	_strikes.append(now)
	while not _strikes.is_empty() and now - _strikes[0] > STRIKE_WINDOW_MSEC:
		_strikes.pop_front()
	var summary := tr("積木失控:%s。已中止這隻桌寵目前所有積木並停用事件 [%s](第 %d/%d 次警告)") % [reason, ", ".join(names), _strikes.size(), MAX_STRIKES]
	push_warning(summary)
	PetErrorLog.write(_pet.get_label(), summary)
	_rates.clear()
	_pet.interrupt_scripts()
	if _strikes.size() >= MAX_STRIKES:
		_ejected = true
		var farewell := tr("短時間內失控 %d 次,強制這隻桌寵退場(積木檔有問題,請修正後重新導入)") % _strikes.size()
		PetErrorLog.write(_pet.get_label(), farewell)
		_state.pet_ejected.emit.call_deferred(_pet, farewell)


func _wait(seconds: float, hold_pose := false) -> void:
	if seconds <= 0.0:
		return
	_progress_stamp += 1
	if hold_pose:
		_pet.extend_hold(seconds)
	# 可被打斷的等待:計時到、或桌寵被即時互動/強制觸發打斷(interrupted),兩者先到的先醒來。
	# 這樣「開啟 run → 等 10 秒 → 關閉 run」在等待中被打斷時,回正(見 _settle_after_abort)是立刻發生,不用等滿 10 秒。
	var gate := WaitGate.new()
	get_tree().create_timer(seconds).timeout.connect(gate.fire)
	_pet.interrupted.connect(gate.fire)
	await gate.fired
	if is_instance_valid(_pet) and _pet.interrupted.is_connected(gate.fire):
		_pet.interrupted.disconnect(gate.fire)


## 等待用的小閘門:多個來源(計時器、打斷訊號)任一個先呼叫 fire() 就放行,只會放行一次。
class WaitGate extends RefCounted:
	signal fired
	var done := false

	func fire() -> void:
		if not done:
			done = true
			fired.emit()


func _statement(block: Dictionary, input_name: String) -> Dictionary:
	return block.get("inputs", {}).get(input_name, {}).get("block", {})


func _eval_input(block: Dictionary, input_name: String) -> Variant:
	var entry: Dictionary = block.get("inputs", {}).get(input_name, {})
	var inner: Dictionary = entry.get("block", entry.get("shadow", {}))
	return _eval_block(inner) if not inner.is_empty() else null


## 積木有沒有接東西在這個值輸入上。
func _has_input(block: Dictionary, input_name: String) -> bool:
	var entry: Dictionary = block.get("inputs", {}).get(input_name, {})
	return not entry.get("block", entry.get("shadow", {})).is_empty()


## 求值型積木:數字、文字、布林、比較、邏輯運算,以及各種條件積木。
func _eval_block(block: Dictionary) -> Variant:
	var fields: Dictionary = block.get("fields", {})
	match block.get("type", ""):
		"math_number":
			return _number(fields.get("NUM", 0.0))
		"math_random_between":
			# 純隨機區間值:FROM ~ TO 之間隨機一個數(含兩端;INTEGER 預設勾選 = 整數,取消勾選 = 小數)。可以接在數值比較、設定/增減數值的值輸入上。
			var random_low := _number(fields.get("FROM", 0.0))
			var random_high := _number(fields.get("TO", 0.0))
			if str(fields.get("INTEGER", "TRUE")).to_upper() == "FALSE":
				return randf_range(minf(random_low, random_high), maxf(random_low, random_high))
			return float(randi_range(int(roundf(minf(random_low, random_high))), int(roundf(maxf(random_low, random_high)))))
		"cond_target_is":
			return _target_is(fields)
		"cond_furniture_using":
			return _any_or_all_pets(fields, func(candidate: Node) -> bool: return candidate.is_using_furniture())
		"cond_furniture_sharing":
			return _furniture_sharing(fields)
		"cond_furniture_state":
			return _furniture_state_matches(fields)
		"text":
			return str(fields.get("TEXT", ""))
		"logic_boolean":
			return str(fields.get("BOOL", "TRUE")).to_upper() == "TRUE"
		"logic_compare":
			return _compare(str(fields.get("OP", "EQ")), _eval_input(block, "A"), _eval_input(block, "B"))
		"logic_operation":
			var left := _truthy(_eval_input(block, "A"))
			var right := _truthy(_eval_input(block, "B"))
			return (left and right) if str(fields.get("OP", "AND")).to_upper() == "AND" else (left or right)
		"cond_prob_percent":
			return randf() * 100.0 < _number(fields.get("PCT", 0.0))
		"cond_pet_present":
			return _pets_present(fields)
		"cond_pet_state":
			return _eval_pet_state(fields)
		"cond_pet_sleeping":
			# 對方睡著了嗎(TAGS / INCLUDE_SELF / MATCH 和 cond_pet_state 一樣);「睡著」= 目前被要求的動作是 sleep,跟邀請對戰的必拒絕判斷同一個標準。
			return _any_or_all_pets(fields, func(candidate: Node) -> bool: return candidate.is_sleeping())
		"cond_holding_prop":
			# 這隻桌寵目前持有的道具是不是 PROP(空白或 any = 任何道具;可持有的道具被拾取後才會持有)。
			var wanted_prop := str(fields.get("PROP", "")).strip_edges()
			return str(_pet.held_prop) != "" if (wanted_prop == "" or wanted_prop.to_lower() == "any") else str(_pet.held_prop) == wanted_prop
		"cond_move_mode":
			# 這隻桌寵目前的移動模式是不是 MODE(ground 地面 / flying 飛行 / floating 漂浮 / fixed 固定 / stationary 靜止);IS = not 時反過來。
			var wanted_mode := Pet.parse_move_mode(str(fields.get("MODE", "ground")))
			var mode_negate := str(fields.get("IS", "is")).strip_edges().to_lower() in ["not", "isnt", "no", "不是"]
			return (wanted_mode >= 0 and int(_pet.move_mode) == wanted_mode) != mode_negate
		"cond_text_set":
			return str(_pet.text_values.get(PetText.sanitize_key(str(fields.get("KEY", ""))), "")) != ""
		"cond_dice_pass":
			# 上一次擲骰(KEY)的檢定有沒有過;WANT = pass(預設)/ fail;還沒擲過視為不成立。
			var dice_entry: Variant = _pet.dice_results.get(PetText.sanitize_key(str(fields.get("KEY", "roll"))))
			if not dice_entry is Dictionary:
				return false
			return bool(dice_entry.get("pass", false)) == (str(fields.get("WANT", "pass")).to_lower() != "fail")
		"cond_dice_compare":
			var compare_entry: Variant = _pet.dice_results.get(PetText.sanitize_key(str(fields.get("KEY", "roll"))))
			if not compare_entry is Dictionary:
				return false
			return _compare(str(fields.get("OP", "GTE")), float(compare_entry.get("total", 0)), _number(fields.get("NUM", 0.0)))
		"cond_game_stat":
			# 戰績比較:KIND = rps / dice / all,FIELD = win / lose / tie / total / rate(勝率百分比),和 NUM 依 OP 比較。
			var record: Dictionary = _pet.game_record(str(fields.get("KIND", "all")).to_lower())
			var stat_field := str(fields.get("FIELD", "win")).to_lower()
			if not record.has(stat_field):
				_warn_once("戰績條件的欄位「%s」不認得(應為 win / lose / tie / total / rate),視為不成立" % stat_field)
				return false
			return _compare(str(fields.get("OP", "GTE")), float(record[stat_field]), _number(fields.get("NUM", 0.0)))
		"cond_time_between":
			return _time_between(str(fields.get("FROM", "00:00")), str(fields.get("TO", "23:59")))
		"cond_date_is":
			var now := Time.get_date_dict_from_system()
			return str(fields.get("DATE", "")) == "%02d/%02d" % [now["month"], now["day"]]
		"cond_weekday_is":
			return _weekday_matches(fields.get("WD", ""))
		"cond_value_compare":
			return _compare(str(fields.get("OP", "EQ")), _get_value(str(fields.get("SCOPE", "")), str(fields.get("KEY", ""))), _number(fields.get("NUM", 0.0)))
		"flag_check":
			return _truthy(_pet.flags.get(str(fields.get("FLAG", "")), false))
		"cond_lens_active":
			return _pet.is_lens_active(str(fields.get("LENS", "")))
		"cond_lens_active_over":
			var lens_name := str(fields.get("LENS", ""))
			return _pet.is_lens_active(lens_name) and _pet.lens_active_seconds(lens_name) > _number(fields.get("SEC", 0.0))
		"cond_mood_compare":
			return _pet.vitality != null and _compare(str(fields.get("OP", "GTE")), _pet.vitality.mood, _number(fields.get("NUM", 50.0)))
		"cond_mood_zone":
			# 心情偏高(≥ 開心門檻)/ 平穩 / 偏低(≤ 生氣門檻)。
			if _pet.vitality == null:
				return false
			var zone := "high" if _pet.vitality.mood >= _pet.vitality.mood_happy_threshold else ("low" if _pet.vitality.mood <= _pet.vitality.mood_angry_threshold else "mid")
			return zone == str(fields.get("ZONE", "high")).to_lower()
		"cond_energy_compare":
			return _pet.vitality != null and _compare(str(fields.get("OP", "LTE")), _pet.vitality.energy, _number(fields.get("NUM", 30.0)))
		"cond_rest_state":
			# WHICH = any 任何一種休息 / standing 站著休息 / resting 坐下休息 / sleeping 睡覺。
			if _pet.vitality == null:
				return false
			var rest_mode: int = _pet.vitality.mode
			match str(fields.get("WHICH", "any")).to_lower():
				"standing":
					return rest_mode == PetVitality.Mode.STANDING
				"resting":
					return rest_mode == PetVitality.Mode.RESTING
				"sleeping":
					return rest_mode == PetVitality.Mode.SLEEPING
			return rest_mode != PetVitality.Mode.ACTIVE
		"cond_lens_nature":
			# 目前有沒有「正面 / 負面 / 持續」性質的狀態鏡生效。
			var wanted_nature: String = {"positive": "正面", "negative": "負面", "continuous": "持續"}.get(str(fields.get("NATURE", "negative")).to_lower(), "負面")
			for lens: PetStateLens in _pet.state_lenses:
				if lens.has_nature(wanted_nature) and _pet.is_lens_active(lens.lens_name):
					return true
			return false
		"cond_loss_streak":
			return _compare(str(fields.get("OP", "GTE")), float(_pet.game_losses_in_row), _number(fields.get("NUM", 2.0)))
		"cond_ball_play":
			# KIND = playing 我正在玩球 / ball_on_field 場上有球。
			if str(fields.get("KIND", "playing")).to_lower() == "ball_on_field":
				return not _pet.ball_play._wanted_balls().is_empty()
			return _pet.ball_play.active()
		"cond_timer_running":
			var timer_kind := str(fields.get("KIND", "any")).to_lower()
			if not _pet.pet_timer.active():
				return false
			return timer_kind == "any" or (timer_kind == "countdown" and _pet.pet_timer.kind == PetTimer.Kind.COUNTDOWN) or (timer_kind == "stopwatch" and _pet.pet_timer.kind == PetTimer.Kind.STOPWATCH)
		"cond_holding_prop":
			_warn_once("條件積木 %s 依賴尚未實作的系統,視為不成立" % block.get("type", ""))
			return false
	return null


## 「當對象是 XX」(cond_target_is):ROLE 指定要看哪個角色 —— opponent 對手、winner 贏家、loser 輸家、inviter 發起挑戰的人(自己是被邀請者時)、invitee 被自己邀請的人、
## follow_target 我正在跟隨的對象、follower 正在跟隨我的人、anyone 場內任何一隻(預設不含自己,INCLUDE_SELF 勾了才含)桌寵。
## TAGS(或 TAG)是允許的辨識代號(逗號分隔;空白 = 只要有這個角色就成立);IS = is(預設)/ not(不是)。
## 對手、贏家、輸家、發起者是小遊戲與邀請對戰結束/發生時記下來的(見 Pet.counterparts),使用者對戰時是 "user"。
## INCLUDE_SELF 只對 "anyone" 有意義——其他角色(對手/贏家/輸家/發起者/被邀請者/跟隨對象/跟隨者)結構上就是「別人」,
## 自己不可能是自己的對手或跟隨對象,加這個選項只會製造遞迴自我比對的假象,所以不提供(見 project_furniture_phase2_spec 的探勘筆記)。
func _target_is(fields: Dictionary) -> bool:
	var wanted := _character_tags(fields)
	var tags := _role_tags(str(fields.get("ROLE", "opponent")).strip_edges().to_lower(), _truthy(fields.get("INCLUDE_SELF", false)))
	var found := not tags.is_empty() if wanted.is_empty() else tags.any(func(tag: String) -> bool: return wanted.has(tag))
	var negate := str(fields.get("IS", "is")).strip_edges().to_lower() in ["not", "isnt", "no", "不是"]
	return found != negate


func _role_tags(role: String, include_self: bool = false) -> Array[String]:
	var tags: Array[String] = []
	match role:
		"follow_target":
			if _pet.is_following():
				tags.append(str(_pet._follow_tag))
		"follower":
			for other: Node in get_tree().get_nodes_in_group("pets"):
				if other != _pet and other.is_following() and str(other._follow_tag) == str(_pet.recognition_tag):
					tags.append(str(other.recognition_tag))
		"anyone":
			for other: Node in get_tree().get_nodes_in_group("pets"):
				if (other != _pet or include_self) and not other.is_queued_for_deletion():
					tags.append(str(other.recognition_tag))
		_:
			var entry: Dictionary = _pet.counterpart(role)
			if not entry.is_empty():
				tags.append(str(entry["tag"]))
	return tags


## 「當與(角色)共用家具時…」:自己要正在使用家具(is_using_furniture()),而且 TAGS/MATCH 指定的對象裡
## 至少一個(any)/全部(all)正跟自己用「同一件」家具(furniture_target() 相同的 FurnitureItem)。自己沒在用家具一律不成立。
func _furniture_sharing(fields: Dictionary) -> bool:
	var mine: FurnitureItem = _pet.furniture_target()
	if mine == null:
		return false
	return _any_or_all_pets(fields, func(candidate: Node) -> bool: return candidate.furniture_target() == mine)


## 「(家具)的觸發狀態為(開/關)」:SELECT 選要看哪件/哪些家具(見 _furniture_candidates),STATE = on(條件成立/conditional)
## 或 off(normal);找不到符合的家具一律不成立(跟 _any_or_all_pets 一樣的邏輯:沒有對象就不成立)。
func _furniture_state_matches(fields: Dictionary) -> bool:
	var candidates := _furniture_candidates(fields)
	if candidates.is_empty():
		return false
	var wants_on := str(fields.get("STATE", "on")).strip_edges().to_lower() != "off"
	if str(fields.get("MATCH", "any")).to_lower() == "all":
		return candidates.all(func(item: FurnitureItem) -> bool: return item.active() == wants_on)
	return candidates.any(func(item: FurnitureItem) -> bool: return item.active() == wants_on)


## 家具選擇器(cond_furniture_state、之後的家具相關積木共用):
##   SELECT = self_furniture(自己正在用的家具)/ other_furniture(TAGS 指定對象正在用的家具,空白 = 場內所有別人)/
##            nearest(離自己最近的一件,不管有沒有人在用)/ tag 或 any(全部家具,預設)。
##   TAG:不管 SELECT 選什麼,都再篩一次「家具要有這個標籤」(空白 = 不篩;讓 SELECT 和 TAG 能「是…且是…」疊加)。
func _furniture_candidates(fields: Dictionary) -> Array[FurnitureItem]:
	var select := str(fields.get("SELECT", "any")).strip_edges().to_lower()
	var pool: Array[FurnitureItem] = []
	match select:
		"self_furniture":
			var mine: FurnitureItem = _pet.furniture_target()
			if mine != null:
				pool.append(mine)
		"other_furniture":
			var wanted := _character_tags(fields)
			for other: Node in get_tree().get_nodes_in_group("pets"):
				if other == _pet:
					continue
				if not wanted.is_empty() and not wanted.has(other.recognition_tag):
					continue
				var theirs: FurnitureItem = other.furniture_target()
				if theirs != null and not pool.has(theirs):
					pool.append(theirs)
		"nearest":
			var manager := _furniture_manager()
			var best: FurnitureItem = null
			var best_distance := INF
			if manager != null:
				for item: FurnitureItem in manager.items:
					if not is_instance_valid(item):
						continue
					var distance: float = _pet.global_position.distance_to(item.global_position)
					if distance < best_distance:
						best_distance = distance
						best = item
			if best != null:
				pool.append(best)
		_:
			var manager := _furniture_manager()
			if manager != null:
				for item: FurnitureItem in manager.items:
					if is_instance_valid(item):
						pool.append(item)
	var tag := str(fields.get("TAG", "")).strip_edges()
	if tag != "":
		pool = pool.filter(func(item: FurnitureItem) -> bool: return item.def != null and item.def.tags.has(tag))
	return pool


func _furniture_manager() -> FurnitureManager:
	var nodes := get_tree().get_nodes_in_group("furniture_manager")
	return nodes[0] as FurnitureManager if not nodes.is_empty() else null


## 「當場內有人的狀態是…」(cond_pet_state / event_when_pet_state 共用):
## TAGS 指定要看哪些角色(空白 = 場內所有「其他」桌寵)、INCLUDE_SELF 是否連自己一起看、MATCH any(任一符合,預設)/ all(全部符合,且至少有一隻);
## KIND = action(桌寵目前被要求播放的動作,例如 sleep、dance)/ lens(該狀態鏡生效中,VALUE 空白 = 任何鏡片)/ talking(正在說話)。
## 不看別人的 Flag/數值(避免角色之間資料耦合)。
func _eval_pet_state(fields: Dictionary) -> bool:
	var kind := str(fields.get("KIND", "action")).to_lower()
	var value := str(fields.get("VALUE", "")).strip_edges()
	return _any_or_all_pets(fields, _pet_matches_state.bind(kind, value))


## 依 TAGS / INCLUDE_SELF 收集要看的桌寵,再依 MATCH(any / all)套用 matches;沒有任何符合對象的桌寵一律不成立。
func _any_or_all_pets(fields: Dictionary, matches: Callable) -> bool:
	var wanted := _character_tags(fields)
	var include_self := _truthy(fields.get("INCLUDE_SELF", false))
	var candidates: Array = []
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other == _pet and not include_self:
			continue
		if wanted.is_empty() or wanted.has(other.recognition_tag):
			candidates.append(other)
	if candidates.is_empty():
		return false
	if str(fields.get("MATCH", "any")).to_lower() == "all":
		return candidates.all(matches)
	return candidates.any(matches)


func _pet_matches_state(candidate: Node, kind: String, value: String) -> bool:
	if kind == "lens":
		return candidate.current_lens_name() != "" if value == "" else candidate.is_lens_active(value)
	if kind == "talking":
		return candidate.is_talking()
	if kind == "present":
		return true   # 交互行為頁籤「遇見某個角色」:對象在場上就成立(邊緣觸發 = 剛出現的那一刻)
	if kind == "move_mode":
		var wanted_mode := Pet.parse_move_mode(value)
		return wanted_mode >= 0 and int(candidate.move_mode) == wanted_mode
	return str(candidate.current_activity()) == value


## 每 0.5 秒:檢查每個 event_when_pet_state 的條件,由不成立變成立(EDGE=start,預設)或由成立變不成立(EDGE=end)時觸發一次;
## 也檢查事件觸發的自主靜音,條件消失就(在設定允許時)自動解除。
func _poll_pet_states() -> void:
	if not is_instance_valid(_pet):
		return
	for hat in _state_hats:
		var fields: Dictionary = hat.get("fields", {})
		var id := str(hat.get("id", hat.hash()))
		var now := _eval_pet_state(fields)
		var last: bool = _state_last.get(id, false)
		_state_last[id] = now
		var edge := str(fields.get("EDGE", "start")).to_lower()
		if (edge == "end" and last and not now) or (edge != "end" and now and not last):
			_run_hat(hat)
	for release in _mute_releases.duplicate():
		if not _eval_pet_state(release["fields"]):
			_mute_releases.erase(release)
			if _pet.auto_unmute_enabled:
				_pet.set_muted(false)


## 小道具事件:kind = collected(拾取/吃掉)/ rubbed(被摩擦)/ candidate(成為候選互動對象);PROP 欄位是道具名稱(空白或 any = 任何道具)。
## 符合的事件全部執行,回傳有沒有事件接手(沒有的話呼叫端用道具的預設交互反應)。
func run_prop_hats(kind: String, prop_name: String) -> bool:
	var hat_type := "event_prop_" + kind
	var handled := false
	for hat in _prop_hats.duplicate():
		if str(hat.get("type", "")) != hat_type:
			continue
		var wanted := str(hat.get("fields", {}).get("PROP", "")).strip_edges()
		if wanted != "" and wanted.to_lower() != "any" and wanted != prop_name:
			continue
		handled = true
		_run_hat(hat)
	return handled


## 有桌寵播放了特效:每個 event_when_effect 依 TAGS(要看哪些角色,空白 = 場內所有其他桌寵)、INCLUDE_SELF(連自己也看)、EFFECT(特效名稱或代號,空白 = 任何特效)判斷,符合就觸發。
func _on_effect_played(who: Node, key: String) -> void:
	if not is_instance_valid(_pet):
		return
	for hat in _effect_hats.duplicate():
		var fields: Dictionary = hat.get("fields", {})
		var wanted_effect := str(fields.get("EFFECT", "")).strip_edges()
		if wanted_effect != "" and wanted_effect.to_lower() != "any" and PetEffects.resolve(wanted_effect) != key:
			continue
		if who == _pet:
			if not _truthy(fields.get("INCLUDE_SELF", false)):
				continue
		var wanted := _character_tags(fields)
		if not wanted.is_empty() and not wanted.has(who.recognition_tag):
			continue
		_run_hat(hat)


## 有桌寵開始/結束使用家具(見 Pet.use_furniture()/stop_using_furniture()):event_furniture_join(using=true 時)/
## event_furniture_leave(using=false 時)依 TAGS/INCLUDE_SELF(跟 event_when_effect 同一套,預設看「別人」)、
## TYPE(sit/lay/any,預設 any)、FURNITURE_TAG(空白 = 不篩,家具要有這個標籤才算)判斷,符合就觸發。
func _on_furniture_use_changed(who: Node, item: Node, anchor_type: String, using: bool) -> void:
	if not is_instance_valid(_pet):
		return
	var wanted_hat_type := "event_furniture_join" if using else "event_furniture_leave"
	for hat in _furniture_hats.duplicate():
		if str(hat.get("type", "")) != wanted_hat_type:
			continue
		var fields: Dictionary = hat.get("fields", {})
		var wanted_type := str(fields.get("TYPE", "any")).to_lower()
		if wanted_type != "" and wanted_type != "any" and wanted_type != anchor_type:
			continue
		if who == _pet:
			if not _truthy(fields.get("INCLUDE_SELF", false)):
				continue
		var wanted := _character_tags(fields)
		if not wanted.is_empty() and not wanted.has(who.recognition_tag):
			continue
		var wanted_furniture_tag := str(fields.get("FURNITURE_TAG", "")).strip_edges()
		if wanted_furniture_tag != "" and (item == null or not is_instance_valid(item) or not ("def" in item) or item.def == null or not (item.def.tags as Array).has(wanted_furniture_tag)):
			continue
		_run_hat(hat)


## 「加入使用(家具)」:TYPE = sit(坐,預設)/ lay(躺),SELECT/TAG 是家具選擇器(見 _furniture_candidates,
## 預設 any = 場上任何一件家具,通常會配 SELECT=nearest 或 TAG 篩選種類再用)。挑到的每一件依序試著用(claim_anchor
## 內部會自己跳過滿的),用成功(真的走過去/坐下)就停手;都不成的話(都滿座或都不是要的類型)什麼都不做——
## 滿座的思考泡泡由 Pet.use_furniture() 自己處理,這裡不用重複判斷。
func _exec_furniture_join(fields: Dictionary) -> void:
	var wanted_type := str(fields.get("TYPE", "sit")).strip_edges().to_lower()
	if wanted_type == "":
		wanted_type = "sit"
	for item in _furniture_candidates(fields):
		if _pet.use_furniture(item, wanted_type):
			return


## 「邀請(角色)加入使用家具」:自己要正在使用家具,才能邀請 TAGS 指定的對象(空白 = 場內所有其他桌寵)一起用「同一件」
## 家具的同一種類型(sit/lay)——用自己目前那個錨點的類型,對方會自己挑一個當下沒人用的錨點(不一定是自己旁邊那個)。
## 自己沒在用家具就什麼都不做。
func _exec_furniture_invite(fields: Dictionary) -> void:
	var mine: FurnitureItem = _pet.furniture_target()
	if mine == null:
		return
	var wanted_type := mine.anchor_type(mine.anchor_index_of(_pet))
	var wanted := _character_tags(fields)
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other == _pet:
			continue
		if not wanted.is_empty() and not wanted.has(other.recognition_tag):
			continue
		other.use_furniture(mine, wanted_type)


## 「觸發家具(開/關/與現況相反)」:SELECT/TAG 選家具(見 _furniture_candidates),MODE = on/off/toggle(與現況相反,預設)。
## 逐一嘗試觸發(FurnitureItem.try_toggle 自己會擋冷卻中的),避免好幾隻桌寵同一時間偵測到同一件家具結果一起瘋狂開關。
func _exec_furniture_toggle(fields: Dictionary) -> void:
	var mode := str(fields.get("MODE", "toggle")).strip_edges().to_lower()
	for item in _furniture_candidates(fields):
		item.try_toggle(mode)


## 執行 pet_flip(轉身演出):MODE = toggle(轉向另一邊,預設)/ right / left / toward(面向對象:TAG 指定的角色,
## TAG 空白就面向最近說話的對話夥伴,沒有夥伴就面向場內最近的其他桌寵)。找不到對象就不動。
## 面向以「素材朝右」為準(「翻轉整隻」設定會處理素材朝左的角色);地面桌寵之後開始走路時仍會依走向重新面向。
func _exec_flip(block: Dictionary) -> void:
	var fields: Dictionary = block.get("fields", {})
	match str(fields.get("MODE", "toggle")).to_lower():
		"right":
			_pet.turn(1)
		"left":
			_pet.turn(-1)
		"toward":
			var target := _flip_target(str(fields.get("TAG", "")).strip_edges())
			if target != null:
				_pet.turn_toward(target.global_position.x)
		_:
			_pet.turn(0)


func _flip_target(tag: String) -> Node2D:
	if tag != "":
		var wanted := _character_tags({"TAG": tag})
		var found: Node2D = null
		for other: Node2D in get_tree().get_nodes_in_group("pets"):
			if other != _pet and wanted.has(other.recognition_tag):
				if found == null or absf(other.global_position.x - _pet.global_position.x) < absf(found.global_position.x - _pet.global_position.x):
					found = other
		return found
	if is_instance_valid(_duet_partner) and Time.get_ticks_msec() - _duet_partner_msec < 20000:
		return _duet_partner
	var nearest: Node2D = null
	for other: Node2D in get_tree().get_nodes_in_group("pets"):
		if other != _pet and (nearest == null or absf(other.global_position.x - _pet.global_position.x) < absf(nearest.global_position.x - _pet.global_position.x)):
			nearest = other
	return nearest


## 執行 pet_mute:on = 只靜音這隻桌寵自己的說話聲與效果音(不動全域音量);off = 解除。SEC 是選用的最長秒數保險。
## 若 on 是在 event_when_pet_state(EDGE=start)的鏈裡執行的,就登記解除條件(見 _poll_pet_states)。
func _exec_mute(block: Dictionary) -> void:
	var fields: Dictionary = block.get("fields", {})
	if str(fields.get("STATE", "on")).to_lower() in ["off", "false", "0"]:
		_pet.set_muted(false)
		_mute_releases.clear()
		return
	_pet.set_muted(true)
	var hat: Dictionary = _hat_of_block.get(str(block.get("id", "")), {})
	if str(hat.get("type", "")) == "event_when_pet_state" and str(hat.get("fields", {}).get("EDGE", "start")).to_lower() != "end":
		_mute_releases.append({"fields": hat["fields"]})
	var seconds := _number(fields.get("SEC", 0.0))
	if seconds > 0.0:
		var stamp: int = _pet.mute_stamp()
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if is_instance_valid(_pet) and _pet.mute_stamp() == stamp:
				_pet.set_muted(false))


## 「桌寵在場」:TAGS(多個代號,逗號/頓號/空白分隔)+ MATCH(any 任一在場 = 預設 / all 全部在場);
## 沒有 TAGS 就讀單一 TAG(舊資料完全相容)。代號都是空的視為不成立。
func _pets_present(fields: Dictionary) -> bool:
	var wanted := _character_tags(fields)
	if wanted.is_empty():
		return false
	var present: Array = get_tree().get_nodes_in_group("pets").map(func(p: Node) -> String: return p.recognition_tag)
	if str(fields.get("MATCH", "any")).to_lower() == "all":
		return wanted.all(func(tag: String) -> bool: return present.has(tag))
	return wanted.any(func(tag: String) -> bool: return present.has(tag))


func _compare(op: String, a: Variant, b: Variant) -> bool:
	var x := _number(a)
	var y := _number(b)
	match op.to_upper():
		"EQ", "=", "==":
			return is_equal_approx(x, y)
		"NEQ", "!=":
			return not is_equal_approx(x, y)
		"LT", "<":
			return x < y
		"LTE", "<=":
			return x <= y
		"GT", ">":
			return x > y
		"GTE", ">=":
			return x >= y
	return false


func _time_between(from_text: String, to_text: String) -> bool:
	var now := Time.get_time_dict_from_system()
	var minutes: int = now["hour"] * 60 + now["minute"]
	var start := _minutes_of(from_text)
	var end := _minutes_of(to_text)
	return (minutes >= start and minutes <= end) if start <= end else (minutes >= start or minutes <= end)


func _minutes_of(text: String) -> int:
	var parts := text.split(":")
	return int(parts[0]) * 60 + (int(parts[1]) if parts.size() > 1 else 0)


## 星期的欄位格式待 HTML 端確認:接受 0–6(0 是星期日)或常見的中英文名稱。
func _weekday_matches(value: Variant) -> bool:
	var today: int = Time.get_date_dict_from_system()["weekday"]
	var text := str(value).strip_edges().to_lower()
	if text.is_valid_int():
		return int(text) == today
	var names := [["sun", "日", "sunday"], ["mon", "一", "monday"], ["tue", "二", "tuesday"], ["wed", "三", "wednesday"], ["thu", "四", "thursday"], ["fri", "五", "friday"], ["sat", "六", "saturday"]]
	for candidate: String in names[today]:
		if text == candidate or text.ends_with(candidate):
			return true
	return false


## 數值讀寫一律走 ValueGateway(依宣告自動判斷作用域、夾限、發 value_updated);SCOPE 欄位只是沒宣告時的提示。
func _get_value(scope: String, key: String) -> float:
	return ValueGateway.get_value(_pet, key, scope)


func _set_value(scope: String, key: String, value: float) -> void:
	ValueGateway.set_value(_pet, key, value, scope)


## 對話文字:依 block id 或 TEXT 欄位查 dialogueTranslations,語言優先取目前語系,缺少就退回
## 第一筆(原始語言),再不行才用欄位原文,絕不顯示空白。字面上的 \n 兩個字元轉成真正的換行。
func _resolve_text(block: Dictionary, field := "TEXT") -> String:
	var raw := str(block.get("fields", {}).get(field, ""))
	var block_id := str(block.get("id", ""))
	# HTML 端的翻譯表以自己的對話 id(dlg_…)當 key,實際的 Blockly 積木 id 記在條目裡的 __blockId;
	# 所以先查 __blockId 索引,再退回「key 就是積木 id」與「key 就是原文」。
	var entry: Variant = _translation_by_block.get(block_id, _translations.get(block_id, _translations.get(raw, _translation_by_text.get(raw, null))))
	# 提問/抽籤積木的 PROMPT 沒有自己的對話 id:HTML 端(H2)用「prompt_<積木id>」當翻譯表的 key(條目內也有 __blockId,通常上面已經對到)。
	if entry == null and field == "PROMPT" and block_id != "":
		entry = _translations.get("prompt_" + block_id, null)
	var text := raw
	if entry is Dictionary:
		var languages: Array = entry.keys().filter(func(k: Variant) -> bool: return not str(k).begins_with("__"))
		if not languages.is_empty():
			# 桌寵自己的「桌寵語系」(介面風格分頁,PetProfile 的 dialogue_locale)設了就以它為準,沒設(預設)才跟著介面語系走——
			# 給「不管介面切成什麼語言,這隻就是要說中文/日文…」的釘住需求用,也是首次啟動選語言彈窗用來保留既有桌寵原本語言的機制
			# (見 DesktopShell._apply_language_choice:選了非預設語言時,把當下已存在的桌寵逐一釘住成原本的語言,之後新放的才跟著新語言走)。
			var locale: String = (str(_pet.dialogue_locale) if str(_pet.dialogue_locale) != "" else TranslationServer.get_locale()).replace("_", "-")
			var language := locale.split("-")[0]
			if entry.has(locale):
				text = str(entry[locale])
			else:
				text = str(entry[languages[0]])
				for key: String in languages:
					if key.split("-")[0] == language:
						text = str(entry[key])
						break
	return text.replace("\\n", "\n")


## 文字裡的特效標記 {fx:名稱} / {fx:名稱|秒數}:插值時不顯示任何字,只記下來,對話出現的那一刻(見 _dialogue_line)才播放。名稱和「播放特效」積木一樣(中文或英文代號)。
var _pending_effects: Array[Dictionary] = []


## 把插值時記下的特效標記播出去;不認得的名稱警告一次、略過。
func _flush_pending_effects() -> void:
	for entry in _pending_effects:
		if not _pet.effects.play(str(entry["name"]), float(entry["seconds"])):
			_warn_once("對話裡的特效標記 {fx:%s} 不認得(可用:%s)" % [entry["name"], "、".join(PetEffects.CATALOG)])
	_pending_effects.clear()


## {kw:N} 用的洗牌順序:同一個事件(以及它的對話與選項)裡固定,所以 {kw:1}~{kw:4} 各不相同(關鍵詞不夠時輪流重複);下一個事件重新洗。桌寵有興趣的與使用者有興趣的各洗各的。
var _keyword_order: Array[String] = []
var _user_keyword_order: Array[String] = []


## 關鍵詞庫的第 index 個(1 起算,依這個事件的洗牌順序);庫是空的回 fallback。which = "pet"(桌寵有興趣的,預設)或 "user"(使用者有興趣的)。
func _shuffled_keyword(index: int, fallback: String, which := "pet") -> String:
	var keywords: PackedStringArray = _pet.user_keywords if which == "user" else _pet.keywords
	if keywords.is_empty():
		return fallback
	var order: Array[String] = _user_keyword_order if which == "user" else _keyword_order
	if order.size() != keywords.size():
		order.assign(Array(keywords))
		order.shuffle()
	return order[posmod(index - 1, order.size())]


## 把文字裡的 { 變數名稱 } 換成即時數值(先找局部、再找全域,找不到就是 0)。
func _interpolate(text: String, for_bbcode := true) -> String:
	var regex := RegEx.create_from_string("\\{\\s*([^{}]+?)\\s*\\}")
	# 依位置逐段組合,不對整段文字做取代:替換進來的內容(尤其是使用者輸入的文字)不會被再次當成 {名稱} 處理。
	var result := ""
	var cursor := 0
	for match_result in regex.search_all(text):
		result += text.substr(cursor, match_result.get_start() - cursor)
		result += _placeholder_text(match_result.get_string(1), for_bbcode)
		cursor = match_result.get_end()
	result += text.substr(cursor)
	return PetText.filter_bbcode(result) if for_bbcode else result


## 一個 {…} 標記換成什麼:
## - { 名稱 } = 小圖示(有綁定的話)+ 數值;{icon:名稱} = 只有小圖示;{num:名稱} = 只有數值;
## - {text:名稱} = 使用者輸入的文字(例如稱呼);{text:名稱|預設} 在還沒有輸入時用「預設」。
##   使用者輸入的文字在 BBCode 顯示時方括號會被跳脫,打 [b]、[img] 之類只會顯示成普通文字。
func _placeholder_text(inner: String, for_bbcode: bool) -> String:
	# 小遊戲的結果:{roll:KEY} 擲骰點數、{contest:mine|best|winner|opponent} 拚骰、{rps:mine|theirs|opponent|score|rounds} 猜拳(沒有就是空字串)。
	# {stats:rps:win} 戰績:種類 rps / dice / all,欄位 win / lose / tie / total / rate(勝率,帶 %)。
	# 單字池:{pick:甲|乙|丙} 每次隨機挑一個(夾在句子裡用,例如「他似乎在想關於 {pick:天氣|晚餐|明天} 的事情」);挑出來的字可以帶氣泡語法。
	if inner.begins_with("pick:"):
		var choices := split_pool(inner.substr(5))
		return str(choices.pick_random()) if not choices.is_empty() else ""
	# 特效標記:{fx:一群小愛心}、{fx:冒汗|4}(4 = 持續秒數,不寫用預設)。不顯示任何字。
	if inner.strip_edges().begins_with("fx:"):
		var fx_body := inner.strip_edges().substr(3)
		var fx_seconds := -1.0
		if fx_body.contains("|"):
			var fx_number := fx_body.get_slice("|", 1).strip_edges()
			fx_seconds = fx_number.to_float() if fx_number.is_valid_float() else -1.0
			fx_body = fx_body.get_slice("|", 0)
		_pending_effects.append({"name": fx_body.strip_edges(), "seconds": clampf(fx_seconds, -1.0, 60.0)})
		return ""
	# 關鍵詞庫(桌寵管理 → 性格 → 關鍵詞庫):{keyword} 隨機挑一個、{keyword|預設} 庫是空的時用「預設」;{kw:N}(N = 1~9)這個事件洗牌後的第 N 個,{kw:2|預設} 同理。
	var keyword_text := inner.strip_edges()
	# 關鍵詞庫分兩份:桌寵有興趣的(預設)與使用者有興趣的。{keyword:user} / {keyword:pet}、{kw:user:2} / {kw:pet:2}(不寫 = 桌寵的)。
	if keyword_text == "keyword" or keyword_text.begins_with("keyword|") or keyword_text.begins_with("keyword:") or keyword_text.begins_with("kw:"):
		var keyword_fallback := PetText.DEFAULT_KEYWORD
		var keyword_body := keyword_text
		if keyword_text.contains("|"):
			keyword_fallback = keyword_text.get_slice("|", 1).strip_edges()
			keyword_body = keyword_text.get_slice("|", 0)
		var keyword_parts := keyword_body.split(":")
		var keyword_owner := "pet"
		var keyword_number := 1
		for part_index in range(1, keyword_parts.size()):
			var part := keyword_parts[part_index].strip_edges().to_lower()
			if part == "user" or part == "pet":
				keyword_owner = part
			elif part.is_valid_int():
				keyword_number = int(part)
		var picked: String
		if keyword_parts[0].strip_edges() == "kw":
			picked = _shuffled_keyword(keyword_number, keyword_fallback, keyword_owner)
		else:
			var pool: PackedStringArray = _pet.user_keywords if keyword_owner == "user" else _pet.keywords
			picked = str(pool[randi() % pool.size()]) if not pool.is_empty() else keyword_fallback
		return PetText.escape_bbcode(picked) if for_bbcode else picked
	# 名字標記:{self} 自己的名字、{other} 最近互動的對象、{opponent} 對手、{winner} 贏家、{loser} 輸家、{inviter} 發起挑戰的人、{invitee} 被邀請的人;
	# {user} 使用者的稱呼(交互行為分頁設定的稱呼清單,見 Pet.pick_user_nickname;每次用時隨機挑一個。還是預設值
	# 「使用者」時,{user|預設} 可以自己指定要顯示什麼)。找不到對象時用「對方」。
	var trimmed := inner.strip_edges()
	if trimmed in ["self", "other", "opponent", "winner", "loser", "inviter", "invitee"] or trimmed == "user" or trimmed.begins_with("user|"):
		var person_name := ""
		if trimmed == "self":
			person_name = str(_pet.display_name)
		elif trimmed == "other":
			person_name = _pet.latest_counterpart_name()
			if person_name == "":
				person_name = "對方"
		elif trimmed.begins_with("user"):
			if _pet.nickname_is_default() and trimmed.begins_with("user|"):
				person_name = trimmed.substr(5)
			else:
				person_name = _pet.pick_user_nickname()
		else:
			person_name = str((_pet.counterpart(trimmed) as Dictionary).get("name", ""))
			if person_name == "":
				person_name = "對方"
		return PetText.escape_bbcode(person_name) if for_bbcode else person_name
	if inner.begins_with("stats:"):
		var stat_parts := inner.substr(6).strip_edges().split(":")
		return _pet.game_stat_text(stat_parts[0], stat_parts[1] if stat_parts.size() > 1 else "rate")
	if inner.begins_with("roll:") or inner.begins_with("contest:") or inner.begins_with("rps:"):
		var game_text := str(_pet.game_vars.get(inner.strip_edges(), ""))
		return PetText.escape_bbcode(game_text) if for_bbcode else game_text
	if inner.begins_with("text:"):
		var parts := inner.substr(5).split("|", true, 1)
		var stored := str(_pet.text_values.get(PetText.sanitize_key(parts[0].strip_edges()), ""))
		if stored == "" and parts.size() > 1:
			stored = PetText.sanitize(parts[1], PetText.HARD_MAX_LENGTH)
		return PetText.escape_bbcode(stored) if for_bbcode else stored
	var mode := "both"
	var key := inner
	if key.begins_with("icon:"):
		mode = "icon"
		key = key.substr(5).strip_edges()
	elif key.begins_with("num:"):
		mode = "num"
		key = key.substr(4).strip_edges()
	var value := ValueGateway.get_value(_pet, key)
	var def := ValueGateway.find_def(_pet, key)
	var number := def.format_number(value) if def != null else (str(int(value)) if is_equal_approx(value, roundf(value)) else str(value))
	# 小圖示以 [icon=名稱] 標記留給對話氣泡繪製(氣泡有桌寵與數值定義,才知道圖示貼圖在哪)。
	var icon := "[icon=%s]" % key if def != null and def.icon != null and for_bbcode else ""
	if mode == "icon":
		return icon
	return number if mode == "num" else icon + number


func _number(value: Variant) -> float:
	if value is float or value is int:
		return float(value)
	var text := str(value)
	return text.to_float() if text.is_valid_float() else 0.0


func _truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is float or value is int:
		return value != 0
	return str(value).to_lower() in ["true", "1", "on", "yes"]


func _warn_once(message: String) -> void:
	if not _warned.has(message):
		_warned[message] = true
		push_warning(message)
