extends Label


func _process(_delta: float) -> void:
	text = "Boids: " + str(BoidBase.boid_count)
