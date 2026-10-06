class_name InteractionTab
extends VBoxContainer
## 交互行為分頁(桌寵管理):不用寫積木就能調的三件事,資料見 InteractionRules(存在角色設定檔的 "interaction"):
## ① 各種事件下用哪個動作(下拉選單換動作,沒設 = 原本的);② 對場上另一個角色(角色庫內的,不含自己)的反應,只能新增純對話;
## ③ 對某個道具(道具管理裡有的)的反應:對話 + 動作(只做一次,或持續到道具用完 / 離開判定,像摸摸移開才恢復)。
## 詳細編輯(條件、選項、連續動作…)要到網頁端積木編輯器調整,每張卡片的 ⓘ 都有這個提醒。改動即時生效(和其他分頁一樣要按「儲存」才寫進檔案)。

signal changed
signal message(text: String)

const CARD_WIDTH := 440.0
const WEB_HINT := "這裡只提供最常用、最簡單的設定;詳細編輯(條件、選項、連續動作、更多種反應…)要到網頁端積木編輯器調整。"
const DEFAULT_LABEL := "(預設)"

var _pet: Node
var _flow: HFlowContainer
var _loading := false
var _action_options: Dictionary = {}
var _char_option: OptionButton
var _char_line: LineEdit
var _char_list: VBoxContainer
var _prop_option: OptionButton
var _prop_kind_option: OptionButton
var _prop_line: LineEdit
var _prop_action_option: OptionButton
var _prop_persist_option: OptionButton
var _prop_list: VBoxContainer
var _pref_list: VBoxContainer
var _pet_pref_list: VBoxContainer
const GAME_DISPLAY_NAMES := {"dice": "拚骰", "rps": "猜拳", "ball": "玩球", "ttt": "井字棋", "blockade": "步步為營", "mastermind": "珠璣妙算"}
const GAME_AI_KEYS: Array[String] = ["ttt", "blockade", "mastermind"]
var _game_kind_order: Array[String] = ["dice", "rps", "ball", "ttt", "blockade", "mastermind"]
var _game_auto_checks: Dictionary = {}
var _game_accept_checks: Dictionary = {}
var _game_decline_checks: Dictionary = {}
var _game_ai_options: Dictionary = {}
var _nickname_line: LineEdit
var _ignore_props_check: CheckBox
var _ignore_furniture_check: CheckBox
var _no_follow_target_check: CheckBox
var _no_follow_source_check: CheckBox
var _no_topic_mention_check: CheckBox
var _reaction_list: VBoxContainer
var _reaction_window: ReactionDialogueWindow
var _reaction_boxes: Dictionary = {}   # reactions 陣列索引 → TextEdit
var _characters: Array[Dictionary] = []
var _props: Array[PropDef] = []
var _keyword_rows: KeywordRows
var _keyword_count: Label
var _user_keyword_rows: KeywordRows
var _topic_rows: TopicRows
var _topic_window: TopicLinesWindow
var _topic_button: Button
var _user_keyword_count: Label


func _ready() -> void:
	name = "交互行為"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 10)
	_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_flow)
	_build_toggle_card()
	_build_nickname_card()
	_build_action_card()
	_build_game_card()
	_build_reaction_dialogue_card()
	_build_keyword_card()
	_build_character_card()
	_build_pet_pref_card()
	_build_prop_card()
	_build_pref_card()


