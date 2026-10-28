port module Main exposing (main)

import Account exposing (Account)
import Browser
import Browser.Dom as Dom
import Browser.Events
import Browser.Navigation as Nav
import Changelog
import Conllu
import Dict exposing (Dict)
import Fsrs
import Html exposing (Html, a, article, aside, button, details, div, footer, h1, h2, h3, header, input, label, li, main_, nav, option, p, section, select, span, summary, table, tbody, td, text, textarea, th, thead, tr, ul)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, href, id, placeholder, rel, rows, selected, style, target, type_, value)
import Html.Events exposing (on, onClick, onInput, stopPropagationOn)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Morphology
import Passage
import Process
import Review
import Route exposing (Route)
import Set exposing (Set)
import Sources
import Study
import Sync
import Task
import Time
import Today
import Url exposing (Url)
import Words


type Screen
    = LibraryScreen
    | WorkspaceScreen
    | SettingsScreen
    | ReaderScreen
    | TodayScreen
    | WordScreen String
    | WordReviewScreen String
    | StatsScreen
    | WhatsNewScreen


{-| Every word occurrence across the library (`preload/lemmas.json`, written by the Roc preload tool), for word pages.
-}
type LemmaIndex
    = IndexNotLoaded
    | IndexLoading
    | IndexLoaded LemmaData
    | IndexFailed


type alias LemmaData =
    { lemmas : Dict String (List IndexOccurrence)
    , passages : Dict String (Dict String String)
    }


type alias IndexOccurrence =
    { work : String
    , ref : String
    , position : Int
    , form : String
    , gloss : String
    }


type Preset
    = ReadPreset
    | AssistedPreset
    | IntensivePreset
    | CustomPreset


type Theme
    = DarkTheme
    | LightTheme


{-| What the reader shows with each passage, switched from its layer bar and remembered in IndexedDB.
-}
type alias ReaderLayers =
    { glosses : Bool
    , morphology : Bool
    , translation : Bool
    }


type ReaderLayer
    = GlossLayer
    | MorphologyLayer
    | TranslationLayer


{-| The study tools a passage offers: per-word glosses and the two translations.
-}
type ModuleId
    = GlossModule
    | LiteralModule
    | ProseModule


type ModuleMode
    = ModuleOff
    | OnDemand


type alias ModuleSettings =
    { gloss : ModuleMode
    , literal : ModuleMode
    , prose : ModuleMode
    }


type PopupTab
    = WordTab
    | SentenceTab


{-| Where the desktop word popup sits relative to its word, measured once it has rendered. Phones show it as a
bottom sheet instead, so this is ignored there.
-}
type alias PopupPlacement =
    { above : Bool
    , shift : Float
    , maxHeight : Float
    }


{-| A touch on the passage. It becomes a horizontal swipe only when it first moves mostly sideways soon after it
starts, so vertical scrolling and long-press text selection are left to the browser.
-}
type alias Swipe =
    { startX : Float
    , startY : Float
    , startTime : Float
    , dx : Float
    , axis : SwipeAxis
    }


type SwipeAxis
    = Undecided
    | Horizontal
    | Vertical


type alias Corpus =
    Conllu.Corpus


type alias CorpusSource =
    Conllu.CorpusSource


type alias Sentence =
    Conllu.Sentence


type alias CorpusToken =
    Conllu.CorpusToken


type alias Manifest =
    { version : Int
    , corpora : List ManifestEntry
    }


type alias ManifestEntry =
    { id : String
    , title : String
    , path : String
    , sentenceCount : Int
    , tokenCount : Int
    , source : CorpusSource
    , citation : Maybe Sources.Citation
    , unitsPath : String
    , passages : List String
    }


type alias Coverage =
    { tokens : Int
    , glossed : Int
    , morphology : Int
    , sentences : Int
    , dependencies : Int
    , literal : Int
    , prose : Int
    }


type alias StorageResponse =
    { id : String
    , ok : Bool
    , value : Decode.Value
    }


type alias Model =
    { screen : Screen
    , corpus : Corpus
    , sentenceIndex : Int
    , preset : Preset
    , settings : ModuleSettings
    , activeModule : Maybe ModuleId
    , study : Study.Draft
    , attempts : List Study.Attempt
    , popupWord : Maybe Int
    , popupTab : PopupTab
    , popupPlacement : Maybe PopupPlacement
    , swipe : Maybe Swipe
    , historyOpen : Bool
    , historyAttempt : Maybe Int
    , zone : Time.Zone
    , routeQuery : Dict String String
    , clock : Int
    , confirmClear : Bool
    , notice : Maybe String
    , theme : Theme
    , corpusReady : Bool
    , corpusLoadedFromNetwork : Bool
    , legacyManifestEntry : Maybe ManifestEntry
    , legacyCorpusRaw : Maybe String
    , library : List ManifestEntry
    , activeEntry : Maybe ManifestEntry
    , requestedWork : Maybe String
    , pendingRoute : Maybe Route
    , changelog : ChangelogState
    , key : Nav.Key
    , currentPath : String
    , positions : Dict String Int
    , readerGloss : Maybe ( Int, Int )
    , readerRevealed : Set Int
    , readerLayers : ReaderLayers
    , scrollGeneration : Int
    , reviews : Dict String Review.Entry
    , newPerDay : Int
    , extraNew : { day : Int, count : Int }
    , queueMode : Bool
    , queueDone : Bool
    , workFinished : Bool
    , wordReviews : List Words.Review
    , wordCards : Dict String Words.Card
    , todayMode : Maybe Today.Mode
    , wordAnswer : { guess : String, revealed : Bool }
    , lemmaIndex : LemmaIndex
    , allWords : Bool
    , todayScope : Maybe String
    , librarySearch : String
    , librarySort : String
    , account : Account
    , appUrl : Url
    , sync : Sync.State
    , syncLoaded : Bool

    {- the stored state has been read; no sync before -}
    , syncStatus : Sync.Status
    , syncBusy : Bool
    , syncDueAt : Int

    {- sync at this clock time (after a rating); 0 when nothing waits -}
    }


type Msg
    = ShowLibrary
    | ShowWorkspace
    | ShowSettings
    | PreviousSentence
    | NextSentence
    | JumpToPassage String
    | JumpToCitation String
    | GoToCitation String
    | Navigate Route
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | KeyPressed String String
    | ReaderTokenTapped Int Int
    | ReaderToggleTranslation Int
    | ToggleReaderLayer ReaderLayer
    | ReaderStep Int
    | ReaderScrolled
    | ReaderSettled Int
    | ReaderMeasured Int (Result Dom.Error ( Dom.Element, List Dom.Element ))
    | NoOp
    | SelectPreset Preset
    | ToggleModule ModuleId
    | OpenModule ModuleId
    | CloseWorkbench
    | OpenWordPopup Int
    | ClosePopup
    | SetPopupTab PopupTab
    | PopupMeasured (Result Dom.Error PopupPlacement)
    | PopupResized
    | SwipeStart Float Float Float
    | SwipeMove Float Float Float
    | SwipeEnd
    | OpenHistory
    | CloseHistory
    | SelectHistoryAttempt Int
    | GotZone Time.Zone
    | StudyGloss Int String
    | StudyLiteral String
    | StudyProse String
    | RevealItem String
    | SubmitStudy
    | ReopenStudy
    | MarkItem String Bool
    | FinishGrading Fsrs.Rating
    | StudyToday ManifestEntry
    | ContinueReading
    | SetNewPerDay String
    | GradingFinished Fsrs.Rating Time.Posix
    | ClearSavedData
    | ConfirmClearSavedData
    | CancelClearSavedData
    | ShowNotice String
    | DismissNotice
    | ToggleTheme
    | Tick Time.Posix
    | GotManifest (Result Http.Error Manifest)
    | GotCorpus ManifestEntry (Result Http.Error ( String, String ))
    | GotStorage Decode.Value
    | SyncNow
    | GotSync (List Sync.Outgoing) (Result Http.Error Sync.Response)
    | VisibilityChanged Browser.Events.Visibility
    | StartToday Today.Mode
    | WordGuess String
    | RevealWord
    | RateWord Fsrs.Rating
    | WordRated String Fsrs.Rating Time.Posix
    | GotLemmaIndex (Result Http.Error LemmaData)
    | GotChangelog (Result Http.Error String)
    | SetAllWords Bool
    | GoTo String
    | SetTodayScope String
    | StartTodayIn String
    | LearnMore
    | SetLibrarySearch String
    | SetLibrarySort String
    | GotAccountConfig (Result Http.Error (Maybe String))
    | GotAccount Account
    | CheckAccount
    | SignOut


port storageRequest : Encode.Value -> Cmd msg


port storageResponse : (Decode.Value -> msg) -> Sub msg


main : Program Decode.Value Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = \model -> { title = documentTitle model, body = [ view model ] }
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }


init : Decode.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        ( model, routeCmd ) =
            applyRoute (Route.fromUrl url |> Maybe.withDefault Route.Library)
                { screen = LibraryScreen
                , corpus = fallbackCorpus
                , sentenceIndex = 0
                , preset = AssistedPreset
                , settings = assistedSettings
                , activeModule = Nothing
                , study = Study.emptyDraft
                , attempts = []
                , popupWord = Nothing
                , popupTab = WordTab
                , popupPlacement = Nothing
                , swipe = Nothing
                , historyOpen = False
                , historyAttempt = Nothing
                , zone = Time.utc
                , routeQuery = Route.query url
                , clock = 0
                , confirmClear = False
                , notice = Nothing
                , theme = DarkTheme
                , corpusReady = False
                , corpusLoadedFromNetwork = False
                , legacyManifestEntry = Nothing
                , legacyCorpusRaw = Nothing
                , library = []
                , activeEntry = Nothing
                , requestedWork = Nothing
                , pendingRoute = Nothing
                , changelog = ChangelogNotLoaded
                , key = key
                , currentPath = urlPath url
                , positions = Dict.empty
                , readerGloss = Nothing
                , readerRevealed = Set.empty
                , scrollGeneration = 0
                , readerLayers = { glosses = True, morphology = True, translation = True }
                , reviews = Dict.empty
                , newPerDay = Review.newPerDayDefault
                , extraNew = { day = 0, count = 0 }
                , queueMode = False
                , queueDone = False
                , workFinished = False
                , wordReviews = []
                , wordCards = Dict.empty
                , todayMode = Nothing
                , wordAnswer = { guess = "", revealed = False }
                , lemmaIndex = IndexNotLoaded
                , allWords = False
                , todayScope = Nothing
                , librarySearch = ""
                , librarySort = "recent"
                , account = Account.NotConfigured
                , appUrl = { url | query = Nothing, fragment = Nothing }
                , sync = Sync.emptyState 0
                , syncLoaded = False
                , syncStatus = Sync.NotSyncing
                , syncBusy = False
                , syncDueAt = 0
                }
    in
    ( model
    , Cmd.batch
        [ fetchManifest
        , Account.fetchConfig GotAccountConfig
        , routeCmd
        , Task.perform Tick Time.now
        , Task.perform GotZone Time.here
        , storageGet "theme" "metadata" "theme"
        , storageGet "reader-layers" "metadata" "reader-layers"
        , storageGet "positions" "metadata" "positions"
        , storageGet "review-settings" "metadata" "review-settings"
        , storageGet "sync-state" "metadata" "sync-state"
        , storageGet "today-scope" "metadata" "today-scope"
        , storageGetAll "attempts" "progress"
        , storageGet "cached-corpus" "metadata" "cached-corpus"
        , storageGet "legacy-manifest" "metadata" "preload-manifest"
        , storageGet "legacy-corpus" "corpora" "anabasis"
        ]
    )


documentTitle : Model -> String
documentTitle model =
    case ( model.screen, model.activeEntry ) of
        ( LibraryScreen, _ ) ->
            "Lyceum Study · Greek reading workspace"

        ( SettingsScreen, _ ) ->
            "Study tools · Lyceum Study"

        ( TodayScreen, _ ) ->
            "Today · Lyceum Study"

        ( StatsScreen, _ ) ->
            "Progress · Lyceum Study"

        ( WhatsNewScreen, _ ) ->
            "What's new · Lyceum Study"

        ( WordScreen lemma, _ ) ->
            displayLemma lemma ++ " · Lyceum Study"

        ( WordReviewScreen lemma, _ ) ->
            "Review " ++ displayLemma lemma ++ " · Lyceum Study"

        ( _, Just entry ) ->
            entry.title ++ " " ++ currentLabel model ++ " · Lyceum Study"

        ( _, Nothing ) ->
            "Lyceum Study"


{-| The route part of a URL in the same form `pathFor` produces, including the fragment's query.
-}
urlPath : Url -> String
urlPath url =
    case url.fragment of
        Just fragment ->
            if String.isEmpty fragment then
                "#/"

            else
                "#" ++ fragment

        Nothing ->
            "#/"


readSettings : ModuleSettings
readSettings =
    { gloss = OnDemand, literal = ModuleOff, prose = ModuleOff }


assistedSettings : ModuleSettings
assistedSettings =
    { gloss = OnDemand, literal = ModuleOff, prose = OnDemand }


intensiveSettings : ModuleSettings
intensiveSettings =
    { gloss = OnDemand, literal = OnDemand, prose = OnDemand }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ storageResponse GotStorage
        , Browser.Events.onVisibilityChange VisibilityChanged
        , Time.every 5000 Tick
        , case model.account of
            Account.Unreachable _ ->
                Time.every (5 * 60 * 1000) (\_ -> CheckAccount)

            _ ->
                Sub.none
        , if model.screen == WorkspaceScreen || model.screen == ReaderScreen then
            Browser.Events.onKeyDown keyDecoder

          else
            Sub.none
        , if model.popupWord /= Nothing && model.screen == WorkspaceScreen then
            Browser.Events.onResize (\_ _ -> PopupResized)

          else
            Sub.none
        ]


