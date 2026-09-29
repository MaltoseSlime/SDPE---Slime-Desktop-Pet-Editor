class_name CharacterLibraryWindow
extends FloatingWindow
## 角色庫(v1):列出專案 sprite 資料夾(見 SpriteLibrary)裡所有角色,每個一張卡片:idle 第一幀的縮圖(統一大小、整體置中)、名稱、動作數與幀數。
## 按鈕:放上桌面、外觀編輯(開精靈圖編輯器)、桌寵管理(不放上桌面就能改數值/狀態鏡/性格/交互行為,見 DesktopShell._open_character_settings 與 Pet.ghost_edit)。
## 工具列:新建角色(取名字後直接開編輯器)、從資料夾匯入、開啟資料夾位置、重新整理、搜尋。
## 縮圖一張一張慢慢補(每個影格一張),角色很多時視窗也不會卡住;縮圖有快取(見 CharacterThumbnail)。視窗重新取得焦點時自動重新整理(編輯器改完回來就看得到)。
## 角色管理:改名、複製、刪除(搬到備份);分享:每張卡片的「⋯」可以「匯出 .pet…」(素材包 + 角色設定 + 積木檔,記憶與戰績要自己勾才會放進去),工具列「匯入 .pet…」把別人的分享包變成新角色(見 PetPackage,匯入時逐項驗證,撞辨識代號會存成獨立的新角色)。

signal place_requested(folder: String)
signal edit_requested(folder: String)
signal settings_requested(folder: String)

const CARD_WIDTH := 132.0

var _flow: HFlowContainer
var _search: LineEdit
var _count_label: Label
var _status: Label
var _folders: Array[String] = []
var _summaries: Dictionary = {}
var _build_serial := 0
var _ready_once := false
## 勾選要一起放上桌面的角色(資料夾路徑 → true),重新整理後還記得。
var _checked: Dictionary = {}
var _place_selected: Button
var _clear_checks: Button


func setup() -> void:
	setup_floating("角色庫", Vector2i(860, 640), Vector2i(560, 420))
	# 第一次開角色庫時裝進預設角色(Mal);裝過就不再動。
	SpriteLibrary.ensure_default_characters()
	_build()
	refresh()
	focus_entered.connect(func() -> void:
		if _ready_once:
			refresh())
	_ready_once = true


func _build() -> void:
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	background.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)

	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	var create := ManagerUi.button("＋ 新建角色…")
	create.tooltip_text = "取一個名字(同時是資料夾名、角色名稱與預設辨識代號),建立空的角色並開啟精靈圖編輯器。"
	create.pressed.connect(_on_create_pressed)
	var import := ManagerUi.button("從資料夾匯入…")
	import.tooltip_text = "選一個外面的素材包資料夾,複製一份進角色庫(原資料夾不動)。"
	import.pressed.connect(_on_import_pressed)
	var import_pet := ManagerUi.button("匯入 .pet…")
	import_pet.tooltip_text = "匯入別人分享的角色分享包(.pet):素材、設定與積木檔會存成角色庫裡的新角色,不會覆蓋現有的角色。匯入前會逐項檢查檔案,不安全的包會被拒絕。"
	import_pet.pressed.connect(_on_import_pet_pressed)
	var backups := ManagerUi.button("🗄 備份資料夾")
	backups.tooltip_text = "刪除的角色會搬到這裡(不會真的刪掉)。"
	backups.pressed.connect(func() -> void: OS.shell_open(SpriteLibrary.backup_root_dir()))
	var reveal := ManagerUi.button("📁 開啟資料夾位置")
	reveal.pressed.connect(func() -> void: OS.shell_open(SpriteLibrary.root_dir()))
	var reload := ManagerUi.button("↻ 重新整理")
	reload.pressed.connect(refresh)
	_search = ManagerUi.line_edit("搜尋角色名稱")
	_search.custom_minimum_size.x = 200.0
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	_place_selected = ManagerUi.button("放上桌面(勾選 0 隻)")
	_place_selected.tooltip_text = "把卡片上勾選的角色一次全部放上桌面,一起活動(同一個角色也可以再放第二隻)。"
	_place_selected.disabled = true
	_place_selected.pressed.connect(place_selected)
	_clear_checks = ManagerUi.button("清除勾選")
	_clear_checks.disabled = true
	_clear_checks.pressed.connect(clear_checks)
	for control in [create, import, import_pet, reveal, backups, reload, _search, VSeparator.new(), _place_selected, _clear_checks]:
		bar.add_child(control)
	page.add_child(bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 10)
	_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_flow)

	var footer := HBoxContainer.new()
	_count_label = Label.new()
	_count_label.theme_type_variation = AppSettings.MUTED_LABEL
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_count_label)
	_status = Label.new()
	_status.theme_type_variation = AppSettings.WARN_LABEL
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_status)
	page.add_child(footer)


