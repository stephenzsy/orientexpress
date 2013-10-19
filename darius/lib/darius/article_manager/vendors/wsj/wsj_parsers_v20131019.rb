require_relative '../../utils/parser'

module ColdBlossom
  module Darius
    module ArticleManager
      module VendorParsers
        module WSJ
          module V20131019
            include Darius::ArticleManager::Utils::Parsers

            EXTERNAL_DOCUMENT_VERSION = '2013-10-19'
            DAILY_ARCHIVE_INDEX_PROCESSOR_VERSION = '2013-10-19'
            ARTICLE_PROCESSOR_VERSION = '2013-10-19-01'
            ARTICLE_PROCESSOR_PATCH = 1

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

            class HeadParser < HTMLParser

              def parse node
                r = []
                named_meta = {}
                itemprop = {}
                og_property = {}
                select_set_to_parse(node, ['meta']) do |meta_node|
                  if meta_node.has_attribute? 'http-equiv'
                    meta_node.unlink
                    next
                  elsif meta_node.has_attribute? 'name'
                    if meta_node.attr('name').match /^(twitter|fb|og):/ or
                        meta_node.attr('name') == 'viewport'
                      meta_node.unlink
                      next
                    end
                    named_meta[meta_node.attr('name')] = meta_node.attr('content')
                  elsif meta_node.has_attribute? 'itemprop'
                    itemprop[meta_node.attr('itemprop')] = meta_node.attr('content')
                  elsif meta_node.has_attribute? 'property' and meta_node.attr('property').match /^og:/
                    itemprop[meta_node.attr('property')] = meta_node.attr('content')
                  else
                    raise "Unsupported head meta tag: #{meta_node.to_s}"
                  end
                end
                select_only_node_to_parse(node, 'title', true) do |title|
                  r << {:title => title.content}
                end
                r << {:named_meta => named_meta} unless named_meta.empty?
                r << {:itemprop => itemprop} unless itemprop.empty?
                r << {:og_property => og_property} unless og_property.empty?
                puts JSON.pretty_generate r
                ensure_empty_node node
                r
              end

            end


            class ArticleParser < HTMLParser
              @@head_parser = HeadParser.new
              #@@head_meta_parser = HeadMetaParser.new
              #   @@article_headline_box_parser = ArticleHeadlineBoxParser.new
              #  @@article_page_parser= ArticlePageParser.new

              def parse(node)
                article = []
                select_only_node_to_parse(node, 'head', false) do |head_node|
                  article << {:head => @@head_parser.parse(head_node)}
                end

                raise 'Need Developer'

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
          end
        end
      end
    end
  end
end

