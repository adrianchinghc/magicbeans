class ProgramsController < ApplicationController
  before_action :set_program, only: [:show, :edit, :update, :destroy]
  after_action :set_default_for_assoc, only: [:update, :create]
  respond_to :html

  def index
    @programs = Program.all
    respond_with(@programs)
  end

  def show
    @program = Program.find(params[:id])
  end

  def new
    @program = Program.new
    1.times {@program.activities.build}
    respond_with(@program)
    
  end

  def edit
  end

  def create
    @program = Program.new(program_params)

    @program.activities.each do |a|
      if a.description.empty?
        a.description = @program.description
      end

      if a.keytakeaway.empty?
        a.keytakeaway = @program.keytakeways
      end

      if a.speaker.empty?
        a.speaker = @program.speaker
      end

      if a.speakerbio.empty?
        a.speakerbio = @program.speakerbio
      end
    end

    @program.activities.each do |activity|
      @event = {
          'summary' => activity.name,
          'description' => activity.description,
          'location' =>  activity.venue,
          'start' => {'dateTime' => activity.date,
                      'timeZone' => "Asia/Kuala_Lumpur"
                      },
          'end' => {'dateTime' => activity.date,
                  'timeZone' => "Asia/Kuala_Lumpur"
                    } }

      client = Google::APIClient.new
      client.authorization.access_token = current_user.token
      service = client.discovered_api('calendar', 'v3')

      @set_event = client.execute(:api_method => service.events.insert,
                                  :parameters => {'calendarId' => current_user.email},
                                  :body => JSON.dump(@event),
                                  :headers => {'Content-Type' => 'application/json'})
    end

    if @program.save
        redirect_to programs_path, success: 'Successfully created a program!'
    else
        render action: "new"
    end
  end

  def update
    @program.activities.each do |activity|

    client = Google::APIClient.new
    client.authorization.access_token = current_user.token
    service = client.discovered_api('calendar', 'v3')
      
    result = client.execute(:api_method => service.events.get,
                        :parameters => {'calendarId' => 'primary', 'eventId' => 'eventId'})
    event = result.data
    event.summary = activity.name

    result = client.execute(:api_method => service.events.update,
                             :parameters => {'calendarId' => current_user.email, 'eventId' => event.id},
                             :body_object => event,
                             :headers => {'Content-Type' => 'application/json'})
    end
    if @program.update(program_params)
      redirect_to programs_path, success: 'Program was successfully updated!'
    else
      render action: 'edit'
    end
  end

  def destroy
    if @program.destroy
      redirect_to programs_path, success: 'Program was successfully deleted!'
    else
      render action: 'index'
    end
  end

  private
    def set_program
      @program = Program.find(params[:id])
      rescue ActiveRecord::RecordNotFound
      redirect_to(root_url, alert: 'Program not found')
    end

    def program_params
      params.require(:program).permit(:name, :description, :speaker, :speakerbio, :biourl, :keytakeways, :tags, :resources, activities_attributes: [:id, :name, :date, :venue, :description, :speaker, :speakerbio, :biolink, :keytakeaway, :prerequisite, :maxattendee, :tags, :resources, :_destroy])
    end


    def set_default_for_assoc
      @program.activities.each do |a|
        if a.description.empty?
          a.description = @program.description
        end

        if a.keytakeaway.empty?
          a.keytakeaway = @program.keytakeways
        end

        if a.speaker.empty?
          a.speaker = @program.speaker
        end

        if a.speakerbio.empty?
          a.speakerbio = @program.speakerbio
        end
      end

      @program.save
    end
end


  
