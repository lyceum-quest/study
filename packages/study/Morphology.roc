## Short learner-facing morphology tags from OGA's AGDT part of speech and
## features, ported from `src/Morphology.elm`: `aor act ind 3pl`,
## `pf m/p ptc gen pl n`, `art gen pl n`, `nom sg m` (nouns carry no
## part-of-speech label), `prep`.
Morphology := [].{

	## The tag for a token's part of speech (`v`, `n`, ...) and features
	## (`Case=g|Number=p|Gender=n`). Empty for punctuation and tokens without an
	## analysis.
	abbreviation : Str, Str -> Str
	abbreviation = |pos, feats| {
		features = parse(feats)
		get = |key, table| match features.get(key) {
			Ok(code) => lookup(code, table)
			Err(_) => ""
		}
		person = get("Person", persons)
		nominal = [
			get("Case", cases),
			number(get("Number", numbers), person),
			if person == "1" or person == "2" "" else get("Gender", genders),
		]
		person_number = "${person}${get("Number", numbers)}"
		verbal = [get("Tense", tenses), get("Voice", voices), get("Mood", moods)]
		parts = match pos {
			"v" =>
				if features.get("Mood") == Ok("p") {
					verbal.concat([get("Case", cases), get("Number", numbers), get("Gender", genders)])
				} else {
					verbal.append(person_number)
				}
			"n" => nominal
			"a" => ["adj"].concat(nominal).append(get("Degree", degrees))
			"l" => ["art"].concat(nominal)
			"p" => ["pron"].concat(nominal)
			"m" => ["num"].concat(nominal)
			"d" => ["adv", get("Degree", degrees)]
			"r" => ["prep"]
			"c" => ["conj"]
			"g" => ["ptcl"]
			"i" => ["intj"]
			_ => []
		}
		Str.join_with(parts.keep_if(|part| !part.is_empty()), " ")
	}
}

## Pronouns of the first and second person carry person with number (`1pl`) and no gender.
number : Str, Str -> Str
number = |count, person| if person == "1" or person == "2" "${person}${count}" else count

## `Key=value` pairs separated by `|`; malformed pairs are skipped, and a
## repeated key keeps its last value, as Elm's `Dict.fromList`.
parse : Str -> Dict(Str, Str)
parse = |feats|
	feats.split_on("|").fold(
		Dict.empty(),
		|found, pair| match pair.split_on("=") {
			[key, value] => found.insert(key, value)
			_ => found
		},
	)

## The label for a code, or "" for an unknown one.
lookup : Str, List((Str, Str)) -> Str
lookup = |code, table| match table.keep_if(|(key, _)| key == code) {
	[(_, label), ..] => label
	[] => ""
}

cases : List((Str, Str))
cases = [("n", "nom"), ("g", "gen"), ("d", "dat"), ("a", "acc"), ("v", "voc"), ("l", "loc")]

numbers : List((Str, Str))
numbers = [("s", "sg"), ("p", "pl"), ("d", "du")]

genders : List((Str, Str))
genders = [("m", "m"), ("f", "f"), ("n", "n"), ("c", "m/f")]

persons : List((Str, Str))
persons = [("1", "1"), ("2", "2"), ("3", "3")]

tenses : List((Str, Str))
tenses = [("p", "pres"), ("i", "impf"), ("f", "fut"), ("a", "aor"), ("r", "pf"), ("l", "plpf"), ("t", "fut pf")]

voices : List((Str, Str))
voices = [("a", "act"), ("m", "mid"), ("p", "pass"), ("e", "m/p")]

moods : List((Str, Str))
moods = [("i", "ind"), ("s", "subj"), ("o", "opt"), ("n", "inf"), ("m", "impv"), ("p", "ptc")]

degrees : List((Str, Str))
degrees = [("c", "comp"), ("s", "superl")]
