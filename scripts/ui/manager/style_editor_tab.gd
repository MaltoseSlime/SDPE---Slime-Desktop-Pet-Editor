class_name StyleEditorTab
extends VBoxContainer
## 介面風格分頁(企劃書第三章「個別桌寵專屬介面主題配色與預設對話字體」):四大顏色(框底色含 Alpha、框線色、文字色、選項色)、
## 邊框粗細與圓角、UI 縮放率(固定 8 檔)、預設對話字體、有選項的對話最長等待時間。
## 顏色可用色盤(含 Godot 內建的螢幕吸色滴管)選,也可以直接輸入或貼上 HEX(#RRGGBB 或 #RRGGBBAA)。
## 最上面是即時預覽:用跟實際對話氣泡同一套 UiStyleKit 繪製,所見即所得。

signal changed
signal message(text: String)

const COLOR_FIELDS := {
	"background": "框底色(含透明度)",
	"border": "框線色",
	"text": "文字色",
	"option": "選項色",
}
## 思考泡泡的四色(對話積木 BUBBLE = thought 用;配色獨立於一般對話框)。
const THOUGHT_COLOR_FIELDS := {
	"thought_background": "框底色(含透明度)",
	"thought_border": "框線色",
	"thought_text": "文字色",
	"thought_option": "選項色",
}
const PREVIEW_TEXT := "你好呀!這是氣泡預覽 [b]粗體[/b] [i]斜體[/i]\n第二行文字"
const THOUGHT_PREVIEW_TEXT := "嗯……這是思考泡泡的預覽\n[i]不知道他在想什麼[/i]"

var _pet: Node
var _flow: HFlowContainer
var _cards: Array[VBoxContainer] = []
var _loading := false
var _preview_box: VBoxContainer
var _pickers: Dictionary = {}
var _hex_edits: Dictionary = {}
var _border_spin: SpinBox
var _radius_spin: SpinBox
var _scale_option: OptionButton
var _font_option: OptionButton
var _font_scale_option: OptionButton
var _dialogue_locale_option: OptionButton
var _wait_spin: SpinBox
var _chat_check: CheckBox
var _chat_min_spin: SpinBox
var _chat_max_spin: SpinBox
var _dance_check: CheckBox
var _land_check: CheckBox
var _fly_option: OptionButton
var _no_fatigue_check: CheckBox
var _dance_spin: SpinBox
var _dance_follow_check: CheckBox
var _body_scale_spin: SpinBox
var _flip_check: CheckBox
var _drag_fixed_check: CheckBox
var _climb_check: CheckBox
var _breath_check: CheckBox
var _hitbox_spins: Array[SpinBox] = []
var _hitbox_auto_label: Label
var _unmute_check: CheckBox
var _fx_option: OptionButton
var _fx_mode_option: OptionButton
var _fx_color1: ColorPickerButton
var _fx_color2: ColorPickerButton
var _fx_size_spin: SpinBox
var _fx_density_row: Control
var _fx_density_spin: SpinBox
var _fx_range_row: Control
var _fx_range_spin: SpinBox
var _fx_ghost_row: Control
var _fx_hold_spin: SpinBox
var _fx_trail_spin: SpinBox
var _effects_check: CheckBox
var _effects_auto_check: CheckBox
var _link_options: Dictionary = {}
var _trail_option: OptionButton
var _sleep_z_check: CheckBox
var _status_energy_check: CheckBox
var _status_mood_check: CheckBox
var _voice_label: Label
var _voice_pitch_spin: SpinBox
var _voice_volume_spin: SpinBox
var _voice_player: AudioStreamPlayer


