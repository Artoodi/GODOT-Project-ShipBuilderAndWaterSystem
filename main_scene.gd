# GameScene.gd
extends Node2D

@export var block_scene: PackedScene
@export var water_level: float = 400.0
@export var spawn_height: float = 200.0
@export var water_density: float = 0.01
@export var gravity: float = 980.0
@export var block_mass: float = 5.0

# 断裂系统参数
@export var joint_break_force: float = 90000.0  # 关节断裂力阈值
@export var block_break_impulse: float = 10.0  # 方块破坏冲击力阈值
@export var show_stress_debug: bool = true  # 显示应力调试信息

# 波浪参数
var wave_line: Line2D
var wave_point_count := 50
var wave_time := 0.0
var wave_amplitude := 5.0
var wave_wavelength := 100.0
var wave_speed := 2.0

# 船只相关
var ship_center_body: RigidBody2D
var ship_blocks: Array[RigidBody2D] = []
var block_joints: Array = []
var joint_connections: Dictionary = {}  # 记录关节连接的方块

# 独立的船只部分（断裂后）
var ship_parts: Array[Dictionary] = []  # 每个部分包含blocks和joints

func _ready():
	# 全局重力设置
	var space = get_world_2d().space
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, gravity)
	# 初始化水体与船
	_create_water()
	_spawn_ship()
	set_process(true)

func _create_water():
	# 水面以下半透明填充
	var water_rect = ColorRect.new()
	water_rect.size = Vector2(get_viewport().size.x, get_viewport().size.y - water_level)
	water_rect.position = Vector2(0, water_level)
	water_rect.color = Color(0.2, 0.5, 0.8, 0.6)
	water_rect.z_index = -1
	add_child(water_rect)

	# 水面线条
	var water_line = Line2D.new()
	water_line.width = 3.0
	water_line.default_color = Color(0.1, 0.3, 0.6)
	water_line.add_point(Vector2(0, water_level))
	water_line.add_point(Vector2(get_viewport().size.x, water_level))
	add_child(water_line)
	
	wave_line = Line2D.new()
	wave_line.width = 2.0
	wave_line.default_color = Color(0.3, 0.6, 0.9, 0.5)
	for i in range(wave_point_count):
		var x = i * get_viewport().size.x / float(wave_point_count - 1)
		wave_line.add_point(Vector2(x, water_level))
	add_child(wave_line)
	

func _spawn_ship():
	var ship_data = GameData.get_ship_data()
	if ship_data.size() == 0:
		push_error("没有船只数据！")
		return

	# 计算包围盒，求中心偏移
	var min_pos = Vector2i(9999, 9999)
	var max_pos = Vector2i(-9999, -9999)
	for p in ship_data:
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)
	var ship_size = (max_pos - min_pos + Vector2i.ONE) * GameData.grid_size
	var center_offset = Vector2(ship_size.x, ship_size.y) * 0.5

	# 创建船心刚体
	ship_center_body = RigidBody2D.new()
	ship_center_body.position = Vector2(get_viewport().size.x * 0.5, water_level - spawn_height)
	ship_center_body.mass = 0.5
	ship_center_body.linear_damp = 2.0
	ship_center_body.angular_damp = 3.0
	ship_center_body.gravity_scale = 0.1
	add_child(ship_center_body)

	# 防止穿透的小碰撞体
	var cc = CollisionShape2D.new()
	var cs = CircleShape2D.new()
	cs.radius = 5
	cc.shape = cs
	ship_center_body.add_child(cc)

	# 实例化并放置方块
	var block_map = {}
	for bp in ship_data:
		var rel = Vector2(
			(bp.x - min_pos.x) * GameData.grid_size,
			(bp.y - min_pos.y) * GameData.grid_size
		) - center_offset
		var global_pos = ship_center_body.position + rel
		var block = _create_ship_block(global_pos)
		block_map[bp] = block
		ship_blocks.append(block)
		
		# 存储方块的网格位置，用于断裂后重建连接
		block.set_meta("grid_pos", bp)

	# 在相邻方块间加关节
	for bp in ship_data:
		for dir in [Vector2i(1,0), Vector2i(0,1)]:
			var nb = bp + dir
			if block_map.has(nb):
				_create_block_joint(block_map[bp], block_map[nb])

