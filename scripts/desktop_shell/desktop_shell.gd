extends Node2D
## 桌面行動容器根節點:初始化透明穿透視窗、覆蓋目前螢幕,
## 並實作右鍵暫時穿透機制(PASSTHROUGH_DURATION 秒)(主企劃書第二章「右鍵穿透與淡出機制」)。
##
## 視窗穿透/透明合成與「Cutout group 逐影格彙整穿透多邊形」的做法,直接繼承自兩個
## 社群參考實作,依 MIT 授權附上 credit:
## - aimforbigfoot,NAD-LAB-Godot-Projects-4.0/movingwindow-interactable
##   https://github.com/aimforbigfoot/NAD-LAB-Godot-Projects-4.0/tree/main/movingwindow-interactable
##   (只用 Window.mouse_passthrough / mouse_passthrough_polygon 兩個屬性操作,
##   每一影格持續重新套用,不使用 DisplayServer.window_set_flag() 直接切底層旗標)
## - ASecondGuy,DesktopPet(MIT License)https://github.com/ASecondGuy/DesktopPet
##   (「Cutout」group 慣例:場上想被點到的節點各自提供自己的形狀,根節點逐影格彙整成
##   一份穿透多邊形,而不是寫死單一矩形;以及用除錯線即時畫出目前的穿透範圍)

const PASSTHROUGH_DURATION := 8.0
const PASSTHROUGH_ALPHA := 0.5
const SHUTDOWN_TIMEOUT := 2.0
const SETTINGS_PATH := "user://settings.cfg"
const MAX_RECENT_PACKS := 5
var _recent_packs: Array[String] = []

const MalSpriteAdapter := preload("res://scripts/pet/sprite_adapters/mal_sprite_adapter.gd")
const StillSpriteAdapter := preload("res://scripts/pet/sprite_adapters/still_sprite_adapter.gd")
const PlatformManager := preload("res://scripts/platform/platform_manager.gd")
const PET_SCENE_PATH := "res://scenes/pet.tscn"
## 穿透多邊形沒變化時,每隔這麼多影格仍強制重設一次。
const POLYGON_REFRESH_FRAMES := 30

## 開啟後即時畫出目前送給視窗的穿透多邊形(亮粉色線),除錯用。
@export var show_debug_polygon := false
## 開機時在行動區放一隻範例桌寵(使用 Mal 素材);桌寵管理面板完成前的開發用途。
@export var spawn_sample_pet := true
## 範例桌寵的初始移動模式(0 地面、1 飛行、2 漂浮)。
@export_enum("地面", "飛行", "漂浮") var sample_pet_move_mode := 0

var _quitting := false
var _tray: Node
var _update_checker: UpdateChecker
var _manager_window: Window
var _settings_window: Window
var _tester_window: Window
var _pack_editor_window: Window
var _library_window: Window
var _props_window: Window
var _furniture_window: Window
## 打開著的「容器內容物」查看視窗:家具實例 → 視窗,雙擊同一件容器只會叫到前景,不會開第二個。
var _container_windows: Dictionary = {}
## 桌面上的小道具(丟入拾取判定、逾時消失),見 PropManager。
var prop_manager: PropManager
## 夜間螢火蟲(背景裝飾,依時段淡入淡出),見 FireflyLayer 與全局設定的「夜間螢火蟲」。
var firefly_layer: FireflyLayer
## 桌面上已經放置的家具(純裝飾,第一批還沒有讓桌寵去用),見 FurnitureManager。
var furniture_manager: FurnitureManager
## 家具編輯模式開著時顯示在行動區的「家具欄」,見 FurnitureBar。
var furniture_bar: FurnitureBar
var save_scheduler: SaveScheduler
## 行動區角落的懸浮球(hover 才現身的選單 + 道具欄),見 HoverBall。
var hover_ball: HoverBall
var _quit_dialog: ConfirmationDialog
var _globals_loaded := false
var _applied_polygon := PackedVector2Array()
var _polygon_age := 0
## 有畫面(非無頭)時,穿透多邊形掛在畫面繪製前套用。
var _polygon_before_draw := false

@onready var action_area: Node2D = $ActionArea
@onready var _pets_layer: Node2D = $ActionArea/PetsLayer
@onready var _debug_polygon_line: Line2D = $DebugPolygonLine

## 以 get_node("/root/...") 動態取得 Autoload,避開新註冊的 Autoload 在同一編輯器工作階段
## 尚未被 GDScript 靜態解析器認得為全域識別字的時序問題(自身仍是本場景的單一存取入口)。
@onready var _shell_state: Node = get_node("/root/DesktopShellState")


func _enter_tree() -> void:
	# _enter_tree() 由上而下(父節點先於子節點)執行,必須在這裡完成視窗設定,
	# 讓 ActionArea._ready() 讀到的 get_window().size 已經是最終正確尺寸——
	# 若放在 _ready() 裡,子節點的 _ready() 會先跑完,讀到的會是視窗 resize 之前的舊尺寸。
	_configure_window()


func _ready() -> void:
	# 桌面透明合成依賴 project.godot 的 rendering/gl_compatibility/driver.windows="opengl3_angle":
	# Intel UHD 這類顯卡走原生 OpenGL 時背景會變純黑,改用 ANGLE(D3D11)才正常。不要刪這個設定。
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	get_tree().root.transparent_bg = true
	# 之後新增的任何子視窗(浮動視窗、確認視窗、下拉選單、提示框…)都算「蓋在桌寵上面」的東西,見 _occluder_polygons。
	get_tree().node_added.connect(_on_node_added)
	get_tree().set_auto_accept_quit(false)
	_debug_polygon_line.visible = show_debug_polygon
	_polygon_before_draw = DisplayServer.get_name() != "headless"
	if _polygon_before_draw:
		RenderingServer.frame_pre_draw.connect(_apply_cutout_polygon)
	action_area.right_click_in_area.connect(_on_action_area_right_click)
	action_area.boundary_changed.connect(_on_action_area_boundary_changed)
	_on_action_area_boundary_changed(action_area.boundary_rect)
	if PetRoster.enabled():
		var defaults_result := AppDefaults.apply()
		if bool(defaults_result["first_run"]) or int(defaults_result["added"]) > 0:
			print("[預設值] ", defaults_result)
	_load_app_settings()
	# 一個角色一個資料夾:角色庫裡角色的舊設定檔(user://profiles、user://logic)搬進各自的資料夾(見 CharacterFiles)。無頭測試不動使用者的資料。
	if PetRoster.enabled():
		var migration := CharacterFiles.migrate_all()
		if not (migration['moved'] as Array).is_empty() or not (migration['errors'] as Array).is_empty() or not (migration['conflicts'] as Array).is_empty():
			print('[角色資料夾] 搬家:', migration)
	_shell_state.pet_ejected.connect(_on_pet_ejected)
	_shell_state.pet_registered.connect(func(pet: Node) -> void: pet.manage_requested.connect(_open_manager))
	_create_tray()
	_create_platform_system()
	prop_manager = PropManager.new()
	prop_manager.name = "PropManager"
	add_child(prop_manager)
	prop_manager.setup(action_area)
	firefly_layer = FireflyLayer.new()
	firefly_layer.name = "FireflyLayer"
	add_child(firefly_layer)
	firefly_layer.setup(action_area)
	furniture_manager = FurnitureManager.new()
	furniture_manager.name = "FurnitureManager"
	add_child(furniture_manager)
	furniture_manager.setup(action_area)
	furniture_manager.container_open_requested.connect(_open_container_contents)
	furniture_bar = FurnitureBar.new()
	furniture_bar.name = "FurnitureBar"
	add_child(furniture_bar)
	furniture_bar.setup(action_area, furniture_manager)
	hover_ball = HoverBall.new()
	hover_ball.name = "HoverBall"
	add_child(hover_ball)
	hover_ball.setup(action_area, prop_manager)
	hover_ball.action_requested.connect(_on_ball_action)
	hover_ball.right_click_requested.connect(_start_passthrough)
	add_child(preload("res://scripts/ui/ui_manager.gd").new())
	add_child(preload("res://scripts/audio/sound_manager.gd").new())
	save_scheduler = SaveScheduler.new()
	save_scheduler.name = "SaveScheduler"
	add_child(save_scheduler)
	if spawn_sample_pet:
		_restore_roster()
		_check_defaults_update.call_deferred()
		_maybe_offer_language_choice.call_deferred()


