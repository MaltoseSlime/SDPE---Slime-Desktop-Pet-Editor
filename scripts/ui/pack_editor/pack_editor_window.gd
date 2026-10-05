class_name PackEditorWindow
extends FloatingWindow
## 精靈圖編輯器(Godot 端逐幀精靈編輯器)。視窗一開始是空的,用上方按鈕「從資料夾匯入…」「新建資料夾…」(都放在專案統一的 sprite 資料夾,見 SpriteLibrary)、
## 匯入圖片、匯入精靈圖、換精靈圖、另存為新素材包;左邊選動作(所有系統動作都有一個槽,沒素材的顯示「空」,也能新增自訂動作)與幀(可複選:複製、貼上、複製一份、刪除、前後移動,貼到別的動作也行),
## 中間是畫布,右邊(可捲動)是編輯模式、數值、圖片處理(裁切、翻轉、旋轉)與檢視。
## 編輯模式預設是「移動視角畫面」(左鍵拖曳平移,不會改到資料);可以編輯軸心(腳底線 + 中心點)、圖片偏移、互動判定框、每個動作的播放速度,全都存進素材包的 pack.json。
## 資料層見 PackEditorModel,格式見 docs/素材包格式.md;撤回/重做各 25 步。
## 離開目前的素材包之前(關視窗、從資料夾匯入、新建、之後的模式切換)一律走 guard_unsaved():有未存的變更就跳出「存檔後繼續 / 放棄變更 / 取消」,不是只在底部的狀態列說一聲。
## 道具編輯區(道具管理的「進階貼圖」):open_prop() 之後,編輯的是道具資料夾裡的 sprite/,動作槽固定是 預設 / 被使用 / 拖曳中(不能新增別的),
## 光源、持有錨點這些角色專用的區塊與匯入資料夾、新建、另存新檔都收起來;右邊多一個「道具狀態動畫」區設定被使用與拖曳中的播放次數與循環或觸發。
## 存檔後發 saved(素材包資料夾),DesktopShell 會讓桌面上用這個素材包生成的桌寵即時換上新圖(見 Pet.reload_pack);道具區存檔不發。
## 「匯出獨立圖檔…」把每個動作的每一幀(套用切片、軸心對齊後的畫布大小)存成一張張 PNG(<動作>_<編號>.png),見 PackEditorModel.export_frames。

## 素材包存檔成功(資料夾路徑)。
signal saved(folder: String)
## 正在編輯家具進階貼圖時,使用者按了「開啟家具庫…」(見 _build_furniture_panel)。
signal furniture_settings_requested

const THUMB_SIZE := Vector2i(56, 56)
const DEFAULT_PREVIEW_FPS := 8.0
const IMAGE_FILTER := "*.png,*.jpg,*.jpeg,*.webp;圖片檔"
const MODE_VIEW := 0
const MODE_PIVOT := 1
const MODE_IMAGE := 2
const MODE_HITBOX := 3
const MODE_CROP := 4
const PROP_STATE_LABELS := {"default": "預設(待著時一直循環)", "used": "被使用(和桌寵交互時播)", "drag": "拖曳中(被滑鼠抓著移動時播)"}
const FURNITURE_STATE_LABELS := {"normal": "平時(一直循環)", "conditional": "條件成立時(一直循環)", "interacted": "被使用時(以後才會播)"}

var _model := PackEditorModel.new()
var _canvas: PackFrameCanvas
var _action_list: ItemList
var _action_rows: Array[Dictionary] = []
var _frame_list: ItemList
var _mode_option: OptionButton
var _scope_option: OptionButton
var _pivot_x: SpinBox
var _pivot_y: SpinBox
var _offset_x: SpinBox
var _offset_y: SpinBox
var _hitbox_w: SpinBox
var _hitbox_h: SpinBox
var _hitbox_x: SpinBox
var _hitbox_y: SpinBox
var _hitbox_state: Label
## 光源區(發光效果,見 PackLights):清單與表單。_lights 是目前編輯中的清單(整理過的字典),改了就寫回 pack.json。
var _lights: Array[Dictionary] = []
var _light_index := -1
var _light_list: ItemList
var _light_name: LineEdit
var _light_x: SpinBox
var _light_y: SpinBox
var _light_radius: SpinBox
var _light_energy: SpinBox
var _light_color: ColorPickerButton
var _light_behind_body: CheckBox
## 條件光源 ID(見 PackLights 的 cond_id 說明、Pet.set_conditional_light());空白 = 一般光源。
var _light_cond_id: LineEdit
var _light_cond_copy: Button
## 底部狀態列與右下「檢視」面板的底色(跟著編輯器配色,見 _restyle_panels)。
var _bar_style: StyleBoxFlat
var _view_style: StyleBoxFlat
var _light_action: OptionButton
var _light_enabled: CheckBox
var _light_frame_enabled: CheckBox
var _light_add: Button
var _light_delete: Button
## 配件區(overlays.json,見 PetOverlays):清單與表單。_accs 是目前編輯中的部件清單(字典),改了就寫回模型(存檔時寫進 overlays.json)。
const ACC_ROLES: Array[String] = ["part", "blink", "speak"]
const ACC_LAYERS: Array[String] = ["front", "back", "top", "above_light"]
const ACC_ORIGINS: Array[String] = ["center", "top_left", "bottom_center", "top_center"]
var _accs: Array = []
var _acc_index := -1
var _acc_textures: Dictionary = {}
var _acc_list: ItemList
var _acc_name: LineEdit
var _acc_role: OptionButton
var _acc_layer: OptionButton
var _acc_scale: SpinBox
var _acc_origin: OptionButton
var _acc_x: SpinBox
var _acc_y: SpinBox
var _acc_actions: LineEdit
var _acc_fps: SpinBox
var _acc_loop: CheckBox
var _acc_images: Label
var _acc_add: Button
var _acc_delete: Button
var _acc_add_image: Button
var _acc_clear_images: Button
var _hold_check: CheckBox
var _hold_x: SpinBox
var _hold_y: SpinBox
var _frame_buttons: Array[Button] = []
var _paste_button: Button
var _replace_sheet_button: Button
var _save_as_button: Button
var _light_scope_label: Label
var _light_frame_unlock: CheckBox
var _acc_scope: OptionButton
var _acc_scope_label: Label
var _acc_scope_clear: Button
var _export_frames_button: Button
var _clean_button: Button
var _fps_spin: SpinBox
var _ghost_check: CheckBox
var _play_button: Button
var _undo_button: Button
var _redo_button: Button
var _import_images_button: Button
var _import_sheet_button: Button
var _save_button: Button
var _add_action_button: Button
var _pack_label: Label
var _status: Label
var _info: Label
var _play_timer: Timer
var _fx_buttons: Array[Button] = []
var _rotate_spin: SpinBox
var _crop_spins: Array[SpinBox] = []
var _fx_label: Label
var _guard_dialog: ConfirmationDialog
## 道具編輯區:目前編輯的道具(空 = 一般的角色素材包)與只有角色才用的控制項。
var _prop_id := ""
var _prop_def: PropDef
var _character_only: Array[Control] = []
var _loop_mode: OptionButton
var _loop_start: SpinBox
var _loop_end: SpinBox
var _loop_hold: SpinBox
var _loop_start_row: Control
var _loop_end_row: Control
var _loop_hold_row: Control
var _loop_times: SpinBox
var _loop_times_row: Control
var _loop_note: Label
var _layer_list: ItemList
var _layer_up: Button
var _layer_down: Button
var _layer_eye: Button
var _layer_game: CheckBox
var _layer_note: Label
var _layer_hidden: Dictionary = {}
var _body_hidden := false
var _layer_rows: Array[int] = []
var _layer_body_focus := false
var _right_tabs: TabContainer
var _tab_scrolls: Dictionary = {}
var _toolbar_pack_controls: Array[Control] = []
var _prop_panel: VBoxContainer
var _prop_mode_options: Dictionary = {}
var _prop_count_spins: Dictionary = {}
## 家具(見 furniture_def.gd):目前在編輯哪件家具的進階貼圖(空字串 = 不是)、對應的定義、專屬面板。
var _furniture_id := ""
var _furniture_def: FurnitureDef
var _furniture_panel: VBoxContainer
## 家具的坐/躺錨點與光源改成在這裡編(畫布上看得到相對貼圖的位置,不然數字看不出判定線有沒有放對,見 _build_furniture_panel)。
var _furn_anchor_list: ItemList
var _furn_anchor_type: OptionButton
var _furn_anchor_add: Button
var _furn_anchor_delete: Button
var _furn_anchor_index := -1
var _furn_anchor_x: SpinBox
var _furn_anchor_y: SpinBox
var _furn_anchor_action: LineEdit
var _furn_anchor_facing: OptionButton
var _furn_light_list: ItemList
var _furn_light_add: Button
var _furn_light_delete: Button
var _furn_light_index := -1
## 每盞燈依三個動作槽(FurnitureDef.LIGHT_SLOT_NAMES)分開設定:槽名 → 對應的模式下拉/起訖幀輸入框/幀範圍列(顯示用)。
var _furn_light_slot_mode: Dictionary = {}
var _furn_light_slot_start: Dictionary = {}
var _furn_light_slot_end: Dictionary = {}
var _furn_light_slot_frame_row: Dictionary = {}
var _furn_light_x: SpinBox
var _furn_light_y: SpinBox
var _furn_light_radius: SpinBox
var _furn_light_energy: SpinBox
var _furn_light_color: ColorPickerButton
var _furn_light_shape: OptionButton
var _furn_light_frame_unlock: CheckBox
var _furn_light_frame_enabled: CheckBox
var _furn_light_angle_row: Control
var _furn_light_angle: SpinBox
var _furn_light_spread: SpinBox
var _furn_above_light: CheckBox
var _furn_render_above_ui: CheckBox
## 「光源」「圖層」頁籤裡,角色內容跟家具內容各自的容器(互斥顯示,見 _apply_prop_mode/_build_furniture_panel 檔頭)。
var _char_light_panel: VBoxContainer
var _char_layer_panel: VBoxContainer
var _furn_light_tab_panel: VBoxContainer
var _furn_anchor_tab_panel: VBoxContainer
var _furn_no_anchor_warning: Label
## 目前的動作(素材包裡真實存在的動作名稱;選到空的槽時是 "")。
var _action := ""
## 目前在動作清單裡選的項目名稱:真實動作、或還沒有素材的系統動作槽 / 自訂動作槽。匯入時預設填進動作名稱。
var _slot := ""
## 使用者新增、還沒有素材的自訂動作槽(匯入第一批圖之後就變成真的動作)。
var _extra_slots: Array[String] = []
## 「動作共用」那一排(只有選到系統動作槽時顯示)與它的下拉選單。
var _action_source_row: Control
var _action_source: OptionButton
var _index := 0
var _selected: Array[int] = []
var _updating := false
var _gesture := 0


## 建立視窗內容。folder 非空就順便開啟那個素材包資料夾(給測試與程式用);回傳空字串或開啟失敗的原因。
func setup(folder := "") -> String:
	setup_floating("精靈圖編輯器", Vector2i(1180, 760), Vector2i(960, 560))
	_build()
	_refresh_all()
	if folder != "":
		var error := open_folder(folder)
		if error != "":
			_status.text = tr("無法開啟:%s") % error
		return error
	return ""


func _exit_tree() -> void:
	_model.release()


# --- 建立介面 ---

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
	row.add_child(_build_center())
	row.add_child(_build_right())
	page.add_child(_build_bottom_bar())
	_play_timer = Timer.new()
	_play_timer.wait_time = 1.0 / DEFAULT_PREVIEW_FPS
	_play_timer.timeout.connect(_on_play_tick)
	add_child(_play_timer)
	_restyle_panels()


## 畫布、底部狀態列、「檢視」面板的底色一律取自編輯器配色(全局設定),不再固定深色。
func _restyle_panels() -> void:
	var colors: Dictionary = AppSettings.appearance()["colors"]
	var bg: Color = colors["bg"]
	var panel: Color = colors["panel"]
	var text: Color = colors["text"]
	_bar_style.bg_color = bg.lerp(text, 0.06)
	_view_style.bg_color = bg.lerp(text, 0.04)
	if _canvas != null:
		_canvas.apply_theme_colors(panel, text)


func refresh_theme() -> void:
	super.refresh_theme()
	_restyle_panels()


func _build_toolbar() -> Control:
	var bar := HFlowContainer.new()
	var open := ManagerUi.button("從資料夾匯入…")
	open.tooltip_text = "選一個素材包資料夾:不在專案 sprite 資料夾裡的會複製一份進來(原資料夾不動),已經在裡面的直接開啟。"
	open.pressed.connect(_on_open_pressed)
	var create := ManagerUi.button("新建資料夾…")
	create.tooltip_text = "在專案統一存放 sprite 的資料夾裡新建一個空的素材包。你取的名字同時是資料夾名、角色顯示名稱與預設辨識代號。"
	create.pressed.connect(_on_create_pressed)
	var reveal := ManagerUi.button("📁")
	reveal.tooltip_text = tr("在檔案總管打開專案的 sprite 資料夾(%s)") % SpriteLibrary.ROOT
	reveal.pressed.connect(func() -> void: OS.shell_open(SpriteLibrary.root_dir()))
	_import_images_button = ManagerUi.button("匯入圖片…")
	_import_images_button.tooltip_text = "選一張或多張圖片,當成一個動作的幀(單張圖 = 單幀動作)。動作已存在時會問你覆蓋還是新增。"
	_import_images_button.pressed.connect(_on_import_images_pressed)
	_import_sheet_button = ManagerUi.button("匯入精靈圖…")
	_import_sheet_button.tooltip_text = "選一張精靈圖(一張圖裡排了很多幀),設定格線後切成一個動作的幀。切片只是引用區域,不會另外產生圖檔。"
	_import_sheet_button.pressed.connect(_on_import_sheet_pressed)
	_replace_sheet_button = ManagerUi.button("換精靈圖…")
	_replace_sheet_button.tooltip_text = "用一張新的圖取代正在使用的精靈圖:切片範圍、每一幀的軸心與偏移、動作與播放速度都原封不動,只有圖換掉(新圖尺寸要和原本一樣)。"
	_replace_sheet_button.pressed.connect(_on_replace_sheet_pressed)
	_save_as_button = ManagerUi.button("另存為新素材包…")
	_save_as_button.tooltip_text = "把目前的素材包(含還沒存檔的編輯)複製到一個新的空資料夾,之後編輯的就是新的那個。搭配「換精靈圖」可以把設定好的素材包當範本,快速做出新角色。"
	_save_as_button.pressed.connect(_on_save_as_pressed)
	_export_frames_button = ManagerUi.button("匯出獨立圖檔…")
	_export_frames_button.tooltip_text = "把每個動作的每一幀存成一張張 PNG(<動作>_<編號>.png,已套用切片與裁切翻轉旋轉),另附 frames.json 記錄播放速度、軸心與偏移。可以拿去別的工具用,或當備份。"
	_export_frames_button.pressed.connect(_on_export_frames_pressed)
	_clean_button = ManagerUi.button("清理未使用檔案…")
	_clean_button.tooltip_text = "找出匯入時複製進素材包、但已經沒有任何動作或配件在用的圖檔,確認後搬到備份資料夾(不直接刪)。也可以挑一個有自己實體檔案的動作(不是精靈圖切片),整個清掉它的圖。"
	_clean_button.pressed.connect(_on_clean_pressed)
	_save_button = ManagerUi.button("存檔  Ctrl+S")
	_save_button.pressed.connect(_save)
	_pack_label = Label.new()
	_pack_label.clip_text = true
	_pack_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pack_label.custom_minimum_size.x = 200.0
	_pack_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toolbar_pack_controls = [open, create, reveal]
	for control in [open, create, reveal, VSeparator.new(), _import_images_button, _import_sheet_button, _replace_sheet_button, VSeparator.new(), _save_button, _save_as_button, _export_frames_button, _clean_button, _pack_label]:
		bar.add_child(control)
	return bar


func _build_left() -> Control:
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	left.add_child(ManagerUi.heading("動作"))
	_action_list = ItemList.new()
	_action_list.custom_minimum_size.y = 120
	_action_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_list.size_flags_stretch_ratio = 1.4
	_action_list.tooltip_text = "所有系統動作(idle、walk…)都有一個槽,沒有素材的顯示「空」;選一個空槽再匯入圖片,就會放進那個動作。「代號 ← 名稱」表示素材包裡叫那個名稱的動作填在這個槽。"
	_action_list.item_selected.connect(_on_action_row_selected)
	left.add_child(_action_list)
	_add_action_button = ManagerUi.button("＋新增自訂動作…")
	_add_action_button.tooltip_text = "新增一個自訂動作槽(名字會出現在網頁編輯器的動作下拉選單)。新增後選它,再匯入圖片或精靈圖放進第一批幀。"
	_add_action_button.pressed.connect(_on_add_action_pressed)
	left.add_child(_add_action_button)
	left.add_child(_build_action_source_row())
	left.add_child(ManagerUi.heading("幀(可複選)"))
	left.add_child(_build_frame_buttons())
	_frame_list = ItemList.new()
	_frame_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame_list.custom_minimum_size.y = 90
	_frame_list.icon_mode = ItemList.ICON_MODE_TOP
	_frame_list.max_columns = 0
	_frame_list.fixed_icon_size = THUMB_SIZE
	_frame_list.select_mode = ItemList.SELECT_MULTI
	_frame_list.tooltip_text = "點選一幀;Ctrl+點 加選、Shift+點 選一段。複製、貼上到別的動作、複製一份、刪除、前後移動、圖片處理都對選取的所有幀動作。"
	_frame_list.multi_selected.connect(_on_frame_multi_selected)
	left.add_child(_frame_list)
	left.add_child(_build_animation_settings())
	return left


## 「動作共用」:選到系統動作槽(idle、walk…)時才顯示。walk 找不到 run 專用素材時預設會借用 walk 的畫面(自動,依別名表),
## 這裡可以手動改成「不共用」(這個動作明確留空,交給引擎原本的降級規則,例如 lay → sit → idle)、或指定共用素材包裡任何一個其他動作。
func _build_action_source_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "動作共用"
	label.custom_minimum_size.x = ManagerUi.LABEL_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_action_source = OptionButton.new()
	_action_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_source.item_selected.connect(_on_action_source_selected)
	row.add_child(_action_source)
	row.add_child(ManagerUi.info_icon("這個系統動作(idle、walk…)要用素材包裡哪一個動作的素材。「自動」照別名規則找(walk 找不到 run 專用素材時會借用 walk,這是預設行為,也是「動作」清單裡「run ← walk」的由來)。「不共用(留空)」明確不要借用任何素材,讓這個動作沒有專屬畫面,交給引擎原本的降級規則(例如躺下沒有就退回坐下、坐下沒有就退回待機)。也可以直接選素材包裡任何一個其他動作,手動指定共用對象。只有選到系統動作的槽才會顯示這排;自訂動作沒有這個概念。"))
	_action_source_row = row
	return row


## 依 _slot 重新填「動作共用」下拉選單:只有系統動作槽(ALIASES 有的)才顯示。
func _sync_action_source_widgets() -> void:
	if _action_source_row == null:
		return
	var is_system := _model.has_pack() and not _in_item_mode() and SpritePackLoader.ALIASES.has(_slot)
	_action_source_row.visible = is_system
	if not is_system:
		return
	_updating = true
	_action_source.clear()
	_action_source.add_item(tr("自動(依素材找)"))
	_action_source.set_item_metadata(0, "")
	_action_source.add_item(tr("不共用(這個動作留空)"))
	_action_source.set_item_metadata(1, PackEditorModel.ACTION_SOURCE_NONE)
	var names := _model.action_names()
	names.sort()
	for action_name in names:
		_action_source.add_item(tr("%s(%d 幀)") % [action_name, _model.frame_count(action_name)])
		_action_source.set_item_metadata(_action_source.item_count - 1, action_name)
	var override: Variant = _model.action_override(_slot)
	var selected_index := 0
	if override is bool:   # 只會是 false(明確不共用);型別要先判斷過才能比較,String/Dictionary 和 bool 直接用 == 比會噴執行期錯誤
		selected_index = 1
	elif override is String:
		for i in _action_source.item_count:
			if str(_action_source.get_item_metadata(i)) == str(override):
				selected_index = i
				break
	elif override != null:
		# 進階設定(Dictionary / Array,例如多個隨機差分):加一個代表它的暫時項目,選別的才會被這裡的簡單設定取代。
		_action_source.add_item(tr("目前是進階設定(選別的項目會換成簡單設定)"))
		selected_index = _action_source.item_count - 1
	_action_source.select(selected_index)
	_updating = false


func _on_action_source_selected(index: int) -> void:
	if _updating or not _model.has_pack():
		return
	var source := str(_action_source.get_item_metadata(index))
	var slot := _slot
	_model.checkpoint("action_source:" + slot)
	_model.set_action_source(slot, source)
	# 不能只用 _reload_lists():它盡量保留「原本顯示的動作」,而借用來源換了之後我們要繼續看這個槽(現在借用的新對象),
	# 不是繼續停在舊的來源動作上(例如 run 原本借 walk,改借 sprint 後應該看到 sprint,而不是留在 walk、槽也跟著跳走)。
	_rebuild_action_list()
	_slot = slot
	var resolved := str(_model.slot_sources().get(slot, ""))
	if resolved != "":
		_select_action(resolved)
	else:
		_select_empty_slot(slot)
	if source == PackEditorModel.ACTION_SOURCE_NONE:
		_status.text = tr("「%s」已設成不共用素材(交給引擎原本的降級規則)。") % slot
	elif source == "":
		_status.text = tr("「%s」改回自動尋找素材。") % slot
	else:
		_status.text = tr("「%s」已設成共用「%s」的素材。") % [slot, source]


