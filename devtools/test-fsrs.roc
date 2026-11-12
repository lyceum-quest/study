app [main!] {
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
}

import pf.Path
import pf.Stderr
import pf.Stdout
import fsrs.Fsrs
import fsrs.FsrsMath
import json.JsonValue

# Checks the Roc FSRS package (packages/fsrs/) against reference outputs from
# ts-fsrs 5.4.2 (exact equality), fsrs-rs 6.6.2 (within f32 tolerance) and V8's
# Math.exp (bit for bit), as tests/FsrsTest.elm does for the Elm port. See
# tests/fixtures/fsrs/README.md. Prints a summary and the first mismatches, and
# exits with 1 if any check fails.
main! = |_args| {
	match load!({}) {
		Err(message) => {
			Stderr.line!("Could not read tests/fixtures/fsrs/: ${message}")?
			Err(Exit(1))
		}
		Ok(fixtures) => {
			groups = [
				("default weights", [check_default_weights(fixtures.ts)]),
				("configurations (clipped weights and interval modifier)", fixtures.ts.configs.map(check_config)),
				("ts-fsrs 5.4.2 review sequences (exact)", fixtures.ts.cases.map(|ts_case| check_ts_case(fixtures.ts.configs, ts_case))),
				("fsrs-rs 6.6.2 memory states (f32 tolerance)", fixtures.rs_cases.keep_oks(|rs_case| check_rs_case(fixtures.ts, rs_case))),
				("FsrsMath.exp equals V8 Math.exp", fixtures.exp_cases.map(check_exp)),
			]
			var $failures = []
			for (title, checks) in groups {
				failed = checks.keep_if(|check| check.problem != "")
				Stdout.line!("${(checks.len() - failed.len()).to_str()}/${checks.len().to_str()} ${title}")?
				$failures = $failures.concat(failed)
			}
			if $failures.is_empty() {
				Stdout.line!("All FSRS checks pass.")?
				Ok({})
			} else {
				Stdout.line!("\n${$failures.len().to_str()} checks failed; the first ${shown_failures.min($failures.len()).to_str()}:")?
				for check in $failures.take_first(shown_failures) {
					Stdout.line!("\n${check.name}\n${check.problem}")?
				}
				Err(Exit(1))
			}
		}
	}
}

shown_failures : U64
shown_failures = 10

# A named check; `problem` is "" when it passes.
Check : { name : Str, problem : Str }

# FIXTURE TYPES

TsFixture : {
	default_weights : List(F64),
	configs : List((Str, TsConfig)),
	cases : List(TsCase),
}

TsConfig : {
	config : Fsrs.Config,
	clipped_weights : List(F64),
	interval_modifier : F64,
}

TsCase : {
	name : Str,
	config : Str,
	start : I64,
	reviews : List(TsReview),
	probes : List((I64, F64)),
}

TsReview : {
	time : I64,
	rating : Fsrs.Rating,
	retrievability : F64,
	outcomes : Outcomes(Fsrs.Card),
	log : Fsrs.ReviewLog,
}

Outcomes(a) : { again : a, hard : a, good : a, easy : a }

RsCase : {
	name : Str,
	reviews : List(RsReview),
}

RsReview : {
	elapsed_days : I64,
	retrievability : [Some(F64), None],
	outcomes : Outcomes(RsState),
}

RsState : { stability : F64, difficulty : F64, interval : F64 }

# LOADING

load! : {} => Try({ ts : TsFixture, rs_cases : List(RsCase), exp_cases : List((F64, F64)) }, Str)
load! = |{}| {
	ts_json = read_json!("ts-fsrs.json")?
	rs_json = read_json!("fsrs-rs.json")?
	exp_json = read_json!("math-exp.json")?
	ts = decode_ts_fixture(ts_json).map_err(|message| "ts-fsrs.json: ${message}")?
	rs_cases = decode_list(JsonValue.field(rs_json, "cases")?, decode_rs_case).map_err(|message| "fsrs-rs.json: ${message}")?
	exp_cases = decode_list(JsonValue.field(exp_json, "cases")?, |pair| Ok((JsonValue.as_f64(at(pair, 0)?)?, JsonValue.as_f64(at(pair, 1)?)?))).map_err(|message| "math-exp.json: ${message}")?
	Ok({ ts, rs_cases, exp_cases })
}

read_json! : Str => Try(JsonValue, Str)
read_json! = |name| {
	path = "tests/fixtures/fsrs/${name}"
	text = Path.read_utf8!(Path.utf8(path)).map_err(|_| "cannot read ${path}")?
	JsonValue.decode(text).map_err(|message| "${name}: ${message}")
}

