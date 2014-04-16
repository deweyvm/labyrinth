{-# LANGUAGE ScopedTypeVariables, ViewPatterns, MultiParamTypeClasses #-}
{-|
Module      : Labyrinth.Path
Description : pathfinding
Copyright   : (c) deweyvm 2014
License     : MIT
Maintainer  : deweyvm
Stability   : experimental
Portability : unknown

Implementation of the A* pathfinding algorithm.
-}
module Labyrinth.Path(pfind, PathGraph(..), Metric(..), Solid(..)) where

import Prelude hiding(elem, all)
import Control.Applicative
import Data.Maybe
import qualified Data.Map as Map
import Data.Foldable(minimumBy)
import qualified Data.PSQueue as Q
import qualified Data.Set as Set
import Labyrinth.Util


class PathGraph a b where
    getNeighbors :: a -> b -> [(b, Float)]

class Metric a where
    guessLength :: a -> a -> Float

class Solid a where
    isSolid :: a -> Bool


mkPath :: (Metric a, Ord a) => a -> a -> Path a
mkPath initial goal = Path Set.empty
                           (Map.singleton initial 0)
                           (Q.singleton initial $ guessLength initial goal)
                           Map.empty
                           goal


data Path b = Path (Set.Set b)       -- ClosedSet
                   (Map.Map b Float) -- g scoroe
                   (Q.PSQ b Float) -- f score, open set
                   (Map.Map b b)     -- PathSoFar
                   b                 -- goal node

rewindPath :: Ord b => Map.Map b b -> b -> [b] -> [b]
rewindPath path end sofar =
    case Map.lookup end path of
        Just next -> rewindPath path next (end:sofar)
        Nothing -> sofar


getMin :: (Ord a, Ord b) => Map.Map a b -> Set.Set a -> Maybe (a, Set.Set a)
getMin fs set =
    let pairs = Set.map (\s -> ((,) s) <$> (Map.lookup s fs)) set in
    let lst = (catMaybes . Set.toList) pairs in
    if length lst == 0
    then Nothing
    else let elt = fst (minimumBy (\(_, y1) (_, y2) -> compare y1 y2) lst) in
         Just (elt, Set.delete elt set)


pathHelper :: forall a b.(Ord b, Metric b, PathGraph a b) => a -> Path b -> Either String [b]
pathHelper coll (Path closedSet gs fsop path goal) =
    case Q.minView fsop of
        Just (current, newOpen) -> processCurrent (Q.key current) newOpen
        Nothing -> Left "Found no path"
    where processCurrent :: b -> Q.PSQ b Float -> Either String [b]
          processCurrent currentNode open =
              let newClosed = Set.insert currentNode closedSet in
              if currentNode == goal
              then Right $ rewindPath path goal []
              else let ns = getNeighbors coll currentNode
                       (gs', fsop', path') = foldl (updatePath goal currentNode newClosed) (gs, open, path) (fst <$> ns) in
                       pathHelper coll (Path newClosed gs' fsop' path' goal)

qMember :: (Ord a, Ord b) => a -> Q.PSQ a b -> Bool
qMember = isJust .: Q.lookup

updatePath :: (Ord b, Metric b)
           => b
           -> b
           -> Set.Set b
           -> (Map.Map b Float, Q.PSQ b Float, Map.Map b b)
           -> b
           -> (Map.Map b Float, Q.PSQ b Float, Map.Map b b)
updatePath goal current closed s@(g, fo, p) n =
    if Set.member n closed
    then s
    else case Map.lookup current g of
        Just tg ->
            let tg' = tg + guessLength n current in
            if tg' < tg || qMember n fo
            then let newPath = Map.insert n current p in
                 let newGs = Map.insert n tg' g in
                 let newFsop = Q.insert n (tg' + guessLength n goal) fo in
                 (newGs, newFsop, newPath)
            else s
        Nothing -> s

-- | Find /a/ shortest path from the initial node to the goal node
pfind :: (Ord b, Metric b, PathGraph a b)
      => a                 -- ^ The graph to be traversed
      -> b                 -- ^ The initial node
      -> b                 -- ^ The goal node
      -> Either String [b] {- ^ Either a string explaining why a path could
                                not be found, or the found shortest path in
                                order from initial to goal.-}
pfind graph initial goal = pathHelper graph $ mkPath initial goal
