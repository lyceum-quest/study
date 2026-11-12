import FsrsMath

## FSRS (Free Spaced Repetition Scheduler) card scheduling, ported from
## [ts-fsrs](https://github.com/open-spaced-repetition/ts-fsrs) **v5.4.2**
## (tag `v5.4.2`, commit `bb71e35a2f5af5a5ac6cce9ef7c41ad24855721d`, npm
## `ts-fsrs@5.4.2`), which implements FSRS-6, by way of the Elm port in
## `src/Fsrs.elm`, which this module translates function for function. Only the
## scheduler is ported; the parameter optimizer, `rollback`, `forget`,
## `reschedule`, and the FSRS-4/5 parameter migration (17 or 19 weights) are not.
##
## The port follows ts-fsrs operation by operation, including its rounding: the
## decay factor, interval modifier, retrievability, difficulty, and stability are
## rounded to 8 decimal places with `Math.round(x * 1e8) / 1e8`, and intervals
## with `Math.round`, as ts-fsrs does. `FsrsMath` reproduces the JavaScript
## `Math.exp`, `Math.log`, `Math.pow`, `Math.round`, `Math.floor` and
## number-to-string that ts-fsrs relies on, so given the same inputs the results
## equal ts-fsrs's exactly (`devtools/test-fsrs.roc` asserts exact equality).
##
## Time is an `I64` of milliseconds since the Unix epoch (UTC), like
## `Date.getTime()`. As in ts-fsrs, the elapsed days used by `next` count UTC
## calendar days between the last review and now, while `retrievability` counts
## whole 24-hour periods.
##
## Fuzz is off by default, as in ts-fsrs. When enabled it is deterministic: like
## ts-fsrs's default seed strategy, the seed is
## `"<review time>_<reps after this review>_<difficulty * stability>"`, fed to
## the Alea generator (Johannes Baagøe, MIT), which is ported here exactly.
##
## Differences from ts-fsrs's API: `scheduler` returns an `Err` where ts-fsrs's
## constructor throws (weights must have exactly 21 finite values; retention must
## be in (0, 1]); `next` and `preview` return an `Err` where ts-fsrs throws (a
## review time on an earlier UTC day than the last review, or an invalid memory
## state). A non-new card without a last review time is treated as reviewed now
## (ts-fsrs throws "Invalid date" from `get_retrievability` in that case).
##
## ts-fsrs license:
##
##     MIT License
##
##     Copyright (c) 2026 Open Spaced Repetition
##
##     Permission is hereby granted, free of charge, to any person obtaining a copy
##     of this software and associated documentation files (the "Software"), to deal
##     in the Software without restriction, including without limitation the rights
##     to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
##     copies of the Software, and to permit persons to whom the Software is
##     furnished to do so, subject to the following conditions:
##
##     The above copyright notice and this permission notice shall be included in all
##     copies or substantial portions of the Software.
##
##     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
##     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
##     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
##     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
##     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
##     OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
##     SOFTWARE.
##
## Alea (ported via ts-fsrs `src/alea.ts`) license: Copyright (C) 2010 by
## Johannes Baagøe, under the same MIT terms as above.
Fsrs := [].{

	## A review grade (ts-fsrs `Rating.Again` .. `Rating.Easy`).
	Rating : [Again, Hard, Good, Easy]

	## A card's learning state.
	State : [New, Learning, Review, Relearning]

	## A (re)learning step (ts-fsrs step strings such as `"10m"`, `"1h"`, `"1d"`).
	Step : [Minutes(I64), Hours(I64), Days(I64)]

	## Scheduler settings, as in ts-fsrs `FSRSParameters`.
	Config : {
		request_retention : F64,
		maximum_interval : I64,
		weights : List(F64),
		enable_fuzz : Bool,
		enable_short_term : Bool,
		learning_steps : List(Step),
		relearning_steps : List(Step),
	}

	## A validated configuration (its weights clipped) with its derived constants.
	Scheduler :: {
		config : Config,
		decay : F64,
		factor : F64,
		interval_modifier : F64,
	}

	## A card, as in ts-fsrs `Card`. `elapsed_days` is deprecated in ts-fsrs but
	## still maintained there, so it is kept here.
	Card : {
		due : I64,
		stability : F64,
		difficulty : F64,
		elapsed_days : I64,
		scheduled_days : I64,
		learning_steps : I64,
		reps : I64,
		lapses : I64,
		state : State,
		last_review : [Some(I64), None],
	}

	## A review log entry, as in ts-fsrs `ReviewLog`; it records the card as it
	## was before the review.
	ReviewLog : {
		rating : Rating,
		state : State,
		due : I64,
		stability : F64,
		difficulty : F64,
		elapsed_days : I64,
		last_elapsed_days : I64,
		scheduled_days : I64,
		learning_steps : I64,
		review : I64,
	}

	## The card after a review and the log of that review.
	Outcome : { card : Card, log : ReviewLog }

	## The outcome of each rating.
	Outcomes : { again : Outcome, hard : Outcome, good : Outcome, easy : Outcome }

	## The FSRS-6 default weights of ts-fsrs v5.4.2 (`default_w`).
	default_weights : List(F64)
	default_weights = [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]

	## ts-fsrs defaults: retention 0.9, maximum interval 36500 days, fuzz off,
	## short-term scheduling on, learning steps 1m and 10m, relearning step 10m.
	default_config : Config
	default_config = {
		request_retention: 0.9,
		maximum_interval: 36500,
		weights: default_weights,
		enable_fuzz: Bool.False,
		enable_short_term: Bool.True,
		learning_steps: [Minutes(1), Minutes(10)],
		relearning_steps: [Minutes(10)],
	}

	## The ts-fsrs `FSRSVersion` string of the ported release.
	fsrs_version : Str
	fsrs_version = "v5.4.2 using FSRS-6.0"

	## Validate a configuration, clip its weights (ts-fsrs `clipParameters`), and
	## precompute the decay factor and interval modifier. As in ts-fsrs, a
	## retention or maximum interval of 0 means the default.
	scheduler : Config -> Try(Scheduler, Str)
	scheduler = |raw| {
		config = {
			..raw,
			request_retention: if (raw.request_retention == 0.0) default_config.request_retention else raw.request_retention,
			maximum_interval: if (raw.maximum_interval == 0) default_config.maximum_interval else raw.maximum_interval,
		}
		if config.weights.len() != 21 {
			Err("Invalid parameter length: ${config.weights.len().to_str()}. Must be 21 (FSRS-6).")
		} else if config.weights.any(|x| x.is_nan() or x.is_infinite()) {
			Err("Non-finite or NaN value in parameters")
		} else if config.request_retention <= 0.0 or config.request_retention > 1.0 {
			Err("Requested retention rate should be in the range (0,1]")
		} else {
			clipped = clip_parameters(config.weights, config.relearning_steps.len(), config.enable_short_term)
			decay = -weight(clipped, 20)
			factor = round_to_8(FsrsMath.exp(FsrsMath.pow(decay, -1.0) * FsrsMath.log(0.9)) - 1.0)
			Ok({
				config: { ..config, weights: clipped },
				decay,
				factor,
				interval_modifier: round_to_8((FsrsMath.pow(config.request_retention, 1.0 / decay) - 1.0) / factor),
			})
		}
	}

	## The clipped weights in use.
	weights : Scheduler -> List(F64)
	weights = |configured| configured.config.weights

	## ts-fsrs `interval_modifier`: interval = stability × modifier (before rounding).
	interval_modifier : Scheduler -> F64
	interval_modifier = |configured| configured.interval_modifier

	## ts-fsrs `createEmptyCard(now)`.
	new_card : I64 -> Card
	new_card = |now| {
		due: now,
		stability: 0.0,
		difficulty: 0.0,
		elapsed_days: 0,
		scheduled_days: 0,
		learning_steps: 0,
		reps: 0,
		lapses: 0,
		state: New,
		last_review: None,
	}

	## ts-fsrs `forgetting_curve`: retrievability after `elapsed_days` at `stability`.
	forgetting_curve : Scheduler, F64, F64 -> F64
	forgetting_curve = |configured, elapsed_days, stability| round_to_8(FsrsMath.pow(1.0 + (configured.factor * elapsed_days) / stability, configured.decay))

	## Review `card` at time `now` (ms) with `rating`: ts-fsrs `next`.
	next : Scheduler, I64, Rating, Card -> Try(Outcome, Str)
	next = |configured, now, rating, card| {
		outcomes = preview(configured, now, card)?
		Ok(
			match rating {
				Again => outcomes.again
				Hard => outcomes.hard
				Good => outcomes.good
				Easy => outcomes.easy
			},
		)
	}

	## The outcome of each rating for a review at `now`: ts-fsrs `repeat`.
	preview : Scheduler, I64, Card -> Try(Outcomes, Str)
	preview = |configured, now, card| {
		context = init_context(configured, now, card)
		if configured.config.enable_short_term {
			match card.state {
				New => each_rating(|grade| basic_learning(context, Learning, grade))
				Learning => each_rating(|grade| basic_learning(context, Learning, grade))
				Relearning => each_rating(|grade| basic_learning(context, Relearning, grade))
				Review => basic_review(context)
			}
		} else {
			match card.state {
				New => long_term_new(context)
				_ => long_term_review(context)
			}
		}
	}

	## ts-fsrs `get_retrievability(card, now, false)`: predicted recall
	## probability at `now`, 0 for a new card. Elapsed time counts whole 24-hour
	## periods since the last review.
	retrievability : Scheduler, I64, Card -> F64
	retrievability = |configured, now, card| {
		if card.state == New {
			0.0
		} else {
			elapsed = match card.last_review {
				Some(last_review) => FsrsMath.floor((now - last_review).to_f64() / day_ms.to_f64()).max(0.0)
				None => 0.0
			}
			# ts-fsrs uses +stability.toFixed(8), which equals round_to_8 for
			# every stability this module produces (they are already rounded).
			forgetting_curve(configured, elapsed, round_to_8(card.stability))
		}
	}
}

