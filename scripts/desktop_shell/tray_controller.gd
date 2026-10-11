class_name TrayController
extends Node
## 系統匣圖示與右鍵選單(主企劃書第二章「系統匣常駐」):
## 利用 Godot 內建 StatusIndicator 節點,在 Windows 通知區域常駐顯示引擎圖示。
## 選單是二層結構:第一層是各隻桌寵的名字,第二層是該桌寵的模式切換(之後也放其他 Status 功能),
## 因為同時置入多隻桌寵時需要分辨在操作哪一隻。選單項目只發出訊號,實際行為由 DesktopShell 決定。

signal toggle_frame_requested
signal recall_requested
signal windows_reset_requested
signal quit_requested
## 對指定桌寵切換移動模式:0 地面、1 飛行、2 漂浮、3 固定、4 靜止(對應 Pet.MoveMode)。
signal move_mode_requested(pet: Node, mode: int)
## 對指定桌寵導出 Schema(給 HTML 積木編輯器)/匯入積木檔(HTML 編輯器導出的邏輯 JSON)。
signal export_schema_requested(pet: Node)
signal import_logic_requested(pet: Node)
signal say_something_requested(pet: Node)
## 右鍵選單「強制休息」:不管有沒有開疲勞機制都手動叫桌寵坐下(見 PetVitality.force_rest)。
signal force_rest_requested(pet: Node)
signal layer_tier_requested(pet: Node, tier: int)
signal open_manager_requested
signal auto_chat_toggled(enabled: bool)
signal add_pet_requested
signal add_still_requested(which: String)
signal relayout_stills_requested
signal add_buddy_requested
signal add_pack_requested
signal add_pack_path_requested(path: String)
signal edit_pack_requested
signal open_library_requested
signal open_props_requested
signal clear_props_requested
signal open_furniture_requested
signal open_error_log_requested
signal make_canonical_requested(pet: Node)
signal remove_pet_requested(pet: Node)
signal open_tester_requested
signal debug_polygon_toggled(enabled: bool)
signal open_settings_requested
## 「檢查更新…」(見 UpdateChecker):只有點了才會真的連線,不會自動背景檢查。
signal check_update_requested
signal hide_outside_furniture_toggled(enabled: bool)
signal do_not_disturb_toggled(enabled: bool)
signal relax_mode_toggled(enabled: bool)

const ID_TOGGLE_FRAME := 0
const ID_RECALL := 1
const ID_QUIT := 2
const ID_MANAGER := 3
const ID_AUTO_CHAT := 4
const ID_ADD_PET := 5
const ID_TESTER := 6
const ID_STILL_A := 8
const ID_STILL_B := 9
const ID_RELAYOUT_STILLS := 10
const ID_ADD_BUDDY := 11
const ID_ERROR_LOG := 12
const ID_ADD_PACK := 13
const ID_EDIT_PACK := 14
const ID_LIBRARY := 15
const ID_SETTINGS := 16
const ID_PROPS := 17
const ID_CLEAR_PROPS := 18
const ID_WINDOWS_RESET := 19
const ID_OPEN_WEB_EDITOR := 20
const ID_FURNITURE := 21
const ID_CHECK_UPDATE := 22
const ID_HIDE_OUTSIDE_FURNITURE := 23
const ID_DO_NOT_DISTURB := 24
const ID_RELAX_MODE := 25
## 最近用過的素材包資料夾,選單項目 id = ID_RECENT_PACK_BASE + 索引。
const ID_RECENT_PACK_BASE := 400
const MAX_SUMMON_LIBRARY := 16
const ID_DEBUG_POLYGON := 7
const ID_REMOVE_PET := 104
const ID_MAKE_CANONICAL := 105
const ID_EXPORT_SCHEMA := 101
const ID_IMPORT_LOGIC := 102
const ID_SAY_SOMETHING := 103
const ID_FORCE_REST := 106
## 桌寵選單「圖層」三個層級:id = ID_LAYER_BASE + 層級(-1 後面 / 0 中間 / 1 前面),見 PetLayering。
const ID_LAYER_BASE := 111
const MODE_NAMES: Array[String] = ["地面模式", "飛行模式", "漂浮模式", "固定模式", "靜止模式"]
const FIXED_MODE := 3
const ICON_NORMAL := preload("res://SDPE_icon.png")
## 右上角紅點版,提醒有「重要更新」(見 UpdateChecker.IMPORTANT_MARKER)。
const ICON_NOTIF := preload("res://SDPE_icon_notif.png")