{-| Every update then follows the passage (loading its saved draft), saves an edited draft, and syncs the URL.
Changes that stay on the same page (popups, tools, reader scrolling) replace the history entry instead of adding one.
-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( updated, cmd ) =
            updateModel msg model

        ( followed, loadCmd ) =
            followPassage model updated

        ( next, placeCmd ) =
            followPopup (isPopupResize msg) model followed

        replace =
            isUrlChange msg
                || (model.screen == ReaderScreen && next.screen == ReaderScreen)
                || (basePath model == basePath next)
    in
    syncUrl replace next (Cmd.batch [ cmd, loadCmd, placeCmd, saveDraft model next ])


{-| A newly shown popup (another word, tab, or page) renders hidden in its natural place below the word, is measured,
and then shown where it fits.
-}
followPopup : Bool -> Model -> Model -> ( Model, Cmd Msg )
followPopup resized previous next =
    case next.popupWord of
        Just tokenId ->
            if resized || previous.popupWord /= next.popupWord || previous.popupTab /= next.popupTab || previous.screen /= next.screen then
                ( { next | popupPlacement = Nothing }, measurePopup tokenId )

            else
                ( next, Cmd.none )

        Nothing ->
            ( { next | popupPlacement = Nothing }, Cmd.none )


popupElementId : String
popupElementId =
    "word-popup"


tokenElementId : Int -> String
tokenElementId tokenId =
    "study-token-" ++ String.fromInt tokenId


{-| Opens below the word unless it fits better above, never taller than the room between the sticky header and the
fixed footer, and shifted sideways to stay inside the viewport.
-}
measurePopup : Int -> Cmd Msg
measurePopup tokenId =
    let
        heightOf elementId =
            Dom.getElement elementId
                |> Task.map (\found -> found.element.height)
                |> Task.onError (\_ -> Task.succeed 0)

        margin =
            12
    in
    Task.map4
        (\word popup headerHeight footerHeight ->
            let
                viewport =
                    popup.viewport

                spaceBelow =
                    viewport.y + viewport.height - footerHeight - margin - (word.element.y + word.element.height + 8)

                spaceAbove =
                    word.element.y - 8 - (viewport.y + headerHeight + margin)

                above =
                    popup.element.height > spaceBelow && spaceAbove > spaceBelow

                right =
                    word.element.x + popup.element.width

                leftShift =
                    min 0 (viewport.x + viewport.width - margin - right)
            in
            { above = above
            , shift = max leftShift (viewport.x + margin - word.element.x)
            , maxHeight =
                max 160
                    (if above then
                        spaceAbove

                     else
                        spaceBelow
                    )
            }
        )
        (Dom.getElement (tokenElementId tokenId))
        (Dom.getElement popupElementId)
        (heightOf appHeaderId)
        (heightOf studyFooterId)
        |> Task.attempt PopupMeasured


appHeaderId : String
appHeaderId =
    "app-header"


studyFooterId : String
studyFooterId =
    "study-footer"


isPopupResize : Msg -> Bool
isPopupResize msg =
    case msg of
        PopupResized ->
            True

        _ ->
            False


isUrlChange : Msg -> Bool
isUrlChange msg =
    case msg of
        UrlChanged _ ->
            True

        _ ->
            False


draftKey : Model -> Maybe String
draftKey model =
    if model.corpusReady then
        model.activeEntry |> Maybe.map (\entry -> "draft:" ++ entry.id ++ ":" ++ currentRef model)

    else
        Nothing


{-| A newly shown passage starts empty until its saved draft (if any) arrives from IndexedDB.
-}
followPassage : Model -> Model -> ( Model, Cmd Msg )
followPassage previous next =
    case draftKey next of
        Just key ->
            if draftKey previous == Just key then
                ( next, Cmd.none )

            else
                ( { next | study = Study.emptyDraft }, storageGet ("study-draft:" ++ key) "metadata" key )

        Nothing ->
            ( next, Cmd.none )


saveDraft : Model -> Model -> Cmd Msg
saveDraft previous next =
    case draftKey next of
        Just key ->
            if draftKey previous == Just key && previous.study /= next.study then
                storagePut "save-draft" "metadata" (Encode.object [ ( "key", Encode.string key ), ( "value", Study.encodeDraft next.study ) ])

            else
                Cmd.none

        Nothing ->
            Cmd.none


updateModel : Msg -> Model -> ( Model, Cmd Msg )
updateModel msg model =
    case msg of
        GotAccountConfig (Ok (Just api)) ->
            ( { model | account = Account.Checking api }, Account.checkSession api GotAccount )

        GotAccountConfig _ ->
            ( model, Cmd.none )

        GotAccount account ->
            startSync { model | account = account }

        SyncNow ->
            startSync model

        GotSync sent result ->
            case result of
                Ok response ->
                    handleSynced sent response model

                Err error ->
                    syncFailed error model

        VisibilityChanged visibility ->
            if visibility == Browser.Events.Visible then
                startSync model

            else
                ( model, Cmd.none )

        CheckAccount ->
            case Account.api model.account of
                Just api ->
                    ( { model | account = Account.Checking api }, Account.checkSession api GotAccount )

                Nothing ->
                    ( model, Cmd.none )

        SignOut ->
            case Account.api model.account of
                Just api ->
                    ( { model | account = Account.Checking api }, Account.signOut api CheckAccount )

                Nothing ->
                    ( model, Cmd.none )

        GotManifest result ->
            handleManifest result model

        GotCorpus entry result ->
            handleFetchedCorpus entry result model

        GotStorage value ->
            showPending (handleStorageResponse value model)

        Navigate route ->
            ( model, Nav.pushUrl model.key (Route.toPath route) )

        UrlRequested (Browser.Internal url) ->
            ( model, Nav.pushUrl model.key (Url.toString url) )

        UrlRequested (Browser.External href) ->
            ( model, Nav.load href )

        UrlChanged url ->
            if urlPath url == model.currentPath then
                ( model, Cmd.none )

            else
                applyRoute (Route.fromUrl url |> Maybe.withDefault Route.Library) { model | currentPath = urlPath url, routeQuery = Route.query url }

        JumpToCitation prefix ->
            jumpToCitation prefix model

        GoToCitation typed ->
            if String.isEmpty (normalizeCitation typed) then
                ( model, Cmd.none )

            else
                jumpToCitation (normalizeCitation typed) model

        JumpToPassage passage ->
            case String.toInt passage of
                Just number ->
                    ( moveToSentence (number - 1) (browsing model), Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        KeyPressed key tag ->
            if List.member tag [ "INPUT", "TEXTAREA", "SELECT" ] then
                ( model, Cmd.none )

            else
                handleShortcut key model

        ReaderTokenTapped sentenceIndex tokenId ->
            ( { model
                | readerGloss =
                    if model.readerGloss == Just ( sentenceIndex, tokenId ) then
                        Nothing

                    else
                        Just ( sentenceIndex, tokenId )
                , sentenceIndex = sentenceIndex
              }
            , Cmd.none
            )

        ToggleReaderLayer layer ->
            let
                current =
                    model.readerLayers

                layers =
                    case layer of
                        GlossLayer ->
                            { current | glosses = not current.glosses }

                        MorphologyLayer ->
                            { current | morphology = not current.morphology }

                        TranslationLayer ->
                            { current | translation = not current.translation }
            in
            ( { model | readerLayers = layers, readerGloss = Nothing }
            , storagePut "reader-layers"
                "metadata"
                (Encode.object
                    [ ( "key", Encode.string "reader-layers" )
                    , ( "value"
                      , Encode.object
                            [ ( "glosses", Encode.bool layers.glosses )
                            , ( "morphology", Encode.bool layers.morphology )
                            , ( "translation", Encode.bool layers.translation )
                            ]
                      )
                    ]
                )
            )

        ReaderToggleTranslation sentenceIndex ->
            ( { model
                | readerRevealed =
                    if Set.member sentenceIndex model.readerRevealed then
                        Set.remove sentenceIndex model.readerRevealed

                    else
                        Set.insert sentenceIndex model.readerRevealed
                , sentenceIndex = sentenceIndex
              }
            , Cmd.none
            )

        ReaderStep delta ->
            let
                target =
                    clamp 0 (List.length model.corpus.sentences - 1) (model.sentenceIndex + delta)
            in
            ( { model | sentenceIndex = target, readerGloss = Nothing, scrollGeneration = model.scrollGeneration + 1 }, scrollToSentence target )

        ReaderScrolled ->
            let
                generation =
                    model.scrollGeneration + 1
            in
            ( { model | scrollGeneration = generation }
            , Process.sleep 200 |> Task.perform (\_ -> ReaderSettled generation)
            )

        ReaderSettled generation ->
            if generation /= model.scrollGeneration then
                ( model, Cmd.none )

            else
                ( model, measureReader generation model )

        ReaderMeasured generation (Ok ( container, sentences )) ->
            -- Measuring takes a frame per passage; a step or scroll since it began makes the result stale.
            if generation /= model.scrollGeneration then
                ( model, Cmd.none )

            else
                let
                    top =
                        container.element.y + 72

                    current =
                        sentences
                            |> List.indexedMap Tuple.pair
                            |> List.filter (\( _, element ) -> element.element.y + element.element.height > top)
                            |> List.head
                            |> Maybe.map Tuple.first
                in
                ( { model | sentenceIndex = Maybe.withDefault model.sentenceIndex current }, Cmd.none )

        ReaderMeasured _ (Err _) ->
            ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )

        ShowLibrary ->
            ( { model | screen = LibraryScreen, notice = Nothing, popupWord = Nothing }, Cmd.none )

        ShowWorkspace ->
            if model.corpusReady then
                ( { model | screen = WorkspaceScreen, notice = Nothing }, Cmd.none )

            else
                ( { model | notice = Just "The local corpus is still loading." }, Cmd.none )

        ShowSettings ->
            ( { model | screen = SettingsScreen, notice = Nothing, popupWord = Nothing, confirmClear = False }, Cmd.none )

        PreviousSentence ->
            ( moveToSentence (model.sentenceIndex - 1) (browsing model), Cmd.none )

        NextSentence ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        SelectPreset preset ->
            ( { model | preset = preset, settings = settingsForPreset preset model.settings, activeModule = Nothing }, Cmd.none )

        ToggleModule moduleId ->
            let
                settings =
                    setModuleMode moduleId
                        (if moduleMode moduleId model.settings == ModuleOff then
                            OnDemand

                         else
                            ModuleOff
                        )
                        model.settings
            in
            ( { model
                | preset = CustomPreset
                , settings = settings
                , activeModule =
                    if model.activeModule == Just moduleId && moduleMode moduleId settings == ModuleOff then
                        Nothing

                    else
                        model.activeModule
              }
            , Cmd.none
            )

        OpenModule moduleId ->
            ( { model | activeModule = Just moduleId, popupWord = Nothing }, Cmd.none )

        CloseWorkbench ->
            ( { model | activeModule = Nothing }, Cmd.none )

        OpenWordPopup tokenId ->
            ( { model
                | popupWord = Just tokenId
                , popupTab =
                    if model.popupWord == Just tokenId then
                        model.popupTab

                    else
                        WordTab
              }
            , Cmd.none
            )

        ClosePopup ->
            ( { model | popupWord = Nothing }, Cmd.none )

        SetPopupTab tab ->
            ( { model | popupTab = tab }, Cmd.none )

        PopupMeasured result ->
            ( { model | popupPlacement = Just (Result.withDefault { above = False, shift = 0, maxHeight = 0 } result) }, Cmd.none )

        PopupResized ->
            ( model, Cmd.none )

        SwipeStart x y time ->
            ( { model | swipe = Just { startX = x, startY = y, startTime = time, dx = 0, axis = Undecided } }, Cmd.none )

        SwipeMove x y time ->
            ( { model | swipe = Maybe.map (followSwipe x y time) model.swipe }, Cmd.none )

        SwipeEnd ->
            let
                settled =
                    { model | swipe = Nothing }
            in
            case model.swipe of
                Just swipe ->
                    if swipe.axis == Horizontal && abs swipe.dx > swipeThreshold then
                        let
                            delta =
                                if swipe.dx < 0 then
                                    1

                                else
                                    -1
                        in
                        if model.screen == ReaderScreen then
                            updateModel (ReaderStep delta) settled

                        else
                            ( moveToSentence (model.sentenceIndex + delta) (browsing settled), Cmd.none )

                    else
                        ( settled, Cmd.none )

                Nothing ->
                    ( settled, Cmd.none )

        OpenHistory ->
            ( { model | historyOpen = True, historyAttempt = Nothing, popupWord = Nothing, activeModule = Nothing }, Cmd.none )

        CloseHistory ->
            ( { model | historyOpen = False, historyAttempt = Nothing }, Cmd.none )

        SelectHistoryAttempt finishedAt ->
            ( { model
                | historyAttempt =
                    if model.historyAttempt == Just finishedAt then
                        Nothing

                    else
                        Just finishedAt
              }
            , Cmd.none
            )

        GotZone zone ->
            ( { model | zone = zone }, Cmd.none )

        StudyGloss tokenId gloss ->
            ( editStudy (\draft -> { draft | glosses = Dict.insert tokenId gloss draft.glosses }) model, Cmd.none )

        StudyLiteral literal ->
            ( editStudy (\draft -> { draft | literal = literal }) model, Cmd.none )

        StudyProse prose ->
            ( editStudy (\draft -> { draft | prose = prose }) model, Cmd.none )

        RevealItem key ->
            ( editStudy (\draft -> { draft | revealed = Set.insert key draft.revealed }) model, Cmd.none )

        SubmitStudy ->
            let
                study =
                    model.study
            in
            ( { model | study = { study | submitted = True, updatedAt = model.clock }, popupWord = Nothing, activeModule = Nothing }, Cmd.none )

        ReopenStudy ->
            let
                study =
                    model.study
            in
            ( { model | study = { study | submitted = False, marks = Dict.empty } }, Cmd.none )

        MarkItem key right ->
            let
                study =
                    model.study

                marks =
                    if Dict.get key study.marks == Just right then
                        Dict.remove key study.marks

                    else
                        Dict.insert key right study.marks
            in
            ( { model | study = { study | marks = marks, updatedAt = model.clock } }, Cmd.none )

        FinishGrading rating ->
            ( model, Task.perform (GradingFinished rating) Time.now )

        GradingFinished rating time ->
            let
                now =
                    Time.posixToMillis time
            in
            case ( buildAttempt now rating model, model.activeEntry ) of
                ( Just attempt, Just entry ) ->
                    let
                        passage =
                            currentRef model

                        scheduled =
                            Review.schedule now rating entry.id passage model.reviews

                        recorded =
                            { model
                                | attempts = attempt :: model.attempts
                                , reviews =
                                    scheduled
                                        |> Maybe.map (\review -> Dict.insert (Review.entryKey entry.id passage) review model.reviews)
                                        |> Maybe.withDefault model.reviews
                                , wordCards = Words.cards (attempt :: model.attempts) model.wordReviews
                                , study = Study.emptyDraft
                                , allWords = False
                                , clock = now
                            }

                        -- In today's session the next item may be a word or another work's passage.
                        ( advanced, navigate ) =
                            case model.todayMode of
                                Just mode ->
                                    goToday mode recorded

                                Nothing ->
                                    ( advance recorded, Cmd.none )
                    in
                    ( { advanced | notice = Nothing, syncDueAt = now + 3000 }
                    , Cmd.batch
                        [ storagePut "save-attempt" "progress" (Study.encodeAttempt attempt)
                        , navigate
                        , scheduled |> Maybe.map (Review.encodeEntry >> storagePut "save-card" "progress") |> Maybe.withDefault Cmd.none
                        , draftKey model
                            |> Maybe.map (\key -> storagePut "save-draft" "metadata" (Encode.object [ ( "key", Encode.string key ), ( "value", Study.encodeDraft Study.emptyDraft ) ]))
                            |> Maybe.withDefault Cmd.none
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        StudyToday entry ->
            let
                today =
                    Review.queue model.clock (newLimit model) entry.id entry.passages model.reviews

                first =
                    List.head (today.due ++ today.new)

                -- With nothing queued, reopen where the learner last was.
                passage =
                    first |> Maybe.withDefault (savedRef entry model)
            in
            ( { model | queueMode = True, queueDone = first == Nothing }
            , Nav.pushUrl model.key (Route.toPath (Route.Study entry.id passage) ++ "?queue=1")
            )

        ContinueReading ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        -- More new passages today, staying in the session: reviews that come due (learning steps included) still come
        -- first, and the new passages are the next unseen ones.
        LearnMore ->
            let
                inQueue =
                    model.queueMode && model.screen /= TodayScreen && model.screen /= LibraryScreen

                day =
                    Review.startOfDay model.clock

                already =
                    if model.extraNew.day == day then
                        model.extraNew.count

                    else
                        0

                more =
                    { model | extraNew = { day = day, count = already + learnMoreStep model } }
            in
            if inQueue then
                ( advance { more | queueDone = False }, Cmd.none )

            else
                let
                    mode =
                        Maybe.withDefault Today.Everything model.todayMode
                in
                goToday mode { more | todayMode = Just mode }

        SetNewPerDay value ->
            case String.toInt value of
                Just newPerDay ->
                    ( { model | newPerDay = newPerDay }
                    , storagePut "save-review-settings" "metadata" (Encode.object [ ( "key", Encode.string "review-settings" ), ( "value", Encode.object [ ( "newPerDay", Encode.int newPerDay ) ] ) ])
                    )

                Nothing ->
                    ( model, Cmd.none )

        StartToday mode ->
            goToday mode { model | todayMode = Just mode, queueMode = False, queueDone = False }

        WordGuess guess ->
            let
                answer =
                    model.wordAnswer
            in
            ( { model | wordAnswer = { answer | guess = guess } }, Cmd.none )

        RevealWord ->
            let
                answer =
                    model.wordAnswer
            in
            ( { model | wordAnswer = { answer | revealed = True } }, Cmd.none )

        RateWord rating ->
            case model.screen of
                WordReviewScreen lemma ->
                    ( model, Task.perform (WordRated lemma rating) Time.now )

                _ ->
                    ( model, Cmd.none )

        WordRated lemma rating time ->
            case Dict.get lemma model.wordCards of
                Just word ->
                    let
                        now =
                            Time.posixToMillis time

                        context =
                            reviewContext model word

                        review =
                            { lemma = lemma, at = now, rating = rating, occurrence = { context | guess = model.wordAnswer.guess } }

                        reviews =
                            review :: model.wordReviews

                        cards =
                            Words.cards model.attempts reviews

                        recorded =
                            { model | wordReviews = reviews, wordCards = cards, clock = now, wordAnswer = { guess = "", revealed = False } }

                        ( moved, navigate ) =
                            case model.todayMode of
                                Just mode ->
                                    goToday mode recorded

                                Nothing ->
                                    ( recorded, Nav.pushUrl model.key (Route.toPath (Route.Word lemma)) )
                    in
                    ( { moved | notice = Nothing, syncDueAt = moved.clock + 3000 }
                    , Cmd.batch [ storagePut "save-word-review" "progress" (Words.encodeReview review), navigate ]
                    )

                Nothing ->
                    ( model, Cmd.none )

        GotChangelog result ->
            ( { model
                | changelog =
                    case result of
                        Ok text ->
                            ChangelogLoaded (Changelog.parse text)

                        Err _ ->
                            ChangelogFailed
              }
            , Cmd.none
            )

        GotLemmaIndex result ->
            ( { model
                | lemmaIndex =
                    case result of
                        Ok data ->
                            IndexLoaded data

                        Err _ ->
                            IndexFailed
              }
            , Cmd.none
            )

        SetAllWords on ->
            ( { model | allWords = on }, Cmd.none )

        GoTo path ->
            ( model, Nav.pushUrl model.key path )

        SetTodayScope work ->
            let
                scope =
                    if String.isEmpty work then
                        Nothing

                    else
                        Just work
            in
            ( { model | todayScope = scope }, saveTodayScope scope )

        SetLibrarySearch query ->
            ( { model | librarySearch = query }, Cmd.none )

        SetLibrarySort sort ->
            ( { model | librarySort = sort }, Cmd.none )

        StartTodayIn work ->
            let
                ( started, navigate ) =
                    goToday Today.Everything { model | todayScope = Just work, todayMode = Just Today.Everything, queueMode = False, queueDone = False }
            in
            ( started, Cmd.batch [ saveTodayScope (Just work), navigate ] )

        ClearSavedData ->
            ( { model | confirmClear = True }, Cmd.none )

        CancelClearSavedData ->
            ( { model | confirmClear = False }, Cmd.none )

        ConfirmClearSavedData ->
            ( { model
                | attempts = []
                , reviews = Dict.empty
                , wordReviews = []
                , wordCards = Dict.empty
                , study = Study.emptyDraft
                , positions = Dict.empty
                , confirmClear = False
                , notice =
                    Just
                        (if syncsProgress model then
                            "Saved study data cleared from this device. Your synced progress comes back from your Lyceum account."

                         else
                            "Saved study data cleared from this device."
                        )

                -- With sync, the device downloads the account's history again.
                , sync = Sync.emptyState 0
                , syncDueAt = model.clock + 1
              }
            , Cmd.batch [ storageClear "clear-progress" "progress", storageClear "clear-metadata" "metadata" ]
            )

        ShowNotice notice ->
            ( { model | notice = Just notice }, Cmd.none )

        DismissNotice ->
            ( { model | notice = Nothing }, Cmd.none )

        ToggleTheme ->
            let
                theme =
                    if model.theme == DarkTheme then
                        LightTheme

                    else
                        DarkTheme
            in
            ( { model | theme = theme }
            , storagePut "theme"
                "metadata"
                (Encode.object
                    [ ( "key", Encode.string "theme" )
                    , ( "value"
                      , Encode.string
                            (if theme == DarkTheme then
                                "dark"

                             else
                                "light"
                            )
                      )
                    ]
                )
            )

        Tick time ->
            let
                ticked =
                    { model | clock = Time.posixToMillis time }

                -- A rating waits a few seconds so a burst of them goes up together; otherwise every few minutes.
                due =
                    case ticked.syncStatus of
                        Sync.Synced at ->
                            ticked.clock - at > 3 * 60 * 1000

                        _ ->
                            False
            in
            if (ticked.syncDueAt > 0 && ticked.clock >= ticked.syncDueAt) || due then
                startSync ticked

            else
                ( ticked, Cmd.none )


{-| Answers can change only before the checkpoint; the first edit stamps when work on the passage began.
-}
editStudy : (Study.Draft -> Study.Draft) -> Model -> Model
editStudy change model =
    if model.study.submitted then
        model

    else
        let
            changed =
                change model.study
        in
        { model
            | study =
                if changed.startedAt == 0 then
                    { changed | startedAt = model.clock, updatedAt = model.clock }

                else
                    { changed | updatedAt = model.clock }
        }


{-| A saved draft resumes grading only if it was touched in the last 30 minutes (a refresh mid-grading). An older
submitted draft is an abandoned checkpoint: it reopens for answering with the answers kept and the marks cleared, so
opening a passage always starts with reading and attempting.
-}
resumable : Int -> Study.Draft -> Study.Draft
resumable now draft =
    if draft.submitted && now - draft.updatedAt > 30 * 60 * 1000 then
        { draft | submitted = False, marks = Dict.empty }

    else
        draft


{-| The items of the current passage in grading order: each word (punctuation excluded), then the translations the learner worked on or has enabled.
-}
studyItems : Model -> List Study.Item
studyItems model =
    let
        sentence =
            currentSentence model

        study =
            model.study

        item key kind form lemma guess reference =
            { key = key
            , kind = kind
            , form = form
            , lemma = lemma
            , guess = guess
            , reference = reference
            , revealedEarly = Set.member key study.revealed
            , mark = Dict.get key study.marks
            }

        targets =
            askedWords model

        words =
            if moduleMode GlossModule model.settings /= ModuleOff || not (Dict.isEmpty study.glosses) then
                sentence.tokens
                    |> List.filter Study.isWordToken
                    -- A word not asked joins the attempt once the learner reveals it or marks it missed in grading.
                    |> List.filter (\token -> isAsked targets (Study.wordKey token.id) || Dict.member (Study.wordKey token.id) study.marks || Set.member (Study.wordKey token.id) study.revealed)
                    |> List.map (\token -> item (Study.wordKey token.id) Study.WordItem token.form token.lemma (Dict.get token.id study.glosses |> Maybe.withDefault "") token.gloss)

            else
                []

        literal =
            if moduleMode LiteralModule model.settings /= ModuleOff || not (String.isEmpty study.literal) then
                [ item Study.literalKey Study.LiteralItem "" "" study.literal sentence.literalTranslation ]

            else
                []

        prose =
            if moduleMode ProseModule model.settings /= ModuleOff || not (String.isEmpty study.prose) then
                [ item Study.proseKey Study.ProseItem "" "" study.prose sentence.proseTranslation ]

            else
                []
    in
    words ++ literal ++ prose


{-| The learner's last finished attempt at the current passage.
-}
lastAttempt : Model -> Maybe Study.Attempt
lastAttempt model =
    model.activeEntry
        |> Maybe.andThen (\entry -> Study.passageAttempts entry.id (currentRef model) model.attempts |> List.head)


{-| Word keys to ask on a repeat: those missed or revealed early last time. `Nothing` asks every word: a first attempt,
or the learner chose every word.
-}
askedWords : Model -> Maybe (Set String)
askedWords model =
    if model.allWords then
        Nothing

    else
        lastAttempt model
            |> Maybe.map
                (\attempt ->
                    attempt.items
                        |> List.filter (\item -> item.kind == Study.WordItem && (item.mark == Just False || item.revealedEarly))
                        |> List.map .key
                        |> Set.fromList
                )


isAsked : Maybe (Set String) -> String -> Bool
isAsked targets key =
    targets |> Maybe.map (Set.member key) |> Maybe.withDefault True


buildAttempt : Int -> Fsrs.Rating -> Model -> Maybe Study.Attempt
buildAttempt now rating model =
    model.activeEntry
        |> Maybe.map
            (\entry ->
                let
                    sentence =
                        currentSentence model

                    passage =
                        currentRef model
                in
                { id = "attempt:" ++ entry.id ++ ":" ++ passage ++ ":" ++ String.fromInt now
                , work = entry.id
                , passage = passage
                , sentenceId = sentence.id
                , sentenceText = sentence.text
                , startedAt =
                    if model.study.startedAt == 0 then
                        now

                    else
                        model.study.startedAt
                , finishedAt = now
                , items = studyItems model
                , rating = Just rating
                }
            )



-- SYNC


{-| Settings that sync, as stored in the metadata store (the newest edit wins). Drafts stay on their device.
-}
syncedSettings : Model -> List ( String, Encode.Value )
syncedSettings model =
    [ ( "theme"
      , Encode.string
            (if model.theme == DarkTheme then
                "dark"

             else
                "light"
            )
      )
    , ( "reader-layers"
      , Encode.object
            [ ( "glosses", Encode.bool model.readerLayers.glosses )
            , ( "morphology", Encode.bool model.readerLayers.morphology )
            , ( "translation", Encode.bool model.readerLayers.translation )
            ]
      )
    , ( "positions", Encode.dict identity Encode.int model.positions )
    , ( "review-settings", Encode.object [ ( "newPerDay", Encode.int model.newPerDay ) ] )
    , ( "today-scope", Encode.string (Maybe.withDefault "" model.todayScope) )
    ]


{-| Records the server doesn't have yet: history it hasn't acknowledged, and settings changed since they last synced
(stamped now), at most 500 per round.
-}
syncOutgoing : Model -> List Sync.Outgoing
syncOutgoing model =
    let
        attempts =
            model.attempts
                |> List.filter (\attempt -> not (Set.member attempt.id model.sync.sent))
                |> List.map (\attempt -> { id = attempt.id, kind = "attempt", mutable = False, updatedAt = attempt.finishedAt, body = Study.encodeAttempt attempt })

        wordReviews =
            model.wordReviews
                |> List.filter (\review -> not (Set.member (Words.reviewKey review) model.sync.sent))
                |> List.map (\review -> { id = Words.reviewKey review, kind = "wordreview", mutable = False, updatedAt = review.at, body = Words.encodeReview review })

        -- Not before the first exchange: a new device's defaults must not overwrite the account's settings.
        settings =
            syncedSettings model
                |> List.filter (\_ -> model.sync.primed)
                |> List.filter (\( key, value ) -> Maybe.map .value (Dict.get key model.sync.settings) /= Just (Encode.encode 0 value))
                |> List.map (\( key, value ) -> { id = "meta:" ++ key, kind = "setting", mutable = True, updatedAt = model.clock, body = value })
    in
    List.take 500 (settings ++ attempts ++ wordReviews)


{-| Sync with the signed-in account if it includes sync and no round is running.
-}
startSync : Model -> ( Model, Cmd Msg )
startSync model =
    case model.account of
        Account.SignedIn origin user ->
            if not (Account.hasSync user) then
                ( { model | syncStatus = Sync.NeedsSupporter, syncDueAt = 0 }, Cmd.none )

            else if model.syncBusy || not model.syncLoaded then
                ( model, Cmd.none )

            else
                let
                    -- Another account on this device starts over: its whole history goes up and comes down.
                    state =
                        if model.sync.account == user.id then
                            model.sync

                        else
                            Sync.emptyState user.id

                    ready =
                        { model | sync = state }

                    outgoing =
                        syncOutgoing ready
                in
                ( { ready | syncBusy = True, syncStatus = Sync.Syncing, syncDueAt = 0 }
                , Sync.request origin state outgoing (GotSync outgoing)
                )

        _ ->
            ( { model | syncDueAt = 0 }, Cmd.none )


{-| A finished round: what was sent is now on the server; received records merge in; cards replay from the merged
history. Another round follows when the server has more or records are still waiting.
-}
handleSynced : List Sync.Outgoing -> Sync.Response -> Model -> ( Model, Cmd Msg )
handleSynced sent response model =
    let
        state =
            model.sync

        acknowledged =
            List.foldl
                (\record acc ->
                    if record.mutable then
                        { acc | settings = Dict.insert (String.dropLeft 5 record.id) { value = Encode.encode 0 record.body, updatedAt = record.updatedAt } acc.settings }

                    else
                        { acc | sent = Set.insert record.id acc.sent }
                )
                state
                sent

        ( merged, writes ) =
            List.foldl applyReceived ( { model | sync = acknowledged }, [] ) response.records

        synced =
            { merged
                | sync = (\s -> { s | cursor = response.cursor, primed = True }) merged.sync
                , wordCards = Words.cards merged.attempts merged.wordReviews
                , reviews = Review.cards merged.reviews merged.attempts
                , syncBusy = False
                , syncStatus = Sync.Synced merged.clock
            }

        saveState =
            storagePut "save-sync-state" "metadata" (Encode.object [ ( "key", Encode.string "sync-state" ), ( "value", Sync.encodeState synced.sync ) ])

        ( next, again ) =
            -- After the first exchange, local setting edits go up.
            if response.more || List.length sent >= 500 || not state.primed then
                startSync synced

            else
                ( synced, Cmd.none )
    in
    ( next, Cmd.batch (saveState :: again :: writes) )


{-| Merges one received record: new history is kept (and stored), a newer setting replaces the local one unless the
local one has an edit that hasn't synced yet (it is newer and will go up next).
-}
applyReceived : Sync.Received -> ( Model, List (Cmd Msg) ) -> ( Model, List (Cmd Msg) )
applyReceived record ( model, writes ) =
    let
        state =
            model.sync

        known =
            { model | sync = { state | sent = Set.insert record.id state.sent } }
    in
    case record.kind of
        "attempt" ->
            case Decode.decodeValue Study.attemptDecoder record.body of
                Ok attempt ->
                    if List.any (\existing -> existing.id == attempt.id) model.attempts then
                        ( known, writes )

                    else
                        ( { known | attempts = attempt :: model.attempts }, storagePut "sync-attempt" "progress" record.body :: writes )

                Err _ ->
                    ( model, writes )

        "wordreview" ->
            case Decode.decodeValue Words.reviewDecoder record.body of
                Ok review ->
                    if List.any (\existing -> Words.reviewKey existing == Words.reviewKey review) model.wordReviews then
                        ( known, writes )

                    else
                        ( { known | wordReviews = review :: model.wordReviews }, storagePut "sync-word-review" "progress" record.body :: writes )

                Err _ ->
                    ( model, writes )

        "setting" ->
            let
                key =
                    String.dropLeft 5 record.id

                synced =
                    Dict.get key state.settings

                current =
                    syncedSettings model |> List.filter (Tuple.first >> (==) key) |> List.head |> Maybe.map (Tuple.second >> Encode.encode 0)

                editedHere =
                    current /= Maybe.map .value synced

                newer =
                    Maybe.map (\s -> record.updatedAt > s.updatedAt) synced |> Maybe.withDefault True
            in
            if current /= Nothing && (synced == Nothing || (newer && not editedHere)) then
                ( applySetting key record.body { model | sync = { state | settings = Dict.insert key { value = Encode.encode 0 record.body, updatedAt = record.updatedAt } state.settings } }
                , storagePut ("sync-" ++ key) "metadata" (Encode.object [ ( "key", Encode.string key ), ( "value", record.body ) ]) :: writes
                )

            else
                ( model, writes )

        _ ->
            ( model, writes )


{-| A setting from another device, read as if loaded from storage; positions merge (theirs win for the same work).
-}
applySetting : String -> Decode.Value -> Model -> Model
applySetting key value model =
    if key == "positions" then
        case Decode.decodeValue (Decode.dict Decode.int) value of
            Ok positions ->
                { model | positions = Dict.union positions model.positions }

            Err _ ->
                model

    else
        handleStorageResponse
            (Encode.object [ ( "id", Encode.string key ), ( "ok", Encode.bool True ), ( "value", Encode.object [ ( "key", Encode.string key ), ( "value", value ) ] ) ])
            model


{-| Whether this device syncs: signed in to an account that includes sync.
-}
syncsProgress : Model -> Bool
syncsProgress model =
    case model.account of
        Account.SignedIn _ user ->
            Account.hasSync user

        _ ->
            False


syncFailed : Http.Error -> Model -> ( Model, Cmd Msg )
syncFailed error model =
    let
        idle =
            { model | syncBusy = False }
    in
    case error of
        Http.BadStatus 402 ->
            ( { idle | syncStatus = Sync.NeedsSupporter }, Cmd.none )

        Http.BadStatus 401 ->
            -- Signed out elsewhere: ask who is signed in.
            update CheckAccount { idle | syncStatus = Sync.NotSyncing }

        Http.NetworkError ->
            ( { idle | syncStatus = Sync.Offline }, Cmd.none )

        Http.Timeout ->
            ( { idle | syncStatus = Sync.Offline }, Cmd.none )

        _ ->
            ( { idle | syncStatus = Sync.Failed }, Cmd.none )



-- ROUTING


{-| Shows a route whose work is loaded, or records it and loads the work first.
-}
applyRoute : Route -> Model -> ( Model, Cmd Msg )
applyRoute route model =
    case route of
        Route.Library ->
            ( { model | screen = LibraryScreen, pendingRoute = Nothing }, Cmd.none )

        Route.Settings ->
            ( { model | screen = SettingsScreen, pendingRoute = Nothing }, Cmd.none )

        Route.Today ->
            ( { model | screen = TodayScreen, pendingRoute = Nothing, todayMode = Just (queryMode model) }, Cmd.none )

        Route.Stats ->
            ( { model | screen = StatsScreen, pendingRoute = Nothing }, Cmd.none )

        Route.WhatsNew ->
            case model.changelog of
                ChangelogLoaded _ ->
                    ( { model | screen = WhatsNewScreen, pendingRoute = Nothing }, Cmd.none )

                _ ->
                    ( { model | screen = WhatsNewScreen, pendingRoute = Nothing, changelog = ChangelogLoading }
                    , Http.get { url = "/CHANGELOG.md", expect = Http.expectString GotChangelog }
                    )

        Route.Word name ->
            ( { model | screen = WordScreen name, pendingRoute = Nothing, lemmaIndex = loadingIndex model.lemmaIndex }, loadLemmaIndex model )

        Route.WordReview name ->
            ( { model
                | screen = WordReviewScreen name
                , pendingRoute = Nothing
                , todayMode = Dict.get "today" model.routeQuery |> Maybe.map Today.modeFromString
                , wordAnswer =
                    if model.screen == WordReviewScreen name then
                        model.wordAnswer

                    else
                        { guess = "", revealed = False }
              }
            , Cmd.none
            )

        Route.WorkLanding work ->
            ( model
            , Nav.replaceUrl model.key
                (Route.toPath
                    (Route.Study work
                        (List.filter (\entry -> entry.id == work) model.library |> List.head |> Maybe.map (\entry -> savedRef entry model) |> Maybe.withDefault "")
                    )
                )
            )

        _ ->
            case routeWork route of
                Just work ->
                    if model.corpusReady && Maybe.map .id model.activeEntry == Just work then
                        showRoute route model

                    else
                        requestWork work route model

                Nothing ->
                    ( model, Cmd.none )


showRoute : Route -> Model -> ( Model, Cmd Msg )
showRoute route model =
    let
        settled =
            { model | pendingRoute = Nothing }

        -- A citation that is not a passage of this work (e.g. an old bookmark) opens the saved position.
        indexFor work ref =
            indexOfRef ref model
                |> Maybe.withDefault (clamp 0 (List.length model.corpus.sentences - 1) ((Dict.get work model.positions |> Maybe.withDefault 1) - 1))
    in
    case route of
        Route.Study work passage ->
            let
                index =
                    indexFor work passage

                moved =
                    if index == settled.sentenceIndex then
                        settled

                    else
                        moveToSentence index settled
            in
            ( applyQuery { moved | screen = WorkspaceScreen, workFinished = False }, Cmd.none )

        Route.Reader work passage ->
            let
                index =
                    indexFor work (passage |> Maybe.withDefault "")
            in
            ( { settled | screen = ReaderScreen, sentenceIndex = index, readerGloss = Nothing }, scrollToSentence index )

        _ ->
            ( settled, Cmd.none )


{-| Restores the popup, its tab, and the open tool from the URL's query.
-}
applyQuery : Model -> Model
applyQuery model =
    let
        query =
            model.routeQuery
    in
    { model
        | popupWord = Dict.get "word" query |> Maybe.andThen String.toInt
        , popupTab =
            if Dict.get "tab" query == Just "sentence" then
                SentenceTab

            else
                WordTab
        , activeModule = Dict.get "tool" query |> Maybe.andThen moduleFromKey
        , historyOpen = Dict.get "history" query == Just "1"
        , historyAttempt = Dict.get "attempt" query |> Maybe.andThen String.toInt
        , queueMode = Dict.get "queue" query == Just "1"
        , todayMode = Dict.get "today" query |> Maybe.map Today.modeFromString
    }


queryFor : Model -> String
queryFor model =
    let
        pairs =
            List.filterMap identity
                [ model.popupWord |> Maybe.map (\word -> "word=" ++ String.fromInt word)
                , model.popupWord
                    |> Maybe.andThen
                        (\_ ->
                            if model.popupTab == SentenceTab then
                                Just "tab=sentence"

                            else
                                Nothing
                        )
                , model.activeModule |> Maybe.map (\moduleId -> "tool=" ++ moduleKey moduleId)
                , if model.historyOpen then
                    Just "history=1"

                  else
                    Nothing
                , model.historyAttempt |> Maybe.map (\finishedAt -> "attempt=" ++ String.fromInt finishedAt)
                , if model.queueMode then
                    Just "queue=1"

                  else
                    Nothing
                , model.todayMode |> Maybe.map (\mode -> "today=" ++ Today.modeToString mode)
                ]
    in
    if List.isEmpty pairs then
        ""

    else
        "?" ++ String.join "&" pairs


{-| The URL follows the model; `replace` avoids a history entry for same-page changes.
-}
syncUrl : Bool -> Model -> Cmd Msg -> ( Model, Cmd Msg )
syncUrl replace model cmd =
    case ( model.pendingRoute, pathFor model ) of
        ( Nothing, Just path ) ->
            if path == model.currentPath then
                ( model, cmd )

            else
                ( { model | currentPath = path }
                , Cmd.batch
                    [ cmd
                    , if replace then
                        Nav.replaceUrl model.key path

                      else
                        Nav.pushUrl model.key path
                    , savePosition model
                    ]
                )

        _ ->
            ( model, cmd )


basePath : Model -> Maybe String
basePath model =
    let
        passage =
            currentRef model

        forWork toRoute =
            model.activeEntry |> Maybe.map (\entry -> Route.toPath (toRoute entry.id))
    in
    case model.screen of
        LibraryScreen ->
            Just (Route.toPath Route.Library)

        SettingsScreen ->
            Just (Route.toPath Route.Settings)

        WorkspaceScreen ->
            forWork (\work -> Route.Study work passage)

        ReaderScreen ->
            forWork (\work -> Route.Reader work (Just passage))

        TodayScreen ->
            Just (Route.toPath Route.Today)

        WordScreen lemma ->
            Just (Route.toPath (Route.Word lemma))

        WordReviewScreen lemma ->
            Just (Route.toPath (Route.WordReview lemma))

        StatsScreen ->
            Just (Route.toPath Route.Stats)

        WhatsNewScreen ->
            Just (Route.toPath Route.WhatsNew)


pathFor : Model -> Maybe String
pathFor model =
    case model.screen of
        WorkspaceScreen ->
            basePath model |> Maybe.map (\path -> path ++ queryFor model)

        TodayScreen ->
            basePath model |> Maybe.map (\path -> path ++ todayQuery model)

        WordReviewScreen _ ->
            basePath model |> Maybe.map (\path -> path ++ todayQuery model)

        _ ->
            basePath model


todayQuery : Model -> String
todayQuery model =
    model.todayMode |> Maybe.map (\mode -> "?today=" ++ Today.modeToString mode) |> Maybe.withDefault ""


handleStorageResponse : Decode.Value -> Model -> Model
handleStorageResponse value model =
    case Decode.decodeValue storageResponseDecoder value of
        Ok response ->
            if not response.ok then
                model

            else if String.startsWith "study-draft:" response.id then
                if Just (String.dropLeft 12 response.id) == draftKey model then
                    case Decode.decodeValue (Decode.field "value" Study.draftDecoder) response.value of
                        Ok draft ->
                            { model | study = resumable model.clock draft }

                        Err _ ->
                            model

                else
                    model

            else if response.id == "attempts" then
                -- The progress store holds both finished attempts and review cards.
                case Decode.decodeValue (Decode.list (Decode.oneOf [ Decode.map Just Study.attemptDecoder, Decode.succeed Nothing ])) response.value of
                    Ok attempts ->
                        let
                            finished =
                                List.filterMap identity attempts

                            wordReviews =
                                Decode.decodeValue (Decode.list (Decode.oneOf [ Decode.map Just Words.reviewDecoder, Decode.succeed Nothing ])) response.value
                                    |> Result.withDefault []
                                    |> List.filterMap identity
                        in
                        { model
                            | attempts = finished
                            , wordReviews = wordReviews
                            , wordCards = Words.cards finished wordReviews
                            , reviews =
                                Decode.decodeValue (Decode.list (Decode.oneOf [ Decode.map Just Review.entryDecoder, Decode.succeed Nothing ])) response.value
                                    |> Result.withDefault []
                                    |> List.filterMap identity
                                    |> List.map (\entry -> ( Review.entryKey entry.work entry.passage, entry ))
                                    |> Dict.fromList
                                    |> (\stored -> Review.cards stored finished)
                        }

                    Err _ ->
                        model

            else if response.id == "today-scope" then
                case Decode.decodeValue (Decode.field "value" Decode.string) response.value of
                    Ok work ->
                        { model
                            | todayScope =
                                if String.isEmpty work then
                                    Nothing

                                else
                                    Just work
                        }

                    Err _ ->
                        model

            else if response.id == "review-settings" then
                case Decode.decodeValue (Decode.at [ "value", "newPerDay" ] Decode.int) response.value of
                    Ok newPerDay ->
                        { model | newPerDay = newPerDay }

                    Err _ ->
                        model

            else if response.id == "sync-state" then
                -- Read once at start (null on a device that never synced); the next tick syncs if signed in.
                { model
                    | syncLoaded = True
                    , syncDueAt = 1
                    , sync = Decode.decodeValue (Decode.field "value" Sync.decodeState) response.value |> Result.withDefault model.sync
                }

            else if response.id == "positions" then
                case Decode.decodeValue (Decode.field "value" (Decode.dict Decode.int)) response.value of
                    Ok positions ->
                        { model | positions = Dict.union model.positions positions }

                    Err _ ->
                        model

            else if response.id == "theme" then
                case Decode.decodeValue (Decode.field "value" Decode.string) response.value of
                    Ok "light" ->
                        { model | theme = LightTheme }

                    Ok "dark" ->
                        { model | theme = DarkTheme }

                    _ ->
                        model

            else if response.id == "reader-layers" then
                case
                    Decode.decodeValue
                        (Decode.field "value"
                            (Decode.map3 ReaderLayers
                                (Decode.field "glosses" Decode.bool)
                                (Decode.field "morphology" Decode.bool)
                                (Decode.field "translation" Decode.bool)
                            )
                        )
                        response.value
                of
                    Ok layers ->
                        { model | readerLayers = layers }

                    Err _ ->
                        model

            else if response.id == "cached-corpus" && not model.corpusLoadedFromNetwork then
                case Decode.decodeValue (Decode.field "value" cachedCorpusDecoder) response.value of
                    Ok ( entry, raw, units ) ->
                        useCachedCorpus entry raw units model

                    Err _ ->
                        model

            else if response.id == "legacy-manifest" then
                case Decode.decodeValue (Decode.field "value" manifestDecoder) response.value of
                    Ok manifest ->
                        { model | legacyManifestEntry = List.head manifest.corpora }
                            |> loadLegacyCache

                    Err _ ->
                        model

            else if response.id == "legacy-corpus" then
                case Decode.decodeValue (Decode.field "content" Decode.string) response.value of
                    Ok raw ->
                        { model | legacyCorpusRaw = Just raw }
                            |> loadLegacyCache

                    Err _ ->
                        model

            else
                model

        Err _ ->
            model


installCorpus : Bool -> ManifestEntry -> Corpus -> Model -> Model
installCorpus loadedFromNetwork entry corpus model =
    { model
        | notice = Nothing
        , activeEntry = Just entry
        , corpus = corpus
        , corpusReady = True
        , corpusLoadedFromNetwork = model.corpusLoadedFromNetwork || loadedFromNetwork
        , sentenceIndex = 0
        , study = Study.emptyDraft
        , popupWord = Nothing
        , readerGloss = Nothing
        , readerRevealed = Set.empty
    }


{-| Opens the first passage whose citation starts with `prefix` (`1` = chapter 1, `1.2` = 1:2), in the reader or
study view, whichever is showing.
-}
jumpToCitation : String -> Model -> ( Model, Cmd Msg )
jumpToCitation prefix model =
    let
        wanted =
            Passage.parts prefix

        target =
            model.corpus.sentences
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, passage ) -> List.take (List.length wanted) (Passage.parts passage.id) == wanted)
                |> List.head
                |> Maybe.map Tuple.first
    in
    case target of
        Just index ->
            if model.screen == ReaderScreen then
                ( { model | sentenceIndex = index, readerGloss = Nothing }, scrollToSentence index )

            else
                ( moveToSentence index (browsing model), Cmd.none )

        Nothing ->
            ( { model | notice = Just ("No passage " ++ prefix ++ " in " ++ workTitle model ++ ".") }, Cmd.none )


{-| `1:2`, `1 2`, `1,2`, or `43 §2` typed into the go-to box -> `1.2` or `43.2`.
-}
normalizeCitation : String -> String
normalizeCitation typed =
    typed
        |> String.trim
        |> String.map
            (\char ->
                if char == ':' || char == ' ' || char == ',' || char == '§' then
                    '.'

                else
                    char
            )
        |> String.split "."
        |> List.filter (not << String.isEmpty)
        |> String.join "."


{-| The current passage's citation (`1.2`), which keys drafts, attempts, review cards, and URLs.
-}
currentRef : Model -> String
currentRef model =
    (currentSentence model).id


{-| The current passage's display citation (`1:2`, `1.1.1`).
-}
currentLabel : Model -> String
currentLabel model =
    (currentSentence model).verse


indexOfRef : String -> Model -> Maybe Int
indexOfRef ref model =
    model.corpus.sentences
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, passage ) -> passage.id == ref)
        |> List.head
        |> Maybe.map Tuple.first


