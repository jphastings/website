require 'kramdown'

module Haml
  module Filters
    module Kramdown
      include Base

      def render(text)
        ::Kramdown::Document.new(text).to_html
      end

    end
  end
end