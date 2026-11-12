import Review
import Study
import Words

## Today's study session across every work, ported from `src/Today.elm`: words
## and passages in one queue, or either alone.
##
## Order: due words (most overdue first), then due passages from every work
## (most overdue first), then new passages, so what has been studied before
## comes before anything new. New passages come from the work studied most
## recently, then the others in library order, up to one daily limit shared by
## all works. A word or passage rated Again or Hard comes due again within
## minutes (FSRS learning steps), so it returns later in the same session, after
## the next item or two.
Today := [].{

	Mode : [Everything, WordsOnly, PassagesOnly]

	## A word to review (its lemma), or a passage (its work and citation).
	Item : [WordItem(Str), PassageItem(Str, Str)]

	## A work's id and its passages in text order.
	Work : { id : Str, passages : List(Str) }

	## Due words (lemmas), then due and new passages as (work, citation).
	Plan : { words : List(Str), due : List((Str, Str)), new : List((Str, Str)) }

	## The `today` query parameter: `all`, `words` or `passages`.
	mode_to_str : Mode -> Str
	mode_to_str = |mode|
		match mode {
			Everything => "all"
			WordsOnly => "words"
			PassagesOnly => "passages"
		}

	mode_from_str : Str -> Mode
	mode_from_str = |name|
		match name {
			"words" => WordsOnly
			"passages" => PassagesOnly
			_ => Everything
		}

	## Everything due or new now, in session order. `last_work` is the work
	## studied most recently. With a `scope`, only that work: its passages, and
	## the words missed or reviewed in it.
	plan : I64, I64, [Some(Str), None], [Some(Str), None], List(Work), Dict(Str, Review.Entry), Dict(Str, Words.Card) -> Plan
	plan = |now, new_per_day, scope, last_work, all_works, entries, all_words| {
		works = all_works.keep_if(|work| in_scope(scope, work.id))
		word_cards = all_words.keep_if(|(_, word)| word_in_scope(scope, word))
		# In key order, as Elm's `Dict.values`.
		cards = entries.to_list().sort_with(|(a, _), (b, _)| compare_text(a, b)).map(|(_, entry)| entry)
		studied = cards.fold(
			Dict.empty(),
			|found, entry| found.insert(entry.work, found.get(entry.work).ok_or(Dict.empty()).insert(entry.passage, {})),
		)
		# The daily new limit counts every work, scoped or not.
		introduced_today = cards.count_if(|entry| entry.introduced_at >= Review.start_of_day(now)).to_i64_wrap()
		ordered = match last_work {
			Some(id) => works.keep_if(|work| work.id == id).concat(works.drop_if(|work| work.id == id))
			None => works
		}
		known = Dict.from_list(works.map(|work| (work.id, {})))
		is_studied = |work, passage| studied.get(work).map_ok(|passages| passages.contains(passage)).ok_or(Bool.False)
		{
			words: Words.due(now, word_cards).map(|word| word.lemma),
			# `cards` is in key order, so this stable sort keeps key order for equal due times.
			due: sort_by(cards.keep_if(|entry| entry.card.due <= now and known.contains(entry.work)), |a, b| compare_i64(a.card.due, b.card.due))
				.map(|entry| (entry.work, entry.passage)),
			new: ordered
				.join_map(|work| work.passages.map(|passage| (work.id, passage)))
				.drop_if(|(work, passage)| is_studied(work, passage))
				.take_first((new_per_day - introduced_today).max(0).to_u64_wrap()),
		}
	}

	## The work of the most recent graded passage, where new passages continue.
	## Ported from `lastWork` in `src/Main.elm`; of attempts finished at the same
	## time, the first listed wins, as there.
	last_work : List(Study.Attempt) -> [Some(Str), None]
	last_work = |attempts|
		match attempts.first() {
			Ok(head) => Some(attempts.fold(head, |latest, attempt| if attempt.finished_at > latest.finished_at attempt else latest).work)
			Err(_) => None
		}

	## The next item to study in this mode, if any is due or new.
	next : Mode, Plan -> [Some(Item), None]
	next = |mode, today| {
		words = today.words.map(|lemma| WordItem(lemma))
		passages = today.due.concat(today.new).map(|(work, passage)| PassageItem(work, passage))
		match by_mode(mode, words, passages).first() {
			Ok(item) => Some(item)
			Err(_) => None
		}
	}

	## The earliest item that comes due later today in this mode (a learning
	## step), with its due time. Of items due at the same time, words come
	## first, then passages, each in key order, as in the Elm app.
	upcoming : I64, Mode, [Some(Str), None], Dict(Str, Review.Entry), Dict(Str, Words.Card) -> [Some((Item, I64)), None]
	upcoming = |now, mode, scope, entries, word_cards| {
		end_of_day = Review.start_of_day(now) + 86400000
		soon = |due| due > now and due < end_of_day
		words = word_cards
			.to_list()
			.sort_with(|(a, _), (b, _)| compare_text(a, b))
			.keep_oks(|(_, word)| if soon(word.card.due) and word_in_scope(scope, word) Ok((WordItem(word.lemma), word.card.due)) else Err({}))
		passages = entries
			.to_list()
			.sort_with(|(a, _), (b, _)| compare_text(a, b))
			.keep_oks(|(_, entry)| if soon(entry.card.due) and in_scope(scope, entry.work) Ok((PassageItem(entry.work, entry.passage), entry.card.due)) else Err({}))
		candidates = by_mode(mode, words, passages)
		match candidates.first() {
			# The first of the earliest, as Elm's stable `List.sortBy` then `List.head`.
			Ok(head) => Some(candidates.fold(head, |earliest, (item, due)| if due < earliest.1 (item, due) else earliest))
			Err(_) => None
		}
	}
}

by_mode : Today.Mode, List(a), List(a) -> List(a)
by_mode = |mode, words, passages|
	match mode {
		Everything => words.concat(passages)
		WordsOnly => words
		PassagesOnly => passages
	}

in_scope : [Some(Str), None], Str -> Bool
in_scope = |scope, work|
	match scope {
		Some(id) => id == work
		None => Bool.True
	}

word_in_scope : [Some(Str), None], Words.Card -> Bool
word_in_scope = |scope, word|
	match scope {
		Some(work) => word.works.contains(work)
		None => Bool.True
	}

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
