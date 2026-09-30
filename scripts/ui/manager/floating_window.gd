class_name FloatingWindow
extends Window
## 浮動工具視窗的共用底層(管理視窗、測試者視窗):獨立的原生作業系統視窗(專案設定 embed_subwindows = false),
## 有自己的焦點與鍵盤輸入,永遠置頂(桌面覆蓋層是永遠置頂的全螢幕視窗,不置頂會被蓋在下面)。
##
## - 原生視窗的 position 是「不含標題列」的客戶區座標,直接放在 (0,0) 標題列會跑到螢幕外面,
##   所以開啟後依標題列實際高度把整個視窗推回可見範圍(place_on_screen)。
## - 標題列預設是自畫的(無邊框視窗,顏色可以在「全局設定」調,見 _install_title_bar);關掉設定就用系統標題列。build_title_bar() 只給需要一列標題文字的小視窗(TextPromptWindow)。
## - 使用者按叉叉(系統的或自畫的)都會呼叫 _request_close(),子類別可覆寫(例如未儲存變更時先詢問)。

const TITLE_BAR_FALLBACK_HEIGHT := 40
## 自訂標題列的高度、按鈕寬度,與視窗四邊/四角縮放感應條的粗細。
const CUSTOM_TITLE_HEIGHT := 34
const TITLE_BUTTON_WIDTH := 46
const RESIZE_STRIP := 5
const RESIZE_CORNER := 12

var _dragging := false
var _drag_mouse_start := Vector2i.ZERO
var _drag_window_start := Vector2i.ZERO
## 自訂標題列跟著配色(設定「視窗標題列跟著配色」開著時):自畫的標題列與內容區(見 _install_title_bar)。
var _title_bar: PanelContainer
var _title_label: Label
var _title_body: Control
var _title_height := 0
var _title_min_button: Button
var _title_close_button: Button
var _title_frame: Panel
var _title_version: Label


func setup_floating(window_title: String, window_size: Vector2i, window_min_size: Vector2i) -> void:
	title = window_title
	size = window_size
	min_size = window_min_size
	always_on_top = AppSettings.floating_on_top()
	borderless = false
	transient = false
	exclusive = false
	theme = ManagerUi.make_theme()
	add_to_group("floating_windows")
	add_to_group("pet_occluders")   # 桌寵與行動區介面不會出現在浮動視窗上面(見 DesktopShell._occluder_polygons)
	_add_backdrop.call_deferred()
	close_requested.connect(_request_close)
	if AppSettings.themed_title_bar():
		_install_title_bar.call_deferred()
	place_on_screen.call_deferred()


## 視窗底色:視窗本身沒有背景色(沒鋪底的地方是黑的),所以墊一塊跟著編輯器配色的底(z_index 壓到最底,子類別自己鋪的背景照樣蓋在上面)。
## 延後一格加,這樣它是最後一個子節點,不會改變子類別內容在 get_child() 的順序。
func _add_backdrop() -> void:
	if not is_inside_tree() or get_node_or_null("ThemedBackdrop") != null:
		return
	var backdrop := Panel.new()
	backdrop.name = "ThemedBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.z_index = -100
	add_child(backdrop)


