{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cinder (Mixer, newCinderState, applyCinderMessage, mixerToMessages) where

import Control.Lens
import Data.Data
import Data.Either
import Data.Int
import Data.List
import Data.Maybe
import Data.Typeable
import GHC.Float
import qualified Data.ByteString.Char8 as BSC
import qualified Sound.OSC as OSC

data Mixer = Mixer { _mixControls :: [Control]
                   , _mixChoiceA :: ChoiceVis
                   , _mixChoiceB :: ChoiceVis
                   , _mixVisualizations :: [Visualization]
                   } deriving (Show)

data ChoiceVis = ChoiceVis { _choiceVisualization :: String
                           , _choiceChoiceControl :: ChoiceCon
                           , _choiceControls :: [Control]
                           , _choiceSliders :: [Control]
                           } deriving (Show)

data Visualization = Visualization { _visName :: String
                                   , _visControls :: [Control]
                                   } deriving (Show)

data Slider = Slider { _controlSliderName :: String
                     , _controlSliderValue :: Float
                     , _controlSliderMin :: Float
                     , _controlSliderMax :: Float
                     } deriving (Show)

data Toggle = Toggle { _controlToggleName :: String
                     , _controlToggleValue :: Float
                     } deriving (Show)

data ChoiceCon = ChoiceCon { _controlChoiceName :: String
                           , _controlChoiceValue :: String
                           , _controlChoiceChoices :: [String]
                           } deriving (Show)

data Control = ControlSlider Slider
  | ControlToggle Toggle
  | ControlChoice ChoiceCon
  deriving (Show)

defaultChoiceVis :: ChoiceVis
defaultChoiceVis = ChoiceVis { _choiceVisualization = "Blank"
                             , _choiceChoiceControl = ChoiceCon "Vises" "Blank" $ map _visName defaultVisualizations
                             , _choiceControls =
                                [ ControlToggle $ Toggle "Apply Effects" 1
                                , ControlToggle $ Toggle "Fade Transition" 0
                                , ControlToggle $ Toggle "Mirror" 0
                                , ControlSlider $ Slider "Fade" 0 0 1
                                , ControlSlider $ Slider "Effect Fade" 0 0 1
                                , ControlSlider $ Slider "Scale" 1 0.85 1.15
                                , ControlSlider $ Slider "Offset Y" 0 ( -0.15 ) 0.15
                                , ControlSlider $ Slider "Hue Shift" 0 0 1
                                , ControlSlider $ Slider "Hue Shift Cycle" 0 0 0.25
                                , ControlSlider $ Slider "Saturation Shift" 0 0 1
                                , ControlSlider $ Slider "Lightness Shift" 1 0 2
                                , ControlSlider $ Slider "Beat Expand" 0 (-0.5) 0.5
                                , ControlSlider $ Slider "Beat Rotate" 0 (-0.3) 0.3
                                , ControlSlider $ Slider "Rotate" 0 (-0.3) 0.3
                                ]
                             , _choiceSliders = []}

defaultVisualizations :: [Visualization]
defaultVisualizations = [ Visualization { _visName="Blank", _visControls=[]}
                        , Visualization { _visName="Simple"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2
                                                       , ControlSlider $ Slider "Hole Size"  0.2 0 1
                                                       ]}
                        , Visualization { _visName="Circular"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2]}
                        , Visualization { _visName="Dots"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2]}
                        , Visualization { _visName="Buffer"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2]}
                        , Visualization { _visName="Rotate"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2]}
                        , Visualization { _visName="Lights"
                                        , _visControls=[ ControlSlider $ Slider "Frequency" 1 0 4]}
                        , Visualization { _visName="EQPointCloud"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 0.25 0 2
                                                       , ControlSlider $ Slider "Rotation Speed" 1 0 2]}
                        , Visualization { _visName="Neurons"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2]}
                        , Visualization { _visName="Smoke"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2
                                                       , ControlSlider $ Slider "Speed" 2 0.5 4]}
                        , Visualization { _visName="Flocking"
                                        , _visControls=[ ControlSlider $ Slider "Volume" 1 0 2
                                                       , ControlSlider $ Slider "Beat Constant" 1.4 1.1 2
                                                       , ControlSlider $ Slider "Speed" 1.4 1.1 2
                                                       , ControlSlider $ Slider "Roaming Distance" 40 20 120
                                                       , ControlSlider $ Slider "Separation Distance" 12 0 30
                                                       , ControlSlider $ Slider "Cohesion Distance" 12 0 30
                                                       , ControlSlider $ Slider "Alignment Distance" 12 0 30
                                                       ]}
                        , Visualization { _visName="Particles"
                                        , _visControls=[]}
                        ]

