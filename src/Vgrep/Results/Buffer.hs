module Vgrep.Results.Buffer
    ( module Vgrep.Results
    , DisplayLine(..)
    , Buffer
    , buffer
    , showPrev, showNext
    , hidePrev, hideNext
    , moveUp, moveDown
    , resize
    , toLines
    , current
    ) where

import           Control.Applicative
import           Data.Sequence ( Seq , (<|), (|>)
                               , ViewL(..), ViewR(..)
                               , viewl, viewr )
import qualified Data.Sequence as S
import           Data.Foldable
import           Data.Function
import           Data.List (groupBy)
import           Data.Monoid
import           Prelude hiding (reverse)

import Vgrep.Results


type Buffer = ( [FileLineReference]    -- above screen (reversed)
              , Seq FileLineReference  -- top of screen (reversed)
              , FileLineReference      -- currently selected
              , Seq FileLineReference  -- bottom of screen
              , [FileLineReference] )  -- below screen

data DisplayLine = FileHeader   File
                 | Line         LineReference
                 | SelectedLine LineReference
                 deriving (Eq)


buffer :: [FileLineReference] -> Maybe Buffer
buffer (ref : refs) = Just ([], empty, ref, empty, refs)
buffer []           = Nothing

reverse :: Buffer -> Buffer
reverse (as, bs, c, ds, es) = (es, ds, c, bs, as)

showNext :: Buffer -> Maybe Buffer
showNext (as, bs, c, ds, es) = do e:es' <- Just es
                                  Just (as, bs, c, ds |> e, es')
showPrev :: Buffer -> Maybe Buffer
showPrev = fmap reverse . showNext . reverse

hideNext :: Buffer -> Maybe Buffer
hideNext (as, bs, c, ds, es) = do ds' :> d <- Just (viewr ds)
                                  Just (as, bs, c, ds', d:es)

hidePrev :: Buffer -> Maybe Buffer
hidePrev = fmap reverse . hideNext . reverse

moveDown :: Buffer -> Maybe Buffer
moveDown (as, bs, c, ds, es) = do d :< ds' <- Just (viewl ds)
                                  Just (as, c <| bs, d, ds', es)

moveUp :: Buffer -> Maybe Buffer
moveUp = fmap reverse . moveDown . reverse

resize :: Int -> Buffer -> Buffer
resize height buf
    | visibleHeight buf < height
    = maybe buf (resize height) (showNext buf)

    | visibleHeight buf > height
    = maybe buf (resize height) (hidePrev buf <|> hideNext buf)

    | otherwise
    = buf

visibleHeight :: Buffer -> Int
visibleHeight = length . toLines

toLines :: Buffer -> [DisplayLine]
toLines (_, bs, c, ds, _) = case viewl bs of
    EmptyL -> header c <> selected c <> go ds
    b :< _ | fst b == fst c
           -> go (S.reverse bs) <> selected c <> go ds
           | otherwise
           -> go (S.reverse bs) <> header c <> selected c <> go ds
  where
    go :: Seq FileLineReference -> [DisplayLine]
    go refs = do
        fileResults <- groupBy ((==) `on` fst) (toList refs)
        header (head fileResults) <> fmap (Line . snd) fileResults
    header   = pure . FileHeader   . fst
    selected = pure . SelectedLine . snd


current :: Buffer -> FileLineReference
current (_, _, c, _, _) = c