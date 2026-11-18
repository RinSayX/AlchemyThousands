class_name RNGContext
extends RefCounted
## Three dedicated streams. Decimal strings preserve int64 through JSON.

const Result := preload("res://scripts/core/transaction_result.gd")
const ENGINE_VERSION := "4.5.stable.official.876b29033"
const SALTS := {"alchemy": 0x1a2b3c4d, "exploration": 0x5e6f7081, "world": 0x2468ace0}
var _streams: Dictionary = {}


func _init(seed_value: int = 1) -> void:
	for stream in SALTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value ^ SALTS[stream]
		_streams[stream] = rng


func next_float(stream: String = "alchemy") -> float:
	assert(_streams.has(stream), "Unknown RNG stream")
	# randf() includes 1.0 in this engine; use an exact half-open interval.
	return float(_streams[stream].randi()) / 4294967296.0


func snapshot() -> Dictionary:
	var streams: Dictionary = {}
	for stream in SALTS:
		streams[stream] = {"seed": str(_streams[stream].seed), "state": str(_streams[stream].state)}
	return {"schema_version": 1, "engine_version": ENGINE_VERSION, "streams": streams}


func restore(value: Variant) -> Dictionary:
	if not valid_snapshot(value):
		return Result.failure("INVALID_RNG_STATE", "随机流快照格式、版本或整数不合法。")
	for stream in SALTS:
		_streams[stream].seed = value.streams[stream].seed.to_int()
		_streams[stream].state = value.streams[stream].state.to_int()
	return Result.success()


static func valid_snapshot(value: Variant) -> bool:
	var engine := Engine.get_version_info()
	if engine.major != 4 or engine.minor != 5 or engine.patch != 0 or engine.status != "stable" or not str(engine.hash).begins_with("876b29033"):
		return false
	if not value is Dictionary or value.size() != 3:
		return false
	var version: Variant = value.get("schema_version")
	if not (version is int or version is float) or version != 1 or not value.get("engine_version") is String or value.engine_version != ENGINE_VERSION:
		return false
	var streams: Variant = value.get("streams")
	if not streams is Dictionary or streams.size() != 3:
		return false
	for stream in SALTS:
		var entry: Variant = streams.get(stream)
		if not entry is Dictionary or entry.size() != 2 or not _decimal_int64(entry.get("seed")) or not _decimal_int64(entry.get("state")):
			return false
	return true


static func _decimal_int64(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(value.to_int()) == value