func _ready() -> void:
	name = "介面與自動行為"
	add_child(ManagerUi.heading("預覽"))
	_preview_box = VBoxContainer.new()
	_preview_box.custom_minimum_size.y = 150.0
	add_child(_preview_box)
	add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# 每個功能板塊是一張方形卡片,依視窗寬度自動排成一行幾張(不用每條都佔一整行)。
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 10)
	_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_flow)
	var form := _new_card("四大顏色")
	_add_color_rows(form, COLOR_FIELDS)

	form = _new_card("思考泡泡配色")
	_add_color_rows(form, THOUGHT_COLOR_FIELDS)
	form.add_child(ManagerUi.hint_row("說明", "對話積木的「泡泡」選「思考」時用這組顏色(和上面的對話框配色分開設定);樣子跟對話框很像,尾巴換成往角色頭部飄的幾顆小圓泡泡。框線粗細、縮放與字體沿用上面的設定,圓角至少 16。"))
	form = _new_card("外框與縮放")
	_border_spin = ManagerUi.spin(1.0, 0.0, PetUiStyle.MAX_BORDER_WIDTH)
	_border_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("邊框粗細", _border_spin))
	_radius_spin = ManagerUi.spin(1.0, 0.0, PetUiStyle.MAX_CORNER_RADIUS)
	_radius_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("圓角", _radius_spin))
	_scale_option = OptionButton.new()
	for step in PetUiStyle.SCALE_STEPS:
		_scale_option.add_item("%d%%" % step)
	_scale_option.item_selected.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("介面縮放率", _scale_option))
	form.add_child(ManagerUi.hint_row("說明", "只影響這隻桌寵的對話氣泡與 Status 面板(框體、邊框、文字一起縮放),不影響角色本體。"))

	form = _new_card("字體與對話")
	_font_option = OptionButton.new()
	for font_name in UiFonts.FONT_NAMES:
		_font_option.add_item(font_name)
	_font_option.item_selected.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("預設對話字體", _font_option))
	form.add_child(ManagerUi.hint_row("說明", "黑體(源樣黑體)、圓體(粉圓體)、像素體 Sliver ,標楷體用系統字型(沒有則退回預設字型);自訂上傳字型之後由素材匯入流程加入。"))
	_font_scale_option = OptionButton.new()
	for step in PetUiStyle.SCALE_STEPS:
		_font_scale_option.add_item("%d%%" % step)
	_font_scale_option.item_selected.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("字級", _font_scale_option))
	form.add_child(ManagerUi.hint_row("說明", "只放大/縮小文字本身,不像「介面縮放率」連框體、間距一起變大;像素體 Sliver 看起來比其他字體小是已知現象,已經私底下補了視覺大小,不用為了 Sliver 特別調高這裡。"))
	_dialogue_locale_option = OptionButton.new()
	_dialogue_locale_option.add_item("預設(原始語言)")
	_dialogue_locale_option.set_item_metadata(0, "")
	for code: String in AppSettings.available_languages():
		if code == AppSettings.DEFAULT_LANGUAGE:
			continue   # 「預設」本身就是原始語言版本,不用再列一次
		_dialogue_locale_option.add_item(str(AppSettings.available_languages()[code]))
		_dialogue_locale_option.set_item_metadata(_dialogue_locale_option.item_count - 1, code)
	_dialogue_locale_option.item_selected.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("桌寵語系", _dialogue_locale_option))
	form.add_child(ManagerUi.hint_row("說明", "這隻角色存在多種語系的對話文本時用來切換;不用檢查這隻角色原本是哪個語系寫的,初始一律是「預設」。翻譯內容要請 HTML 端(積木編輯器)另外製作,這裡只是先讓你能指定切換到哪個語系。"))
	_wait_spin = ManagerUi.spin(5.0, PetUiStyle.MIN_OPTION_WAIT, PetUiStyle.MAX_OPTION_WAIT)
	_wait_spin.suffix = "秒"
	_wait_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("選項最長等待", _wait_spin))

	form = _new_card("角色尺寸")
	_body_scale_spin = ManagerUi.spin(0.05, Pet.MIN_BODY_SCALE, Pet.MAX_BODY_SCALE)
	_body_scale_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("角色縮放倍率", _body_scale_spin))
	form.add_child(ManagerUi.hint_row("說明", "整隻角色(含碰撞箱與可點擊範圍)的大小倍率。"))
	_flip_check = CheckBox.new()
	_flip_check.text = "翻轉整隻(左右鏡像;素材原本朝向和慣例(朝右)相反時用)"
	_flip_check.toggled.connect(_on_field_changed)
	form.add_child(_flip_check)
	_drag_fixed_check = CheckBox.new()
	_drag_fixed_check.text = "固定模式下也能隨時拖曳(貼底的半身立繪只能沿底邊左右拖)"
	_drag_fixed_check.toggled.connect(_on_field_changed)
	form.add_child(_drag_fixed_check)
	_climb_check = CheckBox.new()
	_climb_check.text = "允許攀爬"
	_climb_check.toggled.connect(_on_field_changed)
	form.add_child(_climb_check)
	_breath_check = CheckBox.new()
	_breath_check.text = "呼吸動畫"
	_breath_check.toggled.connect(_on_field_changed)
	form.add_child(_breath_check)
	form = _new_card("判定框(可點擊範圍)")
	form.add_child(ManagerUi.hint_row("說明", "只有判定框裡點得到、抓得起這隻桌寵;畫在框外的翅膀、武器、特效仍然會完整顯示,只是不能點。寬/高填 0 = 自動(用素材包設定或待機圖本體大小)。單位是縮放前的像素,錨點是腳底線的中心點(偏移:X 向右、Y 向下)。系統匣「顯示穿透範圍(除錯)」會用藍框畫出判定框。"))
	_hitbox_auto_label = Label.new()
	form.add_child(_hitbox_auto_label)
	for entry in [["判定框寬(0=自動)", 0.0, 4096.0], ["判定框高(0=自動)", 0.0, 4096.0], ["偏移 X", -4096.0, 4096.0], ["偏移 Y", -4096.0, 4096.0]]:
		var spin := ManagerUi.spin(1.0, entry[1], entry[2])
		spin.value_changed.connect(_on_field_changed)
		form.add_child(ManagerUi.labeled(entry[0], spin))
		_hitbox_spins.append(spin)

	form = _new_card("自動閒聊")
	_chat_check = CheckBox.new()
	_chat_check.text = "讓這隻桌寵隔一段時間自己「說點什麼」"
	_chat_check.toggled.connect(_on_field_changed)
	form.add_child(_chat_check)
	_chat_min_spin = ManagerUi.spin(10.0, PetProfile.MIN_AUTO_CHAT_SECONDS, 86400.0)
	_chat_min_spin.suffix = "秒"
	_chat_min_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("最短間隔", _chat_min_spin))
	_chat_max_spin = ManagerUi.spin(10.0, PetProfile.MIN_AUTO_CHAT_SECONDS, 86400.0)
	_chat_max_spin.suffix = "秒"
	_chat_max_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("最長間隔", _chat_max_spin))
	form.add_child(ManagerUi.hint_row("說明", "每次在最短~最長之間隨機等待。全部桌寵的總開關在系統匣選單「自動閒聊」;使用者剛互動過、正在對話、拖曳或入場中時不會開口。"))

	form = _new_card("自動跳舞")
	_dance_check = CheckBox.new()
	_dance_check.text = "沒有負面狀態時,待機結束有機率自己跳一段舞"
	_dance_check.toggled.connect(_on_field_changed)
	form.add_child(_dance_check)
	_dance_spin = ManagerUi.spin(1.0, 0.0, 100.0)
	_dance_spin.suffix = "%"
	_dance_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("每次待機結束的機率", _dance_spin))
	_dance_follow_check = CheckBox.new()
	_dance_follow_check.text = "看到場內別的桌寵在跳舞時,自己也考慮跟著跳"
	_dance_follow_check.toggled.connect(_on_field_changed)
	form.add_child(_dance_follow_check)
	form.add_child(ManagerUi.hint_row("說明", "需要角色有 dance 動作素材才會跳(沒有就不會觸發);身上有任何「負面」狀態鏡(疲憊等)時不跳,跳到一半出現負面狀態也會立刻收舞。"))

	form = _new_card("道具互動")
	_land_check = CheckBox.new()
	_land_check.text = "飛行模式:道具交互時降落(被拿來洗澡、使用道具時先降落,結束再起飛;取消 = 原地懸停)"
	_land_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_land_check.toggled.connect(_on_field_changed)
	form.add_child(_land_check)
	_fly_option = OptionButton.new()
	for label in ["總是飛行", "會落地", "行走與飛行兼具"]:
		_fly_option.add_item(label)
	_fly_option.tooltip_text = "總是飛行:做什麼都不落地,休息、睡覺也在空中。\n會落地:累了、道具交互等某些時候才落地,其餘時候在飛。\n行走與飛行兼具:以地面行為為主;大跳躍、從平臺下來、偶爾(心情好機率高)會改成飛行一小段,再降落。"
	_fly_option.item_selected.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("飛行模式的行為", _fly_option))
	_no_fatigue_check = CheckBox.new()
	_no_fatigue_check.text = "桌寵不計算疲勞值(不會累、不會自己休息或睡覺,也不會因疲勞陷入負面狀態;奔跑最多持續 15 秒)"
	_no_fatigue_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_fatigue_check.toggled.connect(_on_field_changed)
	form.add_child(_no_fatigue_check)
	form.add_child(ManagerUi.hint_row("說明", "不管什麼移動模式,跳舞、被拿來洗澡、使用道具的時候都不會走來走去,固定模式的桌寵只會收「拖曳到它身上」的道具。"))

	form = _new_card("自主靜音")
	_unmute_check = CheckBox.new()
	_unmute_check.text = "允許自主解除靜音(事件觸發的靜音,在觸發條件消失時自動解除)"
	_unmute_check.toggled.connect(_on_field_changed)
	form.add_child(_unmute_check)
	form.add_child(ManagerUi.hint_row("說明", "關閉後,事件觸發的靜音只會被積木的「解除靜音」或逾時解除;此設定只影響這隻桌寵自己的說話聲與效果音。"))

	form = _new_card("說話聲音")
	_voice_label = Label.new()
	_voice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_voice_label)
	var voice_row := HBoxContainer.new()
	var import_button := ManagerUi.button("導入聲音檔…")
	import_button.pressed.connect(_browse_voice)
	var clear_button := ManagerUi.button("恢復內建聲音")
	clear_button.pressed.connect(_clear_voice)
	var preview_button := ManagerUi.button("試聽")
	preview_button.pressed.connect(_preview_voice)
	voice_row.add_child(import_button)
	voice_row.add_child(clear_button)
	voice_row.add_child(preview_button)
	form.add_child(voice_row)
	_voice_pitch_spin = ManagerUi.spin(0.05, PetVoice.PITCH_RANGE.x, PetVoice.PITCH_RANGE.y)
	_voice_pitch_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("音高(1.0 = 原音)", _voice_pitch_spin))
	_voice_volume_spin = ManagerUi.spin(5.0, 0.0, 100.0)
	_voice_volume_spin.suffix = "%"
	_voice_volume_spin.value_changed.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("說話聲音量", _voice_volume_spin))
	form.add_child(ManagerUi.hint_row("說明", "打字機每輸出一個字播一聲,請用很短的音效(ogg / wav / mp3,3 秒內、1 MB 內)。同一個角色(辨識代號相同)的所有桌寵共用。音高與音量對內建聲音也有效。系統匣「音效」選單的靜音與說話音效開關仍然有效。"))
	_voice_player = AudioStreamPlayer.new()
	add_child(_voice_player)

	form = _new_card("角色特效")
	_effects_check = CheckBox.new()
	_effects_check.text = "啟用角色特效(愛心、火苗、冒汗、閃光、小花、發光、殘影)"
	_effects_check.toggled.connect(_on_field_changed)
	form.add_child(_effects_check)
	_effects_auto_check = CheckBox.new()
	_effects_auto_check.text = "狀態鏡自動觸發(開心 → 小愛心與閃光、生氣 → 火苗、疲憊 → 冒汗)"
	_effects_auto_check.toggled.connect(_on_field_changed)
	form.add_child(_effects_auto_check)
	form.add_child(ManagerUi.hint_row("說明", "特效大小依角色身高自動換算。由積木「播放特效」呼叫;下拉選單的名稱來自 Schema。"))

	_trail_option = OptionButton.new()
	for mode: String in PetEffects.TRAIL_MODES:
		_trail_option.add_item(str(PetEffects.TRAIL_LABELS[mode]))
	_trail_option.item_selected.connect(_on_field_changed)
	form.add_child(ManagerUi.labeled("移動時自動殘影", _trail_option))
	form.add_child(ManagerUi.hint_row("移動時自動殘影", "選「奔跑時」= 開了 run(或狀態鏡讓它奔跑)就一路留殘影;「只要在移動」= 走路、飛行、漂浮都留。殘影的顏色、拖尾距離、停留時間在下面「特效外觀 → 移動殘影」調。想用積木控制,用「開啟 / 關閉殘影」。"))

	form = _new_card("連帶觸發特效")
	form.add_child(ManagerUi.hint_row("說明", "使用者互動時自動播的特效(不用寫積木)。例如「被觸摸 → 幸福」。積木的事件照常執行,兩邊可以同時作用;上面「啟用角色特效」關掉時這裡也不會播。"))
	for kind: String in PetEffects.LINK_KEYS:
		var link_option := OptionButton.new()
		link_option.add_item("(不播)")
		for effect_label in PetEffects.CATALOG:
			link_option.add_item(effect_label)
		link_option.item_selected.connect(_on_field_changed)
		_link_options[kind] = link_option
		form.add_child(ManagerUi.labeled(str(PetEffects.LINK_LABELS[kind]), link_option))

	form = _new_card("特效外觀(顏色、大小、密度)")
	_fx_option = OptionButton.new()
	for effect_label in PetEffects.CATALOG:
		_fx_option.add_item(effect_label)
	_fx_option.item_selected.connect(func(_i: int) -> void: _load_fx_widgets())
	form.add_child(ManagerUi.labeled("要調哪個特效", _fx_option))
	_fx_mode_option = OptionButton.new()
	for mode_label in PetEffects.COLOR_MODE_LABELS:
		_fx_mode_option.add_item(mode_label)
	_fx_mode_option.item_selected.connect(_on_fx_changed)
	form.add_child(ManagerUi.labeled("顏色模式", _fx_mode_option))
	_fx_color1 = ColorPickerButton.new()
	_fx_color1.edit_alpha = false
	_fx_color1.custom_minimum_size = Vector2(90.0, 28.0)
	_fx_color1.color_changed.connect(_on_fx_changed)
	form.add_child(ManagerUi.labeled("顏色一", _fx_color1))
	_fx_color2 = ColorPickerButton.new()
	_fx_color2.edit_alpha = false
	_fx_color2.custom_minimum_size = Vector2(90.0, 28.0)
	_fx_color2.color_changed.connect(_on_fx_changed)
	form.add_child(ManagerUi.labeled("顏色二", _fx_color2))
	_fx_size_spin = ManagerUi.spin(5.0, PetEffects.SIZE_RANGE.x * 100.0, PetEffects.SIZE_RANGE.y * 100.0)
	_fx_size_spin.suffix = "%"
	_fx_size_spin.value_changed.connect(_on_fx_changed)
	form.add_child(ManagerUi.labeled("粒子大小", _fx_size_spin))
	_fx_density_spin = ManagerUi.spin(5.0, PetEffects.DENSITY_RANGE.x * 100.0, PetEffects.DENSITY_RANGE.y * 100.0)
	_fx_density_spin.suffix = "%"
	_fx_density_spin.value_changed.connect(_on_fx_changed)
	_fx_density_row = ManagerUi.labeled("粒子密度", _fx_density_spin)
	form.add_child(_fx_density_row)
	_fx_range_spin = ManagerUi.spin(5.0, PetEffects.RANGE_RANGE.x * 100.0, PetEffects.RANGE_RANGE.y * 100.0)
	_fx_range_spin.suffix = "%"
	_fx_range_spin.value_changed.connect(_on_fx_changed)
	_fx_range_row = ManagerUi.labeled("生成點範圍(離角色遠近)", _fx_range_spin)
	form.add_child(_fx_range_row)
	_fx_hold_spin = ManagerUi.spin(0.05, PetEffects.HOLD_RANGE.x, PetEffects.HOLD_RANGE.y)
	_fx_hold_spin.suffix = " 秒"
	_fx_hold_spin.value_changed.connect(_on_fx_changed)
	_fx_trail_spin = ManagerUi.spin(0.01, PetEffects.TRAIL_RANGE.x, PetEffects.TRAIL_RANGE.y)
	_fx_trail_spin.value_changed.connect(_on_fx_changed)
	var ghost_box := VBoxContainer.new()
	ghost_box.add_child(ManagerUi.labeled("殘影暫留時長", _fx_hold_spin))
	ghost_box.add_child(ManagerUi.labeled("拖尾間距(身高的幾倍,越小越密)", _fx_trail_spin))
	_fx_ghost_row = ghost_box
	form.add_child(_fx_ghost_row)
	var fx_buttons := HBoxContainer.new()
	var fx_try := ManagerUi.button("試放這個特效")
	fx_try.pressed.connect(func() -> void:
		if _pet != null:
			_pet.effects.play(PetEffects.CATALOG[maxi(_fx_option.selected, 0)]))
	var fx_reset := ManagerUi.button("還原這個特效")
	fx_reset.pressed.connect(func() -> void:
		if _pet != null:
			_pet.effects.reset_style(PetEffects.resolve(PetEffects.CATALOG[maxi(_fx_option.selected, 0)]))
			_load_fx_widgets()
			changed.emit())
	fx_buttons.add_child(fx_try)
	fx_buttons.add_child(fx_reset)
	form.add_child(fx_buttons)
	form.add_child(ManagerUi.hint_row("說明", "每個特效可以個別設定:單色、雙色(每顆粒子隨機取兩色之一,火苗是外焰/內焰)、單色漸層、雙色漸層、彩虹色調。大小是依角色身高換算倍率;密度只對會發射很多顆的特效有意義;範圍是生成點離角色的遠近(調大會分散、調小會集中在角色附近,對憂愁/全身發光/移動殘影沒有意義,這三個不會顯示這一項);殘影用暫留時長與拖尾間距。"))

	form = _new_card("睡覺 Zzz")
	_sleep_z_check = CheckBox.new()
	_sleep_z_check.text = "睡著時頭上飄出 Zzz(用這隻角色的字體,從小 z 到大 Z,邊飄邊放大)"
	_sleep_z_check.toggled.connect(_on_field_changed)
	form.add_child(_sleep_z_check)
	form.add_child(ManagerUi.hint_row("說明", "純裝飾的小特效,不需要素材;字體跟「字體與對話」的預設對話字體一致,字級跟著角色大小與介面縮放率。"))

	form = _new_card("Status 面板")
	_status_energy_check = CheckBox.new()
	_status_energy_check.text = "顯示精力條(標出「累了」與「累到睡著」的門檻,底下寫目前的休息階段)"
	_status_energy_check.toggled.connect(_on_field_changed)
	form.add_child(_status_energy_check)
	_status_mood_check = CheckBox.new()
	_status_mood_check.text = "顯示心情條(標出「生氣」與「開心」的門檻)"
	_status_mood_check.toggled.connect(_on_field_changed)
	form.add_child(_status_mood_check)
	form.add_child(ManagerUi.hint_row("說明", "Status 面板預設只顯示創作者勾選的數值(避免洩露彩蛋),這兩條也一樣預設不顯示。精力條要角色有疲勞機制(套用有疲勞參數的性格);心情條隨時都有,但要套用有「心情起伏」參數的性格,心情才會讓角色進入開心/生氣狀態。"))

	var reset := ManagerUi.button("還原成預設風格")
	reset.pressed.connect(_reset)
	form = _new_card("還原")
	form.add_child(ManagerUi.hint_row("說明", "把這隻桌寵的介面風格(顏色、邊框、縮放、字體、選項等待)全部改回預設值;不影響角色尺寸與自動行為。"))
	form.add_child(reset)
	_finish_cards()