## 選單勾選狀態(除錯用的穿透範圍線是否顯示;由 Shell 同步初值)。
var debug_polygon_visible := false
## 「隱藏行動區外的家具」的勾選狀態(DesktopShell 從 FurnitureManager 同步過來,這裡只負責畫勾)。
var hide_outside_furniture := false
## 最近用過的素材包資料夾(由 Shell 設定)。
var recent_packs: Array[String] = []
## 「召喚 / 測試用」選單目前列出的角色資料夾(選單項目的 id 對應這個陣列)。
var _summon_paths: Array[String] = []
var _indicator: StatusIndicator
## 開機背景檢查(見 UpdateChecker.auto_check_if_due())找到「重要更新」時變 true,系統匣圖示換成紅點版、
## 「檢查更新…」選單文字跟著換;由 DesktopShell 在開機時讀快取套用、之後收到 important_state_changed 訊號時更新。
var _important_update_available := false
var _menu: PopupMenu
var _submenus: Array[PopupMenu] = []
var _pets: Array[Node] = []


func _ready() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(_menu)
	_indicator = StatusIndicator.new()
	_indicator.icon = ICON_NOTIF if _important_update_available else ICON_NORMAL
	_indicator.tooltip = tr("史萊姆桌寵引擎")
	add_child(_indicator)
	refresh_pets()


## 系統匣圖示換成紅點版(有重要更新)或普通版,「檢查更新…」選單文字跟著換。DesktopShell 開機讀快取套用一次、
## 之後收到 UpdateChecker.important_state_changed 訊號時再呼叫更新。
func set_important_update(available: bool) -> void:
	_important_update_available = available
	if _indicator != null:
		_indicator.icon = ICON_NOTIF if available else ICON_NORMAL
	if _menu != null:
		var idx := _menu.get_item_index(ID_CHECK_UPDATE)
		if idx >= 0:
			_menu.set_item_text(idx, tr("檢查更新…(存在更新)") if available else tr("檢查更新…(需要連網)"))


## 場上的桌寵增減時呼叫,重建選單。
func refresh_pets() -> void:
	if _menu == null:
		return
	for pet in _pets:
		if is_instance_valid(pet) and pet.move_mode_changed.is_connected(_on_pet_mode_changed):
			pet.move_mode_changed.disconnect(_on_pet_mode_changed)
		if is_instance_valid(pet) and pet.label_changed.is_connected(_on_pet_label_changed):
			pet.label_changed.disconnect(_on_pet_label_changed)
	_pets.assign(get_tree().get_nodes_in_group("pets").filter(func(p: Node) -> bool: return not p.is_queued_for_deletion()))
	for pet in _pets:
		pet.move_mode_changed.connect(_on_pet_mode_changed)
		pet.label_changed.connect(_on_pet_label_changed)
	_rebuild_menu()


func _on_pet_label_changed() -> void:
	_rebuild_menu.call_deferred()


