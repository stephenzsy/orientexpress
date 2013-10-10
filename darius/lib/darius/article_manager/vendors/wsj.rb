require 'active_support/all'
require 'nokogiri'

require_relative '../article_vendor'
require_relative '../utils/cookie_helper'
require_relative '../utils/parser'

module ColdBlossom
  module Darius
    module ArticleManager
      module Vendors
        class WSJ < ArticleVendor
          include ArticleManager::Utils::CookieHelper
          include ArticleManager::Utils::DynamoDBCookieStore

          VENDOR_NAME = 'wsj'
          EXTERNAL_DOCUMENT_VERSION = '2013-09-23'
          DAILY_ARCHIVE_INDEX_PROCESSOR_VERSION = '2013-10-05'
          ARTICLE_PROCESSOR_VERSION = '2013-09-15-04'
          ARTICLE_PROCESSOR_PATCH = 15

          TIME_ZONE = ActiveSupport::TimeZone['America/New_York']

          def initialize(config)
            @log = Logger.new(STDOUT)
            @log.level = Logger::DEBUG

            super VENDOR_NAME
            set_cookie_store config, self
            set_authentication_cookies(get_stored_cookies())
          end

          def get_archive_info(date_str)
            date = Time.parse(date_str).in_time_zone(TIME_ZONE).midnight
            {
                :cache_partition => date.strftime("%Y/%m/%d-"),
                :date => date,
                :valid_after => date + 1.day + 15.minutes
            }
          end


          def get_archive_index_info datetime, url = nil
            datetime = datetime.in_time_zone(TIME_ZONE).midnight
            index_url = get_archive_index_url datetime

            if url.nil?
              url = index_url
            else
              # TODO
              raise 'NOT VALIDATED' unless index_url == url
            end

            {
                :datetime => datetime,
                :url => url,
                :cache_partition => datetime.strftime("%Y/%m/%d-"),
                :valid_after => datetime + 1.day + 15.minutes
            }
          end

          def get_article_info(datetime, url)
            datetime = datetime.in_time_zone TIME_ZONE
            {
                :datetime => datetime,
                :url => url,
                :cache_partition => datetime.strftime("%Y/%m/%d/")
            }
          end

          def handle_set_cookie(set_cookie_line)
            cookies = {}
            set_cookie_line.split(/,\s*/).each do |cookie_line|
              if cookie_line.match /^(?<name>djcs_\w+)=(?<value>[^;]*)/
                cookies[$~[:name]] = $~[:value]
              elsif cookie_line.match /^user_type=subscribed/
                cookies['user_type'] = 'subscribed'
              end
            end
            if (cookies['djcs_auto'] and cookies['djcs_perm'] and cookies['djcs_session'] and cookies['user_type'])
              yield [
                  "djcs_auto=#{cookies['djcs_auto']}",
                  "djcs_perm=#{cookies['djcs_perm']}",
                  "djcs_session=#{cookies['djcs_session']}",
                  "user_type=#{cookies['user_type']}"
              ]
            end
          end

          def get_external_document(url)
            1.upto(5) do
              uri = URI(url)
              response = nil
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = (uri.scheme == 'https')
              @log.debug(url)
              http.start do |http|
                response = http.get(uri.path, {'Cookie' => get_authentication_cookies.join('; ')})
              end
              case response.code
                when '200'
                when '302'
                  unless response['set-cookie'].nil?
                    handle_set_cookie response['set-cookie'] do |cookies|
                      put_stored_cookies cookies
                      set_authentication_cookies cookies
                    end
                  end
                  url = response['location']
                  raise 'Invalid location' unless URI.parse(url).host().end_with? 'wsj.com'
                  next
                else
                  p response
                  raise "Fault Retrieve"
              end
              @log.debug("request DONE")
              body = response.body
              body.force_encoding('UTF-8')
              raise 'Invalid UTF-8 Encoding of body' unless body.valid_encoding?
              yield body, {:document_version => EXTERNAL_DOCUMENT_VERSION}
              break
            end
          end

          def daily_archive_index_to_json(document)
            result = {
                :articles => [],
            }
            doc = Nokogiri::HTML(document)
            archived_articles = doc.css('#archivedArticles')
            news_item = archived_articles.css('ul.newsItem')
            news_item.css('li').each do |item|
              a = item.css('a').first
              p = item.css('p').first
              url = a['href']
              a.remove
              result[:articles] << {
                  :url => url,
                  :title => a.text.strip,
                  :summary => p.text
              }
            end
            yield result, {:document_version => EXTERNAL_DOCUMENT_VERSION, :processor_version => DAILY_ARCHIVE_INDEX_PROCESSOR_VERSION}
          end

          def article_to_json(url, document)
            r = {}

            if url.start_with? 'http://graphicsweb.wsj.com'
              r = {:domain => 'graphicsweb.wsj.com', :url => url}
            else
              fix_article_html! document
              doc = Nokogiri::HTML(document)
              r = Parsers::ArticleParser.new.parse(doc)
              r[:url] = url
            end

            yield r, {:document_version => EXTERNAL_DOCUMENT_VERSION, :processor_version => ARTICLE_PROCESSOR_VERSION, :processor_patch => ARTICLE_PROCESSOR_PATCH}
          end


          private
          def get_archive_index_url datetime
            "http://online.wsj.com/public/page/archive-#{datetime.strftime "%Y-%-m-%-d"}.html"
          end

          module Parsers
            include Utils::Parsers

            class HeadMetaParser < HTMLParser

              @@HEAD_META_NAME_BLACKLIST = Set.new(
                  [
                      'msapplication-task',
                      'format-detection',
                      "apple-itunes-app",
                      "application-name",
                      'sitedomain',
                      'primaryproduct',
                      'GOOGLEBOT'
                  ])

              def parse(node)
                return nil unless node.has_attribute? 'content'
                type = nil
                key = nil
                if node.has_attribute? 'name'
                  type = :name
                  key = node.attr('name')
                elsif node.has_attribute? 'property'
                  type = :property
                  key = node.attr('property')
                else
                  return nil
                end
                case key
                  when /^(fb|twitter):/
                    return nil
                end
                return nil if @@HEAD_META_NAME_BLACKLIST.include? key
                {type => key, :value => node.attr('content')}
              end
            end # class HeadMetaParser

            class SocialBylineParser < HTMLParser
              include Utils::Parsers::ParserRules

              class TextRule < RuleBase
                def parse(node_seq, parent_node)
                  r = []
                  raise ParserRuleNotMatchException unless node_seq.size == 1 and node_seq.first.text?
                  text = node_seq.first.content.strip
                  case text
                    when /^By ([[[:upper:]]\. ]+)( and ([[[:upper:]]\. ]+))?$/
                      r << {:author => [:name => $~[1]]}
                      r << {:author => [:name => $~[3]]} unless $~[3].nil?
                    else
                      raise ParserRuleNotMatchException
                  end
                  node_seq.unlink
                  r
                end
              end # class TextRule

              class By_name_cite_Rule < RuleBase
                def parse(node_seq, parent_node)
                  state = :S
                  r = {}
                  node_seq.each do |node|
                    case state
                      when :S
                        if node.text? and node.content.strip =~ /by (.*)/i
                          r[:author] = $~[1]
                          state = :name
                          next
                        end
                        raise ParserRuleNotMatchException
                      when :name
                        if node.name == 'cite' and node.children.size == 1 and node.children.first.text?
                          r[:cite] = node.children.first.content.strip
                          state = :F
                          next
                        end
                        raise ParserRuleNotMatchException
                    end
                  end
                  raise ParserRuleNotMatchException unless state == :F
                  node_seq.unlink
                  [r]
                end
              end # class By_name_cite_Rule

              class By_byName_star_Cite_Rule < RuleBase

                def parse(node_seq, parent_node)
                  raise ParserRuleNotMatchException unless parent_node.element? and parent_node.name == 'ul'
                  r = []
                  state = :S
                  loc_last_authors = []
                  last_author = nil
                  node_seq.each do |node|
                    case state
                      when :S
                        if node.text? and node.content.strip.downcase == 'by'
                          state = :by
                          next
                        elsif node.element? and ['li', 'cite'].include? node.name
                          state = :li
                          next
                        end
                      when :by, :li_separator
                        if node.element? and ['li', 'cite'].include? node.name
                          last_author = author = {:author => parse_li(node)}
                          loc_last_authors << author
                          r << author
                          state = :li
                          next
                        end
                      when :li_continue
                        if node.element? and node.name == 'li'
                          text = parse_li(node).each do |l|
                            break l[:name] if l.has_key? :name
                          end
                          last_author[:author].each do |l|
                            if l.has_key? :name
                              l[:name] += " #{text}"
                              break
                            end
                          end
                          state = :li
                          next
                        end
                      when :li
                        if node.element? and ['li', 'cite'].include? node.name
                          last_author = author = {:author => parse_li(node)}
                          loc_last_authors << author
                          r << author
                          state = :li
                          next
                        elsif node.text?
                          text = node.content.strip
                          if text == '|'
                            state = :cite_separator
                          elsif text == 'DE'
                            # foreign name
                            last_author[:author].each do |l|
                              if l.has_key? :name
                                l[:name] += " #{text}"
                                break
                              end
                            end
                            state = :li_continue
                          elsif text.match /^(in|at) (.*)( and|,)$/
                            location = $~[1]
                            loc_last_authors.each do |author|
                              author[:location] = location
                            end
                            loc_last_authors.clear
                            state = :li_separator
                          elsif text.match /^(in|at) (.*)$/
                            location = $~[1]
                            loc_last_authors.each do |author|
                              author[:location] = location
                            end
                            loc_last_authors.clear
                            state = :F
                          elsif ['and', ','].include? text.downcase
                            state = :li_separator
                          else
                            raise ParserRuleNotMatchException
                          end
                          next
                        end
                      when :F
                        if node.text?
                          text = node.content.strip
                          if text == '|'
                            state = :cite_separator
                            next
                          end
                        end
                      when :cite_separator
                        if node.name == 'cite'
                          text = node.text.strip
                          r << {:cite => text}
                          state = :F
                          next
                        end
                    end
                    raise ParserRuleNotMatchException
                  end
                  case state
                    when :li, :F
                    else
                      raise ParserRuleNotMatchException
                  end
                  r.reject! { |e| e.nil? }
                  node_seq.unlink
                  return nil if r.empty?
                  r
                end

                def parse_li(node)
                  node = node.dup
                  r = []
                  node.attributes.each do |name, attr|
                    if name.match /data-(\S+)/
                      r << {:data => {:name => $~[1], :value => attr.content}}
                      attr.unlink
                    end
                  end
                  name_parsed = false
                  node.children.each do |nn|
                    if nn.text? and nn.content.strip.empty?
                      nn.unlink
                      next
                    end
                    raise ParserRuleNotMatchException if name_parsed
                    if not node.attr('class').nil? and node.attr('class').split(/\s+/).include? 'byName' and nn.name == 'a'
                      r << {:link => nn.attr('href')}
                      nnn = nn.children.first
                      if nnn.text?
                        r << {:name => nnn.content.strip}
                        nnn.unlink
                      end
                    elsif nn.text?
                      r << {:name => nn.content.strip}
                      nn.unlink
                    end
                    name_parsed = true
                  end

                  ensure_empty_node node
                  r.reject! { |x| x.nil? }
                  return r
                end
              end # class By_byName_star_Rule

              @@node_sequence_rules = [
                  By_byName_star_Cite_Rule.new,
                  By_name_cite_Rule.new,
                  TextRule.new,
              ]

              def parse(node)
                node.css('#connectButton').unlink
                node.css('li.connect').unlink
                node.children.each do |n|
                  n.unlink if n.text? and n.content.strip.empty?
                end
                node_seq = node.children
                matched = false
                begin
                  @@node_sequence_rules.each do |rule|
                    begin
                      r = rule.parse node_seq, node
                      ensure_empty_node node
                      return nil if r.nil?
                      return {:social_byline => r}
                    rescue ParserRuleNotMatchException
                      next
                    end
                  end
                  return {:social_by_line => super(node)}
                ensure
                  node_seq.unlink if matched
                end
              end
            end

            class ArticleHeadlineBoxParser < HTMLParser
              @@social_byline_parser = SocialBylineParser.new

              # @return [Array]
              def parse(node)
                r = []

                # .cMetadata
                c_metadata = []
                select_only_node_to_parse(node, 'ul.cMetadata', true) do |c_metadata_node|
                  c_metadata << select_only_node_to_parse(c_metadata_node, 'li.articleSection', true) do |article_section_node|
                    r_article_section = {:name => article_section_node.text.strip}
                    select_only_node_to_parse article_section_node, 'a', true do |a|
                      r_article_section[:link] = a.attr('href')
                    end
                    {:article_section => r_article_section}
                  end
                  c_metadata << select_only_node_to_parse(c_metadata_node, '.dateStamp') do |date_stamp|
                    text = date_stamp.text
                    date = Time.parse(text)
                    {:date_stamp => {:text => text, :date_stamp => date.iso8601}}
                  end
                  ensure_empty_node c_metadata_node
                end

                node.children.each do |n|
                  if n.comment?
                    lines = n.content.split "\n"
                    if lines.size == 1
                      parsed_comment = parse_single_line_comment(n.content) do |state|
                        yield state
                      end
                      c_metadata << parsed_comment unless parsed_comment.nil?
                    else
                      c_metadata += parse_multi_line_comment(lines)
                    end
                    n.unlink
                  elsif n.name == 'h5'
                    n.children.each do |nn|
                      nn.unlink if nn.text? and nn.content.strip.empty?
                    end
                    if n.children.size == 1
                      nn = n.children.first
                      if nn.text?
                        r << {:heading => n.text, :level => 5}
                        n.unlink
                      elsif nn.element? and nn.name == 'a' and nn.one_level_text?
                        r << {:heading => nn.text, :level => 5, :link => nn.attr('href')}
                        n.unlink
                      end
                    end
                  end
                end
                r << {:c_metadata => c_metadata} unless c_metadata.empty?

                select_only_node_to_parse(node, 'h1') do |h1|
                  r << {:headline => h1.text.strip}
                end
                select_set_to_parse(node, 'h2.subhead') do |nodes|
                  nodes.each do |h2|
                    r << {:subhead => h2.text.strip}
                  end
                end
                select_only_node_to_parse node, '.columnist', true do |columnist_node|
                  columnist_node.css('div.icon').unlink
                  select_only_node_to_parse columnist_node, '.socialByline' do |social_byline_node|
                    r << @@social_byline_parser.parse(social_byline_node)
                  end
                  columnist_node.children.each do |node|
                    node.unlink if node.text? and node.text.strip == '-'
                  end
                  ensure_empty_node columnist_node
                end

                ensure_empty_node node
                r
              end

              private
              def parse_single_line_comment(line)
                line.strip!
                case line
                  when /([^\s:]+):(.*)/
                    return {:key_value => {:key => $~[1], :value => $~[2]}}
                  when 'article start'
                    yield ({:article_start_flag => true})
                  else
                    raise("Unrecognized comment in .articleHeadlineBox:\n#{line}")
                end
                nil
              end

              def parse_multi_line_comment(lines)
                lines.shift if lines.first.empty?
                lines.pop if lines.last.empty?
                r = []
                until lines.empty? do
                  line = lines.first
                  if line.match /^CODE=(\S*) SYMBOL=(\S*)/
                    r << {:code_symbol => {:code => $~[1], :symbol => $~[2]}}
                    lines.shift
                    next
                  end
                  r << {:tree => handle_indented(0, lines)}
                end
                r
              end

              def handle_indented(level, lines)
                result = []
                until lines.empty?
                  line = lines.first
                  m = /^(\s*)(\S.*)?/.match(line)
                  indent_length = m[1].size
                  line = m[2]
                  if indent_length > level
                    result << handle_indented(indent_length, lines)
                  elsif indent_length == level
                    unless line.nil? or line.empty?
                      result << line
                    end
                    lines.shift
                  else
                    break
                  end
                end
                result.reject! { |e| e.nil? or e.empty? }
                result
              end

            end # class ArticleHeadlineBoxParser

            class ArticlePageParser < HTMLParser
              @@social_byline_parser = SocialBylineParser.new

              def parse(article_page_node)
                article_page_node.css('.insetContent', '.insetCol3wide', 'insetCol6wide', '.offDutyMoreSection', 'the', 'table',
                                      '.embedType-interactive', 'void', 'art').unlink

                # .socialByLine
                r = []
                social_byline = select_only_node_to_parse article_page_node, '.socialByline', true do |node|
                  @@social_byline_parser.parse node
                end
                r << social_byline unless social_byline.nil?

                # paragraphs
                paragraphs = []
                f = []
                begin
                  article_page_node.children.each do |node|
                    p, ff = parse_paragraph(node) do |state|
                      yield state
                    end
                    paragraphs << p
                    f << ff unless ff.nil?
                  end
                  paragraphs.reject! { |x| x.nil? }
                  paragraphs = nil if paragraphs.empty?
                end
                if f.empty?
                  f = nil
                elsif f.size == 1
                  f = f.first
                end
                rr = {}
                rr[:paragraphs] = paragraphs unless paragraphs.nil?
                rr[:flattened] = f unless f.nil?
                r << rr unless rr.empty?
                ensure_empty_node article_page_node
                r
              end

              def parse_paragraph(node)
                if node.comment? and node.content.strip == 'article end'
                  yield({:article_end_flag => true})
                  node.unlink
                  return nil
                elsif node.text?
                  begin
                    text = node.content.strip.gsub(/\s+/, ' ')
                    return nil if text.empty?
                    return {:text => text}, text
                  ensure
                    node.unlink
                  end
                end

                # pre parse tree
                case node.name
                  when 'br'
                    node.unlink
                    return nil, nil
                  when 'a'
                    if not node.has_attribute?('href') and node.has_attribute?('name')
                      begin
                        return {:anchor => {:name => node.attr('name')}}, nil
                      ensure
                        node.unlink
                      end
                    end
                  when 'span'
                    if node.has_attribute? 'data-widget'
                      begin
                        return {:widget => {:ticker_name => node.attr('data-ticker-name')}}, nil
                      ensure
                        node.unlink
                      end
                    end
                end

                f = []
                #parse tree
                parsed_children = []
                node.children.each do |n|
                  p, ff = parse_paragraph n do |state|
                    yield state
                  end
                  f << ff unless ff.nil?
                  last_p = parsed_children.last
                  if not (last_p.nil? or p.nil?) and last_p.has_key? :text and p.has_key? :text
                    # append the text to last one
                    last_p[:text] = last_p[:text] + ' ' + p[:text]
                    next
                  end
                  parsed_children << p unless p.nil?
                end
                r = {:p => parsed_children}
                if f.empty?
                  f = nil
                elsif f.size == 1
                  f = f.first
                end

                #post parse tree
                case node.name
                  when /h(\d+)/
                    r = {:heading => parsed_children, :level => $~[1].to_i}
                  when 'cite'
                    r = {:cite => parsed_children}
                  when 'p'
                    if node.has_attribute?('class') and node.matches? '.articleVersion'
                      r = {:article_version => parsed_children}
                      f = nil
                    else
                      raise "Unrecognized Class of node p\n#{node.inspect}" unless node.attr('class').nil?
                    end
                  when 'strong'
                    r = {:strong => parsed_children}
                  when 'em'
                    r = {:em => parsed_children}
                  when 'blockquote'
                    r = {:block_quote => parsed_children}
                  when 'no'
                    r = {:no => parsed_children}
                  when 'a'
                    if node.matches? '.topicLink'
                      return {:topic_link => {:link => node.attr('href'), :_ => parsed_children}}
                    end
                    if node.has_attribute?('href')
                      begin
                        case node.attr('href')
                          when /^mailto:(.*)/
                            r = {:email => {:email_address => $~[1], :_ => parsed_children}}
                          when /^\/public\/quotes\/main\.html\?type=(?<type>\w+)&symbol=(?<symbol>[\w\.:-]+)$/
                            r = {:quote => {:type => $~[:type], :symbol => $~[:symbol], :_ => parsed_children}}
                          else
                            r = {:link => {:url => node.attr('href'), :_ => parsed_children}}
                        end
                      ensure
                        node.unlink
                      end
                    else
                      p node
                      raise "Need Developer"
                    end
                  when 'div', 'span', 'li'
                    ensure_empty_node node
                  when 'ul'
                    if node.matches? '.articleList'
                      r = {:article_list => parsed_children}
                    else
                      p node
                      raise 'Need Developer'
                    end
                  when 'phrase'
                    rr = {}
                    node.attributes.each do |name, attr_node|
                      rr[name] = attr_node.content
                    end
                    rr[:_] = parsed_children
                    r = {:phrase => rr}
                  else
                    raise 'Unrecognized node in .articlePage paragraphs: ' + "\n" + node.inspect + "\n"
                end
                ensure_empty_node node
                return r, f
              end

            end #ArticlePageParser

            class ArticleParser < HTMLParser
              @@head_meta_parser = HeadMetaParser.new
              @@article_headline_box_parser = ArticleHeadlineBoxParser.new
              @@article_page_parser= ArticlePageParser.new

              def parse(node)
                article_start_flag = false
                article_end_flag = false
                no_content = false

                article = []
                r = select_set_to_parse(node, ['head meta']) do |node_set|
                  r = []
                  node_set.each do |n|
                    nr = @@head_meta_parser.parse(n)
                    r << nr unless nr.nil?
                  end
                  {:head_meta => r}
                end
                article << r unless r.nil?
                select_only_node_to_parse(node, '.articleHeadlineBox', true) do |n|
                  article += @@article_headline_box_parser.parse n do |state|
                    article_start_flag = true if state[:article_start_flag]
                  end
                end
                article_story_body_node = node.css('#article_story_body').first
                if article_story_body_node.nil?
                  no_content = true
                  article << {:_nobody => true}
                else
                  select_only_node_to_parse article_story_body_node, '.articlePage', true do |article_page_node|
                    article += @@article_page_parser.parse(article_page_node) do |state|
                      article_end_flag = true if state[:article_end_flag]
                    end
                  end
                end

                #raise "Improper article start/end flag: start(#{article_start_flag}), end(#{article_end_flag})" unless (article_start_flag and article_end_flag) or no_content

                {:article => article}
              end
            end # class ArticleParser

          end # module Parsers

          def fix_article_html!(text)
            text.gsub!('<TH>', ' ')
          end
        end
      end
    end
  end
end