## 自訂標題列(跟著配色):作業系統的標題列顏色 Godot 改不了(Windows 10 只跟系統強調色),所以改成無邊框視窗,自己畫一條標題列
## (標題文字、最小化、關閉),四邊與四角有縮放用的感應條;顏色來自 AppSettings.title_bar_colors(),配色改了 refresh_theme() 會立刻跟著變。
## 子類別建好的內容整個放進標題列下面的內容區(不會被蓋住);視窗總高度加上標題列高度,內容能用的大小不變。forced_height > 0 是測試用。
func _install_title_bar(forced_height := 0) -> void:
	if _title_bar != null or not is_inside_tree():
		return
	_title_height = forced_height if forced_height > 0 else CUSTOM_TITLE_HEIGHT
	borderless = true
	_title_body = Control.new()
	_title_body.name = "TitleBody"
	_title_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_body.offset_top = _title_height
	_title_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_body)
	for child in get_children():
		if child is Control and child != _title_body:
			child.reparent(_title_body, false)
	_title_bar = PanelContainer.new()
	_title_bar.name = "ThemedTitleBar"
	_title_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title_bar.offset_bottom = _title_height
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_title_bar.gui_input.connect(_on_themed_title_input)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_title_bar.add_child(row)
	_title_label = Label.new()
	_title_label.text = title
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_title_label)
	row.add_child(pad)
	_title_version = Label.new()
	_title_version.text = "v" + CreditsData.version()
	_title_version.name = "TitleVersion"
	_title_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_version.add_theme_font_size_override("font_size", 12)
	_title_version.add_theme_constant_override("outline_size", 0)
	row.add_child(_title_version)
	var version_gap := Control.new()
	version_gap.custom_minimum_size.x = 8.0
	version_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(version_gap)
	_title_min_button = _make_title_button("—", "最小化(從系統匣選單再開一次就會回來)", minimize_to_tray)
	row.add_child(_title_min_button)
	_title_close_button = _make_title_button("✕", "關閉", _request_close)
	row.add_child(_title_close_button)
	add_child(_title_bar)
	# 一圈細邊框(無邊框視窗貼在桌面上需要一條邊界),放在最上面、不擋滑鼠。
	_title_frame = Panel.new()
	_title_frame.name = "TitleFrame"
	_title_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_frame)
	_install_resize_strips()
	min_size = Vector2i(min_size.x, min_size.y + _title_height)
	size = Vector2i(size.x, size.y + _title_height)
	_apply_title_colors()
	var sync := Timer.new()
	sync.wait_time = 0.25
	sync.autostart = true
	sync.timeout.connect(func() -> void:
		if _title_label != null and _title_label.text != title:
			_title_label.text = title)
	add_child(sync)


