class_name PetText
extends RefCounted
## 使用者輸入給桌寵的文字(稱呼、抽籤選項…)的消毒與解析。
## 這類文字只會被「當成資料」存起來、顯示出來:永遠不會被當成積木、路徑、指令或格式字串執行。
## 存進 Pet.text_values 前一律經過 sanitize();顯示到對話氣泡前一律經過 escape_bbcode()
## (使用者打的 [b]、[img=…] 之類不會變成排版標籤,{名稱} 之類也不會被再次當成插值)。

const DEFAULT_MAX_LENGTH := 24
const HARD_MAX_LENGTH := 200
const MAX_KEY_LENGTH := 40
const MAX_OPTIONS := 50
const MAX_OPTION_LENGTH := 40
const OPTION_SEPARATORS := "[\\n\\r,，、;；|]+"


## 去掉控制字元(含換行、Tab)、頭尾空白,並截到 max_length 個字元。
static func sanitize(text: String, max_length := DEFAULT_MAX_LENGTH) -> String:
	var cleaned := ""
	for i in text.length():
		var code := text.unicode_at(i)
		# 控制字元、私用區、方向控制字元(可用來偽裝文字順序)一律丟掉。
		if code < 32 or code == 127 or (code >= 0xE000 and code <= 0xF8FF) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069):
			continue
		cleaned += text[i]
	return cleaned.strip_edges().left(clampi(max_length, 1, HARD_MAX_LENGTH))


## 關鍵詞庫(見 Pet.keywords):角色會想或提及的事物。最多 MAX_KEYWORDS 個、每個最多 MAX_KEYWORD_LENGTH 字;
## 消毒後拿掉大括號(免得被當成插值標記)、去掉空白與重複的。順序保留。
const MAX_KEYWORDS := 60
const MAX_KEYWORD_LENGTH := 16
const DEFAULT_KEYWORD := "某個東西"


static func sanitize_keywords(raw: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	var items: Array = []
	if raw is String:
		items = (raw as String).replace("\r", "\n").split("\n")
	elif raw is Array or raw is PackedStringArray:
		items = Array(raw)
	for item in items:
		var cleaned := sanitize(str(item).replace("{", "").replace("}", ""), MAX_KEYWORD_LENGTH)
		if cleaned != "" and not result.has(cleaned):
			result.append(cleaned)
			if result.size() >= MAX_KEYWORDS:
				break
	return result


## 變數名稱:同樣消毒,長度上限 MAX_KEY_LENGTH。
static func sanitize_key(key: String) -> String:
	return sanitize(key, MAX_KEY_LENGTH)


## 給 RichTextLabel(BBCode)顯示前用:方括號換成 [lb] / [rb],使用者打的標籤只會當成普通文字。
static func escape_bbcode(text: String) -> String:
	# 逐字處理:先後取代會把第一次換出來的 [lb] 裡的 ] 又換掉。
	var escaped := ""
	for character in text:
		escaped += "[lb]" if character == "[" else ("[rb]" if character == "]" else character)
	return escaped


## 創作者在積木裡寫的對話允許使用的 BBCode 標籤(與 DialogueBubble.STYLE_TAG_REGEX、HTML 編輯器工具列同一份清單);
## icon 是數值插值產生的圖示標記,lb/rb 是跳脫的方括號。其餘標籤([img]、[url]、[font]…)一律不生效,只會顯示成普通文字。
const ALLOWED_TAGS: Array[String] = ["b", "i", "u", "s", "color", "font_size", "center", "right", "wave", "shake", "rainbow", "pulse", "icon", "lb", "rb"]
static var _TAG_REGEX := RegEx.create_from_string("\\[(/?)([A-Za-z_]+)([^\\[\\]]*)\\]")
static var _PARAM_REGEX := RegEx.create_from_string("^(?:[= ][#\\w.,\\- =]*)?$")


## 把不在白名單的標籤(或參數怪怪的標籤)的開頭方括號換成 [lb],讓它們只顯示成文字、不觸發載入圖片/連結/字型等功能。
static func filter_bbcode(text: String) -> String:
	if not text.contains("["):
		return text
	var result := ""
	var cursor := 0
	for tag_match in _TAG_REGEX.search_all(text):
		result += text.substr(cursor, tag_match.get_start() - cursor)
		var raw := tag_match.get_string()
		var tag_name := tag_match.get_string(2).to_lower()
		var params := tag_match.get_string(3)
		var allowed := ALLOWED_TAGS.has(tag_name) and (tag_name == "icon" or _PARAM_REGEX.search(params) != null) and not (tag_match.get_string(1) == "/" and params != "")
		result += raw if allowed else "[lb]" + raw.substr(1)
		cursor = tag_match.get_end()
	return result + text.substr(cursor)


## 把一串選項(換行、半形逗號、全形逗號、頓號、分號、豎線分隔)拆成清單:每項消毒、去空白項、最多 MAX_OPTIONS 項。
static func parse_options(raw: String) -> Array[String]:
	var options: Array[String] = []
	for part in RegEx.create_from_string(OPTION_SEPARATORS).sub(raw, "\n", true).split("\n", false):
		var option := sanitize(part, MAX_OPTION_LENGTH)
		if option != "":
			options.append(option)
		if options.size() >= MAX_OPTIONS:
			break
	return options

static var _STYLE_ONLY_REGEX := RegEx.create_from_string("\\[/?(?:b|i|u|s|color|font_size|center|right|wave|shake|rainbow|pulse)(?:[= ][^\\]]*)?\\]")


## 這段 BBCode 拿掉樣式標籤後是不是空白(沒有任何可顯示的字;[icon=…] 圖示與 [lb]/[rb] 算內容)。
static func is_blank_bbcode(text: String) -> bool:
	return _STYLE_ONLY_REGEX.sub(text, "", true).strip_edges() == ""
