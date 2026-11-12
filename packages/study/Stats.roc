import fsrs.FsrsMath
import Review
import Study
import Words

## The numbers of the Progress page, ported from `viewStats`,
## `viewColumnChart` and `shortDate` in `src/Main.elm`. As there, days are
## UTC days (`Review.start_of_day`), and "now" is the app's clock.
Stats := [].{

	## A day's start (UTC milliseconds) and how many events fell on it.
	Day : { day : I64, count : I64 }

	## A passage by how many of its answers were marked wrong, over all attempts.
	HardPassage : { work : Str, passage : Str, wrong : U64, attempts : U64 }

	day_ms : I64
	day_ms = 86400000

	## The starts of the last 30 days, oldest first, ending today.
	days : I64 -> List(I64)
	days = |now| {
		today = Review.start_of_day(now)
		List.repeat(0, 30).map_with_index(|_, n| today - (29 - n.to_i64_wrap()) * day_ms)
	}

	## How many of `times` fell on each of the last 30 days.
	per_day : I64, List(I64) -> List(Day)
	per_day = |now, times| {
		counts = times.fold(Dict.empty(), |found, time| found.update(Review.start_of_day(time), |current| Ok((current ?? 0) + 1)))
		days(now).map(|day| { day, count: counts.get(day) ?? 0 })
	}

	## When passages were graded and words reviewed.
	review_times : List(Study.Attempt), List(Words.Review) -> List(I64)
	review_times = |attempts, reviews| attempts.map(|attempt| attempt.finished_at).concat(reviews.map(|review| review.at))

	## Days in a row with a review, ending today, or yesterday while today has none yet.
	streak : I64, List(I64) -> I64
	streak = |now, times| {
		active = Set.from_list(times.map(Review.start_of_day))
		today = Review.start_of_day(now)
		count_from(active, if active.contains(today) today else today - day_ms, 0)
	}

	## Word answers marked in passages and word reviews over the last 7 days
	## (today and the 6 before it), and how many of them were right.
	recent_words : I64, List(Study.Attempt), List(Words.Review) -> { right : U64, total : U64 }
	recent_words = |now, attempts, reviews| {
		week_ago = Review.start_of_day(now) - 6 * day_ms
		judged = attempts
			.keep_if(|attempt| attempt.finished_at >= week_ago)
			.join_map(|attempt| attempt.items)
			.keep_if(|item| item.kind == WordItem and item.mark != None)
		recent = reviews.keep_if(|review| review.at >= week_ago)
		{
			right: judged.count_if(|item| item.mark == Some(Bool.True)) + recent.count_if(|review| review.rating != Again),
			total: judged.len() + recent.len(),
		}
	}

	## `82%` of the recent word answers right, `—` without any (integer division, as the Elm).
	recent_percent : { right : U64, total : U64 } -> Str
	recent_percent = |recent| if recent.total == 0 "—" else "${(recent.right * 100 // recent.total).to_str()}%"

	## The 15 words missed most, ties by lemma.
	missed_words : Dict(Str, Words.Card) -> List(Words.Card)
	missed_words = |cards|
		cards
			.values()
			.keep_if(|word| word.misses > 0)
			.sort_with(|a, b| if a.misses > b.misses Before else if a.misses < b.misses After else compare_text(a.lemma, b.lemma))
			.take_first(15)

	## The 10 passages with the most answers marked wrong; ties in work and citation order.
	hard_passages : List(Study.Attempt) -> List(HardPassage)
	hard_passages = |attempts|
		attempts
			.fold(
				Dict.empty(),
				|found, attempt| found.update(
					(attempt.work, attempt.passage),
					|current| {
						(wrong, count) = current ?? (0, 0)
						Ok((wrong + Study.missed(attempt).len(), count + 1))
					},
				),
			)
			.to_list()
			.map(|((work, passage), (wrong, count))| { work, passage, wrong, attempts: count })
			.keep_if(|hard| hard.wrong > 0)
			.sort_with(
				|a, b|
					if a.wrong > b.wrong {
						Before
					} else if a.wrong < b.wrong {
						After
					} else {
						match compare_text(a.work, b.work) {
							Same => compare_text(a.passage, b.passage)
							order => order
						}
					},
			)
			.take_first(10)

	## The latest of the busiest days, when any day has a count.
	peak_day : List(Day) -> [Some(I64), None]
	peak_day = |points| {
		peak = peak_count(points)
		if peak == 0 {
			None
		} else {
			points.fold(None, |found, point| if point.count == peak Some(point.day) else found)
		}
	}

	peak_count : List(Day) -> I64
	peak_count = |points| points.fold(0, |peak, point| peak.max(point.count))

	## `part` as a percentage of `whole` for a CSS length, written as
	## JavaScript writes the number (`String.fromFloat`).
	css_percent : I64, I64 -> Str
	css_percent = |part, whole| "${FsrsMath.to_js_str(100.0 * part.to_f64() / whole.to_f64())}%"

	## `Nov 12`, in UTC (`shortDate Time.utc`).
	short_date : I64 -> Str
	short_date = |millis| {
		date = civil(floor_div(millis, day_ms))
		month = match date.month {
			1 => "Jan"
			2 => "Feb"
			3 => "Mar"
			4 => "Apr"
			5 => "May"
			6 => "Jun"
			7 => "Jul"
			8 => "Aug"
			9 => "Sep"
			10 => "Oct"
			11 => "Nov"
			_ => "Dec"
		}
		"${month} ${date.day.to_str()}"
	}
}

count_from : Set(I64), I64, I64 -> I64
count_from = |active, day, found| if active.contains(day) count_from(active, day - Stats.day_ms, found + 1) else found

floor_div : I64, I64 -> I64
floor_div = |n, d| {
	q = n // d
	if n % d < 0 q - 1 else q
}

## The proleptic Gregorian date of a day count from 1970-01-01 (Howard
## Hinnant's `civil_from_days`).
civil : I64 -> { year : I64, month : I64, day : I64 }
civil = |days| {
	z = days + 719468
	era = floor_div(z, 146097)
	doe = z - era * 146097
	yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	mp = (5 * doy + 2) // 153
	day = doy - (153 * mp + 2) // 5 + 1
	month = if mp < 10 mp + 3 else mp - 9
	{ year: yoe + era * 400 + (if month <= 2 1 else 0), month, day }
}

## Byte order, which for UTF-8 is code point order; Elm compares UTF-16 code
## units, which differs only past the Basic Multilingual Plane.
compare_text : Str, Str -> [Before, Same, After]
compare_text = |a, b| compare_bytes(a.to_utf8(), b.to_utf8(), 0)

compare_bytes : List(U8), List(U8), U64 -> [Before, Same, After]
compare_bytes = |a, b, at|
	match (a.get(at), b.get(at)) {
		(Err(_), Err(_)) => Same
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		(Ok(x), Ok(y)) => if x < y Before else if x > y After else compare_bytes(a, b, at + 1)
	}