func _make_title_button(text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(TITLE_BUTTON_WIDTH, 0)
	button.pressed.connect(action)
	return button


## 四邊與四角的縮放感應條(無邊框視窗沒有系統的縮放邊):按下去交給作業系統接手縮放。
func _install_resize_strips() -> void:
	var edges := [
		[DisplayServer.WINDOW_EDGE_LEFT, Control.PRESET_LEFT_WIDE, Control.CURSOR_HSIZE],
		[DisplayServer.WINDOW_EDGE_RIGHT, Control.PRESET_RIGHT_WIDE, Control.CURSOR_HSIZE],
		[DisplayServer.WINDOW_EDGE_BOTTOM, Control.PRESET_BOTTOM_WIDE, Control.CURSOR_VSIZE],
		[DisplayServer.WINDOW_EDGE_TOP, Control.PRESET_TOP_WIDE, Control.CURSOR_VSIZE],
	]
	for entry: Array in edges:
		var strip := Control.new()
		strip.name = "ResizeStrip%d" % int(entry[0])
		strip.set_anchors_and_offsets_preset(int(entry[1]))
		match int(entry[1]):
			Control.PRESET_LEFT_WIDE:
				strip.offset_right = RESIZE_STRIP
			Control.PRESET_RIGHT_WIDE:
				strip.offset_left = -RESIZE_STRIP
			Control.PRESET_BOTTOM_WIDE:
				strip.offset_top = -RESIZE_STRIP
			Control.PRESET_TOP_WIDE:
				strip.offset_bottom = RESIZE_STRIP
		strip.mouse_default_cursor_shape = int(entry[2]) as Control.CursorShape
		strip.gui_input.connect(_on_resize_strip_input.bind(int(entry[0])))
		add_child(strip)
	var corners := [
		[DisplayServer.WINDOW_EDGE_TOP_LEFT, Control.PRESET_TOP_LEFT, Control.CURSOR_FDIAGSIZE],
		[DisplayServer.WINDOW_EDGE_TOP_RIGHT, Control.PRESET_TOP_RIGHT, Control.CURSOR_BDIAGSIZE],
		[DisplayServer.WINDOW_EDGE_BOTTOM_LEFT, Control.PRESET_BOTTOM_LEFT, Control.CURSOR_BDIAGSIZE],
		[DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.CURSOR_FDIAGSIZE],
	]
	for entry: Array in corners:
		var corner := Control.new()
		corner.name = "ResizeCorner%d" % int(entry[0])
		corner.set_anchors_and_offsets_preset(int(entry[1]))
		corner.custom_minimum_size = Vector2(RESIZE_CORNER, RESIZE_CORNER)
		match int(entry[1]):
			Control.PRESET_TOP_LEFT:
				corner.offset_right = RESIZE_CORNER
				corner.offset_bottom = RESIZE_CORNER
			Control.PRESET_TOP_RIGHT:
				corner.offset_left = -RESIZE_CORNER
				corner.offset_bottom = RESIZE_CORNER
			Control.PRESET_BOTTOM_LEFT:
				corner.offset_right = RESIZE_CORNER
				corner.offset_top = -RESIZE_CORNER
			Control.PRESET_BOTTOM_RIGHT:
				corner.offset_left = -RESIZE_CORNER
				corner.offset_top = -RESIZE_CORNER
		corner.mouse_default_cursor_shape = int(entry[2]) as Control.CursorShape
		corner.gui_input.connect(_on_resize_strip_input.bind(int(entry[0])))
		add_child(corner)


func _on_resize_strip_input(event: InputEvent, edge: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_DRAG):
		DisplayServer.window_start_resize(edge as DisplayServer.WindowResizeEdge, get_window_id())


func _apply_title_colors() -> void:
	if _title_bar == null:
		return
	var colors := AppSettings.title_bar_colors()
	var background: Color = colors["bg"]
	var text_color: Color = colors["text"]
	var style := StyleBoxFlat.new()
	style.bg_color = background
	_title_bar.add_theme_stylebox_override("panel", style)
	_title_label.add_theme_color_override("font_color", text_color)
	if _title_version != null:
		_title_version.add_theme_color_override("font_color", Color(text_color, 0.65))
	_title_label.text = title
	for button: Button in [_title_min_button, _title_close_button]:
		var danger := button == _title_close_button
		for state in ["normal", "hover", "pressed"]:
			var box := StyleBoxFlat.new()
			match state:
				"normal":
					box.bg_color = Color(text_color, 0.0)
				"hover":
					box.bg_color = Color("#c42b1c") if danger else Color(text_color, 0.2)
				"pressed":
					box.bg_color = Color("#a02318") if danger else Color(text_color, 0.32)
			button.add_theme_stylebox_override(state, box)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(color_name, Color.WHITE if danger and color_name != "font_color" else text_color)
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = background.lightened(0.15) if background.get_luminance() < 0.5 else background.darkened(0.25)
	frame.set_border_width_all(1)
	_title_frame.add_theme_stylebox_override("panel", frame)


## 拖曳標題列 = 移動視窗(交給作業系統接手,可以貼邊縮放);系統不支援時退回自己算滑鼠位移。
func _on_themed_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_DRAG):
			DisplayServer.window_start_drag(get_window_id())
		else:
			_on_title_bar_input(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_on_title_bar_input(event)

## 外觀設定(配色、字體、字級)改了之後重新套用主題;「程式設定」分頁用 call_group("floating_windows", "refresh_theme") 通知所有開著的編輯器視窗。
func refresh_theme() -> void:
	theme = ManagerUi.make_theme()
	_apply_title_colors()


## 最小化:無邊框視窗在工作列沒有圖示,作業系統的最小化會讓它整個消失、叫不回來,所以改成「藏起來」;
## 從系統匣選單再開同一個視窗(bring_to_front)就會顯示出來,內容與位置都還在。
func minimize_to_tray() -> void:
	hide()


## 把視窗叫到前景:藏起來(最小化)的先顯示、系統最小化的先還原,再取得焦點。系統匣選單「開啟…」對已經開著的視窗都走這裡。
func bring_to_front() -> void:
	if mode == Window.MODE_MINIMIZED:
		mode = Window.MODE_WINDOWED
	if not visible:
		show()
	grab_focus()
	DisplayServer.window_move_to_foreground(get_window_id())


## 全局設定改了「浮動視窗保持最上層」之後,用 call_group("floating_windows", "refresh_on_top") 通知所有視窗。
func refresh_on_top() -> void:
	var wanted := AppSettings.floating_on_top()
	if always_on_top == wanted:
		return
	if not visible or mode == Window.MODE_MINIMIZED:
		always_on_top = wanted
		return
	# 開著的視窗在執行中直接改置頂旗標,Windows 會把它排到主視窗(全螢幕透明、永遠置頂)後面而收不到滑鼠(實機回報只有全局設定會中,因為切換就是在它裡面按的);
	# 新開的視窗是「先設好旗標再顯示」就正常,所以這裡也照同樣的順序:先藏起來、改旗標、再顯示並取得焦點。
	_recycle_on_top.call_deferred(wanted)


func _recycle_on_top(wanted: bool) -> void:
	if not is_inside_tree():
		return
	var was_position := position
	hide()
	always_on_top = wanted
	show()
	position = was_position
	grab_focus()
	DisplayServer.window_move_to_foreground(get_window_id())


## 「浮動視窗重設」:顯示(藏起來或系統最小化的也叫回來)、拉到最上層、確保整個視窗在某個螢幕的可用範圍內(被其他程式蓋住、跑到螢幕外都救得回來)。
func reset_window() -> void:
	if mode == Window.MODE_MINIMIZED:
		mode = Window.MODE_WINDOWED
	if not visible:
		show()
	always_on_top = false   # 先放掉再設回去,Windows 才會重新排到最上層
	always_on_top = AppSettings.floating_on_top()
	ensure_on_screen()
	grab_focus()
	DisplayServer.window_move_to_foreground(get_window_id())


## 主行動區換了螢幕(見 DesktopShell.apply_monitor_setting()):這個視窗跟著搬過去,依舊螢幕→新螢幕的
## 比例維持相對位置(不是直接置中),搬完再照 ensure_on_screen() 夾一次(位置算出來理論上就在新螢幕內,
## 這裡是防呆,以防兩個螢幕可用範圍差很多算出界外)。
func move_to_screen(new_screen_index: int, old_screen_rect: Rect2i, new_screen_rect: Rect2i) -> void:
	if old_screen_rect.size.x <= 0 or old_screen_rect.size.y <= 0:
		return
	var relative := Vector2(position - old_screen_rect.position)
	var scale := Vector2(new_screen_rect.size) / Vector2(old_screen_rect.size)
	position = new_screen_rect.position + Vector2i(relative * scale)
	current_screen = new_screen_index
	ensure_on_screen()


## 把視窗拉回最接近它的螢幕的可用範圍內(必要時縮小到放得下);標題列(客戶區上方)不會跑到螢幕外。
func ensure_on_screen() -> void:
	var rects: Array[Rect2i] = []
	for screen in DisplayServer.get_screen_count():
		rects.append(DisplayServer.screen_get_usable_rect(screen))
	var target := FloatingWindow.fit_into_screens(Rect2i(position, size), rects, 0 if borderless else TITLE_BAR_FALLBACK_HEIGHT)
	size = target.size
	position = target.position


## 純計算:把矩形 rect 放進 screens 裡和它重疊最多(都不重疊就取離它最近)的那一塊螢幕可用範圍;放不下就縮小,top_margin 是視窗上方要留給系統標題列的高度。
static func fit_into_screens(rect: Rect2i, screens: Array[Rect2i], top_margin := 0) -> Rect2i:
	var valid: Array[Rect2i] = []
	for screen_rect in screens:
		if screen_rect.has_area():
			valid.append(screen_rect)
	if valid.is_empty():
		return rect
	var chosen := valid[0]
	var best_overlap := -1
	var best_distance := INF
	for usable in valid:
		var overlap := usable.intersection(rect)
		var area := overlap.size.x * overlap.size.y if overlap.has_area() else 0
		var distance := Vector2(usable.get_center() - rect.get_center()).length()
		if area > best_overlap or (area == best_overlap and area == 0 and distance < best_distance):
			best_overlap = area
			best_distance = distance
			chosen = usable
	var size_fit := Vector2i(mini(rect.size.x, chosen.size.x), mini(rect.size.y, maxi(chosen.size.y - top_margin, 1)))
	var top_left := Vector2i(
			clampi(rect.position.x, chosen.position.x, maxi(chosen.end.x - size_fit.x, chosen.position.x)),
			clampi(rect.position.y, chosen.position.y + top_margin, maxi(chosen.end.y - size_fit.y, chosen.position.y + top_margin)))
	return Rect2i(top_left, size_fit)


## 開系統的檔案對話框:開著的時候把其他浮動視窗暫時放掉置頂,免得它們把選取器整個蓋住(對話框關掉就恢復)。
## parent_id 是對話框所屬的視窗(0 = 主視窗);為了讓對話框一定在最上面,所有浮動視窗(包含所屬視窗)在對話框開著時都暫時不置頂。回傳 DisplayServer.file_dialog_show 的結果(不支援時已經自己恢復)。
static func native_file_dialog(title_text: String, start_dir: String, dialog_mode: DisplayServer.FileDialogMode, filters: PackedStringArray, on_picked: Callable, parent_id := 0, default_name := "") -> Error:
	var lowered: Array[FloatingWindow] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node in tree.get_nodes_in_group("floating_windows"):
			var window := node as FloatingWindow
			# 連對話框所屬的視窗(parent_id)也一起放掉置頂:所屬視窗還是置頂的話,系統的檔案對話框會被它壓在下面(實機回報)。所屬關係還在,對話框照樣認得它。
			if window != null and window.always_on_top:
				window.always_on_top = false
				lowered.append(window)
	var restore := func() -> void:
		for window in lowered:
			if is_instance_valid(window):
				window.always_on_top = AppSettings.floating_on_top()
				if window.get_window_id() == parent_id and window.visible:
					window.grab_focus()
	var callback := func(status: bool, paths: PackedStringArray, _filter: int) -> void:
		restore.call()
		if status and not paths.is_empty():
			on_picked.call(paths)
	# 2026-09-30 使用者實機回報:從「桌寵管理」「角色庫」這類視窗匯出/匯入檔案,對話框開著時整個視窗
	# 卡死不能動(程式其他部分正常)。系統匣選單觸發的「導出 Schema…」用的是同一個函式,parent_id 一直
	# 是 0,沒有這個問題——懷疑是系統原生對話框指定 parent_id 給這個專案「自畫、無邊框」的浮動視窗時,
	# 在某些環境下對話框沒有正常取得焦點或顯示位置,變成一個看不見、但仍然強制回應的原生視窗,體感就是
	# 那個視窗卡死了。傳給 DisplayServer 的 parent_id 一律用 0(不指定特定視窗),呼叫端原本傳進來的
	# parent_id 只留著給上面 restore() 的「對話框關閉後幫這個視窗搶回焦點」這個小功能用,不影響對話框
	# 本體的顯示行為,兩者互不相干。
	var result := DisplayServer.file_dialog_show(title_text, start_dir, default_name, false, dialog_mode, filters, callback, 0)
	if result != OK:
		restore.call()
	return result


## 2026-09-30 使用者實機驗證過「host 置頂時撐滿對話框整個生命週期暫時放掉置頂」這條路(舊版 _lower_until_hidden,
## 已移除):對話框開著的整段期間自動重開置頂,反而比手動更不穩定(視窗會閃一下、從工作列消失),所以後來乾脆把
## 浮動視窗的「保持在最上層」整個關掉(AppSettings.floating_on_top() 恆回傳 false)。
## 2026-09-29 改用另一個方向:根本不讓對話框變成 host 的 transient 子視窗。查證 godotengine/godot#117698 的
## 官方說法(開發者原話:"setting both transient and always on top is not valid"),真正衝突的不是「host 置頂」
## 這件事本身,是「transient 子視窗」跟「on top」這兩個狀態不能同時成立在同一個視窗上——不管是哪一邊先設的。
## 只要對話框從頭到尾都不是 transient,host 置不置頂就完全不相干,不需要再撐生命週期、不需要 visibility_changed
## 這種偵測收尾的花招。代價是對話框失去引擎內建的「自動疊在 host 正上方、host 關掉/最小化時跟著收」這些行為,
## 這裡手動補回定位(疊在 top_window 所在的螢幕正中央,不是隨機亂跑)與搶前景兩件事。
## 所有 ConfirmationDialog/AcceptDialog 都要透過這個函式顯示,不要自己呼叫 add_child() + popup_centered()。
## parent = 對話框要掛在場景樹的哪個節點底下(大多數呼叫端傳 self 就好);top_window = 對話框要疊在哪個視窗
## 正中央——FloatingWindow 子類別自己就是 Window,parent 跟 top_window 通常是同一個(self);DesktopShell
## 不是 Window(它操作的是 get_window()),parent 傳 self、top_window 要另外傳 get_window()。
static func popup_child_dialog(parent: Node, top_window: Window, dialog: Window, popup_size := Vector2i.ZERO) -> void:
	if dialog.get_parent() == null:
		parent.add_child(dialog)
	dialog.transient = false
	dialog.current_screen = top_window.current_screen
	if popup_size == Vector2i.ZERO:
		dialog.popup_centered()
	else:
		dialog.popup_centered(popup_size)
	# popup_centered() 自己內部會把 transient 又設回 true(實機測出來的,不是理論上的——2026-09-29 用
	# debug_screenshot_transient.gd 的偵錯場景印出 DIALOG_READY 那行,設 false 後呼叫 popup_centered()
	# 照樣量到 transient=true),彈出來之後要再蓋回去一次才會真的生效。
	dialog.transient = false
	_bring_dialog_forward(dialog, top_window)


## 跟 popup_child_dialog() 同一件事,給要用 popup_centered_clamped()(限制在螢幕範圍內)的呼叫端用。
static func popup_child_dialog_clamped(parent: Node, top_window: Window, dialog: Window, popup_size: Vector2i, ratio: float) -> void:
	if dialog.get_parent() == null:
		parent.add_child(dialog)
	dialog.transient = false
	dialog.current_screen = top_window.current_screen
	dialog.popup_centered_clamped(popup_size, ratio)
	dialog.transient = false
	_bring_dialog_forward(dialog, top_window)


## 不是 transient 就不會自動疊在 top_window 正上方、也不會自動搶到焦點,這裡手動補回來。position 先照
## top_window 的位置重新置中一次(popup_centered() 只認得 current_screen,不知道 top_window 實際在螢幕上
## 哪個位置,多視窗時可能偏掉);grab_focus/搶前景與再次確認 transient 要 call_deferred,等這一幀真的建好
## 原生視窗才有 window id、也才追得到 popup_centered() 那個延後一幀生效的 transient=true。
static func _bring_dialog_forward(dialog: Window, top_window: Window) -> void:
	var host_rect := Rect2i(top_window.position, top_window.size)
	var centered := host_rect.position + (host_rect.size - dialog.size) / 2
	var rects: Array[Rect2i] = []
	for screen in DisplayServer.get_screen_count():
		rects.append(DisplayServer.screen_get_usable_rect(screen))
	dialog.position = fit_into_screens(Rect2i(centered, dialog.size), rects).position
	dialog.grab_focus.call_deferred()
	_foreground_deferred.call_deferred(dialog)
	# 2026-09-30 使用者實機回報「角色庫>編輯圖像>匯入圖片>小彈窗>確認」按下去卡死,查出來是另一個獨立的坑:
	# transient=false 解決了 #117698 那種真的卡死(整個引擎卡住),但無邊框自畫標題列的 FloatingWindow
	# host 用真的滑鼠點擊(不是程式模擬)關掉這種不再 transient 的對話框後,host 在作業系統層級會變成
	# 「看不見」(IsWindowVisible=false),Godot 自己的 window.visible 卻還讀到 true,兩邊狀態對不上,
	# 使用者感受就是視窗憑空消失——用 debug_screenshot_packimport.gd 偵錯場景 + 真滑鼠點擊 + Win32
	# EnumWindows 查證過,不是理論推測。已知解法是host 自己 hide() 再 show() 一次(Godot 會重建原生視窗,
	# 新視窗沒有這個殘留問題),FloatingWindow.reset_window() 剛好就是做這件事,所以這裡讓對話框關掉的那一刻
	# 自動幫 top_window 重新整理一次,不用等使用者發現視窗不見了才手動去系統匣按「浮動視窗重設」。
	# 只對 FloatingWindow 這樣做——DesktopShell 的桌面覆蓋層(get_window(),同樣無邊框)不是 FloatingWindow,
	# 不會被這裡影響到;它自動重開置頂已經實測過反而更不穩定(見上面的說明),沒有證據顯示它有一樣的問題,
	# 不要自作主張套用同一招。
	if not (top_window is FloatingWindow):
		return
	var handlers: Array[Callable] = [Callable(), Callable()]
	var heal := func() -> void:
		if is_instance_valid(dialog):
			if dialog.visibility_changed.is_connected(handlers[0]):
				dialog.visibility_changed.disconnect(handlers[0])
			if dialog.tree_exiting.is_connected(handlers[1]):
				dialog.tree_exiting.disconnect(handlers[1])
		# 2026-09-30 使用者實機回報第二個坑:精靈圖編輯器「叉叉 > 不儲存就關閉」之後,呼叫端(角色庫)卡死。
		# 查出來是這個自癒本身撞到的——guard_unsaved() 的「放棄變更並關閉」是同一個同步呼叫鏈裡先
		# hide() 對話框(觸發這裡)、緊接著馬上把 top_window 自己 queue_free() 掉,heal() 當下同步跑
		# hide()+show() 重建 top_window 的原生視窗,下一行馬上又把它整個釋放掉,兩件事卡在同一幀互踩。
		# 改成 call_deferred,讓「視窗自己要關掉」這件事(is_queued_for_deletion)先跑完,heal 執行的當下
		# 才判斷還在不在,不要在別人正要關掉視窗的同一瞬間硬去重建它的原生視窗。
		_heal_top_window.call_deferred(top_window)
	handlers[0] = func() -> void:
		if not dialog.visible:
			heal.call()
	handlers[1] = func() -> void:
		heal.call()
	dialog.visibility_changed.connect(handlers[0])
	dialog.tree_exiting.connect(handlers[1])


static func _heal_top_window(top_window: Window) -> void:
	if not is_instance_valid(top_window) or top_window.is_queued_for_deletion() or not top_window.is_inside_tree():
		return
	# 不能用 reset_window():它是 `if not visible: show()`,而這個 bug 剛好是 Godot 自己的
	# window.visible 讀到 true(騙過這個判斷),但作業系統層級其實是看不見的,一定要無條件
	# hide() 再 show() 一次(逼 Godot 重建原生視窗)才會真的修好,這裡直接照
	# WINDOW_INTERACT_TEST 偵錯場景驗證過有效的順序做,不透過 reset_window()。
	var was_position := top_window.position
	top_window.hide()
	if not is_instance_valid(top_window) or top_window.is_queued_for_deletion():
		return
	top_window.show()
	top_window.position = was_position
	(top_window as FloatingWindow).ensure_on_screen()
	top_window.grab_focus()
	DisplayServer.window_move_to_foreground(top_window.get_window_id())


static func _foreground_deferred(dialog: Window) -> void:
	if not is_instance_valid(dialog) or not dialog.visible:
		return
	dialog.transient = false
	var id := dialog.get_window_id()
	if id >= 0:
		DisplayServer.window_move_to_foreground(id)


## 使用者要關閉視窗時呼叫(系統叉叉或自畫的 ✕)。預設直接關,子類別可覆寫。
func _request_close() -> void:
	queue_free()


## 2026-09-30 使用者實機回報:精靈圖編輯器「叉叉 > 有未存的變更 > 放棄變更並關閉」置頂開著時還是會卡死
## (不是對話框關閉那一刻,是整個視窗真的被釋放的那一刻)。對話框關閉時的自癒(見 _bring_dialog_forward())
## 已經排除了跟這次釋放搶同一幀的可能;剩下的懷疑是另一個方向——銷毀一個仍然「置頂」的原生視窗本身,可能讓
## Windows 需要重新分配置頂焦點鏈結,而 Godot 的 DisplayServer 處理「銷毀置頂視窗」跟處理「transient + 置頂」
## 一樣不乾淨,連帶讓其他置頂視窗(角色庫)也卡住。NOTIFICATION_PREDELETE 是原生視窗真的被摧毀之前最後
## 收得到的通知,這裡先把置頂旗標放掉,給 Windows 一個乾淨的時機處理焦點轉移,再讓視窗真的被釋放。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and always_on_top:
		always_on_top = false


## 自畫標題列:可拖曳整個視窗,右邊 ✕ 關閉。
func build_title_bar(text: String) -> Control:
	var bar := PanelContainer.new()
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_title_bar_input)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var label := Label.new()
	label.text = "  ⠿ " + text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var close := ManagerUi.button("✕")
	close.tooltip_text = "關閉"
	close.pressed.connect(_request_close)
	row.add_child(close)
	return bar


