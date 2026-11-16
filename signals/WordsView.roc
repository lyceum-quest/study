import pf.Engine exposing [Elem, State, Signal]
import pf.Html
import fsrs.Fsrs
import study.Corpus
import study.Review
import study.Route
import study.Study
import study.Today
import study.Words
import Model
import Nav
import Page
import LibraryView

## Today's page, word reviews and word pages, ported from `viewTodayPage`,
## `viewWordReview`, `viewWordPage` and `viewHighlighted` in `src/Main.elm`.
WordsView := [].{

	## Today's session page: where the session ends when nothing is due, with
	## what returns next.
	today_page : State(Page.S, Model.Model) -> Elem(Page.S)
	today_page = |session| {
		model = session.signal()
		Engine.element(
			"main",
			[Engine.class("page today-page")],
			[
				Engine.element(
					"section",
					[Engine.class("today-panel")],
					[
						LibraryView.today_head(session),
						Engine.switch(
							model.map(|m| if Today.next(mode(m), Model.today_plan(m)) != None "more" else "done"),
							["more", "done"],
							|found| match found {
								"more" =>
									Html.div_attrs(
										[Engine.attr("style", "display: contents")],
										[
											Engine.element("h1", [Engine.class("today-title")], [Engine.text("More is ready")]),
											Html.div("today-actions", [Page.button("Continue →", "primary-button", Page.act(session, |m| Nav.start_today(m, mode(m))))]),
										],
									)
								_ =>
									Html.div_attrs(
										[Engine.attr("style", "display: contents")],
										[
											Engine.element("h1", [Engine.class("today-title")], [Engine.text("Done for now")]),
											Engine.switch(
												model.map(|m| Today.mode_to_str(mode(m))),
												["all", "words", "passages"],
												|name| LibraryView.upcoming(session, Today.mode_from_str(name)),
											),
											Engine.when(
												model.map(|m| mode(m) != WordsOnly and Model.more_to_learn(m)),
												|| Html.div("today-actions", [LibraryView.learn_more_button(session, Bool.True)]),
												|| Engine.text(""),
											),
										],
									)
							},
						),
						Html.p_s(model.map(today_so_far), [Engine.class("today-summary")]),
						Engine.element(
							"p",
							[Engine.class("today-continue")],
							[Html.link("Home", Route.to_path(Library), []), Engine.text(" · "), Html.link("Progress", Route.to_path(Stats), [])],
						),
					],
				),
			],
		)
	}

	## Recall one word's meaning in the passage where it was last missed (or
	## last seen), then rate it.
	word_review : State(Page.S, Model.Model) -> Elem(Page.S)
	word_review = |session| {
		model = session.signal()
		Engine.when(
			model.map(|m| m.word_cards.contains(Model.screen_lemma(m))),
			|| Engine.element(
				"main",
				[Engine.class("page word-review-page")],
				[
					Engine.when(model.map(|m| m.today_mode != None), || Html.p_s(model.map(Model.session_status), [Engine.class("session-status")]), || Engine.text("")),
					Engine.element(
						"section",
						[Engine.class("word-review-card")],
						[
							Html.p_s(model.map(|m| match context(m) { Some(found) => "Word · ${Model.passage_name(m, found.work, found.passage)}"
								None => "" }), [Engine.class("eyebrow")]),
							highlighted(model.map(|m| context_text(context(m)))),
							Html.div_attrs(
								[Engine.class("word-review-form"), Engine.attr("lang", "grc")],
								[Html.span_s(context_text_of(model, |found| found.form), [Engine.class("review-form")]), Engine.element("span", [Engine.class("review-lemma")], [Engine.text_s(model.map(|m| Corpus.display_lemma(Model.screen_lemma(m))))])],
							),
							Html.text_input(
								context_text_of(model, |found| "Meaning of ${found.form}"),
								"text",
								model.map(|m| m.word_answer.guess),
								[Engine.class("gloss-input word-review-input"), Engine.attr("placeholder", "What does it mean here?")],
								Page.act_value(session, |m, guess| { ..m, word_answer: { ..m.word_answer, guess } }),
							),
							Engine.when(
								model.map(|m| m.word_answer.revealed),
								|| Html.div(
									"word-review-answer",
									[
										Html.p_s(context_text_of(model, |found| Corpus.display_gloss(found.gloss)), [Engine.class("reference-answer")]),
										Html.p_s(model.map(|m| reviewed(m, Model.screen_lemma(m))), [Engine.class("muted")]),
										Html.div(
											"rating-buttons",
											[word_rating(session, Again, "Again"), word_rating(session, Hard, "Hard"), word_rating(session, Good, "Good"), word_rating(session, Easy, "Easy")],
										),
									],
								),
								|| Page.button("Show answer", "primary-button", Page.act(session, |m| { ..m, word_answer: { ..m.word_answer, revealed: Bool.True } })),
							),
							Engine.element(
								"p",
								[Engine.class("today-continue")],
								[
									Engine.element("a", [Engine.attr_s("href", model.map(|m| Route.to_path(Word(Model.screen_lemma(m)))))], [Engine.text("Word page →")]),
									Engine.text(" · "),
									Engine.element("a", [Engine.attr_s("href", model.map(|m| match context(m) { Some(found) => Route.to_path(Study(found.work, found.passage))
										None => "#/" }))], [Engine.text("Open the passage →")]),
								],
							),
						],
					),
				],
			),
			|| Engine.element(
				"main",
				[Engine.class("page word-review-page")],
				[Html.p("No review card yet: words get one when a passage trips you up on them.", "muted"), Engine.element("a", [Engine.attr_s("href", model.map(|m| Route.to_path(Word(Model.screen_lemma(m)))))], [Engine.text("Word page →")])],
			),
		)
	}

	## A lemma: the learner's record with it, the passages where they miss it,
	## and every place it occurs.
	word_page : State(Page.S, Model.Model) -> Elem(Page.S)
	word_page = |session| {
		model = session.signal()
		Engine.element(
			"main",
			[Engine.class("page word-page")],
			[
				Engine.element(
					"section",
					[Engine.class("word-header")],
					[
						Html.p("Word", "eyebrow"),
						Engine.element("h1", [Engine.attr("lang", "grc")], [Engine.text_s(model.map(|m| Corpus.display_lemma(Model.screen_lemma(m))))]),
						Html.div(
							"word-status",
							[
								Html.span_s(model.map(|m| word_status(m, Model.screen_lemma(m))), [Engine.test_id("word-status")]),
								Engine.when(
									model.map(|m| known_action(m, Model.screen_lemma(m)) != ""),
									|| Html.button_s(model.map(|m| known_action(m, Model.screen_lemma(m))), [Engine.class("text-button"), Engine.attr("type", "button")], Page.act(session, toggle_known)),
									|| Engine.text(""),
								),
							],
						),
						Engine.when(
							model.map(|m| m.word_cards.contains(Model.screen_lemma(m))),
							|| Html.div(
								"",
								[
									Html.p_s(model.map(|m| card_summary(m, Model.screen_lemma(m))), [Engine.class("today-summary")]),
									Html.p_s(model.map(|m| match m.word_cards.get(Model.screen_lemma(m)) { Ok(word) => "Forms you've met: ${Str.join_with(word.forms, ", ")}"
										Err(_) => "" }), [Engine.class("muted"), Engine.attr("lang", "grc")]),
									Html.div("today-actions", [Engine.element("a", [Engine.class("primary-button"), Engine.attr_s("href", model.map(|m| Route.to_path(WordReview(Model.screen_lemma(m)))))], [Engine.text("Review now →")])]),
								],
							),
							|| Html.p("No review card yet: words get one when a passage trips you up on them.", "muted"),
						),
					],
				),
				Engine.when(
					model.map(|m| !struggles(m, Model.screen_lemma(m)).is_empty()),
					|| Engine.element(
						"section",
						[Engine.class("word-section")],
						[
							Html.h2("Where you struggle", ""),
							Engine.element(
								"ul",
								[Engine.class("word-occurrences")],
								[Engine.each(model.map(|m| struggles(m, Model.screen_lemma(m))), |place| place.key, |row| occurrence_item(row.field(|place| place)))],
							),
						],
					),
					|| Engine.text(""),
				),
				Engine.element(
					"section",
					[Engine.class("word-section")],
					[
						Engine.switch(
							model.map(
								|m| match m.lemma_index {
									IndexLoaded(_) => "loaded"
									IndexFailed => "failed"
									_ => "loading"
								},
							),
							["loaded", "failed", "loading"],
							|found| match found {
								"loaded" =>
									Html.div_attrs(
										[Engine.attr("style", "display: contents")],
										[
											Engine.element("h2", [], [Engine.text_s(model.map(|m| "Every occurrence · ${everywhere(m, Model.screen_lemma(m)).len().to_str()}"))]),
											Engine.element(
												"ul",
												[Engine.class("word-occurrences")],
												[Engine.each(model.map(|m| occurrences(m, Model.screen_lemma(m))), |place| place.key, |row| occurrence_item(row.field(|place| place)))],
											),
											Engine.when(
												model.map(|m| everywhere(m, Model.screen_lemma(m)).len() > 120),
												|| Html.p_s(model.map(|m| "And ${(everywhere(m, Model.screen_lemma(m)).len() - 120).to_str()} more."), [Engine.class("muted")]),
												|| Engine.text(""),
											),
										],
									)
								"failed" => Html.p("Couldn't load where this word occurs.", "muted")
								_ => Html.p("Finding every occurrence…", "muted")
							},
						),
					],
				),
			],
		)
	}
}

