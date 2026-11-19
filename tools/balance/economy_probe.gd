extends RefCounted
## Conditioned stage probes, not reachable saves. Uses production preview/roll/price rules.
const Alchemy := preload("res://scripts/services/alchemy_service.gd")
const Profile := preload("res://scripts/core/profile_state.gd")
const Progression := preload("res://scripts/services/progression_service.gd")
const Lineage := preload("res://scripts/core/lineage_rules.gd")
const Rules := preload("res://scripts/core/alchemy_rules.gd")
const Context := preload("res://scripts/core/rng_context.gd")
const Shop := preload("res://scripts/services/shop_service.gd")
const Pills := preload("res://scripts/core/pill_stack.gd")
const STYLES := ["stable", "rush", "recycle", "research"]
const RARE_SOURCES := {"herb_lingzhi": ["event_old_grove", "choice_trade"], "essence_hunlu": ["event_soul_spring", "choice_offer"]}


static func setup(db: RefCounted, state: Dictionary, recipe_id: String, style: String) -> Dictionary:
	if style == "recycle_smart":
		var selected := setup(db, state, recipe_id, "recycle")
		var advice := refund_advice(db, state, recipe_id, selected)
		if not advice.ok or not advice.recommended: selected.consumable_id = ""
		return selected
	var recipe: Dictionary = db.get_item(recipe_id)
	var furnace := "furnace_basic"
	if "furnace_qingmu" in state.owned_furnaces:
		furnace = "furnace_qingmu"
	if style == "rush" and "fire" in recipe.tags and "furnace_chiyan" in state.owned_furnaces:
		furnace = "furnace_chiyan"
	var flame := "flame_earth" if "flame_earth" in state.owned_flames else "flame_normal"
	if Lineage.world(db, state, "suppress_special_flames", false):
		flame = "flame_normal"
	return {"furnace_id": furnace, "flame_id": flame, "strategy": "rush" if style == "rush" else "stable", "consumable_id": "consumable_hulu" if style == "recycle" and state.rank >= 1 else ""}


static func refund_advice(db: RefCounted, state: Dictionary, recipe_id: String, selected: Dictionary) -> Dictionary:
	var plain := selected.duplicate()
	plain.consumable_id = ""
	var guarded := plain.duplicate()
	guarded.consumable_id = "consumable_hulu"
	var alchemy := Alchemy.new(db)
	var a := alchemy.preview_alchemy(state, recipe_id, plain)
	var b := alchemy.preview_alchemy(state, recipe_id, guarded)
	if not a.ok or not b.ok: return {"ok": false, "recommended": false}
	var extra_value := 0.0
	var quantities: Dictionary = {}
	for id in b.result.failure_returns:
		var delta: int = b.result.failure_returns[id] - a.result.failure_returns.get(id, 0)
		if delta <= 0: continue
		var basis := unit_basis(db, state, id)
		if basis.stones == null: return {"ok": false, "recommended": false}
		extra_value += delta * basis.stones
		quantities[id] = delta
	var price_value: int = db.get_item("consumable_hulu").unlock.price
	var gross: float = (1.0 - a.result.success_rate) * extra_value
	var available: bool = state.rank >= db.get_item("consumable_hulu").unlock.required_rank
	return {"ok": true, "recommended": available and gross > price_value, "available": available, "expected_extra_material_value": gross, "jade_price": price_value, "expected_net_delta": gross - price_value, "extra_failure_returns": quantities}


static func unit_basis(db: RefCounted, state: Dictionary, id: String) -> Dictionary:
	var item: Dictionary = db.get_item(id)
	if item.get("shop_available", false):
		return {"stones": float(Lineage.buy_price(db, state, item, item.buy_price)), "outings": 0.0}
	if not RARE_SOURCES.has(id):
		return {"stones": null, "outings": null}
	var source: Array = RARE_SOURCES[id]
	for original in db.get_item(source[0]).options:
		if original.id == source[1]:
			var option := Lineage.option(db, state, source[0], original)
			var amount: int = option.success_items[id]
			return {"stones": float(option.cost_stones) / amount, "outings": 1.0 / amount}
	return {"stones": null, "outings": null}


static func price(db: RefCounted, recipe_id: String, quality: String) -> int:
	return int(db.get_item(recipe_id).base_sell_price * Shop.QUALITY_NUMERATORS[quality] / 2)


static func fixture(db: RefCounted, target: int, style: String, loadout: Array, worlds: Array) -> Dictionary:
	var number := 3 if loadout.size() > 1 else (1 if worlds.is_empty() else 2)
	var state: Dictionary = Profile.new(db).create_run(1, number, loadout, worlds).result.state
	state.rank = target - 1
	state.unlocked_recipes = db.get_ids("recipes")
	if state.rank >= 1:
		state.owned_furnaces.append("furnace_qingmu")
		state.owned_furnaces.append("furnace_chiyan")
		state.owned_flames.append("flame_earth")
	for rank_index in [3, 6, 9]:
		if rank_index <= state.rank:
			state.talent_choices.append("talent_%s_%d" % ["stable" if style in ["recycle", "recycle_smart"] else style, rank_index])
	return state


