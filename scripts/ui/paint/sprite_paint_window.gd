class_name SpritePaintWindow
extends FloatingWindow
## 精靈圖編輯器的繪圖視窗(2026-10-22 第一期,使用者的規格見記憶「精靈圖繪圖功能評估」):從精靈圖編輯器開,
## 畫的是一個動作的每一幀、或一個圖層的每一張圖(角色、道具、家具都是同一個精靈圖編輯器,所以三種都能畫)。
## 左邊工具(畫筆、橡皮擦、吸色、油漆桶、範圍選取、魔術棒、套索、直線、矩形、橢圓、漸層、平移)、工具設定與繪圖圖層;
## 中間畫布(PaintCanvas);右邊主副色、固定在介面上的選色器(跟其他功能一樣是 Godot 的 ColorPicker,可以輸入色碼)與色票。
## 繪圖圖層(第二期):套用時合併成一張圖交回去,各層另外交給呼叫端存成側檔(edits 的 layers),下次開啟再拆回來。
## 畫完按「套用」(Ctrl+S)把改過的頁交回精靈圖編輯器(發 apply_requested),在那邊變成新的圖檔、可以撤回,
## 再在精靈圖編輯器存檔才會寫進素材包。沒套用就關視窗會先問。
## 畫筆、橡皮擦、吸色的按鈕按右鍵 = 綁到畫布的右鍵(虛線框;一次只有一個,再按一次取消,取消後右鍵是畫筆畫副色)。
## 快捷鍵全部是單一按鍵或 Ctrl 組合,繪圖板驅動程式可以照這個程式(執行檔)設定快捷鍵,表見「⌨ 快捷鍵」。

## 套用:edits = [{page: 頁的索引, image: 合併後的圖, layers: 繪圖圖層(只有一層時是空陣列,見 PaintDocument.layer_entries)}]
## (只有改過的頁)。呼叫端處理完呼叫 applied()。
signal apply_requested(edits: Array)

## [工具, 圖示, 按鈕上的名字, 說明, 能不能綁到右鍵]。兩個一排(套索跟範圍選取同一排);圖示只用 Windows 10 也有的 emoji
## (🪣 油漆桶、🪄 魔術棒是 Emoji 13,2026-10-23 使用者回報 Windows 顯示不出來)。
const TOOLS: Array = [
	["brush", "✏", "畫筆", "畫筆(B)\n右鍵這個按鈕:把畫筆綁到畫布的右鍵(畫副色)", true],
	["eraser", "🧽", "橡皮擦", "橡皮擦(E)\n右鍵這個按鈕:把橡皮擦綁到畫布的右鍵(用畫筆的尺寸與筆刷類型擦)", true],
	["picker", "💧", "吸色", "吸色(I):吸到主色(要不要連透明度一起吸,看左邊吸色的設定)\n右鍵這個按鈕:把吸色綁到畫布的右鍵", true],
	["fill", "🛢", "油漆桶", "油漆桶(G):把相連、顏色完全一樣的範圍填上主色", false],
	["select", "⬚", "範圍選取", "範圍選取(M):拖曳框選;拖曳選取範圍裡面可以移動內容\nShift + 拖曳 = 加選,Ctrl + 拖曳 = 減選", false],
	["lasso", "➰", "套索", "套索(F):按著拖曳圈出範圍,放開就選取\nShift = 加選,Ctrl = 減選", false],
	["wand", "✨", "魔術棒", "魔術棒(W):點一下選取顏色相近的範圍(看目前的繪圖圖層)\nShift + 點 = 加選,Ctrl + 點 = 減選", false],
	["gradient", "🌈", "漸層", "漸層(D):拖曳畫出主色漸變到副色的漸層(有選取時只填選取範圍,沒有就填整個繪圖圖層)\nShift = 鎖定 45 度", false],
	["line", "╱", "直線", "直線(L):拖曳畫直線,用畫筆的尺寸與筆刷類型\nShift = 鎖定 45 度", false],
	["rect", "▭", "矩形", "矩形(R):拖曳畫矩形外框或填滿的矩形\nShift = 正方形", false],
	["ellipse", "◯", "橢圓", "橢圓(C):拖曳畫橢圓外框或填滿的橢圓\nShift = 正圓", false],
	["pan", "✋", "平移", "平移(H):拖曳移動畫面(任何工具按住空白鍵或中鍵也可以)", false],
	["canvas", "📐", "畫布尺寸", "畫布尺寸(K):拖曳畫布的四邊或四角調整範圍,或在左邊輸入寬高;按「套用尺寸」(Enter)才會改,Esc 還原", false],
]
## 工具的快捷鍵(沒有 Ctrl、沒有 Shift)。
const TOOL_KEYS := {KEY_B: "brush", KEY_E: "eraser", KEY_I: "picker", KEY_G: "fill", KEY_M: "select", KEY_W: "wand",
		KEY_F: "lasso", KEY_L: "line", KEY_R: "rect", KEY_C: "ellipse", KEY_D: "gradient", KEY_H: "pan", KEY_K: "canvas"}
const SHORTCUTS: Array = [
	["B", "畫筆"], ["E", "橡皮擦"], ["I", "吸色"], ["G", "油漆桶"], ["M", "範圍選取"], ["W", "魔術棒"], ["F", "套索"],
	["L", "直線"], ["R", "矩形"], ["C", "橢圓"], ["D", "漸層"], ["H", "平移"], ["K", "畫布尺寸(Enter 套用、Esc 還原)"], ["Shift + F", "形狀外框 / 填滿切換"],
	["空白鍵(按住)", "暫時平移"], ["Alt + 左鍵", "暫時吸色"], ["Shift + 點", "從上一筆的終點拉直線"],
	["Shift / Ctrl + 選取", "加選 / 減選"], ["Ctrl + I", "反轉選取範圍"],
	["Shift + H / Shift + V", "水平 / 垂直翻轉(選取範圍,沒選取 = 整個繪圖圖層)"], ["Shift + R / Shift + T", "順時針 / 逆時針轉 90 度"],
	["Shift + N", "新增繪圖圖層"], ["Shift + M", "向下合併繪圖圖層"], ["/", "鎖定透明度開關(目前的繪圖圖層)"], ["Shift + C", "向下剪裁開關(目前的繪圖圖層)"], ["Alt + ↑ / Alt + ↓", "選上面 / 下面的繪圖圖層"],
	["[ / ]", "目前工具的尺寸 −1 / +1"], ["X", "交換主色與副色"], ["Q", "切換覆蓋 / 疊色"],
	[", / .(或 PageUp / PageDown)", "上一幀 / 下一幀"], ["Shift + D / Shift + B", "在後面新增一幀:複製這一幀 / 空白幀(畫動作的幀時)"], ["O", "洋蔥皮開關"], ["Shift + G", "像素格線開關"],
	["+ / −", "放大 / 縮小"], ["Ctrl + 0", "整張放進畫面"], ["Ctrl + 1", "100%"],
	["Ctrl + Z", "撤回"], ["Ctrl + Y / Ctrl + Shift + Z", "重做"],
	["Ctrl + A", "全選"], ["Ctrl + D / Esc", "取消選取(浮動的內容會放下)"], ["Enter", "放下浮動的內容"],
	["方向鍵", "移動選取的內容 1 像素(Shift = 10)"], ["Delete", "清除選取範圍"],
	["Ctrl + C / Ctrl + X", "複製 / 剪下(可以換一幀再貼)"], ["Ctrl + V", "貼上"], ["Ctrl + Shift + V", "貼上外部圖片(別的軟體複製的)"],
	["Ctrl + S", "套用到精靈圖編輯器"],
	["繪圖筆的筆尾", "橡皮擦"],
]
const SWATCH_SIZE := Vector2(22, 22)
const SWATCH_GAP := 3

## 開著的繪圖視窗數(見 _sync_painting)。
static var _open_count := 0
var _counted := false

var _doc := PaintDocument.new()
var _canvas: PaintCanvas
var _settings: Dictionary = {}
## 頁的編號(PaintDocument.page_ids)→ 名字 / 軸心(新增頁之後頁的位置會變,所以照編號記)。
var _label_of := {}
var _marker_of := {}
## 能不能新增幀(畫動作的幀時呼叫端打開;畫圖層的圖時不行)。frame_label_action 不是空的時,頁名照位置顯示「動作 第 N 幀」。
var can_add_pages := false
var frame_label_action := ""
var _add_page_buttons: Array[Button] = []
var _tool_buttons: Dictionary = {}
var _tool_group := ButtonGroup.new()
var _brush_size: SpinBox
var _brush_type: OptionButton
var _eraser_size: SpinBox
var _eraser_type: OptionButton
var _blend_option: OptionButton
var _size_pressure: CheckBox
var _opacity_pressure: CheckBox
var _eraser_size_pressure: CheckBox
var _eraser_opacity_pressure: CheckBox
var _option_groups: Dictionary = {}
var _brush_stabilizer: SpinBox
var _eraser_stabilizer: SpinBox
var _canvas_width: SpinBox
var _canvas_height: SpinBox
var _canvas_scope: OptionButton
var _canvas_info: Label
var _anchor_buttons: Array[Button] = []
## 輸入寬高時內容靠哪裡:(0 / 0.5 / 1, 0 / 0.5 / 1),預設置中。
var _canvas_anchor := Vector2(0.5, 0.5)
var _checker_button: Button
var _onion_check: CheckBox
var _grid_check: CheckBox
var _reference_check: CheckBox
var _key_check: CheckBox
var _shape_filled: CheckBox
var _gradient_kind: OptionButton
var _gradient_steps: SpinBox
var _gradient_dither: CheckBox
var _wand_tolerance: SpinBox
var _wand_contiguous: CheckBox
var _pick_alpha: CheckBox
var _layer_list: VBoxContainer
var _layer_opacity: SpinBox
var _layer_alpha_lock: CheckBox
var _layer_clip: CheckBox
var _layer_buttons: Dictionary = {}
var _layer_key: Variant = null
var _key_color: ColorPickerButton
var _slot_buttons: Array[Button] = []
var _active_slot := 0
var _picker: ColorPicker
var _palette: PaintPalette
var _palette_saved: PaintPalette
var _palette_option: OptionButton
var _palette_state: Label
var _swatch_box: GridContainer
var _page_label: Label
var _zoom_label: Label
var _status: Label
var _hover_label: Label
var _apply_button: Button
var _undo_button: Button
var _redo_button: Button
var _updating := false
var _fitted := false
## 「💾 另存圖檔」預設的檔名(呼叫端設成動作或圖層的名字)。
var export_name := "paint"


