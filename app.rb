require 'mechanize'
require 'byebug'
require 'dotenv'
Dotenv.load

module Quibb
  class Auth
    TWITTER_AUTH_URL = 'http://quibb.com/auth/twitter'
    TOP_STORIES_URL = 'http://quibb.com/stories/top'

    attr_reader :agent, :auth_page, :auth_form, :auth_page, :top_stories_page

    def initialize
      @agent            = Mechanize.new
      @auth_page        = agent.get(TWITTER_AUTH_URL)
      @auth_form        = auth_page.form
      @auth_page        = login
      @top_stories_page = agent.get(TOP_STORIES_URL)
    end

    def posts
      top_stories_page.search('.infinite_row')
    end

    def data
      posts.inject([]) do |all, post_raw|
        post = Quibb::Post.new(post_raw)
        current = { quibb_link: post.quibb_link, title: post.title, user_url: post.user_url, user_name: post.user_name,
                    user_position: post.user_position, views: post.views, stars: post.stars, comments: post.comments, date_time: Time.now }
        all << current
        all
      end
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
  class Post
    attr_reader :post

    def initialize(post)
      @post = post
    end

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
      last_viwer     = viewers_array.pop[5..-1]
      viewers_array << last_viwer
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