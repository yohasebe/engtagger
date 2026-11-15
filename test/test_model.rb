# frozen_string_literal: true

require "test/unit"
require "tmpdir"
require_relative "../lib/engtagger/model_builder"

class TestModel < Test::Unit::TestCase
  CLASSES = %w[jj nn nnp vbd].freeze

  WEIGHTS = {
    "bias" => { "nn" => 0.5, "jj" => -0.25 },
    "i word alice" => { "nnp" => 3.125, "nn" => -1.0 },
    "i suffix ing" => { "vbd" => 0.001, "nn" => 2.5 }
  }.freeze

  TAGDICT = { "the" => "jj", "alice" => "nnp" }.freeze

  def build(path, **opts)
    EngTagger::Model::Builder.new(
      weights: WEIGHTS, tagdict: TAGDICT, classes: CLASSES, **opts
    ).write(path)
  end

  def test_omit_words_leaves_matching_words_out_of_the_model
    weights = WEIGHTS.merge(
      "i word a.person@example.com" => { "nn" => 1.0 },
      "i+1 word http://example.com/x" => { "nn" => 1.0 },
      "i-1 tag+i word nn @handle" => { "nnp" => 1.0 },
      "i shape x@x.x" => { "nn" => 1.0 },
      "i suffix com" => { "nn" => 1.0 }
    )
    tagdict = TAGDICT.merge("a.person@example.com" => "nn", "@" => "nn")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.etm")
      stats = EngTagger::Model::Builder.new(
        weights: weights, tagdict: tagdict, classes: CLASSES, omit_words: EngTagger::Model::Builder::ADDRESS
      ).write(path)
      model = EngTagger::Model.read(path)

      assert_equal(3, stats[:omitted_features])
      assert_equal(1, stats[:omitted_words])
      assert_equal(WEIGHTS.size + 2, model.size)
      assert_equal(0.0, model.weight("i word a.person@example.com", "nn"))
      assert_equal(1.0, model.weight("i shape x@x.x", "nn"))
      assert_equal(1.0, model.weight("i suffix com", "nn"))
      assert_equal(TAGDICT.merge("@" => "nn"), model.tagdict)
    end
  end

  def test_rejects_zero_weight_scale
    blob = EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: TAGDICT, classes: CLASSES).pack
    blob[8, 2] = [0].pack("v")
    assert_raise(EngTagger::Model::Error) { EngTagger::Model.new(blob) }
  end

  def test_bundled_model_carries_no_address_words
    model = EngTagger::Model.read(File.expand_path("../lib/engtagger/model.etm.gz", __dir__))
    address = EngTagger::Model::Builder::ADDRESS
    words = model.tagdict.keys
    model.each_feature { |feature| words << feature[EngTagger::Model::Builder::WORD_FEATURE, 1] }

    assert_empty(words.compact.grep(address))
  end

  def with_model(**opts)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.etm")
      stats = build(path, **opts)
      yield EngTagger::Model.read(path), stats, path
    end
  end

  def test_round_trip_preserves_structure
    with_model do |model, _stats, _path|
      assert_equal(CLASSES, model.classes)
      assert_equal(TAGDICT, model.tagdict)
      assert_equal(WEIGHTS.size, model.size)
    end
  end

  def test_weights_survive_quantization
    with_model do |model, _stats, _path|
      WEIGHTS.each do |feature, tag_weights|
        tag_weights.each do |tag, weight|
          assert_in_delta(weight, model.weight(feature, tag), 0.001,
                          "#{feature} / #{tag}")
        end
      end
    end
  end

  def test_absent_feature_and_tag_are_zero
    with_model do |model, _stats, _path|
      assert_equal(0.0, model.weight("no such feature", "nn"))
      assert_equal(0.0, model.weight("bias", "vbd"))
      assert_equal(0.0, model.weight("bias", "no-such-tag"))
    end
  end

  def test_each_posting_yields_only_that_features_postings
    with_model do |model, _stats, _path|
      seen = []
      model.each_posting("bias") { |tag_id, w| seen << [model.classes[tag_id], w] }
      assert_equal([["jj", -128], ["nn", 256]], seen.sort)
      assert_nil(model.each_posting("absent") { flunk("yielded for absent feature") })
    end
  end

  def test_gzipped_file_is_detected
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.etm.gz")
      build(path)
      assert_equal("\x1f\x8b".b, File.binread(path, 2))
      assert_equal(CLASSES, EngTagger::Model.read(path).classes)
    end
  end

  def test_lookup_is_by_bytes_whatever_the_string_encoding
    weights = { "i word café" => { "nn" => 1.0 } }
    blob = EngTagger::Model::Builder.new(weights: weights, tagdict: {}, classes: CLASSES).pack
    model = EngTagger::Model.new(blob)
    assert_in_delta(1.0, model.weight("i word café".b, "nn"), 0.001)
    assert_equal(0.0, model.weight("i word cafe", "nn"))
  end

  def test_output_does_not_depend_on_input_order
    reordered = EngTagger::Model::Builder.new(
      weights: WEIGHTS.to_a.reverse.to_h, tagdict: TAGDICT.to_a.reverse.to_h, classes: CLASSES.reverse
    ).pack
    assert_equal(EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: TAGDICT, classes: CLASSES).pack,
                 reordered)
  end

  def test_pruning_drops_small_weights_and_empty_features
    with_model(prune: 0.6) do |model, stats, _path|
      assert_equal(0.0, model.weight("i suffix ing", "vbd")) # 0.001 pruned
      assert_in_delta(2.5, model.weight("i suffix ing", "nn"), 0.001)
      assert_equal(1, stats[:dropped_features]) # "bias": both weights below 0.6
      assert_equal(3, stats[:dropped_postings])
    end
  end

  def test_builder_rejects_features_it_cannot_store
    ["", "i word a\0b"].each do |feature|
      assert_raise(EngTagger::Model::Error) do
        EngTagger::Model::Builder.new(
          weights: { feature => { "nn" => 1.0 } }, tagdict: {}, classes: CLASSES
        ).pack
      end
    end
  end

  def test_gzip_output_is_byte_identical_across_builds
    # gzip embeds an mtime by default, which would change the SHA-256 of an
    # otherwise identical model between builds and break hash verification of
    # the published file.
    Dir.mktmpdir do |dir|
      first = File.join(dir, "a.etm.gz")
      second = File.join(dir, "b.etm.gz")
      stats = build(first)
      sleep 1.1 # cross a filesystem timestamp boundary
      build(second)
      assert_equal(File.binread(first), File.binread(second))
      assert_equal(stats[:file_sha256], Digest::SHA256.file(second).hexdigest)
      assert_equal("\0\0\0\0".b, File.binread(first, 4, 4), "gzip header mtime must be zero")
    end
  end

  def test_reports_both_content_and_file_hashes
    # For an uncompressed file the two coincide; for a gzipped one the packed
    # hash still identifies the model content inside the container.
    with_model do |_model, stats, path|
      assert_equal(Digest::SHA256.file(path).hexdigest, stats[:file_sha256])
      assert_equal(stats[:packed_sha256], stats[:file_sha256])
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "hashed.etm.gz")
      stats = build(path)
      assert_equal(Digest::SHA256.file(path).hexdigest, stats[:file_sha256])
      assert_not_equal(stats[:packed_sha256], stats[:file_sha256])
      assert_equal(stats[:packed_sha256],
                   Digest::SHA256.hexdigest(Zlib::GzipReader.open(path, &:read).b))
    end
  end

  def test_builder_rejects_oversized_length_fields
    long = "x" * 256
    assert_raise(EngTagger::Model::Error) do
      EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: TAGDICT, classes: CLASSES + [long])
    end
    assert_raise(EngTagger::Model::Error) do
      EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: { long => "nn" }, classes: CLASSES)
    end
    assert_raise(EngTagger::Model::Error) do
      EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: TAGDICT,
                                    classes: (1..257).map(&:to_s))
    end
    assert_raise(EngTagger::Model::Error) do
      EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: { "the" => "zz" }, classes: CLASSES)
    end
  end

  def test_builder_rejects_weight_overflow
    assert_raise(EngTagger::Model::Error) do
      EngTagger::Model::Builder.new(
        weights: { "big" => { "nn" => 100.0 } }, tagdict: {}, classes: CLASSES
      ).pack
    end
  end

  def test_reader_rejects_foreign_file
    assert_raise(EngTagger::Model::Error) { EngTagger::Model.new("not a model at all".b) }
  end

  def test_reader_rejects_other_format_versions
    blob = EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: TAGDICT, classes: CLASSES).pack
    [1, 3].each do |version|
      other = blob.dup
      other[4, 2] = [version].pack("v")
      assert_raise(EngTagger::Model::Error) { EngTagger::Model.new(other) }
    end
    assert_raise(EngTagger::Model::Error) { EngTagger::Model.new("ETM1".b + blob.byteslice(4..)) }
  end

  def test_reader_rejects_damaged_files
    blob = EngTagger::Model::Builder.new(weights: WEIGHTS, tagdict: TAGDICT, classes: CLASSES).pack
    assert_raise(EngTagger::Model::Error) { EngTagger::Model.new(blob.byteslice(0, blob.bytesize - 1)) }
    assert_raise(EngTagger::Model::Error) { EngTagger::Model.new(blob + "\0".b) }
    assert_raise(EngTagger::Model::Error) { EngTagger::Model.new(blob.byteslice(0, 20)) }

    more_features = blob.dup
    more_features[12, 4] = [WEIGHTS.size + 1].pack("V")
    assert_raise(EngTagger::Model::Error) { EngTagger::Model.new(more_features) }

    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.etm.gz")
      build(path)
      intact = File.binread(path)
      File.binwrite(path, intact.byteslice(0..-9)) # checksum footer cut off
      assert_raise(EngTagger::Model::Error) { EngTagger::Model.read(path) }
      flipped = intact.dup
      flipped.setbyte(flipped.bytesize / 2, flipped.getbyte(flipped.bytesize / 2) ^ 1)
      File.binwrite(path, flipped)
      assert_raise(EngTagger::Model::Error) { EngTagger::Model.read(path) }
    end
  end
end