## 開機後檢查:有桌寵的預設內容(內建性格、狀態鏡…)比目前版本舊,就問使用者要不要追加(見 DefaultsUpdater)。無頭測試與「這一版不要再問」的不問。
func _check_defaults_update() -> void:
	if not PetRoster.enabled() or DefaultsUpdater.acknowledged(SETTINGS_PATH):
		return
	var outdated := DefaultsUpdater.outdated_pets(get_tree())
	if outdated.is_empty():
		return
	var dialog := make_defaults_update_dialog(outdated)
	add_child(dialog)
	dialog.popup_centered(Vector2i(500, 280))


## 「追加新的預設內容?」的確認視窗(獨立成函式方便測試)。三個選項:追加 / 之後再說(下次開機再問)/ 這一版不要再問。
func make_defaults_update_dialog(pets: Array) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("預設組資料更新")
	# 主視窗底下的確認視窗不能是獨佔式:獨佔視窗開著時,Windows 會把主視窗的穿透形狀整個丟掉(整個螢幕都點不到後面的程式);transient 也和置頂衝突(會報錯)
	dialog.exclusive = false
	dialog.transient = false
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	var names := pets.map(func(pet: Node) -> String: return pet.get_label())
	dialog.dialog_text = tr("這個版本更新了預設內容(性格、狀態鏡、反應事件等)的資料。\n是否要追加新的預設內容到既有桌寵上?\n這不會覆蓋自定義內容與手動調整過的預設參數。\n\n(手動調整過的預設參數要同步的話,到桌寵管理的「性格」分頁按「重設此性格副本」。)\n\n會更新:%s") % "、".join(names)
	dialog.dialog_autowrap = true
	dialog.ok_button_text = tr("追加新預設內容")
	dialog.cancel_button_text = tr("之後再說")
	dialog.add_button(tr("這一版不要再問"), true, "ack")
	dialog.confirmed.connect(func() -> void:
		_apply_defaults_update(pets)
		dialog.queue_free())
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"ack":
			DefaultsUpdater.acknowledge(SETTINGS_PATH)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	return dialog


## 首次啟動的中英選擇彈窗(2026-09-28):問過就不再問(見 AppSettings.language_choice_prompted,跟
## AppDefaults 的簽章式 first_run 是不同的旗標,既有使用者升級也會看到一次)。無頭測試環境直接標記已問過、
## 不彈窗(維持預設語系,行為上等同使用者選了繁體中文)。
func _maybe_offer_language_choice() -> void:
	if AppSettings.language_choice_prompted():
		return
	if DisplayServer.get_name() == "headless":
		AppSettings.mark_language_choice_prompted()
		return
	var dialog := make_language_choice_dialog()
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 220))


## 語言選擇彈窗(獨立成函式方便測試)。只有「繁體中文」與「English」兩個選項,兩種語言的文字都要看得懂
## (這時候還不知道使用者的語言),沒有第三個「取消」選項——用系統的關閉鍵/Esc 關掉一樣算選繁體中文(維持預設,
## 不強迫使用者一定要按按鈕)。
func make_language_choice_dialog() -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = "選擇語言 / Choose Language"
	dialog.exclusive = false
	dialog.transient = false
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	dialog.dialog_text = "請選擇介面與桌寵預設語言(之後可以在「全局設定」改介面語系)。\nPlease choose the interface and default pet language (you can change this later in Global Settings)."
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "繁體中文"
	dialog.add_button("English", true, "en")
	dialog.confirmed.connect(func() -> void:
		_apply_language_choice(AppSettings.DEFAULT_LANGUAGE)
		dialog.queue_free())
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"en":
			_apply_language_choice("en")
		dialog.queue_free())
	dialog.canceled.connect(func() -> void:
		_apply_language_choice(AppSettings.DEFAULT_LANGUAGE)
		dialog.queue_free())
	return dialog


## 套用語言選擇:設介面語系、標記問過了;選了非預設語言時,把「當下已經存在」的桌寵逐一釘住在原本的語言
## (PetProfile 的 dialogue_locale,見 LogicInterpreter._resolve_text),不會因為介面語系一改就連帶跟著換語言;
## 這次選擇只影響「之後新放的桌寵」(使用者 2026-09-28 明確要求)。已經自己設定過桌寵語系的(dialogue_locale
## 非空)不動,尊重使用者自己的選擇。
func _apply_language_choice(code: String) -> void:
	AppSettings.set_language(code)
	AppSettings.mark_language_choice_prompted()
	if code == AppSettings.DEFAULT_LANGUAGE:
		return
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		if str(pet.dialogue_locale) == "":
			pet.dialogue_locale = AppSettings.DEFAULT_LANGUAGE
			PetProfile.save_pet(pet)


## 把新預設內容追加到這些桌寵並存檔;回傳每隻的報告。
func _apply_defaults_update(pets: Array) -> Array:
	var reports := []
	for pet: Node in pets:
		if not is_instance_valid(pet):
			continue
		var report := DefaultsUpdater.update_pet(pet)
		PetProfile.save_pet(pet)
		reports.append({"pet": pet.get_label(), "changed": report["changed"], "lines": report["lines"]})
		print("[預設內容更新] %s:%d 項" % [pet.get_label(), report["changed"]])
	return reports


func _create_platform_system() -> void:
	var manager: Node2D = PlatformManager.new()
	action_area.add_child(manager)
	manager.setup(action_area)


## tag / display 預設是 Mal;測試「多角色」積木(在場、跟隨、雙人對話)時可放一隻辨識代號不同的同款素材(見系統匣「放一隻 Buddy」)。
## pack 非空時改用素材包(SpritePackLoader.load_pack 的結果)的圖與設定(名稱、辨識代號、縮放、朝向),數值與狀態鏡仍先給範例的(方便直接用測試包測),
## 使用者在管理視窗存過設定就以存檔為準。
## 回傳生成的桌寵;這隻的自動載入積木檔失敗(見 _apply_saved_logic)被強制退場時回 null。
## ghost = true:角色庫「桌寵管理」用的隱藏臨時實例(見 Pet.ghost_edit),不放上桌面、不進名單/自動召喚清單、
## 不進場動畫、不載入積木檔——設定檔(數值/狀態鏡/性格/交互行為)照常讀進來,存檔時管理視窗照常寫回 user://profiles/。
func _spawn_sample_pet(tag := "mal_sample", display := "Mal", pack := {}, roster_entry := {}, ghost := false) -> Node2D:
	var pet: Node2D = (load(PET_SCENE_PATH) as PackedScene).instantiate()
	if ghost:
		pet.ghost_edit = true
		pet.visible = false   # 隱藏臨時實例:不該在畫面上閃一下,也不給行動區/AI 綁定,免得平白跑起 AI。
	_pets_layer.add_child(pet)
	if not ghost:
		pet.bind_action_area(action_area)
	if pack.is_empty():
		pet.set_sprite_frames(MalSpriteAdapter.build_sprite_frames())
	else:
		var meta: Dictionary = pack["meta"]
		pet.set_sprite_frames(pack["frames"])
		pet.set_smooth_scaling(bool(meta["smooth"]))
		pet.set_body_scale(float(meta["scale"]))
		pet.set_art_flipped(bool(meta["art_flipped"]))
		var overlay_spec: Dictionary = meta.get("overlays", {})
		if not overlay_spec.is_empty():
			for line: String in pet.attach_overlays(overlay_spec, str(meta["path"])):
				push_warning("[桌寵配件 %s] %s" % [display, line])
	pet.display_name = display
	pet.recognition_tag = tag
	var is_still := not pack.is_empty() and str((pack["meta"] as Dictionary).get("kind", "active")) == "still"
	if is_still:
		_apply_still_traits(pet, pack["meta"])
	# 名單資訊要在讀設定檔之前就設好:角色庫裡的角色,設定/狀態/積木檔存在自己的資料夾(見 CharacterFiles.folder_of)。
	pet.set_meta("roster", roster_entry if not roster_entry.is_empty() else {"kind": "sample", "tag": tag, "name": display})
	var character_folder := CharacterFiles.folder_of(pet)
	if character_folder != "":
		CharacterFiles.migrate_pack(character_folder)   # 舊位置還有這個角色的檔案就搬過來(平常開機時已經搬過,這裡是保險)
	_add_sample_values(pet)
	# 使用者在管理視窗存過設定就以存檔為準,取代上面的內建範例。全域數值只在第一隻生成時載入,
	# 之後再放的桌寵共用同一份,避免重新載入把已經在編輯/使用中的定義物件換掉。
	if not _globals_loaded:
		_globals_loaded = true
		PetProfile.load_globals()
	if not PetProfile.load_pet(pet):
		DefaultsUpdater.mark_current(pet)   # 沒有設定檔 = 新放出來的桌寵,拿到的就是最新的預設內容
	PetProfile.load_state(pet)
	if ghost:
		return pet   # 隱藏臨時實例到此為止:不進場、不進名單、不載入積木檔,設定資料已經讀進來,夠管理視窗編輯了。
	# 開機自動召喚時帶著上次的移動模式與水平位置(roster_entry 的 mode / x)。
	# 從角色庫重新放上桌面等沒有名單資料的情況,改用這隻角色自己上次存的移動模式(remembered_move_mode);
	# 兩者都沒有(這隻角色第一次放出來)才用場景預設值(sample_pet_move_mode,地面)。
	var default_mode: int = pet.remembered_move_mode if pet.remembered_move_mode >= 0 else sample_pet_move_mode
	pet.set_move_mode(Pet.MoveMode.FIXED if is_still else int(roster_entry.get("mode", default_mode)))
	pet.move_mode_changed.connect(func(_mode: int) -> void: _save_roster.call_deferred())
	var rect: Rect2 = action_area.boundary_rect
	var jitter := randf_range(-120.0, 120.0) if _pets_layer.get_child_count() > 1 else 0.0
	var start_x := rect.position.x + float(roster_entry["x"]) * rect.size.x if roster_entry.has("x") else rect.get_center().x + jitter
	pet.position = Vector2(start_x, rect.position.y + 60.0)
	if is_still:
		_layout_bottom_pets()
	pet.begin_entrance()
	# 名稱是生成後才設定的(Pet._ready 當時還是預設值),所以要在這裡重新編號(同角色多隻 → (1)(2))。
	PetRegistry.refresh_labels(get_tree())
	_tray.refresh_pets()
	if not _apply_saved_logic(pet):
		return null
	_save_roster()
	return pet


