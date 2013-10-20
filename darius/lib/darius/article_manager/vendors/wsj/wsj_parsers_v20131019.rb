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

            class HeadParser < HTMLParser
              def parse(node)
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
                ensure_empty_node node
                r
              end
            end # HeadParser

            class ArticleHeaderParser < HTMLParser
              def parse_simple_link node
                texts = node.xpath('./text()')
                raise "Not simple link: #{node.inspect}" unless texts.size == 1 and node.name = 'a' and node.has_attribute? 'href'
                r = {:link => node.attr('href'), :text => texts.first.content.strip}
                node.unlink
                r
              end

              def parse_simple_headline_text node
                texts = node.xpath('./text()')
                raise "Not simple headline: #{node.inspect}" unless texts.size == 1
                text = texts.first.content.strip
                node.unlink
                text
              end

              def parse(node)
                clear_empty_texts node
                r = {}
                r[:category] = select_only_node_to_parse node, 'hgroup.hgroup .header h2.region-cat', false do |region_cat_node|
                  link = select_only_node_to_parse region_cat_node, 'a', false do |link_node|
                    parse_simple_link link_node
                  end
                  ensure_empty_node region_cat_node
                  link
                end
                r[:headline] = select_only_node_to_parse node, 'h1[itemprop=headline]', false do |headline_node|
                  parse_simple_headline_text headline_node
                end
                r[:sub_headline] = select_only_node_to_parse node, 'h2.subHed', false do |sub_head_node|
                  parse_simple_headline_text sub_head_node
                end
                ensure_empty_node node
                r
              end
            end # ArticleHeaderParser

            class BylineParser < HTMLParser
              def parse(node)
                clear_empty_texts node
                node.css('span.intro').unlink
                r = {}
                ensure_empty_node node
                r
              end
            end # BylineParser


            class ArticleParser < HTMLParser
              @@head_parser = HeadParser.new
              @@article_header_parser = ArticleHeaderParser.new
              @@byline_parser = BylineParser.new
              #@@head_meta_parser = HeadMetaParser.new
              #   @@article_headline_box_parser = ArticleHeadlineBoxParser.new
              #  @@article_page_parser= ArticlePageParser.new

              def select_article_header_node(node)
                section = node.css('body.standard .pageFrame.standard .contentFrame section.sector.one').first
                header = section.css('header')
                begin_article_flag = false
                end_article_flag = false
                data_modules = {}
                header.children.each do |n|
                  next if end_article_flag
                  if begin_article_flag
                    if n.text? and n.content.strip.empty?
                      n.unlink
                      next
                    end
                    if n.element? and n.has_attribute? 'data-module-name'
                      data_modules[n.attr('data-module-name')] = n
                    end

                    if n.content.strip == 'END Article Header'
                      end_article_flag = true
                      n.unlink
                    elsif n.content.strip.match /^data-module-name="(.*)"$/
                      raise "Unrecognized data-module-name: #{$~[1]}" unless data_modules.has_key? $~[1].strip
                      n.unlink
                    end
                  elsif n.comment? and n.content.strip == 'BEGIN Article Header'
                    begin_article_flag = true
                    n.unlink
                  end
                end

                raise 'Required data-module-name not exist: resp.module.article.ArticleColumnist' unless data_modules.has_key? 'resp.module.article.ArticleColumnist'
                raise "Unmatched BEGIN/END Article Header flags BEGIN:#{begin_article_flag} END:#{end_article_flag}" unless begin_article_flag and end_article_flag
                data_modules['resp.module.article.ArticleColumnist']
              end

              def select_byline_author_connect_node(node)
                section = node.css('body.standard .pageFrame.standard .contentFrame section.sector.two').first
                column = section.css('> .column.one').first
                bylines = column.css('[data-module-name="resp.module.article.BylineAuthorConnect"]')
                raise "Unsupported number of bylines: #{bylines.size}" unless bylines.size == 1
                byline = bylines.first
                while true
                  ns = byline.next_sibling
                  if ns.text? and ns.content.strip.empty?
                    ns.unlink
                    next
                  end
                  if ns.comment? and ns.content.strip == 'data-module-name="resp.module.article.BylineAuthorConnect"'
                    ns.unlink
                    break
                  end
                  raise 'No end comment for module resp.module.article.BylineAuthorConnect'
                end
                byline
              end


              def parse(node)
                begin
                  n = node.xpath('/comment()').first
                  raise "Invalid Page Comment Marker: #{n.inspect}" unless n.content.strip == 'TESLA DESKTOP V1'
                  n.unlink
                end
                article = {}
                article[:meta] = select_only_node_to_parse(node, 'head', false) do |head_node|
                  meta = @@head_parser.parse(head_node)
                  ensure_empty_node head_node
                  meta
                end

                article[:header] = @@article_header_parser.parse(select_article_header_node(node))
                article[:by] = @@byline_parser.parse(select_byline_author_connect_node(node))


                puts (JSON.pretty_generate article).slice -1024..-1
                puts '========'

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

