require 'kramdown'

module Kramdown
  class Document

    def metadata
      @root.children.reduce({}) do |meta, node|
        # stop when we find the header
        if (node.type == :header)
          meta[:title] = node.children.select { |c| c.type == :text }.first.value
          break meta
        end
        # process text nodes before the header as metadata attributes
        node.children.select { |c| c.type == :text }.each do |text|
          key, value = text.value.split(':')
          case key.strip.downcase
          when 'date'
            meta[:date] = Date.parse(value.strip)
          when 'tags'
            meta[:tags] = value.split(',').collect { |tag| tag.strip }
          end
        end
        meta
      end
    end

    def extract_metadata!
      meta = metadata
      @root.children = @root.children.drop_while { |c| c.type != :header }
      meta
    end

  end
end