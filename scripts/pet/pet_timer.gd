class_name PetTimer
extends Node
## 桌寵幫你計時(掛在 Pet 底下,右鍵選單「幫我設定計時器…」「幫我計時…」)。同一隻桌寵同一時間只有一個。
## 兩種:
##  - 計時器(COUNTDOWN):倒數 total 秒,時間到了發出提醒(音效 + 對話 + 連續小跳)。
##  - 計時(STOPWATCH):從現在開始記錄;total > 0 = 記到這麼久就提醒(同上),total = 0 = 一直記到你喊停,喊停時桌寵報出經過的時間。
## 中途遊戲被關掉、或這隻桌寵被收起來,都會暫停計時並把已經記到的時間存起來(user://timers/<辨識代號>.json);下次這隻桌寵出現時,桌寵會說出最後記到的時間並問要不要繼續。
## 執行中每 SAVE_INTERVAL 秒存一次「執行中」的紀錄:下次啟動時如果還是「執行中」(代表上次不是正常結束,例如當機、被強制關閉),
## 或紀錄壞掉讀不出來,桌寵會說「計時失敗」並告知最後記到的時間(如果有)。

enum Kind { NONE, COUNTDOWN, STOPWATCH }

const DIR := "user://timers/"
const SAVE_INTERVAL := 2.0
## 進場後等幾秒才檢查有沒有上次留下的計時(讓入場動畫先播完、辨識代號設定好)。
const RESTORE_DELAY := 3.5
const MAX_SECONDS := 99.0 * 3600.0
const ALERT_SOUND_DEFAULT := "ring1"
const ALERT_HOPS := 4
## 「按一下碼表」最多記幾次;按超過上限時丟掉最舊的一次(留最近的 MAX_LAPS 次)。
const MAX_LAPS := 50

var kind: Kind = Kind.NONE
var total := 0.0
var elapsed := 0.0
var sound := ALERT_SOUND_DEFAULT
var running := false
## 中途提醒(不會結束計時,只響一聲,見 _ping):每隔這麼多秒響一次(0 = 沒設)。
var reminder_interval := 0.0
## 中途提醒:到了這些時間點各響一次(完整清單,restart 用來重置;實際還沒觸發的在 _pending_waypoints)。
var reminder_waypoints: Array[float] = []
var _pending_waypoints: Array[float] = []
var _next_interval_at := 0.0
## 「按一下碼表」按下當時記到的時間(秒),依按下順序;見 MENU_LAP。開始新計時、重新計時、結束都會清空。
var laps: Array[float] = []

var _pet: Node
var _save_left := SAVE_INTERVAL
var _restore_left := RESTORE_DELAY
var _restore_done := false
## 為了測試:覆蓋存檔資料夾。
static var dir_override := ""


func setup(pet: Node) -> void:
	_pet = pet


func active() -> bool:
	return kind != Kind.NONE and running


## 開始計時。回傳 false = 已經有一個在跑或參數不合理。seconds:計時器必須 > 0;計時可以 0(= 一直記到喊停)。
## interval_seconds/waypoint_seconds:中途提醒(見 reminder_interval/reminder_waypoints),0/空 = 不設。
func start(new_kind: Kind, seconds: float, alert_sound := "", interval_seconds := 0.0, waypoint_seconds: Array[float] = []) -> bool:
	if active() or new_kind == Kind.NONE or (new_kind == Kind.COUNTDOWN and seconds <= 0.0):
		return false
	kind = new_kind
	total = clampf(seconds, 0.0, MAX_SECONDS)
	elapsed = 0.0
	laps = []
	reminder_interval = clampf(interval_seconds, 0.0, MAX_SECONDS)
	# 到終點以後才響的提醒沒意義(一直記到喊停的計時,total=0,不設上限);去重、排序。
	reminder_waypoints = []
	for w in waypoint_seconds:
		if w > 0.0 and (total <= 0.0 or w < total) and not reminder_waypoints.has(w):
			reminder_waypoints.append(w)
	reminder_waypoints.sort()
	_reset_reminder_progress()
	var wanted_sound: String = alert_sound if alert_sound != "" else str(_pet.timer_sound)
	sound = wanted_sound if SoundManager.has_sound(wanted_sound) else ALERT_SOUND_DEFAULT
	running = true
	if _pet.vitality != null and _pet.vitality.mode == PetVitality.Mode.SLEEPING:
		_pet.vitality.wake_quietly()   # 計時中的桌寵不睡覺:睡著的先叫醒
	_restore_done = true   # 使用者已經設了新的計時,不用再檢查上次留下的
	_save_left = SAVE_INTERVAL
	_write("running")
	if kind == Kind.COUNTDOWN:
		_say(_pet.speak_tr("好,幫你計時 %s。") % format_duration(total), 3.0)
	elif total > 0.0:
		_say(_pet.speak_tr("好,開始計時,記到 %s 我會提醒你。") % format_duration(total), 3.0)
	else:
		_say(_pet.speak_tr("好,開始計時!要停的時候再叫我。"), 3.0)
	return true


