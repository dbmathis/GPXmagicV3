module Tools.Flythrough exposing (..)

import Actions exposing (ToolAction)
import Dict exposing (Dict)
import DomainModel exposing (EarthPoint, asRecord)
import Element exposing (..)
import Element.Background as Background
import Element.Input as Input exposing (button)
import FeatherIcons
import FlatColors.ChinesePalette
import Length
import Point3d exposing (Point3d)
import Quantity
import Speed
import Time
import TrackLoaded exposing (TrackLoaded)
import UtilsForViews exposing (showLongMeasure, showSpeed)
import Vector3d
import ViewPureStyles exposing (commonShortHorizontalSliderStyles, neatToolsBorder, prettyButtonStyles, useIcon)



{-
   Note that for v3, Flythrough needs to update the current point for rendering to work
-}


type Msg
    = SetFlythroughSpeed Float
    | StartFlythrough
    | PauseFlythrough
    | ResumeFlythrough
    | ResetFlythrough
    | DisplayInfo String String


toolID : String
toolID =
    "fly"


textDictionary : ( String, Dict String String )
textDictionary =
    -- Introducing the convention of toolID, its use as a text tag, and the "info" tag.
    -- ToolsController can use these for info button and tool label.
    ( toolID
    , Dict.fromList
        [ ( toolID, "Flythrough" )
        , ( "info", infoText )
        ]
    )


infoText =
    """It's often useful to see the track as the rider would see in in RGT. We don't have the
sophisticated scenery that RGT offers, but you can set the ride in motion and adjust the speed
to get a quick feel for how it might ride.
"""


type alias Flythrough =
    { cameraPosition : EarthPoint
    , focusPoint : EarthPoint
    , metresFromRouteStart : Length.Length
    , lastUpdated : Time.Posix
    , running : RunState
    , gradient : Float
    }


type RunState
    = Idle
    | AwaitingFirstTick
    | Running
    | Ended
    | Paused


type alias Options =
    { flythroughSpeed : Float
    , flythrough : Maybe Flythrough
    , savedCurrentPosition : Int
    }


defaultOptions =
    { flythroughSpeed = 1.0
    , flythrough = Nothing
    , savedCurrentPosition = 0
    }


eyeHeight =
    Length.meters 2.0


advanceInternal :
    Time.Posix
    -> Flythrough
    -> Float
    -> TrackLoaded msg
    -> Maybe Flythrough
advanceInternal newTime status speed track =
    let
        tempus =
            toFloat (Time.posixToMillis newTime - Time.posixToMillis status.lastUpdated) / 1000.0

        newDistance =
            status.metresFromRouteStart
                |> Quantity.plus (Length.meters <| tempus * 10.0 ^ speed)

        lastPointPassedIndex =
            DomainModel.indexFromDistance newDistance track.trackTree

        currentRoad =
            DomainModel.leafFromIndex lastPointPassedIndex track.trackTree
                |> asRecord

        nextRoad =
            DomainModel.leafFromIndex (lastPointPassedIndex + 1) track.trackTree
                |> asRecord

        lastPointDistance =
            DomainModel.distanceFromIndex lastPointPassedIndex track.trackTree
    in
    case status.running of
        Idle ->
            Just status

        AwaitingFirstTick ->
            Just
                { status
                    | lastUpdated = newTime
                    , running = Running
                }

        Paused ->
            Just { status | lastUpdated = newTime }

        Ended ->
            Just status

        Running ->
            if
                status.metresFromRouteStart
                    |> Quantity.greaterThanOrEqualTo (DomainModel.trueLength track.trackTree)
            then
                Just { status | running = Ended }

            else
                let
                    segInsetMetres =
                        newDistance |> Quantity.minus lastPointDistance

                    segLength =
                        currentRoad.trueLength

                    segFraction =
                        Quantity.ratio segInsetMetres segLength

                    segRemaining =
                        segLength
                            |> Quantity.minus segInsetMetres
                            |> Length.inMeters

                    headTurnFraction =
                        -- Allow for POV rotation as we near segment end.
                        clamp 0.0 1.0 <| (10.0 - segRemaining) / 10.0

                    camera3d =
                        -- The camera is where the bike is!
                        Point3d.translateBy
                            (Vector3d.xyz Quantity.zero Quantity.zero eyeHeight)
                        <|
                            Point3d.interpolateFrom
                                currentRoad.startPoint
                                currentRoad.endPoint
                                segFraction

                    lookingAt =
                        -- Should be looking at the next point, until we are close
                        -- enough to start looking at the one beyond that.
                        Point3d.interpolateFrom
                            currentRoad.endPoint
                            nextRoad.endPoint
                            headTurnFraction
                            |> Point3d.translateBy
                                (Vector3d.xyz Quantity.zero Quantity.zero eyeHeight)
                in
                Just
                    { status
                        | metresFromRouteStart = newDistance
                        , lastUpdated = newTime
                        , cameraPosition = camera3d
                        , focusPoint = lookingAt
                        , gradient = currentRoad.gradientAtStart
                    }


