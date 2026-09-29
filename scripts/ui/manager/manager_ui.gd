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
	# Control 的 text/tooltip_text 會自動照目前語系翻譯(不用另外包 tr()),但 placeholder_text 不在那份
	# 自動翻譯的屬性清單裡——實測過,語系切成英文,不手動翻譯的話 placeholder_text 還是顯示原文中文
	# (2026-09-29 使用者回報「可填入式欄位裡經常有預設的括號提示文字未翻譯」)。這個函式是 static,
	# 不能用 tr()(那是 Object 的非 static 方法),改用等效的 TranslationServer.translate()。
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


static func button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	return button


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
	button.text = "語法字典"
	button.flat = true
	button.tooltip_text = "所有能寫在台詞裡的語法(文字樣式、名字與稱呼、單字池、遊戲結果…),可搜尋、插入、複製。"
	button.pressed.connect(func() -> void: open_syntax_dictionary(host, can_insert))
	row.add_child(button)
	return row


## 開語法字典視窗(host 底下已經有就叫到前景)。
static func open_syntax_dictionary(host: Node, can_insert := true) -> SyntaxDictionaryWindow:
	if host.has_meta("syntax_dictionary_window"):
		var existing: Variant = host.get_meta("syntax_dictionary_window")
		if existing is SyntaxDictionaryWindow and is_instance_valid(existing):
			(existing as SyntaxDictionaryWindow).bring_to_front()
			return existing
	var window := SyntaxDictionaryWindow.new()
	host.add_child(window)
	window.setup(can_insert)
	host.set_meta("syntax_dictionary_window", window)
	window.insert_requested.connect(func(syntax: String) -> void:
		var owner_window := host.get_window()
		var focused: Control = owner_window.gui_get_focus_owner() if owner_window != null else null
		if focused is TextEdit:
			(focused as TextEdit).insert_text_at_caret(syntax)
		elif focused is LineEdit:
			(focused as LineEdit).insert_text_at_caret(syntax)
		else:
			DisplayServer.clipboard_set(syntax))
	return window


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
	# 是誤判——各處原本翻得到都是因為呼叫端自己包了 tr(),不是引擎自動處理的)。heading() 是整個管理視窗
	# 用最多的共用函式(幾乎每個分頁的每個區段標題都靠它),明著翻譯,一次修全部呼叫點。
	label.text = TranslationServer.translate(text)
	label.add_theme_font_size_override("font_size", 17)
	return label


## 給所有視窗化編輯器用的主題:配色、字體、字級跟著「程式設定」分頁的外觀設定(見 AppSettings.build_theme),含只有滾輪的細捲軸。
static func make_theme() -> Theme:
	return AppSettings.build_theme()
