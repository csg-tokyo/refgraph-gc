# frozen_string_literal: true

require "test_helper"
require 'json'

class TestRefgraphSimple < Minitest::Test
  # include Refgraph

  class Foo
    def initialize(x)
      @link = x
    end
    def get()
      @link
    end
    def set(x)
      @link = x
    end
  end

  def make_a_chain(n, outbounds)
    if n > 0
      return Foo.new(make_a_chain(n - 1, outbounds))
    else
      rref = Jscall::RemoteRef.new(outbounds.size)
      outbounds << WeakRef.new(rref)
      return rref
    end
  end

  def make_chains(n)
    inbounds = []
    outbounds = []
    n.times do |i|
      inbounds << make_a_chain(i, outbounds)
    end
    pair = [inbounds[4].get.get.get, outbounds[6].__getobj__]
    inbounds[4].get.get.set(pair)
    pair = nil
    $gvar = inbounds[3].get.get
    $gvar2 = inbounds[8]
    # outbounds = []
    inbounds[9].get.get.set(nil)
    return Refgraph::HiddenRef.new(inbounds),
           Refgraph::HiddenRef.new(outbounds)
  end

  def test_simply_make()
    in_b, out_b = make_chains(11)
    m = Refgraph.simply_make(in_b, out_b, Refgraph::HiddenRef)
    j = JSON.parse(m)
    assert_equal 9, j.size
    assert_equal [3, 8], j["root"]
    assert_equal [0],  j["0"]
    assert_equal [4, 6], j["4"].sort
    assert_nil j["8"]
    assert_nil j["3"]
  end

  def test_simply_make_with_number()
    in_b, out_b = make_chains(11)
    in_b.__getobj__[1] = -1
    out_b.__getobj__[2] = -1
    m = Refgraph.simply_make(in_b, out_b, Refgraph::HiddenRef)
    j = JSON.parse(m)
    assert_equal 7, j.size
    assert_equal [3, 8], j["root"]
    assert_equal [0], j["0"]
    assert_equal [4, 6], j["4"].sort
    assert_nil j["1"]
    assert_nil j["2"]
    assert_nil j["8"]
    assert_nil j["3"]
  end

  def test_simply_make_large()
    in_b, out_b = make_chains(3001)
    m = Refgraph.simply_make(in_b, out_b, Refgraph::HiddenRef)
    j = JSON.parse(m)
    assert_equal 2999, j.size
    assert_equal [3, 8], j["root"]
    assert_equal [0], j["0"]
    assert_equal [4, 6], j["4"].sort
    assert_nil j["8"]
    assert_nil j["3"]
    assert_equal [2998], j["2998"]
  end

end

