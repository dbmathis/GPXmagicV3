module Tools.DisplaySettings exposing (..)

import Actions exposing (PreviewData, PreviewShape(..), ToolAction(..))
import Element exposing (..)
import Element.Background as Background
import Element.Input as Input exposing (button)
import FlatColors.ChinesePalette
import Tools.DisplaySettingsOptions exposing (..)
import TrackLoaded exposing (TrackLoaded)


defaultOptions : Options
defaultOptions =
    { roadSurface = True
    , curtainStyle = PastelCurtain
    , centreLine = False
    , groundPlane = True
    }


type Msg
    = SetRoadSurface Bool
    | SetCurtainStyle CurtainStyle
    | SetCentreLine Bool
    | SetGroundPlane Bool


update :
    Msg
    -> Options
    -> ( Options, List (ToolAction msg) )
update msg options =
    let
        actions =
            []
    in
    case msg of
        SetCentreLine state ->
            let
                newOptions =
                    { options | centreLine = state }
            in
            ( newOptions, actions )

        SetGroundPlane state ->
            let
                newOptions =
                    { options | groundPlane = state }
            in
            ( newOptions, actions )

        SetRoadSurface state ->
            let
                newOptions =
                    { options | groundPlane = state }
            in
            ( newOptions, actions )

        SetCurtainStyle curtainStyle ->
            let
                newOptions =
                    { options | curtainStyle = curtainStyle }
            in
            ( newOptions, actions )


view : (Msg -> msg) -> Options -> Element msg
view wrap options =
    let
        curtainChoice =
            Input.radio
                [ padding 5
                , spacing 5
                ]
                { onChange = wrap << SetCurtainStyle
                , selected = Just options.curtainStyle
                , label = Input.labelHidden "Curtain"
                , options =
                    [ Input.option NoCurtain (text "None")
                    , Input.option PlainCurtain (text "Plain")
                    , Input.option PastelCurtain (text "Coloured")
                    ]
                }
    in
    column
        [ spacing 5
        , padding 5
        , centerX
        , width fill
        , Background.color FlatColors.ChinesePalette.antiFlashWhite
        ]
        [ el [ centerX ] curtainChoice
        , Input.checkbox
            [ padding 5
            , spacing 5
            ]
            { onChange = wrap << SetRoadSurface
            , checked = options.roadSurface
            , label = Input.labelLeft [] <| text "Road surface"
            , icon = Input.defaultCheckbox
            }
        , Input.checkbox
            [ padding 5
            , spacing 5
            ]
            { onChange = wrap << SetGroundPlane
            , checked = options.groundPlane
            , label = Input.labelLeft [] <| text "Ground"
            , icon = Input.defaultCheckbox
            }
        , Input.checkbox
            [ padding 5
            , spacing 5
            ]
            { onChange = wrap << SetCentreLine
            , checked = options.centreLine
            , label = Input.labelLeft [] <| text "Centre line"
            , icon = Input.defaultCheckbox
            }
        ]
