# frozen_string_literal: true

require "stringio"
require "test/unit"
require_relative "../lib/engtagger"

# The public API. Extraction methods operate on tagged strings; tagging
# methods run the bundled model on the README's examples.
class TestEngTagger < Test::Unit::TestCase
  UNTAGGED = <<~UNTAG
    Lisa Raines, a lawyer and director of government relations for the Industrial Biotechnical Association, contends that a judge well-versed in patent law and the concerns of research-based industries would have ruled otherwise. And Judge Newman, a former patent lawyer, wrote in her dissent when the court denied a motion for a rehearing of the case by the full court, "The panel's judicial legislation has affected an important high-technological industry, without regard to the consequences for research and innovation or the public interest." Says Ms. Raines, "[The judgement] confirms our concern that the absence of patent lawyers on the court could prove troublesome."
  UNTAG

  TAGGED = <<~TAG
    <nnp>Lisa</nnp> <nnp>Raines</nnp> <ppc>,</ppc> <det>a</det> <nn>lawyer</nn> <cc>and</cc> <nn>director</nn> <in>of</in> <nn>government</nn> <nns>relations</nns> <in>for</in> <det>the</det> <nnp>Industrial</nnp> <nnp>Biotechnical</nnp> <nnp>Association</nnp> <ppc>,</ppc> <vbz>contends</vbz> <in>that</in> <det>a</det> <nn>judge</nn> <jj>well-versed</jj> <in>in</in> <nn>patent</nn> <nn>law</nn> <cc>and</cc> <det>the</det> <nns>concerns</nns> <in>of</in> <jj>research-based</jj> <nns>industries</nns> <md>would</md> <vb>have</vb> <vbn>ruled</vbn> <rb>otherwise</rb> <pp>.</pp>
  TAG

  def setup
    @tagger = EngTagger.new
  end

  # Testing class methods

  def test_get_ext
    assert_nil(EngTagger.get_ext(nil))
    assert_equal(Regexp.new("<cd>[^<]+</cd>\\s*"), EngTagger.get_ext("cd"))
    assert_match(EngTagger.get_ext("cd"), "<cd>42</cd> ")
  end

  def test_explain_tag
    assert_equal("noun", EngTagger.explain_tag("nn"))
    assert_equal("verb_infinitive", EngTagger.explain_tag("vb"))
  end

  # Testing tagging methods

  def test_add_tags
    assert_instance_of(String, @tagger.add_tags(UNTAGGED))
    assert_equal("<nnp>Alice</nnp> <vbd>chased</vbd> <det>the</det> <nn>cat</nn> <pp>.</pp>",
                 @tagger.add_tags("Alice chased the cat."))
  end

  def test_add_tags_verbose
    assert_equal(
      "<noun_proper>Alice</noun_proper> " \
      "<verb_present_3sg_s_form>runs</verb_present_3sg_s_form> " \
      "<punctuation_sentence_ender>.</punctuation_sentence_ender>",
      @tagger.add_tags("Alice runs.", true)
    )
  end

  def test_tag_pairs
    assert_equal([["Alice", :nnp], ["chased", :vbd], ["the", :det], ["cat", :nn], [".", :pp]],
                 @tagger.tag_pairs("Alice chased the cat."))
  end

  def test_ptb_tagset
    ptb = EngTagger.new(tagset: :ptb)
    assert_equal([["Alice", :NNP], ["chased", :VBD], ["the", :DT], ["cat", :NN], [".", :"."]],
                 ptb.tag_pairs("Alice chased the cat."))
    assert_equal("I/PRP woke/VBD up/RP to/IN the/DT sound/NN of/IN pouring/VBG rain/NN ./.",
                 ptb.get_readable("I woke up to the sound of pouring rain."))
    # add_tags stays on the XML-safe classic tagset by design
    assert_equal("<nn>cat</nn>", ptb.add_tags("cat"))
  end

  def test_assign_tag_tags_one_word_in_the_classic_tagset
    assert_equal("det", @tagger.assign_tag("pp", "the"))
    assert_equal("pp", @tagger.assign_tag("nn", "."))
    assert_equal(@tagger.assign_tag(nil, "cat"), @tagger.assign_tag("pp", "cat"))
    assert_equal("det", EngTagger.new(tagset: :ptb).assign_tag("pp", "the"))
  end

  def test_text_in_another_encoding_is_converted
    latin1 = "caf\u00e9 society".encode("ISO-8859-1")
    assert_equal(%w[café society], @tagger.tag_pairs(latin1).map(&:first))
    assert_match(/café/, @tagger.add_tags(latin1))
  end

  def test_retired_hmm_keys_are_ignored_with_a_warning
    warned = capture_stderr { EngTagger.new(relax: true) }
    assert_match(/:relax.*retired HMM engine/m, warned) if warned # warns only once per process
    assert_nothing_raised { EngTagger.new(unknown_word_tag: "nn").add_tags("Test.") }
  end

  # Testing extraction methods

  def test_get_noun_phrases
    assert_instance_of(Hash, @tagger.get_noun_phrases(TAGGED))
  end

  def test_get_nouns
    assert_instance_of(Hash, @tagger.get_nouns(TAGGED))
  end

  def test_get_verbs
    expected_result = { "have" => 1, "ruled" => 1, "contends" => 1 }
    assert_equal(expected_result, @tagger.get_verbs(TAGGED))
  end

  def test_get_adverbs
    assert_equal({ "otherwise" => 1 }, @tagger.get_adverbs(TAGGED))
  end

  def test_get_interrogatives
    tagged = "<wdt>Which</wdt> <ppc>,</ppc> <wdt>whatever</wdt> <ppc>,</ppc> <wp>who</wp> <ppc>,</ppc> <wp>whoever</wp> <ppc>,</ppc> <wrb>when</wrb> <cc>and</cc> <wrb>how</wrb> <vbp>are</vbp> <det>all</det> <nns>examples</nns> <in>of</in> <nns>interrogatives</nns>"
    expected_result = { "when" => 1, "how" => 1, "Which" => 1,
                        "whatever" => 1, "who" => 1, "whoever" => 1 }
    assert_equal(expected_result, @tagger.get_interrogatives(tagged))
    assert_equal(expected_result, @tagger.get_question_parts(tagged))
  end

  def test_get_conjunctions
    expected_result = { "and" => 2, "of" => 2, "for" => 1, "that" => 1, "in" => 1 }
    assert_equal(expected_result, @tagger.get_conjunctions(TAGGED))
  end

  def test_get_proper_nouns
    test = "<nnp>BBC</nnp> <vbz>means</vbz> <nnp>British Broadcasting Corporation</nnp> <pp>.</pp>"
    assert_instance_of(Hash, @tagger.get_proper_nouns(test))
  end

  def test_get_readable
    result = @tagger.get_readable("I woke up to the sound of pouring rain.")
    assert_equal("I/PRP woke/VBD up/RP to/IN the/DET sound/NN of/IN pouring/VBG rain/NN ./PP",
                 result)
    # Angle brackets in the input are tokenized apart rather than kept as a
    # pseudo-tag, so they can no longer corrupt the output markup.
    assert_match(%r{bad/JJ}, @tagger.get_readable("I woke up with a <bad> word."))
  end

  def test_get_sentences
    result = @tagger.get_sentences(UNTAGGED)
    assert_equal(4, result.length)
    assert_match(/\ALisa Raines, a lawyer and director/, result.first)
  end

  def test_get_words
    @tagger.conf[:longest_noun_phrase] = 1
    result1 = @tagger.get_words(TAGGED)
    @tagger.conf[:longest_noun_phrase] = 10
    result2 = @tagger.get_words(TAGGED)
    assert_instance_of(Hash, result1)
    assert_instance_of(Hash, result2)
  end

  def test_get_noun_phrases_honors_the_length_limit_on_long_noun_runs
    run = "<nn>cat</nn> " * 8
    assert_equal({ "cat" => 8, "cat cat" => 1, "cat cat cat" => 1 },
                 EngTagger.new(longest_noun_phrase: 3).get_noun_phrases(run))
    assert_equal({ "cat" => 8 }, EngTagger.new(longest_noun_phrase: 1).get_noun_phrases(run))
  end

  def test_get_max_noun_phrases
    assert_instance_of(Hash, @tagger.get_max_noun_phrases(TAGGED))
  end

  def test_get_max_noun_regex
    assert_instance_of(Regexp, @tagger.send(:get_max_noun_regex))
  end

  # Testing utility methods

  def test_stem
    old = @tagger.conf[:stem]
    @tagger.conf[:stem] = true
    assert_equal("get", @tagger.stem("gets"))
    @tagger.conf[:stem] = old
    assert_equal("gets", @tagger.stem("gets"))
  end

  def test_strip_tags
    assert_instance_of(String, @tagger.send(:strip_tags, TAGGED))
  end

  def test_valid_text
    assert(!@tagger.send(:valid_text, nil))
    assert(@tagger.send(:valid_text, "this is test text"))
    assert(!@tagger.send(:valid_text, ""))
  end

  def test_valid_text_debug_message
    old_debug = @tagger.conf[:debug]
    @tagger.conf[:debug] = true
    out = StringIO.new
    orig_stdout = $stdout
    $stdout = out
    begin
      assert(!@tagger.send(:valid_text, nil))
    ensure
      $stdout = orig_stdout
      @tagger.conf[:debug] = old_debug
    end
    assert_match(/uninitialized variable/, out.string)
  end

  def test_override_default_params
    tagger = EngTagger.new(longest_noun_phrase: 3)
    assert_equal 3, tagger.conf[:longest_noun_phrase]
  end

  private

  def capture_stderr
    orig = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = orig
  end
end
