module PaneLayoutManager exposing (..)

import Element exposing (Element, column, el, htmlAttribute, inFront, moveDown, none, padding, spacing, text)
import Element.Background as Background
import Element.Input as Input exposing (button)
import FlatColors.ChinesePalette
import Html.Attributes exposing (style)
import Html.Events.Extra.Mouse as Mouse
import ViewContext exposing (ViewContext, ViewMode)
import ViewPureStyles exposing (neatToolsBorder)
import ViewThirdPerson exposing (stopProp)


type PaneType
    = PaneWithMap
    | PaneNoMap


type PaneLayout
    = PanesOne
    | PanesLeftRight
    | PanesUpperLower
    | PanesOnePlusTwo
    | PanesGrid


type PaneId
    = Pane1
    | Pane2
    | Pane3
    | Pane4


type alias PaneContext =
    { paneId : PaneId
    , activeView : ViewMode
    , thirdPersonContext : ViewContext
    }


type alias Options =
    { paneLayout : PaneLayout
    , popupVisible : Bool
    }


defaultOptions =
    { paneLayout = PanesOne
    , popupVisible = False
    }


type Msg
    = SetPaneLayout PaneLayout
    | TogglePopup
    | PaneNoOp


paneLayoutMenu : (Msg -> msg) -> Options -> Element msg
paneLayoutMenu msgWrapper options =
    Input.button
        [ padding 5
        , Background.color FlatColors.ChinesePalette.antiFlashWhite
        , inFront <| showOptionsMenu msgWrapper options
        ]
        { onPress = Just <| msgWrapper TogglePopup
        , label = text "Choose layout"
        }


showOptionsMenu : (Msg -> msg) -> Options -> Element msg
showOptionsMenu msgWrapper options =
    if options.popupVisible then
        el
            [ moveDown 30
            , htmlAttribute <| Mouse.onWithOptions "click" stopProp (always PaneNoOp >> msgWrapper)
            , htmlAttribute <| Mouse.onWithOptions "dblclick" stopProp (always PaneNoOp >> msgWrapper)
            , htmlAttribute <| Mouse.onWithOptions "mousedown" stopProp (always PaneNoOp >> msgWrapper)
            , htmlAttribute <| Mouse.onWithOptions "mouseup" stopProp (always PaneNoOp >> msgWrapper)
            , htmlAttribute (style "z-index" "20")
            ]
        <|
            Input.radio
                (neatToolsBorder
                    ++ [ padding 10, spacing 10 ]
                )
                { options = optionList
                , onChange = msgWrapper << SetPaneLayout
                , selected = Just options.paneLayout
                , label = Input.labelHidden "Choose layout"
                }

    else
        none


optionList =
    [ Input.option PanesOne <| text "One big one"
    , Input.option PanesLeftRight <| text "Wardrobe doors"
    , Input.option PanesUpperLower <| text "Bunk beds"
    , Input.option PanesGrid <| text "Grid of four"
    ]


update : Msg -> (Msg -> msg) -> Options -> Options
update paneMsg msgWrapper options =
    case paneMsg of
        PaneNoOp ->
            options

        SetPaneLayout paneLayout ->
            { options | paneLayout = paneLayout }

        TogglePopup ->
            { options | popupVisible = not options.popupVisible }