## 重新掃描 sprite 資料夾並重排卡片(依搜尋字過濾);縮圖之後一張一張補上。
func refresh() -> void:
	_build_serial += 1
	var serial := _build_serial
	for child in _flow.get_children():
		child.queue_free()
	_folders = SpriteLibrary.list_packs()
	var wanted := _search.text.strip_edges().to_lower() if _search != null else ""
	var shown: Array[Dictionary] = []
	for folder in _folders:
		if not _summaries.has(folder):
			_summaries[folder] = CharacterThumbnail.summarize(folder)
		var summary: Dictionary = _summaries[folder]
		if wanted == "" or str(summary["name"]).to_lower().contains(wanted) or folder.get_file().to_lower().contains(wanted):
			shown.append(summary)
	# 資料夾被刪掉、換掉的摘要別留著
	for stale: String in _summaries.keys():
		if not _folders.has(stale):
			_summaries.erase(stale)
	for stale: String in _checked.keys():
		if not _folders.has(stale):
			_checked.erase(stale)
	var cards: Array[Dictionary] = []
	for summary in shown:
		cards.append(_add_card(summary))
	_count_label.text = tr("共 %d 個角色%s。角色放在:%s") % [_folders.size(), tr("(顯示 %d 個)") % shown.size() if wanted != "" else "", SpriteLibrary.root_dir()]
	if _folders.is_empty():
		var empty := Label.new()
		empty.text = "角色庫還是空的。\n按「＋ 新建角色…」從空白開始,或「從資料夾匯入…」把現有的素材包放進來。"
		empty.theme_type_variation = AppSettings.MUTED_LABEL
		_flow.add_child(empty)
	# 縮圖:每個影格補一張
	for card in cards:
		await get_tree().process_frame
		if serial != _build_serial or not is_inside_tree():
			return
		fill_thumbnail(card)


