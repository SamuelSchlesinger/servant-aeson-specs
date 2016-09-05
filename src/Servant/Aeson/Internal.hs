{-|
Module      : Servant.Aeson.Internal
Description : Servant hspec test functions
Copyright   : (c) Plow Technologies, 2016
License     : MIT
Maintainer  : soenkehahn@gmail.com, mchaver@gmail.com
Stability   : Alpha

Internal module, use at your own risk.
-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module Servant.Aeson.Internal where

import           Data.Aeson
import           Data.Function
import           Data.List
import           Data.Proxy
import           Data.Typeable
import           GHC.TypeLits
import           Servant.API
import           Test.Hspec
import           Test.QuickCheck

import           Test.Aeson.Internal.GoldenSpecs
import           Test.Aeson.Internal.RoundtripSpecs
import           Test.Aeson.GenericSpecs

-- | Allows to obtain roundtrip tests for JSON serialization for all types used
-- in a [servant](http://haskell-servant.readthedocs.org/) api. It uses settings
-- are not used in 'roundtripSpecs'. There is no need to let the user pass
-- cusomt settings. It automatically uses 'defaultSettings'.
--
-- See also 'Test.Aeson.GenericSpecs.roundtripSpecs'.
apiRoundtripSpecs :: (HasGenericSpecs api) => Proxy api -> Spec
apiRoundtripSpecs = sequence_ . map roundtrip . mkRoundtripSpecs defaultSettings

-- | Allows to obtain golden tests for JSON serialization for all types used
-- in a [servant](http://haskell-servant.readthedocs.org/) api.
--
-- See also 'Test.Aeson.GenericSpecs.goldenSpecs'.
apiGoldenSpecs :: HasGenericSpecs api => Proxy api -> Spec
apiGoldenSpecs proxy = apiGoldenSpecsWithSettings defaultSettings proxy

-- | Same as 'apiGoldenSpecs', but allows custom settings.
apiGoldenSpecsWithSettings :: HasGenericSpecs api => Settings -> Proxy api -> Spec
apiGoldenSpecsWithSettings settings proxy = sequence_ $ map golden $ mkRoundtripSpecs settings proxy

-- | Combination of 'apiRoundtripSpecs' and 'apiGoldenSpecs'.
apiSpecs :: (HasGenericSpecs api) => Proxy api -> Spec
apiSpecs proxy = apiSpecsWithSettings defaultSettings proxy

-- | Same as 'apiSpecs', but allows custom settings.
apiSpecsWithSettings :: (HasGenericSpecs api) => Settings -> Proxy api -> Spec
apiSpecsWithSettings settings proxy = sequence_ $ map (\ ts -> roundtrip ts >> golden ts) $ mkRoundtripSpecs settings proxy

-- | Allows to retrieve a list of all used types in a
-- [servant](http://haskell-servant.readthedocs.org/) api as 'TypeRep's.
usedTypes :: (HasGenericSpecs api) => Proxy api -> [TypeRep]
usedTypes = map typ . mkRoundtripSpecs defaultSettings

mkRoundtripSpecs :: (HasGenericSpecs api) => Settings -> Proxy api -> [TypeSpec]
mkRoundtripSpecs settings = normalize . collectRoundtripSpecs settings
  where
    normalize = nubBy ((==) `on` typ) . sortBy (compare `on` (show . typ))

class HasGenericSpecs api where
  collectRoundtripSpecs :: Settings -> Proxy api -> [TypeSpec]

instance (HasGenericSpecs a, HasGenericSpecs b) => HasGenericSpecs (a :<|> b) where
  collectRoundtripSpecs settings Proxy =
    collectRoundtripSpecs settings (Proxy :: Proxy a) ++
    collectRoundtripSpecs settings (Proxy :: Proxy b)

-- * http methods

#if MIN_VERSION_servant(0, 5, 0)
instance {-# OVERLAPPABLE #-}
  (MkTypeSpecs response) =>
  HasGenericSpecs (Verb (method :: StdMethod) returnStatus contentTypes response) where

  collectRoundtripSpecs settings Proxy = do
    mkTypeSpecs settings (Proxy :: Proxy response)

instance {-# OVERLAPPING #-}
  HasGenericSpecs (Verb (method :: StdMethod) returnStatus contentTypes NoContent) where

  collectRoundtripSpecs _ Proxy = []
#else
instance (MkTypeSpecs response) =>
  HasGenericSpecs (Get contentTypes response) where

  collectRoundtripSpecs settings Proxy = do
    mkTypeSpecs settings (Proxy :: Proxy response)

instance (MkTypeSpecs response) =>
  HasGenericSpecs (Post contentTypes response) where

  collectRoundtripSpecs settings Proxy = mkTypeSpecs settings (Proxy :: Proxy response)
#endif

-- * combinators

instance (MkTypeSpecs body, HasGenericSpecs api) =>
  HasGenericSpecs (ReqBody contentTypes body :> api) where

  collectRoundtripSpecs settings Proxy =
    mkTypeSpecs settings (Proxy :: Proxy body) ++
    collectRoundtripSpecs settings (Proxy :: Proxy api)

instance HasGenericSpecs api => HasGenericSpecs ((path :: Symbol) :> api) where
  collectRoundtripSpecs settings Proxy = collectRoundtripSpecs settings (Proxy :: Proxy api)

#if !MIN_VERSION_servant(0, 5, 0)
instance HasGenericSpecs api => HasGenericSpecs (MatrixParam name a :> api) where
  collectRoundtripSpecs settings Proxy = collectRoundtripSpecs settings (Proxy :: Proxy api)
#endif

data TypeSpec
  = TypeSpec {
    typ :: TypeRep,
    roundtrip :: Spec,
    golden :: Spec
  }

-- 'mkTypeSpecs' has to be implemented as a method of a separate class, because we
-- want to be able to have a specialized implementation for lists.
class MkTypeSpecs a where
  mkTypeSpecs :: Settings -> Proxy a -> [TypeSpec]

instance (Typeable a, Eq a, Show a, Arbitrary a, ToJSON a, FromJSON a) => MkTypeSpecs a where

  mkTypeSpecs settings proxy = pure $
    TypeSpec {
      typ = typeRep proxy,
      roundtrip = roundtripSpecs proxy,
      golden = goldenSpecs settings proxy
    }

-- The following instances will only test json serialization of element types.
-- As we trust aeson to do the right thing for standard container types, we
-- don't need to test that. (This speeds up test suites immensely.)

instance {-# OVERLAPPING #-}
  (Eq a, Show a, Typeable a, Arbitrary a, ToJSON a, FromJSON a) =>
  MkTypeSpecs [a] where

  mkTypeSpecs settings Proxy = pure $
    TypeSpec {
      typ = typeRep proxy,
      roundtrip = genericAesonRoundtripWithNote proxy (Just note),
      golden = goldenSpecsWithNote settings proxy (Just note)
    }
    where
      proxy = Proxy :: Proxy a
      note = "(as element-type in [])"

instance {-# OVERLAPPING #-}
  (Eq a, Show a, Typeable a, Arbitrary a, ToJSON a, FromJSON a) =>
  MkTypeSpecs (Maybe a) where

  mkTypeSpecs settings Proxy = pure $
    TypeSpec {
      typ = typeRep proxy,
      roundtrip = genericAesonRoundtripWithNote proxy (Just note),
      golden = goldenSpecsWithNote settings proxy (Just note)
    }
    where
      proxy = Proxy :: Proxy a
      note = "(as element-type in Maybe)"

-- We trust aeson to be correct for ().
instance {-# OVERLAPPING #-}
  MkTypeSpecs () where

  mkTypeSpecs _ Proxy = []