{-| Choosing a passage by hand leaves today's review queue.
-}
browsing : Model -> Model
browsing model =
    { model | queueMode = False, queueDone = False, todayMode = Nothing }


{-| After a graded passage: the next sentence in today's queue, or in text order when browsing.
-}
advance : Model -> Model
advance model =
    if model.queueMode then
        case todayQueue model |> Maybe.andThen (\today -> List.head (today.due ++ today.new)) of
            Just passage ->
                moveToSentence (indexOfRef passage model |> Maybe.withDefault model.sentenceIndex) { model | queueDone = False }

            Nothing ->
                { model | queueDone = True, popupWord = Nothing, activeModule = Nothing }

    else if model.sentenceIndex < List.length model.corpus.sentences - 1 then
        moveToSentence (model.sentenceIndex + 1) model

    else
        -- The last passage of the work: say so, rather than showing it again with the answers cleared.
        { model | workFinished = True, popupWord = Nothing, activeModule = Nothing }


todayQueue : Model -> Maybe Review.Queue
todayQueue model =
    model.activeEntry
        |> Maybe.map (\entry -> Review.queue model.clock (newLimit model) entry.id (List.map .id model.corpus.sentences) model.reviews)


{-| Today's new-passage limit: the daily setting plus whatever "Learn more" added today.
-}
newLimit : Model -> Int
newLimit model =
    if model.extraNew.day == Review.startOfDay model.clock then
        model.newPerDay + model.extraNew.count

    else
        model.newPerDay


{-| How many new passages one "Learn more" adds.
-}
learnMoreStep : Model -> Int
learnMoreStep model =
    max 1 model.newPerDay


{-| Whether "Learn more" would find unseen passages: in the open work during a work's queue, else in today's scope.
-}
moreToLearn : Model -> Bool
moreToLearn model =
    let
        more =
            { model | extraNew = { day = Review.startOfDay model.clock, count = model.extraNew.count + learnMoreStep model + 100000 } }
    in
    if model.queueMode then
        todayQueue more |> Maybe.map (.new >> List.isEmpty >> not) |> Maybe.withDefault False

    else
        not (List.isEmpty (todayPlan more).new)


{-| Today's session across every work (see `Today`).
-}
todayPlan : Model -> Today.Plan
todayPlan model =
    Today.plan model.clock (newLimit model) model.todayScope (lastWork model) (List.map (\entry -> { id = entry.id, passages = entry.passages }) model.library) model.reviews model.wordCards


{-| The work of the most recent graded passage, where new passages continue.
-}
lastWork : Model -> Maybe String
lastWork model =
    model.attempts |> List.sortBy (\attempt -> negate attempt.finishedAt) |> List.head |> Maybe.map .work


queryMode : Model -> Today.Mode
queryMode model =
    Dict.get "today" model.routeQuery |> Maybe.map Today.modeFromString |> Maybe.withDefault Today.Everything


{-| Opens the session's next item: a word review or a passage, in any work; with nothing due, today's page.
-}
goToday : Today.Mode -> Model -> ( Model, Cmd Msg )
goToday mode model =
    let
        query =
            "?today=" ++ Today.modeToString mode

        path =
            case Today.next mode (todayPlan model) of
                Just (Today.WordItem lemma) ->
                    Route.toPath (Route.WordReview lemma)

                Just (Today.PassageItem work passage) ->
                    Route.toPath (Route.Study work passage)

                Nothing ->
                    Route.toPath Route.Today
    in
    ( { model | todayMode = Just mode }, Nav.pushUrl model.key (path ++ query) )


saveTodayScope : Maybe String -> Cmd Msg
saveTodayScope scope =
    storagePut "save-today-scope" "metadata" (Encode.object [ ( "key", Encode.string "today-scope" ), ( "value", Encode.string (Maybe.withDefault "" scope) ) ])


{-| The occurrence to quiz a word in: when studying one work, its latest occurrence there.
-}
reviewContext : Model -> Words.Card -> Words.Occurrence
reviewContext model word =
    model.todayScope
        |> Maybe.andThen (\work -> Dict.get work word.works)
        |> Maybe.withDefault word.context


loadingIndex : LemmaIndex -> LemmaIndex
loadingIndex index =
    case index of
        IndexLoaded _ ->
            index

        _ ->
            IndexLoading


loadLemmaIndex : Model -> Cmd Msg
loadLemmaIndex model =
    case model.lemmaIndex of
        IndexLoaded _ ->
            Cmd.none

        IndexLoading ->
            Cmd.none

        _ ->
            Http.get { url = "/preload/lemmas.json", expect = Http.expectJson GotLemmaIndex lemmaDataDecoder }


lemmaDataDecoder : Decode.Decoder LemmaData
lemmaDataDecoder =
    Decode.map2 LemmaData
        (Decode.field "lemmas"
            (Decode.dict
                (Decode.list
                    (Decode.map5 IndexOccurrence
                        (Decode.field "work" Decode.string)
                        (Decode.field "ref" Decode.string)
                        (Decode.field "position" Decode.int)
                        (Decode.field "form" Decode.string)
                        (Decode.field "gloss" Decode.string)
                    )
                )
            )
        )
        (Decode.field "passages" (Decode.dict (Decode.dict Decode.string)))