## 一張角色卡片:{summary, holder(TextureRect), state(Label)}。
func _add_card(summary: Dictionary) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = AppSettings.ink(0.06)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8.0)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0.28)
	frame_style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.custom_minimum_size = Vector2(CharacterThumbnail.CELL, CharacterThumbnail.CELL)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var holder := TextureRect.new()
	holder.custom_minimum_size = Vector2(CharacterThumbnail.CELL, CharacterThumbnail.CELL)
	holder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	holder.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(holder)
	box.add_child(frame)
	var name_label := Label.new()
	name_label.text = str(summary["name"])
	name_label.tooltip_text = "%s\n%s" % [summary["name"], summary["folder"]]
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size.x = CARD_WIDTH - 16.0
	box.add_child(name_label)
	var state := Label.new()
	state.theme_type_variation = AppSettings.MUTED_LABEL
	state.add_theme_font_size_override("font_size", 12)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.text = tr("%d 個動作 · %d 幀") % [summary["actions"], summary["frames"]] if bool(summary["ok"]) else "(讀不出素材)"
	if not bool(summary["ok"]):
		state.tooltip_text = str(summary["error"])
	box.add_child(state)
	var pick := CheckBox.new()
	pick.text = "勾選(一起放上桌面)"
	pick.add_theme_font_size_override("font_size", 12)
	pick.disabled = not bool(summary["ok"])
	pick.button_pressed = _checked.has(str(summary["folder"]))
	pick.toggled.connect(func(on: bool) -> void: set_checked(str(summary["folder"]), on))
	box.add_child(pick)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var place := ManagerUi.button("放上桌面")
	place.disabled = not bool(summary["ok"])
	place.pressed.connect(func() -> void:
		place_requested.emit(str(summary["folder"]))
		_status.text = tr("已把「%s」放上桌面。") % summary["name"])
	var edit := ManagerUi.button("外觀編輯")
	edit.tooltip_text = "開精靈圖編輯器:改貼圖、動作、光源、家具/道具貼圖等造型相關內容。"
	edit.pressed.connect(func() -> void: edit_requested.emit(str(summary["folder"])))
	var settings := ManagerUi.button("桌寵管理")
	settings.tooltip_text = "不用放上桌面就能改數值、狀態鏡、性格、介面與自動行為、交互行為(自動建一隻隱藏的臨時實例,關視窗就存回去)。"
	settings.pressed.connect(func() -> void: settings_requested.emit(str(summary["folder"])))
	buttons.add_child(place)
	buttons.add_child(edit)
	buttons.add_child(settings)
	var more := MenuButton.new()
	more.text = "⋯"
	more.tooltip_text = "改名、複製、匯出 .pet、刪除(刪除是搬到備份資料夾)"
	var popup := more.get_popup()
	popup.add_item("重新命名…", 0)
	popup.add_item("複製成新角色…", 1)
	popup.add_item("匯出 .pet…", 3)
	popup.add_separator()
	popup.add_item("刪除(搬到備份)…", 2)
	popup.id_pressed.connect(_on_card_menu.bind(str(summary["folder"]), str(summary["name"])))
	buttons.add_child(more)
	box.add_child(buttons)
	_flow.add_child(card)
	return {"summary": summary, "holder": holder, "state": state}


## 勾選 / 取消勾選一個角色(資料夾路徑)。
func set_checked(folder: String, on: bool) -> void:
	if on:
		_checked[folder] = true
	else:
		_checked.erase(folder)
	_update_check_buttons()


func checked_folders() -> Array[String]:
	var result: Array[String] = []
	for folder: String in _folders:
		if _checked.has(folder):
			result.append(folder)
	return result


func clear_checks() -> void:
	_checked.clear()
	_update_check_buttons()
	for card in _flow.get_children():
		for box in card.find_children("*", "CheckBox", true, false):
			(box as CheckBox).set_pressed_no_signal(false)


func _update_check_buttons() -> void:
	var count := checked_folders().size()
	if _place_selected != null:
		_place_selected.text = tr("放上桌面(勾選 %d 隻)") % count
		_place_selected.disabled = count == 0
		_clear_checks.disabled = count == 0


## 把勾選的角色全部放上桌面(依角色庫的排列順序);回傳放了幾隻。
func place_selected() -> int:
	var folders := checked_folders()
	for folder in folders:
		place_requested.emit(folder)
	_status.text = tr("已把勾選的 %d 隻角色放上桌面。") % folders.size()
	return folders.size()


## 補上一張卡片的縮圖(有快取就讀快取)。
func fill_thumbnail(card: Dictionary) -> void:
	var holder: TextureRect = card["holder"]
	if not is_instance_valid(holder):
		return
	holder.texture = CharacterThumbnail.texture_for(card["summary"])
	if holder.texture == null and bool((card["summary"] as Dictionary)["ok"]):
		(card["state"] as Label).text += "(沒有可預覽的圖)"


# --- 改名 / 複製 / 刪除 ---