func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_mouse_start = DisplayServer.mouse_get_position()
			_drag_window_start = position
	elif event is InputEventMouseMotion and _dragging:
		position = _drag_window_start + (DisplayServer.mouse_get_position() - _drag_mouse_start)


## 把視窗放到目前螢幕可用範圍的正中央,並確保系統標題列(在客戶區上方)不會跑到螢幕外。
## 視窗比螢幕可用範圍(扣掉標題列)還大時先縮小到放得下(小螢幕上視窗底部會被工作列或螢幕邊緣吃掉,底下的按鈕與說明文字就看不到了)。
func place_on_screen(offset := Vector2i.ZERO) -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(0))
	var deco_top := TITLE_BAR_FALLBACK_HEIGHT
	var id := get_window_id()
	if id >= 0:
		var client := DisplayServer.window_get_position(id)
		var outer := DisplayServer.window_get_position_with_decorations(id)
		deco_top = 0 if borderless else (maxi(client.y - outer.y, 0) if client.y != outer.y else TITLE_BAR_FALLBACK_HEIGHT)
	var room := Vector2i(usable.size.x, usable.size.y - deco_top)
	if room.x > 0 and room.y > 0:
		min_size = Vector2i(mini(min_size.x, room.x), mini(min_size.y, room.y))
		size = Vector2i(mini(size.x, room.x), mini(size.y, room.y))
	var target := usable.position + (usable.size - size) / 2 + offset
	target.y = maxi(target.y, usable.position.y + deco_top)
	target.x = clampi(target.x, usable.position.x, maxi(usable.end.x - size.x, usable.position.x))
	position = target