## 左下角的動畫設定:播放速度與循環方式,跟著目前選的動作,存進 pack.json(fps_by_action、loop_by_action,見 PackLoop)。
## 幀編號就是上面幀清單縮圖上的數字(從 0 開始)。
func _build_animation_settings() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(ManagerUi.heading_with_info("動畫設定", "播放速度:這個動作每秒播幾幀。循環方式:\n・整段循環:從第一幀播到最後一幀,再回到第一幀(預設)。\n・從指定幀循環:第一次從第 0 幀播到「循環終點」幀,之後每次都從「循環起點」幀接回來,只在起點~終點之間循環(例如 2~4:0 1 2 3 4 2 3 4 2 3 4…;終點之後的幀不會播)。\n・播一次,停在指定幀:播到那一幀就停住,直到動作被切換(例如坐下做好後不再動)。\n・循環 N 次:整段動畫重複播 N 次(填 0 = 只播一次、不循環)後停在最後一幀,直到動作被切換;和「播一次,停在指定幀」不同的地方是這個一定播完整段、可以重複好幾輪。\n幀編號就是幀清單縮圖上的數字。設定只影響遊戲裡的播放;預覽動畫裡「循環 N 次」為了方便看清楚會一直重複播放,不會自動停(遊戲裡才會真的停)。"))
	_fps_spin = ManagerUi.spin(1.0, 1.0, 60.0)
	_fps_spin.value = DEFAULT_PREVIEW_FPS
	_fps_spin.tooltip_text = "這個動作的播放速度(每秒幾幀),存進 pack.json 的 fps_by_action;預覽動畫也用這個速度。"
	_fps_spin.value_changed.connect(_on_fps_changed)
	box.add_child(ManagerUi.labeled("速度 FPS", _fps_spin))
	_loop_mode = OptionButton.new()
	for label in ["整段循環", "從指定幀循環", "播一次,停在指定幀", "循環 N 次"]:
		_loop_mode.add_item(label)
	_loop_mode.item_selected.connect(func(_i: int) -> void: _edit_loop())
	box.add_child(ManagerUi.labeled("循環方式", _loop_mode))
	_loop_start = ManagerUi.spin(1.0, 0.0, 999.0)
	_loop_end = ManagerUi.spin(1.0, 0.0, 999.0)
	_loop_hold = ManagerUi.spin(1.0, 0.0, 999.0)
	for spin: SpinBox in [_loop_start, _loop_end, _loop_hold]:
		spin.value_changed.connect(func(_v: float) -> void: _edit_loop())
	_loop_start_row = ManagerUi.labeled("循環起點幀", _loop_start)
	_loop_end_row = ManagerUi.labeled("循環終點幀", _loop_end)
	_loop_hold_row = ManagerUi.labeled("停在第幾幀", _loop_hold)
	for row: Control in [_loop_start_row, _loop_end_row, _loop_hold_row]:
		box.add_child(row)
	_loop_times = ManagerUi.spin(1.0, 0.0, float(PackLoop.MAX_TIMES))
	_loop_times.value_changed.connect(func(_v: float) -> void: _edit_loop())
	_loop_times_row = ManagerUi.labeled("循環次數", _loop_times)
	box.add_child(_loop_times_row)
	_loop_note = Label.new()
	_loop_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loop_note.theme_type_variation = AppSettings.MUTED_LABEL
	box.add_child(_loop_note)
	return box


## 幀清單上方的按鈕:複製 / 貼上 / 複製一份 / 刪除 / 前移 / 後移(快捷鍵見 tooltip)。
func _build_frame_buttons() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	var specs := [
		["複製", "Ctrl+C:複製選取的幀(連同各自的軸心與圖片偏移)", _copy_selected],
		["貼上", "Ctrl+V:貼在選取的幀後面(沒選取就接在最後);可以先切到別的動作再貼", _paste],
		["複製一份", "Ctrl+D:把選取的幀原地複製一份,接在後面", _duplicate_selected],
		["刪除", "Delete:刪掉選取的幀(至少要留一幀)", _delete_selected],
		["◀ 前移", "Alt+←:選取的幀往前移一格", _move_selected.bind(-1)],
		["後移 ▶", "Alt+→:選取的幀往後移一格", _move_selected.bind(1)],
	]
	for spec: Array in specs:
		var button := ManagerUi.button(spec[0])
		button.tooltip_text = spec[1]
		button.pressed.connect(spec[2])
		grid.add_child(button)
		_frame_buttons.append(button)
		if spec[0] == "貼上":
			_paste_button = button
	return grid


func _build_center() -> Control:
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas = PackFrameCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.edit_started.connect(_on_canvas_edit_started)
	_canvas.pivot_edited.connect(_on_canvas_pivot_edited)
	_canvas.offset_edited.connect(_on_canvas_offset_edited)
	_canvas.hitbox_edited.connect(_on_canvas_hitbox_edited)
	_canvas.light_edited.connect(_on_canvas_light_edited)
	_canvas.light_selected.connect(_on_canvas_light_selected)
	_canvas.accessory_edited.connect(_on_canvas_accessory_edited)
	_canvas.accessory_selected.connect(_on_canvas_accessory_selected)
	_canvas.crop_changed.connect(_on_canvas_crop_changed)
	_canvas.crop_confirm_requested.connect(_apply_crop)
	center.add_child(_canvas)
	return center


## 底部:狀態(剛剛發生了什麼)與目前這一幀的資訊/操作說明。固定在視窗底部的一塊,右邊面板再長也不會把它擠出視窗。
func _build_bottom_bar() -> Control:
	var panel := PanelContainer.new()
	_bar_style = StyleBoxFlat.new()
	_bar_style.set_content_margin_all(6.0)
	panel.add_theme_stylebox_override("panel", _bar_style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.theme_type_variation = AppSettings.MUTED_LABEL
	box.add_child(_info)
	return panel


## 右邊:上方是功能頁籤(編輯 / 圖片 / 判定框 / 光源 / 配件 / 圖層,編輯道具時多一個「道具狀態」),
## 下方固定一塊「檢視」(縮放、顯示開關、預覽動畫),不會隨頁籤捲動。動畫速度與循環設定在左下角(見 _build_left)。
func _build_right() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 330
	column.add_theme_constant_override("separation", 6)
	_right_tabs = TabContainer.new()
	_right_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_tabs.tooltip_text = "功能頁籤:編輯(軸心、圖片偏移)、圖片(翻轉旋轉裁切)、判定框、光源、配件、圖層。"
	column.add_child(_right_tabs)
	var right := _new_tab("編輯")
	_mode_option = OptionButton.new()
	_mode_option.add_item("移動視角畫面")
	_mode_option.add_item("移動軸心(腳底線 / 中心點)")
	_mode_option.add_item("移動圖片")
	_mode_option.add_item("調整判定框")
	_mode_option.add_item("裁切圖片")
	_mode_option.add_item("調整光源錨點")
	_mode_option.add_item("調整配件位置")
	_mode_option.tooltip_text = "移動視角畫面:左鍵拖曳平移畫面,不會改到任何資料(預設;中鍵、右鍵拖曳也可以平移)。\n移動軸心:改「圖片上哪一點是腳底」,判定框與坐下都以它為準。\n移動圖片:軸心(腳底線、坐下判定、配件錨點)不動,只有圖片相對它平移。\n調整判定框:拖曳綠框的邊或角改大小,拖曳框裡面移動(整個素材包共用一個)。\n裁切圖片:在畫布上拖出要保留的範圍,再按「套用裁切」。\n調整光源錨點:拖曳畫布上的光源圓點(或用方向鍵)改位置,光的大小、亮度、顏色在右邊「光源」區。"
	_mode_option.item_selected.connect(_on_mode_selected)
	right.add_child(ManagerUi.labeled("模式", _mode_option))
	_scope_option = OptionButton.new()
	_scope_option.add_item("只有這一幀")
	_scope_option.add_item("整個動作(所有幀共用)")
	_scope_option.tooltip_text = "軸心與圖片偏移的改動要寫給這一幀,還是整個動作共用一個值(會清掉這個動作底下逐幀的舊設定)。"
	right.add_child(ManagerUi.labeled("套用範圍", _scope_option))
	_pivot_x = ManagerUi.spin(1.0, 0.0, 4096.0)
	_pivot_y = ManagerUi.spin(1.0, 0.0, 4096.0)
	_offset_x = ManagerUi.spin(1.0, -PackEditorModel.MAX_OFFSET, PackEditorModel.MAX_OFFSET)
	_offset_y = ManagerUi.spin(1.0, -PackEditorModel.MAX_OFFSET, PackEditorModel.MAX_OFFSET)
	_pivot_x.value_changed.connect(func(_v: float) -> void: _on_spin_changed(true))
	_pivot_y.value_changed.connect(func(_v: float) -> void: _on_spin_changed(true))
	_offset_x.value_changed.connect(func(_v: float) -> void: _on_spin_changed(false))
	_offset_y.value_changed.connect(func(_v: float) -> void: _on_spin_changed(false))
	right.add_child(ManagerUi.labeled("中心點 X", _pivot_x))
	right.add_child(ManagerUi.labeled("腳底線 Y", _pivot_y))
	right.add_child(ManagerUi.labeled("圖片偏移 X", _offset_x))
	right.add_child(ManagerUi.labeled("圖片偏移 Y", _offset_y))
	var apply_all := ManagerUi.button("這一幀的值套用到整個動作")
	apply_all.pressed.connect(func() -> void:
		if _action == "":
			return
		_model.checkpoint()
		_model.apply_to_action(_action, _index)
		_after_edit(tr("已套用到「%s」的所有幀") % _action))
	right.add_child(apply_all)
	var reset := ManagerUi.button("重設(自動軸心、偏移 0)")
	reset.pressed.connect(func() -> void:
		if _action == "":
			return
		_model.checkpoint()
		_model.reset(_action, _index, _scope_option.selected == 1)
		_refresh_frame()
		_after_edit("已重設"))
	right.add_child(reset)
	var history_row := HBoxContainer.new()
	_undo_button = ManagerUi.button("↶ 撤回")
	_undo_button.tooltip_text = tr("Ctrl+Z(最多 %d 步)") % PackEditorModel.UNDO_LIMIT
	_undo_button.pressed.connect(_undo)
	_redo_button = ManagerUi.button("↷ 重做")
	_redo_button.tooltip_text = "Ctrl+Y 或 Ctrl+Shift+Z"
	_redo_button.pressed.connect(_redo)
	history_row.add_child(_undo_button)
	history_row.add_child(_redo_button)
	right.add_child(history_row)
	# 家具狀態動畫的說明+「開啟家具庫…」放在這裡(2026-09-23 改成這樣:原本自己開一個「家具設定」頁,
	# 但那頁除了這塊什麼都沒有,不值得佔一個頁籤,擠在同一頁的「編輯」模式下拉旁邊反而好找)。
	_furniture_panel = VBoxContainer.new()
	_furniture_panel.visible = false
	right.add_child(_furniture_panel)
	_build_furniture_panel(_furniture_panel)
	_build_fx_section(_new_tab("圖片"))
	right = _new_tab("判定框")
	right.add_child(ManagerUi.heading("判定框(縮放前像素)"))
	_hitbox_w = ManagerUi.spin(1.0, 1.0, PackEditorModel.MAX_HITBOX)
	_hitbox_h = ManagerUi.spin(1.0, 1.0, PackEditorModel.MAX_HITBOX)
	_hitbox_x = ManagerUi.spin(1.0, -PackEditorModel.MAX_HITBOX, PackEditorModel.MAX_HITBOX)
	_hitbox_y = ManagerUi.spin(1.0, -PackEditorModel.MAX_HITBOX, PackEditorModel.MAX_HITBOX)
	for spin: SpinBox in [_hitbox_w, _hitbox_h, _hitbox_x, _hitbox_y]:
		spin.value_changed.connect(func(_v: float) -> void: _on_hitbox_spin_changed())
	right.add_child(ManagerUi.labeled("寬", _hitbox_w))
	right.add_child(ManagerUi.labeled("高", _hitbox_h))
	right.add_child(ManagerUi.labeled("偏移 X", _hitbox_x))
	right.add_child(ManagerUi.labeled("偏移 Y", _hitbox_y))
	_hitbox_state = Label.new()
	_hitbox_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hitbox_state.theme_type_variation = AppSettings.MUTED_LABEL
	right.add_child(_hitbox_state)
	var clear_hitbox := ManagerUi.button("清除判定框設定(回到自動)")
	clear_hitbox.pressed.connect(func() -> void:
		if not _model.has_pack():
			return
		_model.checkpoint()
		_model.clear_hitbox()
		_refresh_hitbox()
		_after_edit("判定框已回到自動"))
	right.add_child(clear_hitbox)
	var light_tab := _new_tab("光源")
	_char_light_panel = VBoxContainer.new()
	light_tab.add_child(_char_light_panel)
	_build_light_section(_char_light_panel)
	_build_hold_section(_char_light_panel)
	# 家具的光源設定也在這一頁(跟角色共用同一個頁籤與「調整光源錨點」模式,不是另外開一頁),
	# 兩邊內容互斥顯示(見 _apply_prop_mode),這樣「模式」下拉切到光源模式時頁籤才會跳到看得到欄位的地方。
	_furn_light_tab_panel = VBoxContainer.new()
	_furn_light_tab_panel.visible = false
	light_tab.add_child(_furn_light_tab_panel)
	_build_furniture_light_section(_furn_light_tab_panel)
	# 圖層 = 配件:同一頁上面是圖層清單(順序、預覽顯示),下面是選取的圖層的全部設定(名稱、種類、位置、縮放、圖片、在哪些動作顯示…),匯入的圖層都能在這裡編輯。
	var layer_tab := _new_tab("圖層")
	_char_layer_panel = VBoxContainer.new()
	layer_tab.add_child(_char_layer_panel)
	_build_layers_section(_char_layer_panel)
	_char_layer_panel.add_child(HSeparator.new())
	_build_accessory_section(_char_layer_panel)
	# 家具的坐/躺錨點也在這一頁(借「圖層」頁跟「調整配件位置」模式,理由同上)。
	_furn_anchor_tab_panel = VBoxContainer.new()
	_furn_anchor_tab_panel.visible = false
	layer_tab.add_child(_furn_anchor_tab_panel)
	_build_furniture_anchor_section(_furn_anchor_tab_panel)
	# 角色專用的頁籤(編輯道具時收起;編輯家具時留著,換成上面家具那半邊內容,見 _update_tab_visibility)
	for tab_name: String in ["光源", "圖層"]:
		_character_only.append(_tab_scrolls[tab_name])
	_build_prop_panel(_new_tab("道具狀態"))
	# 固定在右下角的「檢視」
	var view_panel := PanelContainer.new()
	_view_style = StyleBoxFlat.new()
	_view_style.set_content_margin_all(6.0)
	view_panel.add_theme_stylebox_override("panel", _view_style)
	right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	view_panel.add_child(right)
	column.add_child(view_panel)
	right.add_child(ManagerUi.heading("檢視"))
	var zoom_row := HBoxContainer.new()
	var zoom_out := ManagerUi.button("－")
	zoom_out.tooltip_text = tr("縮小(滾輪往下也可以):最小 ×%s") % _zoom_text(PackFrameCanvas.MIN_ZOOM)
	zoom_out.pressed.connect(func() -> void: _canvas.zoom_out())
	var zoom_in := ManagerUi.button("＋")
	zoom_in.tooltip_text = tr("放大(滾輪往上也可以):最大 ×%s") % _zoom_text(PackFrameCanvas.MAX_ZOOM)
	zoom_in.pressed.connect(func() -> void: _canvas.zoom_in())
	var zoom_label := Label.new()
	zoom_label.text = "×%s" % _zoom_text(_canvas.zoom)
	zoom_label.custom_minimum_size.x = 50.0
	_canvas.zoom_changed.connect(func(z: float) -> void: zoom_label.text = "×%s" % _zoom_text(z))
	var recenter := ManagerUi.button("回到中央")
	recenter.pressed.connect(_canvas.reset_view)
	for control in [zoom_out, zoom_label, zoom_in, recenter]:
		zoom_row.add_child(control)
	right.add_child(zoom_row)
	_ghost_check = CheckBox.new()
	_ghost_check.text = "顯示上一幀殘影(對齊用)"
	_ghost_check.button_pressed = true
	_ghost_check.toggled.connect(func(on: bool) -> void:
		_canvas.show_ghost = on
		_canvas.queue_redraw())
	right.add_child(_ghost_check)
	var lights_check := CheckBox.new()
	lights_check.text = "顯示光源"
	lights_check.button_pressed = true
	lights_check.toggled.connect(func(on: bool) -> void:
		_canvas.show_lights = on
		_canvas.queue_redraw())
	right.add_child(lights_check)
	var hitbox_check := CheckBox.new()
	hitbox_check.text = "顯示判定框"
	hitbox_check.button_pressed = true
	hitbox_check.toggled.connect(func(on: bool) -> void:
		_canvas.show_hitbox = on
		_canvas.queue_redraw())
	right.add_child(hitbox_check)
	_play_button = ManagerUi.button("▶ 預覽動畫")
	_play_button.toggle_mode = true
	_play_button.toggled.connect(_on_play_toggled)
	right.add_child(_play_button)
	_update_tab_visibility()
	return column


## 右邊的一個功能頁籤:可捲動,回傳裡面的垂直容器(頁籤名稱 = 名字)。
func _new_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	_right_tabs.add_child(scroll)
	_tab_scrolls[tab_name] = scroll
	return box


## 編輯道具/家具時收起角色專用的頁籤(光源、配件、圖層)、顯示對應的狀態頁籤;編輯角色時相反。目前停在被收起的頁籤就回到第一頁。
func _update_tab_visibility() -> void:
	if _right_tabs == null:
		return
	var item_mode := _in_item_mode()
	# 「光源」「圖層」編輯家具時留著(換成家具那半邊內容,見 _apply_prop_mode),只有編輯道具時才整個藏起來
	# (道具的光源在道具視窗自己那套 PropLightPreview 編輯,不用這兩頁)。
	for scroll: Control in _character_only:
		_right_tabs.set_tab_hidden(_right_tabs.get_tab_idx_from_control(scroll), _prop_id != "")
	_right_tabs.set_tab_hidden(_right_tabs.get_tab_idx_from_control(_tab_scrolls["道具狀態"]), _prop_id == "")
	# 「圖層」頁編輯家具時借去放坐/躺錨點,跟角色本來的圖層功能(順序、顯示開關)沒關係,頁籤名稱換掉避免混淆
	# (2026-09-23:使用者反應打開「圖層」頁看到的不是圖層功能,誤以為圖層功能不見了)。
	var layer_idx := _right_tabs.get_tab_idx_from_control(_tab_scrolls["圖層"])
	_right_tabs.set_tab_title(layer_idx, "坐躺位置" if _furniture_id != "" else "圖層")
	if _right_tabs.is_tab_hidden(_right_tabs.current_tab):
		_right_tabs.current_tab = 0


## 依畫布的編輯模式跳到對應的頁籤(調整光源錨點 → 光源、調整配件位置 → 配件)。
func _show_tab_for_mode(index: int) -> void:
	var wanted := {5: "光源", 6: "圖層"}.get(index, "") as String
	if wanted != "" and _tab_scrolls.has(wanted):
		_right_tabs.current_tab = _right_tabs.get_tab_idx_from_control(_tab_scrolls[wanted])


func _zoom_text(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else str(snappedf(value, 0.01))


## 圖片處理:水平/垂直翻轉、以角度旋轉、裁切,都作用在選取的幀,寫在 pack.json 的 frames 項目(fx 欄位),不改原圖檔。
func _build_fx_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("圖片處理(選取的幀)", "作用在左邊選取的所有幀(可複選)。只寫在 pack.json 的 frames 項目(fx 欄位),不改原圖檔;已設定的軸心會跟著換算;可以撤回。"))
	var flip_row := HBoxContainer.new()
	var flip_h := ManagerUi.button("↔ 水平翻轉")
	flip_h.tooltip_text = "左右對調。再按一次就翻回來。"
	flip_h.pressed.connect(func() -> void: _apply_fx_op({"op": "h"}, "已水平翻轉"))
	var flip_v := ManagerUi.button("↕ 垂直翻轉")
	flip_v.tooltip_text = "上下對調。再按一次就翻回來。"
	flip_v.pressed.connect(func() -> void: _apply_fx_op({"op": "v"}, "已垂直翻轉"))
	flip_row.add_child(flip_h)
	flip_row.add_child(flip_v)
	right.add_child(flip_row)
	var rotate_row := HBoxContainer.new()
	_rotate_spin = ManagerUi.spin(1.0, -360.0, 360.0)
	_rotate_spin.allow_greater = false
	_rotate_spin.allow_lesser = false
	_rotate_spin.value = 90.0
	_rotate_spin.suffix = "°"
	_rotate_spin.tooltip_text = "順時針旋轉的角度(負數 = 逆時針)。90 的倍數是無損的;其他角度畫布會放大到裝得下整張圖,空白處透明。"
	var rotate_button := ManagerUi.button("↻ 旋轉")
	rotate_button.pressed.connect(func() -> void:
		if is_zero_approx(_rotate_spin.value):
			_status.text = "旋轉角度是 0,什麼都不會改變"
			return
		_apply_fx_op({"op": "r", "degrees": _rotate_spin.value}, tr("已旋轉 %s°") % _zoom_text(_rotate_spin.value)))
	rotate_row.add_child(_rotate_spin)
	rotate_row.add_child(rotate_button)
	right.add_child(rotate_row)
	right.add_child(ManagerUi.hint_row("裁切範圍(圖片像素)", "切到「裁切圖片」模式在畫布上拖曳畫出要保留的範圍,或直接填下面的數字(左、上、寬、高),再按「套用裁切」(裁切模式下按 Enter 也可以)。"))
	var crop_grid := GridContainer.new()
	crop_grid.columns = 4
	for caption in ["左", "上", "寬", "高"]:
		var spin := ManagerUi.spin(1.0, 0.0, 4096.0)
		spin.allow_greater = false
		spin.allow_lesser = false
		spin.custom_minimum_size.x = 60.0
		spin.tooltip_text = tr("裁切範圍的%s(圖片像素)") % caption
		spin.value_changed.connect(func(_v: float) -> void: _on_crop_spin_changed())
		_crop_spins.append(spin)
		crop_grid.add_child(spin)
	right.add_child(crop_grid)
	var crop_row := HBoxContainer.new()
	var crop_apply := ManagerUi.button("套用裁切")
	crop_apply.tooltip_text = "把選取的幀都裁成這個範圍(超出圖片的部分截掉)。裁切模式下按 Enter 也可以。"
	crop_apply.pressed.connect(_apply_crop)
	var crop_clear := ManagerUi.button("清掉裁切框")
	crop_clear.pressed.connect(func() -> void: _set_crop_ui(Rect2i()))
	crop_row.add_child(crop_apply)
	crop_row.add_child(crop_clear)
	right.add_child(crop_row)
	_fx_label = Label.new()
	_fx_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fx_label.theme_type_variation = AppSettings.WARN_LABEL
	right.add_child(_fx_label)
	var fx_clear := ManagerUi.button("還原圖片處理(回到原圖)")
	fx_clear.tooltip_text = "拿掉選取的幀的所有裁切、翻轉、旋轉。這些幀手動設定過的軸心是相對處理後的圖,會一併回到自動軸心。"
	fx_clear.pressed.connect(_clear_fx)
	right.add_child(fx_clear)
	_fx_buttons = [flip_h, flip_v, rotate_button, crop_apply, crop_clear, fx_clear]


func _on_mode_selected(index: int) -> void:
	_canvas.mode = [PackFrameCanvas.Mode.VIEW, PackFrameCanvas.Mode.PIVOT, PackFrameCanvas.Mode.IMAGE, PackFrameCanvas.Mode.HITBOX, PackFrameCanvas.Mode.CROP, PackFrameCanvas.Mode.LIGHT, PackFrameCanvas.Mode.ACCESSORY][index]
	_canvas.queue_redraw()
	_show_tab_for_mode(index)


# --- 開啟 / 新建 / 匯入 ---

## 開啟素材包資料夾(有未存的變更時由呼叫端先確認)。成功回空字串,失敗回原因。
func open_folder(folder: String) -> String:
	_prop_id = ""
	_prop_def = null
	_furniture_id = ""
	_furniture_def = null
	var error := _model.open(folder)
	if error == "":
		_after_pack_loaded("已開啟素材包")
	return error


## 新建素材包(資料夾不存在就建立;已有內容則照原樣開啟)。成功回空字串。給測試與程式用;使用者走「新建資料夾…」(create_named)。
func create_folder(folder: String) -> String:
	_prop_id = ""
	_prop_def = null
	_furniture_id = ""
	_furniture_def = null
	var error := _model.create(folder)
	if error == "":
		_after_pack_loaded("已新建素材包(還沒有動作:選一個動作槽,再用「匯入圖片」或「匯入精靈圖」放進第一個動作)" if _model.action_names().is_empty() else "已開啟素材包")
	return error


## 在專案的 sprite 資料夾裡新建素材包(名字 = 資料夾名 = 角色顯示名稱 = 預設辨識代號)。成功回空字串。
func create_named(display_name: String) -> String:
	var created := SpriteLibrary.create_pack(display_name)
	if not bool(created["ok"]):
		return str(created["error"])
	var error := create_folder(str(created["folder"]))
	if error == "":
		_status.text = tr("已在 sprite 資料夾新建「%s」(名字同時是資料夾名、角色名稱與預設辨識代號)。選一個動作槽,再匯入圖片或精靈圖放進第一個動作。") % display_name.strip_edges()
	return error


## 從外面的資料夾匯入:不在 sprite 資料夾裡就複製一份進來(display_name 空白 = 沿用原資料夾名),然後開啟那份。成功回空字串。
func import_folder_copy(source: String, display_name := "") -> String:
	var imported := SpriteLibrary.import_folder(source, display_name)
	if not bool(imported["ok"]):
		return str(imported["error"])
	var error := open_folder(str(imported["folder"]))
	if error == "" and bool(imported["copied"]):
		_status.text = tr("已把資料夾複製到 sprite 資料夾:%s(原資料夾沒有動)。之後編輯的是這一份。") % str(imported["folder"])
	return error


func _after_pack_loaded(message: String) -> void:
	_action = ""
	_slot = ""
	_extra_slots.clear()
	_index = 0
	_reload_lists()
	_status.text = message
	_refresh_all()


func _on_open_pressed() -> void:
	guard_unsaved(_choose_folder_to_open, "匯入")


func _choose_folder_to_open() -> void:
	_show_file_dialog("選擇要匯入的素材包資料夾", DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(), _on_open_picked, SpriteLibrary.root_dir())


func _on_open_picked(paths: PackedStringArray) -> void:
	var source := str(paths[0])
	if SpriteLibrary.is_inside(source):
		var error := open_folder(source)
		if error != "":
			_status.text = tr("無法開啟:%s") % error
		return
	_ask_name("匯入資料夾", "會把這個資料夾複製一份進專案的 sprite 資料夾(原資料夾不動)。\n幫這個角色取個名字(同時是資料夾名、角色名稱與預設辨識代號):", source.get_file(), "匯入", func(chosen: String) -> void:
		var error := import_folder_copy(source, chosen)
		if error != "":
			_status.text = tr("無法匯入:%s") % error)


func _on_create_pressed() -> void:
	guard_unsaved(_ask_new_pack_name, "新建")


func _ask_new_pack_name() -> void:
	_ask_name("新建資料夾", "在專案的 sprite 資料夾裡新建一個素材包。\n幫這個角色取個名字(同時是資料夾名、角色名稱與預設辨識代號,之後可以改 pack.json):", "", "新建", func(chosen: String) -> void:
		var error := create_named(chosen)
		if error != "":
			_status.text = tr("無法新建:%s") % error)


## 問使用者一個名字的小視窗;名字不合格時確定鈕是停用的並說明原因。on_chosen(name) 在按確定後呼叫。
func _ask_name(title_text: String, message: String, default_name: String, ok_text: String, on_chosen: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	# 不設 always_on_top:這種視窗會被 Godot 設成這個(可能置頂的)浮動視窗的 transient 子視窗,跟置頂在
	# Windows 原生視窗上互斥(godotengine/godot#117698,4.7.2 尚未修正),硬設會把視窗卡死到連工作列都找不到
	# (2026-09-30 使用者實機回報)。身為 owned window,Windows 本來就會自動疊在浮動視窗上面,不需要自己也置頂。
	dialog.title = title_text
	dialog.ok_button_text = ok_text
	dialog.cancel_button_text = "取消"
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420.0
	box.add_child(label)
	var edit := ManagerUi.line_edit("角色名稱")
	edit.max_length = SpriteLibrary.MAX_NAME
	edit.text = default_name
	box.add_child(edit)
	var problem := Label.new()
	problem.theme_type_variation = AppSettings.WARN_LABEL
	box.add_child(problem)
	dialog.add_child(box)
	var validate := func(text: String) -> void:
		var reason := SpriteLibrary.name_problem(text)
		problem.text = reason
		dialog.get_ok_button().disabled = reason != ""
	edit.text_changed.connect(validate)
	dialog.confirmed.connect(func() -> void: on_chosen.call(edit.text.strip_edges()))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	validate.call(edit.text)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(480, 220))
		edit.grab_focus()
		edit.select_all()


## 離開目前的素材包(或做會丟掉編輯內容的事)之前一律先過這一關:沒有未存的變更就直接做;有的話跳出「存檔後繼續 / 放棄變更 / 取消」。
## action_text 是繼續要做的事(「關閉」「匯入」…),顯示在按鈕上。之後加「模式切換」(導入角色動作圖 / 導入配件…)也要走這裡。
func guard_unsaved(proceed: Callable, action_text := "繼續") -> void:
	if not _model.dirty:
		proceed.call()
		return
	if is_instance_valid(_guard_dialog):
		return
	_guard_dialog = ConfirmationDialog.new()
	# 不設 always_on_top,見 _ask_name() 的說明(跟置頂衝突,會把視窗卡死)。
	_guard_dialog.title = "有未存的變更"
	_guard_dialog.dialog_text = tr("目前的素材包有還沒存檔的變更。\n要先存檔再%s、放棄這些變更直接%s,還是取消?") % [action_text, action_text]
	_guard_dialog.ok_button_text = tr("存檔後%s") % action_text
	_guard_dialog.cancel_button_text = "取消"
	_guard_dialog.add_button(tr("放棄變更並%s") % action_text, true, "discard")
	_guard_dialog.confirmed.connect(func() -> void:
		_save()
		if not _model.dirty:
			proceed.call())
	_guard_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			_guard_dialog.hide()
			_guard_dialog.queue_free()
			proceed.call())
	_guard_dialog.confirmed.connect(_guard_dialog.queue_free)
	_guard_dialog.canceled.connect(_guard_dialog.queue_free)
	add_child(_guard_dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), _guard_dialog, Vector2i(480, 180))


