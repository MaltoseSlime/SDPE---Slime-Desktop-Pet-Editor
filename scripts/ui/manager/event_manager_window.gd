class_name EventManagerWindow
extends FloatingWindow
## 2026-10-04 新增:查看一隻桌寵目前生效的所有事件(見 LogicInterpreter.list_events()),可以暫時停用或
## 移除某一條。跟測試者面板其他操作同一個原則(見 tester_window.gd 開頭的說明):停用只影響這次執行,
## 不寫檔(停用的事件在這裡也會顯示成「已停用」,跟失控保護共用 LogicInterpreter._disabled_hats)。
## 2026-10-05 改版:使用者自己的事件(來源標「自訂」)移除會真的寫回積木檔(LogicInterpreter.remove_user_hat()
## + save_user_only_file()),下次開機也不會回來;性格/交互行為規則層帶來的仍只影響這次執行。
## 「移除」跟「移除所有已停用事件」都用「再按一次確定」的行內確認,不跳彈窗(這個視窗是置頂的浮動視窗,
## 另開對話框在這裡有既有的顯示問題,見 [[project-always-on-top-disabled]])。
##
## 使用者要求「交互行為」分頁跟測試者面板都要能開這個視窗,所以做成共用元件,透過
## ManagerUi.open_event_manager_window(host, pet) 開啟,不是只掛在某一邊。

const LAYER_LABELS := {"user": "自訂", "personality": "性格", "rule": "交互行為規則", "placeholder": "佔位閒聊", "topic": "話題"}

var _pet: Node
var _list: VBoxContainer
var _status: Label
var _batch_button: Button
var _batch_armed := false