func _create_ship_block(global_pos: Vector2) -> RigidBody2D:
	var b = RigidBody2D.new()
	b.position = global_pos
	b.mass = block_mass
	b.linear_damp = 2.0
	b.angular_damp = 3.0
	add_child(b)
	
	# 存储应力信息
	b.set_meta("stress", 0.0)
	b.set_meta("max_stress", 0.0)
	b.set_meta("connected_joints", [])

	# 视觉
	var spr = Sprite2D.new()
	spr.texture = load("res://assets/wood.png")
	b.add_child(spr)
	b.set_meta("sprite", spr)

	# 碰撞
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(GameData.grid_size, GameData.grid_size)
	col.shape = rect
	b.add_child(col)

	# PinJoint 连接到船心
	var pj = PinJoint2D.new()
	pj.node_a = ship_center_body.get_path()
	pj.node_b = b.get_path()
	pj.position = b.position
	pj.softness = 0.1
	add_child(pj)
	block_joints.append(pj)
	
	# 监听碰撞
	b.body_entered.connect(_on_block_hit.bind(b))

	return b

func _create_block_joint(a: RigidBody2D, b: RigidBody2D):
	var pj = PinJoint2D.new()
	pj.node_a = a.get_path()
	pj.node_b = b.get_path()
	pj.position = (a.position + b.position) * 0.5
	add_child(pj)
	block_joints.append(pj)
	
	# 记录连接关系
	joint_connections[pj] = {"block_a": a, "block_b": b}
	
	# 在方块中记录关节
	var a_joints = a.get_meta("connected_joints", [])
	a_joints.append(pj)
	a.set_meta("connected_joints", a_joints)
	
	var b_joints = b.get_meta("connected_joints", [])
	b_joints.append(pj)
	b.set_meta("connected_joints", b_joints)

func _physics_process(delta):
	
	wave_time += delta * wave_speed
	# 更新每个顶点的 y 值
	for i in range(wave_point_count):
		var x = wave_line.get_point_position(i).x
		var y = water_level + sin(wave_time + x / wave_wavelength) * wave_amplitude
		wave_line.set_point_position(i, Vector2(x, y))
	# 应用浮力
	for block in ship_blocks:
		if is_instance_valid(block):
			_apply_realistic_buoyancy(block, delta)
	
	# 检查断裂
	_check_joint_stress(delta)
	
	# 更新独立部分
	for part in ship_parts:
		for block in part.blocks:
			if is_instance_valid(block):
				_apply_realistic_buoyancy(block, delta)
	
	_update_center_mass()
	
	# 更新应力可视化
	if show_stress_debug:
		_update_stress_visualization()

func _check_joint_stress(delta):
	var joints_to_break = []
	
	# 检查每个关节的应力
	for joint in block_joints:
		if not is_instance_valid(joint) or not joint_connections.has(joint):
			continue
			
		var conn = joint_connections[joint]
		var block_a = conn.block_a
		var block_b = conn.block_b
		
		if not is_instance_valid(block_a) or not is_instance_valid(block_b):
			continue
		
		# 计算关节受力（基于两个方块的相对运动）
		var relative_vel = block_b.linear_velocity - block_a.linear_velocity
		var distance = block_b.position - block_a.position
		var stress = relative_vel.length() * 500.0  # 应力系数
		
		# 添加角速度差异的影响
		var angular_diff = abs(block_b.angular_velocity - block_a.angular_velocity)
		stress += angular_diff * 500.0
		
		# 更新方块应力信息
		block_a.set_meta("stress", stress)
		block_b.set_meta("stress", stress)
		
		# 记录最大应力
		block_a.set_meta("max_stress", max(block_a.get_meta("max_stress", 0.0), stress))
		block_b.set_meta("max_stress", max(block_b.get_meta("max_stress", 0.0), stress))
		
		# 检查是否超过断裂阈值
		if stress > joint_break_force:
			joints_to_break.append(joint)
	
	# 断开超应力的关节
	for joint in joints_to_break:
		_break_joint(joint)

