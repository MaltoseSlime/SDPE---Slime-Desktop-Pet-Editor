class_name CreditsData
extends RefCounted
## 「關於」頁的內容(Godot 端全局設定的頁籤,與網頁編輯器的「關於」分頁共用同一份清單:網頁的 CREDITS_ITEMS 是照這裡的 ITEMS 逐筆產生的,改一邊要改另一邊)。
## 只放隨遊戲一起發行的東西;授權全文寫在遊戲資料夾裡的 THIRD_PARTY_LICENSES.txt(見 docs/打包指南.md),這一頁不解釋。

const AUTHOR := "MaltoseSlime"
const PROJECT_NAME := "史萊姆桌寵引擎"
const AI_NOTE := "程式碼由 Claude(Anthropic)協助撰寫。"
const NO_IMAGE_AI_NOTE := "未使用生成式 AI 製作的圖像素材。"
const LICENSE_FILE := "THIRD_PARTY_LICENSES.txt"
## 網頁積木編輯器上架的位置(itch.io);系統匣「開啟網頁編輯工具」用瀏覽器打開它。
const WEB_EDITOR_URL := "https://maltoseslime.itch.io/slime-desktop-pet-editor-event"


## 目前的版本號(專案設定 應用程式 > 設定 > 版本,例如 "0.1.0");標題列右側顯示,網頁編輯器的頁尾寫同一個號碼。
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## 每筆:{category, name, by, license, url}。url 只放確定的網址(空字串 = 沒有),有的話名稱會變成連結。
const ITEMS: Array[Dictionary] = [
	{"category": "字體", "name": "源樣黑體 GenYoGothic TW", "by": "ButTaiwan", "license": "SIL OFL 1.1", "url": "https://github.com/ButTaiwan/genyo-font"},
	{"category": "字體", "name": "jf open 粉圓", "by": "justfont", "license": "SIL OFL 1.1", "url": "https://github.com/justfont/open-huninn-font"},
	{"category": "字體", "name": "Silver", "by": "Poppy Works", "license": "CC BY 4.0", "url": "https://poppy.works/"},
	{"category": "字體", "name": "Cubic-11 俐方體", "by": "ACh-K", "license": "SIL OFL 1.1", "url": "https://github.com/ACh-K/Cubic-11"},
	{"category": "素材", "name": "範例角色 Mal", "by": "作者提供", "license": "", "url": ""},
	{"category": "素材", "name": "內建音效", "by": "作者提供", "license": "", "url": ""},
	{"category": "引擎與函式庫", "name": "Godot Engine", "by": "Godot Engine 貢獻者", "license": "MIT", "url": "https://godotengine.org"},
	{"category": "引擎與函式庫", "name": "Blockly", "by": "Google", "license": "Apache 2.0", "url": "https://developers.google.com/blockly"},
]


static func categories() -> Array[String]:
	var result: Array[String] = []
	for item in ITEMS:
		if not result.has(str(item["category"])):
			result.append(str(item["category"]))
	return result


## 一筆的一行文字:名稱(有網址就是連結)— 作者(授權)。
static func item_line(item: Dictionary) -> String:
	var name_text := str(item["name"])
	if str(item["url"]) != "":
		name_text = "[url=%s]%s[/url]" % [item["url"], name_text]
	var detail := str(item["by"])
	if str(item["license"]) != "":
		detail += "・%s" % item["license"]
	return "• %s — %s" % [name_text, detail]


## 頁面的 BBCode 內容(RichTextLabel 用;連結由頁面自己驗證再開)。
static func bbcode() -> String:
	var text := TranslationServer.translate("[b][font_size=20]關於[/font_size][/b]\n%s\n作者:[b]%s[/b]\n\n%s\n%s\n") % [PROJECT_NAME, AUTHOR, AI_NOTE, NO_IMAGE_AI_NOTE]
	for category in categories():
		text += "\n[b]%s[/b]\n" % category
		for item in ITEMS:
			if str(item["category"]) == category:
				text += item_line(item) + "\n"
	text += TranslationServer.translate("\n[color=#a8a8a8]授權全文:遊戲資料夾裡的 %s[/color]") % LICENSE_FILE
	return text


## 只有 https 開頭、而且是 ITEMS 裡列出的網址才允許開啟(頁面上的連結由程式產生,這裡再驗證一次)。
static func is_openable(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	for item in ITEMS:
		if str(item["url"]) == url:
			return true
	return false