## 卡片標題列可以點開/收合(預設全部展開):標題本身是一顆扁平按鈕(含展開/收合箭頭),旁邊的 ⓘ 是獨立節點不受影響。
## 收合狀態只存在畫面上(VBoxContainer.visible),不寫進設定檔,每次重開管理視窗都是預設展開。
func _new_card(title_text: String, tip: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = AppSettings.ink(0.05)
	style.border_color = AppSettings.ink(0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10.0)
	card.add_theme_stylebox_override("panel", style)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	card.add_child(outer)

	var header := HBoxContainer.new()
	var toggle := Button.new()
	toggle.flat = true
	# 卡片標題跟圈圈i的說明文字都要用「查表翻譯後」的字串再組字面,不能先用 + 串起來再整串當查表 key
	# (串起來的字面幾乎不可能剛好等於 translations/ui_strings.csv 裡的任何一筆原文,一定翻不到——
	# 2026-09-30 使用者回報「交互行為」的收合卡片標題跟圈圈i沒翻譯到,根因就是這個)。
	var translated_title := TranslationServer.translate(title_text)
	toggle.text = "▾ " + translated_title
	toggle.clip_text = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(toggle)
	var info := InfoIcon.new()
	info.set_tip_parts([tip, WEB_HINT])
	header.add_child(info)
	outer.add_child(header)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	outer.add_child(box)
	toggle.pressed.connect(func() -> void:
		box.visible = not box.visible
		toggle.text = ("▾ " if box.visible else "▸ ") + translated_title)

	_flow.add_child(card)
	return box


func _build_action_card() -> void:
	var box := _new_card("事件對應的動作", "桌寵在各種事件下播放哪個動作:每一列選一個素材包裡有的動作,「(預設)」就是原本的動作。素材沒有選的那個動作時會退回原本的。")
	for slot: Array in InteractionRules.ACTION_SLOTS:
		var option := OptionButton.new()
		option.item_selected.connect(func(_i: int) -> void: _commit_actions())
		_action_options[str(slot[0])] = option
		box.add_child(ManagerUi.labeled(str(slot[1]), option))


func _build_nickname_card() -> void:
	var box := _new_card("對使用者的稱呼", "對話裡的 {user} 會用這裡填的稱呼(見語法字典)。可以填好幾個,用逗號分隔,桌寵每次要用時隨機挑一個。預設只有「使用者」這一筆;還是這個預設值的時候,桌寵會有比較高的機率主動開口問你要怎麼稱呼(問到答案就自動填進來)。")
	_nickname_line = ManagerUi.line_edit("使用者")
	# 這裡只有單一輸入框、沒有 labeled() 那樣的固定寬度標籤可以擠掉多餘空間,不特別限制寬度的話會被撐成卡片全寬
	# (跟其他卡片裡「標籤 + 輸入框」的窄版排版比起來明顯過長)。
	_nickname_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_nickname_line.custom_minimum_size.x = CARD_WIDTH - 140.0
	_nickname_line.text_submitted.connect(func(_t: String) -> void: _commit_nickname())
	_nickname_line.focus_exited.connect(_commit_nickname)
	box.add_child(_nickname_line)


func _commit_nickname() -> void:
	if _loading or _pet == null:
		return
	var cleaned: Array[String] = Pet.clean_user_nicknames(_nickname_line.text)
	_pet.user_nicknames = cleaned
	_nickname_line.text = ", ".join(PackedStringArray(_pet.user_nicknames))
	changed.emit()


## 整隻桌寵層級的總開關(跟下面「對某個道具的反應/喜好」「家具」那種一項一項設定不一樣,這裡是全部生效)。
func _build_toggle_card() -> void:
	var box := _new_card("整體交互開關", "整隻桌寵層級的總開關。「不主動」只是不會自己發起——使用者手動拖曳互動(拖道具給它、拖它去用家具),或積木明確指定的使用,都不受影響。")
	_ignore_props_check = CheckBox.new()
	_ignore_props_check.text = tr("不與道具交互(完全無視:不撿、不被摩擦、不成為候選、不被吸引)")
	_ignore_props_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ignore_props_check.toggled.connect(func(_pressed: bool) -> void: _commit_toggles())
	box.add_child(_ignore_props_check)
	_ignore_furniture_check = CheckBox.new()
	_ignore_furniture_check.text = tr("不主動使用家具(目前只有容器類的自主拿取行為;坐/躺類本來就沒有自主機制)")
	_ignore_furniture_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ignore_furniture_check.toggled.connect(func(_pressed: bool) -> void: _commit_toggles())
	box.add_child(_ignore_furniture_check)
	_no_follow_target_check = CheckBox.new()
	_no_follow_target_check.text = tr("不會被其他桌寵跟隨(別隻桌寵自己決定要跟著誰走時不會選到這隻)")
	_no_follow_target_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_follow_target_check.toggled.connect(func(_pressed: bool) -> void: _commit_toggles())
	box.add_child(_no_follow_target_check)
	_no_follow_source_check = CheckBox.new()
	_no_follow_source_check.text = tr("不跟隨其他桌寵(自己不會主動決定跟著誰走)")
	_no_follow_source_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_follow_source_check.toggled.connect(func(_pressed: bool) -> void: _commit_toggles())
	box.add_child(_no_follow_source_check)
	_no_topic_mention_check = CheckBox.new()
	_no_topic_mention_check.text = tr("不被其他桌寵的話題文本提及(其他桌寵閒聊時不會提到這隻;只對在場的桌寵生效)")
	_no_topic_mention_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_topic_mention_check.toggled.connect(func(_pressed: bool) -> void: _commit_toggles())
	box.add_child(_no_topic_mention_check)
	var follow_note := Label.new()
	follow_note.text = tr("固定模式底下這兩個「不跟隨」開關與「不主動使用家具」都會自動打開,靜止模式只自動打開這兩個「不跟隨」開關(拖去用家具還是會用);切回其他模式後會換回你在這裡自己設定的值。")
	follow_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	follow_note.custom_minimum_size.x = CARD_WIDTH
	follow_note.theme_type_variation = AppSettings.MUTED_LABEL
	box.add_child(follow_note)


func _commit_toggles() -> void:
	if _loading or _pet == null:
		return
	var rules := _rules()
	rules["ignore_props"] = _ignore_props_check.button_pressed
	rules["ignore_furniture"] = _ignore_furniture_check.button_pressed
	rules["no_follow_target"] = _no_follow_target_check.button_pressed
	rules["no_follow_source"] = _no_follow_source_check.button_pressed
	rules["no_topic_mention"] = _no_topic_mention_check.button_pressed
	_apply(rules)


func _build_character_card() -> void:
	var box := _new_card("對其他角色的反應", "選一個角色庫裡的角色(不含自己),寫下看到它出現在場上時要說的話。同一個角色可以新增好幾句,會照順序說。這裡只能新增純對話。")
	box.add_child(ManagerUi.syntax_row(self, "台詞能用的語法", "這裡的對話可以用氣泡樣式、數值、名字標記與單字池等既有語法。點右邊的「語法字典」查全部語法並插入/複製。"))
	_char_option = OptionButton.new()
	box.add_child(ManagerUi.labeled("遇見的角色", _char_option))
	_char_line = ManagerUi.line_edit("看到它時要說的話")
	_char_line.max_length = InteractionRules.MAX_TEXT
	_char_line.text_submitted.connect(func(_t: String) -> void: _on_add_character_pressed())
	box.add_child(ManagerUi.labeled("對話", _char_line))
	var add := ManagerUi.button("＋ 新增這句對話")
	add.pressed.connect(_on_add_character_pressed)
	box.add_child(add)
	_char_list = VBoxContainer.new()
	box.add_child(_char_list)


## 基本反應對話:列出這隻角色目前用的「反應」性格裡,基於預設反應情境(玩球、被邀請、休息等)已經有的對話內容。
## 只能改對話文字本身(跳一下、發抖這類寫死的動作效果不會被動到);要新增反應情境或調整動作,去「性格」分頁按「編輯性格…」。
func _build_reaction_dialogue_card() -> void:
	var box := _new_card(tr("對話事件"), "列出這隻角色目前用的性格,在「玩球」「被邀請對戰」「休息」等既有反應情境裡已經有的對話內容。這裡只能改「對話文字」本身,跳一下、發抖這類動作不會被動到,也不能新增新的反應情境;要做這些,請到「性格」分頁按「編輯性格…」。")
	box.add_child(ManagerUi.heading("事件管理"))
	var event_manager_button := ManagerUi.button("事件管理(查看/暫時停用/移除目前生效的事件)")
	event_manager_button.tooltip_text = tr("查看這隻桌寵目前生效的所有事件(閒聊、反應、計時器…),可以暫時停用或移除。跟測試者面板的「事件管理」是同一個視窗,不會寫進檔案、只影響這次執行——性格/交互行為規則帶來的事件下次重新套用或按「儲存」就會恢復,自訂的要重新匯入積木檔才會恢復。")
	event_manager_button.pressed.connect(func() -> void: ManagerUi.open_event_manager_window(self, _pet))
	box.add_child(event_manager_button)
	box.add_child(HSeparator.new())
	# 基本反應對話:標題 + 圈圈i(格式同事件管理),台詞清單收進獨立視窗(內容長,放在這一頁會拖慢讀取)。
	box.add_child(ManagerUi.heading_with_info(tr("基本反應對話"), tr("列出這隻角色目前用的性格,在「玩球」「被邀請對戰」「休息」等既有反應情境裡已經有的對話內容。這裡只能改「對話文字」本身,跳一下、發抖這類動作不會被動到,也不能新增新的反應情境;要做這些,請到「性格」分頁按「編輯性格…」。")))
	var reactions_button := ManagerUi.button(tr("基本反應對話…"))
	reactions_button.pressed.connect(_open_reaction_window)
	box.add_child(reactions_button)
	box.add_child(HSeparator.new())
	# 話題文本:標題 + 圈圈i(說明含「好感度達到 30 才會調用」),列表同樣收進獨立視窗。
	box.add_child(ManagerUi.heading_with_info(tr("話題文本"), tr("閒聊時會說的句子。需要該桌寵的使用者好感度達到 30 才會開始調用這些話題文本。句中用 {tag:愛好} 引用同標籤的詞、{liked} / {disliked} 引用場上喜歡/討厭的對象;句中引用的標籤沒有詞、或沒有對應的對象時,這句就不會被說。")))
	box.add_child(_hint(tr("閒聊時說的句子(好感度 ≥ 30 才會開始說)")))
	_topic_button = ManagerUi.button("")
	_topic_button.pressed.connect(_open_topic_window)
	box.add_child(_topic_button)
	_update_topic_button()


## 打開基本反應對話視窗並重新載入目前桌寵的台詞(每次打開都重新載入,保證跟桌寵一致)。
func _open_reaction_window() -> void:
	if _pet == null:
		return
	_reaction_window = ManagerUi.open_reaction_dialogue_window(self)
	_reaction_list = _reaction_window.list
	_reload_reaction_dialogue()


func _reload_reaction_dialogue() -> void:
	# 視窗沒開過(或還沒打開)就不用載入,等打開時再載入。
	if _reaction_list == null or _reaction_window == null or not _reaction_window.visible:
		return
	for child in _reaction_list.get_children():
		child.queue_free()
	_reaction_boxes.clear()
	if _pet == null:
		return
	var id := PersonalityApplier.choice_of(_pet, "reactions")
	if id == "":
		_reaction_list.add_child(_muted_label("這隻角色目前沒有套用「反應」性格,沒有預設反應對話可以改。"))
		return
	var personality := PersonalityApplier.personality_of(_pet, id)
	var entries: Array = personality.get("reactions", [])
	var any := false
	for i in entries.size():
		var entry: Dictionary = entries[i]
		if (entry.get("say", []) as Array).is_empty():
			continue
		any = true
		_add_reaction_row(i, entry)
	if not any:
		_reaction_list.add_child(_muted_label(tr("「%s」目前沒有帶對話文字的預設反應可以改。") % str(personality.get("name", id))))


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = AppSettings.MUTED_LABEL
	return label


func _add_reaction_row(index: int, entry: Dictionary) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.add_child(_muted_label(PersonalityFile.trigger_label(str(entry.get("on", "")))))
	var lines_edit := TextEdit.new()
	lines_edit.custom_minimum_size.y = 56.0
	lines_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	lines_edit.placeholder_text = tr("一行一句備選台詞(每次隨機挑一句說)")
	lines_edit.text = "\n".join(PackedStringArray(entry.get("say", [])))
	lines_edit.focus_exited.connect(func() -> void: _commit_reaction_dialogue(index))
	row.add_child(lines_edit)
	_reaction_list.add_child(row)
	_reaction_boxes[index] = lines_edit


## 把某一條反應的對話文字(索引 index,對應 reactions 陣列)存回這隻角色自己的性格副本;action/hop/shiver 等其他欄位原樣保留。
## 台詞跟目前生效的性格版本一樣(或清單是空的)就回傳 true。純讀取,不會複製性格。
func _reaction_unchanged(index: int, id: String) -> bool:
	var source: Array = PersonalityApplier.personality_of(_pet, id).get("reactions", [])
	if index < 0 or index >= source.size() or not _reaction_boxes.has(index):
		return true
	var lines: Array[String] = []
	for line: String in (_reaction_boxes[index] as TextEdit).text.split("
"):
		if line.strip_edges() != "" and lines.size() < PersonalityFile.MAX_LINES_PER_ENTRY:
			lines.append(line.strip_edges().left(PersonalityFile.MAX_LINE_CHARS))
	var old_say: Array = (source[index] as Dictionary).get("say", [])
	if lines.is_empty():
		# 不能把整條反應清成沒有台詞:退回原本的內容(不改性格、不發 changed)。
		(_reaction_boxes[index] as TextEdit).text = "
".join(PackedStringArray(old_say))
		return true
	return "
".join(PackedStringArray(old_say)) == "
".join(PackedStringArray(lines))


func _commit_reaction_dialogue(index: int) -> void:
	if _loading or _pet == null or not _reaction_boxes.has(index):
		return
	var id := PersonalityApplier.choice_of(_pet, "reactions")
	if id == "":
		return
	# 台詞沒真的改就不動(點進去又離開不算改動:不複製性格、不發 changed)。
	if _reaction_unchanged(index, id):
		return
	PersonalityApplier.ensure_own(_pet, id)
	var personality: Dictionary = PersonalityApplier.personality_of(_pet, id).duplicate(true)
	var entries: Array = (personality.get("reactions", []) as Array).duplicate(true)
	if index < 0 or index >= entries.size():
		return
	var edit: TextEdit = _reaction_boxes[index]
	var lines: Array[String] = []
	for line: String in edit.text.split("\n"):
		if line.strip_edges() != "" and lines.size() < PersonalityFile.MAX_LINES_PER_ENTRY:
			lines.append(line.strip_edges().left(PersonalityFile.MAX_LINE_CHARS))
	if lines.is_empty():
		# 這裡只能改對話文字,不能把整條反應清空成沒有台詞;退回原本的內容。
		edit.text = "\n".join(PackedStringArray((entries[index] as Dictionary).get("say", [])))
		return
	var entry: Dictionary = (entries[index] as Dictionary).duplicate(true)
	entry["say"] = lines
	entries[index] = entry
	personality["reactions"] = entries
	var checked := PersonalityFile.validate(PersonalityFile.to_file_data(personality))
	if not bool(checked["ok"]):
		return
	PersonalityApplier.set_own(_pet, id, PersonalityFile.to_file_data(checked["personality"]))
	edit.text = "\n".join(PackedStringArray(lines))
	changed.emit()


func _build_prop_card() -> void:
	var box := _new_card("對道具的反應", "選一個道具管理裡的道具與時機,設定要說的話(選填)和要做的動作(選填)。動作可以只做一次,也可以持續到道具用完或離開判定。有設定時就不再播道具的預設動作。")
	_prop_option = OptionButton.new()
	box.add_child(ManagerUi.labeled("道具", _prop_option))
	_prop_kind_option = OptionButton.new()
	for kind: String in InteractionRules.PROP_KINDS:
		_prop_kind_option.add_item(str(InteractionRules.PROP_KINDS[kind]))
		_prop_kind_option.set_item_metadata(_prop_kind_option.item_count - 1, kind)
	box.add_child(ManagerUi.labeled("時機", _prop_kind_option))
	_prop_line = ManagerUi.line_edit("要說的話(選填)")
	_prop_line.max_length = InteractionRules.MAX_TEXT
	box.add_child(ManagerUi.labeled("對話", _prop_line))
	_prop_action_option = OptionButton.new()
	box.add_child(ManagerUi.labeled("動作", _prop_action_option))
	_prop_persist_option = OptionButton.new()
	_prop_persist_option.add_item(tr("只做一次"))
	_prop_persist_option.add_item(tr("持續到道具用完 / 離開判定"))
	box.add_child(ManagerUi.labeled("動作進行方式", _prop_persist_option))
	var add := ManagerUi.button("＋ 新增這條反應")
	add.pressed.connect(_on_add_prop_pressed)
	box.add_child(add)
	_prop_list = VBoxContainer.new()
	box.add_child(_prop_list)


func _build_pref_card() -> void:
	var box := _new_card("對道具的好惡", "每個道具選「喜歡」、「不喜歡」或「不與此道具交互」(完全無視:不撿、不被摩擦、不成為候選、不被吸引)。喜歡的道具掉在場上,桌寵會自己走過去撿,撿到心情變好;不喜歡的不會自己撿(拖著遞給它還是會收)。道具資料找不到(被刪掉或搬走)的會變成灰色,可以按「重新連結」改指向現有的另一個道具。")
	_pref_list = VBoxContainer.new()
	box.add_child(_pref_list)


## 對其他角色的好惡(2026-10-04 使用者要求,簡化成單一欄位省空間;2026-10-05 卡片用詞從「桌寵」改成
## 「角色」,因為這個設定是依辨識代號/角色身分存的,不是依畫面上哪一隻實體,跟 project-terminology 的
## 桌寵/角色分工一致):每一列一個對象(「全部角色」或角色庫裡的某個)+ 一個好惡程度下拉選單(普通~超級
## 喜歡/不喜歡,預設「普通」= 跟沒有這個功能時行為一樣)。「全部角色」那一列是沒被個別指定的其他角色套用
## 的預設等級;個別指定某個角色會蓋過「全部角色」那一列。
func _build_pet_pref_card() -> void:
	var box := _new_card("對其他角色的好惡", "設定對某個角色、或對全部角色的好惡程度,預設「普通」= 跟沒有這個功能時一樣,沒有額外的好惡表現。目前會影響:主動跟隨的候選與機率(討厭的完全不會主動跟著走,喜歡的機率提高、也更容易被選中);閒置時自己發起對戰要不要挑這隻邀請(討厭的機率降低但不是完全不邀,喜歡的機率提高;「跟場上所有桌寵」這種廣播式邀請不受影響);被邀請對戰時答不答應的機率(喜歡的更容易答應,討厭的更容易拒絕,一樣包括廣播式邀請被邀請的那一端)。目前只能在這裡手動調整,不會自動隨時間漲跌;之後計畫補一顆積木讓你自己設計好惡隨什麼條件變化。")
	_pet_pref_list = VBoxContainer.new()
	box.add_child(_pet_pref_list)


## 「遊戲與對戰」卡片:井字棋/步步為營/珠璣妙算各自的 AI 強度,拚骰/猜拳/玩球/井字棋/步步為營/珠璣妙算
## 各自的「自動邀請」/「一律接受」/「一律拒絕」。這幾個欄位是 Pet 本體的 plain var(game_auto_invite/
## game_force_accept/game_force_decline 字典、xxx_ai_level),不是 interaction_rules 的一部分,所以不走
## _rules()/_apply() 那套,改了直接寫回 _pet 再 emit changed(),跟其他卡片一樣靠管理視窗的「儲存」按鈕落檔。
func _build_game_card() -> void:
	var box := _new_card("遊戲與對戰", "井字棋/步步為營/珠璣妙算各自的 AI 強度(數字愈小愈容易犯錯/隨便選,愈大愈接近一定選目前看起來最好的那個)。每種遊戲各自的「自動邀請」是閒置時自己主動邀別人玩這個;「一律接受」/「一律拒絕」是被別人邀請玩這個時的固定反應,兩個都不勾 = 照原本的機率/其他條件決定。跟右鍵選單「對戰與遊戲」裡同名的欄位是同一份資料,改這裡或改選單都一樣。珠璣妙算的題型(3/4 格密碼)在右鍵選單「珠璣妙算 → 題型」調,這張卡片不重複放。")
	for kind: String in _game_kind_order:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		if GAME_AI_KEYS.has(kind):
			var ai_option := OptionButton.new()
			for lv: int in GameAiLevel.CHOICES:
				ai_option.add_item(tr(str(GameAiLevel.NAMES[lv])))
			ai_option.item_selected.connect(func(_i: int) -> void: _commit_game_prefs())
			_game_ai_options[kind] = ai_option
			row.add_child(ManagerUi.labeled("%s · %s" % [tr(str(GAME_DISPLAY_NAMES[kind])), tr("AI 強度")], ai_option))
		else:
			var name_label := Label.new()
			name_label.text = tr(str(GAME_DISPLAY_NAMES[kind]))
			row.add_child(name_label)
		var checks := HBoxContainer.new()
		checks.add_theme_constant_override("separation", 10)
		var auto_check := CheckBox.new()
		auto_check.text = tr("自動邀請")
		auto_check.toggled.connect(func(_p: bool) -> void: _commit_game_prefs())
		_game_auto_checks[kind] = auto_check
		checks.add_child(auto_check)
		var accept_check := CheckBox.new()
		accept_check.text = tr("一律接受")
		_game_accept_checks[kind] = accept_check
		var decline_check := CheckBox.new()
		decline_check.text = tr("一律拒絕")
		_game_decline_checks[kind] = decline_check
		accept_check.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				decline_check.button_pressed = false
			_commit_game_prefs())
		decline_check.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				accept_check.button_pressed = false
			_commit_game_prefs())
		checks.add_child(accept_check)
		checks.add_child(decline_check)
		row.add_child(checks)
		box.add_child(row)
		if kind != _game_kind_order[-1]:
			box.add_child(HSeparator.new())


