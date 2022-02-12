module Tools.OutAndBack exposing (..)

import Actions exposing (PreviewData, PreviewShape(..), ToolAction(..))
import Angle
import Arc2d exposing (Arc2d)
import Arc3d exposing (Arc3d)
import Axis3d
import DomainModel exposing (..)
import Element exposing (..)
import Element.Background as Background
import Element.Input as Input exposing (button)
import FlatColors.ChinesePalette
import Geometry101 as G exposing (..)
import Length exposing (Meters, inMeters, meters)
import LineSegment2d
import List.Extra
import LocalCoords exposing (LocalCoords)
import Point2d exposing (Point2d)
import Point3d exposing (Point3d, xCoordinate, yCoordinate, zCoordinate)
import Polyline2d
import Polyline3d
import Quantity
import SketchPlane3d
import Tools.Nudge
import Tools.OutAndBackOptions exposing (..)
import TrackLoaded exposing (TrackLoaded)
import UtilsForViews exposing (showShortMeasure)
import Vector2d
import Vector3d
import ViewPureStyles exposing (..)


defaultOptions : Options
defaultOptions =
    { offset = 0.0 }


type alias Point =
    Point2d Meters LocalCoords


type Msg
    = ApplyOutAndBack
    | SetOffset Float


computeNewPoints : Options -> TrackLoaded msg -> List ( EarthPoint, GPXSource )
computeNewPoints options track =
    let
        ( fromStart, fromEnd ) =
            TrackLoaded.getRangeFromMarkers track

        previewPoints points =
            points
                |> List.map
                    (\earth ->
                        ( earth
                        , DomainModel.gpxFromPointWithReference track.referenceLonLat earth
                        )
                    )
    in
    []


apply : Options -> TrackLoaded msg -> ( Maybe PeteTree, List GPXSource )
apply options track =
    let
        nudgeOptions =
            Tools.Nudge.defaultOptions

        ( _, outwardLeg ) =
            -- nudge entire route one way, in natural order
            Tools.Nudge.computeNudgedPoints
                { nudgeOptions | horizontal = Length.meters options.offset }
                track

        ( _, returnLegWrongWay ) =
            -- nudge route other way, reversed
            Tools.Nudge.computeNudgedPoints
                { nudgeOptions | horizontal = Quantity.negate <| Length.meters options.offset }
                track

        returnLeg =
            List.reverse returnLegWrongWay

        homeLeaf =
            getFirstLeaf track.trackTree

        homeTurnMidpoint =
            -- extend first leaf back to find point on turn
            let
                leafAxis =
                    Axis3d.throughPoints homeLeaf.startPoint homeLeaf.endPoint
            in
            case leafAxis of
                Just axis ->
                    Point3d.along
                        axis
                        (Quantity.negate <| Length.meters <| abs options.offset)

                Nothing ->
                    homeLeaf.startPoint

        awayLeaf =
            getFirstLeaf track.trackTree

        awayTurnMidpoint =
            -- extend last leaf to find point on turn
            let
                leafAxis =
                    Axis3d.throughPoints awayLeaf.endPoint awayLeaf.startPoint
            in
            case leafAxis of
                Just axis ->
                    Point3d.along
                        axis
                        (Quantity.negate <| Length.meters <| abs options.offset)

                Nothing ->
                    awayLeaf.endPoint

        awayTurn =
            -- arc through midpoint joining outward and return legs
            let
                finalOutwardPoint =
                    List.Extra.last outwardLeg

                firstInwardPoint =
                    List.head returnLeg
            in
            case ( finalOutwardPoint, firstInwardPoint ) of
                ( Just ( outEarth, outGPX ), Just ( backEarth, backGpx ) ) ->
                    Arc3d.throughPoints
                        outEarth
                        awayTurnMidpoint
                        backEarth

                _ ->
                    Nothing

        homeTurn =
            -- arc through midpoint joining return and outward legs
            let
                finalInwardPoint =
                    List.Extra.last returnLeg

                firstOutwardPoint =
                    List.head outwardLeg
            in
            case ( finalInwardPoint, firstOutwardPoint ) of
                ( Just ( inEarth, inGPX ), Just ( outEarth, outGpx ) ) ->
                    Arc3d.throughPoints
                        inEarth
                        homeTurnMidpoint
                        outEarth

                _ ->
                    Nothing

        homeTurnInGpx =
            case homeTurn of
                Just arc ->
                    arc
                        |> Arc3d.approximate (Length.meters 1.0)
                        |> Polyline3d.vertices
                        |> List.map (gpxFromPointWithReference track.referenceLonLat)

                Nothing ->
                    []

        awayTurnInGpx =
            case awayTurn of
                Just arc ->
                    arc
                        |> Arc3d.approximate (Length.meters 1.0)
                        |> Polyline3d.vertices
                        |> List.map (gpxFromPointWithReference track.referenceLonLat)

                Nothing ->
                    []

        newCourse =
            List.map Tuple.second outwardLeg
                ++ awayTurnInGpx
                ++ List.map Tuple.second returnLeg
                ++ homeTurnInGpx

        newTree =
            DomainModel.treeFromSourcePoints newCourse

        -- New tree built from four parts:
        -- Out (nudged one way), away turn, back (nudged other way), home turn.
        oldPoints =
            -- All the points.
            getAllGPXPointsInNaturalOrder track.trackTree
    in
    ( newTree
    , oldPoints
    )


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
            ( options, [] )


update :
    Msg
    -> Options
    -> Maybe (TrackLoaded msg)
    -> ( Options, List (ToolAction msg) )
update msg options hasTrack =
    case ( hasTrack, msg ) of
        ( Just track, SetOffset offset ) ->
            let
                newOptions =
                    { options | offset = offset }
            in
            ( newOptions, [] )

        ( Just track, ApplyOutAndBack ) ->
            ( options
            , [ Actions.OutAndBackApplyWithOptions options
              , TrackHasChanged
              ]
            )

        _ ->
            ( options, [] )


view : Bool -> (Msg -> msg) -> Options -> Maybe (TrackLoaded msg) -> Element msg
view imperial wrapper options track =
    let
        fixButton =
            button
                neatToolsBorder
                { onPress = Just <| wrapper ApplyOutAndBack
                , label = text "Make out and back"
                }
    in
    case track of
        Just isTrack ->
            column
                [ padding 5
                , spacing 5
                , width fill
                , centerX
                , Background.color FlatColors.ChinesePalette.antiFlashWhite
                ]
                [ el [ centerX ] <| offsetSlider imperial options wrapper
                , el [ centerX ] <| fixButton
                ]

        Nothing ->
            noTrackMessage


offsetSlider : Bool -> Options -> (Msg -> msg) -> Element msg
offsetSlider imperial options wrap =
    Input.slider
        commonShortHorizontalSliderStyles
        { onChange = wrap << SetOffset
        , label =
            Input.labelBelow [] <|
                text <|
                    "Offset: "
                        ++ showShortMeasure imperial (Length.meters options.offset)
        , min =
            Length.inMeters <|
                if imperial then
                    Length.feet -16.0

                else
                    Length.meters -5.0
        , max =
            Length.inMeters <|
                if imperial then
                    Length.feet 16.0

                else
                    Length.meters 5.0
        , step = Just 0.5
        , value = options.offset
        , thumb = Input.defaultThumb
        }
