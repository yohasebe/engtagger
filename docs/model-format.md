# ETM2 — EngTagger packed model format

`lib/engtagger/model.etm.gz` holds the part-of-speech model in this format.
`EngTagger::Model` reads it; `EngTagger::Model::Builder` writes it.

## Contents

A model is three things:

* **classes** — the tag inventory. A tag's position in the sorted list is its
  tag id.
* **tag dictionary** — words that always take one tag and skip scoring.
* **weights** — for each feature string, a list of postings
  `(tag id, weight)`.

Feature strings are stored as they are and looked up by their bytes, so a
feature that is not in the model never receives another feature's weights.

Weights are stored as `int16` at a fixed scale of 512 (one step is 1/512).
Every weight shares that scale, so tag scores are summed and compared as
integers. The builder raises instead of clipping when a weight does not fit.

## Layout

Little-endian throughout. Section order is fixed; there is no directory.

```
offset  type        field
0       char[4]     magic "ETM2"
4       u16         format_version = 2
6       u16         flags (bit0 = int16 quantized weights; rest reserved 0)
8       u16         weight_scale (512)
10      u16         n_classes
12      u32         n_features
16      u32         n_postings
20      u32         n_tagdict
24      u32         keys_bytes (size of the keys section)
28      ...         sections follow
```

| section | encoding |
|---|---|
| classes | `n_classes` × [`u8` len, UTF-8 bytes], in tag id order |
| tagdict | `n_tagdict` × [`u8` len, UTF-8 bytes, `u8` tag id], ascending by word bytes |
| keys | `n_features` × [feature bytes, `0x00`], ascending by feature bytes |
| counts | `n_features` × `u8` — postings per feature, in key order |
| postings | `n_postings` × [`u8` tag id, `i16` weight] — grouped per feature in key order, ascending by tag id |

A feature is neither empty nor contains a `0x00` byte, and has at most 255
postings; a model has at most 256 classes. The builder rejects input outside
these limits.

## Reading

The reader accepts the packed bytes or a gzip file containing them. It rejects
a file whose magic or version differs, whose gzip checksum fails, or whose
weight scale is zero, or whose section sizes do not add up to the file size
exactly. Postings are not checked one by one: load model files only from
sources you trust.

## Building

```
ruby tools/convert_model.rb IN.bin OUT.etm.gz
```

`IN.bin` is the trainer's Marshal dump of `{weights:, tagdict:, classes:}`.
Marshal executes what it loads, so convert only dumps you produced yourself.

The converter leaves out the tag dictionary entries and word features whose
word contains an `@` next to another character (mail addresses, handles) or
is a URI (`EngTagger::Model::Builder::ADDRESS`). Other words of the training
text, including names and bare domain names, stay in the model as vocabulary.

Output is deterministic: sections are sorted, and the gzip container is
written with a zero mtime, no original name and a fixed compression level.
The converter prints two SHA-256 values — `packed` for the model content and
`file` for the gzip file. The `packed` value identifies a model across zlib
versions; the `file` value can differ between them.
