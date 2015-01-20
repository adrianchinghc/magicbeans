class ActivitiesController < ApplicationController
  before_filter :authenticate_user!
  before_action :set_activity, only: [:show, :edit, :update, :destroy, :create_event, :tweet, :create_gcal, :share, :send_mails]
  load_and_authorize_resource
  # GET /activities
  # GET /activities.json
  def index
    @activities = Activity.all
  end

  # GET /activities/1
  # GET /activities/1.json
  def show
  end

  # GET /activities/new
  # def new
  #   @activity = Activity.new
  # end

  # GET /activities/1/edit
  def edit
  end

  # PATCH/PUT /activities/1
  # PATCH/PUT /activities/1.json
  def update
    respond_to do |format|
      if @activity.update(activity_params)
        @log = Log.new(title: 'An activity has been updated', log_type: 'activities', type_id: @activity.id)
        @log.save
        format.html { redirect_to @activity, notice: 'Activity was successfully updated.' }
        format.json { render :show, status: :ok, location: @activity }
      else
        format.html { render :edit }
        format.json { render json: @activity.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /activities/1
  # DELETE /activities/1.json
  def destroy
    @activity.destroy
    @log = Log.new(title: 'An activity has been destroyed', log_type: 'activities', type_id: @activity.id)
    @log.save
    respond_to do |format|
      format.html { redirect_to activities_url, notice: 'Activity was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def create_event
    if (@activity.event_id.nil?)
      @event = Organizer::Event.new(
        name: @activity.name,
        description: @activity.description,
        start: @activity.start_date.to_time,
        end: @activity.end_date.to_time,
        online_event: @activity.online,
        currency: "MYR",
        listed: @activity.listed)

      @event_response = Organizer.events(event: @event).post
      if (@event_response.status == 200)
        @activity.event_id = @event_response.body['id']
        @activity.save
        redirect_to activity_path(@activity), success: 'Successfully created a event!'
      else
        redirect_to activity_path(@activity), alert: "[#{@event_response.status}] #{@event_response.body["error_description"]}"
      end
    else
        redirect_to activity_path(@activity), alert: 'Event has already been created'
    end
  end

  def tweet
    client = Twitter::REST::Client.new do |config|
      config.consumer_key        = Magicbeans.twitter_consumer_key
      config.consumer_secret     = Magicbeans.twitter_consumer_secret
      config.access_token        = Magicbeans.twitter_access_token
      config.access_token_secret = Magicbeans.twitter_access_token_secret
    end

    begin
      message = params[:tweet][:message]
      share_event = Organizer.events(id: @activity.event_id).get
      if !message.blank?
        @send_tweet = client.update_with_media(message + "\n" + share_event.body["url"], File.new(open(share_event.body["logo"]).path))
        redirect_to activity_path(@activity), success: 'Successfully tweeted!'
      else      
        redirect_to activity_path(@activity), alert: 'Message cannot be blank. Try again!'
      end
    rescue Twitter::Error => e
      redirect_to activity_path(@activity), alert: "#{e}"
    end
  end

  def create_gcal
    @gcal_event = {
        'summary' => @activity.name,
        'description' => @activity.description,
        'location' =>  @activity.venue,
        'start' => {'dateTime' => DateTime.parse(@activity.start_date.to_s).rfc3339
                    },
        'end' => {'dateTime' => DateTime.parse(@activity.end_date.to_s).rfc3339
                  }}

    # Initialize the client
    client = Google::APIClient.new(application_name: 'MagicBeans', application_version: '0.0.1')
    # load and decrypt private key
    key = OpenSSL::PKey::RSA.new Magicbeans.rsa_key, 'notasecret'
    # generate request body for authorization
    client.authorization = Signet::OAuth2::Client.new(
                             :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
                             :audience             => 'https://accounts.google.com/o/oauth2/token',
                             :scope                => 'https://www.googleapis.com/auth/calendar',
                             :issuer               =>  Magicbeans.google_service_account_email,
                             :signing_key          =>  key
                             )

    # fetch access token
    client.authorization.fetch_access_token!
    # load API definition
    service = client.discovered_api('calendar', 'v3')
    # access API by using client
    @set_event = client.execute(:api_method => service.events.insert,
                                :parameters => {'calendarId' => Magicbeans.google_calendar_id },
                                :body => JSON.dump(@gcal_event),
                                :headers => {'Content-Type' => 'application/json'})

    if @set_event
      redirect_to activity_path(@activity), success: 'Successfully posted activity to Google Calendar!'
    else
      redirect_to activity_path(@activity), alert: "There was an error posting the event to Google Calendar"
    end
  end

  def share
    begin
      page = Koala::Facebook::API.new(Magicbeans.fb_page_access_token)
      message = params[:share][:message]
      share_event = Organizer.events(id: @activity.event_id).get
      if !message.blank?
        post_status = page.put_wall_post(message, {
                          "name" => @activity.name,
                          "link" => share_event.body["url"],
                          "caption" => @activity.name,
                          "description" => @activity.description,
                          "picture" => share_event.body["logo"]
                          })
        redirect_to activity_path(@activity), success: "Shared to Facebook successfully!"
      else      
        redirect_to activity_path(@activity), alert: 'Message cannot be blank. Try again!'
      end
    rescue Koala::Facebook::APIError => error
      redirect_to activity_path(@activity), notice: "#{error}"
    end
  end

  def send_mails
    @the_content = %Q{

      #{Magicbeans.mailchimp_message}

    <p>Below are details of the event:</p> 

    <p><strong>Program Name : </strong>#{@activity.program.name} </div></strong>
    
    <p><strong>Event Name : </strong>#{@activity.name}</p>

    <p><strong>Event Venue : </strong>#{@activity.venue}</p>
    
    <p><strong>Description : </strong>#{@activity.description}</p>
    
    <p><strong>Date  : </strong>#{@activity.start_date} - #{@activity.end_date}</p>

    Here is the link to RSVP for the event:
    #{Organizer.events(id: @activity.event_id).get.body["url"]}

    See you there!
    }

    begin
      apikey = Magicbeans.mailchimp_apikey
      @h = Hominid::API.new(apikey)
      list_id = params[:send_mails][:mailchimp_list_id]
        if list_id.present?
          campaign_id = @h.campaign_create('regular', 
                                     {:list_id => list_id, 
                                        :subject => 'Invitation to ' + @activity.program.name, 
                                        :from_email => @h.find_list_by_id(list_id)['default_from_email'],
                                        :from_name => @h.find_list_by_id(list_id)['default_from_name']},
                                      {:html => @the_content}
                                      )
          @h.campaign_send_now(campaign_id)
          redirect_to activity_path(@activity), success: 'Successfully sent mails!'
        else
          redirect_to activity_path(@activity), notice: 'Please select a list.' 
        end     
    rescue Hominid::APIError => error
      redirect_to activity_path(@activity), notice: "#{error}"
    end                          
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_activity
      @activity = Activity.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def activity_params
      params.require(:activity).permit(:id, :name, :start_date, :end_date, :venue, :description, :speaker, :speakerbio, :biolink, :keytakeaway, :prerequisite, :maxattendee, :tags, :resources, :speaker_img, :activity_img)
    end
end