# CONSTANTS AND PARAMETERS

s_min : F64
s_min = 0.001

s_max : F64
s_max = 36500.0

init_s_max : F64
init_s_max = 100.0

w17_w18_ceiling : F64
w17_w18_ceiling = 2.0

minute_ms : I64
minute_ms = 60 * 1000

day_ms : I64
day_ms = 24 * 60 * 60 * 1000

clamp_ranges : F64, Bool -> List((F64, F64))
clamp_ranges = |ceiling, enable_short_term| [
	(s_min, init_s_max),
	(s_min, init_s_max),
	(s_min, init_s_max),
	(s_min, init_s_max),
	(1.0, 10.0),
	(0.001, 4.0),
	(0.001, 4.0),
	(0.001, 0.75),
	(0.0, 4.5),
	(0.0, 0.8),
	(0.001, 3.5),
	(0.001, 5.0),
	(0.001, 0.25),
	(0.001, 0.9),
	(0.0, 4.0),
	(0.0, 1.0),
	(1.0, 6.0),
	(0.0, ceiling),
	(0.0, ceiling),
	(if (enable_short_term) 0.01 else 0.0, 0.8),
	(0.1, 0.8),
]

# ts-fsrs `clipParameters`.
clip_parameters : List(F64), U64, Bool -> List(F64)
clip_parameters = |parameters, relearning_step_count, enable_short_term| {
	base = clamp_ranges(w17_w18_ceiling, enable_short_term)
	clip_at = |index| match base.get(index) {
		Ok((low, high)) => js_clamp(weight(parameters, index), low, high)
		Err(_) => weight(parameters, index)
	}
	ceiling =
		if relearning_step_count > 1 {
			value = -(FsrsMath.log(clip_at(11)) + FsrsMath.log(FsrsMath.pow(2.0, clip_at(13)) - 1.0) + clip_at(14) * 0.3) / relearning_step_count.to_f64()
			js_clamp(round_to_8(value.max(0.0).sqrt()), 0.01, w17_w18_ceiling)
		} else {
			w17_w18_ceiling
		}
	List.map2(clamp_ranges(ceiling, enable_short_term), parameters, |(low, high), parameter| js_clamp(parameter, low, high))
}

