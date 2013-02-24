require 'coderay'
require 'haml'
require 'kramdown'
require 'less'
require 'sinatra'

require_relative 'lib/haml/filters/kramdown'
require_relative 'lib/kramdown/document'

set :haml, format: :html5

get '/css/:style.css' do
  less params[:style].to_sym
end

get '/' do
  haml :index, locals: { area: 'Home', title: 'Home' }
end

get '/blog' do
  posts = Dir::glob('blog/**/*.markdown').map do |filename|
    content = Kramdown::Document.new(File.read(filename), coderay_line_numbers: nil)
    metadata = content.metadata
    metadata.merge({ link: '/blog/' + File::basename(filename, '.*') })
  end
  posts.reject! { |post| !post[:date] || post[:date] > Date::today } # only show posts with valid date
  posts.sort! { |a, b| b[:date] <=> a[:date] }
  haml :'blog/index', locals: { area: 'Blog', title: 'Blog', posts: posts }
end

get '/blog/:key' do
  filename = "./blog/#{params[:key]}.markdown"
  unless File.exists?(filename)
    status 404
    return haml :error, locals: { area: 'Blog', title: 'Post not found', message: 'Sorry, that post doesn\'t exist.' }
  end
  content = Kramdown::Document.new(File.read(filename), coderay_line_numbers: nil)
  metadata = content.extract_metadata!
  haml :'blog/post', locals: metadata.merge({ area: 'Blog', text: content.to_html })
end

get '/cv' do
  haml :cv, locals: { area: 'CV', title: 'CV' }
end