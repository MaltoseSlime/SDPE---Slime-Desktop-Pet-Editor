class_name TutorialGuide
extends Node
## 新手教學(2026-10-14 使用者要求):第一次使用、或更新到這一版之後第一次啟動時,由 Mal 用對話氣泡一步一步帶著認識
## 這個程式;「全局設定 > 關於」最底下的「重看新手教學」可以再看一次。每一步都是兩個選項「下一步」「跳過教學」,
## 跳過時 Mal 會提醒去哪裡重看。講到哪個視窗就把那個視窗打開(並挪到 Mal 的另一側,免得蓋住氣泡),
## 講到懸浮球就讓懸浮球選單展開並框出那一項(HoverBall.tutorial_focus)。教學自己打開的視窗,換下一步時收掉
## (走視窗原本的關閉流程,有未儲存的變更照樣會問);使用者本來就開著的不動。
## 帶路的 Mal 一律是「系統用的 Mal」(使用者 2026-10-14 建議):不用角色庫或桌面上的 Mal——那隻可能已經被使用者改過
## (換了圖、性格、對話)或刪掉了。每次把程式內建的 Mal 素材複製到 user://tutorial_guide/ 叫一隻臨時的出來,用自己的
## 辨識代號、不讀寫任何設定與記憶、不進角色庫也不進開機名單,其他桌寵與積木都看不到它(Pet.system_guide);教學結束收回並連檔案一起清掉。
## 收回後桌面上沒有桌寵(第一次啟動時開機就先不放預設角色),由 DesktopShell 補放一隻正常的 Mal。
## 連內建素材都叫不出來時,改由場上任何一隻桌寵帶路;一隻桌寵都沒有就只能不教(不算看過,下次開機再試)。

signal finished(completed: bool)

## 教學內容的版本:跟記在設定檔裡的不一樣就會在開機時自動播一次。之後教學內容大改時才需要跟著改。
const VERSION := "0.2.0"
const SECTION := "tutorial"
const KEY := "seen_version"
## 開機後(語言選好之後)等這麼久才開始,讓桌寵先進場。
const START_DELAY := 3.0
const GUIDE_TAG := "tutorial_guide"
const GUIDE_DIR := "user://tutorial_guide/Mal"
## 氣泡等使用者回應的秒數:逾時、被拖曳/右鍵打斷都不算跳過,稍等一下同一步再問一次。
const PATIENCE := 600.0
const RETRY_DELAY := 1.0
const HOLD_SECONDS := 3600.0
const STEPS: Array[String] = ["intro", "area", "library", "personality", "make_prop", "drop_prop", "clear_props", "move_mode", "export", "blocks", "tray_menu", "colors", "done"]

var running := false
var _shell: Node
var _pet: Node
## 帶路的是系統用的 Mal(教學叫出來的):結束時收回。
var _summoned := false
## 系統用的 Mal 叫成功了:結束時連複製出來的檔案一起清掉。
var _temporary := false
var _opened: Array[Window] = []


## 開機時要不要自動播(這一版的教學還沒看過或跳過)。
static func needed() -> bool:
	var config := ConfigFile.new()
	config.load(AppSettings.SETTINGS_PATH)
	return str(config.get_value(SECTION, KEY, "")) != VERSION


static func mark_seen() -> void:
	var config := ConfigFile.new()
	config.load(AppSettings.SETTINGS_PATH)
	config.set_value(SECTION, KEY, VERSION)
	config.save(AppSettings.SETTINGS_PATH)


func run(shell: Node) -> void:
	if running:
		return
	running = true
	_shell = shell
	_pet = await _find_or_summon_guide()
	if _pet == null:
		running = false
		finished.emit(false)
		return
	var completed := true
	for step in STEPS:
		var choice := await _play_step(step)
		if choice != 0:
			completed = false
			break
	_close_opened()
	_set_focus("")
	mark_seen()
	if is_instance_valid(_pet):
		if not completed:
			GameChat.say(_pet, tr("好喔!之後想重看的話,到「全局設定」的「關於」頁,最下面有「重看新手教學」。"), 8.0, false, true)
		elif _summoned:
			GameChat.say(_pet, tr("那我先走囉,掰掰~"), 3.0, false, true)
		_pet.release_still()
		if _summoned:
			await get_tree().create_timer(8.5 if not completed else 3.5).timeout
			_dismiss_guide()
	running = false
	finished.emit(completed)


