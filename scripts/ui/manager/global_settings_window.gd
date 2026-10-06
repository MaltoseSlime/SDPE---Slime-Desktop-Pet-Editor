class_name GlobalSettingsWindow
extends FloatingWindow
## 全局設定視窗:不屬於任何一隻桌寵的設定——音效(靜音、說話音效、全部桌寵音量)、介面語系、效能、編輯器外觀,另有「關於」頁籤(作者署名、AI 協助聲明、外部素材,見 CreditsData)。
## 設定的內容在 AppSettingsTab;這裡是浮動視窗外殼 + 底部的狀態文字。所有設定改了立刻生效並存進 user://settings.cfg,沒有「儲存」按鈕。

## 音效設定要寫進共享狀態並通知 SoundManager,由開啟視窗的 DesktopShell 接手。
signal audio_setting_requested(kind: String, value: Variant)
## 「設定行動框顯示螢幕」改了,index 是使用者選的原始值(-1 = 自動),由 DesktopShell 接手實際搬動視窗與內容。
signal monitor_setting_requested(index: int)

var _app_settings_tab: AppSettingsTab
var _status_label: Label
var _tabs: TabContainer
var _credits_label: RichTextLabel


func setup() -> void:
	setup_floating(tr("全局設定"), Vector2i(660, 740), Vector2i(480, 420))
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	background.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_tabs)

	var scroll := ScrollContainer.new()
	scroll.name = "設定"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_app_settings_tab = AppSettingsTab.new()
	_app_settings_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_app_settings_tab)
	_app_settings_tab.message.connect(func(text: String) -> void: _status_label.text = text)
	_app_settings_tab.audio_setting_requested.connect(func(kind: String, value: Variant) -> void: audio_setting_requested.emit(kind, value))
	_app_settings_tab.monitor_setting_requested.connect(func(index: int) -> void: monitor_setting_requested.emit(index))

	_build_credits_tab()

	_status_label = Label.new()
	_status_label.theme_type_variation = AppSettings.MUTED_LABEL
	_status_label.text = tr("這裡的設定改了就立刻生效並存起來。")
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_status_label)


## 「關於」頁籤:CreditsData 產生的文字。
func _build_credits_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "關於"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_credits_label = RichTextLabel.new()
	_credits_label.bbcode_enabled = true
	_credits_label.fit_content = true
	_credits_label.scroll_active = false
	_credits_label.selection_enabled = true
	_credits_label.context_menu_enabled = true
	_credits_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_credits_label.text = CreditsData.bbcode()
	_credits_label.meta_clicked.connect(_on_credit_link)
	scroll.add_child(_credits_label)

func _on_credit_link(meta: Variant) -> void:
	var url := str(meta)
	if CreditsData.is_openable(url):
		OS.shell_open(url)