func _rebuild_menu() -> void:
	_menu.clear()
	for submenu in _submenus:
		submenu.queue_free()
	_submenus.clear()
	_add_debug_block()
	_menu.add_separator()
	for i in _pets.size():
		var pet := _pets[i]
		var submenu := PopupMenu.new()
		submenu.name = "PetMenu%d" % i
		for mode in MODE_NAMES.size():
			submenu.add_radio_check_item(tr(MODE_NAMES[mode]), mode)
			submenu.set_item_checked(mode, mode == pet.move_mode)
		submenu.add_separator()
		submenu.add_item(tr("強制休息(坐下,可能再躺下/睡著)"), ID_FORCE_REST)
		submenu.add_separator()
		# 圖層:跟別隻桌寵重疊時誰在前面(半身立繪有自己的圖層,不顯示這幾項)。
		if PetLayering.manages(pet):
			for tier: int in [PetLayering.Tier.FRONT, PetLayering.Tier.MIDDLE, PetLayering.Tier.BACK]:
				submenu.add_radio_check_item(tr("圖層:%s") % tr(PetLayering.TIER_LABELS[tier]), ID_LAYER_BASE + tier)
				submenu.set_item_checked(submenu.get_item_index(ID_LAYER_BASE + tier), pet.layer_tier == tier)
			submenu.set_item_tooltip(submenu.get_item_index(ID_LAYER_BASE + PetLayering.Tier.MIDDLE), tr("跟別隻桌寵重疊時的前後順序。同一個層級裡,站得比較高的自動排在後面。"))
			submenu.add_separator()
		submenu.add_item(tr("說點什麼"), ID_SAY_SOMETHING)
		submenu.set_item_disabled(submenu.get_item_index(ID_SAY_SOMETHING), not pet.logic.has_chat_lines())
		submenu.add_item(tr("導出 Schema…"), ID_EXPORT_SCHEMA)
		submenu.add_item(tr("導入積木檔…"), ID_IMPORT_LOGIC)
		submenu.add_separator()
		submenu.add_item(tr("以這隻為本體(同步給同角色所有複製品)"), ID_MAKE_CANONICAL)
		submenu.add_item(tr("移除這隻桌寵"), ID_REMOVE_PET)
		submenu.id_pressed.connect(_on_pet_menu_pressed.bind(pet))
		_menu.add_child(submenu)
		_submenus.append(submenu)
		_menu.add_submenu_node_item(pet.get_label(), submenu)
	if not _pets.is_empty():
		_menu.add_separator()
	# 會開出獨立視窗的功能放在同一區。
	_menu.add_item(tr("角色庫…"), ID_LIBRARY)
	_menu.add_item(tr("桌寵管理…"), ID_MANAGER)
	_menu.add_item(tr("道具管理…"), ID_PROPS)
	_menu.add_item(tr("清掃桌面道具"), ID_CLEAR_PROPS)
	_menu.add_item(tr("家具庫…"), ID_FURNITURE)
	_menu.add_item(tr("精靈圖編輯器…"), ID_EDIT_PACK)
	_menu.add_item(tr("全局設定…"), ID_SETTINGS)
	_menu.add_item(tr("測試者面板…"), ID_TESTER)
	_menu.add_item(tr("開啟網頁編輯工具(需要連網)"), ID_OPEN_WEB_EDITOR)
	_menu.add_item(tr("檢查更新…(存在更新)") if _important_update_available else tr("檢查更新…(需要連網)"), ID_CHECK_UPDATE)
	_menu.add_separator()
	_add_summon_submenu()
	_menu.add_separator()
	_menu.add_item(tr("完全退出"), ID_QUIT)
	if _indicator != null:
		_indicator.menu = _indicator.get_path_to(_menu)


## 最上面的除錯區:行動區重設、浮動視窗重設、行動區邊框、重排立繪、穿透範圍線、錯誤紀錄資料夾。
func _add_debug_block() -> void:
	_add_behavior_submenu()
	_menu.add_item(tr("行動區重設"), ID_RECALL)
	_menu.add_item(tr("浮動視窗重設"), ID_WINDOWS_RESET)
	_menu.add_item(tr("顯示/隱藏行動區邊框"), ID_TOGGLE_FRAME)
	_menu.add_check_item(tr("隱藏行動區外的家具"), ID_HIDE_OUTSIDE_FURNITURE)
	_menu.set_item_checked(_menu.get_item_index(ID_HIDE_OUTSIDE_FURNITURE), hide_outside_furniture)
	_menu.add_item(tr("重新排開半身立繪"), ID_RELAYOUT_STILLS)
	_menu.add_check_item(tr("顯示穿透範圍(除錯)"), ID_DEBUG_POLYGON)
	_menu.set_item_checked(_menu.get_item_index(ID_DEBUG_POLYGON), debug_polygon_visible)
	_menu.add_item(tr("開啟除錯資料夾(錯誤紀錄)"), ID_ERROR_LOG)


