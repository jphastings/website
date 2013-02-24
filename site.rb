require 'coderay'
require 'haml'
require 'kramdown'
require 'haml-kramdown'
require 'less'
require 'sinatra'

set :haml, format: :html5

get '/css/:style.css' do
  less params[:style].to_sym
end

get '/' do
  haml :index, locals: { area: 'Home', title: 'Home' }
end

get '/blog' do
  filenames = Dir::glob('blog/*.markdown')
  posts = filenames.collect do |filename|
    content = Kramdown::Document.new(File.read(filename), coderay_line_numbers: nil)
    metadata = extract_metadata(content)
    metadata.merge({
      link: '/blog/' + File::basename(filename, '.*')
    })
  end
  posts.sort! { |a, b| b[:date] <=> a[:date] }
  haml :'blog/index', locals: { area: 'Blog', title: 'Blog', posts: posts }
end

get '/blog/:key' do
  filename = "./blog/#{params[:key]}.markdown"
  content = Kramdown::Document.new(File.read(filename), coderay_line_numbers: nil)
  metadata = extract_metadata(content)
  text = strip_metadata!(content).to_html
  haml :'blog/post', locals: metadata.merge({ area: 'Blog', text: text })
end

get '/cv' do
  haml :cv, locals: { area: 'CV', title: 'CV' }
end

def extract_metadata(content)
  content.root.children.reduce({}) do |meta, node|
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

def strip_metadata!(content)
  content.root.children = content.root.children.drop_while { |c| c.type != :header }
  content
end
