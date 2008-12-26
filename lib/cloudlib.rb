# This library provides the means for maintaining a database of
# documents on Amazon's S3 file store, with searchable metadata in
# Amazon's SimpleDB database. Think of it as a filing cabinet or library
# that can be extended indefinitely and accessed from anywhere in the
# world: a library that lives "in the cloud."

# In order to use this library, you need to sign up for
# Amazon's S3 and SimpleDB services:
#
# * Amazon SimpleDB: http://aws.amazon.com/simpledb/
# * Amazon S3: http://aws.amazon.com/s3/
#
# Simple usage example:
#
#   require 'rubygems'
#   require 'cloudlib'
#   include Cloudlib
#   Entry.connect('xxx_key_id_xxx', 'xxx_secret_access_key_xxx', 'my_aws_library')
#   logic_entries = Entry.query('logic')
#   logic_entries.each {|entry| puts entry.to_s}
#
# For more examples of the use of the library, see the programs cloudlib.rb
# and cloudlib-web.rb, included in the gem.

# Author::    John MacFarlane (jgm at berkeley dot edu)
# Copyright:: Copyright (c) 2008 John MacFarlane
# License::   GPL v2

require 'rubygems'
require 'readline'
require 'aws/s3'   # aws-s3 gem
require 'aws_sdb'  # aws-sdb gem
require 'open-uri'
require 'fileutils'

module Cloudlib

# A library entry, including content and metadata. An entry has a name
# (which is also the key of the associated S3 object) and an attributes
# hash. The name is of the form "sha1.ext", where sha1 is a SHA1 hash of
# the contents of the file, and ext is the file extension. This makes
# it impossible to have entries with duplicate contents. The attributes
# hash contains the following fields:
#
# * extension      - file extension including .
# * size           - size of contents (bytes)
# * date-added     - date entry was added to library
# * entry_type     - article, book, chapter, incollection, unpublished
# * authors        - list of authors
# * editors        - list of editors
# * title          - title of entry
# * booktitle      - title of book containing entry
# * year           - publication year of entry
# * publisher      - publisher of book
# * address        - publication address
# * journal        - journal containing entry
# * volume         - volume number of journal
# * pages          - page range of entry in book or journal
# * keywords       - keywords
# * doi            - DOI for entry
# * url            - URL for entry
# * comments       - miscellaneous comments
# * *_lowercase    - lowercase version of *
# * *_words        - lowercase version of *, split into a list of words
# * all_words      - list of words in title, authors, editors, booktitle, keywords