func _on_card_menu(id: int, folder: String, character_name: String) -> void:
	match id:
		0:
			ask_rename(folder, character_name)
		1:
			ask_copy(folder, character_name)
		2:
			ask_delete(folder, character_name)
		3:
			ask_export(folder, character_name)


## 這個角色資料夾現在有沒有被用著(桌面上有用它生成的桌寵、或精靈圖編輯器開著它);有的話回原因,沒有回空字串。
func in_use_reason(folder: String) -> String:
	var normalized := folder.replace("\\", "/").trim_suffix("/")
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		var entry: Variant = pet.get_meta("roster", {})
		if entry is Dictionary and str(entry.get("path", "")).replace("\\", "/").trim_suffix("/") == normalized:
			return "桌面上還有一隻用它生成的桌寵,請先在系統匣把它移除"
	for window: Node in get_tree().get_nodes_in_group("floating_windows"):
		if window is PackEditorWindow and (window as PackEditorWindow)._model.has_pack() and (window as PackEditorWindow)._model.root.replace("\\", "/").trim_suffix("/") == normalized:
			return "精靈圖編輯器正開著它,請先關掉編輯器(或切到別的角色)"
	return ""


## 精靈圖編輯器存檔某個素材包之後呼叫(見 DesktopShell.open_pack_editor):這裡快取的縮圖/動作數摘要可能已經過期,丟掉重算並立刻重排卡片。
## 沒快取過(這張卡片根本沒被看過)就什麼都不用做。
func invalidate(folder: String) -> void:
	var normalized := folder.replace("\\", "/").trim_suffix("/")
	if _summaries.erase(normalized):
		refresh()


func ask_rename(folder: String, current_name: String) -> void:
	var reason := in_use_reason(folder)
	if reason != "":
		_status.text = tr("不能改名:%s。") % reason
		return
	ManagerUi.ask_name(self, "重新命名", "新的名字(角色名稱與資料夾名一起改;辨識代號不變,設定檔與積木檔還是接得上):", current_name, "改名",
			func(text: String) -> String: return SpriteLibrary.name_problem(text),
			func(chosen: String) -> void: rename_character(folder, chosen))


## 改名。回傳錯誤文字(空字串 = 成功)。
func rename_character(folder: String, new_name: String) -> String:
	var reason := in_use_reason(folder)
	if reason != "":
		_status.text = tr("不能改名:%s。") % reason
		return reason
	var result := SpriteLibrary.rename_pack(folder, new_name)
	if not bool(result["ok"]):
		_status.text = tr("改名失敗:%s") % result["error"]
		return str(result["error"])
	_summaries.erase(folder)
	refresh()
	_status.text = tr("已改名為「%s」。") % new_name.strip_edges()
	return ""


func ask_copy(folder: String, current_name: String) -> void:
	ManagerUi.ask_name(self, "複製成新角色", "新角色的名字(整個素材包複製一份;新角色有自己的辨識代號,不帶原角色的設定與記憶):", tr("%s 副本") % current_name, "複製",
			func(text: String) -> String: return SpriteLibrary.name_problem(text),
			func(chosen: String) -> void: copy_character(folder, chosen))


func copy_character(folder: String, new_name: String) -> String:
	var result := SpriteLibrary.copy_pack(folder, new_name)
	if not bool(result["ok"]):
		_status.text = tr("複製失敗:%s") % result["error"]
		return str(result["error"])
	refresh()
	_status.text = tr("已複製成「%s」。") % new_name.strip_edges()
	return ""


