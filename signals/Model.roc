import fsrs.Fsrs
import json.JsonValue
import study.Account
import study.Changelog
import study.Corpus
import study.Review
import study.Route
import study.Study
import study.Sync
import study.Today
import study.Tools
import study.Words
import Store

## The app's state, ported from the `Model` of `src/Main.elm`, and what the
## views and transitions derive from it. The transitions live in Nav (routes
## and loading), Workspace (studying a passage), Storage (IndexedDB results)
## and Update (what follows every transition, as Elm's `update`).
##
## Storage requests leave through `outbox` (see Store): a transition queues
## them with `send`, and Update joins them into one batch. Results carry the
## only wall clock the app has (`clock`) and the browser's UTC offset.
## Workaround: roc-signals 0.3.0 gives apps no clock or time zone
## (https://github.com/lukewilliamboswell/roc-signals/issues/200, closed in
## favour of #216, which adds the time at boot and when a timer fires; roc-issues
## archive/RS-001-wall-clock-time); take both from the platform once it does.
Model := [].{

	Screen : [LibraryScreen, WorkspaceScreen, SettingsScreen, ReaderScreen, TodayScreen, WordScreen(Str), WordReviewScreen(Str), StatsScreen, WhatsNewScreen]

	PopupTab : [WordTab, SentenceTab]

	## An HTTP call to the account API: issued when `serial` changes.
	Call : { serial : U64, request : Account.HttpRequest }

	no_call : Call
	no_call = { serial: 0, request: { method: "GET", url: "", headers: [], body: "", timeout_ms: 0 } }

	## What the reader shows with each passage, remembered in IndexedDB.
	ReaderLayers : { glosses : Bool, morphology : Bool, translation : Bool }

	## Every word occurrence across the library (`preload/lemmas.json`), for word pages.
	Occurrence : { work : Str, ref : Str, position : I64, form : Str, gloss : Str }

	LemmaData : { lemmas : Dict(Str, List(Occurrence)), passages : Dict(Str, Dict(Str, Str)) }

	LemmaIndex : [IndexNotLoaded, IndexLoading, IndexLoaded(LemmaData), IndexFailed]

	ChangelogState : [ChangelogNotLoaded, ChangelogLoading, ChangelogLoaded(List(Changelog.Version)), ChangelogFailed]

	Model : {
		screen : Screen,
		# The library (`corpora.json`) and the open work.
		works : List(Corpus.Work),
		manifest_loaded : Bool,
		active : [Some(Corpus.Work), None],
		passages : List(Corpus.Passage),
		corpus_ready : Bool,
		requested_work : [Some(Str), None],
		pending_route : [Some(Route.Route), None],
		# A downloaded work waits here until both of its files have arrived.
		fetched_conllu : [Some(Str), None],
		fetched_units : [Some(Str), None],
		fetch_serial : U64,
		# The work whose files came from the network (not the cache) this session.
		network_work : Str,
		sentence_index : U64,
		# Studying a passage.
		preset : Tools.Preset,
		settings : Tools.ModuleSettings,
		active_module : [Some(Tools.ModuleId), None],
		study : Study.Draft,
		all_words : Bool,
		popup_word : [Some(U64), None],
		popup_tab : PopupTab,
		history_open : Bool,
		history_attempt : [Some(I64), None],
		queue_mode : Bool,
		queue_done : Bool,
		work_finished : Bool,
		# A rating waits for storage to report the time.
		pending_rating : [Some(Fsrs.Rating), None],
		pending_word_rating : [Some((Str, Fsrs.Rating)), None],
		# Progress.
		attempts : List(Study.Attempt),
		entries : Dict(Str, Review.Entry),
		word_reviews : List(Words.Review),
		word_cards : Dict(Str, Words.Card),
		progress_loaded : Bool,
		positions : Dict(Str, I64),
		new_per_day : I64,
		extra_new : { day : I64, count : I64 },
		today_mode : [Some(Today.Mode), None],
		today_scope : [Some(Str), None],
		word_answer : { guess : Str, revealed : Bool },
		# The reader.
		reader_gloss : [Some((U64, U64)), None],
		reader_revealed : Set(U64),
		reader_layers : ReaderLayers,
		# Other pages.
		lemma_index : LemmaIndex,
		changelog : ChangelogState,
		search : Str,
		sort : Str,
		confirm_clear : Bool,
		# The optional Lyceum account (config.json names its API) and syncing
		# progress with it. Each HTTP call is issued when its `serial` changes.
		account : Account,
		session_call : Call,
		sign_out_call : Call,
		sync_call : Call,
		sync : Sync.State,
		sync_sent : List(Sync.Outgoing),
		sync_loaded : Bool,
		sync_requested : Bool,
		sync_status : Sync.Status,
		sync_busy : Bool,
		# Sync at this clock time (after a rating); 0 when nothing waits.
		sync_due_at : I64,
		account_checked_at : I64,
		# This page's URL without its fragment, where sign-in returns.
		app_url : Str,
		# The page.
		dark : Bool,
		notice : Str,
		query : Dict(Str, Str),
		current_path : Str,
		url : { path : Str, push : Bool, serial : U64 },
		clock : I64,
		offset : I64,
		requests : List(JsonValue),
		outbox : Str,
		serial : U64,
	}

	## The state before anything has loaded, at the URL `location`. Nav.init
	## applies the route.
	empty : Str -> Model.Model
	empty = |location| {
		screen: LibraryScreen,
		works: [],
		manifest_loaded: Bool.False,
		active: None,
		passages: [],
		corpus_ready: Bool.False,
		requested_work: None,
		pending_route: None,
		fetched_conllu: None,
		fetched_units: None,
		fetch_serial: 0,
		network_work: "",
		sentence_index: 0,
		preset: Tools.default_preset,
		settings: Tools.assisted_settings,
		active_module: None,
		study: Study.empty_draft,
		all_words: Bool.False,
		popup_word: None,
		popup_tab: WordTab,
		history_open: Bool.False,
		history_attempt: None,
		queue_mode: Bool.False,
		queue_done: Bool.False,
		work_finished: Bool.False,
		pending_rating: None,
		pending_word_rating: None,
		attempts: [],
		entries: Dict.empty(),
		word_reviews: [],
		word_cards: Dict.empty(),
		progress_loaded: Bool.False,
		positions: Dict.empty(),
		new_per_day: Review.new_per_day_default,
		extra_new: { day: 0, count: 0 },
		today_mode: None,
		today_scope: None,
		word_answer: { guess: "", revealed: Bool.False },
		reader_gloss: None,
		reader_revealed: Set.empty(),
		reader_layers: { glosses: Bool.True, morphology: Bool.True, translation: Bool.True },
		lemma_index: IndexNotLoaded,
		changelog: ChangelogNotLoaded,
		search: "",
		sort: "recent",
		confirm_clear: Bool.False,
		account: NotConfigured,
		session_call: no_call,
		sign_out_call: no_call,
		sync_call: no_call,
		sync: Sync.empty_state(0),
		sync_sent: [],
		sync_loaded: Bool.False,
		sync_requested: Bool.False,
		sync_status: NotSyncing,
		sync_busy: Bool.False,
		sync_due_at: 0,
		account_checked_at: 0,
		app_url: match location.split_first("#") {
			Ok({ before, .. }) => before
			Err(_) => location
		},
		dark: Bool.True,
		notice: "",
		query: Route.query(location),
		current_path: url_path(location),
		url: { path: url_path(location), push: Bool.False, serial: 0 },
		clock: 0,
		offset: 0,
		requests: [],
		outbox: "",
		serial: 1,
	}

	## Queue storage requests, numbering their ids `<purpose>:<n>`.
	send : Model.Model, List((Str, (Str -> JsonValue))) -> Model.Model
	send = |model, requests| {
		messages = requests.map_with_index(|(purpose, build), index| build("${purpose}:${(model.serial + index).to_str()}"))
		{ ..model, requests: model.requests.concat(messages), serial: model.serial + requests.len() }
	}

	## A `metadata` setting saved as the Elm app saves it.
	put_setting : Model.Model, Str, Str, JsonValue -> Model.Model
	put_setting = |model, purpose, key, value| send(model, [(purpose, |id| Store.put(id, "metadata", Store.setting(key, value)))])

	# THE OPEN WORK

	current_passage : Model.Model -> Corpus.Passage
	current_passage = |model| Corpus.passage_at(model.passages, model.sentence_index)

	## The current passage's citation (`1.2`), which keys drafts, attempts, review cards, and URLs.
	current_ref : Model.Model -> Str
	current_ref = |model| current_passage(model).id

	## The current passage's display citation (`1:2`, `1.1.1`).
	current_label : Model.Model -> Str
	current_label = |model| current_passage(model).label

	active_id : Model.Model -> Str
	active_id = |model|
		match model.active {
			Some(work) => work.id
			None => ""
		}

	work_title : Model.Model -> Str
	work_title = |model|
		match model.active {
			Some(work) => work.title
			None => ""
		}

	entry_for : Model.Model, Str -> [Some(Corpus.Work), None]
	entry_for = |model, id|
		match model.works.find_first(|work| work.id == id) {
			Ok(work) => Some(work)
			Err(_) => None
		}

	work_name : Model.Model, Str -> Str
	work_name = |model, id|
		match entry_for(model, id) {
			Some(work) => work.title
			None => id
		}

	passage_name : Model.Model, Str, Str -> Str
	passage_name = |model, work, ref| "${work_name(model, work)} ${Corpus.ref_label(model.works, work, ref)}"

	## The IndexedDB key of the current passage's draft, once its work has loaded.
	draft_key : Model.Model -> [Some(Str), None]
	draft_key = |model|
		match model.active {
			Some(work) if model.corpus_ready => Some(Study.draft_key(work.id, current_ref(model)))
			_ => None
		}

	# TODAY

	## Today's new-passage limit: the daily setting plus whatever "Learn more" added today.
	new_limit : Model.Model -> I64
	new_limit = |model| if model.extra_new.day == Review.start_of_day(model.clock) model.new_per_day + model.extra_new.count else model.new_per_day

	## How many new passages one "Learn more" adds.
	learn_more_step : Model.Model -> I64
	learn_more_step = |model| model.new_per_day.max(1)

	## The open work's queue for today.
	today_queue : Model.Model -> [Some(Review.Queue), None]
	today_queue = |model|
		match model.active {
			Some(work) => Some(Review.queue(model.clock, new_limit(model), work.id, model.passages.map(|passage| passage.id), model.entries))
			None => None
		}

	## Today's session across every work (see Today).
	today_plan : Model.Model -> Today.Plan
	today_plan = |model|
		Today.plan(model.clock, new_limit(model), model.today_scope, Today.last_work(model.attempts), model.works.map(|work| { id: work.id, passages: work.passages }), model.entries, model.word_cards)

	## Whether "Learn more" would find unseen passages: in the open work during a
	## work's queue, else in today's scope.
	more_to_learn : Model.Model -> Bool
	more_to_learn = |model| {
		more = { ..model, extra_new: { day: Review.start_of_day(model.clock), count: model.extra_new.count + learn_more_step(model) + 100000 } }
		if model.queue_mode {
			match today_queue(more) {
				Some(queue) => !queue.new.is_empty()
				None => Bool.False
			}
		} else {
			!today_plan(more).new.is_empty()
		}
	}

	## The occurrence to quiz a word in: when studying one work, its latest occurrence there.
	review_context : Model.Model, Words.Card -> Words.Occurrence
	review_context = |model, word| Words.review_context(model.today_scope, word)

	ref_label : Model.Model, Str, Str -> Str
	ref_label = |model, work, ref| Corpus.ref_label(model.works, work, ref)

	item_name : Model.Model, Today.Item -> Str
	item_name = |model, item|
		match item {
			WordItem(lemma) => Corpus.display_lemma(lemma)
			PassageItem(work, passage) => passage_name(model, work, passage)
		}

	item_path : Today.Mode, Today.Item -> Str
	item_path = |mode, item| {
		path = match item {
			WordItem(lemma) => Route.to_path(WordReview(lemma))
			PassageItem(work, passage) => Route.to_path(Study(work, passage))
		}
		"${path}?today=${Today.mode_to_str(mode)}"
	}

	# THE PAGE

	document_title : Model.Model -> Str
	document_title = |model|
		match (model.screen, model.active) {
			(LibraryScreen, _) => "Lyceum Study · Greek reading workspace"
			(SettingsScreen, _) => "Study tools · Lyceum Study"
			(TodayScreen, _) => "Today · Lyceum Study"
			(StatsScreen, _) => "Progress · Lyceum Study"
			(WhatsNewScreen, _) => "What's new · Lyceum Study"
			(WordScreen(lemma), _) => "${Corpus.display_lemma(lemma)} · Lyceum Study"
			(WordReviewScreen(lemma), _) => "Review ${Corpus.display_lemma(lemma)} · Lyceum Study"
			(_, Some(work)) => "${work.title} ${current_label(model)} · Lyceum Study"
			(_, None) => "Lyceum Study"
		}

	## The route part of a URL in the form `path_for` produces: `#/…`, with the fragment's query.
	url_path : Str -> Str
	url_path = |url|
		match url.split_first("#") {
			Ok({ after, .. }) => if after == "" "#/" else "#${after}"
			Err(_) => "#/"
		}

	## `12 Nov 2026, 09:05` in the browser's time zone (`formatDate`).
	format_date : Model.Model, I64 -> Str
	format_date = |model, millis| {
		local = millis + model.offset * 60000
		day_ms = 86400000
		days = floor_div(local, day_ms)
		minutes_of_day = (local - days * day_ms) // 60000
		date = civil(days)
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
		"${date.day.to_str()} ${month} ${date.year.to_str()}, ${two_digits(minutes_of_day // 60)}:${two_digits(minutes_of_day % 60)}"
	}

	## Whether this device syncs: signed in to an account that includes sync.
	syncs_progress : Model.Model -> Bool
	syncs_progress = |model|
		match model.account {
			SignedIn(_, user) => Account.has_sync(user)
			_ => Bool.False
		}

	## The lemma of a word page or word review.
	screen_lemma : Model.Model -> Str
	screen_lemma = |model|
		match model.screen {
			WordScreen(lemma) | WordReviewScreen(lemma) => lemma
			_ => ""
		}

	## In today's session: how much is left.
	session_status : Model.Model -> Str
	session_status = |model| {
		today = today_plan(model)
		scope = match model.today_scope {
			Some(work) => "${work_name(model, work)} · "
			None => ""
		}
		"Today · ${scope}${counted(today.words.len(), "word", "words")} · ${counted(today.due.len() + today.new.len(), "passage", "passages")} left"
	}

	## The value of `Some`, else `fallback`.
	with_default : [Some(a), None], a -> a
	with_default = |found, fallback|
		match found {
			Some(value) => value
			None => fallback
		}

	plural : U64, Str, Str -> Str
	plural = |count, one, many| if count == 1 one else many

	## `3 words`, `1 word`.
	counted : U64, Str, Str -> Str
	counted = |count, one, many| "${count.to_str()} ${plural(count, one, many)}"
}

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

two_digits : I64 -> Str
two_digits = |n| if n < 10 "0${n.to_str()}" else n.to_str()