## 開系統的檔案對話框(對這個視窗模態);使用者選好後才呼叫 on_picked(paths)。start_dir 非空就從那個資料夾開始。
func _show_file_dialog(title_text: String, dialog_mode: DisplayServer.FileDialogMode, filters: PackedStringArray, on_picked: Callable, start_dir := "") -> void:
	FloatingWindow.native_file_dialog(title_text, start_dir, dialog_mode, filters, on_picked, get_window_id())


func _on_import_images_pressed() -> void:
	if _model.has_pack():
		_show_file_dialog("選擇要匯入的圖片(可多選)", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]), _on_images_picked)


func _on_images_picked(paths: PackedStringArray) -> void:
	open_import_images_dialog(Array(paths))


func _on_import_sheet_pressed() -> void:
	if _model.has_pack():
		_show_file_dialog("選擇要匯入的精靈圖", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray([IMAGE_FILTER]), _on_sheet_picked)


func _on_sheet_picked(paths: PackedStringArray) -> void:
	open_import_sheet_dialog(paths[0])


## 匯入對話框裡動作名稱的預設值:目前選的動作(或選的空槽);都沒有就用檔名猜。
func _default_import_name(file_base: String) -> String:
	if _action != "":
		return _action
	if _slot != "":
		return _slot
	return _suggest_name(file_base)


## 開匯入圖片對話框(選完檔案之後;也給測試用)。
func open_import_images_dialog(paths: Array) -> PackImportDialog:
	var names: Array = paths.map(func(p: String) -> String: return p.get_file())
	var dialog := PackImportDialog.new()
	add_child(dialog)
	dialog.setup_images(names, _existing_actions(), _default_import_name(str(paths[0]).get_file().get_basename()))
	dialog.import_confirmed.connect(func(params: Dictionary) -> void: _do_import(_model.import_images(paths, params["action"], params["mode"]), params["action"]))
	_finish_dialog(dialog)
	return dialog


func open_import_sheet_dialog(path: String) -> PackImportDialog:
	var report: Array[String] = []
	var image := SpritePackLoader.load_frame_image(path, report)
	if image == null:
		_status.text = tr("讀不出這張精靈圖:%s") % path.get_file()
		return null
	var dialog := PackImportDialog.new()
	add_child(dialog)
	dialog.setup_sheet(image, path.get_file(), _existing_actions(), _default_import_name(path.get_file().get_basename()))
	dialog.import_confirmed.connect(func(params: Dictionary) -> void: _do_import(_model.import_sheet(path, params["grid"], params["action"], params["mode"]), params["action"]))
	_finish_dialog(dialog)
	return dialog


func _finish_dialog(dialog: PackImportDialog) -> void:
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(540, 640) if dialog.title == "匯入精靈圖" else Vector2i(540, 220))


func _existing_actions() -> Array[String]:
	return _model.action_names()


## 用檔名猜動作名稱:去掉尾端的序號與分隔線(walk_03 → walk),空的就用 anim。
func _suggest_name(base_name: String) -> String:
	var cleaned := base_name.rstrip("0123456789_- ")
	return SpritePackLoader.clean_action_name(cleaned) if cleaned != "" else "anim"


func _do_import(error: String, action: String) -> void:
	if error != "":
		_status.text = tr("匯入失敗:%s") % error
		return
	_action = action
	_slot = action
	_extra_slots.erase(action)
	_index = 0
	_reload_lists()
	_after_edit(tr("已匯入到動作「%s」(可以用撤回還原)") % action)
	_refresh_all()


# --- 動作與幀 ---

## 道具狀態動畫區:被使用、拖曳中各自的播放方式(觸發 = 進入狀態時播幾次就回預設;循環 = 狀態持續期間一直循環)。改了立刻存進道具設定。
func _build_prop_panel(right: VBoxContainer) -> void:
	_prop_panel = VBoxContainer.new()
	_prop_panel.visible = false
	right.add_child(_prop_panel)
	_prop_panel.add_child(ManagerUi.heading_with_info("道具狀態動畫", "預設:道具待著時一直循環。被使用:和桌寵交互時播(被拾取時、摩擦觸發時)。拖曳中:被滑鼠抓著移動時才播。被使用與拖曳中可以設播放次數,以及「觸發」(進入狀態時播幾次就回預設)或「循環」(狀態持續期間一直循環)。沒有放圖的狀態就不播;預設狀態一定要有圖,進階貼圖才會生效(沒有就用簡單版的一張圖)。"))
	for state: String in ["used", "drag"]:
		var mode := OptionButton.new()
		mode.add_item("觸發時播放")
		mode.add_item("循環播放")
		var count := ManagerUi.spin(1.0, 1.0, PropDef.MAX_STATE_COUNT)
		count.suffix = " 次(觸發式)"
		mode.item_selected.connect(func(_i: int) -> void: _edit_prop_state(state))
		count.value_changed.connect(func(_v: float) -> void: _edit_prop_state(state))
		_prop_mode_options[state] = mode
		_prop_count_spins[state] = count
		_prop_panel.add_child(ManagerUi.labeled("被使用" if state == "used" else "拖曳中", mode))
		_prop_panel.add_child(ManagerUi.labeled("播放次數", count))


func _edit_prop_state(state: String) -> void:
	if _updating or _prop_def == null:
		return
	var mode: String = "loop" if (_prop_mode_options[state] as OptionButton).selected == 1 else "trigger"
	var count := int((_prop_count_spins[state] as SpinBox).value)
	if state == "used":
		_prop_def.used_mode = mode
		_prop_def.used_count = count
	else:
		_prop_def.drag_mode = mode
		_prop_def.drag_count = count
	PropLibrary.save_def(_prop_def)


## 家具狀態的說明+「開啟家具庫…」:實際的觸發方式(時段、動作代號)在家具庫視窗編輯,這裡只解釋三個動作槽的用途,
## 避免兩處重複同一組控制項。跟著「編輯」頁(_build_right)走,不自己另開頁籤(2026-09-23 改成這樣:原本自己開一個
## 「家具設定」頁,但除了這塊什麼都沒有,使用者反應點進去像是在教怎麼設定觸發條件,不值得佔一個頁籤)。
## 坐/躺錨點在「坐躺位置」頁(_build_furniture_anchor_section,借用角色原本的「圖層」頁與「調整配件位置」模式)、
## 光源在「光源」頁(_build_furniture_light_section),跟角色共用同一個頁籤與「模式」下拉,才會在切到對應編輯
## 模式時自動跳過去、看得到欄位。
func _build_furniture_panel(panel: VBoxContainer) -> void:
	panel.add_child(ManagerUi.heading_with_info("家具狀態動畫", "normal(平時):一直循環播放,家具沒有觸發條件時就是這個樣子。conditional(條件成立時):一直循環播放,例如檯燈亮起來、迪斯可燈在轉;觸發條件(指定時段、有桌寵在做某個動作…)在家具庫視窗設定,不在這裡。interacted(被使用時):素材可以先準備,這批還沒有東西會讓桌寵去用家具、播放這個狀態。沒有放圖的狀態就不播;normal 一定要有圖。"))
	var open_library := ManagerUi.button("開啟家具庫…")
	open_library.tooltip_text = "去家具庫視窗改名稱、觸發方式(時段/動作代號)、標籤、縮放倍率、放上桌面。"
	open_library.pressed.connect(func() -> void: furniture_settings_requested.emit())
	panel.add_child(open_library)
	_furn_no_anchor_warning = Label.new()
	_furn_no_anchor_warning.theme_type_variation = AppSettings.WARN_LABEL
	_furn_no_anchor_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_furn_no_anchor_warning.text = "⚠ 這件家具還沒有坐/躺位置(去「坐躺位置」頁加),桌寵沒辦法用它坐下或躺下。"
	panel.add_child(_furn_no_anchor_warning)


## 坐/躺錨點:跟角色的配件系統共用「圖層」頁與「調整配件位置」模式(畫布借用配件的十字/拖曳畫法,不是真的配件,
## 見 _furniture_accessory_previews)。上面「模式」切「調整配件位置」才能在畫布拖;下面的座標框任何時候都能直接打數字。
func _build_furniture_anchor_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("坐/躺位置(錨點)", "桌寵想用這件家具時,自己挑一個當下沒人在用的位置過去。上面「模式」選「調整配件位置」後可以直接在畫布上拖曳錨點(或用方向鍵),放在貼圖的正確位置上;也可以直接在下面打座標。清單選了哪一個,畫布上就是拖哪一個、下面的座標框就是改哪一個。"))
	_furn_anchor_list = ItemList.new()
	_furn_anchor_list.custom_minimum_size.y = 84.0
	_furn_anchor_list.item_selected.connect(func(index: int) -> void:
		_furn_anchor_index = index
		_refresh_furniture_anchors())
	right.add_child(_furn_anchor_list)
	var anchor_buttons := HBoxContainer.new()
	_furn_anchor_type = OptionButton.new()
	for kind: String in FurnitureDef.ANCHOR_TYPES:
		_furn_anchor_type.add_item("坐" if kind == "sit" else "躺")
		_furn_anchor_type.set_item_metadata(_furn_anchor_type.item_count - 1, kind)
	anchor_buttons.add_child(_furn_anchor_type)
	_furn_anchor_add = ManagerUi.button("＋ 新增")
	_furn_anchor_add.pressed.connect(_on_furn_anchor_add_pressed)
	anchor_buttons.add_child(_furn_anchor_add)
	_furn_anchor_delete = ManagerUi.button("刪除這個")
	_furn_anchor_delete.pressed.connect(_on_furn_anchor_delete_pressed)
	anchor_buttons.add_child(_furn_anchor_delete)
	right.add_child(anchor_buttons)
	var pos_row := HBoxContainer.new()
	_furn_anchor_x = ManagerUi.spin(1.0, -FurnitureDef.ANCHOR_RANGE, FurnitureDef.ANCHOR_RANGE)
	_furn_anchor_x.value_changed.connect(func(v: float) -> void: _edit_furn_anchor_position(Vector2(v, _furn_anchor_y.value)))
	pos_row.add_child(_furn_anchor_x)
	_furn_anchor_y = ManagerUi.spin(1.0, -FurnitureDef.ANCHOR_RANGE, FurnitureDef.ANCHOR_RANGE)
	_furn_anchor_y.value_changed.connect(func(v: float) -> void: _edit_furn_anchor_position(Vector2(_furn_anchor_x.value, v)))
	pos_row.add_child(_furn_anchor_y)
	right.add_child(ManagerUi.labeled("座標(X,Y)", pos_row))
	_furn_anchor_action = ManagerUi.line_edit("留空 = 用預設的坐/躺姿勢")
	_furn_anchor_action.text_submitted.connect(func(_t: String) -> void: _edit_furn_anchor_action())
	_furn_anchor_action.focus_exited.connect(_edit_furn_anchor_action)
	var action_row := ManagerUi.labeled("行為重綁(選填)", _furn_anchor_action)
	action_row.add_child(InfoIcon.new("桌寵坐/躺到這個錨點時,改播這個名字的動作(素材包裡的動作名稱)取代預設的坐/躺姿勢。那隻桌寵的素材包沒有這個動作時,自動退回原本的坐/躺;留空就一律用原本的坐/躺,不用特別清空。給素材包作者準備了不同姿勢動作時用。"))
	right.add_child(action_row)
	_furn_anchor_facing = OptionButton.new()
	for facing: String in FurnitureDef.ANCHOR_FACINGS:
		_furn_anchor_facing.add_item({"both": "兩者(隨機擇一)", "left": "左", "right": "右"}[facing])
		_furn_anchor_facing.set_item_metadata(_furn_anchor_facing.item_count - 1, facing)
	_furn_anchor_facing.item_selected.connect(func(_i: int) -> void: _edit_furn_anchor_facing())
	var facing_row := ManagerUi.labeled("使用時面向", _furn_anchor_facing)
	facing_row.add_child(InfoIcon.new("桌寵坐/躺到這個錨點時要面向哪邊。「兩者」是預設值,每次使用時隨機選一個方向(不是使用中途左右來回切換);選「左」或「右」會固定面向那一邊。"))
	right.add_child(facing_row)