func set_pet(pet: Node) -> void:
	_pet = pet
	_load_form()


func _load_form() -> void:
	if _pet == null:
		return
	var style: PetUiStyle = _pet.ui_style
	_loading = true
	for field: String in _all_color_fields():
		var color: Color = style.get(field)
		_pickers[field].color = color
		_hex_edits[field].text = PetProfile.color_to_hex(color)
	_border_spin.value = style.border_width
	_radius_spin.value = style.corner_radius
	_scale_option.select(PetUiStyle.SCALE_STEPS.find(PetUiStyle.nearest_scale_step(style.ui_scale)))
	_font_option.select(maxi(UiFonts.FONT_NAMES.find(style.default_font), 0))
	_font_scale_option.select(PetUiStyle.SCALE_STEPS.find(PetUiStyle.nearest_scale_step(style.font_scale)))
	for i in _dialogue_locale_option.item_count:
		if str(_dialogue_locale_option.get_item_metadata(i)) == _pet.dialogue_locale:
			_dialogue_locale_option.select(i)
			break
	_wait_spin.value = style.option_wait_seconds
	_chat_check.button_pressed = _pet.auto_chat_enabled
	_chat_min_spin.value = _pet.auto_chat_interval.x
	_chat_max_spin.value = _pet.auto_chat_interval.y
	_dance_check.button_pressed = _pet.auto_dance_enabled
	_land_check.button_pressed = _pet.land_for_props
	_fly_option.select([1, 0, 2][_pet.fly_behavior])
	_no_fatigue_check.button_pressed = _pet.fatigue_disabled
	_dance_spin.value = roundf(_pet.auto_dance_chance * 100.0)
	_dance_follow_check.button_pressed = _pet.auto_dance_follow_enabled
	_unmute_check.button_pressed = _pet.auto_unmute_enabled
	_load_fx_widgets()
	for kind: String in PetEffects.LINK_KEYS:
		var loaded_option: OptionButton = _link_options[kind]
		var linked_name := PetEffects.resolve(str(_pet.effects.interaction_links[kind]))
		var catalog_index := -1
		for i in PetEffects.CATALOG.size():
			if PetEffects.resolve(PetEffects.CATALOG[i]) == linked_name:
				catalog_index = i
		loaded_option.select(catalog_index + 1)
	_effects_check.button_pressed = _pet.effects.enabled
	_effects_auto_check.button_pressed = _pet.effects.auto_enabled
	_trail_option.select(maxi(PetEffects.TRAIL_MODES.find(_pet.effects.trail_mode), 0))
	_sleep_z_check.button_pressed = _pet.sleep_z.enabled
	_status_energy_check.button_pressed = _pet.status_show_energy
	_status_mood_check.button_pressed = _pet.status_show_mood
	_body_scale_spin.value = snappedf(_pet.params.scale_multiplier, 0.01)
	_flip_check.button_pressed = _pet.art_flipped
	_drag_fixed_check.button_pressed = _pet.drag_when_fixed
	_climb_check.button_pressed = _pet.climb_enabled
	_breath_check.button_pressed = _pet.breathing_enabled
	_hitbox_spins[0].value = _pet.hitbox_size.x
	_hitbox_spins[1].value = _pet.hitbox_size.y
	_hitbox_spins[2].value = _pet.hitbox_offset.x
	_hitbox_spins[3].value = _pet.hitbox_offset.y
	_hitbox_auto_label.text = tr("目前生效:%d × %d(偏移 %d, %d)") % [_pet.effective_hitbox_size().x, _pet.effective_hitbox_size().y, _pet.effective_hitbox_offset().x, _pet.effective_hitbox_offset().y]
	_voice_pitch_spin.value = _pet.voice_pitch
	_voice_volume_spin.value = roundf(_pet.voice_volume * 100.0)
	_update_voice_label()
	_loading = false
	_rebuild_preview()


