module Tools.BendSmoother exposing (..)

import Actions exposing (PreviewData, PreviewShape(..), ToolAction(..))
import Angle
import Arc2d exposing (Arc2d)
import DomainModel exposing (EarthPoint, GPXSource, PeteTree, RoadSection, endPoint, skipCount, startPoint)
import Element exposing (..)
import Element.Background as Background
import Element.Input as Input exposing (button)
import FlatColors.ChinesePalette
import Geometry101 as G exposing (distance, findIntercept, interpolateLine, isAfter, isBefore, lineEquationFromTwoPoints, lineIntersection, linePerpendicularTo, pointAlongRoad, pointsToGeometry)
import Length exposing (Meters, inMeters)
import LineSegment2d
import LocalCoords exposing (LocalCoords)
import Plane3d
import Point2d exposing (Point2d)
import Point3d exposing (Point3d, xCoordinate, yCoordinate, zCoordinate)
import Polyline2d
import Quantity
import SketchPlane3d
import Tools.BendSmootherOptions exposing (..)
import TrackLoaded exposing (TrackLoaded)
import UtilsForViews exposing (showShortMeasure)
import Vector3d
import ViewPureStyles exposing (..)


defaultOptions : Options
defaultOptions =
    { bendTrackPointSpacing = 5.0
    , smoothedBend = Nothing
    , segments = 1
    }


type alias Point =
    Point2d Meters LocalCoords


type Msg
    = ApplyWithOptions
    | SetBendTrackPointSpacing Float


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
    case options.smoothedBend of
        Just bend ->
            previewPoints bend.nodes

        Nothing ->
            []


tryBendSmoother : TrackLoaded msg -> Options -> Options
tryBendSmoother track options =
    let
        ( fromStart, fromEnd ) =
            TrackLoaded.getRangeFromMarkers track

        ( startPoint, endPoint ) =
            -- Legacy code is zero based from start.
            ( fromStart, skipCount track.trackTree - fromEnd )

        updatedOptions =
            { options
                | smoothedBend =
                    if endPoint >= startPoint + 2 then
                        lookForSmoothBendOption options.bendTrackPointSpacing track startPoint endPoint

                    else
                        Nothing
            }
    in
    updatedOptions