func _ai_field_name(kind: String) -> String:
	return "%s_ai_level" % kind


func _reload_game_prefs() -> void:
	for kind: String in _game_kind_order:
		(_game_auto_checks[kind] as CheckBox).button_pressed = _pet.game_auto_invite_enabled(kind)
		(_game_accept_checks[kind] as CheckBox).button_pressed = bool(_pet.game_force_accept.get(kind, false))
		(_game_decline_checks[kind] as CheckBox).button_pressed = bool(_pet.game_force_decline.get(kind, false))
	for kind: String in GAME_AI_KEYS:
		var level := int(_pet.get(_ai_field_name(kind)))
		(_game_ai_options[kind] as OptionButton).select(maxi(GameAiLevel.CHOICES.find(level), 0))


func _commit_game_prefs() -> void:
	if _loading or _pet == null:
		return
	for kind: String in _game_kind_order:
		_pet.game_auto_invite[kind] = (_game_auto_checks[kind] as CheckBox).button_pressed
		_pet.game_force_accept[kind] = (_game_accept_checks[kind] as CheckBox).button_pressed
		_pet.game_force_decline[kind] = (_game_decline_checks[kind] as CheckBox).button_pressed
	for kind: String in GAME_AI_KEYS:
		var option: OptionButton = _game_ai_options[kind]
		_pet.set(_ai_field_name(kind), GameAiLevel.CHOICES[option.selected])
	changed.emit()