{-| OGA numbers homographs (`λέγω3`); the number is kept in keys but not shown.
-}
displayLemma : String -> String
displayLemma lemma =
    let
        trimmed =
            String.foldr
                (\char found ->
                    if String.isEmpty found && Char.isDigit char then
                        found

                    else
                        String.cons char found
                )
                ""
                lemma
    in
    if String.isEmpty trimmed then
        lemma

    else
        trimmed


moveToSentence : Int -> Model -> Model
moveToSentence sentenceIndex model =
    if sentenceIndex < 0 || sentenceIndex >= List.length model.corpus.sentences then
        model

    else
        { model
            | screen = WorkspaceScreen
            , allWords = False
            , sentenceIndex = sentenceIndex
            , popupWord = Nothing
            , historyOpen = False
            , historyAttempt = Nothing
            , notice = Nothing
            , workFinished = False
        }


storageGetAll : String -> String -> Cmd msg
storageGetAll requestId store =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "getAll" )
            , ( "store", Encode.string store )
            ]
        )


storageClear : String -> String -> Cmd msg
storageClear requestId store =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "clear" )
            , ( "store", Encode.string store )
            ]
        )


settingsForPreset : Preset -> ModuleSettings -> ModuleSettings
settingsForPreset preset current =
    case preset of
        ReadPreset ->
            readSettings

        AssistedPreset ->
            assistedSettings

        IntensivePreset ->
            intensiveSettings

        CustomPreset ->
            current


moduleMode : ModuleId -> ModuleSettings -> ModuleMode
moduleMode moduleId settings =
    case moduleId of
        GlossModule ->
            settings.gloss

        LiteralModule ->
            settings.literal

        ProseModule ->
            settings.prose


setModuleMode : ModuleId -> ModuleMode -> ModuleSettings -> ModuleSettings
setModuleMode moduleId mode settings =
    case moduleId of
        GlossModule ->
            { settings | gloss = mode }

        LiteralModule ->
            { settings | literal = mode }

        ProseModule ->
            { settings | prose = mode }


enabledModules : ModuleSettings -> List ModuleId
enabledModules settings =
    [ GlossModule, LiteralModule, ProseModule ]
        |> List.filter (\moduleId -> moduleMode moduleId settings /= ModuleOff)


moduleKey : ModuleId -> String
moduleKey moduleId =
    case moduleId of
        GlossModule ->
            "gloss"

        LiteralModule ->
            "literal"

        ProseModule ->
            "prose"


moduleFromKey : String -> Maybe ModuleId
moduleFromKey key =
    case key of
        "gloss" ->
            Just GlossModule

        "literal" ->
            Just LiteralModule

        "prose" ->
            Just ProseModule

        _ ->
            Nothing


moduleName : ModuleId -> String
moduleName moduleId =
    case moduleId of
        GlossModule ->
            "Glosses"

        LiteralModule ->
            "Literal translation"

        ProseModule ->
            "Prose translation"


corpusSourceDecoder : Decode.Decoder CorpusSource
corpusSourceDecoder =
    Decode.map5
        (\name url commit license edition ->
            { name = name
            , url = url
            , commit = commit
            , license = license
            , edition = edition
            }
        )
        (Decode.field "name" Decode.string)
        (Decode.field "url" Decode.string)
        (Decode.field "commit" Decode.string)
        (Decode.field "license" Decode.string)
        (Decode.field "edition" Decode.string)


manifestDecoder : Decode.Decoder Manifest
manifestDecoder =
    Decode.map2 Manifest
        (Decode.field "version" Decode.int)
        (Decode.field "corpora" (Decode.list manifestEntryDecoder))


manifestEntryDecoder : Decode.Decoder ManifestEntry
manifestEntryDecoder =
    -- Title, counts, citation, and passages default so entries cached by earlier builds still decode.
    Decode.map3 (\entry unitsPath passages -> entry unitsPath passages)
        (Decode.map7 ManifestEntry
            (Decode.field "id" Decode.string)
            (Decode.oneOf [ Decode.field "title" Decode.string, Decode.field "id" Decode.string ])
            (Decode.field "path" Decode.string)
            (Decode.oneOf [ Decode.field "sentenceCount" Decode.int, Decode.succeed 0 ])
            (Decode.oneOf [ Decode.field "tokenCount" Decode.int, Decode.succeed 0 ])
            (Decode.field "source" corpusSourceDecoder)
            (Decode.oneOf [ Decode.field "citation" (Decode.map Just Sources.decoder), Decode.succeed Nothing ])
        )
        (Decode.oneOf [ Decode.field "unitsPath" Decode.string, Decode.succeed "" ])
        (Decode.oneOf [ Decode.field "passages" (Decode.list Decode.string), Decode.succeed [] ])


storageResponseDecoder : Decode.Decoder StorageResponse
storageResponseDecoder =
    Decode.map3 StorageResponse
        (Decode.field "id" Decode.string)
        (Decode.field "ok" Decode.bool)
        (Decode.field "value" Decode.value)


cachedCorpusDecoder : Decode.Decoder ( ManifestEntry, String, String )
cachedCorpusDecoder =
    Decode.map3 (\entry raw units -> ( entry, raw, units ))
        (Decode.field "entry" manifestEntryDecoder)
        (Decode.field "raw" Decode.string)
        (Decode.oneOf [ Decode.field "units" Decode.string, Decode.succeed "" ])


fallbackCorpus : Corpus
fallbackCorpus =
    { source =
        { name = ""
        , url = ""
        , commit = ""
        , license = ""
        , edition = ""
        }
    , sentences =
        [ { id = "missing"
          , chapter = 1
          , verse = "1"
          , text = "No corpus loaded."
          , literalTranslation = ""
          , proseTranslation = ""
          , tokens = []
          , placeholders = []
          }
        ]
    }


keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.map4
        (\key tag ctrl meta -> ( key, tag, ctrl || meta ))
        (Decode.field "key" Decode.string)
        (Decode.oneOf [ Decode.at [ "target", "tagName" ] Decode.string, Decode.succeed "" ])
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "metaKey" Decode.bool)
        |> Decode.andThen
            (\( key, tag, modified ) ->
                if modified then
                    Decode.fail "modified key"

                else
                    Decode.succeed (KeyPressed key tag)
            )


handleShortcut : String -> Model -> ( Model, Cmd Msg )
handleShortcut key model =
    case ( model.screen, key ) of
        ( WorkspaceScreen, "ArrowLeft" ) ->
            ( moveToSentence (model.sentenceIndex - 1) (browsing model), Cmd.none )

        ( WorkspaceScreen, "k" ) ->
            ( moveToSentence (model.sentenceIndex - 1) (browsing model), Cmd.none )

        ( WorkspaceScreen, "ArrowRight" ) ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        ( WorkspaceScreen, "j" ) ->
            ( moveToSentence (model.sentenceIndex + 1) (browsing model), Cmd.none )

        ( ReaderScreen, "j" ) ->
            updateModel (ReaderStep 1) model

        ( ReaderScreen, "ArrowRight" ) ->
            updateModel (ReaderStep 1) model

        ( ReaderScreen, "k" ) ->
            updateModel (ReaderStep -1) model

        ( ReaderScreen, "ArrowLeft" ) ->
            updateModel (ReaderStep -1) model

        ( WorkspaceScreen, "Escape" ) ->
            if model.historyOpen then
                ( { model | historyOpen = False, historyAttempt = Nothing }, Cmd.none )

            else if model.popupWord /= Nothing then
                ( { model | popupWord = Nothing }, Cmd.none )

            else
                ( { model | activeModule = Nothing }, Cmd.none )

        ( ReaderScreen, "Escape" ) ->
            if model.readerGloss /= Nothing then
                ( { model | readerGloss = Nothing }, Cmd.none )

            else
                ( { model | screen = WorkspaceScreen }, Cmd.none )

        _ ->
            ( model, Cmd.none )



-- ROUTING


routeWork : Route -> Maybe String
routeWork route =
    case route of
        Route.Study work _ ->
            Just work

        Route.Reader work _ ->
            Just work

        _ ->
            Nothing


requestWork : String -> Route -> Model -> ( Model, Cmd Msg )
requestWork work route model =
    let
        waiting =
            { model | requestedWork = Just work, pendingRoute = Just route }
    in
    if List.isEmpty model.library then
        -- handleManifest resumes this request once the library arrives.
        ( waiting, Cmd.none )

    else
        case List.filter (\entry -> entry.id == work) model.library of
            entry :: _ ->
                ( { waiting | notice = Just ("Loading " ++ entry.title ++ "…") }, fetchCorpus entry )

            [] ->
                ( { model | screen = LibraryScreen, pendingRoute = Nothing, notice = Just ("No work named “" ++ work ++ "” is bundled.") }, Cmd.none )


savePosition : Model -> Cmd Msg
savePosition model =
    case model.activeEntry of
        Just entry ->
            if model.screen == WorkspaceScreen || model.screen == ReaderScreen then
                storagePut "save-positions"
                    "metadata"
                    (Encode.object
                        [ ( "key", Encode.string "positions" )
                        , ( "value", Encode.dict identity Encode.int (Dict.insert entry.id (model.sentenceIndex + 1) model.positions) )
                        ]
                    )

            else
                Cmd.none

        Nothing ->
            Cmd.none



-- SWIPING


swipeThreshold : Float
swipeThreshold =
    60


followSwipe : Float -> Float -> Float -> Swipe -> Swipe
followSwipe x y time swipe =
    let
        dx =
            x - swipe.startX

        dy =
            y - swipe.startY
    in
    case swipe.axis of
        Undecided ->
            if max (abs dx) (abs dy) < 10 then
                swipe

            else if time - swipe.startTime > 500 || abs dx < abs dy * 1.2 then
                -- A slow start is a long press selecting text; a steep one is a scroll.
                { swipe | axis = Vertical }

            else
                { swipe | axis = Horizontal, dx = dx }

        Horizontal ->
            { swipe | dx = dx }

        Vertical ->
            swipe


{-| Touch handlers and the finger-following offset for a swipeable passage. `atStart` and `atEnd` damp the offset
when there is no passage in that direction.
-}
swipeAttributes : Model -> Bool -> Bool -> List (Html.Attribute Msg)
swipeAttributes model atStart atEnd =
    let
        touchAt field =
            Decode.at [ "touches", "0", field ] Decode.float

        single toMsg =
            Decode.at [ "touches", "length" ] Decode.int
                |> Decode.andThen
                    (\count ->
                        if count == 1 then
                            Decode.map3 toMsg (touchAt "clientX") (touchAt "clientY") (Decode.field "timeStamp" Decode.float)

                        else
                            Decode.succeed SwipeEnd
                    )

        offset =
            case model.swipe of
                Just swipe ->
                    if swipe.axis == Horizontal then
                        if (swipe.dx > 0 && atStart) || (swipe.dx < 0 && atEnd) then
                            swipe.dx * 0.12

                        else
                            swipe.dx * 0.4

                    else
                        0

                Nothing ->
                    0
    in
    [ class "is-swipeable"
    , classList [ ( "is-swiping", offset /= 0 ) ]
    , on "touchstart" (single SwipeStart)
    , on "touchmove" (single SwipeMove)
    , on "touchend" (Decode.succeed SwipeEnd)
    , on "touchcancel" (Decode.succeed SwipeEnd)
    ]
        ++ (if offset == 0 then
                []

            else
                [ style "transform" ("translateX(" ++ String.fromFloat offset ++ "px)") ]
           )



-- READER SCROLLING


readerScrollId : String
readerScrollId =
    "reader-scroll"


sentenceElementId : Int -> String
sentenceElementId index =
    "passage-" ++ String.fromInt (index + 1)


scrollToSentence : Int -> Cmd Msg
scrollToSentence index =
    Task.map3
        (\container viewport sentence -> viewport.viewport.y + sentence.element.y - container.element.y - 24)
        (Dom.getElement readerScrollId)
        (Dom.getViewportOf readerScrollId)
        (Dom.getElement (sentenceElementId index))
        |> Task.andThen (\y -> Dom.setViewportOf readerScrollId 0 y)
        |> Task.attempt (\_ -> NoOp)


measureReader : Int -> Model -> Cmd Msg
measureReader generation model =
    Task.map2 Tuple.pair
        (Dom.getElement readerScrollId)
        (model.corpus.sentences |> List.indexedMap (\index _ -> Dom.getElement (sentenceElementId index)) |> Task.sequence)
        |> Task.attempt (ReaderMeasured generation)


fetchManifest : Cmd Msg
fetchManifest =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Cache-Control" "no-cache" ]
        , url = "/preload/corpora.json"
        , body = Http.emptyBody
        , expect = Http.expectJson GotManifest manifestDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


handleManifest : Result Http.Error Manifest -> Model -> ( Model, Cmd Msg )
handleManifest result model =
    case result of
        Ok manifest ->
            if manifest.version /= 1 then
                ( model, Cmd.none )

            else
                -- A work URL opened before the library arrived loads now.
                case ( model.pendingRoute |> Maybe.andThen routeWork, model.corpusReady ) of
                    ( Just work, False ) ->
                        case model.pendingRoute of
                            Just route ->
                                requestWork work route { model | library = manifest.corpora }

                            Nothing ->
                                ( { model | library = manifest.corpora }, Cmd.none )

                    _ ->
                        ( { model | library = manifest.corpora }, Cmd.none )

        Err _ ->
            ( model, Cmd.none )


fetchCorpus : ManifestEntry -> Cmd Msg
fetchCorpus entry =
    Task.map2 Tuple.pair
        (fetchText entry.path)
        (if String.isEmpty entry.unitsPath then
            Task.succeed ""

         else
            fetchText entry.unitsPath
        )
        |> Task.attempt (GotCorpus entry)


fetchText : String -> Task.Task Http.Error String
fetchText path =
    Http.task
        { method = "GET"
        , headers = [ Http.header "Cache-Control" "no-cache" ]
        , url = "/preload/" ++ path
        , body = Http.emptyBody
        , resolver =
            Http.stringResolver
                (\response ->
                    case response of
                        Http.GoodStatus_ _ body ->
                            Ok body

                        Http.BadStatus_ metadata _ ->
                            Err (Http.BadStatus metadata.statusCode)

                        Http.BadUrl_ url ->
                            Err (Http.BadUrl url)

                        Http.Timeout_ ->
                            Err Http.Timeout

                        Http.NetworkError_ ->
                            Err Http.NetworkError
                )
        , timeout = Nothing
        }


{-| A work's sentences regrouped into its canonical passages; works without a passages file keep their sentences.
-}
parseWork : ManifestEntry -> String -> String -> Result String Corpus
parseWork entry raw units =
    Conllu.parse entry.source raw
        |> Result.andThen
            (\corpus ->
                if String.isEmpty units then
                    Ok corpus

                else
                    Decode.decodeString Passage.unitsDecoder units
                        |> Result.mapError Decode.errorToString
                        |> Result.map (\decoded -> Passage.fromUnits decoded corpus)
            )


handleFetchedCorpus : ManifestEntry -> Result Http.Error ( String, String ) -> Model -> ( Model, Cmd Msg )
handleFetchedCorpus entry result model =
    case result of
        Ok ( raw, units ) ->
            case parseWork entry raw units of
                Ok corpus ->
                    if model.requestedWork /= Just entry.id then
                        ( model, Cmd.none )

                    else
                        let
                            -- A fresh download of the work already shown from cache keeps the reader's place.
                            installed =
                                if model.corpusReady && Maybe.map .id model.activeEntry == Just entry.id then
                                    { model
                                        | corpus = corpus
                                        , activeEntry = Just entry
                                        , corpusLoadedFromNetwork = True
                                        , sentenceIndex = clamp 0 (List.length corpus.sentences - 1) model.sentenceIndex
                                    }

                                else
                                    installCorpus True entry corpus model

                            ( shown, routeCmd ) =
                                showPending installed
                        in
                        ( shown
                        , Cmd.batch
                            [ routeCmd
                            , storagePut "cache-corpus"
                                "metadata"
                                (Encode.object
                                    [ ( "key", Encode.string "cached-corpus" )
                                    , ( "value"
                                      , Encode.object
                                            [ ( "entry", encodeManifestEntry entry )
                                            , ( "raw", Encode.string raw )
                                            , ( "units", Encode.string units )
                                            ]
                                      )
                                    ]
                                )
                            , storagePut "cache-manifest"
                                "metadata"
                                (Encode.object
                                    [ ( "key", Encode.string "preload-manifest" )
                                    , ( "value"
                                      , Encode.object
                                            [ ( "version", Encode.int 1 )
                                            , ( "corpora", Encode.list encodeManifestEntry [ entry ] )
                                            ]
                                      )
                                    ]
                                )
                            , storagePut "cache-raw-corpus"
                                "corpora"
                                (Encode.object
                                    [ ( "id", Encode.string entry.id )
                                    , ( "path", Encode.string entry.path )
                                    , ( "content", Encode.string raw )
                                    ]
                                )
                            ]
                        )

                Err problem ->
                    ( { model | pendingRoute = Nothing, notice = Just (entry.title ++ " could not be parsed: " ++ problem) }, Cmd.none )

        Err _ ->
            if model.requestedWork == Just entry.id then
                ( { model | pendingRoute = Nothing, notice = Just (entry.title ++ " could not be downloaded. Try again.") }, Cmd.none )

            else
                ( model, Cmd.none )


useCachedCorpus : ManifestEntry -> String -> String -> Model -> Model
useCachedCorpus entry raw units model =
    case ( model.requestedWork == Just entry.id && not model.corpusReady, parseWork entry raw units ) of
        ( True, Ok corpus ) ->
            installCorpus False entry corpus model

        _ ->
            model


showPending : Model -> ( Model, Cmd Msg )
showPending model =
    case model.pendingRoute of
        Just route ->
            if model.corpusReady && Maybe.map .id model.activeEntry == routeWork route then
                showRoute route model

            else
                ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


loadLegacyCache : Model -> Model
loadLegacyCache model =
    if model.corpusReady then
        model

    else
        case ( model.legacyManifestEntry, model.legacyCorpusRaw ) of
            ( Just entry, Just raw ) ->
                useCachedCorpus entry raw "" model

            _ ->
                model


storageGet : String -> String -> String -> Cmd msg
storageGet requestId store key =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "get" )
            , ( "store", Encode.string store )
            , ( "key", Encode.string key )
            ]
        )


storagePut : String -> String -> Encode.Value -> Cmd msg
storagePut requestId store storedValue =
    storageRequest
        (Encode.object
            [ ( "id", Encode.string requestId )
            , ( "operation", Encode.string "put" )
            , ( "store", Encode.string store )
            , ( "value", storedValue )
            ]
        )


encodeManifestEntry : ManifestEntry -> Encode.Value
encodeManifestEntry entry =
    Encode.object
        [ ( "id", Encode.string entry.id )
        , ( "title", Encode.string entry.title )
        , ( "path", Encode.string entry.path )
        , ( "sentenceCount", Encode.int entry.sentenceCount )
        , ( "tokenCount", Encode.int entry.tokenCount )
        , ( "source", encodeCorpusSource entry.source )
        , ( "citation", entry.citation |> Maybe.map Sources.encode |> Maybe.withDefault Encode.null )
        , ( "unitsPath", Encode.string entry.unitsPath )
        , ( "passages", Encode.list Encode.string entry.passages )
        ]


encodeCorpusSource : CorpusSource -> Encode.Value
encodeCorpusSource source =
    Encode.object
        [ ( "name", Encode.string source.name )
        , ( "url", Encode.string source.url )
        , ( "commit", Encode.string source.commit )
        , ( "license", Encode.string source.license )
        , ( "edition", Encode.string source.edition )
        ]


viewReader : Model -> Html Msg
viewReader model =
    let
        total =
            List.length model.corpus.sentences
    in
    main_ [ class "reader-page" ]
        [ header [ class "reader-bar" ]
            [ button [ class "icon-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Back to library" ] [ text "←" ]
            , div [ class "reader-bar-title" ]
                [ span [ class "context-work" ] [ text (workTitle model) ]
                , span [ class "reader-position" ] [ text (currentLabel model ++ " · " ++ String.fromInt (model.sentenceIndex + 1) ++ " / " ++ String.fromInt total) ]
                ]
            , button [ class "icon-button reader-prev", type_ "button", onClick (ReaderStep -1), disabled (model.sentenceIndex == 0), attribute "aria-label" "Previous passage (k)" ] [ text "‹" ]
            , viewCitationPicker model
            , button [ class "icon-button reader-next", type_ "button", onClick (ReaderStep 1), disabled (model.sentenceIndex >= total - 1), attribute "aria-label" "Next passage (j)" ] [ text "›" ]
            , button [ class "icon-button reader-theme", type_ "button", onClick ToggleTheme, attribute "aria-label" (themeActionLabel model.theme) ]
                [ text
                    (if model.theme == DarkTheme then
                        "☀"

                     else
                        "☾"
                    )
                ]
            , button [ class "secondary-button reader-study", type_ "button", onClick ShowWorkspace ] [ text "Study", span [ class "wide-only" ] [ text " this passage" ] ]
            ]
        , viewReaderLayers model.readerLayers
        , div [ id readerScrollId, class "reader-scroll", on "scroll" (Decode.succeed ReaderScrolled) ]
            [ article ([ class "reader-text", attribute "lang" "grc" ] ++ swipeAttributes model (model.sentenceIndex == 0) (model.sentenceIndex >= total - 1))
                (List.indexedMap (viewReaderSentence model) model.corpus.sentences)
            , div [ class "reader-end" ] [ text ("End of " ++ workTitle model ++ " in this edition."), activeSources model ]
            ]
        ]


