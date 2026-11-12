import json.JsonValue
import Corpus
import Review
import Study

## The library page, ported from `viewLibrary`, `lastActivity`, `workingOn`
## and `viewWorkRow` in `src/Main.elm`: when each work was last studied, the
## works the learner is working on, the library searched and sorted, and each
## work's progress line.
Library := [].{

	## A finished word review as the library counts it: its work and when. Word
	## reviews are `wordreview` records in the `progress` store (`src/Words.elm`).
	Activity : { work : Str, at : I64 }

	## `recent` (the default), `title` or `short`, as the Elm app's sort menu.
	Sort : Str

	## A word review's work and time; other records of the progress store are `Err`.
	decode_activity : JsonValue -> Try(Activity, Str)
	decode_activity = |json| {
		if JsonValue.as_str(JsonValue.field(json, "type")?) != Ok("wordreview") {
			return Err("not a word review")
		}
		Ok(
			{
				work: JsonValue.as_str(JsonValue.field(JsonValue.field(json, "occurrence")?, "work")?)?,
				at: JsonValue.as_i64(JsonValue.field(json, "at")?)?,
			},
		)
	}

	## When each work was last studied: its latest graded passage or word review.
	last_activity : List(Study.Attempt), List(Activity) -> Dict(Str, I64)
	last_activity = |attempts, word_reviews|
		attempts
			.map(|attempt| { work: attempt.work, at: attempt.finished_at })
			.concat(word_reviews)
			.fold(
				Dict.empty(),
				|found, event| match found.get(event.work) {
					Ok(seen) if seen >= event.at => found
					_ => found.insert(event.work, event.at)
				},
			)

	## The works the learner is working on: studied ones, most recent first,
	## then ones opened (`opened`: works with a saved position, and the Today
	## scope) but not yet graded.
	working_on : List(Corpus.Work), Dict(Str, I64), List(Str) -> List(Corpus.Work)
	working_on = |works, activity, opened| {
		studied = sort_by(works.keep_if(|work| activity.contains(work.id)), |a, b| compare_i64(activity_of(activity, b), activity_of(activity, a)))
		studied.concat(works.keep_if(|work| !activity.contains(work.id) and opened.contains(work.id)))
	}

	## The library as the search and sort menu show it. The search matches the
	## title, edition, author and original title, ignoring ASCII case.
	## Workaround: Roc's `Str` has no Unicode case mapping, so unlike the Elm
	## app's `String.toLower`, Greek letters match only in the case typed
	## (https://github.com/thebrandonlucas/roc-issues/tree/master/roc/IMPROVEMENT-009-unicode-case-mapping);
	## use Unicode lowercasing once Roc has it.
	shown : List(Corpus.Work), Dict(Str, I64), Str, Sort -> List(Corpus.Work)
	shown = |works, activity, search, sort| {
		query = search.trim().with_ascii_lowercased()
		matches = |work| {
			fields = match work.citation {
				Some(found) => [work.title, work.edition, found.text.author, found.text.title]
				None => [work.title, work.edition]
			}
			query == "" or fields.any(|field| field.with_ascii_lowercased().contains(query))
		}
		sorted = match sort {
			"title" => sort_by(works, |a, b| compare_text(a.title, b.title))
			"short" => sort_by(works, |a, b| compare_u64(a.passages.len(), b.passages.len()))
			_ => sort_by(
				works,
				|a, b| match compare_i64(activity_of(activity, b), activity_of(activity, a)) {
					Same => compare_text(a.title, b.title)
					order => order
				},
			)
		}
		sorted.keep_if(matches)
	}

	## How many of the work's passages have a card, and how many are due now.
	progress : I64, Corpus.Work, Dict(Str, Review.Entry) -> { studied : U64, due : U64 }
	progress = |now, work, entries| {
		studied = entries.values().count_if(|entry| entry.work == work.id)
		# The daily new limit does not change what is due.
		due = Review.queue(now, 0, work.id, work.passages, entries).due.len()
		{ studied, due }
	}

	## A work row's line: `13 passages · not started`, or `2 of 13 passages studied · 1 due`.
	meta : I64, Corpus.Work, Dict(Str, Review.Entry) -> Str
	meta = |now, work, entries| {
		found = progress(now, work, entries)
		total = work.passages.len()
		if found.studied == 0 {
			"${total.to_str()} ${if total == 1 "passage" else "passages"} · not started"
		} else {
			"${found.studied.to_str()} of ${total.to_str()} passages studied · ${found.due.to_str()} due"
		}
	}
}

activity_of : Dict(Str, I64), Corpus.Work -> I64
activity_of = |activity, work| activity.get(work.id).ok_or(0)

## A stable sort: equal items keep their order, as Elm's `List.sortBy` does.
sort_by : List(a), (a, a -> [Before, Same, After]) -> List(a)
sort_by = |items, order|
	items
		.map_with_index(|item, index| { item, index })
		.sort_with(
			|a, b| match order(a.item, b.item) {
				Same => compare_u64(a.index, b.index)
				found => found
			},
		)
		.map(|found| found.item)

compare_i64 : I64, I64 -> [Before, Same, After]
compare_i64 = |a, b| if a < b Before else if a > b After else Same

compare_u64 : U64, U64 -> [Before, Same, After]
compare_u64 = |a, b| if a < b Before else if a > b After else Same

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
