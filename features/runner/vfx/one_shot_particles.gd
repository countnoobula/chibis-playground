class_name OneShotParticles
extends GPUParticles3D

## Self-freeing one-shot burst particle helper for DustPuff, FlowSparkle, SuperBounceWind.


func _ready() -> void:
	one_shot = true
	emitting = true
	finished.connect(queue_free)