## 卡片的最小寬度:放得下「標籤 + 顏色鈕 + 十六進位輸入框」那一列;視窗寬度不夠排兩張就自動一行一張。
const CARD_WIDTH := 430.0


## 新增一張功能板塊卡片(標題 + 內容區),回傳內容區(往裡面加控制項)。
func _new_card(title_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = AppSettings.ink(0.05)
	style.border_color = AppSettings.ink(0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10.0)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)
	box.add_child(ManagerUi.heading(title_text))
	_flow.add_child(card)
	_cards.append(box)
	return box


## 卡片裡的核取方塊文字很長,讓它自己換行,不要撐寬卡片。
func _finish_cards() -> void:
	for box in _cards:
		for child in box.get_children():
			if child is CheckBox:
				(child as CheckBox).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				(child as CheckBox).custom_minimum_size.x = CARD_WIDTH - 30.0


## 特效外觀:把選到的那個特效目前的設定放進控制項(不發變更)。
func _load_fx_widgets() -> void:
	if _pet == null or _fx_option == null:
		return
	var key := PetEffects.resolve(PetEffects.CATALOG[maxi(_fx_option.selected, 0)])
	var style: Dictionary = _pet.effects.style_of(key)
	var was_loading := _loading
	_loading = true
	_fx_mode_option.select(maxi(PetEffects.COLOR_MODES.find(str(style["mode"])), 0))
	_fx_color1.color = style["c1"]
	_fx_color2.color = style["c2"]
	_fx_size_spin.value = roundf(float(style["size"]) * 100.0)
	_fx_density_spin.value = roundf(float(style["density"]) * 100.0)
	_fx_range_spin.value = roundf(float(style["range"]) * 100.0)
	_fx_hold_spin.value = float(style["hold"])
	_fx_trail_spin.value = float(style["trail"])
	_loading = was_loading
	_update_fx_visibility(key)


