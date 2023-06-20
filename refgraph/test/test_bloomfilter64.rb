# frozen_string_literal: true

require "test_helper"

<<-'EOC'
## mock definition of Refgraph::BloomFilter to test the test code

require 'set'

module Refgraph
  remove_const :BloomFilter64

  class BloomFilter64 < Set
    N = 64
    K = 5

    def popcount
      K
    end

    def include?(another)
      another.all? { |x| self.member?(x) }
    end
  end
end
EOC

class TestBloomFilter64 < Minitest::Test

  N = 1

  def setup
    @filters = (0...N).collect do |i|
      f = Refgraph::BloomFilter64.new
      f << i
    end
  end

  def test_num_bits
    @filters.each do |f|
      assert_equal Refgraph::BloomFilter64::K, f.popcount
    end
  end

  def test_reproducibility
    (0 ... N).each do |i|
      f = Refgraph::BloomFilter64.new
      f << i
      assert_equal @filters[i], f
    end
  end

  def test_false_positive_rate
    count = 0
    (0 ... N).each do |i|
      (0 ... N).each do |j|
        if    i == j                            then next
        elsif @filters[i].include?(@filters[j]) then count += 1
        end
      end
    end
    ## check the number of false positives is not too large by binomial-test
    ##   sum [P(X = i) | i <- [1 ..]] = 0.12280...
    ##   sum [P(X = i) | i <- [2 ..]] = 0.00787...
    ##   sum [P(X = i) | i <- [3 ..]] = 0.00034...
    ##   ==>  P(count >= 3) < 0.001
    ##   this probability is calculated with assuming N = 64, K = 5
    assert count < 3
  end

  def num_binarytrees(n)
    @num_binarytrees ||= [0, 1]
    (@num_binarytrees.length .. n).each do |m|
      @num_binarytrees << (1 .. m - 1).collect do |i|
        @num_binarytrees[i] * @num_binarytrees[m - i]
      end.sum
    end
    @num_binarytrees[n]
  end

  def ith_binarytree(i, values, l = 0, r = values.length, &block)
    block ||= proc { |x, y| [x, y] }
    if r - l == 1 then return values[l] end
    if r <= l
      raise "internal error: l must be less than r (got [l, r] = #{ [l, r].inspect })"
    end
    (l + 1 .. r - 1).each do |c|
      ln = num_binarytrees(c - l)
      rn = num_binarytrees(r - c)
      n  = ln * rn
      if i < n
        li = i / rn
        ri = i % rn
        l = ith_binarytree(li, values, l, c, &block)
        r = ith_binarytree(ri, values, c, r, &block)
        return block.call(l, r)
      else
        i -= n
      end
    end
    error "internal error: i must be less than num_binarytrees(r - l) (got [i, l, r] = #{ [i, l, r].insepct })"
  end

  def make_random_union(values)
    n = num_binarytrees(values.length)
    ith_binarytree(rand(n), values) { |l, r| l | r }
  end

  def test_union
    [0, 0, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000].each_with_index do |n, i|
      next if n <= 0
      n.times do
        xs = @filters.sample(i)
        u = make_random_union(xs)
        xs.each do |x|
          ## unless u.include?(x)
          ##   puts "not u.include?(x)  (where u = #{ u }, x = #{ x })"
          ## end
          assert u.include?(x)
        end
      end
    end
  end

  def comb(n, k)
    (n ... n - k).step(-1).reduce(1, &:*) / (2..k).reduce(1, &:*)
  end

  def test_union_false_positive_rate
    [0, 0, 10, 20, 0, 50, 0, 100, 0, 0, 200, 0, 0, 0, 0, 500].each_with_index do |n, i|
      if n <= 0 then next end
        count = 0
        n.times do
        xs = (0 ... N).to_a.sample(i)
        ys = (0 ... N).to_a - xs
        u = make_random_union(xs.collect{|x| @filters[x]})
        ys.sample(50).each do |y|
          if u.include?(@filters[y])
            count += 1
          end
        end
      end
      ## check the number of false positives is not too large by Z-test
      ##   u is a set which contains i elements
      ##   P(u.isset(X)) = 1 - (1 - K/N) ** i
      ##   forall y. P(u.include?(y) | y is not contained in u) = (1 - (1 - K/N) ** i) ** K
      pp = (1.0 - (1.0 - Refgraph::BloomFilter64::K.to_f / Refgraph::BloomFilter64::N.to_f) ** i) ** Refgraph::BloomFilter64::K
      ## sum [P(count == j) | j <- [count ..]]
      ##   = 1 - (1 + Math.erf((count - mu) / (sigma * Math.sqrt(2)))) / 2  ## (approximate to normal distribution)
      ##   = 1 - Math.erf((count - mu) / (sigma * Math.sqrt(2))) / 2
      ##     (mu = n * 50 * pp, sigma = Math.sqrt(n * 50 * pp * (1.0 - pp)))
      z = (count - n * 50 * pp) / Math.sqrt(2 * n * 50 * pp * (1.0 - pp))
      qq = (1.0 - Math.erf(z)) / 2.0
      ## unless qq > 0.05
      ##   puts "qq = #{ qq }, z = #{ z }, count = #{ count }, n = #{ n }, pp = #{ pp }"
      ## end
      assert qq > 0.05
    end
  end

end
