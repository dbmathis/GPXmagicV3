module Tools.Nudge exposing (..)

import Actions exposing (ToolAction(..))
import Dict exposing (Dict)
import Direction2d exposing (Direction2d)
import Direction3d
import DomainModel exposing (..)
import Element exposing (..)
import Element.Background as Background
import Element.Input as Input exposing (button)
import FlatColors.ChinesePalette
import Length exposing (Meters, inMeters)
import LocalCoords exposing (LocalCoords)
import Point2d exposing (Point2d)
import Point3d exposing (Point3d, xCoordinate, yCoordinate, zCoordinate)
import PreviewData exposing (PreviewPoint, PreviewShape(..))
import Quantity exposing (Quantity)
import SketchPlane3d
import Tools.NudgeOptions exposing (..)
import TrackLoaded exposing (TrackLoaded)
import UtilsForViews exposing (showShortMeasure)
import Vector3d
import ViewPureStyles exposing (..)


type Msg
    = SetHorizontalNudgeFactor (Quantity Float Meters)
    | SetVerticalNudgeFactor (Quantity Float Meters)
    | SetFadeExtent (Quantity Float Meters)
    | ZeroNudgeFactors
    | ApplyWithOptions
    | NudgeButton (Quantity Float Meters)
    | DisplayInfo String String


toolID : String
toolID =
    "nudge"


textDictionary : ( String, Dict String String )
textDictionary =
    -- Introducing the convention of toolID, its use as a text tag, and the "info" tag.
    -- ToolsController can use these for info button and tool label.
    ( toolID
    , Dict.fromList
        [ ( toolID, "Nudge" )
        , ( "info", infoText )
        ]
    )


infoText =
    """Sometimes all it takes is a little _Nudge_.
    
A track point, or a run of points, is slightly out of line from where you want it (them).
With Nudge, you can move a single point, or range of points, sideways and up or down.

What "sideways" means is a but subtle with bends. Nudge moves along what a carpenter would 
recognise as the mitre line, effectively half of the turn. **Be aware** than closely spaced
points nudged together can overlap on the inside of a bend. GPXmagic will not stop this.

The optional _Fade_ slider lets you gradually blend the Nudged section with the neighbouring track.
"""


defaultOptions : Options
defaultOptions =
    { horizontal = Quantity.zero
    , vertical = Quantity.zero
    , fadeExtent = Quantity.zero
    }


type alias Point =
    Point2d Meters LocalCoords


applyUsingOptions :
    Options
    -> TrackLoaded msg
    -> ( Maybe PeteTree, List GPXSource, ( Int, Int ) )