func set_pet(pet: Node) -> void:
	_pet = pet
	_reload()


## 從桌寵目前的設定重新填所有控制項(不發變更)。
func _reload() -> void:
	if _pet == null or _flow == null:
		return
	_loading = true
	_nickname_line.text = ", ".join(PackedStringArray(_pet.user_nicknames))
	var names: Array[String] = _pet.action_names()
	var rules: Dictionary = _pet.interaction_rules
	_ignore_props_check.button_pressed = bool(rules.get("ignore_props", false))
	_no_topic_mention_check.button_pressed = bool(rules.get("no_topic_mention", false))
	_ignore_furniture_check.button_pressed = bool(rules.get("ignore_furniture", false))
	_no_follow_target_check.button_pressed = bool(rules.get("no_follow_target", false))
	_no_follow_source_check.button_pressed = bool(rules.get("no_follow_source", false))
	for slot: String in _action_options:
		var option: OptionButton = _action_options[slot]
		option.clear()
		option.add_item(tr(DEFAULT_LABEL) + " " + slot)
		var current := str((rules["actions"] as Dictionary).get(slot, ""))
		var selected := 0
		var listed: Array[String] = names.duplicate()
		if current != "" and not listed.has(current):
			listed.append(current)
		for action_name in listed:
			option.add_item(action_name)
			if action_name == current:
				selected = option.item_count - 1
		option.select(selected)
	_characters.clear()
	_char_option.clear()
	for folder in SpriteLibrary.list_packs():
		var tag := SpriteLibrary.tag_of(folder)
		if tag == str(_pet.recognition_tag):
			continue
		var display := str(SpriteLibrary._read_manifest(folder).get("name", folder.get_file()))
		_characters.append({"tag": tag, "name": display})
		_char_option.add_item("%s(%s)" % [display, tag] if display != tag else tag)
	_props = PropLibrary.list()
	_prop_option.clear()
	for def in _props:
		_prop_option.add_item(def.display_name)
	_prop_action_option.clear()
	_prop_action_option.add_item(tr("(不做動作)"))
	for action_name in names:
		_prop_action_option.add_item(action_name)
	_reload_game_prefs()
	_loading = false
	_rebuild_lists()
	_reload_reaction_dialogue()
	_load_keywords()