## 使用者叫停:計時器 = 取消;計時 = 報出經過的時間。
func stop() -> void:
	if not has_timing():
		return
	running = true   # 暫停中結束也照常報時間
	var spent := elapsed
	var was := kind
	var recorded := laps.duplicate()
	_clear()
	if was == Kind.STOPWATCH:
		_say(_pet.speak_tr("計時結束,一共 %s。%s") % [format_duration(spent), _laps_text(_pet, recorded)], 6.0)
	else:
		_say(_pet.speak_tr("計時器取消了(原本剩 %s)。%s") % [format_duration(maxf(total - spent, 0.0)), _laps_text(_pet, recorded)], 4.0)


## 取消計時(不報時間、清掉存檔);收起桌寵時使用者選「取消計時」用。
func cancel() -> void:
	if kind != Kind.NONE:
		_clear()


## 有計時在身上(跑著或暫停著都算)。
func has_timing() -> bool:
	return kind != Kind.NONE


func is_paused() -> bool:
	return kind != Kind.NONE and not running


## 暫停計時(這次遊戲期間;已經記到的時間留著,可以繼續)。回傳是不是真的暫停了。
func pause() -> bool:
	if not active():
		return false
	running = false
	_write("paused")
	return true


## 繼續暫停中的計時。
func resume() -> bool:
	if not is_paused():
		return false
	running = true
	_save_left = SAVE_INTERVAL
	_write("running")
	return true


## 重新計時:同樣的種類與時間,從頭開始(暫停中也會開始跑);中途提醒也重置成完整清單重新倒數。
func restart() -> bool:
	if kind == Kind.NONE:
		return false
	elapsed = 0.0
	laps = []
	running = true
	_reset_reminder_progress()
	_save_left = SAVE_INTERVAL
	_write("running")
	return true


func _reset_reminder_progress() -> void:
	_next_interval_at = reminder_interval
	_pending_waypoints = reminder_waypoints.duplicate()


## 完整的計時內容,給對話用:「計時器,剩 8:12(共 10 分)」「計時,已 5:03」,後面接已經按過幾次碼表(見 _laps_text)。
func describe() -> String:
	var paused_text: String = _pet.speak_tr("(暫停中)") if is_paused() and is_instance_valid(_pet) else ""
	match kind:
		Kind.COUNTDOWN:
			return _pet.speak_tr("計時器,剩 %s(共 %s)%s%s") % [clock_text(maxf(total - elapsed, 0.0)), format_duration(total), paused_text, _laps_text(_pet, laps)]
		Kind.STOPWATCH:
			if total > 0.0:
				return _pet.speak_tr("計時,已 %s(記到 %s 提醒)%s%s") % [clock_text(elapsed), format_duration(total), paused_text, _laps_text(_pet, laps)]
			return _pet.speak_tr("計時,已 %s%s%s") % [clock_text(elapsed), paused_text, _laps_text(_pet, laps)]
	return ""


