# I built this app from scratch. It was not a part of the Launch School curriculum. All files are my own.

require "sinatra"
require "bcrypt"
require "yaml"
require "tilt/erubis"
require "pry" 

configure(:development) do 
  require "sinatra/reloader" 
end 

configure do 
  enable :sessions
  set :session_secret, 'MySessionSecret!3'
end

before do
  session[:notifications] ||= [] 
  @credentials = load_user_data("credentials") || {}
  @contacts = load_user_data("contacts") || {}
  @current_user = session[:logged_in] || {}
end

helpers do 
  def checked?(category_hash) 
    if @category_id # from failed attempt
      "checked" if @category_id == category_hash[:category_id]
    else
      "checked" if category_hash[:category_id] == next_id("category") - 1
    end 
  end

  def no_contacts? 
    @contacts[@current_user].all? do |category_hash|
      category_hash[:contacts].empty?
    end
  end

  def no_categories? 
    @contacts[@current_user].empty?
  end

  def first_of_category?(category_hash, contact_id) 
    category_hash[:contacts].keys.min == contact_id
  end

  def display_phone_formats 
    ['<li>###-####', '###-###-####', '###.###.####', '##########', '(###)###-####', '+1##########', '+1(###)###-####</li>'].join("</li><li>")
  end

  def which_name(name) 
    if name == "" || duplicate_info?(name, :name)
      @contact[:name]
    else
      name
    end
  end
end

def load_user_data(type)
  path = if ENV["RACK_ENV"] == "test"
           File.expand_path("../test/#{type}.yml", __FILE__)
         else   # ../ is required
           File.expand_path("../data/#{type}.yml",__FILE__)
         end
  YAML.load_file(path) || {} 
end 

def save_user_data(yaml_object)
  environment = (ENV["RACK_ENV"] == "test" ? "test" : "data")
  data_type = (yaml_object == @contacts ? "contacts" : "credentials")
  File.open("#{environment}/#{data_type}.yml", 'w') { |file| file.write yaml_object.to_yaml } # no ../  (see load data)
end

def clear_messages 
  session.delete(:undoable)
  session.delete(:commentary)
  session[:notifications] = []
  session[:messages_shown] = false
end

################### INPUT VALIDATION METHODS ###################

def check_for_valid_name(name)
  session[:notifications] << "Name can not be blank." if name == ""
end

def check_for_duplicate(data, type)
  extended_string = type == "phone" ? "phone number" : "email address"
  session[:notifications] << "You already have a contact with that #{type == "name" ? "name" : extended_string}." if duplicate_info?(data, type.to_sym)
end

def valid_phone?(phone)
  if phone.match?(/\A(\+\d{1,6})?(\(\d{3}\)|\d{3}[-\.]?)?\d{3}[-\.]?\d{4}\z/)
    if phone.include?('+')
      !phone.include?('.')
    elsif phone[-5] == '.' 
      phone[-9] == '.'
    elsif phone[-5] == '-'
      !(phone[-9] == '.')
    else
      !['-', '.'].include?(phone[-8])
    end
  else
    false
  end
end