# DECODERS

decode_list : JsonValue, (JsonValue -> Try(a, Str)) -> Try(List(a), Str)
decode_list = |json, decode_item| {
	var $decoded = []
	for item in JsonValue.items(json)? {
		$decoded = $decoded.append(decode_item(item)?)
	}
	Ok($decoded)
}

# The `index`th element of a JSON array.
at : JsonValue, U64 -> Try(JsonValue, Str)
at = |json, index| JsonValue.items(json)?.get(index).map_err(|_| "missing array element ${index.to_str()}")

f64_field : JsonValue, Str -> Try(F64, Str)
f64_field = |json, name| JsonValue.as_f64(JsonValue.field(json, name)?)

i64_field : JsonValue, Str -> Try(I64, Str)
i64_field = |json, name| JsonValue.as_i64(JsonValue.field(json, name)?)

str_field : JsonValue, Str -> Try(Str, Str)
str_field = |json, name| JsonValue.as_str(JsonValue.field(json, name)?)

f64_list : JsonValue -> Try(List(F64), Str)
f64_list = |json| decode_list(json, JsonValue.as_f64)

decode_ts_fixture : JsonValue -> Try(TsFixture, Str)
decode_ts_fixture = |json| {
	default_weights = f64_list(JsonValue.field(json, "default_w")?)?
	var $configs = []
	for (name, config_json) in JsonValue.fields(JsonValue.field(json, "configs")?) {
		$configs = $configs.append((name, decode_config(config_json).map_err(|message| "config ${name}: ${message}")?))
	}
	cases = decode_list(JsonValue.field(json, "cases")?, decode_ts_case)?
	Ok({ default_weights, configs: $configs, cases })
}

decode_config : JsonValue -> Try(TsConfig, Str)
decode_config = |json| {
	config = {
		request_retention: f64_field(json, "request_retention")?,
		maximum_interval: i64_field(json, "maximum_interval")?,
		weights: f64_list(JsonValue.field(json, "w")?)?,
		enable_fuzz: JsonValue.as_bool(JsonValue.field(json, "enable_fuzz")?)?,
		enable_short_term: JsonValue.as_bool(JsonValue.field(json, "enable_short_term")?)?,
		learning_steps: decode_list(JsonValue.field(json, "learning_steps")?, decode_step)?,
		relearning_steps: decode_list(JsonValue.field(json, "relearning_steps")?, decode_step)?,
	}
	Ok({
		config,
		clipped_weights: f64_list(JsonValue.field(json, "clipped_w")?)?,
		interval_modifier: f64_field(json, "interval_modifier")?,
	})
}

# ts-fsrs step strings: "10m", "1h", "2d".
decode_step : JsonValue -> Try(Fsrs.Step, Str)
decode_step = |json| {
	text = JsonValue.as_str(json)?
	bytes = text.to_utf8()
	count = I64.from_str(Str.from_utf8(bytes.drop_last(1)) ?? "").map_err(|_| "bad step ${text}")?
	match bytes.last() {
		Ok('m') => Ok(Minutes(count))
		Ok('h') => Ok(Hours(count))
		Ok('d') => Ok(Days(count))
		_ => Err("bad step ${text}")
	}
}

decode_rating : JsonValue -> Try(Fsrs.Rating, Str)
decode_rating = |json| match JsonValue.as_str(json)? {
	"Again" => Ok(Again)
	"Hard" => Ok(Hard)
	"Good" => Ok(Good)
	"Easy" => Ok(Easy)
	other => Err("bad rating ${other}")
}

decode_state : JsonValue -> Try(Fsrs.State, Str)
decode_state = |json| match JsonValue.as_str(json)? {
	"New" => Ok(New)
	"Learning" => Ok(Learning)
	"Review" => Ok(Review)
	"Relearning" => Ok(Relearning)
	other => Err("bad state ${other}")
}

decode_ts_case : JsonValue -> Try(TsCase, Str)
decode_ts_case = |json| {
	name = str_field(json, "name")?
	Ok({
		name,
		config: str_field(json, "config")?,
		start: i64_field(json, "start")?,
		reviews: decode_list(JsonValue.field(json, "reviews")?, decode_ts_review).map_err(|message| "case ${name}: ${message}")?,
		probes: decode_list(JsonValue.field(json, "probes")?, |probe| Ok((i64_field(probe, "time")?, f64_field(probe, "retrievability")?)))?,
	})
}

