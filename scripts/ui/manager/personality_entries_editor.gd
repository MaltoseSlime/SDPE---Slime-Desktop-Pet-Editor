class_name PersonalityEntriesEditor
extends VBoxContainer
## 性格編輯器裡的「台詞」編輯區(閒聊台詞或反應台詞):依情境/觸發分組,每組有幾個項目,每個項目是一個文字框
## (一行一句備選台詞,每次隨機挑一句;閒聊可勾「依序全說」)加上機率、順便做的動作(播放動作、跳幾下、發抖幾秒)。
## 資料格式和 PersonalityFile.validate 整理出來的 chat / reactions 項目一樣:{tag, lens, say[], seq[], chance, weight, effects{}} 與 {on, say[], chance, effects{}}(weight 只有 chat 有,是閒聊抽選池的競爭權重,不是獨立機率)。
## 台詞可以直接手打氣泡語法:[b]粗體[/b]、[wave]…[/wave]、[color=#ff8080]…[/color]、{數值名稱}(插入目前數值)。

signal changed

## 反應編輯區固定列出的觸發(沒有項目也會顯示,方便直接新增)。
const REACTION_ORDER: Array[String] = ["interact", "drag", "enter", "sleep", "game_win", "game_lose", "game_tie", "invite_accept", "invite_refuse", "tired", "wake", "ball_found", "ball_invite", "ball_join", "ball_decline", "ball_playing", "ball_end", "ball_watch"]

var _kind := "chat"
var _groups: Dictionary = {}
var _group_order: Array[String] = []
var _updating := false


func setup(kind: String) -> void:
	_kind = kind
	add_theme_constant_override("separation", 6)


## 用一批項目重建整個編輯區(不發 changed)。
func load_entries(entries: Array) -> void:
	_updating = true
	for child in get_children():
		child.queue_free()
	_groups.clear()
	_group_order.clear()
	var keys: Array[String] = []
	if _kind == "chat":
		keys = ["chat", "rest", "sleep", "lens"]
	else:
		keys = REACTION_ORDER.duplicate()
		for entry: Dictionary in entries:
			if not keys.has(str(entry["on"])):
				keys.append(str(entry["on"]))
	for key in keys:
		_add_group(key)
	for entry: Dictionary in entries:
		var key := str(entry["tag"]) if _kind == "chat" else str(entry["on"])
		if _groups.has(key):
			_add_entry(key, entry)
	_updating = false


func _group_title(key: String) -> String:
	if _kind == "chat":
		return "%s(%s)" % [PersonalityFile.CHAT_TAG_LABELS.get(key, key), {"chat": "沒事閒聊時", "rest": "坐著休息時", "sleep": "睡覺時說夢話", "lens": "某個狀態鏡生效時,例如疲憊、生氣、開心"}.get(key, "")]
	return PersonalityFile.trigger_label(key)


func _add_group(key: String) -> void:
	var header := HBoxContainer.new()
	var title := ManagerUi.heading(_group_title(key))
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var add := ManagerUi.button("＋新增一項")
	add.pressed.connect(func() -> void:
		_add_entry(key, {})
		if not _updating:
			changed.emit())
	header.add_child(add)
	add_child(header)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	add_child(list)
	_groups[key] = list
	_group_order.append(key)