## 召喚選單列出的角色:角色庫裡的全部角色(最多 MAX_SUMMON_LIBRARY 個),再加最近用過、不在角色庫裡而且資料夾還在的。
func summon_candidates() -> Array[String]:
	var result: Array[String] = []
	for path: String in SpriteLibrary.list_packs():
		if result.size() >= MAX_SUMMON_LIBRARY:
			break
		result.append(path)
	for path: String in recent_packs:
		if not result.has(path) and DirAccess.dir_exists_absolute(path) and result.size() < MAX_SUMMON_LIBRARY + 6:
			result.append(path)
	return result


## 二階選單「全體行為」(2026-10-11,排在最上面):對全部桌寵生效的行為開關——自動閒聊總開關(原本在「召喚 / 測試用」)、勿擾模式。
func _add_behavior_submenu() -> void:
	var state := get_node("/root/DesktopShellState")
	var submenu := PopupMenu.new()
	submenu.name = "BehaviorMenu"
	submenu.add_check_item(tr("自動閒聊(全部桌寵)"), ID_AUTO_CHAT)
	submenu.set_item_checked(submenu.get_item_index(ID_AUTO_CHAT), state.auto_chat_enabled)
	submenu.add_check_item(tr("勿擾模式"), ID_DO_NOT_DISTURB)
	submenu.set_item_checked(submenu.get_item_index(ID_DO_NOT_DISTURB), state.do_not_disturb)
	submenu.set_item_tooltip(submenu.get_item_index(ID_DO_NOT_DISTURB), tr("桌寵照常閒聊,但不會主動問你問題:帶選項的事件、問稱呼、問關鍵詞、問要不要一起玩。"))
	submenu.add_check_item(tr("放鬆模式"), ID_RELAX_MODE)
	submenu.set_item_checked(submenu.get_item_index(ID_RELAX_MODE), state.relax_mode)
	submenu.set_item_tooltip(submenu.get_item_index(ID_RELAX_MODE), tr("桌寵大多坐著休息、偶爾換個位置坐到別的桌寵旁邊;少閒聊、少玩遊戲、不追球與道具、不互相跟隨、不問你問題,也比較省效能。仍然可以餵食、叫牠跟著滑鼠。"))
	submenu.id_pressed.connect(_on_menu_id_pressed)
	_menu.add_child(submenu)
	_submenus.append(submenu)
	_menu.add_submenu_node_item(tr("全體行為"), submenu)


## 二階選單「召喚 / 測試用」:從素材包召喚、開發時測試多角色用的桌寵(角色庫上線後這些會慢慢退役)。
func _add_summon_submenu() -> void:
	var submenu := PopupMenu.new()
	submenu.name = "SummonMenu"
	submenu.add_item(tr("從素材包資料夾放一隻桌寵…"), ID_ADD_PACK)
	_summon_paths = summon_candidates()
	for i in _summon_paths.size():
		submenu.add_item(tr("再放一隻:%s") % _summon_paths[i].get_file(), ID_RECENT_PACK_BASE + i)
	# 測試用素材只在開發專案裡有(發行版沒有,見 BuildProfile);發行版只從角色庫放角色。
	if BuildProfile.has_sample_pets() or BuildProfile.has_stills():
		submenu.add_separator()
	if BuildProfile.has_sample_pets():
		submenu.add_item(tr("再放一隻範例桌寵"), ID_ADD_PET)
		submenu.add_item(tr("放一隻 Buddy(測試多角色積木用,辨識代號 buddy)"), ID_ADD_BUDDY)
	if BuildProfile.has_stills():
		submenu.add_item(tr("放一隻半身立繪 A(固定在底部)"), ID_STILL_A)
		submenu.add_item(tr("放一隻半身立繪 B(固定在底部)"), ID_STILL_B)
	submenu.id_pressed.connect(_on_menu_id_pressed)
	_menu.add_child(submenu)
	_submenus.append(submenu)
	_menu.add_submenu_node_item(tr("召喚 / 測試用"), submenu)


