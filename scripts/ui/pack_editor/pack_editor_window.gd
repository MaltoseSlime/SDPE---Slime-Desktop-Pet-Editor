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
## 種類下拉的第 4 項「待呼叫」:存檔還是 role = part 加 "visible": false(PetOverlays 的 dormant),舊檔案、網頁都不用改。
const ACC_KIND_STANDBY := 3
const ACC_KIND_LABELS: Array[String] = ["配件", "眨眼", "說話", "待呼叫"]
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
## 逐幀顯示:「這一幀:↺ 照規則 / 👁 顯示 / 🚫 不顯示」三個互斥按鈕(2026-10-16 從兩個勾選框改成這樣,「不顯示」連積木叫出來也不顯示)。
var _acc_frame_label: Label
var _acc_frame_rule_buttons: Array[Button] = []
var _acc_frame_clear: Button
var _acc_flip_h: Button
var _acc_flip_v: Button
## 這個動作整個圖層左右鏡像(mirror_for,建立朝向版本時會自動打開)
var _acc_mirror: Button
var _acc_fps: SpinBox
var _acc_loop: CheckBox
var _acc_images: Label
var _trim_shared: CheckBox
var _trim_recover: CheckBox
var _layer_frames: LayerFramesPanel
## 圖層頁「裁切與對齊點」區段(預設收起;選「自訂」對齊點時自動展開)。
var _layer_crop_fold: FoldSection
## 家具圖層的「誰在用時顯示」(只有編輯家具時出現,見 PetOverlays 檔頭的 used_by)。
var _furn_user_box: VBoxContainer
var _furn_user_mode: OptionButton
var _furn_user_seat: OptionButton
var _furn_user_pets: ItemList
var _furn_user_tags: Array[String] = []
const FURN_USER_MODES: Array[String] = ["always", "idle", "in_use", "pets", "not_pets"]
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
## 「預覽視圖設定」小視窗裡的勾選框:畫布屬性名 → CheckBox。
var _view_checks: Dictionary = {}
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
## 預覽動畫時圖層也一起播(2026-10-16):多張圖依 fps 循環、眨眼隨機眨、說話差分當作一直在講話。
var _layer_clock := 0.0
var _blink_next := 1.0
var _blink_left := 0.0
var _blink_duration := 0.0
const PREVIEW_BLINK_INTERVAL := Vector2(1.5, 3.5)   # 比遊戲裡短一點,預覽時比較快看到
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
var _layer_list: LayerListView
var _layer_delete: Button
var _layer_up: Button
var _layer_down: Button
var _layer_eye: Button
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
var _furn_anchor_hide: CheckBox
var _facing_panel: VBoxContainer
var _facing_option: OptionButton
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
var _direction_row: Control
var _sync_row: Control
var _sync_check: CheckBox
var _sync_push: Button
var _direction_option: OptionButton
var _direction_mirror: Button
var _action_source: OptionButton
var _index := 0
var _selected: Array[int] = []
var _updating := false
var _gesture := 0


## 建立視窗內容。folder 非空就順便開啟那個素材包資料夾(給測試與程式用);回傳空字串或開啟失敗的原因。
func setup(folder := "") -> String:
	setup_floating(tr("精靈圖編輯器"), Vector2i(1180, 760), Vector2i(960, 560))
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
	open.tooltip_text = tr("選一個素材包資料夾:不在專案 sprite 資料夾裡的會複製一份進來(原資料夾不動),已經在裡面的直接開啟。")
	open.pressed.connect(_on_open_pressed)
	var create := ManagerUi.button("新建資料夾…")
	create.tooltip_text = tr("在專案統一存放 sprite 的資料夾裡新建一個空的素材包。你取的名字同時是資料夾名、角色顯示名稱與預設辨識代號。")
	create.pressed.connect(_on_create_pressed)
	var reveal := ManagerUi.button("📁")
	reveal.tooltip_text = tr("在檔案總管打開專案的 sprite 資料夾(%s)") % SpriteLibrary.ROOT
	reveal.pressed.connect(func() -> void: OS.shell_open(SpriteLibrary.root_dir()))
	_import_images_button = ManagerUi.button("匯入圖片…")
	_import_images_button.tooltip_text = tr("選一張或多張圖片,當成一個動作的幀(單張圖 = 單幀動作)。動作已存在時會問你覆蓋還是新增。")
	_import_images_button.pressed.connect(_on_import_images_pressed)
	_import_sheet_button = ManagerUi.button("匯入精靈圖…")
	_import_sheet_button.tooltip_text = tr("選一張精靈圖(一張圖裡排了很多幀),設定格線後切成一個動作的幀。切片只是引用區域,不會另外產生圖檔。")
	_import_sheet_button.pressed.connect(_on_import_sheet_pressed)
	_replace_sheet_button = ManagerUi.button("換精靈圖…")
	_replace_sheet_button.tooltip_text = tr("用一張新的圖取代正在使用的精靈圖:切片範圍、每一幀的軸心與偏移、動作與播放速度都原封不動,只有圖換掉(新圖尺寸要和原本一樣)。")
	_replace_sheet_button.pressed.connect(_on_replace_sheet_pressed)
	_save_as_button = ManagerUi.button("另存為新素材包…")
	_save_as_button.tooltip_text = tr("把目前的素材包(含還沒存檔的編輯)複製到一個新的空資料夾,之後編輯的就是新的那個。搭配「換精靈圖」可以把設定好的素材包當範本,快速做出新角色。")
	_save_as_button.pressed.connect(_on_save_as_pressed)
	_export_frames_button = ManagerUi.button("匯出獨立圖檔…")
	_export_frames_button.tooltip_text = tr("把每個動作的每一幀存成一張張 PNG(<動作>_<編號>.png,已套用切片與裁切翻轉旋轉),另附 frames.json 記錄播放速度、軸心與偏移。可以拿去別的工具用,或當備份。")
	_export_frames_button.pressed.connect(_on_export_frames_pressed)
	_clean_button = ManagerUi.button("清理未使用檔案…")
	_clean_button.tooltip_text = tr("找出匯入時複製進素材包、但已經沒有任何動作或配件在用的圖檔,確認後搬到備份資料夾(不直接刪)。也可以挑一個有自己實體檔案的動作(不是精靈圖切片),整個清掉它的圖。")
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
	_action_list.tooltip_text = tr("所有系統動作(idle、walk…)都有一個槽,沒有素材的顯示「空」;選一個空槽再匯入圖片,就會放進那個動作。「代號 ← 名稱」表示素材包裡叫那個名稱的動作填在這個槽。")
	_action_list.item_selected.connect(_on_action_row_selected)
	left.add_child(_action_list)
	_add_action_button = ManagerUi.button("＋新增自訂動作…")
	_add_action_button.tooltip_text = tr("新增一個自訂動作槽(名字會出現在網頁編輯器的動作下拉選單)。新增後選它,再匯入圖片或精靈圖放進第一批幀。")
	_add_action_button.pressed.connect(_on_add_action_pressed)
	left.add_child(_add_action_button)
	left.add_child(_build_action_source_row())
	left.add_child(_build_direction_row())
	left.add_child(_build_sync_row())
	left.add_child(ManagerUi.heading("幀(可複選)"))
	left.add_child(_build_frame_buttons())
	_frame_list = ItemList.new()
	_frame_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame_list.custom_minimum_size.y = 90
	_frame_list.icon_mode = ItemList.ICON_MODE_TOP
	_frame_list.max_columns = 0
	_frame_list.fixed_icon_size = THUMB_SIZE
	_frame_list.select_mode = ItemList.SELECT_MULTI
	_frame_list.tooltip_text = tr("點選一幀;Ctrl+點 加選、Shift+點 選一段。複製、貼上到別的動作、複製一份、刪除、前後移動、圖片處理都對選取的所有幀動作。")
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
	label.text = tr("動作共用")
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


## 「朝向版本」(2026-10-15):同一個動作可以另外畫朝左/朝右專用的版本(動作名稱後面接 _left / _right),桌寵朝那一邊時改播它、不鏡像;
## 沒畫的那一邊照舊把預設版本鏡像。切到還沒畫的版本會停在空槽,用「匯入圖片…」放圖,或按「複製並左右翻轉」從預設版本開始改。
func _build_direction_row() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = tr("朝向版本")
	label.custom_minimum_size.x = ManagerUi.LABEL_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_direction_option = OptionButton.new()
	_direction_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_direction_option.add_item(tr("預設(另一邊自動鏡像)"))
	_direction_option.add_item(tr("朝左專用"))
	_direction_option.add_item(tr("朝右專用"))
	_direction_option.item_selected.connect(_on_direction_selected)
	row.add_child(_direction_option)
	row.add_child(ManagerUi.info_icon("想讓角色往左、往右時長得不一樣(不是單純左右翻轉),就為動作另外畫「朝左專用」或「朝右專用」的版本:桌寵面向那一邊時改播這組圖,而且不鏡像。沒畫的那一邊照舊用預設版本鏡像,所以通常只要補其中一邊。朝向版本是一個名字後面接 _left / _right 的動作(例如 walk_left),播放速度、循環方式沒另外設定時沿用預設版本的;配件與光源的位置沒另外設定時,沿用預設版本並左右翻過來。"))
	box.add_child(row)
	_direction_mirror = ManagerUi.button("複製預設版本並左右翻轉")
	_direction_mirror.tooltip_text = tr("把預設版本的所有幀複製到這個朝向版本並左右翻轉(軸心、圖片偏移跟著翻;圖層與光源的位置也左右翻過來、圖層的圖跟著鏡像,逐幀顯示設定照抄),再拿來改成這一邊專屬的樣子。可以撤回。")
	_direction_mirror.pressed.connect(_create_mirrored_direction)
	box.add_child(_direction_mirror)
	_direction_row = box
	return box


## 「同步到其他動作」(2026-10-15,見 PackFrameSync):打開之後,在這個動作裡的裁切、軸心、偏移、光源與圖層逐幀設定,
## 會跟著帶到其他動作裡用同一張原圖的幀(那些幀自己改過的值不會被蓋掉,也不會反過來影響這個動作)。
func _build_sync_row() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	_sync_check = CheckBox.new()
	_sync_check.text = tr("同步到其他動作")
	_sync_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sync_check.toggled.connect(_on_sync_toggled)
	row.add_child(_sync_check)
	row.add_child(ManagerUi.info_icon("適合「先把圖匯入一個沒在用的動作,在那裡統一裁切、對軸,再複製貼到各個動作」的做法。打開後,之後在這個動作裡做的調整,會跟著帶到其他動作裡用同一張原圖的幀:圖片處理(裁切翻轉旋轉)、軸心、圖片偏移、每盞光源在那一幀的位置/半徑/亮度/顏色/熄燈,以及每個圖層在那一幀的錨點與逐幀顯示。\n・只帶「之後的改動」,而且只帶給還沒自己改過的幀:其他動作自己改過的值、自己加的光源與圖層設定都不會被蓋掉,也永遠不會反過來影響這個動作。\n・打開之前就有的差異,用「立刻全部同步一次」把其他動作直接改成跟這裡一樣。\n・同一張原圖 = 同一個圖檔(精靈圖則是同一格),不管有沒有裁切過。動作清單上有 🔗 的就是打開同步的動作。"))
	box.add_child(row)
	_sync_push = ManagerUi.button("立刻全部同步一次")
	_sync_push.tooltip_text = tr("不管之前的狀態,把其他動作裡用同一張原圖的幀,直接改成跟這個動作一樣(只改真的不一樣的值)。可以撤回。")
	_sync_push.pressed.connect(_push_sync)
	box.add_child(_sync_push)
	_sync_row = box
	return box


func _sync_sync_widgets() -> void:
	if _sync_row == null:
		return
	var real := _model.has_pack() and _action != "" and _model.action_names().has(_action)
	_sync_row.visible = real
	if not real:
		return
	_updating = true
	_sync_check.button_pressed = _model.is_sync_source(_action)
	_updating = false
	_sync_push.visible = _sync_check.button_pressed


func _on_sync_toggled(on: bool) -> void:
	if _updating or _action == "" or not _model.has_pack():
		return
	_model.checkpoint()
	_model.set_sync_source(_action, on)
	_sync_push.visible = on
	_rebuild_action_list()
	_select_current_row()
	_status.text = tr("「%s」打開同步:之後在這裡的調整會帶到其他動作裡用同一張原圖的幀。") % _action if on else tr("「%s」關掉同步。") % _action
	_refresh_frame_labels_only()


func _push_sync() -> void:
	if _action == "" or not _model.is_sync_source(_action):
		return
	_model.checkpoint()
	var result := _model.push_sync(_action)
	_after_sync(result)
	_status.text = tr("已把「%s」的設定同步到其他動作(%d 幀;可以撤回)") % [_action, int(result["frames"])] if int(result["frames"]) > 0 else tr("其他動作裡用同一張原圖的幀本來就跟這裡一樣")
	_refresh_frame_labels_only()


