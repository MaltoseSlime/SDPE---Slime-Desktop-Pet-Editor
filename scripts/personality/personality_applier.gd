class_name PersonalityApplier
extends RefCounted
## 把性格套用到桌寵:分成五個區塊(參數、數值定義、狀態鏡、對話池、反應事件),每個區塊可以各自選不同的性格(混搭)。
## 保護使用者自己的內容(設計見 docs/性格預設備忘.md):
##  - 事件(對話池、反應):性格的事件放在獨立的一層(LogicInterpreter.set_personality_layer),和使用者的積木檔並存、互不覆蓋;
##    「只用性格的」只是暫時停用使用者自己的同類事件,沒有刪掉,關掉就恢復。
##  - 參數:只覆蓋「使用者沒改過」的值(和預設值、或和上次套用的值一樣);改過的保留,除非明確勾選「連我改過的也覆蓋」。套用時記下原本的值,換性格或取消時還原。
##  - 數值定義、狀態鏡:性格加入的項目帶「來源」標記與內容雜湊;使用者自己建的(沒有來源)永遠不動,性格加入後被使用者改過的也視為使用者的。
## 桌寵狀態(數值目前值、Flag、戰績)完全不碰。所有套用都可以預覽(preview)。

const SECTIONS: Array[String] = ["params", "valueDefs", "lenses", "chat", "reactions", "topicLines"]
const SECTION_NAMES := {"params": "參數", "valueDefs": "數值定義", "lenses": "狀態鏡", "chat": "對話池", "reactions": "反應事件", "topicLines": "話題文本"}
const SOURCE_PREFIX := "personality:"
## 一隻角色最多帶幾份性格副本(五個區塊各選一個不同的性格 + 幾份改過的)。
const MAX_OWN := 16


## 桌寵目前的性格狀態(補齊缺的欄位)。{choices:{區塊→性格 id}, ignore_own:{chat, reactions}, applied:{參數名→{baseline, applied}}, own:{性格 id→{data, edited}}}
## own = **這隻角色自己帶著的性格檔副本**:套用性格時把那份性格的完整內容(性格檔格式)複製一份存在角色身上(跟著角色設定存檔、打包角色時一起走),
## 之後對話池與反應事件都讀這份副本,不再回頭讀共用的性格檔;在性格編輯器改「這隻角色的版本」只會改這份副本,不會影響別隻角色或共用的性格。edited = 使用者改過這份副本。
static func state_of(pet: Node) -> Dictionary:
	var state: Dictionary = pet.personality
	if not state.get("own") is Dictionary:
		state["own"] = {}
	if not state.get("choices") is Dictionary:
		state["choices"] = {}
	if not state.get("ignore_own") is Dictionary:
		state["ignore_own"] = {"chat": false, "reactions": false}
	if not state.get("applied") is Dictionary:
		state["applied"] = {}
	if not state.get("mood_lens") is Dictionary:
		state["mood_lens"] = {"high": [], "low": []}
	pet.personality = state
	return state


## 心情偏高 / 偏低時要用的狀態鏡(使用者在「桌寵設定 → 性格」指定,可以複選;空陣列 = 沒指定,由引擎在勾了
## 「可以被心情門檻叫出來」的正面 / 負面狀態鏡裡隨機挑)。舊資料相容:2026-09-27 之前存的是單一字串
## ("" = 沒指定),讀到字串就當成只有一筆(空字串當沒選)。
static func mood_lens_choices(pet: Node, high: bool) -> Array[String]:
	var raw: Variant = (state_of(pet)["mood_lens"] as Dictionary).get("high" if high else "low", [])
	var result: Array[String] = []
	if raw is String:
		if str(raw) != "":
			result.append(str(raw))
	elif raw is Array:
		for name: Variant in raw:
			if str(name) != "" and not result.has(str(name)):
				result.append(str(name))
	return result


static func set_mood_lens_choices(pet: Node, high: bool, names: Array[String]) -> void:
	var cleaned: Array[String] = []
	for name in names:
		if name != "" and not cleaned.has(name):
			cleaned.append(name)
	(state_of(pet)["mood_lens"] as Dictionary)["high" if high else "low"] = cleaned


static func to_data(pet: Node) -> Dictionary:
	return state_of(pet).duplicate(true)