weight : List(F64), U64 -> F64
weight = |parameters, index| parameters.get(index) ?? 0.0

# MEMORY MODEL (ts-fsrs FSRSAlgorithm)

init_stability : List(F64), I64 -> F64
init_stability = |parameters, grade| weight(parameters, (grade - 1).to_u64_wrap()).max(0.1)

init_difficulty : List(F64), I64 -> F64
init_difficulty = |parameters, grade| round_to_8(weight(parameters, 4) - FsrsMath.exp((grade - 1).to_f64() * weight(parameters, 5)) + 1.0)

linear_damping : F64, F64 -> F64
linear_damping = |delta_difficulty, old_difficulty| round_to_8((delta_difficulty * (10.0 - old_difficulty)) / 9.0)

mean_reversion : List(F64), F64, F64 -> F64
mean_reversion = |parameters, initial, current| round_to_8(weight(parameters, 7) * initial + (1.0 - weight(parameters, 7)) * current)

next_difficulty : List(F64), F64, I64 -> F64
next_difficulty = |parameters, difficulty, grade| {
	delta_difficulty = -weight(parameters, 6) * (grade - 3).to_f64()
	next = difficulty + linear_damping(delta_difficulty, difficulty)
	js_clamp(mean_reversion(parameters, init_difficulty(parameters, 4), next), 1.0, 10.0)
}