## 「按一下碼表」記錄下來的清單給對話用,沒有紀錄回空字串(前面帶空白,直接接在別的句子後面)。
static func _laps_text(pet: Node, values: Array) -> String:
	if values.is_empty():
		return ""
	var times: Array[String] = []
	for value: float in values:
		times.append(clock_text(value))
	var template: String = pet.speak_tr(" 碼表記了 %d 次:%s。") if is_instance_valid(pet) else TranslationServer.translate(" 碼表記了 %d 次:%s。")
	return template % [values.size(), "、".join(times)]


## 使用者叫了一下正在計時的桌寵(雙擊):停下來、報出目前計時狀況並問要做什麼(按一下碼表 / 重新計時 / 暫停或繼續 / 結束 / 沒什麼事)。
## 問答期間桌寵原地不動。回傳選的項目編號(見 MENU_*),沒有計時或沒有介面回 -1。
const MENU_LAP := 0
const MENU_RESTART := 1
const MENU_TOGGLE := 2   # 跑著 = 暫停計時、暫停中 = 繼續計時
const MENU_STOP := 3
const MENU_NOTHING := 4


func open_menu() -> int:
	if _pet == null or not is_instance_valid(_pet) or not has_timing():
		return -1
	var call_name: String = _pet.pick_user_nickname() + _pet.speak_tr(",")
	var opening: String = _pet.speak_tr("%s怎麼了?我還在幫你計時喔!(%s)") % [call_name, describe()] if running else _pet.speak_tr("%s怎麼了?計時先幫你停下囉!(%s)") % [call_name, describe()]
	var labels: Array = [_pet.speak_tr("按一下碼表"), _pet.speak_tr("重新計時"), _pet.speak_tr("暫停計時") if running else _pet.speak_tr("繼續計時"), _pet.speak_tr("結束計時"), _pet.speak_tr("沒什麼事")]
	_pet.hold_still_for(60.0)
	var choice: int = await GameChat.ask(_pet, opening, labels, 40.0)
	if is_instance_valid(_pet):
		_pet.release_still()
	if not is_instance_valid(_pet) or not has_timing():
		return choice
	match choice:
		MENU_LAP:
			laps.append(elapsed)
			if laps.size() > MAX_LAPS:
				laps.pop_front()
			_write("running" if running else "paused")
			_say(_pet.speak_tr("記下來了,第 %d 次:%s。") % [laps.size(), clock_text(elapsed)], 5.0)
		MENU_RESTART:
			restart()
			_say(_pet.speak_tr("好,重新計時!"), 3.0)
		MENU_TOGGLE:
			if running:
				pause()
				_say(_pet.speak_tr("好,先暫停(%s)。要繼續再叫我。") % describe(), 4.0)
			else:
				resume()
				_say(_pet.speak_tr("好,繼續計時!"), 3.0)
		MENU_STOP:
			running = true
			stop()
	return choice


## 選單顯示用:「剩 8:12」或「已 5:03」。
func status_text() -> String:
	if kind == Kind.COUNTDOWN or (kind == Kind.STOPWATCH and total > 0.0):
		return tr("剩 %s") % clock_text(maxf(total - elapsed, 0.0))
	return tr("已 %s") % clock_text(elapsed)


func _process(delta: float) -> void:
	if _pet == null:
		return
	if not _restore_done:
		_restore_left -= delta
		if _restore_left <= 0.0 and not _pet.entering:
			_restore_done = true
			_restore()
	if not running:
		return
	elapsed += delta
	_check_reminders()
	if total > 0.0 and elapsed >= total:
		_finish()
		return
	_save_left -= delta
	if _save_left <= 0.0:
		_save_left = SAVE_INTERVAL
		_write("running")


func _exit_tree() -> void:
	pause_and_save()


## 桌寵被收起來或遊戲正常關閉:暫停並把已經記到的時間存起來(下次再出現時桌寵會說出來)。
func pause_and_save() -> void:
	if not running:
		return
	running = false
	_write("paused")


