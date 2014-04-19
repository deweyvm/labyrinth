{-# LANGUAGE ScopedTypeVariables, ViewPatterns, FlexibleContexts #-}
{-|
Module      : Labyrinth.Pathing.JumpPoint
Description : flood filling
Copyright   : (c) deweyvm 2014
License     : MIT
Maintainer  : deweyvm
Stability   : experimental
Portability : unknown

Implementation of jump point search optimization of the A* (A star) search
algorithm.
-}
module Labyrinth.Pathing.JumpPoint(pfind) where

import Prelude hiding (any)
import Control.Applicative
import qualified Data.PSQueue as Q
import Data.Foldable(any)
import Data.Maybe
import qualified Data.Set as Set
import qualified Data.Map as Map
import Labyrinth.PathGraph
import Labyrinth.Util
import Labyrinth.Data.Array2d
import Labyrinth.Pathing.Util
import Debug.Trace


data Path a = Path (Set.Set a)       -- closed set
                   (Map.Map a Float) -- g score
                   (Q.PSQ a Float)   -- open set, f score
                   (Map.Map a a)     -- parent map
                   a                 -- goal node

mkPath :: Metric Point => Point -> Point -> Path Point
mkPath start goal = Path Set.empty
                         (Map.singleton start 0)
                         (Q.singleton start $ guessLength start goal)
                         Map.empty
                         goal

findNeighbors :: (PathGraph (Array2d a) Point)
              => (Point -> Bool)
              -> Array2d a
              -> Point
              -> Map.Map Point Point
              -> [Point]
findNeighbors checkOpen graph n@(x, y) parents =
    case gatherParent <$> Map.lookup n parents of
      Just lst -> lst
      Nothing -> fst <$> getNeighbors graph n
    where gatherParent :: Point -> [Point]
          gatherParent (px, py) =
           let dir i = i `quot` (max (abs i) 1) in
           let dx = dir (x - px) in
           let dy = dir (y - py) in
           let diag = (dx /= 0 && dy /= 0) in
           let vert = (dx == 0 && checkOpen (x, y + dy)) in
           let horiz = checkOpen (x + dx, y) in
           let sel = select Nothing . Just in
           if diag
           then let v0 = sel (x, y + dy)
                             (checkOpen (x, y + dy)) in
                let v1 = sel (x + dx, y)
                             (checkOpen (x + dx, y)) in
                let v2 = sel (x + dx, y + dy)
                             (checkOpen (x + dx, y + dy) || checkOpen (x + dx, y)) in
                let v3 = sel (x - dx, y + dy)
                             ((not . checkOpen) (x - dx, y) && checkOpen (x, y + dy)) in
                let v4 = sel (x + dx, y - dy)
                             ((not . checkOpen) (x, y - dy) && checkOpen (x + dx, y)) in
                catMaybes [v0, v1, v2, v3, v4]
           else if vert
           then let t0 = sel (x, y + dy) True in
                let t1 = sel (x + 1, y + dy) $ (not . checkOpen) (x + 1, y) in
                let t2 = sel (x - 1, y + dy) $ (not . checkOpen) (x - 1, y) in
                catMaybes [t0, t1, t2]
           else if horiz
           then let u0 = sel (x + dx, y) True in
                let u1 = sel (x + dx, y + 1) $ (not . checkOpen) (x, y + 1) in
                let u2 = sel (x + dx, y - 1) $ (not . checkOpen) (x, y - 1) in
                catMaybes [u0, u1, u2]
           else []


jump :: (Point -> Bool) -> Point -> Point -> Point -> Maybe Point
jump checkOpen goal pt@(x, y) (px, py) =
    let jp = Just pt in
    let dx = x - px in
    let dy = y - py in
    let currentOpen = checkOpen (x, y) in
    let atEnd = pt == goal in
    let check p q r s  = (checkOpen p && (not . checkOpen) q) ||
                         (checkOpen r && (not . checkOpen) s) in
    let diagonal = dx /= 0 && dy /= 0 && check (x - dx, y + dy)
                                               (x - dx, y)
                                               (x + dx, y - dy)
                                               (x, y - dy) in
    let horiz = dx /= 0 && check (x + dx, y + 1)
                                 (x, y + 1)
                                 (x + dx, y - 1)
                                 (x, y - 1) in
    let vert = check (x + 1, y + dy)
                     (x + 1, y)
                     (x - 1, y + dy)
                     (x - 1, y) in
    let recJump = dx /= 0 && dy /= 0 &&
                  ((isJust .: jump checkOpen goal) (x + dx, y) (x, y) ||
                   (isJust .: jump checkOpen goal) (x, y + dy) (x, y)) in
    let forward = checkOpen (x + dx, y) || checkOpen (x, y + dy) in
    if (not currentOpen) || dx == 0 && dy == 0
    then Nothing
    else if (atEnd || diagonal || horiz || vert || recJump)
    then jp
    else if (forward)
    then jump checkOpen goal (x + dx, y + dy) (x, y)
    else Nothing

pathHelper :: (Metric Point, Open a, PathGraph (Array2d a) Point)
           => Array2d a
           -> Path Point
           -> Either String [Point]
pathHelper graph (Path closedSet gs fsop path goal) =
    case Q.minView fsop of
        Just (current, newOpen) -> processCurrent (Q.key current) newOpen
        Nothing -> Left "Found no path"
    where processCurrent currentNode open =
              let checkOpen pt = any isOpen $ geti graph pt in
              let newClosed = Set.insert currentNode closedSet in
              if currentNode == goal
              then Right $ rewindPath path goal []
              else let ns = findNeighbors checkOpen graph currentNode path
                       (gs', fsop', path') = foldl (updatePath checkOpen goal currentNode newClosed) (gs, open, path) ns in
                       pathHelper graph (Path newClosed gs' fsop' path' goal)

--todo: can factor out Array2d a with functional dependency
updatePath :: (Metric Point)
           => (Point -> Bool)
           -> Point
           -> Point
           -> Set.Set Point
           -> (Map.Map Point Float, Q.PSQ Point Float, Map.Map Point Point)
           -> Point
           -> (Map.Map Point Float, Q.PSQ Point Float, Map.Map Point Point)
updatePath checkOpen goal current closed s@(gs, fs, p) nnode = --warning, node cost is ignored, cost must be uniform for this algorithm

    let jMaybe = jump checkOpen goal nnode current in
    case jMaybe of
        Just jumpPoint | Set.notMember jumpPoint closed ->
            let d = euclid current jumpPoint in
            let g = maybe 0 id (Map.lookup current gs) in
            let g' = g + d in
            let inOpen = qMember jumpPoint fs in
            if (not inOpen || g' < g)
            then let f = (g' + guessLength jumpPoint goal) in
                 let gs' = Map.insert jumpPoint g' gs in
                 let fs' = Q.insert jumpPoint f fs in
                 let p' = Map.insert jumpPoint current p in
                 (gs', fs', p')
            else s
        _ -> s


-- | Find a shortest path from the start node to the goal node
pfind :: (Open a, Metric Point, PathGraph (Array2d a) Point)
      => Array2d a             -- ^ The graph to be traversed
      -> Point                 -- ^ The start node
      -> Point                 -- ^ The goal node
      -> Either String [Point] {- ^ Either a string explaining why a path could
                                not be found, or the found shortest path in
                                order from start to goal.-}
pfind graph start goal = pathHelper graph $ mkPath start goal
