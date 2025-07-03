# GameData.gd
extends Node

# 存储船只数据
var ship_blocks: Array[Vector2i] = []

# 游戏设置
var grid_size: int = 32

# 清空数据
func clear_ship_data():
	ship_blocks.clear()

# 设置船只数据
func set_ship_data(blocks: Array[Vector2i]):
	ship_blocks = blocks.duplicate()

# 获取船只数据
func get_ship_data() -> Array[Vector2i]:
	return ship_blocks