func ask_delete(folder: String, character_name: String) -> void:
	var reason := in_use_reason(folder)
	if reason != "":
		_status.text = tr("不能刪除:%s。") % reason
		return
	var related := SpriteLibrary.related_files(folder)
	var dialog := ConfirmationDialog.new()
	dialog.title = "刪除角色"
	dialog.ok_button_text = "搬到備份"
	dialog.cancel_button_text = "取消"
	# 不設 always_on_top:這種視窗會被 Godot 設成這個(可能置頂的)浮動視窗的 transient 子視窗,跟置頂在
	# Windows 原生視窗上互斥(godotengine/godot#117698,4.7.2 尚未修正),硬設會把視窗卡死到連工作列都找不到
	# (2026-09-30 使用者實機回報)。身為 owned window,Windows 本來就會自動疊在浮動視窗上面,不需要自己也置頂。
	dialog.theme = ManagerUi.make_theme()
	dialog.dialog_text = tr("要把「%s」從角色庫移走嗎?\n\n整個素材包資料夾會搬到備份資料夾(不會真的刪掉)%s。之後想找回來,到備份資料夾把它搬回 sprite 資料夾就好。") % [character_name,
			tr("，另外把它的 %d 個設定檔(角色設定、狀態、積木檔)複製一份進同一個備份") % related.size() if not related.is_empty() else ""]
	dialog.confirmed.connect(func() -> void: delete_character(folder, character_name))
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	FloatingWindow.popup_child_dialog(self, get_window(), dialog)


## 刪除(搬到備份)。回傳錯誤文字(空字串 = 成功)。
func delete_character(folder: String, character_name := "") -> String:
	var reason := in_use_reason(folder)
	if reason != "":
		_status.text = tr("不能刪除:%s。") % reason
		return reason
	var result := SpriteLibrary.delete_pack(folder)
	if not bool(result["ok"]):
		_status.text = tr("刪除失敗:%s") % result["error"]
		return str(result["error"])
	_summaries.erase(folder)
	refresh()
	_status.text = tr("已把「%s」搬到備份:%s") % [character_name if character_name != "" else folder.get_file(), result["backup"]]
	return ""


# --- 新建 / 匯入 ---

## 新建角色:先選模板(活動桌寵 / 靜止桌寵)再取名字。模板決定 pack.json 的 kind:靜止桌寵放到桌面時固定貼在行動區底部、會呼吸、可以拖曳。
func _on_create_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("新建角色")
	dialog.ok_button_text = tr("新建")
	dialog.cancel_button_text = tr("取消")
	# 不設 always_on_top,見 ask_delete() 的說明(跟置頂衝突,會把視窗卡死)。
	dialog.theme = ManagerUi.make_theme()
	var box := VBoxContainer.new()
	var group := ButtonGroup.new()
	var kind_buttons := {}
	for entry: Array in [["active", "活動桌寵", "會在行動區裡走動、跳躍、睡覺。適合有 spritesheet(行走圖)的角色。"], ["still", "靜止桌寵", "固定貼在行動區底部、會呼吸、可以拖曳。適合有固定立繪,或想從單張角色圖開始發展的情形。"]]:
		var button := CheckBox.new()
		button.button_group = group
		button.text = tr(str(entry[1]))
		button.button_pressed = str(entry[0]) == "active"
		kind_buttons[str(entry[0])] = button
		box.add_child(button)
		var hint := Label.new()
		hint.text = tr(str(entry[2]))
		hint.theme_type_variation = AppSettings.MUTED_LABEL
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 420.0
		box.add_child(hint)
	var label := Label.new()
	label.text = tr("幫這個角色取個名字(同時是資料夾名、角色名稱與預設辨識代號,之後可以改 pack.json):")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420.0
	box.add_child(label)
	var edit := ManagerUi.line_edit("名稱")
	edit.max_length = 40
	box.add_child(edit)
	var problem := Label.new()
	problem.theme_type_variation = AppSettings.WARN_LABEL
	box.add_child(problem)
	dialog.add_child(box)
	var validate := func(text: String) -> void:
		var reason := SpriteLibrary.name_problem(text.strip_edges())
		problem.text = reason
		dialog.get_ok_button().disabled = reason != ""
	edit.text_changed.connect(validate)
	dialog.confirmed.connect(func() -> void:
		var kind := "still" if (kind_buttons["still"] as CheckBox).button_pressed else "active"
		create_character(edit.text.strip_edges(), kind))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	validate.call(edit.text)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(480, 380))
		edit.grab_focus()


