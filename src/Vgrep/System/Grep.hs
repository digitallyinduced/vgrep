-- | Utilities for invoking @grep@
{-# LANGUAGE Rank2Types #-}
module Vgrep.System.Grep
    ( grep
    , grepForApp
    , recursiveGrep
    , grepVersion
    ) where

import           Control.Concurrent
import           Control.Monad
import           Control.Monad.IO.Class
import           Data.Maybe
import           Data.Text              (Text)
import qualified Data.Text              as T
import           Pipes                  as P
import qualified Pipes.Prelude          as P
import           System.Environment     (getArgs)
import           System.Exit
import           System.Process

import Vgrep.Parser

import System.IO

-- | Like 'grep', but if the input is not prefixed with a file and line
-- number, i. e. is not valid @grep -nH@ output, then adds @-nH@ (@-n@:
-- with line number, @-H@: with file name) to the @grep@ command line
-- arguments.
grepForApp :: Producer Text IO () -> Producer Text IO ()
grepForApp input = do
    (firstInputLine, input') <- peek input
    when (isNothing firstInputLine) (lift exitFailure)
    case firstInputLine >>= parseLine of
        Just _line -> grep input'
        Nothing    -> grepWithFileAndLineNumber input'

grepWithFileAndLineNumber :: Producer Text IO () -> Producer Text IO ()
grepWithFileAndLineNumber input = do
    args <- liftIO getArgs
    grepPipe (withFileName : withLineNumber : args) input

-- | Takes a 'Text' stream and runs it through a @grep@ process, returning
-- a stream of results. The original command line arguments are passed to
-- the process.
grep :: Producer Text IO () -> Producer Text IO ()
grep input = do
    args <- liftIO getArgs
    grepPipe args input

grepPipe :: [String] -> Producer Text IO () -> Producer Text IO ()
grepPipe args input = do
    (hIn, hOut) <- createGrepProcess (lineBuffered : colorized : args)
    _threadId <- liftIO . forkIO . runEffect $ input >-> textToHandle hIn
    streamResultsFrom hOut

-- | Invokes @grep -nH -rI@ (@-n@: with line number, @-H@: with file name,
-- @-r@: recursive, @-I@: ignore binary files) and returns the results as a
-- stream. More arguments (e. g. pattern and directory) are taken from the
-- command line.
recursiveGrep :: Producer Text IO ()
recursiveGrep = do
    args <- lift getArgs
    let grepArgs = recursive
                 : withFileName
                 : withLineNumber
                 : skipBinaryFiles
                 : lineBuffered
                 : colorized
                 : args
    (_hIn, hOut) <- createGrepProcess grepArgs
    streamResultsFrom hOut

grepVersion :: Producer Text IO ()
grepVersion = do
    (_, hOut) <- createGrepProcess [version]
    streamResultsFrom hOut

recursive, withFileName, withLineNumber, skipBinaryFiles, lineBuffered, colorized, version :: String
recursive       = "-r"
withFileName    = "-H"
withLineNumber  = "-n"
skipBinaryFiles = "-I"
lineBuffered    = "--line-buffered"
colorized       = "--color=always"
version         = "--version"


createGrepProcess :: MonadIO io => [String] -> io (Handle, Handle)
createGrepProcess args = liftIO $ do
    (Just hIn, Just hOut, _hErr, _processHandle) <- createProcess
        (proc "grep" args) { std_in  = CreatePipe, std_out = CreatePipe }
    hSetBuffering hIn  LineBuffering
    hSetBuffering hOut LineBuffering
    pure (hIn, hOut)

streamResultsFrom :: Handle -> Producer Text IO ()
streamResultsFrom handle = do
    (maybeFirstLine, grepOutput) <- peek (textFromHandle handle)
    when (isNothing maybeFirstLine) (lift exitFailure)
    grepOutput


textFromHandle :: MonadIO m => Handle -> Producer' Text m ()
textFromHandle h = P.fromHandle h >-> P.map T.pack

textToHandle :: MonadIO m => Handle -> Consumer' Text m ()
textToHandle h = P.map T.unpack >-> P.toHandle h

peek :: Monad m => Producer a m r -> Producer a m (Maybe a, Producer a m r)
peek producer = do
    eitherNext <- lift (next producer)
    pure $ case eitherNext of
        Left r               -> (Nothing, pure r)
        Right (a, producer') -> (Just a,  P.yield a >> producer')