## 開啟要畫的圖。images:每一頁的圖;labels:每一頁的名字(顯示在頁碼旁);markers:每一頁的軸心(Vector2 或 null);
## references:每一頁墊在底下的參考圖({texture, offset} 或 null);page_layers:每一頁上次存的繪圖圖層(見 PaintDocument.setup)。
func setup(title_text: String, images: Array, labels: Array, start_index := 0, markers: Array = [], references: Array = [], page_layers: Array = []) -> void:
	setup_floating(title_text, Vector2i(1180, 820), Vector2i(900, 600))
	_settings = PaintSettings.load_all()
	_doc.setup(images, start_index, page_layers)
	_label_of.clear()
	_marker_of.clear()
	for p in images.size():
		_label_of[p] = str(labels[p]) if p < labels.size() else ""
		_marker_of[p] = markers[p] if p < markers.size() else null
	_build()
	_sync_markers()
	_canvas.references = references
	_reference_check.visible = references.any(func(r: Variant) -> bool: return r is Dictionary)
	_canvas.set_document(_doc)
	_doc.changed.connect(_on_doc_changed)
	_apply_settings_to_canvas()
	_select_tool("brush")
	_load_palette(str(_settings["palette"]))
	_refresh_slots()
	_on_doc_changed()
	_canvas.resized.connect(func() -> void:
		if not _fitted and _canvas.size.x > 0.0:
			_fitted = true
			_canvas.fit_view())
	_status.text = tr("左鍵畫主色、右鍵畫副色;滾輪縮放、按住空白鍵或中鍵拖曳平移。畫完按「套用」交回精靈圖編輯器(可以在那邊撤回)。")
	if is_inside_tree():
		_enter_painting()


func _enter_tree() -> void:
	if _doc.page_count() > 0:
		_enter_painting()


func _exit_tree() -> void:
	if _counted:
		_counted = false
		_open_count = maxi(_open_count - 1, 0)
		_sync_painting.call_deferred()


func _enter_painting() -> void:
	if _counted:
		return
	_counted = true
	_open_count += 1
	_sync_painting.call_deferred()


## 繪圖模式(2026-10-23 使用者回報作畫卡頓、筆刷游標慢半拍):有繪圖視窗開著的期間
## ① 自動勿擾(DesktopShellState.painting,疊加、不動使用者的開關),桌寵不會跳出要你回應的提問;
## ② 最高影格率至少 AppSettings.PAINT_FPS(平常 30,游標與筆畫要等下一格才畫出來);
## ③ 不合併滑鼠移動(Input.use_accumulated_input 預設會把一格內的移動併成一個,筆走得快時轉角會被切掉);
## ④ 關掉省電模式(專案設定 low_processor_mode 每格之間會睡一下,繪圖板的輸入要等醒來才處理,2026-10-23 使用者回報繪圖板鈍鈍的)。
## 最後一個繪圖視窗關掉就全部回到原本的樣子。
static func _sync_painting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var active := _open_count > 0
	Input.use_accumulated_input = not active
	OS.low_processor_usage_mode = false if active else bool(ProjectSettings.get_setting("application/run/low_processor_mode", false))
	var state := tree.root.get_node_or_null("DesktopShellState")
	if state != null and bool(state.painting) != active:
		state.painting = active
		tree.call_group("desktop_shell", "on_painting_changed", active)
	AppSettings.refresh_fps()


static func is_painting() -> bool:
	return _open_count > 0


func document() -> PaintDocument:
	return _doc


func canvas() -> PaintCanvas:
	return _canvas


# --- 介面 ---

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)
	page.add_child(_build_toolbar())
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	row.add_child(_build_left())
	_canvas = PaintCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.color_picked.connect(_on_color_picked)
	_canvas.hover_changed.connect(_on_hover_changed)
	_canvas.view_changed.connect(_refresh_zoom_label)
	_canvas.canvas_margins_changed.connect(_refresh_canvas_info)
	row.add_child(_canvas)
	row.add_child(_build_right())
	var bottom := HBoxContainer.new()
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(_status)
	_hover_label = Label.new()
	_hover_label.custom_minimum_size.x = 200.0
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_hover_label)
	page.add_child(bottom)
	var theme_colors: Dictionary = AppSettings.appearance()["colors"]
	_canvas.apply_theme_colors((theme_colors["bg"] as Color).lerp(theme_colors["text"], 0.05), theme_colors["text"])


func _build_toolbar() -> Control:
	var bar := HFlowContainer.new()
	_apply_button = ManagerUi.button("套用  Ctrl+S")
	_apply_button.tooltip_text = tr("把改過的幀(或圖片)交回精靈圖編輯器,變成新的圖檔。可以在精靈圖編輯器撤回;要在那邊存檔才會寫進素材包。")
	_apply_button.pressed.connect(apply_changes)
	_undo_button = ManagerUi.button("↶")
	_undo_button.tooltip_text = tr("撤回(Ctrl+Z)")
	_undo_button.pressed.connect(undo)
	_redo_button = ManagerUi.button("↷")
	_redo_button.tooltip_text = tr("重做(Ctrl+Y)")
	_redo_button.pressed.connect(redo)
	var previous := ManagerUi.button("◀")
	previous.tooltip_text = tr("上一幀(,)")
	previous.pressed.connect(func() -> void: go_page(-1))
	_page_label = Label.new()
	_page_label.custom_minimum_size.x = 150.0
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var next := ManagerUi.button("▶")
	next.tooltip_text = tr("下一幀(.)")
	next.pressed.connect(func() -> void: go_page(1))
	var copy_page := ManagerUi.button("📑")
	copy_page.tooltip_text = tr("在後面新增一幀:複製這一幀(Shift+D),每個繪圖圖層都複製。\n套用時才真的加進動作,軸心、圖片偏移、圖層與光源在這一幀的設定跟著複製(跟精靈圖編輯器的「複製一份」一樣)。")
	copy_page.pressed.connect(func() -> void: add_page(true))
	var blank_page := ManagerUi.button("⬜")
	blank_page.tooltip_text = tr("在後面新增一張同樣大小的空白幀(Shift+B)。套用時才真的加進動作,軸心放在底部中央。")
	blank_page.pressed.connect(func() -> void: add_page(false))
	_add_page_buttons = [copy_page, blank_page]
	_onion_check = CheckBox.new()
	_onion_check.text = tr("洋蔥皮")
	_onion_check.tooltip_text = tr("淡淡地顯示上一幀(紅)與下一幀(藍),方便對齊動作(O)。")
	_onion_check.toggled.connect(func(on: bool) -> void: _set_setting("onion", on))
	_grid_check = CheckBox.new()
	_grid_check.text = tr("格線")
	_grid_check.tooltip_text = tr("放大到 6 倍以上時顯示像素格線(Shift+G)。")
	_grid_check.toggled.connect(func(on: bool) -> void: _set_setting("grid", on))
	_reference_check = CheckBox.new()
	_reference_check.text = tr("底圖")
	_reference_check.tooltip_text = tr("畫圖層時,在底下淡淡地墊著精靈圖編輯器目前選的那一幀的本體,位置跟編輯器裡看到的一樣。\n在精靈圖編輯器換選別的幀,底圖跟著換(圖層的位置不動)。")
	_reference_check.toggled.connect(func(on: bool) -> void: _set_setting("reference", on))
	_checker_button = ManagerUi.button("☀")
	_checker_button.pressed.connect(func() -> void: _set_setting("checker_dark", not bool(_settings["checker_dark"])))
	var zoom_out := ManagerUi.button("−")
	zoom_out.tooltip_text = tr("縮小(−)")
	zoom_out.pressed.connect(func() -> void: _canvas.step_zoom(-1))
	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size.x = 56.0
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var zoom_in := ManagerUi.button("＋")
	zoom_in.tooltip_text = tr("放大(+)")
	zoom_in.pressed.connect(func() -> void: _canvas.step_zoom(1))
	var fit := ManagerUi.button("⤢")
	fit.tooltip_text = tr("整張放進畫面(Ctrl+0)")
	fit.pressed.connect(func() -> void: _canvas.fit_view())
	var paste_external := ManagerUi.button("📋 貼上外部圖片")
	paste_external.tooltip_text = tr("貼上在別的繪圖軟體複製的圖(Ctrl+Shift+V),透明的地方保持透明;貼上後可以拖曳移動,按 Enter 或點選取範圍外面放下。\n如果貼進來背景不透明,勾左邊「貼上外部圖片時把這個顏色變透明」並指定背景色。")
	paste_external.pressed.connect(paste_external_image)
	var save_png := MenuButton.new()
	save_png.text = tr("💾 另存圖檔")
	save_png.flat = false
	save_png.tooltip_text = tr("把畫的結果(各繪圖圖層合併後)另存成 PNG 放到電腦裡任何地方,不會改到素材包。")
	save_png.get_popup().add_item(tr("目前這一幀…"), 0)
	save_png.get_popup().add_item(tr("全部幀…(檔名後面加上編號)"), 1)
	save_png.get_popup().id_pressed.connect(func(id: int) -> void: _ask_save_png(id == 1))
	var keys := ManagerUi.button("⌨ 快捷鍵")
	keys.tooltip_text = tr("快捷鍵一覽。繪圖板的驅動程式可以針對這個程式設定按鍵,對應到這些快捷鍵。")
	keys.pressed.connect(open_shortcut_table)
	var tablet := ManagerUi.button("🖊 繪圖板…")
	tablet.tooltip_text = tr("繪圖板驅動程式(Windows Ink / Wintab)與筆壓設定。")
	tablet.pressed.connect(open_tablet_dialog)
	# 翻轉 / 旋轉選取的內容(沒選取 = 整層;2026-10-24 使用者要求介面上也要有按鈕,原本只有快捷鍵)
	var transforms: Array[Control] = []
	for spec: Array in [["↔", "水平翻轉選取的內容(Shift+H);沒選取就翻整層", "flip_h"], ["↕", "垂直翻轉選取的內容(Shift+V);沒選取就翻整層", "flip_v"],
			["↻", "選取的內容順時針轉 90 度(Shift+R);沒選取就轉整層", "rotate_cw"], ["↺", "選取的內容逆時針轉 90 度(Shift+T);沒選取就轉整層", "rotate_ccw"]]:
		var button := ManagerUi.button(spec[0])
		button.tooltip_text = tr(spec[1])
		var kind: String = spec[2]
		button.pressed.connect(func() -> void: transform_selection(kind))
		transforms.append(button)
	for control: Control in [_apply_button, _undo_button, _redo_button, VSeparator.new(), previous, _page_label, next, copy_page, blank_page, _onion_check, _grid_check, _reference_check,
			_checker_button, VSeparator.new(), zoom_out, _zoom_label, zoom_in, fit, VSeparator.new()] + transforms + [VSeparator.new(), paste_external, save_png, keys, tablet]:
		bar.add_child(control)
	return bar