## 目前某個區塊選的性格 id(沒選是空字串)。
static func choice_of(pet: Node, section: String) -> String:
	return str(state_of(pet)["choices"].get(section, ""))


# --- 預覽與套用 ---

## 預覽:如果照 wanted 套用會發生什麼,但不改任何東西。
## wanted:{區塊 → 性格 id}(空字串 = 這個區塊不套用性格;沒列出的區塊維持現狀)。options:{overwrite_params, ignore_own_chat, ignore_own_reactions, skip_names:{valueDefs:[…], lenses:[…]}}。
## 回傳 {params:[{key, label, current, new, action}], defs:{valueDefs:[{name, action}], lenses:[…]}, events:{chat:數量, reactions:數量}, missing:[找不到的性格 id]}。
## params 的 action:apply 套用 / same 已經是這個值 / keep 保留你改過的 / revert 還原成原本的值 / release 你改過所以不再管它。
## defs 的 action:add 新增 / replace 換成新性格的 / keep 保留你的 / remove 移除(原本是性格加的、你沒改過)/ same 一樣。
static func preview(pet: Node, wanted: Dictionary, options := {}) -> Dictionary:
	var result := {"params": [], "defs": {"valueDefs": [], "lenses": []}, "events": {"chat": 0, "reactions": 0}, "missing": []}
	var state := state_of(pet)
	var overwrite := bool(options.get("overwrite_params", false))
	for section: String in SECTIONS:
		if not wanted.has(section):
			continue
		var id := str(wanted[section])
		var personality := personality_of(pet, id)
		if id != "" and personality.is_empty():
			(result["missing"] as Array).append(id)
			continue
		match section:
			"params":
				result["params"] = _plan_params(pet, personality, overwrite)
			"valueDefs", "lenses":
				(result["defs"] as Dictionary)[section] = _plan_definitions(pet, section, personality, (options.get("skip_names", {}) as Dictionary).get(section, []))
			"chat":
				(result["events"] as Dictionary)["chat"] = PersonalityFile.chat_hats(personality).size() if not personality.is_empty() else 0
			"reactions":
				(result["events"] as Dictionary)["reactions"] = PersonalityFile.reaction_hats(personality).size() if not personality.is_empty() else 0
	return result


## 套用。回傳 {ok, lines:[給使用者看的文字報告], plan:preview 的結果}。
static func apply(pet: Node, wanted: Dictionary, options := {}) -> Dictionary:
	# 先把要用的性格複製一份到角色身上(之後都讀這份副本),再預覽與套用。
	for section: String in SECTIONS:
		if wanted.has(section) and str(wanted[section]) != "":
			ensure_own(pet, str(wanted[section]))
	var plan := preview(pet, wanted, options)
	var lines: Array[String] = []
	for missing_id: String in plan["missing"]:
		lines.append(TranslationServer.translate("找不到性格「%s」,已略過") % missing_id)
	var state := state_of(pet)
	var choices: Dictionary = state["choices"]
	for section: String in SECTIONS:
		if not wanted.has(section) or (plan["missing"] as Array).has(str(wanted[section])):
			continue
		var id := str(wanted[section])
		match section:
			"params":
				_apply_params(pet, plan["params"], lines)
			"valueDefs", "lenses":
				_apply_definitions(pet, section, plan["defs"][section], id, lines)
		if id == "":
			choices.erase(section)
		else:
			choices[section] = id
	if options.has("ignore_own_chat"):
		state["ignore_own"]["chat"] = bool(options["ignore_own_chat"])
	if options.has("ignore_own_reactions"):
		state["ignore_own"]["reactions"] = bool(options["ignore_own_reactions"])
	_prune_own(pet)
	rebuild_layer(pet)
	return {"ok": true, "lines": lines, "plan": plan}


## 全部取消:參數還原、性格加的定義移除(沒被改過的)、事件層清空;使用者自己的內容不動。
static func clear_all(pet: Node) -> Dictionary:
	var wanted := {}
	for section: String in SECTIONS:
		wanted[section] = ""
	return apply(pet, wanted, {"ignore_own_chat": false, "ignore_own_reactions": false})


