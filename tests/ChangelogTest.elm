module ChangelogTest exposing (suite)

import Changelog
import Expect
import Test exposing (Test, describe, test)


sample : String
sample =
    """# Changelog

Intro.

## [Unreleased]

<!-- Draft
- feat: not shown
-->

### Added

- A **new** text: see [Romans](https://lyceum.quest/read/x) and `code`,
  continued here.

### Internal

- Hidden.

## [2026-10-13]

- First release.

## [2026-01-01]

### Internal

- Only internal.
"""


suite : Test
suite =
    describe "Changelog.parse"
        [ test "versions with something to show, newest first" <|
            \_ ->
                Changelog.parse sample
                    |> List.map .name
                    |> Expect.equal [ "Unreleased", "2026-10-13" ]
        , test "sections and plain items; Internal and comments left out" <|
            \_ ->
                Changelog.parse sample
                    |> List.head
                    |> Maybe.map .sections
                    |> Expect.equal (Just [ { title = "Added", items = [ "A new text: see Romans and code, continued here." ] } ])
        , test "bullets under a version without a section" <|
            \_ ->
                Changelog.parse sample
                    |> List.drop 1
                    |> List.head
                    |> Maybe.map .sections
                    |> Expect.equal (Just [ { title = "", items = [ "First release." ] } ])
        ]