## 同步改了光源/圖層的話,編輯器手上的複本要重讀,不然下一次修改會把同步的結果蓋回去。
func _after_sync(result: Dictionary) -> void:
	if bool(result["objects"]):
		_refresh_lights()
		_refresh_accessories()
	if int(result["frames"]) > 0:
		_refresh_frame_labels_only()


func _sync_mark(action_name: String) -> String:
	return " 🔗" if _model.is_sync_source(action_name) else ""


func _direction_index(name: String) -> int:
	if name.ends_with("_left") and SpritePackLoader.plain_action(name) != name:
		return 1
	if name.ends_with("_right") and SpritePackLoader.plain_action(name) != name:
		return 2
	return 0


func _sync_direction_widgets() -> void:
	if _direction_row == null:
		return
	var current := _slot if _slot != "" else _action
	_direction_row.visible = _model.has_pack() and not _in_item_mode() and current != ""
	if not _direction_row.visible:
		return
	var index := _direction_index(current)
	_updating = true
	_direction_option.select(index)
	_updating = false
	var plain := SpritePackLoader.plain_action(current)
	_direction_mirror.visible = index != 0 and not _model.action_names().has(current)
	_direction_mirror.disabled = _default_action_of(plain) == ""


## 預設版本實際用的素材包動作(系統動作槽可能借別的名字的動作,例如 idle ← stand);沒有回空字串。
func _default_action_of(plain: String) -> String:
	var source := str(_model.slot_sources().get(plain, ""))
	if source != "":
		return source
	return plain if _model.action_names().has(plain) else ""


func _on_direction_selected(index: int) -> void:
	if _updating or not _model.has_pack():
		return
	var plain := SpritePackLoader.plain_action(_slot if _slot != "" else _action)
	var target: String = plain if index == 0 else "%s_%s" % [plain, SpritePackLoader.DIRECTIONS[index - 1]]
	if index == 0:
		var source := _default_action_of(plain)
		_slot = plain
		if source != "":
			_select_action(source)
		else:
			_select_empty_slot(plain)
		return
	if _model.action_names().has(target):
		_slot = target
		_select_action(target)
		return
	if not _extra_slots.has(target):
		_extra_slots.append(target)
	_rebuild_action_list()
	_select_empty_slot(target)
	_select_current_row()
	_status.text = tr("「%s」還沒有%s的版本:用「匯入圖片…」放圖,或按「複製預設版本並左右翻轉」從預設版本開始改。沒畫的話這一邊照舊用預設版本鏡像。") % [plain, tr("朝左專用") if index == 1 else tr("朝右專用")]


func _create_mirrored_direction() -> void:
	var target := _slot
	var plain := SpritePackLoader.plain_action(target)
	var error := _model.create_mirrored_copy(_default_action_of(plain), target)
	if error != "":
		_status.text = tr(error)
		return
	_slot = target
	_reload_lists()
	_select_action(target)
	_after_edit(tr("已從預設版本複製並左右翻轉,建立「%s」") % target)


## 依 _slot 重新填「動作共用」下拉選單:只有系統動作槽(ALIASES 有的)才顯示。
func _sync_action_source_widgets() -> void:
	_sync_direction_widgets()
	_sync_sync_widgets()
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
	_fps_spin.tooltip_text = tr("這個動作的播放速度(每秒幾幀),存進 pack.json 的 fps_by_action;預覽動畫也用這個速度。")
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


## 幀清單上方的按鈕:複製 / 貼上 / 複製一份 / 刪除 / 前移 / 後移 / 更換圖片(2026-10-16 改成圖示按鈕,名稱與快捷鍵見 tooltip)。
func _build_frame_buttons() -> Control:
	var grid := HFlowContainer.new()
	var specs := [
		["📋", "複製(Ctrl+C):複製選取的幀(連同各自的軸心、圖片偏移,以及圖層與光源在這幾幀的設定)", _copy_selected],
		["📥", "貼上(Ctrl+V):貼在選取的幀後面(沒選取就接在最後);可以先切到別的動作再貼", _paste],
		["📑", "複製一份(Ctrl+D):把選取的幀原地複製一份,接在後面", _duplicate_selected],
		["🗑", "刪除(Delete):刪掉選取的幀(至少要留一幀)", _delete_selected],
		["◀", "前移(Alt+←):選取的幀往前移一格", _move_selected.bind(-1)],
		["▶", "後移(Alt+→):選取的幀往後移一格", _move_selected.bind(1)],
		["🔄", "更換圖片:把選取的幀換成別的圖檔(選幾張就依序換幾張),圖片處理(裁切翻轉旋轉)、軸心、圖片偏移都保留——用同一套模板做不同角色、或重畫某幾張時,不用重新裁切對軸。\n這個動作打開了「同步到其他動作」的話,其他動作裡用同一張原圖的幀也會一起換。", _ask_replace_frames],
	]
	for spec: Array in specs:
		var button := ManagerUi.button(spec[0])
		button.tooltip_text = tr(spec[1])
		button.pressed.connect(spec[2])
		grid.add_child(button)
		_frame_buttons.append(button)
		if spec[2] == _paste:
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
	_canvas.locked_accessory_touched.connect(func(_index: int) -> void: _status.text = PackLayers.lock_hint())
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
	_right_tabs.tooltip_text = tr("功能頁籤:編輯(軸心、圖片偏移)、圖片(翻轉旋轉裁切)、判定框、光源、配件、圖層。")
	column.add_child(_right_tabs)
	var right := _new_tab("編輯")
	_mode_option = OptionButton.new()
	_mode_option.add_item(tr("移動視角畫面"))
	_mode_option.add_item(tr("移動軸心(腳底線 / 中心點)"))
	_mode_option.add_item(tr("移動圖片"))
	_mode_option.add_item(tr("調整判定框"))
	_mode_option.add_item(tr("裁切圖片"))
	_mode_option.add_item(tr("調整光源錨點"))
	_mode_option.add_item(tr("調整配件位置"))
	_mode_option.tooltip_text = tr("移動視角畫面:左鍵拖曳平移畫面,不會改到任何資料(預設;中鍵、右鍵拖曳也可以平移)。\n移動軸心:改「圖片上哪一點是腳底」,判定框與坐下都以它為準;圖層與光源會跟著圖片一起移動(位置看起來不變)。\n移動圖片:軸心(腳底線、坐下判定、配件錨點)不動,只有圖片相對它平移。\n調整判定框:拖曳綠框的邊或角改大小,拖曳框裡面移動(整個素材包共用一個)。\n裁切圖片:在畫布上拖出要保留的範圍,再按「套用裁切」。\n調整光源錨點:拖曳畫布上的光源圓點(或用方向鍵)改位置,光的大小、亮度、顏色在右邊「光源」區。")
	_mode_option.item_selected.connect(_on_mode_selected)
	right.add_child(ManagerUi.labeled("模式", _mode_option))
	_scope_option = OptionButton.new()
	_scope_option.add_item(tr("只有這一幀"))
	_scope_option.add_item(tr("整個動作(所有幀共用)"))
	_scope_option.tooltip_text = tr("軸心與圖片偏移的改動要寫給這一幀,還是整個動作共用一個值(會清掉這個動作底下逐幀的舊設定)。")
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
		_after_pivot_edit()
		_after_edit(tr("已套用到「%s」的所有幀") % _action))
	right.add_child(apply_all)
	var reset := ManagerUi.button("重設(自動軸心、偏移 0)")
	reset.pressed.connect(func() -> void:
		if _action == "":
			return
		_model.checkpoint()
		_model.reset(_action, _index, _scope_option.selected == 1)
		_after_pivot_edit()
		_refresh_frame()
		_after_edit("已重設"))
	right.add_child(reset)
	var history_row := HBoxContainer.new()
	_undo_button = ManagerUi.button("↶ 撤回")
	_undo_button.tooltip_text = tr("Ctrl+Z(最多 %d 步)") % PackEditorModel.UNDO_LIMIT
	_undo_button.pressed.connect(_undo)
	_redo_button = ManagerUi.button("↷ 重做")
	_redo_button.tooltip_text = tr("Ctrl+Y 或 Ctrl+Shift+Z")
	_redo_button.pressed.connect(_redo)
	history_row.add_child(_undo_button)
	history_row.add_child(_redo_button)
	right.add_child(history_row)
	# 圖片朝向(2026-10-15 使用者要求:預設朝向在精靈圖編輯器就設定好,不必每隻桌寵放出來後再用右鍵「鏡像翻轉」調)。
	_facing_panel = VBoxContainer.new()
	_facing_panel.add_child(HSeparator.new())
	_facing_option = OptionButton.new()
	_facing_option.add_item(tr("朝右"))
	_facing_option.add_item(tr("朝左"))
	_facing_option.item_selected.connect(_edit_facing)
	var facing_row := ManagerUi.labeled("圖片裡角色面向", _facing_option)
	facing_row.add_child(InfoIcon.new("整個素材包共用:圖片裡的角色原本是朝哪邊畫的。桌寵往左右走時靠它決定要不要鏡像,選錯的話桌寵會倒退走。存檔後,桌面上這個角色的桌寵會跟著轉過來(各自用右鍵「鏡像翻轉」調過的也一起換邊)。"))
	_facing_panel.add_child(facing_row)
	right.add_child(_facing_panel)
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
	# 家具的坐/躺位置:自己一個頁籤(2026-10-15 家具也有圖層之後,不再借「圖層」頁);跟圖層共用「調整配件位置」模式,
	# 畫布上拖的是哪一種看目前停在哪個頁籤(見 _seat_editing)。
	_furn_anchor_tab_panel = _new_tab("坐躺位置")
	_build_furniture_anchor_section(_furn_anchor_tab_panel)
	_right_tabs.tab_changed.connect(func(_tab: int) -> void:
		if _furniture_id != "":
			_push_canvas_accessories())
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
	# 2026-10-18 使用者要求:顯示選項越來越多,收進「預覽視圖設定」按鈕的小視窗(殘影、光源、圖層、判定框、腳底線、中心線)。
	var view_button := ManagerUi.button("預覽視圖設定…")
	var view_popup := PopupPanel.new()
	var view_box := VBoxContainer.new()
	view_box.add_theme_constant_override("separation", 4)
	view_popup.add_child(view_box)
	view_button.add_child(view_popup)
	_view_checks = {}
	for entry: Array in [["show_ghost", "顯示上一幀殘影(對齊用)"], ["show_lights", "顯示光源"], ["show_layers", "顯示圖層"], ["show_hitbox", "顯示判定框"],
			["show_foot_line", "顯示腳底線(移動軸心模式一律顯示)"], ["show_center_line", "顯示中心線(移動軸心模式一律顯示)"]]:
		var property: String = entry[0]
		var check := CheckBox.new()
		check.text = tr(entry[1])
		check.button_pressed = bool(_canvas.get(property))
		check.toggled.connect(func(on: bool) -> void:
			_canvas.set(property, on)
			_canvas.queue_redraw())
		view_box.add_child(check)
		_view_checks[property] = check
	_ghost_check = _view_checks["show_ghost"]
	view_button.pressed.connect(func() -> void:
		view_popup.popup(Rect2i(Vector2i(view_button.get_screen_position()) + Vector2i(0, int(view_button.size.y)), Vector2i(0, 0))))
	right.add_child(view_button)
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
	_right_tabs.set_tab_hidden(_right_tabs.get_tab_idx_from_control(_tab_scrolls["坐躺位置"]), _furniture_id == "")
	if _right_tabs.is_tab_hidden(_right_tabs.current_tab):
		_right_tabs.current_tab = 0


