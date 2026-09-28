class_name PersonalityTab
extends HSplitContainer
## 性格分頁:左邊是「性格與參數」(五個區塊各有下拉選單,可以混搭,每個區塊下面說明「這個性格在這個區塊會怎樣」;再下面是這隻桌寵所有參數的可填式方塊),
## 右邊是「套用預覽」(顯示每個區塊會發生什麼、所有參數的目前值,以及套用後的值),套用、取消、編輯、匯入、匯出的按鈕與選項放在右上角。
## 套用前有預覽;不會蓋掉你自己的內容(規則見 PersonalityApplier);可以匯入自訂性格、把目前的設定匯出成性格檔、用性格編輯器改性格的內容。
## 套用後立刻生效並標成「有未儲存的變更」,按管理視窗的「儲存」才寫進桌寵設定(關掉視窗選「不儲存」會還原)。

signal changed
signal message(text: String)

const NONE_ID := ""

var _pet: Node
var _all_option: OptionButton
var _section_options: Dictionary = {}
var _section_state: Dictionary = {}
var _section_desc: Dictionary = {}
var _ignore_chat: CheckBox
var _ignore_reactions: CheckBox
var _overwrite_params: CheckBox
var _preview: TextEdit
var _vitality_label: Label
var _keyword_edit: TextEdit
var _keyword_count: Label
var _user_keyword_edit: TextEdit
var _user_keyword_count: Label
var _params_panel: PersonalityParamsPanel
var _mood_lens_lists: Dictionary = {}   # true = 心情高、false = 心情低 → ItemList(可複選)
var _personalities: Array[Dictionary] = []
var _updating := false


func _ready() -> void:
	name = "性格"
	_build_left()
	_build_right()


# --- 左邊:性格與參數 ---