def valid_email?(email)
  email.match?(/\A\w+([\-.]\w+)*@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
end

PHONE_MSG = "Phone number format is invalid."
EMAIL_MSG = "Email address format is invalid."
FIX_MSG = "Please update it or leave it blank."
EITHER_MSG = "Either phone or email may be left blank"
BOTH_MSG = ", but not both."

def check_valid_phone_email_combo(phone, email)
  if phone.empty? && email.empty? 
    # both empty
    session[:notifications].push(EITHER_MSG + BOTH_MSG)
  elsif !valid_phone?(phone) && !phone.empty? && !valid_email?(email) && !email.empty? 
    # both invalid not empty
    session[:notifications].push(PHONE_MSG, EMAIL_MSG, EITHER_MSG + ".") 
  elsif !valid_phone?(phone) && !phone.empty? && valid_email?(email)
    # phone invalid not empty, email valid
    session[:notifications].push(PHONE_MSG, EITHER_MSG + ".") 
  elsif !valid_email?(email) && !email.empty? && valid_phone?(phone)
    # email invalid not empty, phone valid
    session[:notifications].push(EMAIL_MSG, EITHER_MSG + ".")
  elsif !valid_phone?(phone) && !phone.empty?
    # phone invalid not empty, email empty
    session[:notifications].push(PHONE_MSG)
  elsif !valid_email?(email) && !email.empty?
    # email invalid not empty, phone empty
    session[:notifications].push(EMAIL_MSG)
  end # else either both valid or one is valid and other empty, in all cases add no msg
end

def duplicate_info?(input, info_type) 
  if @contacts[@current_user].any? do |category_hash|
    category_hash[:contacts].any? { |id, contact_info| contact_info[info_type] == input }
  end 
  @duplicate = true;
  return true unless @contact && input == @contact[info_type]
  end # unless dup of self, temporarilty, due to editing some but not all contact info
  false
end 

def check_for_errant_input(name, phone, email)
  @duplicate = false;
  check_for_valid_name(name)
  check_valid_phone_email_combo(phone, email)

  check_for_duplicate(name, "name") 
  check_for_duplicate(phone, "phone") unless phone == "" 
  check_for_duplicate(email, "email") unless email == ""
end

def next_id(id_type)
  highest_id = 0
  @contacts[@current_user].each do |category_hash|
    if id_type == "category" 
      highest_id = [category_hash[:category_id], highest_id].max
    else  
      category_hash[:contacts].each { |id, info| highest_id = [id, highest_id].max }
    end
  end
  highest_id + 1
end

def create_contact_variables # some vars will be nil in some routes
  @contact_id = params["contact_id"].to_i 
  @category_id = params["category_id"].to_i

  @category_hash = get_category_hash(@category_id) 
  @contact = @category_hash[:contacts][@contact_id]

  @name = params["name"] ? params["name"].strip.capitalize : @contact[:name]
  @phone = params["phone"] ? params["phone"].strip : @contact[:phone]
  @email = params["email"] ? params["email"].strip : @contact[:email]
end

def get_category_hash(category_id)
  @contacts[@current_user].select do |category_hash|
    category_hash[:category_id] == category_id
  end[0]
end


################# GENERATE MESSAGE METHODS ###################

def generate_messages(notification, commentary = false)
  session[:notifications] << notification
  session[:commentary] = commentary if commentary
end

def generate_cat_create_msg
  ["Now add some contacts!", "What organization skills you have.", "Very creative of you..."].sample
end

def generate_cat_delete_msg
  ["People don't need labels, anyways...", "Those people musn't have mattered much.", "Well, that was drastic..."].sample
end

def generate_edit_msg
  ["Ahh, the winds of change...", "You seem to be friends with a chameleon!", "The only constant is that nothing remains constant... - Heraclitus"].sample
end

def generate_cat_rename_msg
  ["Was that really necessary?", "Are you being productive, or just spinning your wheels?", "The contacts therein remain unchanged."].sample
end

def generate_restore_msg
  ["Ugh. Here we go...", "A little indecisive, aren't we?", "Make up your mind!", "Hmmm... This could go on for a while."].sample
end

def generate_delete_msg
  ["Your time is too valuable for people like that...", "I hope you said goodbye!", "We all must go separate ways, eventually."].sample
end

def generate_welcome_msg
  ["It's not what you know, but who you know...", "Life is about relationships...", "Organize your contacts here!"].sample
end

def generate_logout_msg
  ["We're sad to see you go.", "Come back soon!", "Now go make some new friends!"].sample
end

def generate_signup_msg
  ["Get started below!", "Now... Who do you know?", "Today is a great day to meet someone new."].sample
end

def generate_new_contact_msg
  ["Must be an interesting person...", "That's it... Now you're getting the hang of it!", "Building bridges, I see."].sample
end

def generate_unchanged_msg
  ["Is that what you meant to do?", "Maybe you'd like to try again?", "You're wasting my time..."].sample
end

################### PRE-SIGNIN ROUTES #####################

post "/signin" do # display signin form
  clear_messages if session[:messages_shown]
  erb :signin
end

post "/attempt_signin" do 
  @username = params["username"].strip.capitalize 
  encrypted_password = @credentials[@username]
  clear_messages if session[:messages_shown]

  if encrypted_password == params["password"].strip && params["password"] != ""
    session[:logged_in] = @username
    generate_messages("Welcome #{session[:logged_in]}.", generate_welcome_msg)
    redirect "/"

  else
    generate_messages("Invalid Credentials. Please enter a valid username and password.")
    erb :signin 
  end
end

post "/register" do # view register form
  clear_messages if session[:messages_shown]
  erb :register
end

post "/attempt_register" do 
  @username = params["username"].strip.capitalize
  @password = params["password"].strip
  clear_messages if session[:messages_shown]

  if @password != params["confirm_password"].strip
    generate_messages("Password confirmation did not match. Please check your spelling and try again.")
    erb :register

  elsif [@username, @password].include?""
    generate_messages("Username and password may not be blank.")
    erb :register

  elsif @credentials[@username]  
    generate_messages("That username is taken. Please try another one.")
    erb :register
  else

    @credentials[@username] = BCrypt::Password.create(params["password"].strip) 
    save_user_data(@credentials) 
    generate_messages("You have successfully created a new account.", generate_signup_msg)

    @contacts[@username] = [{category_id: 1, contacts: {}, name: "Friends"},
                            {category_id: 2, contacts: {}, name: "Work"},
                            {category_id: 3, contacts: {}, name: "Other"}]
    save_user_data(@contacts) 
    redirect "/"
  end
end

get "/" do 
  clear_messages if session[:messages_shown]
  erb :index
end

post "/cancel" do 
  clear_messages if session[:messages_shown]
  redirect "/"
end 

post "/cancel_to_catagories" do 
  clear_messages if session[:messages_shown]
  redirect "/manage"
end 

#################### POST SIGNIN ROUTES ###################

post "/signout" do 
  session.delete :logged_in
  clear_messages if session[:messages_shown]
  generate_messages("You have been signed out.", generate_logout_msg)
  redirect "/"
end

post "/create" do # view create contact page
  clear_messages if session[:messages_shown]
  erb :create
end

post "/attempt_create" do 
  clear_messages if session[:messages_shown]
  if params["category_id"] == nil
    generate_messages("You must first create a category")
    erb :create
  else

    create_contact_variables
    check_for_errant_input(@name, @phone, @email)

    if session[:notifications].empty? 
      @category_hash[:contacts][next_id("contact")] = {name: @name.capitalize, phone: @phone, email: @email} 
      save_user_data(@contacts)

      clear_messages if session[:messages_shown] # because 
      generate_messages("You have added \"#{@name}\" to your contacts.", generate_new_contact_msg)
      redirect "/"
    else
      erb :create
    end
  end
end


get "/edit/:category_id/:contact_id" do # view edit contact form
  clear_messages if session[:messages_shown]
  create_contact_variables
  erb :edit
end 

post "/:category_id/:contact_id/attempt_edit" do 
  clear_messages if session[:messages_shown]
  @new_category_id = params["new_category"].to_i
  @new_category_hash = get_category_hash(@new_category_id)

  create_contact_variables
  @old_category_hash = @category_hash 
  check_for_errant_input(@name, @phone, @email)

  if [@new_category_id, @name, @phone, @email] == [@category_id, @contact[:name], @contact[:phone], @contact[:email]] 
    generate_messages("You haven't made any changes.", generate_unchanged_msg)
    redirect "/"

  elsif session[:notifications].empty? 
    @new_contact_id = next_id("contact") 
    @old_category_hash[:contacts].reject! { |id, info| id == @contact_id }
    session[:just_deleted] = {category_id: @category_id, contact_id: @contact_id, name: @contact[:name], phone: @contact[:phone], email: @contact[:email]}

    @new_category_hash[:contacts][@new_contact_id] = {name: @name, phone: @phone, email: @email} 
    session[:just_created] = {category_id: @new_category_id, contact_id: @new_contact_id, name: @name, phone: @phone, email: @email} 

    save_user_data(@contacts) 
    clear_messages if session[:messages_shown]
    generate_messages("You've successfully updated #{@name}.", generate_edit_msg)
    session[:undoable] = "undo_edit"
    redirect "/"

  else 
    @category_id = @new_category_id 
    erb :edit
  end
end

post "/undo_edit" do 
  clear_messages if session[:messages_shown]
  @contact = session[:just_deleted] 
  @category_hash = get_category_hash(@contact[:category_id]) 
  @category_hash[:contacts][@contact[:contact_id]] = {name: @contact[:name], phone: @contact[:phone], email: @contact[:email]} 

  @contact = session[:just_created] 
  @category_hash = get_category_hash(@contact[:category_id]) 
  @category_hash[:contacts].reject! { |id, info| id == @contact[:contact_id] } 

  save_user_data(@contacts) 
  generate_messages("\"#{session[:just_deleted][:name]}\" has been restored...", generate_restore_msg)
  session.delete :just_deleted 
  session.delete :just_created 
  redirect "/"
end

post "/:category_id/:contact_id/destroy" do 
  clear_messages if session[:messages_shown]
  create_contact_variables
  session[:just_deleted] = {category_id: @category_id, contact_id: @contact_id, name: @name, phone: @phone, email: @email} 

  @category_hash[:contacts].reject! { |id, info| id == @contact_id } 
  save_user_data(@contacts)

  generate_messages("#{@name} has been deleted.", generate_delete_msg)
  session[:undoable] = "undo_destroy"
  redirect "/"
end

post "/undo_destroy" do 
  clear_messages if session[:messages_shown]
  @contact = session[:just_deleted] 
  @category_hash = get_category_hash(@contact[:category_id]) 

  @category_hash[:contacts][@contact[:contact_id]] = {name: @contact[:name], phone: @contact[:phone], email: @contact[:email]} 

  save_user_data(@contacts)
  session.delete :just_deleted 

  generate_messages("#{@contact[:name]} has been restored...", generate_restore_msg)
  redirect "/"
end

get "/manage" do 
  clear_messages if session[:messages_shown]
  erb :manage
end

post "/create_category" do 
  clear_messages if session[:messages_shown]
  erb :create_category
end

post "/destroy_category/:category_id" do 
  clear_messages if session[:messages_shown]
  @category = get_category_hash(params[:category_id].to_i) 

  session[:just_deleted] = @category 
  @contacts[@current_user].reject! { |category_hash| category_hash == @category }
  save_user_data(@contacts)

  generate_messages("\"#{@category[:name]}\" has been deleted, along with any contacts therein.", generate_cat_delete_msg)
  session[:undoable] = "undo_destroy_category"
  erb :manage
end

post "/undo_destroy_category" do 
  clear_messages if session[:messages_shown]
  @category = session[:just_deleted] 
  @contacts[@current_user] << @category 
  save_user_data(@contacts)

  generate_messages("#{@category[:name]} has been restored.", generate_restore_msg)
  session.delete :just_deleted 
  erb :manage
end

post "/attempt_create_category" do 
  clear_messages if session[:messages_shown]
  @category_name = params["new_category_name"].capitalize.strip
  if @category_name == ''
    generate_messages("Category name may not be blank")
    erb :create_category

  elsif @contacts[@current_user].any? { |category_hash| category_hash[:name] == @category_name} 
    generate_messages("You already have a category with that name")
    erb :create_category

  else 
    @contacts[@current_user] << {category_id: next_id("category"), contacts: {}, name: @category_name}
    save_user_data(@contacts)

    generate_messages("\"#{@category_name}\" has been added to your categories.", generate_cat_create_msg)
    erb :manage
  end
end

get "/edit_category/:category_id" do 
  clear_messages if session[:messages_shown]
  @category = get_category_hash(params[:category_id].to_i) 
  erb :edit_category
end

post "/attempt_edit_category/:category_id" do 
  clear_messages if session[:messages_shown]
  @category_name = params["category_name"].capitalize
  @category = get_category_hash(params[:category_id].to_i) 
  check_for_valid_name(@category_name) 

  if @contacts[@current_user].any? { |category_hash| category_hash[:name] == @category_name } 
    generate_messages("You already have a category with that name")
  end

  if session[:notifications].empty? 
    session[:just_renamed] = {name: @category[:name], id: params[:category_id].to_i} 
    @category[:name] = @category_name 
    save_user_data(@contacts)

    generate_messages("\"#{@category_name}\" has been renamed.", generate_cat_rename_msg)
    session[:undoable] = "undo_rename_category"
    redirect "/manage"
  else
    erb :edit_category
  end
end

post "/undo_rename_category" do
  clear_messages if session[:messages_shown]
  @category = get_category_hash(session[:just_renamed][:id]) 
  @category[:name] = session[:just_renamed][:name] 
  save_user_data(@contacts) 

  generate_messages("#{@category[:name]} has been restored.", generate_restore_msg)
  session.delete :just_renamed 
  redirect "/manage"
end
