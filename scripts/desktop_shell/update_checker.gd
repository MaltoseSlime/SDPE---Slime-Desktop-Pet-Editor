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
## release 說明(body)開頭寫這個標記,代表這是一個「重要更新」(例如修了會讓程式卡死的嚴重 bug),
## 系統匣圖示會變紅點版提醒使用者,不用等使用者自己想到要去點「檢查更新…」。
const IMPORTANT_MARKER := "[IMPORTANT]"
## 開機背景自動檢查(見 auto_check_if_due())的節流間隔:同一台機器這段時間內只會真的連線一次。
## 這個功能不急(重要更新本來就該是很少見的事),節流故意抓寬一點,不要沒事就打 GitHub 的 API。
const AUTO_CHECK_INTERVAL_SECONDS := 3 * 24 * 60 * 60

## {status: "up_to_date"/"update_available"/"error", message: 給使用者看的一句話, latest/current: 版本號(error 時可能沒有)}。
signal check_finished(result: Dictionary)
## 「有沒有重要更新」這個快取旗標改變時發出(不管是使用者主動檢查、還是開機背景自動檢查觸發的都會發)。
## 不會跳任何視窗,純粹給系統匣圖示/選單文字這種被動 UI 用來同步顯示。
signal important_state_changed(available: bool, version: String)

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
	var newer := is_newer(latest, current)
	_update_important_cache(newer and is_important(parsed as Dictionary), latest)
	if newer:
		check_finished.emit({"status": "update_available", "latest": latest, "current": current, "message": TranslationServer.translate("有新版本可以更新:%s(目前是 %s)。") % [latest, current]})
	else:
		check_finished.emit({"status": "up_to_date", "latest": latest, "current": current, "message": TranslationServer.translate("已經是最新版本(%s)。") % current})


## 這一版 release 的說明(body)開頭有沒有寫 IMPORTANT_MARKER。
static func is_important(release: Dictionary) -> bool:
	return str(release.get("body", "")).strip_edges().begins_with(IMPORTANT_MARKER)


func _update_important_cache(available: bool, version: String) -> void:
	AppSettings.set_important_update_state(available, version if available else "")
	important_state_changed.emit(available, version if available else "")


## 開機呼叫:節流(見 AUTO_CHECK_INTERVAL_SECONDS),沒到期就什麼都不做。連線失敗/逾時/格式錯誤一律靜默
## 跳過(不更新 last_check,下次開機還會再試),不影響開機流程、不跳任何視窗——這是背景自動檢查,跟使用者
## 主動按「檢查更新…」(check_for_update())是兩條分開的路徑,只有找到「重要更新」時才會透過
## important_state_changed 訊號讓系統匣圖示/選單文字變成提醒過的樣子。
func auto_check_if_due() -> void:
	var state := AppSettings.important_update_state()
	if Time.get_unix_time_from_system() - int(state["last_check"]) < AUTO_CHECK_INTERVAL_SECONDS:
		return
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	add_child(request)
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not parsed is Dictionary or not (parsed as Dictionary).has("tag_name"):
			return
		var latest := str((parsed as Dictionary)["tag_name"])
		var newer := is_newer(latest, CreditsData.version())
		_update_important_cache(newer and is_important(parsed as Dictionary), latest))
	var error := request.request(_api_url(), PackedStringArray(["User-Agent: SlimeDesktopPetEditor"]))
	if error != OK:
		request.queue_free()


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
