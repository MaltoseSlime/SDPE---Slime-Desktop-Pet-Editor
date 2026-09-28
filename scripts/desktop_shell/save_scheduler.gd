class_name SaveScheduler
extends Node
## 存檔排程(企劃書第三章「在場累計時長與自動存檔持久化機制」、第九章第七階段第 2 項):
## ① 定期非同步存檔:每 AUTOSAVE_INTERVAL 秒(5 分鐘)把所有角色的執行狀態(局部數值、Flag、文字、狀態鏡、戰績、累計在場時長)與全域數值定義寫進存檔;
## ② 關鍵事件即時存檔:拿到 / 吃掉道具(gather)、對話分支選項改了數值、程式正常關閉前,呼叫 SaveScheduler.request(原因)(連續幾個事件會合併成一次);
## ③ 寫入互斥保護:全域只有一個「正在寫入」旗標與一個待寫入佇列,先到先寫,後到的請求排隊,前一次完全寫完才開始下一個(同一個檔案排隊中的舊資料會被新資料取代),
##    所以兩個存檔不會同時對同一個檔案做 I/O。檔案是寫到 .tmp 再換名,寫到一半當機也不會留下半個檔。實際寫檔在工作執行緒(資料先在主執行緒轉成文字),不卡畫面。
## 另外每 UPTIME_TICK 秒替場上每隻桌寵累加 1 分鐘「在場累計時長」(Pet.uptime_minutes,存在狀態檔),疲勞消耗會依它略微加快(見 Pet.uptime_factor)。
## 無頭測試、沒有開機名單的環境(PetRoster.enabled() 為假)預設不自動存,避免測試動到使用者的資料;測試可把 enabled 打開。

signal saved(reason: String, files: int)

const AUTOSAVE_INTERVAL := 300.0
const UPTIME_TICK := 60.0
## 連續的關鍵事件合併成一次存檔的等待時間(秒)。
const REQUEST_DEBOUNCE := 0.3

var enabled := true
## 測試用:每個檔案寫入前人工延遲的毫秒數(模擬慢速磁碟,驗證互斥)。
var write_delay_msec := 0
## 已寫完的檔案路徑(依完成順序,測試用;最多留 200 筆)。
var written_paths: Array[String] = []

var _autosave_left := AUTOSAVE_INTERVAL
var _uptime_left := UPTIME_TICK
var _debounce_left := -1.0
var _pending_reasons: Array[String] = []
var _queue: Array[Dictionary] = []
var _writing := false
var _task_id := -1
var _current_job: Dictionary = {}
var _batch_reason := ""
var _batch_files := 0
var _overlap_detected := false
var _active_writers := 0


func _ready() -> void:
	enabled = PetRoster.enabled()
	var state := get_node_or_null("/root/DesktopShellState")
	if state != null and state.has_signal("save_requested"):
		state.save_requested.connect(_on_save_requested)


## 從任何地方(包含 static 函式)呼叫:請求一次關鍵事件存檔。
static func request(reason: String) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var state := loop.root.get_node_or_null("DesktopShellState")
	if state != null and state.has_signal("save_requested"):
		state.save_requested.emit(reason)


func _on_save_requested(reason: String) -> void:
	if not enabled:
		return
	_pending_reasons.append(reason)
	if _debounce_left < 0.0:
		_debounce_left = REQUEST_DEBOUNCE


func is_busy() -> bool:
	return _writing or not _queue.is_empty()


func queue_size() -> int:
	return _queue.size()


## 有沒有偵測到兩個寫入同時進行(互斥失效才會是真,測試用)。
func overlap_detected() -> bool:
	return _overlap_detected


func _process(delta: float) -> void:
	_poll_writer()
	if not enabled:
		return
	_uptime_left -= delta
	if _uptime_left <= 0.0:
		_uptime_left += UPTIME_TICK
		add_uptime(1.0)
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_INTERVAL
		save_now("autosave")
	if _debounce_left >= 0.0:
		_debounce_left -= delta
		if _debounce_left < 0.0:
			var reasons := ",".join(PackedStringArray(_pending_reasons))
			_pending_reasons.clear()
			_debounce_left = -1.0
			save_now(reasons)


## 場上每隻桌寵加這麼多分鐘的在場累計時長。
func add_uptime(minutes: float) -> void:
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		if is_instance_valid(pet) and not pet.is_queued_for_deletion():
			pet.uptime_minutes += minutes


## 立刻把「現在的狀態」排進寫入佇列(不等下一個定期存檔)。pets = false 只存全域數值(結束程式時用,角色狀態已由結束流程處理)。
func save_now(reason: String, pets := true) -> void:
	var jobs := collect_jobs(pets)
	for job in jobs:
		_enqueue(job)
	_batch_reason = reason
	_batch_files += jobs.size()
	_pump()


## 目前所有要存的檔案(路徑 + 已轉成文字的內容)。每個角色只存代表(同角色多隻依複製品政策選一隻),另外加全域數值。
func collect_jobs(pets := true) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if pets:
		var state := get_node_or_null("/root/DesktopShellState")
		var policy: String = str(state.canonical_policy) if state != null else "earliest"
		var groups := PetRegistry.groups(get_tree())
		for key in groups:
			var pet: Node = PetRegistry.pick_default(groups[key], policy)
			if pet != null and is_instance_valid(pet) and not pet.is_queued_for_deletion():
				jobs.append({"path": PetProfile.state_path(pet), "text": JSON.stringify(PetProfile.state_snapshot(pet), "\t")})
	jobs.append({"path": PetProfile.PROFILE_DIR + PetProfile.GLOBAL_FILE, "text": JSON.stringify(PetProfile.snapshot_globals(), "\t")})
	return jobs


func _enqueue(job: Dictionary) -> void:
	for i in _queue.size():
		if _queue[i]["path"] == job["path"]:
			_queue[i] = job   # 同一個檔案還在排隊:用新的資料取代舊的
			return
	_queue.append(job)


func _pump() -> void:
	if _writing or _queue.is_empty():
		return
	_current_job = _queue.pop_front()
	_writing = true
	_task_id = WorkerThreadPool.add_task(_write_job.bind(_current_job))


func _poll_writer() -> void:
	if not _writing or _task_id < 0:
		return
	if not WorkerThreadPool.is_task_completed(_task_id):
		return
	_finish_current()
	_pump()


func _finish_current() -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	_writing = false
	written_paths.append(str(_current_job.get("path", "")))
	if written_paths.size() > 200:
		written_paths.pop_front()
	if _queue.is_empty():
		saved.emit(_batch_reason, _batch_files)
		_batch_files = 0


## 在工作執行緒執行:寫 .tmp 再換名。_active_writers 只在這裡加減,大於 1 代表互斥被破壞。
func _write_job(job: Dictionary) -> void:
	_active_writers += 1
	if _active_writers > 1:
		_overlap_detected = true
	if write_delay_msec > 0:
		OS.delay_msec(write_delay_msec)
	var path := str(job["path"])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file != null:
		file.store_string(str(job["text"]))
		file.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	_active_writers -= 1


## 等目前這筆寫完、再把佇列裡剩下的全部寫完(結束程式前用;會卡住呼叫者直到寫完)。
func flush() -> void:
	if _writing:
		_finish_current()
	while not _queue.is_empty():
		_current_job = _queue.pop_front()
		_writing = true
		_write_job(_current_job)
		_writing = false
		written_paths.append(str(_current_job.get("path", "")))
	if _batch_files > 0:
		saved.emit(_batch_reason, _batch_files)
		_batch_files = 0