## 這隻角色用的某個性格(驗證過的內容):優先用角色自己帶的副本,沒有(舊角色、還沒套用過)才讀共用的性格檔。找不到回空字典。
static func personality_of(pet: Node, id: String) -> Dictionary:
	if id == "":
		return {}
	var own: Variant = state_of(pet)["own"].get(id)
	# 沒被使用者改過的副本永遠跟著共用的性格檔走(內建性格更新了新的狀態鏡、參數、台詞,舊角色才拿得到);改過的才用自己的副本。
	if own is Dictionary and not bool((own as Dictionary).get("edited", false)):
		var fresh := PersonalityFile.find(id)
		if not fresh.is_empty():
			return fresh["personality"]
	if own is Dictionary and (own as Dictionary).get("data") is Dictionary:
		var checked := PersonalityFile.validate((own as Dictionary)["data"])
		if bool(checked["ok"]):
			var personality: Dictionary = checked["personality"]
			# 改過的副本整份凍結在改的當下那一刻(見上面的說明)——但「參數」的新欄位是例外:改的時候這個
			# 參數根本還不存在,不可能是使用者刻意保留的舊值。2026-10-01 使用者實機回報:舊桌寵一直沒拿到
			# 新加的「自動坐下(idle_sit_chance)」參數,只能手動按「重設此性格副本」;根因就在這裡——凍結的
			# 副本連這個鍵都不存在,後面 DefaultsUpdater/_plan_params 的「沒紀錄就跟類別預設值比對」那套
			# 保護邏輯完全輪不到它(整個 for key in new_params 迴圈就沒這個鍵)。這裡用共用檔「補」缺的參數鍵,
			# 不是整個蓋掉——副本裡已經有的參數(不管是不是使用者刻意留的)一律維持副本原值不動。
			var fresh_for_new_params := PersonalityFile.find(id)
			if not fresh_for_new_params.is_empty():
				var fresh_params: Dictionary = (fresh_for_new_params["personality"] as Dictionary).get("params", {})
				var own_params: Dictionary = personality.get("params", {})
				for key: String in fresh_params:
					if not own_params.has(key):
						own_params[key] = fresh_params[key]
				personality["params"] = own_params
			return personality
	var found := PersonalityFile.find(id)
	return found.get("personality", {})


## 這隻角色有沒有自己帶著這個性格的副本 / 副本是不是被使用者改過。
static func has_own(pet: Node, id: String) -> bool:
	return state_of(pet)["own"].get(id) is Dictionary


static func is_edited(pet: Node, id: String) -> bool:
	var own: Variant = state_of(pet)["own"].get(id)
	return own is Dictionary and bool((own as Dictionary).get("edited", false))


## 確保這隻角色帶著 id 這個性格的副本(沒有就從共用的性格檔複製一份)。找不到共用的性格回 false。
static func ensure_own(pet: Node, id: String) -> bool:
	if id == "":
		return false
	var own: Dictionary = state_of(pet)["own"]
	var found := PersonalityFile.find(id)
	if own.get(id) is Dictionary:
		if not bool((own[id] as Dictionary).get("edited", false)) and not found.is_empty():
			own[id] = {"data": PersonalityFile.to_file_data(found["personality"]), "edited": false}   # 沒改過的副本換成最新的共用版
		return true
	if found.is_empty():
		return false
	own[id] = {"data": PersonalityFile.to_file_data(found["personality"]), "edited": false}
	return true


## 把這隻角色的副本換成 data(性格檔格式,已通過驗證)並標成「改過」;事件層馬上重建。參數要再按「套用」才會寫到桌寵身上。
static func set_own(pet: Node, id: String, data: Dictionary) -> void:
	state_of(pet)["own"][id] = {"data": data.duplicate(true), "edited": true}
	rebuild_layer(pet)


## 丟掉這隻角色改過的副本,重新從共用的性格檔複製一份原版。原版找不到就直接移除副本。
static func reset_own(pet: Node, id: String) -> void:
	state_of(pet)["own"].erase(id)
	ensure_own(pet, id)
	rebuild_layer(pet)


## 清掉沒被任何區塊選用、而且沒被改過的副本(改過的不清,免得使用者的心血不見)。
static func _prune_own(pet: Node) -> void:
	var state := state_of(pet)
	var used: Array = (state["choices"] as Dictionary).values()
	for id: String in (state["own"] as Dictionary).keys():
		var entry: Variant = state["own"][id]
		if not used.has(id) and not (entry is Dictionary and bool((entry as Dictionary).get("edited", false))):
			(state["own"] as Dictionary).erase(id)