## 靜止桌寵(pack.json "kind": "still"):固定貼在行動區底部、可拖曳、不自己跳舞、預設呼吸(overlays.json 的 breathing 可以調)。和舊的 Still A / B 同一套行為。
func _apply_still_traits(pet: Node2D, meta: Dictionary) -> void:
	pet.bottom_anchored = true
	pet.drag_when_fixed = true
	pet.auto_dance_enabled = false
	var overlay_spec: Dictionary = meta.get("overlays", {}) if meta.get("overlays") is Dictionary else {}
	var breathing: Dictionary = overlay_spec.get("breathing", {}) if overlay_spec.get("breathing") is Dictionary else {}
	if breathing.get("amount") is float or breathing.get("amount") is int:
		pet.breath_amount = clampf(float(breathing["amount"]), 0.0, 0.05)
	if breathing.get("period") is float or breathing.get("period") is int:
		pet.breath_period = clampf(float(breathing["period"]), 1.0, 20.0)
	pet.set_breathing(bool(breathing.get("enabled", true)))


## 這個角色有保存的積木檔(使用者導入過)就自動載入。載入失敗(檔案壞了、格式不對)視為這隻桌寵的程式有問題:
## 寫進錯誤紀錄並強制退場,不讓壞掉的角色留在桌面上。回傳是否順利。
func _apply_saved_logic(pet: Node) -> bool:
	if not PetRoster.enabled():
		return true
	var path := PetRoster.logic_path(pet.recognition_tag, CharacterFiles.folder_of(pet))
	if not FileAccess.file_exists(path) or pet.logic.load_file(path):
		return true
	_eject_failed_pet(pet, tr("已保存的積木檔載入失敗(%s),強制退場;請重新導入正確的積木檔") % path)
	return false


func _eject_failed_pet(pet: Node, reason: String) -> void:
	PetErrorLog.write(pet.get_label(), reason)
	push_warning("%s:%s" % [pet.get_label(), reason])
	_on_remove_pet(pet)


## 開機自動召喚:依上次存的名單把桌寵放回來。找不到素材包、素材包壞掉、積木檔載入失敗的那隻直接跳過
## (錯誤寫進 user://logs/pet_errors.log),名單存回剩下的;最後場上一隻都沒有就放預設角色(Mal)。
## 2026-09-30 素材包非同步載入:素材包(SpritePackLoader.load_pack)要解碼每張圖、掃描名牌像素、建材質,
## 是這個迴圈裡真正重的部分;開機存了好幾隻素材包桌寵時,原本整個迴圈一次跑完才會回到事件迴圈,場上有
## 幾隻就卡幾份的載入時間,畫面完全沒反應。改成每放完一隻素材包桌寵就讓一影格出去(await process_frame),
## 把「一次long freeze」拆成「一連串使用者感覺不到的小停頓」,中間輸入/畫面照樣能回應;桌寵會變成一隻隻
## 陸續冒出來,而不是全部卡住之後一次全部出現。sample/still 這兩種很輕,不用跟著等。
## 評估過真正的多執行緒背景解碼(SpritePackLoader.load_pack 拆成「背景解碼圖片」+「主執行緒建材質」兩階段):
## 風險較高(靜態快取 _sheet_cache 要改成非共享、材質建立本來就得留在主執行緒,拆分本身有機會在打包前引入
## 新 bug),使用者確認先做這個風險低很多、但能解決大半實際感受到的問題的版本。
func _restore_roster() -> void:
	for entry: Dictionary in PetRoster.load_entries():
		match str(entry["kind"]):
			"sample":
				if BuildProfile.has_sample_pets():
					_spawn_sample_pet(str(entry["tag"]), str(entry["name"]), {}, entry)
			"still":
				if BuildProfile.has_stills():
					_spawn_still(str(entry["which"]))
			"pack":
				_spawn_pack(str(entry["path"]), true, entry)
				await get_tree().process_frame
	if get_tree().get_nodes_in_group("pets").is_empty():
		_spawn_default_pet()
	_save_roster()


## 開機名單是空的(或全部失敗)時放的預設桌寵:開發專案放範例 Mal;發行版沒有測試素材,改放角色庫裡的預設活動桌寵(第一次會先把預設角色裝進角色庫),都放不出來就什麼都不放。
func _spawn_default_pet() -> Node2D:
	if BuildProfile.has_sample_pets():
		return _spawn_sample_pet()
	SpriteLibrary.ensure_default_characters()
	var folder := SpriteLibrary.root_dir().path_join(SpriteLibrary.DEFAULT_CHARACTER)
	if DirAccess.dir_exists_absolute(folder):
		return _spawn_pack(folder)
	return null


## 把目前場上的桌寵名單存起來(依生成先後),下次開機自動召喚。
func _save_roster() -> void:
	var pets: Array = get_tree().get_nodes_in_group("pets").filter(func(p: Node) -> bool: return not p.is_queued_for_deletion() and p.has_meta("roster"))
	pets.sort_custom(func(a: Node, b: Node) -> bool: return a.spawn_serial < b.spawn_serial)
	PetRoster.save(pets.map(_roster_entry_for))