newCinderState :: Mixer
newCinderState = Mixer {  _mixControls=[ ControlSlider $ Slider "Fade" 0.5 0 1
                                       , ControlSlider $ Slider "Add" 0.2 0 2
                                       , ControlSlider $ Slider "Multiply" 6 0 6
                                       , ControlSlider $ Slider "Beat Expand" 0 (-0.5) 0.5
                                       , ControlSlider $ Slider "Beat Rotate" 0 (-0.25) 0.25
                                       , ControlSlider $ Slider "Beat Light" 0 0 1
                                       ]
                       , _mixChoiceA=defaultChoiceVis
                       , _mixChoiceB=defaultChoiceVis
                       , _mixVisualizations=defaultVisualizations
                       }


-- Lenses

makeLenses ''Mixer
makeLenses ''ChoiceVis
makeLenses ''Toggle
makeLenses ''Slider
makeLenses ''ChoiceCon
makeLenses ''Visualization
makePrisms ''Control


-- Address definition
  
mixAddress = "/cinder/mix" :: String
visAAddress = "/cinder/visA" :: String
visBAddress = "/cinder/visB" :: String
choicesAddress = "/cinder/choices" :: String
controlsAddress = "/controls" :: String
visesAddress = "/vises" :: String
effectsAddress = "/effects" :: String
slidersAddress = "/sliders" :: String
choiceAddress = "/choices" :: String
valueAddress = "/value" :: String
beatAddress = "/beat" :: String

-- OSC Flags

controlFlag = OSC.d_put (32 :: Int32)
toggleFlag = OSC.d_put $ BSC.pack "b"
sliderFlag = OSC.d_put $ BSC.pack "f"
choiceFlag = OSC.d_put $ BSC.pack "c"

-- Applying messages

-- applying choice message -> [{"/visA/sliders/clear" []}, {"/visA/sliders/Fade", ["Fade", 0, 0, 2]}]

applyCinderMessage :: OSC.Message -> Mixer -> (Mixer, [OSC.Message])
applyCinderMessage (OSC.Message address datum) mixer
  | (mixAddress ++ controlsAddress) `isPrefixOf` address =
    createResult mixControls modifiedMixControls
  | (visAAddress ++ effectsAddress) `isPrefixOf` address =
    createResult (mixChoiceA . choiceControls) modifiedChoiceAControl
  | (visBAddress ++ effectsAddress) `isPrefixOf` address =
    createResult (mixChoiceB . choiceControls) modifiedChoiceBControl
  | (visAAddress ++ choiceAddress) `isPrefixOf` address =
    createResult mixChoiceA (modifiedChoice visAAddress (mixer ^. mixChoiceA))
  | (visBAddress ++ choiceAddress) `isPrefixOf` address =
    createResult mixChoiceB (modifiedChoice visBAddress (mixer ^. mixChoiceB))
  | (visAAddress ++ slidersAddress) `isPrefixOf` address =
    createResult (mixChoiceA . choiceSliders) modifiedChoiceASlider
  | (visBAddress ++ slidersAddress) `isPrefixOf` address =
    createResult (mixChoiceB . choiceSliders) modifiedChoiceBSlider
  | beatAddress `isPrefixOf` address = (mixer, [OSC.Message address datum])
  | otherwise = (mixer, [])
  where
    extractControlName = take (last separatorIndices - last (init separatorIndices) - 1) $ drop ((+1) . last . init $ separatorIndices) address
    separatorIndices = elemIndices '/' address
    modifiedControls path getter =
      modifyControlList path extractControlName  datum (view getter mixer)
    modifiedMixControls = modifiedControls (mixAddress ++ controlsAddress) mixControls
    modifiedChoiceAControl =
      modifiedControls (visAAddress ++ effectsAddress) (mixChoiceA . choiceControls)
    modifiedChoiceBControl =
      modifiedControls (visBAddress ++ effectsAddress) (mixChoiceB . choiceControls)
    modifiedChoiceASlider =
      modifiedControls (visAAddress ++ slidersAddress) (mixChoiceA . choiceSliders)
    modifiedChoiceBSlider =
      modifiedControls (visBAddress ++ slidersAddress) (mixChoiceB . choiceSliders)
    createResult getter modifier = (set getter (fst modifier) mixer, snd modifier)
    modifiedChoice path choice = switchChoice path firstValueAsString choice (mixer ^. mixVisualizations)
    firstValueAsString = BSC.unpack $ firstValue datum