## 第二個顏色只在雙色/雙色漸層有意義,彩虹兩色都不用;密度只給複數粒子的特效;殘影才有暫留與拖尾。
func _update_fx_visibility(key: String) -> void:
	var mode: String = PetEffects.COLOR_MODES[maxi(_fx_mode_option.selected, 0)]
	_fx_color1.disabled = mode == "rainbow"
	_fx_color2.disabled = not mode in ["duo", "duo_gradient"]
	_fx_density_row.visible = PetEffects.MULTI.has(key)
	_fx_range_row.visible = not PetEffects.RANGE_UNUSED.has(key)
	_fx_ghost_row.visible = key == "afterimage"


func _on_fx_changed(_value: Variant = null) -> void:
	if _loading or _pet == null:
		return
	var key := PetEffects.resolve(PetEffects.CATALOG[maxi(_fx_option.selected, 0)])
	_pet.effects.set_style(key, {
		"mode": PetEffects.COLOR_MODES[maxi(_fx_mode_option.selected, 0)],
		"c1": _fx_color1.color, "c2": _fx_color2.color,
		"size": _fx_size_spin.value / 100.0, "density": _fx_density_spin.value / 100.0,
		"hold": _fx_hold_spin.value, "trail": _fx_trail_spin.value, "range": _fx_range_spin.value / 100.0,
	})
	_update_fx_visibility(key)
	changed.emit()