## 依畫布的編輯模式跳到對應的頁籤(調整光源錨點 → 光源、調整配件位置 → 配件)。
func _show_tab_for_mode(index: int) -> void:
	if index == 6 and _seat_editing():
		return   # 家具停在「坐躺位置」頁:拖的是坐躺位置,留在這頁
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
	flip_h.tooltip_text = tr("左右對調。再按一次就翻回來。")
	flip_h.pressed.connect(func() -> void: _apply_fx_op({"op": "h"}, "已水平翻轉"))
	var flip_v := ManagerUi.button("↕ 垂直翻轉")
	flip_v.tooltip_text = tr("上下對調。再按一次就翻回來。")
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
	_rotate_spin.tooltip_text = tr("順時針旋轉的角度(負數 = 逆時針)。90 的倍數是無損的;其他角度畫布會放大到裝得下整張圖,空白處透明。")
	var rotate_button := ManagerUi.button("↻ 旋轉")
	rotate_button.pressed.connect(func() -> void:
		if is_zero_approx(_rotate_spin.value):
			_status.text = tr("旋轉角度是 0,什麼都不會改變")
			return
		_apply_fx_op({"op": "r", "degrees": _rotate_spin.value}, tr("已旋轉 %s°") % _zoom_text(_rotate_spin.value)))
	rotate_row.add_child(_rotate_spin)
	rotate_row.add_child(rotate_button)
	right.add_child(rotate_row)
	right.add_child(ManagerUi.hint_row("裁切範圍(圖片像素)", "切到「裁切圖片」模式在畫布上拖曳畫出要保留的範圍,或直接填下面的數字(左、上、寬、高),再按「套用裁切」(裁切模式下按 Enter 也可以)。裁切模式會顯示還沒裁的整張圖,黃線是目前的裁切範圍:抓住黃線的邊或角拖曳可以調整,往外拉就能把裁掉的部分拿回來(「把圖片處理寫進檔案」之前都可以),角色位置不會跑掉。座標是還沒裁的整張圖的像素。"))
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
	crop_apply.tooltip_text = tr("把選取的幀都裁成這個範圍(超出圖片的部分截掉)。裁切模式下按 Enter 也可以。")
	crop_apply.pressed.connect(_apply_crop)
	var crop_clear := ManagerUi.button("框選整張圖")
	crop_clear.tooltip_text = tr("裁切框拉回整張圖(還沒裁的原樣);再按「套用裁切」= 拿掉這幾幀的裁切,位置不變。")
	crop_clear.pressed.connect(func() -> void:
		_set_crop_ui(Rect2i(0, 0, int((_crop_spins[2] as SpinBox).max_value), int((_crop_spins[3] as SpinBox).max_value))))
	crop_row.add_child(crop_apply)
	crop_row.add_child(crop_clear)
	right.add_child(crop_row)
	var trim_row := HFlowContainer.new()
	var trim := ManagerUi.button("自動裁掉透明邊")
	trim.tooltip_text = tr("把選取的幀裁掉四周沒畫東西的透明部分。角色在畫面上的位置不會變:會先把目前的軸心固定下來,而且軸心那一點一定留在範圍裡(所以腳底下的空白通常會留著)。裁掉的部分不算進素材包的像素上限。可以撤回。")
	trim.pressed.connect(_auto_trim_frames)
	_trim_shared = CheckBox.new()
	_trim_shared.text = tr("選取的幀用同一個範圍")
	_trim_shared.button_pressed = true
	_trim_shared.tooltip_text = tr("勾選(建議):把選取的幀疊在一起,找出所有幀合起來有畫東西的範圍,全部裁成一樣大——角色在動畫裡晃來晃去也不會被切到,幀的大小也一致、好對齊。\n取消:每一幀各自裁到自己有畫東西的範圍(省下最多像素,位置一樣不會變)。")
	trim_row.add_child(trim)
	trim_row.add_child(_trim_shared)
	_trim_recover = CheckBox.new()
	_trim_recover.text = tr("拿回之前裁掉的部分")
	_trim_recover.tooltip_text = tr("勾選:在還沒裁的原圖上重新找有畫東西的範圍,之前裁切不小心切到的部分會一起拿回來(範圍可能變大)。\n原圖上有不想要的東西(例如故意裁掉的特效)就不要勾。已經「寫進檔案」的裁切拿不回來。")
	trim_row.add_child(_trim_recover)
	right.add_child(trim_row)
	_fx_label = Label.new()
	_fx_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fx_label.theme_type_variation = AppSettings.WARN_LABEL
	right.add_child(_fx_label)
	var fx_clear := ManagerUi.button("還原圖片處理(回到原圖)")
	fx_clear.tooltip_text = tr("拿掉選取的幀的所有裁切、翻轉、旋轉。這些幀手動設定過的軸心是相對處理後的圖,會一併回到自動軸心。")
	fx_clear.pressed.connect(_clear_fx)
	right.add_child(fx_clear)
	var bake := ManagerUi.button("把圖片處理寫進檔案…")
	bake.tooltip_text = tr("整個素材包裡有圖片處理(裁切翻轉旋轉)的幀,把處理後的樣子各存成一張新圖,幀改成直接用新圖。畫面上完全不變;精靈圖切出來的幀也會變成一張張的圖。好處是素材資料夾、匯出的 .pet 變小,載入也比較快(像素上限本來就只算裁切後的大小)。原圖不會被刪,之後用「清理未使用檔案」收掉。")
	bake.pressed.connect(_confirm_bake)
	right.add_child(bake)
	_fx_buttons = [flip_h, flip_v, rotate_button, crop_apply, crop_clear, trim, fx_clear, bake]


func _on_mode_selected(index: int) -> void:
	_canvas.mode = [PackFrameCanvas.Mode.VIEW, PackFrameCanvas.Mode.PIVOT, PackFrameCanvas.Mode.IMAGE, PackFrameCanvas.Mode.HITBOX, PackFrameCanvas.Mode.CROP, PackFrameCanvas.Mode.LIGHT, PackFrameCanvas.Mode.ACCESSORY][index]
	_canvas.queue_redraw()
	if _model.has_pack():
		_refresh_frame()   # 進出裁切模式:換成還沒裁的底圖 / 換回裁過的圖
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
	# 原圖被直接換成大小不同的新圖、剛自動重新對位過:提醒檢查後存檔(見 PackSourceSizes)
	_status.text = _model.realign_notice if _model.realign_notice != "" else tr(message)
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
	_guard_dialog.title = tr("有未存的變更")
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
	dialog.import_confirmed.connect(func(params: Dictionary) -> void:
		var action := SpritePackLoader.clean_action_name(params["action"])
		var before := _model.frame_count(action) if params["mode"] == "append" else 0
		var error := _model.import_sheet(path, params["grid"], params["action"], params["mode"])
		_do_import(error, params["action"])
		if error == "":
			_ask_split_sheet(action, range(before, _model.frame_count(action))))
	_finish_dialog(dialog)
	return dialog


## 匯入精靈圖後(2026-10-19 使用者要求):問要不要把切出來的幀各存成一張圖(見 PackEditorModel.bake_fx)。
## 不切 = 照舊引用整張精靈圖的區域,之後也能用「把圖片處理寫進檔案」再切。回傳確認視窗(給測試用)。
func _ask_split_sheet(action: String, indices: Array) -> ConfirmationDialog:
	if indices.is_empty():
		return null
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("切成一張張的圖?")
	dialog.ok_button_text = "切成一張張的圖"
	dialog.cancel_button_text = "先不要"
	dialog.theme = ManagerUi.make_theme()
	dialog.dialog_autowrap = true
	dialog.dialog_text = tr("精靈圖切出了 %d 幀。要把每一幀各存成一張圖嗎?\n\n・切:素材資料夾、匯出的 .pet 只留用得到的部分(精靈圖上沒用到的空白、多餘的格子不會帶著走),存檔後可以用「清理未使用檔案」收掉整張精靈圖。\n・先不要:幀照舊引用整張精靈圖,之後也能用「把圖片處理寫進檔案」再切。\n畫面上看起來都一樣,可以撤回。") % indices.size()
	dialog.confirmed.connect(func() -> void: _split_sheet(action, indices))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(500, 300))
	return dialog


func _split_sheet(action: String, indices: Array) -> void:
	_model.checkpoint()
	var result := _model.bake_fx(action, indices)
	if str(result["error"]) != "":
		_model.undo()
		_reload_lists()
		_refresh_all()
		_status.text = tr("沒有切開:%s") % str(result["error"])
		return
	_reload_lists()
	_refresh_all()
	_after_edit(tr("已把 %d 幀切成 %d 張圖(可以撤回)。存檔後可以用「清理未使用檔案」收掉用不到的精靈圖。") % [int(result["frames"]), int(result["files"])])


func _finish_dialog(dialog: PackImportDialog) -> void:
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(540, 640) if dialog.title == tr("匯入精靈圖") else Vector2i(540, 220))


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
		mode.add_item(tr("觸發時播放"))
		mode.add_item(tr("循環播放"))
		var count := ManagerUi.spin(1.0, 1.0, PropDef.MAX_STATE_COUNT)
		count.suffix = tr(" 次")
		count.tooltip_text = tr("觸發式才用")
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
	open_library.tooltip_text = tr("去家具庫視窗改名稱、觸發方式(時段/動作代號)、標籤、縮放倍率、放上桌面。")
	open_library.pressed.connect(func() -> void: furniture_settings_requested.emit())
	panel.add_child(open_library)
	_furn_no_anchor_warning = Label.new()
	_furn_no_anchor_warning.theme_type_variation = AppSettings.WARN_LABEL
	_furn_no_anchor_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_furn_no_anchor_warning.text = tr("⚠ 這件家具還沒有坐/躺位置(去「坐躺位置」頁加),桌寵沒辦法用它坐下或躺下。")
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
		_furn_anchor_type.add_item(tr("坐") if kind == "sit" else tr("躺"))
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
		_furn_anchor_facing.add_item({"both": tr("兩者(隨機擇一)"), "left": tr("左"), "right": tr("右")}[facing])
		_furn_anchor_facing.set_item_metadata(_furn_anchor_facing.item_count - 1, facing)
	_furn_anchor_facing.item_selected.connect(func(_i: int) -> void: _edit_furn_anchor_facing())
	var facing_row := ManagerUi.labeled("使用時面向", _furn_anchor_facing)
	facing_row.add_child(InfoIcon.new("桌寵坐/躺到這個錨點時要面向哪邊。「兩者」是預設值,每次使用時隨機選一個方向(不是使用中途左右來回切換);選「左」或「右」會固定面向那一邊。"))
	right.add_child(facing_row)
	_furn_anchor_hide = CheckBox.new()
	_furn_anchor_hide.text = tr("使用時隱藏桌寵")
	_furn_anchor_hide.toggled.connect(func(on: bool) -> void:
		if _updating or _furniture_def == null or _furn_anchor_index < 0 or _furn_anchor_index >= _furniture_def.anchors.size():
			return
		if on:
			_furniture_def.anchors[_furn_anchor_index]["hide_pet"] = true
		else:
			(_furniture_def.anchors[_furn_anchor_index] as Dictionary).erase("hide_pet")
		_save_furniture())
	var hide_row := HBoxContainer.new()
	hide_row.add_child(_furn_anchor_hide)
	hide_row.add_child(InfoIcon.new("桌寵坐/躺定位到這個位置後整隻不畫,畫面上只剩家具(和家具的圖層)——例如鑽進被窩、躲進紙箱。搭配「圖層」頁的「誰在用時顯示」,就能換成那隻桌寵專屬的樣子。\n藏起來的桌寵照樣點得到、拖得走,拖走就結束使用、重新出現。"))
	right.add_child(hide_row)


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
	_furn_light_frame_unlock.text = tr("單獨調整此幀")
	_furn_light_frame_unlock.tooltip_text = tr("第 0 幀(或還沒解鎖的幀)的半徑/亮度/顏色/是否亮著都跟著這盞燈的預設值(或動作槽的判斷)走。勾選這裡才能單獨改目前這一幀,不影響其他幀;取消勾選會清掉這一幀的所有覆蓋。「是否亮著」比較特別:單獨調整過可以雙向覆蓋動作槽原本的判斷——即使動作槽判斷這一幀該暗,解鎖後還是可以單獨打開,反之亦然。")
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
	_furn_light_frame_enabled.text = tr("亮著(單獨調整此幀時生效)")
	_furn_light_frame_enabled.tooltip_text = tr("只有勾選「單獨調整此幀」時才能改;決定這一幀要不要亮,雙向覆蓋動作槽原本的判斷。")
	_furn_light_frame_enabled.toggled.connect(func(on: bool) -> void: _edit_furn_light_scoped("enabled", on))
	right.add_child(_furn_light_frame_enabled)
	_furn_light_shape = OptionButton.new()
	for kind: String in FurnitureDef.LIGHT_SHAPES:
		_furn_light_shape.add_item(tr("圓形") if kind == "radial" else tr("扇形"))
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
	_furn_above_light.text = tr("貼圖蓋在光暈之上(預設光暈疊在貼圖上面)")
	_furn_above_light.toggled.connect(func(on: bool) -> void:
		if _updating or _furniture_def == null:
			return
		_furniture_def.above_light = on
		_save_furniture())
	right.add_child(_furn_above_light)
	_furn_render_above_ui = CheckBox.new()
	_furn_render_above_ui.text = tr("顯示在桌寵與對話氣泡之上")
	_furn_render_above_ui.tooltip_text = tr("平時家具會被桌寵、對話氣泡蓋住;勾選後改畫在最上層,協助自製 UI(例如當成一塊固定貼在畫面上的相框/邊框)。編輯模式拖曳、光源、坐躺、容器都不受影響,純粹只是換一個畫面圖層。")
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


## 「圖片裡角色面向」改了:寫進 pack.json 的 facing(可撤回)。
func _edit_facing(index: int) -> void:
	if _updating or not _model.has_pack():
		return
	_model.checkpoint()
	_model.set_facing_left(index == 1)
	_after_edit(tr("已設定圖片裡的角色朝左") if index == 1 else tr("已設定圖片裡的角色朝右"))


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
	mode_option.add_item(tr("不啟用"))
	mode_option.add_item(tr("一直啟用"))
	mode_option.add_item(tr("指定幀範圍啟用"))
	mode_option.item_selected.connect(func(i: int) -> void:
		_edit_furn_light_slot(slot_name, "mode", FurnitureDef.LIGHT_SLOT_MODES[i])
		_sync_furn_light_slot_visibility(slot_name))
	right.add_child(ManagerUi.labeled(tr(str(SLOT_LABELS.get(slot_name, slot_name))), mode_option))
	_furn_light_slot_mode[slot_name] = mode_option
	var frame_row := HFlowContainer.new()   # 兩組「標籤 + 數字框」放不下右欄的寬度就折成兩列
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
	_furn_anchor_hide.button_pressed = bool(anchor.get("hide_pet", false))
	_furn_anchor_hide.disabled = not has_anchor
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
	_push_canvas_accessories()