func _build_left() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 210.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	scroll.add_child(left)
	left.add_child(ManagerUi.heading("工具"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for spec: Array in TOOLS:
		var button := PaintToolButton.new()
		button.text = "%s %s" % [spec[1], tr(spec[2])]
		button.tooltip_text = tr(spec[3])
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.button_group = _tool_group
		button.bindable = bool(spec[4])
		var tool_name: String = spec[0]
		button.pressed.connect(func() -> void: _select_tool(tool_name))
		button.right_clicked.connect(func() -> void: toggle_right_binding(tool_name))
		grid.add_child(button)
		_tool_buttons[tool_name] = button
	left.add_child(grid)
	# 工具設定分組,只顯示左鍵或右鍵現在用得到的那幾組(見 _refresh_option_groups,2026-10-23 使用者要求)
	var brush_group := _option_group(left, "brush", "畫筆")
	_brush_size = _size_spin("brush_size")
	brush_group.add_child(ManagerUi.labeled("尺寸", _brush_size))
	_brush_type = _type_option("brush_smooth")
	brush_group.add_child(ManagerUi.labeled("筆刷", _brush_type))
	_size_pressure = _pressure_check("size_pressure", "筆壓影響粗細", "用繪圖筆時,壓得越輕筆越細(滑鼠不受影響)。")
	brush_group.add_child(_size_pressure)
	_opacity_pressure = _pressure_check("opacity_pressure", "筆壓影響不透明度", "用繪圖筆時,壓得越輕顏色越淡(滑鼠不受影響)。")
	brush_group.add_child(_opacity_pressure)
	_brush_stabilizer = _stabilizer_spin("brush_stabilizer")
	brush_group.add_child(ManagerUi.labeled("防手震", _brush_stabilizer))
	var eraser_group := _option_group(left, "eraser", "橡皮擦")
	_eraser_size = _size_spin("eraser_size")
	eraser_group.add_child(ManagerUi.labeled("尺寸", _eraser_size))
	_eraser_type = _type_option("eraser_smooth")
	eraser_group.add_child(ManagerUi.labeled("筆刷", _eraser_type))
	_eraser_size_pressure = _pressure_check("eraser_size_pressure", "筆壓影響粗細", "用繪圖筆時,壓得越輕擦的範圍越小(滑鼠不受影響)。")
	eraser_group.add_child(_eraser_size_pressure)
	_eraser_opacity_pressure = _pressure_check("eraser_opacity_pressure", "筆壓影響不透明度", "用繪圖筆時,壓得越輕擦得越淡(滑鼠不受影響)。")
	eraser_group.add_child(_eraser_opacity_pressure)
	_eraser_stabilizer = _stabilizer_spin("eraser_stabilizer")
	eraser_group.add_child(ManagerUi.labeled("防手震", _eraser_stabilizer))
	var blend_group := _option_group(left, "blend", "")
	_blend_option = OptionButton.new()
	_blend_option.add_item(tr("覆蓋"))
	_blend_option.add_item(tr("疊色"))
	_blend_option.tooltip_text = tr("覆蓋:顏色連透明度直接寫進去(用 alpha 0 的顏色畫 = 擦掉)。\n疊色:照一般繪圖軟體把半透明的顏色疊在原本的顏色上。\n快捷鍵 Q 切換。")
	_blend_option.item_selected.connect(func(index: int) -> void: _set_setting("blend", index == 1))
	blend_group.add_child(ManagerUi.labeled("上色方式", _blend_option))
	var shape_group := _option_group(left, "shape", "形狀")
	_shape_filled = CheckBox.new()
	_shape_filled.text = tr("形狀填滿")
	_shape_filled.tooltip_text = tr("矩形、橢圓畫成填滿的(用主色);不勾 = 只畫外框,用畫筆的尺寸與筆刷類型(Shift+F)。")
	_shape_filled.toggled.connect(func(on: bool) -> void: _set_setting("shape_filled", on))
	shape_group.add_child(_shape_filled)
	var gradient_group := _option_group(left, "gradient", "漸層")
	_gradient_kind = OptionButton.new()
	_gradient_kind.add_item(tr("直線"))
	_gradient_kind.add_item(tr("放射"))
	_gradient_kind.tooltip_text = tr("直線:沿著拖曳的方向漸變。放射:從起點往外一圈一圈漸變。")
	_gradient_kind.item_selected.connect(func(index: int) -> void: _set_setting("gradient_kind", PaintSettings.GRADIENT_KINDS[index]))
	gradient_group.add_child(ManagerUi.labeled("漸層", _gradient_kind))
	_gradient_steps = SpinBox.new()
	_gradient_steps.min_value = 0
	_gradient_steps.max_value = 32
	_gradient_steps.tooltip_text = tr("0 = 平滑漸變;2 以上 = 分成幾個色階(像素風常用)。")
	_gradient_steps.value_changed.connect(func(value: float) -> void: _set_setting("gradient_steps", int(value)))
	gradient_group.add_child(ManagerUi.labeled("色階", _gradient_steps))
	_gradient_dither = CheckBox.new()
	_gradient_dither.text = tr("點陣混色")
	_gradient_dither.tooltip_text = tr("分色階時,色階交界用棋盤狀的點陣混在一起(像素風的漸層畫法)。")
	_gradient_dither.toggled.connect(func(on: bool) -> void: _set_setting("gradient_dither", on))
	gradient_group.add_child(_gradient_dither)
	var wand_group := _option_group(left, "wand", "魔術棒")
	_wand_tolerance = SpinBox.new()
	_wand_tolerance.min_value = 0
	_wand_tolerance.max_value = 255
	_wand_tolerance.tooltip_text = tr("魔術棒:顏色(含透明度)每個通道差多少以內算相近。0 = 完全一樣才選。")
	_wand_tolerance.value_changed.connect(func(value: float) -> void: _set_setting("wand_tolerance", int(value)))
	wand_group.add_child(ManagerUi.labeled("容許差", _wand_tolerance))
	_wand_contiguous = CheckBox.new()
	_wand_contiguous.text = tr("只選相連的")
	_wand_contiguous.tooltip_text = tr("勾:只選跟點到的那一格相連的範圍。不勾:整張圖顏色相近的都選。")
	_wand_contiguous.toggled.connect(func(on: bool) -> void: _set_setting("wand_contiguous", on))
	wand_group.add_child(_wand_contiguous)
	# 2026-10-24 使用者要求:吸色要不要連透明度一起吸
	var picker_group := _option_group(left, "picker", "吸色")
	_pick_alpha = CheckBox.new()
	_pick_alpha.text = tr("連透明度一起吸")
	_pick_alpha.tooltip_text = tr("勾:吸到的顏色連透明度一起變成主色。不勾:只吸顏色,主色的透明度不變(吸到全透明的格子就不吸)。")
	_pick_alpha.toggled.connect(func(on: bool) -> void: _set_setting("pick_alpha", on))
	picker_group.add_child(_pick_alpha)
	_build_canvas_group(_option_group(left, "canvas", "畫布尺寸"))
	# 貼上外部圖片隨時都能用(Ctrl+Shift+V),這組一直顯示
	left.add_child(ManagerUi.heading("貼上外部圖片"))
	_key_check = CheckBox.new()
	_key_check.text = tr("貼上外部圖片時把這個顏色變透明")
	_key_check.tooltip_text = tr("從不支援透明的軟體複製的圖,背景會是實色:勾這個並指定背景色,貼上時那個顏色就變透明。")
	_key_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_check.toggled.connect(func(on: bool) -> void: _set_setting("key_enabled", on))
	left.add_child(_key_check)
	_key_color = ColorPickerButton.new()
	_key_color.edit_alpha = false
	_key_color.custom_minimum_size = Vector2(0, 28)
	_key_color.color_changed.connect(func(color: Color) -> void: _set_setting("key_color", color))
	left.add_child(_key_color)
	left.add_child(ManagerUi.heading_with_info("繪圖圖層", tr("每一幀都有同樣的這幾層,畫的是選中的那一層;最上面的蓋在最前面。\n套用時合併成一張圖交回精靈圖編輯器,各層另外存起來,下次開繪圖還在(在別的地方改過那張圖就只剩合併後的一層)。")))
	_layer_list = VBoxContainer.new()
	_layer_list.add_theme_constant_override("separation", 2)
	left.add_child(_layer_list)
	# GridContainer 而不是 HFlowContainer:HFlowContainer 放在捲動區裡會少算一排高度,下面的內容捲不到(同色票)
	var layer_row := GridContainer.new()
	layer_row.columns = 4
	for spec: Array in [["＋", "新增繪圖圖層(Shift+N)", func() -> void: _layer_action(_doc.add_layer, tr("最多 %d 層") % PaintDocument.MAX_LAYERS)],
			["📑", "複製這一層", func() -> void: _layer_action(_doc.duplicate_layer, tr("最多 %d 層") % PaintDocument.MAX_LAYERS)],
			["🗑", "刪除這一層", func() -> void: _layer_action(_doc.delete_layer, tr("至少要留一層"))],
			["▲", "往上移(蓋在更前面)", func() -> void: _layer_action(func() -> bool: return _doc.move_layer(1), "")],
			["▼", "往下移", func() -> void: _layer_action(func() -> bool: return _doc.move_layer(-1), "")],
			["⤓", "向下合併(Shift+M)", func() -> void: _layer_action(_doc.merge_down, tr("最下面那一層不能再往下合併"))],
			["✎", "重新命名", _ask_rename_layer]]:
		var button := ManagerUi.button(spec[0])
		button.tooltip_text = tr(spec[1])
		button.pressed.connect(spec[2])
		layer_row.add_child(button)
	left.add_child(layer_row)
	_layer_opacity = SpinBox.new()
	_layer_opacity.min_value = 0
	_layer_opacity.max_value = 100
	_layer_opacity.suffix = "%"
	_layer_opacity.tooltip_text = tr("這一層的不透明度(套用時照這個合併)。")
	_layer_opacity.value_changed.connect(func(value: float) -> void:
		if not _updating:
			_doc.set_layer_opacity(_doc.layer, value / 100.0))
	left.add_child(ManagerUi.labeled("不透明度", _layer_opacity))
	_layer_alpha_lock = CheckBox.new()
	_layer_alpha_lock.text = tr("🔒 鎖定透明度(/)")
	_layer_alpha_lock.tooltip_text = tr("畫筆、形狀、漸層、油漆桶只改顏色、不改透明度:沒內容的地方畫不上去,已經畫好的形狀範圍不會變(適合上陰影、換色)。橡皮擦在這一層沒有作用。")
	_layer_alpha_lock.toggled.connect(func(on: bool) -> void:
		if not _updating:
			_doc.set_layer_alpha_lock(_doc.layer, on))
	left.add_child(_layer_alpha_lock)
	_layer_clip = CheckBox.new()
	_layer_clip.text = tr("↳ 向下剪裁(Shift+C)")
	_layer_clip.tooltip_text = tr("這一層只顯示在下面那一層有內容的地方(剪裁遮罩);下面連續好幾層都剪裁的話,一起剪在最下面那個不剪裁的層上。\n可以隨時關掉,原本畫的內容都還在;套用時照剪裁後的樣子合併。")
	_layer_clip.toggled.connect(func(on: bool) -> void:
		if not _updating:
			_doc.set_layer_clip(_doc.layer, on))
	left.add_child(_layer_clip)
	# 最底下墊一段透明空白,最後一項才捲得到、不會貼在視窗邊上(2026-10-24 使用者回報重新命名以下捲不到)
	var tail := Control.new()
	tail.custom_minimum_size.y = 48.0
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tail)
	return scroll


## 一組工具設定(標題 + 內容),收在 _option_groups[key];heading 空字串 = 不加標題。
func _option_group(parent: Control, key: String, heading: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	if heading != "":
		group.add_child(ManagerUi.heading(heading))
	parent.add_child(group)
	_option_groups[key] = group
	return group


## 每組工具設定要不要顯示:左鍵的工具或右鍵綁的工具用得到才顯示(右鍵沒綁 = 畫筆畫副色,所以畫筆那組通常都在)。
## 右鍵綁橡皮擦用的是畫筆的設定,所以只顯示畫筆那組、不顯示橡皮擦那組(2026-10-23 使用者確認)。
## 繪圖筆的筆尾雖然也用橡皮擦的設定,但看不出來使用者有沒有在用,所以只看左右鍵。
static func option_groups_for(tool_name: String, right_tool: String) -> Array[String]:
	if tool_name == "canvas":
		return ["canvas"]   # 畫布尺寸工具的右鍵不畫圖
	var right_paints := right_tool == "" or right_tool == "brush"
	var groups: Array[String] = []
	if tool_name in ["brush", "line", "rect", "ellipse"] or right_paints or right_tool == "eraser":
		groups.append("brush")
	if tool_name == "eraser":
		groups.append("eraser")
	if tool_name in ["brush", "fill", "line", "rect", "ellipse", "gradient"] or right_paints:
		groups.append("blend")
	if tool_name in ["rect", "ellipse"]:
		groups.append("shape")
	if tool_name == "gradient":
		groups.append("gradient")
	if tool_name == "wand":
		groups.append("wand")
	if tool_name == "picker" or right_tool == "picker":
		groups.append("picker")
	if tool_name == "canvas":
		groups.append("canvas")
	return groups


func _refresh_option_groups() -> void:
	if _canvas == null:
		return
	var shown := option_groups_for(_canvas.tool, _canvas.right_tool)
	for key: String in _option_groups:
		(_option_groups[key] as Control).visible = shown.has(key)


func _stabilizer_spin(key: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 10
	spin.tooltip_text = tr("0 = 關。數字越大,畫的位置越慢追上游標、線條越穩越圓滑(收筆時會補到游標的位置)。")
	spin.value_changed.connect(func(value: float) -> void: _set_setting(key, int(value)))
	return spin


## 「畫布尺寸」工具的設定:寬高(即時顯示 px)、輸入寬高時內容靠哪裡(九宮格)、改這一幀或全部幀、套用 / 還原。
## 在畫布上拖曳四邊或四角也會即時更新這裡的數字。
func _build_canvas_group(group: VBoxContainer) -> void:
	_canvas_width = _canvas_spin()
	group.add_child(ManagerUi.labeled("寬", _canvas_width))
	_canvas_height = _canvas_spin()
	group.add_child(ManagerUi.labeled("高", _canvas_height))
	var anchor_grid := GridContainer.new()
	anchor_grid.columns = 3
	anchor_grid.add_theme_constant_override("h_separation", 2)
	anchor_grid.add_theme_constant_override("v_separation", 2)
	var anchor_group := ButtonGroup.new()
	for row in 3:
		for column in 3:
			var button := Button.new()
			button.toggle_mode = true
			button.button_group = anchor_group
			button.custom_minimum_size = Vector2(26, 22)
			button.focus_mode = Control.FOCUS_NONE
			button.tooltip_text = tr("輸入寬高時,原本的內容靠這個位置(其他邊加寬或裁掉)")
			var anchor := Vector2(column * 0.5, row * 0.5)
			button.pressed.connect(func() -> void:
				_canvas_anchor = anchor
				_refresh_anchor_buttons()
				_on_canvas_size_typed(0.0))
			anchor_grid.add_child(button)
			_anchor_buttons.append(button)
	group.add_child(ManagerUi.labeled("內容靠", anchor_grid))
	_canvas_scope = OptionButton.new()
	_canvas_scope.add_item(tr("只改這一幀"))
	_canvas_scope.add_item(tr("全部幀一起改"))
	_canvas_scope.tooltip_text = tr("全部幀一起改:每一幀照自己原本的大小,四邊加減一樣多的格數。")
	_canvas_scope.item_selected.connect(func(index: int) -> void: _set_setting("canvas_all_pages", index == 1))
	group.add_child(ManagerUi.labeled("範圍", _canvas_scope))
	_canvas_info = Label.new()
	_canvas_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_canvas_info.theme_type_variation = AppSettings.MUTED_LABEL
	group.add_child(_canvas_info)
	var row_box := HBoxContainer.new()
	var apply := ManagerUi.button("套用尺寸")
	apply.tooltip_text = tr("照上面的尺寸改畫布(Enter)。可以撤回;軸心會跟著內容移,角色在畫面上的位置不變。")
	apply.pressed.connect(apply_canvas_size)
	row_box.add_child(apply)
	var reset := ManagerUi.button("還原")
	reset.tooltip_text = tr("放棄還沒套用的尺寸(Esc)")
	reset.pressed.connect(func() -> void: _canvas.reset_canvas_margins())
	row_box.add_child(reset)
	group.add_child(row_box)
	_refresh_anchor_buttons()


func _canvas_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = PaintDocument.MAX_CANVAS
	spin.suffix = "px"
	spin.value_changed.connect(_on_canvas_size_typed)
	return spin


func _refresh_anchor_buttons() -> void:
	for k in _anchor_buttons.size():
		var anchor := Vector2((k % 3) * 0.5, (k / 3) * 0.5)
		_anchor_buttons[k].set_pressed_no_signal(anchor == _canvas_anchor)
		_anchor_buttons[k].text = "●" if anchor == _canvas_anchor else ""


## 打了寬高:照「內容靠」的位置分配到四邊。
func _on_canvas_size_typed(_value: float) -> void:
	if _updating or _canvas == null:
		return
	_canvas.set_canvas_margins(margins_for_size(_doc.page_size(), Vector2i(int(_canvas_width.value), int(_canvas_height.value)), _canvas_anchor))
	_refresh_canvas_info()


## 新尺寸照 anchor(0 / 0.5 / 1)分給四邊:[左, 上, 右, 下]。
static func margins_for_size(old_size: Vector2i, new_size: Vector2i, anchor: Vector2) -> Array[int]:
	var grow := new_size - old_size
	var left := floori(grow.x * anchor.x)
	var top := floori(grow.y * anchor.y)
	return [left, top, grow.x - left, grow.y - top]


## 畫布上拖了四邊,或換頁、改完尺寸:左邊的數字跟著更新。
func _refresh_canvas_info() -> void:
	if _canvas_info == null or _doc.page() == null:
		return
	var pending := _canvas.pending_canvas_rect()
	_updating = true
	_canvas_width.value = pending.size.x
	_canvas_height.value = pending.size.y
	_updating = false
	_canvas_info.text = tr("目前 %d × %d px → %s") % [_doc.page_size().x, _doc.page_size().y, PaintCanvas.margins_text(pending.size, _canvas.canvas_margins)]


## 套用「畫布尺寸」:這一幀或全部幀(看設定),一步撤回。畫面跟著內容移,看起來不會跳。
func apply_canvas_size() -> int:
	var margins := _canvas.canvas_margins.duplicate()
	if margins.all(func(m: int) -> bool: return m == 0):
		_status.text = tr("畫布尺寸沒有變")
		return 0
	var pages: Array = range(_doc.page_count()) if bool(_settings["canvas_all_pages"]) else [_doc.index]
	var count := _doc.resize_canvas(pages, margins)
	_canvas.pan -= Vector2(margins[0], margins[1]) * _canvas.zoom
	_canvas.reset_canvas_margins()
	_status.text = tr("畫布改成 %d × %d px(%d 張;可以撤回)") % [_doc.page_size().x, _doc.page_size().y, count] if count > 0 else tr("尺寸超出範圍(每邊 1~%d px),沒有改") % PaintDocument.MAX_CANVAS
	return count


func _pressure_check(key: String, text: String, tooltip: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = tr(text)
	check.tooltip_text = tr(tooltip)
	check.toggled.connect(func(on: bool) -> void: _set_setting(key, on))
	return check


func _size_spin(key: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = PaintSettings.MAX_SIZE
	spin.step = 1
	spin.tooltip_text = tr("筆刷直徑(像素)。快捷鍵 [ / ] 調整目前工具的尺寸。")
	spin.value_changed.connect(func(value: float) -> void: _set_setting(key, int(value)))
	return spin


func _type_option(key: String) -> OptionButton:
	var option := OptionButton.new()
	option.add_item(tr("像素(硬邊)"))
	option.add_item(tr("平滑邊緣"))
	option.tooltip_text = tr("像素:每一格不是全畫就是不畫,適合像素風。平滑邊緣:圓的邊緣半透明,線條比較圓滑。")
	option.item_selected.connect(func(index: int) -> void: _set_setting(key, index == 1))
	return option


func _build_right() -> Control:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300.0
	right.add_theme_constant_override("separation", 6)
	var slots := HBoxContainer.new()
	for slot in 2:
		var button := Button.new()
		button.custom_minimum_size = Vector2(48, 36)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = tr("主色(左鍵畫):點這裡用下面的選色器改主色") if slot == 0 else tr("副色(右鍵畫):點這裡用下面的選色器改副色")
		var at := slot
		button.pressed.connect(func() -> void: _set_active_slot(at))
		button.draw.connect(func() -> void: _draw_slot(button, at))
		slots.add_child(button)
		_slot_buttons.append(button)
		var label := Label.new()
		label.text = tr("主色") if slot == 0 else tr("副色")
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slots.add_child(label)
	var swap := ManagerUi.button("⇄")
	swap.tooltip_text = tr("交換主色與副色(X)")
	swap.pressed.connect(swap_colors)
	slots.add_child(swap)
	right.add_child(slots)
	_picker = ColorPicker.new()
	_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL   # 方塊外面一圈色環(2026-10-23 使用者要求)
	_picker.edit_alpha = true
	_picker.presets_visible = false
	_picker.can_add_swatches = false
	_picker.color_changed.connect(_on_picker_changed)
	right.add_child(_picker)
	right.add_child(HSeparator.new())
	right.add_child(ManagerUi.heading_with_info("色票", tr("左鍵點色塊 = 設成主色,右鍵 = 設成副色,雙擊 = 編輯這個色塊(名字、顏色、刪除),Ctrl + 右鍵 = 直接刪掉這個色塊。\n「＋」把目前的主色加進色票;「💾」用一個名字存起來(存在這台電腦,下拉選單切換);也能匯入 / 匯出 GIMP 色票檔(.gpl),半透明的顏色照 Aseprite 的格式寫。")))
	var palette_row := HBoxContainer.new()
	_palette_option = OptionButton.new()
	_palette_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_option.clip_text = true
	_palette_option.item_selected.connect(_on_palette_selected)
	palette_row.add_child(_palette_option)
	for spec: Array in [["＋", "把目前的主色加進色票", add_primary_swatch], ["💾", "儲存色票(取名字)", _ask_save_palette],
			["📥", "匯入色票檔(.gpl)", _import_palette], ["📤", "匯出色票檔(.gpl)", _export_palette], ["🗑", "刪除這組色票", _ask_delete_palette]]:
		var button := ManagerUi.button(spec[0])
		button.tooltip_text = tr(spec[1])
		button.pressed.connect(spec[2])
		palette_row.add_child(button)
	right.add_child(palette_row)
	_palette_state = Label.new()
	_palette_state.theme_type_variation = AppSettings.MUTED_LABEL
	right.add_child(_palette_state)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 80.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 用固定欄數的格子而不是自動換行的 HFlowContainer:後者放在捲動區裡算出來的高度會少一排,最後一排永遠捲不到
	# (2026-10-23 使用者回報)。欄數跟著捲動區的寬度變。
	_swatch_box = GridContainer.new()
	_swatch_box.add_theme_constant_override("h_separation", SWATCH_GAP)
	_swatch_box.add_theme_constant_override("v_separation", SWATCH_GAP)
	_swatch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var swatch_column := VBoxContainer.new()
	swatch_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swatch_column.add_theme_constant_override("separation", 0)
	swatch_column.add_child(_swatch_box)
	# 底下墊一排看不見的空白,最後一排一定捲得到、不會貼在邊上被切掉(2026-10-23 使用者第二次回報)
	var swatch_tail := Control.new()
	swatch_tail.custom_minimum_size.y = SWATCH_SIZE.y + SWATCH_GAP * 4
	swatch_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch_column.add_child(swatch_tail)
	scroll.add_child(swatch_column)
	scroll.resized.connect(func() -> void:
		var room := scroll.size.x - float(AppSettings.SCROLLBAR_WIDTH)
		_swatch_box.columns = maxi(1, int((room + SWATCH_GAP) / (SWATCH_SIZE.x + SWATCH_GAP))))
	right.add_child(scroll)
	return right


static func _draw_checker_color(item: CanvasItem, rect: Rect2, color: Color) -> void:
	var cell := 6.0
	var y := rect.position.y
	var row := 0
	while y < rect.end.y:
		var x := rect.position.x
		var column := row % 2
		while x < rect.end.x:
			var piece := Rect2(x, y, minf(cell, rect.end.x - x), minf(cell, rect.end.y - y))
			item.draw_rect(piece, Color(0.8, 0.8, 0.82) if column % 2 == 0 else Color(0.62, 0.62, 0.66))
			x += cell
			column += 1
		y += cell
		row += 1
	item.draw_rect(rect, color)


func _draw_slot(button: Button, slot: int) -> void:
	var rect := Rect2(Vector2(5, 5), button.size - Vector2(10, 10))
	_draw_checker_color(button, rect, _canvas.primary if slot == 0 else _canvas.secondary)
	button.draw_rect(rect, Color(0, 0, 0, 0.6), false, 1.0)


# --- 設定 ---

func _apply_settings_to_canvas() -> void:
	_updating = true
	_brush_size.value = int(_settings["brush_size"])
	_brush_type.select(1 if bool(_settings["brush_smooth"]) else 0)
	_eraser_size.value = int(_settings["eraser_size"])
	_eraser_type.select(1 if bool(_settings["eraser_smooth"]) else 0)
	_blend_option.select(1 if bool(_settings["blend"]) else 0)
	_size_pressure.button_pressed = bool(_settings["size_pressure"])
	_opacity_pressure.button_pressed = bool(_settings["opacity_pressure"])
	_eraser_size_pressure.button_pressed = bool(_settings["eraser_size_pressure"])
	_eraser_opacity_pressure.button_pressed = bool(_settings["eraser_opacity_pressure"])
	_brush_stabilizer.value = int(_settings["brush_stabilizer"])
	_eraser_stabilizer.value = int(_settings["eraser_stabilizer"])
	_canvas_scope.select(1 if bool(_settings["canvas_all_pages"]) else 0)
	_onion_check.button_pressed = bool(_settings["onion"])
	_grid_check.button_pressed = bool(_settings["grid"])
	_reference_check.button_pressed = bool(_settings["reference"])
	_key_check.button_pressed = bool(_settings["key_enabled"])
	_key_color.color = _settings["key_color"]
	_shape_filled.button_pressed = bool(_settings["shape_filled"])
	_gradient_kind.select(PaintSettings.GRADIENT_KINDS.find(str(_settings["gradient_kind"])))
	_gradient_steps.value = int(_settings["gradient_steps"])
	_gradient_dither.button_pressed = bool(_settings["gradient_dither"])
	_wand_tolerance.value = int(_settings["wand_tolerance"])
	_wand_contiguous.button_pressed = bool(_settings["wand_contiguous"])
	_pick_alpha.button_pressed = bool(_settings["pick_alpha"])
	_updating = false
	_canvas.brush = {"size": int(_settings["brush_size"]), "smooth": bool(_settings["brush_smooth"]),
			"size_pressure": bool(_settings["size_pressure"]), "opacity_pressure": bool(_settings["opacity_pressure"]), "stabilizer": int(_settings["brush_stabilizer"])}
	_canvas.eraser = {"size": int(_settings["eraser_size"]), "smooth": bool(_settings["eraser_smooth"]),
			"size_pressure": bool(_settings["eraser_size_pressure"]), "opacity_pressure": bool(_settings["eraser_opacity_pressure"]), "stabilizer": int(_settings["eraser_stabilizer"])}
	_canvas.blend = bool(_settings["blend"])
	if _canvas.checker_dark != bool(_settings["checker_dark"]):
		_canvas.set_checker_dark(bool(_settings["checker_dark"]))
	_refresh_checker_button()
	_canvas.show_onion = bool(_settings["onion"])
	_canvas.show_grid = bool(_settings["grid"])
	_canvas.show_reference = bool(_settings["reference"])
	_canvas.primary = _settings["primary"]
	_canvas.secondary = _settings["secondary"]
	_canvas.right_tool = str(_settings["right_tool"])
	_canvas.shape_filled = bool(_settings["shape_filled"])
	_canvas.gradient = {"kind": str(_settings["gradient_kind"]), "steps": int(_settings["gradient_steps"]), "dither": bool(_settings["gradient_dither"])}
	_canvas.wand = {"tolerance": int(_settings["wand_tolerance"]), "contiguous": bool(_settings["wand_contiguous"])}
	for tool_name: String in _tool_buttons:
		(_tool_buttons[tool_name] as PaintToolButton).bound = tool_name == _canvas.right_tool
	_refresh_option_groups()
	_canvas.queue_redraw()


## 透明格子亮 / 暗切換鈕:圖示是現在的樣子(☀ 亮、🌙 暗)。
func _refresh_checker_button() -> void:
	if _checker_button == null:
		return
	var dark := bool(_settings["checker_dark"])
	_checker_button.text = "🌙" if dark else "☀"
	_checker_button.tooltip_text = tr("透明的格子底色:現在是暗的,點一下換成亮的。") if dark else tr("透明的格子底色:現在是亮的,點一下換成暗的。")


func _set_setting(key: String, value: Variant) -> void:
	if _updating:
		return
	_settings[key] = value
	PaintSettings.save_value(key, value)
	_apply_settings_to_canvas()


func settings() -> Dictionary:
	return _settings.duplicate()


# --- 工具 / 顏色 ---

func _select_tool(tool_name: String) -> void:
	if not _tool_buttons.has(tool_name):
		return
	if tool_name != "select":
		_doc.commit_floating()
	_canvas.cancel_drag()
	if tool_name != _canvas.tool:
		_canvas.reset_canvas_margins()
	_canvas.tool = tool_name
	(_tool_buttons[tool_name] as Button).set_pressed_no_signal(true)
	_refresh_option_groups()
	_canvas.queue_redraw()


func current_tool() -> String:
	return _canvas.tool


## 右鍵綁定:同一個再按一次 = 取消(右鍵回到畫筆畫副色)。
func toggle_right_binding(tool_name: String) -> void:
	_set_setting("right_tool", "" if str(_settings["right_tool"]) == tool_name else tool_name)
	var bound := str(_settings["right_tool"])
	_status.text = tr("畫布的右鍵現在是:%s") % (tr("畫筆(畫副色)") if bound == "" or bound == "brush" else (tr("橡皮擦(用畫筆的尺寸與筆刷類型)") if bound == "eraser" else tr("吸色(吸到主色)")))


func set_color(slot: int, color: Color) -> void:
	if slot == 0:
		_canvas.primary = color
		_settings["primary"] = color
		PaintSettings.save_value("primary", color)
	else:
		_canvas.secondary = color
		_settings["secondary"] = color
		PaintSettings.save_value("secondary", color)
	_refresh_slots()


func colors() -> Array[Color]:
	return [_canvas.primary, _canvas.secondary]


func swap_colors() -> void:
	var primary := _canvas.primary
	set_color(0, _canvas.secondary)
	set_color(1, primary)


func _set_active_slot(slot: int) -> void:
	_active_slot = slot
	_refresh_slots()


func _refresh_slots() -> void:
	for slot in _slot_buttons.size():
		_slot_buttons[slot].set_pressed_no_signal(slot == _active_slot)
		_slot_buttons[slot].queue_redraw()
	_updating = true
	_picker.color = _canvas.primary if _active_slot == 0 else _canvas.secondary
	_updating = false


func _on_picker_changed(color: Color) -> void:
	if _updating:
		return
	set_color(_active_slot, color)


func _on_color_picked(color: Color) -> void:
	if not bool(_settings["pick_alpha"]):
		if color.a <= 0.0:
			_status.text = tr("這一格是全透明的,沒有顏色可以吸(吸色設定成不吸透明度)")
			return
		color.a = _canvas.primary.a
	set_color(0, color)
	_status.text = tr("吸到主色:#%s") % color.to_html(true).to_upper()


func _on_hover_changed(pixel: Variant) -> void:
	if pixel is Vector2i:
		var color: Variant = _doc.pick(pixel)
		_hover_label.text = "%d, %d  ·  #%s" % [pixel.x, pixel.y, (color as Color).to_html(true).to_upper() if color is Color else ""]
	else:
		_hover_label.text = ""


func _refresh_zoom_label() -> void:
	_zoom_label.text = "%d%%" % roundi(_canvas.zoom * 100.0)


# --- 頁 / 撤回 / 套用 ---

func go_page(delta: int) -> void:
	if _doc.page_count() <= 1:
		return
	_canvas.cancel_drag()
	_canvas.reset_canvas_margins()   # 每一幀大小可能不同,待套用的尺寸從這一幀重新算
	_doc.set_page((_doc.index + delta + _doc.page_count()) % _doc.page_count())


func _on_doc_changed() -> void:
	var count := _doc.page_count()
	var label := page_label(_doc.index)
	_sync_markers()
	for button in _add_page_buttons:
		button.visible = can_add_pages
		button.disabled = count >= PaintDocument.MAX_PAGES
	_page_label.text = tr("第 %d / %d 張") % [_doc.index + 1, count] + ("  " + label if label != "" else "")
	_undo_button.disabled = not _doc.can_undo()
	_redo_button.disabled = not _doc.can_redo()
	var dirty := has_unapplied_changes()
	_apply_button.disabled = not dirty
	var base_title := title.trim_suffix(" *")
	title = base_title + (" *" if dirty else "")
	_refresh_layers()
	_refresh_canvas_info()


# --- 繪圖圖層 ---

## 圖層清單(最上面的圖層排在最上面)。只有圖層的名字、顯示、不透明度或選中的那層變了才重做。
func _refresh_layers() -> void:
	var key := [_doc.layers.duplicate(true), _doc.layer]
	if key == _layer_key:
		return
	_layer_key = key
	_layer_buttons.clear()
	for child in _layer_list.get_children():
		_layer_list.remove_child(child)
		child.queue_free()
	for l in range(_doc.layers.size() - 1, -1, -1):
		var meta: Dictionary = _doc.layers[l]
		var row := HBoxContainer.new()
		var eye := ManagerUi.button("👁" if bool(meta["visible"]) else "—")
		eye.tooltip_text = tr("顯示 / 隱藏這一層(隱藏的層套用時不會合併進去)")
		eye.custom_minimum_size.x = 34.0
		var at := l
		eye.pressed.connect(func() -> void: _doc.set_layer_visible(at, not bool(_doc.layers[at]["visible"])))
		row.add_child(eye)
		var pick := Button.new()
		pick.toggle_mode = true
		pick.button_pressed = l == _doc.layer
		pick.text = ("↳ " if bool(meta.get("clip", false)) and l > 0 else "") + str(meta["name"]) + ("" if float(meta["opacity"]) >= 1.0 else "  %d%%" % roundi(float(meta["opacity"]) * 100.0)) \
				+ ("  🔒" if bool(meta.get("alpha_lock", false)) else "")
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.clip_text = true
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.focus_mode = Control.FOCUS_NONE
		pick.tooltip_text = tr("點一下 = 畫這一層,雙擊 = 重新命名")
		pick.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if (event as InputEventMouseButton).double_click:
					select_layer(at)
					_ask_rename_layer()
				else:
					select_layer(at)
				pick.accept_event())
		row.add_child(pick)
		_layer_list.add_child(row)
		_layer_buttons[l] = pick
	_updating = true
	_layer_opacity.value = roundi(float(_doc.layers[_doc.layer]["opacity"]) * 100.0)
	_layer_alpha_lock.button_pressed = bool(_doc.layers[_doc.layer].get("alpha_lock", false))
	_layer_clip.button_pressed = bool(_doc.layers[_doc.layer].get("clip", false))
	_layer_clip.disabled = _doc.layer == 0   # 最下面那一層沒有東西可以剪
	_updating = false


## 目前繪圖圖層的鎖定透明度 / 向下剪裁開關(快捷鍵 / 與 Shift+C)。
func toggle_alpha_lock() -> void:
	var on := not bool(_doc.layers[_doc.layer].get("alpha_lock", false))
	_doc.set_layer_alpha_lock(_doc.layer, on)
	_status.text = tr("鎖定透明度:開") if on else tr("鎖定透明度:關")


func toggle_clip() -> void:
	if _doc.layer == 0:
		_status.text = tr("最下面那一層不能向下剪裁")
		return
	var on := not bool(_doc.layers[_doc.layer].get("clip", false))
	_doc.set_layer_clip(_doc.layer, on)
	_status.text = tr("向下剪裁:開") if on else tr("向下剪裁:關")


func select_layer(at: int) -> void:
	_canvas.cancel_drag()
	_doc.set_layer(at)
	_layer_key = null
	_refresh_layers()


func _layer_action(action: Callable, refused_text: String) -> void:
	_canvas.cancel_drag()
	if not bool(action.call()) and refused_text != "":
		_status.text = refused_text


func _ask_rename_layer() -> void:
	var at := _doc.layer
	ManagerUi.ask_name(self, tr("重新命名繪圖圖層"), tr("繪圖圖層的名字:"), str(_doc.layers[at]["name"]), tr("確定"),
			func(text: String) -> String: return tr("名字不能是空的") if text == "" else "",
			func(chosen: String) -> void: _doc.rename_layer(at, chosen))


## 頁的名字:畫動作的幀時照位置顯示「動作 第 N 幀」,新增、還沒套用的頁加註。
func page_label(page_index: int) -> String:
	if page_index < 0 or page_index >= _doc.page_count():
		return ""
	var text := tr("%s 第 %d 幀") % [frame_label_action, page_index] if frame_label_action != "" else str(_label_of.get(_doc.page_ids[page_index], ""))
	if _doc.is_new_page(page_index):
		text += tr("(新的,套用後加進動作)")
	return text


func _sync_markers() -> void:
	var markers: Array = []
	for id in _doc.page_ids:
		markers.append(_marker_of.get(id))
	_canvas.markers = markers
	_canvas.queue_redraw()


## 在目前這一幀後面新增一幀並切過去(copy = 複製這一幀,否則空白;見 PaintDocument.add_page)。
func add_page(copy: bool) -> bool:
	if not can_add_pages:
		return false
	_canvas.cancel_drag()
	var from_id := _doc.page_ids[_doc.index]
	var size := _doc.page_size()
	if not _doc.add_page(copy):
		_status.text = tr("最多 %d 幀") % PaintDocument.MAX_PAGES
		return false
	var id := _doc.page_ids[_doc.index]
	_marker_of[id] = _marker_of.get(from_id) if copy else Vector2(size.x / 2, size.y)
	_on_doc_changed()
	_status.text = tr("已新增一幀(複製上一幀);按「套用」才會加進動作") if copy else tr("已新增一張空白幀;按「套用」才會加進動作")
	return true


## 翻轉 / 旋轉(選取範圍,沒選取 = 整個繪圖圖層),轉完是浮動的一塊,切到範圍選取方便拖曳。
func transform_selection(kind: String) -> void:
	_canvas.cancel_drag()
	if _doc.transform_selection(kind):
		_select_tool("select")
		_status.text = tr("已翻轉 / 旋轉:可以拖曳調整位置,按 Enter 放下")


func undo() -> void:
	_canvas.cancel_drag()
	if _doc.undo():
		_status.text = tr("已撤回")


func redo() -> void:
	_canvas.cancel_drag()
	if _doc.redo():
		_status.text = tr("已重做")


func has_unapplied_changes() -> bool:
	return _doc.floating != null or not _doc.changed_pages().is_empty()


## 把改過的頁交回精靈圖編輯器。浮動的內容先放下。
func apply_changes() -> void:
	_canvas.cancel_drag()
	_doc.commit_floating()
	var edits: Array = []
	for page_index in _doc.changed_pages():
		edits.append({"page": page_index, "image": _doc.composite(page_index), "layers": _doc.layer_entries(page_index),
				"shift": _doc.page_shifts[page_index], "size_before": _doc.base_sizes[page_index]})
	if edits.is_empty():
		_status.text = tr("沒有要套用的變更")
		return
	apply_requested.emit(edits)


## 換掉每一頁墊在底下的參考圖(精靈圖編輯器換了幀,見 PackEditorWindow._refresh_paint_reference)。
func set_references(references: Array) -> void:
	_canvas.references = references
	_reference_check.visible = references.any(func(r: Variant) -> bool: return r is Dictionary)
	_canvas.queue_redraw()


## 呼叫端處理完套用:message 是結果說明;ok = 有成功寫回(現在的樣子變成新的基準)。
func applied(ok: bool, message: String) -> void:
	if ok:
		# 呼叫端已經照畫布尺寸的位移調好軸心:畫布上的軸心標記、墊的參考圖也記成新的位置
		for p in _doc.page_count():
			var shift := Vector2(_doc.page_shifts[p])
			var id := _doc.page_ids[p]
			if _marker_of.get(id) is Vector2:
				_marker_of[id] = (_marker_of[id] as Vector2) + shift
			if p < _canvas.references.size() and _canvas.references[p] is Dictionary:
				_canvas.references[p]["offset"] = Vector2(_canvas.references[p]["offset"]) + shift
		_doc.mark_applied()
	_status.text = message
	_on_doc_changed()


# --- 剪貼簿 ---

func paste_external_image() -> void:
	if not DisplayServer.clipboard_has_image():
		_status.text = tr("剪貼簿裡沒有圖片(在別的軟體複製圖片後再試一次)")
		return
	var image := DisplayServer.clipboard_get_image()
	if image == null or image.is_empty():
		_status.text = tr("讀不出剪貼簿裡的圖片")
		return
	paste_image_from_outside(image)


## 貼上外部來的圖(給按鈕與測試用):照「把這個顏色變透明」的設定處理後變成浮動的一塊,切到範圍選取工具方便拖曳。
func paste_image_from_outside(image: Image) -> void:
	var key: Variant = _settings["key_color"] if bool(_settings["key_enabled"]) else null
	_canvas.cancel_drag()
	_doc.paste_image(PaintDocument.prepare_external(image, key), Vector2i.ZERO)
	_select_tool("select")
	_status.text = tr("已貼上 %d×%d 的圖:拖曳移動,按 Enter 或點選取範圍外面放下") % [image.get_width(), image.get_height()]


## 「💾 另存圖檔」:選存檔位置。all_pages = 全部幀,檔名 <選的名字>_01.png、_02.png…(位數跟著幀數)。
func _ask_save_png(all_pages: bool) -> void:
	var default_name := export_name.validate_filename()
	if not all_pages and _doc.page_count() > 1:
		default_name += "_%d" % (_doc.index + 1)
	FloatingWindow.native_file_dialog(tr("另存全部幀") if all_pages else tr("另存目前這一幀"), "", DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
			PackedStringArray(["*.png;PNG"]), func(paths: PackedStringArray) -> void:
				var result := save_pngs(paths[0], all_pages)
				_status.text = str(result["error"]) if str(result["error"]) != "" else tr("已另存 %d 張圖:%s") % [result["count"], result["folder"]],
			get_window_id(), default_name + ".png")


## 把目前這一幀(或全部幀)合併後的圖存成 PNG,浮動的內容先放下。回傳 {count, folder, error}(error 空字串 = 成功)。
func save_pngs(path: String, all_pages: bool) -> Dictionary:
	_canvas.cancel_drag()
	_doc.commit_floating()
	if path.get_extension().to_lower() != "png":
		path += ".png"
	var pages: Array[int] = []
	if all_pages:
		pages.assign(range(_doc.page_count()))
	else:
		pages.append(_doc.index)
	var digits := maxi(2, str(_doc.page_count()).length())
	var count := 0
	for page_index in pages:
		var target := path
		if all_pages:
			target = "%s_%s.png" % [path.get_basename(), str(page_index + 1).pad_zeros(digits)]
		var image := _doc.composite(page_index)
		if image == null or image.save_png(target) != OK:
			return {"count": count, "folder": path.get_base_dir(), "error": tr("無法寫入圖片:%s") % target}
		count += 1
	return {"count": count, "folder": path.get_base_dir(), "error": ""}


func paste_internal() -> void:
	_canvas.cancel_drag()
	if _doc.paste_clipboard():
		_select_tool("select")
		_status.text = tr("已貼上:拖曳移動,按 Enter 或點選取範圍外面放下")
	elif DisplayServer.clipboard_has_image():
		paste_external_image()
	else:
		_status.text = tr("剪貼簿是空的")


# --- 色票 ---

func palette() -> PaintPalette:
	return _palette


func _load_palette(palette_name: String) -> void:
	var names := PaintPalette.list_names()
	var wanted := palette_name if names.has(palette_name) else (names[0] if not names.is_empty() else "")
	_palette = PaintPalette.load_named(wanted) if wanted != "" else null
	if _palette == null:
		_palette = PaintPalette.new()
		_palette.name = tr(PaintPalette.DEFAULT_NAME)
	_palette_saved = _palette.duplicate_palette()
	_settings["palette"] = _palette.name
	PaintSettings.save_value("palette", _palette.name)
	_refresh_palette_ui()


func _refresh_palette_ui() -> void:
	_updating = true
	_palette_option.clear()
	var names := PaintPalette.list_names()
	if not names.has(_palette.name):
		names.append(_palette.name)
	for i in names.size():
		_palette_option.add_item(names[i])
		if names[i] == _palette.name:
			_palette_option.select(i)
	_updating = false
	_palette_state.text = tr("(有還沒儲存的變更,按 💾 儲存)") if not _palette.same_as(_palette_saved) else ""
	for child in _swatch_box.get_children():
		child.queue_free()
	for i in _palette.swatches.size():
		_swatch_box.add_child(_make_swatch(i))


func _make_swatch(at: int) -> Control:
	var swatch: Dictionary = _palette.swatches[at]
	var button := Button.new()
	button.custom_minimum_size = SWATCH_SIZE
	button.focus_mode = Control.FOCUS_NONE
	var color: Color = swatch["color"]
	var label := str(swatch["name"])
	button.tooltip_text = ("%s\n" % label if label != "" else "") + "#" + color.to_html(true).to_upper() + "\n" + tr("左鍵 = 主色、右鍵 = 副色、雙擊 = 編輯、Ctrl + 右鍵 = 刪除")
	button.draw.connect(func() -> void:
		_draw_checker_color(button, Rect2(Vector2(2, 2), button.size - Vector2(4, 4)), color))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var mouse := event as InputEventMouseButton
			if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.ctrl_pressed:
				delete_swatch(at)
			elif mouse.button_index == MOUSE_BUTTON_LEFT and mouse.double_click:
				open_swatch_editor(at)
			elif mouse.button_index == MOUSE_BUTTON_LEFT:
				set_color(0, color)
			elif mouse.button_index == MOUSE_BUTTON_RIGHT:
				set_color(1, color)
			button.accept_event())
	return button


func add_primary_swatch() -> void:
	if not _palette.add(_canvas.primary):
		_status.text = tr("色票最多 %d 色") % PaintPalette.MAX_SWATCHES
		return
	_refresh_palette_ui()


## 雙擊色塊:改名字、用完整的選色器改顏色,或刪掉這個色塊。回傳對話框(給測試用)。
func open_swatch_editor(at: int) -> ConfirmationDialog:
	if at < 0 or at >= _palette.swatches.size():
		return null
	var swatch: Dictionary = _palette.swatches[at]
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("編輯色塊")
	dialog.ok_button_text = tr("確定")
	dialog.cancel_button_text = tr("取消")
	dialog.theme = ManagerUi.make_theme()
	var box := VBoxContainer.new()
	var name_edit := ManagerUi.line_edit("色塊名稱(可以不填)")
	name_edit.text = str(swatch["name"])
	box.add_child(ManagerUi.labeled("名稱", name_edit))
	var picker := ColorPicker.new()
	picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	picker.edit_alpha = true
	picker.presets_visible = false
	picker.can_add_swatches = false
	picker.color = swatch["color"]
	box.add_child(picker)
	dialog.add_child(box)
	dialog.add_button(tr("刪除這個色塊"), true, "delete")
	dialog.confirmed.connect(func() -> void:
		edit_swatch(at, picker.color, name_edit.text.strip_edges())
		dialog.queue_free())
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"delete":
			delete_swatch(at)
			dialog.hide()
			dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(360, 600))
	return dialog


func edit_swatch(at: int, color: Color, swatch_name: String) -> void:
	if at < 0 or at >= _palette.swatches.size():
		return
	_palette.swatches[at] = {"color": color, "name": swatch_name}
	_refresh_palette_ui()


func delete_swatch(at: int) -> void:
	if at < 0 or at >= _palette.swatches.size():
		return
	_palette.swatches.remove_at(at)
	_refresh_palette_ui()


func _on_palette_selected(index: int) -> void:
	if _updating:
		return
	var wanted := _palette_option.get_item_text(index)
	if _palette.same_as(_palette_saved):
		_load_palette(wanted)
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("色票有還沒儲存的變更")
	dialog.dialog_text = tr("「%s」改過的地方還沒儲存,切換到「%s」會放棄這些變更。") % [_palette.name, wanted]
	dialog.ok_button_text = tr("放棄變更並切換")
	dialog.cancel_button_text = tr("取消")
	dialog.confirmed.connect(func() -> void:
		_load_palette(wanted)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void:
		_refresh_palette_ui()
		dialog.queue_free())
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(440, 160))


func _ask_save_palette() -> void:
	ManagerUi.ask_name(self, tr("儲存色票"), tr("幫這組色票取個名字(存在這台電腦,之後可以用下拉選單切換):"), _palette.name, tr("儲存"),
			func(text: String) -> String: return tr("名字不能是空的") if text == "" else "",
			func(chosen: String) -> void: save_palette_as(chosen))


## 用這個名字存色票。這個名字已經有色票了(包括存回目前這組自己的名字)就先問「覆蓋」還是「另存成 名稱(1)」。
## 回傳對話框(要問的時候;給測試用),不用問就回 null。
func save_palette_as(palette_name: String) -> ConfirmationDialog:
	var clean := palette_name.strip_edges()
	if clean == "":
		return null
	if PaintPalette.exists(clean):
		var dialog := ConfirmationDialog.new()
		dialog.title = tr("已經有同名的色票")
		dialog.dialog_text = tr("已經有一組叫「%s」的色票了。要覆蓋它,還是另存成「%s」?") % [clean, PaintPalette.unique_name(clean)]
		dialog.ok_button_text = tr("覆蓋")
		dialog.cancel_button_text = tr("取消")
		dialog.add_button(tr("另存成「%s」") % PaintPalette.unique_name(clean), true, "append")
		dialog.confirmed.connect(func() -> void:
			_write_palette(clean)
			dialog.queue_free())
		dialog.custom_action.connect(func(action: StringName) -> void:
			if action == &"append":
				_write_palette(PaintPalette.unique_name(clean))
				dialog.hide()
				dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		if is_inside_tree() and DisplayServer.get_name() != "headless":
			FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(460, 170))
		return dialog
	_write_palette(clean)
	return null


func _write_palette(palette_name: String) -> void:
	_palette.name = palette_name
	var error := _palette.save_to_library()
	if error != "":
		_status.text = tr(error)
		return
	_palette_saved = _palette.duplicate_palette()
	_settings["palette"] = palette_name
	PaintSettings.save_value("palette", palette_name)
	_refresh_palette_ui()
	_status.text = tr("已儲存色票「%s」") % palette_name


func _import_palette() -> void:
	FloatingWindow.native_file_dialog(tr("匯入色票檔"), "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.gpl;GIMP Palette"]),
			func(paths: PackedStringArray) -> void: import_palette_file(paths[0]), get_window_id())


