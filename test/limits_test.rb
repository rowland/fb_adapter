require File.expand_path(File.join(File.dirname(__FILE__), 'test_helper'))

class LimitsTestCase < Test::Unit::TestCase
  def setup
    Foo.delete_all
    30.times do |i|
      Foo.create(:v => i)
    end
  end

  def test_select_with_limit
    assert_equal 30, Foo.count
    assert_equal (0..4).to_a, Foo.all(:limit => 5).map(&:v)
    assert_equal (0..9).to_a, Foo.all(:limit => 10).map(&:v)
    assert_equal (0..29).to_a, Foo.all(:limit => 40).map(&:v)
  end

  def test_select_with_limit_and_offset
    assert_equal 30, Foo.count
    assert_equal (5..9).to_a, Foo.all(:limit => 5, :offset => 5).map(&:v)
    assert_equal (10..19).to_a, Foo.all(:limit => 10, :offset => 10).map(&:v)
    assert_equal (25..29).to_a, Foo.all(:limit => 40, :offset => 25).map(&:v)
  end
end