## 編輯家具、而且停在「坐躺位置」頁:畫布的「調整配件位置」拖的是坐躺位置,不是圖層。
func _seat_editing() -> bool:
	return _furniture_id != "" and _right_tabs != null and _tab_scrolls.has("坐躺位置") and _right_tabs.current_tab == _right_tabs.get_tab_idx_from_control(_tab_scrolls["坐躺位置"])


## 畫布上的「配件」:平常是圖層;家具停在「坐躺位置」頁時換成坐躺位置的標記。
func _push_canvas_accessories() -> void:
	if _canvas == null:
		return
	if _seat_editing():
		_canvas.set_accessories(_furniture_accessory_previews(), _furn_anchor_index)
		_canvas.set_backdrop(_accessory_preview())   # 圖層照樣畫出來對照,但不能選、不能拖
	else:
		_canvas.set_accessories(_accessory_preview(), _acc_index)
		_canvas.set_backdrop([] as Array[Dictionary])


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
	_char_layer_panel.visible = _prop_id == ""   # 家具也有圖層(2026-10-15)
	_furn_user_box.visible = _furniture_id != ""
	_refresh_furn_user_widgets()
	_facing_panel.visible = not item_mode
	_updating = true
	_facing_option.select(1 if _model.has_pack() and _model.facing_left() else 0)
	_facing_option.disabled = not _model.has_pack()
	_updating = false
	_furn_light_tab_panel.visible = _furniture_id != ""
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
	_model.furniture_def = def   # 幀的移動/複製/刪除/貼上時家具燈的逐幀設定跟著搬
	_model.furniture_saver = func() -> void:
		_save_furniture()
		_refresh_furniture_lights()
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
				_action_list.add_item("%s(%d)%s" % [_item_state_label(state), count, _sync_mark(state)])
				_action_rows.append({"action": state, "slot": state})
			else:
				_action_list.add_item(tr("%s(空)") % _item_state_label(state))
				_action_list.set_item_custom_fg_color(_action_list.item_count - 1, ManagerUi.muted_color(_action_list))
				_action_rows.append({"action": "", "slot": state})
		return
	var sources := _model.slot_sources()
	var used: Dictionary = {}
	var still_empty: Array[String] = []
	for extra in _extra_slots:
		if not _model.action_names().has(extra):
			still_empty.append(extra)
	_extra_slots = still_empty
	# 朝向版本(walk_left…)排在原動作底下(見 _add_direction_rows),不另外列在自訂動作裡。
	var nested: Dictionary = {}
	for slot: String in SpritePackLoader.ALIASES:
		var source := str(sources.get(slot, ""))
		if source != "":
			used[source] = true
			var text := "%s(%d)" % [slot, _model.frame_count(source)] if source == slot else "%s ← %s(%d)" % [slot, source, _model.frame_count(source)]
			_action_list.add_item(text + _sync_mark(source))
			_action_rows.append({"action": source, "slot": slot})
		else:
			_action_list.add_item(tr("%s(空)") % slot)
			_action_list.set_item_custom_fg_color(_action_list.item_count - 1, ManagerUi.muted_color(_action_list))
			_action_rows.append({"action": "", "slot": slot})
		_add_direction_rows(slot, nested)
	var others: Array[String] = []
	for action_name in _model.action_names():
		if not used.has(action_name) and not nested.has(action_name) and not _is_nested_direction(action_name):
			others.append(action_name)
	var extras: Array[String] = []
	for extra in _extra_slots:
		if not nested.has(extra) and not _is_nested_direction(extra):
			extras.append(extra)
	if not others.is_empty() or not extras.is_empty():
		_action_list.add_item(tr("── 自訂動作 ──"))
		_action_list.set_item_disabled(_action_list.item_count - 1, true)
		_action_rows.append({"action": "", "slot": "", "header": true})
		for action_name in others:
			_action_list.add_item("%s(%d)%s" % [action_name, _model.frame_count(action_name), _sync_mark(action_name)])
			_action_rows.append({"action": action_name, "slot": action_name})
			_add_direction_rows(action_name, nested)
		for extra in extras:
			_action_list.add_item(tr("%s(空)") % extra)
			_action_list.set_item_custom_fg_color(_action_list.item_count - 1, ManagerUi.muted_color(_action_list))
			_action_rows.append({"action": "", "slot": extra})
			_add_direction_rows(extra, nested)


## 名稱是某個動作的朝向版本、而且原動作在清單裡(系統動作槽、素材包的動作或新增的空槽):會排在原動作底下。
func _is_nested_direction(name: String) -> bool:
	var plain := SpritePackLoader.plain_action(name)
	return plain != name and (SpritePackLoader.ALIASES.has(plain) or _model.action_names().has(plain) or _extra_slots.has(plain))


## 在原動作那一列底下加上它已經有的朝向版本(有幀的,或剛切過去、還空著的)。
func _add_direction_rows(plain: String, nested: Dictionary) -> void:
	for side: String in SpritePackLoader.DIRECTIONS:
		var name := "%s_%s" % [plain, side]
		var label := tr("朝左專用") if side == "left" else tr("朝右專用")
		if _model.action_names().has(name):
			_action_list.add_item("    ↳ %s(%d)%s" % [label, _model.frame_count(name), _sync_mark(name)])
			_action_rows.append({"action": name, "slot": name})
			nested[name] = true
		elif _extra_slots.has(name):
			_action_list.add_item(tr("    ↳ %s(空)") % label)
			_action_list.set_item_custom_fg_color(_action_list.item_count - 1, ManagerUi.muted_color(_action_list))
			_action_rows.append({"action": "", "slot": name})
			nested[name] = true


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
	dialog.title = tr("新增自訂動作")
	dialog.ok_button_text = "新增"
	dialog.cancel_button_text = "取消"
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = tr("動作名稱(英數、底線、連字號;會出現在網頁編輯器的動作下拉選單):")
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
	_pack_label.text = _model.root if has_pack else tr("(還沒有開啟素材包)")
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
	var crop_base := _model.crop_base(_action, _index) if _canvas.mode == PackFrameCanvas.Mode.CROP else {}
	if not crop_base.is_empty():
		# 裁切模式畫還沒裁的底圖、裁切線標出目前的範圍(位置跟裁過的圖一樣,見 PackEditorModel.crop_base)
		var crop: Rect2i = crop_base["crop"]
		_canvas.set_frame(crop_base["texture"], crop_base["size"], pivot + Vector2(crop.position), offset)
	else:
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
	_fx_label.text = tr("這一幀的圖片處理:%s") % fx if fx != "" else tr("這一幀沒有圖片處理(原圖)")
	_update_fx_buttons()
	if not crop_base.is_empty():
		_update_crop_limits(crop_base["size"])
		_set_crop_ui(crop_base["crop"])
	else:
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
	_hitbox_state.text = tr("已設定") if box["explicit"] else tr("目前是自動(待機幀本體大小),改任何數字就會變成手動設定")


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
	_hitbox_state.text = tr("已設定")
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
	_light_frame_unlock.text = tr("單獨調整此幀")
	_light_frame_unlock.tooltip_text = tr("第 0 幀(或還沒解鎖的幀)的位置/半徑/亮度/顏色/是否亮著都跟著這盞光的預設值走。勾選這裡才能單獨改目前這一幀,不影響其他幀;取消勾選會清掉這一幀的所有覆蓋,退回預設值(即使預設值是熄燈,解鎖後這一幀還是可以單獨打開)。")
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
	_light_behind_body.text = tr("疊在角色後面")
	_light_behind_body.tooltip_text = tr("預設光暈疊在角色前面(蓋住身體);勾選這裡改成疊在角色與配件的「後面」圖層之後(像從角色身後透出來的光)。整盞光的設定,不分幀。")
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
	_light_cond_copy.tooltip_text = tr("把目前的 ID 複製到剪貼簿,貼到網頁積木編輯器的「條件光源」積木裡。")
	_light_cond_copy.pressed.connect(func() -> void:
		if _light_cond_id.text.strip_edges() != "":
			DisplayServer.clipboard_set(_light_cond_id.text.strip_edges())
			_status.text = tr("已複製條件光源 ID:%s") % _light_cond_id.text.strip_edges())
	cond_row.add_child(_light_cond_copy)
	right.add_child(ManagerUi.labeled("ID", cond_row))
	_light_enabled = CheckBox.new()
	_light_enabled.text = tr("啟用這盞光")
	_light_enabled.tooltip_text = tr("整盞光的總開關;關掉之後,不管套用範圍或分幀設定都不會亮。要「這個動作大部分時間亮、只有某幾幀暗掉」,總開關留著開,改用上面「套用範圍」選這一幀,把下面的「亮著」關掉。")
	_light_enabled.toggled.connect(func(on: bool) -> void: _edit_light("enabled", on, "light_enabled"))
	right.add_child(_light_enabled)
	_light_frame_enabled = CheckBox.new()
	_light_frame_enabled.text = tr("亮著(在目前套用範圍那一層)")
	_light_frame_enabled.tooltip_text = tr("在上面「套用範圍」選的那一層,這盞光要不要亮。用來做「指定幀熄燈」:套用範圍選這一幀,關掉這裡。")
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
	_acc_add.tooltip_text = tr("選一張或多張圖片(多張會循環播放)做成一個新配件,放在角色頭部上方。")
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
	for label in ["配件(一直顯示,可在右鍵選單開關)", "眨眼(隨機短暫出現)", "說話(說話時顯示)", "待呼叫(積木、狀態鏡叫出來或指定的幀才顯示)"]:
		_acc_role.add_item(label)
	_acc_role.tooltip_text = tr("待呼叫:平常不出現,只有積木「暫時顯示圖層」(家具是「家具圖層」積木)、狀態鏡的「啟用時暫時顯示圖層」要求時,或在「顯示時機」把某幾幀設成「👁 顯示」時才出現(例如特定狀態才出現的表情、睡覺時閉眼)。")
	_acc_role.item_selected.connect(_edit_acc_kind)
	right.add_child(ManagerUi.labeled("種類", _acc_role))
	_acc_layer = OptionButton.new()
	for label in ["本體上面", "本體後面", "最上層", "光源之上"]:
		_acc_layer.add_item(label)
	_acc_layer.item_selected.connect(func(index: int) -> void: _edit_accessory("layer", ACC_LAYERS[index], "acc_layer"))
	right.add_child(ManagerUi.labeled("圖層", _acc_layer))
	# 2026-10-15 圖層頁整理:常用的在前、可收合;做好就很少再動的裁切與對齊點放最底下、預設收起。
	var place_fold := FoldSection.new("位置與大小", "錨點是相對腳底軸心的縮放前像素座標;上面「模式」選「調整配件位置」可以直接在畫布上拖曳。")
	right.add_child(place_fold)
	var show_fold := FoldSection.new("顯示時機", "這個圖層在哪些動作出現,以及個別幀要不要顯示。")
	right.add_child(show_fold)
	var image_fold := FoldSection.new("圖片與播放", "選取的圖層的每一張圖。多張圖會依「播放速度」循環(眨眼在眨眼時間內播完一輪)。縮圖可複選(Ctrl / Shift),前移、後移、複製一份、刪除、更換圖片都對選取的圖。")
	right.add_child(image_fold)
	_layer_crop_fold = FoldSection.new("裁切與對齊點", "・預覽:滾輪放大縮小,「移動視角畫面」模式左鍵拖曳平移(任何模式中鍵、右鍵拖曳也可以)。\n・裁切:預覽切到「拖曳畫裁切範圍」,拖出要保留的範圍,再按「套用到選取的圖」(選取的圖 = 上面「圖片與播放」的縮圖)。裁切只是少畫空白,圖層在畫面上的位置不會變。「自動裁掉透明邊」會把每張選取的圖各自裁到有畫東西的範圍。\n・對齊點:圖上放在錨點的那一點,預設是圖片中心;切到「點選對齊點」直接在預覽上點,或填數字(原圖的像素座標,整個圖層共用)。", false)
	right.add_child(_layer_crop_fold)
	right = place_fold.content
	_acc_x = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_acc_y = ManagerUi.spin(1.0, -PackLights.MAX_COORD, PackLights.MAX_COORD)
	_acc_x.value_changed.connect(func(_v: float) -> void: _edit_anchor(Vector2(_acc_x.value, _acc_y.value)))
	_acc_y.value_changed.connect(func(_v: float) -> void: _edit_anchor(Vector2(_acc_x.value, _acc_y.value)))
	_acc_scope = OptionButton.new()
	for label in ["整個配件(預設位置)", "只有目前這個動作", "只有目前這一幀(跟著動畫每一幀)"]:
		_acc_scope.add_item(label)
	_acc_scope.tooltip_text = tr("拖曳畫布或改下面座標時,寫進哪一層:整個配件共用一個位置;或只改目前這個動作(例如舉手動作時帽子要換位置);或只改目前這一幀(動畫每一幀配件位置不同)。執行時優先順序:這一幀 > 這個動作 > 整個配件。")
	_acc_scope.item_selected.connect(func(_i: int) -> void: _refresh_anchor_widgets())
	right.add_child(ManagerUi.labeled("位置套用範圍", _acc_scope))
	_acc_scope_label = Label.new()
	_acc_scope_label.theme_type_variation = AppSettings.MUTED_LABEL
	_acc_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_acc_scope_label)
	_acc_scope_clear = ManagerUi.button("清除這一層的位置")
	_acc_scope_clear.tooltip_text = tr("把上面選的範圍(動作層或幀層)的設定拿掉,回到比較上層的位置。")
	_acc_scope_clear.pressed.connect(_clear_anchor_scope)
	right.add_child(_acc_scope_clear)
	right.add_child(ManagerUi.labeled("錨點 X(右為正)", _acc_x))
	right.add_child(ManagerUi.labeled("錨點 Y(下為正)", _acc_y))
	_acc_scale = ManagerUi.spin(0.05, 0.05, 8.0)
	_acc_scale.value_changed.connect(func(value: float) -> void: _edit_accessory("scale", value, "acc_scale"))
	right.add_child(ManagerUi.labeled("縮放倍率", _acc_scale))
	var flip_row := HBoxContainer.new()
	_acc_flip_h = ManagerUi.button("↔")
	_acc_flip_h.tooltip_text = tr("水平翻轉這個圖層(左右對調,在原地翻,位置不變)。再按一次翻回來。")
	_acc_flip_h.toggle_mode = true
	_acc_flip_h.toggled.connect(func(on: bool) -> void: _edit_acc_flip("flip_h", on))
	_acc_flip_v = ManagerUi.button("↕")
	_acc_flip_v.tooltip_text = tr("垂直翻轉這個圖層(上下對調,在原地翻,位置不變)。再按一次翻回來。")
	_acc_flip_v.toggle_mode = true
	_acc_flip_v.toggled.connect(func(on: bool) -> void: _edit_acc_flip("flip_v", on))
	_acc_mirror = ManagerUi.button("🪞")
	_acc_mirror.tooltip_text = tr("只在目前這個動作把這個圖層左右鏡像(以錨點為中心翻,位置不動;跟 ↔ 各算各的)。「複製預設版本並左右翻轉」建立朝向版本時會自動打開;不想鏡像就再按一次關掉。")
	_acc_mirror.toggle_mode = true
	_acc_mirror.toggled.connect(_edit_acc_mirror)
	flip_row.add_child(_acc_flip_h)
	flip_row.add_child(_acc_flip_v)
	flip_row.add_child(_acc_mirror)
	right.add_child(ManagerUi.labeled("翻轉", flip_row))
	right = show_fold.content
	_acc_actions = ManagerUi.line_edit("* = 所有動作;或動作名稱用逗號分隔,例如 idle, walk")
	_acc_actions.text_changed.connect(func(text: String) -> void: _edit_accessory("actions", _parse_actions(text), "acc_actions"))
	right.add_child(ManagerUi.labeled("在這些動作顯示", _acc_actions))
	# 逐幀顯示(2026-10-13):角色在動畫裡每一幀的角度可能不同,某幾幀要把這個圖層藏起來(或只在某幾幀露出來)。做法比照光源的「單獨調整此幀」。
	var rule_row := HFlowContainer.new()
	_acc_frame_label = Label.new()
	rule_row.add_child(_acc_frame_label)
	var rule_group := ButtonGroup.new()
	var rule_specs := [
		["↺ 照規則", "這一幀沒有自己的設定,照平常的規則(上面「在這些動作顯示」與種類)。"],
		["👁 顯示", "這一幀一定顯示這個圖層:一般配件、待呼叫連「在這些動作顯示」沒列到的動作也會顯示;眨眼、說話差分照樣只在眨眼/說話時出現。"],
		["🚫 不顯示", "這一幀一定不顯示這個圖層:積木、狀態鏡叫出來也不會顯示;眨眼、說話差分播到這一幀就不會眨眼/動嘴。"],
	]
	_acc_frame_rule_buttons.clear()
	for k in rule_specs.size():
		var rule_button := ManagerUi.button(rule_specs[k][0])
		rule_button.tooltip_text = tr(rule_specs[k][1]) + "\n" + tr("在幀清單用 Ctrl / Shift 選好幾幀,就會一次改選取的所有幀。")
		rule_button.toggle_mode = true
		rule_button.button_group = rule_group
		rule_button.toggled.connect(func(on: bool) -> void:
			if on:
				_set_acc_frame_rule([null, true, false][k]))
		rule_row.add_child(rule_button)
		_acc_frame_rule_buttons.append(rule_button)
	right.add_child(rule_row)
	_acc_frame_clear = ManagerUi.button("清除這個圖層的逐幀顯示設定")
	_acc_frame_clear.tooltip_text = tr("所有動作的每一幀都回到「↺ 照規則」(上面「在這些動作顯示」與種類)。只想在某些動作出現,用「在這些動作顯示」列出那些動作就好,不用一幀一幀關;可以復原。")
	_acc_frame_clear.pressed.connect(_clear_layer_frame_rules)
	right.add_child(_acc_frame_clear)
	_build_furn_user_widgets(right)
	right = image_fold.content
	_build_layer_frames(right)
	_acc_fps = ManagerUi.spin(0.5, 0.5, 60.0)
	_acc_fps.value_changed.connect(func(value: float) -> void: _edit_accessory("fps", value, "acc_fps"))
	right.add_child(ManagerUi.labeled("多張圖的播放速度(fps)", _acc_fps))
	_acc_loop = CheckBox.new()
	_acc_loop.text = tr("循環播放(取消 = 播到最後一張停住)")
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
	_acc_add_image.visible = false   # 「加入圖片…」在上面的縮圖按鈕裡
	image_row.add_child(_acc_add_image)
	_acc_clear_images = ManagerUi.button("只留第一張")
	_acc_clear_images.pressed.connect(func() -> void:
		if _acc_index >= 0 and _acc_index < _accs.size() and (_accs[_acc_index]["images"] as Array).size() > 1 and not _acc_locked():
			var crops: Variant = _accs[_acc_index].get("crops")
			if crops is Array and (crops as Array).size() > 1:
				_accs[_acc_index]["crops"] = (crops as Array).slice(0, 1)
			_edit_accessory("images", [(_accs[_acc_index]["images"] as Array)[0]], "acc_images")
			_refresh_accessories())
	image_row.add_child(_acc_clear_images)
	right.add_child(image_row)
	right = _layer_crop_fold.content
	_acc_origin = OptionButton.new()
	for label in ["圖片中心", "左上角", "底邊中心", "上邊中心", "自訂(在下面的預覽點選)"]:
		_acc_origin.add_item(label)
	_acc_origin.item_selected.connect(_on_acc_origin_selected)
	right.add_child(ManagerUi.labeled("圖上放在錨點的那一點", _acc_origin))
	right.add_child(_layer_frames.crop_box)