next_recall_stability : List(F64), F64, F64, F64, I64 -> F64
next_recall_stability = |parameters, difficulty, stability, retrievability, grade| {
	hard_penalty = if (grade == 2) weight(parameters, 15) else 1.0
	easy_bound = if (grade == 4) weight(parameters, 16) else 1.0
	growth = FsrsMath.exp(weight(parameters, 8)) * (11.0 - difficulty) * FsrsMath.pow(stability, -weight(parameters, 9)) * (FsrsMath.exp((1.0 - retrievability) * weight(parameters, 10)) - 1.0) * hard_penalty * easy_bound
	round_to_8(js_clamp(stability * (1.0 + growth), s_min, s_max))
}

next_forget_stability : List(F64), F64, F64, F64 -> F64
next_forget_stability = |parameters, difficulty, stability, retrievability| {
	value = weight(parameters, 11) * FsrsMath.pow(difficulty, -weight(parameters, 12)) * (FsrsMath.pow(stability + 1.0, weight(parameters, 13)) - 1.0) * FsrsMath.exp((1.0 - retrievability) * weight(parameters, 14))
	round_to_8(js_clamp(value, s_min, s_max))
}

next_short_term_stability : List(F64), F64, I64 -> F64
next_short_term_stability = |parameters, stability, grade| {
	increase = FsrsMath.pow(stability, -weight(parameters, 19)) * FsrsMath.exp(weight(parameters, 17) * ((grade - 3).to_f64() + weight(parameters, 18)))
	masked_increase = if (grade >= 2) increase.max(1.0) else increase
	round_to_8(js_clamp(stability * masked_increase, s_min, 36500.0))
}

Memory : { difficulty : F64, stability : F64 }