class Entry

  attr_accessor :name, :attributes

  # Establish connections to the S3 file store and the SimpleDB database.
  # If values are not supplied for the parameters, they will default to
  # the values of the environment variables CLOUDLIB_LIBRARY_NAME,
  # AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY. Note that library_name
  # is the name of both the S3 bucket that will hold the contents of
  # the entries and the SimpleDB domain that will hold the metadata.
  def self.connect(library_name=ENV['CLOUDLIB_LIBRARY_NAME'],
                   aws_access_key_id=ENV['AWS_ACCESS_KEY_ID'],
                   aws_secret_access_key=ENV['AWS_SECRET_ACCESS_KEY'],
                   debug = false)
    @@aws_access_key_id = aws_access_key_id
    @@aws_secret_access_key = aws_secret_access_key
    AWS::S3::Base.establish_connection!(:access_key_id => @@aws_access_key_id, :secret_access_key => @@aws_secret_access_key, :use_ssl => true)
    @@bucket = library_name
    logger = Logger.new(STDERR)
    logger.level = if debug then Logger::DEBUG else Logger::WARN end
    @@db = AwsSdb::Service.new(:access_key_id => @@aws_access_key_id, :secret_access_key => @@aws_secret_access_key, :use_ssl => true, :logger => logger)
  end

  # Creates a new entry object.  To create an entry with contents,
  # use Entry.from_file.
  def initialize(name, attributes={'all_words' => []})
    @name = name
    @attributes = attributes
  end

  # Create the S3 bucket and SimpleDB domain that will store the library entries.
  # This method should be run once to create the library.
  def self.create_library
    AWS::S3::Bucket.create(@@bucket)
    @@db.create_domain(@@bucket)
  end

  # Delete the S3 bucket and SimpleDB domain that store the library entries.
  # All data will be lost.
  def self.delete_library
    AWS::S3::Bucket.delete(@@bucket, :force => true)
    @@db.delete_domain(@@bucket)
  end

  # Creates and saves an entry from a file, using attributes supplied.
  # Returns the entry.
  def self.from_file(path, filename=path, attributes={'all_words' => []})
    sha1 = Digest::SHA1.file(path).hexdigest
    ext  = File.extname(filename)
    name = "#{sha1}#{ext}"
    attributes['size'] = File.size(path).to_s
    attributes['date-added'] = Date.today.to_s
    entry = Entry.new(name, attributes)
    AWS::S3::S3Object.store(name, open(path), @@bucket)
    @@db.put_attributes(@@bucket, name, attributes, replace=true)
    return entry
  end

  # Return an entry with the specified name.  Raises an error if not found.
  def self.find_by_name(name)
    attributes = @@db.get_attributes(@@bucket, name)
    if attributes == {} then raise "Item not found." end
    Entry.new(name, attributes)
  end

  # Queries the database and returns a list [token, entries].  entries is
  # a list of up to numitems Entry objects that match the query. If
  # there are more entries than numitems, token will be nonempty, and
  # can be passed in on a subsequent calls for the remaining entries.
  #
  # The query string can contain one or more words.  If a word is
  # preceded by ti=, only entries that match it in the title will be
  # returned.  Similarly, au= searches authors, jo= journals, pu=
  # publishers, ad= addresses, ed= editors, bo= booktitle (for collections),
  # and ye= years.  ye> and # ye< may also be used.
  # The form ti='word1 word2' may also be used; entries will only match
  # if their titles contain both word1 and word2.
  def self.query(query_string, numitems=10, token=nil)
    query_parts = query_string.downcase.scan(/((ti(?:title)|au(?:thor?s)|jo(?:urnal)|bo(?:ooktitle)|pu(?:blisher)|ad(?:ddress)|ed(?:itor?s)|ye(?:ar))[^<=>]*([<=>])('[^']*'|"[^"]*"|\S*)|\S+)\s*/)
    query = query_parts.reject {|part| part[0] == '*'}.map do |part|
      whole, key, comparison, val = part
      if val then val = val.gsub(/^['"](.*)['"]$/, "\\1") end
      if not val then val = whole end
      key_full = case key
                 when 'ti'
                  'title'
                 when 'au'
                  'authors'
                 when 'jo'
                  'journal'
                 when 'pu'
                  'publisher'
                 when 'ad'
                  'address'
                 when 'ed'
                  'editors'
                 when 'ye'
                  'year'
                 else 'all'
                 end
      vals = val.split
      vals.map do |v|
        if key_full == 'year'    # there is no year_words field
           "['year' #{comparison} '#{v}']"
        else
           "['#{key_full}_words' = '#{v}']"
        end
      end.join(" intersection ")
    end.join(" intersection ")
    # note: query has to include year in order to sort by year
    # hence this dummy search
    if query.empty?
       query = "['year' starts-with ''] sort 'year'"
    else
       query += " intersection ['year' starts-with ''] sort 'year'"
    end
    names, token = if token
                     @@db.query(@@bucket, query, numitems, token)
                   else
                     @@db.query(@@bucket, query, numitems)
                   end
    entries = names.map do |name|
      attributes = @@db.get_attributes(@@bucket, name)
      Entry.new(name, attributes)
    end
    return token, entries
  end

  # Returns a human-friendly filename for the entry, constructed from
  # authors and title.
  def friendly_filename
    authornames = self.attributes['authors'].map {|a| last_name(a)}.join('_')
    title = self.show_attribute('title').gsub(/[,.\/[:space:]]+/,'_')
    ext = File.extname(self.name)
    return "#{authornames}_#{title}#{ext}"
  end

  # Deletes the entry.
  def delete
    AWS::S3::S3Object.delete(self.name, @@bucket)
    @@db.delete_attributes(@@bucket, self.name)
  end

  # Saves the entry (metadata only; contents are saved by the from_file
  # method).
  def save
    @@db.put_attributes(@@bucket, self.name, self.attributes, replace=true)
  end

  # Downloads the entry and saves as filename.
  def download(path)
    if File.exist?(path)
      STDERR.puts "Backing up existing #{path} as #{path}~"
      FileUtils.copy_file(path, "#{path}~", preserve=true)
    end
    open(path, 'w') do |outfile|
      open(self.url, 'r') do |source|
        FileUtils.copy_stream(source, outfile)
      end
    end
    return path
  end

  # Returns a bibtex entry for the entry.
  def to_bibtex
    pairs = self.fields.map do |field|
      if self.attributes[field.to_s]
         sprintf("  %-15s: {%s}", field.to_s, self.show_attribute(field.to_s))
      else
         nil
      end
    end
    pairs += [sprintf("  %-15s: {%s}", "file", self.name)]
    authornames = self.attributes['authors'].map {|a| last_name(a)}.join('.')
    year = self.attributes['year']
    entry_type = self.show_attribute('entry_type') || 'unknown'
    if entry_type == 'chapter' then entry_type = 'inbook' end
    entry_key = "#{authornames}:#{year}"
    "@#{entry_type.upcase}{#{entry_key},\n#{pairs.join(",\n")}\n}"
  end

  # Returns a string representation of the entry's metadata.
  def to_s
    authors = self.show_attribute('authors')
    unless authors.empty?
      authors = "#{authors}, "
    end
    title = "#{self.show_attribute('title')}"
    year = self.show_attribute('year')
    titleyear = if year.empty?
                   title + ". "
                else
                   title + " (#{year}). "
                end
    pubaddr = [self.show_attribute('address'),
               self.show_attribute('publisher')].reject {|x| x.empty?}.join(": ")
    chapter = self.show_attribute('chapter')
    pages = self.show_attribute('pages')
    booktitle = self.show_attribute('booktitle')
    editors = self.show_attribute('editors')
    journal = self.show_attribute('journal')
    volume = self.show_attribute('volume')
    rest = case self.show_attribute('entry_type')
           when 'article'
             if journal.empty?
                ""
             else
                "#{journal} #{volume}" +
                if pages.empty? then "." else ", #{pages}." end
             end
           when 'book'
             if pubaddr.empty? then "" else "#{pubaddr}." end
           when 'chapter'
             if pubaddr.empty? then "" else "#{pubaddr}." end +
             if chapter.empty? then "" else " Chapter #{chapter}." end +
             if pages.empty? then "" else " #{pages}." end
           when 'incollection'
             "In " +
             if editors.empty? then "" else editors + " (eds.), " end +
             booktitle +
             if pubaddr.empty? then "" else " (#{pubaddr})." end +
             if chapter.empty? then "" else " Chapter #{chapter}." end +
             if pages.empty? then "" else " #{pages}." end
           when 'unpublished'
             " (unpublished)."
           else ""
           end
    return authors + titleyear + rest
  end

  # Sets the specified metadata attribute to ans.  ans is assumed to be a regular string.
  # It will be split by " and " for authors and editors, or by spaces for keywords.
  def set_attribute(attribute, ans)
    index = ['title', 'authors', 'editors', 'booktitle'].member?(attribute)
    if ans.nil? || ans.empty?
      self.attributes[attribute] = nil
    else
      newval = if attribute == 'editors' || attribute == 'authors'
                  ans.split(" and ").map {|a| a.strip}
               elsif attribute == 'keywords'
                  ans.split
               else
                  [ans.strip]
               end
      self.attributes[attribute] = newval
      unless ['url', 'doi', 'keywords'].member?(attribute)
        self.attributes[attribute + "_lowercase"] = newval.map {|a| a.downcase}
        self.attributes[attribute + "_words"] = self.attributes[attribute + "_lowercase"].map {|a| a.split(/[[:space:][:punct:]] */)}.flatten
      end
      # recalculate all_words
      tit_auth_words = ['title', 'authors', 'editors', 'booktitle'].map {|att| self.attributes[att + "_words"] || []}.flatten
      keywords = self.attributes['keywords'] || []
      self.attributes['all_words'] = keywords + tit_auth_words
    end
  end

  # Returns a string representation of an attribute.
  def show_attribute(attribute)
    value = self.attributes[attribute]
    if value.nil?
       ""
    elsif attribute == 'keywords'
       value.join(' ')
    elsif attribute == 'editors' || attribute == 'authors'
       value.join(' and ')
    else
       value[0]
    end
  end

  # Returns an array of the field keywords appropriate for a type of entry.
  def self.fields(entry_type='*')
    fields = [:title, :authors, :year]
    case entry_type
    when 'article'
      fields += [:journal, :volume, :pages]
    when 'book'
      fields += [:publisher, :address]
    when 'chapter'
      fields += [:booktitle, :chapter, :publisher, :address, :pages]
    when 'incollection'
      fields += [:booktitle, :chapter, :publisher, :address, :editors, :pages]
    when '*'
      fields += [:journal, :volume, :booktitle, :editors, :chapter,
                 :publisher, :address, :pages]
    end
    fields += [:keywords, :url, :doi, :comments]
    return fields
  end

  # Returns the fields appropriate for an entry.
  def fields
    entry_type = self.show_attribute('entry_type')
    Entry.fields(entry_type)
  end

  def url
    AWS::S3::S3Object.find(self.name, @@bucket).url(:expires_in => 60 * 10)  # expires in 10 min
  end

  private
  # Returns the author's last name.
  def last_name(author)
    if author =~ /,/
      author =~ /([^ ,]+),/
    else
      author =~ /([^ \t]+)$/
    end
    return $1
  end

end

end