## 家具圖層的「誰在用時顯示」(2026-10-15 使用者要求:依使用家具的桌寵是誰決定家具動畫的內容)。
func _build_furn_user_widgets(right: VBoxContainer) -> void:
	_furn_user_box = VBoxContainer.new()
	_furn_user_box.visible = false
	_furn_user_box.add_theme_constant_override("separation", 6)
	right.add_child(_furn_user_box)
	_furn_user_mode = OptionButton.new()
	for label in ["不看有沒有人在用", "沒有桌寵在用時", "有桌寵在用時", "指定的桌寵在用時", "指定以外的桌寵在用時"]:
		_furn_user_mode.add_item(label)
	_furn_user_mode.item_selected.connect(func(index: int) -> void:
		_edit_accessory("used_by", FURN_USER_MODES[index], "acc_used_by")
		_refresh_furn_user_widgets())
	var mode_row := ManagerUi.labeled("誰在用時顯示", _furn_user_mode)
	mode_row.add_child(ManagerUi.info_icon("這個圖層要看「誰在用這件家具」才顯示嗎?「在用」= 桌寵已經走到定位坐好/躺好(走過去的路上不算)。\n例如同一張床,幫每隻桌寵各做一個被子圖層,設成「指定的桌寵在用時」並勾選那隻桌寵,誰躺上去就蓋誰的被子;再做一個「沒有桌寵在用時」的圖層當空床的樣子。\n上面「在這些動作顯示」照樣有效(動作 = 家具的狀態:normal / conditional / interacted)。"))
	_furn_user_box.add_child(mode_row)
	_furn_user_seat = OptionButton.new()
	_furn_user_seat.item_selected.connect(func(index: int) -> void: _edit_accessory("used_seat", index - 1, "acc_used_seat"))
	_furn_user_box.add_child(ManagerUi.labeled("看哪個位置", _furn_user_seat))
	_furn_user_pets = ItemList.new()
	_furn_user_pets.select_mode = ItemList.SELECT_MULTI
	_furn_user_pets.custom_minimum_size.y = 96.0
	_furn_user_pets.tooltip_text = tr("可複選(Ctrl / Shift)。清單是角色庫裡的角色加上目前桌面上的桌寵,用辨識代號比對,所以同一個角色放好幾隻都算。")
	_furn_user_pets.multi_selected.connect(func(_index: int, _selected: bool) -> void:
		var tags: Array = []
		for row in _furn_user_pets.get_selected_items():
			tags.append(_furn_user_tags[row])
		_edit_accessory("used_by_tags", tags, "acc_used_by_tags"))
	_furn_user_box.add_child(_furn_user_pets)


func _refresh_furn_user_widgets() -> void:
	if _furn_user_box == null or not _furn_user_box.visible:
		return
	var has_part := _acc_index >= 0 and _acc_index < _accs.size()
	var part: Dictionary = _accs[_acc_index] if has_part else {}
	_updating = true
	var mode := maxi(FURN_USER_MODES.find(str(part.get("used_by", "always"))), 0)
	_furn_user_mode.select(mode)
	_furn_user_mode.disabled = not has_part
	_furn_user_seat.clear()
	_furn_user_seat.add_item(tr("任何位置"))
	var seats: Array = _furniture_def.anchors if _furniture_def != null else []
	for i in seats.size():
		_furn_user_seat.add_item(tr("位置 %d(%s)") % [i + 1, tr("坐") if str((seats[i] as Dictionary).get("type", "sit")) == "sit" else tr("躺")])
	var seat := int(part.get("used_seat", -1))
	if seat >= seats.size():
		_furn_user_seat.add_item(tr("位置 %d(已刪除)") % (seat + 1))
		_furn_user_seat.select(_furn_user_seat.item_count - 1)
	else:
		_furn_user_seat.select(seat + 1)
	_furn_user_seat.disabled = not has_part or mode == 0
	var chosen: Array = part.get("used_by_tags", []) if part.get("used_by_tags") is Array else []
	var known := PetReferences.known_pets(get_tree() if is_inside_tree() else null)
	_furn_user_tags.clear()
	_furn_user_pets.clear()
	for tag: String in known:
		_furn_user_tags.append(tag)
		_furn_user_pets.add_item("%s(%s)" % [known[tag], tag])
	for tag: Variant in chosen:
		if not _furn_user_tags.has(str(tag)):
			_furn_user_tags.append(str(tag))
			_furn_user_pets.add_item(tr("%s(不在角色庫)") % str(tag))
	for row in _furn_user_tags.size():
		if chosen.has(_furn_user_tags[row]):
			_furn_user_pets.select(row, false)
	_furn_user_pets.visible = mode >= 3
	_updating = false


static func _parse_actions(text: String) -> Array:
	var actions: Array = []
	for part in text.replace("、", ",").split(",", false):
		var clean := part.strip_edges()
		if clean != "" and not actions.has(clean):
			actions.append(clean)
	return actions if not actions.is_empty() else ["*"]


## 圖層圖片(crop = 裁切範圍,見 PetOverlays.crop_rect;null = 整張原圖)。依素材包、檔名、裁切快取。
func _acc_texture(relative: String, crop: Variant = null) -> Texture2D:
	var rect: Variant = PetOverlays.crop_rect(crop)
	var key := "%s|%s|%s" % [_model.root, relative, str(rect) if rect is Rect2i else ""]
	if not _acc_textures.has(key):
		var report: Array[String] = []
		_acc_textures[key] = PetOverlays.load_cropped(_model.root, relative, rect, report)
	return _acc_textures[key]


func _acc_image(relative: String) -> Image:
	var report: Array[String] = []
	return PetOverlays._load_image(_model.root, relative, report)


