class_name InteractionTab
extends VBoxContainer
## 交互行為分頁(桌寵管理):不用寫積木就能調的三件事,資料見 InteractionRules(存在角色設定檔的 "interaction"):
## ① 各種事件下用哪個動作(下拉選單換動作,沒設 = 原本的);② 對場上另一個角色(角色庫內的,不含自己)的反應,只能新增純對話;
## ③ 對某個道具(道具管理裡有的)的反應:對話 + 動作(只做一次,或持續到道具用完 / 離開判定,像摸摸移開才恢復)。
## 詳細編輯(條件、選項、連續動作…)要到網頁端積木編輯器調整,每張卡片的 ⓘ 都有這個提醒。改動即時生效(和其他分頁一樣要按「儲存」才寫進檔案)。

signal changed
signal message(text: String)

const CARD_WIDTH := 440.0
const WEB_HINT := "這裡只提供最常用、最簡單的設定;詳細編輯(條件、選項、連續動作、更多種反應…)要到網頁端積木編輯器調整。"
const DEFAULT_LABEL := "(預設)"

var _pet: Node
var _flow: HFlowContainer
var _loading := false
var _action_options: Dictionary = {}
var _char_option: OptionButton
var _char_line: LineEdit
var _char_list: VBoxContainer
var _prop_option: OptionButton
var _prop_kind_option: OptionButton
var _prop_line: LineEdit
var _prop_action_option: OptionButton
var _prop_persist_option: OptionButton
var _prop_list: VBoxContainer
var _pref_list: VBoxContainer
var _nickname_line: LineEdit
var _ignore_props_check: CheckBox
var _ignore_furniture_check: CheckBox
var _reaction_list: VBoxContainer
var _reaction_boxes: Dictionary = {}   # reactions 陣列索引 → TextEdit
var _characters: Array[Dictionary] = []
var _props: Array[PropDef] = []


func _ready() -> void:
	name = "交互行為"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 10)
	_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_flow)
	_build_action_card()
	_build_nickname_card()
	_build_toggle_card()
	_build_character_card()
	_build_reaction_dialogue_card()
	_build_prop_card()
	_build_pref_card()


