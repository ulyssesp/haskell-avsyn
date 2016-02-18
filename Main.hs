{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}

import System.IO
import Control.Concurrent
import Control.Exception (finally)
import Control.Monad
import Control.Monad.IO.Class (liftIO)
import Data.Maybe
import Data.Text (Text)
import Data.Unique
import Data.ByteString.Lazy (ByteString)
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy.Char8 as BSL
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Network.WebSockets as WS
import qualified Network.Wai
import qualified Network.Wai.Handler.Warp as Warp
import qualified Network.Wai.Handler.WebSockets as WaiWS
import qualified Network.Wai.Application.Static as Static
import qualified Sound.OSC as OSC
import AesonOSC
import Rpi
import Cinder
import HoY

type MessageQueue = Chan OSC.Message

-- Server state
type Client = (Unique, WS.Connection)
type ServerState = [Client]

newServerState :: ServerState
newServerState = []

addClient :: Client -> ServerState -> ServerState
addClient client clients = client : clients

removeClient :: Client -> ServerState -> ServerState
removeClient client = filter ((/= fst client) . fst)

-- Socket messaging

broadcast :: ByteString -> ServerState -> IO ()
broadcast message clients = forM_ clients $ \(_, conn) -> WS.sendTextData conn message

broadcastMessages :: [OSC.Message] -> ServerState -> IO ()
broadcastMessages [] __ = return ()
broadcastMessages m state = (broadcast . bundleToJSON . messagesToBundle) m state

bundleToJSON :: OSC.Bundle -> ByteString
bundleToJSON = A.encode . A.toJSON

extractMessages :: ByteString -> [OSC.Message]
extractMessages bs =  messagesFromMaybe $ fmap bundleToMessages $ join . either (const Nothing) Just $ A.eitherDecode bs

messagesFromMaybe :: Maybe [OSC.Message] -> [OSC.Message]
messagesFromMaybe Nothing = []
messagesFromMaybe (Just x) = x

modifyMixer :: MVar Mixer -> ServerState -> OSC.Message -> IO ()
modifyMixer mixerState serverState message = do
    messages <- modifyMVar mixerState (return . applyCinderMessage message)
    sendMessages serverState messages

modifyRpi :: MVar Program -> ServerState -> OSC.Message -> IO ()
modifyRpi rpiState serverState message = do
    messages <- modifyMVar rpiState (return . applyRpiMessage message)
    sendMessages serverState messages

modifyHoY :: MVar HoYProg -> ServerState -> OSC.Message -> IO ()
modifyHoY hoyState serverState message = do
    messages <- modifyMVar hoyState (return . applyHoYMessage message)
    sendMessages serverState messages

sendMessages :: ServerState -> [OSC.Message] -> IO ()
sendMessages serverState messages = do
    print messages
    hFlush stdout
    sendUDPMessages messages
    broadcastMessages messages serverState

receiveSocketMessages :: MVar HoYProg -> WS.Connection -> MVar ServerState -> IO ()
receiveSocketMessages hoyState conn serverState = forever $ do
  (msg :: ByteString) <- WS.receiveData conn
  clients <- readMVar serverState
  let messages = extractMessages msg
  -- mapM_ (modifyRpi rpiState clients) messages
  -- mapM_ (modifyMixer cinderState clients) messages
  mapM_ (modifyHoY hoyState clients) messages

bundleToMessages :: OSC.Bundle -> [OSC.Message]
bundleToMessages = OSC.bundleMessages

messagesToBundle :: [OSC.Message] -> OSC.Bundle
messagesToBundle = OSC.bundle OSC.immediately

-- OSC messaging

udpAddresses :: [String]
udpAddresses = ["127.0.0.1"]

sendUDPMessage :: OSC.Message -> IO ()
sendUDPMessage  message = OSC.withTransport (OSC.openUDP "64.255.16.255" 3334) $ OSC.sendMessage message

sendUDPMessages :: [ OSC.Message ] -> IO ()
sendUDPMessages messages = do
  print messages
  hFlush stdout
  mapM_ (sendUDPBundleToAddress messages) udpAddresses

sendUDPBundleToAddress :: [OSC.Message] -> String -> IO ()
sendUDPBundleToAddress messages address =
  OSC.withTransport (OSC.openUDP address 3334) (OSC.sendBundle $ OSC.Bundle 0.0 messages)

receiveMessageTransport :: IO OSC.UDP -> MessageQueue -> IO ()
receiveMessageTransport t mChan = OSC.withTransport t $ forever $ do
  msg <- OSC.waitMessage
  liftIO $ writeChan mChan msg

receiveMessages :: MessageQueue -> IO ()
receiveMessages = receiveMessageTransport $ OSC.udpServer "0.0.0.0" 3333

handleUDPMessages:: MessageQueue -> MVar ServerState -> MVar HoYProg -> IO ()
handleUDPMessages mChan serverState hoyProg = do
  msg <- readChan mChan
  clients <- readMVar serverState
  handleUDPMessage msg
  print msg
  hFlush stdout
  -- modifyMixer mixer clients msg
  -- modifyRpi program clients msg
  modifyHoY hoyProg clients msg
  handleUDPMessages mChan serverState hoyProg
  where
    handleUDPMessage (OSC.Message a __)
      -- | "/connection" `T.isPrefixOf` T.pack a = do
      --   mixerState <- readMVar hoyProg
      --   sendUDPMessages $ mixerToMessages False mixerState
      | otherwise = return ()

-- Serve webpage and init sockets
server :: MessageQueue -> IO()
server mq = do
  let port = 3000
  putStrLn $ "Listening on port " ++ show port
  serverState <- newMVar newServerState
  hoyState <- newMVar defaultHoYProg

  forkIO $ handleUDPMessages mq serverState hoyState
  sendUDPMessage $ OSC.message "/connection" []
  Warp.run
    port
    $ WaiWS.websocketsOr WS.defaultConnectionOptions (application hoyState serverState) staticApp

staticApp :: Network.Wai.Application
staticApp = Static.staticApp $ Static.defaultWebAppSettings "C:\\Users\\Ulysses\\Development\\avsyn-web-interface\\public"

application :: MVar HoYProg -> MVar ServerState -> WS.ServerApp
application hoyState serverState pending = do
  conn <- WS.acceptRequest pending
  WS.forkPingThread conn 30
  connId <- newUnique
  let client = (connId, conn)
  flip finally (disconnect client) $ do
    liftIO $ modifyMVar_ serverState $ \s -> do
        let s' = addClient client s
        print "Added client"
        hFlush stdout
        return s'
    hoy <- readMVar hoyState
    -- (WS.sendTextData conn) . bundleToJSON . messagesToBundle $ mixerToMessages True mixer
    (WS.sendTextData conn) . (bundleToJSON . messagesToBundle) $ startMessages hoy
    print $ startMessages hoy
    hFlush stdout
    receiveSocketMessages hoyState conn serverState
    where
        startMessages hoy =  hoyProgToMessages hoy
        disconnect client = do
            s <- modifyMVar_ serverState $ \s ->
                let s' = removeClient client s in return s'
            print "Removed client"

main :: IO ()
main = do
  m <- newChan
  forkIO $ receiveMessages m
  server m