decode_ts_review : JsonValue -> Try(TsReview, Str)
decode_ts_review = |json| {
	outcomes = JsonValue.field(json, "outcomes")?
	Ok({
		time: i64_field(json, "time")?,
		rating: decode_rating(JsonValue.field(json, "rating")?)?,
		retrievability: f64_field(json, "retrievability")?,
		outcomes: {
			again: decode_card(JsonValue.field(outcomes, "Again")?)?,
			hard: decode_card(JsonValue.field(outcomes, "Hard")?)?,
			good: decode_card(JsonValue.field(outcomes, "Good")?)?,
			easy: decode_card(JsonValue.field(outcomes, "Easy")?)?,
		},
		log: decode_log(JsonValue.field(json, "log")?)?,
	})
}

# `[due, stability, difficulty, elapsed_days, scheduled_days, learning_steps, reps, lapses, state, last_review]`
decode_card : JsonValue -> Try(Fsrs.Card, Str)
decode_card = |json| {
	last_review = at(json, 9)?
	Ok({
		due: JsonValue.as_i64(at(json, 0)?)?,
		stability: JsonValue.as_f64(at(json, 1)?)?,
		difficulty: JsonValue.as_f64(at(json, 2)?)?,
		elapsed_days: JsonValue.as_i64(at(json, 3)?)?,
		scheduled_days: JsonValue.as_i64(at(json, 4)?)?,
		learning_steps: JsonValue.as_i64(at(json, 5)?)?,
		reps: JsonValue.as_i64(at(json, 6)?)?,
		lapses: JsonValue.as_i64(at(json, 7)?)?,
		state: decode_state(at(json, 8)?)?,
		last_review: if (JsonValue.is_null(last_review)) None else Some(JsonValue.as_i64(last_review)?),
	})
}

# `[rating, state, due, stability, difficulty, elapsed_days, last_elapsed_days, scheduled_days, learning_steps, review]`
decode_log : JsonValue -> Try(Fsrs.ReviewLog, Str)
decode_log = |json| Ok({
	rating: decode_rating(at(json, 0)?)?,
	state: decode_state(at(json, 1)?)?,
	due: JsonValue.as_i64(at(json, 2)?)?,
	stability: JsonValue.as_f64(at(json, 3)?)?,
	difficulty: JsonValue.as_f64(at(json, 4)?)?,
	elapsed_days: JsonValue.as_i64(at(json, 5)?)?,
	last_elapsed_days: JsonValue.as_i64(at(json, 6)?)?,
	scheduled_days: JsonValue.as_i64(at(json, 7)?)?,
	learning_steps: JsonValue.as_i64(at(json, 8)?)?,
	review: JsonValue.as_i64(at(json, 9)?)?,
})

decode_rs_case : JsonValue -> Try(RsCase, Str)
decode_rs_case = |json| Ok({ name: str_field(json, "name")?, reviews: decode_list(JsonValue.field(json, "reviews")?, decode_rs_review)? })

decode_rs_review : JsonValue -> Try(RsReview, Str)
decode_rs_review = |json| {
	retrievability = JsonValue.field(json, "retrievability")?
	outcomes = JsonValue.field(json, "outcomes")?
	Ok({
		elapsed_days: i64_field(json, "elapsed_days")?,
		retrievability: if (JsonValue.is_null(retrievability)) None else Some(JsonValue.as_f64(retrievability)?),
		outcomes: {
			again: decode_rs_state(at(outcomes, 0)?)?,
			hard: decode_rs_state(at(outcomes, 1)?)?,
			good: decode_rs_state(at(outcomes, 2)?)?,
			easy: decode_rs_state(at(outcomes, 3)?)?,
		},
	})
}

# `[stability, difficulty, interval]`
decode_rs_state : JsonValue -> Try(RsState, Str)
decode_rs_state = |json| Ok({
	stability: JsonValue.as_f64(at(json, 0)?)?,
	difficulty: JsonValue.as_f64(at(json, 1)?)?,
	interval: JsonValue.as_f64(at(json, 2)?)?,
})

# CHECKS

pass : Str -> Check
pass = |name| { name, problem: "" }

check_default_weights : TsFixture -> Check
check_default_weights = |ts| {
	name = "default weights match ts-fsrs default_w"
	if ts.default_weights == Fsrs.default_weights {
		pass(name)
	} else {
		{ name, problem: "${Str.inspect(Fsrs.default_weights)} /= ${Str.inspect(ts.default_weights)}" }
	}
}