## 中途提醒到了沒:每隔 reminder_interval 秒響一次(用 while 而不是 if,避免 delta 太大一次跳過好幾個間隔沒響到);
## reminder_waypoints 裡到的時間點各響一次、響過就從待觸發清單拿掉(不會重複響)。都不影響計時本身,只是響一聲。
func _check_reminders() -> void:
	if reminder_interval > 0.0:
		while elapsed >= _next_interval_at:
			_next_interval_at += reminder_interval
			_ping()
	while not _pending_waypoints.is_empty() and elapsed >= _pending_waypoints[0]:
		_pending_waypoints.pop_front()
		_ping()


## 中途提醒:只響一聲音效,不像 _finish()/_alert() 那樣結束計時、連跳、說話。
func _ping() -> void:
	if not is_instance_valid(_pet):
		return
	_pet.get_node("/root/DesktopShellState").sound_requested.emit(_pet, sound)


func _finish() -> void:
	var finished_kind := kind
	var spent := total
	_clear()
	_alert(finished_kind, spent)


## 時間到:連響音效、說話、連續小跳。
func _alert(finished_kind: Kind, seconds: float) -> void:
	if not is_instance_valid(_pet):
		return
	if _pet.vitality != null:
		_pet.vitality.wake_quietly()   # 睡著的桌寵也要叫醒你
	# 有寫「當角色正在 timer_done 時」的事件積木就交給積木說話,沒有才用內建台詞。
	if _pet.logic != null and _pet.logic.has_action_hat(&"timer_done"):
		_pet.logic.fire_event(&"timer_done")
	else:
		_say(_pet.speak_tr("時間到囉!(%s)") % format_duration(seconds) if finished_kind == Kind.COUNTDOWN else _pet.speak_tr("計時到 %s 了!") % format_duration(seconds), 6.0)
	for i in 3:
		if not is_instance_valid(_pet):
			return
		_pet.get_node("/root/DesktopShellState").sound_requested.emit(_pet, sound)
		_pet.perform_hops(2, false)
		await get_tree().create_timer(1.1).timeout
	for i in ALERT_HOPS - 3:
		if not is_instance_valid(_pet):
			return
		_pet.perform_hops(2, false)
		await get_tree().create_timer(0.9).timeout


# --- 存檔 ---

static func dir_path() -> String:
	return dir_override if dir_override != "" else DIR


func file_path() -> String:
	var name: String = _pet.recognition_tag if _pet.recognition_tag != "" else _pet.display_name
	return dir_path().path_join(name.validate_filename() + ".json")


func _write(state: String) -> void:
	if _pet == null or not is_instance_valid(_pet):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path()))
	var file := FileAccess.open(file_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"kind": int(kind), "total": total, "elapsed": elapsed, "sound": sound, "state": state, "laps": laps,
		"reminder_interval": reminder_interval, "reminder_waypoints": reminder_waypoints, "pending_waypoints": _pending_waypoints,
		"next_interval_at": _next_interval_at, "saved_at": Time.get_unix_time_from_system(),
	}))
	file.close()


func _clear() -> void:
	kind = Kind.NONE
	running = false
	total = 0.0
	elapsed = 0.0
	laps = []
	reminder_interval = 0.0
	reminder_waypoints = []
	_pending_waypoints = []
	_next_interval_at = 0.0
	if _pet != null and is_instance_valid(_pet) and FileAccess.file_exists(file_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path()))