## 圖層的圖片小窗(2026-10-15,見 LayerFramesPanel):放在圖層清單與「選取的圖層設定」之間,管理選取的圖層的每一張圖、裁切與對齊點。
func _build_layer_frames(right: VBoxContainer) -> void:
	_layer_frames = LayerFramesPanel.new()
	_layer_frames.setup(_acc_texture, _acc_image)
	_layer_frames.part_changed.connect(_on_layer_frames_changed)
	_layer_frames.locked_touched.connect(func() -> void: _status.text = PackLayers.lock_hint())
	_layer_frames.add_images_requested.connect(func() -> void:
		FloatingWindow.native_file_dialog("選擇要加進這個配件的圖片", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]),
				func(paths: PackedStringArray) -> void: add_accessory_images(Array(paths)), get_window_id()))
	_layer_frames.replace_images_requested.connect(func(indices: Array) -> void:
		if indices.is_empty():
			return
		FloatingWindow.native_file_dialog("選擇新的圖片(選幾張就依序換掉幾張選取的圖)", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]),
				func(paths: PackedStringArray) -> void: _status.text = replace_accessory_images(indices, Array(paths)), get_window_id()))
	right.add_child(_layer_frames)


func _on_layer_frames_changed(part: Dictionary, message: String, checkpoint_key: String) -> void:
	if _acc_index < 0 or _acc_index >= _accs.size() or _acc_locked():
		return
	_model.checkpoint(checkpoint_key)
	_accs[_acc_index] = part
	_model.set_accessories(_accs)
	_refresh_accessories()
	_after_edit(message)


## 「圖上放在錨點的那一點」:前四項是預設點;「自訂」= 存成原圖像素座標 [x, y](從目前的點開始,再到圖片小窗點選或填數字)。
func _on_acc_origin_selected(index: int) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _acc_locked():
		return
	if index < ACC_ORIGINS.size():
		_edit_accessory("origin", ACC_ORIGINS[index], "acc_origin")
		_refresh_accessories()
		return
	var part: Dictionary = _accs[_acc_index]
	var images: Array = part.get("images", [])
	var texture: Texture2D = _acc_texture(str(images[0])) if not images.is_empty() else null
	var point := PetOverlays._origin_pixels(part.get("origin", "center"), Vector2(texture.get_size()) if texture != null else Vector2.ZERO)
	_edit_accessory("origin", [roundf(point.x), roundf(point.y)], "acc_origin")
	_refresh_accessories()
	_layer_frames.use_mode(LayerFramesPanel.LayerImagePreview.MODE_ORIGIN)
	_layer_crop_fold.set_open(true)
	_status.text = tr("在「裁切與對齊點」的預覽直接點圖上要放在錨點的那一點,或填「對齊點 X / Y」。")


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
		_acc_list.add_item("%s(%s)" % [part.get("name", "?"), tr(ACC_KIND_LABELS[_acc_kind_index(part)])])
	if _acc_index >= 0:
		_acc_list.select(_acc_index)
	var has_part := _acc_index >= 0 and _acc_index < _accs.size()
	for control: Control in [_acc_name, _acc_role, _acc_layer, _acc_x, _acc_y, _acc_origin, _acc_scale, _acc_flip_h, _acc_flip_v, _acc_actions, _acc_fps, _acc_loop, _acc_add_image, _acc_clear_images, _acc_delete]:
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
		_acc_role.select(_acc_kind_index(part))
		_acc_flip_h.set_pressed_no_signal(bool(part.get("flip_h", false)))
		_acc_flip_v.set_pressed_no_signal(bool(part.get("flip_v", false)))
		_acc_layer.select(maxi(ACC_LAYERS.find(str(part.get("layer", "front"))), 0))
		_acc_x.value = (anchor as Vector2).x if anchor is Vector2 else 0.0
		_acc_y.value = (anchor as Vector2).y if anchor is Vector2 else 0.0
		_acc_origin.select(ACC_ORIGINS.size() if part.get("origin") is Array else maxi(ACC_ORIGINS.find(str(part.get("origin", "center"))), 0))
		_acc_scale.value = float(part.get("scale", 1.0))
		_acc_actions.text = ", ".join(PackedStringArray(part.get("actions", ["*"])))
		_acc_fps.value = float(part.get("fps", PetOverlays.DEFAULT_FPS))
		_acc_loop.button_pressed = bool(part.get("loop", true))
		_acc_images.text = tr("圖片 %d 張") % (part.get("images", []) as Array).size()
	else:
		_acc_images.text = ""
	_updating = false
	if _layer_frames != null:
		_layer_frames.set_part(_accs[_acc_index] if has_part else {})
	_refresh_anchor_widgets()
	_refresh_layers()


func _accessory_preview() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: Dictionary in _accs:
		var texture: Texture2D = _layer_preview_texture(part)
		var anchor: Variant = AccessoryAnchors.effective(part, _action, _index)   # 目前這個動作、這一幀實際的位置
		# 畫布從錨點往左上退 origin 畫圖;裁切過的圖用 texture_offset 換算(位置跟沒裁切時一樣)
		var origin := -PetOverlays.texture_offset(part.get("origin", "center"), texture) if texture != null else Vector2.ZERO
		result.append({"x": (anchor as Vector2).x if anchor is Vector2 else 0.0, "y": (anchor as Vector2).y if anchor is Vector2 else 0.0,
				"scale": float(part.get("scale", 1.0)), "origin": origin, "texture": texture, "name": str(part.get("name", "")), "role": str(part.get("role", "part")),
				"layer": PackLayers.layer_of(part), "hidden": bool(_layer_hidden.get(str(part.get("name", "")), false)),
				"flip_h": bool(part.get("flip_h", false)), "flip_v": bool(part.get("flip_v", false)),
				"mirror": part.get("mirror_for") is Array and (part["mirror_for"] as Array).has(_action),
				"locked": PackLayers.is_locked(part),
				# 遊戲裡這一幀不會出現的:預覽不畫,只有選取中的畫成半透明(還是能調位置),見 PackFrameCanvas._acc_shown
				"ghost": _action != "" and not PackLayers.shows_in_game(part, _action, _index)})
	return result


func _on_canvas_accessory_selected(index: int) -> void:
	if _seat_editing():
		_furn_anchor_index = index
		_refresh_furniture_anchors()
		return
	_acc_index = index
	_layer_body_focus = false
	_refresh_accessories()


func _on_canvas_accessory_edited(index: int, at: Vector2) -> void:
	if _seat_editing():
		if _furniture_def == null or index < 0 or index >= _furniture_def.anchors.size():
			return
		_furniture_def.anchors[index]["x"] = at.x
		_furniture_def.anchors[index]["y"] = at.y
		_save_furniture()
		_refresh_furniture_anchors()
		return
	if index < 0 or index >= _accs.size() or _acc_locked(index):
		return
	var promoted := _write_anchor(index, at)
	_updating = true
	_acc_x.value = at.x
	_acc_y.value = at.y
	_updating = false
	_refresh_anchor_widgets()
	_after_edit(promoted)


## 錨點寫進「位置套用範圍」選的那一層(整個配件 / 目前動作 / 目前這一幀)。
## 2026-10-16 使用者回報:按座標框的上下箭頭數字和預覽都不動、編輯器卻說有改動——這個動作已經有更細的位置
## (例如「同步到其他動作」寫進的逐幀位置)蓋過選的那一層,寫了也看不到。現在遇到這種情況自動改寫進正在生效的那一層,
## 範圍選單跟著切過去;回傳要顯示的提示(沒改就是空字串)。
func _write_anchor(index: int, at: Vector2) -> String:
	var scope := _acc_scope.selected if _acc_scope != null else AccessoryAnchors.SCOPE_DEFAULT
	var note := ""
	if _action != "":
		var source := AccessoryAnchors.source_of(_accs[index], _action)
		if source > scope:
			scope = source
			if _acc_scope != null:
				_acc_scope.select(scope)
			note = tr("這個動作的位置被更細的設定蓋過,已改成寫進「%s」(位置套用範圍已切換)") % _acc_scope.get_item_text(scope) if _acc_scope != null else ""
	var count := _model.frame_count(_action) if _action != "" else 0
	if scope == AccessoryAnchors.SCOPE_FRAME:
		# 2026-10-16:選了好幾幀時一起移,每一幀移一樣的距離(各幀原本不同的位置差保留下來)。
		var delta := at - AccessoryAnchors.effective(_accs[index], _action, _index)
		var frames := _selected_frames()
		if not frames.has(_index):
			frames.append(_index)
		for frame in frames:
			var target := at if frame == _index else AccessoryAnchors.effective(_accs[index], _action, frame) + delta
			AccessoryAnchors.set_anchor(_accs[index], scope, _action, frame, count, target)
	else:
		AccessoryAnchors.set_anchor(_accs[index], scope, _action, _index, count, at)
	_model.set_accessories(_accs)
	return note


## 座標框改了(使用者輸入)。
func _edit_anchor(at: Vector2) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _acc_locked():
		return
	_model.checkpoint("acc_anchor")
	var promoted := _write_anchor(_acc_index, at)
	_refresh_anchor_widgets()
	_after_edit(promoted)


func _clear_anchor_scope() -> void:
	if _acc_index < 0 or _acc_index >= _accs.size() or _acc_scope == null or _acc_locked():
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
	_acc_mirror.disabled = not has_part or not has_action
	_acc_mirror.set_pressed_no_signal(has_part and _accs[_acc_index].get("mirror_for") is Array and (_accs[_acc_index]["mirror_for"] as Array).has(_action))
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
	_refresh_frame_visible_widgets()
	_refresh_furn_user_widgets()
	_push_canvas_accessories()
	_apply_layer_lock_ui()


## 逐幀顯示的兩個勾選框跟著目前選的圖層、動作、幀走:沒有動作可選就都不能用;沒勾「單獨調整」時第二個框顯示平常的規則(不能改)。
func _refresh_frame_visible_widgets() -> void:
	if _acc_frame_label == null:
		return
	var has_part := _acc_index >= 0 and _acc_index < _accs.size()
	var has_action := _action != "" and _model.has_pack() and _model.frame_count(_action) > 0
	var rule: Variant = PackLayers.frame_rule(_accs[_acc_index], _action, _index) if has_part and has_action else null
	var was_updating := _updating
	_updating = true
	var pressed := 0 if not rule is bool else (1 if rule else 2)
	for k in _acc_frame_rule_buttons.size():
		_acc_frame_rule_buttons[k].disabled = not (has_part and has_action)
		_acc_frame_rule_buttons[k].set_pressed_no_signal(k == pressed)
	var many := _frame_rule_targets().size() if has_action else 1
	_acc_frame_label.text = tr("這一幀:") if many <= 1 else tr("選取的 %d 幀:") % many
	if _acc_frame_clear != null:
		_acc_frame_clear.disabled = not (has_part and (_accs[_acc_index] as Dictionary).has("frame_visible"))
	_updating = was_updating


## 「這一幀:↺ 照規則 / 👁 顯示 / 🚫 不顯示」:value = null(清掉這一幀的設定)/ true / false,寫進畫布這一幀加上幀清單選取的所有幀。
func _set_acc_frame_rule(value: Variant) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _action == "" or _acc_locked():
		return
	_model.checkpoint()
	for frame in _frame_rule_targets():
		PackLayers.set_frame_rule(_accs[_acc_index], _action, frame, _model.frame_count(_action), value)
	_model.set_accessories(_accs)
	_refresh_anchor_widgets()
	_after_edit(tr("已清除選取的幀的顯示設定") if value == null else "")


## 逐幀顯示要改哪幾幀:畫布上這一幀加上幀清單裡選取的所有幀(2026-10-16:可以一次改好幾幀)。
func _frame_rule_targets() -> Array[int]:
	var frames := _selected_frames()
	if not frames.has(_index):
		frames.append(_index)
	return frames


## 「清除這個圖層的逐幀顯示設定」:所有動作的每一幀都回到平常的規則(「在這些動作顯示」與種類)。
func _clear_layer_frame_rules() -> void:
	if _acc_locked():
		return
	if _acc_index < 0 or _acc_index >= _accs.size() or not (_accs[_acc_index] as Dictionary).has("frame_visible"):
		_status.text = tr("這個圖層沒有逐幀顯示設定")
		return
	_model.checkpoint()
	(_accs[_acc_index] as Dictionary).erase("frame_visible")
	_model.set_accessories(_accs)
	_refresh_anchor_widgets()
	_after_edit(tr("已清除這個圖層所有動作的逐幀顯示設定(可以復原)"))


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
	if _acc_locked():
		return PackLayers.lock_hint()
	var relatives := _model.import_accessory_images(paths)
	if relatives.is_empty():
		return "無法匯入這些圖片"
	var images: Array = (_accs[_acc_index]["images"] as Array).duplicate()
	images.append_array(relatives)
	_edit_accessory("images", images.slice(0, PetOverlays.MAX_FRAMES), "acc_images")
	_refresh_accessories()
	return ""


