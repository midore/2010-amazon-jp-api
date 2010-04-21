#!/path/to/your/ruby
# coding: utf-8

# version and lang
begin
  raise "sorry, only ruby 1.9.1" if RUBY_VERSION < "1.9.1"
  ext = Encoding.default_external.name
  raise "Error, LANG must be UTF-8" unless ext == 'UTF-8'
end

# argv
ary = ARGV
ary.delete("")
w1, w2 = ary[0], ary[1]
exit unless w1
exit if w1.size > 5
exit if w2 && w2.size > 13

# load
load 'config', wrap=true
require 'amazon'
$LOAD_PATH.delete(".")

# require
require 'time'
require 'timeout'
require 'rexml/document'
require 'uri'
require 'net/http'
require 'openssl'
AmazonAPI::Start.new(ary).starter

# $ ./run-amazon-api.rb add 9784797357400
# Saved: たのしいRuby 第3版

