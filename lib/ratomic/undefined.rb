# frozen_string_literal: true

module Ratomic
  # Internal sentinel object for future Hash-like APIs that need to distinguish
  # missing keys from explicit nil values.
  class Undefined
    # @return [String]
    def inspect
      "#<Undefined>"
    end
  end

  # Internal shareable missing-value sentinel.
  UNDEFINED = Ractor.make_shareable(Undefined.new)
end
