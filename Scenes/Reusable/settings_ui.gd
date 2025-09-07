extends Control

func _ready() -> void:
	_dump_hierarchy(self, "user://settings_ui_tree.txt")

func _dump_hierarchy(root: Node, path: String) -> void:
	var lines: Array[String] = []
	_walk_node(root, 0, lines)

	DirAccess.make_dir_recursive_absolute("user://")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
		print("Node hierarchy written to: ", path)

func _walk_node(n: Node, depth: int, lines: Array[String]) -> void:
	lines.append("%s%s [%s]" % ["\t".repeat(depth), n.name, n.get_class()])
	for c in n.get_children():
		_walk_node(c, depth + 1, lines)
