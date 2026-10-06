class_name TopicConditionDialog
extends ConfirmationDialog
## 2026-10-06 話題條件設定視窗(程式端,取代自由輸入的條件欄):勾選要啟用的條件(可複選),設定數值;
## 確定後產生條件字串,多個條件以「，」連接(全部成立才算)。字串格式就是 LogicInterpreter._special_atom() 與 _topic_atom_ok() 認得的寫法,
## 網頁編輯器的積木也照同一套寫法產生。打開舊條件時會盡量還原勾選;認不得的部分保留原文。
## 「高於/等於/低於」與「高/低」這類選擇用一排互斥按鈕(不用彈出式下拉選單,避免在捲動區裡點不開)。

signal condition_chosen(condition: String)

const LEVEL_VALUES := [-3, -2, -1, 0, 1, 2, 3]
const LEVEL_NAMES := {-3: "超級討厭", -2: "討厭", -1: "有點討厭", 0: "普通", 1: "有點喜歡", 2: "喜歡", 3: "超級喜歡"}
const CMP_WORDS := ["高於", "等於", "低於"]

var _rows: Dictionary = {}
var _extra_label: Label
var _warning: Label
var _extra_text: Array[String] = []


func _init() -> void:
	title = tr("話題條件設定")
	ok_button_text = tr("確定")
	cancel_button_text = tr("取消")
	min_size = Vector2i(420, 360)
	exclusive = false
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -52.0
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	box.add_child(_hint(tr("勾選要啟用的條件(可以複選),再設定數值。勾選的條件全部都要成立,閒聊時這句話才會被選。")))
	_add_range_row(box)
	_add_compare_row(box)
	_add_area_row(box)
	_add_mood_row(box)
	_add_vs_liked_row(box)
	_add_contact_row(box)
	_extra_label = _hint("")
	box.add_child(_extra_label)
	_warning = _hint("")
	_warning.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	box.add_child(_warning)
	get_label().visible = false
	confirmed.connect(func() -> void: condition_chosen.emit(build_condition()))


## 依現有條件字串還原勾選;認不得的原文保留(確定時照原樣接在後面)。
func set_condition(condition: String) -> void:
	for key: String in _rows:
		(_rows[key]["check"] as CheckBox).button_pressed = false
	_extra_text.clear()
	for raw: String in condition.replace("，", ",").replace("且", ",").split(","):
		var atom := raw.strip_edges()
		if atom != "" and not _apply_atom(atom):
			_extra_text.append(atom)
	_extra_label.text = (tr("保留原文的條件:%s") % "，".join(_extra_text)) if not _extra_text.is_empty() else ""
	_extra_label.visible = not _extra_text.is_empty()


## 目前勾選組成的條件字串(沒有任何條件 = 空字串)。
func build_condition() -> String:
	var atoms: Array[String] = []
	_warning.text = ""
	if _checked("range"):
		var lo := int(_rows["range"]["min"].value)
		var hi := int(_rows["range"]["max"].value)
		if lo > hi:
			var swap := lo
			lo = hi
			hi = swap
		atoms.append("好感度%d～%d" % [lo, hi])
	if _checked("compare"):
		atoms.append("好感度%s%d" % [CMP_WORDS[_pick(_rows["compare"]["cmp"])], int(_rows["compare"]["value"].value)])
	if _checked("area"):
		var levels := _levels("area")
		if levels == "":
			_warning.text = tr("請至少勾一個好惡分級。")
		else:
			atoms.append("好惡%s的對象%s" % [levels, "在行動區內" if _pick(_rows["area"]["presence"]) == 0 else "不在行動區內"])
	if _checked("mood"):
		atoms.append("心情閾值%s" % ("高" if _pick(_rows["mood"]["level"]) == 0 else "低"))
	if _checked("vs_liked"):
		var vs_levels := _levels("vs_liked")
		if vs_levels == "":
			_warning.text = tr("請至少勾一個好惡分級。")
		else:
			atoms.append("使用者好感度%s好惡%s的對象" % [CMP_WORDS[_pick(_rows["vs_liked"]["cmp"])], vs_levels])
	if _checked("contact"):
		var contact_levels := _levels("contact")
		if contact_levels == "":
			_warning.text = tr("請至少勾一個好惡分級。")
		else:
			atoms.append("好惡%s的對象判定箱接觸" % contact_levels)
	for extra: String in _extra_text:
		atoms.append(extra)
	return "，".join(atoms)


func _checked(key: String) -> bool:
	return _rows.has(key) and (_rows[key]["check"] as CheckBox).button_pressed


## 勾選的好惡分級清單,例如 "-3、1、2"(用頓號,避免跟條件的逗號混淆);沒勾就是空字串。
func _levels(key: String) -> String:
	var picked: Array = []
	for level: int in LEVEL_VALUES:
		if (_rows[key]["levels"][level] as CheckBox).button_pressed:
			picked.append(level)
	picked.sort()
	return "、".join(picked.map(func(v: int) -> String: return str(v)))


