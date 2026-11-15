# frozen_string_literal: true

require "test/unit"
require_relative "../lib/engtagger/tokenizer"

class TestTokenizer < Test::Unit::TestCase
  T = EngTagger::Tokenizer

  def assert_tokens(expected, text)
    assert_equal(expected, T.tokenize(text), text)
  end

  def test_contractions_split_ptb_style
    assert_tokens(%w[I 'm here], "I'm here")
    assert_tokens(%w[did n't], "didn't")
    assert_tokens(%w[ca n't], "can't")
    assert_tokens(%w[we 're all], "we're all")
    assert_tokens(%w[can not], "cannot")
  end

  def test_possessives_and_quotes
    assert_tokens(%w[Alice 's cat], "Alice's cat")
    assert_tokens(["the", "boys", "'", "toys"], "the boys' toys")
    assert_tokens(["O'Brien", "arrived"], "O'Brien arrived")
  end

  def test_abbreviations_keep_their_periods
    assert_tokens(["Dr.", "Smith", "left", "."], "Dr. Smith left.")
    assert_tokens(["The", "U.S.", "economy"], "The U.S. economy")
    assert_tokens(["George", "W.", "Bush"], "George W. Bush")
  end

  def test_hyphens_split_except_bound_prefixes
    assert_tokens(%w[well - known], "well-known")
    assert_tokens(["e-book"], "e-book")
    assert_tokens(["pre-owned"], "pre-owned")
  end

  def test_numbers_urls_and_emails_stay_whole
    assert_tokens(["1,000.50"], "1,000.50")
    assert_tokens(["12/25/2010"], "12/25/2010")
    assert_tokens(["https://example.com/a?b=1"], "https://example.com/a?b=1")
    assert_tokens(["a.b@example.com"], "a.b@example.com")
    assert_tokens(["$", "3.50"], "$3.50")
  end

  def test_every_token_is_a_substring_of_the_input
    text = %(Dr. Smith didn't pay $3.50 for the well-known e-book -- "really"?)
    T.tokenize_spans(text).each do |tok, start, stop|
      assert_equal(tok, text[start...stop], "span mismatch for #{tok.inspect}")
    end
  end

  def test_spans_count_characters_in_multibyte_text
    text = "Café déjà vu — naïve “résumé” at http://example.com/é. 日本語 😀 ok"
    T.tokenize_spans(text).each do |tok, start, stop|
      assert_equal(tok, text[start...stop], "span mismatch for #{tok.inspect}")
    end
  end

  def test_urls_shed_trailing_sentence_punctuation
    assert_tokens(["http://example.com/a.b", ")", "."], "http://example.com/a.b).")
    assert_tokens(["Visit", "http://example.com/a", ",", "then"], "Visit http://example.com/a, then")
  end

  def test_spans_are_ordered_and_non_overlapping
    text = "She said (loudly): it's 20% off!"
    spans = T.tokenize_spans(text)
    spans.each_cons(2) { |(_, _, a_end), (_, b_start, _)| assert_operator(a_end, :<=, b_start) }
    assert_equal(text.delete(" "), spans.map(&:first).join.delete(" "))
  end

  def test_candidates_that_fail_are_still_found_at_later_starts
    assert_tokens(["ab", ".", "c.d"], "ab.c.d")
    assert_tokens(["_", "abc@example.com"], "_abc@example.com")
    assert_tokens(["a", "_", "report.pdf"], "a_ report.pdf")
    assert_tokens(["x", ".", ".", "example.com"], "x. .example.com")
    assert_tokens(["a", "_", "a", "_", "U.S."], "a_a_ U.S.")
  end

  def test_empty_and_whitespace_input
    assert_empty(T.tokenize(""))
    assert_empty(T.tokenize("   \n\t "))
  end
end