## A passage where the word occurs: its link, a note, and its text with the word highlighted.
Place : { key : Str, path : Str, name : Str, note : Str, text : Str, form : Str }

occurrence_item : Signal(ctx, Place) -> Elem(ctx)
occurrence_item = |place|
	Engine.element(
		"li",
		[],
		[
			Engine.element("a", [Engine.attr_s("href", place.map(|p| p.path))], [Engine.text_s(place.map(|p| p.name))]),
			Html.span_s(place.map(|p| p.note), [Engine.class("muted")]),
			Engine.when(place.map(|p| p.text != ""), || highlighted(place.map(|p| { text: p.text, form: p.form })), || Engine.text("")),
		],
	)

## The passage text with the first word equal to `form` highlighted
## (punctuation ignored).
highlighted : Signal(ctx, { text : Str, form : Str }) -> Elem(ctx)
highlighted = |passage|
	Engine.element(
		"p",
		[Engine.class("word-context"), Engine.attr("lang", "grc")],
		[
			Engine.each(
				passage.map(pieces),
				|piece| piece.key,
				|row| Engine.element(
					"span",
					[],
					[
						Engine.when(row.field(|piece| piece.hit), || Html.span_s(row.field(|piece| piece.text), [Engine.class("context-word")]), || Engine.text_s(row.field(|piece| piece.text))),
						Engine.text(" "),
					],
				),
			),
		],
	)