## 出現後檢查上次留下的紀錄:paused = 說出最後記到的時間並問要不要繼續;running = 上次沒正常結束 → 計時失敗;讀不出來 → 計時失敗。
func _restore() -> void:
	if not FileAccess.file_exists(file_path()):
		return
	var json := JSON.new()   # 不用 parse_string:壞掉的紀錄是預期情況,不要在錯誤紀錄裡留下引擎的解析錯誤
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(file_path())) == OK else null
	var path := file_path()
	if not parsed is Dictionary or not _valid(parsed):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_say(_pet.speak_tr("計時失敗了……上次的計時紀錄壞掉,讀不出來。"), 6.0)
		return
	var data: Dictionary = parsed
	var saved_kind := int(data["kind"]) as Kind
	var saved_total := float(data["total"])
	var saved_elapsed := float(data["elapsed"])
	if str(data["state"]) != "paused":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_say(_pet.speak_tr("計時失敗了……上次遊戲不是正常關閉的,最後只記錄到大約 %s。") % format_duration(saved_elapsed), 7.0)
		return
	var recorded: String = _pet.speak_tr("上次計時最後記到 %s") % format_duration(saved_elapsed)
	if saved_total > 0.0:
		recorded += _pet.speak_tr(",還剩 %s") % format_duration(maxf(saved_total - saved_elapsed, 0.0))
	var choice: int = await GameChat.ask(_pet, recorded + _pet.speak_tr("。要繼續計時嗎?"), [_pet.speak_tr("繼續計時"), _pet.speak_tr("結束計時")], 40.0)
	if not is_instance_valid(_pet) or active():
		return
	if choice == 0:
		kind = saved_kind
		total = saved_total
		elapsed = saved_elapsed
		laps = _clean_laps(data.get("laps", []))
		sound = str(data["sound"]) if SoundManager.has_sound(str(data["sound"])) else ALERT_SOUND_DEFAULT
		reminder_interval = clampf(float(data.get("reminder_interval", 0.0)) if _is_number(data.get("reminder_interval", 0.0)) else 0.0, 0.0, MAX_SECONDS)
		reminder_waypoints = _clean_laps(data.get("reminder_waypoints", []))
		_pending_waypoints = _clean_laps(data.get("pending_waypoints", reminder_waypoints))
		_next_interval_at = float(data.get("next_interval_at", reminder_interval)) if _is_number(data.get("next_interval_at", reminder_interval)) else reminder_interval
		running = true
		_write("running")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


static func _valid(data: Dictionary) -> bool:
	for key: String in ["kind", "total", "elapsed", "state"]:
		if not data.has(key):
			return false
	if not (data["kind"] is float or data["kind"] is int) or not [1, 2].has(int(data["kind"])):
		return false
	for key: String in ["total", "elapsed"]:
		if not (data[key] is float or data[key] is int) or float(data[key]) < 0.0 or float(data[key]) > MAX_SECONDS:
			return false
	return data["state"] is String and ["paused", "running"].has(str(data["state"]))


## 存檔裡的 laps 欄位是舊版存檔沒有的選用欄位,不影響整筆紀錄合不合法(見 _valid);這裡另外把它清乾淨:
## 型別不對的值丟掉、超過上限只留最近 MAX_LAPS 個。
static func _clean_laps(raw: Variant) -> Array[float]:
	var result: Array[float] = []
	if raw is Array:
		for value: Variant in raw:
			if (value is float or value is int) and float(value) >= 0.0 and float(value) <= MAX_SECONDS:
				result.append(float(value))
	if result.size() > MAX_LAPS:
		result = result.slice(result.size() - MAX_LAPS)
	return result


## 計時訊息(完成提醒、中途提醒)都要讓使用者當下看到,不管「對話集中」開不開、這隻桌寵有沒有另外開「即使
## 存在聊天室也顯示氣泡」——2026-10-02 使用者要求,見 GameChat.say() 的 force_bubble 參數說明。
func _say(text: String, seconds: float) -> void:
	if is_instance_valid(_pet):
		GameChat.say(_pet, text, seconds, false, true)


# --- 時間的文字 ---

## 「1 小時 2 分 3 秒」(0 的單位省略;整個是 0 = 「0 秒」)。
static func format_duration(seconds: float) -> String:
	var whole := int(round(seconds))
	var hours := whole / 3600
	var minutes := (whole % 3600) / 60
	var secs := whole % 60
	var parts: Array[String] = []
	if hours > 0:
		parts.append(TranslationServer.translate("%d 小時") % hours)
	if minutes > 0:
		parts.append(TranslationServer.translate("%d 分") % minutes)
	if secs > 0 or parts.is_empty():
		parts.append(TranslationServer.translate("%d 秒") % secs)
	return " ".join(parts)


