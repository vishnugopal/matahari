
#Add lib/ to path
$curr_path = File.dirname(__FILE__)
$:.unshift("#{$curr_path}/lib")

require 'mechanize'
require 'yaml'
require 'debuggable'
require 'cryptic'
require 'open-uri'
require 'mechanize_extensions'
require 'logger'
require 'json'


class MataHari
  
  attr_accessor :options, :agent, :simplekey, :ticks
  
  include Debuggable
  
  def initialize(options)
    self.options = options
    self.debug_mode = options['debug_mode'] || false
    self.agent = WWW::Mechanize.new
    self.agent.log = Logger.new("#{$curr_path}/#{options['raw_log']}") if options['debug_mode']
    
    connect_spymaster_to_twitter
    out "Starting seduction..."
    
    self.simplekey = load_simplekey
    self.ticks = 10    
    
    loop do
      sleep assassinate_the_spymaster
    end
  rescue WWW::Mechanize::ResponseCodeError => e
    out "Mechanize error: #{e.inspect}, exiting!"
  end
  
  def load_simplekey
    simplekey = open(spymaster_url_for("simplekey")).read
    out "Found simplekey as: #{simplekey}"
    simplekey
  end
  
  def connect_spymaster_to_twitter
    out "Connecting to twitter..."
    page = agent.get(spymaster_url_for('home'))
    
    begin
      page = agent.click page.links_with(:text => "Start playing Spymaster now.")[0]
    rescue NoMethodError
      out "Cannot connect to twitter (site possibly down for maintanence), exiting!"
      exit
    end
    
    twitter_url = page.body.to_s.match(/url=(.*)">/)[1]
    out "Getting twitter URL as #{twitter_url}"
    page = agent.get(:url => twitter_url, :referer => spymaster_url_for('home'))
    
    # At the twitter form stage, let's fill in our credentials & submit
    login_form = page.forms[0]
    
    unless login_form
      out "Can't reach twitter (site possibly overloaded), exiting!"
      out page.body.to_s
      exit
    end
    
    login_form.field_with(:name => 'session[username_or_email]').value = options['twitter']['username']
    login_form.field_with(:name => 'session[password]').value = options['twitter']['password']
    page = agent.submit(login_form, login_form.buttons[1])
    
    out "Following oauth link back..."
    oauth_link = page.search(".//div[@class='message-content']/p/a").attr('href')
    page = agent.get(oauth_link)
  end
  
  
  def assassinate_the_spymaster
    page = agent.get(spymaster_url_for('assassination'))
        
    auth_token = page.body.to_s.match(/AUTH_TOKEN = "(.*)"/)[1]    
    current_energy = page.search('li#mini-dashboard-energy span.value').inner_html.to_i
    current_health = page.search('li#mini-dashboard-health span.value').inner_html.to_i
    refresh_in = 0
    
    out "Auth token is: #{auth_token}"
    out "Current energy: #{current_energy}"
    out "Current health: #{current_health}"
    out "Refresh in: #{refresh_in}"
    
    page.search('li#mini-dashboard-timer span.vitals-refresh').inner_html.to_s.split(':').tap do 
      |time| refresh_in = time[0].to_i * 60 + time[1].to_i + 5
    end
    
    if current_health < options['spymaster']['minimum_health']
      out "Health #{current_health} is lower than minimum_health value #{options['spymaster']['minimum_health']}"
      out "Assassination is not healthy at this time, waiting #{refresh_in}s."
      return refresh_in
    end
    
    candidate_box = page.search("dl.candidate")
    spy_name = candidate_box.attr("spy")
    level = candidate_box[0].search("dd.level").inner_html
    required_energy = candidate_box[0].search("dd.energy-required").inner_html.to_i
    risk_level = candidate_box[0].search("dd.risk-level").inner_html
    out "Candidate found: #{spy_name}. Level: #{level} Required energy: #{required_energy} Risk Level: #{risk_level}"
    
    if required_energy > current_energy
      out "Not enough energy found for assassination, waiting #{refresh_in}s."
      return refresh_in
    end
    
    out "Assassinating #{spy_name}..."
    
    page = agent.post_with_headers(spymaster_url_for('assassination_execute'), 
            { 'id' => spy_name,  
              'authenticity_token' => auth_token
            },
            {'X-Requested-With' => 'XMLHttpRequest'})
    
    result = JSON.load(page.body.to_s)
    
    out "Victory: #{result['victory']} Encounter ID: #{result['encounter']}"

    results_url = "#{spymaster_url_for('assassination_results')}/#{result['encounter']}"
    out "Your #{result['victory']  ? 'gains' : 'losses'}..."

    page = agent.get(results_url)    
    odds_of_winning = page.search("#left-content p strong")[0].inner_html.to_s.strip
    experience = 0
    health = 0
    
    if result['victory']
      experience = page.search("#gains-content li.delta-experience-statistic span.positive")[0].inner_html.to_s.strip
    else
      health = page.search("#gains-content li.delta-health-statistic span.negative")[0].inner_html.to_s.strip
    end
    
    assets = page.search("#gains-content li.delta-assets-statistic span.amount")[0].inner_html.to_s.strip
    attack = page.search("#gains-content li.delta-attack-statistic")[0].inner_html.to_s.strip
    defense = page.search("#gains-content li.delta-defense-statistic")[0].inner_html.to_s.strip
    
    itemized_liquid = page.search("li#liquid-assets-item span.amount")[0].inner_html.to_s.strip
    itemized_attack = page.search("li#attack-item span").collect { |item| item.inner_html}.join(" ").to_s.strip
    itemized_defense = page.search("li#defence-item span").collect { |item| item.inner_html }.join(" ").to_s.strip
  
    out "Odds of Winning: #{odds_of_winning}"
    out "Experience: #{experience}"
    out "Health: #{health}"
    out "Assets: #{assets}"
    out "Attack: #{attack}"
    out "Defense: #{defense}"
    out "Itemized Liquid: #{itemized_liquid}"
    out "Itemized Attack: #{itemized_attack}"
    out "Itemized Defense: #{itemized_defense}"
    
    if result['victory'] and !itemized_defense.grep(/Armored Luxury Car/).empty?
      out "Armored luxury car got, selling!"
      page = agent.post_with_headers(spymaster_url_for('black_market_sell_item'), 
              { 'item' => 'armored_luxury_car',  
                'quantity' => 1,
                'authenticity_token' => auth_token
              },
              {'X-Requested-With' => 'XMLHttpRequest'})
    end
    
    5
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
      out "Sufficient energy not found to perform task, waiting!"
    else
      task_number = current_energy / required_energy
      out "Sufficient energy found to perform task #{task_number} time(s)."
      task_number.times do
        out "Performing task..."
        signature = Cryptic.hash(simplekey, 
                      options['spymaster']['urls']['tasks_perform'], auth_token, ticks)
        out "signature is: #{signature} ticks #{ticks} task #{task_name} auth token #{auth_token}"
        page = agent.post_with_headers(spymaster_url_for('tasks_perform'), 
                { 'task' => task_name,  
                  'authenticity_token' => auth_token, 
                  'ticks' => ticks, 
                  'ch' => signature },
                  {'X-Requested-With' => 'XMLHttpRequest'})
      end
      out "Done, coolio, waiting now!"
    end
    
    refresh_in
  end
  
  def spymaster_url_for(url_name)
    "#{options['spymaster']['urls']['prefix']}#{options['spymaster']['urls'][url_name]}"
  end

end

options = YAML.load(File.open(File.join(File.dirname(__FILE__), 'config.yml')))
MataHari.new(options)
