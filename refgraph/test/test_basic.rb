# frozen_string_literal: true

require "test_helper"

class TestRefgraph < Minitest::Test
  include Refgraph

  HR = HiddenRef

  # a[0] := a new object
  def element0(a)
    a[0] = Object.new
    return HiddenRef.new(a[0])
  end

  def test_reachability_ary_element
    a = []
    assert Refgraph.reachable(a, element0(a), HR)
  end

  def test_reachability_ary_element_from_root
    a = []
    assert Refgraph.reachable_from_root(element0(a), HR)
  end

  # a[0] := a hidden ref
  def hidden_element0(a)
    a[0] = Refgraph::HiddenRef.new(Object.new)
    return a[0]
  end

  def test_reachability_hidden_ary_element
    a = []
    refute Refgraph.reachable(a, hidden_element0(a), HR)
  end

  def test_reachability_hidden_ary_element_from_root
    a = []
    refute Refgraph.reachable_from_root(hidden_element0(a), HR)
  end

  def test_reachability_ary_from_element
    def set_0th_and_return_href_to_array()
      a = []
      a[0] = Object.new
      return HiddenRef.new(a)
    end

    a = set_0th_and_return_href_to_array()
    refute Refgraph.reachable(a.__getobj__[0], a, HR)
  end

  # a[0] := a weak ref
  def weak_element0(a)
    e = Object.new
    a[0] = WeakRef.new(e)
    return HiddenRef.new(e)
  end

  def test_reachability_ary_element_via_weakref
    a = []
    refute Refgraph.reachable(a, weak_element0(a), HR)
  end

  def test_reachability_ary_element_via_weakref_from_root
    a = []
    refute Refgraph.reachable_from_root(weak_element0(a), HR)
  end

  def test_reachability_localvar_from_root
    a = []
    assert Refgraph.reachable_from_root(HiddenRef.new(a), HR)
  end

  class MyRef
    def initialize(obj)
      @to = obj
    end
    def __getobj__()
      @to
    end
  end

  # a[0] := a weak ref
  def my_element0(a)
    e = Object.new
    a[0] = WeakRef.new(e)
    return MyRef.new(e)
  end

  def test_reachability_ary_element_via_myref
    a = []
    refute Refgraph.reachable(a, my_element0(a), MyRef)
  end
end
