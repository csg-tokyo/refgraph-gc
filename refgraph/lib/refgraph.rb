# frozen_string_literal: true

require "weakref"
require_relative "refgraph/version"
require_relative "refgraph/refgraph"
require_relative "refgraph/jscall"

module Refgraph
  # A reference to an object that the Ruby GC visists
  # but Refgraph does not.
  class HiddenRef
    def initialize(obj)
      @to = obj
    end
    def __getobj__()
      @to
    end
  end
end