## entry 是空字典 = 新的空白項目。
func _add_entry(key: String, entry: Dictionary) -> void:
	var box := PanelContainer.new()
	var inner := VBoxContainer.new()
	box.add_child(inner)
	var lines := TextEdit.new()
	lines.custom_minimum_size.y = 64.0
	lines.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	lines.placeholder_text = tr("一行一句備選台詞(每次隨機挑一句);可以手打 [b]粗體[/b]、[wave]…[/wave]、{數值名稱}")
	var source: Array = []
	if not entry.is_empty():
		source = entry["seq"] if _kind == "chat" and not (entry.get("seq", []) as Array).is_empty() else entry["say"]
	lines.text = "\n".join(PackedStringArray(source))
	lines.text_changed.connect(_notify)
	inner.add_child(lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	inner.add_child(row)
	var sequence: CheckBox = null
	if _kind == "chat":
		sequence = CheckBox.new()
		sequence.text = "依序全說"
		sequence.tooltip_text = "勾了 = 每一行都依序說出來(像一小段獨白);沒勾 = 每次只隨機挑一行說。"
		sequence.button_pressed = not entry.is_empty() and not (entry.get("seq", []) as Array).is_empty()
		sequence.toggled.connect(func(_on: bool) -> void: _notify())
		row.add_child(sequence)
	var chance := _spin(0.0, 100.0, 5.0, " %")
	chance.value = float(entry.get("chance", 100.0)) if not entry.is_empty() else 100.0
	chance.tooltip_text = "這一項真的開口的機率(100 = 一定說)。"
	row.add_child(_captioned("機率", chance))
	var weight: SpinBox = null
	if _kind == "chat":
		weight = _spin(0.0, 200.0, 10.0, "")
		weight.value = float(entry.get("weight", 100.0)) if not entry.is_empty() else 100.0
		weight.tooltip_text = "觸發率(0~200,預設 100):跟同一組情境裡其他台詞競爭被抽中的權重,不是獨立機率——200 不代表一定被抽到,只是機率是預設的兩倍,還是要跟其他台詞比。"
		row.add_child(_captioned("觸發率", weight))
	var action := ManagerUi.line_edit("動作名稱")
	action.custom_minimum_size.x = 100.0
	action.text = str((entry.get("effects", {}) as Dictionary).get("action", ""))
	action.tooltip_text = "說話時順便播放的動作(例如 dance),空白 = 不播。"
	action.text_changed.connect(func(_t: String) -> void: _notify())
	row.add_child(_captioned("動作", action))
	var hop := _spin(0.0, 5.0, 1.0, "")
	hop.value = float((entry.get("effects", {}) as Dictionary).get("hop", 0))
	hop.tooltip_text = "順便小跳幾下(0 = 不跳)。"
	row.add_child(_captioned("跳", hop))
	var shiver := _spin(0.0, 6.0, 0.1, "")
	shiver.value = float((entry.get("effects", {}) as Dictionary).get("shiver", 0.0))
	shiver.tooltip_text = "順便發抖幾秒(0 = 不抖)。"
	row.add_child(_captioned("抖", shiver))
	var lens_edit: LineEdit = null
	if key == "lens":
		lens_edit = ManagerUi.line_edit("狀態鏡名稱")
		lens_edit.custom_minimum_size.x = 100.0
		lens_edit.text = str(entry.get("lens", ""))
		lens_edit.tooltip_text = "這句只在這個狀態鏡生效時說;空白 = 任何狀態鏡生效時都可以。名稱要跟建立當下打的原文完全一樣(通常是中文,使用者自建的狀態鏡沒有翻譯);內建的「開心/悠哉/緊張/生氣/悲傷/疲憊」六個例外,打英文(happy/relaxed/nervous/angry/sad/tired)也認得到。"
		lens_edit.text_changed.connect(func(_t: String) -> void: _notify())
		row.add_child(_captioned("狀態鏡", lens_edit))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var delete := ManagerUi.button("刪除這項")
	delete.pressed.connect(func() -> void:
		box.queue_free()
		# queue_free 之後下一個影格才真的移除;先隱藏並標記,收集時略過。
		box.visible = false
		box.set_meta("deleted", true)
		_notify())
	row.add_child(delete)
	var spins: Array[SpinBox] = [chance, hop, shiver]
	if weight != null:
		spins.append(weight)
	for spin: SpinBox in spins:
		spin.value_changed.connect(func(_v: float) -> void: _notify())
	box.set_meta("parts", {"lines": lines, "sequence": sequence, "chance": chance, "weight": weight, "action": action, "hop": hop, "shiver": shiver, "lens": lens_edit, "key": key})
	(_groups[key] as VBoxContainer).add_child(box)


func _notify(_arg: Variant = null) -> void:
	if not _updating:
		changed.emit()


func _spin(min_value: float, max_value: float, step: float, suffix_text: String) -> SpinBox:
	var spin := ManagerUi.spin(step, min_value, max_value)
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.suffix = suffix_text
	spin.custom_minimum_size.x = 84.0
	return spin


func _captioned(caption: String, control: Control) -> HBoxContainer:
	var box := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.theme_type_variation = AppSettings.MUTED_LABEL
	box.add_child(label)
	box.add_child(control)
	return box


## 目前編輯區裡的所有項目(格式同 PersonalityFile.validate 的 chat / reactions);沒有台詞也沒有動作的空白項目略過。
func entries() -> Array:
	var result: Array = []
	for key in _group_order:
		for box: Node in (_groups[key] as VBoxContainer).get_children():
			if box.has_meta("deleted") or box.is_queued_for_deletion():
				continue
			var parts: Dictionary = box.get_meta("parts")
			var text_lines: Array[String] = []
			for line: String in (parts["lines"] as TextEdit).text.split("\n"):
				if line.strip_edges() != "" and text_lines.size() < PersonalityFile.MAX_LINES_PER_ENTRY:
					text_lines.append(line.strip_edges().left(PersonalityFile.MAX_LINE_CHARS))
			var effects := {}
			var action_text := (parts["action"] as LineEdit).text.strip_edges()
			if action_text != "":
				effects["action"] = action_text.left(40)
			if (parts["hop"] as SpinBox).value >= 1.0:
				effects["hop"] = clampi(int((parts["hop"] as SpinBox).value), 1, 5)
			if (parts["shiver"] as SpinBox).value >= 0.3:
				effects["shiver"] = clampf((parts["shiver"] as SpinBox).value, 0.3, 6.0)
			var sequence: CheckBox = parts["sequence"]
			var as_sequence := sequence != null and sequence.button_pressed
			if text_lines.is_empty() and (_kind == "chat" or effects.is_empty()):
				continue
			var entry := {"say": [] if as_sequence else text_lines, "chance": (parts["chance"] as SpinBox).value, "effects": effects}
			if _kind == "chat":
				entry["tag"] = key
				entry["lens"] = (parts["lens"] as LineEdit).text.strip_edges().left(40) if parts["lens"] != null else ""
				entry["seq"] = text_lines if as_sequence else []
				entry["weight"] = (parts["weight"] as SpinBox).value if parts["weight"] != null else 100.0
			else:
				entry["on"] = key
			result.append(entry)
	return result


## 每一組目前有幾個項目(測試與顯示用)。
func counts() -> Dictionary:
	var result := {}
	for key in _group_order:
		var count := 0
		for box: Node in (_groups[key] as VBoxContainer).get_children():
			if not box.has_meta("deleted") and not box.is_queued_for_deletion():
				count += 1
		result[key] = count
	return result
