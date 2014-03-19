{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RebindableSyntax #-}

module Course.Parser where

import Course.Core
import Course.Person
import Course.Functor
import Course.Apply
import Course.Applicative
import Course.Bind
import Course.Monad
import Course.List
import Course.Optional
import Data.Char

-- $setup
-- >>> :set -XOverloadedStrings
-- >>> import Data.Char(isUpper)

type Input = Chars

data ParseError =
  UnexpectedEof
  | ExpectedEof Input
  | UnexpectedChar Char
  | Failed
  deriving Eq


instance Show ParseError where
  show UnexpectedEof =
    "Unexpected end of stream"
  show (ExpectedEof i) =
    stringconcat ["Expected end of stream, but got >", show i, "<"]
  show (UnexpectedChar c) =
    stringconcat ["Unexpected character", show [c]]
  show Failed =
    "Parse failed"

data ParseResult a =
  ErrorResult ParseError
  | Result Input a
  deriving Eq

instance Show a => Show (ParseResult a) where
  show (ErrorResult e) =
    show e
  show (Result i a) =
    stringconcat ["Result >", hlist i, "< ", show a]

-- Function to determine is a parse result is an error.
isErrorResult ::
  ParseResult a
  -> Bool
isErrorResult (ErrorResult _) =
  True
isErrorResult (Result _ _) =
  False

data Parser a = P {
  parse :: Input -> ParseResult a
}

-- Function to produce a parser with the given result.
result ::
  ParseResult a
  -> Parser a
result =
  P . const

-- | Return a parser that always succeeds with the given value and consumes no input.
--
-- >>> parse (valueParser 3) "abc"
-- Result >abc< 3
valueParser ::
  a
  -> Parser a
valueParser x =
  P (\input -> Result input x)

-- | Return a parser that always fails with the given error.
--
-- >>> isErrorResult (parse failed "abc")
-- True
failed ::
  Parser a
failed =
  P (\_ -> ErrorResult Failed)

-- | Return a parser that succeeds with a character off the input or fails with an error if the input is empty.
--
-- >>> parse character "abc"
-- Result >bc< 'a'
--
-- >>> isErrorResult (parse character "")
-- True
character ::
  Parser Char
character =
  P (\input -> case input of
                 Nil -> ErrorResult UnexpectedEof
                 h:.t -> Result t h)

-- | Return a parser that puts its input into the given parser and
--
--   * if that parser succeeds with a value (a), put that value into the given function
--     then put in the remaining input in the resulting parser.
--
--   * if that parser fails with an error the returned parser fails with that error.
--
-- >>> parse (bindParser (\c -> if c == 'x' then character else valueParser 'v') character) "abc"
-- Result >bc< 'v'
--
-- >>> parse (bindParser (\c -> if c == 'x' then character else valueParser 'v') character) "a"
-- Result >< 'v'
--
-- >>> parse (bindParser (\c -> if c == 'x' then character else valueParser 'v') character) "xabc"
-- Result >bc< 'a'
--
-- >>> isErrorResult (parse (bindParser (\c -> if c == 'x' then character else valueParser 'v') character) "")
-- True
--
-- >>> isErrorResult (parse (bindParser (\c -> if c == 'x' then character else valueParser 'v') character) "x")
-- True
bindParser ::
  (q -> Parser y)
  -> Parser q
  -> Parser y
bindParser f p =
  -- f :: q -> Parser y
  -- p :: Parser q
  -- parse p :: Input -> ParseResult q
  -- rest :: Input
  -- q :: q
  ----
  -- ? :: ParseResult y
  P (\input -> case parse p input of
                 ErrorResult e -> ErrorResult e
                 Result rest q -> parse (f q) rest)

fbindParser ::
  Parser a
  -> (a -> Parser b)
  -> Parser b
fbindParser =
  flip bindParser


pairparser :: Parser (Char, Char)
pairparser = 
  -- undefined :: Parser (Char, Char)

  fbindParser character (\char1 -> 
  fbindParser character (\char2 -> 
  valueParser (char1, char2)))

-- | Return a parser that puts its input into the given parser and
--
--   * if that parser succeeds with a value (a), ignore that value
--     but put the remaining input into the second given parser.
--
--   * if that parser fails with an error the returned parser fails with that error.
--
-- /Tip:/ Use @bindParser@ or @fbindParser@.
--
-- >>> parse (character >>> valueParser 'v') "abc"
-- Result >bc< 'v'
--
-- >>> isErrorResult (parse (character >>> valueParser 'v') "")
-- True
(>>>) ::
  Parser a
  -> Parser b
  -> Parser b
(>>>) pa pb =
  fbindParser pa (\_ -> pb)

-- | Return a parser that tries the first parser for a successful value.
--
--   * If the first parser succeeds then use this parser.
--
--   * If the first parser fails, try the second parser.
--
-- >>> parse (character ||| valueParser 'v') ""
-- Result >< 'v'
--
-- >>> parse (character 'y' ||| character 'n') "y"
-- Result >< 'y'
--
-- >>> parse (failed ||| valueParser 'v') ""
-- Result >< 'v'
--
-- >>> parse (character ||| valueParser 'v') "abc"
-- Result >bc< 'a'
--
-- >>> parse (failed ||| valueParser 'v') "abc"
-- Result >abc< 'v'
(|||) ::
  Parser a
  -> Parser a
  -> Parser a
(|||) p1 p2 =
  -- p1 :: Input -> ParseResult a
  -- p2 :: Input -> ParseResult a
  P (\input -> case parse p1 input of
                 ErrorResult _ -> parse p2 input
                 Result r a -> Result r a)

infixl 3 |||

-- | Return a parser that continues producing a list of values from the given parser.
--
-- /Tip:/ Use @many1@, @valueParser@ and @(|||)@.
--
-- >>> parse (list (character)) ""
-- Result >< ""
--
-- >>> parse (list (digit)) "123abc"
-- Result >abc< "123"
--
-- >>> parse (list digit) "abc"
-- Result >abc< ""
--
-- >>> parse (list (character)) "abc"
-- Result >< "abc"
--
-- >>> parse (list (character *> valueParser 'v')) "abc"
-- Result >< "vvv"
--
-- >>> parse (list (character *> valueParser 'v')) ""
-- Result >< ""
list ::
  Parser a
  -> Parser (List a)
list p =
-- A 0 or many parser is a 1 or many parser (many1)
-- |||OR||| (wink wink) a parser that
-- ALWAYS PRODUCES Nil (valueParser?).
  many1 p ||| valueParser Nil

-- | Return a parser that produces at least one value from the given parser then
-- continues producing a list of values from the given parser (to ultimately produce a non-empty list).
-- The returned parser fails if The input is empty.
--
-- /Tip:/ Use @bindParser@, @list@ and @value@.
--
-- >>> parse (many1 (character)) "abc"
-- Result >< "abc"
--
-- >>> parse (many1 (character *> valueParser 'v')) "abc"
-- Result >< "vvv"
--
-- >>> isErrorResult (parse (many1 (character *> valueParser 'v')) "")
-- True
many1 ::
-- A 1 or many parser is (=) a parser that runs
-- producing a value (call it a), 
-- bi.THEN.ndPar.RUN.ser a 0 or many parser
-- producing a list (call it listofa), 
-- bi.THEN.ndParser cons a to listofa
  Parser a
  -> Parser (List a)
many1 p =
  fbindParser p        (\a -> 
  fbindParser (list p) (\listofa ->
  valueParser (a :. listofa)))

-- | Return a parser that produces a character but fails if
--
--   * The input is empty.
--
--   * The character does not satisfy the given predicate.
--
-- /Tip:/ The @bindParser@ and @character@ functions will be helpful here.
--
-- >>> parse (satisfy isUpper) "Abc"
-- Result >bc< 'A'
--
-- >>> isErrorResult (parse (satisfy isUpper) "abc")
-- True
satisfy ::
  (Char -> Bool)
  -> Parser Char
satisfy p =
  fbindParser character (\char ->
    if p char 
      then valueParser char
      else P (\_ -> ErrorResult (UnexpectedChar char)))
--         result (ErrorResult (UnexpectedChar char))
unexpectedCharP ::
  Char
  -> Parser a
unexpectedCharP c =
  P (\_ -> ErrorResult (UnexpectedChar c))

-- | Return a parser that produces the given character but fails if
--
--   * The input is empty.
--
--   * The produced character is not equal to the given character.
--
-- /Tip:/ Use the @satisfy@ function.
is ::
  Char -> Parser Char
is c =
--  satisfy (\char -> char == c)
  satisfy (== c)
-- satisfy . (==)

-- | Return a parser that produces a character between '0' and '9' but fails if
--
--   * The input is empty.
--
--   * The produced character is not a digit.
--
-- /Tip:/ Use the @satisfy@ and @Data.Char.isDigit@ functions.
digit ::
  Parser Char
digit =
  satisfy isDigit


-- | Return a parser that produces zero or a positive integer but fails if
--
--   * The input is empty.
--
--   * The input does not produce a value series of digits
--
-- /Tip:/ Use the @bindParser@, @valueParser@, @list@, @read@ and @digit@
-- functions.
natural ::
  Parser Int
natural =
  fbindParser (list digit) (\ds -> case read ds of
                                     Empty -> failed
                                     Full n -> valueParser n)

--
-- | Return a parser that produces a space character but fails if
--
--   * The input is empty.
--
--   * The produced character is not a space.
--
-- /Tip:/ Use the @satisfy@ and @Data.Char.isSpace@ functions.
space ::
  Parser Char
space =
  satisfy isSpace

-- | Return a parser that produces one or more space characters
-- (consuming until the first non-space) but fails if
--
--   * The input is empty.
--
--   * The first produced character is not a space.
--
-- /Tip:/ Use the @many1@ and @space@ functions.
spaces1 ::
  Parser Chars
spaces1 =
  many1 space

-- | Return a parser that produces a lower-case character but fails if
--
--   * The input is empty.
--
--   * The produced character is not lower-case.
--
-- /Tip:/ Use the @satisfy@ and @Data.Char.isLower@ functions.
lower ::
  Parser Char
lower =
  satisfy isLower

-- | Return a parser that produces an upper-case character but fails if
--
--   * The input is empty.
--
--   * The produced character is not upper-case.
--
-- /Tip:/ Use the @satisfy@ and @Data.Char.isUpper@ functions.
upper ::
  Parser Char
upper =
  satisfy isUpper

-- | Return a parser that produces an alpha character but fails if
--
--   * The input is empty.
--
--   * The produced character is not alpha.
--
-- /Tip:/ Use the @satisfy@ and @Data.Char.isAlpha@ functions.
alpha ::
  Parser Char
alpha =
  satisfy isAlpha

-- | Return a parser that sequences the given list of parsers by producing all their results
-- but fails on the first failing parser of the list.
--
-- /Tip:/ Use @bindParser@ and @value@.
-- /Tip:/ Optionally use @List#foldRight@. If not, an explicit recursive call.
--
-- >>> parse (sequenceParser (character :. is 'x' :. upper :. Nil)) "axCdef"
-- Result >def< "axC"
--
-- >>> isErrorResult (parse (sequenceParser (character :. is 'x' :. upper :. Nil)) "abCdef")
-- True
sequenceParser ::
  List (Parser a)
  -> Parser (List a)
sequenceParser Nil = 
  valueParser Nil -- foldRight (twiceParser (:.)) (valueParser Nil)
sequenceParser (h:.t) =
  fbindParser h (\a ->
  fbindParser (sequenceParser t) (\as ->
  valueParser (a:.as)))

twiceParser ::
  (a -> b -> c)
  -> Parser a 
  -> Parser b
  -> Parser c
twiceParser f pa pb =
  fbindParser pa (\a ->
  fbindParser pb (\b ->
  valueParser (f a b))) 
{-
twiceOptionalagain ::
  (a -> b -> c)
  -> Optional a 
  -> Optional b
  -> Optional c
twiceOptionalagain f oa ob = 
  fbindOptional oa (\a ->
  fbindOptional ob (\b ->
  Full (f a b))) 
-}
-- | Return a parser that produces the given number of values off the given parser.
-- This parser fails if the given parser fails in the attempt to produce the given number of values.
--
-- /Tip:/ Use @sequenceParser@ and @List.replicate@.
--
-- >>> parse (thisMany 4 upper) "ABCDef"
-- Result >ef< "ABCD"
--
-- >>> isErrorResult (parse (thisMany 4 upper) "ABcDef")
-- True
thisMany ::
  Int
  -> Parser a
  -> Parser (List a)
thisMany n =
--  sequenceParser (replicate n p) 
--  (sequenceParser . replicate n) p
-- replicate n:: d -> List d
-- sequenceParser :: List (Parser a) -> Parser (List a)
-- (.) :: (b -> c) -> (a -> b) -> (a -> c)
-- a -> b :: d -> List d
-- a -> b :: Parser a -> List (Parser a) ~ replicate n 
-- b -> c :: List (Parser a) -> Parser a ~ sequenceParser
-- sequenceParser . replicate n
   sequenceParser . replicate n
-- (sequenceParser .) . replicate

-- | Write a parser for Person.age.
--
-- /Age: positive integer/
--
-- /Tip:/ Equivalent to @natural@.
--
-- >>> parse ageParser "120"
-- Result >< 120
--
-- >>> isErrorResult (parse ageParser "abc")
-- True
--
-- >>> isErrorResult (parse ageParser "-120")
-- True
ageParser ::
  Parser Int
ageParser =
  natural

-- | Write a parser for Person.firstName.
-- /First Name: non-empty string that starts with a capital letter/
--
-- /Tip:/ Use @bindParser@, @valueParser@, @upper@, @list@ and @lower@.
--
-- >>> parse firstNameParser "Abc"
-- Result >< "Abc"
--
-- >>> isErrorResult (parse firstNameParser "abc")
-- True
firstNameParser ::
  Parser Chars
firstNameParser =
  fbindParser upper (\h ->
  fbindParser (list lower) (\t ->
  valueParser (h:.t)))

-- | Write a parser for Person.surname.
--
-- /Surname: string that starts with a capital letter and is followed by 5 or more lower-case letters./
--
-- /Tip:/ Use @bindParser@, @valueParser@, @upper@, @thisMany@, @lower@ and @list@.
--
-- >>> parse surnameParser "Abcdef"
-- Result >< "Abcdef"
--
-- >>> isErrorResult (parse surnameParser "Abc")
-- True
--
-- >>> isErrorResult (parse surnameParser "abc")
-- True
surnameParser ::
  Parser Chars
surnameParser =
  -- tip: upper > thisMany 5 lower > list lower
  --
  -- u <- upper
  -- r <- thisMany 5 lower
  -- s <- list lower
  -- value (u :. r ++ s)
  --
  -- [| 
  --    (\u r s -> u:.r++s)
  --    upper 
  --    (thisMany 5 lower) 
  --    (list lower) 
  -- |]
  fbindParser upper (\u ->
  fbindParser (thisMany 5 lower) (\r ->
  fbindParser (list lower) (\s ->
  valueParser (u :. r ++ s))))

-- | Write a parser for Person.smoker.
--
-- /Smoker: character that must be @'y'@ or @'n'@/
--
-- /Tip:/ Use @is@ and @(|||)@./
--
-- >>> parse smokerParser "yabc"
-- Result >abc< 'y'
--
-- >>> parse smokerParser "nabc"
-- Result >abc< 'n'
--
-- >>> isErrorResult (parse smokerParser "abc")
-- True 
smokerParser ::
  Parser Char
smokerParser =
  -- it is 'y' |OR| it is 'n'
  is 'y' ||| is 'n'

-- | Write part of a parser for Person.phoneBody.
-- This parser will only produce a string of digits, dots or hyphens.
-- It will ignore the overall requirement of a phone number to
-- start with a digit and end with a hash (#).
--
-- /Phone: string of digits, dots or hyphens .../
--
-- /Tip:/ Use @list@, @digit@, @(|||)@ and @is@.
--
-- >>> parse phoneBodyParser "123-456"
-- Result >< "123-456"
--
-- >>> parse phoneBodyParser "123-4a56"
-- Result >a56< "123-4"
-- 
-- >>> parse phoneBodyParser "a123-456"
-- Result >a123-456< ""
phoneBodyParser ::
  Parser Chars
phoneBodyParser =
  -- tip: 0 or many (digit |OR| is dot |OR| is hyphen)
  list (digit ||| is '.' ||| is '-')

-- | Write a parser for Person.phone.
--
-- /Phone: ... but must start with a digit and end with a hash (#)./
--
-- /Tip:/ Use @bindParser@, @valueParser@, @digit@, @phoneBodyParser@ and @is@.
--
-- >>> parse phoneParser "123-456#"
-- Result >< "123-456"
--
-- >>> parse phoneParser "123-456#abc"
-- Result >abc< "123-456"
--
-- >>> isErrorResult (parse phoneParser "123-456")
-- True
--
-- >>> isErrorResult (parse phoneParser "a123-456")
-- True
phoneParser ::
  Parser Chars
phoneParser =
  -- d <- digit
  -- b <- phoneBodyParser
  -- _ <- is '#'
  -- value (d :. b)
  fbindParser digit (\d ->
  fbindParser phoneBodyParser (\b ->
  -- fbindParser (is '#') (\_ ->)
  is '#' >>> (
  valueParser (d :. b))))

-- | Write a parser for Person.
--
-- /Tip:/ Use @bindParser@,
--            @valueParser@,
--            @(>>>)@,
--            @ageParser@,
--            @firstNameParser@,
--            @surnameParser@,
--            @smokerParser@,
--            @phoneParser@.
--
-- >>> isErrorResult (parse personParser "")
-- True
--
-- >>> isErrorResult (parse personParser "12x Fred Clarkson y 123-456.789#")
-- True
--
-- >>> isErrorResult (parse personParser "123 fred Clarkson y 123-456.789#")
-- True
--
-- >>> isErrorResult (parse personParser "123 Fred Cla y 123-456.789#")
-- True
--
-- >>> isErrorResult (parse personParser "123 Fred clarkson y 123-456.789#")
-- True
--
-- >>> isErrorResult (parse personParser "123 Fred Clarkson x 123-456.789#")
-- True
--
-- >>> isErrorResult (parse personParser "123 Fred Clarkson y 1x3-456.789#")
-- True
--
-- >>> isErrorResult (parse personParser "123 Fred Clarkson y -123-456.789#")
-- True
--
-- >>> isErrorResult (parse personParser "123 Fred Clarkson y 123-456.789")
-- True
--
-- >>> parse personParser "123 Fred Clarkson y 123-456.789#"
-- Result >< Person {age = 123, firstName = "Fred", surname = "Clarkson", smoker = 'y', phone = "123-456.789"}
--
-- >>> parse personParser "123 Fred Clarkson y 123-456.789# rest"
-- Result > rest< Person {age = 123, firstName = "Fred", surname = "Clarkson", smoker = 'y', phone = "123-456.789"}
personParser ::
  Parser Person
personParser =
  -- a  <- ageParser
  -- _  <- spaces1
  -- fn <- firstNameParser
  -- _  <- spaces1
  -- sn <- surnameParser
  -- _  <- spaces1  
  -- s  <- smokerParser
  -- _  <- spaces1
  -- p  <- phoneParser
  do
     a <- ageParser
     spaces1
     fn <- firstNameParser 
     _ <- spaces1
     sn <- surnameParser
     _ <- spaces1
     s <- smokerParser
     _ <- spaces1
     p <- phoneParser
     valueParser (Person a fn sn s p)

-- Make sure all the tests pass!


-- | Write a Functor instance for a @Parser@.
-- /Tip:/ Use @bindParser@ and @valueParser@.
instance Functor Parser where
  -- (<$>) :: (a -> b) -> Parser a -> Parser b
  (<$>) f pa = do
    a <- pa
    valueParser (f a)
  -- (<$>) :: (a -> b) -> Parser a -> Parser b

-- | Write a Apply instance for a @Parser@.
-- /Tip:/ Use @bindParser@ and @valueParser@.
instance Apply Parser where
  -- (<$>) ::        (a -> b) -> Parser a -> Parser b
  -- (<*>) :: Parser (a -> b) -> Parser a -> Parser b
  -- (=<<) :: (a -> Parser b) -> Parser a -> Parser b
  (<*>) pf pa =
    do f <- pf
       a <- pa
       valueParser (f a)
    
-- | Write an Applicative functor instance for a @Parser@.
instance Applicative Parser where
  pure =
    error "todoe"

-- | Write a Bind instance for a @Parser@.
instance Bind Parser where
  (=<<) =
    bindParser

instance Monad Parser where