func _build_left() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 320.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	scroll.add_child(side)
	side.add_child(ManagerUi.heading("性格"))
	side.add_child(ManagerUi.syntax_row(self, "台詞能用的語法", "性格的台詞可以用氣泡樣式、數值、名字標記與單字池。點右邊的「語法字典」查所有語法並複製;要寫台詞請用「編輯性格…」。", false))
	side.add_child(ManagerUi.hint_row("選一個性格,五個區塊可以各自混搭", "選一個性格,桌寵就會有那個性格的行動節奏、閒聊與各種反應。五個區塊可以各自選不同的性格。你自己寫的積木、改過的設定不會被蓋掉。每隻角色都帶著自己的一份性格副本(套用時複製):在性格編輯器改「這隻角色的版本」只影響這一隻,共用的性格檔不會被動到。"))

	_vitality_label = Label.new()
	_vitality_label.theme_type_variation = AppSettings.MUTED_LABEL
	# 見 ManagerUi.hint_row() 旁的說明:換行 Label 沒給 custom_minimum_size.x 會被估出離譜的高度。
	# 這顆一開始是空字串(還沒選桌寵)所以蓋的時候看不出問題,選了桌寵、稍後填進文字才會炸。
	_vitality_label.custom_minimum_size.x = 220.0
	_vitality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vitality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_vitality_label)

	var all_row := HBoxContainer.new()
	var all_label := Label.new()
	all_label.text = "整組選同一個:"
	# 換行 Label 要給個 custom_minimum_size.x 當換行估算的底線寬度,不然會被估出離譜的高度、
	# 整個左側欄位被吃掉(見 ManagerUi.hint_row() 旁的說明,這裡是同一個坑)。
	all_label.custom_minimum_size.x = 120.0
	all_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	all_row.add_child(all_label)
	_all_option = OptionButton.new()
	_all_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_all_option.item_selected.connect(_on_all_selected)
	all_row.add_child(_all_option)
	side.add_child(all_row)
	side.add_child(HSeparator.new())

	for section: String in PersonalityApplier.SECTIONS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = PersonalityApplier.SECTION_NAMES[section]
		label.custom_minimum_size.x = 84.0
		# 固定寬度的標籤(跟後面的下拉選單排一列):翻成英文可能比 84px 塞得下的還長(例如「數值定義」→
		# 「Value Definitions」),不截斷/裁切的話會硬撐開整條 row、連帶撐寬整個左側欄位。裁切 + 滑過看完整文字,
		# 不佔額外版面(2026-09-29 使用者實機回報,英文模式下左側欄位被撐得過寬)。
		label.clip_text = true
		label.tooltip_text = label.text
		row.add_child(label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.item_selected.connect(func(_i: int) -> void: _refresh_preview())
		row.add_child(option)
		side.add_child(row)
		var state_label := Label.new()
		state_label.theme_type_variation = AppSettings.MUTED_LABEL
		# 見 ManagerUi.hint_row() 旁的說明:換行 Label 沒給 custom_minimum_size.x 會被估出離譜的高度。
		# 這兩顆一開始是空字串所以蓋的時候看不出問題,選了桌寵、稍後填進文字才會炸。
		state_label.custom_minimum_size.x = 220.0
		state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(state_label)
		var description := Label.new()
		description.custom_minimum_size.x = 220.0
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(description)
		_section_options[section] = option
		_section_state[section] = state_label
		_section_desc[section] = description

	side.add_child(HSeparator.new())
	side.add_child(ManagerUi.heading_with_info("心情與狀態鏡", "心情偏高(超過「開心門檻」)或偏低(低於「生氣門檻」)時,桌寵會進入哪一個狀態鏡:在這裡指定(可以複選,每次要進入時從你勾的裡面隨機挑一個);一個都不勾就從有勾「可以被心情門檻叫出來」的正面 / 負面狀態鏡裡隨機挑一個。要不要被心情叫出來,在「狀態鏡」分頁每個狀態鏡的勾選項裡設定。心情門檻與起伏程度在下面的參數裡。"))
	for high: bool in [true, false]:
		side.add_child(ManagerUi.heading("心情高時" if high else "心情低時"))
		var mood_list := ItemList.new()
		mood_list.select_mode = ItemList.SELECT_MULTI
		mood_list.custom_minimum_size.y = 70.0
		mood_list.multi_selected.connect(func(_index: int, _selected: bool) -> void: _on_mood_lens_picked(high))
		side.add_child(mood_list)
		_mood_lens_lists[high] = mood_list
	side.add_child(HSeparator.new())
	_build_keywords(side)
	side.add_child(HSeparator.new())
	side.add_child(ManagerUi.heading_with_info("這隻桌寵的參數", "直接改下面的方塊,馬上套用在這隻桌寵身上(記得按「儲存」)。你改過的參數,之後換性格時預設會保留。每列右邊的 ↺ 回到預設值。滑過名稱看完整說明。"))
	_params_panel = PersonalityParamsPanel.new()
	_params_panel.value_changed.connect(_on_param_edited)
	side.add_child(_params_panel)


## 關鍵詞庫小板塊:這隻角色會想或提及的事物,一行一個。台詞裡的 {keyword}(隨機一個)與 {kw:1}~{kw:9}(這個事件洗牌後的第幾個,彼此不同)會用到它。
func _build_keywords(side: VBoxContainer) -> void:
	side.add_child(ManagerUi.heading_with_info("關鍵詞庫", tr("簡單地告訴桌寵「你會想到、提到哪些事物」,一行一個(最多 %d 個、每個最多 %d 字)。台詞裡寫 {keyword} 就會隨機換成其中一個,例如「%s似乎在想關於 {keyword} 的事情」「你知道關於 {keyword} 的事嗎?」「oO(有點想念 {keyword} 呀…)」;{kw:1}、{kw:2}… 是同一個事件裡各不相同的幾個,適合做「猜猜我現在最想要什麼?」這種四個選項都是答案的題目。庫是空的就用預設詞(可以寫 {keyword|某件事} 自訂)。改了立刻生效,記得按「儲存」。") % [PetText.MAX_KEYWORDS, PetText.MAX_KEYWORD_LENGTH, "{self}"]))
	side.add_child(ManagerUi.syntax_row(self, "台詞裡怎麼用:{keyword}、{kw:1}", "{keyword} = 隨機一個;{keyword|某件事} = 庫是空的時顯示「某件事」;{kw:1}~{kw:9} = 這個事件洗牌後的第 N 個(1、2、3、4 各不相同)。點右邊的「語法字典」看全部語法。", false))
	side.add_child(_hint("▍桌寵有興趣的關鍵詞(桌寵向你學到的新知識也會記在這裡)"))
	_keyword_edit = TextEdit.new()
	_keyword_edit.custom_minimum_size.y = 96.0
	_keyword_edit.placeholder_text = tr("一行一個關鍵詞,例如:\n晚餐\n星星\n下雨天")
	_keyword_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_keyword_edit.text_changed.connect(_on_keywords_edited)
	side.add_child(_keyword_edit)
	var row := HBoxContainer.new()
	_keyword_count = Label.new()
	_keyword_count.theme_type_variation = AppSettings.MUTED_LABEL
	_keyword_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_keyword_count)
	var suggest := ManagerUi.button("加入建議詞")
	suggest.tooltip_text = "把一組常見的話題(晚餐、星星、天氣…)加進來,已經有的不會重複;不喜歡的自己刪掉。"
	suggest.pressed.connect(_add_suggested_keywords)
	row.add_child(suggest)
	var clear := ManagerUi.button("清空")
	clear.pressed.connect(func() -> void:
		_keyword_edit.text = ""
		_on_keywords_edited())
	row.add_child(clear)
	side.add_child(row)
	# 第二份:使用者有興趣的關鍵詞。台詞裡用 {keyword:user} / {kw:user:1};桌寵「想更了解你」問到的也會記在這裡。
	side.add_child(_hint("▍使用者有興趣的關鍵詞(桌寵想更了解你時問到的會記在這裡;台詞裡用 {keyword:user}、{kw:user:1})"))
	_user_keyword_edit = TextEdit.new()
	_user_keyword_edit.custom_minimum_size.y = 96.0
	_user_keyword_edit.placeholder_text = tr("一行一個,例如:\n貓咪\n爵士樂\n登山")
	_user_keyword_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_user_keyword_edit.text_changed.connect(_on_user_keywords_edited)
	side.add_child(_user_keyword_edit)
	var user_row := HBoxContainer.new()
	_user_keyword_count = Label.new()
	_user_keyword_count.theme_type_variation = AppSettings.MUTED_LABEL
	_user_keyword_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_row.add_child(_user_keyword_count)
	var user_clear := ManagerUi.button("清空")
	user_clear.pressed.connect(func() -> void:
		_user_keyword_edit.text = ""
		_on_user_keywords_edited())
	user_row.add_child(user_clear)
	side.add_child(user_row)