## 匯入 .gpl:變成目前的色票(還沒存進色票庫,按 💾 存;同名的話存的時候會問)。成功回空字串。
func import_palette_file(path: String) -> String:
	var imported := PaintPalette.import_from(path)
	if imported == null:
		_status.text = tr("這不是 GIMP 色票檔(.gpl)")
		return _status.text
	if imported.name.strip_edges() == "":
		imported.name = path.get_file().get_basename()
	_palette = imported
	_palette_saved = PaintPalette.new()
	_palette_saved.name = ""
	_refresh_palette_ui()
	_status.text = tr("已匯入色票「%s」(%d 色),按 💾 存起來") % [imported.name, imported.swatches.size()]
	return ""


func _export_palette() -> void:
	FloatingWindow.native_file_dialog(tr("匯出色票檔"), "", DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(["*.gpl;GIMP Palette"]),
			func(paths: PackedStringArray) -> void:
				var path := paths[0] if paths[0].get_extension().to_lower() == "gpl" else paths[0] + ".gpl"
				var error := _palette.export_to(path)
				_status.text = tr(error) if error != "" else tr("已匯出色票:%s") % path,
			get_window_id(), _palette.name.validate_filename() + ".gpl")


func _ask_delete_palette() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("刪除色票")
	dialog.dialog_text = tr("要刪除色票「%s」嗎?(刪除後不能復原)") % _palette.name
	dialog.ok_button_text = tr("刪除")
	dialog.cancel_button_text = tr("取消")
	dialog.confirmed.connect(func() -> void:
		delete_current_palette()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(420, 150))