modifyControlList :: String -> String -> [OSC.Datum] -> [Control] -> ([Control], [OSC.Message])
modifyControlList path controlName datum controls = (mapControls, createMessages)
  where
    createMessages = [OSC.Message ( path ++ "/" ++ controlName ++ valueAddress) [head datum]]
    mapControls = controls & traverse %~ modifyControl controlName datum

switchChoice :: String -> String -> ChoiceVis -> [Visualization] -> (ChoiceVis, [OSC.Message])
switchChoice path choiceName choice visualizations =
      (choice & (choiceVisualization .~ choiceName) & (choiceSliders .~ visControls_),
       [OSC.Message (path ++ choiceAddress) [OSC.d_put $ BSC.pack choiceName], OSC.Message (path ++ slidersAddress) [] ] ++ controlsMessages path visControls_)
  where
    vis = fromJust $ find (\vis -> vis ^. visName == choiceName) visualizations
    visControls_ = vis ^. visControls

controlsMessages :: String -> [Control] -> [OSC.Message]
controlsMessages path = concatMap controlToMessages
  where
    controlToMessages control = [messageFromControl control True, messageFromControl control False]
    messageFromControl control isClient = let datum = controlToDatum control isClient
      in OSC.Message (path ++ slidersAddress ++ "/" ++ controlName control ++ valueAddress isClient) datum
    valueAddress isClient = if isClient then "" else "/value"

controlToDatum :: Control -> Bool -> [OSC.Datum]
controlToDatum (ControlSlider control) = flip controlSliderToDatum control
controlToDatum (ControlToggle control) = flip controlToggleToDatum control

controlName :: Control -> String
controlName (ControlSlider control) = control ^. controlSliderName
controlName (ControlToggle control) = control ^. controlToggleName

sliderMessages :: Mixer -> String -> [OSC.Message]
sliderMessages mixer choice = []

firstValue :: OSC.Datem a => [OSC.Datum] -> a
firstValue datum = fromJust $ OSC.d_get $ head datum

valueMessages :: String -> OSC.Datum -> [OSC.Message]
valueMessages fullAddress datum = [OSC.Message fullAddress [datum]]

