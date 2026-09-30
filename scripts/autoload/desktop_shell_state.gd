extends Node
## 桌面行動容器的全域訊號匯流排與共享狀態。
## 未來的桌寵、平臺等系統只需訂閱這裡的訊號即可得知穿透凍結狀態與行動區邊界,
## 不需要直接耦合到 DesktopShell 場景節點本身(對應主企劃書第九章「訊號驅動的非同步解耦」原則)。

signal passthrough_started
signal passthrough_ended
signal action_area_rect_changed(global_rect: Rect2)

## 系統匣「緊急召回」被按下:場上所有桌寵應把自己的座標重設到行動區中央。
signal emergency_recall_requested

## 程式即將退出:場上桌寵應播放各自的 leave 退場動作。播放期間請先呼叫 hold_shutdown(),
## 播完再呼叫 release_shutdown();全部放行或逾時(見 DesktopShell)後才會真正關閉程式。
signal shutdown_requested

## 是否處於右鍵暫時穿透期間;為 true 時,場上桌寵應暫停即時點擊與拖曳判斷(穿透凍結)。
var is_passthrough_frozen: bool = false

## 行動區目前的邊界,採虛擬桌面座標(全域螢幕座標),而非視窗本地座標。
var action_area_rect: Rect2 = Rect2()

## 邏輯直譯器(積木執行)對外的訊號:對話氣泡、特效、音效系統完成後各自訂閱,
## 直譯器本身不直接呼叫這些系統(訊號驅動解耦)。
## line 內容:text(已插值的文字)、font(字型名稱,空字串=桌寵預設)、typewriter(bool)、
## auto_seconds(打完後靜置幾秒自動跳下一句,0=依字數自動收起)、wait_click(bool,true=改成等使用者點擊,留給桌寵向使用者發起的重要對話)、
## bind_action、options(選項文字陣列;有選項一律等使用者選)。
## ticket 是 DialogueTicket:對話介面關閉這一句時呼叫 ticket.finish(選項索引,沒有選擇為 -1),
## 直譯器等它;沒有任何對話介面訂閱時,直譯器改用計時器,不會卡住。
signal dialogue_line_requested(pet: Node, line: Dictionary, ticket: RefCounted)
## 對話介面自己發:某隻桌寵的氣泡出現/消失,給全域 UI 避讓管理與其他系統訂閱(企劃書第四章訊號清單)。
signal dialogue_started(pet: Node)
signal dialogue_finished(pet: Node)
signal effect_requested(pet: Node, effect_name: String)
## 某隻桌寵的 PetEffects 開始播放一個特效(key = 內部代號,如 hearts、vein);積木「當(角色)播放(特效)」事件訂閱它。
signal effect_played(pet: Node, key: String)
signal sound_requested(pet: Node, sound_name: String)
signal value_updated(pet: Node, scope: String, key: String, new_value: float, old_value: float)

## 桌寵加入場景時由 Pet 發出,讓 UI 管理器等系統不必自己輪詢場上有哪些桌寵。
signal pet_registered(pet: Node)
## 桌寵想問使用者一段文字(稱呼、抽籤選項…):request = {prompt(純文字問句), bubble_text(氣泡版 BBCode), default, max_length, direct};
## direct = true(使用者自己從選單叫出來的)才直接開輸入視窗;桌寵/積木發起的(direct = false)一律先用氣泡問、使用者按「回答」才開視窗,絕不主動跳出視窗搶焦點。
## 輸入介面用 ticket(InputTicket)回報結果。
signal text_input_requested(pet: Node, request: Dictionary, ticket: RefCounted)
## 積木失控被看門狗處理到「強制退場」的地步(見 LogicInterpreter._runaway):DesktopShell 據此把這隻桌寵移除。
signal pet_ejected(pet: Node, reason: String)
## 要求對話介面把這隻桌寵的氣泡收起來(例如問完話、抽完籤之後)。
signal dialogue_close_requested(pet: Node)
## 某隻桌寵開始跳舞:場內別的桌寵據此考慮跟著跳(見 Pet._on_dance_cue)。
signal pet_dance_started(pet: Node)

## 某隻桌寵開始/結束使用家具(走到錨點坐下/躺下,或放開):using = true 是開始。積木「當(角色)加入/結束使用家具時」訂閱它,
## 見 Pet.use_furniture()/stop_using_furniture()。item 是 FurnitureItem,anchor_type 是 "sit"/"lay"。
signal furniture_use_changed(pet: Node, item: Node, anchor_type: String, using: bool)