const SUGGESTED_KEYWORDS: Array[String] = ["晚餐", "星星", "天氣", "下雨天", "零食", "午睡", "夕陽", "音樂", "冒險", "遠方的朋友"]


func _add_suggested_keywords() -> void:
	var merged := PetText.sanitize_keywords(_keyword_edit.text)
	for word in SUGGESTED_KEYWORDS:
		if not merged.has(word) and merged.size() < PetText.MAX_KEYWORDS:
			merged.append(word)
	_keyword_edit.text = "\n".join(merged)
	_on_keywords_edited()


## 使用者改了關鍵詞:整理後寫到這隻桌寵身上(輸入框的文字不重寫,免得打字時游標亂跳;超過上限或重複的下次載入才會被整理掉)。
func _on_keywords_edited() -> void:
	if _updating or _pet == null:
		return
	_pet.keywords = PetText.sanitize_keywords(_keyword_edit.text)
	_update_keyword_count()
	changed.emit()


## 使用者有興趣的關鍵詞被編輯:整理後寫到桌寵身上。
func _on_user_keywords_edited() -> void:
	if _updating or _pet == null:
		return
	_pet.user_keywords = PetText.sanitize_keywords(_user_keyword_edit.text)
	_update_keyword_count()
	changed.emit()


func _update_keyword_count() -> void:
	if _pet == null:
		return
	_keyword_count.text = tr("目前 %d / %d 個關鍵詞") % [_pet.keywords.size(), PetText.MAX_KEYWORDS]
	if _user_keyword_count != null:
		_user_keyword_count.text = tr("目前 %d / %d 個關鍵詞") % [_pet.user_keywords.size(), PetText.MAX_KEYWORDS]


func _load_keywords() -> void:
	if _pet == null or _keyword_edit == null:
		return
	var was_updating := _updating
	_updating = true
	_keyword_edit.text = "\n".join(_pet.keywords)
	if _user_keyword_edit != null:
		_user_keyword_edit.text = "\n".join(_pet.user_keywords)
	_updating = was_updating
	_update_keyword_count()


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	# 見 ManagerUi.hint_row() 旁的說明:換行 Label 沒給 custom_minimum_size.x 會被估出離譜的高度。
	label.custom_minimum_size.x = 220.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = AppSettings.MUTED_LABEL
	return label


# --- 右邊:套用預覽與按鈕 ---