## 卡片標題列可以點開/收合(預設全部展開):標題本身是一顆扁平按鈕(含展開/收合箭頭),旁邊的 ⓘ 是獨立節點不受影響。
## 收合狀態只存在畫面上(VBoxContainer.visible),不寫進設定檔,每次重開管理視窗都是預設展開。
func _new_card(title_text: String, tip: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = AppSettings.ink(0.05)
	style.border_color = AppSettings.ink(0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10.0)
	card.add_theme_stylebox_override("panel", style)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	card.add_child(outer)

	var header := HBoxContainer.new()
	var toggle := Button.new()
	toggle.flat = true
	# 卡片標題跟圈圈i的說明文字都要用「查表翻譯後」的字串再組字面,不能先用 + 串起來再整串當查表 key
	# (串起來的字面幾乎不可能剛好等於 translations/ui_strings.csv 裡的任何一筆原文,一定翻不到——
	# 2026-09-30 使用者回報「交互行為」的收合卡片標題跟圈圈i沒翻譯到,根因就是這個)。
	var translated_title := TranslationServer.translate(title_text)
	toggle.text = "▾ " + translated_title
	toggle.clip_text = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(toggle)
	var info := InfoIcon.new()
	info.set_tip_parts([tip, WEB_HINT])
	header.add_child(info)
	outer.add_child(header)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	outer.add_child(box)
	toggle.pressed.connect(func() -> void:
		box.visible = not box.visible
		toggle.text = ("▾ " if box.visible else "▸ ") + translated_title)

	_flow.add_child(card)
	return box


func _build_action_card() -> void:
	var box := _new_card("事件對應的動作", "桌寵在各種事件下播放哪個動作:每一列選一個素材包裡有的動作,「(預設)」就是原本的動作。素材沒有選的那個動作時會退回原本的。")
	for slot: Array in InteractionRules.ACTION_SLOTS:
		var option := OptionButton.new()
		option.item_selected.connect(func(_i: int) -> void: _commit_actions())
		_action_options[str(slot[0])] = option
		box.add_child(ManagerUi.labeled(str(slot[1]), option))


func _build_nickname_card() -> void:
	var box := _new_card("對使用者的稱呼", "對話裡的 {user} 會用這裡填的稱呼(見語法字典)。可以填好幾個,用逗號分隔,桌寵每次要用時隨機挑一個。預設只有「使用者」這一筆;還是這個預設值的時候,桌寵會有比較高的機率主動開口問你要怎麼稱呼(問到答案就自動填進來)。")
	_nickname_line = ManagerUi.line_edit("使用者")
	# 這裡只有單一輸入框、沒有 labeled() 那樣的固定寬度標籤可以擠掉多餘空間,不特別限制寬度的話會被撐成卡片全寬
	# (跟其他卡片裡「標籤 + 輸入框」的窄版排版比起來明顯過長)。
	_nickname_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_nickname_line.custom_minimum_size.x = CARD_WIDTH - 140.0
	_nickname_line.text_submitted.connect(func(_t: String) -> void: _commit_nickname())
	_nickname_line.focus_exited.connect(_commit_nickname)
	box.add_child(_nickname_line)


func _commit_nickname() -> void:
	if _loading or _pet == null:
		return
	var cleaned: Array[String] = Pet.clean_user_nicknames(_nickname_line.text)
	_pet.user_nicknames = cleaned
	_nickname_line.text = ", ".join(PackedStringArray(_pet.user_nicknames))
	changed.emit()


## 整隻桌寵層級的總開關(跟下面「對某個道具的反應/喜好」「家具」那種一項一項設定不一樣,這裡是全部生效)。
func _build_toggle_card() -> void:
	var box := _new_card("整體交互開關", "整隻桌寵層級的總開關。「不主動」只是不會自己發起——使用者手動拖曳互動(拖道具給它、拖它去用家具),或積木明確指定的使用,都不受影響。")
	_ignore_props_check = CheckBox.new()
	_ignore_props_check.text = "不與道具交互(完全無視:不撿、不被摩擦、不成為候選、不被吸引)"
	_ignore_props_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ignore_props_check.toggled.connect(func(_pressed: bool) -> void: _commit_toggles())
	box.add_child(_ignore_props_check)
	_ignore_furniture_check = CheckBox.new()
	_ignore_furniture_check.text = "不主動使用家具(目前只有容器類的自主拿取行為;坐/躺類本來就沒有自主機制)"
	_ignore_furniture_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ignore_furniture_check.toggled.connect(func(_pressed: bool) -> void: _commit_toggles())
	box.add_child(_ignore_furniture_check)


func _commit_toggles() -> void:
	if _loading or _pet == null:
		return
	var rules := _rules()
	rules["ignore_props"] = _ignore_props_check.button_pressed
	rules["ignore_furniture"] = _ignore_furniture_check.button_pressed
	_apply(rules)


func _build_character_card() -> void:
	var box := _new_card("對其他角色的反應", "選一個角色庫裡的角色(不含自己),寫下看到它出現在場上時要說的話。同一個角色可以新增好幾句,會照順序說。這裡只能新增純對話。")
	box.add_child(ManagerUi.syntax_row(self, "台詞能用的語法", "這裡的對話可以用氣泡樣式、數值、名字標記與單字池等既有語法。點右邊的「語法字典」查全部語法並插入/複製。"))
	_char_option = OptionButton.new()
	box.add_child(ManagerUi.labeled("遇見的角色", _char_option))
	_char_line = ManagerUi.line_edit("看到它時要說的話")
	_char_line.max_length = InteractionRules.MAX_TEXT
	_char_line.text_submitted.connect(func(_t: String) -> void: _on_add_character_pressed())
	box.add_child(ManagerUi.labeled("對話", _char_line))
	var add := ManagerUi.button("＋ 新增這句對話")
	add.pressed.connect(_on_add_character_pressed)
	box.add_child(add)
	_char_list = VBoxContainer.new()
	box.add_child(_char_list)


## 基本反應對話:列出這隻角色目前用的「反應」性格裡,基於預設反應情境(玩球、被邀請、休息等)已經有的對話內容。
## 只能改對話文字本身(跳一下、發抖這類寫死的動作效果不會被動到);要新增反應情境或調整動作,去「性格」分頁按「編輯性格…」。
func _build_reaction_dialogue_card() -> void:
	var box := _new_card("基本反應對話", "列出這隻角色目前用的性格,在「玩球」「被邀請對戰」「休息」等既有反應情境裡已經有的對話內容。這裡只能改「對話文字」本身,跳一下、發抖這類動作不會被動到,也不能新增新的反應情境;要做這些,請到「性格」分頁按「編輯性格…」。")
	box.add_child(ManagerUi.syntax_row(self, "台詞能用的語法", "這裡的台詞可以用氣泡樣式、數值、名字標記與單字池等既有語法。點右邊的「語法字典」查全部語法並插入/複製。"))
	_reaction_list = VBoxContainer.new()
	_reaction_list.add_theme_constant_override("separation", 8)
	box.add_child(_reaction_list)


func _reload_reaction_dialogue() -> void:
	if _reaction_list == null:
		return
	for child in _reaction_list.get_children():
		child.queue_free()
	_reaction_boxes.clear()
	if _pet == null:
		return
	var id := PersonalityApplier.choice_of(_pet, "reactions")
	if id == "":
		_reaction_list.add_child(_muted_label("這隻角色目前沒有套用「反應」性格,沒有預設反應對話可以改。"))
		return
	var personality := PersonalityApplier.personality_of(_pet, id)
	var entries: Array = personality.get("reactions", [])
	var any := false
	for i in entries.size():
		var entry: Dictionary = entries[i]
		if (entry.get("say", []) as Array).is_empty():
			continue
		any = true
		_add_reaction_row(i, entry)
	if not any:
		_reaction_list.add_child(_muted_label(tr("「%s」目前沒有帶對話文字的預設反應可以改。") % str(personality.get("name", id))))


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = AppSettings.MUTED_LABEL
	return label


func _add_reaction_row(index: int, entry: Dictionary) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.add_child(_muted_label(PersonalityFile.trigger_label(str(entry.get("on", "")))))
	var lines_edit := TextEdit.new()
	lines_edit.custom_minimum_size.y = 56.0
	lines_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	lines_edit.placeholder_text = tr("一行一句備選台詞(每次隨機挑一句說)")
	lines_edit.text = "\n".join(PackedStringArray(entry.get("say", [])))
	lines_edit.focus_exited.connect(func() -> void: _commit_reaction_dialogue(index))
	row.add_child(lines_edit)
	_reaction_list.add_child(row)
	_reaction_boxes[index] = lines_edit


## 把某一條反應的對話文字(索引 index,對應 reactions 陣列)存回這隻角色自己的性格副本;action/hop/shiver 等其他欄位原樣保留。
func _commit_reaction_dialogue(index: int) -> void:
	if _loading or _pet == null or not _reaction_boxes.has(index):
		return
	var id := PersonalityApplier.choice_of(_pet, "reactions")
	if id == "":
		return
	PersonalityApplier.ensure_own(_pet, id)
	var personality: Dictionary = PersonalityApplier.personality_of(_pet, id).duplicate(true)
	var entries: Array = (personality.get("reactions", []) as Array).duplicate(true)
	if index < 0 or index >= entries.size():
		return
	var edit: TextEdit = _reaction_boxes[index]
	var lines: Array[String] = []
	for line: String in edit.text.split("\n"):
		if line.strip_edges() != "" and lines.size() < PersonalityFile.MAX_LINES_PER_ENTRY:
			lines.append(line.strip_edges().left(PersonalityFile.MAX_LINE_CHARS))
	if lines.is_empty():
		# 這裡只能改對話文字,不能把整條反應清空成沒有台詞;退回原本的內容。
		edit.text = "\n".join(PackedStringArray((entries[index] as Dictionary).get("say", [])))
		return
	var entry: Dictionary = (entries[index] as Dictionary).duplicate(true)
	entry["say"] = lines
	entries[index] = entry
	personality["reactions"] = entries
	var checked := PersonalityFile.validate(PersonalityFile.to_file_data(personality))
	if not bool(checked["ok"]):
		return
	PersonalityApplier.set_own(_pet, id, PersonalityFile.to_file_data(checked["personality"]))
	edit.text = "\n".join(PackedStringArray(lines))
	changed.emit()


func _build_prop_card() -> void:
	var box := _new_card("對道具的反應", "選一個道具管理裡的道具與時機,設定要說的話(選填)和要做的動作(選填)。動作可以只做一次,也可以持續到道具用完或離開判定。有設定時就不再播道具的預設動作。")
	_prop_option = OptionButton.new()
	box.add_child(ManagerUi.labeled("道具", _prop_option))
	_prop_kind_option = OptionButton.new()
	for kind: String in InteractionRules.PROP_KINDS:
		_prop_kind_option.add_item(str(InteractionRules.PROP_KINDS[kind]))
		_prop_kind_option.set_item_metadata(_prop_kind_option.item_count - 1, kind)
	box.add_child(ManagerUi.labeled("時機", _prop_kind_option))
	_prop_line = ManagerUi.line_edit("要說的話(選填)")
	_prop_line.max_length = InteractionRules.MAX_TEXT
	box.add_child(ManagerUi.labeled("對話", _prop_line))
	_prop_action_option = OptionButton.new()
	box.add_child(ManagerUi.labeled("動作", _prop_action_option))
	_prop_persist_option = OptionButton.new()
	_prop_persist_option.add_item("只做一次")
	_prop_persist_option.add_item("持續到道具用完 / 離開判定")
	box.add_child(ManagerUi.labeled("動作進行方式", _prop_persist_option))
	var add := ManagerUi.button("＋ 新增這條反應")
	add.pressed.connect(_on_add_prop_pressed)
	box.add_child(add)
	_prop_list = VBoxContainer.new()
	box.add_child(_prop_list)


func _build_pref_card() -> void:
	var box := _new_card("喜歡與不喜歡的道具", "每個道具選「喜歡」、「不喜歡」或「不與此道具交互」(完全無視:不撿、不被摩擦、不成為候選、不被吸引)。喜歡的道具掉在場上,桌寵會自己走過去撿,撿到心情變好;不喜歡的不會自己撿(拖著遞給它還是會收)。道具資料找不到(被刪掉或搬走)的會變成灰色,可以按「重新連結」改指向現有的另一個道具。")
	_pref_list = VBoxContainer.new()
	box.add_child(_pref_list)


func set_pet(pet: Node) -> void:
	_pet = pet
	_reload()


## 從桌寵目前的設定重新填所有控制項(不發變更)。
func _reload() -> void:
	if _pet == null or _flow == null:
		return
	_loading = true
	_nickname_line.text = ", ".join(PackedStringArray(_pet.user_nicknames))
	var names: Array[String] = _pet.action_names()
	var rules: Dictionary = _pet.interaction_rules
	_ignore_props_check.button_pressed = bool(rules.get("ignore_props", false))
	_ignore_furniture_check.button_pressed = bool(rules.get("ignore_furniture", false))
	for slot: String in _action_options:
		var option: OptionButton = _action_options[slot]
		option.clear()
		option.add_item(tr(DEFAULT_LABEL) + " " + slot)
		var current := str((rules["actions"] as Dictionary).get(slot, ""))
		var selected := 0
		var listed: Array[String] = names.duplicate()
		if current != "" and not listed.has(current):
			listed.append(current)
		for action_name in listed:
			option.add_item(action_name)
			if action_name == current:
				selected = option.item_count - 1
		option.select(selected)
	_characters.clear()
	_char_option.clear()
	for folder in SpriteLibrary.list_packs():
		var tag := SpriteLibrary.tag_of(folder)
		if tag == str(_pet.recognition_tag):
			continue
		var display := str(SpriteLibrary._read_manifest(folder).get("name", folder.get_file()))
		_characters.append({"tag": tag, "name": display})
		_char_option.add_item("%s(%s)" % [display, tag] if display != tag else tag)
	_props = PropLibrary.list()
	_prop_option.clear()
	for def in _props:
		_prop_option.add_item(def.display_name)
	_prop_action_option.clear()
	_prop_action_option.add_item("(不做動作)")
	for action_name in names:
		_prop_action_option.add_item(action_name)
	_loading = false
	_rebuild_lists()
	_reload_reaction_dialogue()


func _rules() -> Dictionary:
	return (_pet.interaction_rules as Dictionary).duplicate(true)


func _apply(rules: Dictionary) -> void:
	_pet.set_interaction_rules(rules)
	changed.emit()
	_rebuild_lists()


func _commit_actions() -> void:
	if _loading or _pet == null:
		return
	var rules := _rules()
	for slot: String in _action_options:
		var option: OptionButton = _action_options[slot]
		if option.selected <= 0:
			(rules["actions"] as Dictionary).erase(slot)
		else:
			rules["actions"][slot] = option.get_item_text(option.selected)
	_apply(rules)


## 新增一句「看到某個角色時說的話」(給按鈕與測試用)。回傳錯誤文字,空字串 = 成功。
func add_character_line(tag: String, display_name: String, text: String) -> String:
	if _pet == null:
		return "沒有選桌寵"
	if text.strip_edges() == "":
		return "對話不能是空的"
	if tag == "" or tag == str(_pet.recognition_tag):
		return "要選別的角色(不能是自己)"
	var rules := _rules()
	var found := false
	for entry: Dictionary in rules["characters"]:
		if entry["tag"] == tag:
			(entry["lines"] as Array).append(text)
			found = true
	if not found:
		(rules["characters"] as Array).append({"tag": tag, "name": display_name, "lines": [text]})
	_apply(rules)
	return ""


func remove_character_line(tag: String, index: int) -> void:
	var rules := _rules()
	for entry: Dictionary in rules["characters"]:
		if entry["tag"] == tag and index >= 0 and index < (entry["lines"] as Array).size():
			(entry["lines"] as Array).remove_at(index)
	_apply(rules)


## 新增一條道具反應。回傳錯誤文字,空字串 = 成功。
func add_prop_rule(prop_name: String, kind: String, line: String, action: String, persist: bool) -> String:
	if _pet == null:
		return "沒有選桌寵"
	if prop_name == "":
		return "還沒有道具:先到道具管理新增"
	if line.strip_edges() == "" and action == "":
		return "對話和動作至少要設定一個"
	var rules := _rules()
	(rules["props"] as Array).append({"prop": prop_name, "kind": kind, "line": line.strip_edges(), "action": action, "persist": persist})
	_apply(rules)
	return ""


func remove_prop_rule(index: int) -> void:
	var rules := _rules()
	if index >= 0 and index < (rules["props"] as Array).size():
		(rules["props"] as Array).remove_at(index)
	_apply(rules)


func _on_add_character_pressed() -> void:
	var picked := _char_option.selected
	if picked < 0 or picked >= _characters.size():
		message.emit("角色庫裡沒有別的角色可以選。")
		return
	var error := add_character_line(str(_characters[picked]["tag"]), str(_characters[picked]["name"]), _char_line.text)
	if error != "":
		message.emit(error)
		return
	_char_line.text = ""


func _on_add_prop_pressed() -> void:
	var picked := _prop_option.selected
	var prop_name := _props[picked].display_name if picked >= 0 and picked < _props.size() else ""
	var action := "" if _prop_action_option.selected <= 0 else _prop_action_option.get_item_text(_prop_action_option.selected)
	var error := add_prop_rule(prop_name, str(_prop_kind_option.get_item_metadata(_prop_kind_option.selected)), _prop_line.text, action, _prop_persist_option.selected == 1)
	if error != "":
		message.emit(error)
		return
	_prop_line.text = ""


func _rebuild_lists() -> void:
	if _char_list == null or _pet == null:
		return
	for child in _char_list.get_children():
		child.queue_free()
	for child in _prop_list.get_children():
		child.queue_free()
	var rules: Dictionary = _pet.interaction_rules
	for entry: Dictionary in rules["characters"]:
		for i in (entry["lines"] as Array).size():
			var tag := str(entry["tag"])
			var index := i
			_char_list.add_child(_row(tr("遇見 %s:「%s」") % [entry["name"], entry["lines"][i]], func() -> void: remove_character_line(tag, index)))
	_rebuild_prefs(rules)
	var rule_index := 0
	for rule: Dictionary in rules["props"]:
		var index := rule_index
		var parts: Array[String] = []
		if str(rule["line"]) != "":
			parts.append(tr("說「%s」") % rule["line"])
		if str(rule["action"]) != "":
			parts.append(tr("做 %s(%s)") % [rule["action"], tr("持續") if bool(rule["persist"]) else tr("一次")])
		_prop_list.add_child(_row("%s · %s:%s" % [rule["prop"], InteractionRules.PROP_KINDS[rule["kind"]], "、".join(parts)], func() -> void: remove_prop_rule(index)))
		rule_index += 1


## 設定對某個道具的喜好(pref = "like" / "dislike" / "" = 沒特別)。回傳錯誤文字,空字串 = 成功。
func set_preference(prop_id: String, prop_name: String, pref: String) -> String:
	if _pet == null:
		return "沒有選桌寵"
	if prop_id == "":
		return "找不到這個道具"
	var rules := _rules()
	var prefs: Array = rules["prefs"]
	for i in range(prefs.size() - 1, -1, -1):
		if prefs[i]["id"] == prop_id:
			prefs.remove_at(i)
	if pref != "":
		prefs.append({"id": prop_id, "name": prop_name, "pref": pref})
	_apply(rules)
	return ""


## 把找不到資料的喜好項目改指向現有的另一個道具(喜好保留)。回傳錯誤文字,空字串 = 成功。
func relink_preference(old_id: String, new_def: PropDef) -> String:
	if _pet == null or new_def == null:
		return "沒有選桌寵或道具"
	var rules := _rules()
	var found := false
	for entry: Dictionary in rules["prefs"]:
		if entry["id"] == new_def.id and entry["id"] != old_id:
			return "那個道具已經有設定喜好了"
	for entry: Dictionary in rules["prefs"]:
		if entry["id"] == old_id:
			entry["id"] = new_def.id
			entry["name"] = new_def.display_name
			found = true
	if not found:
		return "找不到要重新連結的項目"
	_apply(rules)
	return ""


func _rebuild_prefs(rules: Dictionary) -> void:
	for child in _pref_list.get_children():
		child.queue_free()
	var known := {}
	for def in _props:
		known[def.id] = true
		var current := InteractionRules.preference_of(rules, def.id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = def.display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var option := OptionButton.new()
		option.add_item("沒特別")
		option.add_item("喜歡")
		option.add_item("不喜歡")
		option.add_item("不與此道具交互")
		option.select(["", "like", "dislike", "ignore"].find(current))
		var prop_id := def.id
		var prop_name := def.display_name
		option.item_selected.connect(func(index: int) -> void: set_preference(prop_id, prop_name, ["", "like", "dislike", "ignore"][index]))
		row.add_child(option)
		_pref_list.add_child(row)
	for entry: Dictionary in rules["prefs"]:
		if known.has(entry["id"]):
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = tr("%s(%s,找不到道具資料)") % [entry["name"], {"like": tr("喜歡"), "dislike": tr("不喜歡")}.get(entry["pref"], tr("不與此道具交互"))]
		label.theme_type_variation = AppSettings.MUTED_LABEL
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var relink := ManagerUi.button("重新連結…")
		var old_id := str(entry["id"])
		relink.pressed.connect(func() -> void: _open_relink_menu(relink, old_id))
		row.add_child(relink)
		var remove := ManagerUi.button("✕")
		remove.tooltip_text = "移除這一項"
		remove.pressed.connect(func() -> void: set_preference(old_id, "", ""))
		row.add_child(remove)
		_pref_list.add_child(row)


func _open_relink_menu(anchor: Control, old_id: String) -> void:
	var menu := PopupMenu.new()
	var candidates: Array[PropDef] = []
	var taken := {}
	for entry: Dictionary in (_pet.interaction_rules as Dictionary)["prefs"]:
		taken[entry["id"]] = true
	for def in _props:
		if not taken.has(def.id):
			candidates.append(def)
			menu.add_item(def.display_name)
	if candidates.is_empty():
		menu.add_item("(沒有可以連結的道具)")
		menu.set_item_disabled(0, true)
	menu.index_pressed.connect(func(index: int) -> void:
		relink_preference(old_id, candidates[index])
		menu.queue_free())
	menu.close_requested.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(anchor.get_screen_position()) + Vector2i(0, int(anchor.size.y)), Vector2i(180, 0)))


func _row(text: String, on_remove: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = CARD_WIDTH - 90.0
	row.add_child(label)
	var remove := ManagerUi.button("✕")
	remove.tooltip_text = "刪除這一條"
	remove.pressed.connect(on_remove)
	row.add_child(remove)
	return row