## 一步:準備畫面(開視窗/框懸浮球)、問使用者。回傳 0 = 繼續,1 = 跳過(桌寵不見了、沒有對話介面也算跳過)。
func _play_step(step: String) -> int:
	_prepare(step)
	var options: Array = [tr("下一步"), tr("跳過教學")]
	if step == "intro":
		options = [tr("好啊,開始吧"), tr("跳過教學")]
	elif step == "done":
		options = [tr("知道了")]
	while true:
		if not is_instance_valid(_pet) or not _pet.is_inside_tree():
			return 1
		var state := get_node("/root/DesktopShellState")
		if state.dialogue_line_requested.get_connections().is_empty():
			return 1
		_pet.hold_still_for(HOLD_SECONDS)
		var choice := await GameChat.ask(_pet, _text(step), options, PATIENCE)
		if choice >= 0:
			return choice
		await get_tree().create_timer(RETRY_DELAY).timeout
	return 1


func _text(step: String) -> String:
	match step:
		"intro":
			return tr("嗨,我是 Mal!要不要我花幾分鐘帶你認識這裡?每一步都可以按「跳過教學」直接結束。")
		"area":
			return tr("這個黃色框框是行動區,我們只會在框裡活動。拖曳黃框四邊的把手可以調整範圍;不想看到框的話,系統匣選單可以「隱藏行動區邊框」。")
		"library":
			return tr("這是「角色庫」,桌寵都住在這裡。按「＋ 新建角色…」就能用自己的圖做出新桌寵。現在不用急著做,知道在哪就好。")
		"personality":
			return tr("這是「桌寵管理」。上面先選要設定哪一隻,第一個「性格」頁籤可以幫它挑性格,說話的語氣和行為都會跟著變。")
		"make_prop":
			return tr("來做一顆球吧!在「交互物件管理」的「道具庫」,模板選「球」,按「＋ 從模板新增」,再把「落地後消失」改成 3 秒。家具則是在旁邊的「家具庫」做。")
		"drop_prop":
			return tr("角落那顆小圓鈕是懸浮球,「道具欄」已經幫你打開了。把剛剛的球從道具欄拖到桌面上放開,它落地 3 秒後就會消失。")
		"clear_props":
			return tr("東西丟太多的話,懸浮球選單裡的「清掃桌面道具」可以一次清乾淨。系統匣選單裡也有同一個指令。")
		"move_mode":
			return tr("在我身上按右鍵可以打開我的選單,裡面的「移動模式」能讓我在地面走、飛行、漂浮,或是固定不動。等一下可以試試看!")
		"export":
			return tr("想備份或分享設定,到「桌寵管理」的「記憶與檔案」頁籤:可以匯出設定、匯入或匯出積木檔,也能存記憶。要把整個角色打包成 .pet,在角色庫角色卡片的「⋯」選單裡。")
		"blocks":
			return tr("積木編輯器是網頁版的:在螢幕右下角系統匣裡的程式圖示上按右鍵,選「開啟網頁編輯工具」就能打開。做好的積木檔再匯入給桌寵。")
		"tray_menu":
			return tr("系統匣選單裡,每隻桌寵的名字底下還有一些別的地方沒有的指令,例如「強制休息」、調整圖層、導出 Schema,偶爾可以去翻翻看。")
		"colors":
			return tr("最後,「全局設定」的「外觀」頁籤可以換主面板的配色、字體和字級,挑一個喜歡的吧!")
		"done":
			return tr("教學到這裡結束!想重看的話,「全局設定」的「關於」頁最下面有「重看新手教學」。")
	return ""


## 每一步開始前:收掉上一步教學開的視窗、取消懸浮球的框,再照這一步需要的打開。
func _prepare(step: String) -> void:
	_close_opened()
	_set_focus("")
	match step:
		"library":
			_open("library")
		"personality":
			_open("manager", "性格")
		"make_prop":
			_open("objects", "props")
		"drop_prop":
			if _shell.hover_ball != null:
				_shell.hover_ball.set_inventory_open(true)
			_set_focus("inventory")
		"clear_props":
			_set_focus("clear_props")
		"export":
			_open("manager", "記憶與檔案")
		"colors":
			_open("settings", "外觀")


func _set_focus(item: String) -> void:
	if is_instance_valid(_shell) and _shell.hover_ball != null:
		_shell.hover_ball.tutorial_focus = item