## 名單項目 = 怎麼重生(Pet meta "roster")+ 現在的移動模式與水平位置比例(半身立繪固定貼底,由排版決定,不存)。
func _roster_entry_for(pet: Node) -> Dictionary:
	var entry: Dictionary = (pet.get_meta("roster") as Dictionary).duplicate()
	if str(entry.get("kind", "")) != "still":
		var rect: Rect2 = action_area.boundary_rect
		entry["mode"] = int(pet.move_mode)
		entry["x"] = clampf((pet.position.x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
	return entry


## 放一隻半身立繪(Still A / B):固定不動、貼行動區底部生成,尺寸預設縮小(見 StillSpriteAdapter),同一個角色已在場就不再重複放。
func _spawn_still(which: String) -> Node2D:
	var tag := "still_%s" % which.to_lower()
	for existing: Node in get_tree().get_nodes_in_group("pets"):
		if existing.recognition_tag == tag:
			return null
	var pet: Node2D = (load(PET_SCENE_PATH) as PackedScene).instantiate()
	_pets_layer.add_child(pet)
	pet.bind_action_area(action_area)
	pet.set_sprite_frames(StillSpriteAdapter.build_sprite_frames(which))
	pet.display_name = "Still %s" % which
	pet.recognition_tag = tag
	pet.bottom_anchored = true
	pet.drag_when_fixed = true
	pet.auto_dance_enabled = false
	pet.set_smooth_scaling(true)
	pet.set_body_scale(StillSpriteAdapter.DEFAULT_SCALE)
	# 半身立繪:預設開呼吸動畫;浮動差分與配件依 overlays.json(有的話)。
	var config := StillSpriteAdapter.load_config(which)
	var breathing: Dictionary = config.get("breathing", {}) if config.get("breathing") is Dictionary else {}
	if breathing.get("amount") is float or breathing.get("amount") is int:
		pet.breath_amount = clampf(float(breathing["amount"]), 0.0, 0.05)
	if breathing.get("period") is float or breathing.get("period") is int:
		pet.breath_period = clampf(float(breathing["period"]), 1.0, 20.0)
	pet.set_breathing(bool(breathing.get("enabled", true)))
	if not config.is_empty():
		for line: String in pet.attach_overlays(config, StillSpriteAdapter.SETS[which]["dir"]):
			push_warning("[立繪配件 %s] %s" % [which, line])
	if not PetProfile.load_pet(pet):
		DefaultsUpdater.mark_current(pet)
	PetProfile.load_state(pet)
	pet.set_move_mode(3)
	_layout_bottom_pets()
	pet.begin_entrance()
	PetRegistry.refresh_labels(get_tree())
	_tray.refresh_pets()
	pet.set_meta("roster", {"kind": "still", "which": which})
	pet.move_mode_changed.connect(func(_mode: int) -> void: _save_roster.call_deferred())
	if not _apply_saved_logic(pet):
		return null
	_save_roster()
	return pet


## 貼底角色(半身立繪)依生成先後,在行動區底邊上平均排開;行動區被拉大縮小時也重新排。
## 被使用者拖過的(layout_pinned)保持在使用者放的位置(只確保還在行動區內),不參與排開;系統匣「重新排開半身立繪」會解除釘選。
func _layout_bottom_pets() -> void:
	var anchored: Array = get_tree().get_nodes_in_group("pets").filter(func(p: Node) -> bool: return p.bottom_anchored and p.move_mode == Pet.MoveMode.FIXED and not p.is_queued_for_deletion())
	anchored.sort_custom(func(a: Node, b: Node) -> bool: return a.spawn_serial < b.spawn_serial)
	var rect: Rect2 = action_area.boundary_rect
	var loose: Array = anchored.filter(func(p: Node) -> bool: return not p.layout_pinned)
	for pinned: Node in anchored.filter(func(p: Node) -> bool: return p.layout_pinned):
		pinned.position = pinned.clamp_to_bounds(pinned.position)
	for i in loose.size():
		loose[i].position = Vector2(rect.position.x + rect.size.x * (i + 1.0) / (loose.size() + 1.0), rect.end.y)
	# 每隻立繪在 DrawLayers 的立繪帶裡佔一格(依生成先後),本體與配件都因此在所有一般桌寵後面。
	for i in anchored.size():
		anchored[i].set_still_band(i)


func _on_relayout_stills() -> void:
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		if pet.bottom_anchored:
			pet.layout_pinned = false
	_layout_bottom_pets()


## 系統匣「再放一隻範例桌寵」:同一個角色可以同時有好幾隻,各自有自己的狀態、狀態鏡與位置。
func _on_add_pet() -> void:
	_spawn_sample_pet()


## 從素材包資料夾放一隻桌寵(見 SpritePackLoader / docs/素材包格式.md)。讀取報告(略過了什麼、對應了什麼)寫進日誌。
func _spawn_pack(folder: String, from_roster := false, roster_entry := {}) -> Node2D:
	var result := SpritePackLoader.load_pack(folder)
	for line: String in result["report"]:
		print("[素材包] ", line)
	if not bool(result["ok"]):
		var message := tr("素材包載入失敗:%s(資料夾:%s)") % [result["report"][0], folder]
		push_warning(message)
		PetErrorLog.write("素材包", message + (";開機自動召喚時略過此角色" if from_roster else ""))
		return null
	var meta: Dictionary = result["meta"]
	var pet := _spawn_sample_pet(str(meta["tag"]), str(meta["name"]), result, roster_entry if not roster_entry.is_empty() else {"kind": "pack", "path": folder})
	if pet != null and not from_roster:
		_remember_pack(folder)
	return pet


func _on_add_pack() -> void:
	FloatingWindow.native_file_dialog(tr("選擇素材包資料夾"), SpriteLibrary.root_dir(), DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(),
			func(paths: PackedStringArray) -> void: _spawn_pack(paths[0]))


## 精靈圖編輯器(見 PackEditorWindow):開一個空的編輯視窗(同時只會有一個),素材包資料夾與圖片都在視窗裡用按鈕選。
func _on_edit_pack() -> void:
	if is_instance_valid(_pack_editor_window):
		_pack_editor_window.bring_to_front()
		return
	open_pack_editor()


## 角色庫(見 CharacterLibraryWindow):同時只會有一個。放上桌面與編輯都交給這裡的既有流程。
func _open_library() -> void:
	if is_instance_valid(_library_window):
		_library_window.bring_to_front()
		return
	var window := CharacterLibraryWindow.new()
	add_child(window)
	window.setup()
	window.place_requested.connect(func(folder: String) -> void: _spawn_pack(folder))
	window.edit_requested.connect(func(folder: String) -> void: open_pack_editor(folder))
	window.settings_requested.connect(_open_character_settings)
	_library_window = window


## 角色庫「桌寵管理」按鈕:不用把角色放上桌面就能改數值/狀態鏡/性格/交互行為——自動生成一隻隱藏的臨時實例
## (Pet.ghost_edit,不進名單、不進場、不載積木檔),管理視窗只給編輯這一隻(見 ManagerWindow.setup_for_single_pet)。
## 視窗關閉(不管是存檔後關還是不儲存關,見 ManagerWindow._request_close/_discard_and_close 都會走到 queue_free)
## 就收掉這隻臨時實例。
func _open_character_settings(folder: String) -> void:
	var result := SpritePackLoader.load_pack(folder)
	if not bool(result["ok"]):
		PetErrorLog.write("角色庫", tr("素材包載入失敗:%s(資料夾:%s)") % [result["report"][0], folder])
		return
	var meta: Dictionary = result["meta"]
	var ghost := _spawn_sample_pet(str(meta["tag"]), str(meta["name"]), result, {"kind": "pack", "path": folder}, true)
	if ghost == null:
		return
	var window := ManagerWindow.new()
	add_child(window)
	window.setup_for_single_pet(ghost, tr("桌寵管理 - %s") % meta["name"])
	window.tree_exiting.connect(func() -> void:
		if is_instance_valid(ghost):
			ghost.queue_free())


## 開精靈圖編輯器視窗。folder 非空就順便開啟那個素材包資料夾(失敗時視窗仍會開,錯誤顯示在視窗裡並寫進錯誤紀錄)。
## 已經有編輯器開著時不會直接把它關掉(會丟掉沒存的變更):沿用那個視窗,有未存的變更就先問「存檔後繼續 / 放棄 / 取消」再切換。
func open_pack_editor(folder := "") -> PackEditorWindow:
	if is_instance_valid(_pack_editor_window):
		var existing := _pack_editor_window as PackEditorWindow
		existing.bring_to_front()
		if folder != "":
			existing.guard_unsaved(func() -> void:
				var switch_error := existing.open_folder(folder)
				if switch_error != "":
					PetErrorLog.write("精靈圖編輯器", tr("無法開啟素材包:%s(%s)") % [switch_error, folder]), "切換")
		return existing
	var window := PackEditorWindow.new()
	add_child(window)
	window.saved.connect(reload_pack_pets)
	# 角色庫視窗(如果開著)快取了這個資料夾的縮圖/動作數摘要,存檔後要丟掉重算,不然編輯完回角色庫還是看到存檔前的樣子(或一直卡在「讀不出素材」)。
	window.saved.connect(func(saved_folder: String) -> void:
		if is_instance_valid(_library_window):
			(_library_window as CharacterLibraryWindow).invalidate(saved_folder))
	var error := window.setup(folder)
	if error != "":
		PetErrorLog.write("精靈圖編輯器", tr("無法開啟素材包:%s(%s)") % [error, folder])
	_pack_editor_window = window
	return window


## 精靈圖編輯器存檔後:桌面上用這個素材包資料夾生成的桌寵直接換上新圖(見 Pet.reload_pack)。回傳更新了幾隻。
func reload_pack_pets(folder: String) -> int:
	var normalized := folder.replace("\\", "/").trim_suffix("/")
	var updated := 0
	var pack: Dictionary = {}
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		var entry: Variant = pet.get_meta("roster", {})
		if not (entry is Dictionary and str(entry.get("kind", "")) == "pack" and str(entry.get("path", "")).replace("\\", "/").trim_suffix("/") == normalized):
			continue
		if pack.is_empty():
			pack = SpritePackLoader.load_pack(normalized)   # 載入一次,每隻各自用(SpriteFrames 資源可共用)
		if not bool(pack.get("ok", false)):
			PetErrorLog.write("精靈圖編輯器", tr("存檔後重新載入素材包失敗:%s") % ", ".join(PackedStringArray(pack.get("report", []))))
			return updated
		pet.reload_pack(pack)
		updated += 1
	return updated


## 開精靈圖編輯器的道具區(編輯某個道具的進階貼圖)。已經有編輯器開著時沿用它,有未存的變更先問。
func open_prop_editor(prop_id: String) -> PackEditorWindow:
	if is_instance_valid(_pack_editor_window):
		var existing := _pack_editor_window as PackEditorWindow
		existing.bring_to_front()
		existing.guard_unsaved(func() -> void:
			var switch_error := existing.open_prop(prop_id)
			if switch_error != "":
				PetErrorLog.write("精靈圖編輯器", tr("無法開啟道具貼圖:%s(%s)") % [switch_error, prop_id]), "切換")
		return existing
	var window := PackEditorWindow.new()
	add_child(window)
	window.saved.connect(reload_pack_pets)
	window.setup()
	var error := window.open_prop(prop_id)
	if error != "":
		PetErrorLog.write("精靈圖編輯器", tr("無法開啟道具貼圖:%s(%s)") % [error, prop_id])
	_pack_editor_window = window
	return window


## 開精靈圖編輯器的家具區(編輯某件家具的進階貼圖)。已經有編輯器開著時沿用它,有未存的變更先問。
func open_furniture_editor(furniture_id: String) -> PackEditorWindow:
	if is_instance_valid(_pack_editor_window):
		var existing := _pack_editor_window as PackEditorWindow
		existing.bring_to_front()
		existing.guard_unsaved(func() -> void:
			var switch_error := existing.open_furniture(furniture_id)
			if switch_error != "":
				PetErrorLog.write("精靈圖編輯器", tr("無法開啟家具貼圖:%s(%s)") % [switch_error, furniture_id]), "切換")
		return existing
	var window := PackEditorWindow.new()
	add_child(window)
	window.furniture_settings_requested.connect(_open_furniture_library)
	window.setup()
	var error := window.open_furniture(furniture_id)
	if error != "":
		PetErrorLog.write("精靈圖編輯器", tr("無法開啟家具貼圖:%s(%s)") % [error, furniture_id])
	_pack_editor_window = window
	return window


## 記住最近用過的素材包資料夾(最多 MAX_RECENT_PACKS 個,新的在前),系統匣選單可一鍵再放一隻。
func _remember_pack(folder: String) -> void:
	_recent_packs.erase(folder)
	_recent_packs.push_front(folder)
	while _recent_packs.size() > MAX_RECENT_PACKS:
		_recent_packs.pop_back()
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("packs", "recent", PackedStringArray(_recent_packs))
	config.save(SETTINGS_PATH)
	_tray.recent_packs = _recent_packs
	_tray.refresh_pets()


func _on_add_buddy() -> void:
	for existing: Node in get_tree().get_nodes_in_group("pets"):
		if existing.recognition_tag == "buddy":
			return
	_spawn_sample_pet("buddy", "Buddy")


## 積木失控、被看門狗強制退場的桌寵:直接移除(原因已由直譯器寫進錯誤紀錄),系統匣選單會更新。
func _on_pet_ejected(pet: Node, reason: String) -> void:
	if not is_instance_valid(pet) or pet.is_queued_for_deletion():
		return
	push_warning("%s 被強制退場:%s" % [pet.get_label(), reason])
	_on_remove_pet(pet)


## 系統匣「移除這隻桌寵」:直接從場上拿掉(退場動畫等 leave 素材流程做好再接)。
## 使用者從系統匣要收起一隻桌寵:它正在幫你計時(跑著或暫停著)的話先問要暫停還是取消計時、並列出目前的計時情形。
## 對話框是獨立視窗、置頂(桌寵自己不能跳彈窗問,但這是使用者主動按的選單,可以)。
func _on_remove_pet_requested(pet: Node) -> void:
	if not is_instance_valid(pet):
		return
	if pet.pet_timer == null or not pet.pet_timer.has_timing():
		_on_remove_pet(pet)
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("收起桌寵")
	# 主視窗底下的確認視窗不能是獨佔式:獨佔視窗開著時,Windows 會把主視窗的穿透形狀整個丟掉(整個螢幕都點不到後面的程式);transient 也和置頂衝突(會報錯)
	dialog.exclusive = false
	dialog.transient = false
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	dialog.dialog_text = tr("「%s」正在幫你計時:\n%s\n\n收起來之前,計時要怎麼處理?") % [pet.get_label(), pet.pet_timer.describe()]
	dialog.dialog_autowrap = true
	dialog.ok_button_text = tr("暫停計時並收起")
	dialog.cancel_button_text = tr("先不收起")
	dialog.add_button(tr("取消計時並收起"), true, "cancel_timer")
	dialog.confirmed.connect(func() -> void:
		_on_remove_pet(pet)   # 收起 = 暫停計時並存起來,下次出現時桌寵會說出記到的時間
		dialog.queue_free())
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"cancel_timer" and is_instance_valid(pet):
			pet.pet_timer.cancel()
			_on_remove_pet(pet)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if DisplayServer.get_name() != "headless":
		dialog.popup_centered(Vector2i(460, 240))


## 系統匣「檢查更新…」:使用者主動點的,才會真的連線;結果用一個小視窗回報(這是使用者主動觸發的操作,不是桌寵自己跳彈窗)。
func _on_check_update_requested() -> void:
	_update_checker.check_for_update()


func _on_update_check_finished(result: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = tr("檢查更新")
	dialog.exclusive = false
	dialog.transient = false
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	dialog.dialog_text = String(result.get("message", ""))
	dialog.dialog_autowrap = true
	if result.get("status", "") == "update_available":
		dialog.add_button(tr("前往下載頁"), true, "open_releases")
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"open_releases":
			OS.shell_open(_update_checker.releases_page_url())
		dialog.queue_free())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	if DisplayServer.get_name() != "headless":
		dialog.popup_centered(Vector2i(420, 200))


func _on_remove_pet(pet: Node) -> void:
	if not is_instance_valid(pet):
		return
	if pet.pet_timer != null:
		pet.pet_timer.pause_and_save()   # 收起來 = 暫停計時,下次出現時桌寵會說出記到的時間
	pet.get_parent().remove_child(pet)
	pet.queue_free()
	PetRegistry.refresh_labels(get_tree())
	_tray.refresh_pets()
	_save_roster()




## 範例數值,方便測試 Status 面板與積木讀寫;等數值管理介面完成後改由資源檔設定。
## 「神秘彩蛋」刻意不勾選在 Status 顯示,示範白名單預設隱藏。
func _add_sample_values(pet: Node) -> void:
	if _shell_state.global_value_defs.is_empty():
		var coins := PetValueDef.new()
		coins.key = "通用金幣"
		coins.is_global = true
		coins.min_value = 0.0
		coins.show_in_status = true
		coins.sort_weight = 2
		coins.suffix = " G"
		_shell_state.global_value_defs.append(coins)
	pet.add_value_def(_make_sample_value("好感度", 50.0, 100.0, 0, "", true, PetValueDef.DisplayMode.BAR))
	pet.add_value_def(_make_sample_value("飽食度", 80.0, 100.0, 1, "%", true, PetValueDef.DisplayMode.BAR))
	pet.add_value_def(_make_sample_value("心情", 65.0, 100.0, 2, "", true, PetValueDef.DisplayMode.GAUGE))
	pet.add_value_def(_make_sample_value("神秘彩蛋", 0.0, 1.0, 9, "", false, PetValueDef.DisplayMode.TEXT))


func _make_sample_value(key: String, default_value: float, max_value: float, weight: int, suffix: String, in_status: bool, mode: PetValueDef.DisplayMode) -> PetValueDef:
	var def := PetValueDef.new()
	def.key = key
	def.default_value = default_value
	def.min_value = 0.0
	def.max_value = max_value
	def.sort_weight = weight
	def.suffix = suffix
	def.show_in_status = in_status
	def.display_mode = mode
	return def


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_graceful_quit()


func _create_tray() -> void:
	_tray = preload("res://scripts/desktop_shell/tray_controller.gd").new()
	add_child(_tray)
	_update_checker = UpdateChecker.new()
	add_child(_update_checker)
	_update_checker.check_finished.connect(_on_update_check_finished)
	_tray.toggle_frame_requested.connect(_on_tray_toggle_frame)
	_tray.recall_requested.connect(_on_tray_recall)
	_tray.windows_reset_requested.connect(reset_floating_windows)
	_tray.quit_requested.connect(_graceful_quit)
	_tray.move_mode_requested.connect(_on_tray_move_mode)
	_tray.export_schema_requested.connect(_on_export_schema)
	_tray.import_logic_requested.connect(_on_import_logic)
	_tray.open_manager_requested.connect(_open_manager)
	_tray.open_settings_requested.connect(_open_settings)
	_tray.auto_chat_toggled.connect(_on_auto_chat_toggled)
	_tray.add_pet_requested.connect(_on_add_pet)
	_tray.add_buddy_requested.connect(_on_add_buddy)
	_tray.add_pack_requested.connect(_on_add_pack)
	_tray.add_pack_path_requested.connect(_spawn_pack)
	_tray.edit_pack_requested.connect(_on_edit_pack)
	_tray.open_library_requested.connect(_open_library)
	_tray.open_props_requested.connect(_open_props)
	_tray.clear_props_requested.connect(clear_props)
	_tray.open_furniture_requested.connect(_open_furniture_library)
	_tray.recent_packs = _recent_packs
	_tray.add_still_requested.connect(_spawn_still)
	_tray.relayout_stills_requested.connect(_on_relayout_stills)
	_tray.make_canonical_requested.connect(_on_make_canonical)
	_tray.remove_pet_requested.connect(_on_remove_pet_requested)
	_tray.open_tester_requested.connect(_open_tester)
	_tray.open_error_log_requested.connect(func() -> void: OS.shell_open(PetErrorLog.folder_global()))
	_tray.debug_polygon_visible = show_debug_polygon
	_tray.debug_polygon_toggled.connect(_on_debug_polygon_toggled)
	_tray.say_something_requested.connect(func(pet: Node) -> void: pet.say_something())
	_tray.force_rest_requested.connect(func(pet: Node) -> void: pet.vitality.force_rest())
	_tray.check_update_requested.connect(_on_check_update_requested)


## 除錯:用亮粉色線即時畫出目前送給視窗的穿透多邊形,拋飛桌寵時看貼圖有沒有超出這個範圍。
func _on_debug_polygon_toggled(enabled: bool) -> void:
	show_debug_polygon = enabled
	_debug_polygon_line.visible = enabled
	if not enabled:
		_debug_polygon_line.points = PackedVector2Array()


## 自動閒聊總開關:寫進共享狀態並存到 user://settings.cfg [chat](只覆寫自己的區段),選單重建以更新勾選。
func _on_auto_chat_toggled(enabled: bool) -> void:
	_shell_state.auto_chat_enabled = enabled
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("chat", "auto_chat_enabled", enabled)
	config.save(SETTINGS_PATH)
	_tray.refresh_pets()


func _load_app_settings() -> void:
	AppSettings.apply_startup()
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_shell_state.auto_chat_enabled = bool(config.get_value("chat", "auto_chat_enabled", true))
		var policy := str(config.get_value("clone", "canonical_policy", "earliest"))
		_shell_state.canonical_policy = policy if policy in ["earliest", "latest"] else "earliest"
		var recent: Variant = config.get_value("packs", "recent", PackedStringArray())
		if recent is PackedStringArray or recent is Array:
			for path in recent:
				if str(path) != "" and _recent_packs.size() < MAX_RECENT_PACKS:
					_recent_packs.append(str(path))


## 開啟(或叫到前景)管理視窗:數值與狀態鏡的編輯介面。同時只會有一個。
func _open_manager() -> void:
	if is_instance_valid(_manager_window):
		_manager_window.bring_to_front()
		return
	_manager_window = ManagerWindow.new()
	add_child(_manager_window)
	_manager_window.setup()


## 開啟(或叫到前景)全局設定視窗(音效、介面語系、效能、編輯器外觀)。同時只會有一個。
func _open_settings() -> void:
	if is_instance_valid(_settings_window):
		_settings_window.bring_to_front()
		return
	_settings_window = GlobalSettingsWindow.new()
	add_child(_settings_window)
	_settings_window.setup()
	_settings_window.audio_setting_requested.connect(_on_audio_setting)


## 懸浮球選單的按鈕:開對應的視窗(道具欄與清空道具由球自己處理)。
func _on_ball_action(action: String) -> void:
	match action:
		"props":
			_open_props()
		"furniture":
			_open_furniture_library()
		"library":
			_open_library()
		"manager":
			_open_manager()
		"settings":
			_open_settings()
		"tester":
			_open_tester()
		"pack_editor":
			_on_edit_pack()


## 清空桌面上丟出來的道具(系統匣、小道具視窗、懸浮球共用),回傳清掉幾個。
func clear_props() -> int:
	return prop_manager.clear_all()


## 開啟(或叫到前景)小道具視窗(物品欄:丟到桌面、新增與編輯小道具)。同時只會有一個。
func _open_props() -> void:
	if is_instance_valid(_props_window):
		_props_window.bring_to_front()
		return
	_props_window = PropsWindow.new()
	add_child(_props_window)
	_props_window.setup(prop_manager)
	(_props_window as PropsWindow).edit_sprite_requested.connect(func(prop_id: String) -> void: open_prop_editor(prop_id))


## 開啟(或叫到前景)家具庫視窗(第一批純裝飾:新增/改名/觸發方式、放上桌面,見 FurnitureWindow)。同時只會有一個。
func _open_furniture_library() -> void:
	if is_instance_valid(_furniture_window):
		_furniture_window.bring_to_front()
		return
	_furniture_window = FurnitureWindow.new()
	add_child(_furniture_window)
	_furniture_window.setup(furniture_manager)
	(_furniture_window as FurnitureWindow).edit_sprite_requested.connect(func(furniture_id: String) -> void: open_furniture_editor(furniture_id))


## 使用者雙擊一件容器家具:開啟(或叫到前景)它的「查看內容物」視窗(見 FurnitureManager.container_open_requested、
## ContainerContentsWindow)。同一件容器同時只會有一個。
func _open_container_contents(item: FurnitureItem) -> void:
	if not is_instance_valid(item):
		return
	var existing: Variant = _container_windows.get(item)
	if existing is ContainerContentsWindow and is_instance_valid(existing):
		existing.bring_to_front()
		return
	var window := ContainerContentsWindow.new()
	add_child(window)
	window.setup(item)
	_container_windows[item] = window


## 開啟(或叫到前景)測試者視窗:強制觸發指定桌寵的對話、動作、事件、狀態鏡等,方便測試。同時只會有一個。
func _open_tester() -> void:
	if is_instance_valid(_tester_window):
		_tester_window.bring_to_front()
		return
	_tester_window = TesterWindow.new()
	add_child(_tester_window)
	_tester_window.setup()


## 音效設定(靜音/說話音效/音量):寫進共享狀態並通知 SoundManager 套用與存檔。
func _on_audio_setting(kind: String, value: Variant) -> void:
	match kind:
		"mute":
			_shell_state.audio_muted = bool(value)
		"speak":
			_shell_state.speak_sound_enabled = bool(value)
		"volume":
			_shell_state.audio_volume = clampf(float(value), 0.0, 1.0)
	_shell_state.audio_settings_changed.emit()


## 導出 Schema:開系統儲存對話框,把該桌寵的資料寫成 HTML 積木編輯器可讀的 JSON。
func _on_export_schema(pet: Node) -> void:
	FloatingWindow.native_file_dialog(tr("導出 Schema"), "", DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(["*.json;JSON"]),
			func(paths: PackedStringArray) -> void:
				if is_instance_valid(pet):
					var error := SchemaExporter.save(pet, paths[0])
					if error != OK:
						push_warning("Schema 導出失敗: %s" % error_string(error)),
			0, "%s.schema.json" % pet.recognition_tag)


## 導入積木檔:開系統開啟對話框,讀入 HTML 編輯器導出的邏輯 JSON 給該桌寵執行。
func _on_import_logic(pet: Node) -> void:
	FloatingWindow.native_file_dialog(tr("導入積木檔"), "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.json;JSON"]),
			func(paths: PackedStringArray) -> void:
				if is_instance_valid(pet):
					# 導入成功就複製一份保存,之後這個角色每次生成都會自動載入(見 _apply_saved_logic)。
					if pet.logic.load_file(paths[0]):
						PetRoster.store_logic(pet.recognition_tag, paths[0], CharacterFiles.folder_of(pet))
					_tray.refresh_pets())