# ts-fsrs `next_state` for grades 1-4.
next_memory : Fsrs.Scheduler, Memory, F64, I64, [Some(F64), None] -> Try(Memory, Str)
next_memory = |configured, { difficulty, stability }, elapsed_days, grade, given_retrievability| {
	parameters = configured.config.weights
	if elapsed_days < 0.0 {
		Err("Invalid delta_t \"${FsrsMath.to_js_str(elapsed_days)}\"")
	} else if difficulty == 0.0 and stability == 0.0 {
		Ok({ difficulty: js_clamp(init_difficulty(parameters, grade), 1.0, 10.0), stability: init_stability(parameters, grade) })
	} else if difficulty < 1.0 or stability < s_min {
		Err("Invalid memory state { difficulty: ${FsrsMath.to_js_str(difficulty)}, stability: ${FsrsMath.to_js_str(stability)} }")
	} else {
		recall = match given_retrievability {
			Some(value) => value
			None => Fsrs.forgetting_curve(configured, elapsed_days, stability)
		}
		new_stability =
			if elapsed_days == 0.0 and configured.config.enable_short_term {
				next_short_term_stability(parameters, stability, grade)
			} else if grade == 1 {
				after_fail = next_forget_stability(parameters, difficulty, stability, recall)
				(w17, w18) = if (configured.config.enable_short_term) (weight(parameters, 17), weight(parameters, 18)) else (0.0, 0.0)
				next_minimum = stability / FsrsMath.exp(w17 * w18)
				js_clamp(round_to_8(next_minimum), s_min, after_fail)
			} else {
				next_recall_stability(parameters, difficulty, stability, recall, grade)
			}
		Ok({ difficulty: next_difficulty(parameters, difficulty, grade), stability: new_stability })
	}
}

# ts-fsrs `next_interval` (with `apply_fuzz`), in days.
next_interval : Fsrs.Scheduler, Str, F64, I64 -> I64
next_interval = |configured, seed, stability, elapsed_days| {
	maximum_interval = configured.config.maximum_interval
	new_interval = FsrsMath.round(stability * configured.interval_modifier).max(1.0).min(maximum_interval.to_f64())
	if !configured.config.enable_fuzz or new_interval < 2.5 {
		to_integer(new_interval)
	} else {
		fuzz_factor = alea_first(seed)
		range = fuzz_range(new_interval, elapsed_days, maximum_interval)
		to_integer(FsrsMath.floor(fuzz_factor * (range.maximum - range.minimum + 1).to_f64() + range.minimum.to_f64()))
	}
}

# ts-fsrs `get_fuzz_range`.
fuzz_range : F64, I64, I64 -> { minimum : I64, maximum : I64 }
fuzz_range = |unclamped_interval, elapsed_days, maximum_interval| {
	var $delta = 1.0
	for (start, end, factor) in [(2.5, 7.0, 0.15), (7.0, 20.0, 0.1), (20.0, F64.infinity, 0.05)] {
		$delta = $delta + factor * (unclamped_interval.min(end) - start).max(0.0)
	}
	interval = unclamped_interval.min(maximum_interval.to_f64())
	lowest = to_integer(FsrsMath.round(interval - $delta)).max(2)
	maximum = to_integer(FsrsMath.round(interval + $delta)).min(maximum_interval)
	minimum = if (interval > elapsed_days.to_f64()) lowest.max(elapsed_days + 1) else lowest
	{ minimum: minimum.min(maximum), maximum }
}

# SCHEDULING (ts-fsrs AbstractScheduler, BasicScheduler, LongTermScheduler)

Context : {
	scheduler : Fsrs.Scheduler,
	now : I64,
	last : Fsrs.Card,
	current : Fsrs.Card,
	elapsed_days : I64,
	seed : Str,
}

