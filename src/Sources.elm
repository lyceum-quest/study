module Sources exposing (Citation, decoder, encode, view)

{-| The citation `scripts/build-corpus-preload.roc` attaches to each manifest entry: the original
edition, the Opera Graeca Adnotata annotation layer, and Lyceum Study's generated layers.
-}

import Html exposing (Html, a, p, span, text)
import Html.Attributes exposing (class, href, rel, target, title)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type alias Citation =
    { text : TextSource
    , annotations : AnnotationSource
    , generated : GeneratedSource
    }


type alias TextSource =
    { urn : String
    , author : String
    , title : String
    , edition : String
    , repository : String
    , snapshot : String
    , license : String
    , readerUrl : String
    , sourceUrl : String
    }


type alias AnnotationSource =
    { name : String
    , version : String
    , url : String
    , license : String
    }


type alias GeneratedSource =
    { name : String
    , layers : String
    , model : String
    , license : String
    }


decoder : Decoder Citation
decoder =
    Decode.map3 Citation
        (Decode.field "text" textDecoder)
        (Decode.field "annotations" annotationDecoder)
        (Decode.field "generated" generatedDecoder)


textDecoder : Decoder TextSource
textDecoder =
    Decode.succeed TextSource
        |> andMap (Decode.field "urn" Decode.string)
        |> andMap (Decode.field "author" Decode.string)
        |> andMap (Decode.field "title" Decode.string)
        |> andMap (Decode.field "edition" Decode.string)
        |> andMap (Decode.field "repository" Decode.string)
        |> andMap (Decode.field "snapshot" Decode.string)
        |> andMap (Decode.field "license" Decode.string)
        |> andMap (Decode.field "readerUrl" Decode.string)
        |> andMap (Decode.field "sourceUrl" Decode.string)


annotationDecoder : Decoder AnnotationSource
annotationDecoder =
    Decode.map4 AnnotationSource
        (Decode.field "name" Decode.string)
        (Decode.field "version" Decode.string)
        (Decode.field "url" Decode.string)
        (Decode.field "license" Decode.string)


generatedDecoder : Decoder GeneratedSource
generatedDecoder =
    Decode.map4 GeneratedSource
        (Decode.field "name" Decode.string)
        (Decode.field "layers" Decode.string)
        (Decode.field "model" Decode.string)
        (Decode.field "license" Decode.string)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


encode : Citation -> Encode.Value
encode citation =
    let
        strings fields =
            Encode.object (List.map (Tuple.mapSecond Encode.string) fields)
    in
    Encode.object
        [ ( "text"
          , strings
                [ ( "urn", citation.text.urn )
                , ( "author", citation.text.author )
                , ( "title", citation.text.title )
                , ( "edition", citation.text.edition )
                , ( "repository", citation.text.repository )
                , ( "snapshot", citation.text.snapshot )
                , ( "license", citation.text.license )
                , ( "readerUrl", citation.text.readerUrl )
                , ( "sourceUrl", citation.text.sourceUrl )
                ]
          )
        , ( "annotations"
          , strings
                [ ( "name", citation.annotations.name )
                , ( "version", citation.annotations.version )
                , ( "url", citation.annotations.url )
                , ( "license", citation.annotations.license )
                ]
          )
        , ( "generated"
          , strings
                [ ( "name", citation.generated.name )
                , ( "layers", citation.generated.layers )
                , ( "model", citation.generated.model )
                , ( "license", citation.generated.license )
                ]
          )
        ]


{-| A compact attribution line; entries cached before citations existed show nothing.
-}
view : Maybe Citation -> Html msg
view maybeCitation =
    case maybeCitation of
        Nothing ->
            text ""

        Just citation ->
            p [ class "sources-line" ]
                [ span [ class "sources-label" ] [ text "Sources " ]
                , external citation.text.readerUrl citation.text.edition (citation.text.author ++ ", " ++ citation.text.title)
                , text " ("
                , external citation.text.sourceUrl (citation.text.repository ++ " " ++ citation.text.snapshot) "TEI XML"
                , text (", " ++ citation.text.license ++ ") · ")
                , external citation.annotations.url "Tokenization, lemmas, morphology, and syntax" (citation.annotations.name ++ " " ++ citation.annotations.version)
                , text (" (" ++ citation.annotations.license ++ ") · " ++ citation.generated.name ++ " " ++ citation.generated.layers ++ ", generated with " ++ citation.generated.model ++ " (" ++ citation.generated.license ++ ")")
                ]


external : String -> String -> String -> Html msg
external url description label =
    a [ href url, target "_blank", rel "noopener", title description ] [ text label ]
