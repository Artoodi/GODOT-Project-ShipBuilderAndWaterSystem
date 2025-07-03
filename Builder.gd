
extends Node2D

# 导出变量
@export var grid_size: int = 32
@export var build_area_width: int = 26  # 格子数（横向）
@export var build_area_height: int = 16  # 格子数（纵向）
@export var block_scene: PackedScene

var is_placing: bool = false
var is_removing: bool = false

# 建造系统变量
var grid_offset: Vector2
var placed_blocks: Dictionary = {}  # key: Vector2i, value: Block
var preview_block: Block
var can_place_current: bool = false
var ship_data: Array[Vector2i] = []

# UI元素
var grid_background: Panel
var start_button: Button
var clear_button: Button
var block_counter_label: Label
var instructions_label: Label

# 信号
signal build_complete(ship_data: Array[Vector2i])

func _ready():
	setup_scene()
	create_ui()
	create_preview_block()

func setup_scene():
	# 计算网格偏移，使建造区域居中
	var viewport_size = get_viewport_rect().size
	var build_area_pixel_size = Vector2(
		build_area_width * grid_size,
		build_area_height * grid_size
	)
	grid_offset = (viewport_size - build_area_pixel_size) / 2
	
	# 创建网格背景
	grid_background = Panel.new()
	grid_background.size = build_area_pixel_size
	grid_background.position = grid_offset
	grid_background.modulate = Color(0.9, 0.9, 0.9)
	add_child(grid_background)
	
	# 绘制网格线
	var grid_lines = Control.new()
	grid_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid_lines.draw.connect(_draw_grid_lines.bind(grid_lines))
	grid_background.add_child(grid_lines)

func _draw_grid_lines(control: Control):
	# 绘制垂直线
	for x in range(build_area_width + 1):
		var start_pos = Vector2(x * grid_size, 0)
		var end_pos = Vector2(x * grid_size, build_area_height * grid_size)
		control.draw_line(start_pos, end_pos, Color(0.7, 0.7, 0.7), 1)
	
	# 绘制水平线
	for y in range(build_area_height + 1):
		var start_pos = Vector2(0, y * grid_size)
		var end_pos = Vector2(build_area_width * grid_size, y * grid_size)
		control.draw_line(start_pos, end_pos, Color(0.7, 0.7, 0.7), 1)

func create_ui():
	# 创建UI容器
	var ui_container = VBoxContainer.new()
	ui_container.position = Vector2(20, 20)
	add_child(ui_container)
	
	# 标题
	var title = Label.new()
	title.text = "船只建造器"
	title.add_theme_font_size_override("font_size", 24)
	ui_container.add_child(title)
	
	# 说明文字
	instructions_label = Label.new()
	instructions_label.text = "左键点击放置方块\n右键删除方块\n方块必须相连"
	ui_container.add_child(instructions_label)
	
	# 方块计数器
	block_counter_label = Label.new()
	block_counter_label.text = "已放置方块: 0"
	ui_container.add_child(block_counter_label)
	
	# 添加间距
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	ui_container.add_child(spacer)
	
	# 开始游戏按钮
	start_button = Button.new()
	start_button.text = "开始"
	start_button.custom_minimum_size = Vector2(120, 40)
	start_button.disabled = true
	start_button.pressed.connect(_on_start_button_pressed)
	ui_container.add_child(start_button)
	
	# 清空按钮
	clear_button = Button.new()
	clear_button.text = "清空"
	clear_button.custom_minimum_size = Vector2(120, 40)
	clear_button.pressed.connect(_on_clear_button_pressed)
	ui_container.add_child(clear_button)

func create_preview_block():
	if not block_scene:
		push_error("Block scene not set!")
		return
	
	preview_block = block_scene.instantiate()
	preview_block.visible = false
	add_child(preview_block)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_placing = event.pressed
			if is_placing:
				try_place_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			is_removing = event.pressed
			if is_removing:
				try_remove_block(event.position)
	elif event is InputEventMouseMotion:
		update_preview_position(event.position)
		if is_placing:
			try_place_block()
		elif is_removing:
			try_remove_block(event.position)

