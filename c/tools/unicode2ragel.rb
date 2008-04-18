#!/usr/bin/env ruby
# 
# This script generates a Ragel state machine that recognizes the
# walpha, wdigit, walnum unicode character classes.  By default, the
# output is a recognizer for UTF8 encoded data, but it can output a
# recognizer for ucs4 encoded data as well.
#
# The script pulls down the unicode spec from unicode.org and looks at
# the defined properties in order to determine what the character
# classes are.
#
# Usage: unicode2ragel.rb [options]
#    -e, --encoding [ucs4 | utf8]     Data encoding
#    -h, --help                       Show this message
#
# Rakan El-Khalil <rakan@well.com>

ENCODINGS = [ "utf8", "ucs4" ]
CHART_URL = "http://www.unicode.org/Public/5.1.0/ucd/DerivedCoreProperties.txt"

require 'optparse'
require 'open-uri'

###
# Default option

options = {}
options[:encoding] = "utf8"

###
# Option parsing

cli_opts = OptionParser.new do |opts|
  opts.on("-e", "--encoding [ucs4 | utf8]", "Data encoding") do |o|
    options[:encoding] = o.downcase
  end

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

cli_opts.parse(ARGV)
unless ENCODINGS.member? options[:encoding]
  puts "Invalid encoding: #{options[:encoding]}"
  puts cli_opts
  exit
end

##
# Downloads the document at url and yields every line that has the
# given property.

def for_each_line(url, property) 
  open(url) do |file|
    file.each_line do |line|
      next if line =~ /^#/;
      next if line !~ /; #{property} #/;

      range, description = line.split(/;/)
      range.strip!
      description.gsub!(/.*#/, '')
      description.strip!

      if range =~ /\.\./
           start, stop = range.split '..'
      else start = stop = range
      end

      yield start.hex..stop.hex, description
    end
  end
end

###
# Formats the hex to have a minimum width without sign confusion

def to_hex( n )
  width = if    n <= 0x7f : 2
          elsif n <= 0x7ff : 3
          elsif n <= 0x7fff : 4
          elsif n <= 0x7ffff : 5
          elsif n <= 0x7fffff : 6
          elsif n <= 0x7ffffff : 7
          else 8
          end
  "0x%0#{width}X" % n
end

###
# Returns a list of range strings.  In the UCS4 case, the range is
# always the same as the original.  For UTF8, we may need to split the
# range if it encompasses encoding boundaries.

def to_ucs4( range )
  rangestr = to_hex(range.begin)
  rangestr << ".." << to_hex(range.end) if range.begin != range.end
  [ rangestr ]
end

##
# 0x00     - 0x7f     -> 0zzzzzzz[7]
# 0x80     - 0x7ff    -> 110yyyyy[5] 10zzzzzz[6]
# 0x800    - 0xffff   -> 1110xxxx[4] 10yyyyyy[6] 10zzzzzz[6]
# 0x010000 - 0x10ffff -> 11110www[3] 10xxxxxx[6] 10yyyyyy[6] 10zzzzzz[6] 

UTF8_BOUNDARIES = [0x7f, 0x7ff, 0xffff, 0x10ffff]

def to_utf8_enc( n )
  r = 0
  if n <= 0x7f
    r = n
  elsif n <= 0x7ff
    y = 0xc0 | (n >> 6)
    z = 0x80 | (n & 0x3f)
    r = y << 8 | z
  elsif n <= 0xffff
    x = 0xe0 | (n >> 12)
    y = 0x80 | (n >>  6) & 0x3f
    z = 0x80 |  n        & 0x3f
    r = x << 16 | y << 8 | z
  elsif n <= 0x10ffff
    w = 0xf0 | (n >> 18)
    x = 0x80 | (n >> 12) & 0x3f
    y = 0x80 | (n >>  6) & 0x3f
    z = 0x80 |  n        & 0x3f
    r = w << 24 | x << 16 | y << 8 | z
  end
  to_hex(r)
end

###
# Given a range, splits it up into ranges that can be continuously
# encoded into utf8.  Eg: 0x00 .. 0xff => [0x00..0x7f, 0x80..0xff]
# This is not strictly needed since the current [5.1] unicode standard
# doesn't have ranges that straddle utf8 boundaries.  This is included
# for completeness as there is no telling if that will ever change.

def utf8_ranges( range )
  ranges = []
  UTF8_BOUNDARIES.each do |max|
    if range.begin <= max
      return ranges << range if range.end <= max

      ranges << range.begin .. max
      range = (max + 1) .. range.end
    end
  end
end

def to_utf8( range )
  utf8_ranges( range ).map do |r|
    rangestr = to_utf8_enc(r.begin)
    rangestr << ".." << to_utf8_enc(r.end) if r.begin != r.end
    rangestr
  end
end

def encode(range, encoding)
  encoding == "ucs4" ? to_ucs4(range) : to_utf8(range)
end

##
# Generate the state maching to stdout

puts <<EOF
# The following Ragel file was autogenerated with #{$0} 
# from: #{CHART_URL}
#
# It defines walpha, wdigit, walnum.
#
# To use this, make sure that your alphtype is set to unsigned int, and
# that your input is in #{options[:encoding]}.

%%{
    machine WChar;
    walpha = 
EOF

pipe = " "
for_each_line( CHART_URL, "Alphabetic" ) do |range, description|

  if description.size > 46
    description = description.slice(0..42) + "..."
  end

  encode(range, options[:encoding]).each_with_index do |r, idx|
    description = "" unless idx.zero?
    puts "      #{pipe} #{'%-23s' % r} ##{description}"
    pipe = "|"
  end
end

puts <<EOF
      ;

    wdigit = '0'..'9';
    walnum = walpha | wdigit;
}%%
EOF
