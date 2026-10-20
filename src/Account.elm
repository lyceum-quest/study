module Account exposing (Account(..), User, api, checkSession, clientHeader, fetchConfig, hasSync, loginHref, signOut)

{-| The optional Lyceum account (see `docs/dev_guide/auth-pattern.md`, "Apps on subdomains", in the Lyceum website).

`/config.json`, written into each release, names the account API's origin; without one Lyceum Study shows no sign-in.
Sign-in happens on Lyceum's own pages: Lyceum Study only asks `/api/me` who is signed in (sending the shared session
cookie) and links to Lyceum's login page with a `return` URL. A Supporter's progress syncs through it (see `Sync`).

-}

import Http
import Json.Decode as Decode
import Url


type Account
    = NotConfigured
    | Checking String
    | SignedOut String String
    | SignedIn String User
    | Unreachable String


{-| The account API origin, once the config has named one.
-}
api : Account -> Maybe String
api account =
    case account of
        NotConfigured ->
            Nothing

        Checking origin ->
            Just origin

        SignedOut origin _ ->
            Just origin

        SignedIn origin _ ->
            Just origin

        Unreachable origin ->
            Just origin


{-| Only the fields Lyceum documents for apps.
-}
type alias User =
    { id : Int
    , handle : String
    , pro : Bool
    , entitlements : List String
    }


{-| Sent with every API call; state-changing calls from an app origin are refused without it.
-}
clientHeader : Http.Header
clientHeader =
    Http.header "X-Lyceum-Client" "aristos/1"


{-| `Ok Nothing` when the config names no account API. A missing or unreadable `config.json` (the local preview
without one) is an error, which callers treat the same way.
-}
fetchConfig : (Result Http.Error (Maybe String) -> msg) -> Cmd msg
fetchConfig toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Cache-Control" "no-cache" ]
        , url = "/config.json"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


configDecoder : Decode.Decoder (Maybe String)
configDecoder =
    Decode.maybe (Decode.field "accountApi" Decode.string)
        |> Decode.map
            (Maybe.map (\origin -> String.trim origin |> dropTrailingSlash)
                >> Maybe.andThen
                    (\origin ->
                        if String.isEmpty origin then
                            Nothing

                        else
                            Just origin
                    )
            )


dropTrailingSlash : String -> String
dropTrailingSlash value =
    if String.endsWith "/" value then
        String.dropRight 1 value

    else
        value


{-| `GET <origin>/api/me` with credentials; any failure (offline, blocked, server down) is `Unreachable`.
-}
checkSession : String -> (Account -> msg) -> Cmd msg
checkSession origin toMsg =
    Http.riskyRequest
        { method = "GET"
        , headers = [ clientHeader ]
        , url = origin ++ "/api/me"
        , body = Http.emptyBody
        , expect =
            Http.expectJson
                (\result ->
                    toMsg
                        (case result of
                            Ok account ->
                                account

                            Err _ ->
                                Unreachable origin
                        )
                )
                (meDecoder origin)
        , timeout = Just 15000
        , tracker = Nothing
        }


meDecoder : String -> Decode.Decoder Account
meDecoder origin =
    Decode.field "user"
        (Decode.nullable
            (Decode.map4 User
                (Decode.field "id" Decode.int)
                (Decode.field "handle" Decode.string)
                (Decode.oneOf [ Decode.field "pro" Decode.bool, Decode.succeed False ])
                (Decode.oneOf [ Decode.field "entitlements" (Decode.list Decode.string), Decode.succeed [] ])
            )
        )
        |> Decode.andThen
            (\user ->
                case user of
                    Just found ->
                        Decode.succeed (SignedIn origin found)

                    Nothing ->
                        Decode.map (SignedOut origin) (Decode.field "login_url" Decode.string)
            )


{-| `POST <origin>/api/logout`; the caller asks `/api/me` again whatever the result.
-}
signOut : String -> msg -> Cmd msg
signOut origin done =
    Http.riskyRequest
        { method = "POST"
        , headers = [ clientHeader ]
        , url = origin ++ "/api/logout"
        , body = Http.emptyBody
        , expect = Http.expectWhatever (\_ -> done)
        , timeout = Just 15000
        , tracker = Nothing
        }


{-| Lyceum's login page, returning to `returnUrl` (which must be on an origin Lyceum allows) after sign-in.
-}
loginHref : String -> String -> String
loginHref loginUrl returnUrl =
    loginUrl
        ++ (if String.contains "?" loginUrl then
                "&"

            else
                "?"
           )
        ++ "return="
        ++ Url.percentEncode returnUrl


{-| Whether the signed-in account includes sync (a Supporter feature).
-}
hasSync : User -> Bool
hasSync user =
    List.member "sync" user.entitlements