applyUsingOptions options track =
    let
        ( ( actualStart, actualEnd ), newPoints ) =
            computeNudgedPoints options track

        newTree =
            DomainModel.replaceRange
                actualStart
                (skipCount track.trackTree - actualEnd)
                track.referenceLonLat
                (List.map .gpx newPoints)
                track.trackTree

        oldPoints =
            DomainModel.extractPointsInRange
                actualStart
                (skipCount track.trackTree - actualEnd)
                track.trackTree
    in
    ( newTree
    , oldPoints |> List.map Tuple.second
    , ( actualStart, actualEnd )
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
            ( options, previewActions options colour theTrack )

        _ ->
            ( options, [ HidePreview "nudge" ] )


previewActions newOptions colour track =
    [ ShowPreview
        { tag = "nudge"
        , shape = PreviewLine
        , colour = colour
        , points = Tuple.second <| computeNudgedPoints newOptions track
        }
    ]


computeNudgedPoints :
    Options
    -> TrackLoaded msg
    -> ( ( Int, Int ), List PreviewPoint )
computeNudgedPoints settings track =
    let
        ( fromStart, fromEnd ) =
            TrackLoaded.getRangeFromMarkers track

        ( fromNode, toNode ) =
            -- Shim for legacy code; not worth re-writing what is already quite clear.
            ( fromStart, skipCount track.trackTree - fromEnd )

        ( startDistance, endDistance ) =
            ( DomainModel.distanceFromIndex fromNode track.trackTree
            , DomainModel.distanceFromIndex toNode track.trackTree
            )

        fadeInStartDistance =
            startDistance |> Quantity.minus settings.fadeExtent

        fadeOutEndDistance =
            endDistance |> Quantity.plus settings.fadeExtent

        startIncludingFade =
            indexFromDistance fadeInStartDistance track.trackTree

        endIncludingFade =
            indexFromDistance fadeOutEndDistance track.trackTree

        fader pointDistance referenceDistance =
            let
                ( place, base ) =
                    ( inMeters pointDistance, inMeters referenceDistance )

                x =
                    abs <| (place - base) / inMeters settings.fadeExtent
            in
            1.0 - x

        liesWithin ( lo, hi ) given =
            (given |> Quantity.greaterThanOrEqualTo lo)
                && (given |> Quantity.lessThanOrEqualTo hi)

        nudge index =
            let
                pointDistance =
                    DomainModel.distanceFromIndex index track.trackTree

                fade =
                    if
                        pointDistance
                            |> liesWithin ( startDistance, endDistance )
                    then
                        1.0

                    else if
                        pointDistance
                            |> liesWithin ( fadeInStartDistance, startDistance )
                    then
                        fader pointDistance startDistance

                    else if
                        pointDistance
                            |> liesWithin ( endDistance, fadeOutEndDistance )
                    then
                        fader pointDistance endDistance

                    else
                        0.0
            in
            nudgeTrackPoint settings fade index track

        newEarthPoints =
            List.map nudge <| List.range startIncludingFade endIncludingFade

        previewPoints =
            TrackLoaded.asPreviewPoints
                track
                (DomainModel.distanceFromIndex startIncludingFade track.trackTree)
                newEarthPoints
    in
    ( ( startIncludingFade, endIncludingFade ), previewPoints )


effectiveDirection : Int -> TrackLoaded msg -> Direction2d LocalCoords
effectiveDirection index track =
    --In v1 and v2, each point had its before and after directions.
    --That's not stored in v3, but not too hard to compute.
    let
        precedingLeaf =
            -- Will be first leaf if index is zero.
            leafFromIndex (index - 1) track.trackTree |> asRecord

        thisLeaf =
            leafFromIndex index track.trackTree |> asRecord

        deviation =
            Direction2d.angleFrom
                precedingLeaf.directionAtStart
                thisLeaf.directionAtStart

        halfDeviation =
            Quantity.half deviation

        bisectedAngle =
            precedingLeaf.directionAtStart
                |> Direction2d.rotateBy halfDeviation
    in
    -- This formulation intended to avoid -180/+180 issues.
    bisectedAngle


nudgeTrackPoint : Options -> Float -> Int -> TrackLoaded msg -> EarthPoint
nudgeTrackPoint options fade index track =
    if fade == 0 then
        earthPointFromIndex index track.trackTree

    else
        let
            current =
                earthPointFromIndex index track.trackTree

            horizontalDirection =
                effectiveDirection index track
                    |> Direction2d.rotateClockwise
                    |> Direction3d.on SketchPlane3d.xy

            horizontalVector =
                Vector3d.withLength options.horizontal horizontalDirection
                    |> Vector3d.scaleBy fade

            verticalVector =
                Vector3d.xyz Quantity.zero Quantity.zero options.vertical
                    |> Vector3d.scaleBy fade

            newXYZ =
                current
                    |> Point3d.translateBy horizontalVector
                    |> Point3d.translateBy verticalVector
        in
        newXYZ


update :
    Msg
    -> Options
    -> Element.Color
    -> TrackLoaded msg
    -> ( Options, List (ToolAction msg) )
update msg options previewColour track =
    case msg of
        SetHorizontalNudgeFactor value ->
            let
                newOptions =
                    { options | horizontal = value }
            in
            ( newOptions, previewActions newOptions previewColour track )

        SetVerticalNudgeFactor value ->
            let
                newOptions =
                    { options | vertical = value }
            in
            ( newOptions, previewActions newOptions previewColour track )

        NudgeButton value ->
            let
                newOptions =
                    { options | vertical = options.vertical |> Quantity.plus value }
            in
            ( newOptions, previewActions newOptions previewColour track )

        SetFadeExtent value ->
            let
                newOptions =
                    { options | fadeExtent = value }
            in
            ( newOptions, previewActions newOptions previewColour track )

        ZeroNudgeFactors ->
            ( defaultOptions, [ HidePreview "nudge" ] )

        ApplyWithOptions ->
            ( options
            , [ Actions.NudgeApplyWithOptions options
              , TrackHasChanged
              ]
            )

        DisplayInfo tool tag ->
            ( options, [ Actions.DisplayInfo tool tag ] )


view : Bool -> Options -> (Msg -> msg) -> Maybe (TrackLoaded msg) -> Element msg
view imperial options msgWrapper track =
    let
        vertical label increment =
            button
                (width fill :: neatToolsBorder)
                { onPress = Just <| msgWrapper <| NudgeButton increment
                , label = text label
                }

        verticalNudgeButtons =
            column [ alignRight ] <|
                if imperial then
                    [ vertical "+1yd" <| Length.yard
                    , vertical "+1ft" <| Length.foot
                    , vertical "+1in" <| Length.inch
                    , vertical "-1in" <| Quantity.negate Length.inch
                    , vertical "-1ft" <| Quantity.negate Length.foot
                    , vertical "-1yd" <| Quantity.negate Length.yard
                    ]

                else
                    [ vertical "+1m" <| Length.meter
                    , vertical "+10cm" <| Length.centimeters 10
                    , vertical "+1cm" <| Length.centimeter
                    , vertical "-1cm" <| Quantity.negate Length.centimeter
                    , vertical "-10cm" <| Quantity.negate <| Length.centimeters 10
                    , vertical "-1m" <| Quantity.negate Length.meter
                    ]
    in
    case track of
        Nothing ->
            noTrackMessage

        Just isTrack ->
            row
                [ width fill
                , padding 5
                , spacing 5
                , Background.color FlatColors.ChinesePalette.antiFlashWhite
                ]
                [ verticalNudgeButtons
                , verticalNudgeSlider imperial options.vertical msgWrapper
                , column [ width fill, centerX, padding 5, spacing 5 ]
                    [ horizontalNudgeSlider imperial options.horizontal msgWrapper
                    , row [ padding 5, spacing 5 ]
                        [ nudgeButton options msgWrapper
                        , zeroButton msgWrapper
                        ]
                    , text "Fade in/out"
                    , fadeSlider imperial options.fadeExtent msgWrapper
                    ]
                ]


horizontalNudgeSlider : Bool -> Length.Length -> (Msg -> msg) -> Element msg
horizontalNudgeSlider imperial value wrap =
    Input.slider
        commonShortHorizontalSliderStyles
        { onChange = Length.meters >> SetHorizontalNudgeFactor >> wrap
        , label = Input.labelBelow [ centerX ] <| text <| showShortMeasure imperial value
        , min =
            Length.inMeters <|
                if imperial then
                    Length.feet -21.0

                else
                    Length.meters -7.0
        , max =
            Length.inMeters <|
                if imperial then
                    Length.feet 21.0

                else
                    Length.meters 7.0
        , step =
            Just <|
                Length.inMeters <|
                    if imperial then
                        Length.inches 2

                    else
                        Length.centimeters 5
        , value = Length.inMeters value
        , thumb = Input.defaultThumb
        }


fadeSlider : Bool -> Length.Length -> (Msg -> msg) -> Element msg
fadeSlider imperial value wrap =
    Input.slider
        commonShortHorizontalSliderStyles
        { onChange = Length.meters >> SetFadeExtent >> wrap
        , label = Input.labelBelow [ centerX ] <| text <| showShortMeasure imperial value
        , min = 0.0
        , max =
            Length.inMeters <|
                if imperial then
                    Length.feet 160.0

                else
                    Length.meters 50.0
        , step = Nothing
        , value = Length.inMeters value
        , thumb = Input.defaultThumb
        }


verticalNudgeSlider : Bool -> Quantity Float Meters -> (Msg -> msg) -> Element msg
verticalNudgeSlider imperial value wrap =
    el [ width fill, alignRight, paddingEach { edges | left = 10 } ] <|
        Input.slider
            commonShortVerticalSliderStyles
            { onChange = Length.meters >> SetVerticalNudgeFactor >> wrap
            , label = Input.labelBelow [ centerY ] <| text <| showShortMeasure imperial value
            , min =
                Length.inMeters <|
                    if imperial then
                        Length.feet -21.0

                    else
                        Length.meters -7.0
            , max =
                Length.inMeters <|
                    if imperial then
                        Length.feet 21.0

                    else
                        Length.meters 7.0
            , step =
                Just <|
                    Length.inMeters <|
                        if imperial then
                            Length.inches 2

                        else
                            Length.centimeters 5
            , value = Length.inMeters value
            , thumb = Input.defaultThumb
            }


nudgeButton : Options -> (Msg -> msg) -> Element msg
nudgeButton settings wrap =
    button
        neatToolsBorder
        { onPress = Just <| wrap ApplyWithOptions
        , label = text "Apply"
        }


zeroButton : (Msg -> msg) -> Element msg
zeroButton wrap =
    button
        neatToolsBorder
        { onPress = Just <| wrap ZeroNudgeFactors
        , label = text "Zero sliders"
        }