func _break_joint(joint):
	if not joint_connections.has(joint):
		return
		
	var conn = joint_connections[joint]
	var block_a = conn.block_a
	var block_b = conn.block_b
	
	print("关节断裂！应力过大")
	
	# 从方块的关节列表中移除
	if is_instance_valid(block_a):
		var a_joints = block_a.get_meta("connected_joints", [])
		a_joints.erase(joint)
		block_a.set_meta("connected_joints", a_joints)
		
		# 添加断裂效果
		_add_break_effect(block_a.position)
	
	if is_instance_valid(block_b):
		var b_joints = block_b.get_meta("connected_joints", [])
		b_joints.erase(joint)
		block_b.set_meta("connected_joints", b_joints)
	
	# 移除关节
	block_joints.erase(joint)
	joint_connections.erase(joint)
	joint.queue_free()
	
	# 检查是否需要分离船只部分
	_check_ship_separation()

func _on_block_hit(other_body: Node, hit_block: RigidBody2D):
	# 当方块被撞击时
  # working in progress
	if other_body.has_method("get_impact_force"):
		var impact = other_body.get_impact_force()
		if impact > block_break_impulse:
			_destroy_block(hit_block)

func _destroy_block(block: RigidBody2D):
	print("方块被摧毁！")
	
	# 断开所有相连的关节
	var connected_joints = block.get_meta("connected_joints", [])
	for joint in connected_joints:
		if is_instance_valid(joint):
			_break_joint(joint)
	
	# 添加破坏效果
	_add_break_effect(block.position)
	
	# 移除方块
	ship_blocks.erase(block)
	block.queue_free()
	
	# 检查船只分离
	_check_ship_separation()

func _check_ship_separation():
	# 使用洪水填充算法检查连通性
  # working in progress
	pass

func _add_break_effect(pos: Vector2):
	# 创建破碎粒子效果
	var particles = CPUParticles2D.new()
	particles.position = pos
	particles.emitting = true
	particles.amount = 10
	particles.lifetime = 0.5
	particles.initial_velocity_min = 100
	particles.initial_velocity_max = 300
	particles.angular_velocity_min = -180
	particles.angular_velocity_max = 180
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	particles.color = Color(0.6, 0.4, 0.2)
	add_child(particles)
	
	# 自动清理
	particles.emitting = false
	await get_tree().create_timer(1.0).timeout
	particles.queue_free()

func _update_stress_visualization():
	# 根据应力改变方块颜色
	for block in ship_blocks:
		if not is_instance_valid(block):
			continue
			
		var sprite = block.get_meta("sprite")
		if not sprite:
			continue
			
		var stress = block.get_meta("stress", 0.0)
		var stress_ratio = clamp(stress / joint_break_force, 0.0, 1.0)
		
		# 从白色（无应力）到红色（高应力）
		var color = Color.WHITE.lerp(Color.RED, stress_ratio)
		sprite.modulate = color

func _apply_realistic_buoyancy(block: RigidBody2D, delta: float):
	var size = GameData.grid_size
	var half = size * 0.5
	var bottom_y = block.global_position.y + half
	var submerged_h = clamp(bottom_y - water_level, 0.0, size)
	if submerged_h <= 0.0:
		return
	var submerged_ratio = submerged_h / size

	# 浮力：V_disp = 面积 * 浸没高度
	var V_disp = size * size * submerged_ratio
	var Fb = water_density * V_disp * gravity
	block.apply_central_force(Vector2(0, -Fb))

	# 水中线性阻尼
	var C_d = 1.0
	var v = block.linear_velocity
	if v.length() > 0:
		var A = size * size
		var drag = -C_d * water_density * A * v.length() * v.normalized() * submerged_ratio
		block.apply_central_force(drag)

	# 水中角阻尼
	var ang_coef = 3.0
	block.angular_velocity *= 1.0 - ang_coef * submerged_ratio * delta

func _update_center_mass():
	var total = 0.0
	var com = Vector2.ZERO
	for b in ship_blocks:
		if is_instance_valid(b):
			total += b.mass
			com += b.global_position * b.mass
	if total > 0:
		com /= total
		ship_center_body.position = ship_center_body.position.lerp(com, 0.1)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		GameData.clear_ship_data()
		get_tree().change_scene_to_file("res://scenes/ship_builder.tscn")
	
	# 切换应力可视化
	if event.is_action_pressed("ui_select"):  # 空格键
		show_stress_debug = not show_stress_debug
		if not show_stress_debug:
			# 重置所有方块颜色
			for block in ship_blocks:
				if is_instance_valid(block):
					var sprite = block.get_meta("sprite")
					if sprite:
						sprite.modulate = Color.WHITE
