import json.JsonValue
import study.Corpus
import study.Morphology
import study.Study
import Model

## Reading a work, ported from the reader branches of `updateModel` and
## `handleShortcut` in `src/Main.elm`: a word's gloss on tap, a passage's
## translation on its marker, the layers shown with the Greek, and stepping
## between passages.
##
## Not ported: the Elm reader follows scrolling (`ReaderScrolled`,
## `ReaderSettled`, `ReaderMeasured` make the passage at the top current) and
## swipes between passages; roc-signals 0.5.0 cannot measure layout
## (https://github.com/lukewilliamboswell/roc-signals/issues/204, closed in
## favour of #211, #213 and #214; roc-issues archive/RS-005-layout-measurement).
## Add both once the app is on a release that has those.
Reader := [].{

	Layer : [GlossLayer, MorphologyLayer, TranslationLayer]

	## One passage of the reader, as `viewReaderSentence` draws it.
	Sentence : {
		key : Str,
		index : U64,
		label : Str,
		current : Bool,
		revealed : Bool,
		interlinear : Bool,
		translation : Bool,
		prose : Str,
		literal : Str,
		words : List(Reader.Word),
		tokens : List(Reader.Token),
	}

	## A word of the interlinear with its following punctuation (`viewReaderWord`).
	Word : { key : Str, greek : Str, gloss : [Some(Str), None], morphology : [Some(Str), None] }

	## A token of the plain Greek, tappable for its gloss (`viewReaderToken`).
	Token : { key : Str, sentence : U64, id : U64, form : Str, space : Bool, open : Bool, gloss : Str }

	## Tapping a word shows its gloss (tapping it again hides it) and makes its passage current.
	tap_token : Model.Model, U64, U64 -> Model.Model
	tap_token = |model, sentence, token| {
		..model,
		reader_gloss: if model.reader_gloss == Some((sentence, token)) None else Some((sentence, token)),
		sentence_index: sentence,
	}

	## A passage's marker shows its translation, with the literal one, or hides it.
	toggle_translation : Model.Model, U64 -> Model.Model
	toggle_translation = |model, sentence| {
		..model,
		reader_revealed: if model.reader_revealed.contains(sentence) model.reader_revealed.remove(sentence) else model.reader_revealed.insert(sentence),
		sentence_index: sentence,
	}

	## Switches a layer and remembers the layers where the Elm app keeps them.
	toggle_layer : Model.Model, Reader.Layer -> Model.Model
	toggle_layer = |model, layer| {
		current = model.reader_layers
		layers = match layer {
			GlossLayer => { ..current, glosses: !current.glosses }
			MorphologyLayer => { ..current, morphology: !current.morphology }
			TranslationLayer => { ..current, translation: !current.translation }
		}
		value = JsonValue.object(
			[
				("glosses", JsonValue.boolean(layers.glosses)),
				("morphology", JsonValue.boolean(layers.morphology)),
				("translation", JsonValue.boolean(layers.translation)),
			],
		)
		Model.put_setting({ ..model, reader_layers: layers, reader_gloss: None }, "save", "reader-layers", value)
	}

	## The passage `delta` away, within the work.
	step : Model.Model, I64 -> Model.Model
	step = |model, delta| {
		last = model.passages.len().to_i64_wrap() - 1
		target = (model.sentence_index.to_i64_wrap() + delta).min(last).max(0)
		{ ..model, sentence_index: target.to_u64_wrap(), reader_gloss: None }
	}

	## Escape closes an open gloss, else leaves for the workspace.
	escape : Model.Model -> Model.Model
	escape = |model|
		if model.reader_gloss != None {
			{ ..model, reader_gloss: None }
		} else {
			{ ..model, screen: WorkspaceScreen }
		}

	## "Study this passage" (`ShowWorkspace`).
	show_workspace : Model.Model -> Model.Model
	show_workspace = |model|
		if model.corpus_ready {
			{ ..model, screen: WorkspaceScreen, notice: "" }
		} else {
			{ ..model, notice: "The local corpus is still loading." }
		}

	show_library : Model.Model -> Model.Model
	show_library = |model| { ..model, screen: LibraryScreen, notice: "", popup_word: None }

	# VIEW DATA

	## `1:3 · 3 / 13`.
	position : Model.Model -> Str
	position = |model| "${Model.current_label(model)} · ${(model.sentence_index + 1).to_str()} / ${model.passages.len().to_str()}"

	sentences : Model.Model -> List(Reader.Sentence)
	sentences = |model| {
		layers = model.reader_layers
		interlinear = layers.glosses or layers.morphology
		model.passages.map_with_index(
			|passage, index| {
				revealed = model.reader_revealed.contains(index)
				{
					key: index.to_str(),
					index,
					label: passage.label,
					current: index == model.sentence_index,
					revealed,
					interlinear,
					translation: (layers.translation or revealed) and passage.prose != "",
					prose: passage.prose,
					literal: if revealed passage.literal else "",
					words: if interlinear words(passage, layers) else [],
					tokens: if interlinear [] else tokens(model, index, passage),
				}
			},
		)
	}
}

words : Corpus.Passage, Model.ReaderLayers -> List(Reader.Word)
words = |passage, layers|
	Study.group_words(passage.tokens).map(
		|(token, suffix)| {
			key: token.id.to_str(),
			greek: "${token.form}${suffix}",
			gloss: if layers.glosses Some(Corpus.display_gloss(token.gloss)) else None,
			morphology: if layers.morphology Some(Morphology.abbreviation(token.upos, token.morphology.summary)) else None,
		},
	)

tokens : Model.Model, U64, Corpus.Passage -> List(Reader.Token)
tokens = |model, sentence, passage|
	passage.tokens.map_with_index(
		|token, position| {
			key: token.id.to_str(),
			sentence,
			id: token.id,
			form: token.form,
			space: position > 0 and !is_punctuation(token.form),
			open: model.reader_gloss == Some((sentence, token.id)),
			gloss: if token.gloss == "" "No gloss" else token.gloss.replace_each("-", " "),
		},
	)

## The reader's own test for punctuation (`isPunctuation`), which keeps a space
## before opening brackets and quotes.
is_punctuation : Str -> Bool
is_punctuation = |form|
	form != "" and [".", ",", ";", ":", "!", "?", "\u(00B7)", "\u(0387)", "\u(037E)", ")", "]", "\u(00BB)", "\u(201D)", "\u(2019)", "\u(2014)", "\u(2013)"].fold(form, |rest, mark| rest.replace_each(mark, "")) == ""
