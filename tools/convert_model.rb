# frozen_string_literal: true

# Convert a trained model (Marshal dump of {weights:, tagdict:, classes:})
# into the packed ETM2 format shipped with the gem.
#
#   ruby tools/convert_model.rb IN.bin OUT.etm.gz [PRUNE]
#
# PRUNE (default 0.0) drops postings whose |weight| is below the threshold.
# Any pruning changes predictions, so it must be measured on dev before use.
#
# Mail addresses, "@" handles and URIs that occur as words in the training text
# are left out of the model (EngTagger::Model::Builder::ADDRESS).
require_relative "../lib/engtagger/model_builder"

src, dst, prune = ARGV
abort "usage: convert_model.rb IN.bin OUT.etm.gz [PRUNE]" unless src && dst

data = Marshal.load(File.binread(src))
builder = EngTagger::Model::Builder.new(
  weights: data[:weights], tagdict: data[:tagdict], classes: data[:classes],
  prune: (prune || 0.0).to_f, omit_words: EngTagger::Model::Builder::ADDRESS
)
stats = builder.write(dst)

mb = ->(bytes) { (bytes / 1e6).round(2) }
puts "source          #{File.basename(src)} (#{mb[File.size(src)]} MB)"
puts "features        #{stats[:features]} (dropped #{stats[:dropped_features]})"
puts "omitted         #{stats[:omitted_features]} features, #{stats[:omitted_words]} tagdict words (addresses)"
puts "postings        #{stats[:postings]} (dropped #{stats[:dropped_postings]})"
puts "packed          #{mb[stats[:packed_bytes]]} MB"
puts "written         #{File.basename(dst)} (#{mb[stats[:file_bytes]]} MB)"
# The packed hash identifies the model content, the file hash the file that
# ships. The gzip container is written deterministically, so re-running this
# reproduces both.
puts "sha256 packed   #{stats[:packed_sha256]}"
puts "sha256 file     #{stats[:file_sha256]}"