func update_preview_position(mouse_pos: Vector2):
	var grid_pos = world_to_grid(mouse_pos)
	
	# 检查是否在建造区域内
	if not is_in_build_area(grid_pos):
		preview_block.visible = false
		return
	
	# 更新预览方块位置
	preview_block.visible = true
	preview_block.position = grid_to_world(grid_pos)
	preview_block.grid_position = grid_pos
	
	# 检查是否可以放置
	can_place_current = can_place_at(grid_pos)
	preview_block.set_preview_mode(can_place_current)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local_pos = world_pos - grid_offset
	return Vector2i(
		int(local_pos.x / grid_size),
		int(local_pos.y / grid_size)
	)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * grid_size + grid_size / 2,
		grid_pos.y * grid_size + grid_size / 2
	) + grid_offset

func is_in_build_area(grid_pos: Vector2i) -> bool:
	return (
		grid_pos.x >= 0 and grid_pos.x < build_area_width and
		grid_pos.y >= 0 and grid_pos.y < build_area_height
	)

func can_place_at(grid_pos: Vector2i) -> bool:
	# 检查位置是否已被占用
	if placed_blocks.has(grid_pos):
		return false
	
	# 第一个方块可以放置在任何位置
	if placed_blocks.is_empty():
		return true
	
	# 检查是否与已有方块相邻
	var neighbors = [
		Vector2i(grid_pos.x - 1, grid_pos.y),  # 左
		Vector2i(grid_pos.x + 1, grid_pos.y),  # 右
		Vector2i(grid_pos.x, grid_pos.y - 1),  # 上
		Vector2i(grid_pos.x, grid_pos.y + 1)   # 下
	]
	
	for neighbor in neighbors:
		if placed_blocks.has(neighbor):
			return true
	
	return false

func try_place_block():
	if not can_place_current or not preview_block.visible:
		return
	
	# 创建新方块
	var new_block = block_scene.instantiate()
	new_block.position = preview_block.position
	new_block.grid_position = preview_block.grid_position
	new_block.set_placed()
	add_child(new_block)
	
	# 记录方块
	placed_blocks[preview_block.grid_position] = new_block
	ship_data.append(preview_block.grid_position)
	
	# 更新UI
	update_block_counter()
	update_start_button()

func try_remove_block(mouse_pos: Vector2):
	var grid_pos = world_to_grid(mouse_pos)
	
	if not placed_blocks.has(grid_pos):
		return
	
	# 检查移除后是否会断开连接
	if will_disconnect_ship(grid_pos):
		print("不能移除此方块，会导致船体断开！")
		return
	
	# 移除方块
	var block = placed_blocks[grid_pos]
	placed_blocks.erase(grid_pos)
	ship_data.erase(grid_pos)
	block.queue_free()
	
	# 更新UI
	update_block_counter()
	update_start_button()

func will_disconnect_ship(remove_pos: Vector2i) -> bool:
	if placed_blocks.size() <= 1:
		return false
	
	# 创建临时的方块集合（用于：排除要移除的方块）
	var temp_blocks = {}
	for pos in placed_blocks:
		if pos != remove_pos:
			temp_blocks[pos] = true
	
	# 检查连通性（洪水算法）
	var visited = {}
	var start_pos = temp_blocks.keys()[0]
	flood_fill(start_pos, temp_blocks, visited)
	
	# 如果访问的方块数量小于临时方块总数，说明会断开
	return visited.size() < temp_blocks.size()

func flood_fill(pos: Vector2i, blocks: Dictionary, visited: Dictionary):
	if visited.has(pos) or not blocks.has(pos):
		return
	
	visited[pos] = true
	
	# 检查四个方向
	flood_fill(Vector2i(pos.x - 1, pos.y), blocks, visited)
	flood_fill(Vector2i(pos.x + 1, pos.y), blocks, visited)
	flood_fill(Vector2i(pos.x, pos.y - 1), blocks, visited)
	flood_fill(Vector2i(pos.x, pos.y + 1), blocks, visited)

func update_block_counter():
	block_counter_label.text = "已放置方块: " + str(placed_blocks.size())

func update_start_button():
	start_button.disabled = placed_blocks.is_empty()

func _on_start_button_pressed():
	if not placed_blocks.is_empty():
		# 保存船只数据到全局变量
		GameData.set_ship_data(ship_data)
		
		# 切换到游戏场景
		get_tree().change_scene_to_file("res://scenes/GameScene.tscn")

func _on_clear_button_pressed():
	# 清除所有方块
	for block in placed_blocks.values():
		block.queue_free()
	
	placed_blocks.clear()
	ship_data.clear()
	
	# 更新UI
	update_block_counter()
	update_start_button()