view : Bool -> Options -> (Msg -> msg) -> Element msg
view imperial options wrapper =
    let
        speed =
            Speed.metersPerSecond (10.0 ^ options.flythroughSpeed)

        flythroughSpeedSlider =
            Input.slider
                commonShortHorizontalSliderStyles
                { onChange = wrapper << SetFlythroughSpeed
                , label =
                    Input.labelBelow [] <|
                        text <|
                            "Speed = "
                                ++ showSpeed imperial speed
                , min = 1.0 -- i.e. 1
                , max = 3.0 -- i.e. 1000
                , step = Nothing
                , value = options.flythroughSpeed
                , thumb = Input.defaultThumb
                }

        resetButton =
            button
                neatToolsBorder
                { onPress = Just <| wrapper ResetFlythrough
                , label = useIcon FeatherIcons.rewind
                }

        playButton =
            button
                neatToolsBorder
                { onPress = Just <| wrapper StartFlythrough
                , label = useIcon FeatherIcons.play
                }

        pauseButton state =
            button
                neatToolsBorder
            <|
                case state of
                    Paused ->
                        { onPress = Just <| wrapper ResumeFlythrough
                        , label = useIcon FeatherIcons.play
                        }

                    _ ->
                        { onPress = Just <| wrapper PauseFlythrough
                        , label = useIcon FeatherIcons.pause
                        }

        playPauseButton =
            case options.flythrough of
                Nothing ->
                    playButton

                Just flying ->
                    pauseButton flying.running
    in
    column
        [ padding 10
        , spacing 10
        , centerX
        , width fill
        , Background.color FlatColors.ChinesePalette.antiFlashWhite
        ]
        [ el [ centerX ] <|
            row [ padding 10, spacing 10, centerX ]
                [ resetButton
                , playPauseButton
                ]
        , el [ centerX ] <| flythroughSpeedSlider
        , el [ centerX ] <|
            case options.flythrough of
                Just flying ->
                    row [ spacing 10 ]
                        [ text "From start "
                        , text <| showLongMeasure imperial flying.metresFromRouteStart
                        ]

                Nothing ->
                    none
        ]


toolStateChange :
    Bool
    -> Element.Color
    -> Options
    -> Maybe (TrackLoaded msg)
    -> ( Options, List (ToolAction msg) )
toolStateChange opened colour options track =
    case ( opened, track ) of
        ( True, Just theTrack ) ->
            ( options, [] )

        _ ->
            ( { options | flythrough = Nothing }
            , [ Actions.StopFlythroughTicks ]
            )


update :
    Options
    -> Msg
    -> TrackLoaded msg
    -> ( Options, List (ToolAction msg) )
update options msg track =
    case msg of
        SetFlythroughSpeed speed ->
            ( { options | flythroughSpeed = speed }
            , []
            )

        StartFlythrough ->
            ( startFlythrough track options
            , [ Actions.StartFlythoughTicks ]
            )

        PauseFlythrough ->
            case options.flythrough of
                Just flythrough ->
                    ( { options | flythrough = Just { flythrough | running = Paused } }
                    , [ Actions.StopFlythroughTicks ]
                    )

                Nothing ->
                    ( options, [] )

        ResumeFlythrough ->
            case options.flythrough of
                Just flythrough ->
                    ( { options | flythrough = Just { flythrough | running = AwaitingFirstTick } }
                    , [ Actions.StartFlythoughTicks ]
                    )

                Nothing ->
                    ( options, [] )

        ResetFlythrough ->
            ( { options | flythrough = Nothing }
            , [ Actions.StopFlythroughTicks
              , Actions.SetCurrent options.savedCurrentPosition
              ]
            )

        DisplayInfo tool tag ->
            ( options, [ Actions.DisplayInfo tool tag ] )


advanceFlythrough :
    Time.Posix
    -> Options
    -> TrackLoaded msg
    -> ( Options, List (ToolAction msg) )
advanceFlythrough posixTime options track =
    case options.flythrough of
        Just flythrough ->
            let
                updatedFlythrough =
                    advanceInternal
                        posixTime
                        flythrough
                        options.flythroughSpeed
                        track

                newOptions =
                    { options | flythrough = updatedFlythrough }
            in
            ( newOptions
            , case updatedFlythrough of
                Just stillFlying ->
                    [ Actions.SetCurrent <|
                        DomainModel.indexFromDistanceRoundedDown
                            stillFlying.metresFromRouteStart
                            track.trackTree
                    ]

                Nothing ->
                    [ Actions.SetCurrent options.savedCurrentPosition
                    , Actions.StopFlythroughTicks
                    ]
            )

        Nothing ->
            ( options, [ Actions.StopFlythroughTicks ] )


prepareFlythrough : TrackLoaded msg -> Options -> Maybe Flythrough
prepareFlythrough track options =
    let
        currentRoad =
            DomainModel.leafFromIndex track.currentPosition track.trackTree
                |> asRecord

        eyePoint =
            currentRoad.startPoint
                |> Point3d.translateBy
                    (Vector3d.xyz Quantity.zero Quantity.zero eyeHeight)

        focusPoint =
            currentRoad.endPoint
                |> Point3d.translateBy
                    (Vector3d.xyz Quantity.zero Quantity.zero eyeHeight)

        cameraShift =
            Point3d.interpolateFrom eyePoint focusPoint -1.0
    in
    Just
        { metresFromRouteStart = DomainModel.distanceFromIndex track.currentPosition track.trackTree
        , cameraPosition = eyePoint
        , focusPoint = focusPoint
        , lastUpdated = Time.millisToPosix 0
        , running = AwaitingFirstTick
        , gradient = currentRoad.gradientAtStart
        }


startFlythrough : TrackLoaded msg -> Options -> Options
startFlythrough track options =
    case prepareFlythrough track options of
        Just flying ->
            { options
                | flythrough = Just flying
                , savedCurrentPosition = track.currentPosition
            }

        Nothing ->
            options


togglePause : Options -> Options
togglePause options =
    case options.flythrough of
        Just flying ->
            { options
                | flythrough =
                    Just
                        { flying
                            | running =
                                case flying.running of
                                    Paused ->
                                        Running

                                    Running ->
                                        Paused

                                    _ ->
                                        flying.running
                        }
            }

        Nothing ->
            options


isActive : Options -> Bool
isActive options =
    case options.flythrough of
        Just fly ->
            fly.running == Running

        Nothing ->
            False