func _on_pet_mode_changed(_mode: int) -> void:
	_rebuild_menu.call_deferred()


func _on_pet_menu_pressed(id: int, pet: Node) -> void:
	if id == ID_EXPORT_SCHEMA:
		export_schema_requested.emit(pet)
	elif id == ID_IMPORT_LOGIC:
		import_logic_requested.emit(pet)
	elif id == ID_SAY_SOMETHING:
		say_something_requested.emit(pet)
	elif id == ID_FORCE_REST:
		force_rest_requested.emit(pet)
	elif id >= ID_LAYER_BASE + PetLayering.Tier.BACK and id <= ID_LAYER_BASE + PetLayering.Tier.FRONT:
		layer_tier_requested.emit(pet, id - ID_LAYER_BASE)
	elif id == ID_MAKE_CANONICAL:
		make_canonical_requested.emit(pet)
	elif id == ID_REMOVE_PET:
		remove_pet_requested.emit(pet)
	else:
		move_mode_requested.emit(pet, id)


func _on_menu_id_pressed(id: int) -> void:
	if id >= ID_RECENT_PACK_BASE and id < ID_RECENT_PACK_BASE + _summon_paths.size():
		add_pack_path_requested.emit(_summon_paths[id - ID_RECENT_PACK_BASE])
		return
	match id:
		ID_TOGGLE_FRAME:
			toggle_frame_requested.emit()
		ID_ADD_PET:
			add_pet_requested.emit()
		ID_STILL_A:
			add_still_requested.emit("A")
		ID_STILL_B:
			add_still_requested.emit("B")
		ID_RELAYOUT_STILLS:
			relayout_stills_requested.emit()
		ID_ADD_BUDDY:
			add_buddy_requested.emit()
		ID_ADD_PACK:
			add_pack_requested.emit()
		ID_LIBRARY:
			open_library_requested.emit()
		ID_PROPS:
			open_props_requested.emit()
		ID_CLEAR_PROPS:
			clear_props_requested.emit()
		ID_FURNITURE:
			open_furniture_requested.emit()
		ID_EDIT_PACK:
			edit_pack_requested.emit()
		ID_SETTINGS:
			open_settings_requested.emit()
		ID_ERROR_LOG:
			open_error_log_requested.emit()
		ID_OPEN_WEB_EDITOR:
			OS.shell_open(CreditsData.WEB_EDITOR_URL)
		ID_CHECK_UPDATE:
			check_update_requested.emit()
		ID_TESTER:
			open_tester_requested.emit()
		ID_DEBUG_POLYGON:
			debug_polygon_visible = not debug_polygon_visible
			debug_polygon_toggled.emit(debug_polygon_visible)
			_rebuild_menu.call_deferred()
		ID_HIDE_OUTSIDE_FURNITURE:
			hide_outside_furniture_toggled.emit(not hide_outside_furniture)
		ID_MANAGER:
			open_manager_requested.emit()
		ID_AUTO_CHAT:
			auto_chat_toggled.emit(not get_node("/root/DesktopShellState").auto_chat_enabled)
		ID_DO_NOT_DISTURB:
			do_not_disturb_toggled.emit(not get_node("/root/DesktopShellState").do_not_disturb)
		ID_RELAX_MODE:
			relax_mode_toggled.emit(not get_node("/root/DesktopShellState").relax_mode)
		ID_RECALL:
			recall_requested.emit()
		ID_WINDOWS_RESET:
			windows_reset_requested.emit()
		ID_QUIT:
			quit_requested.emit()
