# Sources of the silver training text

The model bundled with EngTagger 2.0 was trained on the Universal Dependencies
English Web Treebank and on sentences taken from Wikipedia, Wikinews and
Stack Exchange that were tagged automatically. This directory lists every
article and post those sentences came from.

Model file: `lib/engtagger/model.etm.gz`,
SHA-256 `9666bfddb1655140b1fbfcf6fda2197d4c111e19df0bbc8c29e88c42c6c92a1e`.

## Files

Tab-separated, UTF-8, one header row. `sentences` is the number of sentences
used from that article or post.

| File | Rows | Sentences | Columns |
|---|---|---|---|
| `wikipedia.tsv` | 6,336 | 9,982 | title, url, page_id, revision_id, revision_url, revision_timestamp, license, sentences |
| `wikinews.tsv` | 5,409 | 6,976 | title, url, page_id, revision_id, revision_url, revision_timestamp, published, license, sentences |
| `stackexchange.tsv` | 14,382 | 14,995 | site, post_id, type, url, author, author_url, created, last_edited, license, sentences |

## Licences

| Source | Licence | Attribution |
|---|---|---|
| Wikipedia | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | Wikipedia contributors; `url` leads to the article and its history, `revision_url` to the revision used |
| Wikinews | Public domain before 2005-09-25, [CC BY 2.5](https://creativecommons.org/licenses/by/2.5/) until 2024-12-15, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) after, by publication date | Wikinews; `url` and `revision_url` as above |
| Stack Exchange | [CC BY-SA 2.5](https://creativecommons.org/licenses/by-sa/2.5/), [3.0](https://creativecommons.org/licenses/by-sa/3.0/) or [4.0](https://creativecommons.org/licenses/by-sa/4.0/), per post as recorded in the data dump | `author` and `author_url`; `url` leads to the post and its revision history |

The `license` column gives the licence of each row. For Wikinews it follows
the `published` date; rows without a recognised date name all three
possibilities. Posts by deleted Stack Exchange accounts have no `author_url`.

## Snapshots

| Source | Snapshot | Latest content |
|---|---|---|
| Wikipedia | English Wikipedia `pages-articles` dump, first part | 2026-07-06 |
| Wikinews | English Wikinews `pages-articles` dump | 2026-05-13 |
| Stack Exchange | data dumps of the Cooking, Movies & TV and Travel sites | 2024-03-31 |

## Changes made to the text

Sentences were extracted from the article or post body, split into tokens and
tagged with Penn Treebank part-of-speech tags by Claude Sonnet 5
(`claude-sonnet-5`, Anthropic) in July 2026. The text itself was not edited.
Neither the original authors nor Anthropic endorse the model.
