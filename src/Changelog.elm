module Changelog exposing (Section, Version, parse)

{-| CHANGELOG.md, as the What's new page shows it. The file follows a small part of Keep a Changelog:
`## [version]` headings, `### Section` headings, and `- item` bullets (continued on indented lines). Internal
sections and HTML comments (release drafts) are left out, and so are versions with nothing left to show. Items are
plain text: `**bold**`, backticks, and `[text](url)` keep only their text.
-}


type alias Version =
    { name : String, sections : List Section }


type alias Section =
    { title : String, items : List String }


type alias State =
    { versions : List Version, inComment : Bool, internal : Bool, item : Maybe String }


parse : String -> List Version
parse text =
    String.lines text
        |> List.foldl step { versions = [], inComment = False, internal = False, item = Nothing }
        |> flush
        |> .versions
        |> List.reverse
        |> List.map (\v -> { v | sections = List.reverse v.sections |> List.map (\s -> { s | items = List.reverse s.items }) |> List.filter (\s -> not (List.isEmpty s.items)) })
        |> List.filter (\v -> not (List.isEmpty v.sections))


step : String -> State -> State
step line state =
    let
        trimmed =
            String.trim line
    in
    if state.inComment then
        { state | inComment = not (String.contains "-->" trimmed) }

    else if String.startsWith "<!--" trimmed then
        flush { state | inComment = not (String.contains "-->" trimmed) }

    else if String.startsWith "## " trimmed then
        let
            name =
                String.dropLeft 3 trimmed |> String.trim |> String.replace "[" "" |> String.replace "]" ""
        in
        flushed state (\s -> { s | versions = { name = name, sections = [] } :: s.versions, internal = False })

    else if String.startsWith "### " trimmed then
        let
            title =
                String.dropLeft 4 trimmed |> String.trim
        in
        flushed state
            (\s ->
                { s
                    | internal = String.toLower title == "internal"
                    , versions = mapFirst (\v -> { v | sections = { title = title, items = [] } :: v.sections }) s.versions
                }
            )

    else if String.startsWith "- " trimmed then
        let
            started =
                flush state
        in
        if List.isEmpty started.versions then
            started

        else
            { started
                | item = Just (String.dropLeft 2 trimmed)
                , versions =
                    mapFirst
                        (\v ->
                            if List.isEmpty v.sections then
                                { v | sections = [ { title = "", items = [] } ] }

                            else
                                v
                        )
                        started.versions
            }

    else if trimmed == "" then
        flush state

    else
        case state.item of
            Just item ->
                { state | item = Just (item ++ " " ++ trimmed) }

            Nothing ->
                state


flushed : State -> (State -> State) -> State
flushed state f =
    f (flush state)


flush : State -> State
flush state =
    case state.item of
        Just item ->
            if state.internal then
                { state | item = Nothing }

            else
                { state
                    | item = Nothing
                    , versions = mapFirst (\v -> { v | sections = mapFirst (\s -> { s | items = plain item :: s.items }) v.sections }) state.versions
                }

        Nothing ->
            state


mapFirst : (a -> a) -> List a -> List a
mapFirst f list =
    case list of
        first :: rest ->
            f first :: rest

        [] ->
            []


{-| Markdown's markers off: `**`, backticks, and `[text](url)` to `text`.
-}
plain : String -> String
plain s =
    links (s |> String.replace "**" "" |> String.replace "`" "")


links : String -> String
links s =
    case String.indexes "](" s of
        close :: _ ->
            let
                before =
                    String.left close s

                open =
                    String.indexes "[" before |> List.reverse |> List.head

                rest =
                    String.dropLeft (close + 2) s

                end =
                    String.indexes ")" rest |> List.head
            in
            case ( open, end ) of
                ( Just o, Just e ) ->
                    links (String.left o before ++ String.dropLeft (o + 1) before ++ String.dropLeft (e + 1) rest)

                _ ->
                    s

        [] ->
            s