check_config : (Str, TsConfig) -> Check
check_config = |(name, ts_config)| match Fsrs.scheduler(ts_config.config) {
	Err(message) => { name: "config ${name}", problem: message }
	Ok(configured) => {
		if Fsrs.weights(configured) != ts_config.clipped_weights {
			{ name: "config ${name}", problem: "clipped weights ${Str.inspect(Fsrs.weights(configured))} /= ${Str.inspect(ts_config.clipped_weights)}" }
		} else if Fsrs.interval_modifier(configured) != ts_config.interval_modifier {
			{ name: "config ${name}", problem: "interval modifier ${show(Fsrs.interval_modifier(configured))} /= expected ${show(ts_config.interval_modifier)}" }
		} else {
			pass("config ${name}")
		}
	}
}

scheduler_for : List((Str, TsConfig)), Str -> Try(Fsrs.Scheduler, Str)
scheduler_for = |configs, name| match configs.keep_if(|(config_name, _)| config_name == name) {
	[(_, ts_config), ..] => Fsrs.scheduler(ts_config.config)
	[] => Err("unknown config ${name}")
}

pick : Fsrs.Rating, Outcomes(a) -> a
pick = |rating, outcomes| match rating {
	Again => outcomes.again
	Hard => outcomes.hard
	Good => outcomes.good
	Easy => outcomes.easy
}

# Replay a ts-fsrs case: at every review the retrievability, all four
# candidate cards, and the chosen review log must equal ts-fsrs exactly.
check_ts_case : List((Str, TsConfig)), TsCase -> Check
check_ts_case = |configs, ts_case| {
	problem = match replay_ts_case(configs, ts_case) {
		Ok({}) => ""
		Err(message) => message
	}
	{ name: ts_case.name, problem }
}

replay_ts_case : List((Str, TsConfig)), TsCase -> Try({}, Str)
replay_ts_case = |configs, ts_case| {
	configured = scheduler_for(configs, ts_case.config)?
	var $card = Fsrs.new_card(ts_case.start)
	for (index, review) in indexed(ts_case.reviews) {
		position = "review ${index.to_str()}: "
		recall = Fsrs.retrievability(configured, review.time, $card)
		if recall != review.retrievability {
			return Err("${position}retrievability ${show(recall)} /= ${show(review.retrievability)}")
		}
		outcomes = Fsrs.preview(configured, review.time, $card).map_err(|message| "${position}${message}")?
		cards = { again: outcomes.again.card, hard: outcomes.hard.card, good: outcomes.good.card, easy: outcomes.easy.card }
		chosen = pick(review.rating, outcomes)
		if cards != review.outcomes {
			return Err("${position}cards\n  roc:     ${Str.inspect(cards)}\n  ts-fsrs: ${Str.inspect(review.outcomes)}")
		}
		if chosen.log != review.log {
			return Err("${position}log\n  roc:     ${Str.inspect(chosen.log)}\n  ts-fsrs: ${Str.inspect(review.log)}")
		}
		outcome = Fsrs.next(configured, review.time, review.rating, $card).map_err(|message| "${position}${message}")?
		if outcome != chosen {
			return Err("${position}next differs from preview")
		}
		$card = outcome.card
	}
	problems = ts_case.probes.keep_oks(
		|(time, expected)| {
			recall = Fsrs.retrievability(configured, time, $card)
			if (recall == expected) Err({}) else Ok("probe at ${time.to_str()}: ${show(recall)} /= ${show(expected)}")
		},
	)
	if (problems.is_empty()) Ok({}) else Err(Str.join_with(problems, "\n"))
}

# FSRS-RS

# fsrs-rs computes in f32 without ts-fsrs's 8-decimal rounding. Over the
# fixture sequences the largest differences from ts-fsrs are about 5.1e-6
# (relative stability and interval), 5.5e-6 (absolute difficulty), and 1.7e-7
# (absolute retrievability); these tolerances leave a margin of about 4x.
stability_tolerance : F64
stability_tolerance = 2.0e-5

difficulty_tolerance : F64
difficulty_tolerance = 2.0e-5

retrievability_tolerance : F64
retrievability_tolerance = 1.0e-6

# Configurations position fsrs-rs is known to diverge from ts-fsrs (documented
# in tests/fixtures/fsrs/README.md): its parameter clipping differs for
# out-of-range weights and more than one relearning step.
rs_divergent_configs : List(Str)
rs_divergent_configs = ["clipped-w"]

