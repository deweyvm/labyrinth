{-# LANGUAGE ScopedTypeVariables, ViewPatterns #-}
{-|
Module      : Labyrinth.Flood
Description : flood filling
Copyright   : (c) deweyvm 2014
License     : MIT
Maintainer  : deweyvm
Stability   : experimental
Portability : unknown

Implementation of flood fill for arbitrary graphs.
-}
module Labyrinth.Flood(floodFill, floodAll, simpleFloodAll, getDepth, getNode) where

import Control.Monad
import Control.Applicative
import qualified Data.Set as Set
import qualified Data.Sequence as Seq
import Labyrinth.PathGraph
data FloodNode a = FloodNode Int a

getDepth :: FloodNode a -> Int
getDepth (FloodNode i _) = i

getNode :: FloodNode a -> a
getNode (FloodNode _ x) = x

data Flood a = Flood (Set.Set (FloodNode a)) (Seq.Seq a)

instance Eq a => Eq (FloodNode a) where
    (FloodNode _ x) == (FloodNode _ y) = x == y

instance Ord a => Ord (FloodNode a) where
    compare (FloodNode _ x) (FloodNode _ y) = compare x y

mkFlood :: a -> Flood a
mkFlood = liftM2 Flood (Set.singleton . (FloodNode 0)) Seq.singleton

floodFill :: (PathGraph a b, Ord b, Show b) => a -> b -> Set.Set (FloodNode b)
floodFill graph pt = floodHelper graph 0 $ mkFlood pt


floodHelper :: (PathGraph a b, Ord b, Show b) => a -> Int -> Flood b -> Set.Set (FloodNode b)
floodHelper _ _ (Flood pts (Seq.viewl -> Seq.EmptyL)) = pts
floodHelper graph depth (Flood pts (Seq.viewl -> pt Seq.:< work)) =
    floodHelper graph (depth + 1) (Flood full q)
    where q = (Seq.fromList ns) Seq.>< work
          full = Set.union pts (Set.fromList lst)
          ns = filter (\x -> not (Set.member (FloodNode 0 x) pts)) $ fst <$> getNeighbors graph pt
          lst = zipWith ($) (FloodNode <$> (repeat depth)) ns


floodAll :: (PathGraph a b, Ord b, Show b)
         => a                  -- ^ the grid to be flooded
         -> Set.Set b   -- ^ get all clear elements from the graph
         -> [Set.Set (FloodNode b)] -- ^ the resulting flooded regions
floodAll graph open = floodAllHelper graph open []


hackdiff :: (Ord b) => Set.Set (FloodNode b) -> Set.Set b -> Set.Set b
hackdiff s r = Set.difference r (Set.map getNode s)

floodAllHelper :: (PathGraph a b, Ord b, Show b)
               => a
               -> Set.Set b
               -> [Set.Set (FloodNode b)]
               -> [Set.Set (FloodNode b)]
floodAllHelper graph open sofar =
    case Set.minView open of
        Just (x, _) -> let filled = floodFill graph x in
                       let newOpen = hackdiff filled open in
                       floodAllHelper graph newOpen (filled:sofar)
        Nothing -> sofar

simpleFloodAll :: (PathGraph a b, Ord b, Show b)
               => a
               -> Set.Set b
               -> [Set.Set b]
simpleFloodAll graph open =
    let flooded = floodAll graph open in
    (Set.map getNode) <$> flooded