## 光源:跟角色的光源系統共用「光源」頁與「調整光源錨點」模式(畫布借用同一套多光源清單,不是真的加進角色的光源清單,
## 見 _furniture_lights_preview)。一件家具可以有好幾盞燈(2026-09-23 從單一光源改成清單,像坐/躺錨點那樣有自己的清單
## 可以新增/刪除,列在 _furn_light_list),above_light 疊層順序是整件家具共用一個,不分開放在每盞燈上。
func _build_furniture_light_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("光源", tr("一件家具可以有好幾盞燈(例如吊燈好幾顆燈泡),最多 %d 盞。「一直啟用」以外的觸發方式時,燈只有條件成立(conditional 狀態)才會亮;畫布上的預覽會照現在的真實時間顯示目前應該是亮是暗(不是條件成立的時段會變暗),不用真的等到觸發才看得出來。上面「模式」選「調整光源錨點」後可以直接在畫布上拖曳選取的那一盞,或直接在下面打座標。") % FurnitureDef.MAX_LIGHTS))
	_furn_light_list = ItemList.new()
	_furn_light_list.custom_minimum_size.y = 84.0
	_furn_light_list.item_selected.connect(func(index: int) -> void:
		_furn_light_index = index
		_refresh_furniture_lights())
	right.add_child(_furn_light_list)
	var list_buttons := HBoxContainer.new()
	_furn_light_add = ManagerUi.button("＋ 新增光源")
	_furn_light_add.pressed.connect(_on_furn_light_add_pressed)
	list_buttons.add_child(_furn_light_add)
	_furn_light_delete = ManagerUi.button("刪除這盞")
	_furn_light_delete.pressed.connect(_on_furn_light_delete_pressed)
	list_buttons.add_child(_furn_light_delete)
	right.add_child(list_buttons)
	right.add_child(ManagerUi.heading_with_info("依動作槽設定啟用條件", tr("這件家具現在播哪個動作槽(平時/條件成立時/使用中),這盞燈就照那個槽自己的設定決定要不要亮:不啟用、一直啟用,或只有目前幀落在指定範圍才亮(例如蠟燭動畫只有中間幾幀火苗最亮時才發光)。「使用中」這個動作槽目前還沒有真的接上播放,先讓你設定,之後接上就會生效。")))
	for slot_name: String in FurnitureDef.LIGHT_SLOT_NAMES:
		_build_furn_light_slot_row(right, slot_name)
	var pos_row := HBoxContainer.new()
	_furn_light_x = ManagerUi.spin(1.0, -FurnitureDef.ANCHOR_RANGE, FurnitureDef.ANCHOR_RANGE)
	_furn_light_x.value_changed.connect(func(v: float) -> void: _edit_furn_light("x", v))
	pos_row.add_child(_furn_light_x)
	_furn_light_y = ManagerUi.spin(1.0, -FurnitureDef.ANCHOR_RANGE, FurnitureDef.ANCHOR_RANGE)
	_furn_light_y.value_changed.connect(func(v: float) -> void: _edit_furn_light("y", v))
	pos_row.add_child(_furn_light_y)
	right.add_child(ManagerUi.labeled("座標(X,Y)", pos_row))
	_furn_light_frame_unlock = CheckBox.new()
	_furn_light_frame_unlock.text = "單獨調整此幀"
	_furn_light_frame_unlock.tooltip_text = "第 0 幀(或還沒解鎖的幀)的半徑/亮度/顏色/是否亮著都跟著這盞燈的預設值(或動作槽的判斷)走。勾選這裡才能單獨改目前這一幀,不影響其他幀;取消勾選會清掉這一幀的所有覆蓋。「是否亮著」比較特別:單獨調整過可以雙向覆蓋動作槽原本的判斷——即使動作槽判斷這一幀該暗,解鎖後還是可以單獨打開,反之亦然。"
	_furn_light_frame_unlock.toggled.connect(_on_furn_light_frame_unlock_toggled)
	right.add_child(_furn_light_frame_unlock)
	_furn_light_radius = ManagerUi.spin(1.0, FurnitureDef.LIGHT_LIMITS["radius"].x, FurnitureDef.LIGHT_LIMITS["radius"].y)
	_furn_light_radius.value_changed.connect(func(v: float) -> void: _edit_furn_light_scoped("radius", v))
	right.add_child(ManagerUi.labeled("光暈半徑", _furn_light_radius))
	_furn_light_energy = ManagerUi.spin(0.05, FurnitureDef.LIGHT_LIMITS["energy"].x, FurnitureDef.LIGHT_LIMITS["energy"].y)
	_furn_light_energy.value_changed.connect(func(v: float) -> void: _edit_furn_light_scoped("energy", v))
	right.add_child(ManagerUi.labeled("光暈強度", _furn_light_energy))
	_furn_light_color = ColorPickerButton.new()
	_furn_light_color.edit_alpha = false
	_furn_light_color.custom_minimum_size = Vector2(120, 28)
	_furn_light_color.color_changed.connect(func(color: Color) -> void: _edit_furn_light_scoped("color", "#" + color.to_html(false)))
	right.add_child(ManagerUi.labeled("光源顏色", _furn_light_color))
	_furn_light_frame_enabled = CheckBox.new()
	_furn_light_frame_enabled.text = "亮著(單獨調整此幀時生效)"
	_furn_light_frame_enabled.tooltip_text = "只有勾選「單獨調整此幀」時才能改;決定這一幀要不要亮,雙向覆蓋動作槽原本的判斷。"
	_furn_light_frame_enabled.toggled.connect(func(on: bool) -> void: _edit_furn_light_scoped("enabled", on))
	right.add_child(_furn_light_frame_enabled)
	_furn_light_shape = OptionButton.new()
	for kind: String in FurnitureDef.LIGHT_SHAPES:
		_furn_light_shape.add_item("圓形" if kind == "radial" else "扇形")
		_furn_light_shape.set_item_metadata(_furn_light_shape.item_count - 1, kind)
	_furn_light_shape.item_selected.connect(func(i: int) -> void:
		_edit_furn_light("shape", str(_furn_light_shape.get_item_metadata(i)))
		_sync_furn_light_shape_visibility())
	right.add_child(ManagerUi.labeled("光源形狀", _furn_light_shape))
	_furn_light_angle_row = VBoxContainer.new()
	_furn_light_angle = ManagerUi.spin(1.0, FurnitureDef.LIGHT_LIMITS["angle"].x, FurnitureDef.LIGHT_LIMITS["angle"].y)
	_furn_light_angle.value_changed.connect(func(v: float) -> void: _edit_furn_light("angle", v))
	_furn_light_angle_row.add_child(ManagerUi.labeled("朝向角度", _furn_light_angle))
	_furn_light_spread = ManagerUi.spin(1.0, FurnitureDef.LIGHT_LIMITS["spread"].x, FurnitureDef.LIGHT_LIMITS["spread"].y)
	_furn_light_spread.value_changed.connect(func(v: float) -> void: _edit_furn_light("spread", v))
	_furn_light_angle_row.add_child(ManagerUi.labeled("扇形張角", _furn_light_spread))
	right.add_child(_furn_light_angle_row)
	_furn_above_light = CheckBox.new()
	_furn_above_light.text = "貼圖蓋在光暈之上(預設光暈疊在貼圖上面)"
	_furn_above_light.toggled.connect(func(on: bool) -> void:
		if _updating or _furniture_def == null:
			return
		_furniture_def.above_light = on
		_save_furniture())
	right.add_child(_furn_above_light)
	_furn_render_above_ui = CheckBox.new()
	_furn_render_above_ui.text = "顯示在桌寵與對話氣泡之上"
	_furn_render_above_ui.tooltip_text = "平時家具會被桌寵、對話氣泡蓋住;勾選後改畫在最上層,協助自製 UI(例如當成一塊固定貼在畫面上的相框/邊框)。編輯模式拖曳、光源、坐躺、容器都不受影響,純粹只是換一個畫面圖層。"
	_furn_render_above_ui.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_furn_render_above_ui.toggled.connect(func(on: bool) -> void:
		if _updating or _furniture_def == null:
			return
		_furniture_def.render_above_ui = on
		_save_furniture())
	right.add_child(_furn_render_above_ui)


## 座標框改了(打數字,不是畫布拖曳):跟畫布拖曳走同一條路(_on_canvas_light_edited),數字/拖曳兩邊永遠同步。
func _edit_furn_anchor_position(at: Vector2) -> void:
	if _updating:
		return
	_on_canvas_accessory_edited(_furn_anchor_index, at)


## 行為重綁欄位改了:存回這個錨點的 action 覆蓋值(留空 = 沒有覆蓋,退回 type 本身的預設坐/躺)。
func _edit_furn_anchor_action() -> void:
	if _updating or _furniture_def == null or _furn_anchor_index < 0 or _furn_anchor_index >= _furniture_def.anchors.size():
		return
	_furniture_def.anchors[_furn_anchor_index]["action"] = _furn_anchor_action.text.strip_edges().left(FurnitureDef.MAX_NAME)
	_save_furniture()


## 「使用時面向」下拉選單改了:存回這個錨點的 facing。
func _edit_furn_anchor_facing() -> void:
	if _updating or _furniture_def == null or _furn_anchor_index < 0 or _furn_anchor_index >= _furniture_def.anchors.size():
		return
	_furniture_def.anchors[_furn_anchor_index]["facing"] = str(_furn_anchor_facing.get_item_metadata(_furn_anchor_facing.selected))
	_save_furniture()


## 家具存檔(furniture.json,跟素材包的 pack.json 是分開的檔案,見 FurnitureLibrary)。
func _save_furniture() -> void:
	if _furniture_def == null:
		return
	FurnitureLibrary.save_def(_furniture_def)
	# 場上已經放置的同一件家具抓的是各自讀出來的另一份 FurnitureDef,存檔不會自動同步過去(2026-09-23 修正:
	# 光源座標/大小/顏色編輯後存檔,已經放在桌面的那件不會變,就是因為這裡漏了通知)。
	if is_inside_tree():
		for manager: Node in get_tree().get_nodes_in_group("furniture_manager"):
			if manager.has_method("refresh_def"):
				manager.refresh_def(_furniture_id)


func _edit_furn_light(field: String, value: Variant) -> void:
	if _updating or _furniture_def == null or _furn_light_index < 0 or _furn_light_index >= _furniture_def.lights.size():
		return
	var raw: Dictionary = _furniture_def.lights[_furn_light_index].duplicate(true)
	raw[field] = value
	_furniture_def.lights[_furn_light_index] = FurnitureDef.clean_light(raw)
	_save_furniture()
	_push_furniture_lights_to_canvas()


## 目前算不算「單獨調整這一幀」:第 0 幀(或沒有選到動作槽)一律用預設值;其他幀要先勾選「單獨調整此幀」。
func _furn_light_current_scope() -> int:
	if _action == "" or _index <= 0:
		return ScopedProperty.SCOPE_DEFAULT
	return ScopedProperty.SCOPE_FRAME


func _furn_light_frame_editable() -> bool:
	return _action == "" or _index <= 0 or (_furn_light_frame_unlock != null and _furn_light_frame_unlock.button_pressed)


## 半徑/亮度/顏色/是否亮著(熄燈覆蓋)寫進目前的套用範圍。field 跟 FurnitureDef.set_radius() 等函式的
## 第一個參數對應。沒解鎖這一幀(且不是第 0 幀)時忽略。
func _edit_furn_light_scoped(field: String, value: Variant) -> void:
	if _updating or _furniture_def == null or _furn_light_index < 0 or _furn_light_index >= _furniture_def.lights.size() or not _furn_light_frame_editable():
		return
	var raw: Dictionary = _furniture_def.lights[_furn_light_index].duplicate(true)
	var scope := _furn_light_current_scope()
	var frame_count := _model.frame_count(_action) if _action != "" else 0
	match field:
		"radius":
			FurnitureDef.set_radius(raw, scope, _action, _index, frame_count, value)
		"energy":
			FurnitureDef.set_energy(raw, scope, _action, _index, frame_count, value)
		"color":
			FurnitureDef.set_color(raw, scope, _action, _index, frame_count, value)
		"enabled":
			FurnitureDef.set_enabled_override(raw, scope, _action, _index, frame_count, value)
	_furniture_def.lights[_furn_light_index] = FurnitureDef.clean_light(raw)
	_save_furniture()
	_refresh_furniture_lights()


## 「單獨調整此幀」開關:打開只是讓下面的欄位變成可編輯,還沒有值好寫;關掉要清掉這一幀在四個屬性上的覆蓋。
func _on_furn_light_frame_unlock_toggled(on: bool) -> void:
	if _updating or _furniture_def == null or _furn_light_index < 0 or _furn_light_index >= _furniture_def.lights.size():
		return
	if on:
		_furn_light_radius.editable = true
		_furn_light_energy.editable = true
		_furn_light_color.disabled = false
		_furn_light_frame_enabled.disabled = false
		return
	var raw: Dictionary = _furniture_def.lights[_furn_light_index].duplicate(true)
	FurnitureDef.clear_radius_scope(raw, ScopedProperty.SCOPE_FRAME, _action, _index)
	FurnitureDef.clear_energy_scope(raw, ScopedProperty.SCOPE_FRAME, _action, _index)
	FurnitureDef.clear_color_scope(raw, ScopedProperty.SCOPE_FRAME, _action, _index)
	FurnitureDef.clear_enabled_scope(raw, ScopedProperty.SCOPE_FRAME, _action, _index)
	_furniture_def.lights[_furn_light_index] = FurnitureDef.clean_light(raw)
	_save_furniture()
	_refresh_furniture_lights()


## 一盞燈某個動作槽的欄位(mode/start/end)改了:跟 _edit_furn_light 同一套存檔流程,只是欄位巢狀多一層。
func _edit_furn_light_slot(slot_name: String, field: String, value: Variant) -> void:
	if _updating or _furniture_def == null or _furn_light_index < 0 or _furn_light_index >= _furniture_def.lights.size():
		return
	var raw: Dictionary = _furniture_def.lights[_furn_light_index].duplicate(true)
	var slots: Dictionary = (raw.get("slots", {}) as Dictionary).duplicate(true)
	var slot: Dictionary = (slots.get(slot_name, {}) as Dictionary).duplicate(true)
	slot[field] = value
	slots[slot_name] = slot
	raw["slots"] = slots
	_furniture_def.lights[_furn_light_index] = FurnitureDef.clean_light(raw)
	_save_furniture()
	if field == "mode":
		_refresh_furniture_lights()   # 清單那一行的「・停用」標記(全槽都關掉才算)要跟著換
	else:
		_push_furniture_lights_to_canvas()


## 這個動作槽選了「指定幀範圍啟用」才顯示起訖幀輸入框。
func _sync_furn_light_slot_visibility(slot_name: String) -> void:
	var has := _furniture_def != null and _furn_light_index >= 0 and _furn_light_index < _furniture_def.lights.size()
	var mode := "off"
	if has:
		var slots: Dictionary = _furniture_def.lights[_furn_light_index].get("slots", {})
		mode = str((slots.get(slot_name, {}) as Dictionary).get("mode", "off"))
	(_furn_light_slot_frame_row[slot_name] as Control).visible = has and mode == "frames"


## 一個動作槽的模式下拉 + 起訖幀輸入框(見 FurnitureDef.LIGHT_SLOT_NAMES/LIGHT_SLOT_MODES)。
func _build_furn_light_slot_row(right: VBoxContainer, slot_name: String) -> void:
	const SLOT_LABELS := {"normal_0": "平時", "conditional_0": "條件成立時", "interacted_0": "使用中(尚未接上播放)"}
	var mode_option := OptionButton.new()
	mode_option.add_item("不啟用")
	mode_option.add_item("一直啟用")
	mode_option.add_item("指定幀範圍啟用")
	mode_option.item_selected.connect(func(i: int) -> void:
		_edit_furn_light_slot(slot_name, "mode", FurnitureDef.LIGHT_SLOT_MODES[i])
		_sync_furn_light_slot_visibility(slot_name))
	right.add_child(ManagerUi.labeled(tr(str(SLOT_LABELS.get(slot_name, slot_name))), mode_option))
	_furn_light_slot_mode[slot_name] = mode_option
	var frame_row := HBoxContainer.new()
	var start_spin := ManagerUi.spin(1.0, 0, FurnitureDef.LIGHT_FRAME_MAX)
	start_spin.value_changed.connect(func(v: float) -> void: _edit_furn_light_slot(slot_name, "start", int(v)))
	frame_row.add_child(ManagerUi.labeled("從第幾幀", start_spin))
	var end_spin := ManagerUi.spin(1.0, 0, FurnitureDef.LIGHT_FRAME_MAX)
	end_spin.value_changed.connect(func(v: float) -> void: _edit_furn_light_slot(slot_name, "end", int(v)))
	frame_row.add_child(ManagerUi.labeled("到第幾幀", end_spin))
	right.add_child(frame_row)
	_furn_light_slot_start[slot_name] = start_spin
	_furn_light_slot_end[slot_name] = end_spin
	_furn_light_slot_frame_row[slot_name] = frame_row


func _sync_furn_light_shape_visibility() -> void:
	var has := _furniture_def != null and _furn_light_index >= 0 and _furn_light_index < _furniture_def.lights.size()
	_furn_light_angle_row.visible = has and str(_furniture_def.lights[_furn_light_index].get("shape", "radial")) == "fan"


func _on_furn_light_add_pressed() -> void:
	if _furniture_def == null or _furniture_def.lights.size() >= FurnitureDef.MAX_LIGHTS:
		return
	_furniture_def.lights.append(FurnitureDef.default_light())
	_furn_light_index = _furniture_def.lights.size() - 1
	_save_furniture()
	_refresh_furniture_lights()


func _on_furn_light_delete_pressed() -> void:
	if _furniture_def == null or _furn_light_index < 0 or _furn_light_index >= _furniture_def.lights.size():
		return
	_furniture_def.lights.remove_at(_furn_light_index)
	_furn_light_index = mini(_furn_light_index, _furniture_def.lights.size() - 1)
	_save_furniture()
	_refresh_furniture_lights()


## 錨點清單(名稱 + 座標)+ 座標框 + 畫布上的點,一起重整;index 選取哪一個三邊要一致。
func _refresh_furniture_anchors() -> void:
	if _furn_anchor_list == null:
		return
	_furn_anchor_list.clear()
	if _furniture_def != null:
		for anchor: Dictionary in _furniture_def.anchors:
			var label := "坐" if str(anchor.get("type")) == "sit" else "躺"
			_furn_anchor_list.add_item("%s (%d, %d)" % [label, int(anchor.get("x", 0.0)), int(anchor.get("y", 0.0))])
	var has_anchor := _furniture_def != null and _furn_anchor_index >= 0 and _furn_anchor_index < _furniture_def.anchors.size()
	if has_anchor:
		_furn_anchor_list.select(_furn_anchor_index)
	_furn_anchor_delete.disabled = not has_anchor
	_updating = true
	var anchor: Dictionary = _furniture_def.anchors[_furn_anchor_index] if has_anchor else {}
	_furn_anchor_x.value = float(anchor.get("x", 0.0))
	_furn_anchor_y.value = float(anchor.get("y", 0.0))
	_furn_anchor_x.editable = has_anchor
	_furn_anchor_y.editable = has_anchor
	_furn_anchor_action.text = str(anchor.get("action", ""))
	_furn_anchor_action.editable = has_anchor
	_furn_anchor_facing.select(FurnitureDef.ANCHOR_FACINGS.find(str(anchor.get("facing", "both"))))
	_furn_anchor_facing.disabled = not has_anchor
	_updating = false
	if _furn_no_anchor_warning != null:
		_furn_no_anchor_warning.visible = _furniture_def != null and _furniture_def.anchors.is_empty()
	_push_furniture_anchors_to_canvas()


func _on_furn_anchor_add_pressed() -> void:
	if _furniture_def == null or _furn_anchor_type == null:
		return
	var kind := str(_furn_anchor_type.get_item_metadata(_furn_anchor_type.selected))
	_furniture_def.anchors.append({"type": kind, "x": 0.0, "y": 0.0})
	_furn_anchor_index = _furniture_def.anchors.size() - 1
	_save_furniture()
	_refresh_furniture_anchors()


func _on_furn_anchor_delete_pressed() -> void:
	if _furniture_def == null or _furn_anchor_index < 0 or _furn_anchor_index >= _furniture_def.anchors.size():
		return
	_furniture_def.anchors.remove_at(_furn_anchor_index)
	_furn_anchor_index = mini(_furn_anchor_index, _furniture_def.anchors.size() - 1)
	_save_furniture()
	_refresh_furniture_anchors()


## 借畫布的「配件」畫法畫錨點(沒有圖檔,只畫十字與名字,見 PackFrameCanvas._draw_accessories);跟角色的配件系統完全無關,只是共用畫布元件。
func _furniture_accessory_previews() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _furniture_def == null:
		return result
	for anchor: Dictionary in _furniture_def.anchors:
		result.append({"x": float(anchor.get("x", 0.0)), "y": float(anchor.get("y", 0.0)), "name": "坐" if str(anchor.get("type")) == "sit" else "躺", "texture": null, "scale": 1.0, "origin": Vector2.ZERO, "hidden": false, "layer": "front"})
	return result


func _push_furniture_anchors_to_canvas() -> void:
	if _canvas != null:
		_canvas.set_accessories(_furniture_accessory_previews(), _furn_anchor_index)


## 借畫布的「光源」畫法畫家具的每一盞燈:"enabled" 換成「現在(真實時間)是不是真的會亮」而不是原始資料的開關本身,
## 這樣編輯器裡看到的明暗才會跟桌面上實際看到的一致(2026-09-23 修正:原本編輯器不管觸發條件,只要那盞燈的「啟用」
## 打勾畫布就一直亮著,使用者反應「檯燈明明現在沒觸發,編輯器卻一直亮著,是bug吧」)。
## 2026-09-27:改成依動作槽分開設定後,這裡只能取「一直啟用」這個槽目前是不是真的會亮的靜態畫面(這個預覽不會
## 真的逐幀播放家具動畫,沒辦法準確預覽「指定幀範圍啟用」什麼時候亮,那種模式在這個小預覽裡先當作不亮處理)。
func _furniture_lights_preview() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _furniture_def == null:
		return result
	var condition: Dictionary = _furniture_def.condition
	var currently_conditional := str(condition.get("type", "always")) != "always" and FurnitureCondition.evaluate(condition, AppSettings.minute_of_day_now(), [])
	var slot_name := "conditional_0" if currently_conditional else "normal_0"
	for i in _furniture_def.lights.size():
		var light: Dictionary = FurnitureDef.clean_light(_furniture_def.lights[i])
		var copy := light.duplicate(true)
		copy["name"] = tr("光源 %d") % (i + 1)
		var slots: Dictionary = light["slots"]
		copy["enabled"] = str((slots.get(slot_name, {}) as Dictionary).get("mode", "off")) == "always"
		result.append(copy)
	return result


func _push_furniture_lights_to_canvas() -> void:
	if _canvas != null:
		_canvas.set_lights(_furniture_lights_preview(), _furn_light_index)


## 光源清單(名稱 + 座標 + 開關標記)+ 表單 + 畫布上的點,一起重整;index 選取哪一個三邊要一致(跟坐/躺錨點同一套邏輯)。
func _refresh_furniture_lights() -> void:
	if _furn_light_list == null:
		return
	# 跟角色的多光源清單同一個習慣(_refresh_lights):沒選任何一盞、清單又不是空的,預設選第一盞,不用逼使用者
	# 先點一下列表才看得到/改得動表單欄位(常見情形是只有一盞,選都不用選最方便)。
	if _furn_light_index < 0 and _furniture_def != null and not _furniture_def.lights.is_empty():
		_furn_light_index = 0
	_furn_light_list.clear()
	if _furniture_def != null:
		for i in _furniture_def.lights.size():
			var l := FurnitureDef.clean_light(_furniture_def.lights[i])
			var all_off := true
			for slot_name: String in FurnitureDef.LIGHT_SLOT_NAMES:
				if str((l["slots"] as Dictionary).get(slot_name, {}).get("mode", "off")) != "off":
					all_off = false
					break
			_furn_light_list.add_item(tr("光源 %d (%d, %d)%s") % [i + 1, int(l.get("x", 0.0)), int(l.get("y", 0.0)), tr("・停用") if all_off else ""])
	var has := _furniture_def != null and _furn_light_index >= 0 and _furn_light_index < _furniture_def.lights.size()
	if has:
		_furn_light_list.select(_furn_light_index)
	_furn_light_delete.disabled = not has
	_furn_light_add.disabled = _furniture_def == null or _furniture_def.lights.size() >= FurnitureDef.MAX_LIGHTS
	var light: Dictionary = FurnitureDef.clean_light(_furniture_def.lights[_furn_light_index]) if has else FurnitureDef.default_light()
	_updating = true
	var slots: Dictionary = light["slots"]
	for slot_name: String in FurnitureDef.LIGHT_SLOT_NAMES:
		var slot: Dictionary = slots.get(slot_name, FurnitureDef.default_light_slot())
		(_furn_light_slot_mode[slot_name] as OptionButton).select(maxi(FurnitureDef.LIGHT_SLOT_MODES.find(str(slot.get("mode", "off"))), 0))
		(_furn_light_slot_start[slot_name] as SpinBox).value = float(slot.get("start", 0))
		(_furn_light_slot_end[slot_name] as SpinBox).value = float(slot.get("end", 0))
		(_furn_light_slot_mode[slot_name] as OptionButton).disabled = not has
		(_furn_light_slot_start[slot_name] as SpinBox).editable = has
		(_furn_light_slot_end[slot_name] as SpinBox).editable = has
	_furn_light_x.value = float(light["x"])
	_furn_light_y.value = float(light["y"])
	var is_base_frame := _action == "" or _index <= 0
	_furn_light_frame_unlock.visible = has and not is_base_frame
	if not has or is_base_frame:
		_furn_light_frame_unlock.button_pressed = false
	elif has:
		_furn_light_frame_unlock.button_pressed = (
				FurnitureDef.radius_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME
				or FurnitureDef.energy_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME
				or FurnitureDef.color_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME
				or FurnitureDef.enabled_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME)
	var frame_editable := has and (is_base_frame or _furn_light_frame_unlock.button_pressed)
	_furn_light_radius.value = FurnitureDef.radius_of(light, _action, _index)
	_furn_light_energy.value = FurnitureDef.energy_of(light, _action, _index)
	_furn_light_color.color = Color(FurnitureDef.color_of(light, _action, _index))
	var enabled_override: Variant = FurnitureDef.enabled_override(light, _action, _index)
	_furn_light_frame_enabled.button_pressed = enabled_override if enabled_override is bool else true
	for i in _furn_light_shape.item_count:
		if str(_furn_light_shape.get_item_metadata(i)) == str(light["shape"]):
			_furn_light_shape.select(i)
	_furn_light_angle.value = float(light["angle"])
	_furn_light_spread.value = float(light["spread"])
	for spin: SpinBox in [_furn_light_x, _furn_light_y]:
		spin.editable = has
	_furn_light_radius.editable = frame_editable
	_furn_light_energy.editable = frame_editable
	_furn_light_color.disabled = not frame_editable
	_furn_light_frame_enabled.disabled = not frame_editable
	_furn_light_shape.disabled = not has
	_updating = false
	for slot_name: String in FurnitureDef.LIGHT_SLOT_NAMES:
		_sync_furn_light_slot_visibility(slot_name)
	_sync_furn_light_shape_visibility()
	_push_furniture_lights_to_canvas()


