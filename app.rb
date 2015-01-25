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
        extract_page_data if data.empty?
      rescue NoMethodError
        print "No more results"
      end
    end

    def save
      return 'Scrape data first' if data.empty?
      saver.save
    end

    attr_reader :saver
    def saver
      @saver ||= Quibb::DataSaver.new(data)
    end

    private

    def fetch_data
      @data = page_n.inject([]) do |all_data, n|
        page_data = Quibb::Page.new(auth, n).data
        all_data << page_data
      end.flatten
    end

    def extract_page_data
      page_n.each do |n|
        page_data = Quibb::Page.new(auth, n).data
        data << page_data
        data.flatten!
      end
    end
  end
end

module Quibb
  class DataSaver
    attr_reader :data, :db

    def initialize(data)
      @data = data
      @db   = Quibb::DB.new.connection
    end

    def save
      data.each do |d|
        user_id    = save_user(d)
        article_id = save_article(d, user_id)
        create_new_metric(d, article_id)
      end
    end

    def find_user(d)
      db[:users].filter(name: d.fetch(:user_name),
          url:      d.fetch(:user_url),
          position: d.fetch(:user_position)).first
    end

    def find_article(d)
      db[:articles].filter(quibb_url: d.fetch(:quibb_link),
         title:           d.fetch(:title),
         original_domain: d.fetch(:original_domain)).first
    end

    private

    def save_user(d)
      user = find_user(d)
      return user.fetch(:id) if user
      create_new_user(d)
    end

    def save_article(d, user_id)
      article = find_article(d)
      return article.fetch(:id) if article
      create_new_article(d, user_id)
    end

    def create_new_user(d)
      db[:users].insert(name:     d.fetch(:user_name),
                        url:      d.fetch(:user_url),
                        position: d.fetch(:user_position))
    end

    def create_new_article(d, user_id)
      db[:articles].insert(quibb_url: d.fetch(:quibb_link),
         title:           d.fetch(:title),
         original_domain: d.fetch(:original_domain),
         user_id:         user_id)
    end

    def create_new_metric(d, article_id)
      db[:metrics].insert(date_time:  d.fetch(:date_time),
        views:      d.fetch(:views),
        stars:      d.fetch(:stars),
        comments:   d.fetch(:comments),
        rank:       d.fetch(:rank),
        date_time:  d.fetch(:date_time),
        article_id: article_id)
    end
  end
end

module Quibb
  class DB
    attr_reader :connection
    def initialize
      #@connection = Sequel.sqlite
      # @connection = Sequel.connect('sqlite://quibb.db')
      @connection = Sequel.connect("postgres://#{ ENV['DB_U'] }:#{ ENV['DB_P']}@#{ ENV['DB_H'] }:#{ ENV['DB_PORT'] }/#{ ENV['DB_N'] }")
      create_tables unless tables_exsist?
      connection
    end

    private

    def tables_exsist?
      connection.tables == [:users, :articles, :metrics]
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
        String :original_domain
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
      { quibb_link: quibb_link, title: title, original_domain: original_domain, user_url: user_url,
        user_name: user_name, user_position: user_position, views: views, stars: stars,
        comments: comments }
    end

    private

    def quibb_link
      full_title[0].children[2].attributes['href'].value
    end

    def title
      full_title[0].children[2].children[0].to_s
    end

    def original_domain
      full_title[0].children[1].attributes["data-original-title"].value
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