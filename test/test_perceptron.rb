# frozen_string_literal: true

require "test/unit"
require "fileutils"
require "tmpdir"
require_relative "../lib/engtagger/perceptron"
require_relative "../lib/engtagger/model_builder"

class TestPerceptron < Test::Unit::TestCase
  CLASSES = %w[det nn nnp vbd].freeze

  # A hand-built model exercising the decoder rather than any real linguistics:
  # "alice" is in the tag dictionary, "chased" scores as vbd, and everything
  # else falls back to the highest-scoring tag from the bias feature.
  WEIGHTS = {
    "bias" => { "nn" => 1.0 },
    "i word alice" => { "nnp" => 5.0 },
    "i word chased" => { "vbd" => 5.0 },
    "i word the" => { "det" => 5.0 },
    "i-1 tag det" => { "nn" => 2.0 }
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "tiny.etm")
    EngTagger::Model::Builder.new(
      weights: WEIGHTS, tagdict: { "alice" => "nnp" }, classes: CLASSES
    ).write(@path)
    @tagger = EngTagger::Perceptron.new(model: @path)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_tags_a_string_through_the_tokenizer
    assert_equal([%w[Alice nnp], %w[chased vbd], %w[the det], %w[cat nn]],
                 @tagger.tag("Alice chased the cat"))
  end

  def test_tagdict_short_circuits_scoring
    # "alice" is dictionary-tagged, so it keeps nnp even where the surrounding
    # features would push elsewhere.
    assert_equal(["nnp"], @tagger.tag_tokens(["Alice"]))
  end

  def test_unknown_words_fall_back_to_the_best_scoring_tag
    assert_equal(%w[nn nn], @tagger.tag_tokens(%w[qwertyx zxcvbn]))
  end

  # A model that yields the processor at every feature lookup, so concurrent
  # predictions interleave as tightly as the scheduler allows.
  class YieldingModel < EngTagger::Model
    def each_posting(feature, &block)
      Thread.pass
      super
    end
  end

  def test_one_tagger_serves_concurrent_threads
    tagger = EngTagger::Perceptron.new(model: YieldingModel.new(File.binread(@path)))
    sentences = [%w[Alice chased the cat], %w[the cat chased the dog], %w[qwertyx zxcvbn]]
    expected = sentences.map { |s| tagger.tag_tokens(s) }
    threads = Array.new(12) do |i|
      Thread.new { Array.new(50) { tagger.tag_tokens(sentences[i % sentences.size]) } }
    end
    threads.each_with_index do |thread, i|
      assert_equal([expected[i % sentences.size]], thread.value.uniq)
    end
  end

  def test_ties_go_to_the_lexicographically_last_tag
    # No feature fires for this token beyond bias, and with an all-zero score
    # vector the trainer's `max_by { |t| [score, t] }` picks the last class.
    Dir.mktmpdir do |dir|
      path = File.join(dir, "flat.etm")
      EngTagger::Model::Builder.new(
        weights: { "unused feature" => { "nn" => 1.0 } }, tagdict: {}, classes: CLASSES
      ).write(path)
      assert_equal(["vbd"], EngTagger::Perceptron.new(model: path).tag_tokens(["whatever"]))
    end
  end

  def test_add_tags_and_get_readable
    assert_equal("<nnp>Alice</nnp> <vbd>chased</vbd>", @tagger.add_tags("Alice chased"))
    assert_equal("Alice/nnp chased/vbd", @tagger.get_readable("Alice chased"))
  end

  def test_legacy_tag_mapping
    assert_equal("det", @tagger.legacy_tag("DT"))
    assert_equal("prps", @tagger.legacy_tag("PRP$"))
    assert_equal("pp", @tagger.legacy_tag("."))
    assert_equal("ppc", @tagger.legacy_tag(","))
    assert_equal("nn", @tagger.legacy_tag("NN"))
    assert_equal("vbg", @tagger.legacy_tag("VBG"))
  end

  def test_accepts_a_preloaded_model
    model = EngTagger::Model.read(@path)
    assert_equal(["nnp"], EngTagger::Perceptron.new(model: model).tag_tokens(["Alice"]))
  end

  # The bundled model with the feature extraction above: the README's example
  # sentence and one more.
  def test_bundled_model_tags_a_sentence
    tagger = EngTagger::Perceptron.new
    assert_equal("Alice/NNP chased/VBD the/DT big/JJ black/JJ cat/NN ./.",
                 tagger.get_readable("Alice chased the big black cat."))
    assert_equal(%w[PRP VBP RB VBN DT NN .],
                 tagger.tag("I have never seen the movie.").map(&:last))
  end

  def test_bundled_model_emits_classic_tags_in_legacy_mode
    # The classic extraction methods scan for these lowercase tags, so legacy
    # mode is what EngTagger#get_nouns and the other extraction methods rely on.
    assert_equal("<nnp>Alice</nnp> <vbd>chased</vbd> <det>the</det> <nn>cat</nn> <pp>.</pp>",
                 EngTagger::Perceptron.new.add_tags("Alice chased the cat.", legacy: true))
  end
end