## 關鍵詞庫小板塊:這隻角色會想或提及的事物,一行一個。台詞裡的 {keyword}(隨機一個)與 {kw:1}~{kw:9}(這個事件洗牌後的第幾個,彼此不同)會用到它。
func _build_keyword_card() -> void:
	var side := _new_card("關鍵詞庫", tr("簡單地告訴桌寵「你會想到、提到哪些事物」,一行一個(最多 %d 個、每個最多 %d 字)。台詞裡寫 {keyword} 就會隨機換成其中一個,例如「%s似乎在想關於 {keyword} 的事情」「你知道關於 {keyword} 的事嗎?」「oO(有點想念 {keyword} 呀…)」;{kw:1}、{kw:2}… 是同一個事件裡各不相同的幾個,適合做「猜猜我現在最想要什麼?」這種四個選項都是答案的題目。庫是空的就用預設詞(可以寫 {keyword|某件事} 自訂)。改了立刻生效,記得按「儲存」。") % [PetText.MAX_KEYWORDS, PetText.MAX_KEYWORD_LENGTH, "{self}"])
	side.add_child(ManagerUi.syntax_row(self, "台詞裡怎麼用:{keyword}、{kw:1}", "{keyword} = 隨機一個;{keyword|某件事} = 庫是空的時顯示「某件事」;{kw:1}~{kw:9} = 這個事件洗牌後的第 N 個(1、2、3、4 各不相同)。點右邊的「語法字典」看全部語法。", false))
	side.add_child(_hint("▍桌寵有興趣的關鍵詞(桌寵向你學到的新知識也會記在這裡)"))
	_keyword_rows = KeywordRows.new()
	_keyword_rows.changed.connect(_on_keywords_edited)
	side.add_child(_keyword_rows)
	var row := HBoxContainer.new()
	_keyword_count = Label.new()
	_keyword_count.theme_type_variation = AppSettings.MUTED_LABEL
	_keyword_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_keyword_count)
	var suggest := ManagerUi.button("加入建議詞")
	suggest.tooltip_text = tr("把一組常見的話題(晚餐、星星、天氣…)加進來,已經有的不會重複;不喜歡的自己刪掉。")
	suggest.pressed.connect(_add_suggested_keywords)
	row.add_child(suggest)
	var clear := ManagerUi.button("清空")
	clear.pressed.connect(func() -> void:
		_keyword_rows.set_data(PackedStringArray(), {})
		_on_keywords_edited())
	row.add_child(clear)
	side.add_child(row)
	# 第二份:使用者有興趣的關鍵詞。台詞裡用 {keyword:user} / {kw:user:1};桌寵「想更了解你」問到的也會記在這裡。
	side.add_child(_hint("▍使用者有興趣的關鍵詞(桌寵想更了解你時問到的會記在這裡;台詞裡用 {keyword:user}、{kw:user:1})"))
	_user_keyword_rows = KeywordRows.new()
	_user_keyword_rows.changed.connect(_on_user_keywords_edited)
	side.add_child(_user_keyword_rows)
	var user_row := HBoxContainer.new()
	_user_keyword_count = Label.new()
	_user_keyword_count.theme_type_variation = AppSettings.MUTED_LABEL
	_user_keyword_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_row.add_child(_user_keyword_count)
	var user_clear := ManagerUi.button("清空")
	user_clear.pressed.connect(func() -> void:
		_user_keyword_rows.set_data(PackedStringArray(), {})
		_on_user_keywords_edited())
	user_row.add_child(user_clear)
	side.add_child(user_row)


