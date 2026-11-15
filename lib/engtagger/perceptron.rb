# frozen_string_literal: true

require_relative "model"
require_relative "tokenizer"

class EngTagger
  # Averaged-perceptron part-of-speech tagger (Honnibal-style): greedy
  # left-to-right decoding over local features, with a tag dictionary short-
  # circuiting frequent unambiguous words.
  #
  # Only inference is here; training lives outside the gem. The feature
  # strings built below are the keys of the model's weights, so they must stay
  # byte-identical to the ones the model was trained with.
  #
  # Tags are standard Penn Treebank (as used by Universal Dependencies XPOS),
  # not the modified tagset of the classic EngTagger engine. See
  # `EngTagger::Perceptron::LEGACY_TAGS` for the mapping between them.
  class Perceptron
    START = ["-START-", "-START2-"].freeze
    ENDING = ["-END-", "-END2-"].freeze

    DEFAULT_MODEL = File.join(File.dirname(__FILE__), "model.etm.gz")

    # PTB/UD tag -> classic EngTagger tag. The classic tagset renames a few
    # categories for XML-tag safety (DET for DT, PRPS for PRP$) and splits
    # punctuation into named classes.
    LEGACY_TAGS = {
      "DT" => "det", "PRP$" => "prps", "WP$" => "wps", "PRP" => "prp",
      "." => "pp", "," => "ppc", ":" => "pps", "``" => "ppl", "''" => "ppr",
      "$" => "ppd", "#" => "ppd", "-LRB-" => "lrb", "-RRB-" => "rrb",
      # UD additions with no classic equivalent
      "HYPH" => "ppc", "NFP" => "sym", "AFX" => "jj", "ADD" => "nn",
      "GW" => "nn", "XX" => "sym"
    }.freeze

    attr_reader :model

    # model: path to a packed .etm/.etm.gz file, or an EngTagger::Model.
    def initialize(model: DEFAULT_MODEL)
      @model = model.is_a?(Model) ? model : Model.read(model)
      @classes = @model.classes
      @tagdict = @model.tagdict
    end

    # Tag a string. Returns [[token, tag], ...] with PTB tags. Text in another
    # encoding is converted to UTF-8 first.
    def tag(text)
      tokens = Tokenizer.tokenize(text.encode(Encoding::UTF_8))
      tokens.zip(tag_tokens(tokens))
    end

    # Tag an already-tokenized sentence or text. Returns an array of tags.
    def tag_tokens(tokens)
      context = build_context(tokens)
      prev = "-START-"
      prev2 = "-START2-"
      scores = Array.new(@classes.size, 0)
      tokens.each_index.map do |k|
        word = tokens[k]
        t = @tagdict[normalize(word)] || predict(features(k, word, context, prev, prev2), scores)
        prev2 = prev
        prev = t
        t
      end
    end

    # XML-style output, matching the classic engine's shape:
    # "<nnp>Alice</nnp> <vbd>chased</vbd> ..."
    #
    # legacy: emit classic EngTagger tags instead of PTB ones.
    def add_tags(text, legacy: false)
      tag(text).map do |word, t|
        t = legacy_tag(t) if legacy
        "<#{t}>#{word}</#{t}>"
      end.join(" ")
    end

    # "Alice/NNP chased/VBD the/DET ..."
    def get_readable(text)
      tag(text).map { |word, t| "#{word}/#{t}" }.join(" ")
    end

    # Classic-tagset equivalent of a PTB tag (downcased, as the classic engine
    # emits). Unmapped tags simply downcase: NN -> nn, VBD -> vbd.
    def legacy_tag(ptb_tag)
      LEGACY_TAGS[ptb_tag] || ptb_tag.downcase
    end

    private

    def normalize(word)
      if word.include?("-") && word[0] != "-"
        "!HYPHEN"
      elsif word =~ /\A\d{4}\z/
        "!YEAR"
      elsif word =~ /\A\d/
        "!DIGITS"
      else
        word.downcase
      end
    end

    def build_context(tokens)
      START + tokens.map { |w| normalize(w) } + ENDING
    end

    # Collapsed word-shape pattern: "McDonald's" -> "XxXx'x", "3.5" -> "d.d"
    def shape(word)
      word.gsub(/[A-Z]+/, "X").gsub(/[a-z]+/, "x").gsub(/\d+/, "d")[0, 8]
    end

    def features(idx, word, context, prev, prev2)
      i = idx + 2 # offset for START padding
      w = word.downcase
      suf = w[-3..] || w
      f = ["bias", "i word #{context[i]}",
           "i suffix #{suf}",
           "i suffix4 #{w[-4..] || w}",
           "i pref1 #{w[0]}",
           "i pref2 #{w[0, 2]}",
           "i pref3 #{w[0, 3]}",
           "i shape #{shape(word)}"]
      f << "i first" if idx.zero?
      f << "i shape upper" if word =~ /\A[A-Z]/
      f << "i shape allcaps" if word =~ /\A[A-Z]+\z/ && word.size > 1
      f.concat [
        "i-1 word #{context[i - 1]}",
        "i-1 suffix #{context[i - 1][-3..] || context[i - 1]}",
        "i-2 word #{context[i - 2]}",
        "i+1 word #{context[i + 1]}",
        "i+1 suffix #{context[i + 1][-3..] || context[i + 1]}",
        "i+2 word #{context[i + 2]}",
        "i-1 tag #{prev}",
        "i-2 tag #{prev2}",
        "i tag+i-2 tag #{prev} #{prev2}",
        "i-1 tag+i word #{prev} #{context[i]}",
        "i-1 tag+i suffix #{prev} #{suf}"
      ]
      f
    end

    # Scores accumulate as integers: every weight shares one quantization
    # scale, so the scale cancels out of the comparison. Ties fall to the
    # lexicographically last tag, matching the trainer's `max_by { [score, t] }`.
    # `scores` is a scratch array owned by the caller, so one tagger can serve
    # several threads.
    def predict(feats, scores)
      scores.fill(0)
      feats.each do |feature|
        @model.each_posting(feature) { |tag_id, weight| scores[tag_id] += weight }
      end
      best = 0
      best_score = scores[0]
      1.upto(scores.size - 1) do |i|
        next if scores[i] < best_score

        best = i
        best_score = scores[i]
      end
      @classes[best]
    end
  end
end