## 開/切到家具編輯時重整整個家具面板(表單欄位 + 畫布上的錨點與光點)。
func _refresh_furniture_editor() -> void:
	if _furniture_def == null or _furn_light_slot_mode.is_empty():
		return
	_updating = true
	_furn_above_light.button_pressed = _furniture_def.above_light
	_furn_render_above_ui.button_pressed = _furniture_def.render_above_ui
	_updating = false
	_furn_light_index = mini(_furn_light_index, _furniture_def.lights.size() - 1)
	_refresh_furniture_lights()
	_furn_anchor_index = mini(_furn_anchor_index, _furniture_def.anchors.size() - 1)
	_refresh_furniture_anchors()


## 是不是在編輯「特殊項目」(道具或家具)的進階貼圖,而不是一般角色的素材包。這種模式下動作清單是固定的幾個狀態槽,不是系統動作。
func _in_item_mode() -> bool:
	return _prop_id != "" or _furniture_id != ""


## 目前特殊項目的狀態槽清單與白話標籤(角色模式回空的)。
func _item_states() -> Array[String]:
	if _prop_id != "":
		return PropLibrary.SPRITE_STATES
	if _furniture_id != "":
		return FurnitureLibrary.SPRITE_STATES
	return []


func _item_state_label(state: String) -> String:
	if _prop_id != "":
		return str(PROP_STATE_LABELS.get(state, state))
	return str(FURNITURE_STATE_LABELS.get(state, state))


## 切換道具/家具編輯 / 角色編輯的介面(收起或顯示角色專用的控制項、道具狀態區/家具狀態區)。
func _apply_prop_mode() -> void:
	var item_mode := _in_item_mode()
	for control in _toolbar_pack_controls:
		control.visible = not item_mode
	_update_tab_visibility()
	_save_as_button.visible = not item_mode
	_export_frames_button.visible = not item_mode
	_clean_button.visible = not item_mode
	_add_action_button.visible = not item_mode
	_prop_panel.visible = _prop_id != ""
	_furniture_panel.visible = _furniture_id != ""
	_char_light_panel.visible = not item_mode
	_char_layer_panel.visible = not item_mode
	_furn_light_tab_panel.visible = _furniture_id != ""
	_furn_anchor_tab_panel.visible = _furniture_id != ""
	_sync_action_source_widgets()
	if _prop_id != "" and _prop_def != null:
		_updating = true
		for state: String in ["used", "drag"]:
			(_prop_mode_options[state] as OptionButton).select(1 if (_prop_def.used_mode if state == "used" else _prop_def.drag_mode) == "loop" else 0)
			(_prop_count_spins[state] as SpinBox).value = _prop_def.used_count if state == "used" else _prop_def.drag_count
		_updating = false
	if _furniture_id != "":
		_refresh_furniture_editor()


## 開啟道具的進階貼圖(sprite/ 資料夾,不存在就建立)。成功回空字串。有未存的變更時由呼叫端先確認(見 guard_unsaved)。
func open_prop(prop_id: String) -> String:
	var def := PropLibrary.load_def(prop_id)
	if def == null:
		return "找不到這個道具"
	var folder := ProjectSettings.globalize_path(PropLibrary.sprite_folder(prop_id))
	DirAccess.make_dir_recursive_absolute(folder)
	var error := open_folder(folder)
	if error != "":
		return error
	_prop_id = prop_id
	_prop_def = def
	_extra_slots.clear()
	_action = ""
	_slot = "default"
	_reload_lists()
	_status.text = tr("正在編輯道具「%s」的進階貼圖:選左邊的狀態(預設 / 被使用 / 拖曳中),再匯入圖片或精靈圖。") % def.display_name
	_refresh_all()
	return ""


## 開啟家具的進階貼圖(sprite/ 資料夾,不存在就建立)。成功回空字串。有未存的變更時由呼叫端先確認(見 guard_unsaved)。
func open_furniture(furniture_id: String) -> String:
	var def := FurnitureLibrary.load_def(furniture_id)
	if def == null:
		return "找不到這件家具"
	var folder := ProjectSettings.globalize_path(FurnitureLibrary.sprite_folder(furniture_id))
	DirAccess.make_dir_recursive_absolute(folder)
	var error := open_folder(folder)
	if error != "":
		return error
	_furniture_id = furniture_id
	_furniture_def = def
	_extra_slots.clear()
	_action = ""
	_slot = "normal"
	_reload_lists()
	_status.text = tr("正在編輯家具「%s」的進階貼圖:選左邊的狀態(平時 / 條件成立時 / 被使用時),再匯入圖片或精靈圖。") % def.display_name
	_refresh_all()
	return ""


## 動作清單:每個系統動作(idle、walk…)一個槽(沒素材顯示「空」,素材包裡叫別的名字的顯示「代號 ← 名稱」),再列其他動作與使用者新增的空的自訂動作。
func _rebuild_action_list() -> void:
	_action_list.clear()
	_action_rows.clear()
	if _in_item_mode():
		for state: String in _item_states():
			var count := _model.frame_count(state)
			if count > 0:
				_action_list.add_item("%s(%d)" % [_item_state_label(state), count])
				_action_rows.append({"action": state, "slot": state})
			else:
				_action_list.add_item(tr("%s(空)") % _item_state_label(state))
				_action_list.set_item_custom_fg_color(_action_list.item_count - 1, ManagerUi.muted_color(_action_list))
				_action_rows.append({"action": "", "slot": state})
		return
	var sources := _model.slot_sources()
	var used: Dictionary = {}
	for slot: String in SpritePackLoader.ALIASES:
		var source := str(sources.get(slot, ""))
		if source != "":
			used[source] = true
			var text := "%s(%d)" % [slot, _model.frame_count(source)] if source == slot else "%s ← %s(%d)" % [slot, source, _model.frame_count(source)]
			_action_list.add_item(text)
			_action_rows.append({"action": source, "slot": slot})
		else:
			_action_list.add_item(tr("%s(空)") % slot)
			_action_list.set_item_custom_fg_color(_action_list.item_count - 1, ManagerUi.muted_color(_action_list))
			_action_rows.append({"action": "", "slot": slot})
	var others: Array[String] = []
	for action_name in _model.action_names():
		if not used.has(action_name):
			others.append(action_name)
	var still_empty: Array[String] = []
	for extra in _extra_slots:
		if not _model.action_names().has(extra):
			still_empty.append(extra)
	_extra_slots = still_empty
	if not others.is_empty() or not _extra_slots.is_empty():
		_action_list.add_item("── 自訂動作 ──")
		_action_list.set_item_disabled(_action_list.item_count - 1, true)
		_action_rows.append({"action": "", "slot": "", "header": true})
		for action_name in others:
			_action_list.add_item("%s(%d)" % [action_name, _model.frame_count(action_name)])
			_action_rows.append({"action": action_name, "slot": action_name})
		for extra in _extra_slots:
			_action_list.add_item(tr("%s(空)") % extra)
			_action_list.set_item_custom_fg_color(_action_list.item_count - 1, ManagerUi.muted_color(_action_list))
			_action_rows.append({"action": "", "slot": extra})


## 選中清單裡對應「目前動作/槽」的那一列。
func _select_current_row() -> void:
	for i in _action_rows.size():
		var row: Dictionary = _action_rows[i]
		if bool(row.get("header", false)):
			continue
		if (_action != "" and str(row["action"]) == _action and (_slot == "" or str(row["slot"]) == _slot)) or (_action == "" and _slot != "" and str(row["action"]) == "" and str(row["slot"]) == _slot):
			_action_list.select(i)
			return
	# 選的槽不在清單裡了(例如動作名稱變了):退而求其次,找第一個同動作的列。
	for i in _action_rows.size():
		if _action != "" and str(_action_rows[i]["action"]) == _action:
			_action_list.select(i)
			return


func _on_action_row_selected(row_index: int) -> void:
	var row: Dictionary = _action_rows[row_index]
	if bool(row.get("header", false)):
		return
	_slot = str(row["slot"])
	if str(row["action"]) != "":
		_select_action(str(row["action"]))
	else:
		_select_empty_slot(_slot)


## 選到還沒有素材的槽:幀清單清空,畫布顯示提示,匯入時預設放進這個動作。
func _select_empty_slot(slot: String) -> void:
	_action = ""
	_slot = slot
	_selected = []
	_index = 0
	_frame_list.clear()
	_refresh_all()
	_sync_action_source_widgets()
	_status.text = tr("「%s」這個動作還沒有素材:用「匯入圖片…」或「匯入精靈圖…」放進來。") % slot


## 新增自訂動作槽。名字已經有(素材包裡的動作或系統動作槽)就直接選它。
func _on_add_action_pressed() -> void:
	if not _model.has_pack():
		return
	_ask_action_name(func(chosen: String) -> void: add_custom_action(chosen))


## 加一個自訂動作槽並選它;回傳空字串或原因。
func add_custom_action(action_name: String) -> String:
	var clean := SpritePackLoader.clean_action_name(action_name)
	if clean == "":
		return "動作名稱不能是空的(只能用英數、底線、連字號)"
	if not _model.action_names().has(clean) and not SpritePackLoader.ALIASES.has(clean) and not _extra_slots.has(clean):
		_extra_slots.append(clean)
	_action = clean if _model.action_names().has(clean) else ""
	_slot = clean
	_reload_lists()
	if _action == "":
		_select_empty_slot(clean)
	_select_current_row()
	return ""


func _ask_action_name(on_chosen: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	# 不設 always_on_top,見 _ask_name() 的說明(跟置頂衝突,會把視窗卡死)。
	dialog.title = "新增自訂動作"
	dialog.ok_button_text = "新增"
	dialog.cancel_button_text = "取消"
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "動作名稱(英數、底線、連字號;會出現在網頁編輯器的動作下拉選單):"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 380.0
	box.add_child(label)
	var edit := ManagerUi.line_edit("例如 attack")
	edit.max_length = 40
	box.add_child(edit)
	dialog.add_child(box)
	dialog.get_ok_button().disabled = true
	edit.text_changed.connect(func(text: String) -> void: dialog.get_ok_button().disabled = SpritePackLoader.clean_action_name(text) == "")
	dialog.confirmed.connect(func() -> void: on_chosen.call(edit.text))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(440, 180))
		edit.grab_focus()


## 依模型目前的動作重建左邊兩個清單,盡量保留目前選的動作與幀(select_indices 非空就改選這些幀)。
func _reload_lists(select_indices: Array[int] = []) -> void:
	_rebuild_action_list()
	var names := _model.action_names()
	if names.is_empty() or (_action == "" and _slot != "" and not names.has(_slot)):
		# 沒有任何素材,或停在一個空的槽上:幀清單是空的。
		_action = ""
		_selected = []
		_frame_list.clear()
		_select_current_row()
		_refresh_frame()
		_sync_action_source_widgets()
		return
	var keep := _action if names.has(_action) else (_slot if names.has(_slot) else names[0])
	_select_action(keep, _index if keep == _action else 0, select_indices)


func _select_action(action: String, preferred_index := 0, select_indices: Array[int] = []) -> void:
	_action = action
	if _slot == "" or not _row_matches(_slot, action):
		_slot = action
	_select_current_row()
	_frame_list.clear()
	for i in _model.frame_count(action):
		var frame_data := _model.frame(action, i)
		var icon: Texture2D = frame_data.get("texture")
		_frame_list.add_item(str(i), icon)
	_fps_spin.set_value_no_signal(_model.fps_of(action))
	_play_timer.wait_time = 1.0 / _fps_spin.value
	var count := _model.frame_count(action)
	_refresh_loop_widgets()
	var wanted: Array[int] = []
	for i in select_indices:
		if i >= 0 and i < count:
			wanted.append(i)
	if wanted.is_empty():
		wanted.append(clampi(preferred_index, 0, maxi(count - 1, 0)))
	_selected = []
	_index = 0
	if count > 0:
		_selected = wanted
		_index = wanted[wanted.size() - 1]
	for i in _selected:
		_frame_list.select(i, false)
	_refresh_frame()
	_sync_action_source_widgets()


## 槽 slot 目前對應的就是動作 action(或槽名就是動作名)。
func _row_matches(slot: String, action: String) -> bool:
	for row: Dictionary in _action_rows:
		if str(row["slot"]) == slot and str(row["action"]) == action:
			return true
	return slot == action


## 幀清單的選取變了(可複選):目前顯示在畫布上的是最後點的那一幀。
func _on_frame_multi_selected(index: int, selected: bool) -> void:
	_selected = []
	for i in _frame_list.get_selected_items():
		_selected.append(i)
	if selected:
		_index = index
	elif not _selected.is_empty():
		_index = _selected[_selected.size() - 1]
	_refresh_frame()
	_update_frame_buttons()


func _select_frame(index: int) -> void:
	_index = clampi(index, 0, maxi(_model.frame_count(_action) - 1, 0))
	_selected = []
	if _model.frame_count(_action) > 0:
		_selected.append(_index)
	_refresh_frame()


## 沒有素材包時停用需要它的按鈕、顯示提示。
func _refresh_all() -> void:
	var has_pack := _model.has_pack()
	_import_images_button.disabled = not has_pack
	_import_sheet_button.disabled = not has_pack
	_replace_sheet_button.disabled = not has_pack
	_save_as_button.disabled = not has_pack
	_export_frames_button.disabled = not has_pack
	_clean_button.disabled = not has_pack
	_save_button.disabled = not has_pack
	_add_action_button.disabled = not has_pack
	_pack_label.text = _model.root if has_pack else "(還沒有開啟素材包)"
	_pack_label.tooltip_text = _pack_label.text
	if not has_pack:
		_canvas.hint_text = "還沒有開啟素材包。\n用上方的「從資料夾匯入…」開啟現有的,\n或「新建資料夾…」從空白開始,再用「匯入圖片…」「匯入精靈圖…」放圖進來。"
	elif _action == "" and _slot != "":
		_canvas.hint_text = tr("「%s」這個動作還沒有素材。\n用「匯入圖片…」或「匯入精靈圖…」放進來,\n匯入時動作名稱會預設填「%s」。") % [_slot, _slot]
	elif _model.action_names().is_empty():
		_canvas.hint_text = "這個素材包還沒有任何動作。\n在左邊選一個動作槽,再用「匯入圖片…」或「匯入精靈圖…」放進第一個動作。"
	else:
		_canvas.hint_text = "這一幀讀不出圖。"
	_refresh_frame_labels_only()
	_refresh_frame()
	_update_frame_buttons()
	_refresh_lights()
	_refresh_loop_widgets()
	_sync_action_source_widgets()
	_apply_prop_mode()


## 把目前這一幀的資料(圖、軸心、圖片偏移、殘影、判定框)送到畫布與數值框。
func _refresh_frame() -> void:
	_refresh_hitbox()
	_refresh_anchor_widgets()
	if _furniture_id != "":
		_refresh_furniture_lights()
	else:
		_refresh_light_widgets()
	var frame_data := _model.frame(_action, _index) if _action != "" and _model.frame_count(_action) > 0 else {}
	if frame_data.is_empty():
		_canvas.set_frame(null, Vector2i.ZERO, Vector2.ZERO, Vector2.ZERO)
		_canvas.set_ghost(null, Vector2.ZERO)
		_set_spins(Vector2.ZERO, Vector2.ZERO)
		_info.text = ""
		_fx_label.text = ""
		_update_fx_buttons()
		return
	var pivot := _model.pivot(_action, _index)
	var offset := _model.offset(_action, _index)
	_canvas.set_frame(frame_data["texture"], frame_data["size"], pivot, offset)
	var count := _model.frame_count(_action)
	if count > 1:
		var previous := (_index - 1 + count) % count
		var previous_data := _model.frame(_action, previous)
		if not previous_data.is_empty():
			_canvas.set_ghost(previous_data["texture"], _model.pivot(_action, previous) - _model.offset(_action, previous))
		else:
			_canvas.set_ghost(null, Vector2.ZERO)
	else:
		_canvas.set_ghost(null, Vector2.ZERO)
	_set_spins(pivot, offset)
	var size: Vector2i = frame_data["size"]
	var frame_name := _model.frame_path(_action, _index)
	frame_name = tr("切片 %d(%s)") % [_index, str(SpritePackLoader.parse_virtual(frame_name)["file"]).get_file()] if SpritePackLoader.is_virtual(frame_name) else frame_name.get_file()
	_info.text = tr("%s  第 %d / %d 幀  ·  %d×%d  ·  自動軸心 (%d, %d)%s\n預設模式左鍵拖曳平移畫面、滾輪縮放;切到「移動軸心 / 移動圖片 / 判定框」才會改資料(方向鍵微調 1 像素,Shift = 10;移動軸心時 Shift = 只改腳底線、Ctrl = 只改中心點)。") % [
			frame_name, _index + 1, count, size.x, size.y,
			int(frame_data["auto_pivot"].x), int(frame_data["auto_pivot"].y), "  ·  已手動設定" if _model.has_explicit(_action, _index) else ""]
	var fx := _model.fx_text(_action, _index)
	_fx_label.text = tr("這一幀的圖片處理:%s") % fx if fx != "" else "這一幀沒有圖片處理(原圖)"
	_update_fx_buttons()
	_update_crop_limits(size)


func _set_spins(pivot: Vector2, offset: Vector2) -> void:
	_updating = true
	_pivot_x.value = pivot.x
	_pivot_y.value = pivot.y
	_offset_x.value = offset.x
	_offset_y.value = offset.y
	_updating = false


# --- 判定框 ---

## 判定框在畫布上的範圍:寬 w、高 h、偏移 (ox, oy) → 左上角 (−w/2 + ox, −h + oy)(錨點是腳底中心,和 Pet._hit_rect 一致)。
static func hitbox_rect(box_size: Vector2, box_offset: Vector2) -> Rect2:
	return Rect2(-box_size.x * 0.5 + box_offset.x, -box_size.y + box_offset.y, box_size.x, box_size.y)


func _refresh_hitbox() -> void:
	if not _model.has_pack() or _model.action_names().is_empty():
		_canvas.clear_hitbox_rect()
		_hitbox_state.text = ""
		return
	var box := _model.hitbox()
	_canvas.set_hitbox_rect(hitbox_rect(box["size"], box["offset"]), bool(box["explicit"]))
	_updating = true
	_hitbox_w.value = (box["size"] as Vector2).x
	_hitbox_h.value = (box["size"] as Vector2).y
	_hitbox_x.value = (box["offset"] as Vector2).x
	_hitbox_y.value = (box["offset"] as Vector2).y
	_updating = false
	_hitbox_state.text = "已設定" if box["explicit"] else "目前是自動(待機幀本體大小),改任何數字就會變成手動設定"


func _on_hitbox_spin_changed() -> void:
	if _updating or not _model.has_pack():
		return
	_model.checkpoint("spin_hitbox")
	_model.set_hitbox(Vector2(_hitbox_w.value, _hitbox_h.value), Vector2(_hitbox_x.value, _hitbox_y.value))
	_refresh_hitbox()
	_after_edit("")


## 畫布上拖曳判定框:範圍 → 寬高與偏移(偏移 x = 框的水平中心,偏移 y = 框的底邊)。
func _on_canvas_hitbox_edited(rect: Rect2) -> void:
	_model.set_hitbox(rect.size, Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y))
	var box := _model.hitbox()
	_updating = true
	_hitbox_w.value = (box["size"] as Vector2).x
	_hitbox_h.value = (box["size"] as Vector2).y
	_hitbox_x.value = (box["offset"] as Vector2).x
	_hitbox_y.value = (box["offset"] as Vector2).y
	_updating = false
	_hitbox_state.text = "已設定"
	_after_edit("")


# --- 光源(發光效果) ---