# --- 編輯 ---

func _on_picker_changed(color: Color, field: String) -> void:
	if _loading:
		return
	_apply_color(field, color)
	_hex_edits[field].text = PetProfile.color_to_hex(color)


## HEX 輸入框:格式不對就還原成目前的顏色並提示,不會壞掉。
func _on_hex_submitted(text: String, field: String) -> void:
	var trimmed := text.strip_edges()
	if not trimmed.begins_with("#"):
		trimmed = "#" + trimmed
	if not Color.html_is_valid(trimmed):
		message.emit("色碼格式不對,請輸入 #RRGGBB 或 #RRGGBBAA,已還原。")
		_hex_edits[field].text = PetProfile.color_to_hex(_pet.ui_style.get(field))
		return
	var color := Color.html(trimmed)
	_loading = true
	_pickers[field].color = color
	_hex_edits[field].text = PetProfile.color_to_hex(color)
	_loading = false
	_apply_color(field, color)


func _on_hex_focus_exited(field: String) -> void:
	if _pet != null and _hex_edits[field].text != PetProfile.color_to_hex(_pet.ui_style.get(field)):
		_on_hex_submitted(_hex_edits[field].text, field)


func _apply_color(field: String, color: Color) -> void:
	if _pet == null:
		return
	_pet.ui_style.set(field, color)
	_rebuild_preview()
	changed.emit()


