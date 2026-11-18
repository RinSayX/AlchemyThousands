extends "res://scripts/core/rng_context.gd"
## Test-only scripted draws. Production execution never accepts injected rolls.

var values: Array
var calls := 0


func _init(draws: Array) -> void:
	super(1)
	values = draws


func next_float(stream: String = "alchemy") -> float:
	assert(stream == "alchemy" and calls < values.size())
	var value: float = values[calls]
	calls += 1
	return value