init_context : Fsrs.Scheduler, I64, Fsrs.Card -> Context
init_context = |configured, now, card| {
	interval = match (card.state, card.last_review) {
		(New, _) => 0
		(_, Some(last_review)) => utc_day(now) - utc_day(last_review)
		(_, None) => 0
	}
	current = { ..card, last_review: Some(now), elapsed_days: interval, reps: card.reps + 1 }
	{
		scheduler: configured,
		now,
		last: card,
		current,
		elapsed_days: interval,
		seed: "${now.to_str()}_${current.reps.to_str()}_${FsrsMath.to_js_str(current.difficulty * current.stability)}",
	}
}

each_rating : (I64 -> Try(Fsrs.Outcome, Str)) -> Try(Fsrs.Outcomes, Str)
each_rating = |outcome_for| {
	again = outcome_for(1)?
	hard = outcome_for(2)?
	good = outcome_for(3)?
	easy = outcome_for(4)?
	Ok({ again, hard, good, easy })
}

rating_from_grade : I64 -> Fsrs.Rating
rating_from_grade = |grade| match grade {
	1 => Again
	2 => Hard
	3 => Good
	_ => Easy
}

build_log : Context, I64 -> Fsrs.ReviewLog
build_log = |context, grade| {
	rating: rating_from_grade(grade),
	state: context.current.state,
	due: match context.last.last_review {
		Some(last_review) => last_review
		None => context.last.due
	},
	stability: context.current.stability,
	difficulty: context.current.difficulty,
	elapsed_days: context.elapsed_days,
	last_elapsed_days: context.last.elapsed_days,
	scheduled_days: context.current.scheduled_days,
	learning_steps: context.current.learning_steps,
	review: context.now,
}

next_card_memory : Context, I64, I64, [Some(F64), None] -> Try(Fsrs.Card, Str)
next_card_memory = |context, elapsed_days, grade, given_retrievability| {
	memory = next_memory(context.scheduler, { difficulty: context.current.difficulty, stability: context.current.stability }, elapsed_days.to_f64(), grade, given_retrievability)?
	Ok({ ..context.current, difficulty: memory.difficulty, stability: memory.stability })
}

# BasicScheduler `newState` / `learningState`.
basic_learning : Context, Fsrs.State, I64 -> Try(Fsrs.Outcome, Str)
basic_learning = |context, to_state, grade| {
	card = next_card_memory(context, context.elapsed_days, grade, None)?
	Ok({ card: apply_learning_steps(context, card, grade, to_state), log: build_log(context, grade) })
}

# BasicScheduler `reviewState`.
basic_review : Context -> Try(Fsrs.Outcomes, Str)
basic_review = |context| {
	interval = context.elapsed_days
	recall = Fsrs.forgetting_curve(context.scheduler, interval.to_f64(), context.current.stability)
	next_again = next_card_memory(context, interval, 1, Some(recall))?
	next_hard = next_card_memory(context, interval, 2, Some(recall))?
	next_good = next_card_memory(context, interval, 3, Some(recall))?
	next_easy = next_card_memory(context, interval, 4, Some(recall))?
	days_for = |stability| next_interval(context.scheduler, context.seed, stability, interval)
	hard_interval = days_for(next_hard.stability).min(days_for(next_good.stability))
	good_interval = days_for(next_good.stability).max(hard_interval + 1)
	easy_interval = days_for(next_easy.stability).max(good_interval + 1)
	again = apply_learning_steps(context, next_again, 1, Relearning)
	Ok({
		again: { card: { ..again, lapses: again.lapses + 1 }, log: build_log(context, 1) },
		hard: { card: to_review(context, next_hard, hard_interval), log: build_log(context, 2) },
		good: { card: to_review(context, next_good, good_interval), log: build_log(context, 3) },
		easy: { card: to_review(context, next_easy, easy_interval), log: build_log(context, 4) },
	})
}

to_review : Context, Fsrs.Card, I64 -> Fsrs.Card
to_review = |context, card, days| { ..card, scheduled_days: days, due: context.now + days * day_ms, state: Review, learning_steps: 0 }

