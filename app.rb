require 'mechanize'
require 'byebug'
require 'sequel'

require 'dotenv'
Dotenv.load

module Quibb
  class Scraper
    attr_reader :auth, :data, :page_n

    def initialize
      @auth   = Quibb::Auth.new
      @data   = []
      @page_n = (0..100)
    end

    def scrape
      begin
        # fetch_data
        data = page_n.inject([]) do |all_data, n|
          page_data = Quibb::Page.new(auth, n).data
          all_data << page_data
        end.flatten
      rescue #NoMethodError
        # print "No more results"
      end
    end

    def save
      return 'Scrape data first' if data.empty?

    end

    private

    def fetch_data
      @data = page_n.inject([]) do |all_data, n|
        page_data = Quibb::Page.new(auth, n).data
        all_data << page_data
      end.flatten
    end
  end
end

module Quibb
  class DB
    attr_reader :connection
    def initialize
      @connection = Sequel.sqlite
      create_tables unless exsists?
      connection
    end

    private

    def exsists?
      connection[:users] && connection[:articles]
    end

    def create_tables
      create_users
      create_articles
      create_metrics
    end

    def create_users
      connection.create_table :users do
        primary_key :id
        String :name
        String :url
        String :position
      end
    end

    def create_articles
      connection.create_table :articles do
        primary_key :id
        String :quibb_url
        String :title
        Integer :user_id
      end
    end

    def create_metrics
      connection.create_table :metrics do
        primary_key :id
        DateTime :date_time
        Integer :views
        Integer :stars
        Integer :comments
        Integer :rank
        Integer :article_id
      end
    end
  end
end

module Quibb
  class Auth
    TWITTER_AUTH_URL = 'http://quibb.com/auth/twitter'

    attr_reader :agent, :auth_page, :auth_form, :auth_page

    def initialize
      @agent     = Mechanize.new
      @auth_page = agent.get(TWITTER_AUTH_URL)
      @auth_form = auth_page.form
      @auth_page = login
    end

    private

    def login
      auth_form.fields[2].value = ENV['TWITTER_E']
      auth_form.fields[3].value = ENV['TWITTER_P']
      form_submit_page          = agent.submit(auth_form, auth_form.buttons.first)
      auth_url                  = form_submit_page.links[0].href
      agent.get(auth_url)
    end
  end
end

module Quibb
  class Page
    TOP_STORIES_URL = 'http://quibb.com/stories/top'

    attr_reader :posts, :page_number

    def initialize(auth, page_number)
      @page_number = page_number
      html         = auth.agent.get("#{ TOP_STORIES_URL }?page=#{ page_number }")
      @posts       = html.search('.infinite_row')
      # throw :end_results if posts.empty?
    end

    def data
      posts.each_with_index.inject([]) do |all, (post_raw, n)|
        post    = Quibb::Post.new(post_raw)
        current = post.data
        current = current.merge({ date_time: Time.now, rank: page_number + n + 1 })
        all << current
        all
      end
    end
  end
end

module Quibb
  class Post

    attr_reader :post
    def initialize(post)
      @post = post
    end

    def data
      { quibb_link: quibb_link, title: title, user_url: user_url, user_name: user_name,
        user_position: user_position, views: views, stars: stars, comments: comments }
    end

    private

    def quibb_link
      full_title[0].children[2].attributes['href'].value
    end

    def title
      full_title[0].children[2].children[0].to_s
    end

    def user_url
      full_title[0].children[4].children[1].attributes['href'].value
    end

    def user_name
      full_title[0].children[4].children[1].children.to_s
    end

    def user_position
      full_title[0].children[4].children[1].children[0].to_s
    end

    def views
      body_strings[2].to_i
    end

    def stars
      body_strings[4].to_i
    end

    def comments
      body_strings[6].to_i
    end

    def viewers
      viewers_string = body_strings[8][0..-18]
      viewers_array  = viewers_string.split(',')
      last_viewer    = viewers_array.pop[5..-1]
      viewers_array << last_viewer
      viewers_array.collect { |viewer| viewer.strip }
    end

    def full_title
      post.search('.link_info').search('.post').search('.linkpost').search('.link_box').search('.title')
    end

    def body_strings
      post.search('.link_info').search('.foot').search('.indicators').text.split(/\n/)
    end
  end
end