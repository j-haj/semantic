{-# LANGUAGE DeriveAnyClass #-}

module Data.Tag
  ( Tag (..)
  ) where

import Prelude hiding (span)
import Prologue

import Data.Aeson
import Control.Lens.Lens

import Source.Span

-- | These selectors aren't prefixed with @tag@ for reasons of JSON
-- backwards compatibility.
data Tag = Tag
  { name :: Text
  , kind :: Text
  , span :: Span
  , context :: [Text]
  , line :: Maybe Text
  , docs :: Maybe Text
  } deriving (Eq, Show, Generic, ToJSON)

instance HasSpan Tag where
  span_ = lens span (\t s -> t { span = s })
  {-# INLINE span_ #-}