# --- 參數 ---

static func _plan_params(pet: Node, personality: Dictionary, overwrite: bool) -> Array:
	var plan: Array = []
	var applied: Dictionary = state_of(pet)["applied"]
	var new_params: Dictionary = personality.get("params", {})
	for key: String in new_params:
		var current: Variant = PersonalityParams.get_value(pet, key)
		var value: Variant = new_params[key]
		var record: Variant = applied.get(key)
		var protected := false
		var baseline: Variant = current
		if record is Dictionary:
			protected = not PersonalityParams.same(current, PersonalityParams.normalize(key, record.get("applied")))
			baseline = PersonalityParams.normalize(key, record.get("baseline"))
			if baseline == null:
				baseline = current
		else:
			protected = not PersonalityParams.same(current, PersonalityParams.default_of(key))
		var action := "apply"
		if PersonalityParams.same(current, value):
			action = "same"
		elif protected and not overwrite:
			action = "keep"
		plan.append({"key": key, "label": PersonalityParams.label_of(key), "current": current, "new": value, "action": action, "baseline": baseline})
	for key: String in applied:
		if new_params.has(key):
			continue
		var record: Variant = applied[key]
		var current: Variant = PersonalityParams.get_value(pet, key)
		var applied_value: Variant = PersonalityParams.normalize(key, (record as Dictionary).get("applied")) if record is Dictionary else null
		var baseline: Variant = PersonalityParams.normalize(key, (record as Dictionary).get("baseline")) if record is Dictionary else null
		if applied_value != null and baseline != null and PersonalityParams.same(current, applied_value):
			plan.append({"key": key, "label": PersonalityParams.label_of(key), "current": current, "new": baseline, "action": "revert", "baseline": baseline})
		else:
			plan.append({"key": key, "label": PersonalityParams.label_of(key), "current": current, "new": current, "action": "release", "baseline": current})
	return plan


static func _apply_params(pet: Node, plan: Array, lines: Array[String]) -> void:
	var applied: Dictionary = state_of(pet)["applied"]
	for step: Dictionary in plan:
		var key: String = step["key"]
		match str(step["action"]):
			"apply":
				PersonalityParams.set_value(pet, key, step["new"])
				applied[key] = {"baseline": PersonalityParams.to_json(step["baseline"]), "applied": PersonalityParams.to_json(step["new"])}
				lines.append(TranslationServer.translate("參數「%s」:%s → %s") % [step["label"], PersonalityParams.to_text(step["current"]), PersonalityParams.to_text(step["new"])])
			"same":
				pass
			"keep":
				applied.erase(key)
				lines.append(TranslationServer.translate("保留你改過的「%s」(%s)") % [step["label"], PersonalityParams.to_text(step["current"])])
			"revert":
				PersonalityParams.set_value(pet, key, step["new"])
				applied.erase(key)
				lines.append(TranslationServer.translate("參數「%s」還原成 %s") % [step["label"], PersonalityParams.to_text(step["new"])])
			"release":
				applied.erase(key)


# --- 數值定義與狀態鏡 ---

static func _existing(pet: Node, section: String) -> Array:
	return pet.value_defs if section == "valueDefs" else pet.state_lenses


static func _name_of(item: Variant, section: String) -> String:
	return (item as PetValueDef).key if section == "valueDefs" else (item as PetStateLens).lens_name


static func _dict_of(item: Variant, section: String) -> Dictionary:
	return PetProfile.value_to_dict(item) if section == "valueDefs" else PetProfile.lens_to_dict(item)


## 內容雜湊(不含來源標記):性格加入當下記下來,之後比對就知道使用者有沒有改過。
static func definition_hash(item: Variant, section: String) -> int:
	return JSON.stringify(PersonalityFile.clean_definition(_dict_of(item, section))).hash()


static func _is_from_personality(item: Variant) -> bool:
	return str(item.source).begins_with(SOURCE_PREFIX)


static func _unmodified(item: Variant, section: String) -> bool:
	return _is_from_personality(item) and int(item.source_hash) == definition_hash(item, section)


