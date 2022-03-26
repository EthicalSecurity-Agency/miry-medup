require "json_mapping"
require "zaru_crystal/zaru"
require "json_mapping"

module Medium
  class Post
    class Paragraph
      JSON.mapping(
        {
          name:            String?,
          type:            Int64,
          text:            String,
          markups:         Array(ParagraphMarkup)?,
          metadata:        ParagraphMetadata?,
          layout:          Int64?,
          hasDropCap:      Bool?,
          dropCapImage:    DropCapImage?,
          iframe:          Iframe?,
          mixtapeMetadata: MixtapeMetadata?,
          href:            String?,
          alignment:       Int64?,
        },
        strict: true
      )

      def to_md(options : Array(Medup::Options) = Array(Medup::Options).new) : Tuple(String, String)
        content : String = ""
        assets = ""
        content = case @type
                  when 1
                    markup
                  when 2
                    "# #{markup}"
                  when 3
                    "# #{markup}"
                  when 4
                    m = metadata
                    if !m.nil? && !m.id.nil?
                      asset_id = Base64.strict_encode(m.id)
                      if options.includes?(Medup::Options::ASSETS_IMAGE)
                        if @href
                          "[![#{@text}](./assets/#{m.id})](#{@href})"
                        else
                          "![#{@text}](./assets/#{m.id})"
                        end
                      else
                        assets = "[image_ref_#{asset_id}]: data:image/png;base64,"
                        img = "![#{@text}][image_ref_#{asset_id}]"
                        encoded = download_image(m.id || "")
                        assets += encoded
                        if @href
                          img = "[#{img}](#{@href})"
                        end
                        img
                      end
                    else
                      ""
                    end
                  when 6
                    "> #{markup}"
                  when 7
                    ">> #{markup}"
                  when 8
                    "```\n#{@text}\n```"
                  when 9
                    "* #{markup}"
                  when 10
                    "1. #{markup}"
                  when 11
                    if @iframe.nil?
                      "<!-- Missing iframe -->"
                    else
                      frame = @iframe.not_nil!
                      asset_id = Zaru.sanitize!(frame.mediaResourceId)
                      "<iframe src=\"./assets/#{asset_id}.html\"></iframe>"
                      # Support Frame mode with inline content. Github does not support it.
                      # "<frame>#{frame.get}</frame>"
                    end
                  when 13
                    "### #{markup}"
                  when 14
                    "#{@mixtapeMetadata.try &.href}"
                  when 15
                    ""
                  else
                    raise "Unknown paragraph type #{@type} with text #{@text}"
                  end
        return content, assets
      end

      def download_image(name : String)
        download_url("https://miro.medium.com/#{name}")
      end

      def download_url(src)
        response = HTTP::Client.get(src)
        Base64.strict_encode(response.body)
      end

      def markup
        open_elements = {} of Int64 => Array(ParagraphMarkup)
        close_elements = {} of Int64 => Array(ParagraphMarkup)

        last_marked_pos = 0

        result : String = ""
        _markups = @markups
        return result if _markups.nil?
        _markups.each do |m|
          if open_elements.has_key?(m.start)
            open_elements[m.start] << m
          else
            open_elements[m.start] = [m] of ParagraphMarkup
          end

          if close_elements.has_key?(m.end)
            close_elements[m.end].insert(0, m)
          else
            close_elements[m.end] = [m] of ParagraphMarkup
          end
        end

        @text += " "
        char_index = 0
        # Grapheme is an experimental feature from Crystal to return symbols as
        # rendered, instead of static width bytes. It helpes to easy identify
        # emoji symbols chain.
        @text.each_grapheme do |symbol|
          if close_elements.has_key?(char_index)
            close_elements[char_index].each do |m|
              case m.type
              when 1 # bold
                result += "**"
              when 2 # italic
                result += "*"
              when 3 # link
                href = m.href.nil? ? "" : m.href.not_nil!
                result += "](#{href})"
              when 10 # code inline
                result += "`"
              else
                raise "Unknown markup type #{m.type} with text #{@text[m.start...m.end]}"
              end
            end
          end

          if open_elements.has_key?(char_index)
            open_elements[char_index].each do |m|
              case m.type
              when 1 # bold
                result += "**"
              when 2 # italic
                result += "*"
              when 3 # link
                result += "["
              when 10 # code inline
                result += "`"
              else
                raise "Unknown markup type #{m.type} with text #{@text[m.start...m.end]}"
              end
            end
          end

          result += symbol.to_s
          # Medium count each emoji symbol as 4 bytes, when Crystal uses 2 bytes.
          char_index += symbol.size == 1 ? 1 : symbol.size * 2
        end

        result.rchop
      end

      class ParagraphMarkup
        JSON.mapping(
          type: Int64,
          start: Int64,
          "end": Int64,
          href: String?,
          title: String?,
          rel?: String?,
          anchorType: Int64?
        )
      end

      class Iframe
        getter content : String?

        JSON.mapping(
          mediaResourceId: String
        )

        def get
          @content ||= Medium::Client.default.media(mediaResourceId)
        end
      end

      class MixtapeMetadata
        JSON.mapping(
          mediaResourceId: String,
          href: String?
        )
      end

      class DropCapImage
        JSON.mapping(
          id: String,
          originalWidth: Int64,
          originalHeight: Int64
        )
      end
    end
  end
end