func setup(pet: Node) -> void:
	_pet = pet
	var name_text: String = pet.get_label() if pet != null and is_instance_valid(pet) else ""
	setup_floating(tr("事件管理 — %s") % name_text, Vector2i(560, 580), Vector2i(380, 320))
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	background.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)
	var intro := Label.new()
	intro.text = tr("這隻桌寵目前生效的所有事件(閒聊、反應、計時器、話題…)。左邊的勾選框:打勾 = 生效(會自己觸發),取消勾選 = 暫時停用(不會自己觸發)。停用只影響這次執行、不寫檔,下次開啟或套用性格就會恢復。「自訂」的事件按移除會寫回積木檔、永久刪除;性格/交互行為規則帶來的事件移除只影響這次執行,下次性格重新套用或按交互行為「儲存」就會恢復。")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.theme_type_variation = AppSettings.MUTED_LABEL
	page.add_child(intro)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	page.add_child(toolbar)
	var refresh := ManagerUi.button(tr("重新整理"))
	refresh.tooltip_text = tr("桌寵觸發新事件、使用者匯入新積木檔、或在別的視窗改了交互行為設定後重新讀取")
	refresh.pressed.connect(_refresh)
	toolbar.add_child(refresh)
	_batch_button = ManagerUi.button(tr("移除所有已停用事件"))
	_batch_button.tooltip_text = tr("一次移除所有被取消勾選的事件。自訂的會寫回積木檔(永久),按兩次確定。")
	_batch_button.pressed.connect(_on_batch_pressed)
	toolbar.add_child(_batch_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.theme_type_variation = AppSettings.MUTED_LABEL
	page.add_child(_status)
	_refresh()


func _refresh() -> void:
	_batch_armed = false
	for child in _list.get_children():
		child.queue_free()
	if _pet == null or not is_instance_valid(_pet) or _pet.logic == null:
		_status.text = tr("這隻桌寵已經不在桌面上了。")
		_batch_button.disabled = true
		return
	var events: Array[Dictionary] = _pet.logic.list_events()
	_batch_button.disabled = _disabled_entries(events).is_empty()
	_batch_button.text = tr("移除所有已停用事件")
	if events.is_empty():
		_status.text = tr("目前沒有任何事件。")
		return
	_status.text = tr("共 %d 個事件。") % events.size()
	# 2026-10-05 新增:觸發條件相同的分組提示(見 LogicInterpreter.trigger_signature()/「2026-10-02 新議題」
	# 第 3 類)——先數每個特徵碼出現幾次,等於 1 的不用特別標記。
	var sig_counts: Dictionary = {}
	for entry: Dictionary in events:
		var sig := str(entry.get("trigger_sig", ""))
		sig_counts[sig] = int(sig_counts.get(sig, 0)) + 1
	for entry: Dictionary in events:
		var count: int = sig_counts.get(str(entry.get("trigger_sig", "")), 1)
		_list.add_child(_row(entry, count))


func _disabled_entries(events: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in events:
		if bool(entry.get("disabled", false)):
			result.append(entry)
	return result


## 「移除所有已停用事件」:第一次按只把按鈕改成確認狀態,第二次按才真的執行。
func _on_batch_pressed() -> void:
	if _pet == null or not is_instance_valid(_pet):
		return
	var targets := _disabled_entries(_pet.logic.list_events())
	if targets.is_empty():
		return
	if not _batch_armed:
		_batch_armed = true
		_batch_button.text = tr("再按一次確定移除 %d 個") % targets.size()
		return
	_batch_armed = false
	var result := _remove_entries(targets)
	_refresh()
	_status.text = _removed_message(result)


## 實際移除一批事件。自訂(user 層)的寫回積木檔;其餘只影響這次執行。回傳 {"user": 永久移除數, "memory": 只影響這次數, "saved": 寫檔是否成功}。
func _remove_entries(entries: Array) -> Dictionary:
	var user_removed := 0
	var memory_removed := 0
	for entry: Dictionary in entries:
		var hat: Dictionary = entry["hat"]
		if str(entry.get("layer", "")) == "user":
			if _pet.logic.remove_user_hat(hat):
				user_removed += 1
		elif _pet.logic.remove_hat(hat):
			memory_removed += 1
	var saved := true
	if user_removed > 0:
		saved = _save_user_layer()
	return {"user": user_removed, "memory": memory_removed, "saved": saved}


func _removed_message(result: Dictionary) -> String:
	if not bool(result["saved"]):
		return tr("已移除,但寫回積木檔失敗,重新開啟後可能又會出現。")
	return tr("已永久移除 %d 個自訂事件(已寫回積木檔);已從這次執行移除 %d 個性格/規則事件(下次套用會恢復)。") % [result["user"], result["memory"]]


## 把使用者自己這層(不含性格/規則層)寫回這隻桌寵的積木檔,跟 desktop_shell/memory_tab 去重後覆蓋的做法一樣。
func _save_user_layer() -> bool:
	var path := PetRoster.logic_path(_pet.recognition_tag, CharacterFiles.folder_of(_pet))
	return _pet.logic.save_user_only_file(path) == OK


## 一條事件:啟用/停用勾選框 + 說明(含來源層標籤)+ 移除按鈕,下面視情況再加一行「觸發條件相同」提示。
## 用 VBoxContainer 包著(不是直接回傳 HBoxContainer),提示那一行才能自然往下換行,不會擠壓到上面那排
## 的勾選框/文字/按鈕的橫向空間。
func _row(entry: Dictionary, same_trigger_count: int = 1) -> Control:
	if str(entry.get("kind", "")) == "topic":
		return _topic_row(entry)
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 2)
	var box := HBoxContainer.new()
	# 2026-10 使用者實機回報:這一行漏掉時,整排(連帶裡面會換行的 Label)不會撐滿 _list 的寬度,
	# 自動換行的文字會被壓進一個很窄的欄位,逐字斷行變成直的一條——跟既有的「換行 Label 要有實際可用
	# 寬度」那個坑是同一類,差別在這裡漏掉的是外層列容器的 expand,不是 Label 本身。
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var check := CheckBox.new()
	check.button_pressed = not bool(entry.get("disabled", false))
	check.tooltip_text = tr("取消勾選 = 暫時停用這個事件(不會自己觸發),不寫檔。")
	check.toggled.connect(func(pressed: bool) -> void:
		if _pet == null or not is_instance_valid(_pet):
			return
		_pet.logic.set_hat_disabled(entry["hat"], not pressed)
		_status.text = tr("已%s:%s") % [tr("啟用") if pressed else tr("停用"), str(entry.get("label", ""))])
	box.add_child(check)
	var label := Label.new()
	var layer_tag := str(LAYER_LABELS.get(str(entry.get("layer", "user")), ""))
	label.text = "[%s] %s" % [tr(layer_tag), str(entry.get("label", ""))]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	# 2026-10-05:觸發條件相同的提醒改成一個 ⚠ 圖示,說明文字收在 hover 裡(WrappedTooltipLabel 會自動換行)。
	if same_trigger_count > 1:
		var warn := WrappedTooltipLabel.new()
		warn.text = "⚠"
		warn.tooltip_text = tr("跟另外 %d 個事件的觸發條件相同(型別與關鍵欄位一樣,不含你自己取的事件名稱)。可能是不小心做出重複效果,也可能是故意疊加增加隨機變化,系統不會自動停用或合併,要不要處理由你自己判斷。") % (same_trigger_count - 1)
		warn.mouse_filter = Control.MOUSE_FILTER_STOP
		box.add_child(warn)
	# 2026-10-05:強制觸發,跟測試者面板「強制觸發這個事件」同一個呼叫(見 tester_window.gd _force_event())。
	var play_button := ManagerUi.button("▶")
	play_button.tooltip_text = tr("強制觸發這個事件(跟測試者面板的強制觸發一樣:先中止目前正在播的內容,無視觸發條件與停用狀態)。")
	play_button.pressed.connect(func() -> void:
		if _pet == null or not is_instance_valid(_pet):
			return
		_pet.logic.force_run_hat(entry["hat"])
		_refresh()
		_status.text = tr("強制觸發事件:%s") % str(entry.get("label", "")))
	box.add_child(play_button)
	var remove_button := ManagerUi.button(tr("移除"))
	var is_user := str(entry.get("layer", "")) == "user"
	remove_button.tooltip_text = tr("永久移除(寫回積木檔),按兩次確定。") if is_user else tr("只影響這次執行,下次性格套用或交互行為儲存會恢復。")
	var armed := [false]
	remove_button.pressed.connect(func() -> void:
		if _pet == null or not is_instance_valid(_pet):
			return
		if is_user and not armed[0]:
			armed[0] = true
			remove_button.text = tr("確定移除")
			return
		if is_user:
			var user_result := _remove_entries([entry])
			_refresh()
			_status.text = _removed_message(user_result)
			return
		var ok: bool = _pet.logic.remove_hat(entry["hat"])
		_status.text = (tr("已移除:%s") % str(entry.get("label", ""))) if ok else tr("找不到這個事件(可能是佔位用的閒聊,無法移除)")
		_refresh())
	box.add_child(remove_button)
	container.add_child(box)
	return container


## 話題文本的一列(2026-10-06):說一句(強制)與移除(按兩次確定)。
func _topic_row(entry: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var check := CheckBox.new()
	check.button_pressed = not bool(entry.get("disabled", false))
	check.tooltip_text = tr("取消勾選 = 暫時停用這句話題(閒聊不會挑中它),只影響這次執行、不寫檔。")
	check.toggled.connect(func(pressed: bool) -> void:
		if _pet == null or not is_instance_valid(_pet):
			return
		_pet.logic.set_topic_disabled(int(entry["topic_index"]), not pressed)
		_status.text = tr("已%s:%s") % [tr("啟用") if pressed else tr("停用"), str(entry.get("label", ""))])
	box.add_child(check)
	var label := Label.new()
	label.text = "[%s] %s" % [tr("話題"), str(entry.get("label", ""))]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	var play_button := ManagerUi.button("▶")
	play_button.tooltip_text = tr("強制說這一句話題(不看條件,跟測試者面板的強制說話一樣)。")
	play_button.pressed.connect(func() -> void:
		if _pet == null or not is_instance_valid(_pet):
			return
		_pet.logic.play_topic(int(entry["topic_index"]))
		_status.text = tr("強制說話題:%s") % str(entry.get("label", "")))
	box.add_child(play_button)
	var remove_button := ManagerUi.button(tr("移除"))
	remove_button.tooltip_text = tr("從話題文本移除這一句(按兩次確定),會寫回積木檔與桌寵設定。")
	var armed := [false]
	remove_button.pressed.connect(func() -> void:
		if _pet == null or not is_instance_valid(_pet):
			return
		if not armed[0]:
			armed[0] = true
			remove_button.text = tr("確定移除")
			return
		if _pet.logic.remove_topic(int(entry["topic_index"])):
			_save_user_layer()
			PetProfile.save_pet(_pet)
			_status.text = tr("已移除話題:%s") % str(entry.get("label", ""))
		_refresh())
	box.add_child(remove_button)
	return box

