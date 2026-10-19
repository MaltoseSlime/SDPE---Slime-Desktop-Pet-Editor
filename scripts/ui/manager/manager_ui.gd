class_name ManagerUi
extends RefCounted
## 管理視窗共用的小工具:用程式建表單控制項(專案沒有為這些視窗做 .tscn,全部程序化生成)。

const LABEL_WIDTH := 130.0


static func labeled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is BaseButton:
		# 下拉選單/按鈕文字不夠放的時候用刪節號,不要把最小尺寸撐到超出視窗寬度(視窗窄的時候才會裁掉字或擋住旁邊的欄位)。
		(control as BaseButton).clip_text = true
	row.add_child(control)
	return row


static func line_edit(placeholder := "") -> LineEdit:
	var edit := LineEdit.new()
	# Control 的 text/tooltip_text 會自動照目前語系翻譯(不用另外包 TranslationServer.translate()),但 placeholder_text 不在那份
	# 自動翻譯的屬性清單裡——實測過,語系切成英文,不手動翻譯的話 placeholder_text 還是顯示原文中文
	# (2026-09-29 使用者回報「可填入式欄位裡經常有預設的括號提示文字未翻譯」)。這個函式是 static,
	# 不能用 TranslationServer.translate()(那是 Object 的非 static 方法),改用等效的 TranslationServer.translate()。
	edit.placeholder_text = TranslationServer.translate(placeholder)
	edit.clear_button_enabled = true
	return edit


## 數字輸入框:不夾限(allow_greater/lesser),真正的合法範圍由呼叫端在套用時驗證。
static func spin(step := 1.0, min_value := -1.0e9, max_value := 1.0e9) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = min_value
	box.max_value = max_value
	box.step = step
	box.allow_greater = true
	box.allow_lesser = true
	return box


## 按鈕文字超過這個寬度就自動換行(見 button())。
const BUTTON_WRAP_WIDTH := 220.0


## 一般按鈕。文字很長(多半是翻成英文之後)時自動換行,不要整句擠在一行把所在的欄位、卡片撐寬
## (2026-10-13 使用者實機回報英文介面常見)。文字本來就放得下 BUTTON_WRAP_WIDTH 的按鈕完全不受影響。
static func button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	var fit := func() -> void: wrap_long_button(button)
	button.ready.connect(fit)
	button.theme_changed.connect(fit)
	return button


## 依目前的字體量按鈕文字(翻譯後)的寬度:超過 BUTTON_WRAP_WIDTH 就開自動換行並把最小寬度定在那個寬度
## (開了自動換行的按鈕最小寬度會變成幾乎 0,不給底線會被擠成一個字一行);沒超過就維持單行。
static func wrap_long_button(button: Button) -> void:
	if button.clip_text or not button.is_inside_tree():
		return
	var text := button.tr(button.text) if button.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else button.text
	var width := button.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
	var long := width > BUTTON_WRAP_WIDTH
	var wanted := TextServer.AUTOWRAP_WORD_SMART if long else TextServer.AUTOWRAP_OFF
	if button.autowrap_mode != wanted:
		button.autowrap_mode = wanted
	if long and button.custom_minimum_size.x < BUTTON_WRAP_WIDTH:
		button.custom_minimum_size.x = BUTTON_WRAP_WIDTH


## 單行的說明文字超過這個寬度就改成自動換行(見 wrap_long_label)。
const LABEL_WRAP_WIDTH := 260.0
## 下拉選單最長的選項超過這個寬度就不再跟著選項變寬(見 cap_option_width)。
const OPTION_MAX_WIDTH := 190.0


## 單行、沒有裁切的長文字(多半是翻成英文之後的說明):改成自動換行,並給一個換行估算用的底線寬度
## (換行 Label 沒有底線寬度會被估出離譜的高度,見 hint_row 的說明)。排在一列裡的,讓它吃掉那一列剩下的寬度。
static func wrap_long_label(label: Label) -> void:
	if label.clip_text or label.autowrap_mode != TextServer.AUTOWRAP_OFF or not label.is_inside_tree() or label.text.contains("\n"):
		return
	var text := label.tr(label.text) if label.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else label.text
	var width := label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	# 呼叫端給了固定寬度的(「標籤 + 欄位」那種列的標籤):文字比那個寬度長就在那個寬度裡換行,不要把整列撐寬。
	var fixed := label.custom_minimum_size.x > 0.0
	if width <= (label.custom_minimum_size.x if fixed else LABEL_WRAP_WIDTH):
		return
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not fixed:
		label.custom_minimum_size.x = 200.0
		if label.get_parent() is HBoxContainer:
			label.size_flags_horizontal |= Control.SIZE_EXPAND_FILL


