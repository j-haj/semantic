{-# LANGUAGE DeriveAnyClass, DerivingVia, MultiParamTypeClasses, ScopedTypeVariables, TupleSections, UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-missing-export-lists #-}
module Data.Syntax.Declaration where

import Prologue

import           Control.Lens.Getter
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import           Control.Abstract hiding (AccessControl (..), Function)
import           Data.Abstract.Evaluatable
import           Data.Abstract.Name (__self)
import qualified Data.Abstract.ScopeGraph as ScopeGraph
import           Data.JSON.Fields
import qualified Data.Reprinting.Scope as Scope
import           Diffing.Algorithm
import           Reprinting.Tokenize hiding (Superclass)
import           Source.Span

data Function a = Function { functionContext :: ![a], functionName :: !a, functionParameters :: ![a], functionBody :: !a }
  deriving (Eq, Ord, Show, Foldable, Traversable, Functor, Generic1, Hashable1, ToJSONFields1, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Function

instance Diffable Function where
  equivalentBySubterm = Just . functionName

-- TODO: Filter the closed-over environment by the free variables in the term.
-- TODO: How should we represent function types, where applicable?

instance Evaluatable Function where
  eval _ _ Function{..} = do
    current <- ask @Span
    (name, associatedScope) <- declareFunction (declaredName functionName) ScopeGraph.Public current ScopeGraph.Function

    params <- withScope associatedScope . for functionParameters $ \paramNode -> declareMaybeName (declaredName paramNode) Default ScopeGraph.Public (paramNode^.span_) ScopeGraph.Parameter Nothing

    addr <- lookupSlot (Declaration name)
    v <- function name params functionBody associatedScope
    v <$ assign addr v

declareFunction :: ( Carrier sig m
                   , Member (State (ScopeGraph address)) sig
                   , Member (Allocator address) sig
                   , Member (Reader (CurrentScope address)) sig
                   , Member (Reader ModuleInfo) sig
                   , Member Fresh sig
                   , Ord address
                   )
                => Maybe Name
                -> ScopeGraph.AccessControl
                -> Span
                -> ScopeGraph.Kind
                -> Evaluator term address value m (Name, address)
declareFunction name accessControl span kind = do
  currentScope' <- currentScope
  let lexicalEdges = Map.singleton Lexical [ currentScope' ]
  associatedScope <- newScope lexicalEdges
  name' <- declareMaybeName name Default accessControl span kind (Just associatedScope)
  pure (name', associatedScope)

instance Tokenize Function where
  tokenize Function{..} = within' Scope.Function $ do
    functionName
    within' Scope.Params $ sequenceA_ (sep functionParameters)
    functionBody

instance Declarations1 Function where
  liftDeclaredName declaredName = declaredName . functionName

instance FreeVariables1 Function where
  liftFreeVariables freeVariables f@Function{..} = foldMap freeVariables f `Set.difference` foldMap freeVariables functionParameters

data Method a = Method
  { methodContext :: [a]
  , methodReceiver :: a
  , methodName :: a
  , methodParameters :: [a]
  , methodBody :: a
  , methodAccessControl :: ScopeGraph.AccessControl
  }
  deriving (Eq, Ord, Show, Foldable, Traversable, Functor, Generic1, Hashable1, ToJSONFields1, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Method

instance Diffable Method where
  equivalentBySubterm = Just . methodName

-- Evaluating a Method creates a closure and makes that value available in the
-- local environment.
instance Evaluatable Method where
  eval _ _ Method{..} = do
    current <- ask @Span
    (name, associatedScope) <- declareFunction (declaredName methodName) methodAccessControl current ScopeGraph.Method

    params <- withScope associatedScope $ do
      -- TODO: Should we give `self` a special Relation?
      declare (Declaration __self) ScopeGraph.Prelude ScopeGraph.Public lowerBound ScopeGraph.Unknown Nothing
      for methodParameters $ \paramNode -> declareMaybeName (declaredName paramNode) Default ScopeGraph.Public (paramNode^.span_) ScopeGraph.Parameter Nothing

    addr <- lookupSlot (Declaration name)
    v <- function name params methodBody associatedScope
    v <$ assign addr v

instance Tokenize Data.Syntax.Declaration.Method where
  tokenize Method{..} = within' Scope.Method $ do
    methodName
    within' Scope.Params $ sequenceA_ (sep methodParameters)
    methodBody

instance Declarations1 Method where
  liftDeclaredName declaredName = declaredName . methodName

instance FreeVariables1 Method where
  liftFreeVariables freeVariables m@Method{..} = foldMap freeVariables m `Set.difference` foldMap freeVariables methodParameters


-- | A method signature in TypeScript or a method spec in Go.
data MethodSignature a = MethodSignature
  { methodSignatureContext :: [a]
  , methodSignatureName :: a
  , methodSignatureParameters :: [a]
  , methodSignatureAccessControl :: ScopeGraph.AccessControl
  }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically MethodSignature

-- TODO: Implement Eval instance for MethodSignature
instance Evaluatable MethodSignature


newtype RequiredParameter a = RequiredParameter { requiredParameter :: a }
  deriving (Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically RequiredParameter

instance Declarations1 RequiredParameter where
  liftDeclaredName declaredName = declaredName . requiredParameter

-- TODO: Implement Eval instance for RequiredParameter
instance Evaluatable RequiredParameter where
  eval _ _ RequiredParameter{..} = do
    span <- ask @Span
    _ <- declareMaybeName (declaredName requiredParameter) Default ScopeGraph.Public span ScopeGraph.RequiredParameter Nothing
    unit


newtype OptionalParameter a = OptionalParameter { optionalParameter :: a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically OptionalParameter

-- TODO: Implement Eval instance for OptionalParameter
instance Evaluatable OptionalParameter


-- TODO: Should we replace this with Function and differentiate by context?
-- TODO: How should we distinguish class/instance methods?
-- TODO: It would be really nice to have a more meaningful type contained in here than [a]
-- | A declaration of possibly many variables such as var foo = 5, bar = 6 in JavaScript.
newtype VariableDeclaration a = VariableDeclaration { variableDeclarations :: [a] }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically VariableDeclaration

instance Evaluatable VariableDeclaration where
  eval _    _ (VariableDeclaration [])   = unit
  eval eval _ (VariableDeclaration decs) = do
    for_ decs $ \declaration -> do
      _ <- declareMaybeName (declaredName declaration) Default ScopeGraph.Public (declaration^.span_) ScopeGraph.VariableDeclaration Nothing
      eval declaration
    unit

instance Declarations a => Declarations (VariableDeclaration a) where
  declaredName (VariableDeclaration vars) = case vars of
    [var] -> declaredName var
    _     -> Nothing


-- | A TypeScript/Java style interface declaration to implement.

data InterfaceDeclaration a = InterfaceDeclaration { interfaceDeclarationContext :: ![a], interfaceDeclarationIdentifier :: !a, interfaceDeclarationSuperInterfaces :: ![a], interfaceDeclarationBody :: !a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically InterfaceDeclaration

-- TODO: Implement Eval instance for InterfaceDeclaration
instance Evaluatable InterfaceDeclaration

instance Declarations a => Declarations (InterfaceDeclaration a) where
  declaredName InterfaceDeclaration{..} = declaredName interfaceDeclarationIdentifier


-- | A public field definition such as a field definition in a JavaScript class.
data PublicFieldDefinition a = PublicFieldDefinition
  { publicFieldContext :: [a]
  , publicFieldPropertyName :: a
  , publicFieldValue :: a
  , publicFieldAccessControl :: ScopeGraph.AccessControl
  }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically PublicFieldDefinition

-- TODO: Implement Eval instance for PublicFieldDefinition
instance Evaluatable PublicFieldDefinition where
  eval eval _ PublicFieldDefinition{..} = do
    span <- ask @Span
    name <- declareMaybeName (declaredName publicFieldPropertyName) Instance publicFieldAccessControl span ScopeGraph.PublicField Nothing
    slot <- lookupSlot (Declaration name)
    value <- eval publicFieldValue
    assign slot value
    unit

data Variable a = Variable { variableName :: !a, variableType :: !a, variableValue :: !a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Variable

-- TODO: Implement Eval instance for Variable
instance Evaluatable Variable

data Class a = Class { classContext :: ![a], classIdentifier :: !a, classSuperclasses :: ![a], classBody :: !a }
  deriving (Eq, Ord, Show, Foldable, Traversable, Functor, Generic1, Hashable1, FreeVariables1, ToJSONFields1, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Class

instance Declarations a => Declarations (Class a) where
  declaredName (Class _ name _ _) = declaredName name

instance Diffable Class where
  equivalentBySubterm = Just . classIdentifier

instance Evaluatable Class where
  eval eval _ Class{..} = do
    span <- ask @Span
    currentScope' <- currentScope

    superScopes <- for classSuperclasses $ \superclass -> do
      name <- case declaredName superclass of
                Just name -> pure name
                Nothing   -> gensym
      scope <- associatedScope (Declaration name)
      slot <- lookupSlot (Declaration name)
      superclassFrame <- scopedEnvironment =<< deref slot
      pure $ case (scope, superclassFrame) of
        (Just scope, Just frame) -> Just (scope, frame)
        _                        -> Nothing

    let superclassEdges = (Superclass, ) . pure . fst <$> catMaybes superScopes
        current = (Lexical, ) <$> pure (pure currentScope')
        edges = Map.fromList (superclassEdges <> current)
    classScope <- newScope edges
    name <- declareMaybeName (declaredName classIdentifier) Default ScopeGraph.Public span ScopeGraph.Class (Just classScope)

    let frameEdges = Map.singleton Superclass (Map.fromList (catMaybes superScopes))
    classFrame <- newFrame classScope frameEdges

    classSlot <- lookupSlot (Declaration name)
    assign classSlot =<< klass (Declaration name) classFrame

    withScopeAndFrame classFrame $ do
      void $ eval classBody

    unit

instance Declarations1 Class where
  liftDeclaredName declaredName = declaredName . classIdentifier

-- | A decorator in Python
data Decorator a = Decorator { decoratorIdentifier :: !a, decoratorParamaters :: ![a], decoratorBody :: !a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Decorator

-- TODO: Implement Eval instance for Decorator
instance Evaluatable Decorator

-- TODO: Generics, constraints.


-- | An ADT, i.e. a disjoint sum of products, like 'data' in Haskell, or 'enum' in Rust or Swift.
data Datatype a = Datatype { datatypeContext :: a, datatypeName :: a, datatypeConstructors :: [a], datatypeDeriving :: a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Datatype

-- TODO: Implement Eval instance for Datatype
instance Evaluatable Data.Syntax.Declaration.Datatype


-- | A single constructor in a datatype, or equally a 'struct' in C, Rust, or Swift.
data Constructor a = Constructor { constructorContext :: [a], constructorName :: a, constructorFields :: a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Constructor

-- TODO: Implement Eval instance for Constructor
instance Evaluatable Data.Syntax.Declaration.Constructor


-- | Comprehension (e.g. ((a for b in c if a()) in Python)
data Comprehension a = Comprehension { comprehensionValue :: !a, comprehensionBody :: !a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Comprehension

-- TODO: Implement Eval instance for Comprehension
instance Evaluatable Comprehension


-- | A declared type (e.g. `a []int` in Go).
data Type a = Type { typeName :: !a, typeKind :: !a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically Type

-- TODO: Implement Eval instance for Type
instance Evaluatable Type


-- | Type alias declarations in Javascript/Haskell, etc.
data TypeAlias a = TypeAlias { typeAliasContext :: ![a], typeAliasIdentifier :: !a, typeAliasKind :: !a }
  deriving (Declarations1, Diffable, Eq, Foldable, FreeVariables1, Functor, Generic1, Hashable1, Ord, Show, ToJSONFields1, Traversable, NFData1)
  deriving (Eq1, Show1, Ord1) via Generically TypeAlias

instance Evaluatable TypeAlias where
  eval _ _ TypeAlias{..} = do
    -- This use of `throwNoNameError` is good -- we aren't declaring something new so `declareMaybeName` is not useful here.
    kindName <- maybeM (throwNoNameError typeAliasKind) (declaredName typeAliasKind)
    span <- ask @Span
    assocScope <- associatedScope (Declaration kindName)
    name <- declareMaybeName (declaredName typeAliasIdentifier) Default ScopeGraph.Public span ScopeGraph.TypeAlias assocScope

    slot <- lookupSlot (Declaration name)
    kindSlot <- lookupSlot (Declaration kindName)
    assign slot =<< deref kindSlot

    unit

instance Declarations a => Declarations (TypeAlias a) where
  declaredName TypeAlias{..} = declaredName typeAliasIdentifier