func _build_right() -> void:
	# 右欄放在可捲動的容器裡:視窗窄的時候按鈕會換行、內容太高就捲動,不會被切掉。
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 240.0
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(right_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	right_scroll.add_child(side)
	side.add_child(ManagerUi.heading("套用預覽"))

	# 按鈕與選項:靠右、在「套用預覽」標題的右下方。
	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_END
	var apply := ManagerUi.button("套用")
	apply.pressed.connect(_apply)
	_apply_button = apply
	var clear := ManagerUi.button("取消所有性格(還原)")
	clear.tooltip_text = "參數還原成套用前的值、移除性格加入且沒被你改過的數值定義與狀態鏡、停用性格的事件;你自己的內容不動。"
	clear.pressed.connect(_clear_all)
	var edit := ManagerUi.button("編輯性格…")
	edit.tooltip_text = "打開性格編輯器,改這個性格的參數、閒聊台詞與反應台詞,存成自訂性格。改內建的預設性格會存成新的自訂性格,不會動到原檔。"
	edit.pressed.connect(_open_editor)
	var reset_copy := ManagerUi.button("重設此性格副本")
	reset_copy.tooltip_text = "每隻角色都帶著自己的一份性格(套用時複製的),在性格編輯器改「這隻角色的版本」只影響這一隻。這個按鈕丟掉改動、重新複製共用的原版。"
	reset_copy.pressed.connect(_reset_own_copy)
	var import := ManagerUi.button("匯入自訂性格…")
	import.pressed.connect(_import)
	var export := ManagerUi.button("匯出目前設定為性格檔…")
	export.tooltip_text = "把這隻的參數、數值定義、狀態鏡與你自己的閒聊/反應事件存成性格檔,可以分享或當備份。不含數值目前值、Flag、戰績。"
	export.pressed.connect(_export)
	for button in [apply, clear, edit, reset_copy, import, export]:
		buttons.add_child(button)
	side.add_child(buttons)
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 0)
	_ignore_chat = _check(options, "對話池:只用性格的(暫時停用我自己的閒聊事件;沒有刪除,取消勾選就恢復)")
	_ignore_reactions = _check(options, "反應事件:只用性格的(暫時停用我自己的反應類事件;沒有刪除,取消勾選就恢復)")
	_overwrite_params = _check(options, "參數:連我自己改過的也覆蓋(預設保留我改過的)")
	side.add_child(options)
	_preview = TextEdit.new()
	_preview.editable = false
	_preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_preview.custom_minimum_size.y = 200.0
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_preview)


## 下拉選單(或選項)選的和桌寵現在套用的不一樣 = 還沒按「套用」。這時「套用」鈕用強調色,管理視窗按「儲存」也會先提醒(見 ManagerWindow)。
var _apply_button: Button


func has_pending_apply() -> bool:
	if _pet == null or _section_options.is_empty():
		return false
	var wanted := _wanted()
	for section: String in PersonalityApplier.SECTIONS:
		if wanted.has(section) and str(wanted[section]) != PersonalityApplier.choice_of(_pet, section):
			return true
	var state := PersonalityApplier.state_of(_pet)
	return _ignore_chat.button_pressed != bool(state["ignore_own"].get("chat", false)) or _ignore_reactions.button_pressed != bool(state["ignore_own"].get("reactions", false))