applyUsingOptions : Options -> TrackLoaded msg -> ( Maybe PeteTree, List GPXSource )
applyUsingOptions options track =
    let
        ( fromStart, fromEnd ) =
            TrackLoaded.getRangeFromMarkers track

        newTree =
            DomainModel.replaceRange
                (fromStart + 1)
                (fromEnd + 1)
                track.referenceLonLat
                (List.map Tuple.second <| computeNewPoints options track)
                track.trackTree

        oldPoints =
            DomainModel.extractPointsInRange
                fromStart
                fromEnd
                track.trackTree
    in
    ( newTree
    , oldPoints |> List.map Tuple.second
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
            ( options, [ HidePreview "bend" ] )


previewActions newOptions colour track =
    -- Subverting this mechanism to show the discs and captured points on the views.
    [ ShowPreview
        { tag = "bend"
        , shape = PreviewCircle
        , colour = colour
        , points = computeNewPoints newOptions track
        }
    ]


update :
    Msg
    -> Options
    -> Element.Color
    -> Maybe (TrackLoaded msg)
    -> ( Options, List (ToolAction msg) )
update msg options previewColour hasTrack =
    case ( hasTrack, msg ) of
        ( Just track, SetBendTrackPointSpacing spacing ) ->
            let
                newOptions =
                    { options | bendTrackPointSpacing = spacing }
                        |> tryBendSmoother track
            in
            ( newOptions, previewActions newOptions previewColour track )

        ( Just track, ApplyWithOptions ) ->
            ( options
            , [ Actions.BendSmootherApplyWithOptions options
              , TrackHasChanged
              ]
            )

        _ ->
            ( options, [] )


view : Bool -> (Msg -> msg) -> Options -> Maybe (TrackLoaded msg) -> Element msg
view imperial wrapper options track =
    let
        fixBendButton smooth =
            button
                neatToolsBorder
                { onPress = Just <| wrapper ApplyWithOptions
                , label =
                    case smooth of
                        Just isSmooth ->
                            paragraph [] <|
                                [ text <|
                                    "Smooth between markers\nRadius "
                                        ++ showShortMeasure imperial (Length.meters isSmooth.radius)
                                ]

                        Nothing ->
                            text "No bend found"
                }
    in
    case track of
        Just isTrack ->
            column
                [ padding 10
                , spacing 5
                , width fill
                , centerX
                , Background.color FlatColors.ChinesePalette.antiFlashWhite
                ]
                [ el [ centerX ] <| bendSmoothnessSlider imperial options wrapper
                , el [ centerX ] <| fixBendButton options.smoothedBend
                ]

        Nothing ->
            noTrackMessage


bendSmoothnessSlider : Bool -> Options -> (Msg -> msg) -> Element msg
bendSmoothnessSlider imperial options wrap =
    Input.slider
        commonShortHorizontalSliderStyles
        { onChange = wrap << SetBendTrackPointSpacing
        , label =
            Input.labelBelow [] <|
                text <|
                    "Spacing: "
                        ++ showShortMeasure imperial (Length.meters options.bendTrackPointSpacing)
        , min =
            Length.inMeters <|
                if imperial then
                    Length.feet 3.0

                else
                    Length.meters 1.0
        , max =
            Length.inMeters <|
                if imperial then
                    Length.feet 30.0

                else
                    Length.meters 10.0
        , step = Nothing
        , value = options.bendTrackPointSpacing
        , thumb = Input.defaultThumb
        }



-- Here be the geometry.


roadToGeometry : RoadSection -> G.Road
roadToGeometry road =
    { startAt =
        { x = Length.inMeters <| xCoordinate <| road.startPoint
        , y = Length.inMeters <| yCoordinate <| road.startPoint
        }
    , endsAt =
        { x = Length.inMeters <| xCoordinate <| road.endPoint
        , y = Length.inMeters <| yCoordinate <| road.endPoint
        }
    }


lookForSmoothBendOption :
    Float
    -> TrackLoaded msg
    -> Int
    -> Int
    -> Maybe SmoothedBend
lookForSmoothBendOption trackPointSpacing track pointA pointD =
    let
        ( roadAB, roadCD ) =
            ( DomainModel.asRecord <| DomainModel.leafFromIndex pointA track.trackTree
            , DomainModel.asRecord <| DomainModel.leafFromIndex (pointD - 1) track.trackTree
            )

        -- Try to make minimal changes from v1. Is that wise?
        ( roadIn, roadOut ) =
            ( roadToGeometry roadAB, roadToGeometry roadCD )

        arcFinderGeneral p =
            if isBefore roadIn p && isAfter roadOut p then
                divergentRoadsArc p roadAB roadCD

            else if isAfter roadIn p && isBefore roadOut p then
                convergentRoadsArc p roadAB roadCD

            else
                Nothing

        maybeArc =
            case findIntercept roadIn roadOut of
                Nothing ->
                    parallelFindSemicircle roadAB roadCD

                Just p ->
                    arcFinderGeneral p
    in
    case maybeArc of
        Just arc ->
            Just
                { nodes = makeSmoothBend trackPointSpacing roadAB roadCD arc
                , centre = Arc2d.centerPoint arc
                , radius = Length.inMeters <| Arc2d.radius arc
                , startIndex = pointA
                , endIndex = pointD
                }

        Nothing ->
            Nothing


withElevation : Float -> Point2d Length.Meters LocalCoords -> Point3d Meters LocalCoords
withElevation elevation p2 =
    let
        { x, y } =
            Point2d.toMeters p2
    in
    Point3d.fromMeters { x = x, y = y, z = elevation }


makeSmoothBend :
    Float
    -> RoadSection
    -> RoadSection
    -> Arc2d Meters LocalCoords
    -> List EarthPoint
makeSmoothBend trackPointSpacing roadAB roadCD arc =
    -- Note return list here includes points A and D.
    let
        trueArcLength =
            (abs <| Angle.inRadians <| Arc2d.sweptAngle arc)
                * (Length.inMeters <| Arc2d.radius arc)

        numberPointsOnArc =
            ceiling <| trueArcLength / trackPointSpacing

        segments =
            Arc2d.segments (numberPointsOnArc - 1) arc
                |> Polyline2d.segments

        realArcLength =
            List.sum <| List.map (inMeters << LineSegment2d.length) segments

        ( p1, p2 ) =
            -- The first (last) tangent point is also the first (last) point on the arc
            -- so we don't need to pass these as arguments.
            ( Arc2d.startPoint arc |> Point2d.toRecord inMeters
            , Arc2d.endPoint arc |> Point2d.toRecord inMeters
            )

        ( elevationAtA, elevationAtD ) =
            ( Length.inMeters <| zCoordinate roadAB.startPoint
            , Length.inMeters <| zCoordinate roadCD.endPoint
            )

        ( tang1, tang2 ) =
            -- Say the arc entry is at same elevation as end points
            ( Point3d.fromTuple Length.meters ( p1.x, p1.y, elevationAtA )
            , Point3d.fromTuple Length.meters ( p2.x, p2.y, elevationAtD )
            )

        ( entryStraightLength, exitStraightLength ) =
            ( Length.inMeters <| Point3d.distanceFrom roadAB.startPoint tang1
            , Length.inMeters <| Point3d.distanceFrom tang2 roadCD.endPoint
            )

        totalNewLength =
            -- if we ignore gradient for now
            entryStraightLength + realArcLength + exitStraightLength

        ( tangent1Elevation, tangent2Elevation ) =
            ( elevationAtA + (entryStraightLength / totalNewLength) * (elevationAtD - elevationAtA)
            , elevationAtD + (exitStraightLength / totalNewLength) * (elevationAtA - elevationAtD)
            )

        ( newEntryPoint, newExitPoint ) =
            ( Point3d.translateBy
                (Vector3d.fromMeters { x = 0, y = 0, z = tangent1Elevation - elevationAtA })
                tang1
            , Point3d.translateBy
                (Vector3d.fromMeters { x = 0, y = 0, z = tangent2Elevation - elevationAtD })
                tang2
            )

        eleIncrement =
            (tangent2Elevation - tangent1Elevation) / (toFloat numberPointsOnArc - 1)

        elevate point2d i =
            withElevation
                (tangent1Elevation + toFloat i * eleIncrement)
                point2d

        newArcPoints =
            List.map2
                elevate
                (List.map LineSegment2d.startPoint <| List.drop 1 segments)
                (List.range 1 (numberPointsOnArc - 1))

        newEarthPoints =
            [ roadAB.startPoint, newEntryPoint ]
                ++ newArcPoints
                ++ [ newExitPoint, roadCD.endPoint ]
    in
    newEarthPoints


toPlanarPoint : EarthPoint -> G.Point
toPlanarPoint pt =
    let
        { x, y, z } =
            Point3d.toRecord inMeters pt
    in
    { x = x, y = y }


divergentRoadsArc : G.Point -> RoadSection -> RoadSection -> Maybe (Arc2d Meters LocalCoords)
divergentRoadsArc p r1 r2 =
    let
        ( ( pa, pb ), ( pc, pd ) ) =
            ( ( toPlanarPoint r1.startPoint
              , toPlanarPoint r1.endPoint
              )
            , ( toPlanarPoint r2.startPoint
              , toPlanarPoint r2.endPoint
              )
            )

        ( midAB, midCD ) =
            ( interpolateLine 0.5 pa pb, interpolateLine 0.5 pc pd )

        ( r1Equation, r2Equation ) =
            ( lineEquationFromTwoPoints pa pb, lineEquationFromTwoPoints pc pd )

        ( firstTangentPoint, secondTangentPoint ) =
            -- For divergence, choose midpoint farthest from interesct p.
            if distance p midAB >= distance p midCD then
                ( midAB, pointAlongRoad (pointsToGeometry p pc) (distance p midAB) )

            else
                ( pointAlongRoad (pointsToGeometry p pb) (distance p midCD), midCD )

        ( perpFromFirstTangentPoint, perpFromSecondTangentPoint ) =
            ( linePerpendicularTo r1Equation firstTangentPoint, linePerpendicularTo r2Equation secondTangentPoint )

        circleCenter =
            lineIntersection perpFromFirstTangentPoint perpFromSecondTangentPoint

        findArc : G.Point -> Maybe (Arc2d Meters LocalCoords)
        findArc centre =
            let
                radius =
                    distance centre firstTangentPoint

                bisectorAsRoad =
                    { startAt = p, endsAt = centre }

                midArcPoint =
                    pointAlongRoad
                        bisectorAsRoad
                        (radius + distance p centre)
            in
            Arc2d.throughPoints
                (Point2d.meters firstTangentPoint.x firstTangentPoint.y)
                (Point2d.meters midArcPoint.x midArcPoint.y)
                (Point2d.meters secondTangentPoint.x secondTangentPoint.y)
    in
    Maybe.withDefault Nothing <| Maybe.map findArc circleCenter


convergentRoadsArc : G.Point -> RoadSection -> RoadSection -> Maybe (Arc2d Meters LocalCoords)
convergentRoadsArc p r1 r2 =
    let
        ( ( pa, pb ), ( pc, pd ) ) =
            ( ( toPlanarPoint r1.startPoint
              , toPlanarPoint r1.endPoint
              )
            , ( toPlanarPoint r2.startPoint
              , toPlanarPoint r2.endPoint
              )
            )

        ( midAB, midCD ) =
            ( interpolateLine 0.5 pa pb, interpolateLine 0.5 pc pd )

        ( r1Equation, r2Equation ) =
            ( lineEquationFromTwoPoints pa pb, lineEquationFromTwoPoints pc pd )

        ( firstTangentPoint, secondTangentPoint ) =
            if distance p midAB <= distance p midCD then
                ( midAB, pointAlongRoad (pointsToGeometry p pd) (distance p midAB) )

            else
                ( pointAlongRoad (pointsToGeometry p pa) (distance p midCD), midCD )

        ( perpFromFirstTangentPoint, perpFromSecondTangentPoint ) =
            ( linePerpendicularTo r1Equation firstTangentPoint, linePerpendicularTo r2Equation secondTangentPoint )

        circleCenter =
            lineIntersection perpFromFirstTangentPoint perpFromSecondTangentPoint

        findArc centre =
            let
                radius =
                    distance centre firstTangentPoint

                bisectorAsRoad =
                    { startAt = centre, endsAt = p }

                midArcPoint =
                    pointAlongRoad bisectorAsRoad radius
            in
            Arc2d.throughPoints
                (Point2d.meters firstTangentPoint.x firstTangentPoint.y)
                (Point2d.meters midArcPoint.x midArcPoint.y)
                (Point2d.meters secondTangentPoint.x secondTangentPoint.y)
    in
    Maybe.withDefault Nothing <| Maybe.map findArc circleCenter


parallelFindSemicircle : RoadSection -> RoadSection -> Maybe (Arc2d Meters LocalCoords)
parallelFindSemicircle r1 r2 =
    let
        ( ( pa, pb ), ( pc, pd ) ) =
            ( ( toPlanarPoint r1.startPoint
              , toPlanarPoint r1.endPoint
              )
            , ( toPlanarPoint r2.startPoint
              , toPlanarPoint r2.endPoint
              )
            )

        ( midAB, midBC ) =
            ( interpolateLine 0.5 pa pb
            , interpolateLine 0.5 pb pc
            )

        ( midCD, midDA ) =
            ( interpolateLine 0.5 pc pd
            , interpolateLine 0.5 pd pa
            )

        middle =
            -- As lines are parallel, we can use this as the circle centre.
            interpolateLine 0.5 midBC midDA

        centreLine =
            { startAt = middle, endsAt = midBC }

        ( r1Equation, r2Equation ) =
            ( lineEquationFromTwoPoints pa pb, lineEquationFromTwoPoints pc pd )

        ( radiusToFirstTangentPoint, radiusToSecondTangentPoint ) =
            ( linePerpendicularTo r1Equation middle, linePerpendicularTo r2Equation middle )

        ( firstTangentPoint, secondTangentPoint ) =
            ( lineIntersection r1Equation radiusToFirstTangentPoint
            , lineIntersection r2Equation radiusToSecondTangentPoint
            )
    in
    case ( firstTangentPoint, secondTangentPoint ) of
        ( Just t1, Just t2 ) ->
            let
                radius =
                    distance middle t1

                midArcPoint =
                    pointAlongRoad centreLine radius
            in
            Arc2d.throughPoints
                (Point2d.meters t1.x t1.y)
                (Point2d.meters midArcPoint.x midArcPoint.y)
                (Point2d.meters t2.x t2.y)

        _ ->
            Nothing
