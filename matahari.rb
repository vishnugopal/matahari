
#Add lib/ to path
curr_path = File.dirname(__FILE__)
$:.unshift("#{curr_path}/lib")

require 'mechanize'
require 'yaml'
require 'debuggable'

class MataHari
  
  attr_accessor :options, :agent
  
  include Debuggable
  
  def initialize(options)
    self.options = options
    self.debug_mode = options['debug_mode'] || false
    self.agent = WWW::Mechanize.new
    
    connect_spymaster_to_twitter
    out "Starting seduction..."
    
    loop do
      sleep seduce_the_spymaster
    end
  end
  
  def connect_spymaster_to_twitter
    out "Connecting to twitter..."
    page = agent.get(spymaster_url_for('home'))
    page = agent.click page.links_with(:text => "Start playing Spymaster now.")[0]
    
    # At the twitter form stage, let's fill in our credentials & submit
    login_form = page.forms[0]
    login_form.field_with(:name => 'session[username_or_email]').value = options['twitter']['username']
    login_form.field_with(:name => 'session[password]').value = options['twitter']['password']
    page = agent.submit(login_form, login_form.buttons[1])
    
    out "Following oauth link back..."
    oauth_link = page.search(".//div[@class='message-content']/p/a").attr('href')
    page = agent.get(oauth_link)
  end
  
  def seduce_the_spymaster
    page = agent.get(spymaster_url_for('tasks'))

    auth_token = page.body.to_s.match(/AUTH_TOKEN = "(.*)"/)[1]    
    current_energy = page.search('li#current-energy-item span.vitals-energy').inner_html.to_i
    refresh_in = 0
    page.search('li#mini-dashboard-timer span.vitals-refresh').inner_html.to_s.split(':').tap do 
      |time| refresh_in = time[0].to_i * 60 + time[1].to_i + 5
    end
    last_task = page.search('ul.task-list > li').last
    task_name = last_task.search(".//a[@class='perform-task-button']").attr('task').to_s.strip
    required_energy = last_task.search("li.energy-used").inner_html.gsub('<span class="label">Energy Used</span>', '').to_s.strip.to_i
   
    out "Auth token is: #{auth_token}"
    out "Current energy: #{current_energy}"
    out "Refresh in: #{refresh_in}"
    out "Trying to perform task: #{task_name}"
    out "Required energy for task: #{required_energy}"
    
    if task_name == '' || required_energy == 0
      out "No task to perform (energy is probably not enough!)"
    else
      task_number = current_energy / required_energy
      out "Sufficient energy found to perform task #{task_number} time(s)."
      task_number.times do
        out "Performing task..."
        page = agent.post(spymaster_url_for('tasks_perform'), 
                { 'task' => task_name,  
                  'authenticity_token' => auth_token, 
                  'time' => '700' })
      end
      out "Done, coolio!"
    end
    
    refresh_in
  end
  
  def spymaster_url_for(url_name)
    "#{options['spymaster']['urls']['prefix']}#{options['spymaster']['urls'][url_name]}"
  end

end

options = YAML.load(File.open(File.join(File.dirname(__FILE__), 'config.yml')))
MataHari.new(options)
