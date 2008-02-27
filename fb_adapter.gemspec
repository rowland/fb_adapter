#!/bin/env ruby
require 'rubygems'

spec = Gem::Specification.new do |s|
  s.author = "Brent Rowland"
  s.name = "fb_adapter"
  s.version = "0.5.5"
  s.date = "2008-02-27"
  s.summary = "ActiveRecord Firebird Adapter"
  s.requirements = "Firebird library fb"
  s.require_path = 'lib'
  s.email = "rowland@rowlandresearch.com"
  s.homepage = "http://www.rowlandresearch.com/ruby/"
  s.rubyforge_project = "fblib"
  s.has_rdoc = false
  # s.extra_rdoc_files = ['README']
  # s.rdoc_options << '--title' << 'Fb -- ActiveRecord Firebird Adapter' << '--main' << 'README' << '-x' << 'test'
  s.files = ['fb_adapter.gemspec'] + Dir.glob('lib/active_record/connection_adapters/*')
end

if __FILE__ == $0
  Gem.manage_gems
  Gem::Builder.new(spec).build
end
