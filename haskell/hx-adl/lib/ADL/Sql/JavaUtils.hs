{-# LANGUAGE OverloadedStrings #-}
module ADL.Sql.JavaUtils where

import qualified Data.Aeson as JS
import qualified Data.HashMap.Strict as HM
import qualified Data.Text as T
import qualified Data.Map as M
import qualified ADL.Compiler.AST as AST
import qualified ADL.Sql.SchemaUtils as SC
import qualified ADL.Sql.Schema as SC
import qualified ADL.Compiler.Backends.Java.Internal as J
import qualified ADL.Compiler.Backends.Java as J

import ADL.Compiler.Processing
import Utils(toSnakeCase)

data JavaTableFlags = JavaTableFlags {
  jt_rtpackage :: T.Text,
  jt_package :: T.Text,
  jt_crudfns :: Bool,
  jt_genversion :: GenVersion
}

data GenVersion = V1 | V2;

defaultJavaTableFlags = JavaTableFlags "adl.runtime" "adl" False V1

type DBTable = (J.CDecl,AST.Struct J.CResolvedType,SC.Table,JS.Value)


data DbColumn a
  = IdColumn SC.Column
  | DbColumn SC.Column (AST.Field J.CResolvedType) a

mkDbColumns :: Bool -> [SC.Column] -> [AST.Field J.CResolvedType] -> [DbColumn ()]
mkDbColumns False columns fields = zipWith (\c f -> DbColumn c f ()) columns fields
mkDbColumns True columns fields = (IdColumn (head columns)): mkDbColumns False(tail columns) fields

javaFieldName :: DbColumn a -> T.Text
javaFieldName (IdColumn _) = "id"
javaFieldName (DbColumn _ field _) = J.unreserveWord (AST.f_name field)

withCommas :: [a] -> [(a,T.Text)]
withCommas [] = []
withCommas [l] = [(l," ")]
withCommas (l:ls) = (l,","):withCommas ls

dbTableName :: J.CDecl -> T.Text
dbTableName decl = case getAnnotation (AST.d_annotations decl) dbTableType of
  (Just (JS.Object hm)) -> case HM.lookup "tableName" hm of
    (Just (JS.String t)) -> t
    _ -> dbName (AST.d_name decl)
  _ -> dbName (AST.d_name decl)

getAnnotation :: AST.Annotations J.CResolvedType -> AST.ScopedName -> Maybe JS.Value
getAnnotation annotations annotationName = snd <$> M.lookup annotationName annotations

dbName :: T.Text -> T.Text
dbName =  toSnakeCase

getAnnotationField :: JS.Value -> T.Text -> Maybe JS.Value
getAnnotationField (JS.Object hm) field = HM.lookup field hm
getAnnotationField _ _ = Nothing

dbTableType = AST.ScopedName (AST.ModuleName ["common","db"]) "DbTable"
javaDbTableVersion = AST.ScopedName (AST.ModuleName ["common","db"]) "JavaDbTableVersion"
javaDbCustomType = AST.ScopedName (AST.ModuleName ["common","db"]) "JavaDbCustomType"
withDbIdType = AST.ScopedName (AST.ModuleName ["common","db"]) "WithDbId"
dbKeyType = AST.ScopedName (AST.ModuleName ["common","db"]) "DbKey"

customDbType :: SC.Column -> AST.Field J.CResolvedType -> Maybe T.Text
customDbType col field = do
    jv <- customDbAnnotation col field
    case getAnnotationField jv "javaDbType" of
      Nothing -> Nothing
      (Just (JS.String t)) -> Just t

customDbHelpers :: SC.Column -> AST.Field J.CResolvedType -> Maybe T.Text
customDbHelpers col field = do
    jv <- customDbAnnotation col field
    case getAnnotationField jv "helpers" of
      Nothing -> Nothing
      (Just (JS.String t)) -> Just t

-- The annotation can be be on the field, or on the declaration referenced by the field type
customDbAnnotation :: SC.Column -> AST.Field J.CResolvedType -> Maybe JS.Value
customDbAnnotation col field = case getAnnotation (AST.f_annotations field) javaDbCustomType of
   (Just jv) -> Just jv
   Nothing -> case (SC.column_nullable col,AST.f_type field) of
      (False, AST.TypeExpr (RT_Named (_,decl))  _) -> getAnnotation (AST.d_annotations decl) javaDbCustomType
      (True, AST.TypeExpr _ [AST.TypeExpr (RT_Named (_,decl)) _]) -> getAnnotation (AST.d_annotations decl) javaDbCustomType
      _ -> Nothing

javaTableClassName :: J.CDecl -> T.Text
javaTableClassName decl = AST.d_name decl <> "Table"

javaClassName :: J.CDecl -> T.Text
javaClassName decl = AST.d_name decl

tableClassName :: J.CDecl -> T.Text
tableClassName decl = J.unreserveWord (AST.d_name decl) <> "Table"
