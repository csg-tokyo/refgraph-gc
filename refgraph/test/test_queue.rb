# frozen_string_literal: true

require "test_helper"

class TestRefgraph < Minitest::Test
  include Refgraph

  # initial queue length: 1024 * 16

  def test_queue()
    size = 1024 * 16
    Refgraph::Queue.init
    (size + 100).times do |i|
      Refgraph::Queue.enqueue(i)
    end
    (size + 100).times do |i|
      assert i, Refgraph::Queue.dequeue()
    end
    assert Refgraph::Queue.empty
    Refgraph::Queue.free
  end

  def test_queue_enq_deq_enq_deq()
    size = 1024 * 16
    Refgraph::Queue.init
    22.times do |i|
      Refgraph::Queue.enqueue(i)
    end
    22.times do |i|
      assert i, Refgraph::Queue.dequeue()
    end
    assert Refgraph::Queue.empty
    (size + 100).times do |i|
      Refgraph::Queue.enqueue(i)
    end
    (size + 100).times do |i|
      assert i, Refgraph::Queue.dequeue()
    end
    assert Refgraph::Queue.empty
    Refgraph::Queue.free
  end

  def test_queue_ring()
    Refgraph::Queue.init
    20.times do |j|
      1000.times do |i|
        Refgraph::Queue.enqueue(i)
      end
      1000.times do |i|
        assert i, Refgraph::Queue.dequeue()
      end
      assert Refgraph::Queue.empty
    end
    Refgraph::Queue.free
  end

end