pieces : { text : Str, form : Str } -> List({ key : Str, text : Str, hit : Bool })
pieces = |passage|
	passage.text.split_on(" ").fold(
		{ found: Bool.False, pieces: [] },
		|state, piece| {
			hit = !state.found and strip_punctuation(piece) == passage.form
			{ found: state.found or hit, pieces: state.pieces.append({ key: state.pieces.len().to_str(), text: piece, hit }) }
		},
	).pieces

strip_punctuation : Str -> Str
strip_punctuation = |piece| [".", ",", ";", ":", "!", "?", "·", "·", ";", "(", ")", "[", "]", "«", "»", "“", "”", "‘", "’", "—", "–", "'", "\""].fold(piece, |rest, mark| rest.replace_each(mark, ""))

today_so_far : Model.Model -> Str
today_so_far = |model| {
	day_start = Review.start_of_day(model.clock)
	graded = model.attempts.keep_if(|attempt| attempt.finished_at >= day_start)
	reviews = model.word_reviews.keep_if(|review| review.at >= day_start)
	judged = graded.join_map(|attempt| attempt.items).keep_if(|item| item.mark != None)
	right = judged.count_if(|item| item.mark == Some(Bool.True))
	tail = if judged.is_empty() "." else ", ${(right * 100 // judged.len()).to_str()}% of answers right."
	"Today so far: ${Model.counted(graded.len(), "passage", "passages")} graded, ${Model.counted(reviews.len(), "word review", "word reviews")}${tail}"
}