viewReaderSentence : Model -> Int -> Sentence -> Html Msg
viewReaderSentence model index sentence =
    let
        layers =
            model.readerLayers

        revealed =
            Set.member index model.readerRevealed
    in
    section
        [ id (sentenceElementId index)
        , classList [ ( "reader-sentence", True ), ( "is-current", index == model.sentenceIndex ) ]
        ]
        [ button
            [ classList [ ( "reader-marker", True ), ( "is-open", revealed ) ]
            , type_ "button"
            , onClick (ReaderToggleTranslation index)
            , attribute "aria-label"
                (sentence.verse
                    ++ ": "
                    ++ (if revealed then
                            "hide"

                        else
                            "show"
                       )
                    ++ " translation"
                )
            , attribute "aria-expanded" (boolString revealed)
            ]
            [ text sentence.verse ]
        , if layers.glosses || layers.morphology then
            div [ class "reader-interlinear" ] (List.map (viewReaderWord layers) (groupWords sentence.tokens))

          else
            p [ class "reader-greek" ] (List.concat (List.indexedMap (viewReaderToken model index) sentence.tokens))
        , if (layers.translation || revealed) && not (String.isEmpty sentence.proseTranslation) then
            div [ class "reader-translation", attribute "lang" "en" ]
                [ p [] [ text sentence.proseTranslation ]
                , if not revealed || String.isEmpty sentence.literalTranslation then
                    text ""

                  else
                    p [ class "reader-literal" ] [ text sentence.literalTranslation ]
                ]

          else
            text ""
        ]


{-| Switches for what the reader shows with each passage.
-}
viewReaderLayers : ReaderLayers -> Html Msg
viewReaderLayers layers =
    let
        toggle layer label on =
            button
                [ classList [ ( "layer-toggle", True ), ( "is-on", on ) ]
                , type_ "button"
                , onClick (ToggleReaderLayer layer)
                , attribute "aria-pressed" (boolString on)
                ]
                [ text label ]
    in
    div [ class "reader-layers", attribute "role" "group", attribute "aria-label" "Show with the Greek" ]
        [ toggle GlossLayer "Glosses" layers.glosses
        , toggle MorphologyLayer "Morphology" layers.morphology
        , toggle TranslationLayer "Translation" layers.translation
        ]


{-| A word with its following punctuation, and the gloss and morphology beneath it.
-}
viewReaderWord : ReaderLayers -> ( CorpusToken, String ) -> Html Msg
viewReaderWord layers ( token, suffix ) =
    span [ class "reader-word" ]
        [ span [ class "reader-word-greek" ] [ text (token.form ++ suffix) ]
        , if layers.glosses then
            span [ class "reader-word-gloss", attribute "lang" "en" ] [ text (displayGloss token.gloss) ]

          else
            text ""
        , if layers.morphology then
            span [ class "reader-word-morph", attribute "lang" "en" ] [ text (Morphology.abbreviation token.upos token.morphology.summary) ]

          else
            text ""
        ]


viewReaderToken : Model -> Int -> Int -> CorpusToken -> List (Html Msg)
viewReaderToken model sentenceIndex position token =
    let
        open =
            model.readerGloss == Just ( sentenceIndex, token.id )

        spaceBefore =
            if position == 0 || isPunctuation token.form then
                text ""

            else
                text " "
    in
    [ spaceBefore
    , button
        [ classList [ ( "reader-token", True ), ( "is-open", open ) ]
        , type_ "button"
        , onClick (ReaderTokenTapped sentenceIndex token.id)
        ]
        [ text token.form
        , if open then
            span [ class "reader-gloss", attribute "role" "tooltip", attribute "lang" "en" ]
                [ text
                    (if String.isEmpty token.gloss then
                        "No gloss"

                     else
                        String.replace "-" " " token.gloss
                    )
                ]

          else
            text ""
        ]
    ]


isPunctuation : String -> Bool
isPunctuation form =
    not (String.isEmpty form) && String.all (\char -> String.contains (String.fromChar char) ".,;:!?··;)]»”’—–") form


viewAppHeader : Model -> Html Msg
viewAppHeader model =
    header [ id appHeaderId, class "app-header" ]
        [ button [ class "brand-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Lyceum Study library" ]
            [ span [ class "brand-word" ] [ text "Lyceum Study" ]
            ]
        , nav [ class "global-nav", attribute "aria-label" "Primary navigation" ]
            (navButton "Home" (Navigate Route.Library) (model.screen == LibraryScreen || model.screen == TodayScreen)
                :: navButton "Progress" (Navigate Route.Stats) (model.screen == StatsScreen)
                :: viewSupportLink model
                :: navButton "What's new" (Navigate Route.WhatsNew) (model.screen == WhatsNewScreen)
                :: (case model.activeEntry of
                        Just entry ->
                            [ navButton "Read" (Navigate (Route.Reader entry.id (Just (currentRef model)))) False
                            , navButton "Study" (StartTodayIn entry.id) (List.member model.screen [ WorkspaceScreen, SettingsScreen ])
                            ]

                        Nothing ->
                            []
                   )
            )
        , div [ class "header-actions" ]
            [ viewAccountButton model
            , button
                [ class "theme-button"
                , type_ "button"
                , onClick ToggleTheme
                , attribute "aria-label" (themeActionLabel model.theme)
                , attribute "aria-pressed" (boolString (model.theme == DarkTheme))
                , attribute "title" (themeActionLabel model.theme)
                ]
                [ span [ attribute "aria-hidden" "true" ]
                    [ text
                        (if model.theme == DarkTheme then
                            "☀"

                         else
                            "☾"
                        )
                    ]
                , span [ class "theme-label" ]
                    [ text
                        (if model.theme == DarkTheme then
                            "Light"

                         else
                            "Dark"
                        )
                    ]
                ]
            ]
        ]


{-| Support Lyceum, on Lyceum's own site (the account API's origin; lyceum.quest without one), in a new tab so the
session stays open. Supporters don't see it.
-}
viewSupportLink : Model -> Html Msg
viewSupportLink model =
    let
        supporter =
            case model.account of
                Account.SignedIn _ user ->
                    user.pro

                _ ->
                    False

        origin =
            Account.api model.account |> Maybe.withDefault "https://lyceum.quest"
    in
    if supporter then
        text ""

    else
        a [ class "global-nav-button", href (origin ++ "/pricing"), target "_blank", rel "noopener", attribute "title" "Support Lyceum" ]
            [ text "Support" ]


{-| Sign-in to the optional Lyceum account, shown only when the release names an account API (config.json).
-}
viewAccountButton : Model -> Html Msg
viewAccountButton model =
    case model.account of
        Account.SignedOut _ loginUrl ->
            a [ class "account-button", href (Account.loginHref loginUrl (accountReturnUrl model)) ]
                [ text "Sign in", span [ class "account-label" ] [ text " to sync" ] ]

        Account.SignedIn _ user ->
            a
                [ class "account-button"
                , href (Route.toPath Route.Stats)
                , attribute "title"
                    ("Signed in as "
                        ++ user.handle
                        ++ (if Account.hasSync user then
                                " · " ++ Sync.statusText model.clock model.syncStatus

                            else
                                ""
                           )
                    )
                ]
                [ span [ class "account-handle" ] [ text user.handle ] ]

        _ ->
            text ""


{-| The account panel on the Progress page.
-}
viewAccountPanel : Model -> Html Msg
viewAccountPanel model =
    let
        panel =
            section [ class "account-panel" ]
    in
    case model.account of
        Account.NotConfigured ->
            text ""

        Account.Checking _ ->
            panel [ p [ class "muted" ] [ text "Checking your Lyceum account…" ] ]

        Account.Unreachable _ ->
            panel [ p [ class "muted" ] [ text "Your Lyceum account can't be reached right now. Progress is saved on this device." ] ]

        Account.SignedOut _ loginUrl ->
            panel
                [ p [] [ text "Progress is saved on this device only. Sign in with a Lyceum account to sync it across devices." ]
                , a [ class "primary-button", href (Account.loginHref loginUrl (accountReturnUrl model)) ] [ text "Sign in to sync" ]
                ]

        Account.SignedIn origin user ->
            panel
                (p [] [ text "Signed in to Lyceum as ", span [ class "account-handle" ] [ text user.handle ], text "." ]
                    :: (if Account.hasSync user then
                            [ p [ class "muted sync-status" ] [ text (Sync.statusText model.clock model.syncStatus) ]
                            , button [ class "secondary-button", type_ "button", onClick SyncNow, disabled model.syncBusy ] [ text "Sync now" ]
                            ]

                        else
                            [ p [ class "muted" ] [ text "Progress is saved on this device. Syncing it across your devices comes with supporting Lyceum." ]
                            , a [ class "secondary-button", href (origin ++ "/pricing") ] [ text "Support Lyceum" ]
                            ]
                       )
                    ++ [ button [ class "secondary-button", type_ "button", onClick SignOut ] [ text "Sign out" ] ]
                )


{-| This page's full URL, where Lyceum sends the learner back after sign-in.
-}
accountReturnUrl : Model -> String
accountReturnUrl model =
    Url.toString model.appUrl ++ model.currentPath


navButton : String -> Msg -> Bool -> Html Msg
navButton label msg isActive =
    button
        [ classList [ ( "global-nav-button", True ), ( "is-active", isActive ) ]
        , type_ "button"
        , onClick msg
        ]
        [ text label ]


viewLibrary : Model -> Html Msg
viewLibrary model =
    let
        working =
            workingOn model

        query =
            String.toLower (String.trim model.librarySearch)

        matches entry =
            String.isEmpty query
                || List.any (String.contains query << String.toLower)
                    (entry.title
                        :: entry.source.edition
                        :: (entry.citation |> Maybe.map (\citation -> [ citation.text.author, citation.text.title ]) |> Maybe.withDefault [])
                    )

        activity =
            lastActivity model

        sorted =
            case model.librarySort of
                "title" ->
                    List.sortBy .title model.library

                "short" ->
                    List.sortBy (.passages >> List.length) model.library

                _ ->
                    List.sortBy (\entry -> ( negate (Dict.get entry.id activity |> Maybe.withDefault 0), entry.title )) model.library

        shown =
            List.filter matches sorted
    in
    main_ [ class "page library-page" ]
        [ viewTodayPanel model
        , if List.isEmpty working then
            text ""

          else
            section [ class "home-section", attribute "aria-label" "Working on" ]
                [ h2 [] [ text "Working on" ]
                , div [ class "work-rows" ] (List.map (viewWorkRow model) working)
                ]
        , section [ class "home-section", attribute "aria-label" "Library" ]
            [ div [ class "library-head" ]
                [ h2 [] [ text "Library" ]
                , input
                    [ class "library-search"
                    , type_ "search"
                    , value model.librarySearch
                    , onInput SetLibrarySearch
                    , placeholder "Search title, author, or edition"
                    , attribute "aria-label" "Search the library"
                    ]
                    []
                , select [ class "library-sort", onInput SetLibrarySort, attribute "aria-label" "Sort the library" ]
                    [ option [ value "recent", selected (model.librarySort == "recent") ] [ text "Recently studied" ]
                    , option [ value "title", selected (model.librarySort == "title") ] [ text "Title" ]
                    , option [ value "short", selected (model.librarySort == "short") ] [ text "Shortest first" ]
                    ]
                ]
            , if List.isEmpty model.library then
                p [ class "muted" ] [ text "Loading the library…" ]

              else if List.isEmpty shown then
                p [ class "muted" ] [ text "No works match." ]

              else
                div [ class "work-rows" ] (List.map (viewWorkRow model) shown)
            ]
        ]


{-| When each work was last studied: its latest graded passage or word review.
-}
lastActivity : Model -> Dict String Int
lastActivity model =
    (List.map (\attempt -> ( attempt.work, attempt.finishedAt )) model.attempts
        ++ List.map (\review -> ( review.occurrence.work, review.at )) model.wordReviews
    )
        |> List.foldl (\( work, at ) found -> Dict.update work (Maybe.map (max at) >> Maybe.withDefault at >> Just) found) Dict.empty


{-| The works the learner is working on: studied ones, most recent first, then ones opened but not yet graded.
-}
workingOn : Model -> List ManifestEntry
workingOn model =
    let
        activity =
            lastActivity model

        studied =
            model.library
                |> List.filter (\entry -> Dict.member entry.id activity)
                |> List.sortBy (\entry -> negate (Dict.get entry.id activity |> Maybe.withDefault 0))

        opened =
            List.filter (\entry -> not (Dict.member entry.id activity) && (Dict.member entry.id model.positions || model.todayScope == Just entry.id)) model.library
    in
    studied ++ opened


{-| One work as a compact row: progress and today's counts, Read and Study; edition and source credits on request.
-}
viewWorkRow : Model -> ManifestEntry -> Html Msg
viewWorkRow model entry =
    let
        isLoading =
            model.pendingRoute /= Nothing && model.requestedWork == Just entry.id

        total =
            List.length entry.passages

        studied =
            model.reviews |> Dict.values |> List.filter (\review -> review.work == entry.id) |> List.length

        today =
            Review.queue model.clock model.newPerDay entry.id entry.passages model.reviews

        meta =
            if studied == 0 then
                counted total "passage" "passages" ++ " · not started"

            else
                String.fromInt studied
                    ++ " of "
                    ++ String.fromInt total
                    ++ " passages studied · "
                    ++ String.fromInt (List.length today.due)
                    ++ " due"
    in
    div [ class "work-row" ]
        [ div [ class "work-row-main" ]
            [ h3 [ class "work-row-title" ] [ text entry.title ]
            , p [ class "work-row-meta" ] [ text meta ]
            , details [ class "work-row-sources" ]
                [ summary [] [ text "Edition & sources" ]
                , p [ class "greek-subtitle" ] [ text entry.source.edition ]
                , Sources.view entry.citation
                ]
            ]
        , div [ class "work-row-actions" ]
            [ button [ class "secondary-button", type_ "button", disabled isLoading, onClick (Navigate (Route.Reader entry.id Nothing)) ] [ text "Read" ]
            , button [ class "primary-button", type_ "button", disabled isLoading, onClick (StartTodayIn entry.id) ]
                [ text
                    (if isLoading then
                        "Loading…"

                     else if studied == 0 then
                        "Start →"

                     else
                        "Study →"
                    )
                ]
            ]
        ]



-- TODAY


entryFor : Model -> String -> Maybe ManifestEntry
entryFor model work =
    List.filter (\entry -> entry.id == work) model.library |> List.head


workName : Model -> String -> String
workName model work =
    entryFor model work |> Maybe.map .title |> Maybe.withDefault work


{-| A citation as the work prints it: `1:66` for the Bible, `1.2.1` for sections, `43 §2` for a split page.
-}
refLabel : Model -> String -> String -> String
refLabel model work ref =
    let
        bible =
            entryFor model work
                |> Maybe.andThen .citation
                |> Maybe.map (\citation -> String.contains "tlg0031." citation.text.urn || String.contains "tlg0527." citation.text.urn)
                |> Maybe.withDefault False

        ( base, part ) =
            case String.split "~" ref of
                [ unit, number ] ->
                    ( unit, " §" ++ number )

                _ ->
                    ( ref, "" )

        levels =
            String.split "." base
    in
    (if bible && List.length levels >= 2 then
        String.join "." (List.take (List.length levels - 1) levels) ++ ":" ++ (List.reverse levels |> List.head |> Maybe.withDefault "")

     else
        base
    )
        ++ part


passageName : Model -> String -> String -> String
passageName model work ref =
    workName model work ++ " " ++ refLabel model work ref


itemName : Model -> Today.Item -> String
itemName model item =
    case item of
        Today.WordItem lemma ->
            displayLemma lemma

        Today.PassageItem work passage ->
            passageName model work passage


itemPath : Today.Mode -> Today.Item -> String
itemPath mode item =
    (case item of
        Today.WordItem lemma ->
            Route.toPath (Route.WordReview lemma)

        Today.PassageItem work passage ->
            Route.toPath (Route.Study work passage)
    )
        ++ "?today="
        ++ Today.modeToString mode


counted : Int -> String -> String -> String
counted count one many =
    String.fromInt count
        ++ " "
        ++ (if count == 1 then
                one

            else
                many
           )


{-| The first thing on the home page: what to study now, and where the learner left off.
-}
viewTodayPanel : Model -> Html Msg
viewTodayPanel model =
    let
        today =
            todayPlan model

        words =
            List.length today.words

        due =
            List.length today.due

        fresh =
            List.length today.new

        minutes =
            max 1 (round (toFloat words * 0.3 + toFloat (due + fresh) * 2.5))

        parts =
            List.filterMap identity
                [ if words > 0 then
                    Just (counted words "word" "words" ++ " to review")

                  else
                    Nothing
                , if due > 0 then
                    Just (counted due "passage" "passages" ++ " to review")

                  else
                    Nothing
                , if fresh > 0 then
                    Just (counted fresh "new passage" "new passages")

                  else
                    Nothing
                ]

        continue =
            (case model.todayScope of
                Just work ->
                    Just work

                Nothing ->
                    lastWork model
            )
                |> Maybe.andThen (entryFor model)
                |> Maybe.map (\entry -> ( entry, savedRef entry model ))
    in
    section [ class "today-panel", attribute "aria-label" "Today" ]
        [ viewTodayHead model
        , if List.isEmpty parts then
            h1 [ class "today-title" ] [ text "All caught up" ]

          else
            h1 [ class "today-title" ] [ text (String.join " · " parts) ]
        , if List.isEmpty parts then
            viewUpcoming model Today.Everything

          else
            p [ class "today-summary" ] [ text ("About " ++ counted minutes "minute" "minutes" ++ ". Reviews come first, then new passages.") ]
        , if List.isEmpty parts then
            if moreToLearn { model | queueMode = False, todayMode = Nothing } then
                div [ class "today-actions" ] [ learnMoreButton model True ]

            else
                text ""

          else
            div [ class "today-actions" ]
                [ button [ class "primary-button", type_ "button", onClick (StartToday Today.Everything) ] [ text "Start →" ]
                , button [ class "secondary-button", type_ "button", onClick (StartToday Today.WordsOnly), disabled (words == 0) ] [ text ("Words only · " ++ String.fromInt words) ]
                , button [ class "secondary-button", type_ "button", onClick (StartToday Today.PassagesOnly), disabled (due + fresh == 0) ] [ text ("Passages only · " ++ String.fromInt (due + fresh)) ]
                ]
        , case continue of
            Just ( entry, ref ) ->
                p [ class "today-continue" ]
                    [ text "Continue where you left off: "
                    , a [ href (Route.toPath (Route.Study entry.id ref)) ] [ text (passageName model entry.id ref ++ " →") ]
                    ]

            Nothing ->
                text ""
        ]


{-| "Today", and which works to study: all, or one at a time.
-}
viewTodayHead : Model -> Html Msg
viewTodayHead model =
    div [ class "today-head" ]
        [ p [ class "eyebrow" ] [ text "Today" ]
        , label [ class "today-scope" ]
            [ span [] [ text "Studying" ]
            , select [ onInput SetTodayScope, attribute "aria-label" "Works to study" ]
                (option [ value "", selected (model.todayScope == Nothing) ] [ text "All works" ]
                    :: List.map (\entry -> option [ value entry.id, selected (model.todayScope == Just entry.id) ] [ text entry.title ]) (workingOn model)
                )
            ]
        ]


{-| What comes back later today in this mode, with a way to take it now.
-}
viewUpcoming : Model -> Today.Mode -> Html Msg
viewUpcoming model mode =
    case Today.upcoming model.clock mode model.todayScope model.reviews model.wordCards of
        Just ( item, due ) ->
            p [ class "today-summary" ]
                [ text ("Next: " ++ itemName model item ++ " comes back in " ++ Review.intervalLabel model.clock due ++ ". ")
                , button [ class "text-button", type_ "button", onClick (GoTo (itemPath mode item)) ] [ text "Review it now" ]
                ]

        Nothing ->
            p [ class "today-summary" ] [ text "Nothing else is due today." ]


