class_name NativeHelper
extends RefCounted
## native/ 底下的小 .NET 工具(目前只有視窗列舉 window_rects)的編譯流程:
## 第一次使用時以 Windows 內建的 csc.exe 編譯到 user://helpers/,之後直接重用;原始碼有變動(用內容雜湊判斷)才重新編譯。

const CSC_PATH := "C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
const HELPER_DIR := "user://helpers/"


## 確保小工具已編譯,回傳執行檔的絕對路徑;讀不到原始碼或編譯失敗回傳 ""。
static func ensure_built(source_path: String, helper_name: String) -> String:
	var source := FileAccess.get_file_as_string(source_path)
	if source.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(HELPER_DIR)
	# csc 對路徑裡的正斜線會誤判(把 C:/x/y.cs 當成 C:\y.cs),所以交給它的路徑一律用反斜線。
	var dir := OS.get_user_data_dir().replace("/", "\\") + "\\helpers"
	var exe_path := dir + "\\" + helper_name + ".exe"
	var hash_path := HELPER_DIR + helper_name + ".hash"
	var source_hash := source.md5_text()
	var built_hash := FileAccess.get_file_as_string(hash_path)
	if FileAccess.file_exists(exe_path) and built_hash == source_hash:
		return exe_path
	var cs_path := dir + "\\" + helper_name + ".cs"
	var file := FileAccess.open(HELPER_DIR + helper_name + ".cs", FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(source)
	file.close()
	var output: Array = []
	var code := OS.execute(
		CSC_PATH.replace("/", "\\"),
		["/nologo", "/optimize+", "/target:exe", "/out:" + exe_path, cs_path],
		output
	)
	if code != 0 or not FileAccess.file_exists(exe_path):
		push_warning("csc 編譯輸出: %s" % str(output))
		return ""
	var hash_file := FileAccess.open(hash_path, FileAccess.WRITE)
	hash_file.store_string(source_hash)
	hash_file.close()
	return exe_path