reviewed : Model.Model, Str -> Str
reviewed = |model, lemma|
	match model.word_cards.get(lemma) {
		Ok(word) => {
			found = Model.review_context(model, word)
			answer = if found.guess.trim() == "" "" else " Your answer there: ${found.guess}"
			"Reviewed ${Model.counted(word.seen.to_u64_wrap(), "time", "times")}, missed ${word.misses.to_str()}.${answer}"
		}
		Err(_) => ""
	}

word_rating : State(Page.S, Model.Model), Fsrs.Rating, Str -> Elem(Page.S)
word_rating = |session, rating, label| {
	interval = |m|
		match m.word_cards.get(Model.screen_lemma(m)) {
			Ok(word) => match preview(m.clock, word.card) {
				Ok(outcomes) => {
					outcome = match rating {
						Again => outcomes.again
						Hard => outcomes.hard
						Good => outcomes.good
						Easy => outcomes.easy
					}
					Review.interval_label(m.clock, outcome.card.due)
				}
				Err(_) => ""
			}
			Err(_) => ""
		}
	Engine.element(
		"button",
		[Engine.class("rating-button"), Engine.attr("type", "button"), Html.aria_label(label), Engine.on_click(Page.act(session, |m| Nav.rate_word(m, rating)))],
		[Page.strong(label), Html.span_s(session.signal().map(interval), [Engine.class("rating-interval")])],
	)
}

card_summary : Model.Model, Str -> Str
card_summary = |model, lemma|
	match model.word_cards.get(lemma) {
		Ok(known) => {
			next = if known.card.due <= model.clock "Due for review now." else "Next review in ${Review.interval_label(model.clock, known.card.due)}."
			"Reviewed ${Model.counted(known.seen.to_u64_wrap(), "time", "times")}, missed ${known.misses.to_str()}. ${next}"
		}
		Err(_) => ""
	}

## Each passage where the learner missed this lemma: misses, times seen,
## wrong answers, most missed first.
struggles : Model.Model, Str -> List(Place)
struggles = |model, lemma| {
	met = model.attempts
		.join_map(|attempt| attempt.items.keep_if(|item| item.kind == WordItem and item.lemma == lemma and item.mark != None).map(|item| { work: attempt.work, passage: attempt.passage, item, text: attempt.sentence_text }))
		.fold(
			Dict.empty(),
			|found, seen| {
				key = "${seen.work}\t${seen.passage}"
				prior = found.get(key) ?? new_place(seen.work, seen.passage, seen.text, seen.item.form)
				missed = seen.item.mark == Some(Bool.False)
				wrong = if missed and seen.item.guess.trim() != "" and !prior.wrong.contains(seen.item.guess) prior.wrong.append(seen.item.guess) else prior.wrong
				found.insert(key, { ..prior, misses: if (missed) prior.misses + 1 else prior.misses, seen: prior.seen + 1, wrong })
			},
		)
	by_place = sort_by(met.to_list(), |(a, _), (b, _)| compare_bytes(a.to_utf8(), b.to_utf8(), 0))
	sort_by(by_place.map(|(_, record)| record).keep_if(|record| record.misses > 0), |a, b| compare_u64(b.misses, a.misses))
		.map(
			|record| {
				key: "${record.work}/${record.passage}",
				path: Route.to_path(Study(record.work, record.passage)),
				name: Model.passage_name(model, record.work, record.passage),
				note: " · missed ${record.misses.to_str()} of ${record.seen.to_str()}${if record.wrong.is_empty() "" else " · you answered ${Str.join_with(record.wrong, ", ")}"}",
				text: record.text,
				form: record.form,
			},
		)
}