## 套用鈕的外觀:有待套用的變更就換成強調色並加上「●」。
func _update_apply_button() -> void:
	if _apply_button == null:
		return
	var pending := has_pending_apply()
	_apply_button.text = "套用 ●" if pending else "套用"
	_apply_button.tooltip_text = "你選的性格還沒套用到這隻桌寵身上,按這裡套用。" if pending else "套用上面選的性格。"
	if pending:
		var accent: Color = AppSettings.appearance()["colors"]["accent"]
		for state_name in ["normal", "hover", "pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = accent if state_name != "hover" else accent.lightened(0.15)
			box.set_corner_radius_all(4)
			box.set_content_margin_all(6.0)
			_apply_button.add_theme_stylebox_override(state_name, box)
		_apply_button.add_theme_color_override("font_color", AppSettings.appearance()["colors"]["text"])   # 強調色上放的是文字色(白字在淺色配色的強調色上看不見)
	else:
		for state_name in ["normal", "hover", "pressed"]:
			_apply_button.remove_theme_stylebox_override(state_name)
		_apply_button.remove_theme_color_override("font_color")


func _check(parent: Control, text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.toggled.connect(func(_on: bool) -> void: _refresh_preview())
	parent.add_child(box)
	return box


func set_pet(pet: Node) -> void:
	_pet = pet
	_reload_options()
	var state := PersonalityApplier.state_of(pet)
	_updating = true
	_ignore_chat.button_pressed = bool(state["ignore_own"].get("chat", false))
	_ignore_reactions.button_pressed = bool(state["ignore_own"].get("reactions", false))
	_overwrite_params.button_pressed = false
	_updating = false
	_load_keywords()
	_reload_mood_lens_options()
	_refresh_preview()


## 心情高 / 低時的狀態鏡清單(可複選):列出這隻桌寵的正面 / 負面狀態鏡,勾起來的是使用者指定要進入的那幾個
## (一個都不勾 = 沒指定,由引擎在有勾「可以被心情門檻叫出來」的裡面隨機挑,見 PetVitality.pick_mood_lens)。
func _reload_mood_lens_options() -> void:
	if _pet == null:
		return
	_updating = true
	for high: bool in _mood_lens_lists:
		var list: ItemList = _mood_lens_lists[high]
		list.clear()
		var chosen := PersonalityApplier.mood_lens_choices(_pet, high)
		for lens: PetStateLens in _pet.state_lenses:
			if lens.has_nature("正面" if high else "負面") and lens.lens_name != PetVitality.TIRED_LENS:
				list.add_item(lens.lens_name)
				if chosen.has(lens.lens_name):
					list.select(list.item_count - 1, false)
	_updating = false


func _on_mood_lens_picked(high: bool) -> void:
	if _updating or _pet == null:
		return
	var list: ItemList = _mood_lens_lists[high]
	var names: Array[String] = []
	for index in list.get_selected_items():
		names.append(list.get_item_text(index))
	PersonalityApplier.set_mood_lens_choices(_pet, high, names)
	changed.emit()
	message.emit(tr("已改心情%s時的狀態鏡。記得按「儲存」。") % (tr("高") if high else tr("低")))


## 依目前有哪些性格(內建 + 自訂)重建所有下拉選單,選中桌寵目前的選擇。
func _reload_options() -> void:
	PersonalityFile.clear_cache()
	_personalities = PersonalityFile.list_all()
	_updating = true
	_all_option.clear()
	_all_option.add_item("(選一個,五個區塊一起設成它)")
	_all_option.set_item_metadata(0, NONE_ID)
	for section: String in PersonalityApplier.SECTIONS:
		var option: OptionButton = _section_options[section]
		option.clear()
		option.add_item("(不套用)")
		option.set_item_metadata(0, NONE_ID)
	for item in _personalities:
		var text := str(item["name"]) if item["builtin"] else tr("自訂:%s") % item["name"]
		_all_option.add_item(text)
		_all_option.set_item_metadata(_all_option.item_count - 1, item["id"])
		for section: String in PersonalityApplier.SECTIONS:
			var option: OptionButton = _section_options[section]
			option.add_item(text)
			option.set_item_metadata(option.item_count - 1, item["id"])
			option.set_item_tooltip(option.item_count - 1, str(item["description"]))
	if _pet != null:
		for section: String in PersonalityApplier.SECTIONS:
			_select_id(_section_options[section], PersonalityApplier.choice_of(_pet, section))
	_updating = false


func _select_id(option: OptionButton, id: String) -> void:
	for i in option.item_count:
		if str(option.get_item_metadata(i)) == id:
			option.select(i)
			return
	option.select(0)


func _on_all_selected(index: int) -> void:
	if _updating or index <= 0:
		return
	var id := str(_all_option.get_item_metadata(index))
	_updating = true
	for section: String in PersonalityApplier.SECTIONS:
		_select_id(_section_options[section], id)
	_all_option.select(0)
	_updating = false
	_refresh_preview()


func _wanted() -> Dictionary:
	var wanted := {}
	for section: String in PersonalityApplier.SECTIONS:
		var option: OptionButton = _section_options[section]
		wanted[section] = str(option.get_item_metadata(option.selected))
	return wanted


func _options() -> Dictionary:
	return {"overwrite_params": _overwrite_params.button_pressed, "ignore_own_chat": _ignore_chat.button_pressed, "ignore_own_reactions": _ignore_reactions.button_pressed}


func _refresh_preview() -> void:
	if _updating or _pet == null:
		return
	_update_apply_button()
	var wanted := _wanted()
	for section: String in PersonalityApplier.SECTIONS:
		var current := PersonalityApplier.choice_of(_pet, section)
		var label: Label = _section_state[section]
		label.text = tr("目前:%s") % _name_of(current) if current != "" else "目前:沒有套用"
		var chosen := str(wanted[section])
		var description: Label = _section_desc[section]
		description.text = ""
		if chosen != "":
			var chosen_personality := PersonalityApplier.personality_of(_pet, chosen)
			if not chosen_personality.is_empty():
				description.text = tr("選了「%s」%s→ %s") % [_name_of(chosen), "(這隻角色改過的版本)" if PersonalityApplier.is_edited(_pet, chosen) else "", PersonalityFile.section_description(chosen_personality, section, false)]
	_preview.text = preview_text(_pet, wanted, _options())
	_vitality_label.text = vitality_text(_pet)
	_sync_params()


## 參數方塊顯示桌寵目前的值(不發訊號)。
func _sync_params() -> void:
	if _pet == null:
		return
	var values := {}
	for key: String in PersonalityParams.keys():
		values[key] = PersonalityParams.get_value(_pet, key)
	_params_panel.set_values(values)


## 使用者在參數方塊改了一項:直接寫到這隻桌寵身上(之後換性格時,改過的預設會保留)。
func _on_param_edited(key: String, value: Variant) -> void:
	if _pet == null:
		return
	var normalized: Variant = PersonalityParams.normalize(key, PersonalityParams.to_json(value))
	if normalized == null:
		return
	PersonalityParams.set_value(_pet, key, normalized)
	changed.emit()
	message.emit(tr("已改「%s」:%s。記得按「儲存」。") % [PersonalityFile.short_label(key), PersonalityParams.to_text(normalized)])
	# 預覽跟著更新,但不重設方塊(使用者正在輸入)。
	var wanted := _wanted()
	_preview.text = preview_text(_pet, wanted, _options())
	_vitality_label.text = vitality_text(_pet)


func _name_of(id: String) -> String:
	for item in _personalities:
		if item["id"] == id:
			return str(item["name"])
	return id


## 目前的精力狀態(給使用者實機觀察疲勞機制有沒有在運作)。
static func vitality_text(pet: Node) -> String:
	var v: PetVitality = pet.vitality
	if v == null:
		return ""
	if not v.fatigue_enabled():
		return TranslationServer.translate("精力:疲勞機制目前關閉(套用有疲勞參數的性格才會累);社交意願 %s") % snappedf(pet.sociability, 0.01)
	var mode_text: String = {PetVitality.Mode.ACTIVE: "活動中", PetVitality.Mode.STANDING: "站著休息", PetVitality.Mode.RESTING: "坐著休息", PetVitality.Mode.SLEEPING: "睡覺中"}.get(v.mode, "")
	return TranslationServer.translate("精力 %d%%  ·  %s%s  ·  心情 %d(%s)  ·  社交意願 %s") % [int(v.energy), mode_text, "(累了)" if v.tired else "", int(v.mood), v.mood_text(), snappedf(pet.sociability, 0.01)]


## 預覽的文字(獨立成靜態函式方便測試):每個區塊先說「選了哪個性格、它在這個區塊會怎樣」,再列出會發生的變化;
## 參數區塊另外列出所有參數的目前值(有變化的標出「→ 套用後的值」)。
static func preview_text(pet: Node, wanted: Dictionary, options: Dictionary) -> String:
	var plan := PersonalityApplier.preview(pet, wanted, options)
	var parts: Array[String] = []
	var described: Dictionary = {}
	for section: String in PersonalityApplier.SECTIONS:
		var id := str(wanted.get(section, ""))
		if id != "" and not described.has(id):
			described[id] = true
			var described_personality := PersonalityApplier.personality_of(pet, id)
			if not described_personality.is_empty():
				parts.append("【%s】%s%s" % [described_personality["name"], described_personality["description"], "(這隻角色改過的版本)" if PersonalityApplier.is_edited(pet, id) else ""])
	for missing_id: String in plan["missing"]:
		parts.append(TranslationServer.translate("找不到性格「%s」(可能是自訂性格檔被刪掉了)") % missing_id)
	for section: String in PersonalityApplier.SECTIONS:
		if not wanted.has(section):
			continue
		var id := str(wanted[section])
		var found := PersonalityApplier.personality_of(pet, id) if id != "" else {}
		var header := "〔%s〕" % PersonalityApplier.SECTION_NAMES[section]
		if id != "" and not found.is_empty():
			header += TranslationServer.translate(" 用【%s】") % found["name"]
		var body: Array[String] = []
		if not found.is_empty():
			body.append("  " + PersonalityFile.section_description(found, section, true))
		match section:
			"params":
				body.append_array(_params_lines(pet, plan["params"]))
			"valueDefs", "lenses":
				var lines: Array[String] = []
				for step: Dictionary in (plan["defs"] as Dictionary).get(section, []):
					var text: String = {"add": "新增", "replace": "換成新性格的", "keep": "你已經有自己的,保留", "remove": "移除(原本是性格加的、你沒改過)"}.get(str(step["action"]), "")
					if text != "":
						lines.append("  「%s」%s" % [step["name"], text])
				if lines.is_empty():
					lines.append("  沒有變化")
				body.append_array(lines)
			"chat", "reactions":
				var ignore := bool(options.get("ignore_own_" + section, false))
				var count := int((plan["events"] as Dictionary).get(section, 0))
				if id == "":
					body.append("  不套用性格" + ("" if not ignore else "(「只用性格的」在沒有性格時不會生效)"))
				else:
					body.append(TranslationServer.translate("  加入 %d 個事件") % count + ("(你自己的同類事件暫時停用)" if ignore else "(你自己的同類事件照常保留、一起運作)"))
		parts.append(header + "\n" + "\n".join(PackedStringArray(body)))
	return "\n\n".join(PackedStringArray(parts))


## 參數區塊的預覽行:先列有變化的項目(套用/保留/還原),再列沒有變化的項目的目前值。
static func _params_lines(pet: Node, steps: Array) -> Array[String]:
	var lines: Array[String] = []
	var listed: Dictionary = {}
	for step: Dictionary in steps:
		listed[str(step["key"])] = true
		match str(step["action"]):
			"apply":
				lines.append(TranslationServer.translate("  套用  %s:%s → %s") % [step["label"], PersonalityParams.to_text(step["current"]), PersonalityParams.to_text(step["new"])])
			"keep":
				lines.append(TranslationServer.translate("  保留你改過的  %s(%s,性格想設成 %s)") % [step["label"], PersonalityParams.to_text(step["current"]), PersonalityParams.to_text(step["new"])])
			"revert":
				lines.append(TranslationServer.translate("  還原  %s:%s → %s") % [step["label"], PersonalityParams.to_text(step["current"]), PersonalityParams.to_text(step["new"])])
			"same":
				lines.append(TranslationServer.translate("  一樣  %s:%s") % [step["label"], PersonalityParams.to_text(step["current"])])
	var changed_count := lines.filter(func(l: String) -> bool: return l.begins_with("  套用") or l.begins_with("  還原")).size()
	var result: Array[String] = []
	if changed_count == 0:
		result.append("  沒有變化")
	result.append_array(lines)
	result.append("  ── 這隻桌寵目前的其他參數 ──")
	for key: String in PersonalityParams.keys():
		if listed.has(key):
			continue
		# 一樣要先翻譯再截斷(見 PersonalityFile.short_label() 旁的說明,同一個坑)。
		result.append(TranslationServer.translate("  目前  %s:%s") % [TranslationServer.translate(PersonalityParams.label_of(key)).split("(")[0].strip_edges(), _value_text(key, PersonalityParams.get_value(pet, key))])
	return result


static func _value_text(key: String, value: Variant) -> String:
	if value is bool:
		return "是" if value else "否"
	var text := PersonalityParams.to_text(value)
	return text + " 秒" if str(PersonalityParams.SPECS[key]["kind"]) == "range" else text


func _apply() -> void:
	if _pet == null:
		return
	var result := PersonalityApplier.apply(_pet, _wanted(), _options())
	_reload_options()
	_reload_mood_lens_options()
	_refresh_preview()
	changed.emit()
	var lines: Array = result["lines"]
	message.emit(tr("已套用性格(%d 項變更)。") % lines.size() + (" " + str(lines[0]) if not lines.is_empty() else "") + " 記得按「儲存」。")


func _clear_all() -> void:
	if _pet == null:
		return
	var result := PersonalityApplier.clear_all(_pet)
	_reload_options()
	_reload_mood_lens_options()
	_refresh_preview()
	changed.emit()
	message.emit(tr("已取消所有性格(%d 項還原/移除)。你自己的內容沒動。") % (result["lines"] as Array).size())


# --- 性格編輯器 ---

## 打開性格編輯器:編輯「參數」區塊選的性格(沒選就依序找對話池、反應事件的),都沒選就從這隻桌寵目前的設定開始。
func _open_editor() -> void:
	if _pet == null:
		return
	open_editor()


func open_editor() -> PersonalityEditorWindow:
	var wanted := _wanted()
	var chosen := ""
	for section: String in ["params", "chat", "reactions", "lenses", "valueDefs"]:
		if str(wanted[section]) != "":
			chosen = str(wanted[section])
			break
	var personality: Dictionary
	var builtin := false
	if chosen != "":
		# 改的是這隻角色自己帶的副本(沒有副本就先從共用的性格檔複製一份);builtin 是共用的那份是不是內建的(另存成共用性格時不能撞內建的 id)。
		PersonalityApplier.ensure_own(_pet, chosen)
		personality = PersonalityApplier.personality_of(_pet, chosen)
		if personality.is_empty():
			message.emit(tr("找不到性格「%s」。") % chosen)
			return null
		var shared := PersonalityFile.find(chosen)
		builtin = bool(shared.get("builtin", false))
	else:
		var data := PersonalityFile.export_pet(_pet, "%s_personality" % str(_pet.recognition_tag), tr("%s的性格") % _pet.get_label(), tr("從 %s 目前的設定開始編輯") % _pet.get_label())
		personality = PersonalityFile.validate(data)["personality"]
	var window := PersonalityEditorWindow.new()
	add_child(window)
	window.setup(personality, builtin, _pet if chosen != "" else null)
	window.saved.connect(_on_editor_saved)
	window.saved_to_pet.connect(_on_editor_saved_to_pet)
	return window


## 性格編輯器把改動存到「這隻角色的版本」:事件層已經重建,參數要再按「套用」才會寫到桌寵身上。
func _on_editor_saved_to_pet(id: String) -> void:
	_refresh_preview()
	changed.emit()
	message.emit(tr("已存到這隻角色自己的「%s」(別隻角色與共用的性格不受影響)。要讓新的參數生效請按「套用」,記得再按「儲存」。") % _name_of(id))


## 「重設此性格副本」:丟掉這隻角色改過的副本,從共用的性格檔重新複製原版。
func _reset_own_copy() -> void:
	if _pet == null:
		return
	var wanted := _wanted()
	var chosen := ""
	for section: String in ["params", "chat", "reactions", "lenses", "valueDefs"]:
		if str(wanted[section]) != "":
			chosen = str(wanted[section])
			break
	if chosen == "" or not PersonalityApplier.has_own(_pet, chosen):
		message.emit("這隻角色沒有選任何性格,或還沒帶著性格副本。")
		return
	var edited := PersonalityApplier.is_edited(_pet, chosen)
	var dialog := ConfirmationDialog.new()
	dialog.title = "重設性格副本"
	dialog.dialog_text = tr("要把這隻角色的「%s」%s重設成共用的原版嗎?\n這隻角色改過的台詞與參數設定會消失,而且這個性格管的參數會一併同步成原版的值(連你手動調過的也會換掉;數值定義與狀態鏡沒改過的換成新版、你自己建的不動)。") % [_name_of(chosen), "(有改過)" if edited else ""]
	dialog.ok_button_text = "重設"
	dialog.cancel_button_text = "取消"
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	dialog.confirmed.connect(func() -> void:
		PersonalityApplier.reset_own(_pet, chosen)
		# 同步:這個性格負責的區塊重新套用一次(參數連手動調過的也覆蓋,這是「重設」的意思)
		var sync := {}
		for section: String in PersonalityApplier.SECTIONS:
			if PersonalityApplier.choice_of(_pet, section) == chosen:
				sync[section] = chosen
		var synced := PersonalityApplier.apply(_pet, sync, {"overwrite_params": true}) if not sync.is_empty() else {"lines": []}
		_refresh_preview()
		changed.emit()
		message.emit(tr("已把這隻角色的「%s」重設成原版,並同步了 %d 項(記得再按「儲存」)。") % [_name_of(chosen), (synced["lines"] as Array).size()]))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 200))


