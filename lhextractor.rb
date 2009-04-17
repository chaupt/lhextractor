#!/usr/bin/env ruby -wKU

require 'rubygems'
require 'optparse'
require 'lighthouse'
require 'fastercsv'

class LHExtractorArgs < Hash

  def initialize(args)
    super
    self[:milestone] = nil
    self[:token] = nil
    self[:project] = nil
    self[:account] = nil
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #$0 [options]"
      opts.on('-m', '--milestone [Milestone Name]', 'Name of milestone to process') do |m|
        self[:milestone] = m
      end
      opts.on('-t', '--token [API Token]', 'Authentication Token for API access') do |m|
        self[:token] = m
      end
      opts.on('-p', '--project [Project ID]', 'ID of project to process') do |m|
        self[:project] = m
      end
      opts.on('-a', '--account [Account Subdomain]', 'name of account (subdomain)') do |m|
        self[:account] = m
      end
      opts.on_tail('-h','--help','display this help and exit') do
        puts opts
        exit
      end
    end
    opts.parse!(args)
  end
end

class LHProcessor
  include Lighthouse
  # Current LH API pages 30 results at a time
  MAX_PAGE_SIZE = 30
  
  def initialize(args)
    @args = args
    @max_comments = 0
    Lighthouse.account = @args[:account]
    Lighthouse.token = @args[:token]
    Lighthouse::Base.timeout = 10
  end
  
  def csv_header(default = 'Story,Labels,Owned By,State,Description,Note', dynamic_notes=true)    
	standard = default
    1.upto(@max_comments) {|t| standard += ',Note'} if dynamic_notes
    return standard
  end
  
  def list_tickets
    p = Project.find(@args[:project].to_i)
    raise "No such project for #{@args[:project]} in #{@args[:account]}" if p.nil?
    # get the tickets
    results = []
    page = 1
    done = false
    while !done do
      tickets = p.tickets(:q => %|milestone:"#{@args[:milestone]}"|, :page => page)
      tickets.each do |t|
		  # Get specific versions of ticket, this is the way to get the body according to Rick O.
		  ticket = Lighthouse::Ticket.find(t.id, :params => {:project_id => @args[:project].to_i})
		  line = [t.title, "#{t.tags.join(',')}", (t.respond_to?('assigned_user_name') ? t.assigned_user_name : nil), ticket.state, ticket.versions.first.body, t.url]
		  # get any other thing beyond the initial body here
		  if ticket.versions.size > 1
			ticket.versions[1..ticket.versions.size].each do |v|
			  line << v.body
			end
		  end
		  @max_comments = ticket.versions.size if ticket.versions.size > @max_comments + 1
		  results << line
      end
      if tickets.size >= MAX_PAGE_SIZE
      	page += 1
      else
        done = true
      end
    end
    return results
  end
  
  def csv_output(results, include_header=true)
	puts csv_header if include_header
    results.each do |line|
      puts line.to_csv
    end
  end
end

arguments = LHExtractorArgs.new(ARGV)

if arguments[:account].nil?
  puts "FAIL: Need an account"
  exit 1
end
if arguments[:token].nil?
  puts "FAIL: Need a token"
  exit 1
end
if arguments[:project].nil?
  puts "FAIL: Need a project ID"
  exit 1
end
if arguments[:milestone].nil?
  puts "FAIL: Need a milestone name (in quotes: 'Iteration 7')"
  exit 1
end

lh = LHProcessor.new(arguments)
results = lh.list_tickets
lh.csv_output(results)