## skip_names:這隻角色「以前就有過、後來被使用者刪掉」的項目名稱,不再加回來(更新預設內容時用,見 DefaultsUpdater)。
static func _plan_definitions(pet: Node, section: String, personality: Dictionary, skip_names: Array = []) -> Array:
	var plan: Array = []
	var existing := _existing(pet, section)
	var wanted_names: Array[String] = []
	var source_id := str(personality.get("id", ""))
	for entry: Dictionary in personality.get(section, []):
		var item_name := str(entry.get("key", entry.get("name", "")))
		wanted_names.append(item_name)
		var match_item: Variant = null
		for item: Variant in existing:
			if _name_of(item, section) == item_name:
				match_item = item
				break
		if match_item == null:
			if not skip_names.has(item_name):
				plan.append({"name": item_name, "action": "add", "entry": entry})
		elif _unmodified(match_item, section):
			var same_content := JSON.stringify(PersonalityFile.clean_definition(_dict_of(match_item, section))) == JSON.stringify(entry)
			plan.append({"name": item_name, "action": "same" if same_content and str(match_item.source) == SOURCE_PREFIX + source_id else "replace", "entry": entry})
		else:
			plan.append({"name": item_name, "action": "keep", "entry": entry})
	for item: Variant in existing:
		if not wanted_names.has(_name_of(item, section)) and _unmodified(item, section):
			plan.append({"name": _name_of(item, section), "action": "remove", "entry": {}})
	return plan


static func _apply_definitions(pet: Node, section: String, plan: Array, id: String, lines: Array[String]) -> void:
	var existing := _existing(pet, section)
	var label: String = SECTION_NAMES[section]
	for step: Dictionary in plan:
		var item_name: String = step["name"]
		match str(step["action"]):
			"add", "replace":
				var fresh: Variant = PetProfile.value_from_dict(step["entry"]) if section == "valueDefs" else PetProfile.lens_from_dict(step["entry"])
				if fresh == null:
					continue
				fresh.source = SOURCE_PREFIX + id
				fresh.source_hash = definition_hash(fresh, section)
				var index := -1
				for i in existing.size():
					if _name_of(existing[i], section) == item_name:
						index = i
				if index >= 0:
					if section == "lenses" and pet.is_lens_active(item_name):
						pet.disable_lens(item_name)
					existing[index] = fresh
				else:
					existing.append(fresh)
				lines.append("%s「%s」:%s" % [label, item_name, TranslationServer.translate("新增") if index < 0 else TranslationServer.translate("換成新性格的")])
			"keep":
				lines.append(TranslationServer.translate("%s「%s」你已經有自己的,保留") % [label, item_name])
			"remove":
				for i in range(existing.size() - 1, -1, -1):
					if _name_of(existing[i], section) == item_name:
						if section == "lenses" and pet.is_lens_active(item_name):
							pet.disable_lens(item_name)
						existing.remove_at(i)
				lines.append(TranslationServer.translate("%s「%s」移除(原本是性格加的、你沒改過)") % [label, item_name])
	if section == "valueDefs":
		ValueGateway.init_defaults(pet)
	else:
		pet.reapply_lenses()


# --- 事件層 ---

## 依目前的選擇重建事件層:對話池選了誰就加誰的閒聊事件,反應事件選了誰就加誰的反應類事件。
static func rebuild_layer(pet: Node) -> void:
	if pet.logic == null:
		return
	var state := state_of(pet)
	var choices: Dictionary = state["choices"]
	var blocks: Array = []
	var chat_id := str(choices.get("chat", ""))
	var reaction_id := str(choices.get("reactions", ""))
	var chat_personality := personality_of(pet, chat_id)
	var reaction_personality := personality_of(pet, reaction_id)
	if not chat_personality.is_empty():
		blocks.append_array(PersonalityFile.chat_hats(chat_personality))
	if not reaction_personality.is_empty():
		blocks.append_array(PersonalityFile.reaction_hats(reaction_personality))
	var ignore: Dictionary = state["ignore_own"]
	pet.logic.set_personality_layer(blocks, bool(ignore.get("chat", false)) and not chat_personality.is_empty(), bool(ignore.get("reactions", false)) and not reaction_personality.is_empty())
	# 性格檔自帶的對話翻譯(目前只有預設性格的 chat 對話池有,見 dialogueTranslations):兩個區塊都可能各自帶著,合併進去。
	if chat_personality.get("dialogueTranslations") is Dictionary:
		pet.logic.merge_translations(chat_personality["dialogueTranslations"])
	if reaction_personality.get("dialogueTranslations") is Dictionary:
		pet.logic.merge_translations(reaction_personality["dialogueTranslations"])