# BasicScheduler `applyLearningSteps`.
apply_learning_steps : Context, Fsrs.Card, I64, Fsrs.State -> Fsrs.Card
apply_learning_steps = |context, next_card, grade, to_state| {
	(scheduled_minutes, next_steps) = match learning_steps_strategy(context.scheduler.config, context.current.state, context.current.learning_steps, grade) {
		Some(entry) => (entry.scheduled_minutes.max(0), entry.next_step.max(0))
		None => (0, 0)
	}
	if scheduled_minutes > 0 and scheduled_minutes < 1440 {
		{ ..next_card, learning_steps: next_steps, scheduled_days: 0, state: to_state, due: context.now + scheduled_minutes * minute_ms }
	} else if scheduled_minutes >= 1440 {
		{
			..next_card,
			state: Review,
			learning_steps: next_steps,
			due: context.now + scheduled_minutes * minute_ms,
			scheduled_days: to_integer(FsrsMath.floor(scheduled_minutes.to_f64() / 1440.0)),
		}
	} else {
		interval = next_interval(context.scheduler, context.seed, next_card.stability, context.elapsed_days)
		{ ..next_card, state: Review, learning_steps: 0, scheduled_days: interval, due: context.now + interval * day_ms }
	}
}

step_minutes : Fsrs.Step -> I64
step_minutes = |step| match step {
	Minutes(count) => count
	Hours(count) => count * 60
	Days(count) => count * 1440
}

# ts-fsrs `BasicLearningStepsStrategy`, for one grade.
learning_steps_strategy : Fsrs.Config, Fsrs.State, I64, I64 -> [Some({ scheduled_minutes : I64, next_step : I64 }), None]
learning_steps_strategy = |config, state, current_step, grade| {
	steps = if (state == Relearning or state == Review) config.relearning_steps else config.learning_steps
	count = steps.len().to_i64_wrap()
	minutes_at = |index| {
		if index < 0 {
			None
		} else {
			match steps.get(index.to_u64_wrap()) {
				Ok(step) => Some(step_minutes(step))
				Err(_) => None
			}
		}
	}
	first_minutes = match minutes_at(0) {
		Some(minutes) => minutes
		None => 0
	}
	if count == 0 or current_step >= count {
		None
	} else if state == Review {
		match (grade, minutes_at(current_step.max(0))) {
			(1, Some(minutes)) => Some({ scheduled_minutes: minutes, next_step: 0 })
			_ => None
		}
	} else {
		match grade {
			1 => Some({ scheduled_minutes: first_minutes, next_step: 0 })
			2 => {
				second_minutes = match minutes_at(1) {
					Some(minutes) => minutes
					None => 0
				}
				hard_minutes =
					if count == 1 {
						to_integer(FsrsMath.round(first_minutes.to_f64() * 1.5))
					} else {
						to_integer(FsrsMath.round((first_minutes + second_minutes).to_f64() / 2.0))
					}
				Some({ scheduled_minutes: hard_minutes, next_step: current_step })
			}
			3 => match minutes_at(current_step + 1) {
				Some(minutes) => if (minutes != 0) Some({ scheduled_minutes: minutes, next_step: current_step + 1 }) else None
				None => None
			}
			_ => None
		}
	}
}

# LongTermScheduler `newState`.
long_term_new : Context -> Try(Fsrs.Outcomes, Str)
long_term_new = |context| long_term_all({ ..context, current: { ..context.current, scheduled_days: 0, elapsed_days: 0 } }, 0, None, Bool.False)

# LongTermScheduler `reviewState` (also used for learning states).
long_term_review : Context -> Try(Fsrs.Outcomes, Str)
long_term_review = |context| {
	interval = context.elapsed_days
	long_term_all(context, interval, Some(Fsrs.forgetting_curve(context.scheduler, interval.to_f64(), context.current.stability)), Bool.True)
}

