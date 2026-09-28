class_name UpdateChecker
extends Node
## 檢查更新(系統匣選單「檢查更新…」):使用者點了才會真的連線,不會自動背景檢查。讀公開開源 repo 的 GitHub
## Releases API,拿最新版本標籤跟目前版本(CreditsData.version())比,回報「已是最新」「有新版本(附連結)」
## 或「連線/格式失敗」。失敗一律靜默略過、只顯示一句話,不會讓程式跳錯誤訊息或崩潰。
##
const REPO_OWNER := "MaltoseSlime"
const REPO_NAME := "SDPE---Slime-Desktop-Pet-Editor"
const RELEASES_PAGE_URL := "https://github.com/%s/%s/releases"
const TIMEOUT_SECONDS := 10.0

## {status: "up_to_date"/"update_available"/"error", message: 給使用者看的一句話, latest/current: 版本號(error 時可能沒有)}。
signal check_finished(result: Dictionary)

var _request: HTTPRequest


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT_SECONDS
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)


func _api_url() -> String:
	return "https://api.github.com/repos/%s/%s/releases/latest" % [REPO_OWNER, REPO_NAME]


func releases_page_url() -> String:
	return RELEASES_PAGE_URL % [REPO_OWNER, REPO_NAME]


## 使用者按下「檢查更新…」時呼叫。
func check_for_update() -> void:
	var error := _request.request(_api_url(), PackedStringArray(["User-Agent: SlimeDesktopPetEditor"]))
	if error != OK:
		check_finished.emit({"status": "error", "message": "沒辦法連線檢查更新,請確認網路連線後再試一次。"})


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_finished.emit({"status": "error", "message": TranslationServer.translate("沒辦法連線檢查更新(代碼 %d),請稍後再試一次。") % response_code})
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not (parsed as Dictionary).has("tag_name"):
		check_finished.emit({"status": "error", "message": "更新資訊的格式看不懂,晚點再試試看。"})
		return
	var latest := str((parsed as Dictionary)["tag_name"])
	var current := CreditsData.version()
	if is_newer(latest, current):
		check_finished.emit({"status": "update_available", "latest": latest, "current": current, "message": TranslationServer.translate("有新版本可以更新:%s(目前是 %s)。") % [latest, current]})
	else:
		check_finished.emit({"status": "up_to_date", "latest": latest, "current": current, "message": TranslationServer.translate("已經是最新版本(%s)。") % current})


## 比較兩個版本字串(純函式,方便測試):容許開頭有沒有 "v",用點分隔的數字逐段比較,缺的段當 0。任一段不是
## 數字就當 0——版本號格式壞掉一律當「沒有更新」,不會因為格式跟預期不同就誤判成有新版本推播給使用者。
static func is_newer(remote: String, current: String) -> bool:
	var remote_parts := _version_parts(remote)
	var current_parts := _version_parts(current)
	var length := maxi(remote_parts.size(), current_parts.size())
	for i in length:
		var r := remote_parts[i] if i < remote_parts.size() else 0
		var c := current_parts[i] if i < current_parts.size() else 0
		if r != c:
			return r > c
	return false


static func _version_parts(text: String) -> Array[int]:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("v") or cleaned.begins_with("V"):
		cleaned = cleaned.substr(1)
	var result: Array[int] = []
	for part: String in cleaned.split("."):
		result.append(int(part) if part.is_valid_int() else 0)
	return result