## 新建空的角色資料夾並開精靈圖編輯器。kind:active(活動桌寵)/ still(靜止桌寵)。回傳錯誤文字(空字串 = 成功)。
func create_character(character_name: String, kind := "active") -> String:
	var created := SpriteLibrary.create_pack(character_name, kind)
	if not bool(created["ok"]):
		_status.text = tr("新建失敗:%s") % created["error"]
		return str(created["error"])
	refresh()
	edit_requested.emit(str(created["folder"]))
	_status.text = tr("已新建「%s」,接著在精靈圖編輯器匯入圖片。") % character_name.strip_edges()
	return ""


func _on_import_pressed() -> void:
	FloatingWindow.native_file_dialog("選擇要匯入的素材包資料夾", SpriteLibrary.root_dir(), DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(),
			func(paths: PackedStringArray) -> void: _ask_import_name(str(paths[0])), get_window_id())


func _ask_import_name(source: String) -> void:
	if SpriteLibrary.is_inside(source):
		_status.text = "這個資料夾已經在角色庫裡了。"
		return
	ManagerUi.ask_name(self, "匯入資料夾", "會把這個資料夾複製一份進角色庫(原資料夾不動)。\n幫這個角色取個名字(同時是資料夾名、角色名稱與預設辨識代號):", source.get_file(), "匯入",
			func(text: String) -> String: return SpriteLibrary.name_problem(text),
			func(chosen: String) -> void: import_character(source, chosen))


## 從外面的資料夾複製一份進角色庫。回傳錯誤文字(空字串 = 成功)。
func import_character(source: String, character_name: String) -> String:
	var imported := SpriteLibrary.import_folder(source, character_name)
	if not bool(imported["ok"]):
		_status.text = tr("匯入失敗:%s") % imported["error"]
		return str(imported["error"])
	refresh()
	_status.text = tr("已把「%s」複製進角色庫。") % character_name.strip_edges()
	return ""


# --- 分享包(.pet)---