func _build_light_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("光源(發光效果)", tr("角色身上的發光光暈(沒有陰影,不需要任何圖檔)。每盞光有一個錨點(相對腳底線中心的位置,縮放前像素)、半徑、亮度、顏色,可以指定只在某個動作播放時亮。上面「模式」選「調整光源錨點」後可以直接在畫布上拖曳圓點(或用方向鍵)。全局設定可以整個關掉光源(和效能有關)。最多 %d 盞。") % PackLights.MAX_LIGHTS))
	_light_list = ItemList.new()
	_light_list.custom_minimum_size.y = 84.0
	_light_list.item_selected.connect(_on_light_row_selected)
	right.add_child(_light_list)
	var buttons := HBoxContainer.new()
	_light_add = ManagerUi.button("＋ 新增光源")
	_light_add.pressed.connect(add_light)
	buttons.add_child(_light_add)
	_light_delete = ManagerUi.button("刪除這盞")
	_light_delete.pressed.connect(delete_light)
	buttons.add_child(_light_delete)
	right.add_child(buttons)
	_light_name = ManagerUi.line_edit("光源名稱")
	_light_name.max_length = 24
	_light_name.text_changed.connect(func(text: String) -> void: _edit_light("name", text.strip_edges(), "light_name"))
	right.add_child(ManagerUi.labeled("名稱", _light_name))
	_light_x = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_light_y = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_light_x.value_changed.connect(func(_v: float) -> void: _edit_light_position(Vector2(_light_x.value, _light_y.value)))
	_light_y.value_changed.connect(func(_v: float) -> void: _edit_light_position(Vector2(_light_x.value, _light_y.value)))
	_light_scope_label = Label.new()
	_light_scope_label.theme_type_variation = AppSettings.MUTED_LABEL
	_light_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_light_scope_label)
	_light_frame_unlock = CheckBox.new()
	_light_frame_unlock.text = "單獨調整此幀"
	_light_frame_unlock.tooltip_text = "第 0 幀(或還沒解鎖的幀)的位置/半徑/亮度/顏色/是否亮著都跟著這盞光的預設值走。勾選這裡才能單獨改目前這一幀,不影響其他幀;取消勾選會清掉這一幀的所有覆蓋,退回預設值(即使預設值是熄燈,解鎖後這一幀還是可以單獨打開)。"
	_light_frame_unlock.toggled.connect(_on_light_frame_unlock_toggled)
	right.add_child(_light_frame_unlock)
	right.add_child(ManagerUi.labeled("錨點 X(右為正)", _light_x))
	right.add_child(ManagerUi.labeled("錨點 Y(下為正)", _light_y))
	_light_radius = ManagerUi.spin(1.0, PackLights.RADIUS_RANGE.x, PackLights.RADIUS_RANGE.y)
	_light_radius.value_changed.connect(func(value: float) -> void: _edit_light_scoped("radius", value, "light_radius"))
	right.add_child(ManagerUi.labeled("半徑", _light_radius))
	_light_energy = ManagerUi.spin(0.05, PackLights.ENERGY_RANGE.x, PackLights.ENERGY_RANGE.y)
	_light_energy.value_changed.connect(func(value: float) -> void: _edit_light_scoped("energy", value, "light_energy"))
	right.add_child(ManagerUi.labeled("亮度", _light_energy))
	_light_color = ColorPickerButton.new()
	_light_color.edit_alpha = false
	_light_color.custom_minimum_size = Vector2(120, 28)
	_light_color.color_changed.connect(func(color: Color) -> void: _edit_light_scoped("color", "#" + color.to_html(false), "light_color"))
	right.add_child(ManagerUi.labeled("顏色", _light_color))
	_light_behind_body = CheckBox.new()
	_light_behind_body.text = "疊在角色後面"
	_light_behind_body.tooltip_text = "預設光暈疊在角色前面(蓋住身體);勾選這裡改成疊在角色與配件的「後面」圖層之後(像從角色身後透出來的光)。整盞光的設定,不分幀。"
	_light_behind_body.toggled.connect(func(on: bool) -> void: _edit_light("layer", "back" if on else "front", "light_layer"))
	right.add_child(_light_behind_body)
	_light_action = OptionButton.new()
	_light_action.item_selected.connect(func(index: int) -> void: _edit_light("action", "" if index == 0 else _light_action.get_item_text(index), "light_action"))
	right.add_child(ManagerUi.labeled("只在這個動作亮", _light_action))
	# 條件光源 ID(2026-09-30 使用者要求):平時照常設位置/半徑/顏色,填了 ID 之後這盞光預設不亮,要積木用
	# 同一個 ID「啟用/觸發」過才會亮(啟用這盞光的總開關還是要開著,ID 是疊加的額外門檻,不是取代)。
	right.add_child(ManagerUi.hint_row("條件光源", "填一個 ID 之後,這盞光會多一道「要積木打開才會亮」的門檻(網頁積木編輯器的「條件光源」積木,填同一個 ID 就能開關它)。留空 = 一般光源,跟以前一樣照左邊的設定直接亮。只有這隻桌寵自己的積木能開關自己的 ID。"))
	var cond_row := HBoxContainer.new()
	_light_cond_id = ManagerUi.line_edit("留空 = 一般光源")
	_light_cond_id.max_length = 32
	_light_cond_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_light_cond_id.text_changed.connect(func(text: String) -> void: _edit_light("cond_id", text.strip_edges(), "light_cond_id"))
	cond_row.add_child(_light_cond_id)
	_light_cond_copy = ManagerUi.button("複製 ID")
	_light_cond_copy.tooltip_text = "把目前的 ID 複製到剪貼簿,貼到網頁積木編輯器的「條件光源」積木裡。"
	_light_cond_copy.pressed.connect(func() -> void:
		if _light_cond_id.text.strip_edges() != "":
			DisplayServer.clipboard_set(_light_cond_id.text.strip_edges())
			_status.text = tr("已複製條件光源 ID:%s") % _light_cond_id.text.strip_edges())
	cond_row.add_child(_light_cond_copy)
	right.add_child(ManagerUi.labeled("ID", cond_row))
	_light_enabled = CheckBox.new()
	_light_enabled.text = "啟用這盞光"
	_light_enabled.tooltip_text = "整盞光的總開關;關掉之後,不管套用範圍或分幀設定都不會亮。要「這個動作大部分時間亮、只有某幾幀暗掉」,總開關留著開,改用上面「套用範圍」選這一幀,把下面的「亮著」關掉。"
	_light_enabled.toggled.connect(func(on: bool) -> void: _edit_light("enabled", on, "light_enabled"))
	right.add_child(_light_enabled)
	_light_frame_enabled = CheckBox.new()
	_light_frame_enabled.text = "亮著(在目前套用範圍那一層)"
	_light_frame_enabled.tooltip_text = "在上面「套用範圍」選的那一層,這盞光要不要亮。用來做「指定幀熄燈」:套用範圍選這一幀,關掉這裡。"
	_light_frame_enabled.toggled.connect(func(on: bool) -> void: _edit_light_scoped("enabled", on, "light_frame_enabled"))
	right.add_child(_light_frame_enabled)


## 配件:角色身上的裝飾、手勢、眨眼與說話的差分圖(overlays.json)。每個配件有一到多張圖(多張依播放速度循環)、一個錨點(相對腳底軸心、縮放前像素,右與下為正)、
## 圖層(本體上面 / 後面 / 最上層)、縮放倍率、圖上哪一點放在錨點,以及在哪些動作顯示(* = 全部)。上面「模式」選「調整配件位置」可以直接在畫布上拖曳(或方向鍵微調)錨點。
## 桌寵右鍵選單的「變更配件」會列出種類是「配件」的部件,可以個別開關(眨眼與說話差分不能關)。
func _build_accessory_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("選取的圖層設定", tr("選取的圖層(配件)的全部設定:一到多張圖(多張會循環)、錨點(相對腳底軸心、縮放前像素)、圖層、縮放、在哪些動作顯示。種類「配件」會出現在桌寵右鍵選單的「變更配件」(可以個別開關);「眨眼」「說話」是差分:眨眼隨機短暫出現、說話在打字機說話時顯示。上面「模式」選「調整配件位置」可以直接在畫布上拖曳錨點。存檔會寫進素材包的 overlays.json。最多 %d 個。") % PetOverlays.MAX_PARTS))
	_acc_list = ItemList.new()
	_acc_list.custom_minimum_size.y = 84.0
	_acc_list.visible = false   # 圖層頁上面的圖層清單已經是同一份資料
	_acc_list.item_selected.connect(func(index: int) -> void:
		_acc_index = index
		_layer_body_focus = false
		_refresh_accessories())
	right.add_child(_acc_list)
	var buttons := HBoxContainer.new()
	_acc_add = ManagerUi.button("＋ 新增配件…")
	_acc_add.tooltip_text = "選一張或多張圖片(多張會循環播放)做成一個新配件,放在角色頭部上方。"
	_acc_add.pressed.connect(func() -> void:
		FloatingWindow.native_file_dialog("選擇配件圖片(可多選)", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]),
				func(paths: PackedStringArray) -> void: add_accessory(Array(paths)), get_window_id()))
	buttons.add_child(_acc_add)
	_acc_delete = ManagerUi.button("刪除這個")
	_acc_delete.pressed.connect(delete_accessory)
	buttons.add_child(_acc_delete)
	buttons.visible = false   # 新增 / 刪除在上面「圖層」清單旁邊,這裡不重複顯示
	right.add_child(buttons)
	_acc_name = ManagerUi.line_edit("配件名稱(右鍵選單「變更配件」顯示的名字)")
	_acc_name.max_length = 40
	_acc_name.text_changed.connect(func(text: String) -> void: _edit_accessory("name", text.strip_edges(), "acc_name"))
	right.add_child(ManagerUi.labeled("名稱", _acc_name))
	_acc_role = OptionButton.new()
	for label in ["配件(一直顯示,可在右鍵選單開關)", "眨眼(隨機短暫出現)", "說話(說話時顯示)"]:
		_acc_role.add_item(label)
	_acc_role.item_selected.connect(func(index: int) -> void: _edit_accessory("role", ACC_ROLES[index], "acc_role"))
	right.add_child(ManagerUi.labeled("種類", _acc_role))
	_acc_layer = OptionButton.new()
	for label in ["本體上面", "本體後面", "最上層", "光源之上"]:
		_acc_layer.add_item(label)
	_acc_layer.item_selected.connect(func(index: int) -> void: _edit_accessory("layer", ACC_LAYERS[index], "acc_layer"))
	right.add_child(ManagerUi.labeled("圖層", _acc_layer))
	_acc_x = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_acc_y = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_acc_x.value_changed.connect(func(_v: float) -> void: _edit_anchor(Vector2(_acc_x.value, _acc_y.value)))
	_acc_y.value_changed.connect(func(_v: float) -> void: _edit_anchor(Vector2(_acc_x.value, _acc_y.value)))
	_acc_scope = OptionButton.new()
	for label in ["整個配件(預設位置)", "只有目前這個動作", "只有目前這一幀(跟著動畫每一幀)"]:
		_acc_scope.add_item(label)
	_acc_scope.tooltip_text = "拖曳畫布或改下面座標時,寫進哪一層:整個配件共用一個位置;或只改目前這個動作(例如舉手動作時帽子要換位置);或只改目前這一幀(動畫每一幀配件位置不同)。執行時優先順序:這一幀 > 這個動作 > 整個配件。"
	_acc_scope.item_selected.connect(func(_i: int) -> void: _refresh_anchor_widgets())
	right.add_child(ManagerUi.labeled("位置套用範圍", _acc_scope))
	_acc_scope_label = Label.new()
	_acc_scope_label.theme_type_variation = AppSettings.MUTED_LABEL
	_acc_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_acc_scope_label)
	_acc_scope_clear = ManagerUi.button("清除這一層的位置")
	_acc_scope_clear.tooltip_text = "把上面選的範圍(動作層或幀層)的設定拿掉,回到比較上層的位置。"
	_acc_scope_clear.pressed.connect(_clear_anchor_scope)
	right.add_child(_acc_scope_clear)
	right.add_child(ManagerUi.labeled("錨點 X(右為正)", _acc_x))
	right.add_child(ManagerUi.labeled("錨點 Y(下為正)", _acc_y))
	_acc_origin = OptionButton.new()
	for label in ["圖片中心", "左上角", "底邊中心", "上邊中心"]:
		_acc_origin.add_item(label)
	_acc_origin.item_selected.connect(func(index: int) -> void: _edit_accessory("origin", ACC_ORIGINS[index], "acc_origin"))
	right.add_child(ManagerUi.labeled("圖上放在錨點的那一點", _acc_origin))
	_acc_scale = ManagerUi.spin(0.05, 0.05, 8.0)
	_acc_scale.value_changed.connect(func(value: float) -> void: _edit_accessory("scale", value, "acc_scale"))
	right.add_child(ManagerUi.labeled("縮放倍率", _acc_scale))
	_acc_actions = ManagerUi.line_edit("* = 所有動作;或動作名稱用逗號分隔,例如 idle, walk")
	_acc_actions.text_changed.connect(func(text: String) -> void: _edit_accessory("actions", _parse_actions(text), "acc_actions"))
	right.add_child(ManagerUi.labeled("在這些動作顯示", _acc_actions))
	_acc_fps = ManagerUi.spin(0.5, 0.5, 60.0)
	_acc_fps.value_changed.connect(func(value: float) -> void: _edit_accessory("fps", value, "acc_fps"))
	right.add_child(ManagerUi.labeled("多張圖的播放速度(fps)", _acc_fps))
	_acc_loop = CheckBox.new()
	_acc_loop.text = "循環播放(取消 = 播到最後一張停住)"
	_acc_loop.toggled.connect(func(on: bool) -> void: _edit_accessory("loop", on, "acc_loop"))
	right.add_child(_acc_loop)
	var image_row := HBoxContainer.new()
	_acc_images = Label.new()
	_acc_images.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_row.add_child(_acc_images)
	_acc_add_image = ManagerUi.button("加入圖片…")
	_acc_add_image.pressed.connect(func() -> void:
		FloatingWindow.native_file_dialog("選擇要加進這個配件的圖片", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]),
				func(paths: PackedStringArray) -> void: add_accessory_images(Array(paths)), get_window_id()))
	image_row.add_child(_acc_add_image)
	_acc_clear_images = ManagerUi.button("只留第一張")
	_acc_clear_images.pressed.connect(func() -> void:
		if _acc_index >= 0 and _acc_index < _accs.size() and (_accs[_acc_index]["images"] as Array).size() > 1:
			_edit_accessory("images", [(_accs[_acc_index]["images"] as Array)[0]], "acc_images")
			_refresh_accessories())
	image_row.add_child(_acc_clear_images)
	right.add_child(image_row)


static func _parse_actions(text: String) -> Array:
	var actions: Array = []
	for part in text.replace("、", ",").split(",", false):
		var clean := part.strip_edges()
		if clean != "" and not actions.has(clean):
			actions.append(clean)
	return actions if not actions.is_empty() else ["*"]


func _acc_texture(relative: String) -> Texture2D:
	var key := "%s|%s" % [_model.root, relative]
	if not _acc_textures.has(key):
		var report: Array[String] = []
		_acc_textures[key] = PetOverlays._load_texture(_model.root, relative, report)
	return _acc_textures[key]


## 從模型重新讀配件清單,更新清單、表單與畫布預覽(切換素材包、撤回重做後都會呼叫)。
func _refresh_accessories() -> void:
	if _acc_list == null:
		return
	_accs = _model.accessories() if _model.has_pack() else []
	if _acc_index >= _accs.size():
		_acc_index = _accs.size() - 1
	if _acc_index < 0 and not _accs.is_empty():
		_acc_index = 0
	_updating = true
	_acc_list.clear()
	for part: Dictionary in _accs:
		_acc_list.add_item("%s(%s)" % [part.get("name", "?"), ["配件", "眨眼", "說話"][maxi(ACC_ROLES.find(str(part.get("role", "part"))), 0)]])
	if _acc_index >= 0:
		_acc_list.select(_acc_index)
	var has_part := _acc_index >= 0 and _acc_index < _accs.size()
	for control: Control in [_acc_name, _acc_role, _acc_layer, _acc_x, _acc_y, _acc_origin, _acc_scale, _acc_actions, _acc_fps, _acc_loop, _acc_add_image, _acc_clear_images, _acc_delete]:
		if control is Button or control is OptionButton or control is CheckBox:
			control.set("disabled", not has_part)
		elif control is LineEdit:
			(control as LineEdit).editable = has_part
		elif control is SpinBox:
			(control as SpinBox).editable = has_part
	_acc_add.disabled = not _model.has_pack() or _accs.size() >= PetOverlays.MAX_PARTS
	if has_part:
		var part: Dictionary = _accs[_acc_index]
		var anchor: Variant = AccessoryAnchors.effective(part, _action, _index)
		_acc_name.text = str(part.get("name", ""))
		_acc_role.select(maxi(ACC_ROLES.find(str(part.get("role", "part"))), 0))
		_acc_layer.select(maxi(ACC_LAYERS.find(str(part.get("layer", "front"))), 0))
		_acc_x.value = (anchor as Vector2).x if anchor is Vector2 else 0.0
		_acc_y.value = (anchor as Vector2).y if anchor is Vector2 else 0.0
		_acc_origin.select(maxi(ACC_ORIGINS.find(str(part.get("origin", "center"))), 0))
		_acc_scale.value = float(part.get("scale", 1.0))
		_acc_actions.text = ", ".join(PackedStringArray(part.get("actions", ["*"])))
		_acc_fps.value = float(part.get("fps", PetOverlays.DEFAULT_FPS))
		_acc_loop.button_pressed = bool(part.get("loop", true))
		_acc_images.text = tr("圖片 %d 張") % (part.get("images", []) as Array).size()
	else:
		_acc_images.text = ""
	_updating = false
	_refresh_anchor_widgets()
	_refresh_layers()


func _accessory_preview() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: Dictionary in _accs:
		var images: Array = part.get("images", [])
		var texture: Texture2D = _acc_texture(str(images[0])) if not images.is_empty() else null
		var anchor: Variant = AccessoryAnchors.effective(part, _action, _index)   # 目前這個動作、這一幀實際的位置
		var origin := PetOverlays._origin_pixels(part.get("origin", "center"), Vector2(texture.get_size()) if texture != null else Vector2.ZERO)
		result.append({"x": (anchor as Vector2).x if anchor is Vector2 else 0.0, "y": (anchor as Vector2).y if anchor is Vector2 else 0.0,
				"scale": float(part.get("scale", 1.0)), "origin": origin, "texture": texture, "name": str(part.get("name", "")), "role": str(part.get("role", "part")),
				"layer": PackLayers.layer_of(part), "hidden": bool(_layer_hidden.get(str(part.get("name", "")), false))})
	return result


func _on_canvas_accessory_selected(index: int) -> void:
	if _furniture_id != "":
		_furn_anchor_index = index
		_refresh_furniture_anchors()
		return
	_acc_index = index
	_layer_body_focus = false
	_refresh_accessories()


func _on_canvas_accessory_edited(index: int, at: Vector2) -> void:
	if _furniture_id != "":
		if _furniture_def == null or index < 0 or index >= _furniture_def.anchors.size():
			return
		_furniture_def.anchors[index]["x"] = at.x
		_furniture_def.anchors[index]["y"] = at.y
		_save_furniture()
		_refresh_furniture_anchors()
		return
	if index < 0 or index >= _accs.size():
		return
	_write_anchor(index, at)
	_updating = true
	_acc_x.value = at.x
	_acc_y.value = at.y
	_updating = false
	_refresh_anchor_widgets()
	_after_edit("")


## 錨點寫進「位置套用範圍」選的那一層(整個配件 / 目前動作 / 目前這一幀)。
func _write_anchor(index: int, at: Vector2) -> void:
	var scope := _acc_scope.selected if _acc_scope != null else AccessoryAnchors.SCOPE_DEFAULT
	AccessoryAnchors.set_anchor(_accs[index], scope, _action, _index, _model.frame_count(_action) if _action != "" else 0, at)
	_model.set_accessories(_accs)


## 座標框改了(使用者輸入)。
func _edit_anchor(at: Vector2) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size():
		return
	_model.checkpoint("acc_anchor")
	_write_anchor(_acc_index, at)
	_refresh_anchor_widgets()
	_after_edit("")


func _clear_anchor_scope() -> void:
	if _acc_index < 0 or _acc_index >= _accs.size() or _acc_scope == null:
		return
	_model.checkpoint()
	AccessoryAnchors.clear_scope(_accs[_acc_index], _acc_scope.selected, _action, _index)
	_model.set_accessories(_accs)
	_refresh_anchor_widgets()
	_after_edit(tr("已清除這一層的位置"))


## 依目前選的動作、幀與位置套用範圍,更新座標框、說明文字與畫布上配件的預覽位置。
func _refresh_anchor_widgets() -> void:
	if _acc_scope == null:
		return
	var has_part := _acc_index >= 0 and _acc_index < _accs.size()
	var has_action := _action != "" and _model.has_pack() and _model.frame_count(_action) > 0
	_acc_scope.set_item_disabled(AccessoryAnchors.SCOPE_ACTION, not has_action)
	_acc_scope.set_item_disabled(AccessoryAnchors.SCOPE_FRAME, not has_action)
	if not has_action and _acc_scope.selected != AccessoryAnchors.SCOPE_DEFAULT:
		_acc_scope.select(AccessoryAnchors.SCOPE_DEFAULT)
	_acc_scope_clear.disabled = not has_part or _acc_scope.selected == AccessoryAnchors.SCOPE_DEFAULT
	if has_part:
		var part: Dictionary = _accs[_acc_index]
		var at := AccessoryAnchors.effective(part, _action, _index)
		_updating = true
		_acc_x.value = at.x
		_acc_y.value = at.y
		_updating = false
		_acc_scope_label.text = tr("「%s」在動作「%s」目前套用:%s") % [part.get("name", "?"), _action if _action != "" else "-", [tr("整個配件的預設位置"), tr("這個動作的位置"), tr("每一幀各自的位置")][AccessoryAnchors.source_of(part, _action)]]
	else:
		_acc_scope_label.text = ""
	if _canvas != null:
		_canvas.set_accessories(_accessory_preview(), _acc_index)


## 用選好的圖片新增一個配件(預設放在頭部上方),選中它。回傳錯誤文字,空字串 = 成功。給按鈕與測試用。
func add_accessory(paths: Array) -> String:
	if not _model.has_pack():
		return "還沒有開啟素材包"
	if _accs.size() >= PetOverlays.MAX_PARTS:
		return "配件太多了"
	if paths.is_empty():
		return "沒有選擇圖片"
	var relatives := _model.import_accessory_images(paths)
	if relatives.is_empty():
		return "無法匯入這些圖片"
	var base_name := str(paths[0]).get_file().get_basename()
	var unique := base_name
	var counter := 2
	while _accs.any(func(p: Dictionary) -> bool: return p.get("name") == unique):
		unique = "%s_%d" % [base_name, counter]
		counter += 1
	_model.checkpoint()
	_accs.append({"name": unique, "role": "part", "images": relatives, "anchor": [0.0, -60.0], "layer": "front", "scale": 1.0, "origin": "center", "actions": ["*"], "fps": PetOverlays.DEFAULT_FPS, "loop": true})
	_model.set_accessories(_accs)
	_acc_index = _accs.size() - 1
	_layer_body_focus = false
	_refresh_accessories()
	_after_edit(tr("已新增配件「%s」(拖曳畫布或改右邊的錨點調整位置)") % unique)
	return ""


## 把圖片加進選中的配件(多張會循環播放)。
func add_accessory_images(paths: Array) -> String:
	if _acc_index < 0 or _acc_index >= _accs.size():
		return "還沒有選配件"
	var relatives := _model.import_accessory_images(paths)
	if relatives.is_empty():
		return "無法匯入這些圖片"
	var images: Array = (_accs[_acc_index]["images"] as Array).duplicate()
	images.append_array(relatives)
	_edit_accessory("images", images.slice(0, PetOverlays.MAX_FRAMES), "acc_images")
	_refresh_accessories()
	return ""


func delete_accessory() -> void:
	if _acc_index < 0 or _acc_index >= _accs.size():
		return
	_model.checkpoint()
	_accs.remove_at(_acc_index)
	_model.set_accessories(_accs)
	_acc_index = mini(_acc_index, _accs.size() - 1)
	_refresh_accessories()
	_after_edit(tr("已刪除配件"))


## 表單改了目前這個配件的一個欄位:存撤回點(同一欄位連續改合併成一步)、寫回模型、更新畫布預覽。
func _edit_accessory(field: String, value: Variant, checkpoint_key: String) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size():
		return
	_model.checkpoint(checkpoint_key)
	_accs[_acc_index][field] = value
	_model.set_accessories(_accs)
	if field == "name" or field == "role":
		_updating = true
		_acc_list.set_item_text(_acc_index, "%s(%s)" % [_accs[_acc_index].get("name", "?"), ["配件", "眨眼", "說話"][maxi(ACC_ROLES.find(str(_accs[_acc_index].get("role", "part"))), 0)]])
		_updating = false
	_canvas.set_accessories(_accessory_preview(), _acc_index)
	_after_edit("")