const SUGGESTED_KEYWORDS: Array[String] = ["晚餐", "星星", "天氣", "下雨天", "零食", "午睡", "夕陽", "音樂", "冒險", "遠方的朋友"]


func _add_suggested_keywords() -> void:
	var data: Dictionary = _keyword_rows.get_data()
	var merged: PackedStringArray = data["words"]
	var tags: Dictionary = data["tags"]
	for word in SUGGESTED_KEYWORDS:
		if not merged.has(word) and merged.size() < PetText.MAX_KEYWORDS:
			merged.append(word)
	_keyword_rows.set_data(merged, tags)
	_on_keywords_edited()


## 使用者改了關鍵詞:整理後寫到這隻桌寵身上(輸入框的文字不重寫,免得打字時游標亂跳;超過上限或重複的下次載入才會被整理掉)。
## 使用者改了關鍵詞(文字或標籤):整理後寫到這隻桌寵身上。
func _on_keywords_edited() -> void:
	if _loading or _pet == null:
		return
	var data: Dictionary = _keyword_rows.get_data()
	_pet.keywords = data["words"]
	_pet.keyword_tags = data["tags"]
	_update_keyword_count()
	changed.emit()


## 使用者有興趣的關鍵詞被編輯:整理後寫到桌寵身上。
## 使用者有興趣的關鍵詞被編輯:整理後寫到桌寵身上。
func _on_user_keywords_edited() -> void:
	if _loading or _pet == null:
		return
	var data: Dictionary = _user_keyword_rows.get_data()
	_pet.user_keywords = data["words"]
	_pet.user_keyword_tags = data["tags"]
	_update_keyword_count()
	changed.emit()


func _update_keyword_count() -> void:
	if _pet == null:
		return
	_keyword_count.text = tr("目前 %d / %d 個關鍵詞") % [_pet.keywords.size(), PetText.MAX_KEYWORDS]
	if _user_keyword_count != null:
		_user_keyword_count.text = tr("目前 %d / %d 個關鍵詞") % [_pet.user_keywords.size(), PetText.MAX_KEYWORDS]


func _load_keywords() -> void:
	if _pet == null or _keyword_rows == null:
		return
	var was_loading := _loading
	_loading = true
	_keyword_rows.set_data(_pet.keywords, _pet.keyword_tags)
	if _user_keyword_rows != null:
		_user_keyword_rows.set_data(_pet.user_keywords, _pet.user_keyword_tags)
	_update_topic_button()
	if _topic_window != null and _topic_window.visible:
		_topic_rows.set_data(_pet.topic_lines_effective())
	_loading = was_loading
	_update_keyword_count()


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	# 見 ManagerUi.hint_row() 旁的說明:換行 Label 沒給 custom_minimum_size.x 會被估出離譜的高度。
	label.custom_minimum_size.x = 220.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = AppSettings.MUTED_LABEL
	return label

func _rules() -> Dictionary:
	return (_pet.interaction_rules as Dictionary).duplicate(true)


func _apply(rules: Dictionary) -> void:
	_pet.set_interaction_rules(rules)
	changed.emit()
	_rebuild_lists()


func _commit_actions() -> void:
	if _loading or _pet == null:
		return
	var rules := _rules()
	for slot: String in _action_options:
		var option: OptionButton = _action_options[slot]
		if option.selected <= 0:
			(rules["actions"] as Dictionary).erase(slot)
		else:
			rules["actions"][slot] = option.get_item_text(option.selected)
	_apply(rules)


## 新增一句「看到某個角色時說的話」(給按鈕與測試用)。回傳錯誤文字,空字串 = 成功。
func add_character_line(tag: String, display_name: String, text: String) -> String:
	if _pet == null:
		return "沒有選桌寵"
	if text.strip_edges() == "":
		return "對話不能是空的"
	if tag == "" or tag == str(_pet.recognition_tag):
		return "要選別的角色(不能是自己)"
	var rules := _rules()
	var found := false
	for entry: Dictionary in rules["characters"]:
		if entry["tag"] == tag:
			(entry["lines"] as Array).append(text)
			found = true
	if not found:
		(rules["characters"] as Array).append({"tag": tag, "name": display_name, "lines": [text]})
	_apply(rules)
	return ""