## 把選中配件的第 indices 張圖依序換成 paths(張數取兩邊少的那個),裁切、對齊點、錨點都不動。回傳狀態文字。給按鈕與測試用。
func replace_accessory_images(indices: Array, paths: Array) -> String:
	if _acc_index < 0 or _acc_index >= _accs.size():
		return tr("還沒有選配件")
	if _acc_locked():
		return PackLayers.lock_hint()
	var relatives := _model.import_accessory_images(paths)
	if relatives.is_empty():
		return tr("無法匯入這些圖片")
	var images: Array = (_accs[_acc_index]["images"] as Array).duplicate()
	var count := mini(indices.size(), relatives.size())
	for k in count:
		var at := int(indices[k])
		if at >= 0 and at < images.size():
			images[at] = relatives[k]
	_edit_accessory("images", images, "acc_images")
	_refresh_accessories()
	return tr("已更換 %d 張圖(裁切、對齊點、錨點都保留;可以撤回)") % count


## 複製選中的圖層(全部設定一起複製,名稱加上編號),放在它後面並選中。給按鈕與測試用。成功回空字串。
func duplicate_accessory() -> String:
	if _acc_index < 0 or _acc_index >= _accs.size():
		return "還沒有選圖層"
	if _accs.size() >= PetOverlays.MAX_PARTS:
		return "配件太多了"
	var copy: Dictionary = (_accs[_acc_index] as Dictionary).duplicate(true)
	var base_name := str(copy.get("name", "layer"))
	var unique := "%s_2" % base_name
	var counter := 3
	while _accs.any(func(p: Dictionary) -> bool: return p.get("name") == unique):
		unique = "%s_%d" % [base_name, counter]
		counter += 1
	copy["name"] = unique
	_model.checkpoint()
	_accs.insert(_acc_index + 1, copy)
	_model.set_accessories(_accs)
	_acc_index += 1
	_layer_body_focus = false
	_refresh_accessories()
	_after_edit(tr("已複製成「%s」(可以用小窗的「更換圖片…」換成別的圖,裁切與位置都沿用)") % unique)
	return ""


func delete_accessory() -> void:
	if _acc_index < 0 or _acc_index >= _accs.size() or _acc_locked():
		return
	_model.checkpoint()
	_accs.remove_at(_acc_index)
	_model.set_accessories(_accs)
	_acc_index = mini(_acc_index, _accs.size() - 1)
	_refresh_accessories()
	_after_edit(tr("已刪除配件"))


## 表單改了目前這個配件的一個欄位:存撤回點(同一欄位連續改合併成一步)、寫回模型、更新畫布預覽。
func _edit_accessory(field: String, value: Variant, checkpoint_key: String) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _acc_locked():
		return
	_model.checkpoint(checkpoint_key)
	_accs[_acc_index][field] = value
	_model.set_accessories(_accs)
	if field == "name" or field == "role":
		_updating = true
		_acc_list.set_item_text(_acc_index, "%s(%s)" % [_accs[_acc_index].get("name", "?"), tr(ACC_KIND_LABELS[_acc_kind_index(_accs[_acc_index])])])
		_updating = false
	_push_canvas_accessories()
	_after_edit("")


## 種類下拉在第幾項:平常不顯示(visible: false)的一律算「待呼叫」,其餘照 role。
func _acc_kind_index(part: Dictionary) -> int:
	if part.get("visible") is bool and not bool(part["visible"]):
		return ACC_KIND_STANDBY
	return maxi(ACC_ROLES.find(str(part.get("role", "part"))), 0)


## 種類改了:「待呼叫」= role part + "visible": false;其他種類拿掉 visible(平常照規則顯示)。
## 2026-10-16 使用者提議:原本是另外一個「平常顯示這個圖層」勾選框,併進種類比較好懂。
func _edit_acc_kind(index: int) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _acc_locked():
		return
	_model.checkpoint("acc_role")
	var part: Dictionary = _accs[_acc_index]
	if index == ACC_KIND_STANDBY:
		part["role"] = "part"
		part["visible"] = false
	else:
		part["role"] = ACC_ROLES[clampi(index, 0, ACC_ROLES.size() - 1)]
		part.erase("visible")
	_model.set_accessories(_accs)
	_refresh_accessories()
	_after_edit("")


## 圖層水平/垂直翻轉(整個圖層、每張圖都翻,在原地翻;沒翻就不寫這個欄位)。
func _edit_acc_flip(field: String, on: bool) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _acc_locked():
		return
	_model.checkpoint()
	if on:
		_accs[_acc_index][field] = true
	else:
		(_accs[_acc_index] as Dictionary).erase(field)
	_model.set_accessories(_accs)
	_push_canvas_accessories()
	_after_edit(tr("已翻轉圖層(可以撤回)"))


## 這個圖層在目前動作整個左右鏡像(寫進 mirror_for;清單空了就拿掉欄位)。
func _edit_acc_mirror(on: bool) -> void:
	if _updating or _acc_index < 0 or _acc_index >= _accs.size() or _action == "" or _acc_locked():
		return
	var part: Dictionary = _accs[_acc_index]
	var list: Array = (part["mirror_for"] as Array).duplicate() if part.get("mirror_for") is Array else []
	if on == list.has(_action):
		return
	_model.checkpoint()
	if on:
		list.append(_action)
	else:
		list.erase(_action)
	if list.is_empty():
		part.erase("mirror_for")
	else:
		part["mirror_for"] = list
	_model.set_accessories(_accs)
	_push_canvas_accessories()
	_after_edit(tr("已在「%s」鏡像這個圖層(可以撤回)") % _action if on else tr("已取消「%s」的圖層鏡像(可以撤回)") % _action)


## 圖層:本體(動作的幀)加上所有配件(部件)排成一疊,可以調上下順序、開關預覽顯示、暫時停用。適合只畫了會動的那一小塊(眨眼的眼睛、說話的嘴、尾巴等拆件),
## 把它們蓋在本體上調位置與順序。配件本身的圖片、錨點、縮放等仍在「配件」頁籤設定,這裡看的是整疊的順序。
func _build_layers_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("圖層", tr("清單由上到下 = 畫面由前到後:最上面的蓋在最上面,中間那一列「本體」是動作的幀,「本體後面」的圖層在它下面。用 ▲ ▼ 調順序(跨過本體就會在「本體上面 / 後面」之間切換);眼睛只影響這個編輯器的預覽(方便看被蓋住的東西),不會存檔;種類選「待呼叫」= 這個圖層平常不出現,只有積木「暫時顯示圖層」或狀態鏡要求時,或是「顯示時機」設成「👁 顯示」的幀才顯示(例如特定狀態才出現的表情、睡覺時閉眼)。圖層就是配件(部件),最多 %d 個;眨眼、說話差分只畫有變動的那一小塊也用這裡管理。") % PetOverlays.MAX_PARTS))
	_layer_list = LayerListView.new()
	_layer_list.custom_minimum_size.y = 130.0
	_layer_list.item_selected.connect(_on_layer_selected)
	_layer_list.lock_toggled.connect(_toggle_layer_lock)
	right.add_child(_layer_list)
	# 2026-10-16 改成一排圖示按鈕(文字說明在滑鼠停留提示),版面省一點
	var row := HFlowContainer.new()
	_layer_up = ManagerUi.button("▲")
	_layer_up.tooltip_text = tr("上移:選取的圖層往前(上面)移一格。")
	_layer_up.pressed.connect(func() -> void: _move_layer(1))
	_layer_down = ManagerUi.button("▼")
	_layer_down.tooltip_text = tr("下移:選取的圖層往後(下面)移一格。")
	_layer_down.pressed.connect(func() -> void: _move_layer(-1))
	_layer_eye = ManagerUi.button("👁")
	_layer_eye.tooltip_text = tr("在這個編輯器的預覽裡隱藏 / 顯示選取的圖層(不存檔)。")
	_layer_eye.pressed.connect(_toggle_layer_preview)
	for control in [_layer_up, _layer_down, _layer_eye]:
		row.add_child(control)
	var add_row := row
	var add := ManagerUi.button("➕")
	add.tooltip_text = tr("新增圖層:選一張或多張圖片做成一個新圖層(配件),放在本體上面;再用畫布或下面的設定調位置。")
	add.pressed.connect(func() -> void:
		FloatingWindow.native_file_dialog("選擇圖層圖片(可多選)", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]),
				func(paths: PackedStringArray) -> void: add_accessory(Array(paths)), get_window_id()))
	add_row.add_child(add)
	var duplicate := ManagerUi.button("📑")
	duplicate.tooltip_text = tr("複製這個圖層:把選取的圖層連同全部設定(圖片、裁切、對齊點、錨點、逐幀顯示…)複製一份。再用下面小窗的「更換圖片…」換圖,就不用重新裁切對位。")
	duplicate.pressed.connect(func() -> void:
		var error := duplicate_accessory()
		if error != "":
			_status.text = tr(error))
	add_row.add_child(duplicate)
	_layer_delete = ManagerUi.button("🗑")
	_layer_delete.tooltip_text = tr("刪除這個圖層(可以撤回)。")
	_layer_delete.pressed.connect(delete_accessory)
	add_row.add_child(_layer_delete)
	right.add_child(row)
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
	var locks: Array = []
	for row in _layer_rows.size():
		var entry := _layer_rows[row]
		locks.append(null if entry == PackLayers.BODY else PackLayers.is_locked(_accs[entry]))
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
			marks += tr("[待呼叫]")
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
	_layer_list.set_locks(locks)
	if selected_row >= 0:
		_layer_list.select(selected_row)
	var has_part := not _layer_body_focus and _acc_index >= 0 and _acc_index < _accs.size()
	_layer_up.disabled = not has_part or not bool(PackLayers.move(_accs, _acc_index, 1)["changed"])
	_layer_down.disabled = not has_part or not bool(PackLayers.move(_accs, _acc_index, -1)["changed"])
	_layer_eye.disabled = not has_part and not _layer_body_focus
	_layer_delete.disabled = not has_part
	var hidden_now := _body_hidden if _layer_body_focus else (has_part and bool(_layer_hidden.get(str(_accs[_acc_index].get("name", "")), false)))
	_layer_eye.text = "🙈" if hidden_now else "👁"
	_layer_note.text = tr("本體是動作的幀(在「動作」「幀」清單選),不能移動或停用。") if _layer_body_focus else ""
	_updating = false
	_canvas.show_body = not _body_hidden
	_canvas.queue_redraw()
	_apply_layer_lock_ui()


## 點圖層清單右邊的鎖頭:鎖上 / 解除鎖定(可以撤回)。
func _toggle_layer_lock(row: int) -> void:
	if row < 0 or row >= _layer_rows.size() or _layer_rows[row] == PackLayers.BODY:
		return
	var part: Dictionary = _accs[_layer_rows[row]]
	var on := not PackLayers.is_locked(part)
	_model.checkpoint()
	PackLayers.set_locked(part, on)
	_model.set_accessories(_accs)
	_refresh_accessories()
	_after_edit((tr("已鎖定圖層「%s」") if on else tr("已解除鎖定圖層「%s」")) % str(part.get("name", "?")))


## 圖層鎖住了:手動修改的入口一律不改,狀態列提示先解除鎖定(畫面上的欄位也重整回原本的值)。index 省略 = 選取的圖層。
func _acc_locked(index := -1) -> bool:
	var at := _acc_index if index < 0 else index
	if at < 0 or at >= _accs.size() or not PackLayers.is_locked(_accs[at]):
		return false
	_status.text = PackLayers.lock_hint()
	_refresh_accessories.call_deferred()
	return true


## 選取的圖層鎖住時,改得到它的欄位與按鈕都停用,滑鼠停留提示加上「先解除鎖定」。
func _apply_layer_lock_ui() -> void:
	if _acc_name == null:
		return
	var locked := not _layer_body_focus and _acc_index >= 0 and _acc_index < _accs.size() and PackLayers.is_locked(_accs[_acc_index])
	var controls: Array = [_acc_name, _acc_role, _acc_layer, _acc_x, _acc_y, _acc_scope_clear, _acc_scale, _acc_flip_h, _acc_flip_v, _acc_mirror,
			_acc_actions, _acc_frame_clear, _acc_fps, _acc_loop, _acc_add_image, _acc_clear_images, _acc_delete, _acc_origin,
			_layer_up, _layer_down, _layer_delete, _furn_user_mode, _furn_user_seat, _furn_user_pets]
	controls.append_array(_acc_frame_rule_buttons)
	for control: Variant in controls:
		if control is Control:
			LayerListView.mark_locked(control, locked)


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
	if _acc_index < 0 or _acc_index >= _accs.size() or _layer_body_focus or _acc_locked():
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
	_push_canvas_accessories()
	_refresh_layers()