## 打開(或叫到前景)視窗並切到指定頁籤。教學開的才記下來(換步時收掉),本來就開著的不收。
func _open(kind: String, tab := "") -> void:
	var before: Window = _window_of(kind)
	match kind:
		"library":
			_shell._open_library()
		"manager":
			_shell._open_manager()
		"objects":
			_shell._open_objects(tab)
		"settings":
			_shell._open_settings()
	var window: Window = _window_of(kind)
	if not is_instance_valid(window):
		return
	if not is_instance_valid(before):
		_opened.append(window)
	if kind != "objects" and tab != "":
		select_tab(window, tab)
	_move_aside.call_deferred(window)


func _window_of(kind: String) -> Window:
	var window: Variant = null
	match kind:
		"library":
			window = _shell._library_window
		"manager":
			window = _shell._manager_window
		"objects":
			window = _shell._objects_window
		"settings":
			window = _shell._settings_window
	return window if is_instance_valid(window) else null   # 關掉的視窗變數還留著已釋放的參考


## 切到視窗裡名字是 tab_name(原文)的頁籤。
static func select_tab(window: Node, tab_name: String) -> bool:
	for node: Node in window.find_children("*", "TabContainer", true, false):
		var tabs := node as TabContainer
		for i in tabs.get_tab_count():
			if str(tabs.get_tab_control(i).name) == tab_name:
				tabs.current_tab = i
				return true
	return false


## 浮動視窗會蓋掉後面的桌寵與氣泡(視窗範圍從主視窗的形狀扣掉),所以把視窗挪到 Mal 的另一側。
## 視窗自己會在開啟後的下一影格置中(FloatingWindow.place_on_screen),要等它排完再挪。
func _move_aside(window: Window) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(window) or not is_instance_valid(_pet) or DisplayServer.get_name() == "headless":
		return
	var main := _shell.get_window()
	var screen := DisplayServer.screen_get_usable_rect(main.current_screen)
	var pet_x := float(main.position.x) + (_pet as CanvasItem).get_global_transform_with_canvas().origin.x
	var x := screen.position.x + 16 if pet_x > screen.get_center().x else screen.end.x - window.size.x - 16
	window.position = Vector2i(clampi(x, screen.position.x, maxi(screen.end.x - window.size.x, screen.position.x)), window.position.y)


func _close_opened() -> void:
	for window in _opened:
		if is_instance_valid(window):
			if window.has_method("_request_close"):
				window._request_close()
			else:
				window.queue_free()
	_opened.clear()


# --- 帶路的桌寵 ---

func _find_or_summon_guide() -> Node:
	var pet := _summon_temporary()
	if pet != null:
		_summoned = true
		await get_tree().create_timer(1.5).timeout   # 等進場動畫
		if is_instance_valid(pet):
			return pet
	# 叫不出系統用的 Mal(內建素材不見了):改由場上任何一隻帶路
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if _usable(other):
			_summoned = false
			return other
	return null


func _usable(pet: Node) -> bool:
	return is_instance_valid(pet) and not pet.is_queued_for_deletion() and not bool(pet.get("ghost_edit"))


## 系統用的 Mal:把程式內建的 Mal 素材複製到 user://tutorial_guide/ 叫一隻出來(見 DesktopShell.spawn_system_guide)。
func _summon_temporary() -> Node:
	var target := ProjectSettings.globalize_path(GUIDE_DIR)
	SpriteLibrary._remove_folder(target)   # 上次沒清乾淨(例如教學途中關掉程式)
	if not SpriteLibrary.copy_default_source(str(SpriteLibrary.DEFAULT_CHARACTERS[0]["source"]), target):
		return null
	var result := SpritePackLoader.load_pack(target)
	if not bool(result["ok"]):
		SpriteLibrary._remove_folder(target)
		return null
	_temporary = true
	return _shell.spawn_system_guide(result)


func _dismiss_guide() -> void:
	if is_instance_valid(_pet):
		_pet.get_parent().remove_child(_pet)
		_pet.queue_free()
	if _temporary:
		cleanup_temporary_files()


## 系統用 Mal 留下的檔案(複製出來的素材)。
static func cleanup_temporary_files() -> void:
	SpriteLibrary._remove_folder(ProjectSettings.globalize_path(GUIDE_DIR))
