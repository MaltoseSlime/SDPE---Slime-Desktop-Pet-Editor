class_name InteractionRules
extends RefCounted
## 桌寵管理「交互行為」頁籤的資料(存在角色設定檔的 "interaction"):不用寫積木就能調的三件事。
## 1. actions:事件 → 動作的對應(例如「被摸摸」改用素材包裡的 shy 動作)。程式裡所有播放該事件動作的地方都會換成選的動作(素材沒有就退回原本的)。
## 2. characters:對場上另一個角色(不含自己)的反應,只有對話。編譯成「當場內出現那個角色時」的事件積木(event_when_pet_state,KIND = present),接在解譯器的「規則層」。
## 3. props:對某個道具的反應:對話(編譯成 event_prop_* 積木)+ 動作(執行期由 Pet.begin_prop_action 播:只做一次,或持續到道具用完 / 離開判定,像摸摸移開後才恢復)。
## 4. prefs:喜歡 / 不喜歡的道具(存道具資料夾名稱 id 與當時的顯示名稱)。喜歡的道具掉在場上會自己走過去撿、撿到心情變好;不喜歡的不會自己撿(拖著遞給它還是會收);「不與此道具交互」(ignore)則完全無視:不撿、不被它摩擦、不會成為候選、也不被它吸引。
##    道具資料找不到(被刪掉、搬走)時列表顯示成灰色,可以「重新連結」到現有的另一個道具。
## 5. ignore_props / ignore_furniture / no_follow_target / no_follow_source:整隻桌寵層級的總開關
##    (跟上面 3/4 的「對某個道具/某個偏好」不一樣,這兩個是全部生效)。
##    ignore_props = true 時,Pet.prop_preference() 對任何道具都回傳 "ignore"(等於幫每個道具都設了「不與此道具交互」)。
##    ignore_furniture = true 時,關掉自主使用家具的行為(目前只有容器類的自主拿取,見 Pet._container_goal());
##    使用者手動拖曳桌寵去用家具、或積木「加入使用家具」這種明確指定的互動不受影響,只擋「自己決定要不要去用」的部分。
##    no_follow_target = true 時,不會被選為別隻桌寵「自己決定要跟著誰走」的對象(見 Pet._nearest_followable_pet());
##    no_follow_source = true 時,自己不會主動決定跟著別隻桌寵走(見 Pet._tick_auto_pet_follow())。
##    這三個(no_follow_target/no_follow_source/ignore_furniture)在固定/靜止模式下會被自動強制打開,
##    離開這兩種模式後換回使用者原本自己設定的值,見 Pet._apply_move_mode_interaction_defaults()。
##    show_bubble_in_chatroom = true 時(2026-10-01 加入),全局設定切成「聊天室式」對話顯示時,這隻桌寵不用
##    等使用者互動的句子(閒聊、狀態播報…)依然會額外彈出浮動氣泡(不是只寫進聊天記錄)——兩邊同時顯示,
##    見 UiManager._show_bubble()。沒開啟「聊天室式」對話顯示時這個設定完全不影響行為。
## 詳細編輯(條件、選項、連續動作…)要到網頁端積木編輯器;這裡只提供最常用、最簡單的部分。所有欄位讀進來都會驗證與夾範圍。