func _on_tray_toggle_frame() -> void:
	action_area.set_frame_visible(not action_area.frame_visible)


func _on_tray_move_mode(pet: Node, mode: int) -> void:
	pet.set_move_mode(mode)


## 行動區重設:視窗重新貼合目前螢幕、行動區重設為預設大小並置中,並通知場上所有桌寵回到中央。
func _on_tray_recall() -> void:
	_configure_window()
	var decor := get_tree().root.get_node_or_null("DecorOverlay") as DecorOverlay
	if decor != null and decor.usable:
		decor.keep_behind_main()
	action_area.recenter(Vector2(get_window().size) * 0.5)
	_shell_state.emergency_recall_requested.emit()


## 浮動視窗重設:所有開著的浮動視窗(藏起來的也算)拉到最上層、拉回螢幕範圍內。回傳處理了幾個視窗。
func reset_floating_windows() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("floating_windows"):
		if node is FloatingWindow:
			(node as FloatingWindow).reset_window()
			count += 1
	return count


## 安全退出:先通知桌寵播放 leave 退場動作,等它們放行(或最多 SHUTDOWN_TIMEOUT 秒)才真正關閉。
## 關閉遊戲的入口:先檢查同角色複製品有沒有「狀態不同又還沒指定本體」的,有就逐組詢問(最早/最晚政策可記住),
## 全部處理完才真的退出;取消就整個不退出。強制結束(工作管理員)我們無能為力,不會有這個提醒。
func _graceful_quit() -> void:
	if _quitting or is_instance_valid(_quit_dialog):
		return
	_ask_canonicals(PetRegistry.divergent_groups(get_tree()), {})