func _on_editor_saved(id: String) -> void:
	_reload_options()
	_refresh_preview()
	message.emit(tr("已存成自訂性格「%s」,可以在上面的下拉選單選它套用。") % _name_of(id))


# --- 匯入與匯出 ---

func _import() -> void:
	FloatingWindow.native_file_dialog("匯入自訂性格(性格檔)", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.json;性格檔"]),
			_on_import_picked, get_window().get_window_id())


func _on_import_picked(paths: PackedStringArray) -> void:
	import_from(paths[0])


## 匯入一個性格檔(給檔案對話框與測試用):通過驗證就存進自訂性格資料夾並出現在下拉選單。
func import_from(path: String) -> Dictionary:
	var result := PersonalityFile.import_file(path)
	_reload_options()
	_refresh_preview()
	var report: Array = result["report"]
	if bool(result["ok"]):
		message.emit(tr("已匯入自訂性格「%s」。%s") % [_name_of(str(result["id"])), (" 注意:" + "; ".join(report)) if not report.is_empty() else ""])
	else:
		message.emit(tr("匯入失敗:%s") % "; ".join(report))
	return result


func _export() -> void:
	if _pet == null:
		return
	FloatingWindow.native_file_dialog("匯出目前設定為性格檔", "", DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(["*.json;性格檔"]),
			_on_export_picked, get_window().get_window_id(), "%s.personality.json" % str(_pet.recognition_tag))


func _on_export_picked(paths: PackedStringArray) -> void:
	export_to(paths[0])


func export_to(path: String) -> Error:
	var data := PersonalityFile.export_pet(_pet, "%s_personality" % str(_pet.recognition_tag), tr("%s的性格") % _pet.get_label(), tr("從 %s 匯出的目前設定") % _pet.get_label())
	var error := PersonalityFile.write_file(path, data)
	message.emit(tr("已匯出性格檔:%s") % path if error == OK else tr("匯出失敗(無法寫入):%s") % path)
	return error
