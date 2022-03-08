module Tools.GraphOptions exposing (..)

import BoundingBox3d exposing (BoundingBox3d)
import Dict exposing (Dict)
import DomainModel exposing (PeteTree)
import Length exposing (Meters)
import LocalCoords exposing (LocalCoords)
import Quantity exposing (Quantity)


type Direction
    = Forwards
    | Backwards


type alias XY =
    -- First pass is about detecting revisited points and working out where the edges are.
    -- For that, we build a dictionary indexed by track point position (metric units).
    ( Float, Float )


type alias Options =
    { graph : Maybe Graph
    , pointTolerance : Quantity Float Meters -- How close in metres to consider points equal.
    , minimumEdgeLength : Quantity Float Meters -- So we can ignore short self-loops
    , centreLineOffset : Length.Length
    , boundingBox : BoundingBox3d Length.Meters LocalCoords
    }


type alias Graph =
    { nodes : Dict Int ()
    , edges : Dict Int ( Int, Int, PeteTree )
    , userRoute : List Traversal
    , canonicalRoute : List Traversal
    , selectedTraversal : Maybe Int
    }


type alias Traversal =
    { edge : Int -- Canonical index of edge
    , direction : Direction
    }


type alias Route =
    List Traversal