func _ask_canonicals(pending: Dictionary, chosen: Dictionary) -> void:
	if pending.is_empty():
		_save_states(chosen)
		_finish_quit()
		return
	var key: String = pending.keys()[0]
	var pets: Array = pending[key]
	pending.erase(key)
	_quit_dialog = CanonicalDialog.new()
	add_child(_quit_dialog)
	_quit_dialog.setup(key, pets, _shell_state.canonical_policy)
	_quit_dialog.resolved.connect(func(choice: Node, policy: String) -> void:
		_set_canonical_policy(policy)
		chosen[key] = choice
		_quit_dialog.queue_free()
		_ask_canonicals(pending, chosen))
	_quit_dialog.canceled.connect(func() -> void: _quit_dialog.queue_free())
	_quit_dialog.popup_centered()


## 存每個角色本體的狀態:已指定的用指定者(指定「不存」的略過),其餘用預設政策選出的那隻。
func _save_states(chosen: Dictionary) -> void:
	var all := PetRegistry.groups(get_tree())
	for key in all:
		var pet: Node = chosen[key] if chosen.has(key) else PetRegistry.pick_default(all[key], _shell_state.canonical_policy)
		if pet != null and is_instance_valid(pet):
			PetProfile.save_state(pet)


func _set_canonical_policy(policy: String) -> void:
	_shell_state.canonical_policy = policy
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("clone", "canonical_policy", policy)
	config.save(SETTINGS_PATH)