func delete_current_palette() -> void:
	PaintPalette.delete_named(_palette.name)
	_load_palette("")


# --- 快捷鍵表 / 繪圖板 ---

func open_shortcut_table() -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = tr("繪圖快捷鍵")
	dialog.ok_button_text = tr("關閉")
	dialog.theme = ManagerUi.make_theme()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 420)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	for pair: Array in SHORTCUTS:
		var key := Label.new()
		key.text = tr(pair[0])
		grid.add_child(key)
		var description := Label.new()
		description.text = tr(pair[1])
		grid.add_child(description)
	scroll.add_child(grid)
	var box := VBoxContainer.new()
	box.add_child(scroll)
	var note := Label.new()
	note.text = tr("繪圖板的驅動程式(例如 Wacom 數位板內容)可以針對這個程式的執行檔,把筆身按鍵或快捷鍵按鈕設定成上面的按鍵。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 460.0
	box.add_child(note)
	dialog.add_child(box)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(500, 540))
	return dialog


func open_tablet_dialog() -> AcceptDialog:
	var dialog := AcceptDialog.new()
	dialog.title = tr("繪圖板")
	dialog.ok_button_text = tr("關閉")
	dialog.theme = ManagerUi.make_theme()
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 440.0
	var option := OptionButton.new()
	var drivers := PaintSettings.tablet_drivers()
	var choices: Array[String] = [""]
	choices.append_array(drivers)
	var saved := str(_settings["tablet_driver"])
	for i in choices.size():
		option.add_item(PaintSettings.tablet_driver_label(choices[i]))
		if choices[i] == saved:
			option.select(i)
	var current := Label.new()
	current.text = tr("目前使用:%s") % PaintSettings.tablet_driver_label(DisplayServer.tablet_get_current_driver())
	option.item_selected.connect(func(index: int) -> void:
		_settings["tablet_driver"] = choices[index]
		var now := PaintSettings.set_tablet_driver(choices[index])
		current.text = tr("目前使用:%s") % PaintSettings.tablet_driver_label(now))
	box.add_child(ManagerUi.labeled("驅動程式", option))
	box.add_child(current)
	var note := Label.new()
	note.text = tr("筆畫不出來、沒有筆壓,或筆壓斷斷續續時,換另一個驅動程式試試(Wacom 通常兩種都支援)。設定會記住,下次開程式也用這個。\n筆壓影響粗細 / 不透明度在左邊畫筆、橡皮擦的設定裡各自切換;筆尾(橡皮擦端)一律當橡皮擦。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 自動換行的 Label 沒有寬度時會被算成一字一行,對話框就被撐成整個螢幕高(2026-10-24 使用者回報):給固定寬度
	note.custom_minimum_size.x = 440.0
	box.add_child(note)
	dialog.add_child(box)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(480, 300))
	return dialog