## 匯出:問要不要放積木檔、記憶與戰績,再選存檔位置。
func ask_export(folder: String, character_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "匯出 .pet"
	dialog.ok_button_text = "選擇存檔位置…"
	dialog.cancel_button_text = "取消"
	# 不設 always_on_top,見 ask_delete() 的說明(跟置頂衝突,會把視窗卡死)。
	dialog.theme = ManagerUi.make_theme()
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = tr("把「%s」打包成一個 .pet 檔:素材包與角色設定(數值定義、狀態鏡、性格、介面風格…)一定會放進去。") % character_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 440.0
	box.add_child(label)
	var logic_check := CheckBox.new()
	logic_check.text = "包含導入過的積木檔(事件與對話)"
	logic_check.button_pressed = true
	box.add_child(logic_check)
	var state_check := CheckBox.new()
	state_check.text = "包含記憶與戰績(數值目前的值、記過的東西;分享給別人通常不要勾)"
	state_check.button_pressed = false
	box.add_child(state_check)
	dialog.add_child(box)
	dialog.confirmed.connect(func() -> void:
		var options := {"include_logic": logic_check.button_pressed, "include_state": state_check.button_pressed}
		FloatingWindow.native_file_dialog("匯出角色分享包", SpriteLibrary.root_dir(), DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(["*.pet;角色分享包"]),
				func(paths: PackedStringArray) -> void: export_character(folder, str(paths[0]), options), get_window_id(), PetPackage.suggested_name(folder)))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	FloatingWindow.popup_child_dialog(self, get_window(), dialog)


## 匯出成 .pet。桌面上有用這個角色生成的桌寵時,先把它目前的設定(與狀態)存起來,匯出的才是最新的。回傳錯誤文字(空字串 = 成功)。
func export_character(folder: String, out_path: String, options := {}) -> String:
	var normalized := folder.replace("\\", "/").trim_suffix("/")
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		var entry: Variant = pet.get_meta("roster", {})
		if entry is Dictionary and str(entry.get("path", "")).replace("\\", "/").trim_suffix("/") == normalized:
			PetProfile.save_pet(pet)
			PetProfile.save_state(pet)
			break
	var report := PetPackage.export_package(folder, out_path, options)
	if not bool(report["ok"]):
		_status.text = tr("匯出失敗:%s") % report["error"]
		return str(report["error"])
	var skipped: Array = report["skipped"]
	_status.text = tr("已匯出 %d 個檔案(%.1f MB)到 %s%s") % [report["files"], float(report["bytes"]) / 1_000_000.0, out_path.get_file(), tr(",略過 %d 個不收的檔案") % skipped.size() if not skipped.is_empty() else ""]
	return ""


func _on_import_pet_pressed() -> void:
	FloatingWindow.native_file_dialog("選擇要匯入的角色分享包", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.pet;角色分享包"]),
			func(paths: PackedStringArray) -> void: ask_import_pet(str(paths[0])), get_window_id())


## 匯入前先檢查、告訴使用者裡面有什麼,再問要用什麼名字存成新角色。
func ask_import_pet(path: String) -> void:
	var info := PetPackage.inspect(path)
	if not bool(info["ok"]):
		_status.text = tr("這個檔案不能匯入:%s") % info["error"]
		return
	var manifest: Dictionary = info["manifest"]
	var same := PetPackage.folder_with_tag(str(manifest["tag"]))
	var default_name := str(manifest["name"]) if str(manifest["name"]) != "" else path.get_file().get_basename()
	if same != "" or DirAccess.dir_exists_absolute(SpriteLibrary.root_dir().path_join(SpriteLibrary.folder_name_for(default_name))):
		default_name = tr("%s (匯入)") % default_name
	var contents: Array[String] = [tr("%d 個素材檔") % info["files"]]
	contents.append(tr("角色設定") if bool(info["has_profile"]) else tr("沒有角色設定"))
	if bool(info["has_logic"]):
		contents.append(tr("積木檔"))
	if bool(info["has_state"]):
		contents.append(tr("記憶與戰績"))
	var message := tr("分享包「%s」(辨識代號 %s):%s,共 %.1f MB。\n會存成角色庫裡的新角色,不會覆蓋現有的角色。%s\n幫它取個名字:") % [manifest["name"], manifest["tag"], "、".join(contents), float(info["bytes"]) / 1_000_000.0,
			tr("角色庫裡已經有辨識代號相同的角色「%s」,這份會拿到新的辨識代號。") % same.get_file() if same != "" else ""]
	ManagerUi.ask_name(self, "匯入角色分享包", message, default_name, "匯入",
			func(text: String) -> String: return SpriteLibrary.name_problem(text),
			func(chosen: String) -> void: import_pet(path, chosen))


## 匯入 .pet。回傳錯誤文字(空字串 = 成功)。
func import_pet(path: String, character_name: String) -> String:
	var result := PetPackage.import_package(path, character_name, {"include_state": true})
	if not bool(result["ok"]):
		_status.text = tr("匯入失敗:%s") % result["error"]
		return str(result["error"])
	refresh()
	_status.text = tr("已匯入「%s」%s。") % [result["name"], tr("(辨識代號改成 %s)") % result["tag"] if bool(result["tag_changed"]) else ""]
	return ""

# --- 給測試看的 ---

func card_count() -> int:
	return _flow.get_child_count()


func shown_names() -> Array[String]:
	var names: Array[String] = []
	for child in _flow.get_children():
		if child is PanelContainer:
			var label := _find_label(child)
			if label != null:
				names.append(label.text)
	return names


func _find_label(node: Node) -> Label:
	for child in node.get_children():
		if child is Label and (child as Label).tooltip_text.contains("\n"):
			return child
		var deeper := _find_label(child)
		if deeper != null:
			return deeper
	return null