func _on_field_changed(_value: Variant = null) -> void:
	if _loading or _pet == null:
		return
	var style: PetUiStyle = _pet.ui_style
	style.border_width = int(_border_spin.value)
	style.corner_radius = int(_radius_spin.value)
	style.ui_scale = PetUiStyle.SCALE_STEPS[maxi(_scale_option.selected, 0)]
	style.default_font = UiFonts.FONT_NAMES[maxi(_font_option.selected, 0)]
	style.font_scale = PetUiStyle.SCALE_STEPS[maxi(_font_scale_option.selected, 0)]
	_pet.dialogue_locale = str(_dialogue_locale_option.get_item_metadata(maxi(_dialogue_locale_option.selected, 0)))
	style.option_wait_seconds = _wait_spin.value
	_pet.auto_chat_enabled = _chat_check.button_pressed
	var low := maxf(_chat_min_spin.value, PetProfile.MIN_AUTO_CHAT_SECONDS)
	_pet.auto_chat_interval = Vector2(low, maxf(_chat_max_spin.value, low))
	_pet.auto_dance_enabled = _dance_check.button_pressed
	_pet.land_for_props = _land_check.button_pressed
	var new_behavior := [Pet.FlyBehavior.ALWAYS, Pet.FlyBehavior.LANDS, Pet.FlyBehavior.HYBRID][_fly_option.selected] as Pet.FlyBehavior
	if new_behavior != _pet.fly_behavior:
		_pet.fly_behavior = new_behavior
		if _pet.move_mode == Pet.MoveMode.FLYING:
			_pet.set_move_mode(Pet.MoveMode.FLYING)   # 換行為時飛行狀態重來(空中的兼具階段、降落進度不要帶到新行為)
	if _pet.fatigue_disabled != _no_fatigue_check.button_pressed:
		_pet.fatigue_disabled = _no_fatigue_check.button_pressed
		if _pet.fatigue_disabled and _pet.vitality != null:
			_pet.vitality.restore_energy(100.0)   # 不計算疲勞:精力補滿、疲勞狀態解除(fatigue_enabled 為假時 vitality 會自己收尾)
	_pet.auto_dance_chance = clampf(_dance_spin.value / 100.0, 0.0, 1.0)
	if not is_equal_approx(_pet.params.scale_multiplier, _body_scale_spin.value):
		_pet.set_body_scale(_body_scale_spin.value)
	if _pet.art_flipped != _flip_check.button_pressed:
		_pet.set_art_flipped(_flip_check.button_pressed)
	_pet.drag_when_fixed = _drag_fixed_check.button_pressed
	if _pet.climb_enabled != _climb_check.button_pressed:
		_pet.set_climb_enabled(_climb_check.button_pressed)
	if _pet.breathing_enabled != _breath_check.button_pressed:
		_pet.set_breathing(_breath_check.button_pressed)
	var box_width := _hitbox_spins[0].value
	var box_height := _hitbox_spins[1].value
	_pet.hitbox_size = Vector2(box_width, box_height) if box_width > 0.0 and box_height > 0.0 else Vector2.ZERO
	_pet.hitbox_offset = Vector2(_hitbox_spins[2].value, _hitbox_spins[3].value)
	_hitbox_auto_label.text = tr("目前生效:%d × %d(偏移 %d, %d)") % [_pet.effective_hitbox_size().x, _pet.effective_hitbox_size().y, _pet.effective_hitbox_offset().x, _pet.effective_hitbox_offset().y]
	_pet.auto_dance_follow_enabled = _dance_follow_check.button_pressed
	_pet.auto_unmute_enabled = _unmute_check.button_pressed
	for kind: String in PetEffects.LINK_KEYS:
		var chosen: OptionButton = _link_options[kind]
		_pet.effects.set_interaction_link(kind, "" if chosen.selected <= 0 else PetEffects.resolve(PetEffects.CATALOG[chosen.selected - 1]))
	_pet.effects.enabled = _effects_check.button_pressed
	_pet.effects.auto_enabled = _effects_auto_check.button_pressed
	_pet.effects.set_trail_mode(PetEffects.TRAIL_MODES[maxi(_trail_option.selected, 0)])
	_pet.sleep_z.enabled = _sleep_z_check.button_pressed
	_pet.status_show_energy = _status_energy_check.button_pressed
	_pet.status_show_mood = _status_mood_check.button_pressed
	_apply_voice_tuning()
	_rebuild_preview()
	changed.emit()


# --- 說話聲音 ---

## 音高/音量微調:套用到同一個角色(辨識代號相同)的所有桌寵,跟導入的聲音檔一致。
func _apply_voice_tuning() -> void:
	var pitch := clampf(_voice_pitch_spin.value, PetVoice.PITCH_RANGE.x, PetVoice.PITCH_RANGE.y)
	var volume := clampf(_voice_volume_spin.value / 100.0, 0.0, 1.0)
	for other: Node in _pet.get_tree().get_nodes_in_group("pets"):
		if other == _pet or (other.recognition_tag != "" and other.recognition_tag == _pet.recognition_tag):
			other.voice_pitch = pitch
			other.voice_volume = volume


func _update_voice_label() -> void:
	_voice_label.text = tr("目前:自訂聲音(%s)") % _pet.voice_file if _pet.voice_stream != null else "目前:內建說話聲音"


func _browse_voice() -> void:
	FloatingWindow.native_file_dialog("選擇說話聲音", "", DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.ogg,*.wav,*.mp3;音效檔"]),
			func(paths: PackedStringArray) -> void: _import_voice(paths[0]), get_window().get_window_id())