func remove_character_line(tag: String, index: int) -> void:
	var rules := _rules()
	for entry: Dictionary in rules["characters"]:
		if entry["tag"] == tag and index >= 0 and index < (entry["lines"] as Array).size():
			(entry["lines"] as Array).remove_at(index)
	_apply(rules)


## 新增一條道具反應。回傳錯誤文字,空字串 = 成功。
func add_prop_rule(prop_name: String, kind: String, line: String, action: String, persist: bool) -> String:
	if _pet == null:
		return "沒有選桌寵"
	if prop_name == "":
		return "還沒有道具:先到道具管理新增"
	if line.strip_edges() == "" and action == "":
		return "對話和動作至少要設定一個"
	var rules := _rules()
	(rules["props"] as Array).append({"prop": prop_name, "kind": kind, "line": line.strip_edges(), "action": action, "persist": persist})
	_apply(rules)
	return ""


func remove_prop_rule(index: int) -> void:
	var rules := _rules()
	if index >= 0 and index < (rules["props"] as Array).size():
		(rules["props"] as Array).remove_at(index)
	_apply(rules)


func _on_add_character_pressed() -> void:
	var picked := _char_option.selected
	if picked < 0 or picked >= _characters.size():
		message.emit("角色庫裡沒有別的角色可以選。")
		return
	var error := add_character_line(str(_characters[picked]["tag"]), str(_characters[picked]["name"]), _char_line.text)
	if error != "":
		message.emit(error)
		return
	_char_line.text = ""


func _on_add_prop_pressed() -> void:
	var picked := _prop_option.selected
	var prop_name := _props[picked].display_name if picked >= 0 and picked < _props.size() else ""
	var action := "" if _prop_action_option.selected <= 0 else _prop_action_option.get_item_text(_prop_action_option.selected)
	var error := add_prop_rule(prop_name, str(_prop_kind_option.get_item_metadata(_prop_kind_option.selected)), _prop_line.text, action, _prop_persist_option.selected == 1)
	if error != "":
		message.emit(error)
		return
	_prop_line.text = ""


func _rebuild_lists() -> void:
	if _char_list == null or _pet == null:
		return
	for child in _char_list.get_children():
		child.queue_free()
	for child in _prop_list.get_children():
		child.queue_free()
	var rules: Dictionary = _pet.interaction_rules
	for entry: Dictionary in rules["characters"]:
		for i in (entry["lines"] as Array).size():
			var tag := str(entry["tag"])
			var index := i
			_char_list.add_child(_row(tr("遇見 %s:「%s」") % [entry["name"], entry["lines"][i]], func() -> void: remove_character_line(tag, index)))
	_rebuild_prefs(rules)
	_rebuild_pet_prefs(rules)
	var rule_index := 0
	for rule: Dictionary in rules["props"]:
		var index := rule_index
		var parts: Array[String] = []
		if str(rule["line"]) != "":
			parts.append(tr("說「%s」") % rule["line"])
		if str(rule["action"]) != "":
			parts.append(tr("做 %s(%s)") % [rule["action"], tr("持續") if bool(rule["persist"]) else tr("一次")])
		_prop_list.add_child(_row("%s · %s:%s" % [rule["prop"], InteractionRules.PROP_KINDS[rule["kind"]], "、".join(parts)], func() -> void: remove_prop_rule(index)))
		rule_index += 1


## 設定對某個道具的喜好(pref = "like" / "dislike" / "" = 沒特別)。回傳錯誤文字,空字串 = 成功。
func set_preference(prop_id: String, prop_name: String, pref: String) -> String:
	if _pet == null:
		return "沒有選桌寵"
	if prop_id == "":
		return "找不到這個道具"
	var rules := _rules()
	var prefs: Array = rules["prefs"]
	for i in range(prefs.size() - 1, -1, -1):
		if prefs[i]["id"] == prop_id:
			prefs.remove_at(i)
	if pref != "":
		prefs.append({"id": prop_id, "name": prop_name, "pref": pref})
	_apply(rules)
	return ""


## 把找不到資料的喜好項目改指向現有的另一個道具(喜好保留)。回傳錯誤文字,空字串 = 成功。
func relink_preference(old_id: String, new_def: PropDef) -> String:
	if _pet == null or new_def == null:
		return "沒有選桌寵或道具"
	var rules := _rules()
	var found := false
	for entry: Dictionary in rules["prefs"]:
		if entry["id"] == new_def.id and entry["id"] != old_id:
			return "那個道具已經有設定喜好了"
	for entry: Dictionary in rules["prefs"]:
		if entry["id"] == old_id:
			entry["id"] = new_def.id
			entry["name"] = new_def.display_name
			found = true
	if not found:
		return "找不到要重新連結的項目"
	_apply(rules)
	return ""


