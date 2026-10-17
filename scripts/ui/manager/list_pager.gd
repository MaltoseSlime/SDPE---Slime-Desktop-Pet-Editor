class_name ListPager
extends VBoxContainer
## 2026-10-17 長名單翻頁(使用者要求:新增反應事件、角色、道具、關鍵詞會讓卡片名單越來越長):把一個列表容器包起來,
## 列表頭尾各內嵌一條翻頁鍵(第一頁 / 上一頁 / 下一頁 / 最後一頁),一次只顯示 page_size 列。只有一頁時兩條都藏起來,看起來跟沒包一樣。
## 使用者要求翻頁鍵不要用文字:四個都是程式畫的箭頭圖示(PageIcon,不是圖檔);上一頁、下一頁中間常駐顯示頁碼「1/3」(只寫數字)。
## 列表照舊由呼叫端自己清空/重建(加減子節點就會自動重排,不用通知);重建後停在原本那頁(超出就夾到最後一頁),
## 新增完想跳到最後一頁看剛加的那列,呼叫 show_last()。設了 meta "pager_pinned" 的列(像「有 N 項被隱藏」的頁尾)每頁都顯示。

const DEFAULT_PAGE_SIZE := 10

var list: Container
var page_size := DEFAULT_PAGE_SIZE
var _page := 0
var _pending := false
var _bars: Array[Dictionary] = []   # 頭、尾兩條:{"bar", "first", "prev", "page", "next", "last"}


## 把 target 包進一個新的 ListPager(target 還不能有父節點),回傳包好的節點,拿去 add_child 取代原本的 target。
static func wrap(target: Container, size := DEFAULT_PAGE_SIZE) -> ListPager:
	var pager := ListPager.new()
	pager.page_size = maxi(size, 1)
	pager._setup(target)
	return pager


func _setup(target: Container) -> void:
	list = target
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bars.append(_make_bar())
	add_child(list)
	_bars.append(_make_bar())
	list.child_entered_tree.connect(func(_node: Node) -> void: _queue_refresh())
	list.child_exiting_tree.connect(func(_node: Node) -> void: _queue_refresh())
	_queue_refresh()


func _make_bar() -> Dictionary:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	var entry := {"bar": bar}
	for key: String in ["first", "prev", "next", "last"]:
		var button := PageIcon.new()
		button.kind = key
		button.pressed.connect(func() -> void: _go(key))
		bar.add_child(button)
		entry[key] = button
		if key == "prev":
			var page := Label.new()
			page.theme_type_variation = AppSettings.MUTED_LABEL
			page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			page.custom_minimum_size.x = 44
			bar.add_child(page)
			entry["page"] = page
	return entry


func _go(key: String) -> void:
	match key:
		"first": _page = 0
		"prev": _page -= 1
		"next": _page += 1
		"last": _page = page_count() - 1
	refresh()


## 跳到最後一頁(剛新增一列時用;列表還沒重建完也沒關係,下次重排時才夾範圍)。
func show_last() -> void:
	_page = 1 << 30
	_queue_refresh()


func current_page() -> int:
	return _page


func page_count() -> int:
	return maxi(1, ceili(float(_items().size()) / float(page_size)))


func _items() -> Array[Node]:
	var result: Array[Node] = []
	if list == null:
		return result
	for child: Node in list.get_children():
		if not child.is_queued_for_deletion() and child is Control and not child.has_meta("pager_pinned"):
			result.append(child)
	return result


func _queue_refresh() -> void:
	if _pending:
		return
	_pending = true
	refresh.call_deferred()


func refresh() -> void:
	_pending = false
	if list == null or not is_instance_valid(list):
		return
	var items := _items()
	var pages := maxi(1, ceili(float(items.size()) / float(page_size)))
	_page = clampi(_page, 0, pages - 1)
	var start := _page * page_size
	for i in items.size():
		(items[i] as Control).visible = i >= start and i < start + page_size
	for entry: Dictionary in _bars:
		(entry["bar"] as Control).visible = pages > 1
		(entry["page"] as Label).text = "%d/%d" % [_page + 1, pages]
		for key: String in ["first", "prev", "next", "last"]:
			(entry[key] as Button).tooltip_text = tr(str(PageIcon.TIPS[key]))
		(entry["first"] as Button).disabled = _page == 0
		(entry["prev"] as Button).disabled = _page == 0
		(entry["next"] as Button).disabled = _page >= pages - 1
		(entry["last"] as Button).disabled = _page >= pages - 1


## 翻頁鍵:沒有文字,箭頭用 _draw 畫(平時次要文字色,滑過去一般文字色,停用時淡掉),顏色跟著配色走。
class PageIcon:
	extends Button

	const TIPS := {"first": "第一頁", "prev": "上一頁", "next": "下一頁", "last": "最後一頁"}
	var kind := "next"

	func _init() -> void:
		custom_minimum_size = Vector2(30, 24)
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			queue_redraw()

	func _draw() -> void:
		var color := get_theme_color("font_color", "Label") if is_hovered() else ManagerUi.muted_color(self)
		if disabled:
			color.a *= 0.35
		var center := size * 0.5
		var h := 5.0
		var dir := -1.0 if kind == "first" or kind == "prev" else 1.0
		var tips: Array[float] = [0.0]
		if kind == "first" or kind == "last":
			tips = [-3.0, 3.0]
		for offset: float in tips:
			var tip := center + Vector2(dir * (h * 0.5 + offset), 0)
			var back := tip.x - dir * h
			draw_colored_polygon(PackedVector2Array([tip, Vector2(back, center.y - h), Vector2(back, center.y + h)]), color)
		if kind == "first" or kind == "last":
			var x := center.x + dir * (h * 0.5 + 3.0 + 1.5)
			draw_line(Vector2(x, center.y - h), Vector2(x, center.y + h), color, 1.6)