mixerToMessages :: Bool -> Mixer -> [OSC.Message]
mixerToMessages isClient mixer =
  (createMessages mixControls (mixAddress ++ controlsAddress)) ++
  (createMessages (mixChoiceA . choiceControls) (visAAddress ++ effectsAddress)) ++
  (createMessages (mixChoiceB . choiceControls) (visBAddress ++ effectsAddress)) ++
  [createChoiceVisChoiceMessage (visAAddress ++ choiceAddress) mixChoiceA] ++
  [createChoiceVisChoiceMessage (visBAddress ++ choiceAddress) mixChoiceB] ++
  (createMessages (mixChoiceA . choiceSliders) (visAAddress ++ slidersAddress)) ++
  (createMessages (mixChoiceB . choiceSliders) (visBAddress ++ slidersAddress)) ++
  [createVisChoicesMessage (visAAddress ++ choiceAddress ++ "s") (mixChoiceA . choiceChoiceControl)] ++
  [createVisChoicesMessage (visBAddress ++ choiceAddress ++ "s") (mixChoiceB . choiceChoiceControl)]
  where
    createMessages getter path = map (createMessage path) $ view getter mixer
    createMessage path (ControlSlider control) =
      OSC.Message (path ++ "/" ++ view controlSliderName control ++ valueAddressIfClient) (controlSliderToDatum isClient control)
    createMessage path (ControlToggle control) =
      OSC.Message (path ++ "/" ++ view controlToggleName control ++ valueAddressIfClient) (controlToggleToDatum isClient control)
    createMessage path (ControlChoice control) =
      OSC.Message (path ++ "/" ++ view controlChoiceName control ++ valueAddressIfClient) (controlChoiceToDatum isClient control)
    valueAddressIfClient = if isClient then "" else valueAddress
    createVisChoicesMessage address getter =
      OSC.Message address $ controlChoiceToDatum True (view getter mixer)

createControlListMessages :: String -> Bool -> [Control] -> [OSC.Message]
createControlListMessages address isClient = map createControlMessage
  where
    createControlMessage (ControlSlider control) = OSC.Message address (controlSliderToDatum isClient control)
    createControlMessage (ControlToggle control) = OSC.Message address (controlToggleToDatum isClient control)
    createControlMessage (ControlChoice control) = OSC.Message address (controlChoiceToDatum isClient control)

modifyControl :: String -> [OSC.Datum] -> Control -> Control
modifyControl _ [] control = control
modifyControl controlName (OSC.Float f:_) (ControlSlider slider) =
  if controlName == (slider ^. controlSliderName) then ControlSlider (controlSliderValue .~ f $ slider) else ControlSlider slider
modifyControl controlName (OSC.Float b:_) (ControlToggle toggle) =
  if controlName == (toggle ^. controlToggleName) then ControlToggle (controlToggleValue .~ b $ toggle) else ControlToggle toggle
modifyControl controlName (OSC.ASCII_String s:_) (ControlChoice choice) =
  if controlName == (choice ^. controlChoiceName) then ControlChoice (controlChoiceValue .~ BSC.unpack s $ choice) else ControlChoice choice

controlHasName :: String -> Control -> Bool
controlHasName controlName (ControlSlider slider) = controlName == slider ^. controlSliderName
controlHasName controlName (ControlToggle toggle) = controlName == toggle ^. controlToggleName
controlHasName controlName (ControlChoice choice) = controlName == choice ^. controlChoiceName

controlSliderToDatum :: Bool -> Slider -> [OSC.Datum]
controlSliderToDatum isClient control
   | isClient = [ controlFlag
                , sliderFlag
                , OSC.d_put $ BSC.pack $ view controlSliderName control
                , toDatum controlSliderValue
                , toDatum controlSliderMin
                , toDatum controlSliderMax
                ]
  | otherwise = [toDatum controlSliderValue]
  where
    toDatum f = OSC.d_put $ view f control

controlToggleToDatum :: Bool -> Toggle -> [OSC.Datum]
controlToggleToDatum isClient control
  | isClient = [ controlFlag
               , toggleFlag
               , OSC.d_put $ BSC.pack $ view controlToggleName control
               , OSC.d_put $ view controlToggleValue control
               ]
  | otherwise  = [OSC.d_put $ view controlToggleValue control]

controlChoiceToDatum :: Bool -> ChoiceCon -> [OSC.Datum]
controlChoiceToDatum isClient control
  | isClient = [ choiceFlag
               , (OSC.d_put . BSC.pack) $ view controlChoiceName control
               , (OSC.d_put . BSC.pack) $ view controlChoiceValue control
               ] ++ map (OSC.d_put . BSC.pack) (view controlChoiceChoices control)
  | otherwise  = [(OSC.d_put . BSC.pack) $ view controlChoiceValue control]
