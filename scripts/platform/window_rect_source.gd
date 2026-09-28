extends Node
## 平臺來源 A:桌面上各個視窗的矩形(主企劃書第二章「動態 2D 平臺生成」)。
##
## GDScript 沒有原生的視窗列舉功能,所以用一個 6KB 的小 .NET 程式(native/window_rects/)代勞:
## 第一次使用時以 Windows 內建的 csc.exe 編譯到 user://helpers/,之後直接重用。
## 它常駐待機約 14MB、CPU 幾乎為零,每秒列舉一次,結果有變動才輸出;沒有桌寵時整個程序會被關掉。
## 背景執行緒只負責讀取並解析輸出,結果一律交回主執行緒(不碰場景樹,符合規格一致性總則第 5 條)。

## 視窗矩形有變動時發出,座標為虛擬桌面的實體像素(全域螢幕座標)。
signal windows_changed(rects: Array[Rect2])

const SOURCE_PATH := "res://native/window_rects/window_rects.cs"
const CSC_PATH := "C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
const HELPER_DIR := "user://helpers/"
const HELPER_NAME := "window_rects"
const POLL_INTERVAL_MS := 1000

var windows: Array[Rect2] = []

var _thread: Thread
var _helper_pid := -1
var _stopping := false


func _exit_tree() -> void:
	stop()


func is_running() -> bool:
	return _thread != null


## 啟動或關閉列舉程序。沒有任何桌寵需要平臺時關掉,不留常駐成本。
func set_enabled(enabled: bool) -> void:
	if enabled:
		start()
	else:
		stop()


func start() -> void:
	if _thread != null or OS.get_name() != "Windows":
		return
	_stopping = false
	_thread = Thread.new()
	_thread.start(_run)


func stop() -> void:
	if _thread == null:
		return
	_stopping = true
	if _helper_pid > 0:
		OS.kill(_helper_pid)
	_thread.wait_to_finish()
	_thread = null
	_helper_pid = -1
	if not windows.is_empty():
		windows = []
		windows_changed.emit(windows)


func _run() -> void:
	var exe_path := _ensure_helper_built()
	if exe_path.is_empty():
		push_warning("視窗列舉小工具編譯失敗,平臺來源 A 停用(仍有行動區底部地面可用)")
		return
	var process := OS.execute_with_pipe(exe_path, [str(OS.get_process_id()), str(POLL_INTERVAL_MS)])
	if process.is_empty():
		push_warning("視窗列舉小工具啟動失敗,平臺來源 A 停用")
		return
	_helper_pid = process["pid"]
	var pipe: FileAccess = process["stdio"]
	while not _stopping:
		var line := pipe.get_line()
		if line.is_empty():
			break
		if line.begins_with("W:"):
			_publish.call_deferred(_parse(line))


func _publish(rects: Array[Rect2]) -> void:
	if _stopping:
		return
	windows = rects
	windows_changed.emit(rects)


func _parse(line: String) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var body := line.substr(2).strip_edges()
	if body.is_empty():
		return rects
	for entry in body.split(";"):
		var fields := entry.split(",")
		if fields.size() == 4:
			rects.append(
				Rect2(fields[0].to_float(), fields[1].to_float(), fields[2].to_float(), fields[3].to_float())
			)
	return rects


## 確保小工具已編譯:原始碼有變動(用內容雜湊判斷)或執行檔不存在時才重新編譯。回傳執行檔的絕對路徑。
func _ensure_helper_built() -> String:
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	if source.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(HELPER_DIR)
	# csc 對路徑裡的正斜線會誤判(把 C:/x/y.cs 當成 C:\y.cs),所以交給它的路徑一律用反斜線。
	var dir := OS.get_user_data_dir().replace("/", "\\") + "\\helpers"
	var exe_path := dir + "\\" + HELPER_NAME + ".exe"
	var hash_path := HELPER_DIR + HELPER_NAME + ".hash"
	var source_hash := source.md5_text()
	var built_hash := FileAccess.get_file_as_string(hash_path)
	if FileAccess.file_exists(exe_path) and built_hash == source_hash:
		return exe_path
	var source_path := dir + "\\" + HELPER_NAME + ".cs"
	var file := FileAccess.open(HELPER_DIR + HELPER_NAME + ".cs", FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(source)
	file.close()
	var output: Array = []
	var code := OS.execute(
		CSC_PATH.replace("/", "\\"),
		["/nologo", "/optimize+", "/target:exe", "/out:" + exe_path, source_path],
		output
	)
	if code != 0 or not FileAccess.file_exists(exe_path):
		push_warning("csc 編譯輸出: %s" % str(output))
		return ""
	var hash_file := FileAccess.open(hash_path, FileAccess.WRITE)
	hash_file.store_string(source_hash)
	hash_file.close()
	return exe_path
