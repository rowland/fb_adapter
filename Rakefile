#!/bin/env ruby
require 'rubygems'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s|
  s.author = "Brent Rowland"
  s.name = "fb_adapter"
  s.version = "0.5.7"
  s.date = "2008-12-02"
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

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = false
  pkg.need_zip = false
end
