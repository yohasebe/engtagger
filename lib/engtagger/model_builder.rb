# frozen_string_literal: true

require "digest"
require "zlib"
require_relative "model"

class EngTagger
  class Model
    # Converts a trainer's string-keyed weights into the packed ETM2 format.
    # Build-time only: the gem's runtime never loads this file.
    #
    #   EngTagger::Model::Builder.new(
    #     weights: weights, tagdict: tagdict, classes: classes
    #   ).write("model.etm.gz")
    class Builder
      # int16 at this scale covers weights up to +-64 in steps of 1/512; a
      # weight outside that range raises instead of being clipped.
      DEFAULT_SCALE = 512
      MAX_Q = 32_767

      # Words that are an address: anything around an "@" (mail addresses,
      # handles) and URIs.
      ADDRESS = /@.|.@|\A[a-z][a-z0-9+.-]*:\S|\Awww\./i

      # Features whose last field is a word of the tagged text.
      WORD_FEATURE = /\A(?:i|i[+-]\d|i-1 tag\+i) word (?:\S+ )?(\S+)\z/

      attr_reader :stats

      # prune: drop postings whose absolute weight is below this threshold
      # (0.0 keeps every posting). Features left with no postings are dropped
      # entirely.
      # omit_words: leave out the tag dictionary entries and word features
      # whose word matches this pattern (ADDRESS for a published model), so
      # the file does not carry those words from the training text. The tagger
      # then relies on the shape, prefix and suffix of such tokens.
      def initialize(weights:, tagdict:, classes:, scale: DEFAULT_SCALE, prune: 0.0, omit_words: nil)
        @omit_words = omit_words
        @weights = omit_words ? weights.reject { |feature, _| omitted?(feature[WORD_FEATURE, 1]) } : weights
        @tagdict = omit_words ? tagdict.reject { |word, _| omitted?(word) } : tagdict
        @omitted = { features: weights.size - @weights.size, words: tagdict.size - @tagdict.size }
        @classes = classes.sort
        @scale = scale
        @prune = prune
        @tag_ids = @classes.each_with_index.to_h
        @stats = { omitted_features: @omitted[:features], omitted_words: @omitted[:words] }
        validate_sections!
      end

      def write(path)
        blob = pack
        path.end_with?(".gz") ? write_gzipped(path, blob) : File.binwrite(path, blob)
        @stats[:packed_bytes] = blob.bytesize
        @stats[:file_bytes] = File.size(path)
        @stats[:packed_sha256] = Digest::SHA256.hexdigest(blob)
        @stats[:file_sha256] = Digest::SHA256.file(path).hexdigest
        @stats
      end

      # gzip stores an mtime in its header, so the default writer produces a
      # different file -- and a different SHA-256 -- every run. To keep the
      # file reproducible, mtime is pinned to 0, no orig_name is written and
      # the compression level is fixed.
      def write_gzipped(path, blob)
        File.open(path, "wb") do |file|
          gz = Zlib::GzipWriter.new(file, Zlib::BEST_COMPRESSION)
          gz.mtime = 0
          gz.write(blob)
          gz.close
        end
      end

      def pack
        entries = build_entries
        keys = keys_section(entries)
        header(entries, keys.bytesize) + classes_section + tagdict_section + keys +
          counts_section(entries) + postings_section(entries)
      end

      private

      def omitted?(word)
        word && @omit_words.match?(word)
      end

      # Every length in the format is a u8 and every tag id fits in a byte.
      # Overflowing either would wrap silently and produce a file that reads
      # back as garbage, so the limits are checked up front rather than
      # trusted.
      def validate_sections!
        count = @classes.size
        raise Model::Error, "model has #{count} classes; tag ids are u8 (max 256)" if count > 256

        too_long = @classes.find { |tag| tag.b.bytesize > 255 }
        raise Model::Error, "tag name longer than 255 bytes: #{too_long.inspect}" if too_long

        too_long = @tagdict.keys.find { |word| word.b.bytesize > 255 }
        raise Model::Error, "tagdict word longer than 255 bytes: #{too_long.inspect}" if too_long

        unknown = @tagdict.values.find { |tag| !@tag_ids.key?(tag) }
        raise Model::Error, "tagdict uses tag outside classes: #{unknown.inspect}" if unknown
      end

      # [[feature bytes, [[tag_id, quantized], ...]], ...] sorted bytewise by feature.
      def build_entries
        dropped_postings = 0
        entries = []
        @weights.each do |feature, tag_weights|
          postings = []
          tag_weights.each do |tag, weight|
            if weight.abs < @prune
              dropped_postings += 1
              next
            end
            postings << [@tag_ids.fetch(tag), quantize(weight)]
          end
          next if postings.empty?
          raise Model::Error, "feature has more than 255 postings: #{feature}" if postings.size > 255

          entries << [feature_key(feature), postings.sort_by!(&:first)]
        end
        entries.sort_by!(&:first)
        entries.each_cons(2) do |(a, _), (b, _)|
          raise Model::Error, "duplicate feature: #{a.inspect}" if a == b
        end

        @stats.update(features: entries.size, dropped_features: @weights.size - entries.size,
                      postings: entries.sum { |_, p| p.size }, dropped_postings: dropped_postings)
        entries
      end

      # Keys are stored NUL-terminated, so a feature can neither be empty nor
      # contain a NUL byte.
      def feature_key(feature)
        key = feature.b
        return key unless key.empty? || key.include?(KEY_TERMINATOR)

        raise Model::Error, "feature is empty or contains a NUL byte: #{feature.inspect}"
      end

      def quantize(weight)
        q = (weight * @scale).round
        raise Model::Error, "weight #{weight} overflows int16 at scale #{@scale}" if q.abs > MAX_Q

        q
      end

      def header(entries, keys_bytes)
        [MAGIC].pack("a4") +
          [FORMAT_VERSION, FLAG_QUANTIZED, @scale, @classes.size].pack("v4") +
          [entries.size, entries.sum { |_, p| p.size }, @tagdict.size, keys_bytes].pack("V4")
      end

      def classes_section
        @classes.map { |tag| [tag.bytesize].pack("C") + tag.b }.join
      end

      def tagdict_section
        @tagdict.map { |word, tag| [word.b, tag] }.sort_by(&:first).map do |bytes, tag|
          [bytes.bytesize].pack("C") + bytes + [@tag_ids.fetch(tag)].pack("C")
        end.join
      end

      def keys_section(entries)
        entries.map { |key, _| key + KEY_TERMINATOR }.join
      end

      def counts_section(entries)
        entries.map { |_, p| p.size }.pack("C*")
      end

      # entries is an Array of [key, postings] pairs, not a Hash --
      # rubocop's each_value suggestion does not apply here.
      def postings_section(entries)
        buf = +"".b
        entries.each do |_key, postings| # rubocop:disable Style/HashEachMethods
          postings.each { |tag_id, q| buf << [tag_id, q].pack("Cs<") }
        end
        buf
      end
    end
  end
end
