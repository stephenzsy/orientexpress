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
            ARTICLE_PROCESSOR_VERSION = '2013-11-11-01'
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

            class BylineParser < HTMLParser

              def simple_text?(node)
                return false unless node.children.size == 1 and node.children.first.text?
                true
              end

              def parse(node)
                clear_empty_texts node
                r = select_only_node_to_parse node, '.connect.byline-dsk', true do |byline|
                  if simple_text? byline
                    begin
                      return byline.xpath('./text()').first.content.strip
                    ensure
                      byline.unlink
                    end
                  end
                  result = {}
                  byline.css('span.intro, span.c-aggregate').unlink
                  byline.css('.social-dd').each do |social_dd|
                    author = {}
                    social_dd.css('> menu.c-menu').unlink
                    social_dd.children.each do |d|
                      if d.matches? 'span.c-name[rel=author][itemprop=author]'
                        unlink_empty_nodes d.css('> span.bk-box')
                        texts = d.xpath('./text()')
                        raise "Invalid text members in span.c-name: #{texts.inspect}" unless texts.size == 1
                        author[:name] = texts.first.content.strip
                        d.unlink
                      elsif d.text?
                        if ['and'].include? d.content.strip
                          d.unlink
                        elsif /^in (.*)( and)?$/i.match d.content.strip
                          author[:location] = $~[1].strip
                          d.unlink
                        else
                          author[:extra] = d.text.strip
                          d.unlink
                        end
                      else
                        raise "Invalid node element in .social-dd: #{d.inspect}"
                      end
                    end
                    next if author.empty?
                    result[:authors] ||= []
                    result[:authors] << author
                  end
                  ensure_empty_node byline
                  result
                end
                ensure_empty_node node
                r
              end
            end # BylineParser

            class ArticleHeaderParser < HTMLParser
              @@byline_parser = BylineParser.new

              def parse_simple_link(node)
                texts = node.xpath('./text()')
                raise "Not simple link: #{node.inspect}" unless texts.size == 1 and node.name = 'a' and node.has_attribute? 'href'
                r = {:link => node.attr('href'), :text => texts.first.content.strip}
                texts.unlink
                raise "Not simple link: #{node.inspect}" if node.children.size > 0
                node.unlink
                r
              end

              def parse_simple_headline_text(node)
                texts = node.xpath('./text()')
                raise "Not simple headline: #{node.inspect}" unless texts.size == 1

                text = texts.first.content.strip
                texts.unlink
                raise "Not simple headline: #{node.inspect}" if node.children.size > 0
                node.unlink
                text
              end

              def parse(node)
                clear_empty_texts node
                r = {}
                ['hgroup.hgroup .header h2.region-cat',
                 'hgroup.hgroup .header h5.region-cat',
                 'hgroup.columnist-hgroup .columnist-header h2.region-cat'].each do |selector|
                  category = select_only_node_to_parse node, selector, true do |region_cat_node|
                    rr = select_only_node_to_parse region_cat_node, 'a', true do |link_node|
                      parse_simple_link link_node
                    end
                    if rr.nil?
                      rr = parse_simple_headline_text region_cat_node
                    else
                      ensure_empty_node region_cat_node
                    end
                    rr
                  end

                  unless category.nil?
                    r[:categories] ||= []
                    r[:categories] << category
                  end
                end
                r[:headline] = select_only_node_to_parse node, 'h1[itemprop=headline]', false do |headline_node|
                  parse_simple_headline_text headline_node
                end
                sub_headline = select_only_node_to_parse node, 'h2.subHed', true do |sub_head_node|
                  if sub_head_node.children.size > 0
                    parse_simple_headline_text sub_head_node
                  else
                    nil
                  end
                end
                r[:sub_headline] = sub_headline unless sub_headline.nil?
                columnist = select_only_node_to_parse node, 'hgroup.columnist-hgroup .columnist', true do |columnist_node|
                  @@byline_parser.parse(columnist_node)
                end
                r[:by_columnist] = columnist unless columnist.nil?
                ensure_empty_node node
                r
              end
            end # ArticleHeaderParser

            class ArticleBodyParser < HTMLParser

              def parse_paragraph(node)
                if node.text?
                  begin
                    t = node.content.strip.gsub(/\s+/, ' ')
                    return {:_ => t}, t
                  ensure
                    node.unlink
                  end
                elsif node.comment?
                  case node.content.strip
                    when 'module article chiclet',
                        'up, down, neutral',
                        'T1:M'
                      # pass
                      node.unlink
                      return nil, nil
                    else
                      raise "Invalid comment node: #{node.inspect}"
                  end
                end

                # pre recursive
                case node.name
                  when 'span'
                    if node.matches? '.article-chiclet'
                      node.unlink
                      return nil, nil
                    end
                end

                r = []
                f = []
                begin
                  node.children.each do |n|
                    rr, ff = parse_paragraph n
                    r << rr unless rr.nil?
                    f << ff unless ff.nil?
                  end
                rescue => e
                  raise e
                end

                if r.empty?
                  r = nil
                elsif r.size == 1
                  r = r.first
                end

                case node.name
                  when /^h(\d+)$/
                    r = {:heading => r, :level => $~[1].to_i}
                  when 'div'
                    if node.matches? '.inset-blockquote'
                      # pass
                    else
                      raise "Unsupported span node: #{node.inspect}"
                    end
                  when 'article', 'p'
                    r = {:_ => r}
                  when 'strong', 'em', 'blockquote'
                    r = {node.name.to_sym => {:_ => r}}
                  when 'br'
                    # skip
                  when 'a'
                    if node.matches? '.t-company' and node.has_attribute? 'href'
                      r ||= {}
                      r.merge!({:link => {:url => node.attr('href'), :type => 't-company'}})
                    elsif node.has_attribute?('href')
                      begin
                        case node.attr('href')
                          when /^mailto:(.*)/
                            r = {:_ => r, :email => {:address => $~[1]}}
                          else
                            r = {:_ => r, :link => {:url => node.attr('href')}}
                        end
                      ensure
                        node.unlink
                      end
                    else
                      raise "Unsupported link: #{node.inspect}"
                    end
                  when 'span'
                    if node.matches? '.l-qt, .r-qt'
                      node.unlink
                      return nil, nil
                    elsif node.matches? '.inset-author'
                      r = {:author => r}
                    else
                      raise "Unsupported span node: #{node.inspect}"
                    end
                  when 'ul'
                    if node.matches? '.articleList'
                      r = {:article_list => r}
                    else
                      raise "Unsupported ul node: #{node.inspect}"
                    end
                  when 'li'
                    r = {:item => r}
                  else
                    p r
                    raise "Unsupported node: #{node.inspect}"
                end

                ensure_empty_node node
                if f.empty?
                  f = nil
                elsif f.size == 1
                  f = f.first
                end
                return r, f
              end

              # end parse_paragraph

              def parse(node)
                clear_empty_texts node
                r = {}
                time_dsk = select_only_node_to_parse node, '.module.datestamp-dsk', false do |n|
                  r = {:text => n.text.strip}
                  r[:timestamp] = Time.parse(r[:text]).utc.iso8601
                  r
                end
                r[:body] = select_only_node_to_parse node, 'article.module.articleBody#articleBody[itemprop=articleBody]', false do |body|
                  [
                      '.module.rich-media-inset', '.module.rich-media-inset-iframe',
                      '.module.inset-group', '.module.inset-box',
                      '.module.editors-picks',
                      'i', 'img'
                  ].each { |selector| body.css(selector).unlink }
                  rr, ff = parse_paragraph(body)
                  result = {}
                  result[:paragraphs] = rr unless rr.nil?
                  result[:flattened] = ff unless ff.nil?
                  result
                end
                ensure_empty_node node
                r
              end

            end # ArticleBodyParser

            class ParseException < StandardError
              attr_accessor :status_code

              def initialize(message, status_code)
                super message
                self.status_code = status_code
              end

            end

            class ArticleParser < HTMLParser
              @@head_parser = HeadParser.new
              @@article_header_parser = ArticleHeaderParser.new
              @@byline_parser = BylineParser.new
              @@article_body_parser = ArticleBodyParser.new

              def select_article_header_node(node)
                section = node.css('.contentFrame section.sector.one').first
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

              def select_module_node(node, module_name)
                section = node.css('body.standard .pageFrame.standard .contentFrame section.sector.two').first
                column = section.css('> .column.one').first
                modules = column.css("[data-module-name=\"#{module_name}\"]")
                raise "Unsupported number of modules: #{modules.size} for module name: #{module_name}" unless modules.size == 1
                m = modules.first
                while true
                  ns = m.next_sibling
                  if ns.text? and ns.content.strip.empty?
                    ns.unlink
                    next
                  end
                  if ns.comment? and ns.content.strip == "data-module-name=\"#{module_name}\""
                    ns.unlink
                    break
                  end
                  raise "No end comment for module resp.module.article.#{module_name}"
                end
                m
              end

              def parse(node)
                begin
                  n = node.xpath('/comment()').first
                  if n.nil? or n.content.strip != 'TESLA DESKTOP V1'
                    e = V20131019::ParseException.new "Invalid Page Comment Marker: #{n.inspect}", :invalid_format
                    raise e
                  end
                  n.unlink
                end
                article = {}
                article[:meta] = select_only_node_to_parse(node, 'head', false) do |head_node|
                  meta = @@head_parser.parse(head_node)
                  ensure_empty_node head_node
                  meta
                end

                page_frame = node.css('body .pageFrame').first
                if page_frame.matches? '.content-interactive'
                  return {:article => {:error => :no_static_content}}
                end
                article.merge! @@article_header_parser.parse(select_article_header_node(page_frame))
                byline = @@byline_parser.parse(select_module_node(node, 'resp.module.article.BylineAuthorConnect'))
                article[:by] = byline unless byline.nil?
                article.merge! @@article_body_parser.parse(select_module_node(node, 'resp.module.article.articleBody'))

                {:article => article}
              end
            end # class ArticleParser
          end
        end
      end
    end
  end
end