## 說話打字機每顯示一個字發一次(音效管理器負責節流);對話介面不直接碰音效系統。
signal speech_tick_requested(pet: Node)

## 某隻桌寵拾取/吃掉了一個道具(PropReaction.collect(),不含被摩擦);積木「當(角色)使用了(道具)時」
## 訂閱它,見 LogicInterpreter._on_prop_used。跟 effect_played/furniture_use_changed 同一套廣播設計
## (場上所有桌寵都收得到,各自依 TAGS/INCLUDE_SELF 篩要不要理),讓其他桌寵也能反應「指定角色用了某物品」,
## 不是只有使用者自己(2026-09-30 使用者要求:條件光源錨點要能綁到「指定對象使用了指定物品」)。
signal prop_used(pet: Node, prop_name: String)

## 音效設定(使用者可調,SoundManager 負責存檔與套用):音量 0.0–1.0、靜音、說話音效開關。
signal audio_settings_changed
## 關鍵事件要求即時存檔(見 SaveScheduler.request):拿到道具、對話選項改了數值等。
signal save_requested(reason: String)
var audio_volume := 1.0
var audio_muted := false
var speak_sound_enabled := true

## 自動閒聊的全域總開關(系統匣可切,Shell 負責存讀 user://settings.cfg);個別桌寵還有自己的開關與間隔。
var auto_chat_enabled := true

## 全域數值的定義(PetValueDef 陣列):預設值、上下限、Status 白名單等;全域數值沒有宣告時仍可使用,只是不夾限也不顯示。
var global_value_defs: Array = []

## 全域數值池(所有桌寵共享);局部數值與 Flag 存在各桌寵自己身上。存檔系統完成前不持久化。
var global_values: Dictionary = {}

var _shutdown_holds := 0

## 自動閒聊的錯開(多隻桌寵同時在場時):兩次自動閒聊之間至少要隔這麼久,而且任何一隻正在說話時別的桌寵不會自動開口。
## 手動「說點什麼」與積木觸發的對話不受這個限制。
const AUTO_CHAT_MIN_GAP_SECONDS := 15.0
## 同角色多個複製品狀態不同時,預設讓「最早」或「最晚」生成的那隻當本體("earliest" / "latest",Shell 存讀 settings.cfg)。
var canonical_policy := "earliest"
var _pet_serial := 0
var _dialogues_open := 0


func next_pet_serial() -> int:
	_pet_serial += 1
	return _pet_serial
var _last_auto_chat_msec := -1000000
## 最近一個對話氣泡收掉的時間。自動閒聊的間隔從「對話結束」起算,不從「開口」起算:
## 一場雙人交談要講很久,若從開口算,交談本身就把冷卻吃光了,一結束就能馬上又開下一場。
var _last_dialogue_end_msec := -1000000


func _ready() -> void:
	# 用計數而不是布林:多隻桌寵各有一個氣泡,要全部收起才算「沒有人在說話」。
	dialogue_started.connect(func(_pet: Node) -> void: _dialogues_open += 1)
	dialogue_finished.connect(func(_pet: Node) -> void:
		_dialogues_open = maxi(_dialogues_open - 1, 0)
		_last_dialogue_end_msec = Time.get_ticks_msec())


## 現在輪到桌寵自動開口嗎?(沒人正在說話,且距離上一次自動閒聊「開口」與上一個對話「結束」都已經夠久)
func can_auto_chat() -> bool:
	var now := Time.get_ticks_msec()
	var gap := int(AUTO_CHAT_MIN_GAP_SECONDS * 1000.0)
	return _dialogues_open == 0 and now - _last_auto_chat_msec >= gap and now - _last_dialogue_end_msec >= gap


func note_auto_chat_started() -> void:
	_last_auto_chat_msec = Time.get_ticks_msec()


func set_action_area_rect(global_rect: Rect2) -> void:
	if action_area_rect == global_rect:
		return
	action_area_rect = global_rect
	action_area_rect_changed.emit(global_rect)


func hold_shutdown() -> void:
	_shutdown_holds += 1


func release_shutdown() -> void:
	_shutdown_holds = maxi(_shutdown_holds - 1, 0)


func has_shutdown_holds() -> bool:
	return _shutdown_holds > 0