## 系統匣「以這隻為本體」:立刻把這隻的狀態複製給同角色的所有其他複製品。
func _on_make_canonical(pet: Node) -> void:
	for other: Node in PetRegistry.groups(get_tree()).get(pet.recognition_tag if pet.recognition_tag != "" else pet.display_name, []):
		if other != pet:
			other.adopt_state_from(pet)


func _finish_quit() -> void:
	if _quitting:
		return
	_quitting = true
	_save_roster()
	# 結束前把還在佇列裡的存檔寫完,再存一次全域數值(角色狀態已由上面的結束流程存過)。
	save_scheduler.save_now("quit", false)
	save_scheduler.flush()
	_shell_state.shutdown_requested.emit()
	var deadline := get_tree().create_timer(SHUTDOWN_TIMEOUT)
	while _shell_state.has_shutdown_holds() and deadline.time_left > 0.0:
		await get_tree().process_frame
	get_tree().quit()


func _process(_delta: float) -> void:
	# 持續每影格重新套用穿透狀態,而不是只在事件發生當下設定一次(見檔頭 credit)。
	# 平時 mouse_passthrough 必須是 false,多邊形才會決定「哪裡收得到滑鼠」;實測平時設成 true
	# 整個視窗都收不到點擊(把手拖不動、右鍵沒反應),而且背景也沒有因此變透明,所以改回 false。
	var window := get_window()
	if not window.transparent:
		window.transparent = true
	if _shell_state.is_passthrough_frozen:
		# 右鍵暫時穿透:整個視窗完全無視點擊。
		window.mouse_passthrough = true
		_debug_polygon_line.points = PackedVector2Array()
	else:
		window.mouse_passthrough = false
		# 有畫面時穿透形狀在「畫之前」才套用(見 _apply_cutout_polygon);沒有畫面(無頭測試)就在這裡套用。
		if not _polygon_before_draw:
			_apply_cutout_polygon()


## 套用穿透多邊形。掛在 RenderingServer.frame_pre_draw:此時所有節點的 _process、計時器、對話氣泡的排版與容器重排都做完了,
## 形狀對得上「這一影格馬上要畫的內容」。放在 _process 的話,之後才由計時器/積木冒出來的氣泡、被重排長大的氣泡都會慢一影格,
## 畫出來的部分被視窗區域裁掉(對話與選項剛出現時破圖)。
func _apply_cutout_polygon() -> void:
	if _shell_state.is_passthrough_frozen or _quitting:
		return
	var polygon := _collect_cutout_polygon()
	# 視窗形狀沒變就不再重設:每影格都換一份新的視窗區域(Windows 上是 SetWindowRgn)會讓合成器一直重新裁切,
	# 邊緣容易閃爍/破圖,形狀越複雜(桌寵、氣泡越多)越明顯。隔一小段時間還是強制重設一次(視窗被系統重建時能自己復原)。
	_polygon_age += 1
	if polygon != _applied_polygon or _polygon_age >= POLYGON_REFRESH_FRAMES:
		get_window().mouse_passthrough_polygon = polygon
		_applied_polygon = polygon
		_polygon_age = 0
	if show_debug_polygon:
		_debug_polygon_line.points = polygon
		queue_redraw()


## 除錯:粉色線是穿透形狀(判定框 ∪ 顯示範圍),藍框是每隻桌寵的互動判定框(只有藍框裡點得到、抓得起)。
func _draw() -> void:
	if not show_debug_polygon:
		return
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		draw_rect(pet.get_body_rect(), Color(0.3, 0.7, 1.0, 0.9), false, 2.0)


## 空間分格用的格子邊長(像素):給 _collect_cutout_polygon 的「已覆蓋形狀」廣域比對用,見那裡的說明。
## 隨便選一個比常見形狀(桌寵身體、對話氣泡、光暈)大上幾圈的值,格子太小會讓一個形狀橫跨太多格,
## 格子太大則失去分格的意義(退化成全部都在同一格);這個量級抓桌寵身體的幾倍寬,實測夠用。
const CUTOUT_GRID_CELL := 220.0