everywhere : Model.Model, Str -> List(Model.Occurrence)
everywhere = |model, lemma|
	match model.lemma_index {
		IndexLoaded(data) => data.lemmas.get(lemma) ?? []
		_ => []
	}

## The first 120 occurrences in the library.
occurrences : Model.Model, Str -> List(Place)
occurrences = |model, lemma|
	match model.lemma_index {
		IndexLoaded(data) =>
			everywhere(model, lemma).take_first(120).map_with_index(
				|found, index| {
					key: index.to_str(),
					path: Route.to_path(Study(found.work, found.ref)),
					name: Model.passage_name(model, found.work, found.ref),
					note: " · ${Corpus.display_gloss(found.gloss)}",
					text: match data.passages.get(found.work) {
						Ok(refs) => refs.get(found.ref) ?? ""
						Err(_) => ""
					},
					form: found.form,
				},
			)
		_ => []
	}

context_text : [Some(Words.Occurrence), None] -> { text : Str, form : Str }
context_text = |found|
	match found {
		Some(occurrence) => { text: occurrence.text, form: occurrence.form }
		None => { text: "", form: "" }
	}

## A stable sort, as Elm's `List.sortBy`.
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

compare_u64 : U64, U64 -> [Before, Same, After]
compare_u64 = |a, b| if a < b Before else if a > b After else Same

## Byte order, which for UTF-8 is code point order.
compare_bytes : List(U8), List(U8), U64 -> [Before, Same, After]
compare_bytes = |a, b, at|
	match (a.get(at), b.get(at)) {
		(Err(_), Err(_)) => Same
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		(Ok(x), Ok(y)) => if x < y Before else if x > y After else compare_bytes(a, b, at + 1)
	}

preview : I64, Fsrs.Card -> Try(Fsrs.Outcomes, Str)
preview = |now, card| Fsrs.preview(Review.scheduler?, now, card)

new_place : Str, Str, Str, Str -> { work : Str, passage : Str, misses : U64, seen : U64, wrong : List(Str), text : Str, form : Str }
new_place = |work, passage, text, form| { work, passage, misses: 0, seen: 0, wrong: [], text, form }

mode : Model.Model -> Today.Mode
mode = |model| Model.with_default(model.today_mode, Everything)

## The occurrence the word under review is quizzed in.
context : Model.Model -> [Some(Words.Occurrence), None]
context = |model|
	match model.word_cards.get(Model.screen_lemma(model)) {
		Ok(word) => Some(Model.review_context(model, word))
		Err(_) => None
	}

context_field : Model.Model, (Words.Occurrence -> Str) -> Str
context_field = |model, pick|
	match context(model) {
		Some(found) => pick(found)
		None => ""
	}

context_text_of : Signal(Page.S, Model.Model), (Words.Occurrence -> Str) -> Signal(Page.S, Str)
context_text_of = |model, pick| model.map(|m| context_field(m, pick))

## Whether the learner knows the word (see Reading.statuses).
word_status : Model.Model, Str -> Str
word_status = |model, lemma| {
	marked = model.known_marks.contains(lemma)
	match Model.known_words(model).get(lemma) {
		Ok(Known) => if marked "Known: you marked it." else "Known: recalled right on days three weeks apart."
		Ok(Learning) => "Learning: known once recalled right on days three weeks apart."
		Err(_) => "New to you."
	}
}

## The toggle for marking the word known: none once it is known by recall.
known_action : Model.Model, Str -> Str
known_action = |model, lemma|
	match (Model.known_words(model).get(lemma), model.known_marks.contains(lemma)) {
		(Ok(Known), Bool.True) => "Unmark"
		(Ok(Known), Bool.False) => ""
		_ => "I already know this word"
	}

toggle_known : Model.Model -> Model.Model
toggle_known = |model| {
	lemma = Model.screen_lemma(model)
	Nav.set_known(model, lemma, known_action(model, lemma) != "Unmark")
}