# --- 鍵盤 ---

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		var typing_space := gui_get_focus_owner() is LineEdit or gui_get_focus_owner() is TextEdit
		if not typing_space:
			_canvas.space_held = event.pressed
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed):
		return
	if handle_key(event as InputEventKey):
		get_viewport().set_input_as_handled()


## 處理一個按鍵(給 _input 與測試用)。回傳有沒有用掉。在文字框裡打字時只有 Ctrl+S 有作用。
func handle_key(event: InputEventKey) -> bool:
	var typing := gui_get_focus_owner() is LineEdit or gui_get_focus_owner() is TextEdit
	if event.ctrl_pressed:
		match event.keycode:
			KEY_S:
				apply_changes()
				return true
		if typing:
			return false
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_A:
				_canvas.cancel_drag()
				_doc.select_all()
			KEY_I:
				_canvas.cancel_drag()
				_doc.invert_selection()
			KEY_D:
				_doc.clear_selection()
			KEY_C:
				if _doc.copy_selection():
					_status.text = tr("已複製(可以換一幀或換動作再貼上)")
			KEY_X:
				_canvas.cancel_drag()
				if _doc.cut_selection():
					_status.text = tr("已剪下")
			KEY_V:
				if event.shift_pressed:
					paste_external_image()
				else:
					paste_internal()
			KEY_0:
				_canvas.fit_view()
			KEY_1:
				_canvas.set_zoom(1.0)
			_:
				return false
		return true
	if typing:
		return false
	if event.alt_pressed:
		if event.keycode == KEY_UP or event.keycode == KEY_DOWN:
			select_layer(clampi(_doc.layer + (1 if event.keycode == KEY_UP else -1), 0, _doc.layers.size() - 1))
			return true
		return false
	if event.shift_pressed:
		match event.keycode:
			KEY_G:
				_grid_check.button_pressed = not _grid_check.button_pressed
				return true
			KEY_H:
				transform_selection("flip_h")
				return true
			KEY_V:
				transform_selection("flip_v")
				return true
			KEY_R:
				transform_selection("rotate_cw")
				return true
			KEY_T:
				transform_selection("rotate_ccw")
				return true
			KEY_N:
				_layer_action(_doc.add_layer, tr("最多 %d 層") % PaintDocument.MAX_LAYERS)
				return true
			KEY_M:
				_layer_action(_doc.merge_down, tr("最下面那一層不能再往下合併"))
				return true
			KEY_C:
				toggle_clip()
				return true
			KEY_D, KEY_B:
				if can_add_pages:
					add_page(event.keycode == KEY_D)
					return true
			KEY_F:
				_shape_filled.button_pressed = not _shape_filled.button_pressed
				return true
	if TOOL_KEYS.has(event.keycode) and not event.shift_pressed:
		_select_tool(TOOL_KEYS[event.keycode])
		return true
	match event.keycode:
		KEY_X:
			swap_colors()
		KEY_Q:
			_blend_option.select(0 if bool(_settings["blend"]) else 1)
			_set_setting("blend", not bool(_settings["blend"]))
			_status.text = tr("上色方式:%s") % (tr("疊色") if bool(_settings["blend"]) else tr("覆蓋"))
		KEY_O:
			_onion_check.button_pressed = not _onion_check.button_pressed
		KEY_SLASH:
			toggle_alpha_lock()
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var spin := _eraser_size if _canvas.tool == "eraser" else _brush_size
			spin.value = clampi(int(spin.value) + (1 if event.keycode == KEY_BRACKETRIGHT else -1), 1, PaintSettings.MAX_SIZE)
		KEY_COMMA, KEY_PAGEUP:
			go_page(-1)
		KEY_PERIOD, KEY_PAGEDOWN:
			go_page(1)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_canvas.step_zoom(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_canvas.step_zoom(-1)
		KEY_ESCAPE:
			if _canvas.tool == "canvas":
				_canvas.reset_canvas_margins()
			else:
				_doc.clear_selection()
		KEY_ENTER, KEY_KP_ENTER:
			if _canvas.tool == "canvas":
				apply_canvas_size()
			else:
				_doc.commit_floating()
		KEY_DELETE, KEY_BACKSPACE:
			_canvas.cancel_drag()
			_doc.delete_selection()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if not _doc.has_selection():
				return false
			var step := 10 if event.shift_pressed else 1
			var delta := {KEY_LEFT: Vector2i(-step, 0), KEY_RIGHT: Vector2i(step, 0), KEY_UP: Vector2i(0, -step), KEY_DOWN: Vector2i(0, step)}[event.keycode] as Vector2i
			_doc.lift_selection()
			_doc.move_floating(delta)
		_:
			return false
	return true


# --- 關閉 ---

## 離開之前(關視窗、精靈圖編輯器要換素材包或關掉):有還沒套用的變更就問「套用後繼續 / 放棄變更 / 取消」。
## 套用要靠呼叫端寫回,所以「套用後繼續」= 發 apply_requested,呼叫端寫回成功(applied(true, …))之後才 proceed。
func guard(proceed: Callable, action_text := "關閉") -> ConfirmationDialog:
	if not has_unapplied_changes():
		proceed.call()
		return null
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("繪圖還沒套用")
	dialog.dialog_text = tr("畫的內容還沒有套用到精靈圖編輯器。\n要先套用再%s、放棄這些變更直接%s,還是取消?") % [tr(action_text), tr(action_text)]
	dialog.ok_button_text = tr("套用後%s") % tr(action_text)
	dialog.cancel_button_text = tr("取消")
	dialog.add_button(tr("放棄變更並%s") % tr(action_text), true, "discard")
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		apply_changes()
		if not has_unapplied_changes():
			proceed.call())
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			dialog.hide()
			dialog.queue_free()
			_doc.cancel_floating()
			_doc.mark_applied()
			proceed.call())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(480, 180))
	return dialog


## 關繪圖視窗一律先確認(2026-10-23 使用者要求,避免畫到一半誤按 ✕);有沒套用的內容走 guard 的「套用 / 放棄 / 取消」。
func _request_close() -> void:
	if has_unapplied_changes():
		guard(queue_free)
	else:
		confirm_close()


func confirm_close() -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("關閉繪圖視窗")
	dialog.dialog_text = tr("確定要關閉繪圖視窗嗎?")
	dialog.ok_button_text = tr("關閉")
	dialog.cancel_button_text = tr("取消")
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(360, 140))
	return dialog