# Err({}) for a case in a divergent configuration, which is skipped.
check_rs_case : TsFixture, RsCase -> Try(Check, {})
check_rs_case = |ts, rs_case| match ts.cases.keep_if(|ts_case| ts_case.name == rs_case.name) {
	[ts_case] =>
		if rs_divergent_configs.contains(ts_case.config) {
			Err({})
		} else {
			problem = match compare_rs_case(ts.configs, ts_case, rs_case) {
				Ok({}) => ""
				Err(message) => message
			}
			Ok({ name: rs_case.name, problem })
		}
	_ => Ok({ name: rs_case.name, problem: "no matching ts-fsrs case" })
}

relative_close : F64, F64, F64 -> Bool
relative_close = |tolerance, a, b| (a - b).abs() <= tolerance * b.abs()

absolute_close : F64, F64, F64 -> Bool
absolute_close = |tolerance, a, b| (a - b).abs() <= tolerance

check_rs_outcome : Fsrs.Scheduler, Str, Str, Fsrs.Card, RsState -> [Some(Str), None]
check_rs_outcome = |configured, position, label, card, rs| {
	interval = card.stability * Fsrs.interval_modifier(configured)
	if !relative_close(stability_tolerance, card.stability, rs.stability) {
		Some("${position}${label} stability ${show(card.stability)} vs ${show(rs.stability)}")
	} else if !absolute_close(difficulty_tolerance, card.difficulty, rs.difficulty) {
		Some("${position}${label} difficulty ${show(card.difficulty)} vs ${show(rs.difficulty)}")
	} else if !relative_close(stability_tolerance, interval, rs.interval) {
		Some("${position}${label} interval ${show(interval)} vs ${show(rs.interval)}")
	} else {
		None
	}
}

compare_rs_case : List((Str, TsConfig)), TsCase, RsCase -> Try({}, Str)
compare_rs_case = |configs, ts_case, rs_case| {
	configured = scheduler_for(configs, ts_case.config)?
	if ts_case.reviews.len() != rs_case.reviews.len() {
		return Err("review counts differ")
	}
	var $card = Fsrs.new_card(ts_case.start)
	for (index, (review, rs_review)) in indexed(List.map2(ts_case.reviews, rs_case.reviews, |review, rs_review| (review, rs_review))) {
		position = "review ${index.to_str()}: "
		retrievability_problem = match rs_review.retrievability {
			Some(rs_recall) => {
				recall = Fsrs.forgetting_curve(configured, rs_review.elapsed_days.to_f64(), $card.stability)
				if (absolute_close(retrievability_tolerance, recall, rs_recall)) None else Some("${position}retrievability ${show(recall)} vs ${show(rs_recall)}")
			}
			None => None
		}
		outcomes = Fsrs.preview(configured, review.time, $card).map_err(|message| "${position}${message}")?
		problems = [
			retrievability_problem,
			if (outcomes.again.log.elapsed_days != rs_review.elapsed_days) Some("${position}elapsed days differ") else None,
			check_rs_outcome(configured, position, "Again", outcomes.again.card, rs_review.outcomes.again),
			check_rs_outcome(configured, position, "Hard", outcomes.hard.card, rs_review.outcomes.hard),
			check_rs_outcome(configured, position, "Good", outcomes.good.card, rs_review.outcomes.good),
			check_rs_outcome(configured, position, "Easy", outcomes.easy.card, rs_review.outcomes.easy),
		].keep_oks(
			|problem| match problem {
				Some(message) => Ok(message)
				None => Err({})
			},
		)
		if !problems.is_empty() {
			return Err(Str.join_with(problems, "\n"))
		}
		$card = pick(review.rating, outcomes).card
	}
	Ok({})
}

# `FsrsMath.exp` must equal V8's `Math.exp` bit for bit.
check_exp : (F64, F64) -> Check
check_exp = |(argument, expected)| {
	actual = FsrsMath.exp(argument)
	name = "exp(${show(argument)})"
	if (actual.to_bits() == expected.to_bits()) pass(name) else { name, problem: "${show(actual)} /= expected ${show(expected)}" }
}

# HELPERS

indexed : List(a) -> List((U64, a))
indexed = |items| {
	var $pairs = []
	for item in items {
		$pairs = $pairs.append(($pairs.len(), item))
	}
	$pairs
}

# Numbers as JavaScript prints them, as in the Elm test's messages.
show : F64 -> Str
show = |x| FsrsMath.to_js_str(x)