static func analyze(db: RefCounted, state: Dictionary, recipe_id: String, style: String, min_quality: String, samples: int, seed_value: int) -> Dictionary:
	var view := Alchemy.new(db).preview_alchemy(state, recipe_id, setup(db, state, recipe_id, style))
	if not view.ok:
		return {"ok": false, "error": view.message}
	var snapshot: Dictionary = view.result
	var cost := 0.0
	var return_value := 0.0
	var outings := 0.0
	var returned_outings := 0.0
	for id in snapshot.materials:
		var basis := unit_basis(db, state, id)
		if basis.stones == null:
			return {"ok": false, "error": "No priced deterministic source: " + id}
		cost += basis.stones * snapshot.materials[id]
		outings += basis.outings * snapshot.materials[id]
		return_value += basis.stones * snapshot.failure_returns.get(id, 0)
		returned_outings += basis.outings * snapshot.failure_returns.get(id, 0)
	for id in snapshot.consumables:
		cost += db.get_item(id).unlock.price * snapshot.consumables[id]
	var residue := Lineage.sell_price(db, state, "material_danzha", db.get_item("material_danzha").sell_price)
	var mean_sale := 0.0
	var eligible := 0.0
	var best := 0
	var prices: Dictionary = {}
	for quality in Pills.QUALITIES:
		prices[quality] = price(db, recipe_id, quality)
		mean_sale += snapshot.quality_probabilities[quality] * prices[quality]
		if Pills.QUALITIES.find(quality) >= Pills.QUALITIES.find(min_quality):
			eligible += snapshot.quality_probabilities[quality]
		best = maxi(best, prices[quality])
	var p: float = snapshot.success_rate
	var extra: float = snapshot.extra_pill_chance
	var expected_sale := p * mean_sale * (1 + extra) + (1 - p) * residue
	var expected_net := expected_sale + (1 - p) * return_value - cost
	var qualifying_p := p * eligible
	var rng := Context.new(seed_value)
	var total := 0.0
	var total2 := 0.0
	var success := 0
	var qualified := 0
	var negatives := 0
	var qualities := {"common": 0, "good": 0, "superior": 0, "legendary": 0}
	var values: Array[float] = []
	for index in range(samples):
		var outcome := Rules.roll(snapshot, rng)
		var net := -cost
		if outcome.success:
			success += 1
			qualities[outcome.quality] += 1
			net += prices[outcome.quality] * outcome.quantity
			if Pills.QUALITIES.find(outcome.quality) >= Pills.QUALITIES.find(min_quality): qualified += 1
		else:
			net += residue + return_value
		if net < 0: negatives += 1
		total += net
		total2 += net * net
		values.append(net)
	values.sort()
	var observed := total / samples
	var sd := sqrt(maxf(total2 / samples - observed * observed, 0.0))
	# Hoeffding's bounded-mean interval, alpha=1e-6, valid even for rare jackpots.
	var bound := best * (2 if extra > 0 else 1) + residue + return_value
	var tolerance := bound * sqrt(log(2000000.0) / (2.0 * samples))
	var frequencies_valid := _frequency(p, success, samples, 0.01)
	for quality in Pills.QUALITIES:
		frequencies_valid = frequencies_valid and _frequency(snapshot.quality_probabilities[quality], qualities[quality], success)
	return {"ok": true, "recipe": recipe_id, "rank": state.rank, "style": style, "setup": snapshot.setup, "samples": samples, "success_probability": p, "observed_success": float(success) / samples, "conditional_quality_counts": qualities, "quality_expected": snapshot.quality_probabilities, "frequencies_within_bounds": frequencies_valid, "eligible_probability": qualifying_p, "observed_eligible": float(qualified) / samples, "expected_attempts_for_exam_pill": 1.0 / qualifying_p if qualifying_p > 0 else null, "no_exam_pill_after_8": pow(1.0 - qualifying_p, 8), "input_cost": cost, "failure_material_value": return_value, "rare_outings_per_attempt": outings - (1 - p) * returned_outings, "expected_net": expected_net, "observed_net": observed, "sample_sd": sd, "mean_tolerance": tolerance, "mean_within_bound": absf(observed - expected_net) <= tolerance, "net_p10": percentile(values, 0.1), "net_p50": percentile(values, 0.5), "net_p90": percentile(values, 0.9), "loss_frequency": float(negatives) / samples}


static func _frequency(probability: float, count: int, samples: int, minimum: float = 0.0) -> bool:
	if samples <= 0: return false
	if probability == 0: return count == 0
	if probability == 1: return count == samples
	var tolerance := maxf(minimum, maxf(1.0 / samples, 6.0 * sqrt(probability * (1.0 - probability) / samples)))
	return absf(float(count) / samples - probability) <= tolerance


static func percentile(sorted_values: Array, fraction: float) -> float:
	if sorted_values.is_empty(): return 0.0
	return float(sorted_values[clampi(int(ceil(fraction * sorted_values.size())) - 1, 0, sorted_values.size() - 1)])
