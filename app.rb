require 'airbrake'
require 'sinatra/base'
require 'tracker_api'
require 'rack/ssl-enforcer'
require 'redcarpet'

renderer = Redcarpet::Render::HTML.new(hard_wrap: true)
markdown = Redcarpet::Markdown.new(renderer)


class CardOMatic < Sinatra::Base

  LABEL_PRINTED = 'printed'

  configure :production do
    use Rack::SslEnforcer

    if ENV["USE_AIRBRAKE"]
      Airbrake.configure do |config|
        config.api_key = ENV["AIRBRAKE_API_KEY"]
        config.host    = ENV["AIRBRAKE_HOST"]
        config.port    = 443
        config.secure  = true
        config.params_filters << "api_key"
      end

      use Airbrake::Rack
      enable :raise_errors
    end
  end
  configure do
    set(:google_ad_id, ENV["GOOGLE_AD_ID"])
    set(:google_analytics_id, ENV["GOOGLE_ANALYTICS_ID"])
  end

  get '/' do
    @intro = true

    erb :start
  end

  post '/projects' do
    client = setup_api_key

    begin
      @projects = client.projects
    rescue TrackerApi::Error => e
      render_previous_step_with_error(:start, "We couldn't connect with your API key.")
    end

    erb :projects
  end

  STATE_FILTER_DEFAULTS = {
    "unstarted" => true,
    "started" => true,
    "finished" => true,
    "delivered" => false,
    "rejected" => false,
    "accepted" => false,
    "unscheduled" => false,
  }
  post '/iterations' do
    client = setup_api_key
    setup_project(client)

    @iterations = fetch_iterations(@project)

    erb :iterations
  end

  post '/render' do
    client = setup_api_key
    setup_project(client)

    if params[:iteration].nil? || params[:iteration].empty?
      @iterations = fetch_iterations(@project)
      render_previous_step_with_error(:iterations, 'Please choose an iteration.')
    end

    @story_link = "https://zxing.org/w/chart?cht=qr&chs=120x120&chld=L&choe=UTF-8&chl=https%3A%2F%2Fwww.pivotaltracker.com%2Fstory%2Fshow%2F"

    @stories = case params[:iteration]
    when 'icebox'
      @project.stories(with_state: "unscheduled", fields: ':default,owners')
    when 'backlog'
      @project.iterations(scope: 'backlog', fields: ':default,stories(:default,owners)').first.stories
    when 'epics'
      epics = @project.epics
      epics.each do |epic|
        epic.define_singleton_method(:story_type) do
          "epic"
        end
        epic.define_singleton_method(:labels) do
          []
        end
        epic.define_singleton_method(:owners) do
          []
        end
        epic.define_singleton_method(:estimate) do
          false
        end
      end
      epics
    when 'specific_stories'
      story_ids = params[:story_ids].split(',')
      story_ids.map do |story_id|
        @project.story(story_id.to_i)
      end
    when 'stories_since'
      date = params[:date_since]
      @project.stories(filter: "updated_since:\"#{date}\"")
    when 'label'
      @project.stories(filter: %Q(label:"#{params[:label]}"))
    when 'unprinted'
      @project.iterations(scope: :current_backlog).flat_map(&:stories).
        reject { |story| story.labels.to_a.map(&:name).include? LABEL_PRINTED }
    when /\d+/
      iteration = params[:iteration].to_i
      options = { limit: 1 }
      options.merge!(fields: ':default,stories(:default,owners)')
      options.merge!(offset: iteration-1) if iteration > 1
      @project.iterations(options).first.stories
    end

    @stories = @stories.sort_by(&:updated_at).reverse

    if params[:states].to_s.size > 0 && params[:iteration] != 'icebox'
      @stories = @stories.select do |story|
        params[:states].include?(story.current_state)
      end
    end

    @with_qr_codes = params[:with_qr_codes] == 'true'
    @page_backs = params[:page_backs] == 'true'

    mark_stories_as_printed if params[:mark_as_printed] == 'true'

    if @stories.any?
      erb :cards, :layout => false
    else
      erb :no_cards
    end
  end

  def setup_project(client)
    begin
      @project = client.project(params[:project_id].to_i)
      raise InvalidProjectId unless @project
    rescue TrackerApi::Error
      raise InvalidProjectId
    end
  rescue InvalidProjectId
    @projects = client.projects
    render_previous_step_with_error(:projects, 'Please choose a project to print cards for.')
  end

  def setup_api_key
    @api_key = params[:api_key]

    if @api_key.nil? || @api_key.empty?
      render_previous_step_with_error(:start, 'Please enter an API key')
    end

    TrackerApi::Client.new(token: @api_key)
  end

  def fetch_iterations(project)
    start = [1, project.current_iteration_number-4].max
    (start..project.current_iteration_number)
  end

  def render_previous_step_with_error(view, error)
    @error = error
    halt(400, erb(view))
  end

  def mark_stories_as_printed
    @stories.each do |story|
      story.add_label(LABEL_PRINTED)
      story.save
    end
  end

  class InvalidProjectId < StandardError; end
end