## 試著把一個原子條件套到勾選上;認得就回傳 true。
func _apply_atom(atom: String) -> bool:
	var m := RegEx.create_from_string("^好感度(\\d+)[～~](-?\\d+)$").search(atom)
	if m != null:
		(_rows["range"]["check"] as CheckBox).button_pressed = true
		_rows["range"]["min"].value = float(m.get_string(1))
		_rows["range"]["max"].value = float(m.get_string(2))
		return true
	m = RegEx.create_from_string("^好感度(大於|高於|低於|小於|等於)(-?\\d+)$").search(atom)
	if m != null:
		(_rows["compare"]["check"] as CheckBox).button_pressed = true
		var word := m.get_string(1)
		if word == "大於" or word == "高於":
			word = "高於"
		elif word == "小於":
			word = "低於"
		_set_pick(_rows["compare"]["cmp"], CMP_WORDS.find(word))
		_rows["compare"]["value"].value = float(m.get_string(2))
		return true
	m = RegEx.create_from_string("^好惡((?:-?\\d)(?:、-?\\d)*)的對象(在行動區內|不在行動區內|遭遇時|判定箱接觸)$").search(atom)
	if m != null:
		var kind := m.get_string(2)
		if kind == "在行動區內" or kind == "不在行動區內":
			(_rows["area"]["check"] as CheckBox).button_pressed = true
			_set_pick(_rows["area"]["presence"], 0 if kind == "在行動區內" else 1)
			_pick_levels("area", m.get_string(1))
		else:
			# 「遭遇時」舊寫法 = 判定箱接觸
			(_rows["contact"]["check"] as CheckBox).button_pressed = true
			_pick_levels("contact", m.get_string(1))
		return true
	m = RegEx.create_from_string("^使用者好感度(高於|等於|低於)好惡((?:-?\\d)(?:、-?\\d)*)的對象$").search(atom)
	if m != null:
		(_rows["vs_liked"]["check"] as CheckBox).button_pressed = true
		_set_pick(_rows["vs_liked"]["cmp"], CMP_WORDS.find(m.get_string(1)))
		_pick_levels("vs_liked", m.get_string(2))
		return true
	m = RegEx.create_from_string("^心情閾值(高|低)$").search(atom)
	if m != null:
		(_rows["mood"]["check"] as CheckBox).button_pressed = true
		_set_pick(_rows["mood"]["level"], 0 if m.get_string(1) == "高" else 1)
		return true
	return false


func _pick_levels(key: String, levels_text: String) -> void:
	for part: String in levels_text.split("、"):
		var level := int(part)
		if _rows[key]["levels"].has(level):
			(_rows[key]["levels"][level] as CheckBox).button_pressed = true


func _add_range_row(box: VBoxContainer) -> void:
	var sub := _row(box, "range", tr("使用者好感度"))
	var lo := _spin(-500, 1000, 0)
	var hi := _spin(-500, 1000, 100)
	sub.add_child(lo)
	sub.add_child(_label("～"))
	sub.add_child(hi)
	_rows["range"]["min"] = lo
	_rows["range"]["max"] = hi


func _add_compare_row(box: VBoxContainer) -> void:
	var sub := _row(box, "compare", tr("使用者好感度"))
	_rows["compare"]["cmp"] = _choice(sub, CMP_WORDS)
	var value := _spin(-500, 1000, 100)
	sub.add_child(value)
	_rows["compare"]["value"] = value


func _add_area_row(box: VBoxContainer) -> void:
	var sub := _row(box, "area", tr("好惡對象分級為"))
	_rows["area"]["levels"] = _level_checks(sub)
	sub.add_child(_label(tr("且對方")))
	_rows["area"]["presence"] = _choice(sub, [tr("在行動區內"), tr("不在行動區內")])


func _add_mood_row(box: VBoxContainer) -> void:
	var sub := _row(box, "mood", tr("桌寵心情閾值為"))
	_rows["mood"]["level"] = _choice(sub, [tr("高(開心門檻)"), tr("低(生氣門檻)")])


func _add_vs_liked_row(box: VBoxContainer) -> void:
	var sub := _row(box, "vs_liked", tr("好惡對象分級為"))
	_rows["vs_liked"]["levels"] = _level_checks(sub)
	sub.add_child(_label(tr("且使用者好感度")))
	_rows["vs_liked"]["cmp"] = _choice(sub, CMP_WORDS)
	sub.add_child(_label(tr("好惡對象")))


func _add_contact_row(box: VBoxContainer) -> void:
	var sub := _row(box, "contact", tr("好惡對象分級為"))
	_rows["contact"]["levels"] = _level_checks(sub)
	sub.add_child(_label(tr("且桌寵與好惡對象判定箱接觸時")))


## 一條條件:勾選框(標題)+ 下面一排控制項。條件之間加一條分隔線。回傳控制項的容器。
func _row(box: VBoxContainer, key: String, text: String) -> HFlowContainer:
	if not _rows.is_empty():
		box.add_child(HSeparator.new())
	var check := CheckBox.new()
	check.text = text
	box.add_child(check)
	var sub := HFlowContainer.new()
	sub.add_theme_constant_override("h_separation", 6)
	sub.add_theme_constant_override("v_separation", 4)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(sub)
	_rows[key] = {"check": check}
	return sub


func _level_checks(sub: HFlowContainer) -> Dictionary:
	var checks := {}
	for level: int in LEVEL_VALUES:
		var check := CheckBox.new()
		check.text = "%d %s" % [level, tr(LEVEL_NAMES[level])]
		sub.add_child(check)
		checks[level] = check
	return checks


## 一排互斥按鈕(同一時間只能按一個,跟單選一樣)。回傳 {"buttons": [Button...]}。
func _choice(sub: HFlowContainer, labels: Array) -> Dictionary:
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for text: String in labels:
		var button := Button.new()
		button.text = text
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_ALL
		sub.add_child(button)
		buttons.append(button)
	if not buttons.is_empty():
		buttons[0].button_pressed = true
	return {"buttons": buttons}


func _pick(choice: Dictionary) -> int:
	var buttons: Array = choice["buttons"]
	for i in buttons.size():
		if (buttons[i] as Button).button_pressed:
			return i
	return 0


func _set_pick(choice: Dictionary, index: int) -> void:
	var buttons: Array = choice["buttons"]
	if index >= 0 and index < buttons.size():
		(buttons[index] as Button).button_pressed = true


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1
	spin.value = value
	return spin


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = AppSettings.MUTED_LABEL
	return label