{-| Today's session page: where the session ends when nothing is due, with what returns next.
-}
viewTodayPage : Model -> Html Msg
viewTodayPage model =
    let
        mode =
            Maybe.withDefault Today.Everything model.todayMode

        dayStart =
            Review.startOfDay model.clock

        graded =
            List.filter (\attempt -> attempt.finishedAt >= dayStart) model.attempts

        wordReviews =
            List.filter (\review -> review.at >= dayStart) model.wordReviews

        judged =
            List.concatMap .items graded |> List.filter (\item -> item.mark /= Nothing)

        right =
            List.length (List.filter (\item -> item.mark == Just True) judged)
    in
    main_ [ class "page today-page" ]
        [ section [ class "today-panel" ]
            (viewTodayHead model
                :: (case Today.next mode (todayPlan model) of
                        Just _ ->
                            [ h1 [ class "today-title" ] [ text "More is ready" ]
                            , div [ class "today-actions" ] [ button [ class "primary-button", type_ "button", onClick (StartToday mode) ] [ text "Continue →" ] ]
                            ]

                        Nothing ->
                            [ h1 [ class "today-title" ] [ text "Done for now" ]
                            , viewUpcoming model mode
                            , if mode /= Today.WordsOnly && moreToLearn model then
                                div [ class "today-actions" ] [ learnMoreButton model True ]

                              else
                                text ""
                            ]
                   )
                ++ [ p [ class "today-summary" ]
                        [ text
                            ("Today so far: "
                                ++ counted (List.length graded) "passage" "passages"
                                ++ " graded, "
                                ++ counted (List.length wordReviews) "word review" "word reviews"
                                ++ (if List.isEmpty judged then
                                        "."

                                    else
                                        ", " ++ String.fromInt (right * 100 // List.length judged) ++ "% of answers right."
                                   )
                            )
                        ]
                   , p [ class "today-continue" ]
                        [ a [ href (Route.toPath Route.Library) ] [ text "Home" ]
                        , text " · "
                        , a [ href (Route.toPath Route.Stats) ] [ text "Progress" ]
                        ]
                   ]
            )
        ]


{-| Continues the session with more new passages than today's limit; reviews still come back when due.
-}
learnMoreButton : Model -> Bool -> Html Msg
learnMoreButton model primary =
    button
        [ class
            (if primary then
                "primary-button"

             else
                "secondary-button"
            )
        , type_ "button"
        , onClick LearnMore
        ]
        [ text ("Learn " ++ String.fromInt (learnMoreStep model) ++ " more →") ]


{-| In today's session: how much is left.
-}
viewSessionStatus : Model -> Html Msg
viewSessionStatus model =
    case model.todayMode of
        Just _ ->
            let
                today =
                    todayPlan model
            in
            p [ class "session-status" ]
                [ text
                    ("Today · "
                        ++ (model.todayScope |> Maybe.map (\work -> workName model work ++ " · ") |> Maybe.withDefault "")
                        ++ counted (List.length today.words) "word" "words"
                        ++ " · "
                        ++ counted (List.length today.due + List.length today.new) "passage" "passages"
                        ++ " left"
                    )
                ]

        Nothing ->
            text ""


{-| The passage text with the first word equal to `form` highlighted.
-}
viewHighlighted : String -> String -> Html Msg
viewHighlighted passage form =
    let
        bare piece =
            String.filter (\char -> not (String.contains (String.fromChar char) ".,;:!?··;()[]«»“”‘’—–'\"")) piece
    in
    p [ class "word-context", attribute "lang" "grc" ]
        (String.split " " passage
            |> List.foldl
                (\piece ( html, done ) ->
                    if not done && bare piece == form then
                        ( html ++ [ span [ class "context-word" ] [ text piece ], text " " ], True )

                    else
                        ( html ++ [ text (piece ++ " ") ], done )
                )
                ( [], False )
            |> Tuple.first
        )



-- WORDS


{-| Recall one word's meaning in the passage where it was last missed (or last seen), then rate it.
-}
viewWordReview : Model -> String -> Html Msg
viewWordReview model lemma =
    case Dict.get lemma model.wordCards of
        Nothing ->
            main_ [ class "page word-review-page" ]
                [ p [ class "muted" ] [ text "No review card yet: words get one when a passage trips you up on them." ]
                , a [ href (Route.toPath (Route.Word lemma)) ] [ text "Word page →" ]
                ]

        Just word ->
            let
                context =
                    reviewContext model word

                answer =
                    model.wordAnswer

                outcomes =
                    Review.scheduler |> Maybe.andThen (\fsrs -> Fsrs.preview fsrs model.clock word.card |> Result.toMaybe)

                ratingButton rating label pick =
                    button [ class "rating-button", type_ "button", onClick (RateWord rating) ]
                        [ strongText label
                        , span [ class "rating-interval" ]
                            [ text (outcomes |> Maybe.map (\all -> Review.intervalLabel model.clock (pick all).card.due) |> Maybe.withDefault "") ]
                        ]
            in
            main_ [ class "page word-review-page" ]
                [ viewSessionStatus model
                , section [ class "word-review-card" ]
                    [ p [ class "eyebrow" ] [ text ("Word · " ++ passageName model context.work context.passage) ]
                    , viewHighlighted context.text context.form
                    , div [ class "word-review-form", attribute "lang" "grc" ]
                        [ span [ class "review-form" ] [ text context.form ]
                        , span [ class "review-lemma" ] [ text (displayLemma lemma) ]
                        ]
                    , input
                        [ class "gloss-input word-review-input"
                        , value answer.guess
                        , onInput WordGuess
                        , placeholder "What does it mean here?"
                        , attribute "aria-label" ("Meaning of " ++ context.form)
                        ]
                        []
                    , if answer.revealed then
                        div [ class "word-review-answer" ]
                            [ p [ class "reference-answer" ] [ text (displayGloss context.gloss) ]
                            , p [ class "muted" ]
                                [ text
                                    ("Reviewed "
                                        ++ counted word.seen "time" "times"
                                        ++ ", missed "
                                        ++ String.fromInt word.misses
                                        ++ "."
                                        ++ (if String.isEmpty (String.trim context.guess) then
                                                ""

                                            else
                                                " Your answer there: " ++ context.guess
                                           )
                                    )
                                ]
                            , div [ class "rating-buttons" ]
                                [ ratingButton Fsrs.Again "Again" .again
                                , ratingButton Fsrs.Hard "Hard" .hard
                                , ratingButton Fsrs.Good "Good" .good
                                , ratingButton Fsrs.Easy "Easy" .easy
                                ]
                            ]

                      else
                        button [ class "primary-button", type_ "button", onClick RevealWord ] [ text "Show answer" ]
                    , p [ class "today-continue" ]
                        [ a [ href (Route.toPath (Route.Word lemma)) ] [ text "Word page →" ]
                        , text " · "
                        , a [ href (Route.toPath (Route.Study context.work context.passage)) ] [ text "Open the passage →" ]
                        ]
                    ]
                ]


{-| A lemma: the learner's record with it, the passages where they miss it, and every place it occurs.
-}
viewWordPage : Model -> String -> Html Msg
viewWordPage model lemma =
    let
        word =
            Dict.get lemma model.wordCards

        -- Each passage where the learner met this lemma: misses, times seen, wrong answers, text.
        met =
            model.attempts
                |> List.concatMap
                    (\attempt ->
                        attempt.items
                            |> List.filter (\item -> item.kind == Study.WordItem && item.lemma == lemma && item.mark /= Nothing)
                            |> List.map (\item -> ( ( attempt.work, attempt.passage ), ( item, attempt.sentenceText ) ))
                    )
                |> List.foldl
                    (\( key, ( item, passageText ) ) found ->
                        Dict.update key
                            (\current ->
                                let
                                    prior =
                                        Maybe.withDefault { misses = 0, seen = 0, wrong = [], text = passageText, form = item.form } current

                                    missed =
                                        item.mark == Just False
                                in
                                Just
                                    { prior
                                        | misses =
                                            if missed then
                                                prior.misses + 1

                                            else
                                                prior.misses
                                        , seen = prior.seen + 1
                                        , wrong =
                                            if missed && not (String.isEmpty (String.trim item.guess)) && not (List.member item.guess prior.wrong) then
                                                prior.wrong ++ [ item.guess ]

                                            else
                                                prior.wrong
                                    }
                            )
                            found
                    )
                    Dict.empty
                |> Dict.toList
                |> List.filter (\( _, record ) -> record.misses > 0)
                |> List.sortBy (\( _, record ) -> negate record.misses)
    in
    main_ [ class "page word-page" ]
        [ section [ class "word-header" ]
            [ p [ class "eyebrow" ] [ text "Word" ]
            , h1 [ attribute "lang" "grc" ] [ text (displayLemma lemma) ]
            , case word of
                Just known ->
                    div []
                        [ p [ class "today-summary" ]
                            [ text
                                ("Reviewed "
                                    ++ counted known.seen "time" "times"
                                    ++ ", missed "
                                    ++ String.fromInt known.misses
                                    ++ ". "
                                    ++ (if known.card.due <= model.clock then
                                            "Due for review now."

                                        else
                                            "Next review in " ++ Review.intervalLabel model.clock known.card.due ++ "."
                                       )
                                )
                            ]
                        , p [ class "muted", attribute "lang" "grc" ] [ text ("Forms you've met: " ++ String.join ", " known.forms) ]
                        , div [ class "today-actions" ]
                            [ a [ class "primary-button", href (Route.toPath (Route.WordReview lemma)) ] [ text "Review now →" ] ]
                        ]

                Nothing ->
                    p [ class "muted" ] [ text "No review card yet: words get one when a passage trips you up on them." ]
            ]
        , if List.isEmpty met then
            text ""

          else
            section [ class "word-section" ]
                [ h2 [] [ text "Where you struggle" ]
                , ul [ class "word-occurrences" ]
                    (List.map
                        (\( ( work, passage ), record ) ->
                            li []
                                [ a [ href (Route.toPath (Route.Study work passage)) ] [ text (passageName model work passage) ]
                                , span [ class "muted" ]
                                    [ text
                                        (" · missed "
                                            ++ String.fromInt record.misses
                                            ++ " of "
                                            ++ String.fromInt record.seen
                                            ++ (if List.isEmpty record.wrong then
                                                    ""

                                                else
                                                    " · you answered " ++ String.join ", " record.wrong
                                               )
                                        )
                                    ]
                                , viewHighlighted record.text record.form
                                ]
                        )
                        met
                    )
                ]
        , section [ class "word-section" ]
            (case model.lemmaIndex of
                IndexLoaded data ->
                    let
                        everywhere =
                            Dict.get lemma data.lemmas |> Maybe.withDefault []

                        shown =
                            List.take 120 everywhere
                    in
                    [ h2 [] [ text ("Every occurrence · " ++ String.fromInt (List.length everywhere)) ]
                    , ul [ class "word-occurrences" ]
                        (List.map
                            (\occurrence ->
                                li []
                                    [ a [ href (Route.toPath (Route.Study occurrence.work occurrence.ref)) ] [ text (passageName model occurrence.work occurrence.ref) ]
                                    , span [ class "muted" ] [ text (" · " ++ displayGloss occurrence.gloss) ]
                                    , Dict.get occurrence.work data.passages
                                        |> Maybe.andThen (Dict.get occurrence.ref)
                                        |> Maybe.map (\passage -> viewHighlighted passage occurrence.form)
                                        |> Maybe.withDefault (text "")
                                    ]
                            )
                            shown
                        )
                    , if List.length everywhere > List.length shown then
                        p [ class "muted" ] [ text ("And " ++ String.fromInt (List.length everywhere - List.length shown) ++ " more.") ]

                      else
                        text ""
                    ]

                IndexFailed ->
                    [ p [ class "muted" ] [ text "Couldn't load where this word occurs." ] ]

                _ ->
                    [ p [ class "muted" ] [ text "Finding every occurrence…" ] ]
            )
        ]



-- PROGRESS


{-| Progress over time, from the attempts, word reviews, and cards on this device.
-}
viewStats : Model -> Html Msg
viewStats model =
    let
        now =
            model.clock

        today =
            Review.startOfDay now

        days =
            List.map (\back -> today - back * 86400000) (List.range 0 29 |> List.reverse)

        perDay times =
            let
                counts =
                    List.foldl (\time found -> Dict.update (Review.startOfDay time) (Maybe.map ((+) 1) >> Maybe.withDefault 1 >> Just) found) Dict.empty times
            in
            List.map (\day -> ( day, Dict.get day counts |> Maybe.withDefault 0 )) days

        reviewTimes =
            List.map .finishedAt model.attempts ++ List.map .at model.wordReviews

        words =
            Dict.values model.wordCards

        known =
            List.length (List.filter Words.isMature words)

        weekAgo =
            today - 6 * 86400000

        recentJudged =
            model.attempts
                |> List.filter (\attempt -> attempt.finishedAt >= weekAgo)
                |> List.concatMap .items
                |> List.filter (\item -> item.kind == Study.WordItem && item.mark /= Nothing)

        recentReviews =
            List.filter (\review -> review.at >= weekAgo) model.wordReviews

        recentRight =
            List.length (List.filter (\item -> item.mark == Just True) recentJudged)
                + List.length (List.filter (\review -> review.rating /= Fsrs.Again) recentReviews)

        recentTotal =
            List.length recentJudged + List.length recentReviews

        activeDays =
            List.map Review.startOfDay reviewTimes |> Set.fromList

        streak =
            let
                count day found =
                    if Set.member day activeDays then
                        count (day - 86400000) (found + 1)

                    else
                        found
            in
            -- Today still counts as a streak day until it ends.
            if Set.member today activeDays then
                count today 0

            else
                count (today - 86400000) 0

        missedWords =
            words
                |> List.filter (\word -> word.misses > 0)
                |> List.sortBy (\word -> ( negate word.misses, word.lemma ))
                |> List.take 15

        -- Passages by how many of their answers have been marked wrong, across all attempts.
        hardPassages =
            model.attempts
                |> List.foldl
                    (\attempt found ->
                        Dict.update ( attempt.work, attempt.passage )
                            (\current ->
                                let
                                    ( wrong, attempts ) =
                                        Maybe.withDefault ( 0, 0 ) current
                                in
                                Just ( wrong + List.length (Study.missed attempt), attempts + 1 )
                            )
                            found
                    )
                    Dict.empty
                |> Dict.toList
                |> List.filter (\( _, ( wrong, _ ) ) -> wrong > 0)
                |> List.sortBy (\( _, ( wrong, _ ) ) -> negate wrong)
                |> List.take 10

        studiedIn work =
            model.reviews |> Dict.values |> List.filter (\entry -> entry.work == work) |> List.length
    in
    main_ [ class "page stats-page" ]
        [ section [ class "word-header" ]
            [ p [ class "eyebrow" ] [ text "Progress" ]
            , h1 [] [ text "Your progress" ]
            ]
        , viewAccountPanel model
        , div [ class "stat-tiles" ]
            [ viewStatTile "Words known" (String.fromInt known) "Trouble words now three weeks or more apart"
            , viewStatTile "Words learning" (String.fromInt (List.length words - known)) "Missed in a passage, still being drilled"
            , viewStatTile "Passages studied" (String.fromInt (Dict.size model.reviews)) ("of " ++ String.fromInt (List.sum (List.map (.passages >> List.length) model.library)))
            , viewStatTile "Streak" (counted streak "day" "days") "Days in a row with a review"
            , viewStatTile "Right, last 7 days"
                (if recentTotal == 0 then
                    "—"

                 else
                    String.fromInt (recentRight * 100 // recentTotal) ++ "%"
                )
                (counted recentTotal "word answer" "word answers")
            ]
        , div [ class "chart-grid" ]
            [ viewColumnChart model "Reviews per day" "Passages graded and word reviews, last 30 days" (perDay reviewTimes)
            , viewColumnChart model "New trouble words per day" "Words first missed in a passage" (perDay (List.map .introducedAt words))
            , viewColumnChart model "New passages per day" "Passages studied for the first time" (perDay (List.map .introducedAt (Dict.values model.reviews)))
            ]
        , section [ class "word-section" ]
            [ h2 [] [ text "By work" ]
            , div [ class "work-progress" ]
                (List.map
                    (\entry ->
                        let
                            total =
                                List.length entry.passages

                            studied =
                                studiedIn entry.id
                        in
                        div [ class "work-progress-row" ]
                            [ span [ class "work-progress-title" ] [ text entry.title ]
                            , span [ class "progress-track", attribute "role" "img", attribute "aria-label" (String.fromInt studied ++ " of " ++ String.fromInt total ++ " passages studied") ]
                                [ span [ class "progress-fill", style "width" (String.fromFloat (100 * toFloat studied / toFloat (max 1 total)) ++ "%") ] [] ]
                            , span [ class "work-progress-count" ] [ text (String.fromInt studied ++ " / " ++ String.fromInt total) ]
                            ]
                    )
                    model.library
                )
            ]
        , div [ class "stats-columns" ]
            [ section [ class "word-section" ]
                [ h2 [] [ text "Most-missed words" ]
                , if List.isEmpty missedWords then
                    p [ class "muted" ] [ text "No missed words yet." ]

                  else
                    table [ class "stats-table" ]
                        [ thead [] [ tr [] [ th [] [ text "Word" ], th [] [ text "Missed" ], th [] [ text "Next review" ] ] ]
                        , tbody []
                            (List.map
                                (\word ->
                                    tr []
                                        [ td [ attribute "lang" "grc" ] [ a [ href (Route.toPath (Route.Word word.lemma)) ] [ text (displayLemma word.lemma) ] ]
                                        , td [] [ text (String.fromInt word.misses ++ " of " ++ String.fromInt word.seen) ]
                                        , td []
                                            [ text
                                                (if word.card.due <= now then
                                                    "now"

                                                 else
                                                    "in " ++ Review.intervalLabel now word.card.due
                                                )
                                            ]
                                        ]
                                )
                                missedWords
                            )
                        ]
                ]
            , section [ class "word-section" ]
                [ h2 [] [ text "Hardest passages" ]
                , if List.isEmpty hardPassages then
                    p [ class "muted" ] [ text "No missed answers yet." ]

                  else
                    table [ class "stats-table" ]
                        [ thead [] [ tr [] [ th [] [ text "Passage" ], th [] [ text "Wrong answers" ], th [] [ text "Attempts" ] ] ]
                        , tbody []
                            (List.map
                                (\( ( work, passage ), ( wrong, attempts ) ) ->
                                    tr []
                                        [ td [] [ a [ href (Route.toPath (Route.Study work passage)) ] [ text (passageName model work passage) ] ]
                                        , td [] [ text (String.fromInt wrong) ]
                                        , td [] [ text (String.fromInt attempts) ]
                                        ]
                                )
                                hardPassages
                            )
                        ]
                ]
            ]
        ]


viewStatTile : String -> String -> String -> Html Msg
viewStatTile label value note =
    div [ class "stat-tile" ]
        [ span [ class "stat-tile-label" ] [ text label ]
        , span [ class "stat-tile-value" ] [ text value ]
        , span [ class "stat-tile-note" ] [ text note ]
        ]


{-| One series of daily counts as columns: a single hue, so no legend; the busiest day is labelled, every day has a
tooltip, and a table view carries the values.
-}
viewColumnChart : Model -> String -> String -> List ( Int, Int ) -> Html Msg
viewColumnChart model title subtitle points =
    let
        peak =
            List.maximum (List.map Tuple.second points) |> Maybe.withDefault 0

        scale =
            max 1 peak

        total =
            List.sum (List.map Tuple.second points)

        peakDay =
            points |> List.filter (\( _, value ) -> value == peak && peak > 0) |> List.reverse |> List.head |> Maybe.map Tuple.first

        dateOf day =
            shortDate Time.utc day
    in
    section [ class "column-chart" ]
        [ h3 [ class "chart-title" ] [ text title ]
        , p [ class "chart-subtitle" ] [ text (subtitle ++ " · " ++ String.fromInt total ++ " in all") ]
        , div [ class "chart-plot", attribute "role" "img", attribute "aria-label" (title ++ ": " ++ String.fromInt total ++ " over 30 days, most on one day " ++ String.fromInt peak) ]
            [ span [ class "chart-tick" ] [ text (String.fromInt peak) ]
            , div [ class "chart-columns" ]
                (List.map
                    (\( day, value ) ->
                        div [ class "chart-slot", attribute "data-tip" (dateOf day ++ ": " ++ String.fromInt value), attribute "tabindex" "0" ]
                            [ if Just day == peakDay then
                                span [ class "chart-peak" ] [ text (String.fromInt value) ]

                              else
                                text ""
                            , div [ class "chart-column", style "height" (String.fromFloat (100 * toFloat value / toFloat scale) ++ "%") ] []
                            ]
                    )
                    points
                )
            ]
        , div [ class "chart-axis" ]
            [ span [] [ text (List.head points |> Maybe.map (Tuple.first >> dateOf) |> Maybe.withDefault "") ]
            , span [] [ text "Today" ]
            ]
        , details [ class "chart-table" ]
            [ summary [] [ text "Show as table" ]
            , table [ class "stats-table" ]
                [ thead [] [ tr [] [ th [] [ text "Day" ], th [] [ text "Count" ] ] ]
                , tbody [] (List.map (\( day, value ) -> tr [] [ td [] [ text (dateOf day) ], td [] [ text (String.fromInt value) ] ]) (List.reverse points))
                ]
            ]
        ]


shortDate : Time.Zone -> Int -> String
shortDate zone millis =
    let
        posix =
            Time.millisToPosix millis

        month =
            case Time.toMonth zone posix of
                Time.Jan ->
                    "Jan"

                Time.Feb ->
                    "Feb"

                Time.Mar ->
                    "Mar"

                Time.Apr ->
                    "Apr"

                Time.May ->
                    "May"

                Time.Jun ->
                    "Jun"

                Time.Jul ->
                    "Jul"

                Time.Aug ->
                    "Aug"

                Time.Sep ->
                    "Sep"

                Time.Oct ->
                    "Oct"

                Time.Nov ->
                    "Nov"

                Time.Dec ->
                    "Dec"
    in
    month ++ " " ++ String.fromInt (Time.toDay zone posix)


corpusCoverage : Corpus -> Coverage
corpusCoverage corpus =
    let
        tokens =
            List.concatMap .tokens corpus.sentences

        countSentences predicate =
            List.length (List.filter predicate corpus.sentences)
    in
    { tokens = List.length tokens
    , glossed = List.length (List.filter (\token -> not (String.isEmpty token.gloss)) tokens)
    , morphology = List.length (List.filter (\token -> not (String.isEmpty token.morphology.summary)) tokens)
    , sentences = List.length corpus.sentences
    , dependencies = countSentences (\sentence -> List.any (\token -> token.head == 0) sentence.tokens)
    , literal = countSentences (\sentence -> not (String.isEmpty sentence.literalTranslation))
    , prose = countSentences (\sentence -> not (String.isEmpty sentence.proseTranslation))
    }


fraction : Int -> Int -> String
fraction part whole =
    String.fromInt part ++ "/" ++ String.fromInt whole


plural : Int -> String -> String -> String
plural count singular pluralForm =
    if count == 1 then
        singular

    else
        pluralForm


activeSources : Model -> Html Msg
activeSources model =
    Sources.view (Maybe.andThen .citation model.activeEntry)


workTitle : Model -> String
workTitle model =
    model.activeEntry
        |> Maybe.map .title
        |> Maybe.withDefault model.corpus.source.name


viewPresetCard : Preset -> Preset -> String -> String -> String -> Html Msg
viewPresetCard current target title description budget =
    button
        [ classList [ ( "preset-card", True ), ( "is-selected", current == target ) ]
        , type_ "button"
        , onClick (SelectPreset target)
        , attribute "aria-pressed" (boolString (current == target))
        ]
        [ span [ class "preset-check", attribute "aria-hidden" "true" ]
            [ text
                (if current == target then
                    "✓"

                 else
                    ""
                )
            ]
        , span [ class "preset-title" ] [ text title ]
        , span [ class "preset-description" ] [ text description ]
        , span [ class "preset-budget" ] [ text budget ]
        ]


viewModuleSetting : Model -> ModuleId -> String -> String -> String -> String -> Html Msg
viewModuleSetting model moduleId title description coverage provenance =
    let
        mode =
            moduleMode moduleId model.settings

        enabled =
            mode /= ModuleOff
    in
    div [ classList [ ( "module-row", True ), ( "is-enabled", enabled ) ] ]
        [ div [ class "module-toggle-wrap" ]
            [ input
                [ type_ "checkbox"
                , checked enabled
                , onClick (ToggleModule moduleId)
                , attribute "aria-label" ("Enable " ++ title)
                ]
                []
            ]
        , div [ class "module-copy" ]
            [ div [ class "module-title-line" ]
                [ h3 [] [ text title ]
                , span [ class "coverage-badge" ] [ text coverage ]
                ]
            , p [] [ text description ]
            , span [ class "provenance" ] [ text provenance ]
            ]
        ]


strongText : String -> Html msg
strongText content =
    Html.strong [] [ text content ]


currentSentence : Model -> Sentence
currentSentence model =
    getAt model.sentenceIndex model.corpus.sentences
        |> Maybe.withDefault fallbackSentence


fallbackSentence : Sentence
fallbackSentence =
    fallbackCorpus.sentences
        |> List.head
        |> Maybe.withDefault
            { id = "missing"
            , chapter = 1
            , verse = "1.1.1"
            , text = "No corpus loaded."
            , literalTranslation = ""
            , proseTranslation = ""
            , tokens = []
            , placeholders = []
            }


sentenceReference : Sentence -> String
sentenceReference sentence =
    sentence.verse


getAt : Int -> List a -> Maybe a
getAt index items =
    if index < 0 then
        Nothing

    else
        items |> List.drop index |> List.head


presetLabel : Preset -> String
presetLabel preset =
    case preset of
        ReadPreset ->
            "Read"

        AssistedPreset ->
            "Assisted"

        IntensivePreset ->
            "Intensive"

        CustomPreset ->
            "Custom"


themeActionLabel : Theme -> String
themeActionLabel theme =
    case theme of
        DarkTheme ->
            "Use light theme"

        LightTheme ->
            "Use dark theme"


boolString : Bool -> String
boolString value =
    if value then
        "true"

    else
        "false"


view : Model -> Html Msg
view model =
    div
        [ classList
            [ ( "app-shell", True )
            , ( "dark-theme", model.theme == DarkTheme )
            , ( "light-theme", model.theme == LightTheme )
            , ( "is-reading", model.screen == ReaderScreen )
            ]
        ]
        [ if model.screen == ReaderScreen then
            text ""

          else
            viewAppHeader model
        , case model.notice of
            Just notice ->
                div [ class "notice", attribute "role" "status" ]
                    [ span [] [ text notice ]
                    , button [ type_ "button", onClick DismissNotice, attribute "aria-label" "Dismiss message" ] [ text "×" ]
                    ]

            Nothing ->
                text ""
        , case model.screen of
            LibraryScreen ->
                viewLibrary model

            WorkspaceScreen ->
                viewWorkspace model

            SettingsScreen ->
                viewSettings model

            ReaderScreen ->
                viewReader model

            TodayScreen ->
                viewTodayPage model

            WordScreen lemma ->
                viewWordPage model lemma

            WordReviewScreen lemma ->
                viewWordReview model lemma

            StatsScreen ->
                viewStats model

            WhatsNewScreen ->
                viewWhatsNew model.changelog
        ]


{-| CHANGELOG.md, fetched when the page is first opened (the release build copies it next to index.html).
-}
type ChangelogState
    = ChangelogNotLoaded
    | ChangelogLoading
    | ChangelogLoaded (List Changelog.Version)
    | ChangelogFailed


viewWhatsNew : ChangelogState -> Html Msg
viewWhatsNew state =
    section [ class "whats-new" ]
        (h1 [] [ text "What's new" ]
            :: (case state of
                    ChangelogLoaded versions ->
                        p [ class "whats-new-intro" ] [ text "New texts, features and fixes in Lyceum Study, newest first." ]
                            :: List.map viewChangelogVersion versions

                    ChangelogFailed ->
                        [ p [] [ text "The list of changes couldn't be loaded. Check your connection and open this page again." ] ]

                    _ ->
                        [ p [] [ text "Loading…" ] ]
               )
        )


viewChangelogVersion : Changelog.Version -> Html Msg
viewChangelogVersion version =
    article [ class "whats-new-version" ]
        (h2 []
            [ text
                (if version.name == "Unreleased" then
                    "Not yet released"

                 else
                    version.name
                )
            ]
            :: List.concatMap
                (\sec ->
                    (if sec.title == "" then
                        []

                     else
                        [ h3 [] [ text sec.title ] ]
                    )
                        ++ [ ul [] (List.map (\item -> li [] [ text item ]) sec.items) ]
                )
                version.sections
        )


viewSettings : Model -> Html Msg
viewSettings model =
    let
        coverage =
            corpusCoverage model.corpus

        provenance =
            model.corpus.source.name
    in
    main_ [ class "page settings-page" ]
        [ section [ class "settings-intro compact-intro" ]
            [ div []
                [ p [ class "eyebrow" ] [ text (workTitle model) ]
                , h1 [] [ text "Study tools" ]
                ]
            , button [ class "primary-button open-workspace-button", type_ "button", onClick ShowWorkspace ] [ text "Back to study →" ]
            ]
        , section [ class "setting-block" ]
            [ div [ class "preset-grid" ]
                [ viewPresetCard model.preset ReadPreset "Read" "Glosses only, one word at a time." "≈ 4 min / passage"
                , viewPresetCard model.preset AssistedPreset "Assisted" "Glosses and a prose translation." "≈ 8 min / passage"
                , viewPresetCard model.preset IntensivePreset "Intensive" "Glosses and both translations." "≈ 12 min / passage"
                , viewPresetCard model.preset CustomPreset "Custom" "Your own choice of tools." "Variable"
                ]
            ]
        , section [ class "module-settings" ]
            [ viewModuleSetting model GlossModule "Glosses" "Gloss words one at a time from the word popup, then compare with the imported gloss." (String.fromInt coverage.glossed ++ " of " ++ String.fromInt coverage.tokens ++ " words") (provenance ++ " · imported")
            , viewModuleSetting model LiteralModule "Literal translation" "Expose the structure in your own words, then compare." (String.fromInt coverage.literal ++ " of " ++ String.fromInt coverage.sentences ++ " sentences") (provenance ++ " · aligned reference")
            , viewModuleSetting model ProseModule "Prose translation" "State the meaning naturally, then compare." (String.fromInt coverage.prose ++ " of " ++ String.fromInt coverage.sentences ++ " sentences") (provenance ++ " · aligned reference")
            ]
        , viewProgress model
        ]


viewProgress : Model -> Html Msg
viewProgress model =
    let
        summary =
            Study.stats model.attempts
    in
    section [ class "progress-settings" ]
        [ label [ class "new-per-day" ]
            [ span [] [ text "New passages per day" ]
            , select [ onInput SetNewPerDay ]
                (List.map
                    (\count -> option [ value (String.fromInt count), selected (count == model.newPerDay) ] [ text (String.fromInt count) ])
                    [ 3, 5, 10, 15, 20, 30 ]
                )
            , span [ class "muted" ] [ text "Reviews that are due are never capped." ]
            ]
        , div [ class "progress-heading" ]
            [ h2 [] [ text "Your progress" ]
            , span [ class "muted" ] [ text "Saved only in this browser." ]
            ]
        , div [ class "progress-stats" ]
            [ viewStat (String.fromInt summary.attempts) "graded attempts"
            , viewStat (String.fromInt summary.judged) "answers marked"
            , viewStat (percent summary.right summary.judged) "marked right"
            , viewStat (percent summary.unassistedRight summary.unassistedJudged) "right without reveals"
            ]
        , if List.isEmpty summary.struggles then
            p [ class "muted" ] [ text "Words you mark wrong will be listed here." ]

          else
            div [ class "struggles" ]
                [ h3 [] [ text "Words you miss most" ]
                , div [ class "struggle-list", attribute "lang" "grc" ]
                    (List.map
                        (\stat ->
                            span [ class "struggle" ]
                                [ text stat.lemma
                                , span [ class "struggle-count", attribute "lang" "en" ] [ text (String.fromInt stat.wrong ++ " / " ++ String.fromInt stat.judged ++ " wrong") ]
                                ]
                        )
                        summary.struggles
                    )
                ]
        , div [ class "clear-data" ]
            (if model.confirmClear then
                [ span []
                    [ text
                        (if syncsProgress model then
                            "Delete the attempts, drafts, and reading positions saved in this browser? Your synced progress stays in your Lyceum account and comes back on the next sync."

                         else
                            "Delete all attempts, drafts, and reading positions saved in this browser?"
                        )
                    ]
                , button [ class "danger-button", type_ "button", onClick ConfirmClearSavedData ] [ text "Delete saved data" ]
                , button [ class "secondary-button", type_ "button", onClick CancelClearSavedData ] [ text "Cancel" ]
                ]

             else
                [ button [ class "secondary-button", type_ "button", onClick ClearSavedData ] [ text "Clear saved data…" ] ]
            )
        ]


viewStat : String -> String -> Html Msg
viewStat value label =
    div [ class "progress-stat" ]
        [ span [ class "progress-value" ] [ text value ]
        , span [ class "muted" ] [ text label ]
        ]


percent : Int -> Int -> String
percent part whole =
    if whole == 0 then
        "—"

    else
        String.fromInt (round (toFloat part * 100 / toFloat whole)) ++ "%"


viewWorkspace : Model -> Html Msg
viewWorkspace model =
    let
        total =
            List.length model.corpus.sentences

        showTool =
            not model.study.submitted && not model.historyOpen && model.activeModule /= Nothing
    in
    main_ [ class "workspace-page" ]
        [ div [ class "work-context-bar" ]
            [ div [ class "context-title" ]
                [ button [ class "icon-button", type_ "button", onClick ShowLibrary, attribute "aria-label" "Back to library" ] [ text "←" ]
                , div [] [ span [ class "context-work" ] [ text (workTitle model) ] ]
                ]
            , viewQueueStatus model
            , div [ class "context-actions" ]
                [ div [ class "passage-nav" ]
                    [ button [ class "icon-button", type_ "button", onClick PreviousSentence, disabled (model.sentenceIndex == 0), attribute "aria-label" "Previous passage (← or k)" ] [ text "‹" ]
                    , viewCitationPicker model
                    , button [ class "icon-button", type_ "button", onClick NextSentence, disabled (model.sentenceIndex >= total - 1), attribute "aria-label" "Next passage (→ or j)" ] [ text "›" ]
                    ]
                ]
            ]
        , div [ classList [ ( "workspace-grid", True ), ( "has-workbench", showTool ) ] ]
            [ if model.queueDone then
                viewQueueDone model

              else if model.workFinished then
                viewWorkFinished model

              else if model.historyOpen then
                viewHistory model

              else if model.study.submitted then
                viewGrading model

              else
                viewStudyStage model
            , if showTool then
                viewToolPanel model

              else
                text ""
            ]
        , if model.queueDone || model.workFinished then
            text ""

          else
            viewStudyFooter model
        ]


currentAttempts : Model -> List Study.Attempt
currentAttempts model =
    case model.activeEntry of
        Just entry ->
            Study.passageAttempts entry.id (currentRef model) model.attempts

        Nothing ->
            []


{-| The way into the passage's history; absent until the passage has been graded once.
-}
viewHistoryLink : Model -> Html Msg
viewHistoryLink model =
    let
        count =
            List.length (currentAttempts model)
    in
    if count == 0 then
        text ""

    else
        button [ class "history-link", type_ "button", onClick OpenHistory ]
            [ text (String.fromInt count ++ " past " ++ plural count "attempt" "attempts" ++ " →") ]


{-| Every finished attempt at the passage, newest first, each compared with the one before it.
-}
viewHistory : Model -> Html Msg
viewHistory model =
    let
        attempts =
            currentAttempts model

        olderOf =
            List.drop 1 (List.map Just attempts) ++ [ Nothing ]

        oldestFirst =
            List.reverse attempts

        missedEveryTime =
            if List.length attempts < 2 then
                []

            else
                attempts
                    |> List.head
                    |> Maybe.map Study.missed
                    |> Maybe.withDefault []
                    |> List.filter (\item -> List.all (\attempt -> List.any (\other -> other.key == item.key) (Study.missed attempt)) attempts)
    in
    section [ class "reading-stage history-stage" ]
        [ div [ class "history-heading" ]
            [ div []
                [ p [ class "eyebrow" ] [ text (workTitle model ++ " " ++ currentLabel model) ]
                , h2 [] [ text "Past attempts" ]
                ]
            , button [ class "secondary-button", type_ "button", onClick CloseHistory ] [ text "← Back to current attempt" ]
            ]
        , if List.isEmpty attempts then
            p [ class "muted" ] [ text "No past attempts at this passage yet." ]

          else
            text ""
        , if List.length attempts < 2 then
            text ""

          else
            div [ class "history-trend" ]
                [ p []
                    [ span [ class "muted" ] [ text "Right, oldest to newest: " ]
                    , strongText (oldestFirst |> List.map (Study.tally >> .right >> String.fromInt) |> String.join " → ")
                    ]
                , p []
                    [ span [ class "muted" ] [ text "Wrong, oldest to newest: " ]
                    , strongText (oldestFirst |> List.map (Study.tally >> .wrong >> String.fromInt) |> String.join " → ")
                    ]
                , if List.isEmpty missedEveryTime then
                    text ""

                  else
                    p [] [ span [ class "muted" ] [ text "Missed every time: " ], viewItemChips False missedEveryTime ]
                ]
        , Html.ol [ class "history-list" ] (List.map2 (viewHistoryEntry model) attempts olderOf)
        ]


viewHistoryEntry : Model -> Study.Attempt -> Maybe Study.Attempt -> Html Msg
viewHistoryEntry model attempt older =
    let
        counts =
            Study.tally attempt

        missed =
            Study.missed attempt

        selected =
            model.historyAttempt == Just attempt.finishedAt

        change label now before =
            if now == before then
                Nothing

            else if now > before then
                Just ("+" ++ String.fromInt (now - before) ++ " " ++ label)

            else
                Just ("−" ++ String.fromInt (before - now) ++ " " ++ label)

        missedKeys =
            List.map .key missed
    in
    Html.li [ classList [ ( "history-entry", True ), ( "is-selected", selected ) ] ]
        [ button [ class "history-summary", type_ "button", onClick (SelectHistoryAttempt attempt.finishedAt), attribute "aria-expanded" (boolString selected) ]
            [ span [ class "history-date" ] [ text (formatDate model.zone attempt.finishedAt) ]
            , span [ class "history-counts" ]
                [ span [ class "count-right" ] [ text (String.fromInt counts.right ++ " right") ]
                , span [ class "count-wrong" ] [ text (String.fromInt counts.wrong ++ " wrong") ]
                , if counts.unmarked == 0 then
                    text ""

                  else
                    span [ class "muted" ] [ text (String.fromInt counts.unmarked ++ " unmarked") ]
                ]
            , case older of
                Just previous ->
                    let
                        before =
                            Study.tally previous
                    in
                    span [ class "history-change" ]
                        [ text
                            (case List.filterMap identity [ change "right" counts.right before.right, change "wrong" counts.wrong before.wrong ] of
                                [] ->
                                    "Same as the attempt before"

                                changes ->
                                    String.join ", " changes ++ " since the attempt before"
                            )
                        ]

                Nothing ->
                    span [ class "history-change" ] [ text "First attempt" ]
            ]
        , div [ class "history-missed" ]
            (if List.isEmpty missed then
                [ span [ class "muted" ] [ text "Nothing marked wrong." ] ]

             else
                [ span [ class "muted" ] [ text "Missed: " ], viewItemChips False missed ]
            )
        , case older of
            Just previous ->
                let
                    previousMissed =
                        Study.missed previous

                    newlyMissed =
                        List.filter (\item -> not (List.any (\other -> other.key == item.key) previousMissed)) missed

                    recovered =
                        List.filter (\item -> not (List.member item.key missedKeys)) previousMissed
                in
                div [ class "history-missed" ]
                    [ if List.isEmpty newlyMissed then
                        text ""

                      else
                        span [] [ span [ class "muted" ] [ text "Newly missed: " ], viewItemChips False newlyMissed ]
                    , if List.isEmpty recovered then
                        text ""

                      else
                        span [] [ span [ class "muted" ] [ text "No longer missed: " ], viewItemChips True recovered ]
                    ]

            Nothing ->
                text ""
        , if selected then
            div [ class "history-detail" ] (List.map viewHistoryItem attempt.items)

          else
            text ""
        ]


viewItemChips : Bool -> List Study.Item -> Html Msg
viewItemChips recovered items =
    span [ classList [ ( "history-chips", True ), ( "is-recovered", recovered ) ] ] (List.map (\item -> span [ class "history-chip", attribute "lang" (itemLang item) ] [ text (itemLabel item) ]) items)


viewHistoryItem : Study.Item -> Html Msg
viewHistoryItem item =
    div [ classList [ ( "history-item", True ), ( "is-right", item.mark == Just True ), ( "is-wrong", item.mark == Just False ) ] ]
        [ span [ class "history-item-label", attribute "lang" (itemLang item) ] [ text (itemLabel item) ]
        , span [ class "interlinear-reference" ]
            [ text
                (if item.kind == Study.WordItem then
                    displayGloss item.reference

                 else
                    item.reference
                )
            ]
        , span [ classList [ ( "interlinear-guess", True ), ( "is-empty", String.isEmpty (String.trim item.guess) ) ] ]
            [ text
                (if String.isEmpty (String.trim item.guess) then
                    "—"

                 else
                    item.guess
                )
            ]
        , span [ class "history-mark" ]
            [ text
                (case item.mark of
                    Just True ->
                        "✓ right"

                    Just False ->
                        "✗ wrong"

                    Nothing ->
                        "unmarked"
                )
            , if item.revealedEarly then
                span [ class "item-note" ] [ text "revealed" ]

              else
                text ""
            ]
        ]


itemLabel : Study.Item -> String
itemLabel item =
    case item.kind of
        Study.WordItem ->
            item.form

        Study.LiteralItem ->
            "Literal translation"

        Study.ProseItem ->
            "Prose translation"


itemLang : Study.Item -> String
itemLang item =
    if item.kind == Study.WordItem then
        "grc"

    else
        "en"


formatDate : Time.Zone -> Int -> String
formatDate zone millis =
    let
        time =
            Time.millisToPosix millis

        twoDigits number =
            String.padLeft 2 '0' (String.fromInt number)

        month =
            case Time.toMonth zone time of
                Time.Jan ->
                    "Jan"

                Time.Feb ->
                    "Feb"

                Time.Mar ->
                    "Mar"

                Time.Apr ->
                    "Apr"

                Time.May ->
                    "May"

                Time.Jun ->
                    "Jun"

                Time.Jul ->
                    "Jul"

                Time.Aug ->
                    "Aug"

                Time.Sep ->
                    "Sep"

                Time.Oct ->
                    "Oct"

                Time.Nov ->
                    "Nov"

                Time.Dec ->
                    "Dec"
    in
    String.fromInt (Time.toDay zone time)
        ++ " "
        ++ month
        ++ " "
        ++ String.fromInt (Time.toYear zone time)
        ++ ", "
        ++ twoDigits (Time.toHour zone time)
        ++ ":"
        ++ twoDigits (Time.toMinute zone time)


{-| Swiping is off while a word popup is open, so gestures inside it (or on its backdrop) never change passage.
-}
passageSwipe : Model -> List (Html.Attribute Msg)
passageSwipe model =
    if model.popupWord == Nothing then
        swipeAttributes model (model.sentenceIndex == 0) (model.sentenceIndex >= List.length model.corpus.sentences - 1)

    else
        []


viewStudyStage : Model -> Html Msg
viewStudyStage model =
    let
        sentence =
            currentSentence model

        interlinear =
            moduleMode GlossModule model.settings /= ModuleOff

        targets =
            askedWords model
    in
    section [ class "reading-stage" ]
        [ viewSessionStatus model
        , viewHistoryLink model
        , p [ class "reading-instruction" ]
            (if interlinear then
                [ text "Write a gloss under each word; tap a word for its lemma, the sentence, or to reveal it. "
                , case targets of
                    Just asked ->
                        span []
                            [ text
                                (if Set.isEmpty asked then
                                    "You got every word last time, so only the translation is asked. "

                                 else
                                    "Only the words you missed last time are asked. "
                                )
                            , button [ class "text-button", type_ "button", onClick (SetAllWords True) ] [ text "Ask every word" ]
                            ]

                    Nothing ->
                        if lastAttempt model /= Nothing then
                            button [ class "text-button", type_ "button", onClick (SetAllWords False) ] [ text "Only words missed last time" ]

                        else
                            text ""
                ]

             else
                [ text "Tap a word to gloss it. "
                , span [] [ text "Answers stay hidden until you reveal them or submit." ]
                ]
            )
        , if interlinear then
            div ([ class "interlinear study-interlinear" ] ++ passageSwipe model)
                (List.map (viewStudyCell model targets) (groupWords sentence.tokens))

          else
            div ([ class "greek-passage study-passage", attribute "lang" "grc" ] ++ passageSwipe model)
                (List.concat (List.indexedMap (viewStudyToken model) sentence.tokens))
        , div [ class "source-line" ]
            [ span [] [ text model.corpus.source.edition ]
            , span [] [ text (String.fromInt (List.length (List.filter Study.isWordToken sentence.tokens)) ++ " words") ]
            ]
        , activeSources model
        , viewToolTray model
        ]


{-| One word of the interlinear study passage: the Greek (tap for the popup), and beneath it the learner's gloss, or on a
repeat, for a word not asked this time, nothing: last time's gloss would give the translation away. A revealed word
shows the reference.
-}
viewStudyCell : Model -> Maybe (Set String) -> ( CorpusToken, String ) -> Html Msg
viewStudyCell model targets ( token, suffix ) =
    let
        key =
            Study.wordKey token.id

        asked =
            isAsked targets key

        open =
            model.popupWord == Just token.id

        revealed =
            Set.member key model.study.revealed
    in
    div
        [ classList
            [ ( "interlinear-word", True )
            , ( "study-cell", True )
            , ( "is-repeat", asked && targets /= Nothing )
            , ( "is-settled", not asked )
            ]
        ]
        [ span [ id (tokenElementId token.id), class "study-token-wrap" ]
            [ button
                [ classList [ ( "interlinear-greek", True ), ( "study-cell-greek", True ), ( "is-open", open ), ( "is-revealed", revealed ) ]
                , type_ "button"
                , attribute "lang" "grc"
                , onClick
                    (if open then
                        ClosePopup

                     else
                        OpenWordPopup token.id
                    )
                , attribute "aria-expanded" (boolString open)
                ]
                [ text (token.form ++ suffix) ]
            , if open then
                span [ class "popup-backdrop", onClick ClosePopup, attribute "aria-hidden" "true" ] []

              else
                text ""
            , if open then
                viewWordPopup model token

              else
                text ""
            ]
        , if asked then
            input
                [ class "cell-input"
                , value (Dict.get token.id model.study.glosses |> Maybe.withDefault "")
                , onInput (StudyGloss token.id)
                , attribute "aria-label" ("Your gloss for " ++ token.form)
                , attribute "autocomplete" "off"
                , attribute "autocapitalize" "off"
                ]
                []

          else
            -- Not asked this time: Greek only. Showing last time's gloss would give away the translation.
            text ""
        , if revealed then
            span [ class "interlinear-reference" ] [ text (displayGloss token.gloss) ]

          else
            text ""
        ]


{-| Punctuation is shown attached to the preceding word and is never a study target.
-}
viewStudyToken : Model -> Int -> CorpusToken -> List (Html Msg)
viewStudyToken model position token =
    if not (Study.isWordToken token) then
        [ span [ class "study-punctuation" ] [ text token.form ] ]

    else
        let
            key =
                Study.wordKey token.id

            guessed =
                Dict.get token.id model.study.glosses |> Maybe.map (not << String.isEmpty << String.trim) |> Maybe.withDefault False

            open =
                model.popupWord == Just token.id
        in
        [ if position == 0 then
            text ""

          else
            text " "
        , span [ id (tokenElementId token.id), class "study-token-wrap" ]
            [ button
                [ classList
                    [ ( "study-token", True )
                    , ( "has-guess", guessed )
                    , ( "is-revealed", Set.member key model.study.revealed )
                    , ( "is-open", open )
                    ]
                , type_ "button"
                , onClick
                    (if open then
                        ClosePopup

                     else
                        OpenWordPopup token.id
                    )
                , attribute "aria-expanded" (boolString open)
                ]
                [ text token.form ]
            , if open then
                -- The backdrop only shows on phones, where the popup is a sheet over the footer and navigation.
                span [ class "popup-backdrop", onClick ClosePopup, attribute "aria-hidden" "true" ] []

              else
                text ""
            , if open then
                viewWordPopup model token

              else
                text ""
            ]
        ]


viewWordPopup : Model -> CorpusToken -> Html Msg
viewWordPopup model token =
    let
        placement =
            Maybe.withDefault { above = False, shift = 0, maxHeight = 0 } model.popupPlacement

        -- Custom properties need a style attribute; Elm's `style` cannot set them.
        placementStyle =
            "--popup-shift: "
                ++ String.fromFloat placement.shift
                ++ "px;"
                ++ (if placement.maxHeight > 0 then
                        " --popup-max-height: " ++ String.fromFloat placement.maxHeight ++ "px;"

                    else
                        ""
                   )
    in
    div
        [ id popupElementId
        , classList
            [ ( "word-popup", True )
            , ( "is-above", placement.above )
            , ( "is-measuring", model.popupPlacement == Nothing )
            ]
        , attribute "style" placementStyle
        , attribute "role" "dialog"
        , attribute "lang" "en"
        , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
        ]
        [ div [ class "popup-tabs" ]
            [ popupTabButton model WordTab "Word"
            , popupTabButton model SentenceTab "Sentence"
            , button [ class "popup-close", type_ "button", onClick ClosePopup, attribute "aria-label" "Close" ] [ text "×" ]
            ]
        , case model.popupTab of
            WordTab ->
                viewGlossField model token True

            SentenceTab ->
                div [ class "popup-sentence" ]
                    (List.map (viewTranslationField model) (translationModules model))
        ]


popupTabButton : Model -> PopupTab -> String -> Html Msg
popupTabButton model tab label =
    button [ classList [ ( "popup-tab", True ), ( "is-active", model.popupTab == tab ) ], type_ "button", onClick (SetPopupTab tab) ] [ text label ]


{-| Prose is always available in the popup; literal only when that tool is on.
-}
translationModules : Model -> List ModuleId
translationModules model =
    List.filter (\moduleId -> moduleId == ProseModule || moduleMode moduleId model.settings /= ModuleOff) [ LiteralModule, ProseModule ]


{-| One word's gloss: the learner's guess and a deliberate reveal of the reference beside it.
-}
viewGlossField : Model -> CorpusToken -> Bool -> Html Msg
viewGlossField model token showHeading =
    let
        key =
            Study.wordKey token.id

        revealed =
            Set.member key model.study.revealed
    in
    div [ class "gloss-field" ]
        [ if showHeading then
            p [ class "popup-form" ]
                [ span [ attribute "lang" "grc" ] [ text token.form ]
                , a [ class "muted popup-lemma", attribute "lang" "grc", href (Route.toPath (Route.Word token.lemma)) ] [ text (displayLemma token.lemma ++ " →") ]
                ]

          else
            span [ class "gloss-row-form", attribute "lang" "grc" ] [ text token.form ]
        , input
            [ class "gloss-input"
            , value (Dict.get token.id model.study.glosses |> Maybe.withDefault "")
            , onInput (StudyGloss token.id)
            , placeholder "Your gloss"
            , attribute "aria-label" ("Your gloss for " ++ token.form)
            ]
            []
        , if revealed then
            span [ class "reference-answer" ] [ text (displayGloss token.gloss) ]

          else
            button [ class "reveal-button", type_ "button", onClick (RevealItem key), attribute "title" "Revealing before submitting marks this word as assisted" ] [ text "Reveal" ]
        ]


viewTranslationField : Model -> ModuleId -> Html Msg
viewTranslationField model moduleId =
    let
        ( key, current, onChange ) =
            if moduleId == LiteralModule then
                ( Study.literalKey, model.study.literal, StudyLiteral )

            else
                ( Study.proseKey, model.study.prose, StudyProse )

        sentence =
            currentSentence model

        reference =
            if moduleId == LiteralModule then
                sentence.literalTranslation

            else
                sentence.proseTranslation
    in
    div [ class "translation-field" ]
        [ label [ class "field-label" ] [ text (moduleName moduleId) ]
        , textarea [ rows 3, value current, onInput onChange, placeholder ("Your " ++ String.toLower (moduleName moduleId)) ] []
        , if Set.member key model.study.revealed then
            p [ class "reference-answer" ] [ text reference ]

          else
            button [ class "reveal-button", type_ "button", onClick (RevealItem key), attribute "title" "Revealing before submitting marks this answer as assisted" ] [ text "Reveal" ]
        ]


displayGloss : String -> String
displayGloss gloss =
    if String.isEmpty gloss then
        "—"

    else
        String.replace "-" " " gloss


viewToolTray : Model -> Html Msg
viewToolTray model =
    let
        sentence =
            currentSentence model

        words =
            List.filter Study.isWordToken sentence.tokens

        glossed =
            List.length (List.filter (\token -> Dict.get token.id model.study.glosses |> Maybe.map (not << String.isEmpty << String.trim) |> Maybe.withDefault False) words)

        status moduleId =
            case moduleId of
                GlossModule ->
                    String.fromInt glossed ++ " of " ++ String.fromInt (List.length words) ++ " words"

                LiteralModule ->
                    draftStatus model.study.literal

                ProseModule ->
                    draftStatus model.study.prose
    in
    section [ class "activity-area" ]
        [ div [ class "activity-heading" ]
            [ p [ class "eyebrow" ] [ text "Tools" ]
            , button [ class "text-button", type_ "button", onClick ShowSettings ] [ text "Choose tools" ]
            ]
        , div [ class "activity-tray" ]
            (List.map
                (\moduleId ->
                    button
                        [ classList [ ( "activity-chip", True ), ( "is-active", model.activeModule == Just moduleId ) ]
                        , type_ "button"
                        , onClick
                            (if model.activeModule == Just moduleId then
                                CloseWorkbench

                             else
                                OpenModule moduleId
                            )
                        ]
                        [ span [ class "chip-copy" ]
                            [ strongText (moduleName moduleId)
                            , span [] [ text (status moduleId) ]
                            ]
                        ]
                )
                (enabledModules model.settings)
            )
        ]


draftStatus : String -> String
draftStatus draft =
    if String.isEmpty (String.trim draft) then
        "Not started"

    else
        "Saved"


viewToolPanel : Model -> Html Msg
viewToolPanel model =
    case model.activeModule of
        Just moduleId ->
            aside [ class "workbench" ]
                [ div [ class "workbench-heading" ]
                    [ h2 [] [ text (moduleName moduleId) ]
                    , button [ class "close-workbench", type_ "button", onClick CloseWorkbench, attribute "aria-label" "Close tool" ] [ text "×" ]
                    ]
                , case moduleId of
                    GlossModule ->
                        div [ class "gloss-list" ]
                            (List.map (\token -> viewGlossField model token False) (List.filter Study.isWordToken (currentSentence model).tokens))

                    _ ->
                        viewTranslationField model moduleId
                ]

        Nothing ->
            text ""


{-| After the checkpoint: the reference gloss above the learner's latest answer under every word, with self-marking.
-}
viewGrading : Model -> Html Msg
viewGrading model =
    let
        sentence =
            currentSentence model

        items =
            studyItems model

        itemFor key =
            List.filter (\item -> item.key == key) items |> List.head

        missed =
            model.activeEntry
                |> Maybe.map (\entry -> Study.missedLastTime entry.id (currentRef model) model.attempts)
                |> Maybe.withDefault Dict.empty

        -- Every word stays in place; words not asked this time have no item and show faded.
        words =
            groupWords sentence.tokens
                |> List.map (\( token, suffix ) -> ( token, suffix, itemFor (Study.wordKey token.id) ))

        translations =
            List.filter (\item -> item.kind /= Study.WordItem) items
    in
    section [ class "reading-stage grading-stage" ]
        [ viewHistoryLink model
        , p [ class "reading-instruction" ]
            [ text "Compare each answer with the reference and mark it yourself. "
            , span [] [ text "Different wording can still be right." ]
            ]
        , div [ class "grading-legend" ]
            [ span [ class "legend-reference" ] [ text "Reference" ]
            , span [ class "legend-guess" ] [ text "Your answer" ]
            , if Dict.isEmpty missed then
                text ""

              else
                span [ class "legend-missed" ] [ text "Missed last time" ]
            ]
        , if List.isEmpty words then
            text ""

          else
            div [ class "interlinear" ]
                (List.map
                    (\( token, suffix, found ) ->
                        case found of
                            Just item ->
                                div [ classList [ ( "interlinear-word", True ), ( "was-missed", Dict.member item.key missed ) ] ]
                                    [ span [ class "interlinear-greek", attribute "lang" "grc" ] [ text (token.form ++ suffix) ]
                                    , span [ class "interlinear-reference" ] [ text (displayGloss item.reference) ]
                                    , span [ classList [ ( "interlinear-guess", True ), ( "is-empty", String.isEmpty (String.trim item.guess) ) ] ]
                                        [ text
                                            (if String.isEmpty (String.trim item.guess) then
                                                "—"

                                             else
                                                item.guess
                                            )
                                        ]
                                    , viewMarkButtons item
                                    , viewItemNotes item missed
                                    ]

                            Nothing ->
                                div [ classList [ ( "interlinear-word", True ), ( "is-settled", True ) ] ]
                                    [ span [ class "interlinear-greek", attribute "lang" "grc" ] [ text (token.form ++ suffix) ]
                                    , span [ class "cell-previous" ] [ text (displayGloss token.gloss) ]
                                    , button [ class "missed-button", type_ "button", onClick (MarkItem (Study.wordKey token.id) False), attribute "title" "You weren't asked this word, but got it wrong: it will be asked next time" ] [ text "✗ Missed it" ]
                                    ]
                    )
                    words
                )
        , div [ class "grading-translations" ]
            (List.map
                (\item ->
                    div [ classList [ ( "grading-card", True ), ( "was-missed", Dict.member item.key missed ) ] ]
                        [ h3 []
                            [ text
                                (if item.kind == Study.LiteralItem then
                                    "Literal translation"

                                 else
                                    "Prose translation"
                                )
                            ]
                        , p [ class "interlinear-reference" ] [ text item.reference ]
                        , p [ classList [ ( "interlinear-guess", True ), ( "is-empty", String.isEmpty (String.trim item.guess) ) ] ]
                            [ text
                                (if String.isEmpty (String.trim item.guess) then
                                    "No answer"

                                 else
                                    item.guess
                                )
                            ]
                        , div [ class "grading-card-actions" ] [ viewMarkButtons item, viewItemNotes item missed ]
                        ]
                )
                translations
            )
        ]


viewMarkButtons : Study.Item -> Html Msg
viewMarkButtons item =
    div [ class "mark-buttons" ]
        [ button [ classList [ ( "mark-button", True ), ( "is-right", item.mark == Just True ) ], type_ "button", onClick (MarkItem item.key True), attribute "aria-label" "Mark right" ] [ text "✓" ]
        , button [ classList [ ( "mark-button", True ), ( "is-wrong", item.mark == Just False ) ], type_ "button", onClick (MarkItem item.key False), attribute "aria-label" "Mark wrong" ] [ text "✗" ]
        ]


viewItemNotes : Study.Item -> Dict String String -> Html Msg
viewItemNotes item missed =
    span [ class "item-notes" ]
        [ if item.revealedEarly then
            span [ class "item-note" ] [ text "revealed" ]

          else
            text ""
        , case Dict.get item.key missed of
            Just previous ->
                span [ class "item-note missed-note", attribute "title" ("Last time: " ++ previous) ]
                    [ text
                        ("last: "
                            ++ (if String.isEmpty (String.trim previous) then
                                    "—"

                                else
                                    previous
                               )
                        )
                    ]

            Nothing ->
                text ""
        ]


{-| Pairs each word with the punctuation that follows it.
-}
groupWords : List CorpusToken -> List ( CorpusToken, String )
groupWords tokens =
    tokens
        |> List.foldl
            (\token groups ->
                if Study.isWordToken token then
                    ( token, "" ) :: groups

                else
                    case groups of
                        ( word, suffix ) :: rest ->
                            ( word, suffix ++ token.form ) :: rest

                        [] ->
                            groups
            )
            []
        |> List.reverse


{-| In today's queue: whether this passage is a review or new, and how many passages remain.
-}
viewQueueStatus : Model -> Html Msg
viewQueueStatus model =
    case ( model.queueMode && not model.queueDone, todayQueue model ) of
        ( True, Just today ) ->
            let
                current =
                    currentRef model

                kind =
                    if List.member current today.due then
                        "Review"

                    else
                        "New"
            in
            span [ class "queue-status" ]
                [ span [ class "queue-kind" ] [ text kind ]
                , text (String.fromInt (List.length today.due + List.length today.new) ++ " left today")
                ]

        _ ->
            text ""


{-| After grading the last passage of a work outside a study session: the work is finished. What's due comes back
through Study; the library and progress are a click away.
-}
viewWorkFinished : Model -> Html Msg
viewWorkFinished model =
    let
        work =
            model.activeEntry |> Maybe.map .id |> Maybe.withDefault ""

        dueNow =
            todayQueue model |> Maybe.map (.due >> List.length) |> Maybe.withDefault 0

        nextDue =
            Review.dueLater model.clock work model.reviews
    in
    section [ class "reading-stage queue-done" ]
        [ p [ class "eyebrow" ] [ text (workTitle model) ]
        , h2 [] [ text ("You've finished " ++ workTitle model) ]
        , p [ class "muted" ]
            [ text
                (case ( dueNow, nextDue ) of
                    ( 0, Just due ) ->
                        "That was the last passage. Its next review is due in " ++ Review.intervalLabel model.clock due ++ "."

                    ( 0, Nothing ) ->
                        "That was the last passage."

                    _ ->
                        "That was the last passage. " ++ String.fromInt dueNow ++ plural dueNow " review is" " reviews are" ++ " due now."
                )
            ]
        , div [ class "button-row" ]
            (List.filterMap identity
                [ model.activeEntry
                    |> Maybe.map
                        (\entry ->
                            button [ class "primary-button", type_ "button", onClick (StartTodayIn entry.id) ]
                                [ text
                                    (if dueNow > 0 then
                                        "Review now →"

                                     else
                                        "Study this work →"
                                    )
                                ]
                        )
                , Just (button [ class "secondary-button", type_ "button", onClick (Navigate Route.Stats) ] [ text "Your progress" ])
                , Just (button [ class "secondary-button", type_ "button", onClick ShowLibrary ] [ text "Back to library" ])
                ]
            )
        ]


viewQueueDone : Model -> Html Msg
viewQueueDone model =
    let
        work =
            model.activeEntry |> Maybe.map .id |> Maybe.withDefault ""

        today =
            List.filter (\attempt -> attempt.work == work && attempt.finishedAt >= Review.startOfDay model.clock) model.attempts

        summary =
            Study.stats today

        nextDue =
            Review.dueLater model.clock work model.reviews

        -- Short relearning steps fall due while this panel is open.
        dueNow =
            todayQueue model |> Maybe.map (.due >> List.length) |> Maybe.withDefault 0
    in
    section [ class "reading-stage queue-done" ]
        [ p [ class "eyebrow" ] [ text (workTitle model) ]
        , h2 [] [ text "Done for today" ]
        , p []
            [ text
                (String.fromInt (List.length today)
                    ++ plural (List.length today) " passage" " passages"
                    ++ " graded today"
                    ++ (if summary.judged > 0 then
                            ", " ++ percent summary.right summary.judged ++ " of marked answers right."

                        else
                            "."
                       )
                )
            ]
        , p [ class "muted" ]
            [ text
                (case ( dueNow, nextDue ) of
                    ( 0, Just due ) ->
                        "Next review due in " ++ Review.intervalLabel model.clock due ++ ". New passages: up to " ++ String.fromInt model.newPerDay ++ " a day."

                    ( 0, Nothing ) ->
                        "No reviews scheduled yet. New passages: up to " ++ String.fromInt model.newPerDay ++ " a day."

                    _ ->
                        String.fromInt dueNow ++ plural dueNow " review is" " reviews are" ++ " due now."
                )
            ]
        , div [ class "button-row" ]
            (List.filterMap identity
                [ if dueNow > 0 then
                    model.activeEntry |> Maybe.map (\entry -> button [ class "primary-button", type_ "button", onClick (StartTodayIn entry.id) ] [ text "Review now →" ])

                  else
                    Nothing
                , if moreToLearn model then
                    Just (learnMoreButton model (dueNow == 0))

                  else
                    Nothing
                , Just (button [ class "secondary-button", type_ "button", onClick (Navigate Route.Stats) ] [ text "Your progress" ])
                , Just (button [ class "secondary-button", type_ "button", onClick ShowLibrary ] [ text "Back to library" ])
                ]
            )
        ]


{-| Finishing is choosing a rating: FSRS schedules the passage and the next one opens. Each button shows when the
passage would come back with that rating.
-}
viewRatingButtons : Model -> List Study.Item -> Html Msg
viewRatingButtons model items =
    let
        suggested =
            Review.suggestRating items

        card =
            model.activeEntry
                |> Maybe.andThen (\entry -> Dict.get (Review.entryKey entry.id (currentRef model)) model.reviews)
                |> Maybe.map .card
                |> Maybe.withDefault (Fsrs.newCard model.clock)

        outcomes =
            Review.scheduler |> Maybe.andThen (\fsrs -> Fsrs.preview fsrs model.clock card |> Result.toMaybe)

        ratingButton rating label pick =
            button
                [ classList [ ( "rating-button", True ), ( "is-suggested", rating == suggested ) ]
                , type_ "button"
                , onClick (FinishGrading rating)
                ]
                [ strongText label
                , span [ class "rating-interval" ]
                    [ text (outcomes |> Maybe.map (\all -> Review.intervalLabel model.clock (pick all).card.due) |> Maybe.withDefault "") ]
                ]
    in
    div [ class "rating-buttons" ]
        [ ratingButton Fsrs.Again "Again" .again
        , ratingButton Fsrs.Hard "Hard" .hard
        , ratingButton Fsrs.Good "Good" .good
        , ratingButton Fsrs.Easy "Easy" .easy
        ]


viewStudyFooter : Model -> Html Msg
viewStudyFooter model =
    let
        items =
            studyItems model

        marked =
            List.length (List.filter (\item -> item.mark /= Nothing) items)
    in
    footer [ id studyFooterId, class "workspace-footer" ]
        (if model.historyOpen then
            [ span [] []
            , div [ class "checkpoint-copy" ]
                [ strongText "Reviewing past attempts"
                , span [] [ text "Your current work on this passage is kept." ]
                ]
            , button [ class "checkpoint-button", type_ "button", onClick CloseHistory ] [ text "Back to current attempt →" ]
            ]

         else if model.study.submitted then
            [ button [ class "footer-side-button", type_ "button", onClick ReopenStudy ] [ text "← Keep working" ]
            , div [ class "checkpoint-copy" ]
                [ strongText (String.fromInt marked ++ " of " ++ String.fromInt (List.length items) ++ " marked")
                , span [] [ text "How well did you know it? The suggestion follows your marks." ]
                ]
            , viewRatingButtons model items
            ]

         else
            [ button [ class "footer-side-button", type_ "button", disabled (model.sentenceIndex == 0), onClick PreviousSentence ] [ text "← Previous" ]
            , div [ class "checkpoint-copy" ]
                [ strongText "Work on any section, in any order"
                , span [] [ text "Answers save automatically in this browser." ]
                ]
            , button [ class "checkpoint-button", type_ "button", onClick SubmitStudy ] [ text "Submit checkpoint →" ]
            ]
        )


{-| The passage the learner last had open in a work (positions are saved as 1-based passage indexes), or its first.
-}
savedRef : ManifestEntry -> Model -> String
savedRef entry model =
    Dict.get entry.id model.positions
        |> Maybe.andThen (\position -> getAt (position - 1) entry.passages)
        |> Maybe.withDefault (List.head entry.passages |> Maybe.withDefault "1")


{-| One select per citation level (Chapter/Verse, Book/Chapter/Section, …) and a go-to box accepting `1:2` or `1.2`.
-}
viewCitationPicker : Model -> Html Msg
viewCitationPicker model =
    let
        refs =
            List.map (.id >> Passage.parts) model.corpus.sentences

        current =
            Passage.parts (currentRef model)

        names =
            Passage.levelNames (String.contains ":" (currentLabel model)) (Passage.isSplit model.corpus.sentences) (Passage.levels model.corpus.sentences)

        choices level =
            refs
                |> List.filter (\parts -> List.take level parts == List.take level current)
                |> List.filterMap (getAt level)
                |> List.foldl
                    (\value found ->
                        if List.member value found then
                            found

                        else
                            found ++ [ value ]
                    )
                    []

        levelSelect level name =
            label [ class "chapter-jump" ]
                [ span [] [ text name ]
                , select [ onInput (\value -> JumpToCitation (String.join "." (List.take level current ++ [ value ]))) ]
                    (List.map (\value -> option [ Html.Attributes.value value, selected (getAt level current == Just value) ] [ text value ]) (choices level))
                ]
    in
    div [ class "citation-picker" ]
        (List.indexedMap levelSelect names
            ++ [ input
                    [ class "citation-go"
                    , placeholder
                        (if String.contains ":" (currentLabel model) then
                            "Go to 1:2"

                         else
                            "Go to 1.2"
                        )
                    , attribute "aria-label" "Go to citation"
                    , on "change" (Decode.map GoToCitation (Decode.at [ "target", "value" ] Decode.string))
                    ]
                    []
               ]
        )