long_term_all : Context, I64, [Some(F64), None], Bool -> Try(Fsrs.Outcomes, Str)
long_term_all = |context, interval, recall, count_lapse| {
	next_again = next_card_memory(context, interval, 1, recall)?
	next_hard = next_card_memory(context, interval, 2, recall)?
	next_good = next_card_memory(context, interval, 3, recall)?
	next_easy = next_card_memory(context, interval, 4, recall)?
	days_for = |stability| next_interval(context.scheduler, context.seed, stability, interval)
	again_interval = days_for(next_again.stability).min(days_for(next_hard.stability))
	hard_interval = days_for(next_hard.stability).max(again_interval + 1)
	good_interval = days_for(next_good.stability).max(hard_interval + 1)
	easy_interval = days_for(next_easy.stability).max(good_interval + 1)
	again = to_review(context, next_again, again_interval)
	Ok({
		again: { card: if (count_lapse) { ..again, lapses: again.lapses + 1 } else again, log: build_log(context, 1) },
		hard: { card: to_review(context, next_hard, hard_interval), log: build_log(context, 2) },
		good: { card: to_review(context, next_good, good_interval), log: build_log(context, 3) },
		easy: { card: to_review(context, next_easy, easy_interval), log: build_log(context, 4) },
	})
}

# NUMERICS

# ts-fsrs `roundTo(x, 8)`: `Math.round(x * 1e8) / 1e8`.
round_to_8 : F64 -> F64
round_to_8 = |x| FsrsMath.round(x * 100000000.0) / 100000000.0

# `Math.min(Math.max(value, low), high)`.
js_clamp : F64, F64, F64 -> F64
js_clamp = |value, low, high| value.max(low).min(high)

# A whole-numbered F64 (from `FsrsMath.round` or `FsrsMath.floor`) as an I64.
to_integer : F64 -> I64
to_integer = |whole| F64.to_i64_try(whole) ?? 0

# Days since the epoch of the UTC calendar day containing `ms`.
utc_day : I64 -> I64
utc_day = |ms| to_integer(FsrsMath.floor(ms.to_f64() / day_ms.to_f64()))

# The first output of ts-fsrs `alea(seed)()`.
alea_first : Str -> F64
alea_first = |seed| {
	# Alea's constructor hashes " " three times (s0, s1, s2), then the seed;
	# the first output depends only on s0 and the first seed hash.
	(state1, s0_initial) = mash(4022871197.0, " ") # 0xEFC8249D
	(state2, _) = mash(state1, " ")
	(state3, _) = mash(state2, " ")
	(_, seeded) = mash(state3, seed)
	s0_difference = s0_initial - seeded
	s0 = if (s0_difference < 0.0) s0_difference + 1.0 else s0_difference
	t = 2091639.0 * s0 + 1.0 * 2.3283064365386963e-10
	# JavaScript's `t | 0`; t is non-negative and below 2^31.
	t - FsrsMath.floor(t)
}

# Baagøe's Mash hash: returns the updated state and the hash value. Mash reads
# UTF-16 code units; this reads UTF-8 bytes, which are the same for the ASCII
# seeds `init_context` builds.
mash : F64, Str -> (F64, F64)
mash = |initial, data| {
	var $state = initial
	for code in data.to_utf8() {
		added = $state + code.to_f64()
		h0 = 0.02519603282416938 * added
		integer0 = to_uint32(h0)
		h1 = (h0 - integer0) * integer0
		integer1 = to_uint32(h1)
		h2 = h1 - integer1
		$state = integer1 + h2 * 4294967296.0
	}
	($state, to_uint32($state) * 2.3283064365386963e-10)
}

# JavaScript `x >>> 0` for non-negative finite `x`.
to_uint32 : F64 -> F64
to_uint32 = |x| {
	whole = FsrsMath.floor(x)
	whole - 4294967296.0 * FsrsMath.floor(whole / 4294967296.0)
}