## 圖層:本體(動作的幀)加上所有配件(部件)排成一疊,可以調上下順序、開關預覽顯示、暫時停用。適合只畫了會動的那一小塊(眨眼的眼睛、說話的嘴、尾巴等拆件),
## 把它們蓋在本體上調位置與順序。配件本身的圖片、錨點、縮放等仍在「配件」頁籤設定,這裡看的是整疊的順序。
func _build_layers_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("圖層", tr("清單由上到下 = 畫面由前到後:最上面的蓋在最上面,中間那一列「本體」是動作的幀,「本體後面」的圖層在它下面。用 ▲ ▼ 調順序(跨過本體就會在「本體上面 / 後面」之間切換);眼睛只影響這個編輯器的預覽(方便看被蓋住的東西),不會存檔;「遊戲中顯示」取消 = 這個圖層暫時停用(存檔後遊戲裡不會出現)。圖層就是配件(部件),最多 %d 個;眨眼、說話差分只畫有變動的那一小塊也用這裡管理。") % PetOverlays.MAX_PARTS))
	_layer_list = ItemList.new()
	_layer_list.custom_minimum_size.y = 130.0
	_layer_list.item_selected.connect(_on_layer_selected)
	right.add_child(_layer_list)
	var row := HBoxContainer.new()
	_layer_up = ManagerUi.button("▲ 上移")
	_layer_up.pressed.connect(func() -> void: _move_layer(1))
	_layer_down = ManagerUi.button("▼ 下移")
	_layer_down.pressed.connect(func() -> void: _move_layer(-1))
	_layer_eye = ManagerUi.button("🚫 預覽隱藏")
	_layer_eye.tooltip_text = "在這個編輯器的預覽裡隱藏 / 顯示選取的圖層(不存檔)。"
	_layer_eye.pressed.connect(_toggle_layer_preview)
	for control in [_layer_up, _layer_down, _layer_eye]:
		row.add_child(control)
	right.add_child(row)
	var add_row := HBoxContainer.new()
	var add := ManagerUi.button("＋ 新增圖層…")
	add.tooltip_text = "選一張或多張圖片做成一個新圖層(配件),放在本體上面;再用畫布或「配件」頁籤調位置。"
	add.pressed.connect(func() -> void:
		FloatingWindow.native_file_dialog("選擇圖層圖片(可多選)", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]),
				func(paths: PackedStringArray) -> void: add_accessory(Array(paths)), get_window_id()))
	add_row.add_child(add)
	var delete := ManagerUi.button("刪除這個圖層")
	delete.pressed.connect(delete_accessory)
	add_row.add_child(delete)
	right.add_child(add_row)
	_layer_game = CheckBox.new()
	_layer_game.text = "在遊戲裡顯示這個圖層(取消 = 暫時停用)"
	_layer_game.button_pressed = true
	_layer_game.toggled.connect(_edit_layer_game)
	right.add_child(_layer_game)
	_layer_note = Label.new()
	_layer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layer_note.theme_type_variation = AppSettings.MUTED_LABEL
	right.add_child(_layer_note)


## 依配件清單重排圖層清單(最上面的在前),選取跟著目前選的配件(或本體)。
func _refresh_layers() -> void:
	if _layer_list == null:
		return
	_layer_rows = PackLayers.stack(_accs)
	_updating = true
	_layer_list.clear()
	var selected_row := -1
	for row in _layer_rows.size():
		var entry := _layer_rows[row]
		if entry == PackLayers.BODY:
			_layer_list.add_item("%s%s" % [("🚫 " if _body_hidden else "🧍 "), tr("本體(動作的幀)")])
			if _layer_body_focus:
				selected_row = row
			continue
		var part: Dictionary = _accs[entry]
		var marks := ""
		if bool(_layer_hidden.get(str(part.get("name", "")), false)):
			marks += tr("[預覽隱藏]")
		if part.get("visible") is bool and not bool(part["visible"]):
			marks += tr("[遊戲停用]")
		var band := ""
		match PackLayers.layer_of(part):
			"top":
				band = tr("最上層")
			"back":
				band = tr("本體後面")
			"above_light":
				band = tr("光源之上")
			_:
				band = tr("本體上面")
		_layer_list.add_item("%s %s(%s)%s" % ["🖼", part.get("name", "?"), band, marks])
		if not _layer_body_focus and entry == _acc_index:
			selected_row = row
	if selected_row >= 0:
		_layer_list.select(selected_row)
	var has_part := not _layer_body_focus and _acc_index >= 0 and _acc_index < _accs.size()
	_layer_up.disabled = not has_part or not bool(PackLayers.move(_accs, _acc_index, 1)["changed"])
	_layer_down.disabled = not has_part or not bool(PackLayers.move(_accs, _acc_index, -1)["changed"])
	_layer_eye.disabled = not has_part and not _layer_body_focus
	var hidden_now := _body_hidden if _layer_body_focus else (has_part and bool(_layer_hidden.get(str(_accs[_acc_index].get("name", "")), false)))
	_layer_eye.text = "👁 預覽顯示" if hidden_now else "🚫 預覽隱藏"
	_layer_game.disabled = not has_part
	_layer_game.button_pressed = not has_part or not (_accs[_acc_index].get("visible") is bool and not bool(_accs[_acc_index]["visible"]))
	_layer_note.text = tr("本體是動作的幀(在「動作」「幀」清單選),不能移動或停用。") if _layer_body_focus else ""
	_updating = false
	_canvas.show_body = not _body_hidden
	_canvas.queue_redraw()


func _on_layer_selected(row: int) -> void:
	if _updating or row < 0 or row >= _layer_rows.size():
		return
	var entry := _layer_rows[row]
	_layer_body_focus = entry == PackLayers.BODY
	if not _layer_body_focus:
		_acc_index = entry
		# 選了圖層就能直接在畫布上拖曳它的位置(從「移動視角畫面」自動切到「調整配件位置」)
		if _mode_option.selected == 0:
			_mode_option.select(6)
			_on_mode_selected(6)
		_refresh_accessories()
	else:
		_refresh_layers()


## 選取的圖層上移(direction = 1)或下移(-1)一格,寫回配件清單(可撤回)。
func _move_layer(direction: int) -> void:
	if _acc_index < 0 or _acc_index >= _accs.size() or _layer_body_focus:
		return
	var moved := PackLayers.move(_accs, _acc_index, direction)
	if not bool(moved["changed"]):
		return
	_model.checkpoint()
	_accs = moved["parts"]
	_acc_index = int(moved["index"])
	_model.set_accessories(_accs)
	_refresh_accessories()
	_after_edit(tr("已調整圖層順序"))


func _toggle_layer_preview() -> void:
	if _layer_body_focus:
		_body_hidden = not _body_hidden
	elif _acc_index >= 0 and _acc_index < _accs.size():
		var key := str(_accs[_acc_index].get("name", ""))
		_layer_hidden[key] = not bool(_layer_hidden.get(key, false))
	_canvas.set_accessories(_accessory_preview(), _acc_index)
	_refresh_layers()


## 「在遊戲裡顯示」勾選:取消 = 這個配件寫 "visible": false(遊戲載入時略過),勾回來就拿掉這個欄位。
func _edit_layer_game(on: bool) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _layer_body_focus:
		return
	_model.checkpoint("acc_visible")
	if on:
		(_accs[_acc_index] as Dictionary).erase("visible")
	else:
		_accs[_acc_index]["visible"] = false
	_model.set_accessories(_accs)
	_refresh_layers()
	_after_edit("")


## 持有錨點:桌寵手拿道具的位置(相對腳底線中心的縮放前像素,面向右時)。不勾 = 自動(判定框前側、胸口高度)。
func _build_hold_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("持有錨點(手拿道具的位置)", "桌寵拿著可持有的道具時,道具畫在這個位置(跟著縮放、鏡像、爬牆旋轉)。座標和光源錨點一樣:相對腳底線中心、縮放前像素、右與下為正。不勾自訂就用自動位置(判定框前側、胸口高度)。"))
	_hold_check = CheckBox.new()
	_hold_check.text = "自訂持有錨點"
	_hold_check.toggled.connect(func(on: bool) -> void: _edit_hold(on))
	right.add_child(_hold_check)
	_hold_x = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_hold_y = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_hold_x.value_changed.connect(func(_v: float) -> void: _edit_hold(true))
	_hold_y.value_changed.connect(func(_v: float) -> void: _edit_hold(true))
	right.add_child(ManagerUi.labeled("持有錨點 X(右為正)", _hold_x))
	right.add_child(ManagerUi.labeled("持有錨點 Y(下為正)", _hold_y))


func _refresh_hold() -> void:
	if _hold_check == null:
		return
	var anchor: Variant = _model.hold_anchor() if _model.has_pack() else null
	_updating = true
	_hold_check.disabled = not _model.has_pack()
	_hold_check.button_pressed = anchor is Vector2
	_hold_x.editable = anchor is Vector2
	_hold_y.editable = anchor is Vector2
	if anchor is Vector2:
		_hold_x.value = (anchor as Vector2).x
		_hold_y.value = (anchor as Vector2).y
	_updating = false


func _edit_hold(custom: bool) -> void:
	if _updating or not _model.has_pack():
		return
	_model.checkpoint("hold_anchor")
	if custom:
		var anchor: Variant = _model.hold_anchor()
		var current: Vector2 = anchor if anchor is Vector2 else Vector2(24.0, -40.0)
		var wanted := Vector2(_hold_x.value, _hold_y.value) if _hold_check.button_pressed and anchor is Vector2 else current
		_model.set_hold_anchor(wanted)
	else:
		_model.set_hold_anchor(null)
	_refresh_hold()
	_after_edit("")


## 從 pack.json 重新讀光源清單,更新清單、表單與畫布(切換素材包、撤回重做後都會呼叫)。
func _refresh_lights() -> void:
	if _light_list == null:
		return
	_lights = _model.lights() if _model.has_pack() else ([] as Array[Dictionary])
	if _light_index >= _lights.size():
		_light_index = _lights.size() - 1
	if _light_index < 0 and not _lights.is_empty():
		_light_index = 0
	_updating = true
	_light_list.clear()
	for light in _lights:
		_light_list.add_item("%s%s" % [light["name"], "" if bool(light["enabled"]) else "(停用)"])
	if _light_index >= 0:
		_light_list.select(_light_index)
	_light_action.clear()
	_light_action.add_item("(一直亮)")
	if _model.has_pack():
		for action_name in _model.action_names():
			_light_action.add_item(str(action_name))
	var has_light := _light_index >= 0 and _light_index < _lights.size()
	_light_delete.disabled = not has_light
	_light_enabled.disabled = not has_light
	_light_frame_enabled.disabled = not has_light
	_light_color.disabled = not has_light
	_light_behind_body.disabled = not has_light
	_light_action.disabled = not has_light
	_light_cond_id.editable = has_light
	_light_cond_copy.disabled = not has_light
	_light_name.editable = has_light
	for spin: SpinBox in [_light_x, _light_y, _light_radius, _light_energy]:
		spin.editable = has_light
	_light_add.disabled = not _model.has_pack() or _lights.size() >= PackLights.MAX_LIGHTS
	if has_light:
		var light := _lights[_light_index]
		_light_name.text = str(light["name"])
		_light_cond_id.text = str(light.get("cond_id", ""))
		var light_at := PackLights.position_of(light, _action, _index)
		_light_x.value = light_at.x
		_light_y.value = light_at.y
		_light_radius.value = PackLights.radius_of(light, _action, _index)
		_light_energy.value = PackLights.energy_of(light, _action, _index)
		_light_color.color = Color(PackLights.color_of(light, _action, _index))
		_light_behind_body.button_pressed = str(light.get("layer", "front")) == "back"
		_light_enabled.button_pressed = bool(light["enabled"])
		_light_frame_enabled.button_pressed = PackLights.frame_enabled(light, _action, _index)
		var action_index := 0
		for i in _light_action.item_count:
			if _light_action.get_item_text(i) == str(light["action"]):
				action_index = i
		_light_action.select(action_index)
	_updating = false
	_refresh_light_widgets()
	_refresh_hold()
	_refresh_accessories()


func _on_light_row_selected(index: int) -> void:
	_light_index = index
	_refresh_lights()


func _on_canvas_light_selected(index: int) -> void:
	if _furniture_id != "":
		_furn_light_index = index
		_refresh_furniture_lights()
		return
	_light_index = index
	_refresh_lights()


## 新增一盞光(頭部上方,預設值),選中它。
func add_light() -> void:
	if not _model.has_pack() or _lights.size() >= PackLights.MAX_LIGHTS:
		return
	_model.checkpoint()
	_lights.append(PackLights.new_light(_lights.size()))
	_model.set_lights(_lights)
	_light_index = _lights.size() - 1
	_refresh_lights()
	_after_edit(tr("已新增光源"))


func delete_light() -> void:
	if _light_index < 0 or _light_index >= _lights.size():
		return
	_model.checkpoint()
	_lights.remove_at(_light_index)
	_model.set_lights(_lights)
	_light_index = mini(_light_index, _lights.size() - 1)
	_refresh_lights()
	_after_edit(tr("已刪除光源"))


## 表單改了目前這盞光的一個欄位:存撤回點(同一欄位連續改合併成一步)、寫回 pack.json、更新畫布。
func _edit_light(field: String, value: Variant, checkpoint_key: String) -> void:
	if _updating or _light_index < 0 or _light_index >= _lights.size():
		return
	_model.checkpoint(checkpoint_key)
	_lights[_light_index][field] = value
	_lights = PackLights.clean(_lights)
	_model.set_lights(_lights)
	_push_lights_to_canvas()
	if field == "enabled" or field == "name":
		_refresh_lights()
	_after_edit("")


## 目前算不算「單獨調整這一幀」:第 0 幀(或沒有動作)一律用預設值;其他幀要先勾選「單獨調整此幀」。
func _light_current_scope() -> int:
	if _action == "" or _index <= 0:
		return ScopedProperty.SCOPE_DEFAULT
	return ScopedProperty.SCOPE_FRAME


func _light_frame_editable() -> bool:
	return _action == "" or _index <= 0 or (_light_frame_unlock != null and _light_frame_unlock.button_pressed)


## 表單改了半徑/亮度/顏色/分幀熄燈:寫進目前的套用範圍(field 是 "radius"/"energy"/"color"/"enabled",
## 跟 PackLights.set_radius() 等函式的第一個參數對應)。沒解鎖這一幀(且不是第 0 幀)時忽略。
func _edit_light_scoped(field: String, value: Variant, checkpoint_key: String) -> void:
	if _updating or _light_index < 0 or _light_index >= _lights.size() or not _light_frame_editable():
		return
	_model.checkpoint(checkpoint_key)
	var scope := _light_current_scope()
	var frame_count := _model.frame_count(_action) if _action != "" else 0
	match field:
		"radius":
			PackLights.set_radius(_lights[_light_index], scope, _action, _index, frame_count, value)
		"energy":
			PackLights.set_energy(_lights[_light_index], scope, _action, _index, frame_count, value)
		"color":
			PackLights.set_color(_lights[_light_index], scope, _action, _index, frame_count, value)
		"enabled":
			PackLights.set_frame_enabled(_lights[_light_index], scope, _action, _index, frame_count, value)
	_lights = PackLights.clean(_lights)
	_model.set_lights(_lights)
	_push_lights_to_canvas()
	_refresh_light_widgets()
	_after_edit("")


## 畫布上拖曳(或方向鍵微調)錨點:寫回 pack.json、更新表單的 X / Y。沒解鎖這一幀就忽略(避免拖曳意外建出覆蓋)。
func _on_canvas_light_edited(index: int, at: Vector2) -> void:
	if _furniture_id != "":
		if _furniture_def == null or index < 0 or index >= _furniture_def.lights.size():
			return
		var raw: Dictionary = _furniture_def.lights[index].duplicate(true)
		raw["x"] = at.x
		raw["y"] = at.y
		_furniture_def.lights[index] = FurnitureDef.clean_light(raw)
		_furn_light_index = index
		_save_furniture()
		_refresh_furniture_lights()
		return
	if index < 0 or index >= _lights.size() or not _light_frame_editable():
		return
	_write_light_position(index, at)
	_refresh_light_widgets()
	_after_edit("")


## 座標寫進目前的套用範圍(第 0 幀/沒有動作 = 預設值;其他幀 = 這一幀單獨的值)。
func _write_light_position(index: int, at: Vector2) -> void:
	PackLights.set_position(_lights[index], _light_current_scope(), _action, _index, _model.frame_count(_action) if _action != "" else 0, at)
	_lights = PackLights.clean(_lights)
	_model.set_lights(_lights)


func _edit_light_position(at: Vector2) -> void:
	if _updating or _light_index < 0 or _light_index >= _lights.size() or not _light_frame_editable():
		return
	_model.checkpoint("light_anchor")
	_write_light_position(_light_index, at)
	_refresh_light_widgets()
	_after_edit("")


## 「單獨調整此幀」開關:打開只是讓下面的欄位變成可編輯,還沒有值好寫;關掉要把這一幀在五個屬性上的覆蓋
## 全部清掉,退回跟著預設值走。
func _on_light_frame_unlock_toggled(on: bool) -> void:
	if _updating or _light_index < 0 or _light_index >= _lights.size():
		return
	if on:
		# 只是解鎖,還沒有任何一幀的資料好寫;不能呼叫 _refresh_light_widgets()(它會反過來從資料推算這個
		# 開關該不該勾選,這時候還沒資料,會把剛剛勾上的開關又推回沒勾),單純把欄位變成可編輯狀態就好。
		for control: SpinBox in [_light_x, _light_y, _light_radius, _light_energy]:
			control.editable = true
		_light_color.disabled = false
		_light_frame_enabled.disabled = false
		return
	_model.checkpoint()
	var light: Dictionary = _lights[_light_index]
	PackLights.clear_scope(light, ScopedProperty.SCOPE_FRAME, _action, _index)
	PackLights.clear_radius_scope(light, ScopedProperty.SCOPE_FRAME, _action, _index)
	PackLights.clear_energy_scope(light, ScopedProperty.SCOPE_FRAME, _action, _index)
	PackLights.clear_color_scope(light, ScopedProperty.SCOPE_FRAME, _action, _index)
	PackLights.clear_enabled_scope(light, ScopedProperty.SCOPE_FRAME, _action, _index)
	_lights = PackLights.clean(_lights)
	_model.set_lights(_lights)
	_refresh_light_widgets()
	_after_edit(tr("已清除這一幀的設定"))


## 畫布上畫的光:位置/半徑/亮度/顏色/是否亮著都換成「目前這個動作、這一幀」實際生效的值,
## 這樣切換動作/幀時預覽才看得出分幀調整的效果(例如指定幀熄燈,畫布上這一幀就會變暗)。
func _lights_preview() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for light in _lights:
		var copy := light.duplicate(true)
		var at := PackLights.position_of(light, _action, _index)
		copy["x"] = at.x
		copy["y"] = at.y
		copy["radius"] = PackLights.radius_of(light, _action, _index)
		copy["energy"] = PackLights.energy_of(light, _action, _index)
		copy["color"] = PackLights.color_of(light, _action, _index)
		copy["enabled"] = bool(light["enabled"]) and PackLights.frame_enabled(light, _action, _index)
		result.append(copy)
	return result


func _push_lights_to_canvas() -> void:
	if _canvas != null:
		_canvas.set_lights(_lights_preview(), _light_index)


## 依目前動作、幀更新光源的座標框、半徑/亮度/顏色/是否亮著、「單獨調整此幀」開關與畫布。
func _refresh_light_widgets() -> void:
	if _light_frame_unlock == null:
		return
	var has_light := _light_index >= 0 and _light_index < _lights.size()
	var is_base_frame := _action == "" or _index <= 0
	_light_frame_unlock.visible = not is_base_frame
	var editable := has_light and _light_frame_editable()
	for control: SpinBox in [_light_x, _light_y, _light_radius, _light_energy]:
		control.editable = editable
	_light_color.disabled = not editable
	_light_frame_enabled.disabled = not editable
	if has_light:
		var light: Dictionary = _lights[_light_index]
		_updating = true
		if not is_base_frame:
			_light_frame_unlock.button_pressed = (
					PackLights.source_of(light, _action) == AccessoryAnchors.SCOPE_FRAME
					or PackLights.radius_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME
					or PackLights.energy_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME
					or PackLights.color_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME
					or PackLights.enabled_source_of(light, _action, _index) == ScopedProperty.SCOPE_FRAME)
		var at := PackLights.position_of(light, _action, _index)
		_light_x.value = at.x
		_light_y.value = at.y
		_light_radius.value = PackLights.radius_of(light, _action, _index)
		_light_energy.value = PackLights.energy_of(light, _action, _index)
		_light_color.color = Color(PackLights.color_of(light, _action, _index))
		_light_frame_enabled.button_pressed = PackLights.frame_enabled(light, _action, _index)
		_updating = false
		if is_base_frame:
			_light_scope_label.text = tr("「%s」顯示預設值(整個光源共用,除非之後選到的幀有單獨調整)。") % light.get("name", "?")
		else:
			_light_scope_label.text = tr("「%s」目前顯示動作「%s」第 %d 幀:%s") % [light.get("name", "?"), _action, _index,
					tr("這一幀單獨調整過") if _light_frame_unlock.button_pressed else tr("跟著預設值")]
	else:
		_light_scope_label.text = ""
	_push_lights_to_canvas()


# --- 圖片處理(裁切 / 翻轉 / 旋轉) ---
func _update_fx_buttons() -> void:
	var usable := _model.has_pack() and _action != "" and _model.frame_count(_action) > 0
	for button in _fx_buttons:
		button.disabled = not usable


## 裁切數字框的上限跟著這一幀的圖大小。
func _update_crop_limits(size: Vector2i) -> void:
	_updating = true
	(_crop_spins[0] as SpinBox).max_value = float(size.x)
	(_crop_spins[1] as SpinBox).max_value = float(size.y)
	(_crop_spins[2] as SpinBox).max_value = float(size.x)
	(_crop_spins[3] as SpinBox).max_value = float(size.y)
	_updating = false


## 裁切框(畫布與數字框同步)。空的 Rect2i = 沒有框。
func _set_crop_ui(rect: Rect2i) -> void:
	_updating = true
	(_crop_spins[0] as SpinBox).value = rect.position.x
	(_crop_spins[1] as SpinBox).value = rect.position.y
	(_crop_spins[2] as SpinBox).value = rect.size.x
	(_crop_spins[3] as SpinBox).value = rect.size.y
	_updating = false
	_canvas.set_crop_rect(rect)