## 持有錨點:桌寵手拿道具的位置(相對腳底線中心的縮放前像素,面向右時)。不勾 = 自動(判定框前側、胸口高度)。
func _build_hold_section(right: VBoxContainer) -> void:
	right.add_child(ManagerUi.heading_with_info("持有錨點(手拿道具的位置)", "桌寵拿著可持有的道具時,道具畫在這個位置(跟著縮放、鏡像、爬牆旋轉)。座標和光源錨點一樣:相對腳底線中心、縮放前像素、右與下為正。不勾自訂就用自動位置(判定框前側、胸口高度)。"))
	_hold_check = CheckBox.new()
	_hold_check.text = tr("自訂持有錨點")
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
		_light_list.add_item("%s%s" % [light["name"], "" if bool(light["enabled"]) else tr("(停用)")])
	if _light_index >= 0:
		_light_list.select(_light_index)
	_light_action.clear()
	_light_action.add_item(tr("(一直亮)"))
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
		_status.text = tr("還沒有裁切範圍:在「裁切圖片」模式的畫布上拖曳,或填數字")
		return
	# 2026-10-18:取代原本的裁切(不是再疊一層),框拉大就能把裁掉的部分拿回來;位置不變(見 PackEditorModel.set_crop)
	if not _model.has_pack() or _action == "":
		return
	var picked := _selected_frames()
	var error := _model.set_crop(_action, picked, rect, _index)   # 框是畫在目前這一幀上的,翻轉方向不同的幀換算成同一塊內容
	if error != "":
		_status.text = tr("沒有套用:%s") % tr(error)
		return
	_after_frames_changed(picked, tr("已裁切成 %d×%d(%d 幀;位置不變,寫進檔案前都能把裁切線拉回去恢復;可以撤回)") % [rect.size.x, rect.size.y, picked.size()])


## 自動裁掉選取的幀四周的透明邊(見 PackEditorModel.auto_trim)。
func _auto_trim_frames() -> void:
	if not _model.has_pack() or _action == "":
		return
	var picked := _selected_frames()
	var result := _model.auto_trim(_action, picked, _trim_shared.button_pressed, _trim_recover.button_pressed)
	if str(result["error"]) != "":
		_status.text = tr("沒有套用:%s") % tr(str(result["error"]))
		return
	if int(result["count"]) == 0:
		_status.text = tr("選取的幀四周已經沒有可以裁掉的透明邊了") if not _trim_recover.button_pressed else tr("選取的幀已經剛好裁到有畫東西的範圍了")
		return
	if int(result["saved_percent"]) < 0:
		_after_frames_changed(picked, tr("已重新裁切透明邊(%d 幀,拿回了之前裁掉的部分,像素多了 %d%%;位置不變,可以撤回)") % [int(result["count"]), -int(result["saved_percent"])])
		return
	_after_frames_changed(picked, tr("已自動裁掉透明邊(%d 幀,像素少了 %d%%;位置不變,可以撤回)") % [int(result["count"]), int(result["saved_percent"])])


func _confirm_bake() -> void:
	if not _model.has_pack():
		return
	var count := _model.fx_frame_count()
	if count == 0:
		_status.text = tr("沒有任何幀有圖片處理或精靈圖切片,不用寫進檔案")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("把圖片處理寫進檔案")
	dialog.ok_button_text = "寫進檔案"
	dialog.cancel_button_text = "取消"
	dialog.theme = ManagerUi.make_theme()
	dialog.dialog_text = tr("整個素材包有 %d 幀有圖片處理(裁切翻轉旋轉)或是精靈圖切片。要把處理後的樣子各存成一張新圖、幀改用新圖嗎?\n\n・畫面上完全不變,可以撤回(撤回只改回設定,新存的圖會留著變成未使用檔案)。\n・原圖不會被刪:確定沒問題、存檔後,再用「清理未使用檔案」把用不到的原圖搬到備份。\n・之後想重新裁切,就是從新圖開始裁(裁掉的部分已經不在新圖裡了)。") % count
	dialog.confirmed.connect(func() -> void: bake_fx())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	FloatingWindow.popup_child_dialog(self, get_window(), dialog)


## 把圖片處理寫進檔案(見 PackEditorModel.bake_fx)。成功回空字串。給按鈕與測試用。
func bake_fx() -> String:
	_model.checkpoint()
	var result := _model.bake_fx()
	if str(result["error"]) != "":
		_model.undo()
		_reload_lists()
		_refresh_all()
		_status.text = tr("沒有寫進檔案:%s") % str(result["error"])
		return str(result["error"])
	_reload_lists()
	_refresh_all()
	_after_edit(tr("已把 %d 幀的圖片處理寫進 %d 張新圖(可以撤回)。存檔後可以用「清理未使用檔案」收掉用不到的原圖。") % [int(result["frames"]), int(result["files"])])
	return ""


func _clear_fx() -> void:
	if not _model.has_pack() or _action == "":
		return
	var picked := _selected_frames()
	var count := _model.clear_fx(_action, picked)
	if count == 0:
		_status.text = tr("選取的幀本來就沒有圖片處理")
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
	_write_frame_setting("pivot", pivot)
	pivot = _model.pivot(_action, _index)
	_updating = true
	_pivot_x.value = pivot.x
	_pivot_y.value = pivot.y
	_updating = false
	_after_pivot_edit()
	_after_edit("")


func _on_canvas_offset_edited(offset: Vector2) -> void:
	if _action == "":
		return
	_write_frame_setting("offset", offset)
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
		_write_frame_setting("pivot", Vector2(_pivot_x.value, _pivot_y.value))
		_after_pivot_edit()
	else:
		_write_frame_setting("offset", Vector2(_offset_x.value, _offset_y.value))
	_refresh_frame()
	_after_edit("")


## 軸心/圖片偏移寫進套用範圍:整個動作,或「只有這一幀」時連幀清單多選的其他幀一起移同樣的量(各自保留原本的差距)。
func _write_frame_setting(setting: String, value: Vector2) -> void:
	var picked := _selected_frames()
	if _whole_action() or picked.size() <= 1 or not picked.has(_index):
		if setting == "pivot":
			_model.set_pivot(_action, _index, value, _whole_action())
		else:
			_model.set_offset(_action, _index, value, _whole_action())
		return
	var current := _model.pivot(_action, _index) if setting == "pivot" else _model.offset(_action, _index)
	_model.shift_frames(setting, _action, picked, value - current)


## 軸心改了以後模型裡的圖層、光源位置已經跟著補過;編輯器手上的複本要重讀,畫布才會跟著動,下一次改圖層也不會把舊位置蓋回去。
func _after_pivot_edit() -> void:
	_refresh_lights()   # 連圖層一起重讀(_refresh_accessories)


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
	_status.text = tr("已複製 %d 幀(可以切到別的動作再貼上)") % count if count > 0 else tr("沒有可複製的幀")
	_update_frame_buttons()


## 貼上的目標動作:目前選的動作;停在還沒有素材的動作槽上就是那個槽的名字(貼上時建立);都沒有回空字串。
func _paste_target() -> String:
	if _action != "":
		return _action
	return SpritePackLoader.clean_action_name(_slot) if _slot != "" else ""


func _paste() -> void:
	var target := _paste_target()
	if target == "" or _model.clipboard.is_empty():
		_status.text = tr("剪貼簿是空的:先選幀按「複製」") if _model.clipboard.is_empty() else tr("先選一個動作(或動作槽)再貼上")
		return
	var picked := _selected_frames() if _action != "" else ([] as Array[int])
	var at := picked[picked.size() - 1] + 1 if not picked.is_empty() else -1
	var created := _model.paste_frames(target, at)
	if not created.is_empty():
		_slot = target if _action == "" else _slot
		_after_frames_changed(created, tr("已貼上 %d 幀到「%s」") % [created.size(), target])
		_extra_slots.erase(target)


func _ask_replace_frames() -> void:
	if _action == "":
		return
	var picked := _selected_frames()
	FloatingWindow.native_file_dialog("選擇新的圖片(選幾張就依序換掉幾張選取的幀)", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, PackedStringArray([IMAGE_FILTER]),
			func(paths: PackedStringArray) -> void: replace_frame_images(picked, Array(paths)), get_window_id())


## 把目前動作選取的幀依序換成 paths 的圖(見 PackEditorModel.replace_frame_images)。成功回空字串。給按鈕與測試用。
func replace_frame_images(indices: Array, paths: Array) -> String:
	if _action == "" or paths.is_empty():
		return "沒有選擇圖片"
	_model.checkpoint()
	var result := _model.replace_frame_images(_action, indices, paths)
	if str(result["error"]) != "":
		_model.undo()
		_status.text = tr(str(result["error"]))
		return str(result["error"])
	var keep: Array[int] = []
	for value: Variant in indices:
		keep.append(int(value))
	_after_frames_changed(keep, tr("已更換 %d 幀的圖(圖片處理、軸心、圖片偏移都保留;可以撤回)") % int(result["count"]))
	return ""


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
			# 只寫頭~尾:幀很多時逐幀列出會把視窗撐出畫面(2026-10-16 使用者回報)
			_loop_note.text = tr("播放順序:0~%d,之後 %d~%d 一直循環。") % [int(_loop_end.value), int(_loop_start.value), int(_loop_end.value)]
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
		_status.text = tr("這個素材包沒有使用精靈圖(用「匯入精靈圖…」切出來的動作才有)")
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
	dialog.title = tr("要換哪一張精靈圖?")
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
		_status.text = tr("沒有未使用的檔案。")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("清理未使用檔案")
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
	confirm.title = tr("清除動作的檔案")
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
	_status.text = tr("已把 %d 個未使用的檔案搬到備份:%s") % [result["moved"], result["backup"]] if int(result["moved"]) > 0 else tr("沒有未使用的檔案。")
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
	_status.text = message + ("" if _model.dirty else tr("(回到已存檔的內容)"))


func _update_history_buttons() -> void:
	if _undo_button != null:
		_undo_button.disabled = not _model.can_undo()
		_redo_button.disabled = not _model.can_redo()


func _after_edit(message: String) -> void:
	var synced := _model.propagate_sync() if _model.has_pack() else {"frames": 0, "objects": false}
	_after_sync(synced)
	_refresh_frame_labels_only()
	_status.text = message if message != "" else tr("有未存的變更")
	if int(synced["frames"]) > 0:
		_status.text += tr("(已同步到其他動作 %d 幀)") % int(synced["frames"])
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
	_play_button.text = tr("■ 停止預覽") if on else tr("▶ 預覽動畫")
	_layer_clock = 0.0
	_blink_next = 0.6
	_blink_left = 0.0
	if on:
		_play_timer.start()
	else:
		_play_timer.stop()
		_push_canvas_accessories()   # 停下來回到每個圖層的第一張圖


func _layers_playing() -> bool:
	return _play_button != null and _play_button.button_pressed


## 預覽播放中:圖層動畫跟著時間走(本體只有一幀的動作,像 sleep,圖層照樣會動)。
func _process(delta: float) -> void:
	if not _layers_playing() or _accs.is_empty() or _canvas == null:
		return
	_layer_clock += delta
	if _blink_left > 0.0:
		_blink_left -= delta
	else:
		_blink_next -= delta
		if _blink_next <= 0.0:
			_blink_next = randf_range(PREVIEW_BLINK_INTERVAL.x, PREVIEW_BLINK_INTERVAL.y)
			_blink_duration = 0.0
			for part: Dictionary in _accs:
				if str(part.get("role", "part")) == "blink":
					_blink_duration = maxf(_blink_duration, float(part.get("duration", PetOverlays.DEFAULT_BLINK_SECONDS)))
			_blink_left = _blink_duration
	_push_canvas_accessories()


## 預覽要畫這個圖層的哪一張圖:沒在播放就是第一張;播放中照遊戲的規則(動作對應的動畫段、fps、循環、眨眼時機)。
## 眨眼沒在眨的時候回 null(只畫十字不畫圖)。
func _layer_preview_texture(part: Dictionary) -> Texture2D:
	var clip: Dictionary = part
	if _layers_playing() and part.get("clips") is Dictionary and part.get("clip_for") is Dictionary:
		var by_action: Dictionary = part["clip_for"]
		var plain := SpritePackLoader.plain_action(_action)
		var wanted: Variant = by_action.get(_action, by_action.get(plain, null if (part.get("images") is Array and not (part["images"] as Array).is_empty()) else by_action.get("*")))
		if wanted != null and (part["clips"] as Dictionary).get(str(wanted)) is Dictionary:
			clip = part["clips"][str(wanted)]
	var images: Array = clip.get("images", []) if clip.get("images") is Array else []
	if images.is_empty():
		return null
	var crops: Array = clip.get("crops", []) if clip.get("crops") is Array else []
	var index := 0
	if _layers_playing():
		match str(part.get("role", "part")):
			"blink":
				if _blink_left <= 0.0:
					return null
				index = int(clampf(1.0 - _blink_left / maxf(_blink_duration, 0.001), 0.0, 0.999) * images.size())
			_:
				var fps := clampf(float(clip.get("fps", PetOverlays.DEFAULT_FPS)), 0.5, 60.0)
				index = int(_layer_clock * fps)
				index = index % images.size() if bool(clip.get("loop", true)) else mini(index, images.size() - 1)
	return _acc_texture(str(images[index]), crops[index] if index < crops.size() else null)


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
