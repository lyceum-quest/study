module Route exposing (Route(..), fromUrl, query, toPath)

import Dict exposing (Dict)
import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), Parser, oneOf, s, string, top)


{-| Passages are addressed by their canonical citation, dotted (`1.2` for 1:2, `1.1.1` for a section).
-}
type Route
    = Library
    | Settings
    | WorkLanding String
    | Study String String
    | Reader String (Maybe String)
    | Word String
    | WordReview String
    | Stats
    | Today
    | WhatsNew


{-| Routes live in the URL fragment (`/#/luke/5?word=7`), so the static server only ever serves `/` and every link or reload works without a server-side fallback.
-}
fromUrl : Url -> Maybe Route
fromUrl url =
    Parser.parse parser { url | path = Tuple.first (fragmentParts url), query = Nothing, fragment = Nothing }


{-| Page state (open popup, tab, tool) carried in the fragment's query string.
-}
query : Url -> Dict String String
query url =
    Tuple.second (fragmentParts url)
        |> String.split "&"
        |> List.filterMap
            (\pair ->
                case String.split "=" pair of
                    [ key, value ] ->
                        Maybe.map2 Tuple.pair (Url.percentDecode key) (Url.percentDecode value)

                    _ ->
                        Nothing
            )
        |> Dict.fromList


fragmentParts : Url -> ( String, String )
fragmentParts url =
    case String.split "?" (Maybe.withDefault "/" url.fragment) of
        path :: rest ->
            ( path, String.join "?" rest )

        [] ->
            ( "/", "" )


parser : Parser (Route -> a) a
parser =
    oneOf
        [ Parser.map Library top
        , Parser.map Settings (s "settings")
        , Parser.map Stats (s "stats")
        , Parser.map Today (s "today")
        , Parser.map WhatsNew (s "whats-new")
        , Parser.map Word (s "word" </> lemma)
        , Parser.map WordReview (s "review" </> s "word" </> lemma)
        , Parser.map (\work passage -> Reader work (Just passage)) (string </> s "read" </> string)
        , Parser.map (\work -> Reader work Nothing) (string </> s "read")
        , Parser.map Study (string </> string)
        , Parser.map WorkLanding string
        ]


{-| A lemma path segment, percent-decoded (lemmas are Greek).
-}
lemma : Parser (String -> a) a
lemma =
    Parser.map (\raw -> Url.percentDecode raw |> Maybe.withDefault raw) string


toPath : Route -> String
toPath route =
    "#"
        ++ (case route of
                Library ->
                    "/"

                Settings ->
                    "/settings"

                WorkLanding work ->
                    "/" ++ work

                Study work passage ->
                    "/" ++ work ++ "/" ++ passage

                Word name ->
                    "/word/" ++ Url.percentEncode name

                WordReview name ->
                    "/review/word/" ++ Url.percentEncode name

                Stats ->
                    "/stats"

                WhatsNew ->
                    "/whats-new"

                Today ->
                    "/today"

                Reader work passage ->
                    "/" ++ work ++ "/read" ++ (passage |> Maybe.map (\ref -> "/" ++ ref) |> Maybe.withDefault "")
           )