func _rebuild_prefs(rules: Dictionary) -> void:
	for child in _pref_list.get_children():
		child.queue_free()
	var known := {}
	for def in _props:
		known[def.id] = true
		var current := InteractionRules.preference_of(rules, def.id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = def.display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var option := OptionButton.new()
		option.add_item(tr("沒特別"))
		option.add_item(tr("喜歡"))
		option.add_item(tr("不喜歡"))
		option.add_item(tr("不與此道具交互"))
		option.select(["", "like", "dislike", "ignore"].find(current))
		var prop_id := def.id
		var prop_name := def.display_name
		option.item_selected.connect(func(index: int) -> void: set_preference(prop_id, prop_name, ["", "like", "dislike", "ignore"][index]))
		row.add_child(option)
		_pref_list.add_child(row)
	for entry: Dictionary in rules["prefs"]:
		if known.has(entry["id"]):
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = tr("%s(%s,找不到道具資料)") % [entry["name"], {"like": tr("喜歡"), "dislike": tr("不喜歡")}.get(entry["pref"], tr("不與此道具交互"))]
		label.theme_type_variation = AppSettings.MUTED_LABEL
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var relink := ManagerUi.button("重新連結…")
		var old_id := str(entry["id"])
		relink.pressed.connect(func() -> void: _open_relink_menu(relink, old_id))
		row.add_child(relink)
		var remove := ManagerUi.button("✕")
		remove.tooltip_text = tr("移除這一項")
		remove.pressed.connect(func() -> void: set_preference(old_id, "", ""))
		row.add_child(remove)
		_pref_list.add_child(row)


## 設定對某隻桌寵(或 InteractionRules.ALL_PETS_TARGET)的好惡等級;0 = 移除這一項(退回普通)。
## 直接呼叫 Pet.set_pet_affinity(),跟積木「改變對某桌寵的好惡」背後是同一個函式,不是兩套邏輯。
func set_pet_pref(target: String, display_name: String, level: int) -> void:
	if _pet == null:
		return
	_pet.set_pet_affinity(target, level, display_name)
	changed.emit()
	_rebuild_lists()


func _add_pet_pref_row(target: String, display_name: String, rules: Dictionary) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = display_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	# 2026-10-06:桌寵對這隻桌寵的好感度(參數,不影響好惡等級)。預設列(全部角色)沒有單一對象,不顯示。
	if target != InteractionRules.ALL_PETS_TARGET and _pet != null:
		var favor := Label.new()
		favor.text = tr("當前好感度:%d") % int(roundf(_pet.favor_of(target)))
		favor.theme_type_variation = AppSettings.MUTED_LABEL
		favor.tooltip_text = tr("這隻桌寵對這隻桌寵的好感度(-500~1000)。只是提供的參數,不會自動影響好惡等級;要不要用它做事件,由你自己的積木決定。")
		row.add_child(favor)
	var option := OptionButton.new()
	for level: int in InteractionRules.PET_PREF_LEVELS:
		option.add_item(tr(str(InteractionRules.PET_PREF_LEVEL_NAMES[level])))
	option.select(InteractionRules.PET_PREF_LEVELS.find(InteractionRules.direct_pet_pref_level(rules, target)))
	option.item_selected.connect(func(index: int) -> void: set_pet_pref(target, display_name, InteractionRules.PET_PREF_LEVELS[index]))
	row.add_child(option)
	# 2026-10-06:「不提及此桌寵」(自己的話題文本不會提到它;好惡等級不受影響)。預設列沒有單一對象,不顯示。
	if target != InteractionRules.ALL_PETS_TARGET and _pet != null:
		# 只顯示 🔇 圖示,說明寫在 hover 裡(折行)。
		var no_mention := ManagerUi.button("🔇")
		no_mention.toggle_mode = true
		no_mention.button_pressed = _pet.no_mention_of(target)
		no_mention.tooltip_text = InfoIcon.wrap_text(tr("不提及此桌寵:其他桌寵閒聊時,話題文本不會提到這隻(只對在場的桌寵生效)。好惡等級不受影響。"), InfoIcon.TIP_WIDTH)
		no_mention.toggled.connect(func(pressed: bool) -> void:
			_pet.set_pet_no_mention(target, pressed)
			changed.emit())
		row.add_child(no_mention)
	_pet_pref_list.add_child(row)


func _rebuild_pet_prefs(rules: Dictionary) -> void:
	if _pet_pref_list == null or _pet == null:
		return
	for child in _pet_pref_list.get_children():
		child.queue_free()
	var known := {}
	known[InteractionRules.ALL_PETS_TARGET] = true
	_add_pet_pref_row(InteractionRules.ALL_PETS_TARGET, tr("全部角色(預設)"), rules)
	for character: Dictionary in _characters:
		var tag := str(character["tag"])
		known[tag] = true
		_add_pet_pref_row(tag, str(character["name"]), rules)
	for entry: Dictionary in rules.get("pet_prefs", []):
		var target := str(entry.get("target", ""))
		if known.has(target):
			continue
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = tr("%s(%s,找不到這隻桌寵的角色資料)") % [entry.get("name", target), InteractionRules.PET_PREF_LEVEL_NAMES.get(int(entry.get("level", 0)), "")]
		label.theme_type_variation = AppSettings.MUTED_LABEL
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var remove := ManagerUi.button("✕")
		remove.tooltip_text = tr("移除這一項")
		remove.pressed.connect(func() -> void: set_pet_pref(target, "", 0))
		row.add_child(remove)
		_pet_pref_list.add_child(row)


func _open_relink_menu(anchor: Control, old_id: String) -> void:
	var menu := PopupMenu.new()
	var candidates: Array[PropDef] = []
	var taken := {}
	for entry: Dictionary in (_pet.interaction_rules as Dictionary)["prefs"]:
		taken[entry["id"]] = true
	for def in _props:
		if not taken.has(def.id):
			candidates.append(def)
			menu.add_item(def.display_name)
	if candidates.is_empty():
		menu.add_item(tr("(沒有可以連結的道具)"))
		menu.set_item_disabled(0, true)
	menu.index_pressed.connect(func(index: int) -> void:
		relink_preference(old_id, candidates[index])
		menu.queue_free())
	menu.close_requested.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(anchor.get_screen_position()) + Vector2i(0, int(anchor.size.y)), Vector2i(180, 0)))


func _row(text: String, on_remove: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = CARD_WIDTH - 90.0
	row.add_child(label)
	var remove := ManagerUi.button("✕")
	remove.tooltip_text = tr("刪除這一條")
	remove.pressed.connect(on_remove)
	row.add_child(remove)
	return row


## 按鈕文字:話題文本的句數。
func _update_topic_button() -> void:
	if _topic_button == null:
		return
	var count: int = _pet.topic_lines_effective().size() if _pet != null else 0
	_topic_button.text = tr("話題文本…(%d 句)") % count


## 打開話題文本視窗並載入目前桌寵的話題文本(每次打開都重新載入,保證跟桌寵一致)。
func _open_topic_window() -> void:
	if _pet == null:
		return
	_topic_window = ManagerUi.open_topic_lines_window(self)
	_topic_rows = _topic_window.rows
	if not _topic_window.changed.is_connected(_on_topics_edited):
		_topic_window.changed.connect(_on_topics_edited)
	_loading = true
	_topic_rows.set_data(_pet.topic_lines_effective())
	_loading = false
	_update_topic_button()


## 話題文本被編輯:整理後寫到桌寵身上(見 TopicRows.get_data)。
func _on_topics_edited() -> void:
	if _loading or _pet == null:
		return
	_pet.set_topic_custom(_topic_rows.get_data())
	changed.emit()