## 下拉選單預設會寬到放得下最長的選項:選項很長(英文常見)時改成固定寬度、放不下用刪節號,不要一個選項就把整列撐寬。
## 呼叫端已經自己限制過(fit_to_longest_item 關掉)的不動。
static func cap_option_width(option: OptionButton) -> void:
	if not option.fit_to_longest_item or not option.is_inside_tree():
		return
	var font := option.get_theme_font("font")
	var font_size := option.get_theme_font_size("font_size")
	var longest := 0.0
	for i in option.item_count:
		var text := option.get_item_text(i)
		if option.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED:
			text = option.tr(text)
		longest = maxf(longest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	if longest <= OPTION_MAX_WIDTH:
		return
	option.fit_to_longest_item = false
	option.clip_text = true
	if option.custom_minimum_size.x < OPTION_MAX_WIDTH:
		option.custom_minimum_size.x = OPTION_MAX_WIDTH


## 問使用者一個名字的小視窗(加在 parent 底下):problem_of(名字) 回傳問題文字(空字串 = 可以),有問題時確定鈕停用並顯示原因;按確定呼叫 on_chosen(名字)。
static func ask_name(parent: Node, title_text: String, message: String, default_name: String, ok_text: String, problem_of: Callable, on_chosen: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	dialog.ok_button_text = ok_text
	dialog.cancel_button_text = "取消"
	# 不設 always_on_top:這種視窗會被 Godot 設成呼叫端(可能置頂的)視窗的 transient 子視窗,跟置頂在
	# Windows 原生視窗上互斥(godotengine/godot#117698,4.7.2 尚未修正),硬設會把視窗卡死到連工作列都找不到
	# (2026-09-30 使用者實機回報)。身為 owned window,Windows 本來就會自動疊在呼叫端視窗上面,不需要自己也置頂。
	dialog.theme = make_theme()
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420.0
	box.add_child(label)
	var edit := line_edit("名稱")
	edit.max_length = 40
	edit.text = default_name
	box.add_child(edit)
	var problem := Label.new()
	problem.theme_type_variation = AppSettings.WARN_LABEL
	box.add_child(problem)
	dialog.add_child(box)
	var validate := func(text: String) -> void:
		var reason := str(problem_of.call(text.strip_edges()))
		problem.text = reason
		dialog.get_ok_button().disabled = reason != ""
	edit.text_changed.connect(validate)
	dialog.confirmed.connect(func() -> void: on_chosen.call(edit.text.strip_edges()))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	validate.call(edit.text)
	if parent.is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(parent, parent.get_window(), dialog, Vector2i(480, 220))
		edit.grab_focus()
		edit.select_all()
	return dialog


## 目前編輯器配色的「次要文字色」(停用、無效、提示):控制項需要已加入場景樹並套用了主題才拿得到正確的顏色。
static func muted_color(control: Control) -> Color:
	return control.get_theme_color("muted", "Label")


## 目前編輯器配色的強調色(同上)。
static func accent_color(control: Control) -> Color:
	return control.get_theme_color("accent", "Label")


## 圓形「i」圖示,滑過才顯示說明(tooltip)。長說明放這裡,不要直接印在版面上。
static func info_icon(tip: String) -> InfoIcon:
	return InfoIcon.new(tip)


## 一行「短文字 + i 圖示」:短文字直接看得到(一句話的重點),詳細說明在圖示的 tooltip 裡。
static func hint_row(short_text: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = short_text
	label.theme_type_variation = AppSettings.MUTED_LABEL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 「短文字」翻成英文常常不再短(見主企劃書「介面文字視語系可能變長」):不換行、不吃可用寬度的話,
	# 這顆 Label 會逼整條 row、進而逼整個左側欄位跟著撐寬,擠壓閱讀空間(2026-09-29 使用者實機回報,
	# 桌寵管理→性格分頁最明顯)。改成吃滿可用寬度並自動換行,不會再撐寬外層容器。
	# 2026-09-30 又發現(使用者又一次實機回報,這次是整個分頁被一團空白吃掉):換行 Label 剛蓋好、還沒
	# 加進場景樹、外層容器還沒量出真正可用寬度的當下就把長文字塞給它(這裡就是這樣,建構好馬上設定 text),
	# Godot 會用「還不知道最終寬度」這個當下的極窄寬度去估算換行後要多高,估出離譜的高度(上百甚至上千
	# 像素)——這個過高的估計值會被外層 VBoxContainer 直接當成這一列「需要保留的高度」用,之後就算 Label
	# 實際拿到足夠寬度、真正只需要兩三行,那格保留的高度也不會跟著縮回去,畫面上看起來就是一大塊空白。
	# 加一個合理的 custom_minimum_size.x 當作換行估算的底線寬度,問題就不會發生了(SIZE_EXPAND_FILL 還是
	# 保留,真正版面配置好之後一樣能吃滿可用寬度,只是不會再用「零寬度」去估算換行高度)。
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 220.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	row.add_child(InfoIcon.new(tip))
	return row


## 「短文字 + i 圖示 + 語法字典按鈕」:host 是所在的視窗(節點),字典視窗加在它底下,同一個 host 只開一個。
## can_insert = true 時字典的「插入」會插到 host 視窗裡最後點過的文字框(TextEdit / LineEdit)的游標處,沒有文字框就改成複製到剪貼簿。
static func syntax_row(host: Node, short_text: String, tip: String, can_insert := true) -> HBoxContainer:
	var row := hint_row(short_text, tip)
	var button := Button.new()
	button.text = TranslationServer.translate("語法字典")
	button.flat = true
	button.tooltip_text = TranslationServer.translate("所有能寫在台詞裡的語法(文字樣式、名字與稱呼、單字池、遊戲結果…),可搜尋、插入、複製。")
	button.pressed.connect(func() -> void: open_syntax_dictionary(host, can_insert))
	row.add_child(button)
	return row


const SYNTAX_MENU_ID := 7100
## Godot 內建文字欄位右鍵選單的項目(LineEdit / TextEdit 的 MENU_* 編號相同)換成中文;英文介面時再經翻譯表變回英文。
const TEXT_MENU_NAMES := {
	0: "剪下", 1: "複製", 2: "貼上", 3: "清除", 4: "全選", 5: "復原", 6: "重做",
	7: "文字書寫方向", 8: "跟隨版面方向", 9: "自動偵測方向", 10: "由左至右", 11: "由右至左",
	12: "顯示控制字元", 13: "插入控制字元",
	14: "由左至右標記(LRM)", 15: "由右至左標記(RLM)", 16: "由左至右嵌入開始(LRE)", 17: "由右至左嵌入開始(RLE)",
	18: "由左至右覆寫開始(LRO)", 19: "由右至左覆寫開始(RLO)", 20: "結束方向格式(PDF)", 21: "阿拉伯字母標記(ALM)",
	22: "由左至右隔離(LRI)", 23: "由右至左隔離(RLI)", 24: "第一強方向隔離(FSI)", 25: "結束方向隔離(PDI)",
	26: "零寬連接符(ZWJ)", 27: "零寬不連接符(ZWNJ)", 28: "單字連接符(WJ)", 29: "軟連字號(SHY)",
}


## 文字欄位(LineEdit / TextEdit)的右鍵選單:項目換成中文(DesktopShell 對所有文字欄位都會呼叫)。
## 選單本身是一個子視窗,第一次按右鍵(或選單鍵)時才建、才改(gui_input 訊號比欄位自己處理右鍵早),
## 不然一個分頁幾百格會一口氣開幾百個視窗。
static func watch_text_menu(edit: Control) -> void:
	if edit.has_meta("text_menu_watch") or not (edit is LineEdit or edit is TextEdit):
		return
	edit.set_meta("text_menu_watch", true)
	edit.gui_input.connect(func(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		var key := event as InputEventKey
		if (mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT) or (key != null and key.pressed and key.keycode == KEY_MENU):
			_prepare_text_menu(edit))


## 桌寵管理的文字欄位另外加一項「語法字典…」:開的字典「插入」會插到這一格的游標處。
static func add_syntax_menu(edit: Control) -> void:
	if edit.has_meta("syntax_menu") or not (edit is LineEdit or edit is TextEdit):
		return
	edit.set_meta("syntax_menu", true)
	watch_text_menu(edit)


static func _prepare_text_menu(edit: Control) -> void:
	if edit.has_meta("text_menu_ready"):
		return
	edit.set_meta("text_menu_ready", true)
	var menu: PopupMenu = edit.get_menu()
	_translate_text_menu(menu)
	if edit.has_meta("syntax_menu"):
		_install_syntax_menu_item(edit, menu)


static func _translate_text_menu(menu: PopupMenu) -> void:
	for i in menu.item_count:
		var id := menu.get_item_id(i)
		if TEXT_MENU_NAMES.has(id) and not menu.is_item_separator(i):
			menu.set_item_text(i, TranslationServer.translate(str(TEXT_MENU_NAMES[id])))
		var sub := menu.get_item_submenu_node(i)
		if sub != null:
			_translate_text_menu(sub)


static func _install_syntax_menu_item(edit: Control, menu: PopupMenu) -> void:
	menu.add_separator()
	menu.add_item(TranslationServer.translate("語法字典…"), SYNTAX_MENU_ID)
	menu.id_pressed.connect(func(id: int) -> void:
		if id == SYNTAX_MENU_ID and is_instance_valid(edit) and edit.is_inside_tree():
			open_syntax_dictionary(edit.get_window(), true, edit))


## 名字後面的附註「(代號)」(撞名時區分用,顏色淡、字級跟一般字一樣,見 AppSettings.TAG_NOTE_LABEL)。
static func tag_note(tag: String) -> Label:
	var note := Label.new()
	note.text = "(%s)" % tag
	note.theme_type_variation = AppSettings.TAG_NOTE_LABEL
	note.tooltip_text = TranslationServer.translate("辨識代號:%s(有別的角色同名,用代號區分)") % tag
	note.mouse_filter = Control.MOUSE_FILTER_PASS
	return note


## 開語法字典視窗(host 底下已經有就叫到前景)。target 給了的話「插入」固定插到那個文字框(從文字框右鍵選單開的)。
static func open_syntax_dictionary(host: Node, can_insert := true, target: Control = null) -> SyntaxDictionaryWindow:
	if host.has_meta("syntax_dictionary_window"):
		var existing: Variant = host.get_meta("syntax_dictionary_window")
		# is_instance_valid() 要先檢查,見下面事件管理視窗那段的詳細說明。
		if is_instance_valid(existing) and existing is SyntaxDictionaryWindow:
			var dictionary := existing as SyntaxDictionaryWindow
			if target != null:
				dictionary.set_meta("insert_target", target)
				dictionary.set_can_insert(true)
			elif dictionary.has_meta("insert_target"):
				dictionary.remove_meta("insert_target")   # 改從「語法字典」按鈕開:回到插進最後點過的文字框
			dictionary.bring_to_front()
			return dictionary
	var window := SyntaxDictionaryWindow.new()
	host.add_child(window)
	window.setup(can_insert or target != null)
	if target != null:
		window.set_meta("insert_target", target)
	host.set_meta("syntax_dictionary_window", window)
	window.insert_requested.connect(func(syntax: String) -> void:
		var owner_window := host.get_window()
		var focused: Control = owner_window.gui_get_focus_owner() if owner_window != null else null
		var bound: Variant = window.get_meta("insert_target", null)
		if is_instance_valid(bound) and (bound as Node).is_inside_tree():
			focused = bound
		if focused is TextEdit:
			(focused as TextEdit).insert_text_at_caret(syntax)
		elif focused is LineEdit:
			(focused as LineEdit).insert_text_at_caret(syntax)
		else:
			DisplayServer.clipboard_set(syntax))
	return window


## 開「系統保留數值」視窗(host 底下已經有就叫到前景)——列出 ReservedPetValues.ENTRIES,給數值管理分頁用。
static func open_reserved_values_window(host: Node) -> ReservedValuesWindow:
	if host.has_meta("reserved_values_window"):
		var existing: Variant = host.get_meta("reserved_values_window")
		# is_instance_valid() 要先檢查,見下面事件管理視窗那段的詳細說明。
		if is_instance_valid(existing) and existing is ReservedValuesWindow:
			(existing as ReservedValuesWindow).bring_to_front()
			return existing
	var window := ReservedValuesWindow.new()
	host.add_child(window)
	window.setup()
	host.set_meta("reserved_values_window", window)
	return window


## 基本反應對話視窗(交互行為分頁收納用):同一個 host 只開一個。
static func open_reaction_dialogue_window(host: Node) -> ReactionDialogueWindow:
	if host.has_meta("reaction_dialogue_window"):
		var existing: Variant = host.get_meta("reaction_dialogue_window")
		if is_instance_valid(existing) and existing is ReactionDialogueWindow:
			(existing as ReactionDialogueWindow).bring_to_front()
			return existing
	var window := ReactionDialogueWindow.new()
	host.add_child(window)
	window.setup(host)
	host.set_meta("reaction_dialogue_window", window)
	return window


## 話題文本視窗(交互行為分頁收納用):同一個 host 只開一個,第二次點就把它拉到前面。
## generic = true 開的是「通用話題池」那一個視窗(跟話題文本視窗各自獨立,可以同時開著)。
static func open_topic_lines_window(host: Node, generic := false) -> TopicLinesWindow:
	var key := "topic_generic_window" if generic else "topic_lines_window"
	if host.has_meta(key):
		var existing: Variant = host.get_meta(key)
		if is_instance_valid(existing) and existing is TopicLinesWindow:
			(existing as TopicLinesWindow).bring_to_front()
			return existing
	var window := TopicLinesWindow.new()
	host.add_child(window)
	window.setup(host, generic)
	host.set_meta(key, window)
	return window


## 素材包「成功載入,但有些內容沒進去」的提示(跟載入失敗是兩回事)——跳出 SpritePackLoader.
## limit_warning_dialogs(result) 組好的 0~2 則訊息,給桌面放上桌寵/角色庫/精靈圖編輯器存檔共用,
## 不用各自重複寫 AcceptDialog 的建立邏輯。parent/top_window 的意義見 FloatingWindow.popup_child_dialog()
## 的說明,呼叫端一律傳 (self, get_window())(DesktopShell 跟其他 FloatingWindow 子類別都一樣,是這個
## 專案既有的呼叫慣例)。
static func show_pack_limit_warnings(parent: Node, top_window: Window, result: Dictionary) -> void:
	for entry: Dictionary in SpritePackLoader.limit_warning_dialogs(result):
		var dialog := AcceptDialog.new()
		dialog.title = str(entry["title"])
		dialog.exclusive = false
		dialog.transient = false
		dialog.theme = make_theme()
		dialog.dialog_text = str(entry["message"])
		dialog.dialog_autowrap = true
		FloatingWindow.popup_child_dialog(parent, top_window, dialog, Vector2i(480, 320))


## 開「事件管理」視窗(查看/暫時停用/移除某隻桌寵目前生效的事件,見 EventManagerWindow):同一隻桌寵已經
## 開著就叫到前景,不同桌寵各自開一個。交互行為分頁跟測試者面板都呼叫這個共用函式(2026-10-04 使用者
## 要求兩邊都要有,不是只掛在某一邊)。pet 是 null 或已經不在場上就不開,直接回傳 null。
static func open_event_manager_window(host: Node, pet: Node) -> EventManagerWindow:
	if pet == null or not is_instance_valid(pet):
		return null
	var key := "event_manager_window_%d" % pet.get_instance_id()
	if host.has_meta(key):
		var existing: Variant = host.get_meta(key)
		# 2026-10 使用者實機回報:`existing is EventManagerWindow` 寫在 `is_instance_valid()` 前面時,
		# 視窗被關閉釋放後舊的 meta 還留著同一個已釋放的 Object 參照,`is` 運算子碰到已釋放的實例會直接
		# 噴執行期錯誤(跟呼叫已釋放物件的方法不同,`is` 不會安全失敗)。is_instance_valid() 一定要先檢查。
		if is_instance_valid(existing) and existing is EventManagerWindow:
			(existing as EventManagerWindow).bring_to_front()
			return existing
	var window := EventManagerWindow.new()
	host.add_child(window)
	window.setup(pet)
	host.set_meta(key, window)
	return window


## 卡片式分頁共用的卡片(桌寵管理的「外觀與介面」「行為」「對話與關係」「記憶與檔案」):圓角底框 + 可以點開/收合的標題列
## (預設展開;收合狀態只存在畫面上,不寫進設定檔)+ 內容區。tip_parts 有東西時標題旁邊多一個 ⓘ(整張卡片的說明;
## 每段各自是字串表裡獨立的一筆原文,見 InfoIcon.set_tip_parts)。回傳 {card = 整張卡片, box = 內容區(往裡面加控制項)}。
## 標題與說明都傳「原文」進來,這裡才翻譯——不要先組字串再當查表 key(2026-09-30 踩過的坑)。
const CARD_WIDTH := 440.0


static func card(title_text: String, tip_parts: PackedStringArray = [], min_width := CARD_WIDTH) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = min_width
	var style := StyleBoxFlat.new()
	style.bg_color = AppSettings.ink(0.05)
	style.border_color = AppSettings.ink(0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override("panel", style)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	var toggle := Button.new()
	toggle.flat = true
	var translated_title := TranslationServer.translate(title_text)
	toggle.text = "▾ " + translated_title
	toggle.clip_text = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fixed_font_size(toggle, 17)
	header.add_child(toggle)
	if not tip_parts.is_empty():
		var info := InfoIcon.new()
		info.set_tip_parts(tip_parts)
		header.add_child(info)
	outer.add_child(header)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	outer.add_child(box)
	toggle.pressed.connect(func() -> void:
		box.visible = not box.visible
		toggle.text = ("▾ " if box.visible else "▸ ") + translated_title)
	return {"card": panel, "box": box}


## 卡片裡的一個小節(幾張主題相近的卡片合併成一張時用):前面已經有內容就先畫一條分隔線,再放小標題(+ ⓘ),
## 回傳這個小節自己的內容區。
static func card_section(box: VBoxContainer, title_text: String, tip_parts: PackedStringArray = []) -> VBoxContainer:
	if box.get_child_count() > 0:
		box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(heading(title_text))
	if not tip_parts.is_empty():
		var info := InfoIcon.new()
		info.set_tip_parts(tip_parts)
		row.add_child(info)
	box.add_child(row)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 5)
	box.add_child(section)
	return section


## 卡片式分頁的版面:可以上下捲動的區塊,裡面的卡片依寬度自動排成一行幾張。回傳 {scroll, flow}。
static func card_page() -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(flow)
	return {"scroll": scroll, "flow": flow}


## 跟著卡片寬度伸縮的下拉選單(ManagerUi.labeled 那種「標籤 + 選單」):最小寬度不要跟著最長的選項走,不然一個長選項就把整張卡片撐寬;
## 放不下的文字用刪節號(展開的清單照樣看得到全文)。
static func fit_options_to_card(root: Node) -> void:
	for option: OptionButton in root.find_children("*", "OptionButton", true, false):
		if option.size_flags_horizontal & Control.SIZE_EXPAND:
			option.fit_to_longest_item = false
			option.clip_text = true


## 標題文字後面跟一個 i 圖示。
static func heading_with_info(text: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(heading(text))
	row.add_child(InfoIcon.new(tip))
	return row


## 大標題文字(區段名稱)。
static func heading(text: String) -> Label:
	var label := Label.new()
	# 2026-09-29 實測發現:Control 的 text 屬性純賦值不會自動照語系翻譯(這個 session 早前以為會,
	# 是誤判——各處原本翻得到都是因為呼叫端自己包了 TranslationServer.translate(),不是引擎自動處理的)。heading() 是整個管理視窗
	# 用最多的共用函式(幾乎每個分頁的每個區段標題都靠它),明著翻譯,一次修全部呼叫點。
	label.text = TranslationServer.translate(text)
	fixed_font_size(label, 17)
	return label


## 寫死字級的文字(標題、版本號、小字):字級乘上目前編輯器字體的視覺校正倍率(Silver 會放大),換字體時跟著重算。
## 不這樣做的話,主題的字級放大了、這些寫死的卻沒跟上(2026-10-14 使用者回報 Silver 的標題字比內文還小)。
static func fixed_font_size(control: Control, base_size: int) -> void:
	# 同一個控制項可能被叫兩次(heading() 先給 17、呼叫端再改成 15):只留一條連線,字級以最後一次給的為準,
	# 不然兩條連線各自堅持自己的值、互相觸發 theme_changed 到堆疊爆掉。
	var hooked := control.has_meta("fixed_font_base")
	control.set_meta("fixed_font_base", base_size)
	_apply_fixed_font_size(control)
	if not hooked:
		control.theme_changed.connect(_apply_fixed_font_size.bind(control))


static func _apply_fixed_font_size(control: Control) -> void:
	var wanted := roundi(int(control.get_meta("fixed_font_base", 0)) * AppSettings.font_correction())
	# 加覆寫本身會再發一次 theme_changed:先記下「已經套過這個值」再加。
	if wanted > 0 and int(control.get_meta("fixed_font_size", 0)) != wanted:
		control.set_meta("fixed_font_size", wanted)
		control.add_theme_font_size_override("font_size", wanted)


## 給所有視窗化編輯器用的主題:配色、字體、字級跟著「程式設定」分頁的外觀設定(見 AppSettings.build_theme),含只有滾輪的細捲軸。
static func make_theme() -> Theme:
	return AppSettings.build_theme()
