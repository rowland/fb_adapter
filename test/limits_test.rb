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

  def test_update_with_limit
    assert_equal 1, Foo.count(:conditions => "V = 7")
    Foo.update_all("V = 7", nil, :limit => 5)
    assert_equal 6, Foo.count(:conditions => "V = 7")
    assert_equal [7,7,7,7,7,5,6,7,8,9], Foo.all(:limit => 10).map(&:v)
  end

  def test_update_with_limit_and_offset
    assert_equal 1, Foo.count(:conditions => "V = 7")
    Foo.update_all("V = 7", nil, :limit => 3, :offset => 2)
    assert_equal 4, Foo.count(:conditions => "V = 7")
    assert_equal [0,1,7,7,7,5,6,7,8,9], Foo.all(:limit => 10).map(&:v)
  end

  def test_update_with_limit_and_offset_ordered_desc
    assert_equal 1, Foo.count(:conditions => "V = 7")
    Foo.update_all("V = 7", nil, :limit => 3, :offset => 2, :order => "ID DESC")
    assert_equal 4, Foo.count(:conditions => "V = 7")
    assert_equal [29,28,7,7,7,24,23,22,21,20], Foo.all(:limit => 10, :order => "ID DESC").map(&:v)
  end
end