const MAX_TEXT := 120
const MAX_LINES := 12
const MAX_CHARACTERS := 30
const MAX_PROP_RULES := 60
const MAX_PREFS := 200
const PREFS := ["like", "dislike", "ignore"]
## 可以換動作的事件:[事件代號(= 系統動作名稱), 顯示名稱]。
## sit/lay 這兩個同時也是家具坐/躺錨點類型(見 FurnitureDef.ANCHOR_TYPES)直接拿來播的動作名稱——素材包作者
## 如果準備了不同於預設 sit/lay 的坐躺姿勢動作(例如另外取名的自訂動作),可以在這裡把 sit/lay 重新指到那個動作,
## 既有家具(anchors 存的仍是 "sit"/"lay" 字面值)不用重新編輯就會自動改用新指定的動作,不會因為代號對不起來而壞掉。
## climb_wall/climb_ceiling(2026-10-01 加入):素材包有沒有專屬的爬牆/天花板動畫本身就會自動取代退回用的
## walk 轉 90°/180° 湊出來的效果(見 Pet._wall_upright()/_ceiling_dedicated()),這裡讓使用者能像其他事件
## 一樣,改指到素材包裡另一個自訂名稱的動作(例如叫 "crawl" 的動作),不用剛好取名 climb_wall/climb_ceiling
## 才會被認得;改指到的動作也會反過來影響「該不該轉正」的判斷(_wall_upright/_ceiling_dedicated 也查同一個
## 對應),不會出現「播的是自訂動畫,角度卻還是照舊轉 90°」這種不一致。
const ACTION_SLOTS: Array[Array] = [
	["interact", "被觸摸 / 互動"], ["drag", "被拖曳"], ["gather", "拾取 / 使用道具"], ["enter", "入場"], ["leave", "退場"],
	["sleep", "睡覺"], ["sit", "坐下休息(含家具的坐下錨點)"], ["lay", "躺下休息(含家具的躺下錨點)"], ["dance", "跳舞"], ["walk", "走路"], ["run", "奔跑"], ["idle", "待機"], ["rise", "跳起(上升)"], ["fall", "落下"],
	["climb_wall", "爬牆"], ["climb_ceiling", "爬天花板"],
]
## 道具反應的觸發時機。
const PROP_KINDS := {"collected": "道具消耗", "rubbed": "被摩擦", "candidate": "道具選中"}


static func empty() -> Dictionary:
	return {"actions": {}, "characters": [], "props": [], "prefs": [], "ignore_props": false, "ignore_furniture": false, "no_follow_target": false, "no_follow_source": false, "show_bubble_in_chatroom": false}


static func slot_keys() -> Array[String]:
	var keys: Array[String] = []
	for slot in ACTION_SLOTS:
		keys.append(str(slot[0]))
	return keys


static func _text(value: Variant) -> String:
	return str(value).strip_edges().replace("\n", " ").replace("\t", " ").left(MAX_TEXT)


## 驗證並整理(壞的項目丟掉、超量截斷);回傳乾淨的字典。
static func clean(raw: Variant) -> Dictionary:
	var result := empty()
	if not raw is Dictionary:
		return result
	var slots := slot_keys()
	if raw.get("actions") is Dictionary:
		for key: Variant in raw["actions"]:
			var action := _text(raw["actions"][key])
			if slots.has(str(key)) and action != "" and action != str(key):
				result["actions"][str(key)] = action
	if raw.get("characters") is Array:
		for entry: Variant in raw["characters"]:
			if not entry is Dictionary or (result["characters"] as Array).size() >= MAX_CHARACTERS:
				continue
			var tag := _text(entry.get("tag", ""))
			var lines: Array[String] = []
			if entry.get("lines") is Array:
				for line: Variant in entry["lines"]:
					if _text(line) != "" and lines.size() < MAX_LINES:
						lines.append(_text(line))
			if tag == "" or lines.is_empty():
				continue
			var merged := false
			for existing: Dictionary in result["characters"]:
				if existing["tag"] == tag:
					existing["lines"].append_array(lines.slice(0, maxi(MAX_LINES - (existing["lines"] as Array).size(), 0)))
					merged = true
			if not merged:
				result["characters"].append({"tag": tag, "name": _text(entry.get("name", tag)), "lines": lines})
	if raw.get("props") is Array:
		for entry: Variant in raw["props"]:
			if not entry is Dictionary or (result["props"] as Array).size() >= MAX_PROP_RULES:
				continue
			var prop := _text(entry.get("prop", ""))
			var kind := str(entry.get("kind", "collected"))
			var line := _text(entry.get("line", ""))
			var action := _text(entry.get("action", ""))
			if prop == "" or not PROP_KINDS.has(kind) or (line == "" and action == ""):
				continue
			var persist_raw: Variant = entry.get("persist", false)
			result["props"].append({"prop": prop, "kind": kind, "line": line, "action": action, "persist": persist_raw if persist_raw is bool else false})
	if raw.get("prefs") is Array:
		var seen := {}
		for entry: Variant in raw["prefs"]:
			if not entry is Dictionary or (result["prefs"] as Array).size() >= MAX_PREFS:
				continue
			var id := _text(entry.get("id", ""))
			var pref := str(entry.get("pref", ""))
			if id == "" or not PREFS.has(pref) or seen.has(id):
				continue
			seen[id] = true
			result["prefs"].append({"id": id, "name": _text(entry.get("name", id)), "pref": pref})
	for key in ["ignore_props", "ignore_furniture", "no_follow_target", "no_follow_source", "show_bubble_in_chatroom"]:
		var value_raw: Variant = raw.get(key, false)
		result[key] = value_raw if value_raw is bool else false
	return result


