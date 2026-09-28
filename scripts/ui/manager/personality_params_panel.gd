class_name PersonalityParamsPanel
extends VBoxContainer
## 性格參數的「可填式方塊」表:每個參數(見 PersonalityParams.SPECS)一列,數字用數值框(夾在合法範圍內)、範圍用兩個數值框、開關用勾選框、
## 賽制偏好用三個數值框(1 / 3 / 5 戰);每列右邊有「↺」回到預設值。用在管理視窗的性格分頁(改這隻桌寵目前的值)與性格編輯器(改性格檔裡的值)。
## 只負責顯示與回報:使用者改了一項就發 value_changed(key, value)(value 已是合法值),由使用者決定寫到哪裡。

signal value_changed(key: String, value: Variant)

const LABEL_WIDTH := 150.0

var _rows: Dictionary = {}
var _updating := false


func _init() -> void:
	add_theme_constant_override("separation", 3)
	for key: String in PersonalityParams.keys():
		_build_row(key)


func _build_row(key: String) -> void:
	var spec: Dictionary = PersonalityParams.SPECS[key]
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = PersonalityFile.short_label(key)
	label.tooltip_text = "%s\n(%s)" % [TranslationServer.translate(PersonalityParams.label_of(key)), key]
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.custom_minimum_size.x = LABEL_WIDTH
	# 翻成英文常常比中文長很多(這裡本來就沒有截斷,只靠固定寬度),不換行的話長標籤會直接撐寬整列、
	# 逼整個左側欄位跟著撐寬(2026-09-30 使用者實機回報)。開 autowrap_mode 讓標籤在可用寬度內換行;
	# custom_minimum_size.x(上面已經設)同時也是換行估算的底線寬度,避免換行高度被估爆
	# (見 ManagerUi.hint_row() 旁的說明,同一個坑)。
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var controls: Array = []
	match str(spec["kind"]):
		"float":
			var spin := _spin(spec)
			spin.value_changed.connect(func(value: float) -> void: _emit(key, value))
			row.add_child(spin)
			controls.append(spin)
		"range":
			var low := _spin(spec)
			var high := _spin(spec)
			low.value_changed.connect(func(value: float) -> void:
				if _updating:
					return
				if value > high.value:
					_updating = true
					high.value = value
					_updating = false
				_emit(key, Vector2(low.value, high.value)))
			high.value_changed.connect(func(value: float) -> void:
				if _updating:
					return
				if value < low.value:
					_updating = true
					low.value = value
					_updating = false
				_emit(key, Vector2(low.value, high.value)))
			var separator := Label.new()
			separator.text = "~"
			for control in [low, separator, high]:
				row.add_child(control)
			controls = [low, high]
		"bool":
			var box := CheckBox.new()
			box.toggled.connect(func(on: bool) -> void: _emit(key, on))
			row.add_child(box)
			controls.append(box)
		"weights":
			pass   # 三個數值框改放第二列(下面 weight_row),不要跟第一列擠在一起(見底下說明)
	var reset := ManagerUi.button("↺")
	reset.tooltip_text = tr("回到預設值(%s)") % _default_text(key)
	reset.pressed.connect(func() -> void:
		_set_row(key, PersonalityParams.default_of(key))
		_emit(key, PersonalityParams.default_of(key)))
	row.add_child(reset)
	add_child(row)
	if str(spec["kind"]) == "weights":
		# 三個數值框(1/3/5 戰)擠在第一列裡會把整個視窗撐寬,改放第二列、跟標籤欄位對齊縮排。
		var weight_row := HBoxContainer.new()
		weight_row.add_theme_constant_override("separation", 6)
		var indent := Control.new()
		indent.custom_minimum_size.x = LABEL_WIDTH
		weight_row.add_child(indent)
		for weight_key: int in PersonalityParams.WEIGHT_KEYS:
			var caption := Label.new()
			caption.text = tr("%d戰") % weight_key
			caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var spin := ManagerUi.spin(0.05, 0.0, 10.0)
			spin.allow_greater = false
			spin.allow_lesser = false
			spin.custom_minimum_size.x = 64.0
			spin.value_changed.connect(func(_value: float) -> void: _emit_weights(key))
			weight_row.add_child(caption)
			weight_row.add_child(spin)
			controls.append(spin)
		add_child(weight_row)
	_rows[key] = {"kind": str(spec["kind"]), "controls": controls}


func _default_text(key: String) -> String:
	var value: Variant = PersonalityParams.default_of(key)
	return tr("開") if value is bool and value else (tr("關") if value is bool else PersonalityParams.to_text(value))


func _spin(spec: Dictionary) -> SpinBox:
	var span := float(spec["max"]) - float(spec["min"])
	var step := 0.01 if span <= 5.0 else (0.1 if span <= 100.0 else 1.0)
	var spin := ManagerUi.spin(step, float(spec["min"]), float(spec["max"]))
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.x = 84.0
	return spin


func _emit(key: String, value: Variant) -> void:
	if _updating:
		return
	value_changed.emit(key, value)


## 賽制偏好:三個權重不能全是 0(至少要有一種可選),全 0 就不發出、還原成上次的值。
func _emit_weights(key: String) -> void:
	if _updating:
		return
	var weights := {}
	var total := 0.0
	var controls: Array = _rows[key]["controls"]
	for i in PersonalityParams.WEIGHT_KEYS.size():
		var weight: float = (controls[i] as SpinBox).value
		weights[PersonalityParams.WEIGHT_KEYS[i]] = weight
		total += weight
	if total <= 0.0:
		var previous: Variant = _rows[key].get("last")
		if previous is Dictionary:
			_set_row(key, previous)
		return
	_rows[key]["last"] = weights
	value_changed.emit(key, weights)


## 依 values 更新所有方塊(不發訊號)。values 沒有的鍵顯示預設值。
func set_values(values: Dictionary) -> void:
	for key: String in _rows:
		_set_row(key, values.get(key, PersonalityParams.default_of(key)))


func _set_row(key: String, value: Variant) -> void:
	_updating = true
	var controls: Array = _rows[key]["controls"]
	match str(_rows[key]["kind"]):
		"float":
			(controls[0] as SpinBox).value = float(value)
		"range":
			(controls[0] as SpinBox).value = (value as Vector2).x
			(controls[1] as SpinBox).value = (value as Vector2).y
		"bool":
			(controls[0] as CheckBox).button_pressed = bool(value)
		"weights":
			for i in PersonalityParams.WEIGHT_KEYS.size():
				(controls[i] as SpinBox).value = float((value as Dictionary).get(PersonalityParams.WEIGHT_KEYS[i], 0.0))
			_rows[key]["last"] = (value as Dictionary).duplicate()
	_updating = false


## 目前方塊裡的所有值。
func values() -> Dictionary:
	var result := {}
	for key: String in _rows:
		var controls: Array = _rows[key]["controls"]
		match str(_rows[key]["kind"]):
			"float":
				result[key] = (controls[0] as SpinBox).value
			"range":
				result[key] = Vector2((controls[0] as SpinBox).value, (controls[1] as SpinBox).value)
			"bool":
				result[key] = (controls[0] as CheckBox).button_pressed
			"weights":
				var weights := {}
				for i in PersonalityParams.WEIGHT_KEYS.size():
					weights[PersonalityParams.WEIGHT_KEYS[i]] = (controls[i] as SpinBox).value
				result[key] = weights
	return result