## 彙整場上所有「Cutout」group 成員各自的可點擊形狀,合成一份穿透多邊形。
## 成員實作 get_cutout_polygons() -> Array(每個元素是一個簡單多邊形,全域座標)。
## 視窗的穿透區域是單一多邊形,而且重疊的部分會被當成洞(奇偶填色),所以後面的形狀要先扣掉
## 前面已經算進去的部分,確保輸出的每個環彼此不重疊;環與環之間用 (0,0) 當橋接點串起來,
## 每個環走完後都回到 (0,0),橋接線來回重合、面積為零(這個串接法沿用 DesktopPet)。
## 2026-09-28 效能優化:「這個新形狀要不要扣掉前面某個已覆蓋的形狀」原本是每個新形狀都跟前面全部形狀一一比對
## (即使有 bounding box 提前排除,比對的「次數」本身還是形狀數量的平方成長,桌寵/光源/家具一多就跟著飆漲,
## 見備忘與 perf_probe 的量測)。改成用空間分格(uniform grid,格子邊長 CUTOUT_GRID_CELL)當廣域(broad-phase)
## 篩選:每個已覆蓋形狀依它的外框登記進涵蓋的格子,新形狀只需要跟「自己外框涵蓋的格子」裡登記過的形狀比對,
## 不用管畫面上其他離得很遠、外框不可能相交的形狀。只要格子邊長不小於典型形狀的外框,兩個真的相交的外框
## 一定會共用至少一個格子,結果跟原本逐一比對完全一樣,只是省下大部分「反正也不會相交」的比對。
func _collect_cutout_polygon() -> PackedVector2Array:
	var covered: Array[PackedVector2Array] = []
	var covered_bounds: Array[Rect2] = []
	var grid: Dictionary = {}   # Vector2i(格子座標) -> Array[int](covered 的索引)
	var loops: Array[PackedVector2Array] = []
	# 浮動視窗(管理視窗、編輯器…)蓋住的範圍先當成「已被佔走」:這個視窗的形狀就是桌寵與介面實際能畫、能點的範圍,
	# 所以桌寵、氣泡、行動區介面在浮動視窗底下的部分整個被裁掉(不論兩個視窗誰在上面),也不會擋住浮動視窗的滑鼠。
	var blocked := _occluder_polygons()
	for member in get_tree().get_nodes_in_group("Cutout"):
		if not member.has_method("get_cutout_polygons"):
			continue
		for polygon: PackedVector2Array in member.get_cutout_polygons():
			var pieces := clip_out(polygon, blocked)
			var polygon_bounds := _bounds_of(polygon)
			var seen: Dictionary = {}
			for cell: Vector2i in _grid_cells_for(polygon_bounds):
				for index: int in (grid.get(cell, []) as Array):
					if seen.has(index):
						continue
					seen[index] = true
					# 場上常有很多互不重疊的小形狀(桌寵、螢火蟲…),外框(bounding box)沒交集就一定不用扣,
					# 省下真正的多邊形布林運算(Geometry2D.clip_polygons 相對貴)。
					if not polygon_bounds.intersects(covered_bounds[index]):
						continue
					var next_pieces: Array[PackedVector2Array] = []
					for piece in pieces:
						next_pieces.append_array(Geometry2D.clip_polygons(piece, covered[index]))
					pieces = next_pieces
			loops.append_array(pieces)
			var new_index := covered.size()
			covered.append(polygon)
			covered_bounds.append(polygon_bounds)
			for cell: Vector2i in _grid_cells_for(polygon_bounds):
				if not grid.has(cell):
					grid[cell] = []
				(grid[cell] as Array).append(new_index)
	if loops.is_empty():
		# 空陣列在 Godot 代表「不限制、整個視窗都收滑鼠」,會把整個桌面擋住;
		# 沒有任何可點擊形狀時改給一個位於視窗外的極小三角形,等於整個視窗都穿透。
		return PackedVector2Array([Vector2(-3, -3), Vector2(-2, -3), Vector2(-3, -2)])
	var points := PackedVector2Array([Vector2.ZERO])
	for loop in loops:
		points.append_array(loop)
		points.append(loop[0])
		points.append(Vector2.ZERO)
	return points


## 從 polygon 裡扣掉 blocked 的每一塊,回傳剩下的碎片(可能是 0 塊、1 塊或更多;被完整包住時扣出來的洞也是一塊)。
static func clip_out(polygon: PackedVector2Array, blocked: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [polygon]
	for other in blocked:
		var other_bounds := _bounds_of(other)
		var kept: Array[PackedVector2Array] = []
		for piece in pieces:
			# 外框沒交集就一定扣不到這塊,原樣保留(見 _collect_cutout_polygon 同樣的做法與理由)。
			if not _bounds_of(piece).intersects(other_bounds):
				kept.append(piece)
			else:
				kept.append_array(Geometry2D.clip_polygons(piece, other))
		pieces = kept
	return pieces


## 這個外框橫跨哪些格子(見 CUTOUT_GRID_CELL);零面積外框回空陣列(不用登記進任何格子)。
static func _grid_cells_for(bounds: Rect2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if bounds.size == Vector2.ZERO:
		return cells
	var from := Vector2i((bounds.position / CUTOUT_GRID_CELL).floor())
	var to := Vector2i((bounds.end / CUTOUT_GRID_CELL).floor())
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			cells.append(Vector2i(x, y))
	return cells


## polygon 的外框(bounding box),給早退判斷用;空陣列回傳零面積矩形(不會跟任何東西「相交」)。
static func _bounds_of(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for i in range(1, polygon.size()):
		rect = rect.expand(polygon[i])
	return rect


func _on_node_added(node: Node) -> void:
	# 裝飾層(DecorOverlay)的視窗是全螢幕穿透的,不算「蓋在桌寵上面的視窗」,否則整個螢幕都被扣掉
	if node is Window and node != get_window() and not node.has_meta("click_through"):
		node.add_to_group("pet_occluders")


## 目前開著(顯示中)的子視窗(浮動視窗、確認視窗、選單…)範圍,換算成主視窗座標的矩形多邊形;含系統標題列與邊框。
func _occluder_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var origin := Vector2(get_window().position)
	for node in get_tree().get_nodes_in_group("pet_occluders"):
		var window := node as Window
		if window == null or not window.visible or window.mode == Window.MODE_MINIMIZED:
			continue
		var id := window.get_window_id()
		if id < 0:
			continue
		var top_left := Vector2(DisplayServer.window_get_position_with_decorations(id)) - origin
		var extent := Vector2(DisplayServer.window_get_size_with_decorations(id))
		if extent.x <= 0.0 or extent.y <= 0.0:
			continue
		result.append(PackedVector2Array([top_left, top_left + Vector2(extent.x, 0.0), top_left + extent, top_left + Vector2(0.0, extent.y)]))
	return result


func _configure_window() -> void:
	var window := get_window()
	# 強制釘回一般視窗模式(borderless + 手動覆蓋整個螢幕),絕不使用 Godot 的「全螢幕」或
	# 「獨佔全螢幕」視窗模式——獨佔全螢幕會整個繞過 DWM 桌面合成器,per-pixel 透明在該模式下
	# 架構上就不可能生效,所以每次啟動都強制歸零。
	window.mode = Window.MODE_WINDOWED
	window.borderless = true
	window.transparent = true
	window.always_on_top = true
	# 參考實作 movingwindow-interactable 額外用到的兩項設定(見檔頭 credit):
	# 視窗永不取得 OS 焦點、關閉 Windows 11 的自動圓角/陰影特效。
	window.unfocusable = true
	window.sharp_corners = true
	# 關閉內容縮放,讓 2D 座標與視窗像素 1:1。專案設定裡的基準視窗尺寸(Display > Window > Size)
	# 加上 canvas_items 拉伸模式,會讓畫面座標與實際螢幕像素差一個縮放比例(黃框只出現在左上角
	# 就是這個原因);穿透多邊形吃的是視窗像素座標,所以這裡在執行期強制關掉,
	# 不管使用者螢幕解析度多小、專案基準尺寸設多少,座標都一致。
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# 第一階段先覆蓋目前所在的單一螢幕;跨螢幕虛擬桌面涵蓋留待「多螢幕混合 DPI 縮放校正」
	# 驗證項目(主企劃書第九章第一階段第4點)處理,此處不預先假設涵蓋多顯示器。
	var screen_index := window.current_screen
	window.position = DisplayServer.screen_get_position(screen_index)
	window.size = DisplayServer.screen_get_size(screen_index)


func _on_action_area_right_click() -> void:
	_start_passthrough()


func _on_action_area_boundary_changed(local_rect: Rect2) -> void:
	if is_inside_tree() and _tray != null:
		_layout_bottom_pets()
	var window := get_window()
	_shell_state.set_action_area_rect(Rect2(Vector2(window.position) + local_rect.position, local_rect.size))


func _start_passthrough() -> void:
	if _shell_state.is_passthrough_frozen:
		return
	_shell_state.is_passthrough_frozen = true
	_shell_state.passthrough_started.emit()
	modulate.a = PASSTHROUGH_ALPHA
	await get_tree().create_timer(PASSTHROUGH_DURATION).timeout
	_end_passthrough()


func _end_passthrough() -> void:
	modulate.a = 1.0
	_shell_state.is_passthrough_frozen = false
	_shell_state.passthrough_ended.emit()
