port module MapPortController exposing (..)

import Actions exposing (ToolAction(..))
import Angle
import Direction2d
import DomainModel exposing (..)
import Json.Decode as D exposing (Decoder, field, string)
import Json.Encode as E
import Length
import MapboxKey exposing (mapboxKey)
import SceneBuilderMap
import TrackLoaded exposing (TrackLoaded)


type MapMsg
    = MapPortMessage E.Value


type alias MapInfo =
    -- Mainly used to set the map up.
    { mapZoom : Float -- track values from user map interactions.
    , centreLon : Float
    , centreLat : Float
    }


port mapCommands : E.Value -> Cmd msg


port mapResponses : (E.Value -> msg) -> Sub msg


createMap : MapInfo -> Cmd msg
createMap info =
    mapCommands <|
        E.object
            [ ( "Cmd", E.string "Init" )
            , ( "token", E.string mapboxKey )
            , ( "lon", E.float info.centreLon )
            , ( "lat", E.float info.centreLat )
            , ( "zoom", E.float info.mapZoom )
            ]


refreshMap : Cmd msg
refreshMap =
    mapCommands <|
        E.object
            [ ( "Cmd", E.string "Repaint" )
            , ( "token", E.string mapboxKey )
            ]


centreMap :
    { m
        | trackTree : Maybe PeteTree
        , renderDepth : Int
        , currentPosition : Int
        , referenceLonLat : GPXSource
    }
    -> Cmd msg
centreMap model =
    -- Centre map
    case model.trackTree of
        Just tree ->
            let
                { longitude, latitude, altitude } =
                    earthPointFromIndex model.currentPosition tree
                        |> gpxFromPointWithReference model.referenceLonLat
            in
            mapCommands <|
                E.object
                    [ ( "Cmd", E.string "Centre" )
                    , ( "token", E.string mapboxKey )
                    , ( "lon", E.float <| Angle.inDegrees <| Direction2d.toAngle longitude )
                    , ( "lat", E.float <| Angle.inDegrees latitude )
                    ]

        Nothing ->
            Cmd.none


centreMapOnCurrent : TrackLoaded msg -> Cmd msg
centreMapOnCurrent track =
    let
        { longitude, latitude, altitude } =
            gpxPointFromIndex track.currentPosition track.trackTree
    in
    mapCommands <|
        E.object
            [ ( "Cmd", E.string "Centre" )
            , ( "token", E.string mapboxKey )
            , ( "lon", E.float <| Angle.inDegrees <| Direction2d.toAngle longitude )
            , ( "lat", E.float <| Angle.inDegrees latitude )
            ]



{-
   deferredMapRepaint msgWrapper =
       -- This is now in JS, where it quietly just works.
       after 50 (RepaintMap |> msgWrapper)
-}


update :
    MapMsg
    -> TrackLoaded msg
    -> List (ToolAction msg)
update mapMsg track =
    case mapMsg of
        MapPortMessage value ->
            processMapPortMessage track value



--toggleDragging : Bool -> Track -> Cmd msg
--toggleDragging isDragging track =
--    commandPort <|
--        E.object
--            [ ( "Cmd", E.string "Drag" )
--            , ( "Enable", E.bool isDragging )
--            , ( "points", trackPointsToJSON track ) -- Make track points draggable
--            ]
--requestElevations : Cmd msg
--requestElevations =
--    commandPort <|
--        E.object
--            [ ( "Cmd", E.string "Elev" )
--            ]


addTrackToMap : TrackLoaded msg -> Cmd msg
addTrackToMap track =
    -- This is to add the route as a polyline.
    -- We will separately add track points as draggable features.
    let
        { longitude, latitude, altitude } =
            gpxPointFromIndex track.currentPosition track.trackTree
    in
    mapCommands <|
        E.object
            [ ( "Cmd", E.string "Track" )
            , ( "token", E.string mapboxKey )
            , ( "lon", E.float <| Angle.inDegrees <| Direction2d.toAngle longitude )
            , ( "lat", E.float <| Angle.inDegrees latitude )
            , ( "zoom", E.float 10.0 )
            , ( "data", SceneBuilderMap.renderMapJson track ) -- Route as polyline
            , ( "points", E.null ) --trackPointsToJSON track ) -- Make track points draggable
            ]


showPreview : String -> String -> String -> E.Value -> Cmd msg
showPreview tag shape colour geoJson =
    mapCommands <|
        E.object
            [ ( "Cmd", E.string "ShowPreview" )
            , ( "token", E.string mapboxKey )
            , ( "label", E.string tag )
            , ( "shape", E.string shape )
            , ( "colour", E.string colour )
            , ( "data", geoJson )
            ]


hidePreview : String -> Cmd msg
hidePreview tag =
    mapCommands <|
        E.object
            [ ( "Cmd", E.string "HidePreview" )
            , ( "token", E.string mapboxKey )
            , ( "label", E.string tag )
            ]


addMarkersToMap :
    TrackLoaded msg
    -> Cmd msg
addMarkersToMap track =
    let
        encodePos { longitude, latitude, altitude } =
            E.object
                [ ( "lon", E.float <| Angle.inDegrees <| Direction2d.toAngle longitude )
                , ( "lat", E.float <| Angle.inDegrees latitude )
                ]
    in
    mapCommands <|
        E.object
            [ ( "Cmd", E.string "Mark" )
            , ( "orange", encodePos <| gpxPointFromIndex track.currentPosition track.trackTree )
            , case track.markerPosition of
                Just mark ->
                    ( "purple", encodePos <| gpxPointFromIndex mark track.trackTree )

                Nothing ->
                    ( "ignore", E.null )
            , ( "previews", E.null )
            ]


msgDecoder : Decoder String
msgDecoder =
    field "msg" string


processMapPortMessage :
    TrackLoaded msg
    -> E.Value
    -> List (ToolAction msg)
processMapPortMessage track json =
    let
        jsonMsg =
            D.decodeValue msgDecoder json

        ( lat, lon ) =
            ( D.decodeValue (D.field "lat" D.float) json
            , D.decodeValue (D.field "lon" D.float) json
            )
    in
    case jsonMsg of
        Ok "click" ->
            --{ 'msg' : 'click'
            --, 'lat' : e.lat()
            --, 'lon' : e.lon()
            --} );
            case ( lat, lon ) of
                ( Ok lat1, Ok lon1 ) ->
                    let
                        gpxPoint =
                            { longitude = Direction2d.fromAngle <| Angle.degrees lon1
                            , latitude = Angle.degrees lat1
                            , altitude = Length.meters 0.0
                            }

                        index =
                            DomainModel.nearestToLonLat gpxPoint track.trackTree
                    in
                    [ SetCurrentFromMapClick index ]

                _ ->
                    []

        --( Ok "drag", Just track ) ->
        --    case draggedOnMap json track of
        --        Just undoEntry ->
        --            processPostUpdateAction
        --                model
        --                (PostUpdateActions.ActionTrackChanged TrackEditType.EditPreservesIndex undoEntry)
        --
        --        Nothing ->
        --            ( Model model, Cmd.none )
        --
        --( Ok "elevations", Just track ) ->
        --    case elevations of
        --        Ok mapElevations ->
        --            processPostUpdateAction model
        --                (PostUpdateActions.ActionTrackChanged
        --                    TrackEditType.EditPreservesIndex
        --                    (RotateRoute.buildMapElevations mapElevations track)
        --                )
        --
        --        _ ->
        --            ( Model model, Cmd.none )
        _ ->
            []
