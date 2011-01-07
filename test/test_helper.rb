$:.unshift File.join(File.dirname(__FILE__),'..')
require 'rubygems'
require 'test/unit'
gem 'activesupport', '2.3.5'
gem 'activerecord', '2.3.5'
require 'active_support'
require 'active_record'
require 'fb'

config = {
  :adapter => 'fb',
  :database => 'localhost:/var/fbdata/fb_adapter_test.fdb',
  :username => 'sysdba',
  :password => 'masterkey',
  :charset => 'NONE'
}

db = Fb::Database.new(config)
begin
  conn = db.connect
rescue
  conn = db.create.connect
end
conn.execute "DROP TABLE FOOS" rescue nil
conn.execute "CREATE TABLE FOOS (ID INT, V INT)"
conn.execute "CREATE GENERATOR FOOS_SEQ" rescue nil
conn.execute "SET GENERATOR FOOS_SEQ TO 0"
conn.close

ActiveRecord::Base.establish_connection(config)

class Foo < ActiveRecord::Base
end