func _import_voice(path: String) -> void:
	if _pet == null:
		return
	var result := PetVoice.import_file(_pet, path)
	message.emit(str(result["message"]))
	if result["ok"]:
		_update_voice_label()
		changed.emit()


func _clear_voice() -> void:
	if _pet == null:
		return
	PetVoice.clear(_pet)
	_update_voice_label()
	message.emit("已恢復內建說話聲音。")
	changed.emit()


## 試聽:照打字機的節奏(約每 0.1 秒一聲)連播四聲,用目前的音高與音量。
func _preview_voice() -> void:
	if _pet == null:
		return
	var stream: AudioStream = _pet.voice_stream if _pet.voice_stream != null else load("res://assets/sfx/speak.ogg") as AudioStream
	if stream == null:
		return
	for i in 4:
		if not is_instance_valid(_voice_player):
			return
		_voice_player.stream = stream
		_voice_player.pitch_scale = _pet.voice_pitch
		_voice_player.volume_db = linear_to_db(maxf(_pet.voice_volume, 0.0001))
		_voice_player.play()
		await get_tree().create_timer(0.1).timeout


func _reset() -> void:
	if _pet == null:
		return
	_pet.ui_style.reset_to_defaults()
	_load_form()
	changed.emit()


# --- 預覽 ---

func _all_color_fields() -> Array:
	return COLOR_FIELDS.keys() + THOUGHT_COLOR_FIELDS.keys()


## 一組「標籤 + 顏色鈕 + 十六進位輸入框」的顏色列(對話框與思考泡泡各一組)。
func _add_color_rows(form: VBoxContainer, fields: Dictionary) -> void:
	for field: String in fields:
		var picker := ColorPickerButton.new()
		picker.edit_alpha = true
		picker.custom_minimum_size = Vector2(90.0, 28.0)
		picker.color_changed.connect(_on_picker_changed.bind(field))
		var hex := ManagerUi.line_edit("#RRGGBB 或 #RRGGBBAA")
		hex.custom_minimum_size.x = 160.0
		hex.text_submitted.connect(_on_hex_submitted.bind(field))
		hex.focus_exited.connect(_on_hex_focus_exited.bind(field))
		var row := ManagerUi.labeled(fields[field], picker)
		picker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_child(hex)
		form.add_child(row)
		_pickers[field] = picker
		_hex_edits[field] = hex


## 用實際氣泡同一套 UiStyleKit 畫兩個範例並排(左:一般對話框,右:思考泡泡;名字標籤跨在左上邊框、文字、選項按鈕)。
func _rebuild_preview() -> void:
	for child in _preview_box.get_children():
		_preview_box.remove_child(child)
		child.queue_free()
	if _pet == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_preview_box.add_child(row)
	var parts: Array = []
	for thought in [false, true]:
		parts.append(_make_preview(row, thought))
	_fit_preview(parts)


## 做一個預覽泡泡,回傳 {holder, panel, tag_half}。
func _make_preview(parent: Control, thought: bool) -> Dictionary:
	var style: PetUiStyle = _pet.ui_style
	var factor := style.scale_factor()
	var font := UiFonts.get_font(style.default_font)
	var colors := style.palette(thought)

	var holder := Control.new()
	parent.add_child(holder)
	var tag := UiStyleKit.name_tag(_pet.get_label(), font, style, factor, thought)
	var tag_half := ceilf(tag.get_combined_minimum_size().y * 0.5)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyleKit.panel_style(style, factor, thought))
	panel.position = Vector2(0.0, tag_half)
	holder.add_child(panel)
	holder.add_child(tag)
	tag.position = Vector2(10.0 * factor, 0.0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(6 * factor))
	panel.add_child(column)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size.x = 230.0 * factor
	label.add_theme_font_override("normal_font", font)
	label.add_theme_font_override("bold_font", font)
	label.add_theme_font_override("italics_font", font)
	var text_factor := style.text_scale_factor()
	label.add_theme_font_size_override("normal_font_size", int(UiStyleKit.BASE_FONT_SIZE * text_factor))
	label.add_theme_font_size_override("bold_font_size", int(UiStyleKit.BASE_FONT_SIZE * text_factor))
	label.add_theme_font_size_override("italics_font_size", int(UiStyleKit.BASE_FONT_SIZE * text_factor))
	label.add_theme_color_override("default_color", colors["text"])
	label.text = THOUGHT_PREVIEW_TEXT if thought else PREVIEW_TEXT
	column.add_child(label)
	column.add_child(UiStyleKit.option_button("選項按鈕範例", font, style, factor, thought))
	return {"holder": holder, "panel": panel, "tag_half": tag_half}


## Control 不會自動撐開,預覽區的高度要手動給(面板最小尺寸 + 上方標籤突出的部分,取兩個預覽較高的)。
## 富文字標籤的高度要等下一影格排版完才準,所以等一個影格再量。
func _fit_preview(parts: Array) -> void:
	await get_tree().process_frame
	var tallest := 0.0
	for part: Dictionary in parts:
		if not is_instance_valid(part["holder"]) or not is_instance_valid(part["panel"]):
			return
		var height := (part["panel"] as PanelContainer).get_combined_minimum_size().y + float(part["tag_half"])
		(part["holder"] as Control).custom_minimum_size = (part["panel"] as PanelContainer).get_combined_minimum_size() + Vector2(0.0, float(part["tag_half"]))
		tallest = maxf(tallest, height)
	_preview_box.custom_minimum_size.y = tallest