# --- 存讀(桌寵設定檔的 "personality" 區塊)---

## 從桌寵設定還原性格狀態:目前記錄中、但設定裡沒有的參數先還原成原本的值,再把設定裡記錄的參數值設回去,最後重建事件層。
## data 來自檔案,逐項驗證,壞的略過。
static func restore(pet: Node, data: Variant) -> void:
	var current := state_of(pet)
	var incoming := _clean_state(data)
	for key: String in current["applied"]:
		if not (incoming["applied"] as Dictionary).has(key):
			var baseline: Variant = PersonalityParams.normalize(key, ((current["applied"] as Dictionary)[key] as Dictionary).get("baseline"))
			if baseline != null:
				PersonalityParams.set_value(pet, key, baseline)
	pet.personality = incoming
	for key: String in incoming["applied"]:
		PersonalityParams.set_value(pet, key, PersonalityParams.normalize(key, ((incoming["applied"] as Dictionary)[key] as Dictionary).get("applied")))
	# 舊角色(選了性格但還沒帶副本)在這裡補一份,之後就是這隻角色自己的了。
	for section: String in (incoming["choices"] as Dictionary):
		ensure_own(pet, str(incoming["choices"][section]))
	rebuild_layer(pet)


## 心情狀態鏡選擇清單存讀共用的驗證:相容舊資料(單一字串,""=沒指定)與現在的複選陣列格式,
## 一律清成陣列(見 PersonalityApplier.mood_lens_choices 也有同一套相容邏輯,這裡是存檔路徑用的)。
static func _clean_mood_lens_list(raw: Variant) -> Array:
	var result := []
	if raw is String:
		if str(raw) != "":
			result.append(str(raw).left(40))
	elif raw is Array:
		for name: Variant in raw:
			var cleaned := str(name).left(40)
			if cleaned != "" and not result.has(cleaned):
				result.append(cleaned)
	return result


static func _clean_state(data: Variant) -> Dictionary:
	var state := {"choices": {}, "ignore_own": {"chat": false, "reactions": false}, "applied": {}, "own": {}, "mood_lens": {"high": [], "low": []}}
	if not data is Dictionary:
		return state
	if data.get("mood_lens") is Dictionary:
		state["mood_lens"]["high"] = _clean_mood_lens_list(data["mood_lens"].get("high", []))
		state["mood_lens"]["low"] = _clean_mood_lens_list(data["mood_lens"].get("low", []))
	if data.get("own") is Dictionary:
		for own_id: Variant in (data["own"] as Dictionary):
			var entry: Variant = data["own"][own_id]
			if state["own"].size() >= MAX_OWN or not entry is Dictionary or not (entry as Dictionary).get("data") is Dictionary:
				continue
			var checked := PersonalityFile.validate((entry as Dictionary)["data"])
			if bool(checked["ok"]) and str(checked["personality"]["id"]) == str(own_id):
				state["own"][str(own_id)] = {"data": PersonalityFile.to_file_data(checked["personality"]), "edited": bool((entry as Dictionary).get("edited", false))}
	if data.get("choices") is Dictionary:
		for section: Variant in data["choices"]:
			if SECTIONS.has(str(section)) and data["choices"][section] is String and str(data["choices"][section]) != "":
				state["choices"][str(section)] = str(data["choices"][section]).left(40)
	if data.get("ignore_own") is Dictionary:
		state["ignore_own"]["chat"] = bool(data["ignore_own"].get("chat", false))
		state["ignore_own"]["reactions"] = bool(data["ignore_own"].get("reactions", false))
	if data.get("applied") is Dictionary:
		for key: Variant in data["applied"]:
			var record: Variant = data["applied"][key]
			if not record is Dictionary:
				continue
			var baseline: Variant = PersonalityParams.normalize(str(key), record.get("baseline"))
			var applied_value: Variant = PersonalityParams.normalize(str(key), record.get("applied"))
			if baseline != null and applied_value != null:
				state["applied"][str(key)] = {"baseline": PersonalityParams.to_json(baseline), "applied": PersonalityParams.to_json(applied_value)}
	return state