func _on_canvas_crop_changed(rect: Rect2i) -> void:
	_updating = true
	(_crop_spins[0] as SpinBox).value = rect.position.x
	(_crop_spins[1] as SpinBox).value = rect.position.y
	(_crop_spins[2] as SpinBox).value = rect.size.x
	(_crop_spins[3] as SpinBox).value = rect.size.y
	_updating = false


func _on_crop_spin_changed() -> void:
	if _updating:
		return
	var rect := Rect2i(int((_crop_spins[0] as SpinBox).value), int((_crop_spins[1] as SpinBox).value), int((_crop_spins[2] as SpinBox).value), int((_crop_spins[3] as SpinBox).value))
	_canvas.set_crop_rect(rect if rect.size.x > 0 and rect.size.y > 0 else Rect2i())


## 對選取的幀各加一步圖片處理。
func _apply_fx_op(op: Dictionary, message: String) -> void:
	if not _model.has_pack() or _action == "":
		return
	var picked := _selected_frames()
	var error := _model.apply_fx(_action, picked, op)
	if error != "":
		_status.text = tr("沒有套用:%s") % error
		return
	_after_frames_changed(picked, tr("%s(%d 幀;可以撤回)") % [message, picked.size()])


## 套用畫布上(或數字框裡)的裁切範圍到選取的幀。
func _apply_crop() -> void:
	var rect := _canvas.crop_rect()
	if rect.size.x < 1 or rect.size.y < 1:
		_status.text = "還沒有裁切範圍:在「裁切圖片」模式的畫布上拖曳,或填數字"
		return
	_apply_fx_op({"op": "c", "rect": rect}, tr("已裁切成 %d×%d") % [rect.size.x, rect.size.y])
	_set_crop_ui(Rect2i())


func _clear_fx() -> void:
	if not _model.has_pack() or _action == "":
		return
	var picked := _selected_frames()
	var count := _model.clear_fx(_action, picked)
	if count == 0:
		_status.text = "選取的幀本來就沒有圖片處理"
		return
	_after_frames_changed(picked, tr("已還原 %d 幀的圖片處理(手動軸心一併回到自動)") % count)


# --- 編輯手勢 ---

func _whole_action() -> bool:
	return _scope_option.selected == 1


## 滑鼠拖曳每按一次是新的一步(拖曳過程中的每個位置不算);方向鍵連續按合併成一步。
func _on_canvas_edit_started(kind: String) -> void:
	if kind == "drag":
		_gesture += 1
		_model.checkpoint("drag:%d" % _gesture)
	else:
		_model.checkpoint("key")


func _on_canvas_pivot_edited(pivot: Vector2) -> void:
	if _action == "":
		return
	_model.set_pivot(_action, _index, pivot, _whole_action())
	_updating = true
	_pivot_x.value = pivot.x
	_pivot_y.value = pivot.y
	_updating = false
	_after_edit("")


func _on_canvas_offset_edited(offset: Vector2) -> void:
	if _action == "":
		return
	_model.set_offset(_action, _index, offset, _whole_action())
	_updating = true
	_offset_x.value = offset.x
	_offset_y.value = offset.y
	_updating = false
	_after_edit("")


func _on_spin_changed(is_pivot: bool) -> void:
	if _updating or _action == "":
		return
	_model.checkpoint("spin_pivot" if is_pivot else "spin_offset")
	if is_pivot:
		_model.set_pivot(_action, _index, Vector2(_pivot_x.value, _pivot_y.value), _whole_action())
	else:
		_model.set_offset(_action, _index, Vector2(_offset_x.value, _offset_y.value), _whole_action())
	_refresh_frame()
	_after_edit("")


# --- 幀的複製 / 貼上 / 刪除 / 移動 ---

## 目前選取的幀(沒有選取就是畫布上那一幀)。
func _selected_frames() -> Array[int]:
	var picked: Array[int] = []
	for i in _frame_list.get_selected_items():
		picked.append(i)
	if picked.is_empty() and _action != "" and _model.frame_count(_action) > 0:
		picked.append(_index)
	return picked


## 停用沒有意義的按鈕(沒有動作、剪貼簿是空的…)。
func _update_frame_buttons() -> void:
	var usable := _model.has_pack() and _action != "" and _model.frame_count(_action) > 0
	for button in _frame_buttons:
		button.disabled = not usable
	if _paste_button != null:
		# 貼上可以直接貼進還沒有素材的動作槽(會用槽的名字建立這個動作)
		_paste_button.disabled = not _model.has_pack() or _paste_target() == "" or _model.clipboard.is_empty()
	_update_history_buttons()
	_update_fx_buttons()


## 幀清單改了(貼上、複製一份、移動、刪除、圖片處理):重建清單、選取新的幀、標成有未存的變更。
func _after_frames_changed(new_selection: Array[int], message: String) -> void:
	_reload_lists(new_selection)
	_refresh_all()
	_after_edit(message)


func _copy_selected() -> void:
	if _action == "":
		return
	var count := _model.copy_frames(_action, _selected_frames())
	_status.text = tr("已複製 %d 幀(可以切到別的動作再貼上)") % count if count > 0 else "沒有可複製的幀"
	_update_frame_buttons()


## 貼上的目標動作:目前選的動作;停在還沒有素材的動作槽上就是那個槽的名字(貼上時建立);都沒有回空字串。
func _paste_target() -> String:
	if _action != "":
		return _action
	return SpritePackLoader.clean_action_name(_slot) if _slot != "" else ""


func _paste() -> void:
	var target := _paste_target()
	if target == "" or _model.clipboard.is_empty():
		_status.text = "剪貼簿是空的:先選幀按「複製」" if _model.clipboard.is_empty() else "先選一個動作(或動作槽)再貼上"
		return
	var picked := _selected_frames() if _action != "" else ([] as Array[int])
	var at := picked[picked.size() - 1] + 1 if not picked.is_empty() else -1
	var created := _model.paste_frames(target, at)
	if not created.is_empty():
		_slot = target if _action == "" else _slot
		_after_frames_changed(created, tr("已貼上 %d 幀到「%s」") % [created.size(), target])
		_extra_slots.erase(target)


func _duplicate_selected() -> void:
	if _action == "":
		return
	var created := _model.duplicate_frames(_action, _selected_frames())
	if not created.is_empty():
		_after_frames_changed(created, tr("已複製一份(%d 幀)") % created.size())


func _delete_selected() -> void:
	if _action == "":
		return
	var picked := _selected_frames()
	var deleting_action := _action
	var before_count := _model.frame_count(deleting_action)
	var error := _model.delete_frames(deleting_action, picked)
	if error != "":
		_status.text = error
		return
	var new_count := _model.frame_count(deleting_action)
	var keep: Array[int] = []
	if new_count > 0:
		keep = [mini(picked[0], new_count - 1)]
	var message := tr("已刪除 %d 幀") % picked.size()
	# 選了動作的全部幀來刪:精靈圖切片這個動作真的消失了;平放圖檔/動作資料夾的話清單設定清空後會退回顯示磁碟上原本的圖(檔案沒被刪),告知怎麼真的清掉。
	if picked.size() >= before_count:
		if not _model.action_names().has(deleting_action):
			message = tr("「%s」這個動作已經清空,不再出現在動作清單裡。") % deleting_action
		elif _model.actions_with_own_files().has(deleting_action):
			message = tr("「%s」的幀清單設定清空了,但畫面顯示的還是磁碟上原本的圖檔(共 %d 張),沒有真的不見;想整個清掉這個動作的檔案,用「清理未使用檔案…」裡的「清除動作檔案」。") % [deleting_action, new_count]
	_after_frames_changed(keep, message)


func _move_selected(delta: int) -> void:
	if _action == "":
		return
	var moved := _model.move_frames(_action, _selected_frames(), delta)
	if not moved.is_empty():
		_after_frames_changed(moved, "已移動")


## 左下角「循環方式」與幀範圍的控制項依目前動作重新顯示(幀範圍的上限 = 幀數 - 1)。
func _refresh_loop_widgets() -> void:
	if _loop_mode == null:
		return
	var count := _model.frame_count(_action) if _model.has_pack() and _action != "" else 0
	var entry := _model.loop_of(_action) if count > 0 else {}
	var last := maxi(count - 1, 0)
	var entry_mode := str(entry.get("mode", ""))
	var mode := 3 if entry_mode == "repeat" else (2 if entry_mode == "once" else (1 if not entry.is_empty() else 0))
	_updating = true
	for spin: SpinBox in [_loop_start, _loop_end, _loop_hold]:
		spin.max_value = last
	_loop_mode.select(mode)
	_loop_start.value = clampi(int(entry.get("start", 0)), 0, last)
	_loop_end.value = clampi(int(entry.get("end", last)), 0, last)
	_loop_hold.value = clampi(int(entry.get("hold", last)), 0, last)
	_loop_times.value = clampi(int(entry.get("times", 0)), 0, PackLoop.MAX_TIMES)
	_updating = false
	_loop_mode.disabled = count <= 1
	_loop_start_row.visible = mode == 1
	_loop_end_row.visible = mode == 1
	_loop_hold_row.visible = mode == 2
	_loop_times_row.visible = mode == 3
	match mode:
		1:
			var intro: Array[String] = []
			for i in int(_loop_end.value) + 1:
				intro.append(str(i))
			var loop_part: Array[String] = []
			for i in range(int(_loop_start.value), int(_loop_end.value) + 1):
				loop_part.append(str(i))
			_loop_note.text = tr("播放順序:%s,之後 %s 一直循環。") % [" ".join(intro), " ".join(loop_part)]
		2:
			_loop_note.text = tr("播到第 %d 幀就停住,直到這個動作被切換。") % int(_loop_hold.value)
		3:
			var times := int(_loop_times.value)
			_loop_note.text = tr("只播一次,不循環(播完停在最後一幀)。") if times == 0 else tr("整段重複播 %d 次(含第一次)後停在最後一幀。") % (times + 1)
		_:
			_loop_note.text = ""


## 循環方式或幀範圍改了:寫進 pack.json 的 loop_by_action(可撤回)。起點大於終點時終點跟著起點。
func _edit_loop() -> void:
	if _updating or not _model.has_pack() or _action == "":
		return
	var entry := {}
	match _loop_mode.selected:
		1:
			var start := int(_loop_start.value)
			var end := maxi(int(_loop_end.value), start)
			entry = {"mode": "loop", "start": start, "end": end}
		2:
			entry = {"mode": "once", "hold": int(_loop_hold.value)}
		3:
			entry = {"mode": "repeat", "times": int(_loop_times.value)}
	_model.checkpoint("loop")
	_model.set_loop(_action, entry)
	_refresh_loop_widgets()
	_after_edit("")


func _on_fps_changed(value: float) -> void:
	if _updating or not _model.has_pack() or _action == "":
		return
	_model.checkpoint("fps")
	_model.set_fps(_action, value)
	_play_timer.wait_time = 1.0 / maxf(value, 1.0)
	_after_edit("")


# --- 換精靈圖 / 另存新素材包 ---

func _on_replace_sheet_pressed() -> void:
	if not _model.has_pack():
		return
	if _model.sheets_in_use().is_empty():
		_status.text = "這個素材包沒有使用精靈圖(用「匯入精靈圖…」切出來的動作才有)"
		return
	_show_file_dialog("選擇新的精靈圖(尺寸要和原本的一樣)", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray([IMAGE_FILTER]), _on_replace_picked)


func _on_replace_picked(paths: PackedStringArray) -> void:
	replace_sheet_with(paths[0])


## 用 new_source 取代正在使用的精靈圖。只有一張就直接換;有好幾張先問要換哪一張。
func replace_sheet_with(new_source: String) -> void:
	var sheets := _model.sheets_in_use()
	if sheets.size() == 1:
		_finish_replace(sheets[0], new_source)
		return
	var dialog := ConfirmationDialog.new()
	# 不設 always_on_top,見 _ask_name() 的說明(跟置頂衝突,會把視窗卡死)。
	dialog.title = "要換哪一張精靈圖?"
	var choice := OptionButton.new()
	for sheet_path in sheets:
		choice.add_item(sheet_path)
	dialog.add_child(choice)
	dialog.ok_button_text = "換這一張"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func() -> void: _finish_replace(sheets[choice.selected], new_source))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(460, 120))


func _finish_replace(old_relative: String, new_source: String) -> void:
	var error := _model.replace_sheet(old_relative, new_source)
	if error != "":
		_status.text = tr("換精靈圖失敗:%s") % error
		return
	_reload_lists()
	_refresh_all()
	_after_edit(tr("已把「%s」換成新的圖(切片、軸心、偏移、動作、速度都沒變;可以用撤回還原)") % old_relative)


func _on_save_as_pressed() -> void:
	if not _model.has_pack():
		return
	_ask_name("另存為新素材包", "把目前的素材包(含還沒存檔的編輯)複製到專案 sprite 資料夾裡的一個新資料夾,之後編輯的就是新的那份。\n幫新角色取個名字:", "%s_2" % _model.root.get_file(), "另存", func(chosen: String) -> void:
		var problem := SpriteLibrary.name_problem(chosen)
		if problem != "":
			_status.text = tr("另存失敗:%s") % problem
			return
		save_as_folder(SpriteLibrary.unique_folder(SpriteLibrary.folder_name_for(chosen))))


# --- 匯出獨立圖檔 / 清理未使用檔案 ---

func _on_export_frames_pressed() -> void:
	if not _model.has_pack():
		return
	_show_file_dialog("選擇要放獨立圖檔的資料夾", DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(),
			func(paths: PackedStringArray) -> void: export_frames_to(str(paths[0])), SpriteLibrary.root_dir())


## 匯出獨立圖檔到資料夾。回傳錯誤文字(空字串 = 成功)。
func export_frames_to(folder: String) -> String:
	var result := _model.export_frames(folder)
	if not bool(result["ok"]):
		_status.text = tr("匯出失敗:%s") % result["error"]
		return str(result["error"])
	_status.text = tr("已匯出 %d 張獨立圖檔(和 frames.json)到:%s") % [result["count"], result["folder"]]
	return ""


func _on_clean_pressed() -> void:
	var list := _model.unused_files()
	var own_files_actions := _model.actions_with_own_files()
	if list.is_empty() and own_files_actions.is_empty():
		_status.text = "沒有未使用的檔案。"
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "清理未使用檔案"
	dialog.ok_button_text = "搬到備份"
	dialog.cancel_button_text = "取消"
	# 不設 always_on_top,見 _ask_name() 的說明(跟置頂衝突,會把視窗卡死)。
	dialog.theme = ManagerUi.make_theme()
	if list.is_empty():
		dialog.dialog_text = "沒有匯入時複製進來、卻已經沒人用的檔案。"
		dialog.get_ok_button().disabled = true
	else:
		dialog.dialog_text = tr("有 %d 個檔案已經沒有任何動作或配件在用:\n\n%s\n\n要搬到備份資料夾嗎?(不會直接刪除)") % [list.size(), "\n".join(PackedStringArray(list.slice(0, 12))) + ("\n……" if list.size() > 12 else "")]
		dialog.confirmed.connect(func() -> void: clean_unused())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	if not own_files_actions.is_empty():
		dialog.add_child(_build_clear_action_row(dialog, own_files_actions))
	FloatingWindow.popup_child_dialog(self, get_window(), dialog)


## 「清理未使用檔案」對話框裡附加的一排:挑一個「有自己實體檔案(不是精靈圖切片)」的動作,整個清掉它的圖(幀清單設定清空 + 檔案搬到備份)。
## 另外跳一個確認,不會跟著對話框的主要按鈕一起按下去。
func _build_clear_action_row(host: Window, action_names: Array[String]) -> Control:
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	box.add_child(ManagerUi.hint_row("清除某個動作的檔案", "這些動作至少有一個檔案是自己獨有(沒有被別的動作或配件共用)。整個清掉的話,這個動作就不會再出現在動作清單;它獨有的圖檔搬到備份資料夾(不會直接刪除),被共用的圖檔不會動。"))
	var row := HBoxContainer.new()
	var option := OptionButton.new()
	for name in action_names:
		option.add_item(name)
	row.add_child(option)
	var clear_button := ManagerUi.button("清除這個動作的檔案…")
	clear_button.pressed.connect(func() -> void:
		if option.item_count == 0:
			return
		_confirm_clear_action(str(option.get_item_text(option.selected)), host))
	row.add_child(clear_button)
	box.add_child(row)
	return box


func _confirm_clear_action(action_name: String, host: Window) -> void:
	var files := _model.own_files_of(action_name)
	var confirm := ConfirmationDialog.new()
	confirm.title = "清除動作的檔案"
	confirm.ok_button_text = "清除並搬到備份"
	confirm.cancel_button_text = "取消"
	# 不設 always_on_top,見 _ask_name() 的說明(跟置頂衝突,會把視窗卡死)。
	confirm.theme = ManagerUi.make_theme()
	confirm.dialog_text = tr("要整個清掉「%s」嗎?這個動作就不會再出現在動作清單。它獨有的 %d 個檔案會搬到備份資料夾(不會直接刪除;被別的動作共用的圖檔不會動):\n\n%s") % [action_name, files.size(), "\n".join(PackedStringArray(files.slice(0, 12))) + ("\n……" if files.size() > 12 else "")]
	confirm.confirmed.connect(func() -> void:
		var result := _model.clear_action_files(action_name)
		if not bool(result["ok"]):
			_status.text = tr("清除失敗:%s") % result["error"]
		else:
			_after_frames_changed([], tr("已清除「%s」,搬走 %d 個檔案到:%s") % [action_name, result["moved"], result["backup"]]))
	confirm.confirmed.connect(confirm.queue_free)
	confirm.canceled.connect(confirm.queue_free)
	FloatingWindow.popup_child_dialog(host, host, confirm)


## 把未使用的檔案搬到備份。回傳錯誤文字(空字串 = 成功)。
func clean_unused() -> String:
	var result := _model.remove_unused_files()
	if str(result["error"]) != "":
		_status.text = tr("清理失敗:%s") % result["error"]
		return str(result["error"])
	_status.text = tr("已把 %d 個未使用的檔案搬到備份:%s") % [result["moved"], result["backup"]] if int(result["moved"]) > 0 else "沒有未使用的檔案。"
	return ""


## 把目前的素材包另存到新資料夾並切過去。
func save_as_folder(folder: String) -> String:
	var error := _model.save_as(folder)
	if error != "":
		_status.text = tr("另存失敗:%s") % error
		return error
	_reload_lists()
	_refresh_all()
	_status.text = tr("已另存到:%s。現在編輯的是這個新素材包;接著可以用「換精靈圖…」換成新角色的圖。") % _model.root
	return ""


func _undo() -> void:
	if _model.undo():
		_after_history("已撤回")


func _redo() -> void:
	if _model.redo():
		_after_history("已重做")


## 撤回/重做後動作與幀清單都可能變了(匯入被撤回),整個重建。
func _after_history(message: String) -> void:
	_reload_lists()
	_refresh_all()
	_status.text = message + ("" if _model.dirty else "(回到已存檔的內容)")


func _update_history_buttons() -> void:
	if _undo_button != null:
		_undo_button.disabled = not _model.can_undo()
		_redo_button.disabled = not _model.can_redo()


func _after_edit(message: String) -> void:
	_refresh_frame_labels_only()
	_status.text = message if message != "" else "有未存的變更"
	if message != "":
		_refresh_frame()


## 拖曳中不重設畫布(會讓圖片跳動),只更新標題與按鈕狀態。
func _refresh_frame_labels_only() -> void:
	var subject := (tr(" — 道具:%s") % _prop_def.display_name) if _prop_def != null else ((tr(" — 家具:%s") % _furniture_def.display_name) if _furniture_def != null else (" — " + _model.root.get_file() if _model.has_pack() else ""))
	title = tr("精靈圖編輯器%s%s") % [subject, " *" if _model.dirty else ""]
	_update_history_buttons()


func _save() -> void:
	if not _model.has_pack():
		return
	var error := _model.save()
	_status.text = tr("已存檔:%s(舊檔備份為 pack.json.bak)。桌面上用這個素材包的桌寵會馬上換上新圖。") % _model.root.path_join("pack.json") if error == "" else tr("存檔失敗:%s") % error
	if error == "":
		_warn_about_limits_after_save()
		if _prop_def == null:
			saved.emit(_model.root)
	_refresh_frame_labels_only()


## 存檔後立刻用 SpritePackLoader.load_pack() 真的載入一次,檢查「素材太多太大」(見
## SpritePackLoader.limit_warning_dialogs())——跟 saved.emit() 觸發的桌面重新載入(desktop_shell.gd 的
## reload_pack_pets())是兩條獨立路徑:這裡不管桌面上有沒有已經放著用這個素材包的桌寵都會檢查,不然
## 「存檔當下還沒放上桌面」的素材包永遠不會被檢查到。角色/道具/家具都走這裡,不特判 _prop_def/_furniture_def。
func _warn_about_limits_after_save() -> void:
	var result := SpritePackLoader.load_pack(_model.root)
	if bool(result.get("ok", false)):
		ManagerUi.show_pack_limit_warnings(self, get_window(), result)


func _on_play_toggled(on: bool) -> void:
	_play_button.text = "■ 停止預覽" if on else "▶ 預覽動畫"
	if on:
		_play_timer.start()
	else:
		_play_timer.stop()


func _on_play_tick() -> void:
	var count := _model.frame_count(_action)
	if count <= 1:
		return
	# 預覽照這個動作的循環設定播(從指定幀循環、播一次停住;沒設定就是整段循環)
	var next := PackLoop.next_frame(count, _model.loop_of(_action), _index)
	if next == _index:
		return
	_index = next
	_frame_list.select(_index)
	_refresh_frame()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	# 在文字輸入框(動作名稱、數值框)裡打字時,複製貼上刪除留給輸入框自己。
	var typing := gui_get_focus_owner() is LineEdit or gui_get_focus_owner() is TextEdit
	if event.ctrl_pressed:
		match event.keycode:
			KEY_S:
				_save()
			KEY_Z:
				if event.shift_pressed:
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
			KEY_C:
				if typing:
					return
				_copy_selected()
			KEY_V:
				if typing:
					return
				_paste()
			KEY_D:
				if typing:
					return
				_duplicate_selected()
			_:
				return
	elif event.alt_pressed and (event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT):
		_move_selected(-1 if event.keycode == KEY_LEFT else 1)
	elif event.keycode == KEY_DELETE and not typing and gui_get_focus_owner() != null and not (gui_get_focus_owner() is SpinBox):
		_delete_selected()
	else:
		return
	get_viewport().set_input_as_handled()


## 叉叉(系統的):有未存的變更就跳出「存檔後關閉 / 放棄變更並關閉 / 取消」,沒有就直接關。
func _request_close() -> void:
	guard_unsaved(queue_free, "關閉")