## 對這個道具(資料夾名稱 id)的喜好:"like" / "dislike" / ""(沒設)。
static func preference_of(rules: Dictionary, prop_id: String) -> String:
	for entry: Dictionary in rules.get("prefs", []):
		if entry["id"] == prop_id:
			return str(entry["pref"])
	return ""


## 這個事件現在改用哪個動作(沒設就原本的)。
static func mapped_action(rules: Dictionary, action: StringName) -> StringName:
	var mapped: Variant = (rules.get("actions", {}) as Dictionary).get(String(action))
	return StringName(str(mapped)) if mapped != null else action


## 找對這個道具、這種時機的規則(有動作的優先);沒有回空字典。
static func prop_rule(rules: Dictionary, prop_name: String, kind: String) -> Dictionary:
	var found := {}
	for rule: Dictionary in rules.get("props", []):
		if rule["prop"] == prop_name and rule["kind"] == kind:
			if str(rule["action"]) != "":
				return rule
			if found.is_empty():
				found = rule
	return found


static func _dialogue(text: String, id: String) -> Dictionary:
	return {"type": "dialogue_line", "id": id, "fields": {"TEXT": text, "FONT": "__default__", "BIND_ACTION": "", "SPEAKER": "", "WAIT": true, "TYPEWRITER": true, "AUTOSEC": 3}}


## 把幾句對話串成一條積木鏈(每句的 next 接下一句);沒有句子回空字典。
static func _chain(lines: Array, id_prefix: String) -> Dictionary:
	var head := {}
	for i in range(lines.size() - 1, -1, -1):
		var block := _dialogue(str(lines[i]), "%s_%d" % [id_prefix, i])
		if not head.is_empty():
			block["next"] = {"block": head}
		head = block
	return head


## 編譯成解譯器「規則層」的事件積木:每個角色一顆「出現在場上時」事件、每條有對話的道具規則一顆對應的道具事件。
static func compile(rules: Dictionary) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var index := 0
	for entry: Dictionary in rules.get("characters", []):
		var chain := _chain(entry["lines"], "rule_c%d" % index)
		if not chain.is_empty():
			blocks.append({"type": "event_when_pet_state", "id": "rule_c%d_hat" % index,
					"fields": {"TAGS": entry["tag"], "KIND": "present", "VALUE": "", "EDGE": "start", "MATCH": "any", "INCLUDE_SELF": false},
					"inputs": {"DO": {"block": chain}}})
		index += 1
	index = 0
	for rule: Dictionary in rules.get("props", []):
		if str(rule["line"]) != "":
			blocks.append({"type": "event_prop_" + str(rule["kind"]), "id": "rule_p%d_hat" % index,
					"fields": {"PROP": rule["prop"], "NAME": "交互行為"},
					"inputs": {"DO": {"block": _dialogue(str(rule["line"]), "rule_p%d_line" % index)}}})
		index += 1
	return blocks