## 「8:12」/「1:02:03」。
static func clock_text(seconds: float) -> String:
	var whole := int(ceil(seconds))
	var hours := whole / 3600
	var minutes := (whole % 3600) / 60
	var secs := whole % 60
	return "%d:%02d:%02d" % [hours, minutes, secs] if hours > 0 else "%d:%02d" % [minutes, secs]


## 把使用者輸入的「中途提醒」設定解析成 {ok, interval, waypoints}(純函式,方便測試)。
## 用全形/半形逗號、頓號分段,每段各自判斷:「每…」開頭 = 間隔提醒(每隔這麼多秒響一次);其餘當成一個時間點
## (可以寫「到10分鐘」的「到」也可以省略,兩種都認)。空字串 = 沒設定(ok=true,都是空/0)。任一段看不懂就整個 ok=false
## (不要只套用看得懂的那幾段,免得使用者以為全部都設定成功了)。
static func parse_reminder_spec(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return {"ok": true, "interval": 0.0, "waypoints": [] as Array[float]}
	var pieces := trimmed.replace("、", ",").replace(",", ",").split(",")
	var interval := 0.0
	var waypoints: Array[float] = []
	for raw_piece: String in pieces:
		var piece := raw_piece.strip_edges()
		if piece == "":
			continue
		if piece.begins_with("每"):
			var seconds := parse_duration(piece.substr(1))
			if seconds <= 0.0:
				return {"ok": false, "interval": 0.0, "waypoints": [] as Array[float]}
			interval = seconds
		else:
			var seconds := parse_duration(piece.trim_prefix("到"))
			if seconds <= 0.0:
				return {"ok": false, "interval": 0.0, "waypoints": [] as Array[float]}
			waypoints.append(seconds)
	return {"ok": true, "interval": interval, "waypoints": waypoints}


## 把使用者輸入的時間轉成秒(純函式,方便測試)。認得:
##   「25:00」「1:30:00」(分:秒、時:分:秒)、「10」(單獨一個數字 = 分鐘)、
##   「10 分鐘」「10分」「90秒」「1 小時 30 分」「1小時30分15秒」、「1.5 小時」、「10m」「1h30m」「45s」「90 min」。
## 空字串回 0;看不懂回 -1;超過上限回 -1。
static func parse_duration(text: String) -> float:
	var s := text.strip_edges().to_lower().replace("：", ":").replace("　", " ")
	if s == "":
		return 0.0
	if ":" in s:
		var pieces := s.split(":")
		if pieces.size() < 2 or pieces.size() > 3:
			return -1.0
		var total := 0.0
		for piece in pieces:
			if not piece.strip_edges().is_valid_int():
				return -1.0
			total = total * 60.0 + float(piece.strip_edges().to_int())
		return total if total <= MAX_SECONDS else -1.0
	if s.is_valid_float():
		var minutes := s.to_float()
		return minutes * 60.0 if minutes >= 0.0 and minutes * 60.0 <= MAX_SECONDS else -1.0
	var regex := RegEx.new()
	regex.compile("(\\d+(?:\\.\\d+)?)\\s*(小時|時|hours?|hrs?|h|分鐘|分|minutes?|mins?|m|秒鐘|秒|seconds?|secs?|s)")
	var matches := regex.search_all(s)
	if matches.is_empty():
		return -1.0
	var consumed := ""
	var seconds := 0.0
	for found in matches:
		consumed += found.get_string()
		var amount := float(found.get_string(1))
		var unit := found.get_string(2)
		if unit in ["小時", "時", "hour", "hours", "hr", "hrs", "h"]:
			seconds += amount * 3600.0
		elif unit in ["分鐘", "分", "minute", "minutes", "min", "mins", "m"]:
			seconds += amount * 60.0
		else:
			seconds += amount
	if s.replace(" ", "").length() != consumed.replace(" ", "").length():
		return -1.0   # 有看不懂的多餘文字
	return seconds if seconds <= MAX_SECONDS else -1.0
