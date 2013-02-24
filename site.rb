require 'coderay'
require 'haml'
require 'kramdown'
require 'less'
require 'builder'
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
  haml :'blog/index', locals: { area: 'Blog', title: 'Blog', posts: blog_posts_metadata }
end

get '/blog/rss' do
  content_type 'application/rss+xml'
  posts = blog_posts_metadata
  builder do |rss|
    rss.rss version: '2.0' do
      rss.channel do
        rss.title 'Greg Beech\'s Blog'
        rss.link "http://#{request.host_with_port}/blog"
        rss.description 'Greg Beech\'s Blog'
        rss.language 'en-GB'
        rss.category 'Technology'
        rss.copyright "Copyright (C) Greg Beech 2006-#{Date::today.year}. All Rights Reserved."
        rss.pubDate posts.first[:date].strftime('%a, %d %b %Y %H:%M:%S GMT')
        rss.lastBuildDate Time.new.strftime('%a, %d %b %Y %H:%M:%S GMT')
        rss.docs 'http://blogs.law.harvard.edu/tech/rss'
        rss.generator 'Greg Beech\'s Website'
        rss.managingEditor 'greg@gregbeech.com'
        rss.webMaster 'greg@gregbeech.com'
        rss.ttl '60'
        posts.each do |post|
          rss.item do
            link = "http://#{request.host_with_port}#{post[:link]}"
            rss.title post[:title]
            rss.link link
            rss.description 'TODO: Description'
            rss.pubDate post[:date].strftime('%a, %d %b %Y %H:%M:%S GMT')
            rss.guid link
          end
        end
      end
    end
  end
end

get '/blog/:key' do
  filename = Dir::glob("blog/**/#{params[:key]}.markdown").first
  unless filename
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

def blog_posts_metadata
  posts = Dir::glob('blog/**/*.markdown').map do |filename|
    content = Kramdown::Document.new(File.read(filename), coderay_line_numbers: nil)
    metadata = content.metadata
    metadata.merge({ link: '/blog/' + File::basename(filename, '.*') })
  end
  posts.reject! { |post| !post[:date] || post[:date] > Date::today } # only show posts with valid date
  posts.sort! { |a, b| b[:date] <=> a[:date] }
end